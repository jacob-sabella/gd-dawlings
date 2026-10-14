class_name GridVenue
extends Venue

## Synthwave: a black mirror floor ruled in neon, running out to a ring of wireframe mountains
## under a striped sun at dusk. The gear stands on the grid as it stands on parquet in the
## studio; the only thing marking the working floor is a brighter line where the walls would be.
##
## It moves to the music: the grid, the sun and the mountains all take `pulse`, so a loud chorus
## brightens the whole world a little and the floor throws a ripple out from the desk.

const FLOOR_EXTENT := 420.0
const SUN_DIR := Vector3(0.0, 0.11, -1.0)
## How far the floor runs past the room every way: in front toward the road (which begins just
## past it), out past the zones, behind them.
const OPEN_FLOOR := 3.0
## The palms near the room, there so they are in the shot from the chair and not only on the
## horizon. Walked round: the floor reaches some of them.
const NEAR_PALMS: Array[Vector3] = [Vector3(-7.5, 0, 1.5), Vector3(8.0, 0, -0.5), Vector3(-9.0, 0, 6.0),
		Vector3(10.0, 0, 7.0)]
## A palm trunk's footprint, half a side.
const TRUNK := 0.3

var _floor_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _wire_mat: ShaderMaterial
var _solids: Array[Node3D] = []
var _road_mat: ShaderMaterial
var _tower_mat: ShaderMaterial
var _palm_mat: ShaderMaterial
var _traffic: MultiMesh
var _cars: Array = []  # [x, z, speed, colour]
var _pyramids: Array[Node3D] = []
var _smoothed := 0.0

## The second arrangement (Venue.VARIANTS): the same road, but down an avenue between towers
## instead of out across a desert to the mountains.
const DOWNTOWN := 1
## A downtown block: one tower to a cell this size, jittered inside it and never wider than
## DOWNTOWN_TOWER_MAX, so no two towers ever touch or share a wall's plane.
const DOWNTOWN_CELL := 9.0
const DOWNTOWN_TOWER_MAX := 7.0
## The avenue the road runs down, kerb to kerb, and the block left clear round the room so its
## zones and the near palms stand in an open plaza rather than against a wall of windows.
const DOWNTOWN_AVENUE_HALF := 11.0
const DOWNTOWN_PLAZA := Rect2(-22.0, -12.0, 44.0, 36.0)
var _clock := 0.0

## The third arrangement: no road and no desert, but a sea. The floor is a pier standing over it,
## the sun goes down into it, and wire islands rise out of it.
const NEON_SEA := 2
## Where the water stands, under the pier's deck.
const SEA_LEVEL := -1.6
## How far the pier's deck runs past the walkable floor, so its rail stands on it.
const PIER_LIP := 0.25
## The palms on the pier, at the base width; they step out with the room on their own side.
const PIER_PALMS: Array[Vector3] = [Vector3(-7.5, 0, 1.5), Vector3(8.0, 0, -0.5), Vector3(-8.4, 0, 6.0),
		Vector3(8.4, 0, 8.6)]
## The sun lower than over the desert: its foot already in the sea.
const SEA_SUN_DIR := Vector3(0.0, 0.06, -1.0)
var _sea_mat: ShaderMaterial


func venue_id() -> StringName:
	return &"grid"


## Nothing to hang the roll board or the roulette panel on: they stand.
func back_wall_gear_stands() -> bool:
	return true


## Gloss black and neon: every edge a cyan line, like everything else in this world.
func gear_style() -> GearStyle:
	var gloss := GearStyle.paint(Color(0.025, 0.015, 0.04), 0.22, 0.5)
	gloss.normal_enabled = false
	return GearStyle.new() \
			.with("furniture", gloss) \
			.with("chassis", GearStyle.paint(Color(0.05, 0.03, 0.075), 0.4, 0.4)) \
			.with("brushed", GearStyle.metal(Color(0.62, 0.45, 0.72), 0.2)) \
			.with("trim", GearStyle.glow(Color(0.2, 1.0, 1.0), 3.0)) \
			.with("end_cheek", GearStyle.glow(Color(1.0, 0.2, 0.75), 0.45)) \
			.with("lamp_shade", GearStyle.glow(Color(1.0, 0.2, 0.75), 1.2)) \
			.with("loom_band", GearStyle.glow(Color(1.0, 0.2, 0.75), 1.5)) \
			.with("knob_cap", GearStyle.paint(Color(0.14, 0.02, 0.12), 0.2, 0.3))



