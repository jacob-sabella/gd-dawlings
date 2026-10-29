class_name CabinVenue
extends Venue

## A log cabin in snowy woods, at night: one room under a steep pitched roof, pine boards on the
## walls and worn planks underfoot, a wood stove in the corner by the desk, and small-paned
## windows on firs and falling snow. Like the loft there is no control room -- the desk stands
## in the room and the floor round it is walkable to the walls -- and the zones fill the far end,
## the keys under the big window on the right where you can watch the snow while you play.
##
## Lit by fire and lanterns: the stove's glow on the floor, lanterns hung from the rafters and
## one on the table, the zones' own fittings, and the moon off the snow through the glass.
##
## Three arrangements (Venue.VARIANTS): Snowy night, as above; Summer dusk, the snow gone, the
## clearing green and long in the grass, birches among the firs, a lake glimpsed through a gap in
## the trees in front, the windows thrown open on a warm sky and fireflies, and the stove cold
## with a jug of wildflowers on it; and Northern lights, a clear, bitter night, the snow deep and
## drifted against the walls, the lake out front frozen, frost grown over the panes, the aurora
## rippling green and violet over the trees, the stove roaring, and a covered porch along the
## left-hand wall with the axe left in the chopping block.

## Floor to the top of the side walls, and to the underside of the ridge. Above every zone's head
## room (Venue.ZONES): the lattice's 3.4 m stands under the eaves, and the tie beams at the eaves
## clear the neighbourhoods' banners (Neighbourhoods.SIGN_HEIGHT) by most of a metre. Raised with
## the live room (Venue.LIVE_ROOM_HEIGHT) when the room was spread to 17.6 x 16.4 m: a roof that
## wide at the old pitch sat on your head at the walls.
const EAVES := 3.9
const RIDGE := 6.3
## Log walls, thick.
const WALL := 0.24
## Where the front wall stands, in front of the desk: the footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## Cabin windows: small panes, a deep sill, the head well under the eaves.
const SILL := 0.9
const HEAD := 2.4
const BAY := 1.3
## The front's bays (x) and the right wall's (z), spread down the bigger room: the first of the
## right's is the weather's, beside the desk; then one by the front corner and one over the bricks
## table; and the keys' own big one past them (KEYS_BAY).
const FRONT_BAYS := [-7.0, -4.3, -1.6, 1.6, 4.3, 7.0]
const RIGHT_BAYS := [0.3, -2.4, 6.05]
const KEYS_BAY := 2.2
## The left wall's bays: the porch window past the stove (the icicles' one), and one over the toys'
## shelf, whose top is under the sill.
const LEFT_BAYS := [1.4, 5.0]
## The stove, in the front-left corner beside the desk, door to the room: out in the floor beside
## the footprint, clear of the gear's ring round the seat.
const STOVE_AT := Vector2(-7.6, -2.8)
const STOVE_SIZE := Vector2(0.62, 0.6)
## The rafters, this far apart, and where the two tie beams cross the room: clear of the
## lattice's volume, one over the desk and one between the riser and the lattice.
const RAFTER_SPACING := 1.1
const TIES := [0.5, 7.95]
## Where the ground outside lies: the cabin stands on a sill of logs above the snow.
const GROUND := -0.55

const MODELS := "res://assets/models/"

## The arrangements (Venue.VARIANTS).
const SNOWY := 0
const SUMMER := 1
const AURORA := 2
## The lake in front of the cabin, past the clearing (summer water, winter ice): its middle and
## its radii across and along the view, on the ground.
const LAKE_AT := Vector2(0.0, -62.0)
const LAKE_RADII := Vector2(58.0, 30.0)
## The gap kept in the trees from the front windows to the lake: half its angle.
const VIEW_GAP := 0.5
## The covered porch along the left-hand wall, outside: how far it reaches out, where it runs
## from and to (z), its deck's top, and its roof at the wall and at its edge.
const PORCH_DEPTH := 2.3
const PORCH_FROM := -1.7
const PORCH_TO := 4.6
const PORCH_DECK := -0.04
const PORCH_ROOF := Vector2(3.3, 2.55)

var _stove_light: SpotLight3D
var _flicker := 0.0
## How hard the stove is going: 1 as built; the northern lights' night has it roaring.
var _fire := 1.0
## A second, softer glow off the roaring stove, round the corner it stands in.
var _stove_glow: OmniLight3D
## The aurora's sky, and the key light it breathes in step with.
var _sky_mat: ShaderMaterial
var _key: DirectionalLight3D
## The frost on the panes, one material for all of them.
var _frost: ShaderMaterial

## What follows the mix: the fire's glass and light, the candles and lanterns, and a blacklight
## on the rug's cream border, with embers rising off the stove and motes over the rug.
const UV_REST := 0.03
var _fire_mat: StandardMaterial3D
var _fire_base := Color.WHITE
var _flame_mat: StandardMaterial3D
var _flame_base := Color.WHITE
var _lantern_mat: StandardMaterial3D
var _lantern_base := Color.WHITE
var _uv_rug: StandardMaterial3D
var _uv_light: SpotLight3D
var _embers: GPUParticles3D
var _rug_motes: GPUParticles3D


func venue_id() -> StringName:
	return &"cabin"


## Rough timber carcasses, black iron fittings and pine cheeks: furniture a person built here
## out of what was cut on the hill, with the faceplates a warm near-black.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("wood_floor_deck", 1.4, Color(0.62, 0.46, 0.34))) \
			.with("chassis", GearStyle.paint(Color(0.1, 0.078, 0.062), 0.7, 0.15)) \
			.with("brushed", GearStyle.metal(Color(0.16, 0.15, 0.14), 0.6)) \
			.with("trim", GearStyle.metal(Color(0.12, 0.11, 0.1), 0.7)) \
			.with("end_cheek", GearStyle.scan("weathered_brown_planks", 0.6, Color(0.7, 0.55, 0.42))) \
			.with("lamp_shade", GearStyle.metal(Color(0.12, 0.11, 0.1), 0.7)) \
			.with("loom_band", GearStyle.paint(Color(0.55, 0.12, 0.08), 0.8, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.2, 0.12, 0.07), 0.55, 0.0))


## A plank board with the lettering painted on in cream and the arrows in lamp orange.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.scan("weathered_brown_planks", 0.6, Color(0.42, 0.32, 0.25))
	board.ink = Color(0.95, 0.9, 0.78)
	board.accent = Color(1.0, 0.62, 0.3)
	board.board_ink_fade = Color(0.55, 0.45, 0.36)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	if variant == SUMMER:
		_dress_summer(env, key)
		return
	if variant == AURORA:
		_dress_aurora(env, key)
		return
	env.background_mode = Environment.BG_COLOR
	# A clear night over snow: deep blue, not black, because the snow gives some of it back.
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.46, 0.6)
	env.ambient_light_energy = 0.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The woods going back into the dark.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.065, 0.11)
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 90.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.004
		env.volumetric_fog_albedo = Color(0.8, 0.82, 0.9)
		env.volumetric_fog_length = 10.0
		env.volumetric_fog_ambient_inject = 0.0

	# The moon, high, over the woods in front and to the right: it lights the snow and lays the
	# window bars on the floor, and nothing else.
	key.light_color = Color(0.6, 0.7, 1.0)
	key.light_energy = 0.4
	key.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	key.light_specular = 0.1


## Summer dusk: the sun just down behind the trees in front and to the right, the sky over the
## lake going from gold to rose to a deepening blue, and its warm light still in the clearing.
func _dress_summer(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/dusk_sky.gdshader")
	_sky_mat.set_shader_parameter("zenith", Color(0.1, 0.14, 0.3))
	_sky_mat.set_shader_parameter("upper", Color(0.32, 0.3, 0.46))
	_sky_mat.set_shader_parameter("rose", Color(0.85, 0.5, 0.42))
	_sky_mat.set_shader_parameter("horizon", Color(1.0, 0.66, 0.32))
	_sky_mat.set_shader_parameter("haze", Color(0.24, 0.2, 0.16))
	_sky_mat.set_shader_parameter("sun_dir", Vector3(0.45, -0.03, -1.0))
	_sky_mat.set_shader_parameter("sun_radius", 0.0)
	_sky_mat.set_shader_parameter("stars", 0.3)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.6, 0.58)
	env.ambient_light_energy = 0.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The warm haze of a summer evening over the water, the far shore going soft in it.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.36, 0.28, 0.26)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 260.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.004
		env.volumetric_fog_albedo = Color(0.95, 0.85, 0.75)
		env.volumetric_fog_length = 12.0
		env.volumetric_fog_ambient_inject = 0.0
	# The last of the sun, from where it went down: low and warm, in at the front windows.
	key.light_color = Color(1.0, 0.62, 0.36)
	key.light_energy = 0.75
	key.rotation_degrees = Vector3(-7.0, 155.0, 0.0)
	key.light_specular = 0.2


