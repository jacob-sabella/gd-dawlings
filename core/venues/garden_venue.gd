class_name GardenVenue
extends Venue

## A temple garden in Japan. The working floor is a pavilion: a deck of pale hinoki boards raised
## on stone footings over the garden, open on every side under a hip-and-gable roof of smoked
## tiles on timber columns, a coffered ceiling inside and a vermilion railing round its veranda.
## Paper lanterns hang between the columns. Round it, the garden: raked gravel in front with its
## stones set in moss, the rings raked round them; a koi pond past it, crossed by a vermilion drum
## bridge on its left arm and by stepping stones on its right, stone lanterns on its banks; clipped
## pines leaning over the water; the season's trees -- cherries and maples -- round the edges;
## an earthen wall across the far side with a roofed gate in it, a torii up on the hill past it,
## a pagoda on the hillside to the left, and the temple hall behind the zones. Hills, wooded in
## cedar, rise all round, and past them ranges of mountains fade into the mist (garden_sky).
##
## Three arrangements, three seasons, each its own light and its own weather:
## - Spring: the cherries in blossom and petals drifting down through the morning sun to settle on
##   the gravel, the moss and the pond; the maples in fresh leaf; mist in the valleys.
## - Autumn: the maples blazing red and orange and the cherries gone russet, leaves turning down
##   out of them, a low gold sun late in the afternoon laying the columns' shadows across the deck.
## - Winter: dusk, snow lying on the roofs, the lanterns, the stones and the pines, snow falling,
##   the trees bare, and the stone lanterns lit warm; the hall's paper doors glowing.
##
## The roof, the lanterns, the bridge, the torii, the trees, the stones and the koi are modelled
## in Blender (tools/blender/garden_roof.py, garden_props.py, garden_trees.py); everything
## repeated is a MultiMesh; the koi swim, the water ripples and the trees stir in shaders.

## The deck stands on footings over the garden: the ground is this far below the boards.
const GROUND := -0.62
## The pond's water, a hand under the ground round it.
const WATER := GROUND - 0.18
## The veranda: how far the deck runs on past the walkable floor, all round.
const ENGAWA := 0.95
## The columns stand this far outside the walkable floor (just inside the veranda's railing).
const COLUMN_OUT := 0.35
const COLUMN_R := 0.14
## Column heads, the beam they carry (keta) and the ceiling under the roof. Every zone's head room
## (Venue.ZONES; the lattice's 3.4 m) is under the lowest of them, the lanterns included.
const COLUMN_TOP := 3.84
const BEAM_TOP := 4.3
## The roof's eaves stand this far past the columns, and its eave tips are this high over the
## deck (garden_roof.glb's origin). Its model was drawn for the base width: 9.35 m half-length.
const EAVES_OUT := 1.9
const EAVE := 4.2
const ROOF_DRAWN_HALF := 9.35
## And 7.5 m half-depth, front eave to back: the pavilion's depth when its floor ran from 3.2 m in
## front of the seat to 7.3 m behind it.
const ROOF_DRAWN_DEPTH := 7.5
## The deck's front edge as the garden in front of it was first laid out to (Studio.ROOM_FRONT was
## -3.2): the steps' stones and the lanterns flanking them are moved out by as much as it has.
const DRAWN_FRONT := -3.2
## The railing round the veranda, its height.
const RAIL := 0.62
## Where the wind chimes hang along the deck's right-hand edge beside the desk (z of their middle).
const CHIMES_ALONG := 1.0

const MODELS := "res://assets/models/"
const SPRING := 0
const AUTUMN := 1
const WINTER := 2

## Per season: the sky (zenith, upper, horizon, mist, hills, sun colour, sun's disc, glow,
## clouds, stars), the key (colour, energy, pitch, yaw), the light from everywhere, the haze, how
## lit the lanterns are (paper, stone), the ground's litter, and the snow.
const SEASONS := [
	# A spring morning: soft, pale, the sun up behind the pavilion to the right, lighting the
	# garden in front; mist lying in the far valleys.
	{"zenith": Color(0.36, 0.52, 0.76), "upper": Color(0.62, 0.71, 0.84), "horizon": Color(0.9, 0.86, 0.84),
			"mist": Color(0.8, 0.8, 0.82), "hills": Color(0.26, 0.34, 0.32), "sun": Color(1.0, 0.92, 0.82),
			"disc": 0.0, "glow": 0.5, "clouds": 0.55, "stars": 0.0,
			"key": [Color(1.0, 0.93, 0.84), 1.05, -34.0, 28.0], "ambient": [Color(0.72, 0.78, 0.9), 0.27],
			"fog": [Color(0.74, 0.76, 0.8), 30.0, 230.0], "paper": 0.35, "stone": 0.0,
			"litter": [Color(0.98, 0.8, 0.86), 0.55], "snow": 0.0, "exposure": 0.74},
	# Late on an autumn afternoon: the sun low over the hills to the left, under the eaves and
	# across the deck, everything gold.
	{"zenith": Color(0.26, 0.36, 0.58), "upper": Color(0.55, 0.52, 0.56), "horizon": Color(1.0, 0.7, 0.42),
			"mist": Color(0.72, 0.56, 0.42), "hills": Color(0.24, 0.2, 0.16), "sun": Color(1.0, 0.72, 0.42),
			"disc": 0.028, "glow": 0.9, "clouds": 0.4, "stars": 0.0,
			"key": [Color(1.0, 0.7, 0.42), 1.5, -12.5, 238.0], "ambient": [Color(0.78, 0.62, 0.52), 0.24],
			"fog": [Color(0.6, 0.45, 0.32), 25.0, 210.0], "paper": 0.7, "stone": 0.0,
			"litter": [Color(0.8, 0.28, 0.1), 0.7], "snow": 0.0, "exposure": 0.9},
	# A winter dusk: the sky gone violet over the snow, the lanterns lit.
	{"zenith": Color(0.03, 0.045, 0.11), "upper": Color(0.1, 0.12, 0.24), "horizon": Color(0.42, 0.3, 0.38),
			"mist": Color(0.2, 0.21, 0.3), "hills": Color(0.07, 0.08, 0.13), "sun": Color(0.9, 0.55, 0.5),
			"disc": 0.0, "glow": 0.35, "clouds": 0.25, "stars": 0.7,
			"key": [Color(0.55, 0.62, 0.9), 0.22, -28.0, 160.0], "ambient": [Color(0.45, 0.52, 0.72), 0.2],
			"fog": [Color(0.15, 0.16, 0.24), 18.0, 150.0], "paper": 1.6, "stone": 1.0,
			"litter": [Color(0.5, 0.5, 0.5), 0.0], "snow": 1.0, "exposure": 1.0},
]

## The pond: ellipses (centre x, z, radius x, z) whose union is the water.
const POND := [Vector4(-3.0, -22.0, 11.0, 5.0), Vector4(-13.0, -15.0, 3.2, 6.5), Vector4(8.0, -27.0, 6.0, 3.6)]
## The drum bridge over the pond's left arm (its middle), spanning along X.
const BRIDGE := Vector2(-13.0, -15.5)
## The raked gravel in front of the pavilion, as a rectangle (x, z, w, d), and the stones set in
## it: (x, z, the rings' inner radius, how far the rings run out) -- the ground shader's `stones`.
const GRAVEL := Rect2(-11.5, -16.0, 24.0, 11.4)
const STONE_GROUPS := [Vector4(-6.0, -10.0, 1.5, 1.3), Vector4(5.0, -8.6, 1.4, 1.2), Vector4(9.0, -13.0, 1.3, 1.1),
		Vector4(-1.6, -13.6, 0.8, 0.9), Vector4(-9.6, -6.9, 0.9, 0.9)]
## The far wall across the garden, its gate, the torii up the hill and the pagoda.
const WALL_Z := -40.0
const GATE_HALF := 2.4
const TORII := Vector2(0.0, -64.0)
const PAGODA := Vector2(-36.0, -60.0)
## The temple hall, behind the zones.
const HALL := Vector2(0.0, 33.0)
const HALL_SIZE := Vector2(22.0, 13.0)

var _sky_mat: ShaderMaterial
var _paper: StandardMaterial3D
var _stone_glow: StandardMaterial3D
## The lights the music moves: paper lanterns and, in winter, the stone ones, each with its
## resting energy.
var _lantern_lights: Array = []
var _falling: Array[GPUParticles3D] = []
var _level := 0.0
var _rng := RandomNumberGenerator.new()
var _meshes := {}


func venue_id() -> StringName:
	return &"garden"


func _season() -> Dictionary:
	return SEASONS[clampi(variant, 0, SEASONS.size() - 1)]


## Open on every side: nothing to hang the roll board or the roulette panel on.
func back_wall_gear_stands() -> bool:
	return true


## Hinoki and lacquer: the furniture in pale cypress, the faceplates near-black, metal in dark
## bronze, the edges and the looms' bands in vermilion lacquer, end cheeks in black lacquer, the
## lamp shades washi paper.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("wood_floor_deck", 1.2, Color(0.9, 0.78, 0.62))) \
			.with("chassis", GearStyle.paint(Color(0.075, 0.066, 0.06), 0.6, 0.1)) \
			.with("brushed", GearStyle.metal(Color(0.36, 0.29, 0.2), 0.45)) \
			.with("trim", GearStyle.paint(Color(0.74, 0.17, 0.08), 0.35, 0.0)) \
			.with("end_cheek", GearStyle.paint(Color(0.045, 0.035, 0.03), 0.22, 0.0)) \
			.with("lamp_shade", GearStyle.paint(Color(0.93, 0.87, 0.74), 0.95, 0.0)) \
			.with("loom_band", GearStyle.paint(Color(0.8, 0.2, 0.09), 0.4, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.09, 0.065, 0.055), 0.22, 0.0))


