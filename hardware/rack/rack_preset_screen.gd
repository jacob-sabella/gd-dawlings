class_name RackPresetScreen
extends CanvasLayer

## The rack's presets, as a pop-up (the PRESETS key of the palette): the ready-made patches the mods provide and
## the player's own (RackUserPresets), searched by name or by a module they hold. Choose one to see what is in
## it, then LOAD (or Enter, or a double click) to put it on the rack in place of what is there. Below, SAVE
## keeps the rack as it is now as a preset of the player's own, under the name typed; one of theirs can be
## deleted. Escape or CLOSE shuts it. Loading changes nothing itself: the host answers `load_asked` (the
## `preset` ask for a ready-made one, `load` with the patch for the player's own).

## Asked to replace the rack: `op` and `args` as RackPatch.answer takes them.
signal load_asked(op: String, args: Array)

const _DIM := Color(0.62, 0.68, 0.78)
const _HEAD := Color(1.0, 0.86, 0.5)
const _DONE := Color(0.45, 0.95, 0.55)
const _REFUSED := Color(1.0, 0.5, 0.42)
const _LOAD_TEXT := "LOAD ONTO THE RACK"
const _SAVE_TEXT := "SAVE"
const _DELETE_TEXT := "DELETE"

## The rack's patch as it is now (what SAVE keeps); unset, SAVE has nothing to keep.
var on_rack := Callable()

var _panel: PanelContainer
var _search: LineEdit
var _count: Label
var _list: ItemList
var _detail: RichTextLabel
var _load: Button
var _delete: Button
var _status: Label
var _name: LineEdit
var _save: Button
var _save_note: Label
## What the list shows, in order: {kind: "builtin"|"own", name, title}.
var _found: Array[Dictionary] = []
## A press of SAVE or DELETE that needs a second to go through: the name it was for.
var _save_armed := ""
var _delete_armed := ""


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
	title.text = "RACK PRESETS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "CLOSE  (Esc)"
	PanelLook.button(close)
	close.pressed.connect(close_presets)
	head.add_child(close)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "type to search: a name, or a module in it (plaits, reverb, drums...)"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	_search.text_submitted.connect(func(_t: String) -> void: _load_chosen())
	filters.add_child(_search)
	_count = Label.new()
	_count.add_theme_color_override("font_color", _DIM)
	filters.add_child(_count)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(280, 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_i: int) -> void: _describe())
	_list.item_activated.connect(func(_i: int) -> void: _load_chosen())
	body.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.scroll_active = true
	_detail.custom_minimum_size = Vector2(0, 80)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	right.add_child(_detail)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	right.add_child(acts)
	_load = Button.new()
	_load.text = _LOAD_TEXT
	_load.custom_minimum_size = Vector2(0, 40)
	_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelLook.button(_load)
	_load.pressed.connect(_load_chosen)
	acts.add_child(_load)
	_delete = Button.new()
	_delete.text = _DELETE_TEXT
	_delete.custom_minimum_size = Vector2(0, 40)
	PanelLook.button(_delete)
	_delete.pressed.connect(_delete_chosen)
	acts.add_child(_delete)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", _DIM)
	right.add_child(_status)
	column.add_child(HSeparator.new())
	var keep := Label.new()
	keep.text = "SAVE THE RACK AS IT IS NOW"
	keep.add_theme_color_override("font_color", _HEAD)
	column.add_child(keep)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = "a name for it"
	_name.max_length = RackUserPresets.MOST_TITLE
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(_t: String) -> void: _disarm_save())
	_name.text_submitted.connect(func(_t: String) -> void: save_current())
	row.add_child(_name)
	_save = Button.new()
	_save.text = _SAVE_TEXT
	_save.custom_minimum_size = Vector2(120, 0)
	PanelLook.button(_save)
	_save.pressed.connect(save_current)
	row.add_child(_save)
	_save_note = Label.new()
	_save_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_note.add_theme_color_override("font_color", _DIM)
	_save_note.text = "Kept on this computer with your own presets. A name you have used already is replaced (SAVE twice)."
	column.add_child(_save_note)
	get_viewport().size_changed.connect(_fit)
	_panel.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)


func is_open() -> bool:
	return _panel != null and _panel.visible


func open_presets() -> void:
	_search.text = ""
	_status.text = ""
	_disarm_save()
	_disarm_delete()
	_panel.visible = true
	_fit()
	refresh()
	_search.grab_focus()


func close_presets() -> void:
	if _panel != null:
		_panel.visible = false


