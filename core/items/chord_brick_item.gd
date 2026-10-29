class_name ChordBrick
extends Item

## A chord as a thing in your hand (docs/spatial_loop.md part two, slice 31, idea #16): a toy brick
## lettered on both long faces with its chord and its numeral in the key it was made in
## (Harmony.numeral), with a stud on its top for each bar it lasts, 1, 2 or 4.
##
## The fifths wheel makes them (#29's feeding): a strip tile pulled up out of the strip with a hand,
## or dragged off the board with the mouse, is a brick of its chord in that hand, and MAKE BRICKS
## makes the whole strip as bricks into the ledge. It is a made item (ItemRoom.mint, `brick1`,
## `brick2`, ...), its data {chord, key} sent once. Its length is not in that data: it is its nudge
## (the wheel or the thumbstick over it, or, in a hand, the brick turned in it: `follow_turn`), and
## the room's row `bricks` {id: bars}, so a nudge never resends what it was made of.
##
## The ledge (ChordLedge, holder LEDGE: sixteen slots along the bricks table's near edge) is where
## bricks stand in a row, and the slots' order is the progression. Pressed into a track (a timeline
## lane, a console strip or a stage voice, as a cassette is pasted) the row it was taken from, or
## the brick alone when it came from anywhere else, is block chords voiced at CENTRE, four notes
## (Harmony.voiced), one chord a brick for its bars, from the bar under the press (a lane) or the
## playhead's bar, as one take named TAKE_NAME (`notes_of`). Pressed into a section block, the row's
## harmony (`inside_of`) is written into that section's marker by the wheel's SET path, so the harp,
## the bells and the fingertips follow it there. It stays in the hand either way, to press again.

const KIND := &"brick"
const MODEL := "res://assets/models/chord_brick.glb"
## The real thing's size (tools/blender/chord_brick.py): along its lettered faces, up, through.
const SIZE := Vector3(0.060, 0.035, 0.045)
## The lengths a brick may be, in bars: what its nudge steps through.
const LENGTHS: Array[int] = [1, 2, 4]
## The ledge's holder (ItemRoom.holders) and its bin's.
const LEDGE := &"ledge"
const BIN := &"ledge_bin"
## The track a press on a section block names (ControlAffordance.paste_spot_for): none, but a
## section, whose start is the press's seconds.
const SECTION := -1
## What a brick is made from (ItemRoom.made_data): "chord:<key>:<chord>" into the hand that made it,
## "ledge:<key>:<chord>" onto the ledge (the wheel's MAKE BRICKS).
const INTO_HAND := "chord"
const INTO_LEDGE := "ledge"
## The longest key and chord a brick is made of, as written ("F# minor", "C#m7b5").
const KEY_MOST := 24
const CHORD_MOST := 10
## How its chords are written into a track: voiced at CENTRE, VOICES notes, this hard, named so.
const CENTRE := 60
const VOICES := 4
const VELOCITY := 90
const TAKE_NAME := "chords"
## A stud on its top a bar: their size, and where they stand for 1, 2 and 4 bars.
const STUD_RADIUS := 0.0075
const STUD_TALL := 0.006
const STUDS := {1: [Vector2(0, 0)], 2: [Vector2(-0.015, 0), Vector2(0.015, 0)],
		4: [Vector2(-0.015, -0.011), Vector2(0.015, -0.011), Vector2(-0.015, 0.011), Vector2(0.015, 0.011)]}
## Turned this far in the hand that holds it (Interactor.twist), clockwise as its holder sees it,
## it is a notch longer; back the other way, shorter. A bare hand has no stick and no wheel
## (XRInteractor), so it turns the brick, as a key in a lock: a sixth of a turn a notch, more than a
## hand rolls carrying it across the table.
const TURN_STEP := PI / 3.0
const INK := Color(0.1, 0.07, 0.05)
## A thin halo of the paint round the ink, unlit, so the letters read on a face in shade too.
const HALO := Color(0.95, 0.9, 0.78)

