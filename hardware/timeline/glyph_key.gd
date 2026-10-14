class_name GlyphKey
extends ControlAffordance

## One of the timeline's tools: a dark glass token standing in the air under the arrangement, its
## mark sculpted on its face (see TimelineGlyph) and a ring of light round its rim. Pressed, it
## does its one thing; hovered, it leans out toward the hand and the card says what it is.
##
## No word printed on it. The timeline's tools were desk keys with captions, then screen buttons
## with words on them, and both read as a screen bolted into a room. A token is an object, and an
## object says what it is by its shape and its colour; the hover card is where the words went.
##
## `lit` keeps the console's meaning, so the code that drives a key does not change: for a TOGGLE
## it is "on" -- the token stands forward, its ring full and its mark white-hot -- and for an
## action it is "pressing me does something", its mark glowing in its colour; dark when not.

signal pressed()

## The token, in metres: its diameter, and how far it stands out of the air it hangs in.
const SIZE := 0.034
const HEIGHT := SIZE
const THICK := 0.005
## How far an "on" toggle stands forward of the rest, and a hovered token leans.
const STAND := 0.004
const LEAN := 0.003

## The key's colour: its mark's light, and its ring's.
var led_colour := Color(0.55, 0.85, 0.55):
	set(v):
		led_colour = v
		_refresh()
## On and off, as a mode is (a view, a tab), rather than a thing that is done.
var toggle := false
## What it is called: the hover card's, not printed on it.
var label := "":
	set(v):
		label = v
		_refresh()
## The mark on it. See TimelineGlyph for the kinds.
var glyph := &"":
	set(v):
		if v == glyph:
			return
		glyph = v
		_build_mark()
## A short value worn under the token when it has one worth seeing at a glance (a time
## signature, an input) -- the one place a word stays. "" for none.
var caption := "":
	set(v):
		caption = v
		_refresh()
## Words ON the token instead of a mark, for a key whose whole meaning is a value ("4/4").
var face := "":
	set(v):
		face = v
		_refresh()
## Fixed by whoever lays the keys out, or 0 for the token's own.
var fixed_width := 0.0

var lit := false:
	set(v):
		lit = v
		_refresh()
## False puts it out of reach as well as dark: something a press could not act on.
var available := true:
	set(v):
		available = v
		collision_layer = 2 if available and reachable else 0
		_refresh()
## False while the page it is on is not the one shown: out of reach, whatever it could do.
var reachable := true:
	set(v):
		reachable = v
		collision_layer = 2 if available and reachable else 0

var _body: Node3D
var _puck: MeshInstance3D
var _ring: MeshInstance3D
var _mark: TimelineGlyph
var _caption: Label3D
var _face: Label3D
var _shape: CollisionShape3D
var _hovered := false
var dwell_progress := 0.0


func _ready() -> void:
	collision_layer = 2 if available and reachable else 0
	collision_mask = 0
	_body = Node3D.new()
	add_child(_body)
	_puck = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = SIZE * 0.5
	disc.bottom_radius = SIZE * 0.5
	disc.height = THICK
	disc.radial_segments = 32
	disc.rings = 1
	_puck.mesh = disc
	_puck.rotation = Vector3(PI * 0.5, 0, 0)
	_puck.position = Vector3(0, 0, THICK * 0.5)
	_puck.material_override = puck_finish()
	_body.add_child(_puck)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = SIZE * 0.5 - 0.0011
	torus.outer_radius = SIZE * 0.5 + 0.0003
	torus.rings = 40
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.rotation = Vector3(PI * 0.5, 0, 0)
	_ring.position = Vector3(0, 0, THICK)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_ring)
	_caption = Label3D.new()
	_caption.font_size = 22 * 4
	_caption.pixel_size = 0.000078
	_caption.outline_size = 14
	_caption.outline_modulate = Color(0, 0, 0, 0.85)
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_caption.position = Vector3(0, -SIZE * 0.5 - 0.0018, THICK)
	Lettering.range_to_legibility(_caption)
	add_child(_caption)
	_face = Label3D.new()
	_face.font_size = 40 * 4
	_face.pixel_size = 0.000078
	_face.position = Vector3(0, 0, THICK + 0.0008)
	Lettering.range_to_legibility(_face)
	_body.add_child(_face)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, SIZE, 0.012)
	_shape.shape = box
	_shape.position = Vector3(0, 0, 0.004)
	add_child(_shape)
	hover_changed.connect(func(on: bool):
		_hovered = on
		_refresh())
	_build_mark()


