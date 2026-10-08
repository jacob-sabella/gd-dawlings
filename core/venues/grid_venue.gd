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
var _smoothed := 0.0
var _clock := 0.0


func venue_id() -> StringName:
	return &"grid"



func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/synthwave_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
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

	env.glow_intensity = 1.0
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.9
	env.set_glow_level(3, 1.0)
	env.set_glow_level(5, 0.8)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
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
	_floor_mat.set_shader_parameter("footprint", Vector4(c[0].x, c[0].y, c[2].x, c[2].y))
	ground.material_override = _floor_mat
	add_child(ground)

	_wire_mat = ShaderMaterial.new()
	_wire_mat.shader = preload("res://core/venues/shaders/neon_wire.gdshader")

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


func _process(delta: float) -> void:
	_clock += delta
	for i in _solids.size():
		_solids[i].rotate_y(delta * (0.12 + 0.05 * i))
		_solids[i].rotate_x(delta * 0.05)
	if _floor_mat != null:
		# The floor runs toward you, slowly: you are always arriving at the horizon.
		_floor_mat.set_shader_parameter("travel", fmod(_clock * 0.12, 1000.0))


func pulse(level: float) -> void:
	# Fast up, slow down, like a meter's ballistics: a beat flashes, a gap does not blink.
	var k := 0.5 if level > _smoothed else 0.06
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	for m in [_floor_mat, _sky_mat, _wire_mat]:
		if m != null:
			m.set_shader_parameter("pulse", _smoothed)


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
