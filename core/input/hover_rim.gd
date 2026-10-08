class_name HoverRim
extends MeshInstance3D

## Four corner brackets around whatever an interactor is pointing at.
##
## The one piece of feedback a hand gets for free and a cursor never does: contact. A finger on
## a fader knows it is on the fader. An arrow over a picture of one knows nothing, so the desk
## has to say "this one" before the click, not after something moves.
##
## Brackets rather than a box or a glow. A full outline around every knob the cursor crosses
## turns a sweep across a channel strip into a strobe; four corners say the same thing at a
## quarter of the ink, and they frame the control without painting over its own markings.
##
## Owned by the interactor and drawn in world space, not parented into the control. A control
## can be freed under the cursor -- a rack page turns, a bank moves -- and a rim living inside
## it would take the interactor's reference down with it.

const COLOUR := Color(0.62, 0.82, 1.0, 0.85)
const HELD_COLOUR := Color(0.85, 0.95, 1.0, 1.0)
## Out from the control's own bounds, so the brackets sit beside a fader cap rather than on it.
const MARGIN := 0.003
## Line width in metres. Thin enough to read as a mark, thick enough to survive a monitor at a
## metre, where a millimetre is about one pixel.
const STROKE := 0.0016

var _target: ControlAffordance = null
var _held := false
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Through everything, because the only way to be hovered is to be hit by the ray -- so the
	# control is visible by construction, and depth testing would only let a fader cap that
	# stands proud of its own bounds eat the bottom bracket.
	_material.no_depth_test = true
	_material.render_priority = 10
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material
	visible = false


func show_on(control: ControlAffordance, held: bool) -> void:
	if control != null and not is_instance_valid(control):
		control = null
	if control != _target or held != _held:
		_target = control
		_held = held
		_rebuild()
	visible = _target != null
	if _target != null:
		global_transform = _target.global_transform


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _target == null:
		return
	var box := footprint(_target)
	if box.size == Vector3.ZERO:
		return
	box = box.grow(MARGIN)
	_material.albedo_color = HELD_COLOUR if _held else COLOUR
	var z := box.end.z + 0.001
	var lo := Vector2(box.position.x, box.position.y)
	var hi := Vector2(box.end.x, box.end.y)
	# A third of the shorter side, so a long fader travel gets brackets, not rails.
	var arm := minf(hi.x - lo.x, hi.y - lo.y) * 0.34
	var w := STROKE * (1.5 if _held else 1.0)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]:
		var sx := 1.0 if corner.x == lo.x else -1.0
		var sy := 1.0 if corner.y == lo.y else -1.0
		_quad(corner, corner + Vector2(sx * arm, sy * w), z)
		_quad(corner, corner + Vector2(sx * w, sy * arm), z)
	_mesh.surface_end()


func _quad(a: Vector2, b: Vector2, z: float) -> void:
	var p0 := Vector3(minf(a.x, b.x), minf(a.y, b.y), z)
	var p1 := Vector3(maxf(a.x, b.x), minf(a.y, b.y), z)
	var p2 := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), z)
	var p3 := Vector3(minf(a.x, b.x), maxf(a.y, b.y), z)
	for p in [p0, p1, p2, p0, p2, p3]:
		_mesh.surface_add_vertex(p)


## A control's touchable extent in its own space: the union of its collision shapes. The shape
## and not the mesh, because the shape is what the cursor actually hits -- a fader's covers the
## whole travel, and bracketing only the cap would misstate where a click lands.
static func footprint(control: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for child in control.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var debug := cs.shape.get_debug_mesh()
		if debug == null:
			continue
		var here := cs.transform * debug.get_aabb()
		out = here if first else out.merge(here)
		first = false
	return out
