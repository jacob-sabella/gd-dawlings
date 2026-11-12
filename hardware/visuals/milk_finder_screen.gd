class_name MilkFinderScreen
extends CanvasLayer

## The picture finder for a visualizer TV (MilkScreen): every picture by name, found by typing, with what it does.
## Choosing one in the list puts it on the TV at once and shows it live beside the list, so trying them is
## scrolling through them. HOLD keeps the TV on the one chosen (no change every half minute); unticked, it moves
## on by itself again. Opened by the TV's FIND key; Escape or CLOSE shuts it. Like the rack's module finder
## (RackFinderScreen), and as plain.

const _DIM := Color(0.62, 0.68, 0.78)
const _HEAD := Color(1.0, 0.86, 0.5)
## What each picture does, by name, for the list and the card.
const ABOUT := {
	"Tunnel Dive": "Flies into a tunnel of the wave's trails; the bass pushes the zoom.",
	"Spiral Arms": "The wave wound into turning spiral arms that speed up with the music.",
	"Kaleidoscope": "The picture mirrored into a kaleidoscope round the middle.",
	"Liquid": "A slow liquid warp that wobbles harder on every hit.",
	"Starburst": "Rays from the middle, a punch of zoom and a flash of negative on each hit.",
	"Nebula Drift": "Slow coloured clouds drifting; calm, for quiet music.",
	"Radial Bloom": "The spectrum drawn as rays, blooming outward from the middle.",
	"Strobe Lines": "Lines of the wave, flashing negative on the beat when it is loud.",
	"Vortex": "A whirlpool that pulls the wave in and round.",
	"Echo Hall": "The wave echoed back on itself, layer behind layer.",
}

var screen: MilkScreen
var _panel: PanelContainer
var _search: LineEdit
var _list: ItemList
var _detail: RichTextLabel
var _preview: TextureRect
var _hold: CheckBox
var _count: Label
var _found: Array[int] = []


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.visible = false
	PanelLook.solid(_panel)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "FIND A PICTURE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "CLOSE  (Esc)"
	PanelLook.button(close)
	close.pressed.connect(close_finder)
	head.add_child(close)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "type to search: a name, or a word like tunnel, calm, flash, spectrum"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	filters.add_child(_search)
	_count = Label.new()
	_count.add_theme_color_override("font_color", _DIM)
	filters.add_child(_count)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 0)
	_list.item_selected.connect(func(_i: int) -> void: _choose())
	body.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(0, 300)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	right.add_child(_detail)
	_hold = CheckBox.new()
	_hold.text = "HOLD this picture (no change by itself)"
	_hold.toggled.connect(func(on: bool) -> void:
		if screen != null and is_instance_valid(screen):
			screen.auto_advance = not on)
	right.add_child(_hold)
	get_viewport().size_changed.connect(_fit)


func is_open() -> bool:
	return _panel != null and _panel.visible


## Open the finder for `tv`, its picture now chosen.
func open_finder(tv: MilkScreen) -> void:
	screen = tv
	_search.text = ""
	_hold.set_pressed_no_signal(tv != null and not tv.auto_advance)
	_panel.visible = true
	_fit()
	refresh()
	_search.grab_focus()


func close_finder() -> void:
	if _panel != null:
		_panel.visible = false


## The indices of the pictures that match `words` (every word in the name or what it does), in order.
static func search(words: String) -> Array[int]:
	var out: Array[int] = []
	var want := words.to_lower().split(" ", false)
	for i in MilkPresets.count():
		var name := MilkPresets.preset_name(i)
		var text := (name + " " + String(ABOUT.get(name, ""))).to_lower()
		if Array(want).all(func(w: String) -> bool: return text.contains(w)):
			out.append(i)
	return out


func refresh() -> void:
	_found = search(_search.text)
	_list.clear()
	var now := screen.preset_index if screen != null and is_instance_valid(screen) else -1
	for i in _found:
		_list.add_item(("▶ " if i == now else "    ") + MilkPresets.preset_name(i))
	_count.text = "%d of %d" % [_found.size(), MilkPresets.count()]
	var at := _found.find(now)
	if at >= 0:
		_list.select(at)
		_list.ensure_current_is_visible()
	_describe()


## The picture chosen in the list, or -1.
func chosen() -> int:
	var sel := _list.get_selected_items()
	return _found[sel[0]] if not sel.is_empty() and sel[0] < _found.size() else -1


func _choose() -> void:
	var i := chosen()
	if i >= 0 and screen != null and is_instance_valid(screen) and screen.preset_index != i:
		screen.use_preset(i)
		var keep := _list.get_selected_items()
		refresh()
		if not keep.is_empty():
			_list.select(keep[0])
	_describe()


func _describe() -> void:
	var i := chosen()
	if i < 0:
		_detail.text = "Nothing matches. Try fewer words."
		return
	var name := MilkPresets.preset_name(i)
	_detail.text = "[b][color=#ffdc80]%s[/color][/b]\n%s\n[color=#9fb0c8]On the TV now. Click the TV itself to move on to the next.[/color]" \
			% [name, String(ABOUT.get(name, ""))]


func _process(_delta: float) -> void:
	if is_open() and screen != null and is_instance_valid(screen):
		_preview.texture = screen.picture()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_finder()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := minf(980.0, vp.x - 40.0)
	var h := minf(vp.y - 80.0, 720.0)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)
