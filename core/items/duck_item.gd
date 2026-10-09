class_name DuckItem
extends Item

## A rubber duck. Squeeze it and it squeaks; let go and it squeaks back, softer, as the air goes
## in. The first item, and the one the item system was built round: nothing to it but being
## picked up, carried, squeezed and put down, which is all of the contract and none of anything
## else.

const MODEL := "res://assets/models/duck.glb"
const YELLOW := Color(0.86, 0.64, 0.08)
const ORANGE := Color(0.9, 0.34, 0.05)


func _init() -> void:
	id = &"duck"
	super()


func item_title() -> String:
	return "RUBBER DUCK"


func hint() -> String:
	return "click to pick up, click again to squeeze" if state != State.HELD else ""


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	# Its beak is toward +Z as modelled; an item faces -Z.
	model.rotation.y = PI
	root.add_child(model)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = YELLOW
	skin.roughness = 0.42
	skin.rim_enabled = true
	skin.rim = 0.12
	var beak := StandardMaterial3D.new()
	beak.albedo_color = ORANGE
	beak.roughness = 0.35
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.03, 0.03, 0.04)
	eye.roughness = 0.12
	var swap := {"duck": skin, "beak": beak, "eye": eye}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = 0.075
	return s


## Sat on the palm, looking the way you are, turned a little in toward the middle of the view
## so it shows you its side and its face rather than its tail.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -1.05), Vector3.ZERO)


func use(down: bool) -> void:
	poke(-0.42 if down else 0.25)
	Foley.play(self, Foley.squeak(down), 0.0 if down else -5.0, randf_range(0.94, 1.08))


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()


func on_put_down() -> void:
	Foley.play(self, Foley.rubber_tap(), -4.0)
