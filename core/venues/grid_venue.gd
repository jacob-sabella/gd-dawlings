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
var _clock := 0.0


func venue_id() -> StringName:
	return &"grid"



func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/synthwave_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
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
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = preload("res://core/venues/shaders/grid_floor.gdshader")
	var c := footprint_corners()
	_floor_mat.set_shader_parameter("energy", 1.7)
	_floor_mat.set_shader_parameter("footprint", Vector4(c[0].x, c[0].y, c[2].x, c[2].y))
	ground.material_override = _floor_mat
	add_child(ground)

	_wire_mat = ShaderMaterial.new()
	_wire_mat.shader = preload("res://core/venues/shaders/neon_wire.gdshader")
	_wire_mat.set_shader_parameter("energy", 1.9)

	var range_node := MeshInstance3D.new()
	range_node.name = "Mountains"
	range_node.mesh = mountains(23)
	range_node.material_override = _wire_mat
	range_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(range_node)

	# Two great solids turning slowly in the sky, the way every album cover of the genre has one.
	for spec in [[Vector3(-34, 24, -70), 7.0, Color(0.1, 0.9, 1.0)],
			[Vector3(40, 17, -58), 4.5, Color(1.0, 0.3, 0.85)]]:
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

	_build_highway()
	_plant_palms()
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

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, chrome, glass)
	# A tall slab of black glass behind the stand for the modules, edged in pink: the grid's
	# version of a wall to put a rack on, since it has no walls.
	var slab := Vector3(0.06, 1.1, 1.6)
	var at := Vector3(z[&"synth"].size.x * 0.5 - 0.05, 1.55, 0)
	ZoneKit.block(synth, slab, at, glass, "ModulePanel")
	_neon_edges(synth, slab, at, pink, 0.012)


## The riser, the table and the stand are glass and stop you; the booth is only its neon edges,
## and an invisible wall between them would be a wall you could not see.
func zone_solids() -> Array:
	return ZoneKit.solids(zones(), false)


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
	if _floor_mat != null:
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
	for m in [_floor_mat, _sky_mat, _wire_mat, _road_mat, _tower_mat, _palm_mat]:
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
	for i in 12:
		var z := ROAD_START - 8.0 - i * 15.0
		spots.append(Vector3(-ROAD_HALF - 2.5, 0, z))
		spots.append(Vector3(ROAD_HALF + 2.5, 0, z - 7.5))
	# And a few near the room, so they are in the shot from the chair, not only on the horizon.
	spots.append_array([Vector3(-7.5, 0, 1.5), Vector3(8.0, 0, -0.5), Vector3(-9.0, 0, 6.0),
			Vector3(10.0, 0, 7.0)])
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


func _hang_pyramids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var colours := [Color(1.0, 0.85, 0.2), Color(0.2, 1.0, 0.9), Color(1.0, 0.3, 0.8)]
	var spots := [Vector3(-16, 7, -22), Vector3(19, 9, -28), Vector3(-4, 14, -48)]
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
