class_name TypingPad
extends Node3D

## A line of text typed on keys in the room, for where there is no keyboard: a headset. The
## same answer as NamePrompt -- `answered` with the text on OK, nothing if it is left -- on the
## desk's own keys, pressed by hand as any other is.
##
## Four rows of letters and digits, and a row of SHIFT, SPACE, a few marks, DEL, LEAVE and OK.
## The text it starts with is taken whole by the first key, as a selected name is by typing over
## it; DEL first clears it. SHIFT capitalises the next letter, and is on for the first.

signal answered(text: String)

const PITCH := 0.026
const ROW_PITCH := 0.03
const MAX_LENGTH := NamePrompt.MAX_LENGTH
const ROWS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-.&"]
const CAPTION := Color(0.62, 0.64, 0.68)
const TEXT := Color(0.95, 0.93, 0.85)

var text := ""
## The starting text is taken whole by the first key.
var replacing := true
var shift := true

var _title := ""
var _readout: Label3D
var _shift_key: PanelButton
## Every key by what it types, or by its name for the ones that do something else.
var keys := {}


## A pad under `parent`, at `where` in the parent's space, asking for `title`.
static func ask(parent: Node3D, title: String, current: String, where: Transform3D) -> TypingPad:
	var pad := TypingPad.new()
	pad.name = "TypingPad"
	pad._title = title
	pad.text = current.left(MAX_LENGTH)
	pad.transform = where
	parent.add_child(pad)
	return pad


func _ready() -> void:
	var width := ROWS[0].length() * PITCH
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	# From under the bottom row's captions to over the title.
	var top := (ROWS.size() * 0.5 + 0.9) * ROW_PITCH + 0.018
	var foot := (ROWS.size() * 0.5 - 1 - ROWS.size()) * ROW_PITCH - 0.02
	box.size = Vector3(width + 0.016, top - foot, 0.004)
	plate.mesh = box
	plate.material_override = Materials.chassis()
	plate.position = Vector3(0, (top + foot) * 0.5, -0.003)
	add_child(plate)
	var title := _label(_title, 22, CAPTION)
	title.position = Vector3(-width * 0.5, (ROWS.size() * 0.5 + 0.9) * ROW_PITCH + 0.008, 0.0016)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(title)
	_readout = _label("", 30, TEXT)
	_readout.position = Vector3(-width * 0.5, (ROWS.size() * 0.5 + 0.1) * ROW_PITCH + 0.006, 0.0016)
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_readout)
	for r in ROWS.size():
		var row: String = ROWS[r]
		for c in row.length():
			var ch := row[c]
			var at := Vector3((c - (row.length() - 1) * 0.5) * PITCH, (ROWS.size() * 0.5 - 1 - r) * ROW_PITCH, 0.0)
			keys[ch] = _key("Key" + str(ch.unicode_at(0)), ch, at, Color(0.85, 0.85, 0.8), _type.bind(ch))
	var bottom := (ROWS.size() * 0.5 - 1 - ROWS.size()) * ROW_PITCH
	_shift_key = _key("Shift", "SHIFT", Vector3(-4.5 * PITCH, bottom, 0), Color(0.95, 0.75, 0.35), _shift)
	keys["SHIFT"] = _shift_key
	keys[" "] = _key("Space", "SPACE", Vector3(-2.5 * PITCH, bottom, 0), Color(0.85, 0.85, 0.8), _type.bind(" "))
	keys["DEL"] = _key("Delete", "DEL", Vector3(0.5 * PITCH, bottom, 0), Color(0.95, 0.38, 0.34), _delete)
	keys["LEAVE"] = _key("Leave", "LEAVE", Vector3(2.5 * PITCH, bottom, 0), Color(0.6, 0.6, 0.65), leave)
	keys["OK"] = _key("Ok", "OK", Vector3(4.5 * PITCH, bottom, 0), Color(0.45, 0.85, 0.5), finish)
	_show()


func _key(key_name: String, caption: String, at: Vector3, colour: Color, act: Callable) -> PanelButton:
	var key := PanelButton.new()
	key.name = key_name
	key.led_colour = colour
	key.lamp_scale = Vector2(0.8, 0.5)
	key.scale = Vector3(1.4, 1.4, 1.4)
	key.position = at
	key.lit = true
	key.pressed.connect(act)
	key.describe_title = func() -> String: return caption if caption.length() > 1 else "TYPE  " + caption
	key.describe_value = func(_v: float) -> String: return _title
	add_child(key)
	var l := _label(caption, 26 if caption.length() == 1 else 18, CAPTION)
	l.position = at + Vector3(0, -0.0105, 0.0016)
	add_child(l)
	return key


func _label(content: String, size: int, tint: Color) -> Label3D:
	var l := Label3D.new()
	l.text = content
	l.font_size = size * 4
	l.pixel_size = 0.000055
	l.modulate = tint
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l


func _type(ch: String) -> void:
	if replacing:
		text = ""
		replacing = false
	if text.length() >= MAX_LENGTH:
		return
	# The rows are drawn in capitals, as keys are; a letter is small unless shifted.
	text += ch.to_upper() if shift else ch.to_lower()
	if ch != " ":
		shift = false
	_show()


func _shift() -> void:
	shift = not shift
	_show()


func _delete() -> void:
	if replacing:
		text = ""
		replacing = false
	else:
		text = text.left(text.length() - 1)
	if text.is_empty():
		shift = true
	_show()


## Answers the text, unless there is none, and goes.
func finish() -> void:
	var said := text.strip_edges()
	if not said.is_empty():
		answered.emit(said)
	queue_free()


func leave() -> void:
	queue_free()


func _show() -> void:
	_readout.text = (text if not text.is_empty() else " ") + ("" if replacing else "_")
	_readout.modulate = TEXT if not replacing else Color(TEXT, 0.6)
	_shift_key.lit = shift
