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

## The selected item opened in the clip editor (TimelineSurface.edit_asked), as a double click on
## it does: the one way to it for a hand that cannot double click.
var edit_clip: GlyphKey
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
## Which take lane the item is on, a press the next (DAW.set_item_lane), and the track's comp made to
## sound this item's lane over this item's stretch (DAW.set_comp).
var take_lane: GlyphKey
var comp_here: GlyphKey
## The track's comp made plain clips on the first lane (DAW.flatten_comp).
var flatten: GlyphKey
## Freeze the track to a file of its sound, or thaw it (DAW.freeze_track, DAW.thaw_track).
var freeze: GlyphKey
## Which controller lane the RAMP token works on, and it: the mod wheel, expression, volume, the
## pedal, the pitch wheel, aftertouch. A MIDI item's lane is a rising ramp, a falling one, or none.
var cc_kind: GlyphKey
var cc_ramp: GlyphKey
var _cc_index := 0
const CC_KINDS := [1, 11, 7, 64, DawKitClip.PITCH_BEND, DawKitClip.AFTERTOUCH]
const CC_NAMES := ["mod wheel", "expression", "volume", "sustain pedal", "pitch wheel", "aftertouch"]
const RAMP_POINTS := 16
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
## Two MIDI items selected: the first lends its timing to the second.
var groove: GlyphKey
## An audio item's sound made twice as long or half as long (fine), pitch kept; or a semitone
## higher or lower (fine), length kept. Each makes a new file; one undo step.
var stretch: GlyphKey
var pitch_shift: GlyphKey
var softer: GlyphKey
var harder: GlyphKey
var humanise: GlyphKey
## Every note held until the next begins (DAW.legato_item).
var legato: GlyphKey
## Every note cut short (DAW.staccato_item).
var staccato: GlyphKey
## Every note given the same velocity (DAW.even_velocity).
var even: GlyphKey
## The notes played backwards (DAW.retrograde_item).
var retrograde: GlyphKey
## The note sounding at the playhead taken out (DAW.delete_note).
var note_delete: GlyphKey
## A note of a beat put in at the playhead, at the pitch of the one beside it (DAW.insert_note).
var note_add: GlyphKey
## The note sounding at the playhead made to end there (DAW.set_note_end).
var note_end: GlyphKey
## The note sounding at the playhead moved by a sixteenth, a beat when fine (DAW.move_note).
var note_earlier: GlyphKey
var note_later: GlyphKey
## The note sounding at the playhead moved a semitone, or an octave when fine (DAW.transpose_note).
var note_up: GlyphKey
var note_down: GlyphKey
## Name the item, on the keypad (DAW.rename_item).
var item_name: GlyphKey
## The velocity of the note sounding at the playhead (else the next to start): a rail, set when let go.
var note_velocity: GlyphRail
## [track, item] being edited, or empty while there is not exactly one selected.
var _target: Array = []
## [track, first, second] while exactly two items of one track are selected, else empty.
var _pair: Array = []