## A board of hinoki, written on in sumi ink, the arrows in vermilion like a temple seal.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.scan("wood_floor_deck", 0.6, Color(0.82, 0.7, 0.54))
	board.ink = Color(0.08, 0.07, 0.07)
	board.accent = Color(0.78, 0.18, 0.08)
	board.board_ink_fade = Color(0.5, 0.42, 0.34)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	var s := _season()
	key.light_color = s["key"][0]
	key.light_energy = s["key"][1]
	key.rotation_degrees = Vector3(s["key"][2], s["key"][3], 0.0)
	key.light_specular = 0.2
	# Far enough that the columns' and the railing's shadows reach across the deck.
	key.directional_shadow_max_distance = 18.0

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/garden_sky.gdshader")
	for k in ["zenith", "upper", "horizon", "mist", "hills"]:
		_sky_mat.set_shader_parameter(k, s[k])
	_sky_mat.set_shader_parameter("sun_colour", s["sun"])
	_sky_mat.set_shader_parameter("sun_radius", s["disc"])
	_sky_mat.set_shader_parameter("glow", s["glow"])
	_sky_mat.set_shader_parameter("clouds", s["clouds"])
	_sky_mat.set_shader_parameter("stars", s["stars"])
	# Where the light comes from: the key points along its own -Z.
	var toward_sun := Basis.from_euler(key.rotation).z
	if variant == WINTER:
		# Gone down behind the hills to the front, leaving its colour on the horizon.
		toward_sun = Vector3(0.2, -0.05, -1.0).normalized()
	_sky_mat.set_shader_parameter("sun_dir", toward_sun)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = s["ambient"][0]
	env.ambient_light_energy = s["ambient"][1]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = s["exposure"]
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The air: morning mist, gold haze, the blue of a winter evening; the far hills go into it.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = s["fog"][0]
	env.fog_depth_begin = s["fog"][1]
	env.fog_depth_end = s["fog"][2]
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.1


func lamp_colour(_index: int, authored: Color) -> Color:
	# Light through paper: warm, a little soft.
	return authored.lerp(Color(1.0, 0.76, 0.52), 0.4)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * (0.95 if variant == WINTER else 0.8)


## One open floor: the deck either side of the desk joins the far end.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 42): eight wind chimes off a
## short beam hung from the pavilion's ceiling on two cords, along the right-hand edge of the deck
## beside the desk, where the breeze comes through.
func instrument() -> Dictionary:
	return {"kind": &"chimes", "spot": side_wall_instrument(1.0, CHIMES_ALONG, 0.03), "hang_to": BEAM_TOP}


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), true)


## The lanterns brighten with the music and the falling petals, leaves or snow gust.
func pulse(level: float) -> void:
	_level = lerpf(_level, level, 0.25)
	for l: Array in _lantern_lights:
		(l[0] as Light3D).light_energy = l[1] * (1.0 + 0.45 * _level)
	if _paper != null:
		_paper.emission_energy_multiplier = _season()["paper"] * (1.0 + 0.6 * _level)
	if _stone_glow != null:
		_stone_glow.emission_energy_multiplier = 1.4 * _season()["stone"] * (1.0 + 0.5 * _level)
	for f in _falling:
		f.speed_scale = 1.0 + 0.7 * _level


# --- layout ---------------------------------------------------------------------------------

## The column lines: x of the side rows (either sign), z of the front and back rows.
func column_x() -> float:
	return live_room_half() + COLUMN_OUT


func column_front() -> float:
	return Studio.ROOM_FRONT - COLUMN_OUT


func column_back() -> float:
	return LIVE_ROOM_BACK + COLUMN_OUT


## Every column, in studio space: along the front and back about every three metres, and down
## the sides between.
func column_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cx := column_x()
	var across := maxi(int(round(cx * 2.0 / 3.0)), 2)
	for i in across + 1:
		var x := -cx + cx * 2.0 * i / across
		out.append(Vector2(x, column_front()))
		out.append(Vector2(x, column_back()))
	# Down the sides about every three metres too, however deep the pavilion has grown.
	var along := maxi(roundi((column_back() - column_front()) / 3.0), 4)
	for i in range(1, along):
		var z := lerpf(column_front(), column_back(), float(i) / along)
		out.append(Vector2(-cx, z))
		out.append(Vector2(cx, z))
	return out


## The pond's signed distance at `p` (studio xz): negative in the water.
static func pond_distance(p: Vector2) -> float:
	var best := INF
	for e: Vector4 in POND:
		var q := Vector2((p.x - e.x) / e.z, (p.y - e.y) / e.w)
		best = minf(best, (q.length() - 1.0) * minf(e.z, e.w))
	return best


## The ground's height at `p`: flat round the pavilion, down into the pond, up into mossy mounds
## here and there and into wooded hills all round past the garden's wall.
func ground_at(p: Vector2) -> float:
	var h := GROUND
	var sd := pond_distance(p)
	h -= 0.24 * smoothstep(0.6, 0.0, sd) + 0.75 * smoothstep(0.0, -2.6, sd)
	for m: Vector4 in _mounds():
		var d := Vector2(p.x - m.x, p.y - m.y).length()
		h += m.w * exp(-(d * d) / (m.z * m.z))
	var r := Vector2(p.x * 0.85, (p.y + 6.0) * (1.0 if p.y < 0.0 else 1.35)).length()
	var rise := smoothstep(40.0, 110.0, r)
	h += rise * (7.0 + 20.0 * _noise.get_noise_2d(p.x * 0.6, p.y * 0.6) * 0.5 + 10.0)
	# The hall's terrace, cut level into the slope behind.
	var terrace := Vector2(maxf(absf(p.x - HALL.x) - HALL_SIZE.x * 0.5 - 6.0, 0.0),
			maxf(absf(p.y - HALL.y) - HALL_SIZE.y * 0.5 - 5.0, 0.0)).length()
	h = lerpf(GROUND, h, smoothstep(0.0, 8.0, terrace))
	# The torii's knoll and the pagoda's slope.
	h += 3.5 * exp(-Vector2(p.x - TORII.x, (p.y - TORII.y) * 0.7).length_squared() / 160.0)
	return h


var _noise := FastNoiseLite.new()
var _mound_cache: Array = []


## Low mossy mounds: (x, z, radius, height).
func _mounds() -> Array:
	if _mound_cache.is_empty():
		var half := live_room_half()
		_mound_cache = [Vector4(-half - 6.0, 3.0, 3.2, 0.5), Vector4(half + 6.5, 4.0, 3.5, 0.6),
				Vector4(-17.0, -12.0, 4.0, 0.7), Vector4(17.0, -14.0, 4.5, 0.8), Vector4(-6.0, -31.5, 3.5, 0.5),
				Vector4(13.0, -32.0, 4.0, 0.7), Vector4(-20.0, -24.0, 4.0, 0.9), Vector4(-half - 9.0, 13.0, 4.0, 0.6),
				Vector4(half + 10.0, 14.0, 4.0, 0.7)]
	return _mound_cache


# --- building -------------------------------------------------------------------------------

func _ready() -> void:
	_rng.seed = 88
	_noise.seed = 5
	_noise.frequency = 0.02
	var s := _season()
	_paper = StandardMaterial3D.new()
	_paper.albedo_color = Color(0.95, 0.88, 0.74)
	_paper.roughness = 0.9
	_paper.emission_enabled = true
	_paper.emission = Color(1.0, 0.62, 0.32)
	_paper.emission_energy_multiplier = s["paper"]
	_paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stone_glow = StandardMaterial3D.new()
	_stone_glow.albedo_color = Color(0.1, 0.08, 0.06)
	_stone_glow.emission_enabled = true
	_stone_glow.emission = Color(1.0, 0.6, 0.28)
	_stone_glow.emission_energy_multiplier = 1.4 * s["stone"]

	_build_deck()
	_raise_columns()
	_lay_ceiling()
	_put_on_the_roof()
	_rail_the_veranda()
	_hang_paper_lanterns()
	_lay_the_ground()
	_fill_the_pond()
	_set_the_stones()
	_stand_the_lanterns()
	_span_the_bridge()
	_build_the_wall()
	_raise_the_torii()
	_raise_the_pagoda()
	_build_the_hall()
	_plant_the_trees()
	_plant_the_hills()
	_let_it_fall()
	_dress_zones()


## The meshes in one of the garden's models, by object name, with their materials swapped by
## name (`swap`) and any surface whose material is in `drop` left out.
func _mesh(file: String, part: String, swap: Dictionary, drop: Array = []) -> Mesh:
	if not _meshes.has(file):
		var scene := (load(MODELS + file) as PackedScene).instantiate()
		var found := {}
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			found[String(node.name)] = (node as MeshInstance3D).mesh
		scene.free()
		_meshes[file] = found
	var source: Mesh = _meshes[file][part]
	var out := ArrayMesh.new()
	for i in source.get_surface_count():
		var m := source.surface_get_material(i)
		var key := m.resource_name if m != null else ""
		if drop.has(key):
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(i))
		out.surface_set_material(out.get_surface_count() - 1, swap.get(key, m))
	return out


func _place(mesh: Mesh, at: Vector3, yaw := 0.0, scale := Vector3.ONE, label := "Prop") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), at)
	add_child(node)
	return node


