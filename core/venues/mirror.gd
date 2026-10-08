class_name Mirror
extends Node3D

## A looking-glass: somewhere to see your own ghost, and later to change how it looks.
##
## A planar mirror, done the exact way rather than with a reflection probe. A second camera
## stands at the viewer's eye reflected through the glass, faces back into the room, and looks
## through an off-axis frustum fitted to the glass rectangle, with its near plane ON the glass,
## so nothing behind the mirror is ever drawn into it. What it sees is drawn on the glass with
## left and right swapped -- which is all a mirror is. It renders only while the glass is in
## view, at the venue's resolution, so a mirror nobody is facing costs nothing.
##
## You are a camera, not a body, so there is nothing of you for a mirror to show. Presence keeps
## a ghost of you at your eye on a layer only mirrors see (SELF_ONLY); your own view never draws
## it. Panels that ride in front of your face in screen mode go the other way (NOT_REFLECTED):
## seen directly, never in the glass, where they would be their own backs over your face.
##
## The glass is the same in every venue; the frame is the venue's (Venue.make_mirror).

## Layer 20: drawn in mirrors only -- your own ghost.
const SELF_ONLY := 1 << 19
## Layer 19: drawn directly only -- the glass itself, and the panels stuck to your face.
const NOT_REFLECTED := 1 << 18
const ALL_LAYERS := (1 << 20) - 1
## What a person's own eye draws, and what a mirror's camera draws.
const MAIN_VIEW_MASK := ALL_LAYERS & ~SELF_ONLY
const REFLECTION_MASK := ALL_LAYERS & ~NOT_REFLECTED
## Further than this and the glass is a few pixels: not worth a second render.
const DRAW_DISTANCE := 14.0

const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform sampler2D reflection : filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float haze = 0.0;
uniform vec4 haze_colour : source_color = vec4(0.5, 0.5, 0.5, 1.0);
void fragment() {
	// Left and right swapped: the reflected camera's right is the glass's left.
	vec3 seen = texture(reflection, vec2(1.0 - UV.x, UV.y)).rgb;
	// A little darker toward the edges, the way a silvered back falls off.
	vec2 c = UV - 0.5;
	float edge = 1.0 - smoothstep(0.30, 0.72, length(c * vec2(1.0, 0.6)));
	ALBEDO = mix(seen * tint.rgb * (0.86 + 0.14 * edge), haze_colour.rgb, haze);
}
"""

## The glass, centred on this node, facing +Z.
var glass_size := Vector2(0.62, 1.6)
## The full desktop renderer: twice the resolution and a little antialiasing.
var rich := false
## The look the room is lit with, copied for the mirror's camera without its tonemap and glow,
## which the glass then gets once, from the room's own camera, like everything else.
var environment_from: Environment
var tint := Color.WHITE
var haze := 0.0
var haze_colour := Color(0.5, 0.5, 0.5)
## The board beside it for changing what your ghost wears, set by the venue that built it.
var wardrobe: Wardrobe

var _viewport: SubViewport
var _camera: Camera3D
var _glass: MeshInstance3D
var _material: ShaderMaterial
var _env_clock := 0.0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Reflection"
	_viewport.own_world_3d = false
	# Kept linear and above 1.0, so the room's tonemap applies once, on the glass.
	_viewport.use_hdr_2d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var tall := 1024 if rich else 512
	_viewport.size = Vector2i(maxi(16, roundi(tall * glass_size.x / glass_size.y)), tall)
	_viewport.msaa_3d = Viewport.MSAA_2X if rich else Viewport.MSAA_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.cull_mask = REFLECTION_MASK
	_camera.far = 400.0
	_viewport.add_child(_camera)
	_camera.current = true
	_copy_environment()

	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = glass_size
	_glass.mesh = quad
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GLASS_SHADER
	_material.shader = shader
	_material.set_shader_parameter("reflection", _viewport.get_texture())
	_material.set_shader_parameter("tint", tint)
	_material.set_shader_parameter("haze", haze)
	_material.set_shader_parameter("haze_colour", haze_colour)
	_glass.material_override = _material
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	_glass.layers = NOT_REFLECTED


func _process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	var setup := {}
	if eye != null and in_view(eye):
		setup = reflection(global_transform, glass_size, eye.global_position)
	if setup.is_empty():
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_camera.global_transform = setup["transform"]
	_camera.set_frustum(setup["size"], setup["offset"], setup["near"], _camera.far)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The venues move their air to the music; the mirror follows a beat or so behind.
	_env_clock += delta
	if _env_clock > 1.0:
		_env_clock = 0.0
		_copy_environment()


## Whether the glass is anywhere in front of `eye` and near enough to be worth drawing.
func in_view(eye: Camera3D) -> bool:
	var at := global_transform
	var to_eye := eye.global_position - at.origin
	if to_eye.length() > DRAW_DISTANCE or to_eye.dot(at.basis.z) <= 0.0:
		return false
	var hx := at.basis.x * glass_size.x * 0.5
	var hy := at.basis.y * glass_size.y * 0.5
	for p in [at.origin, at.origin + hx + hy, at.origin - hx + hy, at.origin + hx - hy,
			at.origin - hx - hy]:
		if eye.is_position_in_frustum(p):
			return true
	# Close enough that the glass fills the view and its corners are all outside it.
	return to_eye.length() < 1.2 and not eye.is_position_behind(at.origin)


## The reflected camera for a mirror at `mirror` (glass centred on it, facing +Z, `size`
## metres) seen from `eye`: {transform, size, offset, near} for Camera3D.set_frustum, or {} when
## the eye is behind the glass or touching it.
static func reflection(mirror: Transform3D, size: Vector2, eye: Vector3) -> Dictionary:
	var right := mirror.basis.x.normalized()
	var up := mirror.basis.y.normalized()
	var out := mirror.basis.z.normalized()
	var d := (eye - mirror.origin).dot(out)
	if d < 0.02:
		return {}
	var reflected := eye - 2.0 * d * out
	# Looking back out of the glass into the room. Its right is the glass's left.
	var basis := Basis(-right, up, -out)
	var to_glass := mirror.origin - reflected
	return {
		"transform": Transform3D(basis, reflected),
		"size": size.y,
		"offset": Vector2(to_glass.dot(-right), to_glass.dot(up)),
		"near": d,
	}


func _copy_environment() -> void:
	if environment_from == null:
		return
	var env := environment_from.duplicate() as Environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.adjustment_enabled = false
	_camera.environment = env