func _ready() -> void:
	tab_name = "ITEM"
	tab_glyph = &"item"
	edit_clip = _key("ItemEditClip", &"clip_edit", GO_INK, "ITEM  EDIT CLIP", _edit_clip,
			func() -> String: return "open it in the clip editor, to trim to the millisecond" if edit_clip.lit \
					else "select one item")
	_group()
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
	take_lane = _key("ItemLane", &"lane", EDIT_INK, "ITEM  TAKE LANE", _next_lane, _lane_text)
	comp_here = _key("ItemComp", &"comp", GO_INK, "ITEM  COMP HERE", _comp_here, _comp_text)
	flatten = _key("ItemFlatten", &"flatten", EDIT_INK, "ITEM  FLATTEN COMP", _flatten, _flatten_text)
	freeze = _key("ItemFreeze", &"freeze", GO_INK, "ITEM  FREEZE TRACK", _freeze, _freeze_text)
	cc_kind = _key("ItemCcKind", &"cc", EDIT_INK, "ITEM  CONTROLLER", _next_cc, _cc_text)
	cc_ramp = _key("ItemCcRamp", &"ramp", EDIT_INK, "ITEM  CONTROLLER RAMP", _ramp, _ramp_text)
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
	groove = _key("ItemGroove", &"groove", NOTE_INK, "ITEM  GROOVE", _groove, _groove_text)
	stretch = _key("ItemStretch", &"stretch", EDIT_INK, "ITEM  STRETCH", _stretch, _stretch_text)
	pitch_shift = _key("ItemPitchShift", &"pitch_shift", EDIT_INK, "ITEM  PITCH SHIFT", _pitch_shift, _pitch_text)
	softer = _key("ItemSofter", &"softer", NOTE_INK, "ITEM  NOTES SOFTER", func(): _velocity(-1),
			func() -> String: return "every note a little softer; fine: much softer" if softer.lit else "for a MIDI item")
	harder = _key("ItemHarder", &"harder", NOTE_INK, "ITEM  NOTES HARDER", func(): _velocity(1),
			func() -> String: return "every note a little harder; fine: much harder" if harder.lit else "for a MIDI item")
	humanise = _key("ItemHumanise", &"humanise", NOTE_INK, "ITEM  HUMANISE", _humanise, _humanise_text)
	legato = _key("ItemLegato", &"legato", NOTE_INK, "ITEM  LEGATO", func(): _legato(), _legato_text)
	staccato = _key("ItemStaccato", &"staccato", NOTE_INK, "ITEM  STACCATO", func(): _staccato(), _staccato_text)
	item_name = _key("ItemName", &"item_name", Color(0.45, 0.78, 0.95), "ITEM  NAME", func(): _rename(),
			func() -> String:
				var item: MixState.ItemState = null if _target.is_empty() else DAW.state.item(_target[0], _target[1])
				return "rename \"%s\", on the keypad" % item.name if item != null else "select one item")
	retrograde = _key("ItemRetrograde", &"retrograde", NOTE_INK, "ITEM  NOTES BACKWARDS", func(): _retrograde(), _retrograde_text)
	note_add = _key("ItemNoteAdd", &"note_add", Color(0.55, 0.85, 0.55), "ITEM  ADD NOTE", func(): _add_note(),
			func() -> String: return "a note a beat long at the playhead, at the pitch of the one beside it" if note_add.lit \
					else "put the playhead inside a MIDI item")
	note_end = _key("ItemNoteEnd", &"note_end", NOTE_INK, "ITEM  NOTE ENDS HERE", func(): _end_note(),
			func() -> String: return "the note sounding at the playhead ends there" if note_end.lit else "put the playhead on a note")
	note_earlier = _key("ItemNoteEarlier", &"note_earlier", NOTE_INK, "ITEM  NOTE EARLIER", func(): _shift_note(-1),
			func() -> String: return "the note at the playhead a sixteenth earlier; fine: a beat" if note_earlier.lit else "put the playhead on a note")
	note_later = _key("ItemNoteLater", &"note_later", NOTE_INK, "ITEM  NOTE LATER", func(): _shift_note(1),
			func() -> String: return "the note at the playhead a sixteenth later; fine: a beat" if note_later.lit else "put the playhead on a note")
	note_down = _key("ItemNoteDown", &"note_down", NOTE_INK, "ITEM  NOTE DOWN", func(): _move_note(-1),
			func() -> String: return "the note at the playhead a semitone down; fine: an octave" if note_down.lit else "put the playhead on a note")
	note_up = _key("ItemNoteUp", &"note_up", NOTE_INK, "ITEM  NOTE UP", func(): _move_note(1),
			func() -> String: return "the note at the playhead a semitone up; fine: an octave" if note_up.lit else "put the playhead on a note")
	note_delete = _key("ItemNoteDelete", &"note_delete", Color(0.95, 0.38, 0.34), "ITEM  DELETE NOTE", func(): _delete_note(),
			func() -> String: return "the note sounding at the playhead" if note_delete.lit else "put the playhead on a note")
	even = _key("ItemEven", &"even", NOTE_INK, "ITEM  EVEN VELOCITY", func(): _even(), _even_text)
	note_velocity = _slider("ItemNoteVelocity", &"note_velocity", NOTE_INK, func() -> String: return "ITEM  NOTE VELOCITY",
			func(v: float) -> String: return "the note at the playhead: velocity %d" % _velocity_of(v))
	note_velocity.value_committed.connect(func(v: float):
		var n := _note_index()
		if n >= 0:
			DAW.set_note_velocity(_target[0], _target[1], n, _velocity_of(v)))
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
	item_name.lit = one
	edit_clip.available = one
	edit_clip.lit = one
	for c in [gain, fade_in, fade_out, fade_in_shape, fade_out_shape, mute, lock, reverse, take_lane, comp_here, flatten, freeze, cc_kind, cc_ramp, normalise, down, up, quant, swing, softer, harder, humanise, legato, staccato, even, retrograde, note_velocity, note_delete, note_add, note_end, note_earlier, note_later, note_up, note_down, item_name]:
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
	groove.available = picked.size() == 2
	var processable := one and _processable(item)
	stretch.available = processable
	stretch.lit = processable
	pitch_shift.available = processable
	pitch_shift.lit = processable
	groove.lit = not _groove_pair().is_empty()
	var glues := not DAWBackend.glue_picks(DAW.state).is_empty()
	glue.available = picked.size() >= 2
	glue.lit = glues
	notice = "" if not picked.is_empty() else "select an item on the timeline"
	if not one:
		for c in [mute, lock, reverse, normalise, down, up, quant, softer, harder, humanise, legato, staccato, even, retrograde, fade_in_shape, fade_out_shape]:
			c.lit = false
		return
	gain.snap_to(clampf((item.gain_db - GAIN_LOW) / (GAIN_HIGH - GAIN_LOW), 0.0, 1.0))
	fade_in.snap_to(_fade_value(item.fade_in))
	fade_out.snap_to(_fade_value(item.fade_out))
	mute.lit = item.muted
	lock.lit = item.locked
	# A locked item's shape is not the rails' to change.
	for c in [gain, fade_in, fade_out, fade_in_shape, fade_out_shape, reverse, take_lane, comp_here, flatten, freeze, cc_kind, cc_ramp, normalise, down, up, quant, swing, softer, harder, humanise, legato, staccato, even, retrograde, note_velocity]:
		c.available = not item.locked
	fade_in_shape.glyph = TimelineGlyph.fade_glyph(item.fade_shape, false)
	fade_in_shape.lit = item.fade_shape != DawKitClip.FADE_LINEAR
	fade_out_shape.glyph = TimelineGlyph.fade_glyph(item.fade_out_shape, true)
	fade_out_shape.lit = item.fade_out_shape != DawKitClip.FADE_LINEAR
	normalise.lit = item.sound_peak() > 0.0
	reverse.lit = item.reversed
	take_lane.lit = item.lane != 0
	comp_here.lit = true
	flatten.lit = not DAW.state.track(_target[0]).comp.is_empty()
	freeze.lit = DAW.state.track(_target[0]).is_frozen()
	var moving := not item.notes.is_empty() and not item.locked
	cc_kind.available = moving
	cc_ramp.available = moving
	cc_ramp.lit = lane_shape(item, CC_KINDS[_cc_index]) != 0
	cc_kind.lit = item.controls.size() > 0
	reverse.available = not item.locked and not item.source.is_empty() and not item.is_looped()
	var midi := not item.notes.is_empty()
	for key in [down, up, quant, softer, harder, humanise, legato, staccato, even, retrograde]:
		key.lit = midi
	swing.available = midi and not item.locked
	note_velocity.available = midi and not item.locked
	note_delete.available = midi and not item.locked
	note_up.available = midi and not item.locked
	note_add.available = midi and not item.locked
	note_end.available = midi and not item.locked
	note_earlier.available = midi and not item.locked
	note_later.available = midi and not item.locked
	note_earlier.lit = midi and _sounding_note() >= 0
	note_later.lit = note_earlier.lit
	note_end.lit = midi and _sounding_note() >= 0
	var inside := DAW.state.position_seconds > item.start and DAW.state.position_seconds < item.start + item.length - MidiTake.MIN_NOTE
	note_add.lit = midi and inside
	note_down.available = midi and not item.locked
	note_delete.lit = midi and _sounding_note() >= 0
	note_up.lit = note_delete.lit
	note_down.lit = note_delete.lit
	var n := _note_index()
	if n >= 0:
		note_velocity.snap_to((float(item.notes[n * MidiTake.NOTE_WIDTH + 3]) - 1.0) / 126.0)


