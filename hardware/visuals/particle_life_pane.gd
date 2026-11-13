class_name ParticleLifePane
extends GpuSim

## A glass pane of particle life (docs/visuals.md): six species of glowing points, each pulled toward or
## pushed from each other species as an attraction matrix says, in a space that wraps at the edges, so
## they gather into cells, chains and chasing swarms. The music drives each species from its own part of
## the spectrum (the first from the bass, the last from the treble); a hit shakes the matrix and kicks
## the points; every MATRIX_SECONDS a new matrix is blended in over BLEND_SECONDS.
##
## Centred on the origin, the glass facing +Z.

## The pane (m): width x height x depth. Set before it is added.
var size := Vector3(1.2, 0.8, 0.07)
## How many particles (a whole number of 256), and the picture's texels.
var particle_count := 4096
var picture_size := Vector2i(384, 256)
## The matrix in use (SPECIES x SPECIES, row = the species moved), for a test or a look.
var matrix := PackedFloat32Array()

const SPECIES := 6
const MATRIX_SECONDS := 45.0
const BLEND_SECONDS := 6.0
const FRAME := 0.012

var _from := PackedFloat32Array()
var _to := PackedFloat32Array()
var _shake := PackedFloat32Array()
var _blend := 1.0
var _age := 0.0
var _last_hit := 0.0
var _seed := 3
var _rng := RandomNumberGenerator.new()


## `a` turned into `b` by `t` (0..1), eased at both ends so a new matrix arrives without a jolt.
static func blend_matrix(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
	var k := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = lerpf(a[i], b[i], k)
	return out


## Each species' force strength from the spectrum `bars` (0..1, low to high): species s hears the s-th
## of `species` equal runs of bars, so the first moves with the bass and the last with the treble.
## Silence is a gentle 0.6, a full band 2.
static func species_drive(bars: PackedFloat32Array, species := SPECIES) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(species)
	var n := bars.size()
	for s in species:
		var lo := s * n / species
		var hi := maxi((s + 1) * n / species, lo + 1)
		var sum := 0.0
		for i in range(lo, mini(hi, n)):
			sum += clampf(bars[i], 0.0, 1.0)
		out[s] = 0.6 + 1.4 * (sum / float(hi - lo) if n > 0 else 0.0)
	return out


## A fresh matrix, each entry -1..1, the diagonal leaning to attraction so each species holds together.
static func random_matrix(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SPECIES * SPECIES)
	for i in SPECIES:
		for j in SPECIES:
			out[i * SPECIES + j] = rng.randf_range(-1.0, 1.0) if i != j else rng.randf_range(0.1, 1.0)
	return out


## The species' colours round the mood colour: a fan of hues either side of it.
static func species_colours(mood: Color) -> Array[Color]:
	var out: Array[Color] = []
	for s in SPECIES:
		var h := fposmod(mood.h + (float(s) / (SPECIES - 1) - 0.5) * 0.6, 1.0)
		out.append(Color.from_hsv(h, clampf(maxf(mood.s, 0.5) + 0.1, 0.0, 0.9), 1.0))
	return out


func _choose_sizes() -> void:
	particle_count = VisualBudget.pick(4096, 1536)
	var across: int = VisualBudget.pick(384, 256)
	picture_size = Vector2i(across, roundi(across * size.y / size.x))
	_rng.seed = hash(name) + 5
	_from = random_matrix(_rng)
	_to = _from.duplicate()
	_shake.resize(SPECIES * SPECIES)
	matrix = _from.duplicate()


func _bounds() -> AABB:
	return AABB(-size * 0.5, size)


func _build_static() -> void:
	var dark := GpuSim.metal_material(Color(0.012, 0.012, 0.016))
	dark.metallic = 0.2
	dark.roughness = 0.6
	ZoneKit.block(self, Vector3(size.x, size.y, 0.006), Vector3(0, 0, -size.z * 0.5 + 0.003), dark, "Back")
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = ZoneKit.edges(size, FRAME)
	frame.material_override = GpuSim.metal_material()
	add_child(frame)
	var glass := ZoneKit.block(self, Vector3(size.x, size.y, 0.004), Vector3(0, 0, size.z * 0.5 - 0.002),
			GpuSim.glass_material(), "Glass")
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x - FRAME, size.y - FRAME)
	screen.mesh = quad
	screen.position = Vector3(0, 0, -size.z * 0.5 + 0.008)


func _make_kernel() -> GpuSim.Kernel:
	return PlifeKernel.new()


func _shader_paths() -> Dictionary:
	return {"plife": "res://hardware/visuals/shaders/plife.glsl"}


func _kernel_setup() -> Dictionary:
	return {"count": particle_count, "picture": picture_size}


