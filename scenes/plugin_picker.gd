class_name PluginPicker
extends CanvasLayer

## A searchable list, for choosing one plugin out of however many the DAW offers: the same
## problem NamePrompt solves for a line of free text, but for a pick out of a long list instead.
##
## The rack's own ADD PLUGIN wheel (TabletSelector) is fine for a handful of choices -- the
## built-in engine's own kinds, or a dozen-odd stock Reaper plugins -- and is left exactly as it
## was: scrolling it one at a time still works, still passes the tests built against it. This is
## the FIND button beside it, for when a live Reaper connection has turned that dozen into
## however many VSTs happen to be installed (2026-10-11: "i have so many plugins there needs to
## be a more elegant way to choose a plugin"). Type a few letters, the list narrows, click or
## Enter takes the top match.

signal chosen(id: String)

## Candidates shown at once. The rest are still reachable -- narrowing the search gets them into
## view -- this just keeps one screenful from turning into a scrollbar.
const MAX_SHOWN := 9

var _edit: LineEdit
var _rows: VBoxContainer
var _status: Label
var _choices: Array = []
var _filtered: Array = []
var _highlighted := 0


## `choices` is DAW.state.fx_choices's own shape: Array of [id, label].
static func ask(parent: Node, title: String, choices: Array) -> PluginPicker:
	var p := PluginPicker.new()
	p.layer = 100
	p._choices = choices
	parent.get_tree().root.add_child(p)
	p._build(title)
	return p


func _build(title: String) -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(440, 0)
	box.position = Vector2(-220, -160)
	add_child(box)
	var column := VBoxContainer.new()
	box.add_child(column)
	var label := Label.new()
	label.text = title
	column.add_child(label)
	_edit = LineEdit.new()
	_edit.name = "Search"
	_edit.placeholder_text = "type to search"
	_edit.text_changed.connect(_refilter)
	_edit.text_submitted.connect(func(_t): _choose(_highlighted))
	# Up and down move the highlight from the search box itself: it has the keys, and a LineEdit
	# takes them for its caret, so they never reached `_unhandled_input`.
	_edit.gui_input.connect(_on_search_key)
	column.add_child(_edit)
	_rows = VBoxContainer.new()
	column.add_child(_rows)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_status)
	var hint := Label.new()
	hint.text = "↑↓ to pick, Enter to add, Escape to leave it"
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)
	_refilter("")
	_edit.grab_focus.call_deferred()


func _refilter(query: String) -> void:
	var q := query.strip_edges().to_lower()
	_filtered = _choices if q.is_empty() else _choices.filter(
			func(c): return str(c[1]).to_lower().contains(q))
	_highlighted = 0
	_redraw()


func _redraw() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var shown := mini(_filtered.size(), MAX_SHOWN)
	for i in shown:
		var row := Button.new()
		row.text = str(_filtered[i][1])
		row.flat = i != _highlighted
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(_choose.bind(i))
		# The highlight only: rebuilding the rows here made a new button under the mouse, which
		# entered it again, every frame, and a click could land on one already gone.
		row.mouse_entered.connect(func(): _highlighted = i; _light())
		_rows.add_child(row)
	if _filtered.is_empty():
		_status.text = "no match"
	elif _filtered.size() > MAX_SHOWN:
		_status.text = "+ %d more — keep typing to narrow it down" % (_filtered.size() - shown)
	else:
		_status.text = ""


## The highlighted row lit, the rest flat, without making them again.
func _light() -> void:
	var rows := _rows.get_children().filter(func(n): return not n.is_queued_for_deletion())
	for i in rows.size():
		(rows[i] as Button).flat = i != _highlighted


func _choose(i: int) -> void:
	if i >= 0 and i < _filtered.size():
		chosen.emit(str(_filtered[i][0]))
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
	elif _step(event):
		get_viewport().set_input_as_handled()


func _on_search_key(event: InputEvent) -> void:
	if _step(event):
		_edit.accept_event()


## Up or down (held, it repeats) moves the highlight one row; true if it was one of those.
func _step(event: InputEvent) -> bool:
	var by := 0
	if event.is_action_pressed("ui_down", true):
		by = 1
	elif event.is_action_pressed("ui_up", true):
		by = -1
	if by == 0:
		return false
	if not _filtered.is_empty():
		move_highlight(by)
	return true


func move_highlight(by: int) -> void:
	_highlighted = clampi(_highlighted + by, 0, mini(_filtered.size(), MAX_SHOWN) - 1)
	_light()
