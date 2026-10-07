class_name Fader
extends ControlAffordance

## A 100mm channel fader.
##
## The affordance covers the WHOLE TRAVEL, not just the cap, and that is deliberate on both
## input paths. With a mouse it gives you click-in-the-trough-to-jump, which is how every desk
## and every DAW already behaves. With a hand it means the grab does not lapse the instant the
## cap slides out from under your fingertip, which at 100mm of throw is immediately.
##
## Travel is along local +Y. The panel normal is local +Z, which is the plane the Interactor
## projects a wandering ray onto -- so a fader laid onto a tilted console works without the
## interactor knowing anything about consoles.

const TRAVEL := 0.10
const WIDTH := 0.014
const CAP_HEIGHT := 0.022

## Reaper's normalised taper value. Kept separate from `value` only in name: they are the same
## number, and that is the point -- no conversion happens on the way to the DAW.
var track_index: int = 0

var _cap: Node3D
var _grab_offset := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	var slot := MeshInstance3D.new()
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(WIDTH * 0.45, TRAVEL + 0.012, 0.004)
	slot.mesh = slot_mesh
	slot.material_override = Materials.recess()
	slot.position = Vector3(0, TRAVEL * 0.5, 0.002)
	add_child(slot)

	_cap = MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(WIDTH, CAP_HEIGHT, 0.016)
	_cap.mesh = cap_mesh
	_cap.material_override = Materials.cap_plastic(Color(0.17, 0.18, 0.2))
	add_child(_cap)

	# A pale line across the cap. It is the thing you actually read a fader position from at a
	# glance -- the cap's own silhouette against a dark slot is nearly invisible under low
	# studio lighting, which is the lighting this scene has.
	var line := MeshInstance3D.new()
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(WIDTH * 1.05, 0.0015, 0.0165)
	line.mesh = line_mesh
	line.material_override = Materials.legend()
	_cap.add_child(line)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH * 2.2, TRAVEL + CAP_HEIGHT, 0.02)
	shape.shape = box
	shape.position = Vector3(0, TRAVEL * 0.5, 0.008)
	add_child(shape)

	_on_value_changed()


func _on_grab_begin(at: Vector3) -> void:
	# Grabbing the cap must not jump the value; grabbing the trough should. The offset is kept
	# only when the contact was already on the cap, which is what distinguishes the two without
	# needing two colliders.
	var local_y := to_local(at).y
	var cap_y := value * TRAVEL
	_grab_offset = (cap_y - local_y) if absf(local_y - cap_y) < CAP_HEIGHT else 0.0
	_apply_from_local_y(local_y)


func _on_grab_move(at: Vector3) -> void:
	_apply_from_local_y(to_local(at).y)


func _apply_from_local_y(local_y: float) -> void:
	value = clampf((local_y + _grab_offset) / TRAVEL, 0.0, 1.0)
	_on_value_changed()
	Reaper.set_track_volume(track_index, value)


func _on_value_changed() -> void:
	if _cap:
		_cap.position = Vector3(0, value * TRAVEL, 0.009)
