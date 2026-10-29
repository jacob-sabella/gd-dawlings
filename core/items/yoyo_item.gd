class_name YoyoItem
extends FidgetItem

## A yo-yo (docs/items_loop.md). Picked up, its string's loop is on your finger and the yo-yo is
## in your hand; each press throws a trick, in turn: thrown down to sleep spinning at the end of
## its string and tugged back up, around the world (out in front, up over and round in a full
## circle and back), and loop the loop (two quick loops past the hand, down first).
##
## The item's origin is the finger. Where the yo-yo is on its string is a function of the trick
## and the time alone, laid out against the world's down and your forward wherever the hand is,
## so it hangs true however the hand is turned. On the shelf, or on the floor, it lies on its side
## with its string wound up.

const MODEL := "res://assets/models/yoyo.glb"
## tools/blender/yoyo.py's sizes.
const RADIUS := 0.028
const HALF_WIDTH := 0.0178
## The string: as far as it is let out, and how much of it is between finger and yo-yo in the
## hand.
const STRING := 0.7
const IN_HAND := 0.035
## The string your own hand throws on a desktop: the screen is the eye, the hand is at the
## bottom corner of it, and a full string's tricks happen below and behind the picture. Shorter,
## they happen in it. Everybody else sees your ghost throw the full length.
const DESK_STRING := 0.15
## How fast it spins on the end of its string (rad/s).
const SPIN := 70.0
const COLOURS := [Color(0.85, 0.12, 0.1), Color(0.95, 0.95, 0.92)]

var yoyo: Node3D
var cord: MeshInstance3D


func _init() -> void:
	id = &"yoyo"
	super()
	_shape.position.y = HALF_WIDTH


func item_title() -> String:
	return "YO-YO"


func tricks() -> int:
	return 3


func trick_name(k: int) -> String:
	return ["throw it down", "go around the world", "loop the loop"][k]


## How long each trick takes, and what it rings when (FidgetItem.trick_sounds): the whirr as it
## goes out to the end of its string, and the clack of it back in the palm.
const SECONDS := [1.7, 2.2, 2.0]
const SOUNDS := [
	[[0.3 / 1.7, &"yoyo_spin", -8.0, 1.0], [1.55 / 1.7, &"yoyo_catch", -6.0, 1.0]],
	[[0.3 / 2.2, &"yoyo_spin", -8.0, 0.9], [1.95 / 2.2, &"yoyo_catch", -6.0, 1.0]],
	[[0.2 / 2.0, &"yoyo_spin", -10.0, 1.1], [1.85 / 2.0, &"yoyo_catch", -6.0, 1.0]],
]


func trick_seconds(k: int) -> float:
	return SECONDS[k]


func trick_sounds(k: int) -> Array:
	return SOUNDS[k]


func trick_kind() -> StringName:
	return &"yoyo_trick"


## Trick `take` heard whole (Foley.take_of's `yoyo_trick`): what the sampler keeps of one.
static func trick_take(take: int) -> AudioStreamWAV:
	return FidgetItem.trick_stream("yoyo_trick", SOUNDS, SECONDS, take)


func _build_body() -> Node3D:
	var root := Node3D.new()
	yoyo = (load(MODEL) as PackedScene).instantiate() as Node3D
	yoyo.name = "Yoyo"
	root.add_child(yoyo)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = COLOURS[0]
	shell.roughness = 0.25
	shell.clearcoat_enabled = true
	shell.clearcoat = 0.6
	var cap := Materials.brushed_metal()
	var axle := StandardMaterial3D.new()
	axle.albedo_color = Color(0.3, 0.3, 0.32)
	axle.metallic = 0.8
	var swap := {"shell": shell, "cap": cap, "axle": axle}
	for mesh: MeshInstance3D in yoyo.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	cord = MeshInstance3D.new()
	cord.name = "String"
	var line := CylinderMesh.new()
	line.top_radius = 0.0006
	line.bottom_radius = 0.0006
	line.height = 1.0
	line.radial_segments = 4
	line.rings = 1
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.91, 0.86)
	white.roughness = 0.9
	line.material = white
	cord.mesh = line
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cord)
	rest()
	return root


## Down, up and forward, in the item's own frame: the world's, wherever the hand has it turned.
## Forward is along the ground, the way the item faces.
func _ways() -> Array[Vector3]:
	var to_local := global_basis.inverse() if is_inside_tree() else Basis.IDENTITY
	var down := (to_local * Vector3.DOWN).normalized()
	var ahead := global_basis * Vector3.FORWARD if is_inside_tree() else Vector3.FORWARD
	ahead.y = 0.0
	if ahead.length() < 0.01:
		ahead = Vector3.FORWARD
	var forward := (to_local * ahead.normalized()).normalized()
	return [down, -down, forward]


