class_name LoftVenue
extends Venue

## A converted warehouse at night: one long brick room, concrete underfoot, steel overhead, and
## tall factory windows on a city that is still up. The desk stands in the middle of it rather
## than in a room of its own -- a loft has no control room, only the end you work at -- and the
## activity zones fill the far end, with a steel gallery along the back wall to look down on the
## lattice from.
##
## Lit the way a loft is at night: enamel pendants hung low on long cords, each zone's own
## fitting, and the moon and the city coming in through the glass. Nothing from the ceiling but
## what hangs from it.
##
## Three arrangements (Venue.VARIANTS), the same room at three times: City night, as above; Sunday
## morning, the pendants off and a low sun streaming in at the left-hand windows, laying their
## glazing bars across the concrete in shafts of dusty air, plants on the sills, a sofa and the
## coffee by the glass, the city out there in daylight; and Thunderstorm, rain streaming down the
## glass, the city drowned in it, lightning flashing the room now and then, puddles under the
## windows where the old frames leak, a bucket under the drip, and the pendants on and swinging
## in the draught.

## Floor to the underside of the roof deck. A warehouse floor is tall; this is what makes the
## windows tall.
const HEIGHT := 5.6
## Brick, 32 cm: an outside wall of a building this age, and thick enough for a deep reveal.
const WALL := 0.32
## Where the room's front wall stands, in front of the desk. The footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The windows' sill and head, and how wide one bay of glass is.
const SILL := 0.95
const HEAD := 4.6
const BAY := 1.7
## Window bays: centres along the front wall (x) and the left wall (z). The front's middle bay is
## behind the timeline, which is a shame and also what a real loft would make you do.
const FRONT_BAYS := [-4.3, -1.6, 1.6, 4.3]
const LEFT_BAYS := [-0.9, 1.25]
## Iron columns holding the roof up, either side of the desk: [x, z] at the base width.
const COLUMNS := [Vector2(-4.6, -0.6), Vector2(4.6, -0.6), Vector2(-4.6, 2.6), Vector2(4.6, 2.6)]
const COLUMN_RADIUS := 0.13
## The gallery along the back wall: its deck's height, and how far it reaches into the room.
## Above every zone's head room (Venue.ZONES), so the lattice stands under it and is seen from it.
const GALLERY_Y := 3.6
const GALLERY_DEPTH := 0.95
## The gallery's deck boards, on its frame: what you stand on up there.
const DECK_TOP := GALLERY_Y + 0.06
## The stair up to it: a straight flight in front of the gallery's edge, rising toward the right
## wall, each step a riser no taller than the walker steps (Walker.STEP_HEIGHT) and a tread
## deep enough to stand on. It lands at the gallery's right-hand end, where the rail stops short.
const STAIR_STEPS := 12
const STAIR_TREAD := 0.3
const STAIR_WIDTH := 0.62
const LANDING := 1.0
## Steel beams across the room under the roof deck, this far apart.
const BEAM_SPACING := 2.4

## The arrangements (Venue.VARIANTS).
const NIGHT := 0
const SUNDAY := 1
const STORM := 2

## Where the Sunday sun is going: in at the left-hand windows from low in the west-ish sky behind
## them, down across the floor toward the front -- so it lays the left windows' bars across the
## concrete by the desk, and rakes the faces of the towers out in front. Its height is a morning's.
const SUN_TRAVEL := Vector3(1.0, -0.46, -0.36)
## The Sunday corner by the left windows, at the base width: the sofa's middle (it faces the
## glass), and the low table between it and the windows.
const SOFA_AT := Vector2(-3.75, 0.6)
const SOFA_SIZE := Vector2(0.86, 2.0)
const SOFA_TOP := 0.8
const TABLE_AT := Vector2(-5.05, 0.6)
const TABLE_SIZE := Vector2(0.5, 1.0)
const TABLE_TOP := 0.4
## Where the storm's leak comes through the roof, at the base width: the bucket stands under it.
const LEAK_AT := Vector2(4.75, 1.5)

const MODELS := "res://assets/models/"

var _city_mat: ShaderMaterial
## The storm's: what flashes with the lightning, and what swings in the draught.
var _sky_mat: ShaderMaterial
var _rain_glass: ShaderMaterial
var _env: Environment
var _key: DirectionalLight3D
var _puddles: Array[ShaderMaterial] = []
var _rain: Array[GPUParticles3D] = []
## Each swinging pendant: its pivot at the top of the cord, and its own phase and reach.
var swingers: Array[Node3D] = []
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
## The next strike, from the start of the arrangement; the one going now, and its shape.
var _next_strike := 9.0
var _strike_at := -100.0
var _strike: Array = []
## How bright the lightning is right now, 0..1: read by the tests and by anything that cares.
var flash := 0.0


func venue_id() -> StringName:
	return &"loft"


## Industrial: raw steel plate, black iron and reclaimed walnut, the warehouse's own vocabulary.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("blue_metal_plate", 1.6, Color(0.85, 0.8, 0.76))) \
			.with("chassis", GearStyle.paint(Color(0.075, 0.085, 0.095), 0.5, 0.5)) \
			.with("brushed", GearStyle.metal(Color(0.3, 0.29, 0.28), 0.5)) \
			.with("trim", GearStyle.metal(Color(0.2, 0.19, 0.18), 0.55)) \
			.with("end_cheek", GearStyle.scan("black_walnut_veneer_01", 0.8, Color(0.55, 0.42, 0.32))) \
			.with("lamp_shade", GearStyle.paint(Color(0.12, 0.25, 0.18), 0.35, 0.2)) \
			.with("loom_band", GearStyle.paint(Color(0.75, 0.3, 0.15), 0.7, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.06, 0.06, 0.06), 0.3, 0.0))


## Dark steel plate, chalky white lettering, brick-orange arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.scan("blue_metal_plate", 0.6, Color(0.3, 0.3, 0.3))
	board.ink = Color(0.92, 0.9, 0.86)
	board.accent = Color(0.95, 0.5, 0.3)
	board.board_ink_fade = Color(0.45, 0.44, 0.43)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	if variant == SUNDAY:
		_dress_sunday(env, key)
		return
	if variant == STORM:
		_dress_storm(env, key)
		return
	env.background_mode = Environment.BG_COLOR
	# The night past the glass: not black, a city sky has light in it from below.
	env.background_color = Color(0.022, 0.03, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.42, 0.55)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	# Distance in the city: the far towers sink into the night.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.06, 0.1)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 220.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.4
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_out = 1.4
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.7, 0.75, 0.85)
		env.volumetric_fog_length = 12.0
		env.volumetric_fog_ambient_inject = 0.0

	# The moon, low over the city in front and to the left, coming in through the glass: cool,
	# faint, and the only thing in the room that casts a window's shape on the floor.
	key.light_color = Color(0.62, 0.72, 1.0)
	key.light_energy = 0.32
	key.rotation_degrees = Vector3(-24.0, -35.0, 0.0)
	key.light_specular = 0.1


