class_name NotePad
extends ControlAffordance

## A pad of sticky notes on the side table by the seat, or at the console's left end in AR, where there is
## no wing (docs/spatial_loop.md part two, slice 35): take a note off it and stick it on the
## timeline's ruler or a lane, or the miniature's bed, and the song time there is where it goes; then its words are typed (TypingPad in a headset, NamePrompt at a
## desk) and it is a `NOTE ` marker (Harmony.NOTE_PREFIX), which everyone sees on their ruler.
##
## Grabbed, a note card rides the hand's ray -- on whatever the ray is on, or out in front of the
## hand -- and let go, `stuck` says what the ray was on and where. What that means as a time is the
## studio's to say (PointAndMark), so the pad knows nothing about the song or the session: a desk's
## prop, like the typing pad. A mouse drags it the same way, from the pad onto the ruler; O does it
## in one key over the ruler.

## The pad was let go with its card on `control` at `point` (global): stick a note there.
## `by` is the hand that carried it. Not emitted for a let-go over nothing, or over the pad.
signal stuck(by: Node, control: ControlAffordance, point: Vector3)

## The pad, a square block of paper, and its card as carried: a sheet off the top of it.
const SIZE := Vector3(0.076, 0.014, 0.076)
const CARD := Vector2(0.06, 0.045)
## How far out in front of the hand the card rides over nothing, along its ray (m).
const CARRY_OUT := 0.32
## How far off the face it lands on the card is held, so it is seen on it rather than in it (m).
const CARD_OFF := 0.006
const PAPER := Color(0.96, 0.92, 0.55)
const EDGE := Color(0.80, 0.75, 0.40)
const INK := Color(0.16, 0.14, 0.09)

## The card the hand carries, while it does: top level, so it goes where the ray does.
var card: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var block := MeshInstance3D.new()
	block.name = "Block"
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	block.mesh = mesh
	block.position = Vector3(0, SIZE.y * 0.5, 0)
	block.material_override = _paper(EDGE)
	add_child(block)
	# The top sheet, a shade lighter, with what it is for lettered on it.
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	var top := BoxMesh.new()
	top.size = Vector3(SIZE.x, 0.0015, SIZE.z)
	sheet.mesh = top
	sheet.position = Vector3(0, SIZE.y + 0.00075, 0)
	sheet.material_override = _paper(PAPER)
	add_child(sheet)
	var words := Label3D.new()
	words.name = "Words"
	words.text = "NOTES\ndrag one onto\nthe ruler"
	words.font_size = 40
	words.pixel_size = 0.00028
	words.modulate = INK
	words.outline_size = 0
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.rotation = Vector3(-PI * 0.5, 0, 0)
	words.position = Vector3(0, SIZE.y + 0.0017, 0)
	Lettering.range_to_legibility(words)
	add_child(words)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE + Vector3(0.01, 0.01, 0.01)
	shape.shape = box
	shape.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(shape)
	card = MeshInstance3D.new()
	card.name = "Card"
	var face := BoxMesh.new()
	face.size = Vector3(CARD.x, CARD.y, 0.001)
	card.mesh = face
	card.material_override = _paper(PAPER)
	card.top_level = true
	card.visible = false
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	describe_title = func() -> String: return "NOTE PAD"
	describe_value = func(_v: float) -> String: return "a sticky note for a song time, everyone's"


func hint() -> String:
	return "drag a note onto the ruler, a lane or the miniature, then type it; O over the ruler at a desk"


static func _paper(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m


func _on_grab_begin(_at: Vector3) -> void:
	card.visible = true
	_carry()


func _on_grab_end() -> void:
	var by := held_by
	card.visible = false
	if by == null:
		return
	var on := by.get("hovered") as ControlAffordance
	if on == null or on == self or not is_instance_valid(on):
		return
	stuck.emit(by, on, by.get("hover_point"))


func _process(_delta: float) -> void:
	if held_by != null and is_instance_valid(held_by):
		_carry()


## The card where the carrying hand's ray is: flat on what it is on, facing back along the ray, or
## out in front of the hand over nothing.
func _carry() -> void:
	var by := held_by
	if by == null or not by.has_method("aim") or not card.is_inside_tree():
		return
	var aim: Transform3D = by.aim()
	var toward := -aim.basis.z.normalized()
	var on := by.get("hovered") as ControlAffordance
	var at: Vector3 = aim.origin + toward * CARRY_OUT
	if on != null and on != self and is_instance_valid(on):
		at = (by.get("hover_point") as Vector3) - toward * CARD_OFF
	var up := Vector3.UP if absf(toward.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	card.global_transform = Transform3D(Basis.looking_at(-toward, up), at)
