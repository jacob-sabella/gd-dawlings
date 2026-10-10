class_name TourBrief
extends RefCounted

## One brief's definition: what to hit, how long there is, and how it is judged.
##
## Every target here is against something the game can already measure (TourMeasure) -- loudness
## off the real master bus, frequency balance off a spectrum analyzer dropped onto it for the
## brief's duration, and timing off notes already placed against the project's own tempo map.
## Nothing here invents a new kind of analysis for Tour's sake.

var id: StringName
var title: String = ""
var flavour: String = ""
## The brief's time limit, in seconds at the project's tempo.
var seconds: float = 45.0
## Which of TourMeasure's samplers this brief runs: a subset of &"loudness", &"balance", &"timing".
var measures: Array[StringName] = []
## Measure-specific numbers; see TourBriefs._build for what each measure reads out of it.
var targets: Dictionary = {}
var is_boss: bool = false


## `samples`: {"loudness": {"avg_db", "peak_db"}, "balance": {"low_db", "mid_db", "high_db"},
## "timing": {"avg_beats_off", "worst_beats_off", "notes"}} -- whichever of `measures` ran.
## `tolerance_mult` widens the timing brief's beat windows (TourRun.tempo_tolerance_mult); it has
## no bearing on loudness or balance, which are not about tempo at all.
##
## A brief with more than one measure passes only when every one of them does: the boss brief's
## "harder target" is not an averaged score, it is three simultaneous bars to clear.
func judge(samples: Dictionary, tolerance_mult: float = 1.0) -> Dictionary:
	var passed := true
	var score_sum := 0
	var score_count := 0
	var detail := PackedStringArray()

	if &"loudness" in measures:
		var r: Dictionary = samples.get("loudness", {})
		var avg: float = float(r.get("avg_db", -100.0))
		var peak: float = float(r.get("peak_db", -100.0))
		var lo: float = float(targets.get("loudness_min_db", -16.0))
		var hi: float = float(targets.get("loudness_max_db", -10.0))
		var ceiling: float = float(targets.get("loudness_peak_max_db", -1.0))
		var mid := (lo + hi) * 0.5
		var ok := avg >= lo and avg <= hi and peak <= ceiling
		passed = passed and ok
		score_sum += clampi(int(round(100.0 - 10.0 * absf(avg - mid))), 0, 100)
		score_count += 1
		detail.append("loudness: avg %.1f dB (want %.1f to %.1f), peak %.1f dB (ceiling %.1f dB)" \
				% [avg, lo, hi, peak, ceiling])

	if &"balance" in measures:
		var r: Dictionary = samples.get("balance", {})
		var low: float = float(r.get("low_db", -100.0))
		var mid_band: float = float(r.get("mid_db", -100.0))
		var high: float = float(r.get("high_db", -100.0))
		var hi_band := maxf(low, maxf(mid_band, high))
		var lo_band := minf(low, minf(mid_band, high))
		var spread := hi_band - lo_band
		var max_spread: float = float(targets.get("balance_spread_max_db", 8.0))
		var ok := spread <= max_spread
		passed = passed and ok
		score_sum += clampi(int(round(100.0 - 6.0 * maxf(spread - max_spread, 0.0))), 0, 100)
		score_count += 1
		detail.append("balance: spread %.1f dB (want %.1f dB or less)" % [spread, max_spread])

	if &"timing" in measures:
		var r: Dictionary = samples.get("timing", {})
		var avg_off: float = float(r.get("avg_beats_off", 1.0))
		var worst_off: float = float(r.get("worst_beats_off", 1.0))
		var notes: int = int(r.get("notes", 0))
		var mean_max: float = float(targets.get("timing_mean_max_beats", 0.12)) * tolerance_mult
		var worst_max: float = float(targets.get("timing_worst_max_beats", 0.30)) * tolerance_mult
		var ok := notes > 0 and avg_off <= mean_max and worst_off <= worst_max
		passed = passed and ok
		score_sum += clampi(int(round(100.0 - 200.0 * avg_off)), 0, 100)
		score_count += 1
		detail.append("timing: avg %.2f beats off (want %.2f or less), worst %.2f (want %.2f or less), %d note(s)" \
				% [avg_off, mean_max, worst_off, worst_max, notes])

	if samples.has("flaws"):
		var r: Dictionary = samples["flaws"]
		var fixed_n: int = int(r.get("fixed", 0))
		var total: int = int(r.get("total", 0))
		var seconds_left_frac: float = float(r.get("seconds_left_frac", 0.0))
		var all_fixed := total > 0 and fixed_n == total
		passed = passed and all_fixed
		score_sum += 60 + roundi(40.0 * seconds_left_frac) if all_fixed \
				else roundi(60.0 * float(fixed_n) / float(maxi(total, 1)))
		score_count += 1
		detail.append("flaws: %d of %d fixed" % [fixed_n, total])

	# A part nobody has taken (or taken but not yet cleared) blocks the pass exactly as an
	# unfixed flaw does -- scored the same way, off the same clock, so a band that mixes well
	# but leaves a job untaken still does not clear the brief.
	if samples.has("parts"):
		var r: Dictionary = samples["parts"]
		var played_n: int = int(r.get("played", 0))
		var total: int = int(r.get("total", 0))
		var seconds_left_frac: float = float(samples.get("flaws", {}).get("seconds_left_frac", 0.0))
		var all_played := total > 0 and played_n == total
		passed = passed and all_played
		score_sum += 60 + roundi(40.0 * seconds_left_frac) if all_played \
				else roundi(60.0 * float(played_n) / float(maxi(total, 1)))
		score_count += 1
		detail.append("parts: %d of %d played" % [played_n, total])

	if score_count == 0:
		return {"passed": false, "score": 0, "detail": detail}
	return {"passed": passed, "score": int(round(float(score_sum) / float(score_count))), "detail": detail}
