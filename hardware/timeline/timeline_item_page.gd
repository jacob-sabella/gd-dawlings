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
## How the fade in runs, and the fade out (DawKitClip.FADE_*), each its own token, its mark the
## curve; a press is the next shape.
var fade_in_shape: GlyphKey
var fade_out_shape: GlyphKey
var mute: GlyphKey
var lock: GlyphKey
var reverse: GlyphKey
var normalise: GlyphKey
var copy_here: GlyphKey
var loop_to: GlyphKey
var crossfade: GlyphKey
## The selection on each track made one item (DAW.glue_selected).
var glue: GlyphKey
## The selection a step of the grid earlier or later (TimelineLanes.grid; fine: ten milliseconds).
var nudge_earlier: GlyphKey
var nudge_later: GlyphKey
var down: GlyphKey
var up: GlyphKey
var quant: GlyphKey
## How swung QUANTISE is, from straight to triplet: a setting of the next press, this person's
## own, not an edit of anything.
var swing: GlyphRail
var softer: GlyphKey
var harder: GlyphKey
var humanise: GlyphKey
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
	fade_in_shape = _key("ItemFadeInShape", &"fade_linear", ITEM_INK, "ITEM  FADE IN SHAPE",
			func(): _next_shape(false), func() -> String: return _shape_text(false))
	fade_out = _slider("ItemOut", &"fade_out", ITEM_INK, func() -> String: return "ITEM  FADE OUT",
			func(v: float) -> String: return "%.2f s" % _fade_seconds(v))
	fade_out.value_committed.connect(func(v: float): _set_fades(NAN, _fade_seconds(v)))
	fade_out_shape = _key("ItemFadeOutShape", &"fade_out_linear", ITEM_INK, "ITEM  FADE OUT SHAPE",
			func(): _next_shape(true), func() -> String: return _shape_text(true))
	_group()
	mute = _key("ItemMute", &"mute", STOP_INK, "ITEM  MUTE", _toggle_mute,
			func() -> String: return "muted: press to play it again" if mute.lit else "silence it", true)
	lock = _key("ItemLock", &"lock", Color(0.92, 0.94, 1.0), "ITEM  LOCK", _toggle_lock,
			func() -> String: return "locked: press to let it move again" if lock.lit else "pin it where it is", true)
	reverse = _key("ItemReverse", &"reverse", EDIT_INK, "ITEM  REVERSE", _toggle_reverse, _reverse_text, true)
	normalise = _key("ItemNormalise", &"normalise", EDIT_INK, "ITEM  NORMALISE", _normalise,
			func() -> String: return "gain so its loudest moment is full scale" if normalise.lit \
					else "for a recorded item")
	copy_here = _key("ItemCopyHere", &"copy_here", GO_INK, "ITEM  COPY TO PLAYHEAD",
			func(): DAW.copy_selected_to(DAW.state.position_seconds),
			func() -> String: return "a copy where the song is now")
	loop_to = _key("ItemLoop", &"loop", GO_INK, "ITEM  LOOP IT", func(): DAW.loop_selected_items(),
			func() -> String: return "loop from the start of the selection to its end")
	crossfade = _key("ItemCrossfade", &"crossfade", EDIT_INK, "ITEM  CROSSFADE", _crossfade,
			func() -> String: return "fade the earlier out and the later in, equal power, over the overlap" if crossfade.lit \
					else "select two overlapping items on one track")
	glue = _key("ItemGlue", &"glue", EDIT_INK, "ITEM  GLUE", func(): DAW.glue_selected(), _glue_text)
	nudge_earlier = _key("ItemNudgeEarlier", &"nudge_earlier", GO_INK, "ITEM  NUDGE EARLIER", func(): _nudge(-1),
			func() -> String: return _nudge_text("earlier"))
	nudge_later = _key("ItemNudgeLater", &"nudge_later", GO_INK, "ITEM  NUDGE LATER", func(): _nudge(1),
			func() -> String: return _nudge_text("later"))
	_group()
	down = _key("ItemDown", &"pitch_down", NOTE_INK, "ITEM  TRANSPOSE DOWN", func(): _transpose(-1),
			func() -> String: return "a semitone down; fine: an octave" if down.lit else "for a MIDI item")
	up = _key("ItemUp", &"pitch_up", NOTE_INK, "ITEM  TRANSPOSE UP", func(): _transpose(1),
			func() -> String: return "a semitone up; fine: an octave" if up.lit else "for a MIDI item")
	quant = _key("ItemQuant", &"quantise", NOTE_INK, "ITEM  QUANTISE", _quantise, _quant_text)
	swing = _slider("ItemSwing", &"swing", NOTE_INK, func() -> String: return "ITEM  QUANTISE SWING",
			func(v: float) -> String: return "straight" if v <= 0.0 else "%d%% (100%%: triplet)" % roundi(v * 100.0))
	swing.fixed_width = GlyphRail.WIDTH * 0.8
	softer = _key("ItemSofter", &"softer", NOTE_INK, "ITEM  NOTES SOFTER", func(): _velocity(-1),
			func() -> String: return "every note a little softer; fine: much softer" if softer.lit else "for a MIDI item")
	harder = _key("ItemHarder", &"harder", NOTE_INK, "ITEM  NOTES HARDER", func(): _velocity(1),
			func() -> String: return "every note a little harder; fine: much harder" if harder.lit else "for a MIDI item")
	humanise = _key("ItemHumanise", &"humanise", NOTE_INK, "ITEM  HUMANISE", _humanise, _humanise_text)
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
	for c in [gain, fade_in, fade_out, fade_in_shape, fade_out_shape, mute, lock, reverse, normalise, down, up, quant, swing, softer, harder, humanise]:
		c.available = one
	var movable: bool = picked.any(func(p): return not DAW.state.item(p[0], p[1]).locked)
	for key in [nudge_earlier, nudge_later]:
		key.available = movable
		key.lit = movable
	copy_here.available = not picked.is_empty()
	loop_to.available = not picked.is_empty()
	copy_here.lit = not picked.is_empty()
	loop_to.lit = not picked.is_empty()
	crossfade.available = not _pair.is_empty()
	crossfade.lit = not _pair.is_empty() and _overlaps(_pair)
	var glues := not DAWBackend.glue_picks(DAW.state).is_empty()
	glue.available = picked.size() >= 2
	glue.lit = glues
	notice = "" if not picked.is_empty() else "select an item on the timeline"
	if not one:
		for c in [mute, lock, reverse, normalise, down, up, quant, softer, harder, humanise, fade_in_shape, fade_out_shape]:
			c.lit = false
		return
	gain.snap_to(clampf((item.gain_db - GAIN_LOW) / (GAIN_HIGH - GAIN_LOW), 0.0, 1.0))
	fade_in.snap_to(_fade_value(item.fade_in))
	fade_out.snap_to(_fade_value(item.fade_out))
	mute.lit = item.muted
	lock.lit = item.locked
	# A locked item's shape is not the rails' to change.
	for c in [gain, fade_in, fade_out, fade_in_shape, fade_out_shape, reverse, normalise, down, up, quant, swing, softer, harder, humanise]:
		c.available = not item.locked
	fade_in_shape.glyph = TimelineGlyph.fade_glyph(item.fade_shape, false)
	fade_in_shape.lit = item.fade_shape != DawKitClip.FADE_LINEAR
	fade_out_shape.glyph = TimelineGlyph.fade_glyph(item.fade_out_shape, true)
	fade_out_shape.lit = item.fade_out_shape != DawKitClip.FADE_LINEAR
	normalise.lit = item.sound_peak() > 0.0
	reverse.lit = item.reversed
	reverse.available = not item.locked and not item.source.is_empty() and not item.is_looped()
	var midi := not item.notes.is_empty()
	for key in [down, up, quant, softer, harder, humanise]:
		key.lit = midi
	swing.available = midi and not item.locked


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


