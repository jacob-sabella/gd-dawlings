class_name TourChaosEvent
extends RefCounted

## One way a brief can go gloriously wrong mid-way through, on top of its flaws: telegraphed a
## couple of seconds ahead, struck once by the host, and re-judged every tick exactly as a flaw
## is fixed. Mirrors TourFlaw's shape -- `bake`/`fixed` there is `strike`/`recovered` here --
## because a chaos event IS a flaw that arrives late, and the state machine that drives it
## (TourChaos.State, core/tour/tour.gd's `_tick_chaos`) is the live-judging half of
## `_tick_flaws` with a clock bolted on the front.
##
## See core/tour/tour_chaos.gd for the catalogue, the schedule, and why a chaos event's own
## random draw (which strip, which way the tempo lurches) lives in `TourRun.event_track` rather
## than being re-rolled at strike time.

var id: StringName
## Said on every peer, from their own clock, TourChaos.TELEGRAPH_SECONDS before the strike.
var telegraph: String = ""
## Said once struck, and while it stays struck or has recovered.
var line: String = ""
## Whether `TourChaos.pick_track` draws this event a target strip, stored in
## `TourRun.event_track`; false for an event with no strip of its own (`stage_unplugged`, whose
## track is always Stage, and `tempo_lurch`, whose slot holds the sign of the kick instead --
## see TourChaos.pick_sign).
var wants_track: bool = false
## Extra track names `pick_track` never gives this event, beyond Stage, Keys, a muted strip and
## this brief's own flaws' tracks -- `plugin_haywire`'s "never on Bass DI", so a muddy_bass brief
## is never judged twice on one strip.
var extra_track_excludes: Array[String] = []
## Flaws (or other events) this one is never drawn alongside -- see TourChaos.draw.
var excludes_flaws: Array[StringName] = []
## (run: TourRun, track_index: int) -> void -- DAW verbs only, the one place this runs.
var _strike: Callable = Callable()
## (state: MixState, run: TourRun, track_index: int) -> bool
var _recovered: Callable = Callable()


func strike(run: TourRun, track_index: int) -> void:
	if _strike.is_valid():
		_strike.call(run, track_index)


func recovered(state: MixState, run: TourRun, track_index: int) -> bool:
	return bool(_recovered.call(state, run, track_index)) if _recovered.is_valid() else true


func telegraph_for(run: TourRun, track_index: int) -> String:
	return _fill(telegraph, run, track_index)


func line_for(run: TourRun, track_index: int) -> String:
	return _fill(line, run, track_index)


## A single "%s" fills with the struck strip's name, upper-cased, the way TourHud's flaw lines
## read; a single "%d" fills with the run's song tempo, the way TourFlaw.line_for's does. Never
## both in the one string -- nothing in the catalogue needs both at once.
func _fill(text: String, run: TourRun, track_index: int) -> String:
	if "%s" in text:
		return text % _track_name(track_index).to_upper()
	if "%d" in text:
		return text % run.song_tempo
	return text


func _track_name(track_index: int) -> String:
	if track_index <= 0 or DAW.state == null:
		return ""
	var t := DAW.state.track(track_index, false)
	return t.name if t != null else ""