## The northern lights: a clear night, the stars all out, and the aurora over the trees -- whose
## green comes into the room off the snow, breathing as the display does (_process).
func _dress_aurora(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/cabin_aurora_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.52, 0.55)
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	# Bitter, clear air: the woods go back a long way before the dark takes them.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.02, 0.045, 0.05)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 220.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
	# The aurora's own light, from high over the trees in front: green, faint, enough to show the
	# snow and lay the window bars on the floor.
	_key = key
	key.light_color = AURORA_GREEN
	key.light_energy = AURORA_KEY
	key.rotation_degrees = Vector3(-34.0, 168.0, 0.0)
	key.light_specular = 0.1


## The aurora's green in the room, and how strong the key it makes is at full display.
const AURORA_GREEN := Color(0.45, 1.0, 0.7)
const AURORA_KEY := 0.32


func lamp_colour(_index: int, authored: Color) -> Color:
	# Firelight and oil: the warmest of any venue.
	return authored.lerp(Color(1.0, 0.62, 0.32), 0.45)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.8


## One room: the floor either side of the desk joins the far end, as in the loft.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


func stove_spot() -> Vector2:
	return Vector2(STOVE_AT.x - _grow(), STOVE_AT.y)


## Its weather (Weather, docs/spatial_loop.md part two, slice 44): on the Snowy night, the snow on
## the right-hand wall's window beside the desk, and the switch on its sill board. The big window
## past it is the keys' zone's, out of reach behind the keys. No weather in summer or under the
## northern lights, whose night is clear.
func weather() -> Dictionary:
	if variant != SNOWY:
		return {}
	var half := live_room_half()
	var along := float(RIGHT_BAYS[0])
	var turn := Basis(Vector3.UP, -PI * 0.5)
	return {"kind": &"snow", "spot": Transform3D(turn, Vector3(half, 0, along)), "sill": SILL + 0.003,
			"switch_z": 0.05, "glass": Transform3D(turn, Vector3(half + WALL * 0.5 - 0.006, (SILL + HEAD) * 0.5, along)),
			"size": Vector2(BAY - 0.12, HEAD - SILL - 0.12), "low": 76}


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 42): icicles along an eave
## board across the porch window on the left wall, inside the glass, where a hand can reach them.
func instrument() -> Dictionary:
	return {"kind": &"icicles", "spot": side_wall_instrument(-1.0, float(LEFT_BAYS[0]), 0.06)}


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	# The stove and its hearth: hot, and not something to walk through.
	out.append({"c": stove_spot(), "h": STOVE_SIZE * 0.5 + Vector2(0.15, 0.15), "a": 0.0, "top": 0.9})
	return out


## The roof's underside height at `x`: the eaves at the walls, the ridge over the middle.
func roof_at(x: float) -> float:
	return lerpf(RIDGE, EAVES, clampf(absf(x) / live_room_half(), 0.0, 1.0))


func _ready() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 0.2, back - FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (back + FRONT) * 0.5
	# Wide old boards, scrubbed grey-brown where people walk.
	floor_mesh.material_override = Materials.scanned(StandardMaterial3D.new(), "weathered_brown_planks", "2k",
			2.2, Color(0.62, 0.55, 0.5))
	add_child(floor_mesh)

	var pine := _pine()
	var frame := _timber()
	_build_walls(pine, frame)
	_build_roof(pine, frame)
	_light_the_stove()
	_furnish()
	_hang_lanterns()
	_put_up_the_shelf()
	_plant_the_woods()
	if variant == SNOWY:
		_let_it_snow()
	else:
		_lay_the_lake()
	if variant == SUMMER:
		_grow_the_meadow()
		_light_the_fireflies()
	elif variant == AURORA:
		_drift_the_snow()
		_build_the_porch()
	_dress_zones()


## The fire's glass, the candle flames and the lanterns swell with the mix and flash on each hit
## (the stove's and candles' lights follow in _process); the rug's cream border fluoresces under a
## violet blacklight that comes up with it, and embers and motes lift. At rest all as authored.
func pulse(level: float) -> void:
	hear(level)
	if _fire_mat != null:
		_fire_mat.albedo_color = _fire_base * (1.0 + 0.5 * heard + 0.9 * heard_hit)
	if _flame_mat != null:
		_flame_mat.albedo_color = _flame_base * (1.0 + 0.6 * heard + 1.0 * heard_hit)
	if _lantern_mat != null:
		_lantern_mat.albedo_color = _lantern_base * (1.0 + 0.4 * heard + 0.8 * heard_hit)
	if _uv_rug != null:
		_uv_rug.emission_energy_multiplier = UV_REST + 2.0 * heard + 1.5 * heard_hit
	if _uv_light != null:
		_uv_light.light_energy = 3.0 * heard + 2.5 * heard_hit
	drive_sparks(_embers)
	drive_sparks(_rug_motes)


func _process(delta: float) -> void:
	_flicker += delta
	if _stove_light != null:
		# A fire breathes: two slow waves and a quick one, never out and never flaring. A roaring
		# one breathes harder, and a quicker flutter rides on it.
		var f := 0.82 + 0.1 * sin(_flicker * 2.3) + 0.06 * sin(_flicker * 5.1 + 1.3) + 0.04 * sin(_flicker * 13.7)
		if _fire > 1.0:
			f += 0.07 * sin(_flicker * 9.3 + 0.5) * sin(_flicker * 3.7)
		var up := 1.0 + 0.35 * heard + 0.7 * heard_hit
		_stove_light.light_energy = 2.6 * _fire * f * up
		if _stove_glow != null:
			_stove_glow.light_energy = 0.9 * f * up
	if _sky_mat != null and variant == AURORA:
		# The display swells and fades over minutes; the room's green with it.
		var glow := 0.75 + 0.3 * sin(_flicker * 0.09) * sin(_flicker * 0.053 + 1.1) + 0.08 * sin(_flicker * 0.4)
		_sky_mat.set_shader_parameter("glow", glow)
		if _key != null:
			_key.light_energy = AURORA_KEY * glow
	for i in candle_lights.size():
		var t := _flicker + i * 1.7
		candle_lights[i].light_energy = 1.6 * (0.85 + 0.07 * sin(t * 3.1) + 0.05 * sin(t * 7.9 + 0.4)
				+ 0.03 * sin(t * 17.3)) * (1.0 + 0.3 * heard + 0.6 * heard_hit)


## Knotty pine boards, honey-coloured and oiled.
func _pine() -> StandardMaterial3D:
	return Materials.cached_scanned("cabin_pine", "wood_floor_deck", "2k", 1.8, Color(0.72, 0.6, 0.5))


## Rough-sawn timber for the frames, the rafters and the ties: darker, older than the boards.
func _timber() -> StandardMaterial3D:
	return Materials.cached_scanned("cabin_timber", "weathered_brown_planks", "2k", 1.2,
			Color(0.42, 0.34, 0.28))


## The windows' glass: as _glass, except on the bitter night, when frost has grown over it.
func _window_glass() -> Material:
	if variant != AURORA:
		return _glass()
	if _frost == null:
		_frost = ShaderMaterial.new()
		_frost.shader = preload("res://core/venues/shaders/cabin_frost_glass.gdshader")
	return _frost


## Snow lying on something outside: the sills, the porch's roof, the drifts.
func _snow_cap() -> StandardMaterial3D:
	return Materials.cached_scanned("cabin_snow_cap", "snow_02", "2k", 1.5, Color(0.78, 0.84, 0.92))


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.66, 0.72, 0.08)
	glass.roughness = 0.06
	glass.metallic_specular = 0.7
	return glass


# --- the shell ------------------------------------------------------------------------------

