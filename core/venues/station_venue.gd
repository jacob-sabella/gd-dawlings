class_name StationVenue
extends Venue

## A space station in orbit: one module of a ring, its walls flush grey panels on dark ribs, its
## section an octagon -- walls, chamfered corners, a low ceiling -- and a long viewport across
## the front on a planet below, its night side turned toward you, cities lit on its land. Under
## the lattice the deck is glass, and the planet is straight down through it. Through a pressure
## hatch in each side wall the ring's corridor runs on, its floor curving up and away overhead,
## the way a ring's does.
##
## Lit like a ship on its night cycle: cool LED coves along the chamfers, a row of downlights,
## the zones' own fittings, and the sun, low beyond the planet's limb, laying the viewport's
## frames across the deck.
##
## Three arrangements, three places in the orbit. NIGHT_SIDE, as first built. DAY_SIDE: over the
## lit side of the planet, the sun high to the left pouring through the viewports and laying
## their panes across the deck, the downlights turned down for the day, the planet's own blue
## coming up through the glass in the deck, and a cargo ship docked alongside, a tunnel run out
## to it from under the right-hand viewport. SUNRISE: the sun on the planet's limb ahead, the air
## round the limb a burning band of colour, the light coming in flat and long down the module to
## the zones, the lights still on for the night just ending, and the station's power truss
## standing across the view, black against the dawn.

## Floor to the top of the side walls, and to the ceiling between the chamfers: the live room's
## own height (Venue.LIVE_ROOM_HEIGHT), so the lattice's 3.4 m stands under the ceiling with a
## hand raised over it, and the neighbourhoods' banners hang clear under the ribs.
const WALL_TOP := 3.9
const CEILING := 5.0
## How far in from the side walls the ceiling starts: the chamfer's run, at 45 degrees.
const CHAMFER := 1.1
const WALL := 0.2
## Where the viewport wall stands, in front of the desk: the footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The viewport: four bays across the front, a pair either side of a pier behind the timeline,
## and the wide piers between each pair and the next where the roulette panel (left) and the door
## to its room (right) hang on the front wall (Venue.rig_roulette_spot / rig_roulette_door), so
## neither stands in front of the glass.
const SILL := 0.7
const HEAD := 3.2
const BAY := 2.8
const FRONT_BAYS := [-7.0, -1.9, 1.9, 7.0]
## The hatches: in each side wall, beside the desk. Their outside size, from hatch.glb.
const DOOR_Z := 0.8
const HATCH := Vector2(2.0, 2.7)
const HATCH_OPENING := Vector2(1.4, 2.25)
## The ring: its radius, and the corridor beyond each hatch (its width along z, its height),
## built a step at a time round the ring up to the angle where its own ceiling hides the rest.
const RING := 60.0
const RING_STEP := 2.5
const RING_TO := 80.0
const CORRIDOR := Vector2(2.4, 2.6)
## The frames the module is built on, this far apart.
const RIB_SPACING := 2.4
## The sun, beyond the planet's limb, in front and to the left: what the sky draws and what
## lights the deck through the viewport.
const SUN_DIR := Vector3(-0.85, 0.15, -0.5)

const MODELS := "res://assets/models/"

## The arrangements (Venue.VARIANTS).
const NIGHT_SIDE := 0
const DAY_SIDE := 1
const SUNRISE := 2
## The day's sun: high, to the left and ahead, so it comes in through the viewports at a slant
## and their panes fall across the deck toward the right.
const DAY_SUN := Vector3(-0.42, 0.55, -0.72)
## The dawn's: this far round to the left of straight ahead, a hair over the planet's limb
## (sun_dir() finds the limb), and the planet a little higher in the window than at night, so
## the limb -- and the light off it -- stand high enough to come in over the sill and down the
## deck rather than straight at the back wall.
const DAWN_AZIMUTH := 17.0
const DAWN_CENTRE := Vector3(0.0, -2800.0, -2000.0)
const PLANET_RADIUS := 3000.0
## The docked ship (station_ship.glb): its berthing port's face, and its heading.
const SHIP_AT := Vector3(9.0, -1.0, -22.0)
const SHIP_YAW := -0.3
const TUNNEL_R := 0.75
## The power truss (station_array.glb): its root, out of sight to the left, and the line it runs
## along in front of the module, its wings' faces toward the viewports.
const TRUSS_AT := Vector3(-80.0, 6.0, -64.0)

## How fast the station comes round its orbit, in radians a second: one turn in about a
## quarter of an hour, slow enough that the ground below is only seen to move if watched.
const ORBIT_RATE := 0.007
## How often the sky is turned: each turn redraws it, so not every frame.
const ORBIT_STEP := 0.1

var _sky_mat: ShaderMaterial
var orbit := 0.0
var _orbit_wait := 0.0
## What blinks outside: the ship's running lights by day, the truss's beacon at dawn.
var _blinkers: Array[StandardMaterial3D] = []
var _blink_colours: Array[Color] = []
var _blink_time := 0.0

