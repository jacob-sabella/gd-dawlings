class_name TimelineItemPage
extends TimelinePage

## What can be done to the selected item, on the deck's ITEM page: its gain and fades on rails,
## mute, normalise, a copy at the playhead, a loop round it; for a MIDI item its notes up or down
## a semitone, onto the beat, harder or softer; for two overlapping items of one track, a crossfade.
##
## A rail edits the item when it is let go (or wheeled), not on every step of the drag: an item's
## gain is an edit, one undo step and one call to the DAW, where a fader is a live control. The
## rail says what letting go will do over its bead while it moves.

## Gain across the bar, in dB. The DAW takes more (DAWBackend.ITEM_GAIN_MIN/MAX); a bar that spent
## most of its travel below -24 dB would be a mute with extra steps.
const GAIN_LOW := -24.0
const GAIN_HIGH := 12.0
## A note grid for QUANTISE, in beats: the beat, or a sixteenth when fine.
const QUANT_GRID := 1.0
const QUANT_FINE_GRID := 0.25

const ITEM_INK := Color(0.45, 0.78, 0.95)
const NOTE_INK := Color(0.55, 0.70, 0.95)
const EDIT_INK := Color(0.90, 0.80, 0.40)
const GO_INK := Color(0.55, 0.85, 0.55)
const STOP_INK := Color(0.95, 0.45, 0.40)

var gain: GlyphRail
var fade_in: GlyphRail
var fade_out: GlyphRail
var mute: GlyphKey
var lock: GlyphKey
var normalise: GlyphKey
var copy_here: GlyphKey
var loop_to: GlyphKey
var crossfade: GlyphKey
var down: GlyphKey
var up: GlyphKey
var quant: GlyphKey
var softer: GlyphKey
var harder: GlyphKey
## [track, item] being edited, or empty while there is not exactly one selected.
var _target: Array = []
## [track, first, second] while exactly two items of one track are selected, else empty.
var _pair: Array = []


func _ready() -> void:
	tab_name = "ITEM"
	tab_glyph = &"item"
	gain = _slider("ItemGain", &"gain", ITEM_INK, func() -> String: return "ITEM  GAIN",
			func(v: float) -> String: return "%+.1f dB" % _gain_db(v))
	gain.value_committed.connect(func(v: float):
		if not _target.is_empty():
			DAW.set_item_gain(_target[0], _target[1], _gain_db(v)))
	fade_in = _slider("ItemIn", &"fade_in", ITEM_INK, func() -> String: return "ITEM  FADE IN",
			func(v: float) -> String: return "%.2f s" % _fade_seconds(v))
	fade_in.value_committed.connect(func(v: float): _set_fades(_fade_seconds(v), NAN))
	fade_out = _slider("ItemOut", &"fade_out", ITEM_INK, func() -> String: return "ITEM  FADE OUT",
			func(v: float) -> String: return "%.2f s" % _fade_seconds(v))
	fade_out.value_committed.connect(func(v: float): _set_fades(NAN, _fade_seconds(v)))
	_group()
	mute = _key("ItemMute", &"mute", STOP_INK, "ITEM  MUTE", _toggle_mute,
			func() -> String: return "muted: press to play it again" if mute.lit else "silence it", true)
	lock = _key("ItemLock", &"lock", Color(0.92, 0.94, 1.0), "ITEM  LOCK", _toggle_lock,
			func() -> String: return "locked: press to let it move again" if lock.lit else "pin it where it is", true)
	normalise = _key("ItemNormalise", &"normalise", EDIT_INK, "ITEM  NORMALISE", _normalise,
			func() -> String: return "gain so its loudest moment is full scale" if normalise.lit \
					else "for a recorded item")
	copy_here = _key("ItemCopyHere", &"copy_here", GO_INK, "ITEM  COPY TO PLAYHEAD",
			func(): DAW.copy_selected_to(DAW.state.position_seconds),
			func() -> String: return "a copy where the song is now")
	loop_to = _key("ItemLoop", &"loop", GO_INK, "ITEM  LOOP IT", func(): DAW.loop_selected_items(),
			func() -> String: return "loop from the start of the selection to its end")
	crossfade = _key("ItemCrossfade", &"crossfade", EDIT_INK, "ITEM  CROSSFADE", _crossfade,
			func() -> String: return "fade the earlier out and the later in, over the overlap" if crossfade.lit \
					else "select two overlapping items on one track")
	_group()
	down = _key("ItemDown", &"pitch_down", NOTE_INK, "ITEM  TRANSPOSE DOWN", func(): _transpose(-1),
			func() -> String: return "a semitone down; fine: an octave" if down.lit else "for a MIDI item")
	up = _key("ItemUp", &"pitch_up", NOTE_INK, "ITEM  TRANSPOSE UP", func(): _transpose(1),
			func() -> String: return "a semitone up; fine: an octave" if up.lit else "for a MIDI item")
	quant = _key("ItemQuant", &"quantise", NOTE_INK, "ITEM  QUANTISE", _quantise,
			func() -> String: return "notes onto the beat; fine: onto sixteenths" if quant.lit else "for a MIDI item")
	softer = _key("ItemSofter", &"softer", NOTE_INK, "ITEM  NOTES SOFTER", func(): _velocity(-1),
			func() -> String: return "every note a little softer; fine: much softer" if softer.lit else "for a MIDI item")
	harder = _key("ItemHarder", &"harder", NOTE_INK, "ITEM  NOTES HARDER", func(): _velocity(1),
			func() -> String: return "every note a little harder; fine: much harder" if harder.lit else "for a MIDI item")
	DAW.timeline_changed.connect(refresh)
	DAW.transport_changed.connect(refresh)
	refresh()