func _many(mesh: Mesh, xforms: Array, label: String, custom: Array = [], shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if not custom.is_empty():
			mm.set_instance_custom_data(i, custom[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _snowy(colour: Color, roughness := 0.8, tex := "", metres := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/garden_snowy.gdshader")
	m.set_shader_parameter("albedo", colour)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("snow", _season()["snow"])
	if tex != "":
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("tex", load("res://assets/textures/%s/%s_diff_%s.jpg" % [tex, tex,
				"1k" if tex == "gravel" else "2k"]))
		m.set_shader_parameter("tex_metres", metres)
	return m


## Hinoki: the deck and the zones' tops. Pale, fine-grained, oiled.
func _hinoki() -> StandardMaterial3D:
	# The grey planks' grain, warmed and lifted to the cream of cypress.
	return Materials.cached_scanned("garden_hinoki", "wood_planks_grey", "2k", 1.8, Color(1.3, 1.1, 0.84))


## The pavilion's frame: old timber stained dark.
func _timber() -> StandardMaterial3D:
	return Materials.cached_scanned("garden_timber", "weathered_brown_planks", "2k", 1.4, Color(0.4, 0.3, 0.24))


func _lacquer() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.68, 0.14, 0.06)
	m.roughness = 0.38
	return m


func _black_lacquer() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.03, 0.028)
	m.roughness = 0.25
	return m


func _stone() -> ShaderMaterial:
	return _snowy(Color(0.8, 0.77, 0.72), 0.9, "concrete_floor_worn_001", 1.2)


# --- the pavilion ---------------------------------------------------------------------------

## The boards at y = 0 out to the veranda's edge, the deck's body under them, and the stone
## footings and short posts it stands on over the garden.
func _build_deck() -> void:
	var half := live_room_half() + ENGAWA
	var front := Studio.ROOM_FRONT - ENGAWA
	var back := LIVE_ROOM_BACK + ENGAWA
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, back - front)
	deck.mesh = plane
	deck.position.z = (back + front) * 0.5
	deck.material_override = _hinoki()
	add_child(deck)
	# The deck's edge beam all round: under the boards, so its top is never in their plane.
	var timber := _timber()
	ZoneKit.block(self, Vector3(half * 2.0 + 0.04, 0.26, back - front + 0.04), Vector3(0, -0.006 - 0.13,
			(back + front) * 0.5), timber, "DeckEdge")
	# Posts on stones every 1.8 m round the edge and through the middle.
	var posts: Array = []
	var stones: Array = []
	var x := -half + 0.3
	while x <= half - 0.29:
		var z := front + 0.3
		while z <= back - 0.29:
			var edge := absf(x) > half - 0.5 or z < front + 0.5 or z > back - 0.5
			if edge or _rng.randf() < 0.25:
				var low := GROUND + 0.14
				posts.append(Transform3D(Basis.from_scale(Vector3(1, -0.15 - low, 1)), Vector3(x, (low - 0.15) * 0.5, z)))
				stones.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, GROUND - 0.06, z)))
			z += 1.8
		x += 1.8
	var post := CylinderMesh.new()
	post.top_radius = 0.1
	post.bottom_radius = 0.1
	post.height = 1.0
	post.radial_segments = 10
	_many(post, posts, "DeckPosts").material_override = timber
	var foot := CylinderMesh.new()
	foot.top_radius = 0.2
	foot.bottom_radius = 0.28
	foot.height = 0.36
	foot.radial_segments = 7
	_many(foot, stones, "Footings").material_override = _stone()
	# Steps down to the garden at the front, timber treads on stringers, and the stone you leave
	# your shoes on at their foot.
	var tread := Vector3(2.6, 0.06, 0.34)
	for i in 3:
		var y := -0.155 - i * 0.155
		ZoneKit.block(self, tread, Vector3(0, y - 0.03, front - 0.2 - i * 0.3), timber, "Step")
	for sx in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.08, 0.5, 1.0), Vector3(sx * 1.36, -0.37, front - 0.5), timber, "Stringer")
	_place(_mesh("garden_props.glb", "Rock3", {"stone": _stone()}), Vector3(0, GROUND - 0.05, front - 1.35),
			0.3, Vector3(2.2, 0.9, 1.4), "ShoeStone")


## The columns, each on a bronze-capped foot, a bearing block on its head, the beams over them
## all round with a tie beam lower down, and the frieze over the beams up into the eaves.
func _raise_columns() -> void:
	var timber := _timber()
	var bronze := Materials.cached_scanned("garden_bronze", "blue_metal_plate", "2k", 0.5, Color(0.42, 0.32, 0.2))
	bronze.metallic = 0.6
	var shafts: Array = []
	var feet: Array = []
	var blocks: Array = []
	for c in column_spots():
		shafts.append(Transform3D(Basis(), Vector3(c.x, COLUMN_TOP * 0.5, c.y)))
		feet.append(Transform3D(Basis(), Vector3(c.x, 0.09, c.y)))
		blocks.append(Transform3D(Basis(), Vector3(c.x, (COLUMN_TOP + 4.0) * 0.5, c.y)))
	var shaft := CylinderMesh.new()
	shaft.top_radius = COLUMN_R * 0.94
	shaft.bottom_radius = COLUMN_R
	shaft.height = COLUMN_TOP
	shaft.radial_segments = 16
	_many(shaft, shafts, "Columns").material_override = timber
	var foot := CylinderMesh.new()
	foot.top_radius = COLUMN_R + 0.02
	foot.bottom_radius = COLUMN_R + 0.035
	foot.height = 0.18
	foot.radial_segments = 16
	_many(foot, feet, "ColumnFeet").material_override = bronze
	var block := BoxMesh.new()
	block.size = Vector3(0.4, 4.0 - COLUMN_TOP, 0.4)
	_many(block, blocks, "BearingBlocks").material_override = timber
	var cx := column_x()
	var f := column_front()
	var b := column_back()
	var beam := BEAM_TOP - 4.0
	# Front and back beams run the whole width; the sides fit between them, a hair lower so the
	# corners' tops do not fight.
	for z in [f, b]:
		ZoneKit.block(self, Vector3(cx * 2.0 + 0.5, beam, 0.26), Vector3(0, 4.0 + beam * 0.5, z), timber, "Beam")
		ZoneKit.block(self, Vector3(cx * 2.0 + 0.3, 0.14, 0.13), Vector3(0, 3.2, z), timber, "TieBeam")
		# The frieze: boards from the beam up into the soffit, so there is no gap into the roof.
		ZoneKit.block(self, Vector3(cx * 2.0 + 0.46, 0.4, 0.06), Vector3(0, BEAM_TOP + 0.2, z + signf(z - 2.0) * 0.1),
				timber, "Frieze")
	for x in [-cx, cx]:
		ZoneKit.block(self, Vector3(0.26, beam - 0.004, b - f - 0.26), Vector3(x, 4.0 + (beam - 0.004) * 0.5,
				(f + b) * 0.5), timber, "Beam")
		ZoneKit.block(self, Vector3(0.13, 0.14 - 0.004, b - f - 0.13), Vector3(x, 3.2 - 0.002, (f + b) * 0.5),
				timber, "TieBeam")
		ZoneKit.block(self, Vector3(0.06, 0.4 - 0.004, b - f + 0.1), Vector3(x + signf(x) * 0.1, BEAM_TOP + 0.2,
				(f + b) * 0.5), timber, "Frieze")


## A coffered ceiling inside the columns: boards over a grid of battens.
func _lay_ceiling() -> void:
	var cx := column_x()
	var f := column_front()
	var b := column_back()
	var boards := Materials.cached_scanned("garden_ceiling", "wood_floor_deck", "2k", 1.2, Color(0.55, 0.42, 0.32))
	ZoneKit.block(self, Vector3(cx * 2.0 + 0.2, 0.06, b - f + 0.2), Vector3(0, BEAM_TOP + 0.03, (f + b) * 0.5), boards,
			"Ceiling")
	var battens: Array = []
	var step := 0.9
	var nx := int((cx * 2.0) / step)
	for i in range(1, nx):
		var x := -cx + cx * 2.0 * i / nx
		battens.append(Transform3D(Basis.from_scale(Vector3(1, 1, b - f)), Vector3(x, BEAM_TOP - 0.03, (f + b) * 0.5)))
	var nz := int((b - f) / step)
	for i in range(1, nz):
		var z := f + (b - f) * i / nz
		# 2 mm higher, so where they cross their undersides are not one plane.
		battens.append(Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(cx * 2.0, 1, 1)) * Basis(),
				Vector3(0, BEAM_TOP - 0.028, z)))
	var bar := BoxMesh.new()
	bar.size = Vector3(0.06, 0.06, 1.0)
	_many(bar, battens, "Coffers", [], false).material_override = _timber()


func _put_on_the_roof() -> void:
	var soffit := Materials.cached_scanned("garden_soffit", "wood_floor_deck", "2k", 1.0, Color(0.5, 0.38, 0.28))
	var stretch := (live_room_half() + COLUMN_OUT + EAVES_OUT) / ROOF_DRAWN_HALF
	var deep := ((column_back() - column_front()) * 0.5 + EAVES_OUT) / ROOF_DRAWN_DEPTH
	_place(_roof_mesh(soffit), Vector3(0, EAVE, (column_front() + column_back()) * 0.5), 0.0, Vector3(stretch, 1, deep),
			"Roof")


## A vermilion railing round the veranda's edge, open at the front steps: posts at every
## column's bay, a top rail and a low one, bronze caps on the posts.
func _rail_the_veranda() -> void:
	var lacquer := _snowy(Color(0.68, 0.14, 0.06), 0.4)
	var half := live_room_half() + ENGAWA - 0.12
	var front := Studio.ROOM_FRONT - ENGAWA + 0.12
	var back := LIVE_ROOM_BACK + ENGAWA - 0.12
	var runs := [[Vector2(-half, front), Vector2(-1.4, front)], [Vector2(1.4, front), Vector2(half, front)],
			[Vector2(-half, back), Vector2(half, back)], [Vector2(-half, front), Vector2(-half, back)],
			[Vector2(half, front), Vector2(half, back)]]
	var posts: Array = []
	var rails: Array = []
	var caps: Array = []
	for r: Array in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var n := maxi(int(a.distance_to(b) / 1.5), 1)
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			posts.append(Transform3D(Basis(), Vector3(p.x, RAIL * 0.5, p.y)))
			caps.append(Transform3D(Basis(), Vector3(p.x, RAIL + 0.05, p.y)))
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		var along := Basis(Vector3.UP, atan2(b.x - a.x, b.y - a.y))
		# The two rails at different heights per run, the side runs a few mm inboard so the corners'
		# rails cross rather than share faces.
		var inset := 0.004 if absf(a.x - b.x) < 0.01 else 0.0
		var stretch := along * Basis.from_scale(Vector3(1, 1, length))
		rails.append(Transform3D(stretch, Vector3(mid.x - signf(mid.x) * inset, RAIL - 0.03 - inset, mid.y)))
		rails.append(Transform3D(stretch, Vector3(mid.x - signf(mid.x) * inset, 0.18 - inset, mid.y)))
	var post := BoxMesh.new()
	post.size = Vector3(0.09, RAIL, 0.09)
	_many(post, posts, "RailPosts").material_override = lacquer
	var rail := BoxMesh.new()
	rail.size = Vector3(0.07, 0.06, 1.0)
	_many(rail, rails, "Rails").material_override = lacquer
	var cap := SphereMesh.new()
	cap.radius = 0.055
	cap.height = 0.13
	cap.radial_segments = 10
	cap.rings = 5
	var bronze := Materials.cached_scanned("garden_bronze", "blue_metal_plate", "2k", 0.5, Color(0.42, 0.32, 0.2))
	_many(cap, caps, "Giboshi", [], false).material_override = bronze