## What follows the mix: the cool strips (cove, deck lip, riser edge), the downlights, the
## planet's glow, and a blacklit lattice -- the glass floor's lip going violet, weightless motes
## kicked up over it.
var _lip_mat: StandardMaterial3D
var _lip_base := Color.WHITE
var _cove_mat: StandardMaterial3D
var _cove_base := Color.WHITE
var _downlights: Array[SpotLight3D] = []
var _down_base := 1.0
var _planetshine: SpotLight3D
var _dust_mat: StandardMaterial3D
var _dust_base := Color.WHITE
var _uv_light: SpotLight3D
var _motes: GPUParticles3D


func venue_id() -> StringName:
	return &"station"


## White hull panels and blue status strips: the station's own fitted equipment.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.paint(Color(0.7, 0.72, 0.76), 0.42, 0.1)) \
			.with("chassis", GearStyle.paint(Color(0.07, 0.08, 0.1), 0.5, 0.3)) \
			.with("brushed", GearStyle.metal(Color(0.78, 0.8, 0.84), 0.25)) \
			.with("trim", GearStyle.glow(Color(0.3, 0.62, 1.0), 2.0)) \
			.with("end_cheek", GearStyle.paint(Color(0.55, 0.57, 0.62), 0.5, 0.1)) \
			.with("lamp_shade", GearStyle.paint(Color(0.8, 0.82, 0.86), 0.4, 0.1)) \
			.with("loom_band", GearStyle.glow(Color(0.3, 0.62, 1.0), 1.5)) \
			.with("knob_cap", GearStyle.paint(Color(0.12, 0.16, 0.22), 0.45, 0.2))


## A white hull panel with navy lettering and blue status arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.paint(Color(0.72, 0.74, 0.78), 0.42, 0.1)
	board.ink = Color(0.06, 0.1, 0.2)
	board.accent = Color(0.2, 0.5, 1.0)
	board.board_ink_fade = Color(0.4, 0.44, 0.52)


## Where the sun is, this arrangement.
func sun_dir() -> Vector3:
	match variant:
		DAY_SIDE:
			return DAY_SUN.normalized()
		SUNRISE:
			return _on_the_limb(deg_to_rad(DAWN_AZIMUTH), DAWN_CENTRE, PLANET_RADIUS)
	return SUN_DIR.normalized()


## The direction `azimuth` to the left of straight ahead in which the planet's limb is, nudged
## up by the sun's own radius so the disc's top is just clear of it.
static func _on_the_limb(azimuth: float, centre: Vector3, r: float) -> Vector3:
	var lo := -0.3
	var hi := 0.5
	var at := func(e: float) -> Vector3:
		return Vector3(-sin(azimuth) * cos(e), sin(e), -cos(azimuth) * cos(e))
	# Bisect for the elevation where the ray just grazes the sphere.
	for i in 40:
		var mid := (lo + hi) * 0.5
		var d: Vector3 = at.call(mid)
		var b := (-centre).dot(d)
		var hits := b * b - ((-centre).length_squared() - r * r) > 0.0 and b < 0.0
		if hits:
			lo = mid
		else:
			hi = mid
	return at.call(hi + deg_to_rad(0.3))


func dress(env: Environment, key: DirectionalLight3D) -> void:
	if variant == NIGHT_SIDE:
		_dress_night(env, key)
		return
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/station_orbit_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", sun_dir())
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.03, 0.04, 0.06)
	env.fog_depth_begin = 15.0
	env.fog_depth_end = 120.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.3
	var light := sun_dir()
	if variant == SUNRISE:
		# The light a few degrees steeper than the bead on the limb: dead level, it would only
		# ever reach the back wall; this way the panes fall long down the deck to the zones.
		var flat := Vector3(light.x, 0.0, light.z).normalized()
		light = (flat * cos(deg_to_rad(9.0)) + Vector3.UP * sin(deg_to_rad(9.0))).normalized()
	key.basis = Basis.looking_at(-light, Vector3.UP)
	# The panes' shadows reach the back of the module: further than the house's nine metres.
	key.directional_shadow_max_distance = 16.0
	if variant == DAY_SIDE:
		_sky_mat.set_shader_parameter("dawn", 0.0)
		_sky_mat.set_shader_parameter("stars", 0.15)
		# The lit planet fills four viewports: a step down, or from the seat it is the room.
		_sky_mat.set_shader_parameter("energy", 0.85)
		# The planet below fills the room with its blue.
		env.ambient_light_color = Color(0.42, 0.56, 0.78)
		env.ambient_light_energy = 0.24
		key.light_color = Color(1.0, 0.98, 0.94)
		key.light_energy = 1.25
		key.light_specular = 0.35
	else:
		_sky_mat.set_shader_parameter("dawn", 1.0)
		_sky_mat.set_shader_parameter("centre", DAWN_CENTRE)
		_sky_mat.set_shader_parameter("stars", 0.8)
		env.ambient_light_color = Color(0.34, 0.4, 0.6)
		env.ambient_light_energy = 0.1
		# Through the whole thickness of the air: the first light is gold, going on red.
		key.light_color = Color(1.0, 0.62, 0.32)
		key.light_energy = 1.3
		key.light_specular = 0.5