func _edit_clip() -> void:
	if not _target.is_empty() and surface != null:
		surface.edit_asked.emit(_target[0], _target[1])


static func _velocity_of(v: float) -> int:
	return clampi(1 + roundi(v * 126.0), 1, 127)


## The note sounding at the playhead, else -1.
func _sounding_note() -> int:
	var n := _note_index()
	var item: MixState.ItemState = null if _target.is_empty() else DAW.state.item(_target[0], _target[1])
	if n < 0 or item == null:
		return -1
	var t := DAW.state.position_seconds - item.start
	var at := n * MidiTake.NOTE_WIDTH
	return n if item.notes[at] <= t and t < item.notes[at + 1] else -1


func _add_note() -> void:
	var item: MixState.ItemState = null if _target.is_empty() else DAW.state.item(_target[0], _target[1])
	if item == null or item.notes.is_empty() and item.source != "":
		return
	var on := DAW.state.position_seconds - item.start
	var n := DAWBackend.note_near(item.notes, on)
	var pitch := int(item.notes[n * MidiTake.NOTE_WIDTH + 2]) if n >= 0 else 60
	DAW.insert_note(_target[0], _target[1], on, minf(on + 60.0 / DAW.state.tempo, item.length), pitch)


func _shift_note(direction: int) -> void:
	var n := _sounding_note()
	if n >= 0:
		var beat := 60.0 / DAW.state.tempo
		DAW.move_note(_target[0], _target[1], n, direction * beat * (1.0 if _fine(note_earlier) or _fine(note_later) else 0.25))