## Paper lanterns between the columns, hung from the beams: warm in the evening, faint by day.
## A few throw light down onto the deck's edge.
func _hang_paper_lanterns() -> void:
	var mesh := _mesh("garden_props.glb", "Chochin", {"paper": _paper, "lacquer": _black_lacquer()})
	var spots := column_spots()
	var hangs: Array = []
	var cx := column_x()
	for z in [column_front(), column_back()]:
		var row := spots.filter(func(c: Vector2) -> bool: return is_equal_approx(c.y, z))
		row.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for i in row.size() - 1:
			hangs.append(Vector3((row[i].x + row[i + 1].x) * 0.5, 4.0, z))
	for x in [-cx, cx]:
		var row := spots.filter(func(c: Vector2) -> bool: return is_equal_approx(c.x, x))
		row.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
		for i in row.size() - 1:
			hangs.append(Vector3(x, 4.0, (row[i].y + row[i + 1].y) * 0.5))
	# And from the ceiling over the walks between the neighbourhoods, in the middle of a back of
	# house twice as big as it was, which the lanterns round its edge no longer reach.
	var inner: Array[Vector3] = []
	for at: Vector2 in [Vector2(-0.5, 6.4), Vector2(0.5, 6.6), Vector2(-0.41, 10.6), Vector2(0.52, 9.0)]:
		inner.append(Vector3(at.x * cx, 4.0, at.y))
	hangs.append_array(inner)
	var xforms: Array = []
	for h: Vector3 in hangs:
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), h))
	_many(mesh, xforms, "PaperLanterns", [], false)
	# Light from the ones along the sides of the back of house and at the front corners.
	var lit: float = 0.6 + 0.4 * _season()["paper"]
	for h: Vector3 in hangs:
		if absf(h.x) > cx - 0.01 or (h.z < 0.0 and absf(h.x) > cx * 0.5) or inner.has(h):
			var l := OmniLight3D.new()
			l.name = "LanternLight"
			l.position = h + Vector3(0, -0.36, 0)
			l.light_color = Color(1.0, 0.68, 0.4)
			l.light_energy = 0.55 * lit
			l.omni_range = 4.2
			l.omni_attenuation = 1.4
			l.light_specular = 0.05
			l.shadow_enabled = false
			add_child(l)
			_lantern_lights.append([l, l.light_energy])


# --- the garden -----------------------------------------------------------------------------

## The ground: one mesh, dense near the pavilion and coarser out over the hills, painted by
## vertex colour into gravel, moss and earth for the ground shader.
func _lay_the_ground() -> void:
	var xs := _axis(-34.0, 34.0, 0.55, 260.0)
	var zs := _axis(-48.0, 34.0, 0.55, 260.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := []
	for z in zs:
		var row := []
		for x in xs:
			row.append(ground_at(Vector2(x, z)))
		heights.append(row)
	var half := live_room_half()
	var deck := Rect2(-half - ENGAWA - 0.2, Studio.ROOM_FRONT - ENGAWA - 0.2, (half + ENGAWA + 0.2) * 2.0,
			LIVE_ROOM_BACK - Studio.ROOM_FRONT + ENGAWA * 2.0 + 0.4)
	var drip := deck.grow(EAVES_OUT - ENGAWA + COLUMN_OUT + 0.3)
	for j in zs.size():
		for i in xs.size():
			var p := Vector2(xs[i], zs[j])
			st.set_color(_paint(p, deck, drip))
			st.set_uv(p)
			var h: float = heights[j][i]
			var dx: float = heights[j][mini(i + 1, xs.size() - 1)] - heights[j][maxi(i - 1, 0)]
			var dz: float = heights[mini(j + 1, zs.size() - 1)][i] - heights[maxi(j - 1, 0)][i]
			var wx: float = xs[mini(i + 1, xs.size() - 1)] - xs[maxi(i - 1, 0)]
			var wz: float = zs[mini(j + 1, zs.size() - 1)] - zs[maxi(j - 1, 0)]
			st.set_normal(Vector3(-dx / wx, 1.0, -dz / wz).normalized())
			st.add_vertex(Vector3(p.x, h, p.y))
	var w := xs.size()
	for j in zs.size() - 1:
		for i in w - 1:
			var a := j * w + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + w)
			st.add_index(a + 1)
			st.add_index(a + w + 1)
			st.add_index(a + w)
	st.generate_tangents()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/venues/shaders/garden_ground.gdshader")
	mat.set_shader_parameter("gravel_tex", load("res://assets/textures/gravel/gravel_diff_1k.jpg"))
	mat.set_shader_parameter("gravel_nor", load("res://assets/textures/gravel/gravel_nor_gl_1k.jpg"))
	var s := _season()
	mat.set_shader_parameter("snow", s["snow"])
	mat.set_shader_parameter("litter_colour", s["litter"][0])
	mat.set_shader_parameter("litter", s["litter"][1])
	if variant == AUTUMN:
		mat.set_shader_parameter("moss", Color(0.2, 0.26, 0.09))
		mat.set_shader_parameter("moss_dry", Color(0.4, 0.33, 0.14))
	var stones: Array = []
	for g: Vector4 in STONE_GROUPS:
		stones.append(Vector4(g.x, g.y, g.z, g.w))
	while stones.size() < 10:
		stones.append(Vector4(0, 0, -1, 0))
	mat.set_shader_parameter("stones", stones)
	mat.set_shader_parameter("stone_count", STONE_GROUPS.size())
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## Grid lines along one axis: `step` apart from `lo` to `hi`, then further and further apart out
## to `far` either way.
static func _axis(lo: float, hi: float, step: float, far: float) -> Array:
	var out := []
	var x := lo
	while x < hi:
		out.append(x)
		x += step
	out.append(hi)
	var gap := step
	x = hi
	while x < far:
		gap *= 1.22
		x += gap
		out.append(x)
	gap = step
	x = lo
	while x > -far:
		gap *= 1.22
		x -= gap
		out.push_front(x)
	return out


## What the ground is at `p`: raked gravel in front and round the pavilion, the drip line of dark
## pebbles under its eaves, earth in the pond and along the paths, moss everywhere else.
func _paint(p: Vector2, deck: Rect2, drip: Rect2) -> Color:
	var wobble := _noise.get_noise_2d(p.x * 8.0, p.y * 8.0) * 0.6
	var gravel := 0.0
	var g := GRAVEL
	var into := minf(minf(p.x - g.position.x, g.end.x - p.x), minf(p.y - g.position.y, g.end.y - p.y))
	gravel = smoothstep(-0.2, 0.4, into + wobble)
	# Round the pavilion, a band of gravel two metres wide.
	var ring := drip.grow(2.0)
	var into_ring := minf(minf(p.x - ring.position.x, ring.end.x - p.x), minf(p.y - ring.position.y, ring.end.y - p.y))
	gravel = maxf(gravel, smoothstep(-0.3, 0.3, into_ring + wobble * 0.5))
	# Moss islands round the stone groups.
	for s: Vector4 in STONE_GROUPS:
		var d := p.distance_to(Vector2(s.x, s.y))
		gravel *= smoothstep(s.z - 0.6, s.z - 0.2, d + wobble * 0.4)
	var sd := pond_distance(p)
	gravel *= smoothstep(0.6, 1.6, sd)
	var earth := 1.0 - smoothstep(-0.2, 0.5, sd)
	# The drip line: under the eaves' edge, a strip of dark stones.
	var into_drip := minf(minf(p.x - drip.position.x, drip.end.x - p.x), minf(p.y - drip.position.y, drip.end.y - p.y))
	if into_drip > -0.45 and into_drip < 0.45:
		earth = maxf(earth, 1.0)
		gravel = 0.0
	if deck.has_point(p):
		earth = 1.0
		gravel = 0.0
	# The path from the steps to the pond is stepping stones over the gravel; the path from the
	# gate is beaten earth.
	if absf(p.x) < 1.6 and p.y < WALL_Z + 8.0 and p.y > WALL_Z - 30.0:
		earth = maxf(earth, smoothstep(1.6, 1.0, absf(p.x + wobble * 0.3)))
	var moss := clampf(1.0 - gravel - earth, 0.0, 1.0)
	return Color(gravel, moss, earth)


