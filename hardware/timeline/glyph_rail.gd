class_name GlyphRail
extends ControlAffordance

## A setting of the timeline's as a rod of light with a bead on it: its mark at the left end (see
## TimelineGlyph), the rod lit from there to the bead, the bead where the setting is. Pressed
## anywhere along the rod the bead goes there and follows the drag; let go, it commits
## (`value_committed`), one edit. What it is set to floats over the bead while a hand is on it,
## and nowhere else: the rod's length is the value at a glance, the number is for the hand moving it.

signal turned(v: float)

const HEIGHT := GlyphKey.SIZE
const WIDTH := 0.096
## The rod, from after the mark to the right end.
const MARK := 0.022
const ROD := 0.0016
const BEAD := 0.0042
## A wheel notch moves it this much of its travel; fine, a tenth of that.
const STEP := 1.0 / 40.0
const FINE := 0.1

var led_colour := Color(0.45, 0.78, 0.95):
	set(v):
		led_colour = v
		_refresh()
## What it is called: the hover card's.
var label := ""
var glyph := &"gain"
var fixed_width := WIDTH
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

var _mark: TimelineGlyph
var _rod: MeshInstance3D
var _fill: MeshInstance3D
var _bead: MeshInstance3D
var _value: Label3D
var _shape: CollisionShape3D
var _hovered := false


func _ready() -> void:
	collision_layer = 2 if available and reachable else 0
	collision_mask = 0
	_mark = TimelineGlyph.of(glyph, led_colour, 0.0085)
	add_child(_mark)
	_rod = _cylinder(ROD * 0.5)
	_rod.material_override = Materials.led(Color(0.3, 0.32, 0.38), false)
	_fill = _cylinder(ROD * 0.75)
	_bead = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = BEAD
	s.height = BEAD * 2.0
	s.radial_segments = 16
	s.rings = 8
	_bead.mesh = s
	_bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bead)
	_value = Label3D.new()
	_value.font_size = 26 * 4
	_value.pixel_size = 0.000078
	_value.outline_size = 16
	_value.outline_modulate = Color(0, 0, 0, 0.85)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	Lettering.range_to_legibility(_value)
	add_child(_value)
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	hover_changed.connect(func(on: bool):
		_hovered = on
		_refresh())
	grab_started.connect(func(_by): _refresh())
	grab_ended.connect(func(_by): _refresh())
	_refresh()


func _cylinder(r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 1.0
	c.radial_segments = 10
	c.rings = 1
	m.mesh = c
	m.rotation = Vector3(0, 0, PI * 0.5)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func width() -> float:
	return fixed_width


func _left() -> float:
	return -width() * 0.5 + MARK


func _span() -> float:
	return width() * 0.5 - BEAD - _left()


func _refresh() -> void:
	if _bead == null:
		return
	var w := width()
	_mark.position = Vector3(-w * 0.5 + MARK * 0.45, 0, 0.002)
	_mark.set_light(led_colour, 1.0 if available else 0.0)
	var left := _left()
	var span := _span()
	var at := left + clampf(value, 0.0, 1.0) * span
	_rod.scale = Vector3(1, span + BEAD, 1)
	_rod.position = Vector3(left + span * 0.5, 0, 0.004)
	_fill.visible = available and at - left > 0.0005
	_fill.scale = Vector3(1, maxf(at - left, 0.0005), 1)
	_fill.position = Vector3((left + at) * 0.5, 0, 0.004)
	_fill.material_override = Materials.led(led_colour, true)
	_bead.position = Vector3(at, 0, 0.004)
	var hot := (_hovered or held_by != null) and available
	_bead.scale = Vector3.ONE * (1.3 if hot else 1.0)
	_bead.material_override = Materials.led(Color(1, 1, 1).lerp(led_colour, 0.4) if available
			else Color(0.35, 0.37, 0.42), available)
	(_shape.shape as BoxShape3D).size = Vector3(w, HEIGHT * 0.8, 0.012)
	_shape.position = Vector3(0, 0, 0.004)
	_value.text = readout() if available else ""
	_value.position = Vector3(at, BEAD + 0.002, 0.006)
	_value.visible = hot


func _on_grab_begin(at: Vector3) -> void:
	_set_from(at)


func _on_grab_move(at: Vector3) -> void:
	_set_from(at)


func _set_from(at: Vector3) -> void:
	var to := clampf((to_local(at).x - _left()) / maxf(_span(), 0.001), 0.0, 1.0)
	value = Ergonomics.current.quantise(to)
	_refresh()
	turned.emit(value)


func _on_value_changed() -> void:
	_refresh()


func _on_nudge(notches: int, fine: bool) -> bool:
	var to := clampf(value + notches * STEP * (FINE if fine else 1.0), 0.0, 1.0)
	if is_equal_approx(to, value):
		return true
	value = to
	_refresh()
	turned.emit(value)
	return true


func _default_title() -> String:
	return label


func hint() -> String:
	return "press where it should be, or drag along it  ·  scroll to step  ·  shift for fine"
