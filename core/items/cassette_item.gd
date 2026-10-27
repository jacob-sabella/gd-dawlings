class_name CassetteItem
extends Item

## A clip out of the arrangement, as a thing in your hand (docs/spatial_loop.md part two, slice 23,
## idea #4): a cassette, lettered on both faces with the clip's name, its track and its length.
##
## Pulled out of the 3D timeline (TimelineLanes' PULL), it is a copy: the arrangement keeps the
## clip. What it carries is the clip packed whole (`clip`, MixWire.pack_item: a MIDI item's notes
## and controls, an audio item's source with its offset, fades, gain and loop, a demo item's part
## and window) and where it came from (`from_track`, `from_index`, `track_name`), all of it in
## `data`, which is the made item's row in `Session.made` and travels once (ItemRoom.mint). It is
## carried, pocketed, thrown, caught, handed over and shelved in the cassette rack like any item;
## the BIN at the rack's foot retires it. Pressed onto a track (`pastes`, slice 24) it pastes its
## clip there, and stays in the hand: a clipboard pastes again. Held to the ear (slice 25, EarCue) it
## plays its clip to this player alone, and its tag (`hearing`) says when it cannot. Its id is the
## room's, `cassette1`, `cassette2`, ..., so `ItemRoom.kind_of` answers `cassette` and `look_of` gives
## a blank one for a ghost's glove.
##
## A sample cassette (slice 26, Sampler) is one the sampler made of one sound: its clip is an audio
## clip of the WAV it wrote, from the SAMPLER (track -1), and `data` says which of Foley's sounds it
## is (`sample`, `is_sample`). It is lettered with its length in seconds rather than bars.

const KIND := &"cassette"
const MODEL := "res://assets/models/cassette.glb"
## The real thing's size (tools/blender/cassette.py), standing on its long edge.
const SIZE := Vector3(0.100, 0.064, 0.012)
## The label's lettering: where its two lines sit on the face, how wide it runs, and its ink.
const NAME_Y := 0.051
const FROM_Y := 0.026
const LETTER_WIDTH := 0.080
const INK := Color(0.08, 0.07, 0.09)

## The clip, packed (MixWire.pack_item); empty on a blank one (a ghost's look-alike).
var clip: Dictionary = {}
## Where it was pulled from: the track's index and its item's, and the track's name then.
var from_track := 0
var from_index := -1
var track_name := ""
## Everything it carries, as minted: what `read` was given.
var data: Dictionary = {}
## What holding it to the ear is doing (EarCue.TAGS: "AT YOUR EAR", "FETCHING", "not on this
## machine", ...), lettered in place of where it came from; "" for nothing.
var hearing := "":
	set(v):
		if v == hearing:
			return
		hearing = v
		_letter()
var _letters: Array[Label3D] = []


func _init() -> void:
	id = KIND
	super()


## What a cassette made of `track`'s item `index` in `state` carries: the clip packed, its part
## its track's where it has none of its own, and where it came from. Empty where there is no
## such item.
static func data_of(state: MixState, track: int, index: int) -> Dictionary:
	if state == null or not state.tracks.has(track):
		return {}
	var item := state.item(track, index)
	if item == null:
		return {}
	var t := state.track(track)
	return {"clip": MixWire.pack_item(item, t.part), "track": track, "index": index, "track_name": t.name}


## The made item's row read back (`data`, from the host or a file): what it carries, lettered.
func read(made: Dictionary) -> void:
	data = made
	var c: Variant = made.get("clip", {})
	clip = c if c is Dictionary else {}
	from_track = int(made.get("track", 0))
	from_index = int(made.get("index", -1))
	track_name = str(made.get("track_name", "")).substr(0, 32)
	_letter()


## The clip's name, or what to call it when it has none.
func clip_name() -> String:
	var n := str(clip.get("name", "")).strip_edges()
	return n if not n.is_empty() else "untitled clip"


func length() -> float:
	return float(clip.get("length", 0.0))


## "4.0 bars, 8.0 s" at the song's tempo here.
func length_text() -> String:
	var bar := DAW.state.bar_to_seconds(2.0) if DAW.state != null else 2.0
	return "%.1f bars, %.1f s" % [length() / maxf(bar, 0.0001), length()]