## Sunday morning: a clear sky with the sun low in it behind the left-hand windows, the room lit
## by what comes in at the glass -- the sun's own shafts, and the sky's light off the concrete.
func _dress_sunday(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/dusk_sky.gdshader")
	# A washed blue overhead going pale and warm at the horizon, haze over the streets.
	_sky_mat.set_shader_parameter("zenith", Color(0.2, 0.36, 0.66))
	_sky_mat.set_shader_parameter("upper", Color(0.36, 0.52, 0.78))
	_sky_mat.set_shader_parameter("rose", Color(0.62, 0.7, 0.84))
	_sky_mat.set_shader_parameter("horizon", Color(0.95, 0.84, 0.66))
	_sky_mat.set_shader_parameter("haze", Color(0.55, 0.52, 0.5))
	_sky_mat.set_shader_parameter("sun_dir", -SUN_TRAVEL.normalized())
	_sky_mat.set_shader_parameter("sun_radius", 0.025)
	_sky_mat.set_shader_parameter("sun_colour", Color(1.0, 0.9, 0.72))
	_sky_mat.set_shader_parameter("stars", 0.0)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.3
	# A morning's haze over the city: the far towers go pale into it.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.62, 0.66, 0.74)
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 320.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0025
		env.volumetric_fog_albedo = Color(0.95, 0.9, 0.82)
		env.volumetric_fog_length = 14.0
		env.volumetric_fog_ambient_inject = 0.0
	# The sun: low, warm, and the one light in the room, in at the left-hand windows.
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 3.0
	key.basis = Basis.looking_at(SUN_TRAVEL.normalized(), Vector3.UP)
	key.light_specular = 0.3
	# The sun's own size, not the house key's soft panel: sharp enough to draw the glazing bars.
	key.light_angular_distance = 0.5


## The storm: a low, heavy sky over a city gone dim in the rain, the room lit by its pendants,
## and every so often the lightning (see _process), which this keeps hold of to flash.
func _dress_storm(env: Environment, key: DirectionalLight3D) -> void:
	_env = env
	_key = key
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/loft_storm_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.4, 0.52)
	env.ambient_light_energy = STORM_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The rain between here and the rest of the city: the towers go grey into it, close.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = STORM_FOG
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 140.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.4
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_out = 1.4
	# The storm's light, from the sky in front and to the left: between strikes a cold grey-blue
	# off the cloud and the wet city, enough for the brick and the bars; when it strikes, the
	# lightning, white.
	key.light_color = Color(0.72, 0.8, 1.0)
	key.light_energy = STORM_FILL
	key.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key.light_specular = 0.6


## The storm's haze between strikes, and the light the lightning throws: room and sky together.
const STORM_FOG := Color(0.04, 0.045, 0.06)
const STRIKE_KEY := 3.2
const STRIKE_AMBIENT := 0.9
const STORM_FILL := 0.5
const STORM_AMBIENT := 0.16


func _process(delta: float) -> void:
	if variant != STORM:
		return
	_clock += delta
	# The pendants swing in the draught: each on its cord's own period, a gust now and then
	# pushing them all a little further.
	var gust := 0.55 + 0.45 * sin(_clock * 0.37) * sin(_clock * 0.23 + 1.0)
	for i in swingers.size():
		var p := swingers[i]
		var phase: float = p.get_meta(&"phase")
		var period: float = p.get_meta(&"period")
		p.rotation.x = deg_to_rad(3.2) * gust * sin(_clock * TAU / period + phase)
		p.rotation.z = deg_to_rad(1.6) * gust * sin(_clock * TAU / (period * 1.13) + phase * 1.7)
	_lightning()


## The lightning: now and then a strike, a few flickers over most of a second, the room lit
## white from the windows' side and the sky lit round the bolt.
func _lightning() -> void:
	if _clock >= _next_strike:
		_strike_at = _clock
		_next_strike = _clock + _rng.randf_range(7.0, 19.0)
		# Its flickers: [start, strength, how quickly it dies], in seconds from the strike.
		_strike = [[0.0, 1.0, 0.07]]
		var t := 0.0
		for i in _rng.randi_range(1, 3):
			t += _rng.randf_range(0.08, 0.22)
			_strike.append([t, _rng.randf_range(0.45, 1.0), _rng.randf_range(0.06, 0.18)])
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("bolt", _rng.randf_range(-1.1, 0.5))
			_sky_mat.set_shader_parameter("bolt_seed", _rng.randf() * 100.0)
	var since := _clock - _strike_at
	var f := 0.0
	for k: Array in _strike:
		var dt: float = since - k[0]
		if dt >= 0.0:
			f = maxf(f, k[1] * exp(-dt / k[2]))
	flash = f if since < 2.0 else 0.0
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("flash", flash)
	if _rain_glass != null:
		_rain_glass.set_shader_parameter("flash", flash)
	for m in _puddles:
		m.set_shader_parameter("flash", flash)
	if _key != null:
		_key.light_energy = STORM_FILL + flash * STRIKE_KEY
	if _env != null:
		_env.ambient_light_energy = STORM_AMBIENT + flash * STRIKE_AMBIENT
		_env.fog_light_color = STORM_FOG.lerp(Color(0.5, 0.55, 0.7), flash * 0.6)


func lamp_colour(_index: int, authored: Color) -> Color:
	# Tungsten, warmer than the studio's: bare bulbs in an old building.
	return authored.lerp(Color(1.0, 0.7, 0.42), 0.4)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.85


## Past the footprint the loft is one room: the floor either side of the desk is as walkable as
## the far end, so two strips beside the footprint join it to the back of house.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


func _column_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c: Vector2 in COLUMNS:
		out.append(Vector2(c.x + signf(c.x) * _grow(), c.y))
	return out


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	for c in _column_spots():
		out.append({"c": c, "h": Vector2.ONE * COLUMN_RADIUS, "a": 0.0, "top": HEIGHT})
	# The stair, a step at a time, and the gallery it climbs to: you walk up one onto the other.
	out.append_array(stair_steps())
	var half := live_room_half()
	var front := LIVE_ROOM_BACK - GALLERY_DEPTH
	out.append({"c": Vector2(0, LIVE_ROOM_BACK - GALLERY_DEPTH * 0.5), "h": Vector2(half, GALLERY_DEPTH * 0.5),
			"a": 0.0, "top": DECK_TOP})
	# And its rail, which keeps you on it except where the stair comes up.
	var gap := _landing_x()
	out.append({"c": Vector2((gap - half) * 0.5, front + 0.03), "h": Vector2((gap + half) * 0.5, 0.03),
			"a": 0.0, "top": DECK_TOP + 1.1})
	# Sunday's sofa and its table by the windows; the storm's bucket under the leak.
	if variant == SUNDAY:
		out.append({"c": _beside(SOFA_AT), "h": SOFA_SIZE * 0.5, "a": 0.0, "top": SOFA_TOP})
		out.append({"c": _beside(TABLE_AT), "h": TABLE_SIZE * 0.5, "a": 0.0, "top": TABLE_TOP})
		out.append({"c": _big_plant_spot(), "h": Vector2(0.22, 0.22), "a": 0.0, "top": 1.2})
	elif variant == STORM:
		out.append({"c": _beside(LEAK_AT), "h": Vector2(0.17, 0.17), "a": 0.0, "top": 0.3})
	return out