func _dress_night(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/space_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Turned every tenth of a second (_process): its reflections catch up over a few frames
	# rather than all in one.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.44, 0.62)
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The corridor going away round the ring: a little haze so its far end is not as sharp as
	# its near one. None on the sky: there is no air out there.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.03, 0.04, 0.06)
	env.fog_depth_begin = 15.0
	env.fog_depth_end = 120.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.3

	# The sun, unfiltered: white, hard-edged, low through the viewport.
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 0.75
	key.basis = Basis.looking_at(-SUN_DIR.normalized(), Vector3.UP)
	key.light_specular = 0.3


func lamp_colour(_index: int, authored: Color) -> Color:
	# The station's LEDs: a cool white.
	return authored.lerp(Color(0.86, 0.92, 1.0), 0.35)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.85


## The module is one open floor: the deck either side of the desk joins the far end.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 43): a ring of tuned hull
## panels between two of the hull's ribs, on the back wall between the kit and the lattice, the
## ring curving round whoever stands at it.
func instrument() -> Dictionary:
	return {"kind": &"hull_panels", "spot": back_wall_instrument(0.06)}


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), true)


## The glass in the deck, under the lattice: the matrix zone's floor, a hair inside it.
func glass_floor() -> Rect2:
	var box: AABB = zones()[&"matrix"]
	return Rect2(box.position.x + 0.04, box.position.z + 0.04, box.size.x - 0.08, box.size.z - 0.08)


## Where a point on the corridor's floor centre line is, `degrees` round the ring from a hatch on
## `side` (-1 left, 1 right): level at the hatch, rising as it goes.
func ring_point(side: float, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees)
	# From the hatch frame's outside face, so there is no gap between the two.
	var x0 := live_room_half() + WALL * 0.5 + 0.16
	return Vector3(side * (x0 + RING * sin(a)), RING * (1.0 - cos(a)), DOOR_Z)


## The strips and downlights swell with the mix and flash on each hit, the planet's glow comes up,
## the dust brightens, and the lattice's lip turns toward violet under a blacklight, motes kicked
## up over it. At rest all as authored.
func pulse(level: float) -> void:
	hear(level)
	var up := 1.0 + 0.5 * heard + 0.9 * heard_hit
	if _lip_mat != null:
		# Toward violet as it gets louder.
		_lip_mat.albedo_color = (_lip_base * up).lerp(Color(0.8, 0.4, 2.0), clampf(heard * 0.6 + heard_hit * 0.4, 0.0, 0.8))
	if _cove_mat != null:
		_cove_mat.albedo_color = _cove_base * (1.0 + 0.4 * heard + 0.7 * heard_hit)
	for l in _downlights:
		l.light_energy = _down_base * (1.0 + 0.25 * heard + 0.5 * heard_hit)
	if _planetshine != null:
		_planetshine.light_energy = 1.4 * (1.0 + 0.6 * heard + 0.8 * heard_hit)
	if _dust_mat != null:
		_dust_mat.albedo_color = Color(_dust_base.r * (1.0 + 0.6 * heard), _dust_base.g, _dust_base.b * (1.0 + 0.8 * heard + heard_hit),
				minf(_dust_base.a + 0.2 * heard + 0.2 * heard_hit, 1.0))
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("energy", (0.85 if variant == DAY_SIDE else 1.0) * (1.0 + 0.15 * heard + 0.3 * heard_hit))
	if _uv_light != null:
		_uv_light.light_energy = 3.0 * heard + 2.5 * heard_hit
	drive_sparks(_motes)


func _process(delta: float) -> void:
	orbit = fmod(orbit + delta * ORBIT_RATE, TAU)
	_orbit_wait -= delta
	if _orbit_wait <= 0.0 and _sky_mat != null:
		_orbit_wait = ORBIT_STEP
		_sky_mat.set_shader_parameter("spin", orbit)
	if not _blinkers.is_empty():
		# A short flash every second and a half, each light a beat after the last.
		_blink_time += delta
		for i in _blinkers.size():
			var on := fmod(_blink_time + i * 0.35, 1.5) < 0.12
			_blinkers[i].albedo_color = _blink_colours[i] * (6.0 if on else 0.6)


func _ready() -> void:
	var skin := _panels(Color(0.5, 0.52, 0.55), Vector2(1.2, 0.6), 0.04)
	var dark := _ribs()
	_lay_the_deck()
	_build_shell(skin, dark)
	_raise_ribs(dark)
	_build_corridors(dark)
	_light_the_module()
	_dress_zones()
	match variant:
		DAY_SIDE:
			_dock_the_ship()
			_shine_up_through_the_deck()
		SUNRISE:
			_run_the_truss()