## Follows the selection: the bars set from the item while exactly one is selected, the crossfade
## while two of one track are, and everything out of reach while neither.
func refresh() -> void:
	var picked: Array = DAW.state.selected_items()
	_target = picked[0] if picked.size() == 1 else []
	_pair = []
	if picked.size() == 2 and picked[0][0] == picked[1][0]:
		_pair = [picked[0][0], picked[0][1], picked[1][1]]
	var item: MixState.ItemState = null if _target.is_empty() else DAW.state.item(_target[0], _target[1])
	if item == null:
		_target = []
	var one := item != null
	for c in [gain, fade_in, fade_out, mute, lock, normalise, down, up, quant, softer, harder]:
		c.available = one
	copy_here.available = not picked.is_empty()
	loop_to.available = not picked.is_empty()
	copy_here.lit = not picked.is_empty()
	loop_to.lit = not picked.is_empty()
	crossfade.available = not _pair.is_empty()
	crossfade.lit = not _pair.is_empty() and _overlaps(_pair)
	notice = "" if not picked.is_empty() else "select an item on the timeline"
	if not one:
		for c in [mute, lock, normalise, down, up, quant, softer, harder]:
			c.lit = false
		return
	gain.snap_to(clampf((item.gain_db - GAIN_LOW) / (GAIN_HIGH - GAIN_LOW), 0.0, 1.0))
	fade_in.snap_to(_fade_value(item.fade_in))
	fade_out.snap_to(_fade_value(item.fade_out))
	mute.lit = item.muted
	lock.lit = item.locked
	# A locked item's shape is not the rails' to change.
	for c in [gain, fade_in, fade_out, normalise, down, up, quant, softer, harder]:
		c.available = not item.locked
	normalise.lit = item.sound_peak() > 0.0
	var midi := not item.notes.is_empty()
	for key in [down, up, quant, softer, harder]:
		key.lit = midi


func _gain_db(v: float) -> float:
	return lerpf(GAIN_LOW, GAIN_HIGH, v)


## Squared, so the short fades a click wants have most of the travel; the whole item at the end.
func _fade_seconds(v: float) -> float:
	return v * v * _item_length()


func _fade_value(seconds: float) -> float:
	return sqrt(clampf(seconds / maxf(_item_length(), 0.0001), 0.0, 1.0))


func _item_length() -> float:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	return item.length if item != null else 1.0


func _set_fades(fin: float, fout: float) -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return
	DAW.set_item_fades(_target[0], _target[1], item.fade_in if is_nan(fin) else fin,
			item.fade_out if is_nan(fout) else fout)


func _transpose(direction: int) -> void:
	if not _target.is_empty():
		DAW.transpose_item(_target[0], _target[1], direction * (12 if _fine(up) or _fine(down) else 1))


func _velocity(direction: int) -> void:
	if not _target.is_empty():
		DAW.shift_velocity(_target[0], _target[1], direction * (32 if _fine(harder) or _fine(softer) else 8))


func _quantise() -> void:
	if not _target.is_empty():
		DAW.quantize_item(_target[0], _target[1], QUANT_FINE_GRID if _fine(quant) else QUANT_GRID)


func _overlaps(pair: Array) -> bool:
	var a := DAW.state.item(pair[0], pair[1])
	var b := DAW.state.item(pair[0], pair[2])
	return a != null and b != null and minf(a.end(), b.end()) - maxf(a.start, b.start) >= DAWBackend.MIN_ITEM_SECONDS


func _crossfade() -> void:
	if not _pair.is_empty():
		DAW.crossfade_items(_pair[0], _pair[1], _pair[2])


func _normalise() -> void:
	if not _target.is_empty():
		DAW.normalise_item(_target[0], _target[1])


func _toggle_lock() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item != null:
		DAW.set_item_locked(_target[0], _target[1], not item.locked)


func _toggle_mute() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item != null:
		DAW.set_item_muted(_target[0], _target[1], not item.muted)


## The hand pressing a key holds fine (shift on a monitor).
func _fine(key: ControlAffordance) -> bool:
	var by: Node = key.held_by
	return by != null and by.has_method("fine") and by.fine()
