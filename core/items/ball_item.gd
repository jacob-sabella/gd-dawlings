class_name BallItem
extends Item

## A bouncy ball. The thing to throw: hard rubber, so it comes back off the floor and the walls
## most of the way, and a stripe wound round it so you can see it spin. Squeeze it and it gives
## a little.

const MODEL := "res://assets/models/ball.glb"
const RADIUS := 0.045
const RED := Color(0.8, 0.16, 0.13)
const CREAM := Color(0.93, 0.85, 0.66)


func _init() -> void:
	id = &"ball"
	super()


func item_title() -> String:
	return "BOUNCY BALL"


func hint() -> String:
	return "click to pick up; hold R and let go to throw" if state != State.HELD else ""


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = RED
	skin.roughness = 0.38
	var seam := StandardMaterial3D.new()
	seam.albedo_color = CREAM
	seam.roughness = 0.45
	var swap := {"ball": skin, "stripe": seam}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = 0.07
	return s


func centre_height() -> float:
	return RADIUS


## Most of its speed back off anything it hits, and it rolls a long way.
func flies() -> Dictionary:
	return {"bounce": 0.78, "roll": 0.7, "drag": 0.05}


func use(down: bool) -> void:
	poke(-0.25 if down else 0.15)
	if down:
		Foley.play(self, Foley.rubber_tap(), -6.0, 1.3)


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.ball_bounce(), clampf(linear_to_db(speed / 5.0), -24.0, 0.0),
			randf_range(0.95, 1.06))


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()


func on_put_down() -> void:
	Foley.play(self, Foley.ball_bounce(), -10.0)