## A spot beside the desk, at the base width, moved out with its side of the room as it widens.
func _beside(at: Vector2) -> Vector2:
	return Vector2(at.x + signf(at.x) * _grow(), at.y)


## The stair's steps as walker footprints: each a column from the floor to its tread.
func stair_steps() -> Array:
	var out := []
	var half := live_room_half()
	var start := half - 0.05 - STAIR_STEPS * STAIR_TREAD
	var z := LIVE_ROOM_BACK - GALLERY_DEPTH - 0.01 - STAIR_WIDTH * 0.5
	for i in STAIR_STEPS:
		out.append({"c": Vector2(start + STAIR_TREAD * (i + 0.5), z), "h": Vector2(STAIR_TREAD, STAIR_WIDTH) * 0.5,
				"a": 0.0, "top": DECK_TOP * (i + 1) / STAIR_STEPS})
	return out


## Where the gallery's rail stops, so the stair can land: the last LANDING of its length.
func _landing_x() -> float:
	return live_room_half() - LANDING


func _ready() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 0.2, back - FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (back + FRONT) * 0.5
	# Power-floated concrete, worn, a little polished: it takes a soft reflection of every pendant.
	var concrete := Materials.scanned(StandardMaterial3D.new(), "concrete_floor_worn_001", "2k", 2.4,
			Color(0.55, 0.55, 0.56))
	floor_mesh.material_override = concrete
	add_child(floor_mesh)

	var brick := Materials.cached_scanned("loft_brick", "red_brick_03", "2k", 1.6, Color(0.55, 0.42, 0.38))
	var steel := _steel()
	_build_walls(brick, steel)
	_build_roof(steel)
	_raise_columns()
	_build_gallery(steel)
	_hang_pendants()
	_raise_city()
	_dress_zones()
	if variant == SUNDAY:
		_let_the_sun_in()
		_put_out_the_plants()
		_make_a_corner()
	elif variant == STORM:
		_rng.seed = 61
		_let_it_rain()
		_lay_puddles()
		_catch_the_leak()
	set_process(variant == STORM)


func _steel() -> StandardMaterial3D:
	var steel := StandardMaterial3D.new()
	# Black-painted mild steel, the paint worn thin at the edges nobody can see from here.
	steel.albedo_color = Color(0.045, 0.047, 0.05)
	steel.metallic = 0.55
	steel.roughness = 0.5
	return steel


# --- the shell ------------------------------------------------------------------------------

## Four brick walls, the front and left full of windows. Each wall with windows is built as a
## band under the sills, a band over the heads, and piers between the bays -- the bands a hair
## thicker than the piers so no two pieces share a face.
func _build_walls(brick: Material, steel: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var outside := half + WALL * 0.5
	# Front: in front of the desk, the windows you look out of from the seat.
	# Its right-hand end a few millimetres short of the right wall's outside face, not in it.
	_wall_with_bays("Front", Vector3(0, 0, FRONT - WALL * 0.5), Vector3.RIGHT, -outside - WALL * 0.5,
			outside + WALL * 0.5 - 0.003, _spread(FRONT_BAYS), brick, steel)
	# Left: two more bays beside the desk, on the city side.
	# Starting a few millimetres past the front wall's inside face, so the two walls' bands
	# never overlap and share a top.
	_wall_with_bays("Left", Vector3(-outside, 0, 0), Vector3.BACK, FRONT + 0.003, back, LEFT_BAYS,
			brick, steel)
	# Right and back: plain brick. A hair shorter top and bottom than the walls they run into.
	ZoneKit.block(self, Vector3(WALL, HEIGHT - 0.004, back - FRONT), Vector3(outside, HEIGHT * 0.5,
			(back + FRONT) * 0.5), brick, "RightWall")
	ZoneKit.block(self, Vector3(outside * 2.0 - WALL - 0.002, HEIGHT - 0.008, WALL),
			Vector3(0, HEIGHT * 0.5, back + WALL * 0.5), brick, "BackWall")


## The bay centres along the front wall, spread with the room the way the zones are.
func _spread(bays: Array) -> Array:
	return bays.map(func(x: float) -> float: return x + signf(x) * _grow())


## Each windowed wall's openings (their centres), by the wall's label: where the sun comes in and
## the plants stand.
var window_openings := {}


## A brick wall with factory windows in its bays (ShellKit).
func _wall_with_bays(label: String, at: Vector3, along: Vector3, from: float, to: float, bays: Array,
		brick: Material, steel: Material) -> void:
	var openings := ShellKit.wall_with_bays(self, label, at, along, from, to, bays, BAY, SILL, HEAD,
			HEIGHT, WALL, brick)
	window_openings[label] = openings
	for i in openings.size():
		# A factory window: black steel glazing bars every 0.45 m, five uprights to a bay.
		ShellKit.glazed(self, label + "Window%d" % i, openings[i], along, Vector2(BAY, HEAD - SILL),
				steel, _window_glass())


## The windows' glass: as _glass, except in the storm, when rain streams down every pane -- one
## material, so the lightning lights them all at once.
func _window_glass() -> Material:
	if variant != STORM:
		return _glass()
	if _rain_glass == null:
		_rain_glass = ShaderMaterial.new()
		_rain_glass.shader = preload("res://core/venues/shaders/loft_rain_glass.gdshader")
	return _rain_glass


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Old glass, a little green and a little dirty: it holds a faint reflection of the room.
	glass.albedo_color = Color(0.5, 0.58, 0.56, 0.1)
	glass.roughness = 0.08
	glass.metallic_specular = 0.7
	return glass


## The roof: a dark timber deck on steel beams across the room.
func _build_roof(steel: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var deck := ZoneKit.block(self, Vector3(half * 2.0 + 0.1, 0.12, back - FRONT + 0.1),
			Vector3(0, HEIGHT + 0.061, (back + FRONT) * 0.5),
			Materials.cached_scanned("loft_deck", "black_walnut_veneer_01", "2k", 1.2, Color(0.2, 0.16, 0.13)),
			"RoofDeck")
	# By night nothing comes down through the deck to need stopping; a low sun through the
	# windows would carry on up the walls through a roof that cast nothing.
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if variant == SUNDAY \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beams := MultiMesh.new()
	beams.transform_format = MultiMesh.TRANSFORM_3D
	var beam := BoxMesh.new()
	# Its ends buried in the side walls.
	beam.size = Vector3(half * 2.0 + WALL - 0.02, 0.36, 0.16)
	beams.mesh = beam
	var count := ceili((back - FRONT) / BEAM_SPACING)
	beams.instance_count = count
	for i in count:
		var z := FRONT + BEAM_SPACING * (i + 0.5)
		beams.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.181, z)))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Beams"
	holder.multimesh = beams
	holder.material_override = steel
	add_child(holder)