## Its length was nudged here, to `bars`: for the room's row (Studio, the `bricks` ask).
signal resized(bars: int)

## Its chord, as the wheel spelled it ("Am", "Bdim"), and the key it was made in ("C major").
var chord := ""
var key := ""
## Everything it carries, as minted: what `read` was given.
var data: Dictionary = {}
## How many bars it lasts: one of LENGTHS. The room's (`bricks`), never its data.
var bars := 1:
	set(v):
		v = v if v in LENGTHS else 1
		if v == bars:
			return
		bars = v
		_stud()
		_letter()
## The ledge slot it was taken from, while it is in a hand: what makes a press write the ledge's
## whole row and not the brick alone. -1 for none.
var from_ledge := -1
## The holding hand's twist the last notch was counted from; NAN while it is in no hand that turns.
var _turn_from := NAN
var _letters: Array[Label3D] = []
var _studs: Array[MeshInstance3D] = []


func _init() -> void:
	id = KIND
	super()


# --- what it is made of ----------------------------------------------------------------------

## What a brick of `chord` in `key` is made from, into the maker's hand or onto the ledge.
static func from_text(onto_ledge: bool, in_key: String, of_chord: String) -> String:
	return "%s:%s:%s" % [INTO_LEDGE if onto_ledge else INTO_HAND, in_key, of_chord]


## Whether `from` (ItemRoom.made_data's) makes a brick onto the ledge.
static func into_ledge(from: String) -> bool:
	return from.begins_with(INTO_LEDGE + ":")


## What a brick made `from` carries ({chord, key}), sanitised as the host packs it: a key and a
## chord that read together (Harmony.parse), each no longer than it may be. Empty otherwise.
static func data_from(from: String) -> Dictionary:
	var part := from.split(":")
	if part.size() != 3 or not (part[0] in [INTO_HAND, INTO_LEDGE]):
		return {}
	var k := part[1].strip_edges()
	var c := part[2].strip_edges()
	if k.is_empty() or c.is_empty() or k.length() > KEY_MOST or c.length() > CHORD_MOST or c == "-":
		return {}
	var h := Harmony.parse("[%s: %s]" % [k, c])
	if h == null or h.progression.size() != 1:
		return {}
	return {"chord": c, "key": k}


## The made item's row read back (`data`, from the host or a file): what it is, lettered.
func read(made: Dictionary) -> void:
	data = made
	chord = str(made.get("chord", "")).substr(0, CHORD_MOST)
	key = str(made.get("key", "")).substr(0, KEY_MOST)
	_letter()


## Its numeral in the key it was made in: `IV`, `vi`, `vii°`; "" for a chord out of that key.
func numeral() -> String:
	var k := Harmony.parse("[%s]" % key)
	return k.numeral(chord) if k != null else ""


## "vi · 2 bars": what is lettered under the chord.
func under_text() -> String:
	var n := numeral()
	var length := "%d BAR%s" % [bars, "" if bars == 1 else "S"]
	return "%s · %s" % [n, length] if not n.is_empty() else length


# --- the row it is in ------------------------------------------------------------------------

## The bricks standing on `room`'s ledge, in slot order: the progression.
static func ledge_row(room: ItemRoom) -> Array[ChordBrick]:
	var by_slot := {}
	if room != null:
		for id in room.items:
			var b := room.items[id] as ChordBrick
			if b != null and b.slot_in == LEDGE and b.state == Item.State.LOOSE:
				by_slot[float(b.slot_n)] = b
	return _in_order(by_slot)


