class_name PadItem
extends InstrumentItem

## A drum pad: struck or shaken to a stop the same way (InstrumentItem.feel). Recorded as the
## General MIDI low-mid tom, 47, or its low voice, the low tom, 45 -- a Tour spill's second
## copy (`voice`).

const MODEL := "res://assets/models/pad.glb"
## tools/blender/spill_percussion.py's rim cylinder: lying face up, its middle is this high.
const HEIGHT := 0.02
const RADIUS := 0.118
const PAD := Color(0.1, 0.1, 0.11)
const RIM := Color(0.68, 0.68, 0.7)
const LED := Color(0.95, 0.25, 0.1)
const PITCHES := [47, 45]


func _init() -> void:
	id = &"pad"
	super()
	_shape.position.y = HEIGHT * 0.5 + 0.01


func item_title() -> String:
	return ("LOW " if voice > 0 else "") + "DRUM PAD"


func hint() -> String:
	return _hint("click to pick up, then shake or strike it")


func pitch() -> int:
	return PITCHES[mini(voice, 1)]


func sound_kind(_struck: bool) -> StringName:
	return &"pad"


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.position.y = HEIGHT * 0.5
	root.add_child(model)
	var pad := StandardMaterial3D.new()
	pad.albedo_color = PAD
	pad.roughness = 0.75
	var rim := StandardMaterial3D.new()
	rim.albedo_color = RIM
	rim.metallic = 0.6
	rim.roughness = 0.4
	var led := StandardMaterial3D.new()
	led.albedo_color = LED
	led.emission_enabled = true
	led.emission = LED
	led.emission_energy_multiplier = 1.2
	var swap := {"pad": pad, "rim": rim, "led": led}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = RADIUS
	s.height = 0.07
	return s


func centre_height() -> float:
	return 0.02


## Held slanted like the tambourine, the pad face up where a beater (or the hand itself) finds
## it.
func held_pose() -> Transform3D:
	var turn := Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, 0.3) * Basis(Vector3.RIGHT, 0.2)
	return Transform3D(turn, turn * Vector3(0, -0.02, -0.11))


func flies() -> Dictionary:
	return {"bounce": 0.15, "roll": 4.0, "drag": 0.1}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.pad(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0), pitch_scale())


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()
