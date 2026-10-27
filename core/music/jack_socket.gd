class_name JackSocket
extends ControlAffordance

## The output jack on an instrument (docs/spatial_loop.md, slice 5): a small socket at its
## `InstrumentItem.jack_point()`, facing out along its `jack_out()`, that says where what it plays
## goes (`Jacks`).
##
## A press steps it on through unplugged and then each track that takes MIDI, round again, so
## every hand gets back to unplugged by pressing; the wheel and the thumbstick (`nudge`) step it
## either way. Any hand presses it: a finger, a ray, a controller, a cursor, and a dwell. The hand
## that carries the instrument does not reach its own socket (Interactor._cast leaves it out of
## that hand's ray), so its trigger or click still strikes the instrument: the other hand, or on
## a desktop P and Shift+P (MouseInteractor), steps it while it is carried. On the shelf anyone
## may press it.
##
## Plugged, it says so twice, neither of them by colour: a tag over it in words (`-> 3 BASS`),
## and a short lead out of it ending in a plug. Only a short one into a track: a cable across the
## room to the patchbay would say it was a send, and it is not one. Into a bandmate (slice 6) the
## cable is real and long: slack, from this socket to the nearer glove of their ghost
## (`Jacks.far_end`), rebuilt at most CABLE_HZ while either end moves. Where they have no ghost to
## hold it, the short lead hangs instead.
##
## Its look is under the instrument's body (`_look`), so it is drawn, hidden and kept out of the
## mirror with the body; the socket itself is beside the body, as the grip is, so the body's
## squash never scales its shape.
##
## A socket on no instrument (`JackSocket.new(null, source)`) is the same plug for a source that is
## not an item: the chord harp's, on its pillar (`Jack.HARP`), and a player's own keys', on their
## wrist (`mine_keys`: `keys:P` for whoever this player is now). Its look is its own, facing out
## along its -Z, and it is there to press while it is drawn and `available` says so.
##
## Beside a player's own keys' socket on the wrist they wear one more (`into_me`): not a source's
## but theirs as a sink, for a headset's hand to do what Shift+P with an empty hand does on a
## desktop. It is there only while something goes into them, its tag says what (`<- GRACE'S KEYS,
## SHAKER`), and a press takes all of it out (Jacks.unplug_mine). It is how a bandmate's keys,
## whose own socket is on the bandmate's wrist and not here, come out of this player.

const SOCKETS := &"jack_sockets"
## How far round its middle a ray finds it (m): bigger than the nut, as a grip is bigger than its
## item, and standing clear of the instrument's own grip so a ray at it reaches it first.
const REACH := 0.026
## The nut on the instrument: its radius and how far it stands out of the body.
const NUT_RADIUS := 0.0085
const NUT_DEPTH := 0.007
## The lead, plugged: how far it hangs below the jack, and its jacket.
const LEAD_DROP := 0.11
const LEAD_RADIUS := 0.0024
const LEAD_COLOUR := Color(0.13, 0.13, 0.14)
## The tag's lettering, over the jack.
const TAG_SIZE := 30
const TAG_PIXEL := 0.0006
const TAG_LIFT := 0.07
## How often the tag's words are read again (s): a track renamed shows within this.
const RELETTER := 0.5
## The cable into a bandmate: its jacket's radius, the most often it is rebuilt (Hz), and how far
## an end has to move before it is.
const CABLE_RADIUS := 0.003
const CABLE_HZ := 15.0
const CABLE_MOVED := 0.005

## The instrument it is on, or null for a socket on no instrument.
var item: InstrumentItem
## The source it plugs, on no instrument: `harp`. An item's is its id (`source_id`).
var source := &""
## A socket for this player's own keys (`keys:P`, P whoever this player is now), on their wrist.
var mine_keys := false
## The socket for what goes into this player, on their wrist: a press unplugs all of it.
var into_me := false
## What goes into this player, as last shown, on an `into_me` socket.
var ins: Array[StringName] = []
## What its card calls it, on no instrument: `CHORD HARP`, `MY KEYS`.
var label := ""
## () -> bool: whether it is there to press, on no instrument (a wrist's, while that hand is
## tracked). Unset, while it is drawn.
var available: Callable = Callable()
## Where it goes now, as last shown: a sink, or empty for unplugged.
var sink := &""
var _shape: CollisionShape3D
var _look: Node3D
var _tag: Label3D
var _lead: Node3D
var _metal: StandardMaterial3D
var _jacket: StandardMaterial3D
var _reletter_in := 0.0
## The cable into a bandmate (top level, in world space), the plug seated in the nut while it
## runs, the ends it was last built between, and how long until it may be built again.
var _cable: MeshInstance3D
var _boot: MeshInstance3D
var _cable_ends := [Vector3.INF, Vector3.INF]
var _cable_in := 0.0
## The lead's centre line in the lead's own space, and the cable's into a bandmate in world space:
## what the beads ride (SignalBeads).
var _lead_spine := PackedVector3Array()
var _cable_spine := PackedVector3Array()