func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/synthwave_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", SEA_SUN_DIR if variant == NEON_SEA else SUN_DIR)
	_sky_mat.set_shader_parameter("sun_energy", 1.1)
	_sky_mat.set_shader_parameter("horizon", Color(0.72, 0.12, 0.45))
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.20, 0.55)
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Haze into the horizon, so the grid does not stop at a hard line against the sky.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.55, 0.10, 0.42)
	env.fog_light_energy = 1.0
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 140.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0

	# Restrained, after "a bit too bright": a venue you work in for hours has to be one your
	# eyes can rest in. The neon should read as lines, not as a haze over the gear.
	env.glow_intensity = 0.65
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.set_glow_level(3, 1.0)
	env.set_glow_level(5, 0.8)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	if rich:
		env.ssr_enabled = true
		env.ssr_max_steps = 80
		env.ssr_fade_out = 1.2
		env.ssao_intensity = 1.2

	# The sun, low and behind the gear: a rim of hot pink along every edge facing the horizon.
	key.light_color = Color(1.0, 0.45, 0.62)
	key.light_energy = 0.9
	key.rotation_degrees = Vector3(-9.0, 180.0, 0.0)
	if variant == NEON_SEA:
		# Setting: lower, and the islands far enough out that the haze must reach further. The sun
		# is straight ahead of the desk here, the open sea all round it, and both are more of the
		# picture than over the desert: a little less of each, so the room is still for working in.
		key.rotation_degrees = Vector3(-3.5, 180.0, 0.0)
		env.fog_depth_end = 210.0
		_sky_mat.set_shader_parameter("sun_energy", 0.85)
		_sky_mat.set_shader_parameter("horizon", Color(0.58, 0.09, 0.36))
		_sky_mat.set_shader_parameter("upper", Color(0.12, 0.015, 0.26))
		env.tonemap_exposure = 0.74
	# A sun nine degrees up glints off a glossy floor in a streak that runs straight at you and
	# blooms into a white pillar in front of the gear. The sky already draws the sun; the floor
	# can reflect that through SSR without the light painting its own highlight on top.
	key.light_specular = 0.08


func lamp_colour(index: int, _authored: Color) -> Color:
	return Color(1.0, 0.2, 0.8) if index % 2 == 0 else Color(0.15, 0.85, 1.0)


func lamp_energy(_index: int, authored: float) -> float:
	# Over a near-mirror floor a lamp's highlight is a second, smaller sun; at full strength it
	# was a white hole in the grid.
	return authored * 0.6


func _ready() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GridFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_EXTENT, FLOOR_EXTENT)
	ground.mesh = plane
	if variant == NEON_SEA:
		# Only the pier's deck: past it is water.
		var deck := _pier_rect()
		plane.size = deck.size
		ground.position = Vector3(deck.get_center().x, 0, deck.get_center().y)
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = preload("res://core/venues/shaders/grid_floor.gdshader")
	var c := footprint_corners()
	# The pier's deck dimmer than the plain: the sea round it is ruled too, and both at full
	# strength filled the picture with lines.
	_floor_mat.set_shader_parameter("energy", 0.9 if variant == NEON_SEA else 1.5)
	_floor_mat.set_shader_parameter("footprint", Vector4(c[0].x, c[0].y, c[2].x, c[2].y))
	ground.material_override = _floor_mat
	add_child(ground)

	_wire_mat = ShaderMaterial.new()
	_wire_mat.shader = preload("res://core/venues/shaders/neon_wire.gdshader")
	_wire_mat.set_shader_parameter("energy", 1.9)

	if variant != DOWNTOWN and variant != NEON_SEA:
		var range_node := MeshInstance3D.new()
		range_node.name = "Mountains"
		range_node.mesh = mountains(23)
		range_node.material_override = _wire_mat
		range_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(range_node)

	# Two great solids turning slowly in the sky, the way every album cover of the genre has one.
	var specs := [[Vector3(-34, 24, -70), 7.0, Color(0.1, 0.9, 1.0)],
			[Vector3(40, 17, -58), 4.5, Color(1.0, 0.3, 0.85)]]
	if variant == DOWNTOWN:
		# Out there they would be inside a tower: up over the avenue instead, above the roofs.
		specs[0][0] = Vector3(-9, 52, -120)
		specs[1][0] = Vector3(10, 40, -84)
	for spec in specs:
		var solid := MeshInstance3D.new()
		solid.name = "Solid"
		solid.mesh = wireframe(_faceted_sphere())
		var m := _wire_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("line_colour", spec[2])
		m.set_shader_parameter("top_colour", spec[2])
		m.set_shader_parameter("fill", Color(0.03, 0.0, 0.06, 1.0))
		solid.material_override = m
		solid.position = spec[0]
		solid.scale = Vector3.ONE * spec[1]
		solid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(solid)
		_solids.append(solid)

	if variant == NEON_SEA:
		_flood()
		_build_pier()
		_raise_islands()
	else:
		_build_highway()
	_plant_palms()
	if variant == DOWNTOWN:
		_close_in_the_city()
	elif variant != NEON_SEA:
		_raise_city()
	_hang_pyramids()
	_dress_zones()