## The pond's water, with koi under it and a ring of rounded stones along its bank.
func _fill_the_pond() -> void:
	var water := MeshInstance3D.new()
	water.name = "Pond"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 24.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 6
	water.mesh = plane
	water.position = Vector3(-2.0, WATER, -21.5)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/venues/shaders/garden_water.gdshader")
	if variant == WINTER:
		mat.set_shader_parameter("deep", Color(0.015, 0.025, 0.04))
		mat.set_shader_parameter("shallow", Color(0.05, 0.07, 0.1))
	elif variant == AUTUMN:
		mat.set_shader_parameter("shallow", Color(0.14, 0.14, 0.08))
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# The koi: each on a loop of its own inside one of the pond's ellipses.
	var koi := ShaderMaterial.new()
	koi.shader = preload("res://core/venues/shaders/garden_koi.gdshader")
	# In the cold they hang deep and barely move.
	koi.set_shader_parameter("pace", 0.35 if variant == WINTER else 1.0)
	var mesh := _mesh("garden_props.glb", "Koi", {"koi": koi})
	var xforms: Array = []
	var custom: Array = []
	var loops := [[Vector2(-5.0, -22.0), Vector2(5.5, 2.4), 6], [Vector2(0.5, -21.6), Vector2(3.4, 1.8), 4],
			[Vector2(-9.0, -22.5), Vector2(2.2, 1.6), 3], [Vector2(8.0, -27.0), Vector2(3.2, 1.6), 4],
			[Vector2(-13.0, -15.5), Vector2(1.4, 3.6), 2]]
	for l: Array in loops:
		for i in l[2]:
			var size := _rng.randf_range(0.5, 0.78)
			var c: Vector2 = l[0]
			var r: Vector2 = l[1] * _rng.randf_range(0.75, 1.0)
			xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3(c.x, WATER - 0.32, c.y)))
			var speed := _rng.randf_range(0.06, 0.11) * (1.0 if _rng.randf() < 0.6 else -1.0) * 4.0 / maxf(r.x, r.y)
			custom.append(Color(r.x / size, r.y / size, speed, _rng.randf() * TAU))
	var school := _many(mesh, xforms, "Koi", custom, false)
	school.custom_aabb = AABB(Vector3(-24, -4, -34), Vector3(42, 6, 26))
	# The bank: rounded stones along the water's edge, sampled round each ellipse where it is the
	# shore (not inside another).
	var rocks: Array = []
	for e: Vector4 in POND:
		var n := int((e.z + e.w) * 2.2)
		for i in n:
			var a := TAU * i / n + _rng.randf_range(-0.08, 0.08)
			var p := Vector2(e.x + cos(a) * e.z, e.y + sin(a) * e.w)
			if absf(pond_distance(p)) > 0.2:
				continue
			if p.distance_to(BRIDGE + Vector2(-3.6, 0)) < 1.2 or p.distance_to(BRIDGE + Vector2(3.6, 0)) < 1.2:
				continue
			var s := _rng.randf_range(0.35, 0.6)
			rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s)),
					Vector3(p.x, WATER - 0.1, p.y)))
	_many(_mesh("garden_props.glb", "Rock2", {"stone": _stone()}), rocks, "BankStones")


## The placed stones: in groups in the raked gravel, each group with a tall one and lower ones
## set round it; stepping stones from the pavilion's steps across the gravel to the pond and on
## across the water.
func _set_the_stones() -> void:
	var stone := _stone()
	var groups := [
		[["Rock0", Vector2(-6.2, -10.2), 1.25, 0.3], ["Rock1", Vector2(-5.0, -9.5), 0.9, 1.4], ["Rock2", Vector2(-6.9, -9.1), 0.7, 0.4]],
		[["Rock1", Vector2(5.0, -8.6), 1.1, 2.2], ["Rock3", Vector2(6.1, -8.0), 1.0, 0.7], ["Rock0", Vector2(4.2, -9.0), 0.7, 2.6]],
		[["Rock0", Vector2(9.1, -13.2), 1.0, 1.0], ["Rock2", Vector2(8.3, -12.4), 0.9, 2.0]],
		[["Rock2", Vector2(-1.6, -13.6), 0.85, 0.2]],
		[["Rock1", Vector2(-9.6, -6.9), 0.7, 1.7], ["Rock3", Vector2(-8.9, -6.4), 0.8, 2.9]],
	]
	for g: Array in groups:
		for s: Array in g:
			var at: Vector2 = s[1]
			_place(_mesh("garden_props.glb", s[0], {"stone": stone}), Vector3(at.x, ground_at(at) - 0.04, at.y), s[3],
					Vector3.ONE * s[2], "Stone")
	# Stepping stones: across the gravel from the steps, then across the pond.
	var path := [Vector2(0.4, -5.9), Vector2(-0.3, -6.9), Vector2(0.5, -7.9), Vector2(-0.1, -9.0), Vector2(0.6, -10.1),
			Vector2(0.1, -11.2), Vector2(0.9, -12.3), Vector2(1.6, -13.4), Vector2(2.3, -14.5), Vector2(2.9, -15.6),
			Vector2(3.3, -16.7)]
	var across := [Vector2(3.6, -18.0), Vector2(4.4, -19.2), Vector2(4.0, -20.4), Vector2(4.9, -21.6), Vector2(4.5, -22.8),
			Vector2(5.4, -24.0), Vector2(5.1, -25.3), Vector2(6.0, -26.5), Vector2(5.8, -27.8), Vector2(6.6, -29.0)]
	var xforms: Array = []
	for i in path.size():
		# The first ones out from the steps, moved out as far as the deck's front has, easing back
		# to where they cross the pond.
		var p: Vector2 = path[i] + Vector2(0, (Studio.ROOM_FRONT - DRAWN_FRONT) * (1.0 - float(i) / path.size()))
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.05, 0.5, 1.05)),
				Vector3(p.x, ground_at(p) - 0.05, p.y)))
	for p: Vector2 in across:
		# Standing up out of the water, their tops a hand above it.
		var bed := ground_at(p)
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.1, (WATER + 0.12 - bed) / 0.2, 1.1)),
				Vector3(p.x, bed, p.y)))
	_many(_mesh("garden_props.glb", "Rock3", {"stone": stone}), xforms, "SteppingStones")


## The stone lanterns: a pair flanking the steps, snow-viewing lanterns on the pond's banks, one
## at the bridge, pairs beside the pavilion and inside the gate. Lit in winter.
func _stand_the_lanterns() -> void:
	var stone := _stone()
	var half := live_room_half()
	var toro := _mesh("garden_props.glb", "Toro", {"stone": stone, "light": _stone_glow})
	var yukimi := _mesh("garden_props.glb", "Yukimi", {"stone": stone, "light": _stone_glow})
	var ahead := Studio.ROOM_FRONT - DRAWN_FRONT
	var spots := [[toro, Vector2(-2.7, -5.5 + ahead), 1.0], [toro, Vector2(2.7, -5.5 + ahead), 1.0], [yukimi, Vector2(1.4, -17.0), 1.1],
			[yukimi, Vector2(11.8, -23.9), 1.0], [toro, Vector2(-8.4, -12.6), 0.9], [toro, Vector2(-half - 3.4, 2.6), 1.0],
			[toro, Vector2(half + 3.4, 4.4), 1.0], [toro, Vector2(-3.4, WALL_Z + 3.5), 1.1], [toro, Vector2(3.4, WALL_Z + 3.5), 1.1]]
	var lit: bool = _season()["stone"] > 0.0
	var fires := 0
	for s: Array in spots:
		var at: Vector2 = s[1]
		var y := ground_at(at)
		var node := _place(s[0], Vector3(at.x, y, at.y), _rng.randf_range(-0.3, 0.3), Vector3.ONE * s[2], "StoneLantern")
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Only the nearer ones light the ground round them; the rest only glow.
		fires += 1
		if lit and fires <= 4:
			var l := OmniLight3D.new()
			l.name = "LanternFire"
			l.position = Vector3(at.x, y + (1.48 if s[0] == toro else 0.88) * s[2], at.y)
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 0.9
			l.omni_range = 5.0
			l.omni_attenuation = 1.5
			l.light_specular = 0.1
			add_child(l)
			_lantern_lights.append([l, l.light_energy])


func _span_the_bridge() -> void:
	var lacquer := _snowy(Color(0.7, 0.14, 0.06), 0.4)
	var deck := _snowy(Color(0.5, 0.4, 0.3), 0.85, "weathered_brown_planks", 1.4)
	var bronze := _snowy(Color(0.5, 0.38, 0.2), 0.4)
	bronze.set_shader_parameter("metallic", 0.6)
	var mesh := _mesh("garden_props.glb", "Bridge", {"lacquer": lacquer, "deck": deck, "bronze": bronze,
			"stone": _stone()})
	_place(mesh, Vector3(BRIDGE.x, GROUND, BRIDGE.y), 0.0, Vector3.ONE, "Bridge")


## The temple's earthen wall across the far side of the garden, ochre with five white lines (a
## temple of rank), a tiled cap; in its middle a roofed gate.
func _build_the_wall() -> void:
	var plaster := _snowy(Color(0.78, 0.62, 0.38), 0.95)
	var lines := _snowy(Color(0.92, 0.9, 0.86), 0.9)
	var base := _stone()
	var cap := _snowy(Color(0.2, 0.21, 0.23), 0.5)
	for side in [-1.0, 1.0]:
		var from := GATE_HALF + 0.3
		var to := 32.0
		var length := to - from
		var x: float = side * (from + to) * 0.5
		ZoneKit.block(self, Vector3(length, 0.6, 0.9), Vector3(x, GROUND + 0.3 - 0.4, WALL_Z), base, "WallBase")
		ZoneKit.block(self, Vector3(length, 2.3, 0.7), Vector3(x, GROUND + 0.2 + 1.15, WALL_Z), plaster, "Wall")
		for k in 5:
			ZoneKit.block(self, Vector3(length - 0.02, 0.07, 0.72), Vector3(x, GROUND + 1.0 + k * 0.24, WALL_Z), lines,
					"WallLine")
		for sz in [-1.0, 1.0]:
			# The two slopes a little different in length, so their ends are not one plane.
			var slab := ZoneKit.block(self, Vector3(length + 0.2 + sz * 0.03, 0.08, 0.75), Vector3(x, GROUND + 2.62, WALL_Z + sz * 0.3),
					cap, "WallCap")
			slab.rotation.x = sz * 0.42
		ZoneKit.block(self, Vector3(length + 0.24, 0.14, 0.16), Vector3(x, GROUND + 2.78, WALL_Z), cap, "WallRidge")
	var timber := _snowy(Color(0.36, 0.26, 0.18), 0.8, "weathered_brown_planks", 1.2)
	_place(_mesh("garden_props.glb", "Gate", {"timber": timber}), Vector3(0, GROUND, WALL_Z), 0.0, Vector3.ONE, "Gate")
	_place(_roof_mesh(), Vector3(0, GROUND + 4.35, WALL_Z), 0.0, Vector3(3.3 / ROOF_DRAWN_HALF, 0.42, 2.4 / 7.5),
			"GateRoof")


## The tiled roof's mesh (garden_roof.glb), dressed for the season: the pavilion's, the gate's
## and the hall's. Its soffit is boarded in `soffit`, or the frame's timber.
func _roof_mesh(soffit: Material = null) -> Mesh:
	var tiles := ShaderMaterial.new()
	tiles.shader = preload("res://core/venues/shaders/garden_roof.gdshader")
	tiles.set_shader_parameter("snow", _season()["snow"])
	var timber := _timber()
	return _mesh("garden_roof.glb", "Roof", {"tiles": tiles, "ridge": _snowy(Color(0.2, 0.21, 0.23), 0.5),
			"fascia": timber, "soffit": soffit if soffit != null else timber, "rafters": timber, "gable": timber})


