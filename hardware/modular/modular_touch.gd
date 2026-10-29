class_name ModularTouch
extends ControlAffordance

## One plate of the modular's touch keys (ModularWall, docs/spatial_loop.md part two, slice 51): a
## row of thirteen on the keyboard stand's deck under the wall, an octave from C, so a player with no
## keyboard to hand plays the modular with a fingertip, a controller or a click. Pressed is a note
## down on this player's keys (the wall says it, `ModularWall.touched`), let go the note up. The wheel
## over a plate moves the row an octave.

signal pressed(pitch: int, down: bool)
signal octave_asked(by: int)

const NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## The semitone above the row's C this plate plays, and the row's C now (the wall's).
var step := 0
var base := 48
var size := Vector2(0.08, 0.2)
## The cap's height (m), its letters' height and how far they lean back from upright (degrees).
const CAP := 0.008
const LETTER := 0.016
const LEAN := 55.0

var _cap: MeshInstance3D
var _paint := StandardMaterial3D.new()
var _name: Label3D
var _down := -1


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var black: bool = (NAMES[step % 12] as String).ends_with("#")
	_cap = MeshInstance3D.new()
	_cap.name = "Cap"
	var box := BoxMesh.new()
	box.size = Vector3(size.x - 0.006, CAP, size.y)
	_cap.mesh = box
	_cap.position = Vector3(0, CAP * 0.5, 0)
	_paint.albedo_color = Color(0.13, 0.13, 0.14) if black else Color(0.74, 0.72, 0.66)
	_paint.roughness = 0.55
	_cap.material_override = _paint
	add_child(_cap)
	_name = Label3D.new()
	_name.name = "Name"
	_name.pixel_size = 0.0002
	_name.font_size = roundi(LETTER / _name.pixel_size)
	_name.modulate = Color(0.9, 0.88, 0.82) if black else Color(0.1, 0.09, 0.08)
	# Leant back on the cap at its near end, read from in front of it and above: its lower edge
	# stood on the cap's top, so none of the letter is inside it, and on the cap, so it goes down
	# with the press.
	_name.rotation_degrees = Vector3(-LEAN, 0, 0)
	_name.position = Vector3(0, CAP * 0.5 + letter_rise(), size.y * 0.5 - 0.022)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.double_sided = false
	Lettering.range_to_legibility(_name)
	_cap.add_child(_name)
	_say()
	var shape := CollisionShape3D.new()
	var hit := BoxShape3D.new()
	hit.size = Vector3(size.x, 0.02, size.y)
	shape.shape = hit
	shape.position = Vector3(0, 0.01, 0)
	add_child(shape)


## How far above the cap's top a letter's middle is (m): half its line (its glyphs and the font's
## room above and below them, about 1.2 of its size), leant back LEAN, and a millimetre clear.
static func letter_rise() -> float:
	return LETTER * 0.6 * cos(deg_to_rad(LEAN)) + 0.001


## Where the cap's top is now, in the plate's frame (m): lower while it is pressed.
func cap_top() -> float:
	return _cap.position.y + CAP * 0.5 if _cap != null else CAP


func pitch() -> int:
	return base + step


func set_base(to: int) -> void:
	base = to
	_say()


func _say() -> void:
	if _name == null:
		return
	var n := pitch()
	_name.text = "%s%d" % [NAMES[n % 12], n / 12 - 1] if step % 12 == 0 else NAMES[n % 12]


func _on_grab_begin(_at: Vector3) -> void:
	_down = pitch()
	_cap.position.y = 0.001
	pressed.emit(_down, true)


func _on_grab_end() -> void:
	_cap.position.y = CAP * 0.5
	if _down >= 0:
		pressed.emit(_down, false)
	_down = -1


func _on_nudge(notches: int, _fine: bool) -> bool:
	octave_asked.emit(signi(notches))
	return true


func personal() -> bool:
	return true


func _default_title() -> String:
	return "MODULAR  TOUCH KEYS"


func _default_readout() -> String:
	var n := pitch()
	return "%s%d" % [NAMES[n % 12], n / 12 - 1]


func hint() -> String:
	return "press to play the modular through your keys · the wheel moves the row an octave"