## What a press with `brick` writes: the ledge's row with it back in the place it was taken from,
## when it came from the ledge; else the brick alone.
static func row_of(brick: ChordBrick) -> Array[ChordBrick]:
	var room := ItemRoom.of(brick)
	if brick.from_ledge < 0 or room == null:
		return [brick]
	var by_slot := {}
	for b in ledge_row(room):
		by_slot[float(b.slot_n)] = b
	# Its own slot taken since, by another: just before that one.
	by_slot[float(brick.from_ledge) - (0.5 if by_slot.has(float(brick.from_ledge)) else 0.0)] = brick
	return _in_order(by_slot)


static func _in_order(by_slot: Dictionary) -> Array[ChordBrick]:
	var keys := by_slot.keys()
	keys.sort()
	var out: Array[ChordBrick] = []
	for k in keys:
		out.append(by_slot[k])
	return out


## How many bars `row` lasts.
static func bars_in(row: Array) -> int:
	var total := 0
	for b: ChordBrick in row:
		total += b.bars
	return total


## The row's chords, "Am F C G" (a brick's held bars not said).
static func chords_text(row: Array) -> String:
	return " ".join(PackedStringArray(row.map(func(b: ChordBrick) -> String: return b.chord)))


## The row as a bracket's inside, the wheel's SET has it: the first brick's key, then a chord a bar,
## `-` holding it: "C major: Am - F C". "" for no bricks.
static func inside_of(row: Array) -> String:
	if row.is_empty():
		return ""
	var words := PackedStringArray()
	for b: ChordBrick in row:
		words.append(b.chord)
		for _i in b.bars - 1:
			words.append("-")
	return "%s: %s" % [(row[0] as ChordBrick).key, " ".join(words)]


## The bar (MixState.bar_at's count, 0 the first) that `seconds` is in.
static func bar_of(state: MixState, seconds: float) -> int:
	return maxi(floori(state.bar_at(maxf(seconds, 0.0)) + Harmony.BAR_SLACK), 0)


## What a press of `row` into the section starting at `start` writes, as the wheel's SET asks it:
## [the section's bar, the bracket's inside] (FifthsWheel.write, or a guest's `harmony` ask).
static func section_ask(row: Array, state: MixState, start: float) -> Array:
	return [bar_of(state, start), inside_of(row)]


## The row's block chords from the start of bar `first`: each brick's chord voiced at CENTRE,
## VOICES notes, held for its bars, one after another. [on, off, pitch, velocity, channel] each, in
## seconds, as DAW.insert_midi_take takes them.
static func notes_of(row: Array, state: MixState, first: int) -> Array:
	var out: Array = []
	var bar := first
	for b: ChordBrick in row:
		var h := Harmony.parse("[%s: %s]" % [b.key, b.chord])
		var on := state.bar_to_seconds(bar + 1.0)
		var off := state.bar_to_seconds(bar + 1.0 + b.bars)
		if h != null:
			for pitch in Harmony.voiced(h, CENTRE, VOICES):
				out.append([on, off, pitch, VELOCITY, 0])
		bar += b.bars
	return out


## Where the row's take starts and ends from bar `first`, in seconds.
static func span_of(row: Array, state: MixState, first: int) -> Array:
	return [state.bar_to_seconds(first + 1.0), state.bar_to_seconds(first + 1.0 + bars_in(row))]


## Why chords cannot be written onto `track` here, in words for the presser, or "": a DAW that
## takes no MIDI, no such track, a frozen one, or one whose input is a microphone.
static func write_refusal(state: MixState, track: int) -> String:
	if DAW.backend == null or not DAW.backend.can(DAWBackend.Capability.MIDI_TAKES):
		return "This DAW cannot take MIDI yet: in Reaper, load the dawlings bridge script."
	if state == null or not state.tracks.has(track):
		return "There is no track %d to write the chords onto." % track
	var t := state.track(track)
	if t.is_frozen():
		return "%s is frozen: thaw it to write chords onto it." % t.display_name()
	if state.input_of(track).begins_with("audio:"):
		return "%s takes no MIDI: its input is %s. Press the bricks where the keys go." % [t.display_name(),
				state.input_name(state.input_of(track))]
	return ""