func _raise_the_torii() -> void:
	var lacquer := _snowy(Color(0.72, 0.15, 0.06), 0.45)
	var black := _snowy(Color(0.04, 0.035, 0.03), 0.3)
	var y := ground_at(TORII)
	_place(_mesh("garden_props.glb", "Torii", {"lacquer": lacquer, "black": black}), Vector3(TORII.x, y - 0.1, TORII.y),
			0.0, Vector3.ONE * 1.25, "Torii")
	# Stone steps up the knoll to it, from the gate's path.
	var stone := _stone()
	for i in 10:
		var z := TORII.y + 6.0 + i * 1.1
		var at := Vector2(0, z)
		# Each a hair wider than the last, so their overlapping ends are not one plane.
		ZoneKit.block(self, Vector3(3.2 + i * 0.01, 0.3, 1.2), Vector3(0, ground_at(at) - 0.05, z), stone, "ToriiStep")


## A five-storey pagoda on the hillside: each storey a square body under its own roof, the
## roofs stepping in as it rises, a bronze spire of rings on top.
func _raise_the_pagoda() -> void:
	var y := ground_at(PAGODA)
	var timber := _snowy(Color(0.5, 0.18, 0.1), 0.7)
	var plaster := _snowy(Color(0.9, 0.87, 0.8), 0.9)
	var tiles := ShaderMaterial.new()
	tiles.shader = preload("res://core/venues/shaders/garden_roof.gdshader")
	tiles.set_shader_parameter("snow", _season()["snow"])
	tiles.set_shader_parameter("pitch", 0.15)
	var dark := _snowy(Color(0.2, 0.21, 0.23), 0.5)
	var roof := _mesh("garden_roof.glb", "RoofSquare", {"tiles": tiles, "ridge": dark, "fascia": timber,
			"soffit": timber, "rafters": timber, "gable": timber})
	ZoneKit.block(self, Vector3(8.0, 1.2, 8.0), Vector3(PAGODA.x, y + 0.4, PAGODA.y), _stone(), "PagodaPlinth")
	var at := y + 1.0
	for k in 5:
		var body := 5.6 - k * 0.55
		var tall := 3.4 if k == 0 else 2.6
		ZoneKit.block(self, Vector3(body, tall, body), Vector3(PAGODA.x, at + tall * 0.5, PAGODA.y), plaster, "PagodaStorey")
		ZoneKit.block(self, Vector3(body + 0.06, tall * 0.98, body * 0.3), Vector3(PAGODA.x, at + tall * 0.5, PAGODA.y),
				timber, "PagodaDoor")
		ZoneKit.block(self, Vector3(body * 0.3 - 0.004, tall * 0.98 - 0.004, body + 0.06), Vector3(PAGODA.x, at + tall * 0.5,
				PAGODA.y), timber, "PagodaDoor")
		var eave := body * 0.5 + 1.8 - k * 0.1
		# Low enough that its soffit meets the storey's walls; the next storey stands in it.
		_place(roof, Vector3(PAGODA.x, at + tall - 0.25, PAGODA.y), 0.0, Vector3(eave, 1.6, eave), "PagodaRoof")
		at += tall + 0.05
	var spire := CylinderMesh.new()
	spire.top_radius = 0.05
	spire.bottom_radius = 0.16
	spire.height = 6.5
	var bronze := _snowy(Color(0.46, 0.36, 0.2), 0.4)
	bronze.set_shader_parameter("metallic", 0.6)
	var mast := MeshInstance3D.new()
	mast.name = "Spire"
	mast.mesh = spire
	mast.material_override = bronze
	mast.position = Vector3(PAGODA.x, at + 3.0, PAGODA.y)
	add_child(mast)
	for r in 9:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.26 - r * 0.012
		ring.outer_radius = 0.34 - r * 0.012
		var node := MeshInstance3D.new()
		node.name = "SpireRing"
		node.mesh = ring
		node.material_override = bronze
		node.position = Vector3(PAGODA.x, at + 1.0 + r * 0.42, PAGODA.y)
		add_child(node)


## The main hall behind the zones: a stone platform, a veranda, vermilion columns and white
## walls with lattice doors of paper, under a great tiled roof. In winter its doors glow.
func _build_the_hall() -> void:
	var at := Vector3(HALL.x, GROUND, HALL.y)
	var w := HALL_SIZE.x
	var d := HALL_SIZE.y
	var stone := _stone()
	var timber := _snowy(Color(0.6, 0.16, 0.08), 0.6)
	var plaster := _snowy(Color(0.74, 0.71, 0.65), 0.9)
	ZoneKit.block(self, Vector3(w + 4.0, 1.3, d + 4.0), at + Vector3(0, 0.55, 0), stone, "HallPlinth")
	ZoneKit.block(self, Vector3(w + 2.4, 0.2, d + 2.4), at + Vector3(0, 1.3, 0), _timber(), "HallVeranda")
	var floor_y := GROUND + 1.4
	var tall := 5.6
	# Up past the doors' head into the roof, so there is no gap under its soffit.
	ZoneKit.block(self, Vector3(w, tall + 2.2, d), Vector3(at.x, floor_y + (tall + 2.2) * 0.5, at.z), plaster, "HallBody")
	# The front, toward the pavilion: paper doors between vermilion columns.
	var doors := StandardMaterial3D.new()
	doors.albedo_color = Color(0.72, 0.68, 0.58)
	doors.emission_enabled = true
	doors.emission = Color(1.0, 0.66, 0.36)
	doors.emission_energy_multiplier = [0.0, 0.2, 1.2][variant]
	var bays := 7
	var cols: Array = []
	for i in bays + 1:
		var x := -w * 0.5 + w * i / bays
		cols.append(Transform3D(Basis(), Vector3(at.x + x, floor_y + tall * 0.5, at.z - d * 0.5 - 0.22)))
		if i < bays:
			ZoneKit.block(self, Vector3(w / bays - 0.5, tall - 1.4, 0.06), Vector3(at.x + x + w / bays * 0.5,
					floor_y + (tall - 1.4) * 0.5 + 0.1, at.z - d * 0.5 - 0.03), doors, "HallDoor")
	var column := CylinderMesh.new()
	column.top_radius = 0.24
	column.bottom_radius = 0.26
	column.height = tall
	column.radial_segments = 14
	_many(column, cols, "HallColumns").material_override = timber
	ZoneKit.block(self, Vector3(w + 0.8, 0.5, 0.4), Vector3(at.x, floor_y + tall + 0.25, at.z - d * 0.5 - 0.22), timber,
			"HallBeam")
	# The doors' lattice, dark over the glowing paper.
	var lattice: Array = []
	for i in bays:
		var cx := -w * 0.5 + w * (i + 0.5) / bays
		for k in 5:
			lattice.append(Transform3D(Basis.from_scale(Vector3(1, tall - 1.4, 1)), Vector3(at.x + cx - 1.0 + k * 0.5,
					floor_y + (tall - 1.4) * 0.5 + 0.1, at.z - d * 0.5 - 0.07)))
		for k in 7:
			lattice.append(Transform3D(Basis.from_scale(Vector3(w / bays - 0.5, 1, 1)), Vector3(at.x + cx,
					floor_y + 0.3 + k * 0.62, at.z - d * 0.5 - 0.072)))
	# One bar a metre long, stretched: the uprights along Y, the rails along X.
	var bar := BoxMesh.new()
	bar.size = Vector3(0.05, 1.0, 0.04)
	var uprights := lattice.filter(func(t: Transform3D) -> bool: return t.basis.y.length() > 1.01)
	var rails := lattice.filter(func(t: Transform3D) -> bool: return t.basis.y.length() <= 1.01)
	_many(bar, uprights, "HallLattice", [], false).material_override = _black_lacquer()
	var rail := BoxMesh.new()
	rail.size = Vector3(1.0, 0.05, 0.04)
	_many(rail, rails, "HallRails", [], false).material_override = _black_lacquer()
	var stretch := Vector3((w * 0.5 + 3.2) / ROOF_DRAWN_HALF, 1.55, (d * 0.5 + 3.0) / 7.5)
	_place(_roof_mesh(), Vector3(at.x, floor_y + tall + 0.6, at.z), 0.0, stretch, "HallRoof")
	# Its steps down toward the pavilion.
	for i in 4:
		ZoneKit.block(self, Vector3(5.0, 0.32, 0.5), at + Vector3(0, 1.1 - i * 0.32 - 0.16, -d * 0.5 - 2.25 - i * 0.45), stone,
				"HallStep")


# --- trees ----------------------------------------------------------------------------------

