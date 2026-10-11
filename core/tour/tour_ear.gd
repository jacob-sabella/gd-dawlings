class_name TourEar
extends RefCounted

## The crowd's own two bars, judged off `TourMeasure.Ear`'s live, windowed reading: LEVEL ("the
## room is too quiet" / happy / "too loud, the limiter's pumping") and BALANCE ("it's thin, all
## top" / happy / "it's a mudslide"). Pure arithmetic -- no audio, no `AudioServer` touched here
## -- so every function below is a plain static a test can call directly.
##
## THRESHOLDS are measured, not guessed: tools/tour_ear.sh renders Tour's rescue song (clean,
## and each flaw) through the real master bus into the null sink and prints the numbers this
## comment quotes. Recalibrate -- rerun the tool, paste its rows here -- after any change to
## DemoSong's parts/trims, the master chain, FXCatalogue's EQ, or a flaw's bake; the tool's own
## checks fail if the current build no longer reads those rows the way they are quoted here.

const BARS: Array[StringName] = [&"level", &"balance"]

## Measured by `flock ~/.cache/dawlings/shared.lock tools/tour_ear.sh --flaws all --diag --repeat 1`
## on 2026-10-11, PulseAudio into dawlings_null, 8 bars, clean and every flaw at tempo 84/100/124:
##   EAR tempo=84  case=clean      avg_db=-6.25  spread_db=26.15 tilt_db=-1.95
##   EAR tempo=100 case=clean      avg_db=-5.87  spread_db=25.54 tilt_db=-1.41
##   EAR tempo=124 case=clean      avg_db=-5.52  spread_db=24.26 tilt_db=-0.68
##   EAR tempo=84  case=hard_pan   avg_db=-5.16  spread_db=26.61 tilt_db=-1.56  (widest happy spread)
##   EAR tempo=124 case=hard_pan   avg_db=-4.45  spread_db=24.78 tilt_db=-0.46  (loudest happy avg)
##   EAR tempo=84  case=quiet_vox  avg_db=-6.75  spread_db=26.33 tilt_db=-1.85  (quietest happy avg)
##   EAR tempo=100 case=muddy_bass avg_db=-1.69  spread_db=36.77 tilt_db=9.34   (meant to read unhappy)
##   EAR tempo=100 case=master_-12 avg_db=-17.91 (compensated, ~12 dB below clean: a fader at half)
##   EAR tempo=100 case=all_muted  avg_db=-200.0 (silence floor)
##   EAR tempo=100 case=band_+6    avg_db=-1.94  spread_db=25.60 tilt_db=-1.43  (a flat boost: loud,
##                                                                               not mud)
## Full rows: `flock ~/.cache/dawlings/shared.lock tools/tour_ear.sh --flaws all --diag --repeat 1`.
##
## The first pass at this table was never actually run against the real mix -- see
## docs/loop_backlog.md's "The crowd's ear" for the full story -- and read every clean row as
## "thin" by tens of dB, because the built-in engine's own mix sits far brighter in the low and
## mid than the top (DemoSong's own parts, nothing a Tour flaw touches): HIGH reads 40-50 dB under
## LOW/MID on every clean row above, which is why the clean band's own spread is ~25 dB, not the
## single digits that first guess assumed. The thresholds below are derived against the rows
## actually measured, not guessed:
##   quiet_db: quietest happy avg (quiet_vox@84, -6.75) less 6 dB -- comfortably above
##             master_-12 (-17.91) and all_muted's floor.
##   loud_db: loudest happy avg (hard_pan@124, -4.45) plus 2 dB -- still below band_+6 (-1.94)
##            and muddy_bass (-1.60 to -1.72), the two cases meant to read loud.
##   spread_max_db: widest happy spread (hard_pan@84, 26.61) plus 3 dB -- well short of
##                  muddy_bass's narrowest spread (35.88, tempo 124).
## hyst_db is 1.0, inside every margin above. The boss window halves each margin (3/1/1.5) and is
## still passed by every happy row above (the tool's own checks assert this).
const THRESHOLDS := {
	"quiet_db": -12.75, "loud_db": -2.45, "spread_max_db": 29.61, "hyst_db": 1.0,
	"boss_quiet_db": -9.75, "boss_loud_db": -3.45, "boss_spread_max_db": 28.11,
}

