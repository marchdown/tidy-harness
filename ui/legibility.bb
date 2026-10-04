#!/usr/bin/env bb
;; ui/legibility.bb — "superlegible, dense, HIG-respecting, explorable, comprehensible at a glance" as CHECKS, not adjectives.
;; Reads one HTML file (read-only) and reports PASS / WARN / FAIL per check; exit 1 if any FAIL.
;;   usage: bb ui/legibility.bb page.html [--json]
;; Honest limits: static analysis of CSS custom properties and markup. It cannot see colours computed in JS, layout at runtime,
;; or whether the page reads well at a glance. Those need a human or a browser; see the checklist printed at the end.
(require '[clojure.string :as str] '[cheshire.core :as json])

(def path (first (remove #(str/starts-with? % "--") *command-line-args*)))
(def as-json? (some #{"--json"} *command-line-args*))
(when-not (and path (.exists (java.io.File. path)))
  (binding [*out* *err*] (println "usage: bb ui/legibility.bb page.html [--json]")) (System/exit 2))
(def html (slurp path))

;; ---- colour ----
(defn hex->rgb [h]
  (let [h (str/replace h "#" "") h (if (= 3 (count h)) (apply str (mapcat #(repeat 2 %) h)) h)]
    (when (re-matches #"[0-9a-fA-F]{6}" h) (mapv #(Integer/parseInt (subs h % (+ % 2)) 16) [0 2 4]))))
(defn parse-colour [v]
  (let [v (str/trim (str v))]
    (cond (str/starts-with? v "#") (hex->rgb v)
          (re-matches #"\d+\s*,\s*\d+\s*,\s*\d+" v) (mapv #(Integer/parseInt (str/trim %)) (str/split v #","))
          (re-matches #"rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)" v) (mapv #(Integer/parseInt %) (re-seq #"\d+" v)))))
(defn lum [[r g b]]
  (let [f (fn [c] (let [c (/ c 255.0)] (if (<= c 0.03928) (/ c 12.92) (Math/pow (/ (+ c 0.055) 1.055) 2.4))))]
    (+ (* 0.2126 (f r)) (* 0.7152 (f g)) (* 0.0722 (f b)))))
(defn contrast [a b] (let [[hi lo] (reverse (sort [(lum a) (lum b)]))] (/ (+ hi 0.05) (+ lo 0.05))))

;; ---- CSS custom properties: base :root and the dark-scheme override ----
(defn resolve-refs
  "Resolve `var(--x)` values against the map itself (a few passes), so `--paper: var(--kraft)` becomes a colour, not a silent skip."
  [m]
  (loop [m m, n 0]
    (let [m2 (update-vals m (fn [v] (if-let [[_ k] (re-find #"^var\(--([a-zA-Z0-9-]+)\)$" v)] (get m k v) v)))]
      (if (or (= m m2) (>= n 4)) m2 (recur m2 (inc n))))))
(defn vars-in [block] (into {} (for [[_ k v] (re-seq #"--([a-zA-Z0-9-]+)\s*:\s*([^;}]+)" block)] [k (str/trim v)])))
(def root-blocks (map second (re-seq #":root\s*\{([^}]*)\}" html)))
(def base (resolve-refs (vars-in (or (first root-blocks) ""))))
(def dark-media (second (re-find #"(?s)prefers-color-scheme\s*:\s*dark\s*\)\s*\{(.*?:root[^{]*\{[^}]*\})" html)))
(def dark (resolve-refs (merge (vars-in (or (first root-blocks) "")) (vars-in (or dark-media (str/join ";" (rest root-blocks)))))))
(def has-dark? (boolean dark-media))

(def text-names #"^(fg|text|ink|mute|muted|faint|pen|dim|c)$")
(def bg-names #"^(bg|paper|surface|k)$")
(def panel-names #"^(dark|panel|wash)$")
(defn pick [m re] (first (for [[k v] m :when (re-matches re k) :let [c (parse-colour v)] :when c] [k c])))
(defn scheme-checks [label m]
  (let [[bgk bg] (pick m bg-names)
        ;; a "text" candidate identical to the background is that background's palette source (e.g. --paper: var(--ink)), not text
        texts (for [[k v] m :when (re-matches text-names k) :let [c (parse-colour v)] :when (and c (not= c bg))] [k c])
        graphics (for [[k v] m :let [c (parse-colour v)] :when (and c (re-matches #"\d+\s*,\s*\d+\s*,\s*\d+" v))] [k c])]
    (if-not bg
      [{:check (str label " colours") :level :warn :detail "no recognisable background variable (--bg/--paper); contrast not checked"}]
      (concat
       (for [[k c] texts :let [r (contrast c bg)]]
         {:check (format "%s text --%s on --%s" label k bgk) :level (cond (>= r 4.5) :pass (>= r 3.0) :warn :else :fail)
          :detail (format "%.2f:1 (WCAG AA needs 4.5)" r)})
       (for [[k c] graphics :let [r (contrast c bg)]]
         {:check (format "%s graphic --%s on --%s" label k bgk) :level (if (>= r 3.0) :pass :fail)
          :detail (format "%.2f:1 (WCAG 1.4.11 needs 3.0 for meaningful non-text colour)" r)})))))

;; ---- markup / platform checks ----
(def font-sizes (->> (re-seq #"font(?:-size)?\s*:\s*(?:[a-z0-9]+\s+)*?(\d+(?:\.\d+)?)px" html) (map #(Double/parseDouble (second %)))))
(def min-font (when (seq font-sizes) (apply min font-sizes)))
(def animated? (boolean (re-find #"@keyframes|transition\s*:|setInterval|requestAnimationFrame" html)))
(def static-click-divs (count (re-seq #"<(div|span|li)[^>]*\sonclick=" html)))

(defn chk [name level detail] {:check name :level level :detail detail})
(def results
  (vec (concat
        (scheme-checks "light" base)
        (if has-dark? (scheme-checks "dark" dark) [(chk "dark scheme" :warn "no prefers-color-scheme: dark override found")])
        [(chk "viewport meta" (if (re-find #"<meta[^>]+name=.viewport" html) :pass :fail) "needed for any phone/narrow layout")
         (chk "document language" (if (re-find #"<html[^>]*\slang=" html) :pass :warn) "screen readers pick a voice from <html lang>")
         (chk "title" (if (re-find #"<title>[^<]+" html) :pass :fail) "")
         (chk "smallest declared font" (cond (nil? min-font) :warn (>= min-font 11) :pass :else :fail)
              (if min-font (format "%.0fpx (HIG floor is 11pt; denser than that stops being legible)" min-font) "none declared in px"))
         (chk "focus ring" (if (re-find #":focus-visible" html) :pass :warn) "keyboard users must see where they are")
         (chk "reduced motion" (cond (not animated?) :pass (re-find #"prefers-reduced-motion" html) :pass :else :warn)
              (if animated? "page animates; honour prefers-reduced-motion" "no animation found"))
         (chk "touch targets" (if (or (re-find #"pointer\s*:\s*coarse" html) (re-find #"min-(height|width)\s*:\s*4[4-9]px" html)) :pass :warn)
              "HIG: 44pt minimum hit target; add (pointer:coarse) sizing")
         (chk "clickable non-buttons in markup" (if (zero? static-click-divs) :pass :warn)
              (str static-click-divs " div/span/li with onclick (not keyboard-operable unless given role+tabindex); JS-attached handlers are invisible to this check"))])))

(def counts (frequencies (map :level results)))
(if as-json?
  (println (json/generate-string {:file path :counts counts :results results} {:pretty true}))
  (do
    (println (str "LEGIBILITY  " path))
    (doseq [{:keys [check level detail]} results]
      (println (format "  %-5s %-44s %s" (str/upper-case (name level)) check detail)))
    (println (format "\n  %d pass, %d warn, %d fail" (get counts :pass 0) (get counts :warn 0) (get counts :fail 0)))
    (println "\n  Not machine-checkable (needs eyes): 5-second test (can a stranger say what it shows and what to do?);")
    (println "  hierarchy (is the primary thing the biggest/darkest?); density without clutter; explorability (overview -> zoom -> detail).")))
(System/exit (if (pos? (get counts :fail 0)) 1 0))
