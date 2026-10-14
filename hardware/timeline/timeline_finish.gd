class_name TimelineFinish
extends RefCounted

## What the timeline is made of. It is not a screen and not a panel: it is light and glass in the
## air. Clips are lit glass ingots, their sound and their notes standing out of their faces; each
## track runs in a channel of smoked glass with a thread of its colour along its foot; the playhead
## is a blade of light through all of it.
##
## Self-lit rather than lit by the room, for the reason the old screen was unlit: the studio's
## warm key turned every lane and block the same brown, and the blocks vanished into their lanes.
## But not flat. The ingots shade their own faces -- top lit, underside dark, sides between -- and
## light their own edges, so they read as solids from any seat without any lamp's help, and the
## same in every venue.

static var _ingot_shader: Shader
static var _glass_shader: Shader
static var _ingots := {}
static var _glass: ShaderMaterial
static var _glow: ShaderMaterial


## A bank of ingots: unit cubes scaled to each clip, coloured per instance (linear), their edges
## lit `rim` metres in from every edge.
## Where the playhead's blade is, for every ingot: a point on it in the world, and the
## timeline's x axis in the world (metres of timeline per metre of world folded in).
static func light_beam(at: Vector3, axis: Vector3, reach: float) -> void:
	for m in _ingots.values():
		(m as ShaderMaterial).set_shader_parameter("beam_at", at)
		(m as ShaderMaterial).set_shader_parameter("beam_axis", axis)
		(m as ShaderMaterial).set_shader_parameter("beam_reach", reach)


static func ingots(rim: float, glow := 1.0) -> MeshBank:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var bank := MeshBank.meshed(box)
	bank.material_override = ingot(rim, glow)
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bank


static func ingot(rim: float, glow := 1.0) -> ShaderMaterial:
	var key := "%.5f|%.2f" % [rim, glow]
	if _ingots.has(key):
		return _ingots[key]
	if _ingot_shader == null:
		_ingot_shader = Shader.new()
		_ingot_shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform float rim = 0.0012;
uniform float glow = 1.0;
// The playhead, as a plane in the world: a point on it and the timeline's own x axis (unit,
// scaled to metres of the timeline). What it is passing through is lit by it.
uniform vec3 beam_at = vec3(0.0, -1000.0, 0.0);
uniform vec3 beam_axis = vec3(1.0, 0.0, 0.0);
uniform float beam_reach = 0.012;
varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 extent;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	local_normal = NORMAL;
	extent = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec3 n = local_normal;
	// Its own light: the top catches it, the underside is in shade, the ends between.
	float shade = 1.0;
	if (n.y > 0.5) shade = 1.45;
	else if (n.y < -0.5) shade = 0.38;
	else if (abs(n.x) > 0.5) shade = 0.72;
	// How far this point is from the nearest edge of the face it is on, in metres.
	vec3 d = (0.5 - abs(local_pos)) * extent;
	float e;
	if (abs(n.z) > 0.5) e = min(d.x, d.y);
	else if (abs(n.y) > 0.5) e = min(d.x, d.z);
	else e = min(d.y, d.z);
	float edge = 1.0 - smoothstep(0.0, rim, e);
	// Down the face, lighter toward the top, as glass lit from inside and above.
	float fall = abs(n.z) > 0.5 ? mix(0.70, 1.12, clamp(local_pos.y + 0.5, 0.0, 1.0)) : 1.0;
	vec3 body = c * shade * fall * glow;
	// A bevel, drawn: on the face, the band along its top catches the light and the band along
	// its foot is in its own shade, so it stands off the glass seen straight on, as it does seen
	// from the side.
	vec3 lit_edge = c * 1.7 + vec3(0.10);
	if (abs(n.z) > 0.5 && d.y < rim && local_pos.y < 0.0) lit_edge = c * 0.42;
	vec3 lit = mix(body, lit_edge, edge * 0.8);
	// Where the blade cuts through it, it is lit from inside: warm, and brightest at the cut.
	float near = 1.0 - smoothstep(0.0, beam_reach, abs(dot(world - beam_at, beam_axis)));
	// Held under the glow pass's threshold but at the cut: a selected clip, lifted toward white,
	// bloomed into a blob of light that hid its own name.
	ALBEDO = min(lit, vec3(0.95)) + (c * 0.9 + vec3(0.30, 0.24, 0.10)) * near * near;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _ingot_shader
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("glow", glow)
	_ingots[key] = m
	return m


## A bank of smoked glass: unit cubes, each its own colour and its own see-through (alpha).
static func glass_bank() -> MeshBank:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var bank := MeshBank.meshed(box)
	bank.material_override = glass()
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bank


static func glass() -> ShaderMaterial:
	if _glass == null:
		_glass_shader = Shader.new()
		_glass_shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_back, depth_draw_never, blend_mix;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""
		_glass = ShaderMaterial.new()
		_glass.shader = _glass_shader
	return _glass


## Light added to what is behind it: a halo, a beam. Colour and strength in one.
static func glow(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = colour
	return m


## A bank of glow: unit cubes of added light, each its own colour (alpha is its strength).
static func glow_bank() -> MeshBank:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var bank := MeshBank.meshed(box)
	if _glow == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, blend_add, depth_draw_never, cull_back;

void fragment() {
	ALBEDO = COLOR.rgb * COLOR.a;
}
"""
		_glow = ShaderMaterial.new()
		_glow.shader = sh
	bank.material_override = _glow
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bank


static var _gem: ShaderMaterial


## A cut stone in its own colour (per instance), its facets lit from above and in front so it
## sparkles as a stone does rather than reading as a flat diamond of colour.
static func gem() -> ShaderMaterial:
	if _gem == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled;

void fragment() {
	vec3 key = normalize(vec3(-0.35, 0.75, 0.6));
	float facet = max(dot(NORMAL, key), 0.0);
	float spark = pow(facet, 12.0);
	ALBEDO = COLOR.rgb * (0.45 + 0.85 * facet) + vec3(spark * 0.6);
}
"""
		_gem = ShaderMaterial.new()
		_gem.shader = sh
	return _gem