# --- the item ----------------------------------------------------------------------------------

func item_title() -> String:
	return "CHORD BRICK  %s" % chord if not chord.is_empty() else "CHORD BRICK"


## The id, not the chord: two Am bricks are two things to hold.
func network_key() -> String:
	return "BRICK %s" % String(id).trim_prefix(String(KIND))


func readout() -> String:
	if chord.is_empty():
		return super()
	var n := numeral()
	var what := "%s of %s" % [n, key] if not n.is_empty() else "out of %s" % key
	var where := super()
	if slot_in == LEDGE:
		var row := ledge_row(ItemRoom.of(self))
		where = "on the ledge, %d of %d: %s" % [row.find(self) + 1, row.size(), chords_text(row)]
	elif state == State.HOME:
		where = "on the ledge's tray"
	return "%s · %d bar%s · %s" % [what, bars, "" if bars == 1 else "s", where]


## A chord on it presses into a track or a section (slice 31). A blank one (a ghost's look-alike)
## has nothing to write.
func pastes() -> bool:
	return not chord.is_empty()


## What a press at `spot` ([track, seconds], or [SECTION, a section's start]) writes, for the card:
## "writes Am F C G (4 bars) onto Bass from bar 12"; "sets Verse 2's harmony to [C major: Am F]".
func paste_text(spot: Array) -> String:
	var s := DAW.state
	if s == null or spot.size() != 2:
		return ""
	var row := row_of(self)
	var said := "%s (%d bar%s)" % [chords_text(row), bars_in(row), "" if bars_in(row) == 1 else "s"]
	if row.size() > 1:
		said = "the ledge's " + said
	if int(spot[0]) == SECTION:
		var r := s.region_at(float(spot[1]) + 0.001)
		var section := str(s.regions[r][2]) if r >= 0 else "that section"
		return "sets %s's harmony to [%s]" % [section, inside_of(row)]
	var t := s.track(int(spot[0]), false)
	return "writes %s onto %s from bar %d" % [said, t.display_name() if t != null else "track %d" % spot[0],
			bar_of(s, float(spot[1])) + 1]


func hint() -> String:
	if state == State.HELD and carried_by != null and not is_nan(carried_by.twist()):
		return "turn it in your hand for 1, 2 or 4 bars · press it into a lane, a strip or a stage voice to write its chords there · into a section block for that section's harmony · from the ledge, its whole row · aimed back at its slot, it goes back in its place"
	if state == State.HELD and carried_by != null:
		return "click a timeline lane, a strip or a stage voice to write its chords there · click a section block for that section's harmony · from the ledge, its whole row · click the ledge to stand it there · Q puts it down"
	return _hint("click to pick up · wheel for 1, 2 or 4 bars · drag a strip tile off the fifths wheel for another")


## Its length a step longer (`notches` above 0) or shorter, through LENGTHS: the room's row, said
## (`resized`), never its data.
func _on_nudge(notches: int, _fine: bool) -> bool:
	if chord.is_empty() or is_held_elsewhere():
		return false
	var at := LENGTHS.find(bars)
	var to := clampi(at + signi(notches), 0, LENGTHS.size() - 1)
	if to != at:
		bars = LENGTHS[to]
		resized.emit(bars)
	return true


## One frame of the hand that holds it: turned TURN_STEP on from where the last notch was counted,
## it is a notch longer (clockwise) or shorter, by the same nudge as the wheel's and the stick's, so
## the room's row is told the same way. Turned on past 1 or 4 bars is not counted, as a key at its
## stop, so the first sixth back is a notch. Nothing in a hand that cannot turn (a mouse's), nor in
## somebody else's, nor out of the hand.
func follow_turn() -> void:
	var hand := carried_by if in_hand() and is_instance_valid(carried_by) and carried_by.carrying == self else null
	var turned := hand.twist() if hand != null else NAN
	if is_nan(turned):
		_turn_from = NAN
		return
	if is_nan(_turn_from):
		_turn_from = turned
		return
	while not chord.is_empty():
		if turned == _turn_from:
			return
		var notch := 1 if turned > _turn_from else -1
		var at := LENGTHS.find(bars)
		if (notch > 0 and at == LENGTHS.size() - 1) or (notch < 0 and at <= 0):
			_turn_from = turned
			return
		if absf(turned - _turn_from) < TURN_STEP:
			return
		_turn_from += TURN_STEP * notch
		_on_nudge(notch, false)