func _raise_columns() -> void:
	var iron := StandardMaterial3D.new()
	# Cast iron, painted a dark green a long time ago.
	iron.albedo_color = Color(0.07, 0.09, 0.075)
	iron.metallic = 0.4
	iron.roughness = 0.55
	var i := 0
	for c in _column_spots():
		var column := MeshInstance3D.new()
		column.name = "Column%d" % i
		var shaft := CylinderMesh.new()
		shaft.top_radius = COLUMN_RADIUS * 0.85
		shaft.bottom_radius = COLUMN_RADIUS
		# Up to the underside of a beam's line, not into the deck.
		shaft.height = HEIGHT - 0.362
		shaft.radial_segments = 20
		column.mesh = shaft
		column.position = Vector3(c.x, (HEIGHT - 0.362) * 0.5 + 0.001, c.y)
		column.material_override = iron
		add_child(column)
		# A square base plate, so it stands on the floor rather than in it.
		ZoneKit.block(self, Vector3(0.34, 0.03, 0.34), Vector3(c.x, 0.017, c.y), iron, "ColumnBase%d" % i)
		i += 1


## A steel gallery along the back wall: a deck on brackets, a rail, and a stair up to it at the
## right-hand end, between the keys and the wall. You can climb it, and stand over the lattice --
## which is made to be looked down on.
func _build_gallery(steel: Material) -> void:
	var half := live_room_half()
	var wall := LIVE_ROOM_BACK
	var front := wall - GALLERY_DEPTH
	var length := half * 2.0 - 0.004
	ZoneKit.block(self, Vector3(length, 0.06, GALLERY_DEPTH - 0.002),
			Vector3(0, GALLERY_Y + 0.03, wall - GALLERY_DEPTH * 0.5 - 0.001),
			Materials.cached_scanned("loft_deck", "black_walnut_veneer_01", "2k", 1.2, Color(0.2, 0.16, 0.13)),
			"GalleryDeck")
	# The edge beam under the deck's front, which is what the deck reads as from below.
	ZoneKit.block(self, Vector3(length - 0.002, 0.24, 0.1), Vector3(0, GALLERY_Y - 0.121, front + 0.05),
			steel, "GalleryBeam")
	# Brackets back to the wall every couple of metres.
	var brackets := int(length / 2.0) + 1
	for i in brackets:
		var x := lerpf(-half + 0.3, half - 0.3, float(i) / (brackets - 1))
		var brace := ZoneKit.block(self, Vector3(0.06, 0.06, GALLERY_DEPTH * 1.25),
				Vector3(x, GALLERY_Y - 0.5, wall - GALLERY_DEPTH * 0.48), steel, "GalleryBrace%d" % i)
		brace.rotation.x = -0.72
	# The rail: posts, a top rail and a mid rail, stopping where the stair lands.
	var gap := _landing_x()
	var railed := gap + half
	var posts := int(railed / 1.2) + 1
	for i in posts:
		var x := lerpf(-half + 0.05, gap, float(i) / (posts - 1))
		ZoneKit.block(self, Vector3(0.04, 1.0, 0.04), Vector3(x, GALLERY_Y + 0.56, front + 0.03), steel,
				"GalleryPost%d" % i)
	for y in [GALLERY_Y + 1.07, GALLERY_Y + 0.58]:
		ZoneKit.block(self, Vector3(railed - 0.06, 0.035, 0.03), Vector3((gap - half) * 0.5 + 0.02, y, front + 0.03),
				steel, "GalleryRail")
	# Lamps clamped under the deck's edge beam, grazing the brick behind: the back wall is what
	# you see from the desk, and grazed brick is what a loft looks like at night.
	# Not on a sunny morning: the sun is doing it.
	var grazers := 0 if variant == SUNDAY else 4
	for i in grazers:
		var x := lerpf(-half * 0.75, half * 0.75, float(i) / (grazers - 1))
		var lamp := ZoneKit.spot_down(self, Vector3(x, GALLERY_Y - 0.046, wall - 0.35),
				Color(1.0, 0.66, 0.4), 5.5, 38.0, 4.8, steel)
		lamp.rotation_degrees.x = -78.0
	_string_festoon(front + 0.03, GALLERY_Y + 1.07, length)
	_build_stair(steel)


## The stair: a steel plate at each step's height (stair_steps), two stringers along its sides,
## and a handrail on the open side, the room's.
func _build_stair(steel: Material) -> void:
	var steps := stair_steps()
	var first: Dictionary = steps[0]
	var last: Dictionary = steps[-1]
	var z: float = first["c"].y
	for i in steps.size():
		var step: Dictionary = steps[i]
		ZoneKit.block(self, Vector3(STAIR_TREAD - 0.004, 0.03, STAIR_WIDTH - 0.08),
				Vector3(step["c"].x, step["top"] - 0.015, z), steel, "StairTread%d" % i)
	var foot := Vector3(first["c"].x - STAIR_TREAD * 0.5, 0, z)
	var top := Vector3(last["c"].x + STAIR_TREAD * 0.5, DECK_TOP, z)
	var rise := top - foot
	for side in [-1.0, 1.0]:
		var stringer := ZoneKit.block(self, Vector3(rise.length(), 0.2, 0.03),
				(foot + top) * 0.5 + Vector3(0, -0.12, side * (STAIR_WIDTH * 0.5 - 0.022)), steel, "StairStringer")
		stringer.rotation.z = atan2(rise.y, rise.x)
	# The handrail, a metre over the nosings, on two posts.
	var rail_z := z - STAIR_WIDTH * 0.5 + 0.02
	for end in [foot + Vector3(STAIR_TREAD * 0.5, first["top"], 0), top - Vector3(STAIR_TREAD * 0.5, 0, 0)]:
		ZoneKit.block(self, Vector3(0.04, 1.0, 0.04), Vector3(end.x, end.y + 0.5, rail_z), steel, "StairPost")
	var handrail := ZoneKit.block(self, Vector3(rise.length() - STAIR_TREAD, 0.035, 0.035),
			(foot + top) * 0.5 + Vector3(0, 0.98, rail_z - z), steel, "StairRail")
	handrail.rotation.z = atan2(rise.y, rise.x)


## A festoon of bare bulbs hung along the gallery's top rail, each a little drop on its wire:
## lit by nothing but themselves, and enough to say where the gallery is from anywhere in the
## room. One MultiMesh.
func _string_festoon(z: float, rail_y: float, length: float) -> void:
	var spacing := 0.55
	var count := int(length / spacing)
	var bulbs := MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	var bulb := SphereMesh.new()
	bulb.radius = 0.028
	bulb.height = 0.06
	bulb.radial_segments = 10
	bulb.rings = 5
	bulbs.mesh = bulb
	bulbs.instance_count = count
	for i in count:
		var x := -length * 0.5 + spacing * (i + 0.5)
		# Every bulb hangs a little lower in the middle of a span, the way wire sags.
		var sag := 0.1 + 0.05 * sin(PI * fposmod(x / 1.2, 1.0))
		bulbs.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, rail_y - sag, z + 0.03)))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Festoon"
	holder.multimesh = bulbs
	holder.material_override = _dark_bulb() if variant == SUNDAY else ZoneKit.glow(Color(1.0, 0.7, 0.38), 1.5)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


## A bulb switched off in daylight: clear glass with the filament dark behind it.
func _dark_bulb() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.42)
	m.roughness = 0.15
	m.metallic_specular = 0.8
	return m


