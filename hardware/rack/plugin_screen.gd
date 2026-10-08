class_name PluginScreen
extends ControlAffordance

## The plugin's own window, on the plugin tablet's face: the picture its maker drew, and the
## pointer passed back into it, so a click on the screen is a click on the plugin.
##
## The picture is fitted into `size` and keeps its shape; a plugin drawn wide sits in a band
## across the tablet rather than being stretched to fill it. Only the picture takes the pointer,
## so a click on the margin around it is a click on nothing.
##
## Personal, like a mirror's buttons: the window is on the host's desktop and this is only ever
## the host's, so it is never claimed as a hold or shown as somebody's pointer across a session.

## The most of the tablet the picture may cover, centred on this node.
var size := Vector2(0.29, 0.17)
var window: PluginWindow

var _glass: MeshInstance3D
var _quad := QuadMesh.new()
var _material := StandardMaterial3D.new()
var _box := BoxShape3D.new()
var _shape: CollisionShape3D
var _waiting: Label3D
## The picture's size on the tablet, in metres; zero until there is a picture.
var _shown := Vector2.ZERO
var _last := Vector2i(-1, -1)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_glass = MeshInstance3D.new()
	_glass.name = "Picture"
	_glass.mesh = _quad
	_glass.position.z = 0.0006
	_glass.material_override = _material
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glass.visible = false
	add_child(_glass)

	_shape = CollisionShape3D.new()
	_shape.shape = _box
	_shape.position.z = 0.003
	_shape.disabled = true
	add_child(_shape)

	_waiting = Label3D.new()
	_waiting.name = "Waiting"
	_waiting.text = "OPENING THE PLUGIN'S WINDOW"
	_waiting.pixel_size = 0.0002
	_waiting.font_size = 44
	_waiting.modulate = Color(0.62, 0.65, 0.70)
	_waiting.position.z = 0.001
	add_child(_waiting)
	Lettering.range_to_legibility(_waiting)


func _process(_delta: float) -> void:
	if window == null:
		return
	window.poll()
	var pixels := window.pixel_size()
	var texture := window.texture()
	var showing := texture != null and pixels.x > 0 and pixels.y > 0
	_glass.visible = showing
	_shape.disabled = not showing
	_waiting.visible = not showing
	if not window.is_open():
		_waiting.text = "THE PLUGIN'S WINDOW COULD NOT BE SHOWN"
	if not showing:
		_shown = Vector2.ZERO
		return
	_material.albedo_texture = texture
	var fit := minf(size.x / pixels.x, size.y / pixels.y)
	var shown := Vector2(pixels) * fit
	if not shown.is_equal_approx(_shown):
		_shown = shown
		_quad.size = shown
		_box.size = Vector3(shown.x, shown.y, 0.006)
	# The pointer resting on the picture is the pointer on the plugin: its knobs light under it,
	# its tooltips come up.
	if is_hovered() and not is_held():
		var by := _hovered_by[0]
		var at = by.get("hover_point")
		if at is Vector3:
			_point(&"move", pixel_at(at))


## The picture's pixel under `at`, a point in global space, clamped to the picture.
func pixel_at(at: Vector3) -> Vector2i:
	var pixels := window.pixel_size() if window != null else Vector2i.ZERO
	if pixels.x <= 0 or _shown.x <= 0.0:
		return Vector2i.ZERO
	var local := to_local(at)
	var u := clampf(local.x / _shown.x + 0.5, 0.0, 1.0)
	var v := clampf(0.5 - local.y / _shown.y, 0.0, 1.0)
	return Vector2i(mini(int(u * pixels.x), pixels.x - 1), mini(int(v * pixels.y), pixels.y - 1))


func _point(kind: StringName, at: Vector2i) -> void:
	if window == null:
		return
	match kind:
		&"move":
			if at != _last:
				window.pointer_move(at)
		&"down":
			window.pointer_move(at)
			window.pointer_down(at)
		&"up":
			window.pointer_up(at)
	_last = at


func _on_grab_begin(at: Vector3) -> void:
	_point(&"down", pixel_at(at))


func _on_grab_move(at: Vector3) -> void:
	_point(&"move", pixel_at(at))


func _on_grab_end() -> void:
	_point(&"up", _last)


func _on_nudge(notches: int, _fine: bool) -> bool:
	if window == null or _shown.x <= 0.0:
		return false
	window.wheel(_last, notches)
	return true


func personal() -> bool:
	return true


func _default_readout() -> String:
	return "the plugin's own window"


func hint() -> String:
	return "click and drag as you would on the plugin's own screen  ·  the wheel turns what it is over"