func _init(on: InstrumentItem = null, named := &"") -> void:
	item = on
	source = named
	name = "Jack"
	collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
	collision_mask = 0
	_shape = CollisionShape3D.new()
	_shape.name = "Reach"
	var ball := SphereShape3D.new()
	ball.radius = REACH
	_shape.shape = ball
	add_child(_shape)


func _enter_tree() -> void:
	super()
	add_to_group(SOCKETS)
	if not into_me:
		add_to_group(SignalBeads.CARRIERS)


## What it plugs: the item's id, this player's keys, or the source it was made for.
func source_id() -> StringName:
	if item != null and is_instance_valid(item):
		return item.id
	if mine_keys:
		return Jack.keys_source(Session.local_peer_id)
	return source


func _ready() -> void:
	if item == null and source == &"" and not mine_keys and not into_me:
		return
	# Its own metal, not Materials' shared one: a held instrument's rim goes on every material in
	# its body (Item.set_rim), and a shared one would ring every plug on the patchbay too.
	_metal = Materials.plug_metal().duplicate() as StandardMaterial3D
	_jacket = StandardMaterial3D.new()
	_jacket.albedo_color = LEAD_COLOUR
	_jacket.roughness = 0.5
	_look = Node3D.new()
	_look.name = "JackLook"
	if item != null:
		position = item.jack_point()
		# Built facing -Z, turned to face out of the instrument.
		_look.transform = Transform3D(Basis.looking_at(item.jack_out(), Vector3.UP), item.jack_point())
		item.body.add_child(_look)
	else:
		add_child(_look)
	_look.add_child(_nut())
	_boot = _barrel(Vector3(0, 0, -NUT_DEPTH - 0.012), Basis(Vector3.RIGHT, PI * 0.5), 0.0042, 0.024, _jacket)
	_boot.visible = false
	_look.add_child(_boot)
	_cable = MeshInstance3D.new()
	_cable.name = "Cable"
	_cable.top_level = true
	_cable.material_override = _jacket
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cable.visible = false
	add_child(_cable)
	_lead = _build_lead()
	_lead.visible = false
	_look.add_child(_lead)
	_tag = Label3D.new()
	_tag.name = "JackTag"
	_tag.font_size = TAG_SIZE
	_tag.pixel_size = TAG_PIXEL
	_tag.outline_size = 8
	_tag.modulate = Color(0.97, 0.94, 0.86)
	_tag.outline_modulate = Color(0.05, 0.04, 0.03)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, TAG_LIFT, -NUT_DEPTH)
	_tag.visible = false
	Lettering.range_to_legibility(_tag)
	_look.add_child(_tag)
	# Made after the item may already be in a hand: drawn on the layer the body is on now.
	if item != null and item.body.get_child_count() > 0:
		var layers := _body_layers()
		for node in _look.find_children("*", "VisualInstance3D", true, false):
			(node as VisualInstance3D).layers = layers
	var jacks := Jacks.of(self)
	if into_me:
		show_ins(jacks.into(Session.local_peer_id) if jacks != null and Session.local_peer_id != 0 else [] as Array[StringName])
		return
	show_sink(jacks.sink_of(source_id()) if jacks != null else &"")


## Where it goes now, shown: the tag's words and the lead (or into a bandmate, the cable to
## them), or neither, unplugged.
func show_sink(to: StringName) -> void:
	sink = to
	if _tag == null:
		return
	var plugged := to != &""
	_tag.visible = plugged
	_lead.visible = plugged
	if plugged:
		_tag.text = tag_text(to)
	if Jack.player_of(to) == 0:
		_cable.visible = false
		_boot.visible = false
	# Built again at once, wherever the ends are.
	_cable_ends = [Vector3.INF, Vector3.INF]
	_cable_in = 0.0
	_follow_cable(0.0)


