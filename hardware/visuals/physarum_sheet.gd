class_name PhysarumSheet
extends GpuSim

## A glowing sheet of slime-mould veins (docs/visuals.md), meant for a ceiling: physarum agents that
## each follow the trail the others leave, so a network of veins grows, joins and thins across it.
## The louder the music the faster they run and the brighter they lay; a hit throws a ring of them out
## of a point, which the network then swallows; the bass turns the colour round `tint`. With nothing
## playing the network still slowly evolves.
##
## The sheet is `size` across, centred on the origin, lit on the side `facing` (straight down by default,
## for a ceiling), in a thin dark frame.

## The sheet (m). Set before it is added.
var size := Vector2(7.0, 6.0)
## Which way the lit face looks (local). Set before it is added.
var facing := Vector3.DOWN
## How many agents, and the trail map they run over (texels; square texels over `size`).
var agent_count := 131072
var trail_size := Vector2i(512, 439)

const FRAME := 0.04

var _pivot := Node3D.new()
var _last_hit := 0.0
var _flash := 0.0
var _seed := 1
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


## The faint and the bright colour of the veins for mood `tint` with `bass` (1 typical, up to 4): the
## faint one the mood itself, the bright one swung warmer as the bass comes in. Alpha is the brightness.
static func vein_colours(mood: Color, bass: float, flash: float) -> Array[Color]:
	var swing := clampf(bass - 1.0, -1.0, 2.0) * 0.06
	var low := Color.from_hsv(fposmod(mood.h + swing, 1.0), clampf(maxf(mood.s, 0.5) + 0.15, 0.0, 1.0), 1.0)
	var high := Color.from_hsv(fposmod(mood.h + 0.08 + swing * 1.5, 1.0), clampf(mood.s * 0.45, 0.0, 1.0), 1.0)
	low.a = 1.0 + clampf(flash, 0.0, 1.0) * 0.8
	return [low, high]


func _choose_sizes() -> void:
	agent_count = VisualBudget.pick(131072, 32768)
	var across: int = VisualBudget.pick(512, 256)
	trail_size = Vector2i(across, maxi(16, roundi(across * size.y / size.x)))


func _bounds() -> AABB:
	var n := facing.normalized()
	var b := _basis()
	var box := AABB(b * Vector3(-0.5 * size.x, -0.5 * size.y, 0.0), Vector3.ZERO)
	for corner in [Vector3(0.5, -0.5, 0), Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0)]:
		box = box.expand(b * (corner * Vector3(size.x, size.y, 0.0)))
	return box.expand(n * 0.05).expand(-n * 0.05)


## The pivot's basis: the sheet is built facing +Z, turned to face `facing`.
func _basis() -> Basis:
	var n := facing.normalized()
	if n.is_equal_approx(Vector3.BACK):
		return Basis.IDENTITY
	if n.is_equal_approx(Vector3.FORWARD):
		return Basis(Vector3.UP, PI)
	var axis := Vector3.BACK.cross(n).normalized()
	return Basis(axis, Vector3.BACK.angle_to(n))


func _build_static() -> void:
	_rng.seed = hash(name) + 11
	_pivot.name = "Sheet"
	_pivot.basis = _basis()
	add_child(_pivot)
	var dark := GpuSim.metal_material(Color(0.02, 0.02, 0.025))
	dark.metallic = 0.3
	dark.roughness = 0.7
	# The dark board behind the veins, and a thin frame proud of it round the edge.
	ZoneKit.block(_pivot, Vector3(size.x + FRAME, size.y + FRAME, 0.02), Vector3(0, 0, -0.012), dark, "Board")
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = ZoneKit.edges(Vector3(size.x, size.y, 0.01), FRAME * 0.5)
	frame.material_override = GpuSim.metal_material()
	_pivot.add_child(frame)
	var quad := QuadMesh.new()
	quad.size = size
	screen.mesh = quad


func build() -> void:
	super.build()
	# The base put the picture under this node; it belongs on the turned sheet.
	screen.reparent(_pivot, false)
	screen.position = Vector3(0, 0, 0.002)


