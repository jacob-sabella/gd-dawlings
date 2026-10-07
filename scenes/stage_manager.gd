class_name StageManager
extends CanvasLayer

## The one place a participant can say where they want each piece of gear.
##
## `SurfaceMount.set_mode()` has worked since the mount was written and nothing called it, which
## meant the central claim of this project -- that the same console can be a panel for the
## engineer at the desk and a physical object for the two people standing behind them -- was
## only ever true in principle. It needed a control, and this is the smallest one that makes it
## true in practice.
##
## A FLAT OVERLAY, which is the honest shape for the thing it serves. This is the SCREEN
## participant's tool: someone wearing a headset has no 2D layer worth putting a list on, and
## the in-world equivalent is a grab handle on the surface itself rather than a menu. The
## decision each one makes is the same call into the same mount; only the control differs, and
## that is the division the presentation layer was built for.
##
## Opens with Tab, which is unbound in every other part of this project.

const TOGGLE_KEY := KEY_TAB

var mount: SurfaceMount

var _panel: PanelContainer
var _rows: VBoxContainer


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 44)
	_panel.visible = false
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = "WHERE THE GEAR IS  —  tab to close"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	column.add_child(title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)


func open() -> void:
	_panel.visible = true
	rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		_panel.visible = not _panel.visible
		if _panel.visible:
			rebuild()
		get_viewport().set_input_as_handled()


## Rebuilt on open rather than kept in sync. The list changes only when a surface is registered,
## which happens once at startup, and a panel that is not visible has nothing to keep in sync.
func rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	if mount == null:
		return

	for id in mount.mounted_ids():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_rows.add_child(row)

		var name_label := Label.new()
		name_label.text = String(id)
		name_label.custom_minimum_size = Vector2(110, 0)
		name_label.add_theme_font_size_override("font_size", 13)
		row.add_child(name_label)

		var current := mount.mode_of(id)
		for mode in [Presentation.Mode.SCREEN, Presentation.Mode.ROOM, Presentation.Mode.STUDIO]:
			var button := Button.new()
			button.text = String(Presentation.MODE_NAMES[mode]).to_upper()
			button.custom_minimum_size = Vector2(76, 0)
			button.add_theme_font_size_override("font_size", 12)
			button.toggle_mode = true
			button.button_pressed = mode == current
			# The current mode stays visibly selected and does nothing when pressed again --
			# re-applying a mode would re-anchor the surface and throw away a placement the
			# viewer has since dragged it to.
			button.disabled = mode == current
			button.pressed.connect(_on_mode_chosen.bind(id, mode))
			row.add_child(button)

		var reset := Button.new()
		reset.text = "RESET"
		reset.add_theme_font_size_override("font_size", 12)
		reset.pressed.connect(_on_reset.bind(id))
		row.add_child(reset)


func _on_mode_chosen(surface_id: StringName, mode: int) -> void:
	mount.set_mode(surface_id, mode)
	rebuild()


func _on_reset(surface_id: StringName) -> void:
	mount.reset_placement(surface_id)
	rebuild()
