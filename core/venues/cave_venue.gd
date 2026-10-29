class_name CaveVenue
extends Venue

## A cavern deep inside a mountain, the studio set up on its floor. The rock is sculpted, not
## built: walls and roof are one sheet of noise-pushed stone (cave_rock.gdshader draws its grain,
## its beds and, in the lava tube, its ropes), the ground round the working floor rubble that
## rises to meet them. Nothing comes in from outside; every light is either something the crew
## carried in (floods, lanterns, work lamps) or the cave's own -- crystals, glowworms, lava.
##
## Three arrangements, three caves (Venue.VARIANTS):
##   Crystal grotto -- a high vault of dark rock, stalactites over it and stalagmites round it,
##     amethyst and ice-blue quartz growing out of the walls and the floor and glowing from
##     within; ahead of the desk, past a lip of rock, the floor falls away into a pit of giant
##     crystals. Mist lies low, and water drips.
##   Glowworm lake -- a wide, low, very dark cavern. The studio stands on a timber landing over the
##     rock, and in front of it a still black lake runs off to the far wall, a rowing boat tied at
##     the jetty. The roof is dotted with thousands of blue-green glowworms, each with its threads
##     hanging, and all of it is mirrored in the water.
##   Lava tube -- a long basalt tube, ropy and banded where the flows stood, the studio on the
##     bench of an old flow; beside it, behind a lip of rock and a steel rail, a river of lava
##     creeps down its channel and away round the bend ahead. Embers drift up off it, the air
##     over it shimmers, its light comes up orange from below. Cooled basalt columns stand along
##     the walls.
## The crystals swell, the glowworms twinkle and the lava breathes with the music (`pulse`).

const GROTTO := 0
const LAKE := 1
const TUBE := 2

const MODELS := "res://assets/models/"
const FORMATIONS := "cave_formations.glb"
const CRYSTALS := "cave_crystals.glb"

## How far the rock is kept back from the floor you walk on, and how high the roof is kept over
## it: the lattice stands 3.4 m and a hand goes up over it, and a stalactite's tip must clear
## the lot.
const WALL_CLEAR := 1.1
const ROOF_CLEAR := 4.8
## The glowworm lake's surface, under the landing's boards.
const WATER_Y := -0.45
## The grotto's lip of rock: where the floor in front of the desk starts to fall away into the
## pit, and how deep the pit is.
const PIT_FROM := 1.8
const PIT_DEPTH := 5.2

## The cave's outline, as a superellipse in plan with a profile up its walls (pairs of: how much
## of the plan's size at that height, the height), for the two domed caves.
const GROTTO_PROFILE := [Vector2(1.0, -8.0), Vector2(1.0, -2.0), Vector2(0.99, 1.5), Vector2(0.95, 5.0),
		Vector2(0.86, 8.5), Vector2(0.7, 11.8), Vector2(0.48, 14.2), Vector2(0.24, 15.6), Vector2(0.0, 16.2)]
const LAKE_PROFILE := [Vector2(1.0, -4.0), Vector2(1.0, 0.2), Vector2(0.98, 2.0), Vector2(0.92, 3.6),
		Vector2(0.8, 5.0), Vector2(0.6, 6.0), Vector2(0.32, 6.6), Vector2(0.0, 6.8)]

## The lava tube: its length (from, to, along z), its roof's height, how square its section is,
## and how far the river's centre is out past the working floor's right-hand edge.
const TUBE_FROM := -44.0
const TUBE_TO := 32.0
const TUBE_HEIGHT := 7.8
const TUBE_SQUARE := 2.8
const RIVER_OUT := 2.8
const RIVER_HALF := 1.8
const LAVA_Y := -0.2
## Where the river turns across the tube in front of the desk: how far ahead of the levelled
## floor its middle runs, and how tight it takes its two corners.
const RIVER_ACROSS := 2.4
const RIVER_TURN := 2.5
## The tube's levelled floor: how far past the working floor it runs on the river side (short of
## the lip), ahead down the tube and behind the zones.
const TUBE_FLOOR_RIGHT := 0.5
const TUBE_FLOOR_AHEAD := 0.6
const TUBE_FLOOR_BEHIND := 3.0

## The jetty off the landing's front in the glowworm lake: how far in from the left edge, its
## width and how far it runs out over the water.
const JETTY_IN := 0.9
const JETTY_WIDTH := 1.2
const JETTY_RUN := 5.4

## The pit, the giants and the columns in it were placed by number when the floor was 6.3 m either
## side of centre (the old LIVE_ROOM_HALF) and its front was 3.2 m ahead of the seat: what `_wide`
## and `_ahead` scale and shift those numbers from, so they stand round the floor it is now rather
## than huddling in front of the old one.
const PIT_DRAWN_HALF := 6.3
const PIT_DRAWN_FRONT := -3.2

const AMETHYST := Color(0.55, 0.16, 1.0)
const QUARTZ := Color(0.25, 0.68, 1.0)
const WORM := Color(0.3, 1.0, 0.85)
const LAVA_LIGHT := Color(1.0, 0.42, 0.12)
const LANTERN := Color(1.0, 0.68, 0.38)

## The walls and roof, as the grid they were sculpted on: kept to set things on.
var _grid: Array[PackedVector3Array] = []
var _normals: Array[PackedVector3Array] = []
var _ground_noise: FastNoiseLite
## Everything the music moves: shader materials with a `pulse`, and the lights with their
## resting energy, how much a loud bar lifts them and whether they flicker.
var _pulsed: Array[ShaderMaterial] = []
var _lights: Array = []
var _level := 0.0
var _t := 0.0
var _dark := false
var _models := {}
## Where things were put, for the tests (a headless MultiMesh keeps no transforms).
var crystal_spots: Array[Transform3D] = []
var glowworms := 0
## The lava river's middle line, upstream to down, and its samples bucketed by metre of z.
var _river: PackedVector2Array = []
var _river_cells := {}


func venue_id() -> StringName:
	return &"cave"


## Rock all round, and never a flat face of it to hang a board on: they stand.
func back_wall_gear_stands() -> bool:
	return true


## Slate and pewter, gem-cut: the gear dressed as if it were found down here. Black slate
## furniture, pewter metal, a lit amethyst edge, ice-quartz looms and amethyst caps.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("concrete_floor_worn_001", 0.9, Color(0.3, 0.28, 0.36))) \
			.with("chassis", GearStyle.paint(Color(0.07, 0.065, 0.085), 0.65, 0.25)) \
			.with("brushed", GearStyle.metal(Color(0.58, 0.56, 0.64), 0.32)) \
			.with("trim", GearStyle.glow(Color(0.66, 0.4, 1.0), 1.2)) \
			.with("end_cheek", GearStyle.paint(Color(0.16, 0.12, 0.21), 0.3, 0.1)) \
			.with("lamp_shade", GearStyle.metal(Color(0.42, 0.36, 0.53), 0.45)) \
			.with("loom_band", GearStyle.glow(Color(0.42, 0.85, 1.0), 0.9)) \
			.with("knob_cap", GearStyle.paint(Color(0.34, 0.14, 0.5), 0.25, 0.05))


## Black slate, chalk-white lettering, amethyst arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.paint(Color(0.09, 0.08, 0.11), 0.75, 0.05)
	board.ink = Color(0.86, 0.9, 1.0)
	board.accent = Color(0.72, 0.46, 1.0)
	board.board_ink_fade = Color(0.4, 0.38, 0.48)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	# No sky: rock, and past the light, black.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_sky_affect = 0.0
	match variant:
		LAKE:
			# The glowworms' blue-green is the only light from everywhere, and there is little of it.
			env.ambient_light_color = Color(0.25, 0.6, 0.58)
			env.ambient_light_energy = 0.15
			env.glow_intensity = 0.75
			env.glow_bloom = 0.03
			env.fog_light_color = Color(0.004, 0.012, 0.014)
			env.fog_depth_begin = 6.0
			env.fog_depth_end = 46.0
		TUBE:
			# Smoke and heat: the air itself is warm, and the far tube goes into it.
			env.ambient_light_color = Color(0.75, 0.38, 0.22)
			env.ambient_light_energy = 0.16
			env.glow_intensity = 0.7
			env.glow_bloom = 0.05
			env.fog_light_color = Color(0.13, 0.05, 0.02)
			env.fog_depth_begin = 4.0
			env.fog_depth_end = 40.0
		_:
			env.ambient_light_color = Color(0.5, 0.4, 0.75)
			env.ambient_light_energy = 0.2
			env.glow_intensity = 0.8
			env.glow_bloom = 0.04
			env.fog_light_color = Color(0.025, 0.015, 0.045)
			env.fog_depth_begin = 8.0
			env.fog_depth_end = 52.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.3
	# No sun this deep: the key is the room's general light, all but off.
	key.light_color = Color(0.8, 0.75, 1.0)
	key.light_energy = 0.03
	key.shadow_enabled = false
	key.basis = Basis.looking_at(Vector3(0.2, -1.0, 0.3), Vector3.FORWARD)


func lamp_colour(_index: int, authored: Color) -> Color:
	match variant:
		LAKE:
			return authored.lerp(LANTERN, 0.4)
		TUBE:
			return authored.lerp(Color(1.0, 0.62, 0.4), 0.3)
	# Cool, as the crystals are: an LED the crew brought.
	return authored.lerp(Color(0.86, 0.84, 1.0), 0.35)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.8


## The crew's own lights go; the crystals, the glowworms and the lava do not.
func blackout(on: bool) -> void:
	_dark = on


## One floor: the working floor, the strips beside it and the back of house.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 42): crystals growing out of a
## shelf of rock at the foot of the back wall, between the kit and the lattice, glowing as the
## cave's own do.
func instrument() -> Dictionary:
	return {"kind": &"crystals", "spot": back_wall_instrument(0.2)}


## Its weather (Weather, docs/spatial_loop.md part two, slice 44): drips off the ceiling into a few
## pools of standing water on the floor along its left edge, beside the desk, and the switch on an
## iron post at the edge among them. In the grotto and on the glowworm lake's landing, whose boards
## are as wet; nothing drips into the lava tube.
func weather() -> Dictionary:
	if variant == TUBE:
		return {}
	# Its post's whole foot on the floor, not half over the edge into the rubble.
	var x := -live_room_half() + 0.16
	var pools: Array = []
	for p: Vector2 in POOLS:
		pools.append(Vector3(x + p.x, POOL_TOP, POOLS_ALONG + p.y))
	return {"kind": &"drips", "spot": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0, POOLS_ALONG)),
			"sill": 0.95, "post": true, "pools": pools, "low": 64}


## The drips' pools: where each is from the switch's post, across (x, into the room) and along the
## edge (z) from POOLS_ALONG; how wide each is, and how far its water stands over the floor.
const POOLS := [Vector2(0.05, -0.8), Vector2(0.18, -0.42), Vector2(0.1, 0.45), Vector2(0.02, 0.85)]
const POOLS_ALONG := 1.25
const POOL_RADIUS := 0.16
const POOL_TOP := 0.004


## The drips' pools: still dark water standing on the floor, each a thin disc, for the drips to
## fall into (Weather draws the drops and their rings).
func _fill_the_pools() -> void:
	var spec := weather()
	if spec.is_empty():
		return
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.09, 0.11, 0.16)
	water.metallic = 0.2
	water.roughness = 0.04
	water.rim_enabled = true
	water.rim = 0.6
	# A faint sheen of its own: the grotto's light on still water, so a pool reads as water and
	# not a hole in the floor.
	water.emission_enabled = true
	water.emission = Color(0.05, 0.07, 0.12)
	var disc := CylinderMesh.new()
	disc.top_radius = POOL_RADIUS
	disc.bottom_radius = POOL_RADIUS
	# Down through the floor as far as it stands over it: no face on the floor's own plane.
	disc.height = POOL_TOP * 2.0
	disc.radial_segments = 32
	for n in (spec["pools"] as Array).size():
		var pool := MeshInstance3D.new()
		pool.name = "Pool%d" % n
		pool.mesh = disc
		pool.material_override = water
		pool.position = (spec["pools"][n] as Vector3) - Vector3(0, POOL_TOP, 0)
		# Each a little out of round, as standing water is.
		pool.scale = Vector3(1.0 + 0.25 * float(n % 2), 1.0, 1.0 + 0.2 * float((n + 1) % 2))
		add_child(pool)


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), true)


