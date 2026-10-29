class_name NamePrompt
extends CanvasLayer

## A line of text asked for on the monitor: a name typed, Enter to keep it, Escape to leave it.
## For what a desk cannot spell out with its keys, like a track's name.

const MAX_LENGTH := 64

signal answered(text: String)

var _edit: LineEdit


## Opens over everything with `current` in the box, selected so typing replaces it. `answered` is
## emitted with the text on Enter, and not at all if it is left. `limit` is the most it takes: a
## name's MAX_LENGTH unless said (a Workshop request is a sentence, and its box is wider).
static func ask(parent: Node, title: String, current: String, limit := MAX_LENGTH) -> NamePrompt:
	var p := NamePrompt.new()
	p.layer = 100
	parent.get_tree().root.add_child(p)
	p._build(title, current, limit)
	return p


func _build(title: String, current: String, limit := MAX_LENGTH) -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	var wide := 420 if limit <= MAX_LENGTH else 760
	box.custom_minimum_size = Vector2(wide, 0)
	box.position = Vector2(-wide * 0.5, -48)
	add_child(box)
	var column := VBoxContainer.new()
	box.add_child(column)
	var label := Label.new()
	label.text = title
	column.add_child(label)
	_edit = LineEdit.new()
	_edit.name = "Name"
	_edit.text = current
	_edit.max_length = limit
	_edit.select_all_on_focus = true
	_edit.text_submitted.connect(func(text: String):
		answered.emit(text.strip_edges())
		queue_free())
	column.add_child(_edit)
	var hint := Label.new()
	hint.text = "Enter to keep, Escape to leave it"
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)
	_edit.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
