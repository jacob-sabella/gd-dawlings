class_name BongoItem
extends InstrumentItem

## A pair of bongos, joined: struck by hand, a stroke-stop plays it exactly like a click
## (InstrumentItem.feel). Recorded as the General MIDI hi bongo, 60, or its low voice, the low
## bongo, 61 -- a Tour spill's second copy (`voice`).

const MODEL := "res://assets/models/bongos.glb"
## tools/blender/spill_percussion.py's joined shells: its own origin is its vertical middle, the
## same convention as the cowbell, the pad, the triangle, the claves and the hi-hat.
const HEIGHT := 0.095
const SHELL := Color(0.42, 0.24, 0.1)
const PITCHES := [60, 61]


func _init() -> void:
	id = &"bongo"
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return ("LOW " if voice > 0 else "") + "BONGO"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound(_struck: bool, take: int) -> AudioStream:
	return Foley.bongo(take)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = SHELL
	shell.roughness = 0.5
	var swap := {"shell": shell}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.24, 0.085, 0.14)
	return s


func centre_height() -> float:
	return HEIGHT * 0.5


## Held flat across the palm, both drumheads facing up where a strike lands -- the same
## held-across gesture as the hi-hat's, widened for a joined pair this long.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.FORWARD, 0.3) * Basis(Vector3.UP, 0.2), Vector3(0.02, -0.04, 0))


func flies() -> Dictionary:
	return {"bounce": 0.24, "roll": 2.6, "drag": 0.07}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.bongo(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()