func _end_note() -> void:
	var n := _sounding_note()
	if n >= 0:
		DAW.set_note_end(_target[0], _target[1], n, DAW.state.position_seconds - DAW.state.item(_target[0], _target[1]).start)


func _move_note(direction: int) -> void:
	var n := _sounding_note()
	if n >= 0:
		DAW.transpose_note(_target[0], _target[1], n, direction * (12 if _fine(note_up) or _fine(note_down) else 1))


func _delete_note() -> void:
	var n := _sounding_note()
	if n >= 0:
		DAW.delete_note(_target[0], _target[1], n)


## Which note of the target the velocity rail means: the one at the playhead. -1 for none.
func _note_index() -> int:
	if _target.is_empty():
		return -1
	var item: MixState.ItemState = DAW.state.item(_target[0], _target[1])
	if item == null or item.notes.is_empty():
		return -1
	return DAWBackend.note_near(item.notes, DAW.state.position_seconds - item.start)


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


func _legato_text() -> String:
	return "each note held until the next begins" if legato.lit else "for a MIDI item"


func _legato() -> void:
	if not _target.is_empty():
		DAW.legato_item(_target[0], _target[1])


func _rename() -> void:
	if not _target.is_empty() and surface != null:
		surface.ask_item_name(_target[0], _target[1])


func _retrograde_text() -> String:
	return "the notes played backwards, last first" if retrograde.lit else "for a MIDI item"


func _retrograde() -> void:
	if not _target.is_empty():
		DAW.retrograde_item(_target[0], _target[1])


func _even_text() -> String:
	return "every note at the item's average velocity" if even.lit else "for a MIDI item"


func _even() -> void:
	if not _target.is_empty():
		DAW.even_velocity(_target[0], _target[1])


func _staccato_text() -> String:
	return "each note cut to half its length" if staccato.lit else "for a MIDI item"


func _staccato() -> void:
	if not _target.is_empty():
		DAW.staccato_item(_target[0], _target[1])


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


## With two MIDI items selected (not one), [target track, target item, source track, source item]: the
## second, in lane order, is pulled to the first's feel.
func _groove_pair() -> Array:
	var picked: Array = DAW.state.selected_items()
	if picked.size() != 2:
		return []
	for p in picked:
		var it := DAW.state.item(p[0], p[1])
		if it == null or it.notes.is_empty() or it.locked:
			return []
	return [picked[1][0], picked[1][1], picked[0][0], picked[0][1]]


func _groove_text() -> String:
	return "the second selected item takes the first's timing" if not _groove_pair().is_empty() \
			else "select two MIDI items: the first lends its feel to the second"


func _groove() -> void:
	var pair := _groove_pair()
	if not pair.is_empty():
		DAW.groove_item(pair[0], pair[1], pair[2], pair[3], QUANT_FINE_GRID if _fine(groove) else 0.5, 1.0)


## An item with a sound of its own that is not locked, reversed or looped.
func _processable(item: MixState.ItemState) -> bool:
	return not item.source.is_empty() and not item.locked and not item.reversed and not item.is_looped()


func _stretch_text() -> String:
	return "twice as long, same pitch; fine: half as long" if stretch.lit \
			else "for a sound item that is not locked, reversed or looped"


func _stretch() -> void:
	if not _target.is_empty():
		DAW.process_item(_target[0], _target[1], DAWBackend.PROCESS_STRETCH, 0.5 if _fine(stretch) else 2.0)


func _pitch_text() -> String:
	return "a semitone up, same length; fine: a semitone down" if pitch_shift.lit \
			else "for a sound item that is not locked, reversed or looped"


