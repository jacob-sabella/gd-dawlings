class_name RoomMaker
extends CanvasLayer

## The new-room maker (docs/layouts.md 8): a small plain panel the host opens and closes with F4, beside the
## room's edit mode (F3). It asks for a name, a size (small, standard, large), a look, any of the zones
## that fit that size, which of the single items the room keeps, and, on a line of its own because it is
## of the other class, the room-scale mod (the modular room). MAKE writes the room as a layout file
## (`MadeRooms.make`, checked by `MadeRoom` and the validator) and takes the band into it. It holds
## nothing but the spec being asked for; a guest sees only that the host makes rooms.

const TOGGLE_KEY := KEY_F4
const HOST_ONLY := "Only the host can make a new room."

var studio: Studio
## What is being asked for (`MadeRoom`'s spec).
var spec: Dictionary = MadeRoom.default_spec()

var _panel: PanelContainer
var _rows: VBoxContainer
var _status: Label
var _name: LineEdit


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
	title.text = "MAKE A NEW ROOM  -  F4 to close"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	column.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 0)
	column.add_child(_status)


func is_open() -> bool:
	return _panel != null and _panel.visible


## Open or close it. A guest gets the notice in place of the controls.
func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		if not Session.is_authority():
			Session.notice.emit(HOST_ONLY)
			_panel.visible = false
			return
		rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY \
			and not (_name != null and _name.has_focus()):
		toggle()
		get_viewport().set_input_as_handled()


## Choose a size: the zones that do not fit it, and the pieces that needed them, are let go.
func set_size(size: StringName) -> void:
	spec["size"] = String(size)
	var fits := MadeRoom.zones_fitting(size)
	spec["zones"] = (spec["zones"] as Array).filter(func(z: Variant) -> bool: return StringName(str(z)) in fits)
	_drop_unneeded()
	rebuild()


## Tick or untick a zone; the pieces that need an unticked one go with it.
func set_zone(zone: StringName, on: bool) -> void:
	var zones: Array = spec["zones"]
	if on and String(zone) not in zones:
		zones.append(String(zone))
	elif not on:
		zones.erase(String(zone))
	_drop_unneeded()
	rebuild()


## Tick or untick a single item (it can only be ticked where its zone is).
func set_piece(kind: StringName, on: bool) -> void:
	var pieces: Array = spec["pieces"]
	if on and String(kind) not in pieces and (not MadeRoom.NEEDS.has(kind) or String(MadeRoom.NEEDS[kind]) in spec["zones"]):
		pieces.append(String(kind))
	elif not on:
		pieces.erase(String(kind))
	rebuild()


func _drop_unneeded() -> void:
	spec["pieces"] = (spec["pieces"] as Array).filter(func(p: Variant) -> bool:
		return not MadeRoom.NEEDS.has(StringName(str(p))) or String(MadeRoom.NEEDS[StringName(str(p))]) in spec["zones"])


func rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_name = LineEdit.new()
	_name.text = str(spec["title"])
	_name.max_length = MadeRoom.MAX_TITLE
	_name.placeholder_text = "name"
	_name.text_changed.connect(func(text: String) -> void: spec["title"] = text)
	_rows.add_child(_name)
	var size := StringName(spec["size"])
	_row("size", MadeRoom.SIZES.map(func(s: StringName) -> Array: return [String(s).to_upper(), s == size, func() -> void: set_size(s)]))
	_row("look", BoxStyle.IDS.map(func(s: StringName) -> Array:
		return [String(BoxStyle.TABLE[s]["title"]).to_upper(), String(s) == str(spec["style"]), func() -> void: spec["style"] = String(s); rebuild()]))
	var fits := MadeRoom.zones_fitting(size)
	_row("zones", fits.map(func(z: StringName) -> Array:
		return [String(MadeRoom.ZONE_TITLES[z]).to_upper(), String(z) in spec["zones"], func() -> void: set_zone(z, String(z) not in spec["zones"])]))
	_row("pieces", PieceCatalogue.kinds().map(func(k: StringName) -> Array:
		return [PieceCatalogue.title(k), String(k) in spec["pieces"], func() -> void: set_piece(k, String(k) not in spec["pieces"])]))
	_row("room-scale", [["MODULAR ROOM", bool(spec["annex"]), func() -> void: spec["annex"] = not spec["annex"]; rebuild()]])
	var go := HBoxContainer.new()
	_rows.add_child(go)
	go.add_child(_button("MAKE THE ROOM", false, make))


## One labelled row of toggle buttons, each `[text, pressed, call]`.
func _row(label: String, buttons: Array) -> void:
	var row := HFlowContainer.new()
	_rows.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	for b: Array in buttons:
		row.add_child(_button(b[0], b[1], b[2]))


func _button(text: String, pressed: bool, call: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.toggle_mode = true
	b.button_pressed = pressed
	b.pressed.connect(call)
	return b


## Make the room asked for and go into it: its file is written and the band is taken there. The words
## come back too (what was wrong, or that it is made).
func make() -> String:
	var said := ""
	if studio == null or not Session.is_authority():
		said = HOST_ONLY
	else:
		var made := MadeRooms.make(spec)
		if made["ok"]:
			studio.venue_switch.choose_venue(StringName(made["id"]))
			said = ""
			_panel.visible = false
			Session.notice.emit("Made the room %s." % str(spec["title"]))
		else:
			said = " ".join(made["errors"])
	_status.text = said
	_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	return said