## A step of the person's grid, as [amount, unit]: a bar, a beat or part of one, or with no grid
## (or fine) ten milliseconds.
static func nudge_step(fine: bool) -> Array:
	var g := TimelineLanes.grid
	if fine or g == TimelineLanes.OFF:
		return [NUDGE_FREE, DAWBackend.NUDGE_SECONDS]
	if g == TimelineLanes.BAR:
		return [1.0, DAWBackend.NUDGE_BARS]
	return [g, DAWBackend.NUDGE_BEATS]
const NUDGE_FREE := 0.01


func _nudge(direction: int) -> void:
	var step := nudge_step(_fine(nudge_earlier) or _fine(nudge_later))
	DAW.nudge_selected(direction * float(step[0]), int(step[1]))


func _nudge_text(way: String) -> String:
	if not nudge_earlier.available:
		return "select an item that is not locked"
	var g := TimelineLanes.grid
	var what := "ten milliseconds" if g == TimelineLanes.OFF else "a bar" if g == TimelineLanes.BAR \
			else "a beat" if g == 1.0 else "half a beat" if g == 0.5 else "a quarter beat"
	return "the selection %s %s; fine: ten milliseconds" % [what, way]


func _transpose(direction: int) -> void:
	if not _target.is_empty():
		DAW.transpose_item(_target[0], _target[1], direction * (12 if _fine(up) or _fine(down) else 1))