func _build_walls(pine: Material, frame: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var outside := half + WALL * 0.5
	var front_bays := FRONT_BAYS.map(func(x: float) -> float: return x + signf(x) * _grow())
	# The front's right-hand end a few millimetres short of the right wall's outside face.
	_windowed("Front", Vector3(0, 0, FRONT - WALL * 0.5), Vector3.RIGHT, -outside - WALL * 0.5,
			outside + WALL * 0.5 - 0.003, front_bays, BAY, pine, frame)
	# The side walls start a few millimetres past the front's inside face, so no bands overlap.
	_windowed("Left", Vector3(-outside, 0, 0), Vector3.BACK, FRONT + 0.003, back, LEFT_BAYS, BAY, pine,
			frame)
	_windowed("Right", Vector3(outside, 0, 0), Vector3.BACK, FRONT + 0.003, back, RIGHT_BAYS, BAY, pine,
			frame, _keys_window())
	# The back wall: plain boards, a hair inside the side walls' ends.
	ZoneKit.block(self, Vector3(outside * 2.0 - WALL - 0.002, EAVES - 0.008, WALL),
			Vector3(0, EAVES * 0.5, back + WALL * 0.5), pine, "BackWall")
	# The gables over the front and back walls, up into the roof's pitch.
	for g in [[FRONT - WALL * 0.5, "FrontGable"], [back + WALL * 0.5, "BackGable"]]:
		_gable(g[1], g[0], half + WALL, pine)


## The bay over the keys: wider than the others, centred on the synth's zone.
func _keys_window() -> float:
	return (zones()[&"synth"] as AABB).get_center().z


## A wall with windows: ShellKit's bays, each with a cabin window in it -- four panes high, two
## wide, in heavy timber, and a sill board proud of the wall to stand a lantern on. `wide_at`,
## if given, is one more bay KEYS_BAY wide.
func _windowed(label: String, at: Vector3, along: Vector3, from: float, to: float, bays: Array,
		bay: float, pine: Material, frame: Material, wide_at := NAN) -> void:
	var widths: Array = []
	var centres: Array = []
	for c in bays:
		centres.append(c)
		widths.append(bay)
	if not is_nan(wide_at):
		centres.append(wide_at)
		widths.append(KEYS_BAY)
	# ShellKit takes one bay width; a wall with a wide bay is built as its bands and piers by
	# hand from the same pieces.
	var across := Vector3(along.z, 0, along.x).abs()
	var inward := -signf(at.x + at.z)
	var openings: Array[Vector3] = []
	if is_nan(wide_at):
		openings = ShellKit.wall_with_bays(self, label, at, along, from, to, centres, bay, SILL, HEAD, EAVES,
				WALL, pine)
	else:
		openings = _wall_with_mixed_bays(label, at, along, from, to, centres, widths, pine)
	for i in openings.size():
		var w: float = widths[i]
		var uprights := 3 if w < 2.0 else 4
		if variant == SUMMER:
			# Thrown open on the evening: two casements to a window, swung out on their hinges.
			_casements(label + "Window%d" % i, openings[i], along, across * -inward, Vector2(w, HEAD - SILL), frame)
		else:
			ShellKit.glazed(self, label + "Window%d" % i, openings[i], along, Vector2(w, HEAD - SILL), frame,
					_window_glass(), uprights, (HEAD - SILL) / 4.0, 0.07)
		if variant == AURORA:
			# Each pane's frost grows from its own edges and its own small panes' corners.
			var pane := get_node(NodePath(label + "Window%dPane" % i)) as MeshInstance3D
			pane.set_instance_shader_parameter(&"half_size", Vector2(w, HEAD - SILL) * 0.5)
			pane.set_instance_shader_parameter(&"cell", Vector2(w / (uprights - 1), (HEAD - SILL) / 4.0))
			# And snow lying on the sill outside it.
			ZoneKit.block(self, along.abs() * (w - 0.004) + across * 0.13 + Vector3(0, 0.07, 0),
					openings[i] + Vector3(0, -(HEAD - SILL) * 0.5 + 0.036, 0) - across * inward * 0.115,
					_snow_cap(), label + "SillSnow%d" % i)
		# The sill board, on the room side, its top 3 mm proud of the wall's sill.
		ZoneKit.block(self, along.abs() * (w + 0.16) + across * 0.14 + Vector3(0, 0.045, 0),
				openings[i] + Vector3(0, -(HEAD - SILL) * 0.5 - 0.0195, 0) + across * inward * (WALL * 0.5 + 0.05),
				frame, label + "SillBoard%d" % i)


func _wall_with_mixed_bays(label: String, at: Vector3, along: Vector3, from: float, to: float,
		centres: Array, widths: Array, pine: Material) -> Array[Vector3]:
	var across := Vector3(along.z, 0, along.x)
	var place := func(centre: float, y: float) -> Vector3:
		return at * across.abs() + along * centre + Vector3(0, y, 0)
	var sized := func(length: float, tall: float, deep: float) -> Vector3:
		return along.abs() * length + across.abs() * deep + Vector3(0, tall, 0)
	ZoneKit.block(self, sized.call(to - from, SILL, WALL + 0.004), place.call((from + to) * 0.5, SILL * 0.5),
			pine, label + "Sill")
	ZoneKit.block(self, sized.call(to - from, EAVES - HEAD, WALL + 0.004),
			place.call((from + to) * 0.5, (HEAD + EAVES) * 0.5), pine, label + "Head")
	var order := range(centres.size())
	order.sort_custom(func(a: int, b: int) -> bool: return centres[a] < centres[b])
	var edge := from
	var n := 0
	for i: int in order:
		var a: float = centres[i] - widths[i] * 0.5
		if a - edge > 0.01:
			ZoneKit.block(self, sized.call(a - edge, HEAD - SILL, WALL), place.call((a + edge) * 0.5,
					(SILL + HEAD) * 0.5), pine, label + "Pier%d" % n)
			n += 1
		edge = centres[i] + widths[i] * 0.5
	if to - edge > 0.01:
		ZoneKit.block(self, sized.call(to - edge, HEAD - SILL, WALL), place.call((to + edge) * 0.5,
				(SILL + HEAD) * 0.5), pine, label + "Pier%d" % n)
	var out: Array[Vector3] = []
	for c: float in centres:
		out.append(place.call(c, (SILL + HEAD) * 0.5))
	return out


## A gable: the triangle of wall between the eaves and the ridge, `WALL` deep, at depth `z`.
func _gable(label: String, z: float, half: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := WALL * 0.5
	# Its foot sits a few millimetres into the wall below, its sloped edges just under the roof.
	var base := EAVES - 0.004
	var corners := [Vector3(-half, base, 0), Vector3(half, base, 0), Vector3(0, RIDGE + 0.05, 0)]
	var front := corners.map(func(c: Vector3) -> Vector3: return c + Vector3(0, 0, -d))
	var rear := corners.map(func(c: Vector3) -> Vector3: return c + Vector3(0, 0, d))
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	tri.call(front[0], front[2], front[1])
	tri.call(rear[0], rear[1], rear[2])
	for i in 3:
		var j := (i + 1) % 3
		tri.call(front[i], front[j], rear[j])
		tri.call(front[i], rear[j], rear[i])
	st.generate_normals()
	var gable := MeshInstance3D.new()
	gable.name = label
	gable.mesh = st.commit()
	gable.position.z = z
	gable.material_override = material
	add_child(gable)


## The roof: two boarded slopes from the eaves to the ridge, a ridge beam, rafters under the
## boards every RAFTER_SPACING, and two tie beams across the room at the eaves.
func _build_roof(pine: Material, frame: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var rise := RIDGE - EAVES
	var run := half + WALL
	var pitch := atan2(rise, half)
	var slope := Vector2(run, rise * run / half).length()
	var length := back - FRONT + WALL * 2.0 + 0.6
	var ceiling := Materials.cached_scanned("cabin_ceiling", "wood_floor_deck", "2k", 1.8,
			Color(0.5, 0.4, 0.33))
	for side in [-1.0, 1.0]:
		# The right slope a few millimetres shorter, so where they cross at the ridge their
		# ends are not in one plane.
		var board := ZoneKit.block(self, Vector3(slope, 0.08, length - (0.004 if side > 0 else 0.0)),
				Vector3.ZERO, ceiling,
				"Roof" + ("Left" if side < 0 else "Right"))
		# Its underside on the line from the eaves at the wall to the ridge over the middle.
		var mid := Vector2(side * run * 0.5, RIDGE - rise * run * 0.5 / half)
		var normal := Vector2(-side * sin(pitch), cos(pitch))
		board.position = Vector3(mid.x + normal.x * 0.04, mid.y + normal.y * 0.04, (back + FRONT) * 0.5)
		board.rotation.z = -side * pitch
	ZoneKit.block(self, Vector3(0.2, 0.28, length - 0.02), Vector3(0, RIDGE - 0.1, (back + FRONT) * 0.5),
			frame, "RidgeBeam")
	# Rafters: one MultiMesh a side, each under its board.
	var count := int((back - FRONT) / RAFTER_SPACING) + 1
	for side in [-1.0, 1.0]:
		var rafters := MultiMesh.new()
		rafters.transform_format = MultiMesh.TRANSFORM_3D
		var beam := BoxMesh.new()
		beam.size = Vector3(slope - 0.25, 0.18, 0.1)
		rafters.mesh = beam
		rafters.instance_count = count
		var mid := Vector2(side * (run * 0.5 + 0.05), RIDGE - rise * (run * 0.5 + 0.05) / half)
		var normal := Vector2(-side * sin(pitch), cos(pitch))
		for i in count:
			var z := lerpf(FRONT + 0.2, back - 0.2, float(i) / (count - 1))
			var basis := Basis(Vector3.BACK, -side * pitch)
			rafters.set_instance_transform(i, Transform3D(basis,
					Vector3(mid.x - normal.x * 0.091, mid.y - normal.y * 0.091, z)))
		var holder := MultiMeshInstance3D.new()
		holder.name = "Rafters" + ("Left" if side < 0 else "Right")
		holder.multimesh = rafters
		holder.material_override = frame
		add_child(holder)
	for z: float in TIES:
		ZoneKit.block(self, Vector3(half * 2.0 - 0.02, 0.22, 0.16), Vector3(0, EAVES - 0.11, z), frame,
				"TieBeam")


# --- the fire -------------------------------------------------------------------------------

## A cast-iron stove (assets/models/wood_stove.glb) on a slate hearth, its flue up through the
## roof, the fire behind its door glass the brightest thing in the room.
func _light_the_stove() -> void:
	var at := stove_spot()
	var hearth := StandardMaterial3D.new()
	hearth.albedo_color = Color(0.09, 0.09, 0.1)
	hearth.roughness = 0.75
	ZoneKit.block(self, Vector3(1.1, 0.04, 1.1), Vector3(at.x, 0.021, at.y), hearth, "Hearth")
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.035, 0.035, 0.038)
	iron.metallic = 0.6
	iron.roughness = 0.6
	var fire := ZoneKit.glow(Color(1.0, 0.38, 0.1), 1.7)
	_fire_mat = fire
	if variant == SUMMER:
		# Cold: the grate behind the glass grey with old ash.
		fire = StandardMaterial3D.new()
		fire.albedo_color = Color(0.09, 0.085, 0.08)
		fire.roughness = 0.95
		_fire_mat = null
	elif variant == AURORA:
		# Roaring: stoked up against the cold, the glass white-hot orange.
		_fire = 1.45
		fire = ZoneKit.glow(Color(1.0, 0.45, 0.12), 3.0)
		_fire_mat = fire
	# Turned so its door faces into the room, across the corner.
	var stove := _model("wood_stove.glb", Vector3(at.x, 0.041, at.y), deg_to_rad(55.0),
			{"iron": iron, "fire": fire})
	stove.name = "Stove"
	var top := 0.041 + 0.87
	var flue_top := roof_at(at.x) + 0.3
	var flue := MeshInstance3D.new()
	flue.name = "Flue"
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.075
	pipe.bottom_radius = 0.075
	pipe.height = flue_top - top + 0.04
	pipe.radial_segments = 16
	flue.mesh = pipe
	# The flue collar is 8 cm behind the stove's middle, the door being in front.
	var collar := Basis(Vector3.UP, deg_to_rad(55.0)) * Vector3(0, 0, -0.08)
	flue.position = Vector3(at.x + collar.x, top - 0.04 + pipe.height * 0.5, at.y + collar.z)
	flue.material_override = iron
	add_child(flue)
	if variant == SUMMER:
		# No fire to light on a summer evening: a jug of what was picked in the clearing stands on
		# the stove top instead (assets/models/cabin_wildflowers.glb).
		_pick_wildflowers(Vector3(at.x, top + 0.001, at.y) + Basis(Vector3.UP, deg_to_rad(55.0)) * Vector3(0.06, 0, 0.1))
		return
	_fire_base = _fire_mat.albedo_color
	var door := Vector3(at.x, 0.55, at.y) + Basis(Vector3.UP, deg_to_rad(55.0)) * Vector3(0, 0, 0.3)
	var warm := Gradient.new()
	warm.set_color(0, Color(1.0, 0.7, 0.25))
	warm.set_color(1, Color(1.0, 0.35, 0.1))
	_embers = make_sparks("Embers", door, Vector3(0.12, 0.05, 0.12),
			AABB(door - Vector3(2.5, 0.6, 2.5), Vector3(5, 4.5, 5)), warm, 60, true)
	# The fire's light, low, out through the door and across the floor.
	_stove_light = SpotLight3D.new()
	_stove_light.name = "Firelight"
	var facing := Basis(Vector3.UP, deg_to_rad(55.0))
	_stove_light.position = Vector3(at.x, 0.45, at.y) + facing * Vector3(0, 0, 0.4)
	_stove_light.basis = facing * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	_stove_light.light_color = Color(1.0, 0.5, 0.2)
	_stove_light.light_energy = 2.6
	_stove_light.spot_angle = 70.0
	_stove_light.spot_range = 5.5
	_stove_light.spot_angle_attenuation = 0.9
	_stove_light.shadow_enabled = rich
	_stove_light.light_specular = 0.1
	add_child(_stove_light)
	if variant == AURORA:
		# Stoked, the stove throws its heat round the whole corner: the iron, the hearth, the
		# rocking chair, the wall behind, all warm and moving.
		_stove_glow = OmniLight3D.new()
		_stove_glow.name = "StoveGlow"
		_stove_glow.position = Vector3(at.x, 0.7, at.y) + facing * Vector3(0, 0, 0.55)
		_stove_glow.light_color = Color(1.0, 0.48, 0.18)
		_stove_glow.light_energy = 0.9
		_stove_glow.omni_range = 3.2
		_stove_glow.omni_attenuation = 1.6
		_stove_glow.light_specular = 0.05
		add_child(_stove_glow)


## The jug of wildflowers on the cold stove: daisies, cornflowers, tansy and grass heads in a
## stoneware jug with a dark-glazed neck.
func _pick_wildflowers(at: Vector3) -> void:
	var jug := StandardMaterial3D.new()
	jug.albedo_color = Color(0.62, 0.55, 0.45)
	jug.roughness = 0.75
	var glaze := StandardMaterial3D.new()
	glaze.albedo_color = Color(0.2, 0.12, 0.07)
	glaze.roughness = 0.25
	glaze.metallic_specular = 0.6
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color(0.16, 0.3, 0.08)
	stem.roughness = 0.8
	var petal := func(c: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m
	var jar := _model("cabin_wildflowers.glb", at, 0.4, {"jug": jug, "glaze": glaze, "stem": stem,
			"white": petal.call(Color(0.92, 0.9, 0.84)), "blue": petal.call(Color(0.2, 0.32, 0.85)),
			"yellow": petal.call(Color(0.92, 0.7, 0.12))})
	jar.name = "Wildflowers"


## A rocking chair by the fire and a stack of split logs against the wall.
func _furnish() -> void:
	var at := stove_spot()
	var chair := _model("rocking_chair.glb", Vector3(at.x + 1.15, 0.0, at.y + 1.2), deg_to_rad(200.0), {})
	chair.name = "RockingChair"
	_lay_rug(Vector2(at.x + 1.15, at.y + 1.2), deg_to_rad(200.0))
	var bark := Materials.cached_scanned("cabin_logs", "weathered_brown_planks", "2k", 0.5,
			Color(0.38, 0.28, 0.2))
	var logs := MultiMesh.new()
	logs.transform_format = MultiMesh.TRANSFORM_3D
	var split := CylinderMesh.new()
	split.top_radius = 0.07
	split.bottom_radius = 0.07
	split.height = 0.45
	split.radial_segments = 7
	logs.mesh = split
	var rows := [5, 4, 3]
	logs.instance_count = 12
	var n := 0
	var wall := -live_room_half() + 0.3
	for r in rows.size():
		for i: int in rows[r]:
			var z: float = at.y + 1.3 + (i - (rows[r] - 1) * 0.5) * 0.145
			var y: float = 0.07 + r * 0.125
			logs.set_instance_transform(n, Transform3D(Basis(Vector3.BACK, PI * 0.5)
					* Basis(Vector3.UP, i * 1.7), Vector3(wall, y, z)))
			n += 1
	var pile := MultiMeshInstance3D.new()
	pile.name = "Logs"
	pile.multimesh = logs
	pile.material_override = bark
	add_child(pile)


## A long shelf on the back wall between the wall lanterns: a plank on iron brackets, a row of
## preserving jars (assets/models/jar.glb) in amber and green, and candles burning in a few of
## them. It is what the back wall is seen by from the desk -- a warm line at shoulder height --
## and two soft lights under the shelf wash the boards below it.
const SHELF_Y := 1.5
const SHELF_DEPTH := 0.24

## Where each jar on the shelf stands, kept here as well as in the MultiMeshes (which a headless
## run does not hold on to).
var shelf_jars: Array[Transform3D] = []
## The soft lights the shelf's candles cast, which flicker in _process.
var candle_lights: Array[SpotLight3D] = []

func _put_up_the_shelf() -> void:
	var back := LIVE_ROOM_BACK
	# Behind the riser, between the walk out of the booth's door and the lattice, which stands
	# close to the wall.
	var zone := zones()
	var from := (zone[&"vocals"] as AABB).end.x + 1.3
	var to := (zone[&"matrix"] as AABB).position.x - 0.6
	var length := to - from
	var plank := _timber()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.04, 0.04, 0.04)
	iron.metallic = 0.6
	iron.roughness = 0.55
	ZoneKit.block(self, Vector3(length, 0.045, SHELF_DEPTH), Vector3((from + to) * 0.5, SHELF_Y,
			back - SHELF_DEPTH * 0.5 - 0.002), plank, "Shelf")
	for x in [from + 0.25, (from + to) * 0.5, to - 0.25]:
		ZoneKit.block(self, Vector3(0.03, 0.2, 0.03), Vector3(x, SHELF_Y - 0.125, back - 0.017), iron, "ShelfBracket")
		var arm := ZoneKit.block(self, Vector3(0.025, 0.025, 0.24), Vector3(x, SHELF_Y - 0.11, back - 0.11), iron,
				"ShelfStay")
		arm.rotation.x = -0.7
	# The jars: one MultiMesh for the preserves, one for the candle jars, each jar scaled a
	# little differently, the way no two batches are the same.
	var source := (load(MODELS + "jar.glb") as PackedScene).instantiate()
	var mesh := ((source.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D).mesh
	source.free()
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.55, 0.3, 0.08)
	amber.roughness = 0.5
	amber.metallic_specular = 0.35
	var green := amber.duplicate() as StandardMaterial3D
	green.albedo_color = Color(0.2, 0.32, 0.12)
	var tin := StandardMaterial3D.new()
	tin.albedo_color = Color(0.45, 0.4, 0.3)
	tin.metallic = 0.8
	tin.roughness = 0.4
	# A candle jar is open, its lid off: smoky glass lit from inside, so it glows a little
	# itself, a stub of wax in it and a flame on the wick.
	var candle := StandardMaterial3D.new()
	candle.albedo_color = Color(0.85, 0.55, 0.3, 0.35)
	candle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	candle.emission_enabled = true
	candle.emission = Color(1.0, 0.5, 0.18)
	candle.emission_energy_multiplier = 0.9
	candle.roughness = 0.2
	var looks := [[amber, tin], [green, tin], [candle, null]]
	var placed: Array = [[], [], []]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var x := from + 0.12
	var i := 0
	while x < to - 0.12:
		var kind := 2 if i % 5 == 2 else (rng.randi() % 2)
		var size := rng.randf_range(0.8, 1.25)
		placed[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, size, 1)
				* rng.randf_range(0.9, 1.1)), Vector3(x, SHELF_Y + 0.0226, back - SHELF_DEPTH * 0.5)))
		x += rng.randf_range(0.12, 0.2)
		i += 1
	for k in placed.size():
		shelf_jars.append_array(placed[k])
	for k in looks.size():
		var jars := mesh.duplicate() as ArrayMesh
		jars.surface_set_material(0, looks[k][0])
		if looks[k][1] == null:
			jars.surface_remove(1)
		else:
			jars.surface_set_material(1, looks[k][1])
		_shelf_row(["Preserves", "Pickles", "CandleJars"][k], jars, placed[k])
	# Inside each candle jar: the wax, and over it a flame drawn bright and unshaded, a thin
	# teardrop on the wick. They stand at the jar's foot and are not stretched with its height.
	var wax := CylinderMesh.new()
	wax.top_radius = 0.034
	wax.bottom_radius = 0.034
	wax.height = 0.05
	wax.radial_segments = 12
	wax.rings = 1
	var tallow := StandardMaterial3D.new()
	tallow.albedo_color = Color(0.9, 0.82, 0.66)
	tallow.emission_enabled = true
	tallow.emission = Color(1.0, 0.6, 0.3)
	tallow.emission_energy_multiplier = 0.6
	wax.material = tallow
	var flame := SphereMesh.new()
	flame.radius = 0.008
	flame.height = 0.03
	flame.radial_segments = 8
	flame.rings = 4
	_flame_mat = ZoneKit.glow(Color(1.0, 0.78, 0.45), 2.2)
	_flame_base = _flame_mat.albedo_color
	flame.material = _flame_mat
	var stubs: Array = []
	var tips: Array = []
	for jar: Transform3D in placed[2]:
		stubs.append(Transform3D(Basis(), jar.origin + Vector3(0, 0.026, 0)))
		tips.append(Transform3D(Basis(), jar.origin + Vector3(0, 0.066, 0)))
	_shelf_row("CandleWax", wax, stubs)
	_shelf_row("CandleFlames", flame, tips)
	# The candles light the boards under the shelf, softly, and the wall above it, and they
	# gutter as candles do -- each to its own beat, quicker than the stove.
	for t in [0.28, 0.72]:
		var at := Vector3(lerpf(from, to, t), SHELF_Y + 0.12, back - SHELF_DEPTH - 0.05)
		var wash := ZoneKit.spot_down(self, at, Color(1.0, 0.62, 0.3), 1.6, 80.0, 2.6)
		wash.name = "CandleWash"
		wash.rotation_degrees.x = 20.0
		wash.rotation_degrees.y = 180.0
		candle_lights.append(wash)