func pulse(level: float) -> void:
	_level = lerpf(_level, level, 0.3)
	for m in _pulsed:
		m.set_shader_parameter("pulse", _level)


func _process(delta: float) -> void:
	_t += delta
	for i in _lights.size():
		var spec: Array = _lights[i]
		var light := spec[0] as Light3D
		var rest: float = spec[1]
		var lift: float = spec[2]
		var kind: StringName = spec[3]
		var e := rest * (1.0 + lift * _level)
		match kind:
			&"flame":
				e *= 0.9 + 0.07 * sin(_t * 7.1 + i * 2.3) * sin(_t * 2.9 + i) + 0.03 * sin(_t * 17.0 + i * 5.0)
			&"lava":
				e *= 0.85 + 0.15 * sin(_t * 0.5 + i * 0.7)
			&"crystal":
				e *= 0.9 + 0.1 * sin(_t * (0.4 + i * 0.07) + i)
		if _dark and kind in [&"crew", &"flame"]:
			e = 0.0
		light.light_energy = e


func _ready() -> void:
	_make_ground_noise()
	match variant:
		LAKE:
			_build_lake()
		TUBE:
			_build_tube()
		_:
			_build_grotto()
	_fill_the_pools()


## The ground's noise, made once: by _ready, or by the first thing to ask where the ground is before
## then (`weather`, whose pools lie on it).
func _make_ground_noise() -> void:
	if _ground_noise != null:
		return
	_ground_noise = FastNoiseLite.new()
	_ground_noise.seed = 9 + variant
	_ground_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ground_noise.frequency = 0.22
	_ground_noise.fractal_octaves = 3


# --- materials -------------------------------------------------------------------------------

