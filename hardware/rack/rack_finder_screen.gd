class_name RackFinderScreen
extends CanvasLayer

## The module finder: every module the rack can hold, found by typing (name, kind, knob or blurb), by palette group
## and by kind. Choose one to read what it is, then ADD (or Enter, or a double click) to put it in the next free
## place in the case. Opened by the FIND key and by the AIRWINDOWS key of the palette (532 effects will not fit on
## keys). Escape or CLOSE shuts it. It changes nothing itself: the host answers `add_asked` and tells it what came
## of the ask (`tell_added`): the button flashes ADDED, a line under it says so (or why not), and a module the rack
## holds is ticked in the list with how many, since the panel hides the rack the module went into.

## Module `type` is asked to be put in the case.
signal add_asked(type: String)

const _DIM := Color(0.62, 0.68, 0.78)
const _HEAD := Color(1.0, 0.86, 0.5)
const _DONE := Color(0.45, 0.95, 0.55)
const _REFUSED := Color(1.0, 0.5, 0.42)
## How long the button says ADDED.
const FLASH_SECONDS := 1.4
const _ADD_TEXT := "ADD TO THE RACK"
## The rows listed at most (the list is a window on the matches; typing narrows them).
const MOST_LISTED := 600

var _panel: PanelContainer
var _search: LineEdit
var _groups: OptionButton
var _kinds: OptionButton
var _count: Label
var _list: ItemList
var _detail: RichTextLabel
var _add: Button
var _status: Label
var _found: Array[String] = []
var _flash: Tween
## The rack's patch as it is now, for the ticks in the list; unset, nothing is ticked.
var on_rack := Callable()


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
	title.text = "FIND A MODULE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "CLOSE  (Esc)"
	PanelLook.button(close)
	close.pressed.connect(close_finder)
	head.add_child(close)
	_search = LineEdit.new()
	_search.placeholder_text = "type to search: a name, a kind (reverb, dither...), a knob, a word from the description"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	_search.text_submitted.connect(func(_t: String) -> void: _add_chosen())
	column.add_child(_search)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	filters.add_child(_lead("GROUP"))
	_groups = OptionButton.new()
	_groups.item_selected.connect(func(_i: int) -> void: refresh())
	filters.add_child(_groups)
	filters.add_child(_lead("KIND"))
	_kinds = OptionButton.new()
	_kinds.item_selected.connect(func(_i: int) -> void: refresh())
	filters.add_child(_kinds)
	_count = Label.new()
	_count.add_theme_color_override("font_color", _DIM)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	filters.add_child(_count)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_i: int) -> void: _describe())
	_list.item_activated.connect(func(_i: int) -> void: _add_chosen())
	body.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	right.add_child(_detail)
	_add = Button.new()
	_add.text = _ADD_TEXT
	_add.custom_minimum_size = Vector2(0, 40)
	PanelLook.button(_add)
	_add.pressed.connect(_add_chosen)
	right.add_child(_add)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", _DIM)
	right.add_child(_status)
	get_viewport().size_changed.connect(_fit)


func _lead(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _DIM)
	return l


func is_open() -> bool:
	return _panel != null and _panel.visible


## Open the finder, with `group` (a palette group, "" for all) chosen and the search empty.
func open_finder(group := "") -> void:
	_groups.clear()
	_groups.add_item("ALL")
	_groups.set_item_metadata(0, "")
	for g in RackCatalogue.groups():
		_groups.add_item(g.to_upper())
		_groups.set_item_metadata(_groups.item_count - 1, g)
	_select_meta(_groups, group)
	_kinds.clear()
	_kinds.add_item("ANY")
	_kinds.set_item_metadata(0, "")
	for k in RackFinder.all_kinds():
		_kinds.add_item(k.to_upper())
		_kinds.set_item_metadata(_kinds.item_count - 1, k)
	_search.text = ""
	_status.text = ""
	_panel.visible = true
	_fit()
	refresh()
	_search.grab_focus()