## Enamel factory shades on long cords from the beams, low over the walkway between the desk and
## the zones: the room's light comes from these, not from the roof.
func _hang_pendants() -> void:
	var enamel := StandardMaterial3D.new()
	enamel.albedo_color = Color(0.09, 0.16, 0.13)
	enamel.roughness = 0.3
	enamel.metallic_specular = 0.7
	var half := live_room_half()
	var spots := [Vector3(-half * 0.68, 3.0, 3.25), Vector3(-half * 0.24, 3.0, 3.25),
			Vector3(half * 0.24, 3.0, 3.25), Vector3(half * 0.68, 3.0, 3.25),
			# And one either side of the desk, over the floor beside it.
			Vector3(-half * 0.72, 3.1, 0.9), Vector3(half * 0.72, 3.1, 0.9)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var drop := HEIGHT - 0.36 - at.y
		# In the storm each hangs from a pivot at the top of its cord, and swings (_process); else
		# it is built straight into the room.
		var parent: Node3D = self
		var origin := Vector3.ZERO
		if variant == STORM:
			parent = Node3D.new()
			parent.name = "Swing%d" % i
			origin = at + Vector3(0, drop + 0.11, 0)
			parent.position = origin
			# A cord's own period, near enough a pendulum's, and a phase of its own.
			parent.set_meta(&"period", TAU * sqrt((drop + 0.11) / 9.8) * 1.6)
			parent.set_meta(&"phase", i * 1.9)
			add_child(parent)
			swingers.append(parent)
		var cord := ZoneKit.block(parent, Vector3(0.008, drop, 0.008), at + Vector3(0, drop * 0.5 + 0.11, 0) - origin,
				steel_cord(), "PendantCord%d" % i)
		cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shade := MeshInstance3D.new()
		shade.name = "Shade%d" % i
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 0.26
		cone.height = 0.2
		cone.radial_segments = 24
		shade.mesh = cone
		shade.position = at - origin
		shade.material_override = enamel
		parent.add_child(shade)
		# Off on a sunny morning: the bulb only glass.
		var lit := variant != SUNDAY
		var bulb := ZoneKit.block(parent, Vector3(0.08, 0.04, 0.08), at + Vector3(0, -0.075, 0) - origin,
				ZoneKit.glow(Color(1.0, 0.72, 0.42), 2.4) if lit else _dark_bulb(), "Bulb%d" % i)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if lit:
			var light := ZoneKit.spot_down(parent, at + Vector3(0, -0.11, 0) - origin, Color(1.0, 0.74, 0.5), 4.0,
					66.0, 5.2)
			if variant == STORM:
				# Turned up against the dark, a wider pool on the concrete, and enough of a highlight
				# to show in the wet under the windows. A soft glow round each too, for the brick and
				# the rain on the glass near it; both swing with the shade.
				light.light_energy = 6.0
				light.spot_range = 6.5
				light.spot_angle = 72.0
				light.light_specular = 0.35
				var spill := OmniLight3D.new()
				spill.name = "Spill%d" % i
				spill.position = at + Vector3(0, -0.2, 0) - origin
				spill.light_color = Color(1.0, 0.68, 0.4)
				spill.light_energy = 0.9
				spill.omni_range = 5.5
				spill.omni_attenuation = 1.4
				spill.shadow_enabled = false
				spill.light_specular = 0.5
				parent.add_child(spill)


func steel_cord() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.roughness = 0.7
	return m


## The city past the glass, in front and to the left: dark blocks with their windows lit warm,
## a few cold, near enough at the front to read as the next street. One MultiMesh, one draw.
func _raise_city() -> void:
	_city_mat = ShaderMaterial.new()
	if variant == SUNDAY:
		# By day: stone, brick and glass in the sun, lit as anything is.
		_city_mat.shader = preload("res://core/venues/shaders/loft_day_tower.gdshader")
	else:
		_city_mat.shader = preload("res://core/venues/shaders/tower.gdshader")
		_city_mat.set_shader_parameter("roof_from_custom", true)
		_city_mat.set_shader_parameter("body", Color(0.012, 0.013, 0.02))
		_city_mat.set_shader_parameter("lit_a", Color(1.0, 0.72, 0.4))
		_city_mat.set_shader_parameter("lit_b", Color(0.08, 0.09, 0.12))
		_city_mat.set_shader_parameter("lit_c", Color(0.75, 0.85, 1.0))
		# In the storm the rain dims every window, and the roofline lights are lost in it.
		_city_mat.set_shader_parameter("energy", 0.75 if variant == STORM else 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var towers: Array[Transform3D] = []
	var roofs: Array[float] = []
	var cell := 10.0
	var keep_clear := Rect2(-live_room_half() - 12.0, FRONT - 12.0, live_room_half() * 2.0 + 24.0,
			LIVE_ROOM_BACK - FRONT + 30.0)
	for gx in range(-14, 15):
		for gz in range(-14, 6):
			var at := Vector2(gx * cell, gz * cell)
			if keep_clear.grow(cell * 0.5).has_point(at) or rng.randf() < 0.2:
				continue
			var w := rng.randf_range(5.0, 8.5)
			var d := rng.randf_range(5.0, 8.5)
			var h := rng.randf_range(12.0, 55.0)
			var centre := Vector3(at.x + rng.randf_range(-0.6, 0.6), h * 0.5 - 6.0,
					at.y + rng.randf_range(-0.6, 0.6))
			# The room is a third-floor loft: the street is six metres down.
			towers.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), centre))
			roofs.append(h - 6.0)
	var city := MultiMesh.new()
	city.transform_format = MultiMesh.TRANSFORM_3D
	city.use_custom_data = true
	city.mesh = BoxMesh.new()
	city.instance_count = towers.size()
	for i in towers.size():
		city.set_instance_transform(i, towers[i])
		city.set_instance_custom_data(i, Color(roofs[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "City"
	mmi.multimesh = city
	mmi.material_override = _city_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Where a fitting clamped under a roof beam hangs.
func _under_beam() -> float:
	return HEIGHT - 0.362 - 0.03


## The roof beam nearest over a zone's middle.
func _beam_z(box: AABB) -> float:
	var i := roundi((box.get_center().z - FRONT) / BEAM_SPACING - 0.5)
	return FRONT + BEAM_SPACING * (i + 0.5)


# --- Sunday morning -------------------------------------------------------------------------

## The sun in at the left-hand windows, made visible by the dust in the air: each window's
## opening swept along the sun's line into the room as sheets of light (loft_sunbeam.gdshader),
## standing ones between the uprights and lying ones between the crossbars, so the shaft comes in
## striped by the glazing just as the floor under it is. One MultiMesh. And motes turning in it
## (loft_mote.gdshader), which only show while they are in the sun.
func _let_the_sun_in() -> void:
	var d := SUN_TRAVEL.normalized()
	# Far enough that a sheet from the window's head has reached the floor.
	var reach := HEAD / -d.y + 0.4
	var tall := HEAD - SILL
	var along := d * reach
	var xforms: Array[Transform3D] = []
	var custom: Array[Color] = []
	var panes := 4
	var rows := 8
	for centre: Vector3 in window_openings["Left"]:
		# Standing sheets, three to a pane across, each the window's full height.
		for p in panes:
			for k in 3:
				var u := (p + (k + 1) / 4.0) / panes
				var at := centre + Vector3.BACK * ((u - 0.5) * BAY)
				var normal := along.cross(Vector3.UP).normalized()
				xforms.append(Transform3D(Basis(along, Vector3.UP * tall, normal), at + along * 0.5))
				custom.append(Color(0.0, randf_from(xforms.size()), 0, 0))
		# Lying sheets, two to a row of panes, each the window's full width.
		for r in rows:
			for k in 2:
				var v := (r + (k + 1) / 3.0) / rows
				var at := centre + Vector3.UP * ((v - 0.5) * tall)
				var normal := along.cross(Vector3.BACK).normalized()
				xforms.append(Transform3D(Basis(along, Vector3.BACK * BAY, normal), at + along * 0.5))
				custom.append(Color(1.0, randf_from(xforms.size()), 0, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, custom[i])
	var beam := ShaderMaterial.new()
	beam.shader = preload("res://core/venues/shaders/loft_sunbeam.gdshader")
	# With the full renderer the air's own volumetric fog shows the shafts too; the sheets are then
	# only the bars' stripes in it.
	beam.set_shader_parameter("strength", 0.0016 if rich else 0.0035)
	beam.set_shader_parameter("uprights", 5.0)
	beam.set_shader_parameter("rows", float(rows))
	beam.set_shader_parameter("bar", Vector2(0.05 / BAY, 0.05 / tall))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Sunbeams"
	holder.multimesh = mm
	holder.material_override = beam
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)

	# The dust, drifting all over the left of the room, lit only in the shafts.
	var half := live_room_half()
	var mote := ShaderMaterial.new()
	mote.shader = preload("res://core/venues/shaders/loft_mote.gdshader")
	var openings: Array = window_openings["Left"]
	mote.set_shader_parameter("travel", d)
	mote.set_shader_parameter("wall_x", -half - WALL * 0.5)
	mote.set_shader_parameter("opening_a", Vector2(openings[0].z, openings[0].y))
	mote.set_shader_parameter("opening_b", Vector2(openings[1].z, openings[1].y))
	mote.set_shader_parameter("half_size", Vector2(BAY, tall) * 0.5)
	mote.set_shader_parameter("rows", float(rows))
	var speck := QuadMesh.new()
	speck.size = Vector2(0.012, 0.012)
	speck.material = mote
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	var box := Vector3(half * 0.5, 2.3, 3.2)
	dust.position = Vector3(-half * 0.5, 2.4, -0.2)
	dust.amount = 1400
	dust.lifetime = 30.0
	dust.preprocess = 30.0
	dust.draw_pass_1 = speck
	dust.visibility_aabb = AABB(-box - Vector3.ONE, box * 2.0 + Vector3.ONE * 2.0)
	var air := ParticleProcessMaterial.new()
	air.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	air.emission_box_extents = box
	air.direction = Vector3(0.3, 0.2, -0.1)
	air.spread = 180.0
	air.initial_velocity_min = 0.005
	air.initial_velocity_max = 0.03
	air.gravity = Vector3(0, -0.002, 0)
	air.turbulence_enabled = true
	air.turbulence_noise_strength = 0.05
	air.turbulence_noise_speed_random = 0.2
	air.turbulence_influence_min = 0.02
	air.turbulence_influence_max = 0.06
	dust.process_material = air
	add_child(dust)


## A number in 0..1 from an index, for a sheet's seed: the same every run.
func randf_from(i: int) -> float:
	return fposmod(sin(i * 12.9898) * 43758.5453, 1.0)


## A board on each window's sill, inside the room, and house plants on them in the sun
## (assets/models/loft_plants.glb): the cheese plant, the snake plant and the fern, in turn, and a
## big cheese plant on the floor in the front corner.
func _put_out_the_plants() -> void:
	var half := live_room_half()
	var oak := Materials.cached_scanned("loft_bench", "black_walnut_veneer_01", "2k", 0.8, Color(0.72, 0.58, 0.44))
	var looks := _plant_looks()
	var kinds := ["plant_monstera", "plant_snake", "plant_fern"]
	var n := 0
	for wall in ["Front", "Left"]:
		var openings: Array = window_openings[wall]
		for i in openings.size():
			var c: Vector3 = openings[i]
			# Into the room from the wall's inside face, and along the bay.
			var inward := Vector3.BACK if wall == "Front" else Vector3.RIGHT
			var along := Vector3.RIGHT if wall == "Front" else Vector3.BACK
			var face := FRONT if wall == "Front" else -half
			var on_face := c * along + inward * face
			var board := ZoneKit.block(self, along * (BAY - 0.006) + inward * 0.24 + Vector3(0, 0.04, 0),
					on_face + inward * 0.04 + Vector3(0, SILL + 0.021, 0), oak, wall + "PlantSill%d" % i)
			board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			# One or two to a sill, never the same two side by side.
			var count := 2 if (i + n) % 2 == 0 else 1
			for k in count:
				var kind: String = kinds[(n + k) % kinds.size()]
				var x := (k - (count - 1) * 0.5) * 0.55 + (0.12 if count == 1 else 0.0)
				var spot := on_face + inward * 0.06 + along * x + Vector3(0, SILL + 0.041, 0)
				_plant(kind, spot, n * 1.3 + k, 1.0, looks)
			n += 1
	# The big one, on the floor in the front corner by the left windows.
	var corner := _big_plant_spot()
	_plant("plant_monstera", Vector3(corner.x, 0, corner.y), 0.6, 2.4, looks)


## The plants' materials by their names in the model.
func _plant_looks() -> Dictionary:
	var pot := StandardMaterial3D.new()
	pot.albedo_color = Color(0.6, 0.31, 0.19)
	pot.roughness = 0.9
	var glaze := StandardMaterial3D.new()
	glaze.albedo_color = Color(0.11, 0.2, 0.23)
	glaze.roughness = 0.22
	glaze.metallic_specular = 0.7
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.07, 0.05, 0.035)
	soil.roughness = 1.0
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.05, 0.19, 0.06)
	leaf.roughness = 0.5
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The sun shows through a leaf held up to it.
	leaf.backlight_enabled = true
	leaf.backlight = Color(0.25, 0.4, 0.08)
	var pale := leaf.duplicate() as StandardMaterial3D
	pale.albedo_color = Color(0.2, 0.38, 0.1)
	return {"pot": pot, "glaze": glaze, "soil": soil, "leaf": leaf, "leaf_pale": pale}


func _plant(kind: String, at: Vector3, yaw: float, size: float, looks: Dictionary) -> MeshInstance3D:
	var plant := _part("loft_plants.glb", kind, looks)
	plant.name = kind.capitalize().replace(" ", "")
	plant.position = at
	plant.rotation.y = yaw
	plant.scale = Vector3.ONE * size
	add_child(plant)
	return plant


## Where the big plant stands, in studio space, for the walker.
func _big_plant_spot() -> Vector2:
	return Vector2(-live_room_half() + 0.55, FRONT + 0.55)


## The corner by the left windows, where Sunday is spent: a rug, a leather sofa facing the glass,
## a low table, and the coffee on it (assets/models/loft_sofa.glb, loft_coffee.glb), the sun
## coming across all of it.
func _make_a_corner() -> void:
	var sofa_at := _beside(SOFA_AT)
	var table_at := _beside(TABLE_AT)
	# A flat-woven rug: a madder-red border round an oatmeal field.
	var mid := Vector2((sofa_at.x + table_at.x) * 0.5 - 0.2, SOFA_AT.y + 0.05)
	var border := Materials.cached_scanned("loft_rug_border", "wool_boucle", "1k", 0.35, Color(0.5, 0.17, 0.12))
	var field := Materials.cached_scanned("loft_rug_field", "wool_boucle", "1k", 0.35, Color(0.72, 0.64, 0.52))
	var rug := ZoneKit.block(self, Vector3(2.3, 0.01, 2.1), Vector3(mid.x, 0.005, mid.y), border, "Rug")
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := ZoneKit.block(self, Vector3(1.9, 0.01, 1.7), Vector3(mid.x, 0.007, mid.y), field, "RugField")
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.36, 0.17, 0.08)
	leather.roughness = 0.5
	leather.normal_enabled = true
	leather.normal_texture = Materials.grain("loft_leather", 0.9, 0.35)
	leather.normal_scale = 0.4
	var walnut := Materials.cached_scanned("loft_bench", "black_walnut_veneer_01", "2k", 0.8, Color(0.72, 0.58, 0.44))
	var looks := {"leather": leather, "walnut": walnut, "steel": _steel()}
	# Facing the windows: its front (+Z in the model) turned to -X.
	var sofa := _part("loft_sofa.glb", "sofa", looks)
	sofa.name = "Sofa"
	sofa.position = Vector3(sofa_at.x, 0.01, sofa_at.y)
	sofa.rotation.y = -PI * 0.5
	add_child(sofa)
	var table := _part("loft_sofa.glb", "table", looks)
	table.name = "LowTable"
	table.position = Vector3(table_at.x, 0.01, table_at.y)
	table.rotation.y = PI * 0.5
	add_child(table)
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color(0.88, 0.85, 0.78)
	cream.roughness = 0.2
	cream.metallic_specular = 0.6
	var blue := cream.duplicate() as StandardMaterial3D
	blue.albedo_color = Color(0.2, 0.32, 0.48)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.7, 0.75, 0.75, 0.18)
	glass.roughness = 0.05
	glass.metallic_specular = 0.8
	var coffee := StandardMaterial3D.new()
	coffee.albedo_color = Color(0.09, 0.045, 0.02)
	coffee.roughness = 0.15
	var pastry := StandardMaterial3D.new()
	pastry.albedo_color = Color(0.72, 0.45, 0.18)
	pastry.roughness = 0.55
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.75, 0.75, 0.76)
	chrome.metallic = 0.9
	chrome.roughness = 0.2
	var tray := _part("loft_coffee.glb", "coffee_set", {"tray": walnut, "glass": glass, "steel": chrome,
			"coffee": coffee, "cream": cream, "blue": blue, "pastry": pastry})
	tray.name = "Coffee"
	tray.position = Vector3(table_at.x + 0.02, 0.01 + TABLE_TOP, table_at.y - 0.18)
	tray.rotation.y = PI * 0.5 + 0.12
	add_child(tray)
	# The paper, folded, at the other end.
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.78, 0.76, 0.7)
	paper.roughness = 0.9
	var news := ZoneKit.block(self, Vector3(0.3, 0.012, 0.42), Vector3(table_at.x - 0.03, 0.01 + TABLE_TOP + 0.007,
			table_at.y + 0.26), paper, "Newspaper")
	news.rotation.y = -0.2