## On an `into_me` socket, what goes into this player, shown: the nut and a tag naming each of
## them while there is any, nothing while there is none.
func show_ins(sources: Array[StringName]) -> void:
	ins = sources.duplicate()
	if _look == null:
		return
	_look.visible = not ins.is_empty()
	_tag.visible = not ins.is_empty()
	_tag.text = ins_text(ins)


## What the tag over the socket for what goes into this player says: `<- GRACE'S KEYS, SHAKER`.
func ins_text(sources: Array[StringName]) -> String:
	var by_id := {}
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(Item.ITEMS):
			var thing := node as Item
			if thing != null and sources.has(thing.id):
				by_id[thing.id] = thing
	var names: Array[String] = []
	for source in sources:
		names.append(Jacks.source_name(source, by_id.get(source)).to_upper())
	return "<- %s" % ", ".join(names)


## What the tag over a jack plugged into `to` says: `-> 3 BASS`.
static func tag_text(to: StringName) -> String:
	return "-> %s" % Jacks.sink_name(to)


func _physics_process(delta: float) -> void:
	if _look == null:
		return
	if item != null:
		if not is_instance_valid(item):
			return
		# Nothing to reach for while the instrument is in a pocket, on a head, or not drawn.
		_shape.disabled = item.pocket >= 0 or item.on_head or not item.body.is_visible_in_tree()
	else:
		_shape.disabled = not is_visible_in_tree() or (available.is_valid() and not available.call()) \
				or (into_me and ins.is_empty())
	_reletter_in -= delta
	if _reletter_in <= 0.0 and sink != &"" and _tag != null:
		_reletter_in = RELETTER
		_tag.text = tag_text(sink)
	_follow_cable(delta)


## Into a bandmate: the cable from the plug in this socket to their ghost's nearer glove, built
## again when either end has moved, at most CABLE_HZ. Where they have no ghost here, the short
## lead hangs instead.
func _follow_cable(delta: float) -> void:
	var player := Jack.player_of(sink)
	if player == 0 or _cable == null:
		return
	_cable_in -= delta
	if _cable_in > 0.0:
		return
	var jacks := Jacks.of(self)
	var from := _look.global_transform * Vector3(0, 0, -NUT_DEPTH - 0.024)
	var far: Variant = jacks.far_end.call(player, from) if jacks != null and jacks.far_end.is_valid() else null
	var running := far is Vector3 and _look.is_visible_in_tree()
	_lead.visible = not running
	_boot.visible = running
	if not running:
		_cable.visible = false
		return
	var to: Vector3 = far
	if _cable.visible and from.distance_to(_cable_ends[0]) < CABLE_MOVED and to.distance_to(_cable_ends[1]) < CABLE_MOVED:
		return
	_cable_in = 1.0 / CABLE_HZ
	_cable_ends = [from, to]
	_cable.global_transform = Transform3D.IDENTITY
	_cable_spine = slack(from, (_look.global_basis * Vector3.FORWARD).normalized(), to)
	_cable.mesh = CableSweep.tube(_cable_spine, CABLE_RADIUS, 8)
	_cable.layers = _body_layers() if item != null else 1
	_cable.visible = _cable.mesh != null


## A slack cable's spine from `from`, leaving along `out`, to `to`, coming up into it from below:
## it sags under both ends by more the longer it is, and never through the floor.
static func slack(from: Vector3, out: Vector3, to: Vector3) -> PackedVector3Array:
	var span := from.distance_to(to)
	var middle := (from + to) * 0.5
	middle.y = maxf(minf(from.y, to.y) - 0.08 - span * 0.18, 0.03)
	return CableSweep.smooth(PackedVector3Array([from, from + out * 0.05, middle,
			to + Vector3.DOWN * 0.06, to]), 8)


# --- what its beads ride (SignalBeads) ----------------------------------------------------

## The cable into a bandmate while it runs, else the short lead while it hangs, in world space;
## nothing unplugged.
func signal_spine() -> PackedVector3Array:
	if sink == &"" or _look == null:
		return PackedVector3Array()
	if cable_running():
		return _cable_spine
	if _lead != null and _lead.is_visible_in_tree():
		return _lead.global_transform * _lead_spine
	return PackedVector3Array()


func signal_length() -> float:
	return SignalBeads.length_of(signal_spine())


## What it plays, as its last hit fades (Jacks.level_of): still when nothing is playing, and
## nothing unplugged.
func signal_level() -> float:
	if sink == &"":
		return 0.0
	var jacks := Jacks.of(self)
	return jacks.level_of(source_id()) if jacks != null else 0.0


