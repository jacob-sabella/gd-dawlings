class_name TourPart
extends RefCounted

## One job a brief hands to a player: notes that actually have to land on the Stage lane
## (Tour.STAGE_TRACK), on a particular instrument, in a particular place -- a backbeat, an
## eighth-note pulse, a stab on the one. Mirrors TourFlaw's shape, but is judged by
## TourMeasure.Rhythm against notes a hand played, not by anything sitting on the desk.
##
## Who played it is not on the lane -- a take's name cannot be trusted, and HitRecorder/GuestMidi
## both land on the one shared, first-armed lane regardless of who held the instrument (see
## core/tour/tour_parts.gd) -- so a part is told apart from another by its instrument
## (`channel`/`pitches`), the way the room can only ever hold one of each.

var id: StringName
## The Item.id a player has to be holding to make these notes: &"shaker", &"tambourine", or
## &"keytar". Read by TourParts.draw (never two parts for the same instrument at once) and by
## the HUD to say which strip a holder is sent to; not read by the judge itself, which only
## looks at the notes' channel and pitch.
var instrument: StringName
## What the band is told.
var line: String = ""
## The channels items record on, 0-based: 9 the hand percussion's (HitRecorder.CHANNEL) and 10
## the pitched items' (InstrumentItem.MELODIC_CHANNEL, the handbells). Mirrored here rather than
## referenced, because Tour code knows nothing of core/items/; a suite check keeps them equal.
const ITEM_CHANNELS: Array[int] = [9, 10]

## A note's MIDI channel, 0-based as HitRecorder/GuestMidi write it: 9 is the hand percussion's
## channel (HitRecorder.CHANNEL, not referenced directly -- Tour code knows nothing of
## core/items/). -1 means any channel but the items' (ITEM_CHANNELS): a keytar's keys, wherever
## they come from, and never a handbell rung during the brief.
var channel: int = 9
## Which General MIDI pitches count; empty means any pitch counts (a keytar's stabs, whose chord
## is the player's call).
var pitches: PackedInt32Array = PackedInt32Array()
## Bar positions in beats this part is judged against (0 = the one); empty means use `grid`.
var beats: PackedFloat64Array = PackedFloat64Array()
## A beat grid judged against instead of fixed `beats`; 0.0 means `beats` is used instead.
var grid: float = 0.0
## Beats either side of a target (circular, so a wrap at the bar's edge is not a cliff) that
## still counts as landing on it.
var window: float = 0.2
## On-grid notes needed before the part counts as played.
var need: int = 8
## on-grid / all matching notes: a flood of off-grid hits must not pass a part just by volume.
var clean: float = 0.7


## `stage`: TourMeasure.Rhythm.result() for this part -- {"on", "off", "notes"}.
func played(stage: Dictionary) -> bool:
	var on := int(stage.get("on", 0))
	var notes := int(stage.get("notes", 0))
	return on >= need and notes > 0 and float(on) >= clean * float(notes)


func progress_line(hits: int) -> String:
	return "%d/%d" % [hits, need]
