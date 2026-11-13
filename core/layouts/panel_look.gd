class_name PanelLook
extends RefCounted

## The look the edit panels share (F3 LayoutEditor, F4 RoomMaker): a solid dark panel, so text in the
## room behind never shows through it, and buttons whose selected state cannot be missed: a picked
## button is a filled accent with bold white text, an unpicked one a flat dark grey.

const PANEL_BG := Color(0.07, 0.08, 0.10, 1.0)
const PANEL_EDGE := Color(0.32, 0.38, 0.48)
const BUTTON_BG := Color(0.17, 0.19, 0.23)
const BUTTON_HOVER := Color(0.25, 0.28, 0.34)
const PICKED_BG := Color(0.20, 0.52, 0.92)
const PICKED_EDGE := Color(0.85, 0.93, 1.0)


## Gives `panel` the solid background and a thin edge.
static func solid(panel: PanelContainer) -> void:
	var box := _box(PANEL_BG, PANEL_EDGE, 1, 6)
	panel.add_theme_stylebox_override("panel", box)


## Gives `b` the flat and picked looks; a toggle button that is down is the filled accent.
static func button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(BUTTON_BG, BUTTON_BG, 1, 4))
	b.add_theme_stylebox_override("hover", _box(BUTTON_HOVER, PANEL_EDGE, 1, 4))
	b.add_theme_stylebox_override("pressed", _box(PICKED_BG, PICKED_EDGE, 2, 4))
	b.add_theme_stylebox_override("hover_pressed", _box(PICKED_BG.lightened(0.12), PICKED_EDGE, 2, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


## Sizes a pop-up `panel` to at most `most`, never more than the screen less `edge` all round, and centres it.
## A panel whose content still asks for more than that grows past it; it is then kept on screen from the top
## left, so its title and CLOSE can always be reached. Call again when the screen or the content changes.
static func fit_modal(panel: Control, most: Vector2, edge := 20.0) -> void:
	var vp := panel.get_viewport_rect().size
	var want := Vector2(minf(most.x, vp.x - edge * 2.0), minf(most.y, vp.y - edge * 2.0))
	panel.custom_minimum_size = want
	panel.size = want
	var got := panel.size
	panel.position = Vector2(maxf(edge * 0.5, (vp.x - got.x) * 0.5), maxf(edge * 0.5, (vp.y - got.y) * 0.5))


static func _box(fill: Color, edge: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box
