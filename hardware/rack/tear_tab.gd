class_name TearTab
extends ControlAffordance

## The grip on a rack unit's name strip: pull it and the plugin comes away on a tablet.
##
## A drag, because that is the gesture the thing is -- you take hold of the unit's title and pull
## it off the rack -- and a click as well, because a gesture nobody discovers is a feature
## nobody has. While it is being pulled, a ghost of the tablet follows the hand, so the pull
## reads as taking something rather than as a drag that might do nothing.
##
## The tab says where it was let go; what stands there is the studio's business.

signal torn(at: Vector3)

## The grip's hit area, centred on this node.
var size := Vector2(0.2, 0.02)
## Further than this from where it was taken hold of and the pull is a tear, not a click.
const TEAR_DISTANCE := 0.06
## The ghost is the tablet at this scale: big enough to read as one, small enough not to hide
## the rack it is coming off.
const GHOST_SCALE := 0.6

var ghost_colour := Color(0.6, 0.8, 1.0)
## The size of what comes away, at full scale: a tablet unless the tab is for something else (a
## whole track's rack).
var ghost_size := Vector2(PluginTablet.WIDTH, PluginTablet.HEIGHT)
## What the hover card says pulling it does.
var hint_text := "drag it off the rack, or click, to get this plugin on a tablet"

var _from := Vector3.ZERO
var _at := Vector3.ZERO
var _ghost: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.008)
	shape.shape = box
	shape.position = Vector3(size.x * 0.5, 0, 0.004)
	add_child(shape)

	# Three ridges, the universal mark for "this part is for holding".
	for i in 3:
		var ridge := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(0.0012, size.y * 0.55, 0.0012)
		ridge.mesh = bar
		ridge.position = Vector3(0.004 + i * 0.0028, 0, 0.0008)
		ridge.material_override = Materials.cap_plastic(Color(0.42, 0.43, 0.46))
		add_child(ridge)


func _on_grab_begin(at: Vector3) -> void:
	_from = at
	_at = at


func _on_grab_move(at: Vector3) -> void:
	_at = at
	var pulled := _from.distance_to(at) > TEAR_DISTANCE * 0.5
	if pulled and _ghost == null:
		_ghost = _make_ghost()
		add_child(_ghost)
	if _ghost != null:
		_ghost.visible = pulled
		_ghost.global_transform = Transform3D(global_basis.orthonormalized(), at + global_basis.z * 0.03)


func _on_grab_end() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	# A click and a tear both ask for the tablet; only the tear says where.
	torn.emit(_at)


func pulled_far_enough() -> bool:
	return _from.distance_to(_at) > TEAR_DISTANCE


func _make_ghost() -> MeshInstance3D:
	var g := MeshInstance3D.new()
	g.name = "Ghost"
	g.top_level = true
	var quad := QuadMesh.new()
	quad.size = ghost_size * GHOST_SCALE
	g.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(ghost_colour, 0.28)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


func _foley_contact() -> AudioStream:
	return Foley.plug_seat()


func hint() -> String:
	return hint_text
