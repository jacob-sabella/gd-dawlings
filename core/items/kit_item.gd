class_name KitItem
extends InstrumentItem

## Drum pads on anything (docs/spatial_loop.md part two, slice 41, idea #10): the room's one shared
## kit, a fixed kind (ItemRoom.KINDS, `Item.fixed`) whose pads are six on the desk's front rail and
## whatever this player has marked on real surfaces (SurfacePads, this machine's own).
##
## Six pads stand in a row along its X on the console's armrest (ConsoleSurface.pad_rail, where the
## studio stands it), lettered left to right KICK, SNARE, HAT, CLAP, TOM and RIM, with the key that
## strikes each at a desk under its name, 4 to 9. Each is a 6 cm disk, PAD_RADIUS across its middle.
## A marked pad is the same disk on a real surface, its drum its own (SurfacePads.drum_of).
##
## Every pad is one of its `faces`, so Strike reads a fingertip or a controller's tip crossing any of
## them, and where it crosses is which pad (`zone_at`: the nearest face), so its `zone` is that pad's
## drum. A click on the rail strikes the pad it lands on (`struck_by`), 96, Shift 64; a click or a
## trigger aimed at a marked pad strikes that one (SurfacePads.Pad, `strike_marked`). Struck here,
## a hit is heard at once on the fast path or MONITOR, goes to the room as `item_hit` on `kit` with
## the drum as its zone, and is recorded as the drum's General MIDI note on the drums' channel
## (NOTES), so a take plays back as drums (ItemVoices, slice 16).
##
## Because a bandmate's marked pads are on their own surfaces, nowhere in this room, a bandmate's hit
## on the kit is heard from their ghost (`heard_at`, Presence), not from the desk.
##
## Unplugged, its jack goes to the drum track (`default_sink`, `drum_track`): a track named DRUMS, or
## failing that the first whose part is a drum's (DemoSong.role_of: kick, snare, hat, overheads),
## else wherever an unplugged instrument goes, the armed track. So a tap on the desk plays the drum
## track. Plugged, it goes where it is plugged, as every jack does (Jacks).
##
## Under the row, on the armrest's front edge, hangs the PADS card (SurfacePads.build_card): its MARK
## key puts this player's hands to marking pads on real surfaces, CLEAR, pressed twice, takes them
## all away.

const KIND := &"kit"
## The drums, in the rail's order, left to right, and the order a new marked pad takes them in.
const DRUMS: Array[StringName] = [&"kick", &"snare", &"hat", &"clap", &"tom", &"rim"]
const TITLES := {&"kick": "KICK", &"snare": "SNARE", &"hat": "HAT", &"clap": "CLAP", &"tom": "TOM", &"rim": "RIM"}
## The General MIDI note each drum is recorded as: the bass drum, the snare, the closed hat, the hand
## clap, the low-mid tom (ItemVoices' drum pad at its own pitch) and the side stick.
const NOTES := {&"kick": 36, &"snare": 38, &"hat": 42, &"clap": 39, &"tom": 47, &"rim": 37}
## Foley's sound each rings (each on the hits' helper already: Foley.SOUNDS).
const SOUNDS := {&"kick": &"kick", &"snare": &"snare", &"hat": &"hihat", &"clap": &"clap", &"tom": &"pad", &"rim": &"rim"}
## The keys that strike the rail's pads at a desk, in order (Studio).
const KEYS := ["4", "5", "6", "7", "8", "9"]
## A pad's disk: its radius, how thick it stands off what it is on, and the rail's spacing. Six at
## PAD_PITCH fit the armrest of the smallest desk there is (four strips and the master).
const PAD_RADIUS := 0.03
const PAD_THICK := 0.004
const PAD_PITCH := 0.064
## The track names that are the drum track, as a name is shown upper-cased (DRUMS, DRUM KIT).
const DRUM_NAMES := ["DRUMS", "DRUM"]
## The demo parts that are drums (DemoSong.ROLES), for a session with no track named for them.
const DRUM_PARTS := ["kick", "snare", "hat", "overheads"]
## Where the PADS card hangs, in its frame: off the armrest's front edge under the row's middle.
const CARD_AT := Vector3(0, -0.004, 0.038)
const RUBBER := Color(0.06, 0.06, 0.065)
const RIM := Color(0.42, 0.42, 0.44)
const INK := Color(0.93, 0.9, 0.82)

## This machine's marked pads, whose faces are the kit's too: the studio's, or none (a test's kit,
## the desk with no headset, where nothing is marked).
var surface: SurfacePads = null
## The marked pad the last `zone_at` landed nearest, or -1 for a rail pad: so a strike there while
## marking steps that pad's drum (SurfacePads.marking).
var _marked_hit := -1