func close_finder() -> void:
	if _panel != null:
		_panel.visible = false


static func _select_meta(o: OptionButton, value: String) -> void:
	for i in o.item_count:
		if String(o.get_item_metadata(i)) == value:
			o.select(i)
			return
	o.select(0)


## The list again, for what is typed and chosen; `keep` stays chosen if it is still found.
func refresh(keep := "") -> void:
	var held := held_counts()
	_found = RackFinder.search(_search.text, String(_groups.get_item_metadata(_groups.selected)),
			String(_kinds.get_item_metadata(_kinds.selected)))
	_list.clear()
	for t in _found.slice(0, MOST_LISTED):
		var s := RackCatalogue.spec(t)
		var kinds := RackFinder.kinds_of(t)
		var n := int(held.get(t, 0))
		var mark := "✓ " if n > 0 else "    "
		var many := "  ×%d" % n if n > 1 else ""
		_list.add_item("%s%s%s     %s" % [mark, s["title"], many, String(kinds[0]).to_upper() if not kinds.is_empty() else String(s["group"]).to_upper()])
	_count.text = "%d found" % _found.size() if _found.size() <= MOST_LISTED else "%d found (showing %d)" % [_found.size(), MOST_LISTED]
	if not _found.is_empty():
		var at := maxi(0, _found.find(keep))
		_list.select(at)
		_list.ensure_current_is_visible()
	_describe()


## How many of each type the rack holds, by type; empty where it cannot be read.
func held_counts() -> Dictionary:
	var counts := {}
	if not on_rack.is_valid():
		return counts
	var p: Dictionary = on_rack.call()
	for id in p.get("modules", {}):
		var t := String(p["modules"][id].get("type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


## What came of asking for `type`: "" for added, else why not. The button flashes, the line under it says
## so, and the list ticks the module.
func tell_added(type: String, refusal: String) -> void:
	if _panel == null:
		return
	var title := String(RackCatalogue.spec(type).get("title", type))
	if _flash != null and _flash.is_valid():
		_flash.kill()
	if refusal != "":
		_status.add_theme_color_override("font_color", _REFUSED)
		_status.text = "%s was not added: %s." % [title, refusal]
		_add.text = _ADD_TEXT
		_add.modulate = Color.WHITE
		return
	var n := int(held_counts().get(type, 0))
	_status.add_theme_color_override("font_color", _DONE)
	_status.text = "✓ %s is on the rack%s. CLOSE to see it, or add another." % [title, " (%d of them now)" % n if n > 1 else ""]
	refresh(type)
	_add.text = "✓ ADDED"
	_add.modulate = _DONE
	_flash = create_tween()
	_flash.tween_interval(FLASH_SECONDS)
	_flash.tween_callback(func() -> void:
		_add.text = _ADD_TEXT
		_add.modulate = Color.WHITE)


## The type chosen in the list, or "".
func chosen() -> String:
	var sel := _list.get_selected_items()
	return _found[sel[0]] if not sel.is_empty() and sel[0] < _found.size() else ""


func _describe() -> void:
	var t := chosen()
	_add.disabled = t == ""
	if t == "":
		_detail.text = "Nothing matches. Try fewer words, or ALL and ANY."
		return
	var s := RackCatalogue.spec(t)
	var text := "[b][color=#ffdc80]%s[/color][/b]   %s\n" % [String(s["title"]), String(s["group"]).to_upper()]
	var kinds := RackFinder.kinds_of(t)
	if not kinds.is_empty():
		text += "[color=#9fb0c8]%s[/color]\n" % ", ".join(kinds)
	text += "[color=#9fb0c8]Once it is on the rack, click the ? on its plate to read this again.[/color]\n"
	text += RackHelpScreen.card_bbcode(RackHelp.card(t))
	_detail.text = text


func _add_chosen() -> void:
	var t := chosen()
	if t != "":
		add_asked.emit(t)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_finder()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := minf(1000.0, vp.x - 40.0)
	var h := minf(vp.y - 80.0, 760.0)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)
