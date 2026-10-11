class_name WoodblockItem
extends InstrumentItem

## A woodblock: a solid knock, struck or shaken to a stop the same way (InstrumentItem.feel).
## Recorded as the General MIDI hi wood block, 76, or its low voice, the low wood block, 77 --
## a Tour spill's second copy (`voice`).

const MODEL := "res://assets/models/woodblock.glb"
## tools/blender/spill_percussion.py's box: lying on its slot face, its middle is this high.
const HEIGHT := 0.045
const WOOD := Color(0.42, 0.26, 0.14)
const SLOT := Color(0.12, 0.08, 0.05)
const PITCHES := [76, 77]


func _init() -> void:
	id = &"woodblock"
	super()
	_shape.position.y = HEIGHT * 0.5


func item_title() -> String:
	return ("LOW " if voice > 0 else "") + "WOODBLOCK"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound(_struck: bool, take: int) -> AudioStream:
	return Foley.woodblock(take)


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD
	wood.roughness = 0.5
	var slot := StandardMaterial3D.new()
	slot.albedo_color = SLOT
	slot.roughness = 0.7
	var swap := {"wood": wood, "slot": slot}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.19, 0.08, 0.09)
	return s


func centre_height() -> float:
	return 0.025


## Held like the shaker: across the view, tipped toward the outside, the slot up where a beater
## would find it.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.FORWARD, 0.5) * Basis(Vector3.UP, 0.35), Vector3(0.02, -0.025, 0))


func flies() -> Dictionary:
	return {"bounce": 0.3, "roll": 2.5, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.woodblock(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()