## The station's grey skin (station_panel.gdshader).
func _panels(base: Color, size: Vector2, lights: float, metal := 0.2, roughness := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/station_panel.gdshader")
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("panel", size)
	m.set_shader_parameter("lights", lights)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("roughness_base", roughness)
	return m


func _ribs() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.105, 0.115)
	m.metallic = 0.45
	m.roughness = 0.5
	return m


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.06, 0.07, 0.08, 0.07)
	glass.roughness = 0.04
	# Little shine: the downlights' reflections in it read as white blobs over the planet.
	glass.metallic_specular = 0.1
	return glass


# --- the shell ------------------------------------------------------------------------------

## The deck: dark plates, in four pieces round the glass under the lattice; the glass, the
## deck's own depth showing round the hole, and a lit strip round its edge.
func _lay_the_deck() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var hole := glass_floor()
	var plates := _panels(Color(0.15, 0.16, 0.17), Vector2(0.6, 0.6), 0.0, 0.5, 0.45)
	var x0 := -half - 0.1
	var x1 := half + 0.1
	var z0 := FRONT - 0.1
	var z1 := back + 0.1
	# Front first: it is the piece under the gear, as wide as the room.
	for piece: Rect2 in [Rect2(x0, z0, x1 - x0, hole.position.y - z0),
			Rect2(x0, hole.end.y, x1 - x0, z1 - hole.end.y),
			Rect2(x0, hole.position.y, hole.position.x - x0, hole.size.y),
			Rect2(hole.end.x, hole.position.y, x1 - hole.end.x, hole.size.y)]:
		var floor_mesh := MeshInstance3D.new()
		floor_mesh.name = "Floor"
		var plane := PlaneMesh.new()
		plane.size = piece.size
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(piece.get_center().x, 0, piece.get_center().y)
		floor_mesh.material_override = plates
		add_child(floor_mesh)
	var pane := ZoneKit.block(self, Vector3(hole.size.x, 0.02, hole.size.y),
			Vector3(hole.get_center().x, -0.012, hole.get_center().y), _glass(), "FloorGlass")
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The deck's depth round the hole, 40 cm of structure, and the lit strip at its lip.
	var deep := 0.4
	var dark := _ribs()
	var c := hole.get_center()
	for spec in [[Vector3(hole.size.x + 0.08, deep, 0.04), Vector3(c.x, -deep * 0.5 - 0.003, hole.position.y - 0.02)],
			[Vector3(hole.size.x + 0.08, deep, 0.04), Vector3(c.x, -deep * 0.5 - 0.003, hole.end.y + 0.02)],
			[Vector3(0.04, deep, hole.size.y), Vector3(hole.position.x - 0.02, -deep * 0.5 - 0.003, c.y)],
			[Vector3(0.04, deep, hole.size.y), Vector3(hole.end.x + 0.02, -deep * 0.5 - 0.003, c.y)]]:
		ZoneKit.block(self, spec[0], spec[1], dark, "DeckEdge")
	_lip_mat = ZoneKit.glow(Color(0.35, 0.8, 1.0), 1.4)
	_lip_base = _lip_mat.albedo_color
	ZoneKit.floor_frame(self, hole.size + Vector2(0.06, 0.06), Vector3(c.x, 0.0, c.y), 0.03, _lip_mat)


