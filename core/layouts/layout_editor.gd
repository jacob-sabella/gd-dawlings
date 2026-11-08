class_name LayoutEditor
extends CanvasLayer

## The room's edit mode (docs/layouts.md 7): a small plain panel the host opens and closes with F3, beside
## the StageManager (Tab). Mouse and keys, so it is not VR-only; in a headset the same verb is `ask_layout`.
## It lists the pieces the room stands, nudges and turns the one picked, takes it out or resets it, adds a
## piece from `PieceCatalogue` a little ahead of the walker (and lists the pieces the room lacks, to put each
## back where the layout stands it), resets the whole room, and shows in one
## line what the host's validator said to the last thing asked. It holds nothing: every button is one
## `studio.ask_layout(...)`, and the room is saved by `RoomDeltas` as ever. A guest sees only that the
## host arranges the room.

const TOGGLE_KEY := KEY_F3
## One nudge, in metres, and one turn, in degrees.
const STEP := 0.1
const TURN := 15.0
## How far ahead of the walker an added piece is put, in metres.
const AHEAD := 1.5

var studio: Studio

var _panel: PanelContainer
var _rows: VBoxContainer
var _status: Label
var _picked: StringName = &""


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 44)
	_panel.visible = false
	PanelLook.solid(_panel)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ARRANGE THE ROOM  -  F3 to close"
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


## Whether the panel is showing.
func is_open() -> bool:
	return _panel != null and _panel.visible


## Open or close it. A guest gets the notice in place of the controls.
func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		if not Session.is_authority():
			Session.notice.emit(LayoutEdit.HOST_ONLY)
			_panel.visible = false
			return
		rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()


## Rebuilt after every edit: the pieces change with it.
func rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if studio == null:
		return
	var here := RoomFloor.room_pieces(studio).filter(func(t: Trolley) -> bool: return t.visible)
	if _picked == &"" or not here.any(func(t: Trolley) -> bool: return t.piece_id == _picked):
		_picked = here[0].piece_id if not here.is_empty() else &""
	var list := HFlowContainer.new()
	_rows.add_child(list)
	for t: Trolley in here:
		list.add_child(_button(LayoutChecks.name_of(t.piece_id).to_upper(), func() -> void: _pick(t.piece_id), t.piece_id == _picked))
	if _picked != &"":
		_controls()
	var edit: LayoutEdit = studio.layout_edit
	var back := edit.missing()
	if not back.is_empty():
		var puts := HFlowContainer.new()
		puts.name = "PutBack"
		_rows.add_child(puts)
		var put_label := Label.new()
		put_label.text = "put back"
		puts.add_child(put_label)
		for kind in back:
			puts.add_child(_button("+ " + PieceCatalogue.title(kind), func() -> void: _put_back(kind)))
	var adds := HFlowContainer.new()
	adds.name = "Adds"
	_rows.add_child(adds)
	var label := Label.new()
	label.text = "add"
	adds.add_child(label)
	for kind in edit.addable().filter(func(k: StringName) -> bool: return k not in back):
		adds.add_child(_button("+ " + PieceCatalogue.title(kind), func() -> void: _add(kind)))
	adds.add_child(_button("RESET ROOM", func() -> void: _ask("reset", ["all"])))


func _controls() -> void:
	var row := HFlowContainer.new()
	_rows.add_child(row)
	for step: Array in [["<", -STEP, 0.0], [">", STEP, 0.0], ["^ away", 0.0, -STEP], ["v near", 0.0, STEP]]:
		row.add_child(_button(step[0], func() -> void: _nudge(step[1], step[2])))
	row.add_child(_button("TURN L", func() -> void: _turn(-TURN)))
	row.add_child(_button("TURN R", func() -> void: _turn(TURN)))
	row.add_child(_button("REMOVE", func() -> void: _ask("remove", [String(_picked)])))
	row.add_child(_button("RESET", func() -> void: _ask("reset", [String(_picked)])))


func _button(text: String, call: Callable, pressed := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	PanelLook.button(b)
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.pressed.connect(call)
	return b


func _pick(id: StringName) -> void:
	_picked = id
	rebuild()


func _nudge(dx: float, dz: float) -> void:
	var t := studio.room_rows._floor_piece(_picked)
	if t != null:
		_ask("move", [String(_picked), t.position.x + dx, t.position.z + dz, t.rotation.y])


func _turn(degrees: float) -> void:
	var t := studio.room_rows._floor_piece(_picked)
	if t != null:
		_ask("rotate", [String(_picked), t.rotation.y + deg_to_rad(degrees)])


## A piece the room lacks goes back where the room's layout stands it.
func _put_back(kind: StringName) -> void:
	_ask("add", [String(kind)])


func _add(kind: StringName) -> void:
	var at := Vector3.ZERO
	var yaw := 0.0
	if studio.walker != null:
		var f := -studio.walker.global_transform.basis.z
		f.y = 0.0
		at = studio.walker.global_position + f.normalized() * AHEAD
		yaw = atan2(-f.x, -f.z)
	_ask("add", [String(kind), at.x, at.z, yaw])


## One ask, then what the validator said, or that it was done.
func _ask(op: String, args: Array) -> void:
	var why := studio.rack_host.ask_layout(op, args)
	_status.text = why if why != "" else "Done: %s." % op
	_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5) if why != "" else Color(0.6, 0.9, 0.7))
	rebuild()