## The season's trees round the garden (cherries and maples), the clipped pines by the water and
## the clipped shrubs on the mounds, each kind one MultiMesh.
func _plant_the_trees() -> void:
	var half := live_room_half()
	var bark := _snowy(Color(0.2, 0.15, 0.12), 0.9, "weathered_brown_planks", 0.8)
	var cherry_crown := _crown()
	var maple_crown := _crown()
	var winter := variant == WINTER
	var drop := ["crown"] if winter else []
	# None in the line of the autumn sun, low in the front left, so it reaches in under the eaves.
	var cherries := [Vector2(-half - 8.5, -1.5), Vector2(-half - 9.5, 10.0), Vector2(half + 8.0, 0.5), Vector2(half + 10.0, 12.0),
			Vector2(-20.5, -15.5), Vector2(-21.5, -20.0), Vector2(14.5, -9.0), Vector2(16.0, -29.0), Vector2(-9.0, -32.0),
			Vector2(-7.5, -37.0), Vector2(8.0, -37.0), Vector2(-14.0, 16.0), Vector2(-20.0, 4.0)]
	var maples := [Vector2(-half - 5.8, 6.0), Vector2(half + 6.4, 7.5), Vector2(-14.5, -12.5), Vector2(19.0, -16.0),
			Vector2(3.0, -34.0), Vector2(-17.0, -28.5), Vector2(13.0, 18.0), Vector2(20.0, 2.0), Vector2(12.0, -33.0)]
	for kind in [["Cherry", cherries, cherry_crown], ["Maple", maples, maple_crown]]:
		var spots: Array = kind[1]
		var by_shape := [[], []]
		var tints := [[], []]
		for i in spots.size():
			var p: Vector2 = spots[i]
			var s := _rng.randf_range(0.85, 1.12)
			by_shape[i % 2].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(p.x, ground_at(p) - 0.05, p.y)))
			tints[i % 2].append(_tint(kind[0], i))
		for k in 2:
			var mesh := _mesh("garden_trees.glb", "%s%s" % [kind[0], ["A", "B"][k]], {"bark": bark, "crown": kind[2]}, drop)
			var node := _many(mesh, by_shape[k], "%s%d" % [kind[0], k], tints[k])
			node.name = "%sTrees%d" % [kind[0], k]
	# Pines: leaning out over the water, and at the pavilion's front corners.
	var needles := _snowy(Color(0.1, 0.2, 0.09), 0.85)
	needles.set_shader_parameter("backlight", Color(0.05, 0.1, 0.03))
	needles.set_shader_parameter("sway", 0.03)
	var pine_mesh := _mesh("garden_trees.glb", "Pine", {"bark": bark, "needles": needles})
	var pines := [[Vector2(-5.6, -16.6), 2.8], [Vector2(7.8, -15.4), 0.5], [Vector2(-1.0, -30.6), 4.4],
			[Vector2(11.6, -20.8), 3.6], [Vector2(-half - 3.4, LIVE_ROOM_BACK + 2.4), 0.9],
			[Vector2(half + 4.2, Studio.ROOM_FRONT - 3.2), 2.2], [Vector2(-6.0, LIVE_ROOM_BACK + 4.0), 1.2], [Vector2(7.0, LIVE_ROOM_BACK + 3.6), 4.0]]
	var pine_xf: Array = []
	for p: Array in pines:
		var at: Vector2 = p[0]
		pine_xf.append(Transform3D(Basis(Vector3.UP, p[1]).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.15)),
				Vector3(at.x, ground_at(at) - 0.05, at.y)))
	_many(pine_mesh, pine_xf, "Pines")
	# Clipped shrubs on the mounds and along the pavilion's sides and the pond.
	var leaf := _snowy(Color(0.14, 0.26, 0.1), 0.85)
	leaf.set_shader_parameter("use_custom", true)
	var shrubs: Array = []
	var shrub_tints: Array = []
	for m: Vector4 in _mounds():
		for k in 5:
			var a := _rng.randf() * TAU
			var r := _rng.randf() * m.z * 0.6
			var p := Vector2(m.x + cos(a) * r, m.y + sin(a) * r)
			_add_shrub(shrubs, shrub_tints, p, _rng.randf_range(0.8, 1.6))
	for i in 20:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(side * (half + ENGAWA + _rng.randf_range(2.6, 3.4)),
				lerpf(Studio.ROOM_FRONT + 1.7, LIVE_ROOM_BACK + 1.2, float(i) / 19.0))
		_add_shrub(shrubs, shrub_tints, p, _rng.randf_range(0.9, 1.3))
	for e: Vector4 in POND:
		for k in 4:
			var a := _rng.randf() * TAU
			var p := Vector2(e.x + cos(a) * (e.z + 1.2), e.y + sin(a) * (e.w + 1.2))
			if pond_distance(p) > 0.8 and p.distance_to(BRIDGE) > 4.5 and absf(p.x - 4.5) > 2.0:
				_add_shrub(shrubs, shrub_tints, p, _rng.randf_range(0.9, 1.4))
	_many(_mesh("garden_props.glb", "Shrub", {"shrub": leaf}), shrubs, "Shrubs", shrub_tints)


func _add_shrub(xforms: Array, tints: Array, p: Vector2, s: float) -> void:
	var half := live_room_half()
	if absf(p.x) < half + ENGAWA + 2.2 and p.y > Studio.ROOM_FRONT - ENGAWA - 2.2 and p.y < LIVE_ROOM_BACK + ENGAWA + 2.2:
		return
	if pond_distance(p) < 0.6:
		return
	xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.1), s)),
			Vector3(p.x, ground_at(p) - 0.06, p.y)))
	# Azaleas: in spring a few in flower, in autumn a few gone red; snow on all of them in winter.
	var t := Color(1, 1, 1, 1)
	var roll := _rng.randf()
	if variant == SPRING and roll < 0.35:
		# Pink, red and white flowers over the leaves (the tint multiplies the leaf's green).
		t = [Color(6.4, 1.5, 6.0), Color(6.0, 0.77, 2.5), Color(6.0, 3.2, 8.0)][_rng.randi() % 3]
	elif variant == AUTUMN and roll < 0.4:
		t = [Color(5.0, 0.58, 0.6), Color(5.4, 1.35, 0.8)][_rng.randi() % 2]
	else:
		t = Color(_rng.randf_range(0.8, 1.15), _rng.randf_range(0.85, 1.1), _rng.randf_range(0.8, 1.05))
	tints.append(t)


## The crown's material: blossom, leaf or (in winter, left out) nothing; each tree tinted on its
## own through INSTANCE_CUSTOM, and translucent against the sun.
func _crown() -> ShaderMaterial:
	var m := _snowy(Color(1, 1, 1), 0.85)
	m.set_shader_parameter("use_custom", true)
	m.set_shader_parameter("backlight", Color(0.35, 0.22, 0.18))
	m.set_shader_parameter("sway", 0.06)
	m.set_shader_parameter("sway_height", 6.0)
	return m


## Each tree's colour this season.
func _tint(kind: String, i: int) -> Color:
	var r := fmod(i * 0.618, 1.0)
	match variant:
		SPRING:
			if kind == "Cherry":
				return Color(0.94, 0.6, 0.72).lerp(Color(0.98, 0.76, 0.84), r)
			return Color(0.42, 0.62, 0.2).lerp(Color(0.56, 0.7, 0.26), r)
		AUTUMN:
			if kind == "Cherry":
				return Color(0.66, 0.2, 0.06).lerp(Color(0.76, 0.36, 0.1), r)
			return [Color(0.78, 0.1, 0.05), Color(0.9, 0.3, 0.06), Color(0.86, 0.56, 0.08), Color(0.7, 0.06, 0.06)][i % 4]
	return Color(0.5, 0.45, 0.4)


## The hills: cedars in their hundreds, and among them broadleaf trees in the season's colour --
## wild cherry in spring, maple and beech blazing in autumn, bare grey in winter.
func _plant_the_hills() -> void:
	var bark := _snowy(Color(0.18, 0.14, 0.1), 0.9)
	var needles := _snowy(Color(0.06, 0.12, 0.07), 0.9)
	var round := _snowy(Color(1, 1, 1), 0.9)
	round.set_shader_parameter("use_custom", true)
	needles.set_shader_parameter("use_custom", true)
	var sugi: Array = []
	var sugi_c: Array = []
	var broad: Array = []
	var broad_c: Array = []
	for i in 1100:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(46.0, 190.0)
		var p := Vector2(cos(a) * r, sin(a) * r - 6.0)
		if p.y > -40.0 and p.y < 34.0 and absf(p.x) < 40.0:
			continue
		# Keep the line from the pavilion to the torii open.
		if absf(p.x - TORII.x) < 7.0 and p.y > TORII.y - 6.0:
			continue
		if p.distance_to(PAGODA) < 9.0:
			continue
		var y := ground_at(p)
		var conifer := _rng.randf() < 0.55
		if conifer:
			var tall := _rng.randf_range(9.0, 17.0)
			sugi.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(tall * 0.9, tall, tall * 0.9)),
					Vector3(p.x, y - 0.3, p.y)))
			sugi_c.append(Color(_rng.randf_range(0.8, 1.2), _rng.randf_range(0.85, 1.15), _rng.randf_range(0.8, 1.1), 1.0))
		else:
			var tall := _rng.randf_range(6.0, 10.0)
			broad.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(tall * 1.2, tall, tall * 1.2)),
					Vector3(p.x, y - 0.3, p.y)))
			broad_c.append(_hill_colour())
	_many(_mesh("garden_trees.glb", "Sugi", {"bark": bark, "needles": needles}), sugi, "Cedars", sugi_c, false)
	_many(_mesh("garden_trees.glb", "Round", {"bark": bark, "crown": round}), broad, "HillTrees", broad_c, false)
	# Cedars flanking the torii and the steps up to it.
	var flank: Array = []
	var flank_c: Array = []
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(TORII.x + side * _rng.randf_range(7.5, 12.0), TORII.y - 4.0 + (i / 2) * 3.2)
		var tall := _rng.randf_range(16.0, 22.0)
		flank.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(tall * 0.8, tall, tall * 0.8)),
				Vector3(p.x, ground_at(p) - 0.3, p.y)))
		flank_c.append(Color(1, 1, 1, 1))
	_many(_mesh("garden_trees.glb", "Sugi", {"bark": bark, "needles": needles}), flank, "ToriiCedars", flank_c, false)


func _hill_colour() -> Color:
	var r := _rng.randf()
	match variant:
		SPRING:
			if r < 0.22:
				return Color(1.0, 0.82, 0.86)
			return Color(0.32, 0.5, 0.2).lerp(Color(0.5, 0.62, 0.26), _rng.randf())
		AUTUMN:
			return [Color(0.8, 0.16, 0.06), Color(0.9, 0.42, 0.08), Color(0.85, 0.62, 0.12), Color(0.5, 0.3, 0.12),
					Color(0.3, 0.36, 0.14)][int(r * 5.0)]
	return Color(0.42, 0.38, 0.36, 0.6)


# --- what falls ------------------------------------------------------------------------------