## Side walls with a hatch in each, the viewport across the front, a plain back, the chamfers
## and the ceiling between them, and the end walls' upper parts closing the octagon.
func _build_shell(skin: Material, dark: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	# The sides take the corners, front and back.
	var z_from := FRONT - WALL
	var z_to := back + WALL
	# The hatch frames: bare machined steel, a step lighter than the panels round them.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.34, 0.37)
	steel.metallic = 0.7
	steel.roughness = 0.35
	for side in [-1.0, 1.0]:
		var x: float = side * (half + WALL * 0.5)
		var a := DOOR_Z - HATCH.x * 0.5
		var b := DOOR_Z + HATCH.x * 0.5
		ZoneKit.block(self, Vector3(WALL, WALL_TOP, a - z_from), Vector3(x, WALL_TOP * 0.5, (z_from + a) * 0.5), skin,
				"SideWall")
		ZoneKit.block(self, Vector3(WALL, WALL_TOP, z_to - b), Vector3(x, WALL_TOP * 0.5, (b + z_to) * 0.5), skin,
				"SideWall")
		ZoneKit.block(self, Vector3(WALL - 0.004, WALL_TOP - HATCH.y, HATCH.x), Vector3(x, (HATCH.y + WALL_TOP) * 0.5,
				DOOR_Z), skin, "OverHatch")
		var hatch := _model("hatch.glb", Vector3(x, 0, DOOR_Z), PI * 0.5,
				{"frame": steel, "hazard": _hazard(), "lamp": ZoneKit.glow(Color(1.0, 0.6, 0.2), 1.6)})
		hatch.name = "HatchLeft" if side < 0.0 else "HatchRight"
		# A pressure door of glass, shut, in the middle of the frame: the corridor is seen, not walked.
		var door := ZoneKit.block(self, Vector3(0.03, HATCH_OPENING.y + 0.1, HATCH_OPENING.x + 0.1),
				Vector3(x, 0.06 + HATCH_OPENING.y * 0.5, DOOR_Z), _glass(),
				"HatchGlassLeft" if side < 0.0 else "HatchGlassRight")
		door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The chamfer, from the wall's top in to the ceiling at 45 degrees, running into the
		# end walls at both ends.
		var run := CHAMFER * sqrt(2.0)
		var slab := ZoneKit.block(self, Vector3(run + 0.1, 0.1, z_to - z_from - 0.02), Vector3.ZERO, skin, "Chamfer")
		var mid := Vector2(side * (half - CHAMFER * 0.5), (WALL_TOP + CEILING) * 0.5)
		var out := Vector2(side, 1.0).normalized() * 0.05
		slab.position = Vector3(mid.x + out.x, mid.y + out.y, (z_from + z_to) * 0.5)
		slab.rotation.z = -side * PI * 0.25
	var ceiling := _panels(Color(0.3, 0.31, 0.33), Vector2(1.2, 0.6), 0.0)
	# The side walls, the chamfers and the ceiling each stop a step shorter into the end walls,
	# so their ends are never one plane.
	ZoneKit.block(self, Vector3((half - CHAMFER) * 2.0 + 0.1, 0.1, z_to - z_from - 0.04),
			Vector3(0, CEILING + 0.05, (z_from + z_to) * 0.5), ceiling, "Ceiling")
	# The viewport.
	var openings := ShellKit.wall_with_bays(self, "Front", Vector3(0, 0, FRONT - WALL * 0.5), Vector3(1, 0, 0),
			-half, half, FRONT_BAYS, BAY, SILL, HEAD, WALL_TOP, WALL, skin)
	for i in openings.size():
		ShellKit.glazed(self, "Viewport%d" % i, openings[i], Vector3(1, 0, 0), Vector2(BAY, HEAD - SILL), dark,
				_glass(), 4, 1.0, 0.06)
	ZoneKit.block(self, Vector3(half * 2.0, WALL_TOP, WALL), Vector3(0, WALL_TOP * 0.5, back + WALL * 0.5), skin,
			"BackWall")
	for z in [FRONT - WALL * 0.5, back + WALL * 0.5]:
		_end_wall_top(z, skin)


## The end wall's part above the side walls' tops: a trapezoid filling the octagon's top.
func _end_wall_top(z: float, material: Material) -> void:
	var half := live_room_half()
	var d := WALL * 0.5
	# Its foot a few millimetres into the wall below, its top just over the ceiling's underside.
	var outline := [Vector2(-half - 0.004, WALL_TOP - 0.004), Vector2(half + 0.004, WALL_TOP - 0.004),
			Vector2(half - CHAMFER + 0.05, CEILING + 0.02), Vector2(-half + CHAMFER - 0.05, CEILING + 0.02)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, e: Vector3) -> void:
		for v in [a, b, c, a, c, e]:
			st.add_vertex(v)
	var front: Array = outline.map(func(p: Vector2) -> Vector3: return Vector3(p.x, p.y, -d))
	var rear: Array = outline.map(func(p: Vector2) -> Vector3: return Vector3(p.x, p.y, d))
	# Both faces both ways round: whichever way the winding falls, each face is seen from inside.
	quad.call(front[0], front[1], front[2], front[3])
	quad.call(front[3], front[2], front[1], front[0])
	quad.call(rear[0], rear[1], rear[2], rear[3])
	quad.call(rear[3], rear[2], rear[1], rear[0])
	st.generate_normals()
	var top := MeshInstance3D.new()
	top.name = "EndWallTop"
	top.mesh = st.commit()
	top.position.z = z
	top.material_override = material
	add_child(top)


func _hazard() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/hazard.gdshader")
	return m


## The frames: a rib round the octagon every RIB_SPACING, proud of the skin -- up each wall, along
## each chamfer, across the ceiling -- except where a hatch is.
func _raise_ribs(dark: Material) -> void:
	var half := live_room_half()
	var z := FRONT + RIB_SPACING * 0.5
	while z < LIVE_ROOM_BACK - 0.3:
		for side in [-1.0, 1.0]:
			if absf(z - DOOR_Z) > HATCH.x * 0.5 + 0.1:
				ZoneKit.block(self, Vector3(0.08, WALL_TOP, 0.14), Vector3(side * (half - 0.04), WALL_TOP * 0.5, z), dark,
						"Rib")
			var run := CHAMFER * sqrt(2.0)
			# A hair thinner than the pieces either side of it, so the faces where they meet are
			# not one plane.
			var rib := ZoneKit.block(self, Vector3(run, 0.08, 0.12), Vector3.ZERO, dark, "Rib")
			var mid := Vector2(side * (half - CHAMFER * 0.5), (WALL_TOP + CEILING) * 0.5)
			var into := Vector2(-side, -1.0).normalized() * 0.04
			rib.position = Vector3(mid.x + into.x, mid.y + into.y, z)
			rib.rotation.z = -side * PI * 0.25
		ZoneKit.block(self, Vector3((half - CHAMFER) * 2.0, 0.08, 0.14), Vector3(0, CEILING - 0.04, z), dark, "Rib")
		z += RIB_SPACING


## The ring's corridor beyond each hatch: floor, ceiling and walls a step at a time round the
## ring, all one MultiMesh of the skin, a light strip down the middle of its ceiling, and a few
## lamps so its floor reads as it climbs away.
func _build_corridors(dark: Material) -> void:
	var skin_pieces: Array[Transform3D] = []
	var strips: Array[Transform3D] = []
	var step_len := RING * deg_to_rad(RING_STEP) + 0.02
	var w := CORRIDOR.x
	var h := CORRIDOR.y
	for side in [-1.0, 1.0]:
		var deg := RING_STEP * 0.5
		while deg < RING_TO:
			var at := ring_point(side, deg)
			var a := deg_to_rad(deg)
			# The corridor's frame here: along it, up (toward the ring's axis), and across (z).
			var along := Vector3(side * cos(a), sin(a), 0)
			var up := Vector3(-side * sin(a), cos(a), 0)
			# Across from the other two, so the frame stays a rotation on both sides.
			var across := along.cross(up)
			var basis := Basis(along, up, across)
			var piece := func(size: Vector3, offset: Vector3) -> Transform3D:
				return Transform3D(basis * Basis.from_scale(size), at + basis * offset)
			skin_pieces.append(piece.call(Vector3(step_len, 0.1, w + 0.2), Vector3(0, -0.05, 0)))
			skin_pieces.append(piece.call(Vector3(step_len, 0.1, w + 0.2), Vector3(0, h + 0.05, 0)))
			skin_pieces.append(piece.call(Vector3(step_len, h, 0.1), Vector3(0, h * 0.5, -w * 0.5 - 0.05)))
			skin_pieces.append(piece.call(Vector3(step_len, h, 0.1), Vector3(0, h * 0.5, w * 0.5 + 0.05)))
			strips.append(piece.call(Vector3(step_len * 0.7, 0.03, 0.18), Vector3(0, h - 0.016, 0)))
			deg += RING_STEP
		# Two lamps down the first stretch of it, where it can be seen from the room.
		for deg_at in [4.0, 12.0]:
			var lamp := OmniLight3D.new()
			lamp.name = "CorridorLight"
			var a := deg_to_rad(deg_at)
			lamp.position = ring_point(side, deg_at) + Vector3(-side * sin(a), cos(a), 0) * (h - 0.3)
			lamp.light_color = Color(0.7, 0.85, 1.0)
			lamp.light_energy = 1.2
			lamp.omni_range = 7.0
			lamp.shadow_enabled = false
			add_child(lamp)
	_multimesh("Corridor", BoxMesh.new(), skin_pieces, _panels(Color(0.45, 0.47, 0.5), Vector2(1.2, 0.6), 0.05))
	_multimesh("CorridorStrips", BoxMesh.new(), strips, ZoneKit.glow(Color(0.75, 0.88, 1.0), 1.3))


func _multimesh(label: String, mesh: Mesh, at: Array[Transform3D], material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
	var holder := MultiMeshInstance3D.new()
	holder.name = label
	holder.multimesh = mm
	holder.material_override = material
	add_child(holder)


## The downlights in the ceiling: three rows down the module's length, a pair either side of the
## middle row over the desk and the zones, every RIB_SPACING from the viewport to the back wall.
const DOWN_X := [-5.2, 0.0, 5.2]
const DOWN_FROM := -2.2


## LED coves along the chamfers' feet, and three rows of downlights in the ceiling.
func _light_the_module() -> void:
	var half := live_room_half()
	var length := LIVE_ROOM_BACK - FRONT
	var cove := ZoneKit.glow(Color(0.6, 0.85, 1.0), 1.2)
	_cove_mat = cove
	_cove_base = cove.albedo_color
	for side in [-1.0, 1.0]:
		var strip := ZoneKit.block(self, Vector3(0.03, 0.03, length - 0.2), Vector3(side * (half - 0.1), WALL_TOP - 0.08,
				(FRONT + LIVE_ROOM_BACK) * 0.5), cove, "Cove")
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var can := _ribs()
	# By day the sun does the work, and the ship's day cycle has the downlights turned down.
	# From a five-metre ceiling over twice the floor they throw harder than the old module's did.
	var down := 1.8 if variant == DAY_SIDE else 3.2
	_down_base = down
	var glass := glass_floor()
	for x: float in DOWN_X:
		var z := DOWN_FROM
		while z < LIVE_ROOM_BACK - 0.6:
			# Between the ribs, never on one; none over the glass, where the UV lamp hangs.
			var at := Vector3(x, CEILING - 0.03, z)
			if not glass.grow(0.3).has_point(Vector2(x, z)):
				var light := ZoneKit.spot_down(self, at, Color(0.86, 0.92, 1.0), down, 64.0, 8.0, can)
				light.name = "Downlight"
				_downlights.append(light)
			z += RIB_SPACING


# --- outside --------------------------------------------------------------------------------

## The cargo ship docked alongside by day, and the tunnel from the module to its berthing port:
## out from the front wall under the right-hand viewport's sill, ribbed, its far end a flange.
func _dock_the_ship() -> void:
	var white := _panels(Color(0.82, 0.83, 0.85), Vector2(1.0, 0.5), 0.0, 0.1, 0.5)
	var foil := StandardMaterial3D.new()
	foil.albedo_color = Color(0.85, 0.6, 0.2)
	foil.metallic = 1.0
	foil.roughness = 0.32
	foil.normal_enabled = true
	foil.normal_texture = Materials.grain("station_foil", 1.6, 2.5)
	foil.normal_scale = 0.6
	foil.uv1_triplanar = true
	foil.uv1_scale = Vector3.ONE * 0.8
	var dark := _ribs()
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.5, 0.5, 0.52)
	frame.metallic = 0.7
	frame.roughness = 0.35
	var windows := ZoneKit.glow(Color(1.0, 0.82, 0.55), 1.3)
	var lamps := {}
	for spec in [["red", Color(1.0, 0.1, 0.06)], ["green", Color(0.1, 1.0, 0.25)], ["white", Color(1.0, 1.0, 1.0)]]:
		var m := ZoneKit.glow(spec[1], 1.0)
		lamps[spec[0]] = m
		_blinkers.append(m)
		_blink_colours.append(spec[1])
	var ship := _model("station_ship.glb", SHIP_AT, SHIP_YAW, {"hull": white, "foil": foil, "dark": dark,
			"cell": _cells(Vector2(12, 8), Vector2(2, 1)), "frame": frame, "window": windows,
			"red": lamps["red"], "green": lamps["green"], "white": lamps["white"]})
	ship.name = "Ship"
	# The tunnel: straight back from the port along its facing to the module's front wall.
	var facing := Basis(Vector3.UP, SHIP_YAW) * Vector3.BACK
	var wall := FRONT - WALL - 0.002
	var reach := (wall - SHIP_AT.z) / facing.z
	var tunnel := MeshInstance3D.new()
	tunnel.name = "Tunnel"
	var tube := CylinderMesh.new()
	tube.top_radius = TUNNEL_R
	tube.bottom_radius = TUNNEL_R
	tube.height = reach
	tube.radial_segments = 28
	tunnel.mesh = tube
	tunnel.material_override = white
	var along := Basis(Vector3.UP, SHIP_YAW) * Basis(Vector3.RIGHT, PI * 0.5)
	tunnel.transform = Transform3D(along, SHIP_AT + facing * reach * 0.5)
	add_child(tunnel)
	# Its ribs, and the collar where it meets the wall.
	var k := 0.6
	while k < reach - 0.3:
		var rib := MeshInstance3D.new()
		rib.name = "TunnelRib"
		var ring := CylinderMesh.new()
		ring.top_radius = TUNNEL_R + 0.05
		ring.bottom_radius = TUNNEL_R + 0.05
		ring.height = 0.12
		ring.radial_segments = 28
		rib.mesh = ring
		rib.material_override = dark
		rib.transform = Transform3D(along, SHIP_AT + facing * k)
		add_child(rib)
		k += 1.4


## The planet's light up through the glass in the deck by day: a wide blue wash from below,
## lighting the lattice's air and the underside of whatever is built in it.
func _shine_up_through_the_deck() -> void:
	var hole := glass_floor()
	var up := SpotLight3D.new()
	_planetshine = up
	up.name = "Planetshine"
	up.light_color = Color(0.45, 0.65, 1.0)
	up.light_energy = 1.4
	up.spot_range = 7.0
	up.spot_angle = 60.0
	up.shadow_enabled = false
	up.light_specular = 0.1
	up.position = Vector3(hole.get_center().x, -1.2, hole.get_center().y)
	up.rotation_degrees = Vector3(90, 0, 0)
	add_child(up)


## The power truss across the view at dawn (station_array.glb): its girder level with the limb,
## running from out of sight on the left past the module, its wings' cells toward the viewports
## and black against the burning air, a red beacon on its end.
func _run_the_truss() -> void:
	var truss := StandardMaterial3D.new()
	truss.albedo_color = Color(0.62, 0.63, 0.66)
	truss.metallic = 0.6
	truss.roughness = 0.4
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.24, 0.25, 0.27)
	frame.metallic = 0.6
	frame.roughness = 0.45
	var radiator := StandardMaterial3D.new()
	radiator.albedo_color = Color(0.8, 0.8, 0.82)
	radiator.roughness = 0.55
	var beacon := ZoneKit.glow(Color(1.0, 0.12, 0.08), 1.0)
	_blinkers.append(beacon)
	_blink_colours.append(Color(1.0, 0.12, 0.08))
	var array := _model("station_array.glb", TRUSS_AT, 0.0, {"truss": truss, "frame": frame, "radiator": radiator,
			"cell": _cells(Vector2(14, 44), Vector2(2, 8)), "red": beacon})
	array.name = "Truss"