## Whether the sampler made it (slice 26): one sound, not a clip of the song.
func is_sample() -> bool:
	return data.has("sample")


## "KICK, 4.0 bars": what is lettered under the name; "SAMPLE · 0.26 s" for a sample.
func from_text() -> String:
	if is_sample():
		return "SAMPLE · %.2f s" % length()
	var t := track_name.to_upper() if not track_name.is_empty() else "TRACK %d" % from_track
	return "%s · %.1f bars" % [t, length() / maxf(DAW.state.bar_to_seconds(2.0) if DAW.state != null else 2.0, 0.0001)]


func item_title() -> String:
	return "CASSETTE  %s" % clip_name() if not clip.is_empty() else "CASSETTE"


## The id, not the title: two cassettes of clips with one name are two things to hold.
func network_key() -> String:
	return "CASSETTE %s" % String(id).trim_prefix(String(KIND))


func readout() -> String:
	if clip.is_empty():
		return super()
	var what := "MIDI" if clip.has("notes") else ("audio" if clip.has("source") else
			("the demo's %s" % clip.get("part", "") if clip.has("part") else "empty"))
	var where := super()
	if slot_in == &"rack":
		where = "on the rack, slot %d" % (slot_n + 1)
	if is_sample():
		var heard := "a sample, %s, %.2f s, %s" % [str(clip.get("source", "")), length(), where]
		return heard if hearing.is_empty() else "%s · %s" % [heard, hearing]
	var said := "%s, from %s: %s, %s" % [what, track_name if not track_name.is_empty() else "track %d" % from_track,
			length_text(), where]
	return said if hearing.is_empty() else "%s · %s" % [said, hearing]


## A clip on it pastes (docs/spatial_loop.md part two, slice 24): pressed onto a timeline lane, a
## console strip or a stage voice, it is a copy of its clip there, and stays in the hand to paste
## again. A blank one (a ghost's look-alike) has nothing to paste.
func pastes() -> bool:
	return not clip.is_empty()


func hint() -> String:
	if state == State.HELD and carried_by != null:
		return "hold L to hear it · click a timeline lane, a channel strip or a stage voice to paste it there · click a bandmate to hand it over · click a rack slot to shelve it, or the BIN to bin it · Q puts it down"
	return _hint("click to pick up · pull a clip off the timeline for another")


## On its edge in the palm, its label toward you.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.01, 0))


func centre_height() -> float:
	return SIZE.y * 0.5


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(SIZE.x + 0.01, SIZE.y + 0.012, 0.03)
	return s


func _ready() -> void:
	super()
	# The grip round the cassette, not round its bottom edge.
	_shape.position = Vector3(0, SIZE.y * 0.5, 0)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	# Its own copies: the rim a holder's colour puts round it is per cassette (Item.set_rim).
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null:
				mesh.set_surface_override_material(s, m.duplicate())
	# Both faces lettered: whichever way round it is held or racked, it says what it is.
	for side in [-1.0, 1.0]:
		var face := SIZE.z * 0.5 + 0.0007
		var title := _label(46, Vector3(0, NAME_Y, side * face), side)
		var under := _label(30, Vector3(0, FROM_Y, side * face), side)
		root.add_child(title)
		root.add_child(under)
		_letters.append(title)
		_letters.append(under)
	return root


static func _label(size: int, at: Vector3, side: float) -> Label3D:
	var label := Label3D.new()
	# A label's lettering: the name about 9 mm tall, as a pen writes on one.
	label.pixel_size = 0.0002
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


func _letter() -> void:
	for i in _letters.size():
		var label := _letters[i]
		label.text = clip_name() if i % 2 == 0 else (from_text() if hearing.is_empty() else hearing)
		Lettering.fit(label, LETTER_WIDTH, 46 if i % 2 == 0 else 30, 16)
		label.outline_size = 0


## Clacks like the plastic it is.
func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()


## A flat plastic thing: it skids and stops.
func flies() -> Dictionary:
	return {"bounce": 0.25, "roll": 6.0, "drag": 0.1}