func _physics_process(delta: float) -> void:
	super(delta)
	follow_turn()


## Into a hand: which ledge slot it came from, if any, so a press writes that row.
func take_into(hand: Interactor) -> void:
	from_ledge = slot_n if slot_in == LEDGE else -1
	_turn_from = NAN
	super(hand)


## Out of the hand, anywhere: alone again, until it is taken from the ledge.
func on_put_down() -> void:
	from_ledge = -1


## Upright in the palm, a lettered face toward you.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.012, 0))


func centre_height() -> float:
	return SIZE.y * 0.5


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = SIZE + Vector3(0.012, 0.016, 0.012)
	return s


func _ready() -> void:
	super()
	# The grip round the brick, not round its bottom.
	_shape.position = Vector3(0, SIZE.y * 0.5, 0)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var paint: Material = null
	# Its own copies: the rim a holder's colour puts round it is per brick (Item.set_rim).
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null:
				var own := m.duplicate()
				mesh.set_surface_override_material(s, own)
				paint = own
	var stud := CylinderMesh.new()
	stud.top_radius = STUD_RADIUS
	stud.bottom_radius = STUD_RADIUS
	stud.height = STUD_TALL
	stud.radial_segments = 16
	for n in 4:
		var s := MeshInstance3D.new()
		s.name = "Stud%d" % (n + 1)
		s.mesh = stud
		s.material_override = paint
		root.add_child(s)
		_studs.append(s)
	# Both long faces lettered: whichever way round it stands or is held, it says what it is.
	for side in [-1.0, 1.0]:
		var face := SIZE.z * 0.5 + 0.0007
		var big := _label(70, Vector3(0, 0.0235, side * face), side)
		var small := _label(34, Vector3(0, 0.0085, side * face), side)
		root.add_child(big)
		root.add_child(small)
		_letters.append(big)
		_letters.append(small)
	_stud()
	return root


static func _label(size: int, at: Vector3, side: float) -> Label3D:
	var label := Label3D.new()
	label.pixel_size = 0.00028
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.font_size = size
	label.modulate = INK
	label.position = at
	# A Label3D faces +Z: the -Z face's is turned round to face out of it.
	label.rotation.y = PI if side < 0.0 else 0.0
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(label)
	return label


## A stud on its top for each bar.
func _stud() -> void:
	var at: Array = STUDS.get(bars, STUDS[1])
	for n in _studs.size():
		_studs[n].visible = n < at.size()
		if n < at.size():
			_studs[n].position = Vector3(at[n].x, SIZE.y + STUD_TALL * 0.5, at[n].y)


func _letter() -> void:
	for i in _letters.size():
		var label := _letters[i]
		label.text = chord if i % 2 == 0 else under_text()
		Lettering.fit(label, SIZE.x - 0.008, 70 if i % 2 == 0 else 34, 16)
		# Drawn as far as it can be read at the size it fits at, ink on the painted wood.
		Lettering.range_to_legibility(label)
		label.modulate = INK
		label.outline_modulate = HALO
		label.outline_size = maxi(4, roundi(label.font_size * 0.14))


## Clacks like the wood it is.
func _foley_contact() -> AudioStream:
	return Foley.chip_clack(0)


## A wooden block: a short hop and it stops.
func flies() -> Dictionary:
	return {"bounce": 0.3, "roll": 5.0, "drag": 0.1}