func _build_mark() -> void:
	if _body == null:
		return
	if _mark != null:
		_mark.free()
	_mark = TimelineGlyph.of(glyph, led_colour, SIZE * 0.29)
	_mark.position = Vector3(0, 0, THICK)
	_body.add_child(_mark)
	_refresh()


## How wide the key is: fixed, or the token's own.
func width() -> float:
	return fixed_width if fixed_width > 0.0 else SIZE


func _refresh() -> void:
	if _mark == null:
		return
	var on := toggle and lit
	var can := available and (lit or toggle)
	var glow := 0.0 if not available else (1.6 if on else (1.0 if can else 0.25))
	if _hovered and available:
		glow += 0.4
	_mark.set_light(Color(1, 1, 1).lerp(led_colour, 0.35) if on else led_colour, glow)
	var ring := led_colour if available else Color(0.3, 0.32, 0.36)
	var ring_glow := 0.0
	if on:
		ring_glow = 2.2
	elif can:
		ring_glow = 0.7
	elif available:
		ring_glow = 0.18
	ring_glow = maxf(ring_glow, dwell_progress * 2.2)
	if _hovered and available:
		ring_glow += 0.6
	_ring.material_override = Materials.led(ring, ring_glow > 0.5) if ring_glow > 0.0 else Materials.led(ring, false)
	_ring.visible = ring_glow > 0.0 or available
	_body.position.z = (STAND if on else 0.0) + (LEAN if _hovered and available else 0.0)
	_body.scale = Vector3.ONE * (1.08 if _hovered and available else 1.0)
	_caption.text = caption
	_face.text = face
	_face.visible = face != ""
	_mark.visible = face == ""
	_face.modulate = (Color(1, 1, 1).lerp(led_colour, 0.35) if available else Color(0.4, 0.42, 0.48))
	if _face.visible:
		Lettering.fit(_face, SIZE * 0.78, 40 * 4, 20 * 4)
	_caption.visible = caption != ""
	_caption.modulate = Color(0.94, 0.95, 0.97) if available else Color(0.5, 0.52, 0.58)


func dwell_activates() -> bool:
	return available


func set_dwell_progress(fraction: float) -> void:
	dwell_progress = clampf(fraction, 0.0, 1.0)
	_refresh()


func _on_grab_begin(_at: Vector3) -> void:
	if available:
		pressed.emit()


func _foley_contact() -> AudioStream:
	return Foley.button_click()


func _default_title() -> String:
	return label


func _default_readout() -> String:
	return "ON" if lit else "OFF"


func hint() -> String:
	return "press"


static var _puck_finish: StandardMaterial3D


## Smoked glass: dark, glossy, a little see-through, so the token reads as a solid object in the
## room's light and its mark as the bright thing on it.
static func puck_finish() -> StandardMaterial3D:
	if _puck_finish == null:
		_puck_finish = StandardMaterial3D.new()
		_puck_finish.albedo_color = Color(0.05, 0.055, 0.07, 0.88)
		_puck_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puck_finish.roughness = 0.12
		_puck_finish.metallic = 0.3
		_puck_finish.metallic_specular = 0.8
		_puck_finish.rim_enabled = true
		_puck_finish.rim = 0.6
		_puck_finish.rim_tint = 0.3
	return _puck_finish