# --- the storm ------------------------------------------------------------------------------

## Rain falling past the windows, in front and on the left: streaks in boxes outside the glass,
## blowing a little away from the building so nothing comes in.
func _let_it_rain() -> void:
	var half := live_room_half()
	var streak := StandardMaterial3D.new()
	streak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.albedo_color = Color(0.62, 0.68, 0.8, 0.3)
	streak.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.billboard_keep_scale = true
	var quad := QuadMesh.new()
	# Wider than a drop, as a drop's streak is in a camera's eye: thinner would fall between pixels.
	quad.size = Vector2(0.022, 0.6)
	quad.material = streak
	for side in [["RainFront", Vector3(0, 0.5, FRONT - WALL - 2.6), Vector3(half + 4.0, 7.5, 2.2)],
			["RainLeft", Vector3(-half - WALL - 2.6, 0.5, 1.5), Vector3(2.2, 7.5, 6.0)]]:
		var fall := GPUParticles3D.new()
		fall.name = side[0]
		fall.position = side[1]
		fall.amount = 2600
		fall.lifetime = 1.8
		fall.preprocess = 2.0
		fall.draw_pass_1 = quad
		fall.visibility_aabb = AABB(-side[2] - Vector3(1, 10, 1), side[2] * 2.0 + Vector3(2, 20, 2))
		var drive := ParticleProcessMaterial.new()
		drive.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		drive.emission_box_extents = side[2]
		# Away from both windowed walls: the wind is off the building.
		drive.direction = Vector3(-0.1, -1.0, -0.12)
		drive.spread = 2.0
		drive.initial_velocity_min = 8.0
		drive.initial_velocity_max = 10.0
		drive.gravity = Vector3(0, -3.0, 0)
		fall.process_material = drive
		add_child(fall)
		_rain.append(fall)


