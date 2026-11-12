class_name FluidTank
extends GpuSim

## A glass tank of dark water with coloured ink rising through it (docs/visuals.md): a stable-fluids
## solver (advect, vorticity confinement, a pressure solve, advect the dye) on a vertical sheet inside
## a glass box with a thin metal frame on a base. Each hit of the music shoots ink up from the floor of
## the tank, harder with more bass, its colour turning through hues around `tint`; the mids and the
## treble stir smaller swirls in. With nothing playing a slow wisp still rises now and then.
##
## Stands on its base: the origin is the middle of the base's underside, the glass faces +Z.

## The glass box, width x height x depth (m), not counting the base. Set before it is added.
var size := Vector3(1.6, 0.7, 0.3)
## The solver's grid (cells across the width, and the height that keeps them square); the dye is twice it.
var sim_size := Vector2i(256, 112)
var dye_size := Vector2i(512, 224)
## Pressure iterations each step (even, so the answer lands where the next pass reads it).
var iterations := 18

const BASE_HEIGHT := 0.07
const FRAME := 0.014
const MAX_SPLATS := 8
## How often (s) an idle tank lets a wisp rise.
const IDLE_EVERY := 1.6

var _echo := MeshInstance3D.new()
var _echo_material := StandardMaterial3D.new()
var _last_hit := 0.0
var _quiet := 10.0
var _idle := 0.0
var _swirl := 0.0
var _wisp_left := 0.0
var _wisp_x := 0.5
var _hue := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


