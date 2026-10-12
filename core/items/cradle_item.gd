class_name CradleItem
extends FidgetItem

## A Newton's cradle, the desk toy (docs/items_loop.md): five steel balls hung in a row. Each
## press lifts the end ones and lets them go -- one ball, then two, then three, in turn -- and
## the row clacks back and forth on its own, dying away over a few seconds. A press while it is
## still going stops it dead and starts the next, as a hand does.
##
## The swing is the textbook one, not a simulation of five balls: the lifted group swings down,
## stops dead against the row, and the same number leave the far end, each half swing. So at any
## moment only one group is out, on one side, and its angle is a damped pendulum's (`swing`):
## the same numbers on every machine, from the trick count alone.

const MODEL := "res://assets/models/cradle.glb"
## tools/blender/cradle.py's sizes.
const BALLS := 5
const BALL := 0.0095
const STRING := 0.095
const PIVOT_Y := 0.15
## How far the lifted balls are pulled out (rad), how long the pull takes (s), and how fast the
## swing dies (s for it to fall to a third).
const LIFT_ANGLE := 0.7
const LIFT := 0.45
const DIES := 2.2
## A pendulum this long, at the room's gravity: rad/s.
const SWING_RATE := 10.2
## How long a trick runs: lift, and swinging until it is all but still.
const RUNS := 6.5

## The balls' pivots, left to right.
var balls: Array[Node3D] = []


func _init() -> void:
	id = &"cradle"
	super()
	_shape.position.y = 0.08


func item_title() -> String:
	return "NEWTON'S CRADLE"


func tricks() -> int:
	return 3


func trick_name(k: int) -> String:
	return ["swing one", "swing two", "swing three"][k]


func trick_seconds(_k: int) -> float:
	return RUNS


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.05, 0.05, 0.055)
	base.roughness = 0.35
	var chrome := Materials.brushed_metal()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.79, 0.8)
	steel.metallic = 1.0
	steel.roughness = 0.12
	var thread := StandardMaterial3D.new()
	thread.albedo_color = Color(0.85, 0.85, 0.82)
	thread.roughness = 0.9
	var swap := {"base": base, "chrome": chrome, "ball": steel, "thread": thread}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	# The one ball the model has, hung five times along the rails, touching.
	var one := model.find_child("Ball", true, false) as Node3D
	one.get_parent().remove_child(one)
	for i in BALLS:
		var pivot := Node3D.new()
		pivot.name = "Ball%d" % i
		pivot.position = Vector3((i - (BALLS - 1) * 0.5) * BALL * 2.0, PIVOT_Y, 0)
		pivot.add_child(one if i == 0 else one.duplicate())
		root.add_child(pivot)
		balls.append(pivot)
	return root


## How far out the swinging group is, `t` seconds into trick `k`: positive, the right-hand group
## out to the right; negative, the left-hand one out to the left. Lifted, then let go.
static func swing(t: float) -> float:
	if t < LIFT:
		return LIFT_ANGLE * smoothstep(0.0, 1.0, t / LIFT)
	var free := t - LIFT
	# And brought to rest at the very end, so a trick played out leaves it still.
	var tail := 1.0 - smoothstep(RUNS - LIFT - 0.6, RUNS - LIFT, free)
	return LIFT_ANGLE * exp(-free / DIES) * cos(SWING_RATE * free) * tail


## The moments, from letting go, that the swinging group strikes the row: each zero of the swing.
static func strikes() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var m := 0
	while true:
		var at := (PI * 0.5 + m * PI) / SWING_RATE
		if at > RUNS - LIFT - 0.6:
			break
		out.append(at)
		m += 1
	return out


func pose(k: int, p: float) -> void:
	var t := p * RUNS
	var s := swing(t)
	var n := k + 1
	for i in BALLS:
		var out := 0.0
		if s > 0.0 and i >= BALLS - n:
			out = s
		elif s < 0.0 and i < n:
			out = s
		balls[i].rotation.z = out
	if cue(p, 0.0):
		Foley.play(self, Foley.cradle_click(tricks_done), -26.0, 0.7)
	var times := strikes()
	for m in times.size():
		if cue(p, (LIFT + times[m]) / RUNS):
			# As loud as the swing that ended in it.
			var level := LIFT_ANGLE * exp(-times[m] / DIES) / LIFT_ANGLE
			Foley.play(self, Foley.cradle_click(tricks_done * 31 + m), linear_to_db(level) - 4.0,
					randf_range(0.98, 1.02))


func rest() -> void:
	for b in balls:
		b.rotation = Vector3.ZERO


func end(_k: int) -> void:
	rest()


## Round the frame and taller than it: its rails are thin to point at.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.23, 0.17, 0.14)
	return s


func centre_height() -> float:
	return 0.075


## Held up just over the hand, turned a little toward you so the row is seen at three-quarters:
## along its swing, and the balls out either end both in view.
func held_pose() -> Transform3D:
	var turn := Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, 0.25)
	if carried_by is MouseInteractor:
		return Transform3D(turn, Vector3(0.05, 0.0, -0.08))
	return Transform3D(turn, Vector3(0.05, -0.03, -0.08))


func flies() -> Dictionary:
	return {"bounce": 0.2, "roll": 6.0, "drag": 0.1}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.cradle_click(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), 0.7)


func _foley_contact() -> AudioStream:
	return Foley.cradle_click(0)
