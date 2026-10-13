class_name BoardFeed
extends Node3D

## A live picture of one surface on the big board: a second camera, the way the mirror has one,
## held square to the surface's working face and fitted to it, drawn on the board's screen. So
## the band can watch the console's meters or the arrange timeline from across the room while
## the gear stays where it stands -- the surface is not moved, only looked at.
##
## The camera is orthographic and draws one layer only, ON_BOARD, which the feed puts on every
## part of the surface it shows (and takes off again when it shows something else): so a stand
## beside the gear, someone's head in front of it, or the wall behind it is never in the picture,
## only the gear on the screen's plate colour. A camera's mask culls lights as well as meshes,
## so the room's lights are given the layer too (`_light_the_board`), or the gear is drawn black.
## It renders only while the board is in view, like the mirror.

## The picture, centred on this node, facing +Z.
var screen_size := Vector2(3.4, 1.0)
## The full desktop renderer: twice the resolution and a little antialiasing.
var rich := false
## The room's look, copied for the camera without its tonemap and glow (the board gets those
## once, from the room's own camera), and with the plate's colour behind the gear.
var environment_from: Environment
var backdrop := Color(0.035, 0.04, 0.05)
## What it shows. Null shows nothing.
var target: Surface:
	set(value):
		if target == value:
			return
		_mark(target, false)
		target = value
		_mark(target, true)

## Layer 18: what the big board is showing. Drawn by every camera as well as the feed's.
const ON_BOARD := 1 << 17
## How often the shown surface's parts are marked again: a surface rebuilds, and a fader or a
## take it spawns arrives without the mark.
const MARK_EVERY := 0.25

## Further than this and the board is a few pixels: not worth a second render.
const DRAW_DISTANCE := 24.0
## Room round the surface inside the picture, so its edges do not touch the frame.
const MARGIN := 1.06

var _viewport: SubViewport
var _camera: Camera3D
var _picture: MeshInstance3D
var _env_clock := 0.0
var _mark_clock := 0.0
var _lights_clock := 0.0

const ROLLOFF_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform sampler2D feed : filter_linear, repeat_disable;
const float KNEE = 0.8;
void fragment() {
	// The room's glow blooms anything over 1, and a desk lit from above by the room's lamps is
	// over it on the screen -- a white bar where the armrest is. Rolled off above KNEE, as the
	// mirror's glass does, and everything darker left alone.
	vec3 seen = texture(feed, UV).rgb;
	float peak = max(max(seen.r, seen.g), seen.b);
	if (peak > KNEE) {
		float over = peak - KNEE;
		seen *= (KNEE + over / (1.0 + over * 2.0)) / peak;
	}
	ALBEDO = seen;
}
"""


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Feed"
	_viewport.own_world_3d = false
	_viewport.use_hdr_2d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var wide := 1600 if rich else 1024
	_viewport.size = Vector2i(wide, maxi(16, roundi(wide * screen_size.y / screen_size.x)))
	_viewport.msaa_3d = Viewport.MSAA_2X if rich else Viewport.MSAA_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.cull_mask = ON_BOARD
	_viewport.add_child(_camera)
	_camera.current = true
	_copy_environment()

	_picture = MeshInstance3D.new()
	_picture.name = "Picture"
	var quad := QuadMesh.new()
	quad.size = screen_size
	_picture.mesh = quad
	var m := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = ROLLOFF_SHADER
	m.shader = shader
	m.set_shader_parameter("feed", _viewport.get_texture())
	_picture.material_override = m
	_picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_picture)


func _process(delta: float) -> void:
	var eye := get_viewport().get_camera_3d()
	var setup := {}
	if target != null and is_instance_valid(target) and target.is_inside_tree() and eye != null \
			and in_view(eye):
		setup = framing(target, screen_size.x / screen_size.y)
	if setup.is_empty():
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_camera.global_transform = setup["transform"]
	_camera.size = setup["size"]
	_camera.near = setup["near"]
	_camera.far = setup["far"]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mark_clock += delta
	if _mark_clock > MARK_EVERY:
		_mark_clock = 0.0
		_mark(target, true)
	_env_clock += delta
	_lights_clock -= delta
	if _lights_clock <= 0.0:
		_lights_clock = 2.0
		_light_the_board()
	if _env_clock > 1.0:
		_env_clock = 0.0
		_copy_environment()


## Whether the board is anywhere in front of `eye` and near enough to be worth drawing.
func in_view(eye: Camera3D) -> bool:
	var at := global_transform
	var to_eye := eye.global_position - at.origin
	if to_eye.length() > DRAW_DISTANCE or to_eye.dot(at.basis.z) <= 0.0:
		return false
	var hx := at.basis.x * screen_size.x * 0.5
	var hy := at.basis.y * screen_size.y * 0.5
	for p in [at.origin, at.origin + hx + hy, at.origin - hx + hy, at.origin + hx - hy,
			at.origin - hx - hy]:
		if eye.is_position_in_frustum(p):
			return true
	return false


## The camera that shows `surface` square on, filling a picture `aspect` wide to one high:
## {transform, size, near, far}, or {} before the surface has been built and has no size.
##
## Square on is the surface's own +Z pitched by its `screen_pitch_degrees`, the same face the
## mount turns to a monitor: a console's panel lies back sixty degrees inside the desk, and
## straight down its +Z is the desk seen edge first.
static func framing(surface: Surface, aspect: float) -> Dictionary:
	var bounds := surface.content_aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {}
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(surface.screen_pitch_degrees))
	var faced := Transform3D(pitch, Vector3.ZERO) * bounds
	var at := surface.global_transform
	var scale := at.basis.get_scale().x
	var back_off := faced.size.z * 0.5 + 0.5
	var local_eye := bounds.get_center() + pitch.inverse() * Vector3(0, 0, back_off)
	return {
		"transform": Transform3D(at.basis.orthonormalized() * pitch.inverse(), at * local_eye),
		"size": maxf(faced.size.y, faced.size.x / aspect) * MARGIN * scale,
		"near": (back_off - faced.size.z * 0.5 - 0.02) * scale,
		"far": (back_off + faced.size.z * 0.5 + 0.02) * scale,
	}


## Every light in the room on the ON_BOARD layer as well as its own: a light the feed's camera
## cannot see lights nothing in its picture. Again every couple of seconds, for a lamp that has
## come in since (a venue's, a stand's).
func _light_the_board() -> void:
	for node in get_tree().root.find_children("*", "Light3D", true, false):
		(node as Light3D).layers |= ON_BOARD


func _exit_tree() -> void:
	_mark(target, false)


## Put the ON_BOARD layer on every drawn part of `surface`, or take it off.
static func _mark(surface: Surface, on: bool) -> void:
	if surface == null or not is_instance_valid(surface):
		return
	for node in surface.find_children("*", "VisualInstance3D", true, false):
		var drawn := node as VisualInstance3D
		# Not the grab handle and its tab: chrome for whoever is at the gear, not part of it.
		if on and drawn.is_in_group(&"presentation_chrome"):
			continue
		drawn.layers = (drawn.layers | ON_BOARD) if on else (drawn.layers & ~ON_BOARD)


func _copy_environment() -> void:
	var env := environment_from.duplicate() as Environment if environment_from != null \
			else Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.adjustment_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = backdrop
	_camera.environment = env
