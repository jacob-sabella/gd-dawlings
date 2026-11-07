class_name RackPad
extends ControlAffordance

## A module's second face: a pane of dark glass with a glowing orb floating over it, and the orb is two
## knobs at once. Drag it about and both move; the glass shows where it is with a grid, a halo, crosshairs
## and rings that spread from it, all drawn by one shader, and the orb bobs and swells under a hand. The
## wall maps its two axes onto two of the module's knobs; the pad only says where the orb is.

## The orb moved to (`x`, `y`), each 0..1, while held.
signal moved(x: float, y: float)
## The orb was let go at (`x`, `y`).
signal released(x: float, y: float)

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform vec2 orb = vec2(0.5, 0.5);
uniform float hot = 0.0;
void fragment() {
	vec2 uv = UV;
	vec2 g = min(fract(uv * 8.0), 1.0 - fract(uv * 8.0));
	float grid = max(smoothstep(0.05, 0.0, g.x), smoothstep(0.05, 0.0, g.y));
	float d = length(uv - orb);
	float halo = exp(-d * d * 55.0);
	float rings = (0.5 + 0.5 * sin(d * 46.0 - TIME * (3.0 + hot * 6.0))) * exp(-d * 5.0);
	float cross = (smoothstep(0.014, 0.0, abs(uv.x - orb.x)) + smoothstep(0.014, 0.0, abs(uv.y - orb.y))) * exp(-d * 2.4);
	vec3 col = vec3(0.012, 0.016, 0.03) + tint.rgb * (grid * 0.10 + halo * (0.55 + hot) + rings * (0.16 + hot * 0.3) + cross * 0.45);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	col += tint.rgb * smoothstep(0.03, 0.0, edge) * 0.5;
	ALBEDO = col;
	ALPHA = 0.96;
}
"""

var size := 0.08
var tint := Color(0.4, 0.8, 1.0)
var x := 0.5
var y := 0.5
var _orb: MeshInstance3D
var _stem: MeshInstance3D
var _glass: MeshInstance3D
var _mat: ShaderMaterial
var _orb_mat: StandardMaterial3D
var _swell := 0.0
var _curve: MeshInstance3D
var _curve_values := PackedFloat32Array()
var _curve_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size, 0.03)
	shape.shape = box
	shape.position = Vector3(0, 0, 0.015)
	add_child(shape)
	_glass = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	_glass.mesh = quad
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("tint", tint)
	_glass.material_override = _mat
	_glass.position = Vector3(0, 0, 0.0015)
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	_stem = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0008
	cyl.bottom_radius = 0.0008
	cyl.height = 1.0
	_stem.mesh = cyl
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.albedo_color = tint
	_orb_mat.emission_enabled = true
	_orb_mat.emission = tint
	_orb_mat.emission_energy_multiplier = 2.0
	_orb_mat.roughness = 0.2
	_stem.material_override = _orb_mat
	_stem.rotation_degrees = Vector3(90, 0, 0)
	_stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stem)
	_orb = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.0075
	ball.height = 0.015
	ball.radial_segments = 20
	ball.rings = 10
	_orb.mesh = ball
	_orb.material_override = _orb_mat
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	_place(0.0)
	if _curve_values.size() > 1:
		_draw_curve()


## A shape standing out of the glass: a ramp from the pane's floor up to a lit ridge that follows
## `values` (heights from 0 to 1, left to right).
func set_curve(values: PackedFloat32Array) -> void:
	if values == _curve_values:
		return
	_curve_values = values
	if _glass != null:
		_draw_curve()


func _draw_curve() -> void:
	if _curve == null:
		_curve = MeshInstance3D.new()
		_curve.name = "Curve"
		_curve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_curve)
		for a in [0.28, 1.0]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(tint.r, tint.g, tint.b, a)
			if a == 1.0:
				m.albedo_color = tint.lerp(Color.WHITE, 0.5)
			_curve_mats.append(m)
	var n := _curve_values.size()
	var floor_y := -size * 0.5 + size * 0.08
	var reach := size * 0.78
	var fill_v := PackedVector3Array()
	var ridge_v := PackedVector3Array()
	var fill_i := PackedInt32Array()
	var ridge_i := PackedInt32Array()
	for i in n:
		var v := _curve_values[i]
		var px := (float(i) / float(n - 1) - 0.5) * (size - 0.008)
		var top := Vector3(px, floor_y + v * reach, 0.004 + v * 0.016)
		fill_v.append(Vector3(px, floor_y, 0.002))
		fill_v.append(top)
		ridge_v.append(top + Vector3(0, -0.0008, 0))
		ridge_v.append(top + Vector3(0, 0.0008, 0.0008))
		if i < n - 1:
			var b := i * 2
			fill_i.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))
			ridge_i.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))
	var mesh := ArrayMesh.new()
	for k in 2:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = fill_v if k == 0 else ridge_v
		arrays[Mesh.ARRAY_INDEX] = fill_i if k == 0 else ridge_i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(k, _curve_mats[k])
	_curve.mesh = mesh


## Place the orb at (`nx`, `ny`), clamped to 0..1; ignored while a hand holds it.
func set_xy(nx: float, ny: float) -> void:
	if is_held():
		return
	x = clampf(nx, 0.0, 1.0)
	y = clampf(ny, 0.0, 1.0)
	if _orb != null:
		_place(0.0)


func _process(delta: float) -> void:
	if _orb == null or not is_visible_in_tree():
		return
	var want := 1.0 if is_held() else (0.4 if is_hovered() else 0.0)
	_swell = move_toward(_swell, want, delta * 6.0)
	_place(Time.get_ticks_msec() * 0.001)


func _place(t: float) -> void:
	var lift := 0.014 + _swell * 0.012 + sin(t * 2.3 + x * 6.0) * 0.0015
	var at := Vector3((x - 0.5) * size, (y - 0.5) * size, lift)
	_orb.position = at
	_orb.scale = Vector3.ONE * (1.0 + _swell * 0.35)
	_stem.position = Vector3(at.x, at.y, lift * 0.5)
	_stem.scale = Vector3(1, lift, 1)
	_mat.set_shader_parameter("orb", Vector2(x, 1.0 - y))
	_mat.set_shader_parameter("hot", _swell)
	_orb_mat.emission_energy_multiplier = 1.4 + _swell * 1.2


func hint() -> String:
	return "drag the orb: across and up are two knobs at once"


func _aim(at: Vector3) -> void:
	var l := to_local(at)
	x = clampf(l.x / size + 0.5, 0.0, 1.0)
	y = clampf(l.y / size + 0.5, 0.0, 1.0)
	_place(Time.get_ticks_msec() * 0.001)
	moved.emit(x, y)


func _on_grab_begin(at: Vector3) -> void:
	_aim(at)


func _on_grab_move(at: Vector3) -> void:
	_aim(at)


func _on_grab_end() -> void:
	released.emit(x, y)
