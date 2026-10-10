class_name TourFlaw
extends RefCounted

## One way a brief's rescue song can be wrong, and how the band judges and fixes it.
##
## `bake` writes the flaw into the `DawKitProject` TourProject.song_for is building, before it
## is loaded through ProjectBridge. `fixed` is asked every host tick, against the live desk
## (`MixState`) or, for `dragging_keys`, against the Timing measure (which reads placed notes,
## not audio) -- never against anything a screenshot could not also answer, because nothing here
## is new instrumentation invented for Tour's sake. See core/tour/tour_flaws.gd for the catalogue.

var id: StringName
## The one line the band is told. Formatted with the run's song tempo where it has a "%d".
var line: String = ""
## Which rescue track (TourProject.BAND name) this flaw breaks; "" for the whole project.
var track: String = ""
## Flaws this one never shares a brief with -- see TourFlaws.draw.
var excludes: Array[StringName] = []
## (p: DawKitProject, rng: RandomNumberGenerator, song_tempo: float) -> void
var _bake: Callable = Callable()
## (state: MixState, run: TourRun) -> bool
var _fixed: Callable = Callable()


func bake(p: DawKitProject, rng: RandomNumberGenerator, song_tempo: float) -> void:
	if _bake.is_valid():
		_bake.call(p, rng, song_tempo)


func fixed(state: MixState, run: TourRun) -> bool:
	return bool(_fixed.call(state, run)) if _fixed.is_valid() else false


func line_for(run: TourRun) -> String:
	return line % run.song_tempo if "%d" in line else line