func _shelf_row(label: String, mesh: Mesh, at: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for n in at.size():
		mm.set_instance_transform(n, at[n])
	var holder := MultiMeshInstance3D.new()
	holder.name = label
	holder.multimesh = mm
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


## A braided rag rug, oval, under the rocking chair: rings of colour, each a hair above the last.
func _lay_rug(at: Vector2, yaw: float) -> void:
	var rings := [[1.0, Color(0.36, 0.12, 0.09)], [0.8, Color(0.55, 0.47, 0.33)], [0.62, Color(0.2, 0.25, 0.3)],
			[0.42, Color(0.42, 0.14, 0.1)], [0.22, Color(0.55, 0.47, 0.33)]]
	for i in rings.size():
		var r: float = rings[i][0]
		var disc := MeshInstance3D.new()
		disc.name = "Rug%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.7 * r
		cyl.bottom_radius = 0.7 * r
		cyl.height = 0.006
		cyl.radial_segments = 32
		cyl.rings = 1
		disc.mesh = cyl
		disc.position = Vector3(at.x, 0.003 + i * 0.0015, at.y)
		disc.rotation.y = yaw
		disc.scale = Vector3(1.0, 1.0, 0.7)
		disc.material_override = Materials.cached_scanned("cabin_rug%d" % i, "wool_boucle", "1k", 0.4, rings[i][1])
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)