func _rock(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/cave_rock.gdshader")
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	if params.get("heat", 0.0) > 0.0:
		_pulsed.append(m)
	return m


## The same rock, cut off at the lake's surface: `real` draws it above, its reflection below.
func _cut(m: ShaderMaterial, real: bool) -> ShaderMaterial:
	var out := m.duplicate() as ShaderMaterial
	out.set_shader_parameter("clip_below", WATER_Y if real else -1000.0)
	out.set_shader_parameter("clip_above", 1000.0 if real else WATER_Y)
	if _pulsed.has(m):
		_pulsed.append(out)
	return out


func _paint(colour: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	return m


func _iron() -> StandardMaterial3D:
	return _paint(Color(0.05, 0.048, 0.05), 0.55, 0.6)


func _pewter() -> StandardMaterial3D:
	return GearStyle.metal(Color(0.5, 0.48, 0.55), 0.38)


func _planks(tint: Color) -> StandardMaterial3D:
	return Materials.cached_scanned("cave_planks", "weathered_brown_planks", "2k", 1.4, tint)


# --- the rock --------------------------------------------------------------------------------

## The cave's walls and roof: a grid of points `cols` round (or along) and `rows` up from
## `at(u, v)`, each pushed in or out along the surface by noise -- big slow bulges and sharp
## ridged crags -- so no two metres of it are alike, then kept off the floor you walk on and
## above the head room over it. Kept, with its normals, for setting things on it.
func _sculpt(cols: int, rows: int, wrap: bool, at: Callable, inside: Callable, amp: float, crag: float,
		seed: int, extra := Callable()) -> void:
	var bulge := FastNoiseLite.new()
	bulge.seed = seed
	bulge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bulge.frequency = 0.1
	bulge.fractal_octaves = 4
	var ridge := FastNoiseLite.new()
	ridge.seed = seed + 7
	ridge.frequency = 0.3
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 3
	var width := cols if wrap else cols + 1
	var base: Array[PackedVector3Array] = []
	for j in rows + 1:
		var row := PackedVector3Array()
		row.resize(width)
		for i in width:
			row[i] = at.call(float(i) / cols, float(j) / rows)
		base.append(row)
	var pushed: Array[PackedVector3Array] = []
	for j in rows + 1:
		var row := PackedVector3Array()
		row.resize(width)
		for i in width:
			var p := base[j][i]
			var n := _grid_normal(base, i, j, wrap, inside)
			var d := bulge.get_noise_3dv(p) * amp + ridge.get_noise_3dv(p * Vector3(1.0, 1.6, 1.0)) * crag
			if extra.is_valid():
				d += extra.call(p)
			row[i] = _keep_clear(p + n * d)
		pushed.append(row)
	_grid = pushed
	_normals = []
	for j in rows + 1:
		var nrow := PackedVector3Array()
		nrow.resize(width)
		for i in width:
			nrow[i] = _grid_normal(_grid, i, j, wrap, inside)
		_normals.append(nrow)


func _grid_normal(grid: Array[PackedVector3Array], i: int, j: int, wrap: bool, inside: Callable) -> Vector3:
	var width := grid[0].size()
	var rows := grid.size() - 1
	var left := grid[j][(i - 1 + width) % width] if wrap else grid[j][maxi(i - 1, 0)]
	var right := grid[j][(i + 1) % width] if wrap else grid[j][mini(i + 1, width - 1)]
	var p := grid[j][i]
	var n := (right - left).cross(grid[mini(j + 1, rows)][i] - grid[maxi(j - 1, 0)][i])
	var into: Vector3 = inside.call(p) - p
	if n.length_squared() < 1e-10:
		n = into
	n = n.normalized()
	return n if n.dot(into) >= 0.0 else -n


## Rock that has come in over the floor you walk on goes back: a wall low down is pushed out
## sideways to the nearest edge of the floor's clearance, a roof low over it is lifted.
func _keep_clear(p: Vector3) -> Vector3:
	var half := live_room_half() + WALL_CLEAR
	var front := Studio.ROOM_FRONT - WALL_CLEAR
	var back := LIVE_ROOM_BACK + WALL_CLEAR
	if p.x <= -half or p.x >= half or p.z <= front or p.z >= back or p.y >= ROOF_CLEAR:
		return p
	if p.y > 2.5:
		return Vector3(p.x, ROOF_CLEAR, p.z)
	var to_edge := [half - p.x, p.x + half, back - p.z, p.z - front]
	var least: float = to_edge.min()
	match to_edge.find(least):
		0:
			return Vector3(half, p.y, p.z)
		1:
			return Vector3(-half, p.y, p.z)
		2:
			return Vector3(p.x, p.y, back)
	return Vector3(p.x, p.y, front)


## The sculpted grid as meshes: `chunks` of it, side by side, so a headset's renderer -- eight
## lights a mesh -- lights each part of the cave by the lights near it. `heat`, when given, says
## how near the lava each point is (the rock's colour, which cave_rock.gdshader reads).
func _shell_meshes(wrap: bool, chunks: int, material: Material, label: String, heat := Callable()) -> Array[MeshInstance3D]:
	var rows := _grid.size()
	var width := _grid[0].size()
	var spans := width if wrap else width - 1
	var out: Array[MeshInstance3D] = []
	for c in chunks:
		var i0 := spans * c / chunks
		var i1 := spans * (c + 1) / chunks
		var cols := i1 - i0 + 1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in rows:
			for k in cols:
				var i := (i0 + k) % width
				var p := _grid[j][i]
				if heat.is_valid():
					st.set_color(Color(heat.call(p), 0, 0))
				st.set_normal(_normals[j][i])
				st.add_vertex(p)
		for j in rows - 1:
			for k in cols - 1:
				var a := j * cols + k
				var n := _normals[j][(i0 + k) % width]
				_quad(st, a, a + 1, a + cols + 1, a + cols, _grid[j][(i0 + k) % width],
						_grid[j][(i0 + k + 1) % width], _grid[j + 1][(i0 + k + 1) % width], n)
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % [label, c]
		mi.mesh = st.commit()
		mi.material_override = material
		add_child(mi)
		out.append(mi)
	return out


## Two triangles over the quad a-b-c-d, wound so their front faces `facing`.
func _quad(st: SurfaceTool, a: int, b: int, c: int, d: int, pa: Vector3, pb: Vector3, pc: Vector3, facing: Vector3) -> void:
	# Godot's front face for (a, b, c) is along (c - a) x (b - a).
	if (pc - pa).cross(pb - pa).dot(facing) >= 0.0:
		for k in [a, b, c, a, c, d]:
			st.add_index(k)
	else:
		for k in [a, c, b, a, d, c]:
			st.add_index(k)


## The ground: a height field over `cols` x `rows` points from `at(u, v)` (u, v in 0..1, giving
## x and z), its height the arrangement's own (`_ground_h`). Cells `keep` refuses are left out --
## under the lake, and outside the cave. In `tiles` x `tiles` meshes, for the lights' sake.
func _lay_ground(cols: int, rows: int, at: Callable, keep: Callable, material: Material, tiles: int,
		heat := Callable()) -> Array[MeshInstance3D]:
	var pts: Array[PackedVector3Array] = []
	for j in rows + 1:
		var row := PackedVector3Array()
		row.resize(cols + 1)
		for i in cols + 1:
			var xz: Vector2 = at.call(float(i) / cols, float(j) / rows)
			row[i] = Vector3(xz.x, _ground_h(xz.x, xz.y), xz.y)
		pts.append(row)
	var out: Array[MeshInstance3D] = []
	for ty in tiles:
		for tx in tiles:
			var i0 := cols * tx / tiles
			var i1 := cols * (tx + 1) / tiles
			var j0 := rows * ty / tiles
			var j1 := rows * (ty + 1) / tiles
			var w := i1 - i0 + 1
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := pts[j][i]
					var n := (pts[j][mini(i + 1, cols)] - pts[j][maxi(i - 1, 0)]).cross(
							pts[maxi(j - 1, 0)][i] - pts[mini(j + 1, rows)][i])
					n = n.normalized() if n.y >= 0.0 else -n.normalized()
					if heat.is_valid():
						st.set_color(Color(heat.call(p), 0, 0))
					st.set_normal(n)
					st.add_vertex(p)
			var any := false
			for j in range(j0, j1):
				for i in range(i0, i1):
					if not keep.call(pts[j][i], pts[j][i + 1], pts[j + 1][i], pts[j + 1][i + 1]):
						continue
					var a := (j - j0) * w + (i - i0)
					_quad(st, a, a + 1, a + w + 1, a + w, pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], Vector3.UP)
					any = true
			if not any:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Ground%d" % (ty * tiles + tx)
			mi.mesh = st.commit()
			mi.material_override = material
			add_child(mi)
			out.append(mi)
	return out


func _ground_h(x: float, z: float) -> float:
	match variant:
		LAKE:
			return _lake_h(x, z)
		TUBE:
			return _tube_h(x, z)
	return _grotto_h(x, z)


## How far (x, z) is outside a rectangle of the floor: `half` either side of the middle, from
## `front` to `back`. Negative inside, how far in from its nearest edge.
static func _outside(x: float, z: float, half: float, front: float, back: float) -> float:
	var dx := absf(x) - half
	var dz := maxf(front - z, z - back)
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


## A point in a domed cave's outline: round its plan (a superellipse `n`, half sizes `ax`, `az`,
## centred on `centre`) at u, up its profile at v.
static func _dome_point(u: float, v: float, centre: Vector2, ax: float, az: float, n: float, profile: Array) -> Vector3:
	var a := u * TAU
	var c := cos(a)
	var s := sin(a)
	var px := signf(c) * pow(absf(c), 2.0 / n)
	var pz := signf(s) * pow(absf(s), 2.0 / n)
	var f := v * (profile.size() - 1)
	var k := mini(int(f), profile.size() - 2)
	var at: Vector2 = (profile[k] as Vector2).lerp(profile[k + 1], f - k)
	return Vector3(centre.x + ax * px * at.x, at.y, centre.y + az * pz * at.x)


## Whether (x, z) is inside a domed cave's plan, grown by `grow`.
static func _in_plan(x: float, z: float, centre: Vector2, ax: float, az: float, n: float, grow: float) -> bool:
	var r := pow(absf(x - centre.x) / (ax + grow), n) + pow(absf(z - centre.y) / (az + grow), n)
	return r <= 1.0


## A point on the rock, somewhere between rows `v_from` and `v_to` of its height (0..1), and the
## way out of the rock there.
func _on_rock(rng: RandomNumberGenerator, v_from: float, v_to: float) -> Array:
	var rows := _grid.size() - 1
	var width := _grid[0].size()
	var j := rng.randi_range(int(v_from * rows), maxi(int(v_from * rows), mini(int(v_to * rows), rows - 1)))
	var i := rng.randi_range(0, width - 2)
	var a := rng.randf()
	var b := rng.randf()
	var p := _grid[j][i].lerp(_grid[j][i + 1], a).lerp(_grid[j + 1][i].lerp(_grid[j + 1][i + 1], a), b)
	var n := _normals[j][i].lerp(_normals[j][i + 1], a).lerp(_normals[j + 1][i].lerp(_normals[j + 1][i + 1], a), b)
	return [p, n.normalized()]


## Over the floor you walk on, with `margin` to spare.
## An x placed by number round the old floor (PIT_DRAWN_HALF), as far out round this one.
func _wide(x: float) -> float:
	return x * live_room_half() / PIT_DRAWN_HALF


## A z placed by number ahead of the old floor's front (PIT_DRAWN_FRONT), as far ahead of this one's.
func _ahead(z: float) -> float:
	return z + Studio.ROOM_FRONT - PIT_DRAWN_FRONT


## A z placed by number along the old back of house (DRAWN_BACK), as far along this one's.
func _along(z: float) -> float:
	return remap(z, 2.8, DRAWN_BACK, Studio.ROOM_BACK, LIVE_ROOM_BACK)


func _over_floor(p: Vector3, margin: float) -> bool:
	return _outside(p.x, p.z, live_room_half(), Studio.ROOM_FRONT, LIVE_ROOM_BACK) < margin


## The roof's height over (x, z): the sculpted grid's highest point near it.
func _roof_over(x: float, z: float) -> float:
	var best := INF
	var y := 0.0
	for row in _grid:
		for p in row:
			if p.y < 2.0:
				continue
			var d := Vector2(p.x - x, p.z - z).length_squared()
			if d < best:
				best = d
				y = p.y
	return y


# --- models ----------------------------------------------------------------------------------

func _part(file: String, part: String) -> ArrayMesh:
	if not _models.has(file):
		_models[file] = load(MODELS + file) as PackedScene
	var source := (_models[file] as PackedScene).instantiate()
	var mesh := (source.find_child(part, true, false) as MeshInstance3D).mesh.duplicate() as ArrayMesh
	source.free()
	return mesh


## One kind of part, many times over, as one MultiMesh: `swap` puts the cave's materials on its
## surfaces by name; `custom`, when given, is each instance's custom data (the crystals' colour).
## `mirror` draws it upside down under the lake's surface.
func _many(file: String, part: String, spots: Array[Transform3D], swap: Dictionary, label: String,
		custom: Array[Color] = [], mirror := false) -> MultiMeshInstance3D:
	var mesh := _part(file, part)
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swap.has(m.resource_name):
			mesh.surface_set_material(s, swap[m.resource_name])
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = not custom.is_empty()
	many.mesh = mesh
	many.instance_count = spots.size()
	for i in spots.size():
		many.set_instance_transform(i, spots[i])
		if not custom.is_empty():
			many.set_instance_custom_data(i, custom[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = many
	if mirror:
		node.transform = _mirror()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _model(file: String, at: Transform3D, swap: Dictionary) -> Node3D:
	var node := (load(MODELS + file) as PackedScene).instantiate() as Node3D
	node.transform = at
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	add_child(node)
	return node


## The lake's mirror: everything under it upside down about the water.
static func _mirror() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3(0, 2.0 * WATER_Y, 0))


## A basis whose up is `up`, turned `spin` about it.
static func _standing(up: Vector3, spin: float, size: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Basis(x, y, z) * Basis(Vector3.UP, spin) * Basis.from_scale(size)


# --- lights ----------------------------------------------------------------------------------

## A light the cave keeps track of: `lift` is how much a loud bar raises it, `kind` how it
## behaves (crystal, lava, flame, worm; crew for the electric ones the blackout takes).
func _light(at: Vector3, colour: Color, energy: float, reach: float, kind: StringName, lift := 0.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "%sLight" % String(kind).capitalize()
	l.position = at
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.light_specular = 0.25
	l.shadow_enabled = false
	add_child(l)
	_lights.append([l, energy, lift, kind])
	return l


## A small LED flood the crew set on the rock, aimed up at `target`: a black housing on a foot
## and a lit lens, and the beam.
func _flood(at: Vector3, target: Vector3, colour: Color, energy: float) -> void:
	var holder := Node3D.new()
	holder.name = "Flood"
	add_child(holder)
	holder.transform = Transform3D(Basis.looking_at(target - at, Vector3.UP if absf((target - at).normalized().y) < 0.95 else Vector3.FORWARD), at)
	var black := _paint(Color(0.03, 0.03, 0.035), 0.5, 0.4)
	ZoneKit.block(holder, Vector3(0.22, 0.16, 0.12), Vector3(0, 0, 0.06), black, "FloodBody")
	ZoneKit.block(holder, Vector3(0.19, 0.13, 0.01), Vector3(0, 0, -0.006), ZoneKit.glow(colour, 2.2), "FloodLens")
	var foot := ZoneKit.block(self, Vector3(0.05, 0.3, 0.05), at - Vector3(0, 0.2, 0), black, "FloodFoot")
	foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beam := SpotLight3D.new()
	beam.name = "FloodBeam"
	beam.light_color = colour
	beam.light_energy = energy
	beam.spot_range = 20.0
	beam.spot_angle = 32.0
	beam.spot_attenuation = 1.2
	beam.light_specular = 0.2
	beam.position = Vector3(0, 0, -0.03)
	holder.add_child(beam)
	_lights.append([beam, energy, 0.0, &"crew"])


# --- the crystal grotto -------------------------------------------------------------------------

## The grotto's plan: as far round the floor as it ever was -- 12.8 m of pit ahead of its front,
## 4.7 m of rubble behind its back -- so the vault grows with the room rather than pressing its
## back wall flat against the back of house.
const GROTTO_AHEAD := 12.8
const GROTTO_BEHIND := 4.7


func _grotto_centre() -> Vector2:
	return Vector2(0.0, (Studio.ROOM_FRONT - GROTTO_AHEAD + LIVE_ROOM_BACK + GROTTO_BEHIND) * 0.5)


func _grotto_size() -> Vector2:
	return Vector2(live_room_half() + 5.5, (LIVE_ROOM_BACK + GROTTO_BEHIND - Studio.ROOM_FRONT + GROTTO_AHEAD) * 0.5)


func _grotto_h(x: float, z: float) -> float:
	var o := _outside(x, z, live_room_half(), Studio.ROOM_FRONT, LIVE_ROOM_BACK)
	if o <= 0.0:
		return -0.07
	var n := _ground_noise.get_noise_2d(x, z)
	var h := -0.07 + smoothstep(0.0, 2.5, o) * (0.4 + o * 0.16) + (n * 0.5 + 0.3) * smoothstep(0.2, 1.4, o) * 0.55
	# Ahead of the desk, past the lip, the floor falls away into the pit.
	var ahead := Studio.ROOM_FRONT - z
	return h - smoothstep(PIT_FROM, 7.5, ahead) * (PIT_DEPTH + n * 0.6)


func _build_grotto() -> void:
	var c := _grotto_centre()
	var size := _grotto_size()
	var wall := _rock({"dark": Color(0.07, 0.064, 0.08), "light": Color(0.3, 0.27, 0.32),
			"strata_tint": Color(0.32, 0.25, 0.22), "scale": 1.8, "bump": 1.0, "strata": 0.5, "wet_below": 0.8})
	var outline := func(u: float, v: float) -> Vector3: return _dome_point(u, v, c, size.x, size.y, 3.0, GROTTO_PROFILE)
	var inside := func(_p: Vector3) -> Vector3: return Vector3(c.x, 2.0, c.y)
	_sculpt(200, 44, true, outline, inside, 1.3, 0.55, 3)
	_shell_meshes(true, 8, wall, "Vault")
	# The working floor: the cave's own floor, levelled and worn smooth, wet enough to hold the
	# crystals' light. Bigger than the room, so the rubble round it rises through its edge.
	var flowstone := _rock({"dark": Color(0.08, 0.074, 0.09), "light": Color(0.26, 0.24, 0.28),
			"scale": 1.2, "bump": 0.35, "strata": 0.0, "wet_below": 0.4})
	_lay_floor(flowstone, 1.0, 1.0, 1.0, 1.0)
	var half := size.x + 1.0
	var spread := func(u: float, v: float) -> Vector2: return Vector2(lerpf(-half, half, u),
			lerpf(c.y - size.y - 1.0, c.y + size.y + 1.0, v))
	var in_cave := func(p: Vector3) -> bool: return _in_plan(p.x, p.z, c, size.x, size.y, 3.0, 0.8)
	var keep := func(a: Vector3, b: Vector3, d: Vector3, e: Vector3) -> bool: return in_cave.call(a) \
			or in_cave.call(b) or in_cave.call(d) or in_cave.call(e)
	_lay_ground(110, 80, spread, keep, wall, 4)
	var drip := _rock({"dark": Color(0.14, 0.12, 0.11), "light": Color(0.45, 0.4, 0.38), "scale": 0.9,
			"bump": 0.8, "strata": 0.2, "wet_below": 40.0})
	_hang_stalactites(drip, 150, Vector2(0.6, 3.4), 0.5)
	_raise_stalagmites(drip, 80, Vector2(0.4, 2.4))
	_grow_crystals(wall)
	_light_the_grotto()
	_lay_mist([[0.22, Color(0.32, 0.26, 0.5), 0.2], [-2.6, Color(0.36, 0.3, 0.6), 0.32]])
	_drip()
	_dress_zones({"riser_top": flowstone, "riser_skirt": _pewter(), "frame": _pewter(),
			"glass": _glass(Color(0.55, 0.45, 0.8, 0.09)), "inlay": ZoneKit.glow(AMETHYST, 1.3),
			"top": Materials.cached_scanned("cave_slate", "concrete_floor_worn_001", "2k", 0.8, Color(0.22, 0.2, 0.26)),
			"legs": _pewter(), "booth_light": Color(0.85, 0.82, 1.0), "shelf_lamp": Color(0.9, 0.84, 1.0)})


## The floor plane at y = 0 every venue has: the working floor, wider than the room by `left` and
## `right` and longer by `front` and `back`, under everything the crew stood on it.
func _lay_floor(material: Material, left: float, right: float, front: float, back: float) -> MeshInstance3D:
	var x0 := -live_room_half() - left
	var x1 := live_room_half() + right
	var z0 := Studio.ROOM_FRONT - front
	var z1 := LIVE_ROOM_BACK + back
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(x1 - x0, z1 - z0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	floor_mesh.material_override = material
	add_child(floor_mesh)
	return floor_mesh


## Stalactites from the roof, three shapes and every size: never with a tip lower than the head
## room over the floor, so the long ones hang over the rubble and the pit.
func _hang_stalactites(material: Material, count: int, length: Vector2, from_v: float, mirror_too := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21 + variant
	var spots := [[], [], []]
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 20:
		tries += 1
		var on := _on_rock(rng, from_v, 1.0)
		var p: Vector3 = on[0]
		var n: Vector3 = on[1]
		# Only where the rock faces down: a roof, not a wall.
		if n.y > -0.45:
			continue
		var l := lerpf(length.x, length.y, pow(rng.randf(), 2.2))
		var floor_y := 0.0 if _over_floor(p, 0.5) else _ground_h(p.x, p.z)
		var lowest := ROOF_CLEAR if _over_floor(p, 0.5) else floor_y + 2.2
		if p.y - l < lowest:
			l = p.y - lowest
		if l < length.x * 0.4:
			continue
		var r := pow(l, 0.55) * rng.randf_range(0.7, 1.1)
		var at := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, l, r)), p + Vector3(0, 0.05, 0))
		(spots[rng.randi() % 3] as Array).append(at)
		placed += 1
	for k in 3:
		var list: Array[Transform3D] = []
		list.assign(spots[k])
		if list.is_empty():
			continue
		_many(FORMATIONS, "Stalactite%d" % k, list, {"rock": material}, "Stalactites%d" % k)
		if mirror_too:
			_many(FORMATIONS, "Stalactite%d" % k, list, {"rock": _cut(material as ShaderMaterial, false)},
					"StalactitesMirrored%d" % k, [], true)


## Stalagmites on the ground round the floor, clear of it, bigger the further out.
func _raise_stalagmites(material: Material, count: int, height: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + variant
	var spots := [[], [], []]
	var c := _grotto_centre()
	var size := _grotto_size()
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 30:
		tries += 1
		var x := rng.randf_range(-size.x, size.x)
		var z := rng.randf_range(c.y - size.y, c.y + size.y)
		if not _in_plan(x, z, c, size.x, size.y, 3.0, -1.2):
			continue
		var o := _outside(x, z, live_room_half(), Studio.ROOM_FRONT, LIVE_ROOM_BACK)
		if o < 0.9:
			continue
		var h := lerpf(height.x, height.y, pow(rng.randf(), 1.8)) * clampf(0.5 + o * 0.15, 0.5, 1.6)
		var r := pow(h, 0.6) * rng.randf_range(0.75, 1.15)
		var y := _ground_h(x, z)
		(spots[rng.randi() % 3] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, h, r)),
				Vector3(x, y - 0.05, z)))
		placed += 1
	for k in 3:
		var list: Array[Transform3D] = []
		list.assign(spots[k])
		if not list.is_empty():
			_many(FORMATIONS, "Stalagmite%d" % k, list, {"rock": material}, "Stalagmites%d" % k)
	# Three columns in the pit, where the roof has had the longest to come down to the floor.
	var cols: Array[Transform3D] = []
	for at in [Vector2(-4.5, -11.0), Vector2(5.8, -9.5), Vector2(-9.5, -6.5)]:
		var x := _wide(at.x)
		var z := _ahead(at.y)
		var y := _ground_h(x, z)
		var top := _roof_over(x, z)
		var span := top - y + 0.3
		var r := 0.9 + span * 0.05
		cols.append(Transform3D(Basis.from_scale(Vector3(r * 2.2, span, r * 2.2)), Vector3(x, y - 0.15, z)))
	_many(FORMATIONS, "Column", cols, {"rock": material}, "Columns")


## The crystals: amethyst and ice-blue quartz, on the walls and on the floor round the room, a
## row of them along the lip in front of the desk, and the giants standing up out of the pit.
## Violet on the left and down in the pit, blue on the right, mixed where they meet.
func _grow_crystals(host: Material) -> void:
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://core/venues/shaders/cave_crystal.gdshader")
	glass.set_shader_parameter("glow", 1.0)
	_pulsed.append(glass)
	var swap := {"crystal": glass, "matrix": host}
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var kinds := {}
	var place := func(kind: String, at: Transform3D, colour: Color) -> void:
		if not kinds.has(kind):
			kinds[kind] = [[], []]
		kinds[kind][0].append(at)
		kinds[kind][1].append(colour)
		crystal_spots.append(at)
	var colour_at := func(p: Vector3, bright: float) -> Color:
		var blue := smoothstep(-3.0, 4.0, p.x + _ground_noise.get_noise_2d(p.x * 3.0, p.z * 3.0) * 4.0)
		if p.z < Studio.ROOM_FRONT - 4.0:
			blue *= 0.35
		var tint: Color = AMETHYST.lerp(QUARTZ, 1.0 if rng.randf() < blue else 0.0)
		return Color(tint.r, tint.g, tint.b, bright * rng.randf_range(0.7, 1.3))
	# On the walls, growing out of the rock and a little upward.
	var tries := 0
	var on_walls := 0
	while on_walls < 220 and tries < 4000:
		tries += 1
		var on := _on_rock(rng, 0.08, 0.62)
		var p: Vector3 = on[0]
		var n: Vector3 = on[1]
		if absf(n.y) > 0.7:
			continue
		var s := rng.randf_range(0.7, 2.4) * (1.0 + maxf(0.0, -p.y) * 0.15)
		# Its reach out of the wall, kept off the floor you walk on.
		if _over_floor(p + n * 0.8 * s, 0.3) and p.y < ROOF_CLEAR:
			continue
		var up := (n + Vector3(0, 0.45, 0)).normalized()
		var kind := "Cluster%d" % (rng.randi() % 4)
		place.call(kind, Transform3D(_standing(up, rng.randf() * TAU, Vector3.ONE * s), p - n * 0.06),
				colour_at.call(p, 1.0))
		on_walls += 1
	# On the floor round the room.
	var c := _grotto_centre()
	var size := _grotto_size()
	var on_floor := 0
	tries = 0
	while on_floor < 110 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-size.x, size.x)
		var z := rng.randf_range(c.y - size.y, c.y + size.y)
		if not _in_plan(x, z, c, size.x, size.y, 3.0, -1.0):
			continue
		var o := _outside(x, z, live_room_half(), Studio.ROOM_FRONT, LIVE_ROOM_BACK)
		if o < 0.5:
			continue
		var p := Vector3(x, _ground_h(x, z), z)
		var s := rng.randf_range(0.6, 1.6) * clampf(0.6 + o * 0.12, 0.6, 2.2)
		var tilt := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3))
		place.call("Cluster%d" % (rng.randi() % 4), Transform3D(_standing(tilt, rng.randf() * TAU, Vector3.ONE * s),
				p - Vector3(0, 0.04, 0)), colour_at.call(p, 0.9))
		on_floor += 1
	# Along the lip in front of the desk: low druses, so the view over them into the pit is clear.
	var half := live_room_half()
	var x := -half - 0.4
	while x < half + 0.4:
		x += rng.randf_range(0.4, 0.9)
		var z := Studio.ROOM_FRONT - rng.randf_range(0.9, 1.5)
		var p := Vector3(x, _ground_h(x, z), z)
		var kind := "Cluster0" if rng.randf() < 0.6 else "Cluster3"
		place.call(kind, Transform3D(_standing(Vector3(rng.randf_range(-0.2, 0.2), 1.0, -0.25), rng.randf() * TAU,
				Vector3.ONE * rng.randf_range(0.6, 1.0)), p - Vector3(0, 0.03, 0)), colour_at.call(p, 1.0))
	# The giants: great single crystals leaning up out of the pit and out of the walls beside
	# it, three to seven metres long.
	for spec in [[-3.2, -9.5, 4.6], [1.5, -11.5, 5.0], [4.6, -8.0, 3.6], [-6.8, -12.0, 4.2], [7.6, -12.5, 4.8],
			[0.0, -14.0, 3.4], [-1.4, -7.4, 2.4], [2.8, -6.6, 2.2], [-9.4, -3.5, 3.0], [9.8, -2.0, 3.2],
			[-5.4, -14.2, 3.0], [5.6, -14.6, 2.6]]:
		var gx := _wide(spec[0])
		var gz := _ahead(spec[1])
		var p := Vector3(gx, _ground_h(gx, gz), gz)
		var lean := Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.2, 0.6))
		var s: float = spec[2]
		place.call("Shard", Transform3D(_standing(lean, rng.randf() * TAU, Vector3(s * 0.9, s, s * 0.9)), p),
				colour_at.call(p, 0.75))
		# Each giant has a brood of points round its foot.
		for k in 3:
			var off := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			var q := p + off
			q.y = _ground_h(q.x, q.z)
			place.call("Cluster%d" % [1, 2, 3][k], Transform3D(_standing(Vector3(off.x, 2.0, off.z), rng.randf() * TAU,
					Vector3.ONE * rng.randf_range(1.2, 2.2)), q - Vector3(0, 0.05, 0)), colour_at.call(q, 0.9))
	# Round the back of house, just off the floor: big clusters whose light is the zones' light.
	# Each is [across (-1..1 of the floor's width, +-1 a side), along (over 0.9: the back), kind].
	for spec in [[-0.75, 1.0, 0], [-0.3, 1.0, 1], [0.15, 1.0, 0], [0.6, 1.0, 1], [-1.0, -0.35, 0], [1.0, -0.2, 1],
			[-1.0, 0.45, 1], [1.0, 0.5, 0], [-1.0, 0.05, 0], [1.0, 0.15, 1]]:
		var side := absf(spec[0]) > 0.99
		var at_back: bool = spec[1] > 0.9
		var bx: float = signf(spec[0]) * (half + 0.95) if side else spec[0] * (half + 0.9)
		var bz: float = LIVE_ROOM_BACK + 1.0 if at_back else lerpf(Studio.ROOM_BACK, LIVE_ROOM_BACK, 0.5 + spec[1])
		var p := Vector3(bx, _ground_h(bx, bz), bz)
		var tint: Color = AMETHYST if spec[2] == 0 else QUARTZ
		var inward := Vector3(-signf(bx) * 0.4 if side else 0.0, 1.0, -0.4 if at_back else 0.0)
		place.call("Cluster2" if rng.randf() < 0.6 else "Cluster1", Transform3D(_standing(inward, rng.randf() * TAU,
				Vector3.ONE * rng.randf_range(1.5, 2.1)), p - Vector3(0, 0.05, 0)), Color(tint.r, tint.g, tint.b, 1.0))
		_light(p + Vector3(0, 0.9, 0), tint, 2.4, 6.5, &"crystal", 0.8)
	for kind: String in kinds:
		var spots: Array[Transform3D] = []
		spots.assign(kinds[kind][0])
		var colours: Array[Color] = []
		colours.assign(kinds[kind][1])
		var node := _many(CRYSTALS, kind, spots, swap, "Crystals" + kind, colours)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The grotto's light: what the crystals throw, violet and blue, from where they are thickest;