## The ink a hit of `strength` (0..1) adds at hue step `phase` (whole turns): hues swung either side of
## the mood colour's, bright and saturated, brighter for a harder hit.
static func splat_colour(mood: Color, phase: float, strength: float) -> Color:
	var h := fposmod(mood.h + 0.14 * sin(phase * TAU) + 0.05 * sin(phase * TAU * 2.7), 1.0)
	var s := clampf(maxf(mood.s, 0.55) + 0.1, 0.0, 1.0)
	var c := Color.from_hsv(h, s, 1.0)
	var k := 0.3 + 0.9 * clampf(strength, 0.0, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


## How hard (sim cells a second, upward) a hit of `strength` pushes ink up a tank `height` cells tall,
## with `bass` (1 typical, up to 4): a hit with the bass in it throws the ink to the top.
static func splat_force(bass: float, strength: float, height: float) -> float:
	var b := clampf(bass, 0.0, 3.0) / 3.0
	return (0.5 + 1.2 * b) * clampf(strength, 0.0, 1.0) * height * 4.2


func _choose_sizes() -> void:
	var across: int = VisualBudget.pick(256, 128)
	var inner := _inner()
	sim_size = Vector2i(across, maxi(16, roundi(across * inner.y / inner.x)))
	dye_size = sim_size * 2
	iterations = VisualBudget.pick(18, 14)


func _inner() -> Vector2:
	return Vector2(size.x - FRAME * 2.0, size.y - FRAME * 2.0)


func _bounds() -> AABB:
	return AABB(Vector3(-size.x * 0.5, 0, -size.z * 0.5), Vector3(size.x, size.y + BASE_HEIGHT, size.z))


func _build_static() -> void:
	_rng.seed = hash(name) + 7
	var metal := GpuSim.metal_material()
	var mid := BASE_HEIGHT + size.y * 0.5
	# The base: a dark plinth a little wider than the glass, a lit strip along its front.
	ZoneKit.block(self, Vector3(size.x + 0.06, BASE_HEIGHT, size.z + 0.06), Vector3(0, BASE_HEIGHT * 0.5, 0),
			GpuSim.metal_material(Color(0.035, 0.035, 0.04)), "Base")
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = ZoneKit.edges(size, FRAME)
	frame.material_override = metal
	frame.position = Vector3(0, mid, 0)
	add_child(frame)
	var glass := ZoneKit.block(self, size - Vector3(0.002, 0.002, 0.002), Vector3(0, mid, 0), GpuSim.glass_material(), "Glass")
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The back of the tank is dark, so the ink glows against it.
	var dark := GpuSim.metal_material(Color(0.012, 0.013, 0.016))
	dark.metallic = 0.2
	dark.roughness = 0.6
	ZoneKit.block(self, Vector3(size.x - FRAME, size.y - FRAME, 0.004), Vector3(0, mid, -size.z * 0.5 + 0.006), dark, "Back")
	var quad := QuadMesh.new()
	quad.size = _inner()
	screen.mesh = quad
	screen.position = Vector3(0, mid, 0.02)
	# A dimmer copy of the sheet further back: the ink seems to have depth.
	_echo.name = "Echo"
	_echo.mesh = quad
	_echo.position = Vector3(0, mid, -size.z * 0.22)
	_echo.scale = Vector3(1.0, 1.0, 1.0)
	_echo.material_override = _echo_material
	_echo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_echo.visible = false
	add_child(_echo)


func build() -> void:
	super.build()
	if compute:
		for m in [screen_material, _echo_material]:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR


func _process(delta: float) -> void:
	super._process(delta)
	if compute and not _echo.visible and screen_material.albedo_texture != null:
		_echo_material.albedo_texture = display
		_echo_material.albedo_color = Color(0.28, 0.28, 0.3)
		_echo.visible = true


func _parts() -> Array[Node]:
	var out := super._parts()
	out.append(_echo)
	return out


func _make_kernel() -> GpuSim.Kernel:
	return FluidKernel.new()


func _shader_paths() -> Dictionary:
	return {"fluid": "res://hardware/visuals/shaders/fluid.glsl"}


func _kernel_setup() -> Dictionary:
	return {"size": sim_size, "iterations": iterations}


func _frame(dt: float) -> Dictionary:
	var a := AudioFeatures.now()
	_clock += dt
	_quiet += dt
	var w := float(sim_size.x)
	var h := float(sim_size.y)
	var splats: Array = []
	# A hit: ink thrown up from the floor, one jet or a few.
	if a.hit > _last_hit + 0.15 and a.hit > 0.3:
		_quiet = 0.0
		_hue += 0.11 + _rng.randf() * 0.05
		var jets := 1 + int(a.hit > 0.7) + int(a.bass > 2.0)
		var x0 := _rng.randf_range(0.15, 0.85)
		for j in jets:
			var x := clampf(x0 + (j - (jets - 1) * 0.5) * 0.18 + _rng.randf_range(-0.04, 0.04), 0.06, 0.94)
			var up := splat_force(a.bass, a.hit, h)
			splats.append({
				"at": Vector2(x * w, h - 3.0),
				"radius": h * (0.045 + 0.03 * a.hit),
				"force": Vector2(_rng.randf_range(-0.25, 0.25) * up, -up),
				"colour": splat_colour(tint, _hue + j * 0.08, a.hit) * 0.9,
			})
	_last_hit = a.hit
	# The mids and the treble: small swirls part way up, sideways.
	_swirl += (clampf(a.mid_att, 0.0, 3.0) + clampf(a.treb_att, 0.0, 3.0)) * a.level * dt
	if _swirl > 0.5 and splats.size() < MAX_SPLATS:
		_swirl = 0.0
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		splats.append({
			"at": Vector2(_rng.randf_range(0.1, 0.9) * w, _rng.randf_range(0.35, 0.8) * h),
			"radius": h * 0.03,
			"force": Vector2(side * h * (0.8 + a.treb_att * 0.5), -h * 0.3),
			"colour": splat_colour(tint, _hue + 0.5, 0.2) * 0.3,
		})
	# Nothing playing: now and then a slow wisp, a thin stream fed for a second or so, so the tank is
	# never dead.
	_idle += dt
	if _quiet > 1.5 and _idle > IDLE_EVERY:
		_idle = _rng.randf_range(-1.0, 0.4)
		_hue += 0.04
		_wisp_left = _rng.randf_range(0.8, 1.6)
		_wisp_x = _rng.randf_range(0.12, 0.88)
	if _wisp_left > 0.0 and splats.size() < MAX_SPLATS:
		_wisp_left -= dt
		_wisp_x = clampf(_wisp_x + _rng.randf_range(-0.004, 0.004), 0.05, 0.95)
		splats.append({
			"at": Vector2(_wisp_x * w, h - 3.0),
			"radius": h * 0.03,
			"force": Vector2(_rng.randf_range(-0.05, 0.05) * h, -h * 0.35) * clampf(dt * 60.0, 0.25, 2.0),
			"colour": splat_colour(tint, _hue, 0.6) * (10.0 * dt),
		})
	var base := tint.darkened(0.2)
	return {
		"dt": dt,
		"splats": splats,
		"curl": 6.0 + 4.0 * clampf(a.mid_att, 0.0, 3.0),
		"vel_keep": exp(-0.25 * dt),
		"dye_keep": exp(-(0.4 + 0.3 * a.level) * dt),
		"buoyancy": h * 0.9,
		"exposure": 1.2,
		"time": _clock,
		"base": Color(base.r * 0.025, base.g * 0.025, base.b * 0.03),
	}


## The tank's render-thread half: the grids, and the passes of one step in one compute list.
class FluidKernel extends GpuSim.Kernel:
	var _pipe := RID()
	var _set := RID()
	var _splats := RID()
	var _size := Vector2i.ZERO
	var _iterations := 18

	func build(spirv: Dictionary, setup: Dictionary) -> void:
		_size = setup["size"]
		_iterations = setup["iterations"]
		_pipe = pipeline(spirv.get("fluid"))
		if not _pipe.is_valid():
			return
		var r32 := RenderingDevice.DATA_FORMAT_R32_SFLOAT
		var vel_a := texture(_size.x, _size.y)
		var vel_b := texture(_size.x, _size.y)
		var curl := texture(_size.x, _size.y, r32)
		var div := texture(_size.x, _size.y, r32)
		var p_a := texture(_size.x, _size.y, r32)
		var p_b := texture(_size.x, _size.y, r32)
		var dye_a := texture(_size.x * 2, _size.y * 2)
		var dye_b := texture(_size.x * 2, _size.y * 2)
		display = texture(_size.x * 2, _size.y * 2)
		var blank := PackedByteArray()
		blank.resize(16 * FluidTank.MAX_SPLATS * 3)
		_splats = uniform_buffer(blank)
		_set = uniform_set(_pipe, [vel_a, vel_b, curl, div, p_a, p_b, dye_a, dye_b, display, [_splats, false]])

	func step(p: Dictionary) -> void:
		if not ready:
			return
		var splats: Array = p["splats"]
		var n := mini(splats.size(), FluidTank.MAX_SPLATS)
		if n > 0:
			var at := PackedFloat32Array()
			var force := PackedFloat32Array()
			var colour := PackedFloat32Array()
			at.resize(FluidTank.MAX_SPLATS * 4)
			force.resize(FluidTank.MAX_SPLATS * 4)
			colour.resize(FluidTank.MAX_SPLATS * 4)
			for i in n:
				var s: Dictionary = splats[i]
				at[i * 4] = s["at"].x
				at[i * 4 + 1] = s["at"].y
				at[i * 4 + 2] = s["radius"]
				force[i * 4] = s["force"].x
				force[i * 4 + 1] = s["force"].y
				var c: Color = s["colour"]
				colour[i * 4] = c.r
				colour[i * 4 + 1] = c.g
				colour[i * 4 + 2] = c.b
			var bytes := at.to_byte_array() + force.to_byte_array() + colour.to_byte_array()
			rd.buffer_update(_splats, 0, bytes.size(), bytes)
		var base: Color = p["base"]
		var head := [p["dt"], float(_size.x), float(_size.y), float(n), p["curl"], p["vel_keep"], p["dye_keep"],
				p["buoyancy"], p["exposure"], p["time"], 0.0, base.r, base.g, base.b, 0.0]
		var sim := Vector3i(ceili(_size.x / 8.0), ceili(_size.y / 8.0), 1)
		var dye := Vector3i(ceili(_size.x / 4.0), ceili(_size.y / 4.0), 1)
		var list := rd.compute_list_begin()
		for mode in [0, 1, 2, 3]:
			pass_(list, _pipe, _set, _push(mode, head), sim)
		for i in _iterations:
			pass_(list, _pipe, _set, _push(4 + i % 2, head), sim)
		pass_(list, _pipe, _set, _push(6, head), sim)
		pass_(list, _pipe, _set, _push(7, head), dye)
		pass_(list, _pipe, _set, _push(8, head), dye)
		rd.compute_list_end()

	func _push(mode: int, head: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array([float(mode)])
		for v in head:
			out.append(float(v))
		return out