## Rainwater on the floor under the windows, where the old frames let it in
## (loft_puddle.gdshader), and a probe so the water has the room to mirror.
func _lay_puddles() -> void:
	var half := live_room_half()
	var spots: Array = []
	for c: Vector3 in window_openings["Left"]:
		spots.append([Vector2(-half + 0.6, c.z + 0.15), Vector2(1.3, 0.9)])
	spots.append([Vector2(-half + 1.3, FRONT + 0.55), Vector2(1.5, 0.8)])
	spots.append([Vector2(half - 1.3, FRONT + 0.5), Vector2(1.2, 0.75)])
	for i in spots.size():
		var spot: Dictionary = {"at": spots[i][0], "size": spots[i][1]}
		var water := ShaderMaterial.new()
		water.shader = preload("res://core/venues/shaders/loft_puddle.gdshader")
		water.set_shader_parameter("seed", float(i) * 1.37)
		_puddles.append(water)
		var pool := MeshInstance3D.new()
		pool.name = "Puddle%d" % i
		var quad := QuadMesh.new()
		quad.size = spot["size"]
		pool.mesh = quad
		pool.material_override = water
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Each a hair higher than the last, so where two meet they are not in one plane.
		pool.position = Vector3(spot["at"].x, 0.002 + i * 0.0004, spot["at"].y)
		pool.rotation = Vector3(-PI * 0.5, 0, _rng.randf_range(-0.4, 0.4))
		add_child(pool)
	var probe := ReflectionProbe.new()
	probe.name = "Reflections"
	probe.position = Vector3(0, HEIGHT * 0.5, (LIVE_ROOM_BACK + FRONT) * 0.5)
	probe.size = Vector3(half * 2.0, HEIGHT, LIVE_ROOM_BACK - FRONT)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 1.0
	add_child(probe)


