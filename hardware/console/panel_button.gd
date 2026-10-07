class_name PanelButton
extends ControlAffordance

## A latching console button with a light in it: mute, solo, rec-arm, FX bypass.
##
## Latching rather than momentary, because every one of those functions is a state in Reaper
## rather than an event. The press is reported on grab, not on release: a desk button takes
## effect when it goes down, and waiting for the release makes a solo feel broken.

signal pressed()

const SIZE := Vector2(0.016, 0.010)

@export var led_colour: Color = Color(0.95, 0.3, 0.25)

var lit := false:
	set(v):
		lit = v
		_refresh()

var _lamp: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(SIZE.x, SIZE.y, 0.006)
	body.mesh = body_mesh
	body.material_override = Materials.cap_plastic(Color(0.12, 0.13, 0.15))
	add_child(body)

	_lamp = MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(SIZE.x * 0.66, SIZE.y * 0.42, 0.0015)
	_lamp.mesh = lamp_mesh
	_lamp.position = Vector3(0, 0, 0.0038)
	add_child(_lamp)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x * 1.2, SIZE.y * 1.4, 0.01)
	shape.shape = box
	add_child(shape)

	_refresh()


func _on_grab_begin(_at: Vector3) -> void:
	pressed.emit()


func _foley_contact() -> AudioStream:
	return Foley.button_click()


func _refresh() -> void:
	if _lamp:
		_lamp.material_override = Materials.led(led_colour, lit)
