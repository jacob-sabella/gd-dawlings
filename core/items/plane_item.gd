class_name PlaneItem
extends Item

## A paper plane. The thing that glides (`Flight`'s wing): thrown level at about walking pace it
## crosses the room, banking off a little to the right the way a hand-folded dart always does;
## thrown at the floor, it goes into it; thrown hard, the paper flutters and it falls short.
## Once it touches anything it is a sheet of paper, and slides to a stop where it lands.

const MODEL := "res://assets/models/plane.glb"
## Off-white, and not too bright: it sits under the shelf lamp, where whiter paper blows out.
const PAPER := Color(0.7, 0.69, 0.64)
const INK := Color(0.72, 0.12, 0.1)
## Its wing (see `Flight.fly`). A paper dart glides at about 4 m/s and comes down a metre for
## every five it goes forward; under 3 m/s it stalls. Past 5 m/s the paper flutters, so a hard
## throw is a short one. Out of the hand it takes 0.4 s to start flying, long enough that a
## throw at the floor hits it. It leans a few degrees right of its own accord.
const WING := {"trim": 4.2, "glide": 5.0, "stall": 3.0, "most": 2.6, "flutter": 5.0, "flap": 1.0,
		"settle": 0.4, "bank": 0.08}


func _init() -> void:
	id = &"plane"
	super()


func item_title() -> String:
	return "PAPER PLANE"


func hint() -> String:
	return _hint("click to pick up; hold R a moment and let go to fly it")


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	# One sheet, seen from both sides.
	var sheet := StandardMaterial3D.new()
	sheet.albedo_color = PAPER
	sheet.roughness = 0.85
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	var line := StandardMaterial3D.new()
	line.albedo_color = INK
	line.roughness = 0.7
	line.cull_mode = BaseMaterial3D.CULL_DISABLED
	var swap := {"paper": sheet, "ink": line}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.16, 0.07, 0.25)
	return s


func centre_height() -> float:
	return 0.025


## Pinched by the keel, nose out ahead and tipped up a little, ready to go.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 0.02, -0.04))


## Paper on the floor: no bounce at all, and it stops in a hand's length.
func flies() -> Dictionary:
	return {"bounce": 0.12, "roll": 12.0, "drag": 0.3, "wing": WING}


func use(down: bool) -> void:
	# A pinch: the wings flex.
	poke(-0.12 if down else 0.06)


func on_launch() -> void:
	Foley.play(self, Foley.paper_swish(), -8.0, randf_range(0.92, 1.1))


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.paper_tap(), clampf(linear_to_db(speed / 4.0), -24.0, -2.0),
			randf_range(0.9, 1.1))


func _foley_contact() -> AudioStream:
	return Foley.paper_tap()


func on_put_down() -> void:
	Foley.play(self, Foley.paper_tap(), -12.0)
