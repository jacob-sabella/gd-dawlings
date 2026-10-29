class_name WorldSocket
extends ControlAffordance

## One of the world's sockets on the modular's patch (docs/spatial_loop.md part two, slice 53; idea
## #31), out in the room where what it carries is made: on the weather's switch (`world:weather`, or
## `world:drips` by the cave's pools), by the venue's instrument's plaque (`world:venue`), on a strip
## beside each of the looper's rings (`world:ring_N`), and on the marble run's tray (`world:marbles`).
## A socket in the patchbay's metal on a small pale plate lettered MODULAR and what it is (pale as the
## wall's outputs are, since it is one), beside the
## station's track jack (JackSocket), which it is independent of: the rain can record onto a track
## and drive the filter at once, one a jack row and the other a cable in the modular's patch.
##
## A press steps its cable through the modular wall's free inputs (Modular.step_input: unplugged, then
## each free input, VCF CV first, and past the last unplugged again); the wheel and the thumbstick
## (`nudge`) step it either way, and on a desktop P and Shift+P over it (MouseInteractor). Any hand
## presses it, as a track jack: a finger, a ray, a controller, a cursor, and a dwell. It only asks
## (`step_asked`): the studio asks the room, and the room's patch comes back through `show_into`.
##
## Patched, it says so twice, neither by colour: a tag over it in words (`-> MODULAR VCF CV IN`), and
## a long cable from its plug down to the floor and along it, up into the input on the wall
## (`wall_jack`, the input's plug as the studio finds it), swept by CableSweep and built again when
## either end moves (a trolley pushed), at most CABLE_HZ. Its front is +Z, out into the room.

## Its cable, in the world, wants patching to an input: the studio's to step, `way` 1 on or -1 back.
signal step_asked(socket: StringName, way: int)

const SOCKETS := &"modular_world_sockets"
## How far round its middle a ray finds it (m), as a track jack's.
const REACH := 0.028
## Its plate, and the socket's bore (the wall's jacks' size).
const PLATE := Vector2(0.05, 0.064)
const RADIUS := 0.0062
## How far beside a station's track jack it stands (m), the further from the plaque.
const BESIDE := 0.075
## The cable: its jacket's radius, how far its run lies over the floor (global y, m), the most often
## it is rebuilt (Hz), and how far an end has to move before it is.
const CABLE_RADIUS := 0.005
const FLOOR := 0.012
const CABLE_HZ := 15.0
const CABLE_MOVED := 0.005
## The cable's colour: the world's own, a sand yellow, as the wall's cables are their module's.
const CABLE_COLOUR := Color(0.86, 0.74, 0.46)
## The tag's lettering, over it.
const TAG_SIZE := 30
const TAG_PIXEL := 0.0006
const TAG_LIFT := 0.09
## How far out from the wall its cable comes before it falls to the floor (m): past the keyboard
## stand's decks under the panel, so it hangs in front of them rather than through them.
const WALL_CLEAR := 0.6

## Which socket it is (Modular.WORLD).
var socket := &""
## The wall's input its cable goes into, or &"" unplugged (`show_into`).
var into := &""
## Where a plug in the wall's input `id` sits, in world space, facing out of the panel, or null where
## there is no wall: the studio's (ModularJack.plug_transform).
var wall_jack: Callable = Callable()
var _shape: CollisionShape3D
var _look: Node3D
var _tag: Label3D
var _cable: MeshInstance3D
var _far_boot: MeshInstance3D
var _near_boot: MeshInstance3D
var _jacket: StandardMaterial3D
var _cable_ends := [Vector3.INF, Vector3.INF]
var _cable_in := 0.0
var _spine := PackedVector3Array()


func _init(id := &"") -> void:
	socket = id
	name = "WorldSocket_%s" % String(id).trim_prefix("world:")
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