## Oil lanterns (assets/models/lantern.glb) hung on chains from the rafters over the walk to the
## zones and over the walkways between the neighbourhoods (never over a middle, where its banner
## hangs), and one on the table. Each lantern's glass glows; the hung ones light the floor.
func _hang_lanterns() -> void:
	var half := live_room_half()
	var chain := StandardMaterial3D.new()
	chain.albedo_color = Color(0.05, 0.045, 0.04)
	chain.metallic = 0.7
	chain.roughness = 0.5
	var spots := [Vector3(-half * 0.62, 2.55, 2.95), Vector3(0, 2.7, 1.05), Vector3(half * 0.62, 2.55, 2.95),
			Vector3(-half * 0.62, 2.6, -0.3), Vector3(half * 0.62, 2.6, -0.3),
			Vector3(-4.2, 2.8, 4.9), Vector3(-4.0, 2.8, 8.6), Vector3(4.0, 2.8, 8.0), Vector3(4.0, 2.8, 11.0)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var hook := roof_at(at.x) - 0.2
		var drop := hook - (at.y + 0.29)
		var link := ZoneKit.block(self, Vector3(0.012, drop, 0.012), Vector3(at.x, at.y + 0.29 + drop * 0.5, at.z),
				chain, "Chain%d" % i)
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lantern("Lantern%d" % i, at)
		ZoneKit.spot_down(self, at + Vector3(0, -0.02, 0), Color(1.0, 0.68, 0.38), 3.4, 75.0, 4.4)
	# Two more on iron brackets on the back wall, between the zones, washing the boards.
	var back := LIVE_ROOM_BACK
	for i in 2:
		# At the shelf's end by the booth, and in the walkway between the lattice and the synths.
		var x: float = [-4.35 - _grow(), 4.0 + _grow()][i]
		var at := Vector3(x, 2.05, back - 0.26)
		ZoneKit.block(self, Vector3(0.03, 0.03, 0.26), Vector3(x, at.y + 0.33, back - 0.13), chain,
				"Bracket%d" % i)
		var link := ZoneKit.block(self, Vector3(0.012, 0.04, 0.012), Vector3(x, at.y + 0.305, at.z), chain,
				"BracketChain%d" % i)
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lantern("WallLantern%d" % i, at)
		var wash := ZoneKit.spot_down(self, at + Vector3(0, 0.12, 0), Color(1.0, 0.66, 0.36), 3.0, 70.0, 3.6)
		# Up and down the wall as much as onto the floor.
		wash.rotation_degrees.x = -60.0
		wash.rotation_degrees.y = 180.0


func _lantern(label: String, at: Vector3) -> Node3D:
	if _lantern_mat == null:
		_lantern_mat = ZoneKit.glow(Color(1.0, 0.66, 0.34), 1.6)
		_lantern_base = _lantern_mat.albedo_color
	var lantern := _model("lantern.glb", at, 0.0, {"Lantern_01_glass": _lantern_mat})
	lantern.name = label
	# Small, and lit from inside: a shadow apiece would cost more than it shows.
	for mesh: MeshInstance3D in lantern.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lantern


## The woods: firs (assets/models/firs.glb, three shapes) on snow all round, thick close in and
## thinning into the fog, with a clearing round the cabin. One MultiMesh a shape.
func _plant_the_woods() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Snow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(360, 360)
	ground.mesh = plane
	ground.position.y = GROUND
	if variant == SUMMER:
		var meadow := ShaderMaterial.new()
		meadow.shader = preload("res://core/venues/shaders/cabin_meadow.gdshader")
		meadow.set_shader_parameter("centre", Vector2(0.0, 2.5))
		ground.material_override = meadow
	else:
		# Under the aurora the snow is deep and new, and brighter for it.
		ground.material_override = Materials.scanned(StandardMaterial3D.new(), "snow_02", "2k", 4.0,
				Color(0.62, 0.66, 0.74) if variant == SNOWY else Color(0.7, 0.76, 0.84))
	add_child(ground)
	var source := load(MODELS + "firs.glb") as PackedScene
	var firs := source.instantiate()
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.035, 0.065, 0.05)
	needles.roughness = 0.9
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.7, 0.75, 0.85)
	snow.roughness = 0.8
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.1, 0.07, 0.05)
	if variant == SUMMER:
		# No snow on them: the caps are the new growth at the tips, a lighter green.
		needles.albedo_color = Color(0.04, 0.075, 0.045)
		snow.albedo_color = Color(0.07, 0.12, 0.05)
		snow.roughness = 0.9
	elif variant == AURORA:
		snow.albedo_color = Color(0.8, 0.85, 0.94)
	var swap := {"needles": needles, "snow": snow, "bark": bark}
	var shapes: Array[Mesh] = []
	for node in firs.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.surface_set_material(s, swap[m.resource_name])
		shapes.append(mesh)
	firs.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var half := live_room_half()
	var clearing := Rect2(-half - 3.0, FRONT - 3.0, half * 2.0 + 6.0, LIVE_ROOM_BACK - FRONT + 6.0)
	var placed: Array = shapes.map(func(_m): return [])
	for i in 420:
		var r := sqrt(rng.randf()) * 90.0
		var a := rng.randf() * TAU
		var at := Vector2(cos(a) * r, sin(a) * r + 2.5)
		if clearing.grow(1.5).has_point(at) or (variant != SNOWY and not _wooded(at)):
			continue
		var tall := rng.randf_range(5.0, 13.0) * (1.0 + clampf(r / 90.0, 0, 1) * 0.4)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * tall),
				Vector3(at.x, GROUND, at.y))
		placed[rng.randi() % shapes.size()].append(t)
	if variant != SNOWY:
		# The far shore: woods on past the lake, a dark line under the sky across the water.
		for i in 260:
			var r := rng.randf_range(LAKE_AT.length() + LAKE_RADII.y * 0.7, 160.0)
			var a := -PI * 0.5 + rng.randf_range(-1.1, 1.1)
			var at := Vector2(cos(a) * r, sin(a) * r + 2.5)
			if not _wooded(at):
				continue
			var tall := rng.randf_range(8.0, 16.0)
			placed[rng.randi() % shapes.size()].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
					.scaled(Vector3.ONE * tall), Vector3(at.x, GROUND, at.y)))
	for k in shapes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shapes[k]
		mm.instance_count = placed[k].size()
		for i in placed[k].size():
			mm.set_instance_transform(i, placed[k][i])
		var holder := MultiMeshInstance3D.new()
		holder.name = "Firs%d" % k
		holder.multimesh = mm
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(holder)