func _cells(cells: Vector2, bays: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/station_cells.gdshader")
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("bays", bays)
	return m


# --- the zones ------------------------------------------------------------------------------

## The zones in the station's own materials: a riser of deck plate edged in light, a booth of
## glass in the ribs' dark frame, the glass floor under the lattice (built with the deck) with
## dust hanging in the air over it, a white composite bench, and the keys.
func _dress_zones() -> void:
	var z := zones()
	var dark := _ribs()
	var plates := _panels(Color(0.18, 0.19, 0.2), Vector2(0.6, 0.6), 0.0, 0.5, 0.45)
	var composite := StandardMaterial3D.new()
	composite.albedo_color = Color(0.72, 0.74, 0.76)
	composite.roughness = 0.35

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var riser := Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, riser, ZoneKit.RISER_HEIGHT, plates, dark)
	# A line of light along its front edge, so the step up is seen.
	ZoneKit.block(drums, Vector3(riser.x, 0.02, 0.02), Vector3(0, ZoneKit.RISER_HEIGHT - 0.03, -riser.y * 0.5 - 0.011),
			_lip_mat, "EdgeLight")

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, dark, _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(0.86, 0.92, 1.0),
			1.3, 60.0, 3.2, dark)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var lattice: AABB = z[&"matrix"]
	_hang_dust(matrix, lattice.size)
	_uv_light = ZoneKit.spot_down(matrix, Vector3(0.3, CEILING - 0.05, 0), Color(0.55, 0.25, 1.0), 0.0, 50.0, 7.0)
	_uv_light.light_specular = 0.0
	var cold := Gradient.new()
	cold.set_color(0, Color(0.45, 0.9, 1.0))
	cold.set_color(1, Color(0.7, 0.35, 1.0))
	# Weightless: they leave the floor and keep going, none falling back.
	_motes = make_sparks("Motes", Vector3(lattice.get_center().x, 0.15, lattice.get_center().z),
			Vector3(lattice.size.x * 0.4, 0.05, lattice.size.z * 0.4),
			AABB(lattice.get_center() - Vector3(2.5, 0.3, 2.5), Vector3(5, 4, 5)), cold, 90, true)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, composite, dark)
	_dress_prop_shelf(composite, dark)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, dark, composite)


