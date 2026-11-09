class_name RackHelpScreen
extends CanvasLayer

## The help card of a rack module (RackHelp), opened by the "?" on its plate. Plain-words help for someone new to
## modular synthesis: what the module is, how it works, what each jack and knob does, a first thing to try, and
## the glossary words the text uses. On an AIRWINDOWS module it is also the effect browser: a kind (reverb, filter,
## ...) and an effect to choose, which sets the module's EFFECT knob and its parameters to that effect's own starting
## values (`knob_asked`), with Chris Johnson's description of the effect and what each knob is for it.
## Escape or the close button shuts it. It changes nothing itself: the host answers `knob_asked`.

## A knob of module `id` is asked to `pos` (0..1).
signal knob_asked(id: String, knob: String, pos: float)

const _TEXT := Color(0.9, 0.92, 0.95)
const _DIM := Color(0.62, 0.68, 0.78)
const _HEAD := Color(1.0, 0.86, 0.5)

var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _browser: VBoxContainer
var _kinds: OptionButton
var _list: ItemList
var _id := ""
var _type := ""
var _effect := ""
var _listed: Array = []


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
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", _HEAD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "CLOSE  (Esc)"
	PanelLook.button(close)
	close.pressed.connect(close_card)
	head.add_child(close)
	_browser = VBoxContainer.new()
	_browser.visible = false
	column.add_child(_browser)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 8)
	_browser.add_child(pick)
	var lead := Label.new()
	lead.text = "KIND"
	lead.add_theme_color_override("font_color", _DIM)
	pick.add_child(lead)
	_kinds = OptionButton.new()
	_kinds.item_selected.connect(_on_kind)
	pick.add_child(_kinds)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 150)
	_list.item_selected.connect(_on_effect)
	_browser.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_font_size_override("bold_font_size", 15)
	scroll.add_child(_body)
	get_viewport().size_changed.connect(_fit)


func is_open() -> bool:
	return _panel != null and _panel.visible


## Open the card of module `id` of `patch`.
func open_for(patch: Dictionary, id: String) -> void:
	var m: Dictionary = patch["modules"].get(id, {})
	if m.is_empty():
		return
	_id = id
	_type = String(m["type"])
	_effect = ""
	if _type == RackHelp.AW_TYPE:
		var names := _effect_names()
		var i := int(RackPatch.knob_of(patch, id, "effect") * names.size())
		_effect = names[clampi(i, 0, names.size() - 1)] if not names.is_empty() else ""
		_fill_browser()
	_browser.visible = _type == RackHelp.AW_TYPE
	_show()


func close_card() -> void:
	if _panel != null:
		_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_card()
		get_viewport().set_input_as_handled()


func _effect_names() -> PackedStringArray:
	var k := RackCatalogue.knob(RackHelp.AW_TYPE, "effect")
	return String(k.get("names", "")).split("|") if not k.is_empty() else PackedStringArray()


func _fill_browser() -> void:
	_kinds.clear()
	var cats := RackHelp.airwindows_categories()
	var pick := 0
	var mine: Array = RackHelp.airwindows(_effect)["categories"]
	var n := 0
	for kind: String in cats:
		_kinds.add_item("%s  (%d)" % [kind, (cats[kind] as Array).size()])
		_kinds.set_item_metadata(n, kind)
		if not mine.is_empty() and kind == mine[0]:
			pick = n
		n += 1
	_kinds.select(pick)
	_list_kind(String(_kinds.get_item_metadata(pick)))


func _on_kind(i: int) -> void:
	_list_kind(String(_kinds.get_item_metadata(i)))


func _list_kind(kind: String) -> void:
	_list.clear()
	_listed = RackHelp.airwindows_categories().get(kind, [])
	for n in _listed.size():
		_list.add_item(String(_listed[n]))
		if _listed[n] == _effect:
			_list.select(n)
			_list.ensure_current_is_visible()


func _on_effect(i: int) -> void:
	choose_effect(String(_listed[i]))