## and four floods the crew set on the rock, washing up the vault so its stalactites stand out
## of the dark.
func _light_the_grotto() -> void:
	var half := live_room_half()
	for spec in [[Vector3(_wide(-3.0), -1.0, _ahead(-9.0)), AMETHYST, 6.0, 14.0],
			[Vector3(_wide(3.0), -1.4, _ahead(-11.5)), AMETHYST, 5.0, 14.0],
			[Vector3(_wide(6.5), -1.0, _ahead(-9.5)), QUARTZ, 4.5, 12.0], [Vector3(-half - 2.6, 1.6, -1.0), AMETHYST, 3.0, 9.0],
			[Vector3(half + 2.6, 1.6, 0.5), QUARTZ, 3.0, 9.0], [Vector3(-half - 2.2, 1.8, _along(5.5)), AMETHYST, 2.6, 8.0],
			[Vector3(half + 2.2, 1.8, _along(6.0)), QUARTZ, 2.6, 8.0], [Vector3(0.0, 2.0, LIVE_ROOM_BACK + 2.4), AMETHYST, 2.6, 9.0],
			[Vector3(0.0, 0.6, Studio.ROOM_FRONT - 1.4), AMETHYST.lerp(QUARTZ, 0.5), 1.0, 4.0]]:
		_light(spec[0], spec[1], spec[2], spec[3], &"crystal", 0.8)
	# The back of house is twice the floor it was: the crystals over it, high on the vault, throw
	# down onto the zones' middle as well as round their edges.
	var mid := (Studio.ROOM_BACK + LIVE_ROOM_BACK) * 0.5
	for spec in [[Vector3(-half * 0.5, 4.4, mid), AMETHYST], [Vector3(half * 0.5, 4.4, mid), QUARTZ],
			[Vector3(0.0, 4.4, LIVE_ROOM_BACK - 1.6), AMETHYST.lerp(QUARTZ, 0.5)]]:
		_light(spec[0], spec[1], 2.2, 9.0, &"crystal", 0.8)
	var warm := Color(1.0, 0.86, 0.72)
	for spec in [[Vector3(-half - 1.4, 0.0, -2.2), Vector3(_wide(-4.0), 14.0, _ahead(-6.0))],
			[Vector3(half + 1.4, 0.0, -1.6), Vector3(_wide(4.0), 14.0, _ahead(-5.0))],
			[Vector3(-half - 1.2, 0.0, LIVE_ROOM_BACK + 0.8), Vector3(_wide(-2.0), 13.0, _along(2.0 + 2.8))],
			[Vector3(half + 1.2, 0.0, LIVE_ROOM_BACK + 0.8), Vector3(_wide(2.0), 13.0, _along(2.5 + 2.8))]]:
		var at: Vector3 = spec[0]
		at.y = maxf(_ground_h(at.x, at.z), 0.0) + 0.3
		_flood(at, spec[1], warm, 7.0)


