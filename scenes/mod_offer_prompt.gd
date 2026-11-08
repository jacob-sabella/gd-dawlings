class_name ModOfferPrompt
extends VBoxContainer

## The guest's accept / decline prompt for a mod the host offers (`ModSend`, docs/mods.md section 13), a block of
## the session panel. Each waiting offer is a card naming the mod, its version, licence and size, with ACCEPT and
## DECLINE; one being received shows how far it is; the last few that finished or failed say so. Empty (and
## hidden) for a host, a solo player and a guest with nothing offered.

const INK := Color(0.86, 0.89, 0.93)
const DIM := Color(0.56, 0.60, 0.67)
const WARN := Color(1.0, 0.62, 0.55)
const CARD := Color(0.10, 0.11, 0.135)
const ACCENT := Color(0.92, 0.6, 0.25)
## How many finished cards stay below the waiting ones.
const KEEP_DONE := 3

var _send: ModSend


func _init(send: ModSend = null) -> void:
	name = "ModOffers"
	add_theme_constant_override("separation", 8)
	_send = send
	visible = false


## The send node the prompt reads (the session's), when it was not given at construction.
func bind(send: ModSend) -> void:
	_send = send
	refresh()


## Whether an offer is waiting for the player's answer.
func has_pending() -> bool:
	return _send != null and not _send.pending().is_empty()


## Draws the cards again from the inbox.
func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var shown: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	if _send != null:
		for e in _send.inbox:
			if e["state"] in [ModSend.OFFERED, ModSend.RECEIVING]:
				shown.append(e)
			elif e["state"] in [ModSend.INSTALLED, ModSend.FAILED]:
				done.append(e)
	shown.append_array(done.slice(maxi(done.size() - KEEP_DONE, 0)))
	visible = not shown.is_empty()
	if shown.is_empty():
		return
	add_child(_text("MODS FROM THE HOST", 11, DIM))
	for e in shown:
		add_child(_card(e))


func _card(e: Dictionary) -> Control:
	var meta: Dictionary = e["meta"]
	var panel := PanelContainer.new()
	panel.name = "Offer_%s" % str(meta["id"]).replace(".", "_")
	panel.add_theme_stylebox_override("panel", _box(CARD, 8, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var title := "%s offers the mod %s" % [Session.name_of(int(e["peer"])), str(meta["name"]).to_upper()] if e["state"] == ModSend.OFFERED \
			else str(meta["name"]).to_upper()
	col.add_child(_text(title, 14, INK))
	col.add_child(_text("%s  %s  ·  licence %s  ·  %s, %d %s" % [meta["id"], meta["version"], meta["licence"],
			size_words(int(meta["size"])), int(meta["count"]), "file" if int(meta["count"]) == 1 else "files"], 12, DIM))
	match e["state"]:
		ModSend.OFFERED:
			col.add_child(_text("Data only: a patch and a look, no code. Decline and its plates stay unavailable; you still hear the host.", 12, DIM))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var accept := _button("ACCEPT", true)
			accept.name = "Accept"
			accept.pressed.connect(func() -> void: _answer(e, true))
			var decline := _button("DECLINE", false)
			decline.name = "Decline"
			decline.pressed.connect(func() -> void: _answer(e, false))
			row.add_child(accept)
			row.add_child(decline)
			col.add_child(row)
		ModSend.RECEIVING:
			var bar := ProgressBar.new()
			bar.name = "Progress"
			bar.max_value = float(meta["size"])
			bar.value = float(e["got"])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 8)
			col.add_child(bar)
			col.add_child(_text("Receiving %s of %s" % [size_words(int(e["got"])), size_words(int(meta["size"]))], 12, DIM))
		ModSend.INSTALLED:
			col.add_child(_text("Installed. Its plates are live.", 12, Color(0.6, 0.9, 0.65)))
		ModSend.FAILED:
			col.add_child(_text("Not installed: %s" % e["why"], 12, WARN))
	return panel


func _answer(e: Dictionary, yes: bool) -> void:
	if _send == null:
		return
	if yes:
		_send.accept(int(e["offer"]))
	else:
		_send.decline(int(e["offer"]))
	refresh()


## A byte count in words: "812 B", "3.4 KB", "1.2 MB".
static func size_words(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)


func _text(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	var base := ACCENT if primary else Color(0.15, 0.16, 0.19)
	var ink := Color(0.08, 0.06, 0.04) if primary else INK
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ink)
	b.add_theme_stylebox_override("normal", _box(base, 8, 12))
	b.add_theme_stylebox_override("hover", _box(base.lightened(0.12), 8, 12))
	b.add_theme_stylebox_override("pressed", _box(base.darkened(0.15), 8, 12))
	return b


func _box(colour: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad * 0.6
	box.content_margin_bottom = pad * 0.6
	box.anti_aliasing = true
	return box