func _init() -> void:
	id = KIND
	fixed = true
	own_home = true
	super()
	# The grip over the row, its middle at the pads' faces.
	_shape.position = Vector3(0, PAD_THICK, 0)


func item_title() -> String:
	return "DRUM PADS"


## Where rail pad `n` (0 to 5, left to right) is in its own frame: the middle of its face.
static func rail_point(n: int) -> Vector3:
	return Vector3((float(n) - 2.5) * PAD_PITCH, PAD_THICK, 0.0)


## The drum the rail's pad `n` is.
static func rail_drum(n: int) -> StringName:
	return DRUMS[clampi(n, 0, DRUMS.size() - 1)]


func pitch() -> int:
	return NOTES[&"snare"]


func sound_kind(_struck: bool) -> StringName:
	return SOUNDS[&"snare"]


## The six on the rail, facing up out of the armrest, then each marked pad of this machine's
## (SurfacePads.faces), its face along the surface it is on. Each says its `drum`; a marked one its
## `marked` index too.
func faces() -> Array:
	var out: Array = []
	for n in DRUMS.size():
		out.append({"frame": global_transform * Transform3D(Basis.IDENTITY, rail_point(n)),
				"radius": PAD_RADIUS, "drum": DRUMS[n]})
	if surface != null and is_instance_valid(surface) and surface.is_inside_tree():
		out.append_array(surface.faces())
	return out


## Which pad a strike or a click at `point` (global) lands on: the nearest one's drum, by the
## distance to its middle. A strike crosses a pad, so it is nearest to the one it crossed.
func zone_at(point: Vector3) -> StringName:
	var best := INF
	var drum := &""
	_marked_hit = -1
	for face: Dictionary in faces():
		var d := point.distance_to((face["frame"] as Transform3D).origin)
		if d < best:
			best = d
			drum = face["drum"]
			_marked_hit = int(face.get("marked", -1))
	return drum


func zone_words() -> String:
	return "KICK · SNARE · HAT · CLAP · TOM · RIM, 4 to 9 · onto %s" % \
			(Jacks.sink_name(default_sink()) if default_sink() != &"" else "the armed track")


func zone_kind(zone: StringName) -> StringName:
	return SOUNDS.get(zone, &"")


func zone_note(zone: StringName, seconds: float) -> int:
	return NOTES.get(zone, note_at(seconds))


func has_zone(zone: StringName) -> bool:
	return zone == &"" or zone in DRUMS


func centre_height() -> float:
	return PAD_THICK


## A strike on it: on a marked pad while this player marks (SurfacePads.marking), that pad steps on to
## its next drum first and rings as it, so a hand laying pads out hears each one as it sets it; and
## the hand that tapped it may rest there after without its dwell taking the pad away
## (SurfacePads.tapped).
func strike(velocity: int, zone: StringName, side := 0) -> void:
	var marked := _marked_hit
	_marked_hit = -1
	if marked >= 0 and surface != null and is_instance_valid(surface) and surface.marking:
		zone = surface.step_drum(marked, 1)
		surface.tapped(marked)
	super(velocity, zone, side)


## Marked pad `n` struck by a click, or a trigger or pinch aimed at it (SurfacePads.Pad): `velocity`,
## by the hand on `side`.
func strike_marked(n: int, velocity: int, side := 0) -> void:
	if surface == null or n < 0 or n >= surface.pads.size():
		return
	_marked_hit = n
	strike(velocity, surface.drum_of(n), side)


## The rail's pad `n` struck from the keyboard (4 to 9): a click's velocity, from neither hand.
func strike_rail(n: int, velocity := Strike.CLICK) -> void:
	if n < 0 or n >= DRUMS.size():
		return
	_marked_hit = -1
	strike(velocity, DRUMS[n], 0)


## Unplugged, the drum track (`drum_track`); none where there is no such track.
func default_sink() -> StringName:
	var track := drum_track()
	return Jack.track_sink(track) if track > 0 else &""


## The drum track: the first track named DRUMS (or DRUM), or failing that the first whose part is a
## drum's (DemoSong.role_of), and that takes a take (Jacks.takes_midi); 0 for none.
static func drum_track() -> int:
	if DAW.state == null:
		return 0
	var indices: Array = DAW.state.tracks.keys()
	indices.sort()
	for index: int in indices:
		var t: MixState.TrackState = DAW.state.tracks[index]
		if t != null and t.display_name().strip_edges().to_upper() in DRUM_NAMES and Jacks.takes_midi(index):
			return index
	for index: int in indices:
		var t: MixState.TrackState = DAW.state.tracks[index]
		if t != null and DemoSong.role_of(t.display_name()) in DRUM_PARTS and Jacks.takes_midi(index):
			return index
	return 0


