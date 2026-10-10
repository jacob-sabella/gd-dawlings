class_name WelcomeCard
extends CanvasLayer

## What someone opening dawlings for the first time needs to make a sound, record and play with
## friends, on one card. Shown once, on a sent-out build's first launch (`first_time`), and again
## with F1 whenever it is wanted. A click, Esc or F1 puts it away.
##
## Not shown on runs from the editor, which are the tests', the probes' and the screenshots', unless
## asked for with --welcome.

const SEEN := "user://welcome_seen"
const TEXT := Color(0.92, 0.9, 0.84)
const DIM := Color(0.62, 0.64, 0.68)
const ACCENT := Color(0.88, 0.74, 0.44)

const LINES := [
	["Play the song", "PLAY on the tape deck, to your right. Drag along the top band of the timeline to loop a stretch."],
	["Look and move", "Right-drag looks, WASD walks. F brings you to the gear you are looking at, shift-F back again."],
	["Change things", "Click, drag or scroll any control. Hover over it first to see what it does."],
	["Record", "Press a channel's red key to arm it, then REC on the tape deck."],
	["Your keys and mic", "M opens the session panel: \"Play with the computer keys\", \"Open MIDI\", your microphone."],
	["Play with friends", "M, then \"Host a session\", or type a friend's address and \"Join\". See the README."],
	["Headphones", "H puts them on. Best when you record, so the song does not end up in your microphone."],
]

var _panel: PanelContainer
## Where "seen" is kept; the suite points it elsewhere.
var seen_path := SEEN


## Whether this machine has not seen the card yet.
static func first_time() -> bool:
	return not FileAccess.file_exists(SEEN)


func _ready() -> void:
	layer = 90
	_build()
	visible = false


func open() -> void:
	visible = true


func close() -> void:
	visible = false
	if not FileAccess.file_exists(seen_path):
		var f := FileAccess.open(seen_path, FileAccess.WRITE)
		if f != null:
			f.store_string("1\n")


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_F1:
			if visible:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
		elif visible and key.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
	elif visible and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.085, 0.1, 0.94)
	style.border_color = Color(0.3, 0.31, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	column.add_child(_label("Welcome to dawlings", 26, TEXT))
	column.add_child(_label("A studio you walk around in, with a song already on the desk.", 15, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for line in LINES:
		grid.add_child(_label(line[0], 15, ACCENT))
		var said := _label(line[1], 15, TEXT)
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		said.custom_minimum_size.x = 560
		grid.add_child(said)
	column.add_child(_label("F1 shows this again.  Click or press Esc to start.", 14, DIM))


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l