## Whether trees grow at `at` (on the ground, studio space) in an arrangement with the lake: not
## in the water and its shore, and not in the gap kept from the front windows down to it.
func _wooded(at: Vector2) -> bool:
	var q := (at - LAKE_AT) / (LAKE_RADII + Vector2(4.0, 4.0))
	if q.length() < 1.0:
		return false
	var ahead := -(at.y - FRONT)
	if ahead > 0.0 and ahead < LAKE_AT.length() and absf(atan2(at.x, ahead)) < VIEW_GAP:
		return false
	return true


## Snow falling past the windows, in front and on the right: GPU particles, a few hundred flakes
## drifting down in boxes outside the glass. Nothing falls indoors.
func _let_it_snow() -> void:
	var half := live_room_half()
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.albedo_color = Color(0.8, 0.84, 0.95, 0.85)
	flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.billboard_keep_scale = true
	# A soft round flake, not a square one.
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = fade
	soft.width = 32
	soft.height = 32
	flake.albedo_texture = soft
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	quad.material = flake
	# Each box a metre and more clear of the walls, and the drift too gentle to carry a flake
	# that far, so nothing falls indoors.
	for side in [["SnowFront", Vector3(0, 4.0, FRONT - 6.5), Vector3(half + 6.0, 4.5, 5.0)],
			["SnowRight", Vector3(half + 5.6, 4.0, 4.2), Vector3(4.0, 4.5, 8.6)],
			["SnowLeft", Vector3(-half - 5.6, 4.0, 4.2), Vector3(4.0, 4.5, 8.6)]]:
		var fall := GPUParticles3D.new()
		fall.name = side[0]
		fall.position = side[1]
		fall.amount = 900
		fall.lifetime = 12.0
		fall.preprocess = 12.0
		fall.draw_pass_1 = quad
		fall.visibility_aabb = AABB(-side[2] - Vector3(0, 6, 0), side[2] * 2.0 + Vector3(0, 6, 0))
		var drift := ParticleProcessMaterial.new()
		drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		drift.emission_box_extents = side[2]
		drift.direction = Vector3(0, -1, 0)
		# Straight down, with only a little sway: a flake that starts a metre and a half out from
		# the wall in twelve seconds must still be outside it.
		drift.spread = 2.0
		drift.initial_velocity_min = 0.4
		drift.initial_velocity_max = 0.8
		drift.gravity = Vector3(0, -0.15, 0)
		drift.turbulence_enabled = true
		drift.turbulence_noise_strength = 0.12
		drift.turbulence_influence_min = 0.01
		drift.turbulence_influence_max = 0.04
		drift.turbulence_noise_scale = 4.0
		drift.scale_min = 0.6
		drift.scale_max = 1.4
		fall.process_material = drift
		add_child(fall)


# --- summer and the lights ------------------------------------------------------------------

## The lake past the clearing (cabin_lake.gdshader): open water on a summer evening, mirroring
## the sky; on the bitter night, ice with the snow blown across it.
func _lay_the_lake() -> void:
	var water := ShaderMaterial.new()
	water.shader = preload("res://core/venues/shaders/cabin_lake.gdshader")
	water.set_shader_parameter("centre", LAKE_AT)
	water.set_shader_parameter("radii", LAKE_RADII)
	water.set_shader_parameter("ice", 1.0 if variant == AURORA else 0.0)
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	var plane := PlaneMesh.new()
	plane.size = LAKE_RADII * 2.0 + Vector2(10.0, 10.0)
	lake.mesh = plane
	# A hand over the ground plane, so the two never share it.
	lake.position = Vector3(LAKE_AT.x, GROUND + 0.04, LAKE_AT.y)
	lake.material_override = water
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)


## The summer clearing: meadow grass in tufts all round the cabin, thinning out toward the trees
## (assets/models/cabin_porch.glb's "grass", cabin_grass.gdshader), and birches standing among
## the firs (cabin_birches.glb), white trunks catching the last of the light.
func _grow_the_meadow() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var half := live_room_half()
	var cabin := Rect2(-half - WALL - 0.3, FRONT - WALL - 0.3, (half + WALL + 0.3) * 2.0,
			LIVE_ROOM_BACK - FRONT + WALL * 2.0 + 0.6)
	var grass := ShaderMaterial.new()
	grass.shader = preload("res://core/venues/shaders/cabin_grass.gdshader")
	var holder := _part("cabin_porch.glb", "grass")
	var tuft := holder.mesh
	holder.free()
	var tufts: Array[Transform3D] = []
	while tufts.size() < 4200:
		var r := 1.0 + pow(rng.randf(), 1.6) * 30.0
		var a := rng.randf() * TAU
		var at := Vector2(cos(a) * r * 1.2, sin(a) * r + 2.5)
		if cabin.has_point(at) or ((at - LAKE_AT) / LAKE_RADII).length() < 1.08:
			continue
		var size := rng.randf_range(0.7, 1.5) * (1.2 if r < 6.0 else 1.0)
		tufts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.8, 1.3), size)),
				Vector3(at.x, GROUND, at.y)))
	_bank("Meadow", tuft, tufts, grass)
	# The birches.
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.82, 0.8, 0.76)
	white.roughness = 0.8
	var mark := StandardMaterial3D.new()
	mark.albedo_color = Color(0.07, 0.06, 0.05)
	mark.roughness = 0.9
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.2, 0.33, 0.09)
	leaves.roughness = 0.75
	leaves.backlight_enabled = true
	leaves.backlight = Color(0.3, 0.32, 0.08)
	var source := (load(MODELS + "cabin_birches.glb") as PackedScene).instantiate()
	var shapes: Array[Mesh] = []
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null:
				mesh.surface_set_material(s, {"bark": white, "mark": mark, "leaves": leaves}.get(m.resource_name, m))
		shapes.append(mesh)
	source.free()
	var clearing := Rect2(-half - 3.0, FRONT - 3.0, half * 2.0 + 6.0, LIVE_ROOM_BACK - FRONT + 6.0)
	var placed: Array = shapes.map(func(_m): return [])
	for i in 140:
		var r := rng.randf_range(7.0, 55.0)
		var a := rng.randf() * TAU
		var at := Vector2(cos(a) * r, sin(a) * r + 2.5)
		if clearing.grow(2.5).has_point(at) or not _wooded(at):
			continue
		var tall := rng.randf_range(7.0, 13.0)
		placed[rng.randi() % shapes.size()].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3.ONE * tall), Vector3(at.x, GROUND, at.y)))
	for k in shapes.size():
		_bank("Birches%d" % k, shapes[k], placed[k], null)