## Sheets of mist lying low: each [height, colour, density], kept off the working floor.
func _lay_mist(sheets: Array) -> void:
	var c := _grotto_centre() if variant == GROTTO else Vector2(0.0, -7.0)
	var size := Vector2(live_room_half() + 9.0, 24.0)
	for k in sheets.size():
		var spec: Array = sheets[k]
		var m := ShaderMaterial.new()
		m.shader = preload("res://core/venues/shaders/cave_mist.gdshader")
		m.set_shader_parameter("tint", spec[1])
		m.set_shader_parameter("density", spec[2])
		m.set_shader_parameter("keep_clear", Vector4(-live_room_half() - 0.3, Studio.ROOM_FRONT - 0.3,
				live_room_half() + 0.3, LIVE_ROOM_BACK + 0.3))
		_pulsed.append(m)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y: float = spec[0]
		var corners := [Vector3(c.x - size.x, y, c.y - size.y), Vector3(c.x + size.x, y, c.y - size.y),
				Vector3(c.x + size.x, y, c.y + size.y), Vector3(c.x - size.x, y, c.y + size.y)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i in 4:
			st.set_uv(uvs[i])
			st.set_normal(Vector3.UP)
			st.add_vertex(corners[i])
		_quad(st, 0, 1, 2, 3, corners[0], corners[1], corners[2], Vector3.UP)
		var sheet := MeshInstance3D.new()
		sheet.name = "Mist%d" % k
		sheet.mesh = st.commit()
		sheet.material_override = m
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sheet)


## Water dripping from the tips of a few stalactites over the rubble, where you can see it fall.
func _drip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var drop := QuadMesh.new()
	drop.size = Vector2(0.008, 0.05)
	var wet := StandardMaterial3D.new()
	wet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	wet.albedo_color = Color(0.75, 0.8, 1.0, 0.55)
	drop.material = wet
	var made := 0
	var tries := 0
	while made < 10 and tries < 400:
		tries += 1
		var on := _on_rock(rng, 0.45, 0.8)
		var p: Vector3 = on[0]
		if (on[1] as Vector3).y > -0.5 or _over_floor(p, 0.8) or _outside(p.x, p.z, live_room_half(), Studio.ROOM_FRONT,
				LIVE_ROOM_BACK) > 6.0:
			continue
		var fall := p.y - _ground_h(p.x, p.z)
		var drips := GPUParticles3D.new()
		drips.name = "Drips"
		drips.amount = 2
		drips.lifetime = sqrt(2.0 * fall / 9.8)
		drips.explosiveness = 0.0
		drips.randomness = 0.6
		var motion := ParticleProcessMaterial.new()
		motion.gravity = Vector3(0, -9.8, 0)
		motion.direction = Vector3(0, -1, 0)
		motion.initial_velocity_min = 0.0
		motion.initial_velocity_max = 0.1
		drips.process_material = motion
		drips.draw_pass_1 = drop
		drips.position = p - Vector3(0, 0.3, 0)
		drips.visibility_aabb = AABB(Vector3(-0.5, -fall - 0.5, -0.5), Vector3(1, fall + 1.0, 1))
		add_child(drips)
		made += 1


# --- the glowworm lake ---------------------------------------------------------------------------

## The lake's cave the same way: 23.8 m of water and shore ahead of the landing, 5.7 m behind it.
const LAKE_AHEAD := 23.8
const LAKE_BEHIND := 5.7


func _lake_centre() -> Vector2:
	return Vector2(0.0, (Studio.ROOM_FRONT - LAKE_AHEAD + LIVE_ROOM_BACK + LAKE_BEHIND) * 0.5)


func _lake_size() -> Vector2:
	return Vector2(live_room_half() + 8.0, (LIVE_ROOM_BACK + LAKE_BEHIND - Studio.ROOM_FRONT + LAKE_AHEAD) * 0.5)


## Where the shore is, at x: straight across under the landing's front, then drawn forward along
## the walls, so the lake is held in a bay of rock in front of the desk.
func _shore_z(x: float) -> float:
	return Studio.ROOM_FRONT + 0.3 - smoothstep(live_room_half() + 2.0, live_room_half() + 7.5, absf(x)) * 6.5 \
			+ _ground_noise.get_noise_1d(x * 0.6) * 0.8


func _lake_h(x: float, z: float) -> float:
	var n := _ground_noise.get_noise_2d(x, z)
	var deck := _outside(x, z, live_room_half() + 0.45, Studio.ROOM_FRONT - 0.6, LIVE_ROOM_BACK + 0.45)
	var land := -0.36 + n * 0.04
	if deck > 0.0:
		land += smoothstep(0.0, 3.0, deck) * (0.6 + deck * 0.22) + (n * 0.5 + 0.3) * smoothstep(0.0, 1.5, deck) * 0.6
	var into := _shore_z(x) - z
	if into <= 0.0:
		return land
	var under := WATER_Y - 0.12 - smoothstep(0.0, 2.5, into) * 1.4
	return lerpf(land, under, smoothstep(0.0, 0.9, into))


func _build_lake() -> void:
	var c := _lake_centre()
	var size := _lake_size()
	var rock := _rock({"dark": Color(0.05, 0.056, 0.058), "light": Color(0.24, 0.25, 0.24),
			"strata_tint": Color(0.1, 0.1, 0.09), "scale": 2.0, "bump": 0.9, "strata": 0.7, "wet_below": 0.3})
	var real := _cut(rock, true)
	var mirrored := _cut(rock, false)
	var outline := func(u: float, v: float) -> Vector3: return _dome_point(u, v, c, size.x, size.y, 3.2, LAKE_PROFILE)
	var inside := func(_p: Vector3) -> Vector3: return Vector3(c.x, 1.5, c.y)
	_sculpt(240, 34, true, outline, inside, 0.8, 0.35, 5)
	for mi in _shell_meshes(true, 8, real, "Roof"):
		var twin := MeshInstance3D.new()
		twin.name = mi.name + "Mirrored"
		twin.mesh = mi.mesh
		twin.material_override = mirrored
		twin.transform = _mirror()
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(twin)
	var half := size.x + 1.0
	var deep := WATER_Y - 0.45
	var in_cave := func(p: Vector3) -> bool: return _in_plan(p.x, p.z, c, size.x, size.y, 3.2, 0.8)
	# Under the lake there is no ground: the reflection is drawn there.
	var keep := func(a: Vector3, b: Vector3, d: Vector3, e: Vector3) -> bool: return \
			not (a.y < deep and b.y < deep and d.y < deep and e.y < deep) \
			and (in_cave.call(a) or in_cave.call(b) or in_cave.call(d) or in_cave.call(e))
	var spread := func(u: float, v: float) -> Vector2: return Vector2(lerpf(-half, half, u),
			lerpf(c.y - size.y - 1.0, c.y + size.y + 1.0, v))
	for mi in _lay_ground(120, 100, spread, keep, real, 4):
		var twin := MeshInstance3D.new()
		twin.name = mi.name + "Mirrored"
		twin.mesh = mi.mesh
		twin.material_override = mirrored
		twin.transform = _mirror()
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(twin)
	_fill_the_lake()
	_build_landing()
	_moor_the_boat()
	_light_the_glowworms()
	var straws := _rock({"dark": Color(0.08, 0.075, 0.07), "light": Color(0.26, 0.25, 0.23), "scale": 0.8,
			"bump": 0.6, "strata": 0.1, "wet_below": 40.0})
	_hang_stalactites(_cut(straws, true), 90, Vector2(0.2, 1.4), 0.55, true)
	_scatter_boulders(real, mirrored)
	_lay_mist([[WATER_Y + 0.14, Color(0.12, 0.3, 0.3), 0.16]])
	var boards := _planks(Color(0.62, 0.56, 0.5))
	var timber := Materials.cached_scanned("cave_timber", "weathered_brown_planks", "2k", 0.7, Color(0.32, 0.26, 0.22))
	_dress_zones({"riser_top": boards, "riser_skirt": timber, "frame": timber,
			"glass": _glass(Color(0.4, 0.7, 0.68, 0.08)), "inlay": ZoneKit.glow(WORM, 1.0), "top": boards,
			"legs": timber, "booth_light": LANTERN, "shelf_lamp": LANTERN})


## The water: one dark sheet over the reflection under it.
func _fill_the_lake() -> void:
	var c := _lake_centre()
	var size := _lake_size()
	var water := MeshInstance3D.new()
	water.name = "Lake"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x * 2.0 + 2.0, size.y * 2.0 + 2.0)
	water.mesh = plane
	water.position = Vector3(c.x, WATER_Y, c.y)
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/cave_water.gdshader")
	water.material_override = m
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