func _ready() -> void:
	_jacket = StandardMaterial3D.new()
	_jacket.albedo_color = CABLE_COLOUR
	_jacket.roughness = 0.55
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(PLATE.x, PLATE.y, 0.004)
	plate.mesh = box
	plate.position = Vector3(0, 0.008, -0.002)
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color(0.78, 0.76, 0.7)
	pale.roughness = 0.7
	plate.material_override = pale
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_look.add_child(plate)
	var bore := Part.build(PatchPoint.MESH_PATH, Materials.brushed_metal(), {"bore": Materials.recess()})
	if bore != null:
		bore.rotation_degrees = Vector3(90, 0, 0)
		bore.scale = Vector3.ONE * (RADIUS / PatchPoint.RADIUS)
		_look.add_child(bore)
	_look.add_child(_letter("MODULAR", 0.0085, Vector3(0, 0.03, 0.001)))
	_look.add_child(_letter(short_name(socket), 0.0075, Vector3(0, -0.017, 0.001)))
	_tag = Label3D.new()
	_tag.name = "Tag"
	_tag.font_size = TAG_SIZE
	_tag.pixel_size = TAG_PIXEL
	_tag.outline_size = 8
	_tag.modulate = Color(0.97, 0.94, 0.86)
	_tag.outline_modulate = Color(0.05, 0.04, 0.03)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, TAG_LIFT, 0.01)
	_tag.visible = false
	Lettering.range_to_legibility(_tag)
	_look.add_child(_tag)
	_near_boot = _boot(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.014)), "Boot")
	_look.add_child(_near_boot)
	_cable = MeshInstance3D.new()
	_cable.name = "Cable"
	_cable.top_level = true
	_cable.material_override = _jacket
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cable.visible = false
	add_child(_cable)
	_far_boot = _boot(Transform3D.IDENTITY, "FarBoot")
	_far_boot.top_level = true
	_far_boot.visible = false
	add_child(_far_boot)
	show_into(into)


## What the plate letters under the socket: `WEATHER`, `RING 3`.
static func short_name(id: StringName) -> String:
	var name := String(id).trim_prefix("world:")
	if name.begins_with("ring_"):
		return "RING %s" % name.trim_prefix("ring_")
	return name.to_upper()


## Where its cable goes now (`to`, an input on the wall, or &""), shown: the tag in words, and the
## cable built again at once.
func show_into(to: StringName) -> void:
	into = to
	if _tag == null:
		return
	_tag.visible = to != &""
	_tag.text = tag_text(to)
	_near_boot.visible = to != &""
	_cable_ends = [Vector3.INF, Vector3.INF]
	_cable_in = 0.0
	_follow_cable(0.0)


static func tag_text(to: StringName) -> String:
	return "-> MODULAR %s" % Modular.jack_title(to) if to != &"" else ""


func _physics_process(delta: float) -> void:
	if _shape != null:
		_shape.disabled = not is_visible_in_tree()
	_follow_cable(delta)


## Its cable to the wall while it is patched and the wall has the input: from its plug, out and down
## to the floor, along it and up into the input, built again when either end has moved.
func _follow_cable(delta: float) -> void:
	if _cable == null:
		return
	_cable_in -= delta
	if _cable_in > 0.0:
		return
	var far: Variant = wall_jack.call(into) if into != &"" and wall_jack.is_valid() else null
	var running := far is Transform3D and is_visible_in_tree()
	_far_boot.visible = running
	if not running:
		_cable.visible = false
		_spine = PackedVector3Array()
		return
	var end: Transform3D = far
	var from := global_transform * Vector3(0, 0, 0.026)
	var out := (global_basis * Vector3.BACK).normalized()
	var to := end.origin + end.basis.z.normalized() * 0.026
	if _cable.visible and from.distance_to(_cable_ends[0]) < CABLE_MOVED and to.distance_to(_cable_ends[1]) < CABLE_MOVED:
		return
	_cable_in = 1.0 / CABLE_HZ
	_cable_ends = [from, to]
	_spine = route(from, out, to, end.basis.z.normalized())
	_cable.global_transform = Transform3D.IDENTITY
	_cable.mesh = CableSweep.tube(_spine, CABLE_RADIUS, 8, 12.0)
	_cable.visible = _cable.mesh != null
	_far_boot.global_transform = Transform3D(Basis.looking_at(-end.basis.z, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5),
			end.origin + end.basis.z.normalized() * 0.014)