## The yo-yo at `at` on its string, spun round its axle by `spin`, its axle across the plane the
## string swings in (`across`).
func _hang(at: Vector3, spin: float, across := Vector3.ZERO) -> void:
	var ways := _ways()
	var up := ways[1]
	var side := across if across.length() > 0.01 else ways[2].cross(up).normalized()
	if side.length() < 0.01:
		side = Vector3.RIGHT
	var y := up - side * side.dot(up)
	if y.length() < 0.01:
		y = side.cross(Vector3.FORWARD)
	y = y.normalized()
	yoyo.transform = Transform3D(Basis(side, y, side.cross(y)) * Basis(Vector3.RIGHT, spin), at)
	var length := at.length()
	cord.visible = length > 0.012
	if cord.visible:
		var along := at / length
		var tip := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		cord.transform = Transform3D(Basis(tip, along, tip.cross(along)) * Basis.from_scale(Vector3(1, length, 1)),
				at * 0.5)


## In the hand: just under the finger, string wound up.
func _in_hand() -> void:
	_hang(_ways()[0] * IN_HAND, 0.0)


func on_picked_up() -> void:
	_in_hand()


## Lying on its side, string wound up: on the shelf, or wherever it landed.
func rest() -> void:
	if yoyo == null:
		return
	yoyo.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, HALF_WIDTH, 0))
	cord.visible = false


func end(_k: int) -> void:
	if state == State.HELD:
		_in_hand()
	else:
		rest()


func pose(k: int, p: float) -> void:
	var t := p * trick_seconds(k)
	var ways := _ways()
	var down := ways[0]
	var up := ways[1]
	var forward := ways[2]
	var start := down * IN_HAND
	var full := string_length()
	match k:
		0:
			# Thrown down, faster as it falls; asleep at the bottom, spinning; tugged back up.
			var length := IN_HAND
			if t < 0.3:
				length = lerpf(IN_HAND, full, pow(t / 0.3, 2.0))
			elif t < 1.2:
				length = full + 0.012 * full / STRING * sin((t - 0.3) * 40.0) * exp(-(t - 0.3) * 12.0)
			else:
				length = lerpf(full, IN_HAND, span(t, 1.2, 1.55))
			_hang(down * length, SPIN * t)
		1:
			# Out in front at the end of its string, then up, over, behind, under and round to in
			# front again, and back to the hand.
			var out := forward * full
			if t < 0.3:
				_hang(start.lerp(out, span(t, 0.0, 0.3)), SPIN * t)
			elif t < 1.6:
				var a := TAU * span(t, 0.3, 1.6)
				_hang((forward * cos(a) + up * sin(a)) * full, SPIN * t)
			else:
				_hang(out.lerp(start, span(t, 1.6, 1.95)), SPIN * t)
		2:
			# Out in front a short way, then round past the hand twice, down first.
			var reach := minf(full, STRING * 0.45)
			var out := forward * reach
			if t < 0.2:
				_hang(start.lerp(out, span(t, 0.0, 0.2)), SPIN * t)
			elif t < 1.6:
				var a := -2.0 * TAU * span(t, 0.2, 1.6)
				_hang((forward * cos(a) + up * sin(a)) * reach, SPIN * t)
			else:
				_hang(out.lerp(start, span(t, 1.6, 1.85)), SPIN * t)


## How long a string this hand throws: short for your own on a desktop (DESK_STRING).
func string_length() -> float:
	if carried_by is MouseInteractor and (carried_by as MouseInteractor).draws_own_hand():
		return DESK_STRING
	return STRING


## Where the yo-yo is now, in the item's frame.
func yoyo_at() -> Vector3:
	return yoyo.position


func _grip_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = 0.05
	return s


func centre_height() -> float:
	return HALF_WIDTH


## The string's loop on your middle finger, at the glove's fingertips; the yo-yo hangs into the
## palm.
func held_pose() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.04, 0.05, -0.05))


## Round: it bounces, rolls, and goes through a hoop (Flight.fly's `hoops`).
func flies() -> Dictionary:
	return {"bounce": 0.5, "roll": 2.0, "drag": 0.05, "radius": RADIUS}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.yoyo_catch(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), 0.8)


func _foley_contact() -> AudioStream:
	return Foley.yoyo_catch(0)