## Choose Airwindows effect `effect`: the module's EFFECT knob goes to it and its parameters to its own starting values.
func choose_effect(effect: String) -> void:
	var names := _effect_names()
	var at := names.find(effect)
	if at < 0 or _id == "":
		return
	_effect = effect
	knob_asked.emit(_id, "effect", (float(at) + 0.5) / names.size())
	var params: Array = RackHelp.airwindows(effect)["params"]
	for n in 12:
		var v := 0.5
		if n < params.size():
			v = float(params[n]["default"])
		knob_asked.emit(_id, char(97 + n), v)
	_show()


func _show() -> void:
	var c := RackHelp.card(_type, _effect)
	if c.is_empty():
		return
	_title.text = "%s   ·   %s" % [c["title"], String(c["group"]).to_upper()]
	_body.text = card_bbcode(c)
	_panel.visible = true
	_fit()


func _fit() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := minf(820.0, vp.x - 40.0)
	var h := minf(vp.y - 80.0, 900.0)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)


static func _e(s: String) -> String:
	return s.replace("[", "[lb]")


## The card as BBCode (static, for the tests too).
static func card_bbcode(c: Dictionary) -> String:
	var t := ""
	var heading := func(s: String) -> String: return "\n[color=#ffdc80][b]%s[/b][/color]\n" % s
	if c["what"] != "":
		t += _e(String(c["what"])) + "\n"
	elif not c.has("airwindows"):
		t += _e(String(c["blurb"])) + "\n"
	if c["how"] != "":
		t += heading.call("HOW IT WORKS") + _e(String(c["how"])) + "\n"
	if c.has("airwindows"):
		t += _airwindows_bbcode(c["airwindows"])
	if not (c["ins"] as Array).is_empty():
		t += heading.call("INPUTS  (where signals come in)")
		for row: Dictionary in c["ins"]:
			t += "[b]%s[/b]   %s\n" % [_e(String(row["id"])), _e(String(row["text"]))]
	if not (c["outs"] as Array).is_empty():
		t += heading.call("OUTPUTS  (where signals go out)")
		for row: Dictionary in c["outs"]:
			t += "[b]%s[/b]   %s\n" % [_e(String(row["id"])), _e(String(row["text"]))]
	if not (c["knobs"] as Array).is_empty():
		t += heading.call("KNOBS")
		for row: Dictionary in c["knobs"]:
			var text := String(row["text"])
			if c.has("airwindows") and String(row["id"]).length() == 1:
				text = _aw_knob_text(c["airwindows"], String(row["id"]), text)
			t += "[b]%s[/b]  [color=#9fb0c8](%s)[/color]   %s\n" % [_e(String(row["label"])), _e(String(row["range"])), _e(text)]
	if c["try"] != "":
		t += heading.call("TRY THIS") + _e(String(c["try"])) + "\n"
	if not (c["terms"] as Array).is_empty():
		t += heading.call("WORDS USED HERE")
		for pair: Array in c["terms"]:
			t += "[b]%s[/b]   %s\n" % [_e(String(pair[0])), _e(String(pair[1]))]
	return t


static func _aw_knob_text(aw: Dictionary, id: String, generic: String) -> String:
	var n := id.unicode_at(0) - 97
	var params: Array = aw["params"]
	if n >= params.size():
		return "Not used by %s." % aw["title"] if params.size() > 0 else generic
	return "%s: %s" % [params[n]["name"], "starts at %d%%" % roundi(float(params[n]["default"]) * 100.0)]


static func _airwindows_bbcode(aw: Dictionary) -> String:
	var t := "\n[color=#ffdc80][b]THE EFFECT: %s[/b][/color]\n" % _e(String(aw["title"]))
	if aw["summary"] != "":
		t += "[i]%s[/i]\n" % _e(String(aw["summary"]))
	for p: String in aw["text"]:
		t += "\n" + _e(p) + "\n"
	if aw["more"]:
		t += "\n[color=#9fb0c8](Shortened. The full text is in Airwindopedia.txt in the Airwindows repository.)[/color]\n"
	if aw["summary"] == "" and aw["known"]:
		t += "[color=#9fb0c8]No description of this one in the Airwindopedia; its knobs are listed below.[/color]\n"
	t += "[color=#9fb0c8]Chris Johnson, airwindows.com (MIT licence).[/color]\n"
	return t