func _parts() -> Array[Node]:
	var out := super._parts()
	out.append(_pivot)
	return out


func _make_kernel() -> GpuSim.Kernel:
	return PhysarumKernel.new()


func _shader_paths() -> Dictionary:
	return {"physarum": "res://hardware/visuals/shaders/physarum.glsl"}


func _kernel_setup() -> Dictionary:
	return {"size": trail_size, "count": agent_count}


func _frame(dt: float) -> Dictionary:
	var a := AudioFeatures.now()
	_clock += dt
	var scale := float(trail_size.x) / 512.0
	var step_scale := clampf(dt * 60.0, 0.25, 2.0)
	var burst := 0.0
	var at := Vector2(0.5, 0.5)
	if a.hit > _last_hit + 0.15 and a.hit > 0.3:
		burst = 0.015 + 0.03 * a.hit
		at = Vector2(_rng.randf_range(0.15, 0.85), _rng.randf_range(0.15, 0.85))
		_flash = maxf(_flash, a.hit)
	_last_hit = a.hit
	_flash = maxf(_flash - dt * 2.5, 0.0)
	_seed = (_seed + 7919) % 1000003
	var cols := vein_colours(tint, a.bass_att, _flash)
	var level := clampf(a.level, 0.0, 1.0)
	return {
		"speed": (0.9 + 1.3 * level) * scale * step_scale,
		"sense_angle": deg_to_rad(45.0),
		"sense_dist": 9.0 * scale,
		"turn": deg_to_rad(20.0 + 12.0 * level) * step_scale,
		"deposit": (1.6 + 2.5 * level) * step_scale * (131072.0 / agent_count) * (trail_size.x * trail_size.y) / (512.0 * 439.0),
		"decay": pow(0.9, step_scale),
		"diffuse": clampf(0.4 * step_scale, 0.0, 1.0),
		"seed": float(_seed),
		"burst": burst,
		"at": at,
		"time": _clock,
		"low": cols[0],
		"high": cols[1],
	}


## The sheet's render-thread half: the agents, the two trail maps, two passes a step.
class PhysarumKernel extends GpuSim.Kernel:
	var _pipe := RID()
	var _set := RID()
	var _size := Vector2i.ZERO
	var _count := 0
	var _parity := 0
	var _seeded := false

	func build(spirv: Dictionary, setup: Dictionary) -> void:
		_size = setup["size"]
		_count = setup["count"]
		_pipe = pipeline(spirv.get("physarum"))
		if not _pipe.is_valid():
			return
		var blank := PackedByteArray()
		blank.resize(_count * 16)
		var agents := storage_buffer(blank)
		var r32 := RenderingDevice.DATA_FORMAT_R32_SFLOAT
		var a := texture(_size.x, _size.y, r32)
		var b := texture(_size.x, _size.y, r32)
		display = texture(_size.x, _size.y)
		_set = uniform_set(_pipe, [[agents, true], a, b, display])

	func step(p: Dictionary) -> void:
		if not ready:
			return
		var low: Color = p["low"]
		var high: Color = p["high"]
		var at: Vector2 = p["at"]
		var head := [float(_parity), float(_size.x), float(_size.y), float(_count), p["speed"], p["sense_angle"],
				p["sense_dist"], p["turn"], p["deposit"], p["decay"], p["diffuse"], p["seed"], p["burst"], at.x, at.y,
				low.r, low.g, low.b, low.a, high.r, high.g, high.b, 1.0, p["time"], 0.9, 0.0, 0.0]
		var agents := Vector3i(ceili(_count / 256.0), 1, 1)
		var texels := Vector3i(ceili(_size.x * _size.y / 256.0), 1, 1)
		var list := rd.compute_list_begin()
		if not _seeded:
			_seeded = true
			pass_(list, _pipe, _set, _push(2, head), agents)
		pass_(list, _pipe, _set, _push(0, head), agents)
		pass_(list, _pipe, _set, _push(1, head), texels)
		rd.compute_list_end()
		_parity = 1 - _parity

	func _push(mode: int, head: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array([float(mode)])
		for v in head:
			out.append(float(v))
		return out