## The clean rows' own numbers (above), so a test can assert the table still passes what it was
## measured on.
const MEASURED_CLEAN := [
	{"tempo": 84.0, "avg_db": -6.25, "spread_db": 26.15, "tilt_db": -1.95},
	{"tempo": 100.0, "avg_db": -5.87, "spread_db": 25.54, "tilt_db": -1.41},
	{"tempo": 124.0, "avg_db": -5.52, "spread_db": 24.26, "tilt_db": -0.68},
]
const MEASURED_MUDDY_BASS := {"tempo": 100.0, "avg_db": -1.69, "spread_db": 36.77, "tilt_db": 9.34}

const LINES := {
	&"level": {"happy": "happy with the level", "under": "the room is too quiet",
			"over": "too loud, the limiter's pumping", "waiting": "listening..."},
	&"balance": {"happy": "the mix is clear", "under": "it's thin, all top",
			"over": "it's a mudslide", "waiting": "listening..."},
}


## The regular or boss subset of THRESHOLDS, as plain "quiet_db"/"loud_db"/"spread_max_db" keys.
static func window(is_boss: bool) -> Dictionary:
	if is_boss:
		return {"quiet_db": THRESHOLDS["boss_quiet_db"], "loud_db": THRESHOLDS["boss_loud_db"],
				"spread_max_db": THRESHOLDS["boss_spread_max_db"]}
	return {"quiet_db": THRESHOLDS["quiet_db"], "loud_db": THRESHOLDS["loud_db"],
			"spread_max_db": THRESHOLDS["spread_max_db"]}


## -1 under (too quiet), 0 happy, +1 over (too loud). `was_happy` -- the bar's own last reading
## -- is the hysteresis: while happy, the PLAIN threshold is enough to go unhappy (a reading
## must cross it, but no further, to be noticed as trouble); once unhappy, it takes clearing
## the threshold by the full `hyst_db` margin to be called happy again. So a reading sitting
## right on the line flips to unhappy at once but only flips back once it has clearly recovered
## -- it does not chatter.
static func judge_level(avg_db: float, is_boss: bool, was_happy: bool) -> int:
	var w := window(is_boss)
	var hyst: float = THRESHOLDS["hyst_db"]
	var quiet: float = float(w["quiet_db"]) + (0.0 if was_happy else hyst)
	var loud: float = float(w["loud_db"]) - (0.0 if was_happy else hyst)
	if avg_db < quiet:
		return -1
	if avg_db > loud:
		return 1
	return 0


## -1 thin (all top), 0 happy, +1 mud. The spread bar is one-sided -- there is no "too narrow"
## -- so only `spread_db` past `spread_max_db` fails it at all; `tilt_db` (low minus mid) then
## says which way: positive beyond the window is mud (the low end swamping the mix), negative
## is thin (the low end missing). Hysteresis the same way as `judge_level`: the plain threshold
## while happy, `spread_max_db + hyst_db` to become happy again once not.
static func judge_balance(spread_db: float, tilt_db: float, is_boss: bool, was_happy: bool) -> int:
	var w := window(is_boss)
	var hyst: float = THRESHOLDS["hyst_db"]
	var max_spread: float = float(w["spread_max_db"]) + (0.0 if was_happy else hyst)
	if spread_db <= max_spread:
		return 0
	return 1 if tilt_db >= 0.0 else -1


## "CROWD: <words>" for the HUD's crowd lines. `heard` false (the ear has not filled its first
## window yet, or `Tour` never started one) always reads "listening...", whatever `happy`/`over`
## say.
static func line(bar: StringName, happy: bool, over: bool, heard: bool) -> String:
	var words: Dictionary = LINES.get(bar, {})
	if not heard:
		return "CROWD: %s" % String(words.get("waiting", "listening..."))
	if happy:
		return "CROWD: %s" % String(words.get("happy", "happy"))
	return "CROWD: %s" % String(words.get("over" if over else "under", ""))