func _velocity(direction: int) -> void:
	if not _target.is_empty():
		DAW.shift_velocity(_target[0], _target[1], direction * (32 if _fine(harder) or _fine(softer) else 8))


## 15 ms and 8 velocity a press; 35 ms and 20 when fine.
const HUMANISE := [0.015, 8]
const HUMANISE_FINE := [0.035, 20]


func _humanise_text() -> String:
	if not humanise.lit:
		return "for a MIDI item"
	return "nudge every note's time and velocity a little, at random; fine: more"


func _humanise() -> void:
	if not _target.is_empty():
		var by: Array = HUMANISE_FINE if _fine(humanise) else HUMANISE
		DAW.humanise_item(_target[0], _target[1], by[0], by[1])


func _quant_text() -> String:
	if not quant.lit:
		return "for a MIDI item"
	var swung := "" if swing.value <= 0.0 else ", swung %d%%" % roundi(swing.value * 100.0)
	return "notes onto the beat; fine: onto sixteenths" + swung


func _quantise() -> void:
	if not _target.is_empty():
		DAW.quantize_item(_target[0], _target[1], QUANT_FINE_GRID if _fine(quant) else QUANT_GRID, 1.0,
				swing.value)


func _overlaps(pair: Array) -> bool:
	var a := DAW.state.item(pair[0], pair[1])
	var b := DAW.state.item(pair[0], pair[2])
	return a != null and b != null and minf(a.end(), b.end()) - maxf(a.start, b.start) >= DAWBackend.MIN_ITEM_SECONDS


## What each of DawKitClip's fade shapes is called on a card, in its order.
const SHAPE_NAMES := ["straight", "equal power", "slow, then quick", "quick, then slow", "S-curve"]


## The fade in's shape, or the fade out's, the next one round; the other end left as it is.
func _next_shape(out: bool) -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return
	var in_shape := item.fade_shape
	var out_shape := item.fade_out_shape
	if out:
		out_shape = (out_shape + 1) % DawKitClip.FADE_SHAPES
	else:
		in_shape = (in_shape + 1) % DawKitClip.FADE_SHAPES
	DAW.set_item_fade_shape(_target[0], _target[1], in_shape, out_shape)


func _shape_text(out: bool) -> String:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return "select an item"
	var shape := item.fade_out_shape if out else item.fade_shape
	return "%s; press for %s" % [SHAPE_NAMES[shape], SHAPE_NAMES[(shape + 1) % DawKitClip.FADE_SHAPES]]


func _glue_text() -> String:
	var picks := DAWBackend.glue_picks(DAW.state)
	if not picks.is_empty():
		var parts := 0
		for index in picks:
			parts += (picks[index] as Array).size()
		return "%d items made one, on %d track(s)" % [parts, picks.size()]
	if DAW.state.selected_items().size() >= 2:
		return "MIDI items, or the pieces of one cut recording, side by side"
	return "select two or more items on a track"


func _crossfade() -> void:
	if not _pair.is_empty():
		DAW.crossfade_items(_pair[0], _pair[1], _pair[2])


func _normalise() -> void:
	if not _target.is_empty():
		DAW.normalise_item(_target[0], _target[1])


func _reverse_text() -> String:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null or item.source.is_empty():
		return "for a recorded item"
	if item.is_looped():
		return "not while it loops"
	return "backwards: press to play it forwards" if item.reversed else "play it backwards"


func _toggle_reverse() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item != null:
		DAW.set_item_reversed(_target[0], _target[1], not item.reversed)


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
