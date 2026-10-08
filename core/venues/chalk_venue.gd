class_name ChalkVenue
extends Venue

## The chalk zone: the studio stood on a blackboard the size of the world, with everything past
## the edge of the floor drawn in neon chalk and hanging in the dark. Stars and planets and
## lightning bolts float at every distance, bobbing as if they had just been drawn and had not
## quite settled; there is dust in the air, and the working floor is outlined in chalk the way
## a stage is taped.
##
## It moves to the music: the chalk itself glows brighter on a loud passage, and the doodles
## nearest the desk jump a little on the beat.

const FLOOR_EXTENT := 300.0
const DOODLE_COUNT := 64
const SEED := 11

var _floor_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _doodles: Array[Node3D] = []
var _rest: Array[Vector3] = []
var _phase: Array[float] = []
var _smoothed := 0.0
var _clock := 0.0


func venue_id() -> StringName:
	return &"chalk"



func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/chalk_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.36, 0.62)
	env.ambient_light_energy = 0.38
	env.glow_intensity = 1.1
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0
	env.set_glow_level(2, 0.8)
	env.set_glow_level(4, 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.04, 0.10)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 160.0
	env.fog_sky_affect = 0.0

	# Moonlight, cold and from high up: enough to model the gear, never enough to compete
	# with the colour the lamps put down.
	key.light_color = Color(0.70, 0.78, 1.0)
	key.light_energy = 0.55


func lamp_colour(index: int, _authored: Color) -> Color:
	return [Chalk.PINK, Chalk.CYAN, Chalk.LIME, Chalk.VIOLET][index % 4]


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 1.2


func _ready() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Chalkboard"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_EXTENT, FLOOR_EXTENT)
	ground.mesh = plane
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = preload("res://core/venues/shaders/chalkboard.gdshader")
	ground.material_override = _floor_mat
	add_child(ground)

	_draw_floor()
	_scatter_doodles()
	_add_dust()


## The working footprint outlined, a chalk circle around the mix position, and a few marks
## scrawled near it: a stage taped out by someone who also likes to draw.
func _draw_floor() -> void:
	var lift := Vector3(0, 0.004, 0)
	var c := footprint_corners()
	var outline := PackedVector3Array()
	for i in 5:
		var p := c[i % 4]
		outline.append(Vector3(p.x, 0, p.y) + lift)
	var lines: Array = [_subdivide(outline, 0.25)]
	var ring := PackedVector3Array()
	for p in Chalk.loop(Vector3.ZERO, 1.35, 56):
		ring.append(Vector3(p.x, 0, p.y + 0.55) + lift)
	lines.append(ring)
	var floor_art := Chalk.drawing(lines, Chalk.WHITE * 0.45, 0.02, true, 2, SEED)
	floor_art.name = "FloorChalk"
	add_child(floor_art)

	# Out past the footprint, big floor doodles in colour -- arrows, a star, a spiral -- that
	# you see when you look down past the desk.
	var marks := [[Chalk.star(), Vector3(-4.6, 0, -3.6), 1.1, Chalk.YELLOW],
			[Chalk.spiral(), Vector3(4.8, 0, -3.2), 1.3, Chalk.CYAN],
			[Chalk.heart(), Vector3(-4.4, 0, 3.8), 0.9, Chalk.PINK],
			[Chalk.lightning(), Vector3(4.3, 0, 3.6), 1.2, Chalk.LIME]]
	for i in marks.size():
		var flat: Array = []
		for line: PackedVector3Array in marks[i][0]:
			var laid := PackedVector3Array()
			for p in line:
				laid.append(marks[i][1] + Vector3(p.x, 0, -p.y) * marks[i][2] + lift)
			flat.append(laid)
		var art := Chalk.drawing(flat, marks[i][3], 0.035, true, 2, SEED + i)
		art.name = "FloorDoodle"
		add_child(art)


func _scatter_doodles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var shapes := Chalk.shapes()
	for i in DOODLE_COUNT:
		var shape: Callable = shapes[i % shapes.size()]
		var colour: Color = Chalk.NEON[rng.randi() % Chalk.NEON.size()]
		# Near ones small, far ones huge, so the space reads as deep from the chair.
		var far := pow(rng.randf(), 0.8)
		var distance := lerpf(6.5, 70.0, far)
		var angle := rng.randf_range(-PI, PI)
		var height := lerpf(1.2, 4.0, rng.randf()) + far * rng.randf_range(2.0, 28.0)
		var size := lerpf(0.35, 9.0, far * far) * rng.randf_range(0.7, 1.3)
		var holder := Node3D.new()
		holder.name = "Doodle"
		holder.position = Vector3(sin(angle) * distance, height, -cos(angle) * distance + 0.3)
		var art := Chalk.drawing(shape.call(), colour, 0.05, false, 2, SEED * 31 + i)
		holder.add_child(art)
		add_child(holder)
		# Face the room, tipped a little so they do not all look like posters.
		holder.look_at(Vector3(0, 1.5, 0.3), Vector3.UP, true)
		holder.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.5, 0.5))
		holder.scale = Vector3.ONE * size
		_doodles.append(holder)
		_rest.append(holder.position)
		_phase.append(rng.randf() * TAU)


func _add_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "ChalkDust"
	dust.amount = 600
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.visibility_aabb = AABB(Vector3(-12, -1, -12), Vector3(24, 8, 24))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(10, 3, 10)
	process.gravity = Vector3(0, -0.01, 0)
	process.direction = Vector3(0.3, 0.2, 0.1)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 0.7))
	fade.add_point(0.8, Color(1, 1, 1, 0.7))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	dust.process_material = process
	dust.position = Vector3(0, 3.0, 0.3)
	var speck := QuadMesh.new()
	speck.size = Vector2(0.012, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 0.85, 1.0)
	# Round and soft. A square mote reads as a pixel, which is to say as a bug.
	var mote := GradientTexture2D.new()
	mote.fill = GradientTexture2D.FILL_RADIAL
	mote.fill_from = Vector2(0.5, 0.5)
	mote.fill_to = Vector2(1.0, 0.5)
	mote.width = 32
	mote.height = 32
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	mote.gradient = soft
	mat.albedo_texture = mote
	speck.material = mat
	dust.draw_pass_1 = speck
	add_child(dust)


func _process(delta: float) -> void:
	_clock += delta
	for i in _doodles.size():
		var bob := sin(_clock * 0.6 + _phase[i]) * 0.08 * _doodles[i].scale.x
		var kick := _smoothed * 0.12 if _rest[i].length() < 14.0 else 0.0
		_doodles[i].position = _rest[i] + Vector3(0, bob + kick, 0)


func pulse(level: float) -> void:
	var k := 0.5 if level > _smoothed else 0.06
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	Chalk.material().set_shader_parameter("pulse", _smoothed)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("pulse", _smoothed)


static func _subdivide(line: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in line.size() - 1:
		var n := maxi(1, int(line[i].distance_to(line[i + 1]) / step))
		for k in n:
			out.append(line[i].lerp(line[i + 1], float(k) / float(n)))
	out.append(line[line.size() - 1])
	return out
