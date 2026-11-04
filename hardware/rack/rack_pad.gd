class_name RackPad
extends ControlAffordance

## A module's second face: a pane of dark glass with a glowing orb floating over it, and the orb is two
## knobs at once. Drag it about and both move; the glass shows where it is with a grid, a halo, crosshairs
## and rings that spread from it, all drawn by one shader, and the orb bobs and swells under a hand. The
## wall maps its two axes onto two of the module's knobs; the pad only says where the orb is.

signal moved(x: float, y: float)
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
	_orb_mat.emission_energy_multiplier = 2.0 + _swell * 3.0


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