## Petals in spring, leaves in autumn, snow in winter: GPU particles over the garden that come
## to rest where they land (a height field of the scene stops them), the snow vanishing into what
## it lands on. None falls under the roof: the roof is in the height field.
func _let_it_fall() -> void:
	var half := live_room_half()
	var field := GPUParticlesCollisionHeightField3D.new()
	field.name = "FallField"
	field.size = Vector3(90.0, 30.0, 90.0)
	field.position = Vector3(0, 6.0, -12.0)
	field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(field)
	var boxes: Array = []
	match variant:
		SPRING:
			# Over the cherries and the garden in front.
			boxes = [[Vector3(0, 7.0, -18.0), Vector3(24.0, 3.5, 14.0), 1400], [Vector3(-half - 9.0, 6.0, 4.0),
					Vector3(4.5, 3.0, 9.0), 500], [Vector3(half + 9.0, 6.0, 5.0), Vector3(4.5, 3.0, 9.0), 500]]
		AUTUMN:
			boxes = [[Vector3(0, 7.0, -18.0), Vector3(24.0, 3.5, 14.0), 700], [Vector3(-half - 7.0, 5.5, 5.0),
					Vector3(4.0, 3.0, 8.0), 260], [Vector3(half + 7.5, 5.5, 6.0), Vector3(4.0, 3.0, 8.0), 260]]
		WINTER:
			boxes = [[Vector3(0, 9.0, -6.0), Vector3(28.0, 4.0, 24.0), 4500]]
	for b: Array in boxes:
		var f := GPUParticles3D.new()
		f.name = "Falling"
		f.position = b[0]
		f.amount = b[2]
		f.lifetime = 18.0 if variant != WINTER else 16.0
		f.preprocess = f.lifetime
		f.collision_base_size = 0.02
		f.visibility_aabb = AABB(-b[1] - Vector3(4, 14, 4), b[1] * 2.0 + Vector3(8, 18, 8))
		f.process_material = _fall_material(b[1])
		f.draw_pass_1 = _fall_mesh()
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		_falling.append(f)


func _fall_material(extents: Vector3) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3(0.3, -1, 0.1)
	m.spread = 25.0
	m.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT if variant == WINTER \
			else ParticleProcessMaterial.COLLISION_RIGID
	m.collision_friction = 1.0
	m.collision_bounce = 0.0
	m.turbulence_enabled = true
	m.turbulence_noise_scale = 3.0
	match variant:
		WINTER:
			# Falling steadily, not accelerating: what pulls it down is spent against the air.
			m.initial_velocity_min = 0.7
			m.initial_velocity_max = 1.1
			m.gravity = Vector3(0.02, -0.02, 0)
			m.turbulence_noise_strength = 0.2
			m.turbulence_influence_min = 0.02
			m.turbulence_influence_max = 0.06
			m.scale_min = 0.6
			m.scale_max = 1.4
		_:
			# A petal or a leaf flutters: slow, swinging, turning over as it falls.
			m.initial_velocity_min = 0.45 if variant == SPRING else 0.7
			m.initial_velocity_max = 0.8 if variant == SPRING else 1.1
			m.gravity = Vector3(0.04, -0.03, 0.02)
			m.turbulence_noise_strength = 0.9
			m.turbulence_influence_min = 0.08
			m.turbulence_influence_max = 0.2
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.angular_velocity_min = -120.0
			m.angular_velocity_max = 120.0
			m.particle_flag_rotate_y = true
			m.scale_min = 0.7
			m.scale_max = 1.3
			var ramp := Gradient.new()
			if variant == SPRING:
				ramp.set_color(0, Color(1.0, 0.86, 0.9))
				ramp.set_color(1, Color(1.0, 0.72, 0.8))
			else:
				ramp.set_color(0, Color(0.85, 0.14, 0.05))
				ramp.add_point(0.5, Color(0.95, 0.48, 0.08))
				ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 0.7, 0.15))
			var tex := GradientTexture1D.new()
			tex.gradient = ramp
			m.color_initial_ramp = tex
			# Lying where it landed, then gone at the end of its life.
			var fade := Gradient.new()
			fade.set_color(0, Color(1, 1, 1, 1))
			fade.add_point(0.88, Color(1, 1, 1, 1))
			fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
			var fade_tex := GradientTexture1D.new()
			fade_tex.gradient = fade
			m.color_ramp = fade_tex
	return m


func _fall_mesh() -> Mesh:
	if variant == WINTER:
		var flake := StandardMaterial3D.new()
		flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flake.albedo_color = Color(0.82, 0.86, 0.95, 0.85)
		flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flake.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		flake.billboard_keep_scale = true
		var soft := GradientTexture2D.new()
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(0.5, 0.5)
		soft.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		soft.gradient = g
		soft.width = 32
		soft.height = 32
		flake.albedo_texture = soft
		var quad := QuadMesh.new()
		quad.size = Vector2(0.035, 0.035)
		quad.material = flake
		return quad
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	m.backlight_enabled = true
	m.backlight = Color(0.4, 0.25, 0.2)
	var part := "Petal" if variant == SPRING else "Leaf"
	var mesh := _mesh("garden_props.glb", part, {}) as ArrayMesh
	mesh.surface_set_material(0, m)
	var size := 0.026 if variant == SPRING else 0.07
	var scaled := ArrayMesh.new()
	var arrays := mesh.surface_get_arrays(0)
	# Tipped up, so that spun about the vertical as it falls it turns over and back.
	var tip := Basis(Vector3.RIGHT, 0.9)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = tip * verts[i] * size
		normals[i] = tip * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	scaled.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	scaled.surface_set_material(0, m)
	return scaled


# --- the zones ------------------------------------------------------------------------------

## The zones on the deck, in the pavilion's own materials: a hinoki riser on a black lacquer
## skirt, a booth framed in dark timber with paper-pale glass, the lattice's square laid with
## tatami, a hinoki table on lacquered legs, and the keys on a stand of black lacquer. Bronze
## temple lanterns hang from the ceiling over the riser, the table and the keys.
func _dress_zones() -> void:
	var z := zones()
	var hinoki := Materials.cached_scanned("garden_riser", "wood_planks_grey", "2k", 0.9, Color(1.3, 1.1, 0.84))
	var black := _black_lacquer()
	var timber := _timber()

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, hinoki, black)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.95, 0.92, 0.84, 0.14)
	glass.roughness = 0.12
	glass.metallic_specular = 0.6
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, timber, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.74, 0.5), 1.3, 60.0, 3.2,
			timber)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	_lay_tatami(matrix)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, hinoki, black)
	_dress_prop_shelf(hinoki, black, Color(1.0, 0.74, 0.48))

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, black, hinoki)

	# Bronze lanterns hung from the ceiling over the riser, the table, the keys and the lattice,
	# each throwing a pool down.
	var bronze := Materials.cached_scanned("garden_bronze", "blue_metal_plate", "2k", 0.5, Color(0.42, 0.32, 0.2))
	var tsuri := _mesh("garden_props.glb", "Tsuri", {"bronze": bronze, "light": _stone_glow if variant == WINTER else _paper})
	for id in [&"drums", &"bricks", &"synth", &"matrix"]:
		var box: AABB = z[id]
		var at := Vector3(box.get_center().x, BEAM_TOP, box.get_center().z)
		if id == &"synth":
			at.x -= 0.5
		var lamp := _place(tsuri, at, 0.0, Vector3.ONE, "TempleLantern")
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spot := ZoneKit.spot_down(self, at + Vector3(0, -0.75, 0), Color(1.0, 0.7, 0.42),
				1.9 if id != &"matrix" else 1.4, 62.0, 5.0)
		spot.name = "LanternPool"
		_lantern_lights.append([spot, spot.light_energy])


## Eight tatami in the lattice's square, each a rush mat bound along its long sides in black
## cloth, laid in the pinwheel a room of tatami is laid in.
func _lay_tatami(parent: Node3D) -> void:
	var rush := Materials.cached_scanned("garden_tatami", "rough_linen", "1k", 0.5, Color(0.78, 0.74, 0.5))
	var heri := StandardMaterial3D.new()
	heri.albedo_color = Color(0.06, 0.07, 0.06)
	heri.roughness = 0.8
	var mat := Vector2(1.54, 0.77)
	var gap := 0.004
	# (centre x, centre z, long side along X?) in the 3.08 m square.
	var laid := [[-0.77, -1.155, true], [0.77, -1.155, true], [-1.155, 0.0, false], [-0.385, 0.0, false],
			[0.385, 0.0, false], [1.155, 0.0, false], [-0.77, 1.155, true], [0.77, 1.155, true]]
	for t: Array in laid:
		var along_x: bool = t[2]
		var size := Vector3(mat.x - gap, 0.022, mat.y - gap) if along_x else Vector3(mat.y - gap, 0.022, mat.x - gap)
		var at := Vector3(t[0], 0.011, t[1])
		ZoneKit.block(parent, size, at, rush, "Tatami")
		# The binding: a strip along each long edge, a hair proud of the mat's top and sides.
		for s in [-1.0, 1.0]:
			if along_x:
				ZoneKit.block(parent, Vector3(size.x + 0.002, 0.024, 0.04), at + Vector3(0, 0.003, s * (size.z * 0.5 - 0.019)),
						heri, "Heri")
			else:
				ZoneKit.block(parent, Vector3(0.04, 0.024, size.z + 0.002), at + Vector3(s * (size.x * 0.5 - 0.019), 0.003, 0),
						heri, "Heri")


## The mirror stands on the deck in a frame of dark timber with a vermilion lip.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.06, 0.04, 0.012, _timber())
	Venue.frame_bars(mirror, 0.012, 0.03, 0.016, _lacquer(), 0.006)


## The tracks' colours here (TrackColours), in its STANDARD order: the old dyes and pigments --
## vermilion, persimmon, yamabuki gold, young-leaf green, pine, celadon, sky, indigo, wisteria,
## peony, cherry blossom, and mouse grey.
func track_palette() -> Array:
	return [
		Color(0.86, 0.26, 0.16), Color(0.93, 0.52, 0.22), Color(0.96, 0.74, 0.2), Color(0.6, 0.72, 0.25),
		Color(0.24, 0.52, 0.3), Color(0.32, 0.64, 0.56), Color(0.45, 0.66, 0.86), Color(0.2, 0.3, 0.6),
		Color(0.6, 0.5, 0.8), Color(0.76, 0.3, 0.55), Color(0.97, 0.7, 0.76), Color(0.6, 0.58, 0.55),
	]
