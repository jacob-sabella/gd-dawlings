class_name ModsScreen
extends CanvasLayer

## The MODS screen (docs/mods.md section 5): a read-only list of every mod folder the registry read, opened
## and closed with F5 by the host and by a guest alike. One line per mod: status, id, version, licence,
## source pin and what it provides; an unavailable mod (a bad manifest, a missing binary, a missing
## dependency) says why on a line under it, in red, and the warnings of an ok one in grey. It changes nothing: it reads `ModListing` and shows it.

const TOGGLE_KEY := KEY_F5
const _COLUMNS := [["", 104], ["MOD", 230], ["VERSION", 70], ["LICENCE", 110], ["SOURCE PIN", 330], ["PROVIDES", 300]]
const _OK := Color(0.45, 0.88, 0.55)
const _BAD := Color(1.0, 0.45, 0.4)
const _DIM := Color(0.62, 0.68, 0.78)
const _TEXT := Color(0.9, 0.92, 0.95)

## The registry shown; the game's shared one unless a test or tool sets another before opening.
var registry: ModRegistry

var _panel: PanelContainer
var _head: Label
var _rows: VBoxContainer


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 44)
	_panel.visible = false
	PanelLook.solid(_panel)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 13)
	_head.add_theme_color_override("font_color", _DIM)
	column.add_child(_head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1160, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	get_viewport().size_changed.connect(_fit)


func is_open() -> bool:
	return _panel != null and _panel.visible


## Open or close it.
func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY \
			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		toggle()
		get_viewport().set_input_as_handled()


## Throw the rows away and read the registry again.
func rebuild() -> void:
	var reg := registry if registry != null else ModRegistry.ensure_current()
	var mods := ModListing.rows(reg)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var bad := ModListing.unavailable_count(mods)
	_head.text = "MODS  -  %d mods%s  -  F5 to close" % [mods.size(), ", %d unavailable" % bad if bad > 0 else ""]
	_line(_COLUMNS.map(func(c: Array) -> Array: return [c[0], c[1], _DIM]))
	for r in mods:
		var ok: bool = r["status"] == ModListing.OK
		_line([[("OK" if ok else "UNAVAILABLE"), _COLUMNS[0][1], _OK if ok else _BAD], [r["id"], _COLUMNS[1][1], _TEXT],
				[r["version"], _COLUMNS[2][1], _TEXT], [r["licence"], _COLUMNS[3][1], _TEXT],
				[r["source"], _COLUMNS[4][1], _DIM], [r["kind"], _COLUMNS[5][1], _DIM]])
		if not ok:
			_note("      " + r["reason"], _BAD)
		for n: String in r["notes"]:
			_note("      " + n, _DIM)
	_fit()


## One row of cells, each `[text, width, colour]`.
func _line(cells: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for c in cells:
		var label := Label.new()
		label.text = str(c[0])
		label.custom_minimum_size = Vector2(float(c[1]), 0)
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", c[2])
		row.add_child(label)
	_rows.add_child(row)


## A line of words under a row, the width of the whole table.
func _note(text: String, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1150, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", colour)
	_rows.add_child(label)


## Keep the list inside the window: it scrolls past the window's height.
func _fit() -> void:
	if _panel == null:
		return
	var room := get_viewport().get_visible_rect().size.y - 44.0 - 32.0 - 60.0
	var scroll := _panel.find_child("Scroll", true, false) as ScrollContainer
	scroll.custom_minimum_size.y = clampf(_rows.get_combined_minimum_size().y + 4.0, 80.0, maxf(room, 80.0))
