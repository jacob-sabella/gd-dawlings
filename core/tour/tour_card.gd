class_name TourCard
extends RefCounted

## One gear card from the draft: a boon, or a curse riding along with it.
##
## `apply` is the only place a card touches the DAW, and it only ever goes through `DAW`'s own
## verbs -- `add_track`, `add_fx`, `set_track_mute` -- the same door every other surface uses, or
## through a plain change to the run's own numbers (`TourRun.tempo_tolerance_mult`) for the gear
## that never touches the mix at all.

var id: StringName
var title: String = ""
var description: String = ""
var is_curse: bool = false
## Called with the run so `apply` can read/write `TourRun` fields; the DAW side, if any, is
## bound into this at construction (see TourDeck.all_cards).
var _effect: Callable = Callable()


func apply(run: TourRun) -> void:
	if _effect.is_valid():
		_effect.call(run)
