class_name RealmLeavePrompt
extends CanvasLayer

## Asked before leaving home for someone else's realm (docs/realms.md, step 2), when there is something to lose:
## changes to the song no save has kept, or visitors who would be sent home. SAVE AND GO keeps the song first (and
## stays if it cannot be kept), GO WITHOUT SAVING leaves the changes behind (home opens the song as it was last
## saved), STAY goes nowhere. Escape is STAY.
##
## `RealmLeavePrompt.leave_home(parent, where, go)` is the whole of it: it asks only when it must, sets home aside
## (Session.home) and then calls `go`.

signal answered(choice: StringName)

const SAVE := &"save"
const DISCARD := &"discard"
const STAY := &"stay"

const _HEAD := Color(1.0, 0.86, 0.5)
const _DIM := Color(0.62, 0.68, 0.78)
const _REFUSED := Color(1.0, 0.5, 0.42)

var _panel: PanelContainer
var _title: Label
var _said: Label
var _status: Label
var _save: Button
var _discard: Button
var _stay: Button
## What GO does once home is set aside.
var _go := Callable()


## Leaves home for `where` (words: "Ada's realm"), asking first when there is something to lose. `go` does the
## leaving. In a headset there is no screen to ask on: unsaved changes are refused with a notice instead.
static func leave_home(parent: Node, where: String, go: Callable) -> void:
	if not RealmHome.needs_asking():
		Session.home.set_aside()
		go.call()
		return
	if parent.get_viewport() != null and parent.get_viewport().use_xr and RealmHome.before_leaving()["unsaved"]:
		Session.notice.emit("Save your song first: it has changes no save has kept.")
		return
	var prompt: RealmLeavePrompt = null
	for c in parent.get_children():
		if c is RealmLeavePrompt:
			prompt = c
	if prompt == null:
		prompt = RealmLeavePrompt.new()
		prompt.name = "RealmLeavePrompt"
		parent.add_child(prompt)
	prompt.open(where, go)


func _ready() -> void:
	layer = 30
	_panel = PanelContainer.new()
	_panel.visible = false
	PanelLook.solid(_panel)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", _HEAD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	_said = Label.new()
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_said.add_theme_color_override("font_color", _DIM)
	column.add_child(_said)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	_save = _button("SAVE AND GO", row, func() -> void: choose(SAVE))
	_discard = _button("GO WITHOUT SAVING", row, func() -> void: choose(DISCARD))
	_stay = _button("STAY", row, func() -> void: choose(STAY))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", _REFUSED)
	column.add_child(_status)
	get_viewport().size_changed.connect(_fit)
	_panel.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)


func _button(text: String, row: HBoxContainer, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 44)
	PanelLook.button(b)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(pressed)
	row.add_child(b)
	return b


## Shows the question for leaving home for `where`; `go` is called if the player goes.
func open(where: String, go: Callable) -> void:
	_go = go
	var b := RealmHome.before_leaving()
	var guests := int(b["guests"])
	var lines := PackedStringArray()
	if b["unsaved"]:
		_title.text = "\"%s\" has changes no save has kept" % b["title"]
		lines.append("Going to %s puts your song away until you come home. Save it now to have it back as it is; go without saving and it comes back as it was last saved%s." % [
				where, "" if str(b["file"]) != "" else " (never, so you will start a new one)"])
	else:
		_title.text = "Leave for %s?" % where
	if guests > 0:
		lines.append("Your realm closes while you are away, so %s home." % [
				"your visitor goes" if guests == 1 else "your %d visitors go" % guests])
	_said.text = "\n\n".join(lines)
	_save.visible = b["unsaved"]
	_discard.text = "GO WITHOUT SAVING" if b["unsaved"] else "GO"
	_status.text = ""
	_status.visible = false
	_panel.visible = true
	_fit()
	(_save if b["unsaved"] else _discard).grab_focus()


func is_open() -> bool:
	return _panel != null and _panel.visible


func choose(choice: StringName) -> void:
	if not is_open():
		return
	if choice == SAVE:
		var why := RealmHome.save_home()
		if why != "":
			_status.text = "Not kept, so you have not gone: %s." % why
			_status.visible = true
			_fit()
			return
	_panel.visible = false
	answered.emit(choice)
	if choice == STAY:
		return
	Session.home.set_aside()
	var go := _go
	_go = Callable()
	if go.is_valid():
		go.call()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		choose(STAY)


func _fit() -> void:
	if _panel != null and _panel.visible:
		# As wide as 620 allows; as tall as what it says (no room kept for an empty status line).
		var vp := _panel.get_viewport_rect().size
		_panel.custom_minimum_size = Vector2(minf(620.0, vp.x - 40.0), 0)
		_panel.size = Vector2.ZERO
		_panel.position = ((vp - _panel.size) * 0.5).max(Vector2(10, 10))