## The leak: a drip from the roof deck beside the desk, and a bucket under it
## (assets/models/loft_bucket.glb) with water in it and a wet ring round it.
func _catch_the_leak() -> void:
	var at := _beside(LEAK_AT)
	var zinc := StandardMaterial3D.new()
	zinc.albedo_color = Color(0.56, 0.58, 0.6)
	zinc.metallic = 0.8
	zinc.roughness = 0.42
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.03, 0.035, 0.04)
	water.roughness = 0.03
	water.metallic_specular = 0.9
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.32, 0.2, 0.11)
	grip.roughness = 0.6
	var bucket := _part("loft_bucket.glb", "bucket", {"zinc": zinc, "water": water, "grip": grip})
	bucket.name = "Bucket"
	bucket.position = Vector3(at.x, 0.0, at.y)
	bucket.rotation.y = 0.7
	add_child(bucket)
	var wet := ShaderMaterial.new()
	wet.shader = preload("res://core/venues/shaders/loft_puddle.gdshader")
	wet.set_shader_parameter("seed", 9.1)
	wet.set_shader_parameter("drips", 0.0)
	_puddles.append(wet)
	var ring := MeshInstance3D.new()
	ring.name = "Splash"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.7)
	ring.mesh = quad
	ring.material_override = wet
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(at.x, 0.0025, at.y)
	ring.rotation.x = -PI * 0.5
	add_child(ring)
	# The drip: a drop every half second or so from the deck, falling into the bucket.
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.7, 0.75, 0.8, 0.6)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.roughness = 0.05
	drop_mat.metallic_specular = 1.0
	var bead := SphereMesh.new()
	bead.radius = 0.007
	bead.height = 0.03
	bead.radial_segments = 6
	bead.rings = 3
	bead.material = drop_mat
	var drip := GPUParticles3D.new()
	drip.name = "Drip"
	drip.position = Vector3(at.x, HEIGHT - 0.01, at.y)
	drip.amount = 2
	drip.lifetime = sqrt(2.0 * (HEIGHT - 0.1) / 9.8)
	drip.draw_pass_1 = bead
	drip.visibility_aabb = AABB(Vector3(-0.3, -HEIGHT, -0.3), Vector3(0.6, HEIGHT + 0.2, 0.6))
	var fall := ParticleProcessMaterial.new()
	fall.direction = Vector3(0, -1, 0)
	fall.spread = 0.0
	fall.initial_velocity_min = 0.0
	fall.initial_velocity_max = 0.0
	fall.gravity = Vector3(0, -9.8, 0)
	drip.process_material = fall
	add_child(drip)
	# Where it comes through: a dark stain on the deck's boards.
	var stain := StandardMaterial3D.new()
	stain.albedo_color = Color(0.05, 0.04, 0.035)
	stain.roughness = 0.3
	var mark := ZoneKit.block(self, Vector3(0.5, 0.004, 0.35), Vector3(at.x, HEIGHT - 0.003, at.y), stain, "LeakStain")
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One object's mesh out of a model in assets/models, as a fresh MeshInstance3D, its materials
## swapped by name.
func _part(file: String, object: String, swap: Dictionary) -> MeshInstance3D:
	var source := (load(MODELS + file) as PackedScene).instantiate()
	var found := source.find_child(object, true, false)
	var mesh: Mesh = null
	if found is MeshInstance3D:
		mesh = (found as MeshInstance3D).mesh
	else:
		for m: MeshInstance3D in found.find_children("*", "MeshInstance3D", true, false):
			mesh = m.mesh
			break
	source.free()
	var out := MeshInstance3D.new()
	out.mesh = mesh
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swap.has(m.resource_name):
			out.set_surface_override_material(s, swap[m.resource_name])
	return out


# --- the zones ------------------------------------------------------------------------------

## The zones in the loft's own materials: a riser of black-stained ply with a rubber top, a booth
## framed in black steel, the lattice's square painted on the concrete in safety yellow, a
## butcher-block workbench on steel legs, and the keys under a module case.
func _dress_zones() -> void:
	var z := zones()
	var steel := _steel()
	var ply := StandardMaterial3D.new()
	# Raw birch ply, sealed and scuffed: what a riser in a warehouse is knocked up from.
	ply.albedo_color = Color(0.42, 0.33, 0.22)
	ply.roughness = 0.72
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.035, 0.035, 0.038)
	rubber.roughness = 0.95
	var block_wood := Materials.cached_scanned("loft_bench", "black_walnut_veneer_01", "2k", 0.8,
			Color(0.72, 0.58, 0.44))

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, rubber, ply)
	# Clamped under the roof beam that crosses the kit's front edge.
	ZoneKit.spot_down(drums, Vector3(0, _under_beam(), _beam_z(drum_box) - drum_box.get_center().z),
			Color(1.0, 0.8, 0.6), 4.2, 40.0, 7.0, steel)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, steel, _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.68, 0.42),
			1.4, 60.0, 3.2, steel)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	# Safety yellow on the concrete, the way a loading bay is marked, and a cross at the middle.
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.66, 0.08)
	paint.roughness = 0.6
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.07, paint)
	ZoneKit.block(matrix, Vector3(0.5, 0.002, 0.06), Vector3(0, 0.002, 0), paint, "Cross")
	ZoneKit.block(matrix, Vector3(0.06, 0.002, 0.5), Vector3(0, 0.0025, 0), paint, "Cross")
	# Lit from the beam over it, cold, down onto the square.
	var lattice: AABB = z[&"matrix"]
	ZoneKit.spot_down(matrix, Vector3(0, _under_beam(), _beam_z(lattice) - lattice.get_center().z),
			Color(0.72, 0.82, 1.0), 7.0, 42.0, 7.0, steel)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, block_wood, steel)
	_dress_prop_shelf(block_wood, steel)
	ZoneKit.spot_down(bricks, Vector3(0, 2.6, 0), Color(1.0, 0.78, 0.55), 2.2, 50.0, 4.2, steel)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	var keys: AABB = z[&"synth"]
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, steel, block_wood)
	ZoneKit.block(synth, Vector3(0.1, 0.62, 1.5), Vector3(keys.size.x * 0.5 - 0.06, 1.6, 0), Materials.chassis(),
			"ModuleCase")
	ZoneKit.spot_down(synth, Vector3(-0.2, 3.0, 0), Color(1.0, 0.8, 0.62), 2.4, 44.0, 4.5, steel)


# --- the mirror -----------------------------------------------------------------------------

## The mirror stands where it does in every venue (Venue.mirror_spot), at the footprint's left
## edge -- open floor here, not a wall -- framed in the loft's black steel.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _steel())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Brick and iron: muted industrial colours, copper and patina, enamel paint gone dull.
func track_palette() -> Array:
	return [
		Color(0.69, 0.29, 0.24), Color(0.75, 0.47, 0.28), Color(0.78, 0.64, 0.31), Color(0.56, 0.60, 0.29),
		Color(0.35, 0.52, 0.35), Color(0.29, 0.54, 0.52), Color(0.35, 0.53, 0.66), Color(0.29, 0.37, 0.54),
		Color(0.43, 0.34, 0.52), Color(0.56, 0.35, 0.47), Color(0.72, 0.48, 0.53), Color(0.60, 0.61, 0.62),
	]