## The landing: boards over the rock and the water's edge, a fascia round its edge on posts
## down into the lake, a rope rail along its front on posts, lanterns at its corners, and a
## jetty off its front-left corner out over the water.
func _build_landing() -> void:
	var half := live_room_half()
	var front := Studio.ROOM_FRONT - 0.6
	var back := LIVE_ROOM_BACK + 0.45
	var edge := half + 0.45
	_lay_floor(_planks(Color(0.62, 0.56, 0.5)), 0.45, 0.45, 0.6, 0.45)
	var timber := Materials.cached_scanned("cave_timber", "weathered_brown_planks", "2k", 0.7, Color(0.32, 0.26, 0.22))
	var beam := 0.08
	var deep := 0.3
	var y := -0.005 - deep * 0.5
	# The fascia: the front and back take the corners.
	for spec in [[Vector3(edge * 2.0 + beam * 2.0, deep, beam), Vector3(0, y, front - beam * 0.5)],
			[Vector3(edge * 2.0 + beam * 2.0, deep, beam), Vector3(0, y, back + beam * 0.5)],
			[Vector3(beam, deep - 0.004, back - front), Vector3(-edge - beam * 0.5, y - 0.002, (front + back) * 0.5)],
			[Vector3(beam, deep - 0.004, back - front), Vector3(edge + beam * 0.5, y - 0.002, (front + back) * 0.5)]]:
		ZoneKit.block(self, spec[0], spec[1], timber, "Fascia")
	# Posts under the edge, down into the water and the rock.
	var post := 0.16
	var length := 1.6
	var posts: Array[Vector3] = []
	var x := -edge + 0.25
	while x < edge:
		posts.append(Vector3(x, 0, front + 0.12))
		x += 1.8
	var z := front + 1.9
	while z < back:
		posts.append(Vector3(-edge + 0.12, 0, z))
		posts.append(Vector3(edge - 0.12, 0, z))
		z += 2.2
	for p in posts:
		ZoneKit.block(self, Vector3(post, length, post), p + Vector3(0, -0.31 - length * 0.5, 0), timber, "Pile")
	# The rope rail along the front, a lantern on each end post.
	var rail_z := front + 0.09
	var hemp := _paint(Color(0.42, 0.34, 0.24), 0.9)
	var stops: Array[float] = []
	var span := ceili((edge * 2.0 - 0.3) / 2.4)
	for i in span + 1:
		stops.append(lerpf(-edge + 0.15, edge - 0.15, float(i) / span))
	var jetty_x := _jetty_x()
	for i in stops.size():
		ZoneKit.block(self, Vector3(0.07, 0.95, 0.07), Vector3(stops[i], 0.475, rail_z), timber, "RailPost")
		ZoneKit.block(self, Vector3(0.09, 0.03, 0.09), Vector3(stops[i], 0.965, rail_z), timber, "RailCap")
		if i == stops.size() - 1:
			continue
		# No rope across the head of the jetty.
		if absf((stops[i] + stops[i + 1]) * 0.5 - jetty_x) < JETTY_WIDTH * 0.5 + 0.2:
			continue
		_rope(Vector3(stops[i], 0.86, rail_z), Vector3(stops[i + 1], 0.86, rail_z), 0.12, hemp)
	for at in [Vector3(-edge + 0.15, 0.98, rail_z), Vector3(edge - 0.15, 0.98, rail_z)]:
		_lantern(at, true)
	# Lanterns on taller posts along the sides and at the back corners, so the back of house
	# has light, each on the landing's edge clear of the floor you walk on.
	var mid := (Studio.ROOM_BACK + LIVE_ROOM_BACK) * 0.5
	for spec in [Vector3(-edge + 0.12, 0, 0.0), Vector3(edge - 0.12, 0, 0.0), Vector3(-edge + 0.12, 0, mid),
			Vector3(edge - 0.12, 0, mid), Vector3(-edge + 0.12, 0, back - 0.12), Vector3(edge - 0.12, 0, back - 0.12),
			Vector3(-half * 0.45, 0, back - 0.12), Vector3(half * 0.45, 0, back - 0.12)]:
		var at: Vector3 = spec
		ZoneKit.block(self, Vector3(0.09, 1.7, 0.09), at + Vector3(0, 0.85, 0), timber, "LanternPost")
		ZoneKit.block(self, Vector3(0.3, 0.05, 0.05), at + Vector3(signf(-at.x) * 0.12, 1.66, 0), timber, "LanternArm")
		_lantern(at + Vector3(signf(-at.x) * 0.24, 1.36, 0), false, 0.0)
	# The jetty.
	var jz0 := front - beam
	var jz1 := front - beam - JETTY_RUN
	var deck := ZoneKit.block(self, Vector3(JETTY_WIDTH, 0.05, JETTY_RUN), Vector3(jetty_x, -0.055, (jz0 + jz1) * 0.5),
			_planks(Color(0.55, 0.5, 0.45)), "Jetty")
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	z = jz0 - 0.4
	while z > jz1:
		for side in [-1.0, 1.0]:
			ZoneKit.block(self, Vector3(0.14, 1.9, 0.14), Vector3(jetty_x + side * (JETTY_WIDTH * 0.5 - 0.1), -0.08 - 0.95, z),
					timber, "JettyPile")
		z -= 1.8
	var end := Vector3(jetty_x - JETTY_WIDTH * 0.5 + 0.1, -0.03, jz1 + 0.12)
	ZoneKit.block(self, Vector3(0.1, 1.45, 0.1), end + Vector3(0, 0.725, 0), timber, "JettyPost")
	_lantern(end + Vector3(0, 1.46, 0), true)
	# A cleat on the jetty's edge for the boat's line.
	ZoneKit.block(self, Vector3(0.05, 0.06, 0.24), Vector3(jetty_x + JETTY_WIDTH * 0.5 - 0.08, -0.0, jz0 - 2.0),
			_iron(), "Cleat")


func _jetty_x() -> float:
	return -live_room_half() + JETTY_IN


## A rope between two points, sagging `sag` in the middle, as a few straight lengths.
func _rope(a: Vector3, b: Vector3, sag: float, material: Material) -> void:
	var steps := 5
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var piece := MeshInstance3D.new()
		piece.name = "Rope"
		var rod := CylinderMesh.new()
		rod.top_radius = 0.012
		rod.bottom_radius = 0.012
		rod.height = prev.distance_to(p)
		rod.radial_segments = 6
		rod.rings = 1
		piece.mesh = rod
		piece.material_override = material
		piece.transform = Transform3D(_standing(p - prev, 0.0, Vector3.ONE), (prev + p) * 0.5)
		add_child(piece)
		prev = p


## An oil lantern: a base, four iron corners round a lit glass, a pyramid roof and a ring; its
## light flickers. `reflected` also hangs its reflection in the lake.
func _lantern(at: Vector3, reflected: bool, _yaw := 0.0) -> void:
	var holder := Node3D.new()
	holder.name = "Lantern"
	holder.position = at
	add_child(holder)
	var iron := _iron()
	ZoneKit.block(holder, Vector3(0.15, 0.02, 0.15), Vector3(0, 0.01, 0), iron, "LanternBase")
	ZoneKit.block(holder, Vector3(0.11, 0.176, 0.11), Vector3(0, 0.024 + 0.088, 0), ZoneKit.glow(LANTERN, 1.5), "LanternGlass")
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			ZoneKit.block(holder, Vector3(0.014, 0.195, 0.014), Vector3(cx * 0.062, 0.02 + 0.0975, cz * 0.062), iron,
					"LanternCorner")
	var roof := MeshInstance3D.new()
	roof.name = "LanternRoof"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.012
	cone.bottom_radius = 0.11
	cone.height = 0.08
	cone.radial_segments = 4
	cone.rings = 1
	roof.mesh = cone
	roof.material_override = iron
	roof.rotation.y = PI * 0.25
	roof.position = Vector3(0, 0.218 + 0.04, 0)
	holder.add_child(roof)
	var ring := MeshInstance3D.new()
	ring.name = "LanternRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.018
	torus.outer_radius = 0.026
	torus.rings = 12
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = iron
	ring.rotation.x = PI * 0.5
	ring.position = Vector3(0, 0.33, 0)
	holder.add_child(ring)
	_light(at + Vector3(0, 0.11, 0), LANTERN, 2.9, 8.0, &"flame")
	if reflected:
		var twin := holder.duplicate() as Node3D
		twin.name = "LanternMirrored"
		twin.transform = _mirror() * holder.transform
		add_child(twin)


## The rowing boat (cave_boat.glb), tied up alongside the jetty, its line to the cleat.
func _moor_the_boat() -> void:
	var jetty_x := _jetty_x()
	var at := Vector3(jetty_x + JETTY_WIDTH * 0.5 + 0.66, WATER_Y, Studio.ROOM_FRONT - 0.6 - 3.2)
	var hull := _paint(Color(0.12, 0.22, 0.2), 0.55)
	hull.metallic_specular = 0.45
	var boat := _model("cave_boat.glb", Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.06), at),
			{"hull": hull, "wood": _planks(Color(0.6, 0.52, 0.42)), "iron": _iron()})
	boat.name = "Boat"
	_rope(Vector3(jetty_x + JETTY_WIDTH * 0.5 - 0.08, 0.02, Studio.ROOM_FRONT - 2.6),
			at + Vector3(0.0, 0.42, -1.42), 0.18, _paint(Color(0.42, 0.34, 0.24), 0.9))


## The glowworms: thousands of points of blue-green on the roof, thickest over the lake and in
## drifts elsewhere, each with its threads hanging; and all of it again in the water.
func _light_the_glowworms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var clumps := FastNoiseLite.new()
	clumps.seed = 3
	clumps.frequency = 0.18
	var dots: Array[Transform3D] = []
	var threads: Array[Transform3D] = []
	var tries := 0
	while dots.size() < 6500 and tries < 120000:
		tries += 1
		var on := _on_rock(rng, 0.3, 1.0)
		var p: Vector3 = on[0]
		var n: Vector3 = on[1]
		if n.y > 0.1 or p.y < 1.4:
			continue
		var want := 0.25 + (0.55 if p.z < Studio.ROOM_FRONT else 0.0) + clumps.get_noise_3dv(p) * 0.6
		if rng.randf() > want:
			continue
		var at := p + n * 0.03
		dots.append(Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.025, 0.055)), at))
		if rng.randf() < 0.75:
			var l := rng.randf_range(0.1, 0.7)
			threads.append(Transform3D(Basis.from_scale(Vector3(0.008, l, 1.0)), at - Vector3(0, 0.01, 0)))
	glowworms = dots.size()
	var dot := QuadMesh.new()
	dot.size = Vector2.ONE
	var line := QuadMesh.new()
	line.size = Vector2.ONE
	line.center_offset = Vector3(0, -0.5, 0)
	for mirror in [false, true]:
		var glow := ShaderMaterial.new()
		glow.shader = preload("res://core/venues/shaders/cave_glowworm.gdshader")
		glow.set_shader_parameter("colour", WORM)
		glow.set_shader_parameter("dim", 0.55 if mirror else 1.0)
		var silk := ShaderMaterial.new()
		silk.shader = preload("res://core/venues/shaders/cave_thread.gdshader")
		silk.set_shader_parameter("colour", WORM)
		silk.set_shader_parameter("dim", 0.5 if mirror else 1.0)
		_pulsed.append(glow)
		_pulsed.append(silk)
		for spec in [[dot, dots, glow, "Glowworms"], [line, threads, silk, "Threads"]]:
			var spots: Array[Transform3D] = spec[1]
			var many := MultiMesh.new()
			many.transform_format = MultiMesh.TRANSFORM_3D
			many.mesh = spec[0]
			many.instance_count = spots.size()
			for i in spots.size():
				many.set_instance_transform(i, spots[i])
			var node := MultiMeshInstance3D.new()
			node.name = spec[3] + ("Mirrored" if mirror else "")
			node.multimesh = many
			node.material_override = spec[2]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mirror:
				node.transform = _mirror()
			add_child(node)
	# A faint wash of their colour on the rock under them: they are many, if each is little.
	for at in [Vector3(0, 4.2, -12.0), Vector3(-7.0, 4.0, -5.0), Vector3(7.0, 4.0, -6.0), Vector3(0, 4.8, 2.0)]:
		_light(at, WORM, 1.6, 16.0, &"worm", 0.6)


## Boulders fallen on the shore and standing out of the water, and their reflections.
func _scatter_boulders(real: Material, mirrored: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var c := _lake_centre()
	var size := _lake_size()
	var spots := [[], [], []]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 3000:
		tries += 1
		var x := rng.randf_range(-size.x, size.x)
		var z := rng.randf_range(c.y - size.y, c.y + size.y)
		if not _in_plan(x, z, c, size.x, size.y, 3.2, -1.0):
			continue
		var o := _outside(x, z, live_room_half() + 0.45, Studio.ROOM_FRONT - 0.6, LIVE_ROOM_BACK + 0.45)
		if o < 0.7 or absf(x - _jetty_x()) < 2.6 and z > Studio.ROOM_FRONT - JETTY_RUN - 2.0 and z < Studio.ROOM_FRONT:
			continue
		var y := _ground_h(x, z)
		var in_lake := y < WATER_Y
		# Out in the lake, only a few, big, breaking the surface.
		if in_lake and rng.randf() < 0.75:
			continue
		var s := rng.randf_range(0.6, 1.8) if not in_lake else rng.randf_range(1.6, 2.6)
		var at := Vector3(x, (WATER_Y - 0.28 * s) if in_lake else y - 0.04, z)
		(spots[rng.randi() % 3] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), at))
		placed += 1
	for k in 3:
		var list: Array[Transform3D] = []
		list.assign(spots[k])
		if list.is_empty():
			continue
		_many(FORMATIONS, "Boulder%d" % k, list, {"rock": real}, "Boulders%d" % k)
		_many(FORMATIONS, "Boulder%d" % k, list, {"rock": mirrored}, "BouldersMirrored%d" % k, [], true)