## Weightless dust over the glass floor, drifting every way at once and never settling: what
## says there is no down here, before anything is built in the lattice.
func _hang_dust(parent: Node3D, size: Vector3) -> void:
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 220
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = size * 0.5 - Vector3(0.2, 0.2, 0.2)
	motion.gravity = Vector3.ZERO
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 180.0
	motion.initial_velocity_min = 0.01
	motion.initial_velocity_max = 0.04
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.2
	motion.turbulence_influence_min = 0.01
	motion.turbulence_influence_max = 0.03
	dust.process_material = motion
	var mote := QuadMesh.new()
	mote.size = Vector2(0.016, 0.016)
	# A soft round speck, not a square: a radial fade on the quad.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var spot := GradientTexture2D.new()
	spot.gradient = fade
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5, 0.5)
	spot.fill_to = Vector2(1.0, 0.5)
	spot.width = 32
	spot.height = 32
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	shine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shine.albedo_texture = spot
	shine.albedo_color = Color(0.6, 0.85, 1.0, 0.8)
	_dust_mat = shine
	_dust_base = shine.albedo_color
	mote.material = shine
	dust.draw_pass_1 = mote
	dust.position = Vector3(0, size.y * 0.5, 0)
	dust.visibility_aabb = AABB(-size * 0.5, size)
	parent.add_child(dust)


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


## The mirror stands on the open deck at the footprint's left edge, framed like the viewport.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _ribs())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Orbital station: warning and status lights on white panels, cold and clean.
func track_palette() -> Array:
	return [
		Color(1.00, 0.23, 0.19), Color(1.00, 0.58, 0.00), Color(1.00, 0.80, 0.00), Color(0.66, 0.88, 0.19),
		Color(0.20, 0.78, 0.35), Color(0.19, 0.78, 0.75), Color(0.35, 0.78, 0.98), Color(0.23, 0.51, 1.00),
		Color(0.54, 0.36, 1.00), Color(0.88, 0.35, 0.85), Color(1.00, 0.35, 0.54), Color(0.82, 0.84, 0.87),
	]