## Fireflies over the grass outside, in front and either side and out in the clearing toward the
## lake: GPU particles drifting low, each glowing up and going out on its own slow beat
## (cabin_firefly.gdshader).
func _light_the_fireflies() -> void:
	var half := live_room_half()
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://core/venues/shaders/cabin_firefly.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = glow
	for spot in [["FirefliesFront", Vector3(0, GROUND + 1.0, FRONT - 9.0), Vector3(half + 8.0, 0.9, 6.0), 110],
			["FirefliesRight", Vector3(half + 6.5, GROUND + 1.0, 2.5), Vector3(4.0, 0.9, 7.0), 50],
			["FirefliesLeft", Vector3(-half - 6.5, GROUND + 1.0, 2.5), Vector3(4.0, 0.9, 7.0), 50]]:
		var swarm := GPUParticles3D.new()
		swarm.name = spot[0]
		swarm.position = spot[1]
		swarm.amount = spot[3]
		swarm.lifetime = 14.0
		swarm.preprocess = 14.0
		swarm.draw_pass_1 = quad
		swarm.visibility_aabb = AABB(-spot[2] - Vector3.ONE * 2.0, spot[2] * 2.0 + Vector3.ONE * 4.0)
		var drift := ParticleProcessMaterial.new()
		drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		drift.emission_box_extents = spot[2]
		drift.direction = Vector3(1, 0.2, 0)
		drift.spread = 180.0
		drift.initial_velocity_min = 0.05
		drift.initial_velocity_max = 0.2
		drift.gravity = Vector3.ZERO
		drift.turbulence_enabled = true
		drift.turbulence_noise_strength = 0.4
		drift.turbulence_noise_scale = 3.0
		drift.turbulence_influence_min = 0.05
		drift.turbulence_influence_max = 0.15
		swarm.process_material = drift
		add_child(swarm)


## Two casements in an opening, swung out on their hinges at the jambs: each a timber frame with
## a glazing bar across it and its glass, hinged at the wall's outside face.
func _casements(label: String, centre: Vector3, along: Vector3, outward: Vector3, size: Vector2,
		frame: Material) -> void:
	var leaf_w := size.x * 0.5 - 0.005
	var h := size.y - 0.01
	for side in [-1.0, 1.0]:
		var hinge: Vector3 = centre + along * (side * size.x * 0.5 - side * 0.002) + outward * (WALL * 0.5)
		# Open by most of a right angle, the right-hand leaf a little wider than the left.
		var swing: float = deg_to_rad(68.0 if side < 0 else 78.0)
		var open: Vector3 = (-side * along) * cos(swing) + outward * sin(swing)
		var leaf := Node3D.new()
		leaf.name = label + ("CasementL" if side < 0 else "CasementR")
		leaf.transform = Transform3D(Basis(open, Vector3.UP, open.cross(Vector3.UP)), hinge)
		add_child(leaf)
		for y in [-1.0, 1.0]:
			ZoneKit.block(leaf, Vector3(leaf_w, 0.06, 0.05), Vector3(leaf_w * 0.5, y * (h * 0.5 - 0.03), 0), frame, "Rail")
		for x in [0.03, leaf_w - 0.03]:
			ZoneKit.block(leaf, Vector3(0.06, h - 0.124, 0.046), Vector3(x, 0, 0), frame, "Stile")
		ZoneKit.block(leaf, Vector3(leaf_w - 0.124, 0.035, 0.03), Vector3(leaf_w * 0.5, 0, 0), frame, "Bar")
		var pane := ZoneKit.block(leaf, Vector3(leaf_w - 0.122, h - 0.122, 0.006), Vector3(leaf_w * 0.5, 0, 0), _glass(),
				"Pane")
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Snow drifted deep against the cabin's walls on the bitter night: long mounds along the front
## and the right-hand wall, their tops up about as high as the floor inside.
func _drift_the_snow() -> void:
	var half := live_room_half()
	var snow := Materials.cached_scanned("cabin_drift", "snow_02", "2k", 2.0, Color(0.74, 0.8, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var mounds: Array = []
	# Long, low banks, each overlapping the next, so the drift is one shape along the wall.
	var x := -half - 1.0
	while x < half + 1.0:
		mounds.append([Vector3(x, GROUND - 0.1, FRONT - WALL - 0.2), Vector3(rng.randf_range(2.2, 3.2),
				rng.randf_range(0.75, 0.95), rng.randf_range(1.0, 1.4))])
		x += rng.randf_range(1.1, 1.6)
	var z := FRONT
	while z < LIVE_ROOM_BACK + 0.5:
		mounds.append([Vector3(half + WALL + 0.2, GROUND - 0.1, z), Vector3(rng.randf_range(1.0, 1.4),
				rng.randf_range(0.75, 0.95), rng.randf_range(2.2, 3.2))])
		z += rng.randf_range(1.1, 1.6)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 16
	ball.rings = 8
	var placed: Array[Transform3D] = []
	for m: Array in mounds:
		var s: Vector3 = m[1] * Vector3(1.0, 0.6, 1.0)
		placed.append(Transform3D(Basis.from_scale(s), m[0]))
	_bank("Drifts", ball, placed, snow)


## The covered porch along the left-hand wall, outside, seen through the window past the stove: a
## plank deck a step under the floor, a lean-to roof on three posts with a foot of snow on it and
## icicles along its edge, a plank door, a bench under the window, firewood stacked against the
## wall, the axe in the chopping block (assets/models/cabin_porch.glb), and a lantern by the door.
func _build_the_porch() -> void:
	var half := live_room_half()
	var wall := -half - WALL
	var edge := wall - PORCH_DEPTH
	var length := PORCH_TO - PORCH_FROM
	var mid_z := (PORCH_FROM + PORCH_TO) * 0.5
	var timber := _timber()
	var planks := Materials.cached_scanned("cabin_porch_deck", "weathered_brown_planks", "2k", 1.0,
			Color(0.5, 0.42, 0.36))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.04, 0.04, 0.04)
	iron.metallic = 0.6
	iron.roughness = 0.55
	var snow := _snow_cap()
	ZoneKit.block(self, Vector3(PORCH_DEPTH - 0.004, 0.08, length), Vector3(wall - PORCH_DEPTH * 0.5 - 0.002,
			PORCH_DECK - 0.04, mid_z), planks, "PorchDeck")
	# Its fascia down to the snow, and the snow blown in over its outer edge.
	ZoneKit.block(self, Vector3(0.06, PORCH_DECK - 0.08 - GROUND + 0.1, length - 0.004), Vector3(edge + 0.028,
			(PORCH_DECK - 0.08 + GROUND - 0.1) * 0.5, mid_z), timber, "PorchFascia")
	ZoneKit.block(self, Vector3(0.55, 0.07, length - 0.3), Vector3(edge + 0.3, PORCH_DECK + 0.034, mid_z), snow,
			"PorchSnow")
	# Posts, a plate along their tops, and the roof leaning from the wall onto it.
	var post_x := edge + 0.14
	var roof_at_post := lerpf(PORCH_ROOF.x, PORCH_ROOF.y, (wall - post_x) / PORCH_DEPTH)
	for z: float in [PORCH_FROM + 0.15, mid_z, PORCH_TO - 0.15]:
		ZoneKit.block(self, Vector3(0.16, roof_at_post - 0.2 - PORCH_DECK, 0.16), Vector3(post_x,
				(roof_at_post - 0.2 + PORCH_DECK) * 0.5, z), timber, "PorchPost")
	ZoneKit.block(self, Vector3(0.18, 0.2, length + 0.1), Vector3(post_x, roof_at_post - 0.1 - 0.001, mid_z), timber,
			"PorchPlate")
	var run := PORCH_DEPTH + 0.35
	var drop := (PORCH_ROOF.x - PORCH_ROOF.y) * run / PORCH_DEPTH
	var slope := Vector2(run, drop).length()
	var pitch := atan2(drop, run)
	var roof_mid := Vector3(wall - run * 0.5, PORCH_ROOF.x - drop * 0.5 + 0.05, mid_z)
	var roof := ZoneKit.block(self, Vector3(slope, 0.08, length + 0.5), roof_mid, timber, "PorchRoof")
	roof.rotation.z = pitch
	# The snow on it, a foot deep, rounded off over its edge.
	var cap := ZoneKit.block(self, Vector3(slope - 0.08, 0.26, length + 0.42), roof_mid + Vector3(sin(pitch) * -0.17,
			cos(pitch) * 0.17, 0), snow, "PorchRoofSnow")
	cap.rotation.z = pitch
	# Icicles along the roof's low edge, all lengths, one MultiMesh.
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.75, 0.85, 0.95, 0.75)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.roughness = 0.08
	ice.metallic_specular = 0.9
	var spike := CylinderMesh.new()
	spike.top_radius = 0.022
	spike.bottom_radius = 0.0
	spike.height = 1.0
	spike.radial_segments = 6
	spike.rings = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var icicles: Array[Transform3D] = []
	var low := Vector3(wall - run + 0.03, PORCH_ROOF.x - drop + 0.01, 0)
	var z := PORCH_FROM - 0.2
	while z < PORCH_TO + 0.2:
		var long := rng.randf_range(0.08, 0.5) * (1.0 if rng.randf() < 0.7 else 0.4)
		icicles.append(Transform3D(Basis.from_scale(Vector3(rng.randf_range(0.7, 1.4), long, rng.randf_range(0.7, 1.4))),
				Vector3(low.x, low.y - long * 0.5, z)))
		z += rng.randf_range(0.06, 0.2)
	_bank("Icicles", spike, icicles, ice)
	# The door, on the wall's outside face, with its strap hinges and latch.
	var door_z := 2.75
	ZoneKit.block(self, Vector3(0.05, 2.0, 0.9), Vector3(wall - 0.027, PORCH_DECK + 1.0 + 0.002, door_z), planks,
			"PorchDoor")
	for y in [0.35, 1.65]:
		ZoneKit.block(self, Vector3(0.012, 0.05, 0.62), Vector3(wall - 0.056, PORCH_DECK + y, door_z + 0.12), iron,
				"DoorStrap")
	ZoneKit.block(self, Vector3(0.03, 0.04, 0.18), Vector3(wall - 0.065, PORCH_DECK + 1.05, door_z - 0.3), iron,
			"DoorLatch")
	# Firewood stacked against the wall at the front end, under the roof.
	var bark := Materials.cached_scanned("cabin_logs", "weathered_brown_planks", "2k", 0.5, Color(0.38, 0.28, 0.2))
	var split := CylinderMesh.new()
	split.top_radius = 0.075
	split.bottom_radius = 0.075
	split.height = 0.5
	split.radial_segments = 7
	split.rings = 1
	var logs: Array[Transform3D] = []
	for row in 7:
		var n := 11 - (row / 3)
		for i in n:
			logs.append(Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, (i * 7 + row) * 0.9),
					Vector3(wall - 0.3, PORCH_DECK + 0.075 + row * 0.14, PORCH_FROM + 0.35 + i * 0.152 + (row % 2) * 0.07)))
	_bank("PorchWood", split, logs, bark)
	# The bench under the window, and the chopping block out by the steps with the axe in it.
	var bench := _part("cabin_porch.glb", "bench", {"bark": bark, "end_grain": planks, "ash": timber})
	bench.name = "PorchBench"
	bench.position = Vector3(wall - 0.3, PORCH_DECK, 1.4)
	bench.rotation.y = PI * 0.5
	add_child(bench)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.3, 0.3, 0.32)
	steel.metallic = 0.85
	steel.roughness = 0.4
	var ash := StandardMaterial3D.new()
	ash.albedo_color = Color(0.6, 0.48, 0.32)
	ash.roughness = 0.55
	var end_grain := StandardMaterial3D.new()
	end_grain.albedo_color = Color(0.62, 0.5, 0.36)
	end_grain.roughness = 0.85
	var block := _part("cabin_porch.glb", "chopping_block", {"bark": bark, "end_grain": end_grain, "steel": steel,
			"ash": ash})
	block.name = "ChoppingBlock"
	block.position = Vector3(edge + 0.75, PORCH_DECK, 3.75)
	block.rotation.y = 2.2
	add_child(block)
	# A lantern on a bracket by the door: the porch's light, on the deck and the snow past it.
	var at := Vector3(wall - 0.55, PORCH_DECK + 2.15, door_z - 0.75)
	ZoneKit.block(self, Vector3(0.5, 0.03, 0.03), Vector3(wall - 0.25, at.y + 0.33, at.z), iron, "LanternBracket")
	_lantern("PorchLantern", at)
	var wash := ZoneKit.spot_down(self, at + Vector3(0, -0.02, 0), Color(1.0, 0.66, 0.36), 2.6, 80.0, 5.0)
	wash.name = "PorchLight"
	wash.rotation_degrees.z = -18.0