## A long cable's spine from `from`, leaving along `out`, to `to`, coming into it along `into_out`
## reversed: out a little, down to the floor, along it, and up into the input, coming out from the
## wall WALL_CLEAR first so it hangs clear of the stand under the panel, lying on the floor
## (CableSweep.rest_on) rather than hanging across the room.
static func route(from: Vector3, out: Vector3, to: Vector3, into_out: Vector3) -> PackedVector3Array:
	var a := from + out * 0.06
	var b := to + into_out * 0.08
	var clear := to + into_out * WALL_CLEAR + Vector3.DOWN * 0.12
	var down_a := Vector3(a.x + out.x * 0.1, FLOOR, a.z + out.z * 0.1)
	var down_b := Vector3(clear.x + into_out.x * 0.1, FLOOR, clear.z + into_out.z * 0.1)
	var waypoints := PackedVector3Array([from, a])
	if from.y - FLOOR > 0.15:
		waypoints.append(Vector3(down_a.x, lerpf(FLOOR, a.y, 0.35), down_a.z))
	waypoints.append(down_a)
	if down_a.distance_to(down_b) > 0.2:
		waypoints.append(down_a.lerp(down_b, 0.5))
	waypoints.append(down_b)
	if clear.y - FLOOR > 0.15:
		waypoints.append(Vector3(down_b.x, lerpf(FLOOR, clear.y, 0.4), down_b.z))
	waypoints.append(clear)
	waypoints.append(to + into_out * 0.25 + Vector3.DOWN * 0.03)
	waypoints.append(b)
	waypoints.append(to)
	return CableSweep.rest_on(CableSweep.smooth(waypoints, 6), FLOOR, 0.03)


## The cable's spine in world space while it runs, for the suite and anything riding it.
func spine() -> PackedVector3Array:
	return _spine


func cable_running() -> bool:
	return _cable != null and _cable.visible


func _letter(text: String, cap: float, at: Vector3) -> Label3D:
	var words := Label3D.new()
	words.text = text
	words.pixel_size = 0.0002
	words.font_size = roundi(cap / words.pixel_size)
	words.modulate = Color(0.12, 0.11, 0.1)
	words.position = at
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.double_sided = false
	Lettering.range_to_legibility(words)
	return words


## A plug's boot, standing along its Y.
func _boot(at: Transform3D, called: String) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = called
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0045
	mesh.bottom_radius = 0.0045
	mesh.height = 0.028
	mesh.radial_segments = 12
	piece.mesh = mesh
	piece.material_override = _jacket
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.transform = at
	piece.visible = false
	return piece


# --- pressing it -------------------------------------------------------------------------------

func dwell_activates() -> bool:
	return true


## Where it goes is the room's (the `modular_patch` verb), not a hold.
func personal() -> bool:
	return true


func _on_grab_begin(_at: Vector3) -> void:
	step(1)


func _on_nudge(notches: int, _fine: bool) -> bool:
	return step(signi(notches))


## Its cable one input on (`way` 1) or back (-1), asked.
func step(way: int) -> bool:
	if way == 0 or socket == &"":
		return false
	step_asked.emit(socket, way)
	return true


func _foley_contact() -> AudioStream:
	return Foley.plug_seat()


func _default_title() -> String:
	return "MODULAR  %s OUT" % Modular.world_title(socket)


func _default_readout() -> String:
	if into == &"":
		return "not patched into the modular wall"
	return "into %s on the modular wall" % Modular.jack_title(into)


func hint() -> String:
	if InstrumentItem.hands_hint:
		return "press it: its cable goes into the modular wall's next free input (VCF CV first), round to out again · the stick either way"
	return "click or P: its cable goes into the modular wall's next free input (VCF CV first), round to out again · Shift+P or the wheel back"
