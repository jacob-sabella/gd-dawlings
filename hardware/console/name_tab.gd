class_name NameTab
extends ControlAffordance

## An invisible hit target laid over a channel strip's name: the one thing every strip already
## shows is also where adding a plugin to that track starts.
##
## The strip has no free millimetre for a dedicated button -- every one of them is already
## claimed by a label, a knob or a lamp (2026-10-11: "i genuinely cant tell how to do it...
## adding a plugin", after the rack's own FIND button turned out to be furniture nobody had
## found yet). This rides on ground the strip already drew instead of claiming new ground: no
## mesh of its own, just a collider the size of the header, over the name that was always there.

signal pressed()

const SIZE := Vector3(ChannelStrip.WIDTH - 0.002, 0.032, 0.012)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	add_child(shape)


func _on_grab_begin(_at: Vector3) -> void:
	pressed.emit()


func _foley_contact() -> AudioStream:
	return Foley.button_click()


func hint() -> String:
	return "click to find a plugin"
