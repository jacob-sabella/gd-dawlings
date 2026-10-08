class_name TabletSelector
extends ControlAffordance

## A little lit window that names one choice from a list: scroll over it to change the choice,
## click it to act on the choice. The plugin tablet's KEY IN and MOVE TO are both one of these.
##
## Two gestures rather than one because the choice is a track and the act is a routing change.
## A wheel that patched a sidechain on every notch would key the compressor from every track it
## passed on the way to the one that was meant.

signal pressed(choice: int)
## The wheel moved the window to another choice.
signal chosen(choice: int)

## The window's size on the panel, centred on this node.
var size := Vector2(0.07, 0.016)
## () -> Array of [id: int, words: String], in the order the wheel walks them.
var options: Callable = Callable()
## The id currently in the window, or -1 for none.
var choice := -1
## What clicking does, for the hover card.
var hint_text := "scroll to choose  ·  click"
## Lit when the choice in the window is the one in effect: KEY IN's window glows while that
## track really is keying the plugin.
var lit := false:
	set(v):
		lit = v
		_paint()

var _words: Label3D
var _glass := StandardMaterial3D.new()


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = size
	glass.mesh = quad
	glass.position.z = 0.0008
	glass.material_override = _glass
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	_words = Label3D.new()
	_words.name = "Words"
	_words.pixel_size = 0.0002
	_words.font_size = 44
	_words.position.z = 0.0014
	add_child(_words)
	Lettering.range_to_legibility(_words)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y * 1.3, 0.01)
	shape.shape = box
	shape.position.z = 0.004
	add_child(shape)
	refresh()


## Re-read the list, keeping the choice if it is still on it.
func refresh() -> void:
	var list := _list()
	if not list.any(func(o): return int(o[0]) == choice):
		choice = int(list[0][0]) if not list.is_empty() else -1
	if _words != null:
		_words.text = words()
		Lettering.fit(_words, size.x - 0.006, 44)
	_paint()


func words() -> String:
	for o in _list():
		if int(o[0]) == choice:
			return str(o[1])
	return "—"


func _list() -> Array:
	return options.call() if options.is_valid() else []


func _paint() -> void:
	_glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass.albedo_color = Color(0.10, 0.17, 0.13) if lit else Color(0.045, 0.05, 0.055)
	if _words != null:
		_words.modulate = Color(0.62, 1.0, 0.72) if lit else Color(0.78, 0.80, 0.84)


func _on_nudge(notches: int, _fine: bool) -> bool:
	var list := _list()
	if list.is_empty():
		return false
	var at := 0
	for i in list.size():
		if int(list[i][0]) == choice:
			at = i
	choice = int(list[posmod(at + signi(notches), list.size())][0])
	refresh()
	chosen.emit(choice)
	return true


func _on_grab_begin(_at: Vector3) -> void:
	pressed.emit(choice)


func dwell_activates() -> bool:
	return false


func _foley_contact() -> AudioStream:
	return Foley.button_click()


func _default_readout() -> String:
	return words()


func hint() -> String:
	return hint_text