func _pitch_shift() -> void:
	if not _target.is_empty():
		DAW.process_item(_target[0], _target[1], DAWBackend.PROCESS_PITCH, -1.0 if _fine(pitch_shift) else 1.0)


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


## The lane after this item's, going back to the first past one more than the highest the other
## items use.
func _next_lane() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return
	var top := 0
	for other in DAW.state.track(_target[0]).items:
		if other != item:
			top = maxi(top, other.lane)
	var next := item.lane + 1
	if next > mini(top + 1, MixWire.LANES_MAX):
		next = 0
	DAW.set_item_lane(_target[0], _target[1], next)


func _lane_text() -> String:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return "select one item"
	return "on take lane %d: press for the next" % (item.lane + 1)


## The track plays this item's lane across this item's stretch.
func _comp_here() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item != null:
		DAW.set_comp(_target[0], item.start, item.end(), item.lane)


func _flatten() -> void:
	if not _target.is_empty():
		DAW.flatten_comp(_target[0])


## What the item's lane of controller `kind` is: 0 none, 1 a rising ramp, 2 a falling one, 3 anything else.
static func lane_shape(item: MixState.ItemState, kind: int) -> int:
	var c := DawKitClip.new()
	c.controls = item.controls
	var lane := c.control_lane(kind)
	if lane.is_empty():
		return 0
	for rising in [true, false]:
		var want := ramp_points(kind, item.length, rising)
		if lane.size() == want.size() and range(lane.size()).all(func(i): return is_equal_approx(lane[i][0], want[i][0]) and is_equal_approx(lane[i][1], want[i][1])):
			return 1 if rising else 2
	return 3


## A ramp across an item `length` seconds long, in RAMP_POINTS steps: from the bottom of the
## controller's range to the top, or from the top to the bottom.
static func ramp_points(kind: int, length: float, rising: bool) -> Array:
	var low := DawKitClip.BEND_MIN if kind == DawKitClip.PITCH_BEND else 0.0
	var high := DawKitClip.BEND_MAX if kind == DawKitClip.PITCH_BEND else 127.0
	var out: Array = []
	for k in RAMP_POINTS:
		var t := float(k) / (RAMP_POINTS - 1)
		out.append([length * float(k) / RAMP_POINTS, roundf(lerpf(low, high, t if rising else 1.0 - t))])
	return out


func _next_cc() -> void:
	_cc_index = (_cc_index + 1) % CC_KINDS.size()
	refresh()


## Rising, then falling, then gone: each press moves the chosen controller's lane on one.
func _ramp() -> void:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return
	var kind: int = CC_KINDS[_cc_index]
	var points: Array = []
	match lane_shape(item, kind):
		0, 3:
			points = ramp_points(kind, item.length, true)
		1:
			points = ramp_points(kind, item.length, false)
	DAW.set_item_controls(_target[0], _target[1], kind, 0, points)


func _cc_text() -> String:
	return "the %s: press for the next controller" % CC_NAMES[_cc_index]


func _ramp_text() -> String:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null or item.notes.is_empty():
		return "for a MIDI item"
	match lane_shape(item, CC_KINDS[_cc_index]):
		1:
			return "%s rises across it: press to make it fall" % CC_NAMES[_cc_index]
		2:
			return "%s falls across it: press to take it away" % CC_NAMES[_cc_index]
		3:
			return "%s has its own shape: press to ramp it up" % CC_NAMES[_cc_index]
	return "draw the %s rising across it" % CC_NAMES[_cc_index]


func _freeze() -> void:
	if _target.is_empty():
		return
	if DAW.state.track(_target[0]).is_frozen():
		DAW.thaw_track(_target[0])
	else:
		DAW.freeze_track(_target[0])


func _freeze_text() -> String:
	if _target.is_empty():
		return "select one item"
	if DAW.state.track(_target[0]).is_frozen():
		return "frozen: press to thaw it"
	return "bake the track's sound, plugins and all, into one file (plays the song once)"


func _flatten_text() -> String:
	if _target.is_empty() or DAW.state.track(_target[0]).comp.is_empty():
		return "for a track with a comp"
	return "make what the comp plays plain items on the first lane"


func _comp_text() -> String:
	var item := DAW.state.item(_target[0], _target[1]) if not _target.is_empty() else null
	if item == null:
		return "select one item"
	return "play take lane %d from here to its end" % (item.lane + 1)


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