# --- the lava tube ----------------------------------------------------------------------------

## The tube's half width, and its centre line at z: straight past the room, bending right ahead
## (the river glows away round the bend) and left behind.
func _tube_half() -> float:
	return live_room_half() + 3.6


func _bend(z: float) -> float:
	var ahead := _ahead(-9.0)
	var behind := LIVE_ROOM_BACK + 3.7
	if z < ahead:
		return 0.03 * (z - ahead) * (z - ahead)
	if z > behind:
		return -0.035 * (z - behind) * (z - behind)
	return 0.0


func _tube_x(z: float) -> float:
	return 1.9 + _bend(z)


## A point on the tube's rock: u along it, v across its section from the foot of the right-hand
## wall, over the roof, down to the foot of the left -- both feet running on below the floor.
func _tube_point(u: float, v: float) -> Vector3:
	var half := _tube_half()
	var z := lerpf(TUBE_FROM, TUBE_TO, u)
	var a := lerpf(-0.4, PI + 0.4, v)
	var xc := _tube_x(z)
	if a < 0.0:
		return Vector3(xc + half, a / 0.4 * 2.6, z)
	if a > PI:
		return Vector3(xc - half, (PI - a) / 0.4 * 2.6, z)
	var c := cos(a)
	return Vector3(xc + half * signf(c) * pow(absf(c), 2.0 / TUBE_SQUARE), TUBE_HEIGHT * pow(sin(a), 2.0 / TUBE_SQUARE), z)


## The river's middle line, sampled every quarter metre from upstream (behind you) down: out
## past the floor's right edge beside the room, meandering once clear of it; then round a corner
## and straight across the tube in front of the desk; round again and away down the left-hand
## side, round the bend ahead.
func _river_line() -> PackedVector2Array:
	if not _river.is_empty():
		return _river
	var h := live_room_half()
	var right := h + RIVER_OUT
	var left := -h + 0.6
	var turn_z := Studio.ROOM_FRONT - TUBE_FLOOR_AHEAD - RIVER_ACROSS + RIVER_TURN
	var across_z := turn_z - RIVER_TURN
	var pts := PackedVector2Array()
	var z := TUBE_TO
	while z > turn_z:
		var wander := sin(z * 0.21) * 0.35 * smoothstep(8.0, 14.0, absf(z - 2.0))
		pts.append(Vector2(right + _bend(z) + wander, z))
		z -= 0.25
	var c1 := Vector2(right - RIVER_TURN, turn_z)
	for k in 13:
		var a := -PI * 0.5 * k / 12.0
		pts.append(c1 + Vector2(cos(a), sin(a)) * RIVER_TURN)
	var x := right - RIVER_TURN - 0.25
	while x > left + RIVER_TURN:
		pts.append(Vector2(x, across_z))
		x -= 0.25
	var c2 := Vector2(left + RIVER_TURN, across_z - RIVER_TURN)
	for k in 13:
		var a := PI * 0.5 + PI * 0.5 * k / 12.0
		pts.append(c2 + Vector2(cos(a), sin(a)) * RIVER_TURN)
	z = across_z - RIVER_TURN - 0.25
	while z > TUBE_FROM:
		pts.append(Vector2(left + _bend(z) - _bend(across_z - RIVER_TURN), z))
		z -= 0.25
	_river = pts
	for k in pts.size():
		var cell := floori(pts[k].y)
		# Packed arrays are values: take it out, add to it, put it back.
		var ks: PackedInt32Array = _river_cells.get(cell, PackedInt32Array())
		ks.append(k)
		_river_cells[cell] = ks
	return _river


## How far (x, z) is from the river's middle (capped at 6 m: nothing cares past that).
func _river_d(x: float, z: float) -> float:
	var pts := _river_line()
	var best := 36.0
	var cz := floori(z)
	for cell in range(cz - 6, cz + 7):
		if not _river_cells.has(cell):
			continue
		for k: int in _river_cells[cell]:
			best = minf(best, Vector2(x, z).distance_squared_to(pts[k]))
	return sqrt(best)


## How near the lava (x, y, z) is, 0..1: what makes the rock glow dull red along its cracks.
func _heat(p: Vector3) -> float:
	return (1.0 - smoothstep(RIVER_HALF - 0.2, RIVER_HALF + 1.4, _river_d(p.x, p.z))) * (1.0 - smoothstep(-0.4, 1.6, p.y))


func _tube_h(x: float, z: float) -> float:
	var n := _ground_noise.get_noise_2d(x, z)
	var d := _river_d(x, z)
	if d < RIVER_HALF:
		return -1.0 + 0.6 * pow(d / RIVER_HALF, 4.0)
	# Out of the channel: a low lip of rock, no higher than a kerb, so the lava shows over it;
	# then the bench of the old flow the room stands on, and rubble toward the walls.
	var out := d - RIVER_HALF
	var lip := -0.4 + 0.46 * smoothstep(0.0, 0.3, out) - 0.46 * smoothstep(0.45, 1.0, out) + n * 0.04
	var bench := -0.07
	# Past the levelled floor, ahead and behind, the tube's own floor: lumpy, a little proud.
	if z < Studio.ROOM_FRONT - TUBE_FLOOR_AHEAD or z > LIVE_ROOM_BACK + TUBE_FLOOR_BEHIND:
		bench = 0.03 + absf(n) * 0.25 * smoothstep(0.5, 1.5, out)
	# Toward the walls, rubble rising to meet them, kept back from the river.
	var lateral := absf(x - (_tube_x(z) - 1.9)) - (live_room_half() + 0.2)
	if lateral > 0.0:
		bench += (smoothstep(0.0, 2.5, lateral) * (0.2 + lateral * 0.12) \
				+ (n * 0.5 + 0.35) * smoothstep(0.2, 1.4, lateral) * 0.45) * smoothstep(0.6, 2.0, out)
	return maxf(bench, lip)


func _build_tube() -> void:
	var half := _tube_half()
	var basalt := {"dark": Color(0.03, 0.026, 0.025), "light": Color(0.16, 0.14, 0.13),
			"strata_tint": Color(0.16, 0.06, 0.035), "scale": 1.4, "bump": 1.1, "strata": 0.3, "ropes": 1.0,
			"wet_below": -20.0, "roughness_dry": 0.72, "heat": 1.4}
	var wall := _rock(basalt)
	var outline := func(u: float, v: float) -> Vector3: return _tube_point(u, v)
	var inside := func(p: Vector3) -> Vector3: return Vector3(_tube_x(p.z), 2.5, p.z)
	# Ledges where the flow stood a while: a lip along each wall at two heights.
	var ledges := func(p: Vector3) -> float: return 0.14 * (smoothstep(1.45, 1.55, p.y) - smoothstep(1.7, 1.8, p.y)) \
			+ 0.1 * (smoothstep(3.0, 3.1, p.y) - smoothstep(3.25, 3.35, p.y))
	_sculpt(220, 96, false, outline, inside, 0.45, 0.28, 7, ledges)
	_shell_meshes(false, 10, wall, "Tube", _heat)
	# The floor: the old flow's own skin, ropy, levelled where the crew laid out the room, and on
	# ahead down the tube.
	var skin := basalt.duplicate()
	skin["heat"] = 0.0
	skin["bump"] = 0.7
	_lay_floor(_rock(skin), 1.2, TUBE_FLOOR_RIGHT, TUBE_FLOOR_AHEAD, TUBE_FLOOR_BEHIND)
	var spread := func(u: float, v: float) -> Vector2: return Vector2(
			_tube_x(lerpf(TUBE_FROM, TUBE_TO, v)) + lerpf(-half - 0.6, half + 0.6, u), lerpf(TUBE_FROM, TUBE_TO, v))
	var keep := func(_a: Vector3, _b: Vector3, _d: Vector3, _e: Vector3) -> bool: return true
	_lay_ground(70, 230, spread, keep, wall, 5, _heat)
	_run_the_river()
	_rail_the_lip()
	var cold := basalt.duplicate()
	cold["heat"] = 0.0
	cold["ropes"] = 0.0
	cold["strata"] = 0.0
	cold["bump"] = 0.6
	cold["scale"] = 0.7
	var columns := _rock(cold)
	_stand_basalt(columns)
	# The tube's two ends, round their bends: rock across them, too far into the smoke to see as
	# more than the dark where the tube goes on.
	for spec in [[TUBE_FROM + 0.6, 0.0], [TUBE_TO - 0.6, PI]]:
		var cap := MeshInstance3D.new()
		cap.name = "TubeEnd"
		var quad := QuadMesh.new()
		quad.size = Vector2(half * 2.0 + 6.0, TUBE_HEIGHT + 5.0)
		cap.mesh = quad
		cap.material_override = columns
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var z: float = spec[0]
		cap.transform = Transform3D(Basis(Vector3.UP, spec[1]), Vector3(_tube_x(z), TUBE_HEIGHT * 0.5 - 1.0, z))
		add_child(cap)
	_hang_stalactites(columns, 140, Vector2(0.06, 0.45), 0.3)
	_hang_work_lamps()
	_dress_zones({"riser_top": Materials.cached_scanned("cave_plate", "blue_metal_plate", "2k", 1.2, Color(0.36, 0.34, 0.34)),
			"riser_skirt": _iron(), "frame": _iron(), "glass": _glass(Color(0.85, 0.5, 0.3, 0.08)),
			"inlay": ZoneKit.glow(Color(1.0, 0.45, 0.12), 1.2), "top": columns, "legs": _iron(),
			"booth_light": Color(1.0, 0.86, 0.7), "shelf_lamp": Color(1.0, 0.72, 0.45)})


## The river: a ribbon of lava down its channel the length of the tube, its light along it,
## embers rising from it, and the air over it shimmering.
func _run_the_river() -> void:
	var lava := ShaderMaterial.new()
	lava.shader = preload("res://core/venues/shaders/cave_lava.gdshader")
	_pulsed.append(lava)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var line := _river_line()
	var along := 0.0
	var reach := RIVER_HALF + 0.2
	var edges: Array[Vector3] = []
	for k in line.size():
		var here := line[k]
		var ahead := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
		var across := Vector2(-ahead.y, ahead.x).normalized()
		if k > 0:
			along += here.distance_to(line[k - 1])
		for side in [-1.0, 1.0]:
			var p: Vector2 = here + across * side * reach
			st.set_uv(Vector2(0.5 + side * 0.5, along))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, LAVA_Y, p.y))
			edges.append(Vector3(p.x, LAVA_Y, p.y))
	for k in line.size() - 1:
		var a := k * 2
		_quad(st, a, a + 1, a + 3, a + 2, edges[a], edges[a + 1], edges[a + 3], Vector3.UP)
	var river := MeshInstance3D.new()
	river.name = "Lava"
	river.mesh = st.commit()
	river.material_override = lava
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)
	# Stations down the stretch you can see, every metre of it: its light every few metres, an
	# ember fountain over each few metres, a pane of haze over each one and a half.
	var stations: Array[Vector2] = []
	var tangents: Array[Vector2] = []
	var run := 0.0
	for k in range(1, line.size()):
		run += line[k].distance_to(line[k - 1])
		if run >= 1.0 and line[k].y > -30.0 and line[k].y < 16.0:
			run = 0.0
			stations.append(line[k])
			tangents.append((line[k] - line[k - 1]).normalized())
	for k in range(0, stations.size(), 3):
		_light(Vector3(stations[k].x, 0.9, stations[k].y), LAVA_LIGHT, 6.0, 15.0, &"lava", 0.5)
	for k in range(0, stations.size(), 4):
		_embers(stations[k], tangents[k], 4.0)
	var pane := QuadMesh.new()
	pane.size = Vector2.ONE
	var haze := ShaderMaterial.new()
	haze.shader = preload("res://core/venues/shaders/cave_haze.gdshader")
	haze.set_shader_parameter("strength", 0.012)
	for k in range(0, stations.size(), 2):
		if stations[k].y < -18.0 or stations[k].y > 10.0:
			continue
		var shimmer := MeshInstance3D.new()
		shimmer.name = "Haze"
		shimmer.mesh = pane
		shimmer.material_override = haze
		shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shimmer.transform = Transform3D(Basis.from_scale(Vector3(3.4, 3.0, 1.0)),
				Vector3(stations[k].x, LAVA_Y + 1.5, stations[k].y))
		add_child(shimmer)