## Every preset that matches `words` (all of them, in a title or a module title): the ready-made ones in the
## mods' order, then the player's own by name.
static func search(words: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in RackPatch.presets():
		out.append({"kind": "builtin", "name": String(n), "title": RackPatch.preset_title(n)})
	for own in RackUserPresets.all():
		out.append({"kind": "own", "name": String(own["name"]), "title": String(own["title"])})
	var want := words.strip_edges().to_lower().split(" ", false)
	if want.is_empty():
		return out
	var kept: Array[Dictionary] = []
	for it in out:
		var hay := String(it["title"]).to_lower()
		for t in module_titles(patch_of(it)):
			hay += " " + String(t).to_lower()
		var all := true
		for w in want:
			if not hay.contains(w):
				all = false
				break
		if all:
			kept.append(it)
	return kept


## The patch an entry of the list stands for (a room patch), or an empty one.
static func patch_of(it: Dictionary) -> Dictionary:
	if it.get("kind") == "own":
		return RackPatch.from_dict(RackUserPresets.patch_dict(String(it["name"])))
	return RackPatch.preset(StringName(it["name"]))


## The modules a patch holds, by title, each once, with how many there are: ["Plaits x2", "Reverb"].
static func module_titles(p: Dictionary) -> Array[String]:
	var counts := {}
	var order: Array[String] = []
	for id in RackPatch.module_ids(p):
		var type := String(p["modules"][id]["type"])
		var t := String(RackCatalogue.spec(type).get("title", type))
		if not counts.has(t):
			order.append(t)
		counts[t] = int(counts.get(t, 0)) + 1
	var out: Array[String] = []
	for t in order:
		out.append(t if counts[t] == 1 else "%s x%d" % [t, counts[t]])
	return out


## The list again, for what is typed; `keep` (a name) stays chosen if it is still found.
func refresh(keep := "") -> void:
	_found = search(_search.text)
	_list.clear()
	var at := 0
	for i in _found.size():
		var it := _found[i]
		var mark := "★ " if it["kind"] == "own" else "    "
		_list.add_item("%s%s" % [mark, it["title"]])
		if it["name"] == keep:
			at = i
	var own := 0
	for it in _found:
		if it["kind"] == "own":
			own += 1
	_count.text = "%d presets, %d of them yours (★)" % [_found.size(), own]
	if not _found.is_empty():
		_list.select(at)
		_list.ensure_current_is_visible()
	_describe()


## The entry chosen in the list, or {}.
func chosen() -> Dictionary:
	var sel := _list.get_selected_items()
	return _found[sel[0]] if not sel.is_empty() and sel[0] < _found.size() else {}


func _describe() -> void:
	_disarm_delete()
	var it := chosen()
	_load.disabled = it.is_empty()
	_delete.visible = not it.is_empty() and it["kind"] == "own"
	if it.is_empty():
		_detail.text = "Nothing matches. Try fewer words."
		return
	var p := patch_of(it)
	var mods := RackPatch.module_ids(p).size()
	var text := "[b][color=#ffdc80]%s[/color][/b]   %s\n" % [String(it["title"]), "YOURS" if it["kind"] == "own" else "READY-MADE"]
	text += "[color=#9fb0c8]%d module%s, %d cable%s. Loading it replaces everything on the rack.[/color]\n\n" % [
			mods, "" if mods == 1 else "s", (p["cables"] as Array).size(), "" if (p["cables"] as Array).size() == 1 else "s"]
	text += ", ".join(module_titles(p)) if mods > 0 else "An empty rack (only what every rack keeps)."
	_detail.text = text


func _load_chosen() -> void:
	var it := chosen()
	if it.is_empty():
		return
	if it["kind"] == "own":
		var d := RackUserPresets.patch_dict(String(it["name"]))
		if d.is_empty():
			_tell("%s could not be read." % it["title"], false)
			return
		_tell("✓ %s is on the rack." % it["title"], true)
		load_asked.emit("load", [d])
	else:
		_tell("✓ %s is on the rack." % it["title"], true)
		load_asked.emit("preset", [String(it["name"])])


## What came of a load the host refused: said under the button.
func tell_refused(why: String) -> void:
	if _status != null:
		_tell("Not loaded: %s." % why, false)


## Keeps the rack as it is now under the name typed. A name already used needs a second press. The refusal in
## words, or "" when kept (or waiting for that second press).
func save_current() -> String:
	var title := _name.text.strip_edges()
	if not on_rack.is_valid():
		return _saved("there is no rack to keep")
	if RackUserPresets.name_of(title) == "":
		return _saved("type a name for it first")
	if RackUserPresets.has(title) and _save_armed != RackUserPresets.name_of(title):
		_save_armed = RackUserPresets.name_of(title)
		_save.text = "REPLACE?"
		_save_note.add_theme_color_override("font_color", _HEAD)
		_save_note.text = "You have a preset called that. SAVE again to replace it with the rack as it is now."
		return ""
	var why := RackUserPresets.save(title, on_rack.call())
	if why != "":
		return _saved(why)
	_disarm_save()
	_save_note.add_theme_color_override("font_color", _DONE)
	_save_note.text = "✓ Saved as %s." % title
	_search.text = ""
	refresh(RackUserPresets.name_of(title))
	return ""


func _saved(why: String) -> String:
	_disarm_save()
	_save_note.add_theme_color_override("font_color", _REFUSED)
	_save_note.text = "Not saved: %s." % why
	return why


func _disarm_save() -> void:
	_save_armed = ""
	if _save != null:
		_save.text = _SAVE_TEXT


func _delete_chosen() -> void:
	var it := chosen()
	if it.is_empty() or it["kind"] != "own":
		return
	if _delete_armed != it["name"]:
		_delete_armed = String(it["name"])
		_delete.text = "SURE?"
		_tell("DELETE again to forget %s for good." % it["title"], false)
		return
	RackUserPresets.remove(String(it["name"]))
	_disarm_delete()
	refresh()
	_tell("%s is deleted." % it["title"], true)


func _disarm_delete() -> void:
	_delete_armed = ""
	if _delete != null:
		_delete.text = _DELETE_TEXT


func _tell(text: String, good: bool) -> void:
	_status.add_theme_color_override("font_color", _DONE if good else _REFUSED)
	_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_presets()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel != null:
		PanelLook.fit_modal(_panel, Vector2(900.0, 640.0))
