class_name HoverCard
extends Node

## What is under the pointer -- name, value, what you can do -- printed flat on the panel it is
## mounted on, just under it, in that panel's own plane: lettering on the gear, never a card in
## the air beside the cursor.
##
## Everything here is already somewhere on the desk -- the track name on the scribble strip,
## the dB under the fader -- but at a monitor's distance most of it is three pixels tall, and
## reading a value off a scribble strip is not how anyone checks a setting while their hand is
## on it. The words are where the eye already is, and lie on the face like the rest of its
## markings, so a desk laid back sixty degrees carries them laid back with it.
##
## It also teaches. The hint is the manual, delivered at the moment the question arises and to
## nobody who has not asked it by pointing. A control that is not part of a surface (a held item,
## a thing in the room) gets none: it says what it is by its own shape and markings.

## Its lettering's cap height and how wide it may run, in metres.
const CAP := 0.017
const WIDEST := 0.7
const PIXEL := 0.0002
## Under the control's footprint, and out from its face, in metres.
const DROP := 0.01
const LIFT := 0.003
const INK := Color(0.95, 0.97, 1.0)
const DIM := Color(0.78, 0.83, 0.9)

## The lettering, in world space (top_level), put under whichever control it describes.
var _strip: Node3D = null
var _on: Surface = null
var _shown: ControlAffordance = null
var _line: Label3D
var _hint: Label3D


## The surface a control is part of, or null.
static func surface_of(control: Node) -> Surface:
	var n := control.get_parent() if control != null else null
	while n != null:
		if n is Surface:
			return n
		n = n.get_parent()
	return null


## The strip's words: the name and value on one line, the hint under them.
static func words(control: ControlAffordance) -> Array:
	var title := control.title()
	var reading := control.readout()
	var line := title if reading == "" else "%s   %s" % [title, reading]
	var hint := "" if control.is_held() else control.card_hint()
	return [line, hint]


func show_for(control: ControlAffordance, _at := Vector2.ZERO) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		hide_card()
		return
	var surface := surface_of(control)
	if surface == null:
		hide_card()
		return
	if _strip == null or not is_instance_valid(_strip):
		_build()
	_on = surface
	var said := words(control)
	_shown = control
	_line.text = said[0]
	_hint.text = said[1]
	_hint.visible = said[1] != ""
	Lettering.fit(_line, WIDEST, _line.get_meta(&"largest"), 24)
	# The hint wraps rather than shrinks: it is the longest thing said and the one read last.
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.width = WIDEST / PIXEL
	var box := HoverRim.footprint(control)
	var face := control.global_transform.orthonormalized()
	var tall := CAP * (3.4 if _hint.visible else 1.4)
	var under := control.global_transform * Vector3(box.get_center().x, box.position.y - DROP, box.end.z + LIFT)
	var over := control.global_transform * Vector3(box.get_center().x, box.end.y + DROP + tall, box.end.z + LIFT)
	# Under the control, unless that is off the view -- a fader's travel ends at the desk's front
	# lip, at the bottom of the frame -- and then over it.
	var at := under if _in_view(under - face.basis.y.normalized() * tall) or not _in_view(over) else over
	_strip.global_transform = Transform3D(face.basis, at)
	_strip.visible = true


func _in_view(point: Vector3) -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null or cam.is_position_behind(point):
		return cam == null
	var p := cam.unproject_position(point)
	var size := vp.get_visible_rect().size
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= size.x and p.y <= size.y


func hide_card() -> void:
	_shown = null
	if _strip != null and is_instance_valid(_strip):
		_strip.visible = false


## Whether a strip is up, and on which surface: for the suite.
func showing() -> Surface:
	return _on if _strip != null and is_instance_valid(_strip) and _strip.visible else null


func line_text() -> String:
	return _line.text if _line != null and is_instance_valid(_line) else ""


func hint_text() -> String:
	return _hint.text if _hint != null and is_instance_valid(_hint) and _hint.visible else ""


func _exit_tree() -> void:
	_drop()


func _drop() -> void:
	if _strip != null and is_instance_valid(_strip):
		_strip.queue_free()
	_strip = null
	_on = null


func _build() -> void:
	_strip = Node3D.new()
	_strip.name = "HoverStrip"
	_strip.top_level = true
	add_child(_strip)
	_line = _label(CAP, INK)
	_hint = _label(CAP * 0.72, DIM)
	_hint.position.y = -CAP * 1.6
	# A heavier outline than the gear's own: the hint can lie over keys and lanes, not bare panel.
	_hint.outline_size = maxi(_hint.outline_size, roundi(_hint.font_size * 0.3))
	_strip.visible = false


func _label(cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.set_meta(&"largest", l.font_size)
	l.modulate = colour
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = false
	l.double_sided = false
	Lettering.dress(l)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_strip.add_child(l)
	return l
