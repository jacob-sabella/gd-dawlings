class_name PanelButton
extends ControlAffordance

## A latching console button with a light in it: mute, solo, rec-arm, FX bypass.
##
## Latching rather than momentary, because every one of those functions is a state in Reaper
## rather than an event. The press is reported on grab, not on release: a desk button takes
## effect when it goes down, and waiting for the release makes a solo feel broken.
##
## DRAWN BY ITSELF, OR BY A BANK
##
## A button is two meshes, a body and a lamp, and on a 90-track desk there are 270 buttons --
## 540 objects, a quarter of everything the studio draws. So a surface that has a lot of them
## can hand each button a `MeshBank` and the button will claim a slot in it instead of building
## its own; the whole console's bodies then cost one draw call and its lamps cost one more.
##
## Banks are OPTIONAL and a button with none behaves exactly as it always did. That is not
## politeness about old code: the transport has four buttons and the bank selector has two, and
## a MultiMesh holding two instances is strictly worse than two meshes. The repetition is the
## thing that makes a bank pay, so only the places with repetition use one.

signal pressed()

const SIZE := Vector2(0.016, 0.010)
## Stated once, because a bank needs the same numbers to size its shared mesh as a lone button
## needs to size its own -- and a bank whose box is a different shape from the button it stands
## for is a bug that only shows up in a photograph.
const BODY_SIZE := Vector3(SIZE.x, SIZE.y, 0.006)
const LAMP_SIZE := Vector3(SIZE.x * 0.66, SIZE.y * 0.42, 0.0015)
const LAMP_OFFSET := Vector3(0, 0, 0.0038)

## How much bigger than the cap the place that takes the click is. Larger where the button is
## always seen from further off than it is drawn for -- a rack beyond the end of a forty-track
## desk -- and where nothing is close enough beside it for the pad to steal from.
var hit_pad := Vector2(1.2, 1.4)


static func body_material() -> StandardMaterial3D:
	return Materials.cap_plastic(Color(0.12, 0.13, 0.15))

@export var led_colour: Color = Color(0.95, 0.3, 0.25)

## The lamp's silhouette, as a fraction of the full window: a wide bar, a narrow stub, a thin
## line. The redundant half of the coding.
##
## Three identical rectangles in a vertical column, telling you record from solo from mute by
## hue alone, is the textbook form of the most common accessibility defect in audio software --
## and red against amber is exactly the pair a deutan cannot separate. There is no label to
## fall back on at 16 by 10 millimetres, and lettering small enough to fit would be below the
## legibility threshold anyway, so the fallback is shape.
##
## Free, which is why it is done this way rather than with three meshes: the bank places an
## instance from a node's transform, so scaling the marker scales that one lamp and the console
## still draws every lamp it owns in a single call.
@export var lamp_scale := Vector2.ONE

var lit := false:
	set(v):
		lit = v
		_refresh()

## Set before the button enters the tree to draw through a bank instead of through meshes of
## its own. The collider is unaffected either way -- a button still has to be grabbable one at a
## time, and a collision shape is not a draw call.
var body_bank: MeshBank
var lamp_bank: MeshBank

var _lamp: MeshInstance3D
var _lamp_slot := -1
## How far through a dwell this button is, 0 to 1. Read by the suite, which has no eyes.
var dwell_progress := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	if body_bank != null:
		body_bank.place(self, Color.WHITE)
	else:
		var body := MeshInstance3D.new()
		var body_mesh := BoxMesh.new()
		body_mesh.size = BODY_SIZE
		body.mesh = body_mesh
		body.material_override = body_material()
		add_child(body)

	if lamp_bank != null:
		# A marker node rather than arithmetic, so the lamp's offset is stated once and the
		# bank is handed a transform instead of a position plus an assumption about rotation.
		var at := Node3D.new()
		add_child(at)
		at.position = LAMP_OFFSET
		at.scale = Vector3(lamp_scale.x, lamp_scale.y, 1.0)
		_lamp_slot = lamp_bank.place(at, Materials.lamp_colour(led_colour, lit))
		at.queue_free()
	else:
		_lamp = MeshInstance3D.new()
		var lamp_mesh := BoxMesh.new()
		lamp_mesh.size = Vector3(LAMP_SIZE.x * lamp_scale.x, LAMP_SIZE.y * lamp_scale.y, LAMP_SIZE.z)
		_lamp.mesh = lamp_mesh
		_lamp.position = LAMP_OFFSET
		add_child(_lamp)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x * hit_pad.x, SIZE.y * hit_pad.y, 0.01)
	shape.shape = box
	add_child(shape)

	_refresh()


## Cheap to fire by accident -- a mute you did not mean is one press to undo -- which is the
## whole test for whether a control should be dwellable.
func dwell_activates() -> bool:
	return true


func set_dwell_progress(fraction: float) -> void:
	var to := clampf(fraction, 0.0, 1.0)
	if is_equal_approx(to, dwell_progress):
		return
	dwell_progress = to
	_refresh()


func _on_grab_begin(_at: Vector3) -> void:
	pressed.emit()


func _foley_contact() -> AudioStream:
	return Foley.button_click()


func _refresh() -> void:
	# The dwell shows as the lamp filling in. Not a separate ring or bar: the button already has
	# the one thing a person is looking at while they wait for it, and adding a second indicator
	# next to it would mean watching two things to understand one.
	if _lamp_slot >= 0 and lamp_bank != null:
		lamp_bank.set_colour(_lamp_slot, Materials.lamp_colour(led_colour, lit).lerp(
				Materials.lamp_colour(led_colour, true), 0.0 if lit else dwell_progress))
	elif _lamp:
		_lamp.material_override = Materials.led(led_colour, lit or dwell_progress >= 1.0)


func _default_readout() -> String:
	return "ON" if lit else "OFF"


func hint() -> String:
	return "click"
