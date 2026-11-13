class_name AssistantScreen
extends CanvasLayer

## The assistant's overlay (docs/mcp_assistant.md): F10 from anywhere, or the ASK key on its wall station. A transcript
## of what was asked and what the assistant did (each tool call a row), a line to ask on, SEND, CANCEL (the run
## that is yours, or any if you are the host), NEW CHAT, and the confirm cards for anything destructive it wants
## to do: ALLOW or DENY. It changes nothing itself: everything goes through `Assistant`.

const _TEXT := Color(0.9, 0.92, 0.95)
const _DIM := Color(0.62, 0.68, 0.78)
const _HEAD := Color(1.0, 0.86, 0.5)
const _GOOD := "8fe3a0"
const _BAD := "ff8a70"
const _ASK := "ffdb80"
const _TOOL := "9db4d6"
const RUNS_SHOWN := 8

var assistant: Assistant
var _panel: PanelContainer
var _status: Label
var _log: RichTextLabel
var _scroll: ScrollContainer
var _input: LineEdit
var _cards: VBoxContainer
var _send: Button
var _cancel: Button
var _stick := true


func _ready() -> void:
	layer = 11
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
	title.text = "ASSISTANT"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _HEAD)
	head.add_child(title)
	_status = Label.new()
	_status.add_theme_color_override("font_color", _DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_status)
	var fresh := Button.new()
	fresh.text = "NEW CHAT"
	PanelLook.button(fresh)
	fresh.tooltip_text = "Clear the conversation and start a fresh one (a run still going stays: CANCEL stops it)."
	fresh.pressed.connect(func() -> void: assistant.new_conversation(); _redraw())
	head.add_child(fresh)
	var close := Button.new()
	close.text = "CLOSE  (Esc)"
	PanelLook.button(close)
	close.pressed.connect(close_screen)
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = false
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_size_override("bold_font_size", 15)
	_scroll.add_child(_log)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 6)
	column.add_child(_cards)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_input = LineEdit.new()
	_input.max_length = Session.ASSISTANT_ASK_MAX
	_input.placeholder_text = "Ask about the room, or ask for a change: \"put a slow tremolo on the pad\"  (Enter sends)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t: String) -> void: _on_send())
	row.add_child(_input)
	_send = Button.new()
	_send.text = "SEND"
	PanelLook.button(_send)
	_send.pressed.connect(_on_send)
	row.add_child(_send)
	_cancel = Button.new()
	_cancel.text = "CANCEL"
	PanelLook.button(_cancel)
	_cancel.pressed.connect(_on_cancel)
	row.add_child(_cancel)
	get_viewport().size_changed.connect(_fit)
	_fit()
	if assistant != null:
		assistant.changed.connect(_redraw)


func is_open() -> bool:
	return _panel != null and _panel.visible


func open_screen() -> void:
	if _panel == null:
		return
	_panel.visible = true
	_fit()
	_redraw()
	_input.grab_focus()


func close_screen() -> void:
	if _panel != null:
		_panel.visible = false
		_input.release_focus()


func toggle() -> void:
	if is_open():
		close_screen()
	else:
		open_screen()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_screen()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := minf(860.0, vp.x - 40.0)
	var h := minf(vp.y - 80.0, 820.0)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)


func _on_send() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		return
	_input.clear()
	assistant.ask(text)


func _on_cancel() -> void:
	var mine := mine_running()
	if mine != 0:
		assistant.cancel(mine)


## The id of the newest run that is running or waiting and that this machine may cancel (its own, or any on the host).
func mine_running() -> int:
	for i in range(assistant.runs.size() - 1, -1, -1):
		var r: Dictionary = assistant.runs[i]
		if r["status"] in [Assistant.RUNNING, Assistant.QUEUED] and (Session.is_authority() or int(r["peer"]) == Session.local_peer_id):
			return int(r["id"])
	return 0


## What the status line says: who runs it and whether it can.
func status_text() -> String:
	if Session.is_authority():
		var why := []
		if not assistant.can_run(why):
			return str(why[0])
		return "runs here · answers as whoever asks"
	return "runs on the host's machine · it sees the host's room"


func _redraw() -> void:
	if _panel == null or not _panel.visible:
		return
	_status.text = status_text()
	_log.text = transcript_bbcode()
	_stick = _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y - 40)
	if _stick:
		_scroll.call_deferred("set", "scroll_vertical", 100000)
	_cancel.disabled = mine_running() == 0
	for c in _cards.get_children():
		c.queue_free()
	for card: Dictionary in assistant.cards.values():
		if card["done"] or not (Session.is_authority() or int(card["who"]) == Session.local_peer_id):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = "%s?  %s" % [str(card["tool"]), AssistantStream.row("", card["args"]).strip_edges()]
		l.add_theme_color_override("font_color", _HEAD)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		for yes in [true, false]:
			var b := Button.new()
			b.text = "ALLOW" if yes else "DENY"
			PanelLook.button(b)
			b.pressed.connect(func() -> void: assistant.answer(int(card["id"]), yes))
			row.add_child(b)
		_cards.add_child(row)


## The conversation as BBCode: newest runs, each with what was asked and what the assistant did.
func transcript_bbcode() -> String:
	var out := ""
	var first := maxi(0, assistant.runs.size() - RUNS_SHOWN)
	if assistant.runs.is_empty():
		return "[color=#%s]Nothing asked yet. Ask about the room (\"what is on the drum bus?\") or for a change (\"mute the hats and add a reverb to the snare\").[/color]" % "9db4d6"
	for i in range(first, assistant.runs.size()):
		var r: Dictionary = assistant.runs[i]
		out += "[color=#%s][b]%s:[/b] %s[/color]\n" % [_ASK, _e(str(r["who"])), _e(str(r["text"]))]
		for ev: Dictionary in r["events"]:
			var kind := str(ev["kind"])
			match kind:
				"say", "result":
					out += _e(str(ev["text"])) + "\n"
				"tool":
					out += "[color=#%s]  › %s[/color]\n" % [_TOOL, _e(str(ev["text"]))]
				"tool_result":
					if not bool(ev.get("ok", true)):
						out += "[color=#%s]    refused: %s[/color]\n" % [_BAD, _e(str(ev["text"]))]
				"error":
					out += "[color=#%s]%s[/color]\n" % [_BAD, _e(str(ev["text"]))]
				"confirm", "confirmed":
					out += "[color=#%s]  ? %s[/color]\n" % [_HEAD.to_html(false), _e(str(ev["text"]))]
		match str(r["status"]):
			"queued":
				out += "[color=#%s]  waiting for its turn...[/color]\n" % _TOOL
			"running":
				out += "[color=#%s]  working...[/color]\n" % _TOOL
			"cancelled":
				out += "[color=#%s]  cancelled[/color]\n" % _BAD
		out += "\n"
	return out


static func _e(s: String) -> String:
	return s.replace("[", "[lb]")