func hint() -> String:
	if hands_hint:
		return "tap a pad with a fingertip or a controller's tip · MARK on the card under them puts pads on real surfaces"
	return "click a pad to strike it, Shift-click softly · 4 to 9 strike them from anywhere"


## Its jack at the row's left end, on the armrest, facing out along it: seen from the seat, out of
## the pads' way, and clear of the grip over them.
func jack_point() -> Vector3:
	return Vector3(rail_point(0).x - PAD_RADIUS - 0.012 - JackSocket.REACH * 0.6, 0.008, 0.0)


## A bandmate's hit, heard from `at` (global: a glove of their ghost, Presence) rather than from the
## desk, since the pad they struck may be on their own knee. Otherwise as `heard`.
func heard_at(at: Vector3, velocity: int, song := -1.0, take := -1, snap := false, zone := &"") -> void:
	if not is_inside_tree():
		heard(velocity, true, song, take, snap, zone)
		return
	var spot := Node3D.new()
	spot.name = "HeardAt"
	add_child(spot)
	spot.global_position = at
	_ring_on_node = spot
	heard(velocity, true, song, take, snap, zone)
	_ring_on_node = null
	var players := spot.get_children()
	if players.is_empty():
		spot.queue_free()
	else:
		(players[-1] as AudioStreamPlayer3D).finished.connect(spot.queue_free)


var _ring_on_node: Node3D = null


func ring_on() -> Node3D:
	return _ring_on_node if _ring_on_node != null and is_instance_valid(_ring_on_node) else self


func _grip_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(PAD_PITCH * DRUMS.size(), 0.02, PAD_RADIUS * 2.0 + 0.006)
	return box


func _build_body() -> Node3D:
	var root := Node3D.new()
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = RUBBER
	rubber.roughness = 0.95
	var rim := StandardMaterial3D.new()
	rim.albedo_color = RIM
	rim.roughness = 0.5
	rim.metallic = 0.6
	for n in DRUMS.size():
		var at := rail_point(n)
		# Each pad's rim a little wider than it, a millimetre short of the next one's, and the pad's
		# foot a millimetre up inside it: no two of their faces on one plane.
		var ring := MeshInstance3D.new()
		ring.name = "Bezel%d" % n
		var bezel := CylinderMesh.new()
		bezel.top_radius = PAD_PITCH * 0.5 - 0.0005
		bezel.bottom_radius = PAD_PITCH * 0.5 - 0.0005
		bezel.height = PAD_THICK * 0.6
		bezel.radial_segments = 32
		ring.mesh = bezel
		ring.position = Vector3(at.x, PAD_THICK * 0.3, 0)
		ring.material_override = rim
		root.add_child(ring)
		var disk := MeshInstance3D.new()
		disk.name = "Pad%d" % n
		var mesh := CylinderMesh.new()
		mesh.top_radius = PAD_RADIUS
		mesh.bottom_radius = PAD_RADIUS
		mesh.height = PAD_THICK - 0.001
		mesh.radial_segments = 32
		disk.mesh = mesh
		disk.position = Vector3(at.x, PAD_THICK * 0.5 + 0.0005, 0)
		disk.material_override = rubber
		root.add_child(disk)
		root.add_child(pad_lettering(TITLES[DRUMS[n]], KEYS[n], Vector3(at.x, PAD_THICK + 0.0006, 0)))
	return root


## A pad's letters lying on it, its drum and under it a smaller line (its key, or its number), read
## from the player's side (+Z), at `at` in the pad's frame.
static func pad_lettering(drum: String, under: String, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Letters"
	holder.position = at
	holder.rotation = Vector3(-PI * 0.5, 0, 0)
	var word := Label3D.new()
	word.name = "Drum"
	word.text = drum
	word.pixel_size = 0.0001
	word.font_size = 120
	word.outline_size = 0
	word.modulate = INK
	word.double_sided = false
	word.shaded = false
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.position = Vector3(0, 0.0045, 0)
	Lettering.range_to_legibility(word)
	holder.add_child(word)
	var key := Label3D.new()
	key.name = "Key"
	key.text = under
	key.pixel_size = 0.0001
	key.font_size = 90
	key.outline_size = 0
	key.modulate = INK.darkened(0.25)
	key.double_sided = false
	key.shaded = false
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.position = Vector3(0, -0.01, 0)
	Lettering.range_to_legibility(key)
	holder.add_child(key)
	return holder