## The activity zones as the grid draws everything: black glass ruled in neon. No walls out here,
## so each zone is its own outline -- a riser edged in pink, a booth that is only its edges, the
## lattice's whole volume as a faint violet ghost of itself -- and reads from across the floor.
func _dress_zones() -> void:
	var z := zones()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.015, 0.01, 0.03)
	glass.metallic = 0.2
	glass.roughness = 0.12
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.5, 0.5, 0.6)
	chrome.metallic = 1.0
	chrome.roughness = 0.2
	var pink := ZoneKit.glow(Color(1.0, 0.2, 0.75), 1.6)
	var cyan := ZoneKit.glow(Color(0.15, 0.9, 1.0), 1.5)

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var deck := Vector2(z[&"drums"].size.x, z[&"drums"].size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, deck, ZoneKit.RISER_HEIGHT, glass, glass)
	_neon_edges(drums, Vector3(deck.x, ZoneKit.RISER_HEIGHT, deck.y),
			Vector3(0, ZoneKit.RISER_HEIGHT * 0.5, 0), pink, 0.018)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth: AABB = z[&"vocals"]
	_neon_edges(vocals, booth.size - Vector3(0.1, 0, 0.1), Vector3(0, booth.size.y * 0.5, 0), cyan,
			0.02)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT, chrome, ZoneKit.MIC_YAW)

	# The lattice's volume drawn at a third of the strength of everything else: a promise of the
	# thing, not the thing, and dim enough not to light the grid round it.
	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	_neon_edges(matrix, Vector3(3.0, 3.0, 3.0), Vector3(0, 1.5, 0),
			ZoneKit.glow(Color(0.65, 0.35, 1.0), 0.9), 0.012)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.04, glass, chrome)
	_neon_edges(bricks, ZoneKit.TABLE_TOP, Vector3(0, ZoneKit.TABLE_HEIGHT - ZoneKit.TABLE_TOP.y * 0.5, 0),
			cyan, 0.012)
	var shelf := _dress_prop_shelf(glass, chrome, Color(0.45, 0.85, 1.0))
	_neon_edges(shelf, Vector3(ZoneKit.SHELF.x, 0.035, ZoneKit.SHELF.z),
			Vector3(0, ZoneKit.SHELF.y - 0.0175, 0), cyan, 0.012)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, chrome, glass)
	# A tall slab of black glass behind the stand for the modules, edged in pink: the grid's
	# version of a wall to put a rack on, since it has no walls.
	var slab := Vector3(0.06, 1.1, 1.6)
	var at := Vector3(z[&"synth"].size.x * 0.5 - 0.05, 1.55, 0)
	ZoneKit.block(synth, slab, at, glass, "ModulePanel")
	_neon_edges(synth, slab, at, pink, 0.012)


## Out on the plain nothing stands round the room but more plain: you walk out beside the desk
## and in front of it, and round the zones, as well as between them.
func rooms() -> Array[Rect2]:
	return [open_floor(OPEN_FLOOR)]


## The riser, the table and the stand are glass and stop you; the booth is only its neon edges,
## and an invisible wall between them would be a wall you could not see. The palms near the room
## stand on the floor and are walked round.
func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), false)
	for palm in _near_palms():
		out.append({"c": Vector2(palm.x, palm.z), "h": Vector2.ONE * TRUNK, "a": 0.0, "top": 3.0})
	return out


func _neon_edges(parent: Node3D, size: Vector3, at: Vector3, material: Material,
		thick: float) -> void:
	var outline := MeshInstance3D.new()
	outline.name = "Neon"
	outline.mesh = ZoneKit.edges(size, thick)
	outline.position = at
	outline.material_override = material
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(outline)


func _process(delta: float) -> void:
	_clock += delta
	for i in _solids.size():
		_solids[i].rotate_y(delta * (0.12 + 0.05 * i))
		_solids[i].rotate_x(delta * 0.05)
	if _floor_mat != null and variant != NEON_SEA:
		# The floor runs toward you, slowly: you are always arriving at the horizon.
		_floor_mat.set_shader_parameter("travel", fmod(_clock * 0.12, 1000.0))
	if _road_mat != null:
		_road_mat.set_shader_parameter("travel", fmod(_clock * 0.12, 1000.0))
	_drive(delta)
	for i in _pyramids.size():
		var p := _pyramids[i]
		p.rotate_y(delta * (0.25 - 0.1 * i))
		p.position.y = p.get_meta(&"rest_y") + sin(_clock * 0.5 + i * 2.0) * 0.6


func pulse(level: float) -> void:
	# Fast up, slow down, like a meter's ballistics: a beat flashes, a gap does not blink.
	var k := 0.5 if level > _smoothed else 0.06
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	for m in [_floor_mat, _sky_mat, _wire_mat, _road_mat, _tower_mat, _palm_mat, _sea_mat]:
		if m != null:
			m.set_shader_parameter("pulse", _smoothed)


## A road out of the back of the room straight at the sun, so the eye has somewhere to go.
## Starts well clear of the working floor: nobody wants traffic through the patchbay.
const ROAD_START := -6.0
const ROAD_LENGTH := 400.0
const ROAD_HALF := 5.0
const LANES := [-3.75, -1.25, 1.25, 3.75]


func _build_highway() -> void:
	var road := MeshInstance3D.new()
	road.name = "Highway"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_HALF * 2.0 + 0.6, ROAD_LENGTH)
	road.mesh = plane
	# Above the grid by a centimetre, which nobody can see and which keeps the two floors from
	# fighting over the same plane.
	road.position = Vector3(0, 0.01, ROAD_START - ROAD_LENGTH * 0.5)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = preload("res://core/venues/shaders/highway.gdshader")
	_road_mat.set_shader_parameter("half_width", ROAD_HALF)
	_road_mat.set_shader_parameter("energy", 2.0)
	road.material_override = _road_mat
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)

	# Traffic: red tail lights going away on the right, white heads coming home on the left.
	var light := BoxMesh.new()
	light.size = Vector3(0.22, 0.10, 1.8)
	_traffic = MultiMesh.new()
	_traffic.transform_format = MultiMesh.TRANSFORM_3D
	_traffic.use_colors = true
	_traffic.mesh = light
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 36:
		var lane: float = LANES[i % LANES.size()]
		var away := lane > 0.0
		_cars.append([lane, ROAD_START - rng.randf() * ROAD_LENGTH * 0.8,
				rng.randf_range(18.0, 34.0) * (1.0 if away else -1.0),
				Color(1.0, 0.08, 0.2) if away else Color(0.9, 0.95, 1.0)])
	_traffic.instance_count = _cars.size() * 2
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Traffic"
	mmi.multimesh = _traffic
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://core/venues/shaders/streak.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-ROAD_HALF, 0, ROAD_START - ROAD_LENGTH), Vector3(ROAD_HALF * 2, 2, ROAD_LENGTH))
	add_child(mmi)
	_drive(0.0)