## Embers thrown up off `length` metres of the river at `at`, running along `along`.
func _embers(at: Vector2, along: Vector2, length: float) -> void:
	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = int(length * 22.0)
	embers.lifetime = 6.0
	embers.preprocess = 6.0
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(RIVER_HALF * 0.8, 0.05, length * 0.5)
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 30.0
	motion.initial_velocity_min = 0.3
	motion.initial_velocity_max = 0.9
	motion.gravity = Vector3(0, 0.15, 0)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.8
	motion.turbulence_noise_scale = 2.5
	motion.scale_min = 0.6
	motion.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.08, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.8, 0.4, 0.0), Color(1.0, 0.65, 0.25, 1.0), Color(1.0, 0.3, 0.06, 0.7),
			Color(0.5, 0.06, 0.0, 0.0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	motion.color_ramp = tex
	embers.process_material = motion
	var spark := QuadMesh.new()
	spark.size = Vector2(0.034, 0.034)
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	hot.vertex_color_use_as_albedo = true
	hot.albedo_color = Color(4.0, 2.2, 1.1)
	hot.disable_fog = true
	spark.material = hot
	embers.draw_pass_1 = spark
	# The box's length runs down the stream.
	embers.transform = Transform3D(Basis(Vector3.UP, atan2(along.x, along.y)), Vector3(at.x, LAVA_Y + 0.05, at.y))
	embers.visibility_aabb = AABB(Vector3(-3, -0.5, -length * 0.5 - 2.0), Vector3(6, 8, length + 4.0))
	add_child(embers)


## A steel rail along the top of the lip past the room: nobody leans over a lava channel.
func _rail_the_lip() -> void:
	var steel := _iron()
	var stripe := ShaderMaterial.new()
	stripe.shader = preload("res://core/venues/shaders/hazard.gdshader")
	var x := live_room_half() + 0.32
	var z0 := Studio.ROOM_FRONT - TUBE_FLOOR_AHEAD + 0.12
	var z1 := LIVE_ROOM_BACK + 0.6
	var posts := ceili((z1 - z0) / 1.6)
	for i in posts + 1:
		var z := lerpf(z0, z1, float(i) / posts)
		var foot := maxf(_ground_h(x, z), 0.0) - 0.1
		ZoneKit.block(self, Vector3(0.05, 1.1 - foot, 0.05), Vector3(x, foot + (1.1 - foot) * 0.5, z), steel, "LipPost")
	ZoneKit.block(self, Vector3(0.06, 0.05, z1 - z0 + 0.1), Vector3(x, 1.125, (z0 + z1) * 0.5), steel, "LipRail")
	ZoneKit.block(self, Vector3(0.03, 0.03, z1 - z0), Vector3(x, 0.66, (z0 + z1) * 0.5), steel, "LipMidRail")
	# A warning stripe on the top rail's inside face, where you would put your hand.
	ZoneKit.block(self, Vector3(0.004, 0.035, z1 - z0 - 0.2), Vector3(x - 0.032, 1.125, (z0 + z1) * 0.5), stripe, "LipStripe")
	# And across the front, where the river turns past the desk: a hair lower than the side
	# rail, so the two never share a face where they meet.
	var x0 := -live_room_half() - 1.1
	var x1 := x - 0.02
	var spans := ceili((x1 - x0) / 1.6)
	for i in spans:
		var px := lerpf(x0, x1, float(i) / spans)
		var foot := maxf(_ground_h(px, z0), 0.0) - 0.1
		ZoneKit.block(self, Vector3(0.05, 1.09 - foot, 0.05), Vector3(px, foot + (1.09 - foot) * 0.5, z0), steel, "FrontPost")
	ZoneKit.block(self, Vector3(x1 - x0 + 0.03, 0.044, 0.056), Vector3((x0 + x1) * 0.5 - 0.015, 1.12, z0), steel, "FrontRail")
	ZoneKit.block(self, Vector3(x1 - x0, 0.026, 0.026), Vector3((x0 + x1) * 0.5, 0.655, z0), steel, "FrontMidRail")
	ZoneKit.block(self, Vector3(x1 - x0 - 0.2, 0.03, 0.004), Vector3((x0 + x1) * 0.5, 1.12, z0 + 0.03), stripe, "FrontStripe")


## Cooled basalt: stands of hexagonal columns along the walls, behind the zones and across the
## river, and stretches of worn pavement out on the tube floor ahead.
func _stand_basalt(material: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	var half := live_room_half()
	var stands: Array[Transform3D] = []
	for z in [_ahead(-5.2), -1.8, 2.4, 6.6, 10.4, 14.2, _ahead(-11.5), _ahead(-15.0)]:
		var x := _tube_x(z) - _tube_half() + 0.9 + rng.randf_range(-0.2, 0.2)
		var s := rng.randf_range(1.0, 1.7)
		# None stands in the river where it runs down the left ahead.
		if _river_d(x, z) < RIVER_HALF + 1.2:
			continue
		stands.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(1.0, 1.6), s)),
				Vector3(x, _ground_h(x, z) - 0.1, z)))
	for x in [-3.5, 0.5, 3.8]:
		var z := LIVE_ROOM_BACK + 2.4 + rng.randf_range(-0.3, 0.6)
		var s := rng.randf_range(1.1, 1.6)
		var xx := _wide(x)
		stands.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 1.4, s)),
				Vector3(xx, _ground_h(xx, z) - 0.1, z)))
	for z in [-1.0, 3.0, 7.0, 11.0]:
		var x := half + RIVER_OUT + RIVER_HALF + 1.4
		var s := rng.randf_range(0.9, 1.3)
		stands.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, _ground_h(x, z) - 0.1, z)))
	_many(FORMATIONS, "Basalt0", stands, {"basalt": material}, "BasaltStands")
	var pavement: Array[Transform3D] = []
	for spec in [Vector2(-2.6, -16.0), Vector2(1.2, -19.5), Vector2(-4.8, -21.0), Vector2(-1.0, 12.5),
			Vector2(-4.2, -12.5)]:
		# Ahead down the tube from the old front, or behind the old back of house, as far as ever.
		var z: float = _ahead(spec.y) if spec.y < 0.0 else spec.y - DRAWN_BACK + LIVE_ROOM_BACK
		var x: float = _tube_x(z) - 1.9 + _wide(spec.x)
		var s := rng.randf_range(1.2, 2.0)
		if _river_d(x, z) < RIVER_HALF + 1.6:
			continue
		pavement.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s)),
				Vector3(x, _ground_h(x, z) - 0.12, z)))
	_many(FORMATIONS, "Basalt1", pavement, {"basalt": material}, "BasaltPavement")


## Caged work lamps on steel poles along the left, strung on one cable: the zones on the cold
## side of the tube need light the river's does not give them.
func _hang_work_lamps() -> void:
	var x := -live_room_half() - 0.35
	var steel := _iron()
	var cable := _paint(Color(0.02, 0.02, 0.02), 0.6)
	var tops: Array[Vector3] = []
	for z in [-2.4, 1.6, 5.6, 9.2, 12.0]:
		tops.append(_work_lamp(x, z, steel))
	for i in tops.size() - 1:
		_rope(tops[i], tops[i + 1], 0.25, cable)
	# And two across the back of house, where the river's light does not reach round the stands.
	var back := LIVE_ROOM_BACK + 0.4
	var behind: Array[Vector3] = []
	for bx in [-live_room_half() * 0.55, 0.0, live_room_half() * 0.55]:
		behind.append(_work_lamp(bx, back, steel))
	for i in behind.size() - 1:
		_rope(behind[i], behind[i + 1], 0.3, cable)


## One caged lamp on a steel pole at (x, z), its arm reaching toward +x; returns the pole's top.
func _work_lamp(x: float, z: float, steel: Material) -> Vector3:
	var foot := maxf(_ground_h(x, z), 0.0) - 0.05
	var top := 2.6
	ZoneKit.block(self, Vector3(0.06, top - foot, 0.06), Vector3(x, foot + (top - foot) * 0.5, z), steel, "LampPole")
	var at := Vector3(x + 0.16, top - 0.12, z)
	ZoneKit.block(self, Vector3(0.22, 0.04, 0.05), Vector3(x + 0.09, top - 0.04, z), steel, "LampArm")
	ZoneKit.block(self, Vector3(0.12, 0.16, 0.12), at, ZoneKit.glow(Color(1.0, 0.82, 0.6), 1.6), "LampGlass")
	# The cage: bars round the glass, a little proud of it.
	ZoneKit.block(self, Vector3(0.14, 0.012, 0.14), at + Vector3(0, 0.04, 0), steel, "LampCage")
	ZoneKit.block(self, Vector3(0.14, 0.012, 0.14), at + Vector3(0, -0.04, 0), steel, "LampCage")
	ZoneKit.block(self, Vector3(0.13, 0.02, 0.13), at + Vector3(0, 0.095, 0), steel, "LampCap")
	# Far enough to meet the next lamp's light across a back of house twice the size it was.
	var l := _light(at + Vector3(0.1, -0.05, 0), Color(1.0, 0.8, 0.58), 2.6, 9.0, &"crew")
	l.light_specular = 0.15
	return Vector3(x, top - 0.02, z)


# --- the zones -------------------------------------------------------------------------------

func _glass(colour: Color) -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = colour
	glass.roughness = 0.05
	glass.metallic_specular = 0.7
	return glass


## The zones in the cave's own materials (`m`): a riser, a booth with its mic stand and a light
## in its lid, the lattice's square inlaid in light on the floor, a table, the keys, and the prop
## shelf in the table's materials.
func _dress_zones(m: Dictionary) -> void:
	var z := zones()
	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, m["riser_top"], m["riser_skirt"])
	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, m["frame"], m["glass"])
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), m["booth_light"], 1.3, 60.0, 3.2,
			m["frame"])
	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.035, m["inlay"])
	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, m["top"], m["legs"])
	_dress_prop_shelf(m["top"], m["legs"], m["shelf_lamp"])
	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, m["legs"], m["top"])


## The mirror in each cave's own metal or timber.
func _frame_mirror(mirror: Mirror) -> void:
	match variant:
		LAKE:
			Venue.frame_bars(mirror, 0.06, 0.04, 0.012,
					Materials.cached_scanned("cave_timber", "weathered_brown_planks", "2k", 0.7, Color(0.32, 0.26, 0.22)))
		TUBE:
			Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _iron())
		_:
			Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _pewter())


## The tracks' colours here (TrackColours), in its STANDARD order: gemstones. Garnet, carnelian,
## citrine, peridot, emerald, aquamarine, topaz, sapphire, amethyst, rhodolite, rose quartz and
## smoky quartz.
func track_palette() -> Array:
	return [
		Color(0.78, 0.16, 0.26), Color(0.92, 0.48, 0.22), Color(0.95, 0.78, 0.30), Color(0.66, 0.86, 0.30),
		Color(0.20, 0.70, 0.45), Color(0.30, 0.82, 0.78), Color(0.42, 0.70, 0.95), Color(0.24, 0.38, 0.88),
		Color(0.60, 0.38, 0.92), Color(0.82, 0.30, 0.70), Color(0.95, 0.62, 0.74), Color(0.60, 0.56, 0.58),
	]