## One object's mesh out of a model with several, as a MeshInstance3D, its materials swapped by
## name; not yet in the tree.
func _part(file: String, object: String, swap := {}) -> MeshInstance3D:
	var source := (load(MODELS + file) as PackedScene).instantiate()
	var found := source.find_child(object, true, false)
	var mesh: Mesh = (found as MeshInstance3D).mesh if found is MeshInstance3D \
			else (found.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	source.free()
	var out := MeshInstance3D.new()
	out.mesh = mesh
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swap.has(m.resource_name):
			out.set_surface_override_material(s, swap[m.resource_name])
	return out


## A MultiMesh of `mesh` at each of `at`, added under `label`; `material` over all of it if given.
func _bank(label: String, mesh: Mesh, at: Array, material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
	var holder := MultiMeshInstance3D.new()
	holder.name = label
	holder.multimesh = mm
	if material != null:
		holder.material_override = material
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


# --- the zones ------------------------------------------------------------------------------

## The zones in the cabin's own materials: a plank riser on a rag rug, a booth framed in timber,
## the lattice's square as a braided rug's border, a farmhouse table with a lantern on it, and
## the keys under the big window.
func _dress_zones() -> void:
	var z := zones()
	var frame := _timber()
	var pine := _pine()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.04, 0.04, 0.04)
	iron.metallic = 0.6
	iron.roughness = 0.55
	var wool := Materials.cached_scanned("cabin_wool", "wool_boucle", "1k", 0.6, Color(0.5, 0.16, 0.12))

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, wool, pine)
	ZoneKit.spot_down(drums, Vector3(0, roof_at(drum_box.get_center().x) - 0.4, 0), Color(1.0, 0.72, 0.45),
			3.4, 46.0, 5.5, iron)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, frame, _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.66, 0.4),
			1.3, 60.0, 3.2, iron)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var lattice: AABB = z[&"matrix"]
	# A braided rug's border, deep red and cream, the floor inside it bare boards.
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.003, 0), 0.14, wool)
	# The cream thread glows blue-white under a blacklight, as bleached wool does.
	_uv_rug = (Materials.cached_scanned("cabin_cream", "wool_boucle", "1k", 0.6, Color(0.7, 0.64, 0.52))
			.duplicate() as StandardMaterial3D)
	_uv_rug.emission_enabled = true
	_uv_rug.emission = Color(0.55, 0.65, 1.0)
	_uv_rug.emission_energy_multiplier = UV_REST
	ZoneKit.floor_frame(matrix, Vector2(2.82, 2.82), Vector3(0, 0.004, 0), 0.05, _uv_rug)
	ZoneKit.spot_down(matrix, Vector3(0, roof_at(0.0) - 0.45, 0), Color(0.95, 0.8, 0.62), 4.2, 40.0, 6.5,
			iron)
	_uv_light = ZoneKit.spot_down(matrix, Vector3(0.4, roof_at(0.0) - 0.45, 0), Color(0.55, 0.25, 1.0), 0.0,
			46.0, 6.5)
	_uv_light.light_specular = 0.0
	var lc := lattice.get_center()
	var cold := Gradient.new()
	cold.set_color(0, Color(0.55, 0.7, 1.0))
	cold.set_color(1, Color(0.7, 0.35, 1.0))
	_rug_motes = make_sparks("RugMotes", Vector3(lc.x, 0.15, lc.z), Vector3(1.4, 0.05, 1.4),
			AABB(Vector3(lc.x - 2.5, 0, lc.z - 2.5), Vector3(5, 4, 5)), cold, 80, true)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	var bench: AABB = z[&"bricks"]
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.08, pine, frame)
	_dress_prop_shelf(pine, frame)
	# At the far end: the near end is the fifths wheel's (Venue.wheel_spot).
	var on_table := Vector3(0.25, ZoneKit.TABLE_HEIGHT + 0.001, 0.75)
	_lantern("TableLantern", bench.get_center() * Vector3(1, 0, 1) + on_table)
	ZoneKit.spot_down(bricks, Vector3(0, roof_at(bench.get_center().x) - 0.5, 0), Color(1.0, 0.72, 0.45),
			2.2, 50.0, 4.4, iron)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, iron, frame)
	ZoneKit.spot_down(synth, Vector3(-0.3, EAVES - 0.3, 0), Color(1.0, 0.74, 0.5), 2.0, 46.0, 4.0, iron)


## A model from assets/models, stood at `at` turned `yaw`, with its materials swapped by name.
func _model(file: String, at: Vector3, yaw: float, swap: Dictionary) -> Node3D:
	var node := (load(MODELS + file) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	add_child(node)
	return node


func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.06, 0.04, 0.014, _timber())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Wood stove and firs: earth pigments, brick and ochre, moss and pine, a faded denim.
func track_palette() -> Array:
	return [
		Color(0.71, 0.27, 0.18), Color(0.78, 0.45, 0.23), Color(0.82, 0.65, 0.29), Color(0.60, 0.65, 0.28),
		Color(0.37, 0.56, 0.31), Color(0.31, 0.54, 0.49), Color(0.37, 0.56, 0.68), Color(0.31, 0.39, 0.57),
		Color(0.48, 0.35, 0.55), Color(0.60, 0.35, 0.48), Color(0.76, 0.48, 0.48), Color(0.65, 0.60, 0.53),
	]