func _drive(delta: float) -> void:
	if _traffic == null:
		return
	var far := ROAD_START - ROAD_LENGTH * 0.8
	for i in _cars.size():
		var car: Array = _cars[i]
		car[1] -= car[2] * delta
		if car[1] < far:
			car[1] = ROAD_START - 2.0
		elif car[1] > ROAD_START - 2.0:
			car[1] = far
		for k in 2:
			var x: float = car[0] + (k * 2 - 1) * 0.55
			_traffic.set_instance_transform(i * 2 + k,
					Transform3D(Basis.IDENTITY, Vector3(x, 0.55, car[1])))
			_traffic.set_instance_color(i * 2 + k, car[3])


func _plant_palms() -> void:
	var source := load("res://assets/models/palms.glb") as PackedScene
	if source == null:
		return
	var holder := source.instantiate()
	var meshes: Array[ArrayMesh] = []
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		meshes.append(wireframe((node as MeshInstance3D).mesh))
	holder.free()
	if meshes.is_empty():
		return
	_palm_mat = _wire_mat.duplicate() as ShaderMaterial
	_palm_mat.set_shader_parameter("line_colour", Color(1.0, 0.2, 0.7))
	_palm_mat.set_shader_parameter("top_colour", Color(0.15, 1.0, 0.85))
	_palm_mat.set_shader_parameter("top", 7.0)
	_palm_mat.set_shader_parameter("width", 1.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var spots: Array[Vector3] = []
	if variant == NEON_SEA:
		# No boulevard: the pier's own, and a clump on the low island off to the left.
		spots.append_array(_near_palms())
		for at in [Vector3(-27.0, 0, -33.0), Vector3(-24.5, 0, -35.5), Vector3(-29.5, 0, -36.0)]:
			spots.append(at + Vector3(0, SEA_LEVEL + 1.9, 0))
	else:
		for i in 12:
			var z := ROAD_START - 8.0 - i * 15.0
			spots.append(Vector3(-ROAD_HALF - 2.5, 0, z))
			spots.append(Vector3(ROAD_HALF + 2.5, 0, z - 7.5))
		spots.append_array(NEAR_PALMS)
	for i in spots.size():
		var palm := MeshInstance3D.new()
		palm.name = "Palm"
		palm.mesh = meshes[i % meshes.size()]
		palm.material_override = _palm_mat
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		palm.position = spots[i]
		# Leaning in toward the road, mostly, the way they are planted along a boulevard.
		var inward := PI if spots[i].x > 0.0 else 0.0
		palm.rotation.y = inward + rng.randf_range(-0.6, 0.6)
		palm.scale = Vector3.ONE * rng.randf_range(0.8, 1.2)
		add_child(palm)


func _raise_city() -> void:
	_tower_mat = ShaderMaterial.new()
	_tower_mat.shader = preload("res://core/venues/shaders/tower.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Two districts either side of the road, laid out on a coarse grid with jitter inside each
	# cell -- towers in the same cell never touch, so no two walls ever share a plane.
	for district in [[-62.0, -118.0], [42.0, -126.0]]:
		for gx in 5:
			for gz in 4:
				if rng.randf() < 0.25:
					continue
				var w := rng.randf_range(3.0, 6.0)
				var d := rng.randf_range(3.0, 6.0)
				var h := rng.randf_range(10.0, 46.0) * (1.0 - absf(gx - 2.0) * 0.15)
				var tower := MeshInstance3D.new()
				tower.name = "Tower"
				var box := BoxMesh.new()
				box.size = Vector3(w, h, d)
				tower.mesh = box
				tower.material_override = _tower_mat
				tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tower.position = Vector3(district[0] + gx * 8.0 + rng.randf_range(-0.8, 0.8),
						h * 0.5, district[1] + gz * 8.0 + rng.randf_range(-0.8, 0.8))
				tower.set_instance_shader_parameter(&"roof", h)
				add_child(tower)


## Downtown: the city all round, near enough to read the windows. Taller toward the avenue, so
## the road is a canyon and the sun sits at the end of it. One MultiMesh: three hundred towers,
## one draw.
func _close_in_the_city() -> void:
	_tower_mat = ShaderMaterial.new()
	_tower_mat.shader = preload("res://core/venues/shaders/tower.gdshader")
	_tower_mat.set_shader_parameter("roof_from_custom", true)
	# Near windows are big windows: at the highway's strength a block away was a wall of glare.
	_tower_mat.set_shader_parameter("energy", 1.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var towers: Array[Transform3D] = []
	var roofs: Array[float] = []
	var jitter := (DOWNTOWN_CELL - DOWNTOWN_TOWER_MAX) * 0.5
	for gx in range(-7, 8):
		for gz in range(-22, 5):
			var at := Vector2(gx * DOWNTOWN_CELL, gz * DOWNTOWN_CELL)
			var reach := DOWNTOWN_CELL * 0.5
			if absf(at.x) - reach < DOWNTOWN_AVENUE_HALF and at.y < 0.0:
				continue
			if DOWNTOWN_PLAZA.grow(reach).has_point(at):
				continue
			if rng.randf() < 0.15:
				continue
			var w := rng.randf_range(4.0, DOWNTOWN_TOWER_MAX)
			var d := rng.randf_range(4.0, DOWNTOWN_TOWER_MAX)
			var near := 1.0 - clampf((absf(at.x) - DOWNTOWN_AVENUE_HALF) / 50.0, 0.0, 1.0)
			var h := rng.randf_range(14.0, 30.0) + near * rng.randf_range(10.0, 45.0)
			var centre := Vector3(at.x + rng.randf_range(-jitter, jitter), h * 0.5,
					at.y + rng.randf_range(-jitter, jitter))
			towers.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), centre))
			roofs.append(h)
	var city := MultiMesh.new()
	city.transform_format = MultiMesh.TRANSFORM_3D
	city.use_custom_data = true
	city.mesh = BoxMesh.new()
	city.instance_count = towers.size()
	for i in towers.size():
		city.set_instance_transform(i, towers[i])
		city.set_instance_custom_data(i, Color(roofs[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Downtown"
	mmi.multimesh = city
	mmi.material_override = _tower_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _hang_pyramids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var colours := [Color(1.0, 0.85, 0.2), Color(0.2, 1.0, 0.9), Color(1.0, 0.3, 0.8)]
	var spots := [Vector3(-16, 7, -22), Vector3(19, 9, -28), Vector3(-4, 14, -48)]
	if variant == DOWNTOWN:
		# Strung down the avenue, clear of the towers either side of it.
		spots = [Vector3(-6, 9, -24), Vector3(6.5, 12, -36), Vector3(-2, 17, -58)]
	for i in spots.size():
		var p := MeshInstance3D.new()
		p.name = "Pyramid"
		p.mesh = pyramid()
		var m := _wire_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("line_colour", colours[i])
		m.set_shader_parameter("top_colour", colours[(i + 1) % colours.size()])
		m.set_shader_parameter("top", 1.0)
		p.material_override = m
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = spots[i]
		p.scale = Vector3.ONE * rng.randf_range(2.0, 3.5)
		p.set_meta(&"rest_y", spots[i].y)
		add_child(p)
		_pyramids.append(p)


## A square pyramid, apex up, with no diagonals across its base: a wireframe shows every edge
## it has, so a pyramid built from a cone would draw lines no pyramid has.
static func pyramid() -> ArrayMesh:
	var apex := Vector3(0, 1.0, 0)
	var b := [Vector3(-0.7, -0.4, -0.7), Vector3(0.7, -0.4, -0.7), Vector3(0.7, -0.4, 0.7),
			Vector3(-0.7, -0.4, 0.7)]
	var tris := PackedVector3Array()
	for i in 4:
		tris.append_array([b[i], b[(i + 1) % 4], apex])
	# Inverted twin below, an octahedron's lower half, so it reads as a crystal from beneath.
	var low := Vector3(0, -1.4, 0)
	for i in 4:
		tris.append_array([b[(i + 1) % 4], b[i], low])
	return _barycentric(tris)


## A ring of jagged ridges, low where the sun sets and tall to either side of it, so the sun
## sits in a valley with its stripes showing.
static func mountains(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var segments := 96
	var profile := [0.0, 0.55, 1.0, 0.75, 0.35, 0.0]
	var rows := profile.size()
	var grid := []
	for i in segments + 1:
		var a := TAU * float(i % segments) / float(segments)
		# Angle away from straight ahead (-Z), 0..PI.
		var off := absf(wrapf(a, -PI, PI))
		var amp := lerpf(2.5, 15.0, smoothstep(0.12, 0.7, off / PI)) * rng.randf_range(0.6, 1.25)
		var column := []
		for j in rows:
			var r := 85.0 + float(j) * 9.0 + rng.randf_range(-2.0, 2.0)
			var y: float = amp * profile[j] * rng.randf_range(0.7, 1.15)
			column.append(Vector3(sin(a) * r, y, -cos(a) * r))
		grid.append(column)
	var tris := PackedVector3Array()
	for i in segments:
		for j in rows - 1:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			tris.append_array([a, b, c, a, c, d])
	return _barycentric(tris)


static func wireframe(source: Mesh) -> ArrayMesh:
	var tris := PackedVector3Array()
	var arrays := source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		tris = verts
	else:
		for i in index:
			tris.append(verts[i])
	return _barycentric(tris)


static func _faceted_sphere() -> Mesh:
	var s := SphereMesh.new()
	s.radial_segments = 8
	s.rings = 4
	s.radius = 1.0
	s.height = 2.0
	return s


static func _barycentric(tris: PackedVector3Array) -> ArrayMesh:
	var corners := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	var colours := PackedColorArray()
	var normals := PackedVector3Array()
	for t in tris.size() / 3:
		var n := (tris[t * 3 + 1] - tris[t * 3]).cross(tris[t * 3 + 2] - tris[t * 3]).normalized()
		for k in 3:
			colours.append(corners[k])
			normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A free-standing mirror outlined in two neon tubes, cyan outside pink, on a black lacquer
## stand -- the dressing-room mirror of a club that only exists at 3am in 1986.
func _dress_wardrobe(board: Wardrobe) -> void:
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color(0.02, 0.015, 0.03)
	lacquer.roughness = 0.12
	lacquer.metallic = 0.4
	board.board_material = lacquer
	board.ink = Color(1.0, 0.75, 0.95)
	board.accent = Color(0.2, 0.95, 1.0)


func _frame_mirror(mirror: Mirror) -> void:
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color(0.02, 0.015, 0.03)
	lacquer.roughness = 0.12
	lacquer.metallic = 0.4
	Venue.frame_bars(mirror, 0.05, 0.04, 0.008, lacquer)
	for tube in [[0.0, 0.012, Color(1.0, 0.3, 0.85)], [0.05, 0.010, Color(0.1, 0.9, 1.0)]]:
		var neon := StandardMaterial3D.new()
		neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		neon.albedo_color = tube[2] * 2.2
		# The pink just inside the glass's edge; the cyan round the outside of the lacquer.
		Venue.frame_bars(mirror, tube[1], tube[1], 0.016, neon, -tube[0] + 0.004)
	var back := MeshInstance3D.new()
	var board := BoxMesh.new()
	# Inside the lacquer's outer edge, never flush with it.
	board.size = Vector3(mirror.glass_size.x + 0.08, mirror.glass_size.y + 0.08, 0.014)
	back.mesh = board
	back.material_override = lacquer
	back.position = Vector3(0, 0, -0.028)
	mirror.add_child(back)
	# Two splayed legs behind it, down to the floor.
	var floor_y := -mirror.transform.origin.y
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var rod := BoxMesh.new()
		var reach := Vector3(side * 0.22, floor_y, -0.32)
		var from := Vector3(side * (mirror.glass_size.x * 0.5 - 0.04), 0.0, -0.04)
		rod.size = Vector3(0.025, 0.025, (reach - from).length())
		leg.mesh = rod
		leg.material_override = lacquer
		leg.transform = Transform3D(Basis.looking_at(reach - from, Vector3.UP), from + (reach - from) * 0.5)
		mirror.add_child(leg)


## The tracks' colours here (TrackColours), in its STANDARD order.
## Synthwave: neon at full tilt, every one a light.
func track_palette() -> Array:
	return [
		Color(1.00, 0.16, 0.33), Color(1.00, 0.48, 0.10), Color(1.00, 0.88, 0.10), Color(0.71, 1.00, 0.10),
		Color(0.16, 1.00, 0.48), Color(0.10, 1.00, 0.84), Color(0.10, 0.84, 1.00), Color(0.23, 0.42, 1.00),
		Color(0.63, 0.23, 1.00), Color(1.00, 0.16, 0.88), Color(1.00, 0.35, 0.71), Color(0.78, 0.71, 1.00),
	]


## The palms near the room that stop you: the boulevard's four out on the plain, or the pier's,
## stepped out with the room so they stay on its deck.
func _near_palms() -> Array[Vector3]:
	if variant != NEON_SEA:
		return NEAR_PALMS
	var out: Array[Vector3] = []
	for at in PIER_PALMS:
		out.append(at + Vector3(signf(at.x) * _grow(), 0, 0))
	return out


## The pier's deck, on the floor plan: the walkable floor and its lip, where the rail stands.
func _pier_rect() -> Rect2:
	return open_floor(OPEN_FLOOR).grow(PIER_LIP)


## Neon sea: the water, from under the pier out to the horizon. One mesh, its rows close together
## by the pier and opening out with distance, so the swell has vertices where it is seen and the
## horizon costs nothing.
func _flood() -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = sea_mesh(90, 1500.0)
	sea.position = Vector3(0, SEA_LEVEL, 0)
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = preload("res://core/venues/shaders/grid_sea.gdshader")
	_sea_mat.set_shader_parameter("sun_dir", SEA_SUN_DIR)
	sea.material_override = _sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The swell lifts it off its flat plan; the plan's box would cull it at the wrong moment.
	sea.custom_aabb = AABB(Vector3(-1500, -2, -1500), Vector3(3000, 4, 3000))
	add_child(sea)


## A square of water `half` metres each way, `rings` rows out from the middle on each side: the
## rows a metre or so apart by the pier and a hundred apart at the horizon. Indexed triangles,
## flat (the shader raises the swell).
static func sea_mesh(rings: int, half: float) -> ArrayMesh:
	var coords := PackedFloat32Array()
	for i in range(-rings, rings + 1):
		var t := float(i) / rings
		coords.append(signf(t) * (60.0 * absf(t) + (half - 60.0) * pow(absf(t), 3.0)))
	var n := coords.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in n:
		for x in n:
			verts.append(Vector3(coords[x], 0, coords[z]))
			normals.append(Vector3.UP)
	var index := PackedInt32Array()
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			index.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The pier: the floor's black glass laid on a deck standing on piles over the water, a neon lip
## round its edge, a rail on posts round all of it, and a ladder down to the water off the right.
func _build_pier() -> void:
	var deck := _pier_rect()
	var mid := Vector3(deck.get_center().x, 0, deck.get_center().y)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.015, 0.01, 0.03)
	glass.metallic = 0.2
	glass.roughness = 0.12
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.5, 0.5, 0.6)
	chrome.metallic = 1.0
	chrome.roughness = 0.2
	var pink := ZoneKit.glow(Color(1.0, 0.2, 0.75), 2.2)
	var cyan := ZoneKit.glow(Color(0.15, 0.9, 1.0), 1.8)

	# The deck's slab, its top just under the floor so the two never share a plane.
	var slab_h := 0.32
	ZoneKit.block(self, Vector3(deck.size.x, slab_h, deck.size.y), mid + Vector3(0, -0.003 - slab_h * 0.5, 0),
			glass, "PierDeck")
	# The lip: a pink tube round the slab's edge, a hair out from it. The ends along x run past the
	# corners; those along z stop inside them and stand a millimetre less tall, so no two faces meet.
	var tube := 0.035
	for side in [-1.0, 1.0]:
		var lip := ZoneKit.block(self, Vector3(deck.size.x + tube * 2.0 + 0.02, tube, tube),
				mid + Vector3(0, -0.07, side * (deck.size.y * 0.5 + 0.01 + tube * 0.5)), pink, "PierLip")
		lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var end := ZoneKit.block(self, Vector3(tube, tube - 0.002, deck.size.y),
				mid + Vector3(side * (deck.size.x * 0.5 + 0.01 + tube * 0.5), -0.07, 0), pink, "PierLip")
		end.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Piles down into the water, every few metres under the edge and in rows beneath, braced
	# across under the deck. One MultiMesh each.
	var pile_at: Array[Vector3] = []
	var cols := int(ceil(deck.size.x / 3.2))
	var rows := int(ceil(deck.size.y / 3.2))
	for i in cols + 1:
		for j in rows + 1:
			var inset := Vector2(0.35, 0.35)
			var x := lerpf(deck.position.x + inset.x, deck.end.x - inset.x, float(i) / cols)
			var z := lerpf(deck.position.y + inset.y, deck.end.y - inset.y, float(j) / rows)
			pile_at.append(Vector3(x, 0, z))
	var deep := 6.0
	var pile := CylinderMesh.new()
	pile.top_radius = 0.14
	pile.bottom_radius = 0.16
	pile.height = deep
	pile.radial_segments = 12
	var piles := MultiMesh.new()
	piles.transform_format = MultiMesh.TRANSFORM_3D
	piles.mesh = pile
	piles.instance_count = pile_at.size()
	# A neon collar on each, a hand above the highest the swell reaches.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.15
	ring.outer_radius = 0.19
	ring.rings = 16
	ring.ring_segments = 6
	var collars := MultiMesh.new()
	collars.transform_format = MultiMesh.TRANSFORM_3D
	collars.mesh = ring
	collars.instance_count = pile_at.size()
	for k in pile_at.size():
		var at := pile_at[k]
		piles.set_instance_transform(k, Transform3D(Basis.IDENTITY, at + Vector3(0, -slab_h - deep * 0.5, 0)))
		collars.set_instance_transform(k, Transform3D(Basis.IDENTITY, at + Vector3(0, SEA_LEVEL + 0.75, 0)))
	_bank("Piles", piles, glass)
	_bank("PileCollars", collars, cyan)

	# Cross-bracing between the edge piles, an X in each bay along the four sides.
	var brace := BoxMesh.new()
	brace.size = Vector3(0.07, 0.07, 1.0)
	var braces := MultiMesh.new()
	braces.transform_format = MultiMesh.TRANSFORM_3D
	braces.mesh = brace
	var xs: Array[Transform3D] = []
	var top := -slab_h - 0.1
	var low := SEA_LEVEL + 0.55
	for edge in [[0, 0, 1, 0], [0, rows, 1, 0], [0, 0, 0, 1], [cols, 0, 0, 1]]:
		var count: int = cols if edge[2] == 1 else rows
		for b in count:
			var a := pile_at[(edge[0] + b * edge[2]) * (rows + 1) + edge[1] + b * edge[3]]
			var c := pile_at[(edge[0] + (b + 1) * edge[2]) * (rows + 1) + edge[1] + (b + 1) * edge[3]]
			for diag in [[top, low], [low, top]]:
				var from := Vector3(a.x, diag[0], a.z)
				var to := Vector3(c.x, diag[1], c.z)
				var along := to - from
				var basis := Basis.looking_at(along, Vector3.UP).scaled_local(Vector3(1, 1, along.length()))
				xs.append(Transform3D(basis, (from + to) * 0.5))
	braces.instance_count = xs.size()
	for k in xs.size():
		braces.set_instance_transform(k, xs[k])
	_bank("Braces", braces, chrome)

	# The rail, round the whole deck: chrome posts, and a cyan tube along their tops.
	var rail_h := 0.95
	var post := BoxMesh.new()
	post.size = Vector3(0.04, rail_h, 0.04)
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	posts.mesh = post
	var post_at: Array[Vector3] = []
	var edge_in := PIER_LIP * 0.5
	var r := deck.grow(-edge_in)
	var along_x := int(ceil(r.size.x / 1.8))
	var along_z := int(ceil(r.size.y / 1.8))
	for i in along_x + 1:
		var x := lerpf(r.position.x, r.end.x, float(i) / along_x)
		post_at.append(Vector3(x, 0, r.position.y))
		post_at.append(Vector3(x, 0, r.end.y))
	for j in range(1, along_z):
		var z := lerpf(r.position.y, r.end.y, float(j) / along_z)
		post_at.append(Vector3(r.position.x, 0, z))
		post_at.append(Vector3(r.end.x, 0, z))
	posts.instance_count = post_at.size()
	for k in post_at.size():
		posts.set_instance_transform(k, Transform3D(Basis.IDENTITY, post_at[k] + Vector3(0, rail_h * 0.5, 0)))
	_bank("RailPosts", posts, chrome)
	var bar := 0.03
	for side in [-1.0, 1.0]:
		var along := ZoneKit.block(self, Vector3(r.size.x + bar * 2.0, bar, bar),
				Vector3(r.get_center().x, rail_h + bar * 0.5, r.get_center().y + side * r.size.y * 0.5), cyan, "Rail")
		along.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var across := ZoneKit.block(self, Vector3(bar, bar - 0.002, r.size.y - bar),
				Vector3(r.get_center().x + side * r.size.x * 0.5, rail_h + bar * 0.5, r.get_center().y), cyan, "Rail")
		across.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A ladder down to the water off the right-hand side, beside the hoop's end of the deck.
	var ladder := Node3D.new()
	ladder.name = "Ladder"
	ladder.position = Vector3(deck.end.x + 0.06, 0, deck.get_center().y - 1.0)
	add_child(ladder)
	var reach := 0.0 - (SEA_LEVEL - 0.8)
	for s in [-0.24, 0.24]:
		ZoneKit.block(ladder, Vector3(0.04, reach + 0.9, 0.04), Vector3(0, (0.9 - reach) * 0.5 + 0.0, s), chrome,
				"LadderRail")
	for k in int(reach / 0.3):
		ZoneKit.block(ladder, Vector3(0.03, 0.03, 0.44), Vector3(0, -0.15 - k * 0.3, 0), chrome, "Rung")


func _bank(called: String, multimesh: MultiMesh, material: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = called
	mmi.multimesh = multimesh
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Wire islands out in the sea, none on the sun's bearing, each with its reflection hung under the
## waterline where the see-through sea shows it, dimmer and drawn at the same bearings.
const ISLANDS := [
	# [centre on the plan, radius, height, seed, flat top]
	[Vector2(-27.0, -34.0), 7.0, 1.9, 3, true],
	[Vector2(-62.0, -88.0), 24.0, 17.0, 11, false],
	[Vector2(-38.0, -120.0), 16.0, 9.0, 12, false],
	[Vector2(48.0, -72.0), 15.0, 12.0, 17, false],
	[Vector2(96.0, -140.0), 30.0, 22.0, 19, false],
	[Vector2(-110.0, 20.0), 26.0, 14.0, 23, false],
	[Vector2(90.0, 40.0), 20.0, 10.0, 29, false],
]


func _raise_islands() -> void:
	var colours := [[Color(1.0, 0.2, 0.75), Color(0.15, 1.0, 0.9)], [Color(0.15, 0.9, 1.0), Color(1.0, 0.3, 0.85)]]
	for i in ISLANDS.size():
		var spec: Array = ISLANDS[i]
		var plan: Vector2 = spec[0]
		var pair: Array = colours[i % 2]
		var m := _wire_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("line_colour", pair[0])
		m.set_shader_parameter("top_colour", pair[1])
		m.set_shader_parameter("top", SEA_LEVEL + float(spec[2]))
		var shown := MeshInstance3D.new()
		shown.name = "Island"
		shown.mesh = island(spec[3], spec[1], spec[2], spec[4], true)
		shown.material_override = m
		shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shown.position = Vector3(plan.x, SEA_LEVEL, plan.y)
		add_child(shown)
		# Upside down under the water, without the skirt that only keeps the shore under the swell.
		var below := MeshInstance3D.new()
		below.name = "IslandReflection"
		below.mesh = island(spec[3], spec[1], spec[2], spec[4], false)
		var dim := m.duplicate() as ShaderMaterial
		# Its heights run down from the water, which the wire's height gradient does not read:
		# one colour, the summit's.
		dim.set_shader_parameter("energy", 4.0)
		dim.set_shader_parameter("line_colour", pair[1])
		dim.set_shader_parameter("top_colour", pair[1])
		below.material_override = dim
		below.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		below.position = Vector3(plan.x, SEA_LEVEL - 0.05, plan.y)
		below.scale = Vector3(1, -1, 1)
		add_child(below)


## A jagged wire island, `radius` across its shore and `height` at its peak: rings climbing in to
## a crooked summit, or, `flat`, a low one with a level top for palms. `skirt` carries the shore
## down under the swell's troughs.
static func island(seed: int, radius: float, height: float, flat: bool, skirt: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var segments := 18
	var levels := [[1.0, 0.0], [0.72, 0.35], [0.45, 0.72], [0.2, 0.95]] if not flat \
			else [[1.0, 0.0], [0.82, 0.7], [0.55, 1.0]]
	var peak := Vector3(rng.randf_range(-0.15, 0.15) * radius, height, rng.randf_range(-0.15, 0.15) * radius)
	if flat:
		peak = Vector3(0, height, 0)
	var rings := []
	if skirt:
		var base := []
		for i in segments:
			var a := TAU * i / segments
			base.append(Vector3(sin(a), 0, cos(a)) * radius * 1.08 + Vector3(0, -0.8, 0))
		rings.append(base)
	var jitter := []
	for i in segments:
		jitter.append(rng.randf_range(0.75, 1.2))
	for level in levels:
		var ring := []
		for i in segments:
			var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / segments
			var rr: float = radius * level[0] * (jitter[i] if level[0] > 0.3 else 1.0) * rng.randf_range(0.9, 1.1)
			var y: float = height * level[1] * (rng.randf_range(0.75, 1.15) if not flat else 1.0)
			# Each ring leans toward the summit's side.
			ring.append(Vector3(sin(a) * rr, y, cos(a) * rr) + Vector3(peak.x, 0, peak.z) * (1.0 - level[0]))
		rings.append(ring)
	var tris := PackedVector3Array()
	for j in rings.size() - 1:
		for i in segments:
			var a: Vector3 = rings[j][i]
			var b: Vector3 = rings[j][(i + 1) % segments]
			var c: Vector3 = rings[j + 1][(i + 1) % segments]
			var d: Vector3 = rings[j + 1][i]
			tris.append_array([a, b, c, a, c, d])
	var last: Array = rings[rings.size() - 1]
	for i in segments:
		tris.append_array([last[i], last[(i + 1) % segments], peak])
	return _barycentric(tris)
