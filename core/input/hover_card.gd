class_name HoverCard
extends CanvasLayer

## The small panel beside the cursor that says what is under it: name, value, what you can do.
##
## Everything here is already somewhere on the desk -- the track name on the scribble strip,
## the dB under the fader -- but at a monitor's distance most of it is three pixels tall, and
## reading a value off a scribble strip is not how anyone checks a setting while their hand is
## on it. The card is where the eye already is.
##
## It also teaches. The hint line is the manual, delivered at the moment the question arises
## and to nobody who has not asked it by pointing.

const OFFSET := Vector2(22, 18)

var _panel: PanelContainer
var _title: Label
var _value: Label
var _hint: Label
var _shown: ControlAffordance = null


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.90)
	style.border_color = Color(0.62, 0.82, 1.0, 0.85)
	style.border_width_left = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 7
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_title = _line(column, Color(0.66, 0.72, 0.80))
	_value = _line(column, Color(0.95, 0.97, 1.0))
	_hint = _line(column, Color(0.50, 0.55, 0.62))
	_restyle()
	_panel.visible = false


func _line(parent: Control, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Sized off the same text scale as the lettering on the gear, so one +/- press is one answer
## to "can you read it" across the whole room, card included.
func _restyle() -> void:
	var k := clampf(Ergonomics.current.text_scale, 0.6, 3.0)
	_title.add_theme_font_size_override("font_size", roundi(11 * k))
	_value.add_theme_font_size_override("font_size", roundi(17 * k))
	_hint.add_theme_font_size_override("font_size", roundi(10 * k))


func show_for(control: ControlAffordance, at: Vector2) -> void:
	if control == null or not is_instance_valid(control):
		_panel.visible = false
		_shown = null
		return
	if control != _shown:
		_shown = control
		_restyle()
	_title.text = control.title()
	var reading := control.readout()
	_value.text = reading
	_value.visible = reading != ""
	_hint.text = control.hint()
	_hint.visible = _hint.text != "" and not control.is_held()
	_panel.visible = true
	# Shrink to the text every time, or a card that once showed a long name keeps its width.
	_panel.reset_size()
	var view := _panel.get_viewport_rect().size
	var pos := at + OFFSET
	# Flipped to the other side of the cursor rather than clamped, so the card never ends up
	# under the pointer it is describing.
	if pos.x + _panel.size.x > view.x - 4:
		pos.x = at.x - OFFSET.x - _panel.size.x
	if pos.y + _panel.size.y > view.y - 4:
		pos.y = at.y - OFFSET.y - _panel.size.y
	_panel.position = pos.floor()


func hide_card() -> void:
	_panel.visible = false
	_shown = null
