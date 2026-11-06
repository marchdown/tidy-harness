#!/usr/bin/env bb
;; reference/scorecard.bb — the REFERENCE implementation of the lens (Clojure/babashka); HarnessCore (Swift) must conform to it.
;; (home: ~/tidy-harness; ~/pi-doctrine-prod/bin/scorecard.bb is a thin wrapper that loads this file)
;; scorecard.bb — what do agents ACTUALLY do, measured from transcripts (the deterministic lens; Sensor 2).
;; Sensor 1 is ~/pi-harness/eval (controlled probes). This one reads real sessions and never asks the agent anything.
;; usage: bb bin/scorecard.bb [sessions-dir] [--json out.json]
;; Every rule is a predicate over the ordered transcript; "n/a" means the rule did not apply, not that it passed.
(require '[cheshire.core :as json] '[babashka.fs :as fs] '[clojure.string :as str])

(def args *command-line-args*)
(defn flag [f] (second (drop-while #(not= % f) args)))
(def out (flag "--json"))
(def summary-out (flag "--summary"))   ; compact machine-readable summary, compared against other implementations
(def spec-path (flag "--spec"))        ; shared rules-as-data (spec/doctrine.json); defaults below equal its v1 content
(def sessions-dir (or (first (remove #(or (str/starts-with? % "--") (#{out summary-out spec-path} %)) args))
                      (str (System/getenv "HOME") "/.pi/agent/sessions")))
(def spec (when spec-path (json/parse-string (slurp spec-path) true)))

(defn recs [f] (keep #(try (json/parse-string % true) (catch Exception _ nil)) (str/split-lines (slurp (str f)))))
(defn blocks [m] (let [c (:content m)] (if (sequential? c) c [])))
(defn text-of [m] (let [c (:content m)]
                    (if (string? c) c (->> (blocks m) (filter #(= "text" (:type %))) (map :text) (str/join "\n")))))

(defn events
  "Ordered events: {:k :text|:call|:result, :model ...}. Model = the assistant model most recently seen."
  [ms]
  (loop [ms ms, model nil, i 0, acc []]
    (if-let [m (first ms)]
      (case (:role m)
        "assistant" (let [model (or (:model m) model)
                          t (text-of m)
                          cs (filter #(= "toolCall" (:type %)) (blocks m))]
                      (recur (rest ms) model (inc i)
                             (-> acc
                                 ;; one marker per assistant MESSAGE: the denominator for every "turn" figure
                                 (conj {:k :assistant :i i :model model})
                                 (into (when (seq t) [{:k :text :i i :t t :model model :stop (:stopReason m)}]))
                                 (into (map (fn [c] {:k :call :i i :name (:name c) :args (:arguments c) :model model}) cs))
                                 (into (when (= "error" (:stopReason m)) [{:k :errstop :i i :model model}])))))
        "toolResult" (recur (rest ms) model (inc i) (conj acc {:k :result :i i :err (boolean (:isError m)) :model model}))
        (recur (rest ms) model (inc i) acc))
      acc)))

(def mutating? (set (or (:mutatingTools spec) ["write" "edit"])))
(def net-re (re-pattern (or (:networkPattern spec) "\\b(curl|ssh|wget|rsync|scp|git (push|clone|fetch|pull))\\b")))
(def guard-re (re-pattern (or (:timeoutGuardPattern spec) "(timeout |alarm|--max-time|-m \\d|ConnectTimeout)")))
(def done-when-marker (or (get-in spec [:markers :doneWhen]) "Done when:"))
(def gate-phase-marker (or (get-in spec [:markers :gatePhase]) "Phase 1 of 2"))
(def verified-marker (or (get-in spec [:markers :verified]) "Verified:"))
(def levels (or (:levels spec) ["edited" "compiled" "tested" "deployed"]))
(def claim-levels (set (or (:claimLevelsNeedingARun spec) ["tested" "deployed"])))
(def probe-prefix (or (:probeCwdPrefix spec) "/private/tmp"))
(def level-re (re-pattern (str (java.util.regex.Pattern/quote verified-marker) "\\W*(" (str/join "|" levels) ")")))

(defn analyse [f]
  (let [rs (recs f)
        cwd (some #(when (= "session" (:type %)) (:cwd %)) rs)
        ms (map :message (filter #(= "message" (:type %)) rs))
        evs (events ms)
        ;; the done-when-gate extension appends "[Phase 1 of 2 ..." to the user's first message: a mechanical tell
        gated (boolean (some #(and (= "user" (:role %)) (str/includes? (text-of %) gate-phase-marker)) ms))
        per-model (reduce (fn [acc e]
                            (let [m (or (:model e) "?")]
                              (case (:k e)
                                :assistant (update-in acc [m :turns] (fnil inc 0))
                                :errstop (update-in acc [m :err-stops] (fnil inc 0))
                                :result (cond-> (update-in acc [m :results] (fnil inc 0))
                                          (:err e) (update-in [m :result-errs] (fnil inc 0)))
                                acc)))
                          {} evs)
        calls (filter #(= :call (:k %)) evs)
        muts (filter #(mutating? (:name %)) calls)
        texts (filter #(= :text (:k %)) evs)
        first-mut (:i (first muts)) last-mut (:i (last muts))
        last3 (str/join "\n" (map :t (take-last 3 texts)))
        level (some-> (re-find level-re last3) second)
        edits (filter #(= "edit" (:name %)) calls)
        seen (volatile! #{})
        edit-ok (for [c calls :let [p (-> c :args :path)]
                      :when (and p (#{"read" "write" "edit"} (:name c)))
                      :let [ok (contains? @seen p)]]
                  (do (vswap! seen conj p) (when (= "edit" (:name c)) ok)))
        edit-checks (remove nil? edit-ok)
        bash (filter #(= "bash" (:name %)) calls)
        netb (filter #(re-find net-re (str (-> % :args :command))) bash)
        guarded (filter #(or (-> % :args :timeout) (re-find guard-re (str (-> % :args :command)))) netb)]
    {:file (str f) :cwd cwd :kind (if (str/starts-with? (str cwd) probe-prefix) :probe :real)
     :assistant-turns (count (filter #(= :assistant (:k %)) evs))
     :err-stops (count (filter #(= :errstop (:k %)) evs))
     :results (count (filter #(= :result (:k %)) evs)) :result-errs (count (filter #(and (= :result (:k %)) (:err %)) evs))
     :models (frequencies (keep :model evs)) :gated gated :per-model per-model
     ;; rules: true / false / nil (= n/a)
     :done-when-before-first-mutation (when (seq muts) (boolean (some #(and (< (:i %) first-mut) (str/includes? (:t %) done-when-marker)) texts)))
     :verified-line-at-end            (when (seq muts) (boolean level))
     :tested-claim-has-run-after-edit (when (claim-levels level) (boolean (and last-mut (some #(> (:i %) last-mut) bash))))
     :edits-read-first                (when (seq edit-checks) (every? true? edit-checks))
     :network-cmds {:total (count netb) :guarded (count guarded)}}))

(defn rate [rows k]
  (let [vs (remove nil? (map k rows))] [(count (filter true? vs)) (count vs)]))

(defn pct [[a b]] (if (zero? b) "  n/a" (format "%3d%%" (long (/ (* 100.0 a) b)))))

(def files (->> (fs/glob sessions-dir "**/*.jsonl") (map str) sort))
(def rows (mapv analyse files))
(def rules [:done-when-before-first-mutation :verified-line-at-end :tested-claim-has-run-after-edit :edits-read-first])

(println (format "SCORECARD  %d sessions under %s   (as of %s)" (count rows) sessions-dir (str (java.time.Instant/now))))
(println "kind    sessions | rule (passed/applicable, rate)")
(doseq [kind [:real :probe]
        :let [rs (filter #(= kind (:kind %)) rows)]]
  (println (format "%-7s %8d |" (name kind) (count rs)))
  (doseq [r rules :let [[a b] (rate rs r)]]
    (println (format "          %-36s %3d/%-3d %s" (name r) a b (pct [a b]))))
  (let [n (reduce + (map #(-> % :network-cmds :total) rs)) g (reduce + (map #(-> % :network-cmds :guarded) rs))]
    (println (format "          %-36s %3d/%-3d %s" "network-cmds-have-a-timeout" g n (pct [g n])))))
(println "\nwith vs without the done-when gate (real sessions with a write/edit; the gate's own tell is \"Phase 1 of 2\" in the user message)")
(doseq [g [true false]
        :let [rs (filter #(and (= :real (:kind %)) (= g (:gated %))) rows) [a b] (rate rs :done-when-before-first-mutation)]]
  (println (format "  gate %-3s  sessions %-3d  done-when-before-first-mutation %d/%d %s" (if g "ON" "off") (count rs) a b (pct [a b]))))
(println "\nper model (all sessions)             sessions  turns  err-stops (rate)   tool-results  tool-errors (rate)")
(let [agg (apply merge-with #(merge-with + %1 %2) (map :per-model rows))
      sess (frequencies (mapcat #(keys (:per-model %)) rows))]
  (doseq [[m v] (sort-by (comp - :turns val) agg)]
    (println (format "  %-38s %8d %6d %6d %-8s %12d %9d %-8s" m (sess m) (:turns v 0) (:err-stops v 0) (pct [(:err-stops v 0) (:turns v 0)])
                     (:results v 0) (:result-errs v 0) (pct [(:result-errs v 0) (:results v 0)])))))
(println (format "totals: assistant turns %d, error stops %d (%s), tool results %d, tool errors %d (%s)"
                 (reduce + (map :assistant-turns rows)) (reduce + (map :err-stops rows))
                 (pct [(reduce + (map :err-stops rows)) (reduce + (map :assistant-turns rows))])
                 (reduce + (map :results rows)) (reduce + (map :result-errs rows))
                 (pct [(reduce + (map :result-errs rows)) (reduce + (map :results rows))])))
(when out
  (spit out (json/generate-string {:generated_at (str (java.time.Instant/now)) :generator "bin/scorecard.bb"
                                   :sessions_dir sessions-dir :n_sessions (count rows) :sessions rows} {:pretty true}))
  (println "wrote" out))

;; Compact summary for conformance: every other implementation must produce this exact structure from the same logs.
(when summary-out
  (let [by-kind (fn [k] (filter #(= k (:kind %)) rows))
        net (fn [rs] [(reduce + (map #(-> % :network-cmds :guarded) rs)) (reduce + (map #(-> % :network-cmds :total) rs))])
        rule-map (fn [rs] (into {"network-cmds-have-a-timeout" (net rs)} (for [r rules] [(name r) (vec (rate rs r))])))
        gate (fn [g] (vec (rate (filter #(and (= :real (:kind %)) (= g (:gated %))) rows) :done-when-before-first-mutation)))
        agg (apply merge-with #(merge-with + %1 %2) (map :per-model rows))
        sess (frequencies (mapcat #(keys (:per-model %)) rows))]
    (spit summary-out
          (json/generate-string
           {:sessions (count rows) :real (count (by-kind :real)) :probe (count (by-kind :probe))
            :rules {:real (rule-map (by-kind :real)) :probe (rule-map (by-kind :probe))}
            :gate {:on (gate true) :off (gate false)}
            :totals {:turns (reduce + (map :assistant-turns rows)) :errStops (reduce + (map :err-stops rows))
                     :results (reduce + (map :results rows)) :resultErrs (reduce + (map :result-errs rows))}
            :perModel (into {} (for [[m v] agg] [m {:sessions (sess m) :turns (:turns v 0) :errStops (:err-stops v 0)
                                                    :results (:results v 0) :resultErrs (:result-errs v 0)}]))}
           {:pretty true}))
    (println "wrote" summary-out)))