func signal_radius() -> float:
	return CABLE_RADIUS if cable_running() else LEAD_RADIUS


## Whether the cable into a bandmate is running, and where its far end is.
func cable_running() -> bool:
	return _cable != null and _cable.visible


func cable_end() -> Vector3:
	return _cable_ends[1]


func _default_title() -> String:
	if item != null:
		return "%s  JACK" % item.item_title()
	return "%s  JACK" % label


func _default_readout() -> String:
	if into_me:
		return ins_text(ins) if not ins.is_empty() else "nothing goes into you"
	return tag_text(sink) if sink != &"" else "unplugged"


func hint() -> String:
	if into_me:
		return "press to unplug everything going into you" if not ins.is_empty() else ""
	var jacks := Jacks.of(self)
	if jacks == null or source_id() == &"":
		return ""
	if Session.local_peer_id != 0 and jacks.player_into(source_id()) == Session.local_peer_id:
		return "it goes into you: press to unplug it"
	var next := jacks.next_sink(source_id(), 1)
	return "press for %s; the wheel steps either way" % (Jacks.sink_name(next) if next != &"" else "unplugged")


## Cheap to get wrong and one press to put right: a dwell steps it too.
func dwell_activates() -> bool:
	return true


## Where it goes is the room's (the `plug` verb), not a hold: nobody is told this is held.
func personal() -> bool:
	return true


func _on_grab_begin(_at: Vector3) -> void:
	step(1)


func _on_nudge(notches: int, _fine: bool) -> bool:
	return step(signi(notches))


## On (`way` 1) or back (-1) one sink: said to the room's jacks. False with none to say it to.
func step(way: int) -> bool:
	var jacks := Jacks.of(self)
	if jacks == null or way == 0:
		return false
	if into_me:
		# Either way out: there is only the one thing it does.
		return jacks.unplug_mine() > 0
	if source_id() == &"":
		return false
	jacks.step_source(source_id(), way)
	return true


## The layer the item's body is drawn on now: its own view and the mirror, or its own view only
## while a hand here has it.
func _body_layers() -> int:
	for node in item.body.find_children("*", "VisualInstance3D", true, false):
		if not _look.is_ancestor_of(node):
			return (node as VisualInstance3D).layers
	return 1


## The nut it plugs into: a short metal ring standing out of the instrument (the look's -Z).
func _nut() -> MeshInstance3D:
	var nut := MeshInstance3D.new()
	nut.name = "Nut"
	var mesh := CylinderMesh.new()
	mesh.top_radius = NUT_RADIUS
	mesh.bottom_radius = NUT_RADIUS
	mesh.height = NUT_DEPTH
	mesh.radial_segments = 14
	nut.mesh = mesh
	nut.material_override = _metal
	nut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nut.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -NUT_DEPTH * 0.5))
	return nut


## The lead, plugged: a plug seated in the nut, a hand's width of cable out of it falling away,
## and a plug on its far end. Built once, shown while plugged.
func _build_lead() -> Node3D:
	var lead := Node3D.new()
	lead.name = "Lead"
	var jacket := _jacket
	var out := -NUT_DEPTH
	lead.add_child(_barrel(Vector3(0, 0, out - 0.012), Basis(Vector3.RIGHT, PI * 0.5), 0.0042, 0.024, jacket))
	var spine := CableSweep.smooth(PackedVector3Array([
			Vector3(0, 0, out - 0.024), Vector3(0, -0.006, out - 0.045),
			Vector3(0.008, -0.045, out - 0.062), Vector3(0.012, -LEAD_DROP + 0.02, out - 0.066)]), 6)
	_lead_spine = spine
	var tube := MeshInstance3D.new()
	tube.name = "Cable"
	tube.mesh = CableSweep.tube(spine, LEAD_RADIUS, 10)
	tube.material_override = jacket
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lead.add_child(tube)
	var end := spine[spine.size() - 1]
	lead.add_child(_barrel(end + Vector3(0, -0.008, 0), Basis.IDENTITY, 0.0042, 0.016, jacket))
	lead.add_child(_barrel(end + Vector3(0, -0.022, 0), Basis.IDENTITY, 0.0032, 0.012, _metal))
	return lead


## A short cylinder at `at`, standing along `turn`'s Y: a plug's boot or its sleeve.
func _barrel(at: Vector3, turn: Basis, radius: float, length: float, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	piece.mesh = mesh
	piece.material_override = material
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.transform = Transform3D(turn, at)
	return piece