## The matrix one step on: the blend toward the next one, a shake from a hit fading out of it.
func advance_matrix(dt: float, hit: float) -> void:
	_age += dt
	if _age >= MATRIX_SECONDS:
		_age = 0.0
		_from = matrix.duplicate()
		_to = random_matrix(_rng)
		_blend = 0.0
	_blend = minf(_blend + dt / BLEND_SECONDS, 1.0)
	var calm := exp(-dt / 1.2)
	for i in _shake.size():
		_shake[i] *= calm
	if hit > 0.0:
		for k in 5:
			var i := _rng.randi_range(0, SPECIES * SPECIES - 1)
			_shake[i] = clampf(_shake[i] + _rng.randf_range(-0.6, 0.6) * hit, -0.8, 0.8)
	var base := blend_matrix(_from, _to, _blend)
	for i in base.size():
		base[i] = clampf(base[i] + _shake[i], -1.0, 1.0)
	matrix = base


func _frame(dt: float) -> Dictionary:
	var a := AudioFeatures.now()
	var hit := 0.0
	if a.hit > _last_hit + 0.15 and a.hit > 0.3:
		hit = a.hit
	_last_hit = a.hit
	advance_matrix(dt, hit)
	_seed = (_seed + 1) % 100003
	var drive := species_drive(a.bars)
	var lift := 1.0 + 0.6 * clampf(a.level, 0.0, 1.0)
	return {
		"dt": minf(dt, 1.0 / 30.0),
		"matrix": matrix,
		"strength": drive,
		"colours": species_colours(tint),
		"rmax": 0.085 * sqrt(4096.0 / particle_count),
		"friction": pow(0.5, dt / 0.05),
		"force": 9.0 * lift,
		"radius": VisualBudget.pick(2.4, 1.9),
		"fade": pow(0.84, dt * 60.0),
		"kick": hit * 0.35,
		"seed": float(_seed),
		"exposure": 0.9,
	}


## The pane's render-thread half: the particles (twice, read and written in turn), the rules, the
## accumulator and the picture.
class PlifeKernel extends GpuSim.Kernel:
	var _pipe := RID()
	var _set := RID()
	var _rules := RID()
	var _count := 0
	var _pic := Vector2i.ZERO
	var _parity := 0
	var _seeded := false

	func build(spirv: Dictionary, setup: Dictionary) -> void:
		_count = setup["count"]
		_pic = setup["picture"]
		_pipe = pipeline(spirv.get("plife"))
		if not _pipe.is_valid():
			return
		var parts := PackedByteArray()
		parts.resize(_count * 2 * 16)
		var particles := storage_buffer(parts)
		var rules := PackedByteArray()
		rules.resize((9 + 2 + ParticleLifePane.SPECIES) * 16)
		_rules = uniform_buffer(rules)
		var acc := PackedByteArray()
		acc.resize(_pic.x * _pic.y * 3 * 4)
		var accum := storage_buffer(acc)
		display = texture(_pic.x, _pic.y)
		_set = uniform_set(_pipe, [[particles, true], [_rules, false], [accum, true], display])

	func step(p: Dictionary) -> void:
		if not ready:
			return
		var data := PackedFloat32Array()
		var m: PackedFloat32Array = p["matrix"]
		data.append_array(m)
		var strength: PackedFloat32Array = p["strength"]
		data.append_array(strength)
		data.resize(9 * 4 + 2 * 4)
		for c: Color in p["colours"]:
			data.append_array(PackedFloat32Array([c.r, c.g, c.b, 1.0]))
		var bytes := data.to_byte_array()
		rd.buffer_update(_rules, 0, bytes.size(), bytes)
		var head := [float(_count), float(_parity), p["dt"], float(_pic.x) / float(_pic.y), p["rmax"], p["friction"],
				p["force"], float(_pic.x), float(_pic.y), p["radius"], p["fade"], p["kick"], p["seed"], p["exposure"], 0.0]
		var groups := Vector3i(ceili(_count / 256.0), 1, 1)
		var list := rd.compute_list_begin()
		if not _seeded:
			_seeded = true
			pass_(list, _pipe, _set, _push(3, head), groups)
		pass_(list, _pipe, _set, _push(0, head), Vector3i(_count / 32, 1, 1))
		pass_(list, _pipe, _set, _push(1, head), groups)
		pass_(list, _pipe, _set, _push(2, head), Vector3i(ceili(_pic.x * _pic.y / 256.0), 1, 1))
		rd.compute_list_end()
		_parity = 1 - _parity

	func _push(mode: int, head: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array([float(mode)])
		for v in head:
			out.append(float(v))
		return out
