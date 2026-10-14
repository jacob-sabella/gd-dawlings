class_name DesertVenue
extends Venue

## A nomad camp in the desert. The studio is pitched under a Bedouin canopy: one sheet of woven
## goat hair pulled taut on a ring of poles and guy ropes (assets/models/desert_tent.glb), its
## front lifted high as an awning, a woven valance with tassels round its hems and its back closed
## by a hanging wall. Underfoot, kilims laid over the sand and over each other, every one drawn
## its own (desert_kilim.gdshader). Brass lanterns hang from the cloth on chains; either side of
## the desk is a lounge of floor cushions, bolsters and a pouffe round a brass tray table with the
## tea things on it. No walls: the desk stands in the tent and the floor beside it is walkable to
## the poles, the zones under the back of the canopy.
##
## Three arrangements (Venue.VARIANTS), three deserts round the same camp:
##   Starlit canyon  night in a red-rock canyon: sandstone walls in beds of colour towering either
##                   side, the canyon opening ahead onto mesa country, the Milky Way overhead, the
##                   moon, and a campfire in front of the tent, flickering, throwing embers.
##   Dawn dunes      sunrise over a sea of dunes: the sun just up ahead, the sky pink and gold,
##                   long shadows over rippled sand, the wind lifting sand off the crests, and a
##                   camel caravan going along a ridge far off. Last night's fire smoking.
##   Oasis           evening at a pool of still water ringed with date palms and reeds, walled in
##                   mud brick, a tower of the village behind it, lanterns on posts round the
##                   water and their light lying in it upside down with the palms and the sky.

const CANYON := 0
const DUNES := 1
const OASIS := 2

## The tent's poles at the base width, (x, height of the head, z), round its edge in order. The
## same list as POLES in tools/blender/desert_tent.py: the cloth was solved to these heads.
const TENT_POLES := [
	Vector3(-6.55, 3.75, -3.55), Vector3(-2.3, 4.85, -3.55), Vector3(2.3, 4.85, -3.55),
	Vector3(6.55, 3.75, -3.55), Vector3(6.55, 4.35, 2.1), Vector3(6.55, 3.7, 7.75),
	Vector3(2.3, 4.25, 7.75), Vector3(-2.3, 4.25, 7.75), Vector3(-6.55, 3.7, 7.75),
	Vector3(-6.55, 4.35, 2.1),
]
const TENT_HALF := 6.55
## The middle of the tent's plan, which the guy ropes pull away from.
const TENT_MIDDLE := Vector2(0.0, 2.1)
## The tent's lantern hooks (tools/blender/desert_tent.py HOOKS), by what they hang over: the two
## lounges, the walk to the zones either side and down the middle, the back corners, over the
## desk's front corners, and over the kit and the table.
const HOOK_LOUNGE := [0, 1]
const HOOK_WALK := [2, 3]
const HOOK_MIDDLE := 4
const HOOK_BACK := [5, 6]
const HOOK_FRONT := [7, 8]
const HOOK_DRUMS := 9
const HOOK_BRICKS := 10
const HOOK_MATRIX := 11

## A lantern's ring is this far above its foot (tools/blender/desert_props.py LANTERN_RING).
const LANTERN_RING := 0.52

const MODELS := "res://assets/models/"
const SHADERS := "res://core/venues/shaders/"

## Per arrangement: the sky (zenith, upper, horizon; the glow's colour and strength; the sun's
## direction and disc; the moon's direction, size and phase; stars; the Milky Way; how bright the
## sky is), the air (ambient colour and energy; fog colour, start and end), the key light
## (colour, energy, pitch, yaw), the sand, and how bright the lanterns burn.
const HOURS := [
	{"sky": [Color(0.004, 0.006, 0.018), Color(0.01, 0.014, 0.035), Color(0.035, 0.038, 0.07)],
			"glow": [Color(0.3, 0.32, 0.5), 0.15], "sun": Vector3(0.2, -0.5, 1.0), "disc": 0.0,
			"moon": [Vector3(-0.25, 0.75, -0.6), 0.03, 0.6], "stars": 1.0, "milky_way": 1.0, "energy": 1.0,
			"ambient": [Color(0.42, 0.48, 0.7), 0.09], "fog": [Color(0.025, 0.03, 0.06), 60.0, 700.0],
			"key": [Color(0.74, 0.8, 1.0), 0.36, -52.0, 210.0],
			"sand": [Color(0.66, 0.44, 0.3), Color(0.55, 0.34, 0.24)], "lanterns": 1.0},
	{"sky": [Color(0.16, 0.2, 0.38), Color(0.5, 0.36, 0.48), Color(0.98, 0.62, 0.42)],
			"glow": [Color(1.0, 0.66, 0.36), 1.1], "sun": Vector3(0.5, 0.045, -1.0), "disc": 0.022,
			"moon": [Vector3(-0.7, 0.3, 0.6), 0.016, 0.85], "stars": 0.0, "milky_way": 0.0, "energy": 0.74,
			"ambient": [Color(0.8, 0.62, 0.6), 0.13], "fog": [Color(0.62, 0.46, 0.42), 120.0, 1400.0],
			"key": [Color(1.0, 0.7, 0.46), 1.0, -5.0, 154.0],
			"sand": [Color(0.76, 0.6, 0.46), Color(0.7, 0.53, 0.41)], "lanterns": 0.45},
	{"sky": [Color(0.015, 0.02, 0.06), Color(0.07, 0.06, 0.15), Color(0.36, 0.2, 0.22)],
			"glow": [Color(1.0, 0.45, 0.24), 0.8], "sun": Vector3(-0.55, -0.07, -1.0), "disc": 0.0,
			"moon": [Vector3(-0.32, 0.3, -1.0), 0.02, 0.2], "stars": 0.55, "milky_way": 0.0, "energy": 1.0,
			"ambient": [Color(0.5, 0.42, 0.62), 0.1], "fog": [Color(0.06, 0.045, 0.07), 50.0, 520.0],
			"key": [Color(0.8, 0.55, 0.62), 0.22, -8.0, 150.0],
			"sand": [Color(0.72, 0.52, 0.36), Color(0.6, 0.42, 0.3)], "lanterns": 1.0},
]

## The fire in the canyon, in front of the tent and to the left: in view from the desk past the
## gear, clear of the guy ropes.
const FIRE_AT := Vector2(-3.0, -9.5)
## The oasis's pool: its middle, its radii, and the water's height.
const POOL := Vector2(0.0, -12.5)
const POOL_RADII := Vector2(8.0, 4.6)
const WATER := -0.3
## The dunes' wind (the way it blows, in plan), which lays the ripples and lifts the sand.
const WIND := Vector2(0.78, -0.62)

var _sky_mat: ShaderMaterial
var _sand_mat: ShaderMaterial
var _glass: StandardMaterial3D
var _brass_mat: StandardMaterial3D
var _flame_mat: ShaderMaterial
var _noise := FastNoiseLite.new()
## The lantern lights and what each is set to, for pulse and blackout.
var lantern_lights: Array[Light3D] = []
var _authored: Array[float] = []
var _fire_light: OmniLight3D
var _fire_base := 0.0
var _glass_base := 0.0
var _smoothed := 0.0
var _clock := 0.0
var _dark := false


func venue_id() -> StringName:
	return &"desert"


## No wall at the front or on the right to hang the roll board or the roulette panel on: the tent
## is open on every side but the back. They stand.
func back_wall_gear_stands() -> bool:
	return true


## Camp furniture: cedar carcasses, brass fittings and an indigo-black lacquer, the lamps in
## pierced brass and the looms bound in saffron cloth.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("black_walnut_veneer_01", 0.9, Color(0.86, 0.6, 0.42))) \
			.with("chassis", GearStyle.paint(Color(0.07, 0.065, 0.1), 0.6, 0.15)) \
			.with("brushed", GearStyle.metal(Color(0.78, 0.6, 0.34), 0.32)) \
			.with("trim", GearStyle.metal(Color(0.7, 0.5, 0.26), 0.4)) \
			.with("end_cheek", GearStyle.scan("black_walnut_veneer_01", 0.6, Color(0.6, 0.38, 0.26))) \
			.with("lamp_shade", GearStyle.metal(Color(0.74, 0.53, 0.22), 0.48)) \
			.with("loom_band", GearStyle.paint(Color(0.86, 0.56, 0.12), 0.85, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.11, 0.42, 0.44), 0.4, 0.05))


## A board of woven camel hair, the writing in chalky cream and the arrows in saffron.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = Materials.scanned(StandardMaterial3D.new(), "rough_linen", "1k", 0.5, Color(0.42, 0.3, 0.22))
	board.ink = Color(0.94, 0.88, 0.74)
	board.accent = Color(0.95, 0.66, 0.18)
	board.board_ink_fade = Color(0.6, 0.5, 0.4)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	var hour: Dictionary = HOURS[variant]
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/desert_sky.gdshader")
	_sky_mat.set_shader_parameter("zenith", hour["sky"][0])
	_sky_mat.set_shader_parameter("upper", hour["sky"][1])
	_sky_mat.set_shader_parameter("horizon", hour["sky"][2])
	_sky_mat.set_shader_parameter("glow_colour", hour["glow"][0])
	_sky_mat.set_shader_parameter("glow", hour["glow"][1])
	_sky_mat.set_shader_parameter("sun_dir", hour["sun"])
	_sky_mat.set_shader_parameter("sun_radius", hour["disc"])
	_sky_mat.set_shader_parameter("moon_dir", hour["moon"][0])
	_sky_mat.set_shader_parameter("moon_radius", hour["moon"][1])
	_sky_mat.set_shader_parameter("moon_phase", hour["moon"][2])
	_sky_mat.set_shader_parameter("stars", hour["stars"])
	_sky_mat.set_shader_parameter("milky_way", hour["milky_way"])
	if variant == CANYON:
		# Down the slot: the only sky a canyon floor has is the strip between the rims, so the
		# galaxy runs along it, its bright core over the canyon's mouth, and the moon rides high
		# in the same strip.
		_sky_mat.set_shader_parameter("galaxy_pole", Vector3(1.0, 0.1, 0.1))
		_sky_mat.set_shader_parameter("galaxy_core", Vector3(0.0, 0.62, -0.78))
	_sky_mat.set_shader_parameter("energy", hour["energy"])
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = hour["ambient"][0]
	env.ambient_light_energy = hour["ambient"][1]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The air: clear at night, the dawn's haze over the dunes, the evening's over the palms.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = hour["fog"][0]
	env.fog_depth_begin = hour["fog"][1]
	env.fog_depth_end = hour["fog"][2]
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.0
	key.light_color = hour["key"][0]
	key.light_energy = hour["key"][1]
	key.rotation_degrees = Vector3(hour["key"][2], hour["key"][3], 0.0)
	key.light_specular = 0.12


func lamp_colour(_index: int, authored: Color) -> Color:
	# Through brass and amber glass, like the lanterns.
	return authored.lerp(Color(1.0, 0.64, 0.34), 0.42)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * (0.7 if variant == DUNES else 0.82)


## The lanterns go out with the house lights.
func blackout(on: bool) -> void:
	_dark = on
	for i in lantern_lights.size():
		lantern_lights[i].light_energy = 0.0 if on else _authored[i]
	if _glass != null:
		_glass.emission_energy_multiplier = 0.05 if on else _glass_base


## The lanterns and the fire breathe with the mix: fast up, slow down, as a meter does.
func pulse(level: float) -> void:
	var k := 0.5 if level > _smoothed else 0.05
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	if _dark:
		return
	var lift := 1.0 + 0.32 * _smoothed
	for i in lantern_lights.size():
		lantern_lights[i].light_energy = _authored[i] * lift
	if _glass != null:
		_glass.emission_energy_multiplier = _glass_base * (1.0 + 0.5 * _smoothed)
	if _flame_mat != null:
		_flame_mat.set_shader_parameter("level", 0.8 + 0.6 * _smoothed)


func _process(delta: float) -> void:
	_clock += delta
	if _fire_light != null and not _dark:
		# A fire breathes: two slow waves and a quick one, never out, a little higher with the music.
		var f := 0.8 + 0.1 * sin(_clock * 2.1) + 0.07 * sin(_clock * 5.3 + 1.1) + 0.05 * sin(_clock * 13.1)
		_fire_light.light_energy = _fire_base * f * (1.0 + 0.4 * _smoothed)


# --- the floor plan ----------------------------------------------------------------------------

## One floor: the tent's, either side of the desk to the poles, and back to the zones.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## How much wider than drawn the tent is, as the room grows with the desk.
func tent_scale() -> float:
	return (live_room_half() + 0.25) / TENT_HALF


func pole_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in TENT_POLES:
		out.append(Vector3(p.x * tent_scale(), p.y, p.z))
	return out


## The lounges either side of the desk: where each side's tray table, pouffe and floor lantern
## stand, in studio space.
func tray_spot(side: float) -> Vector2:
	return Vector2(side * (5.05 + _grow()), -1.0 if side < 0.0 else -0.6)


func pouf_spot(side: float) -> Vector2:
	return Vector2(side * (4.55 + _grow()), 0.85 if side < 0.0 else -2.2)


func jar_spots() -> Array[Vector2]:
	return [Vector2(-(5.9 + _grow()), -2.75), Vector2(5.95 + _grow(), 1.75), Vector2(5.65 + _grow(), 2.25)]


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	for side: float in [-1.0, 1.0]:
		out.append({"c": tray_spot(side), "h": Vector2(0.36, 0.36), "a": 0.0, "top": 0.43})
		out.append({"c": pouf_spot(side), "h": Vector2(0.25, 0.25), "a": 0.0, "top": 0.31})
	for j in jar_spots():
		out.append({"c": j, "h": Vector2(0.2, 0.2), "a": 0.0, "top": 0.62})
	return out


# --- building it -------------------------------------------------------------------------------

func _ready() -> void:
	_noise.seed = 17
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	var hour: Dictionary = HOURS[variant]
	_sand_mat = ShaderMaterial.new()
	_sand_mat.shader = preload("res://core/venues/shaders/desert_sand.gdshader")
	_sand_mat.set_shader_parameter("grain_tex", load("res://assets/textures/coast_sand_01/coast_sand_01_diff_1k.jpg"))
	_sand_mat.set_shader_parameter("grain_normal", load("res://assets/textures/coast_sand_01/coast_sand_01_nor_gl_1k.jpg"))
	_sand_mat.set_shader_parameter("tint", hour["sand"][0])
	_sand_mat.set_shader_parameter("patch_tint", hour["sand"][1])
	_sand_mat.set_shader_parameter("wind", WIND)
	# Ripples raked by a low sun want to be deep; under lanterns at night, shallow.
	_sand_mat.set_shader_parameter("ripple_depth", 0.3 if variant == DUNES else 0.2)
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.3, 0.16, 0.06)
	_glass.emission_enabled = true
	_glass.emission = Color(1.0, 0.6, 0.26)
	_glass_base = 2.4 * float(hour["lanterns"])
	_glass.emission_energy_multiplier = _glass_base

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(live_room_half() * 2.0 + 0.2, LIVE_ROOM_BACK - Studio.ROOM_FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (LIVE_ROOM_BACK + Studio.ROOM_FRONT) * 0.5
	floor_mesh.material_override = _sand_mat
	add_child(floor_mesh)

	_pitch_the_tent()
	_lay_rugs()
	_furnish_lounges()
	_hang_lanterns()
	_dress_zones()
	match variant:
		CANYON:
			_carve_the_canyon()
		DUNES:
			_raise_the_dunes()
		OASIS:
			_make_the_oasis()


## A model's scene, instanced, with its materials swapped by name.
func _model(file: String, at: Vector3, yaw: float, swap: Dictionary, parent: Node3D = null) -> Node3D:
	var node := (load(MODELS + file) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	_swap(node, swap)
	(parent if parent != null else self).add_child(node)
	return node


func _swap(node: Node, swap: Dictionary) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])


## One piece out of a file of several (desert_props.glb, desert_flora.glb...): its mesh, with its
## materials swapped by name and baked in, ready for a MeshInstance or a MultiMesh.
static var _meshes := {}


func _piece(file: String, piece: String, swap: Dictionary) -> Mesh:
	var key := file + "/" + piece
	if not _meshes.has(key):
		var scene := (load(MODELS + file) as PackedScene).instantiate()
		for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			_meshes[file + "/" + String(node.name)] = node.mesh
		scene.free()
	var mesh := (_meshes[key] as Mesh).duplicate() as Mesh
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swap.has(m.resource_name):
			mesh.surface_set_material(s, swap[m.resource_name])
	return mesh


func _put(mesh: Mesh, at: Vector3, yaw := 0.0, label := "Piece", parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.position = at
	mi.rotation.y = yaw
	(parent if parent != null else self).add_child(mi)
	return mi


func _many(label: String, mesh: Mesh, at: Array, shadows := false, parent: Node3D = null,
		colours: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colours.is_empty()
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
		if not colours.is_empty():
			mm.set_instance_color(i, colours[i])
	var holder := MultiMeshInstance3D.new()
	holder.name = label
	holder.multimesh = mm
	if not shadows:
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(holder)
	return holder


## Brass, a little dulled by the dust: the lanterns, the fittings, the tray tables. One for all.
func _brass() -> StandardMaterial3D:
	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.albedo_color = Color(0.62, 0.44, 0.2)
		_brass_mat.metallic = 0.85
		_brass_mat.roughness = 0.38
	return _brass_mat


## Cedar, oiled and dark: the riser's skirt, the booth's frame, the tables.
func _cedar() -> StandardMaterial3D:
	return Materials.cached_scanned("desert_cedar", "black_walnut_veneer_01", "2k", 0.8, Color(0.78, 0.5, 0.34))


func _rope() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.4, 0.27)
	m.roughness = 1.0
	return m


func _paint(colour: Color, roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m


# --- the tent ----------------------------------------------------------------------------------

## The canopy (desert_tent.glb) at the room's width, its poles, and the ropes that hold it:
## two from every corner and one from every other pole, out to iron stakes in the sand.
func _pitch_the_tent() -> void:
	var cloth := ShaderMaterial.new()
	cloth.shader = preload("res://core/venues/shaders/desert_cloth.gdshader")
	# By day the sun comes through the hair a little; at night nothing does.
	cloth.set_shader_parameter("backlight", Color(0.22, 0.13, 0.07) if variant == DUNES else Color(0.02, 0.012, 0.008))
	var band := ShaderMaterial.new()
	band.shader = preload("res://core/venues/shaders/desert_kilim.gdshader")
	band.set_shader_parameter("mode", 1)
	var tassel := _paint(Color(0.5, 0.1, 0.07))
	# The back wall is the tent's best weaving: the camel-hair strips, banded on most of them.
	var hanging := cloth.duplicate() as ShaderMaterial
	hanging.set_shader_parameter("hair", Color(0.2, 0.12, 0.08))
	hanging.set_shader_parameter("banded", 0.75)
	var tent := _model("desert_tent.glb", Vector3.ZERO, 0.0, {"cloth": cloth, "valance": band, "tassel": tassel,
			"wall": hanging})
	tent.name = "Tent"
	tent.scale = Vector3(tent_scale(), 1.0, 1.0)
	for mesh: MeshInstance3D in tent.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	var wood := Materials.cached_scanned("desert_pole", "weathered_brown_planks", "2k", 0.6, Color(0.55, 0.4, 0.3))
	var brass := _brass()
	var ropes: Array[Transform3D] = []
	var stakes: Array[Transform3D] = []
	for p in pole_spots():
		var pole := CylinderMesh.new()
		pole.top_radius = 0.045
		pole.bottom_radius = 0.055
		pole.height = p.y + 0.12
		pole.radial_segments = 10
		var mi := _put(pole, Vector3(p.x, pole.height * 0.5, p.z), 0.0, "Pole")
		mi.material_override = wood
		# A brass knob on top, over the cloth.
		var knob := SphereMesh.new()
		knob.radius = 0.06
		knob.height = 0.1
		knob.radial_segments = 10
		knob.rings = 5
		var k := _put(knob, Vector3(p.x, p.y + 0.15, p.z), 0.0, "PoleKnob")
		k.material_override = brass
		var out := (Vector2(p.x, p.z) - TENT_MIDDLE).normalized()
		var corner := absf(absf(p.x) - TENT_HALF * tent_scale()) < 0.01 and (p.z < 0.0 or p.z > 7.0)
		var spreads: Array = [-0.42, 0.42] if corner else [0.0]
		for spread: float in spreads:
			var dir := out.rotated(spread)
			var reach := p.y * 0.8
			var stake := Vector3(p.x + dir.x * reach, 0.0, p.z + dir.y * reach)
			var from := Vector3(p.x, p.y + 0.05, p.z)
			var to := stake + Vector3(0, 0.12, 0)
			var look := Basis.looking_at(to - from, Vector3.UP) * Basis.from_scale(Vector3(1, 1, from.distance_to(to)))
			ropes.append(Transform3D(look, (from + to) * 0.5))
			stakes.append(Transform3D(Basis(Vector3.RIGHT, -0.35 * signf(dir.y + 0.001)), stake + Vector3(0, 0.08, 0)))
	var line := BoxMesh.new()
	line.size = Vector3(0.012, 0.012, 1.0)
	_many("GuyRopes", line, ropes).material_override = _rope()
	var peg := BoxMesh.new()
	peg.size = Vector3(0.035, 0.3, 0.035)
	var iron := _paint(Color(0.08, 0.07, 0.06), 0.6)
	_many("Stakes", peg, stakes).material_override = iron


## Where hook `n` hangs in studio space: the tent's own empties, at the room's width.
func hook(n: int) -> Vector3:
	var tent := get_node_or_null("Tent") as Node3D
	var h := tent.find_child("hook_%d" % n, true, false) as Node3D
	var at := h.transform
	var up := h.get_parent()
	while up != null and up != self:
		if up is Node3D:
			at = (up as Node3D).transform * at
		up = up.get_parent()
	return at.origin


# --- the rugs ----------------------------------------------------------------------------------

## Kilims over the sand: a big one under the desk, others over and beside it at angles, a rug
## under each lounge and under each zone. (x, z, width, depth, yaw, layer, palette); x is out
## from the middle at the base width and steps out with the room on its own side.
const RUGS := [
	[0.0, -0.3, 6.4, 4.8, 0.0, 0, 0.0], [-2.7, 1.7, 2.2, 3.2, 0.22, 1, 1.0], [2.9, -1.9, 2.0, 3.0, -0.28, 1, 2.0],
	[-2.4, -2.2, 1.5, 2.3, 1.35, 2, 3.0], [2.4, 2.2, 1.4, 2.0, -1.2, 2, 1.3],
	[-5.15, -0.7, 2.0, 3.6, 0.04, 0, 3.4], [5.15, -0.8, 2.0, 3.4, -0.05, 0, 0.6],
	[-4.9, 4.6, 3.2, 2.4, 0.08, 0, 2.2], [1.2, 5.4, 3.7, 3.7, 0.0, 1, 0.2], [4.4, 4.7, 2.3, 3.4, -0.06, 0, 1.6],
	[-2.1, 3.4, 2.1, 1.3, 0.35, 2, 2.7], [-2.2, 5.8, 2.9, 2.9, 0.0, 2, 3.1],
]
## How thick a rug is, and how much higher each layer lies than the one under it.
const RUG_THICK := 0.004
const RUG_LAYER := 0.0037


func _lay_rugs() -> void:
	var kilim := ShaderMaterial.new()
	kilim.shader = preload("res://core/venues/shaders/desert_kilim.gdshader")
	kilim.set_shader_parameter("mode", 0)
	# The low sun comes in under the cloth and lies along the rugs; the dyes are the same, less lit.
	kilim.set_shader_parameter("brightness", 0.82 if variant == DUNES else 1.0)
	for i in RUGS.size():
		var r: Array = RUGS[i]
		var x: float = r[0] + signf(r[0]) * _grow()
		var box := BoxMesh.new()
		# A millimetre's difference between any two, so no two edges ever lie in one plane.
		box.size = Vector3(r[2] + i * 0.001, RUG_THICK, r[3] + i * 0.0013)
		var top: float = 0.0045 + int(r[5]) * RUG_LAYER + i * 0.0002
		var rug := _put(box, Vector3(x, top - RUG_THICK * 0.5, r[1]), r[4], "Rug%d" % i)
		rug.material_override = kilim
		rug.set_instance_shader_parameter("rug_size", Vector2(box.size.x, box.size.z))
		rug.set_instance_shader_parameter("seed", r[6])
		rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The height of the rugs' top at the lounges and in the zones, for what stands on them.
const ON_RUGS := 0.0045 + RUG_LAYER * 2.0 + 0.004


# --- the lounges -------------------------------------------------------------------------------

## Either side of the desk, on its own rug: floor cushions against the outside, bolsters behind
## them, a pouffe, a brass tray table with the tea things on it, and a lantern on the floor. The
## water jars stand by the poles.
func _furnish_lounges() -> void:
	var cushion := ShaderMaterial.new()
	cushion.shader = preload("res://core/venues/shaders/desert_kilim.gdshader")
	cushion.set_shader_parameter("mode", 2)
	var piping := _paint(Color(0.78, 0.6, 0.3), 0.6)
	var cushions: Array = []
	var colours: Array = []
	var bolsters: Array = []
	var bolster_colours: Array = []
	var hues := [Color(0.55, 0.12, 0.08), Color(0.12, 0.16, 0.36), Color(0.7, 0.42, 0.12), Color(0.18, 0.36, 0.34),
			Color(0.42, 0.1, 0.18), Color(0.6, 0.5, 0.34)]
	var n := 0
	for side: float in [-1.0, 1.0]:
		var wall_x: float = side * (6.0 + _grow())
		for k in 4:
			var z: float = -2.6 + k * 0.68 + (0.0 if side < 0.0 else 0.25)
			cushions.append(Transform3D(Basis(Vector3.UP, 0.08 * sin(k * 2.0 + side)), Vector3(wall_x, ON_RUGS, z)))
			colours.append(hues[n % hues.size()])
			n += 1
			if k % 2 == 0:
				bolsters.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(wall_x + side * 0.24, ON_RUGS + 0.16,
						z + 0.34)))
				bolster_colours.append(hues[(n + 2) % hues.size()])
		# Two more round the tray table's other side, turned in.
		var tray := tray_spot(side)
		for k in 2:
			var at := Vector3(tray.x - side * 0.62, ON_RUGS, tray.y - 0.4 + k * 0.8)
			cushions.append(Transform3D(Basis(Vector3.UP, 0.3 * (k - 0.5)), at))
			colours.append(hues[(n + 3) % hues.size()])
			n += 1
	_many("Cushions", _piece("desert_props.glb", "cushion", {"cushion": cushion, "piping": piping}), cushions, true,
			null, colours)
	_many("Bolsters", _piece("desert_props.glb", "bolster", {"cushion": cushion, "piping": piping}), bolsters, true,
			null, bolster_colours)
	var brass := _brass()
	var wood := _cedar()
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.72, 0.72, 0.7)
	silver.metallic = 0.9
	silver.roughness = 0.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.8, 0.7, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var tea := _paint(Color(0.45, 0.22, 0.05), 0.2)
	var leather := Materials.cached_scanned("desert_leather", "wool_boucle", "1k", 0.3, Color(0.55, 0.3, 0.16))
	var tray_mesh := _piece("desert_props.glb", "tray_table", {"brass": brass, "wood": wood})
	var pot := _piece("desert_props.glb", "teapot", {"silver": silver})
	var cup := _piece("desert_props.glb", "tea_glass", {"glass": glass, "tea": tea})
	var pouf := _piece("desert_props.glb", "pouf", {"leather": leather, "piping": piping})
	for side: float in [-1.0, 1.0]:
		var at := tray_spot(side)
		_put(tray_mesh, Vector3(at.x, ON_RUGS, at.y), side * 0.3, "TrayTable")
		var top := ON_RUGS + 0.4 + 0.0065
		_put(pot, Vector3(at.x + 0.08, top, at.y - 0.05), 2.4 + side, "Teapot")
		for g in 4:
			var a := g * 1.5 + side
			_put(cup, Vector3(at.x + cos(a) * 0.2, top, at.y + sin(a) * 0.2), 0.0, "TeaGlass")
		var p := pouf_spot(side)
		_put(pouf, Vector3(p.x, ON_RUGS, p.y), side, "Pouf")
	var clay := Materials.cached_scanned("desert_clay", "coast_sand_01", "1k", 0.5, Color(0.7, 0.42, 0.28))
	var jar := _piece("desert_props.glb", "water_jar", {"clay": clay})
	for j in jar_spots():
		_put(jar, Vector3(j.x, 0.0, j.y), j.x, "WaterJar")


# --- the lanterns ------------------------------------------------------------------------------

## A brass lantern (desert_props.glb) at `at` (its foot), its glass the shared glowing glass.
func _lantern(at: Vector3, label: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh := _piece("desert_props.glb", "lantern", {"brass": _brass(), "glass": _glass})
	var mi := _put(mesh, at, 0.0, label, parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A light of a lantern's: warm, soft, short, shadowless.
func _lantern_light(at: Vector3, energy: float, reach: float, parent: Node3D = null) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = at
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = energy * float(HOURS[variant]["lanterns"])
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.light_specular = 0.08
	light.shadow_enabled = false
	(parent if parent != null else self).add_child(light)
	lantern_lights.append(light)
	_authored.append(light.light_energy)
	return light


## Lanterns on chains from the cloth: over the lounges, the walk to the zones, the kit and the
## table and the back corners (those light the floor and the back wall round them); over the
## middle and the desk's front corners they only glow -- seen from the desk as lights along the
## awning.
func _hang_lanterns() -> void:
	var chain := _paint(Color(0.3, 0.22, 0.12), 0.5)
	chain.metallic = 0.7
	var lit: Array = HOOK_LOUNGE + HOOK_WALK + HOOK_BACK + [HOOK_DRUMS, HOOK_BRICKS]
	var all: Array = lit + HOOK_FRONT + [HOOK_MIDDLE]
	for n: int in all:
		var top := hook(n)
		# How far each hangs below its hook: the ones over the walk at head height plus a hand.
		# Over the kit and the table they hang high, clear of a raised stick or a reach across.
		var drop := 0.55 if n in HOOK_FRONT else (0.25 if n in [HOOK_DRUMS, HOOK_BRICKS] else 0.75)
		var foot := top - Vector3(0, drop + LANTERN_RING, 0)
		var link := ZoneKit.block(self, Vector3(0.01, drop, 0.01), top - Vector3(0, drop * 0.5, 0), chain, "Chain%d" % n)
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lantern(foot, "Lantern%d" % n)
		if n in lit:
			_lantern_light(foot + Vector3(0, 0.18, 0), 1.5, 5.0)
	# On the floor in each lounge, by the tray table.
	for side: float in [-1.0, 1.0]:
		var at := tray_spot(side)
		_lantern(Vector3(at.x + side * 0.55, ON_RUGS, at.y + 0.75), "FloorLantern")


# --- the zones ---------------------------------------------------------------------------------

## The zones in the camp's own things: the riser a cedar platform with a kilim on it, the booth
## framed in cedar, the lattice's square inlaid in brass on its rug, a cedar table on brass legs,
## the keys on a brass stand.
func _dress_zones() -> void:
	var z := zones()
	var cedar := _cedar()
	var brass := _brass()
	var kilim := ShaderMaterial.new()
	kilim.shader = preload("res://core/venues/shaders/desert_kilim.gdshader")
	kilim.set_shader_parameter("mode", 0)

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var deck := Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, deck, ZoneKit.RISER_HEIGHT, kilim, cedar)
	var top := drums.get_node("RiserTop") as MeshInstance3D
	top.set_instance_shader_parameter("rug_size", deck + Vector2(0.02, 0.02))
	top.set_instance_shader_parameter("seed", 1.7)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.72, 0.62, 0.5, 0.1)
	glass.roughness = 0.05
	glass.metallic_specular = 0.7
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, cedar, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), brass, ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.66, 0.38),
			1.3, 60.0, 3.2, brass)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, ON_RUGS, 0), 0.05, brass)
	# A brass can sewn to the cloth over the middle of the lattice, high over its three metres.
	ZoneKit.spot_down(matrix, Vector3(0, hook(HOOK_MATRIX).y - 0.05, 0), Color(1.0, 0.76, 0.5), 2.6, 44.0, 5.5, brass)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.07, cedar, brass)
	_dress_prop_shelf(cedar, brass, Color(1.0, 0.66, 0.34))

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, brass, cedar)


## The mirror stands framed in brass.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.055, 0.04, 0.013, _brass())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Dyes of the camp: madder, saffron, ochre, henna-green and palm, turquoise, the indigo of the
## veils and the night, a violet of amethyst, a rose of the dawn, and sand.
func track_palette() -> Array:
	return [
		Color(0.8, 0.24, 0.16), Color(0.94, 0.52, 0.16), Color(0.92, 0.76, 0.3), Color(0.66, 0.7, 0.28),
		Color(0.36, 0.6, 0.3), Color(0.18, 0.62, 0.6), Color(0.36, 0.6, 0.86), Color(0.26, 0.32, 0.7),
		Color(0.56, 0.36, 0.72), Color(0.78, 0.3, 0.52), Color(0.94, 0.6, 0.62), Color(0.72, 0.62, 0.48),
	]


# --- the ground --------------------------------------------------------------------------------

## The land round the camp, out to `reach` every way: a grid fine near the tent and coarse far
## off, lifted by `height` (x, z) -> y, and left open where `hole` (x, z) says (the oasis's pool,
## under the water). Its normals come from the height itself, so the dunes are smooth. A point in
## the hole that still corners a kept square is moved by `rim` (x, z) -> (x, z) onto the hole's
## edge, so the edge is the hole's own curve and not the grid's staircase.
func _ground(reach: float, height: Callable, hole := Callable(), rim := Callable()) -> MeshInstance3D:
	# Half a metre apart out to INNER either way (the camp, the pool's bank, the fire), then each
	# step a little longer than the last out to `reach`.
	const INNER := 34.0
	const STEP := 0.5
	const OUTER := 44
	var growth := _growth(INNER, STEP, reach, OUTER)
	var half_axis: Array[float] = []
	var at := 0.0
	while at < INNER - 0.001:
		half_axis.append(at)
		at += STEP
	var step := STEP
	for k in OUTER + 1:
		half_axis.append(at)
		step *= growth
		at += step
	var coords: Array[float] = []
	for k in range(half_axis.size() - 1, 0, -1):
		coords.append(-half_axis[k])
	coords.append_array(half_axis)
	var n := coords.size() - 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector2(0.0, 2.0)
	var heights := PackedFloat32Array()
	var places := PackedVector2Array()
	var holes: Array[bool] = []
	for i in n + 1:
		for j in n + 1:
			var x := coords[i] + centre.x
			var z := coords[j] + centre.y
			var in_hole := hole.is_valid() and bool(hole.call(x, z))
			holes.append(in_hole)
			if in_hole and rim.is_valid():
				var to: Vector2 = rim.call(x, z)
				x = to.x
				z = to.y
			places.append(Vector2(x, z))
			heights.append(float(height.call(x, z)))
	for i in n + 1:
		for j in n + 1:
			# The normal from the neighbours' heights, either side along each axis.
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, n)
			var dx := (heights[i1 * (n + 1) + j] - heights[i0 * (n + 1) + j]) / (coords[i1] - coords[i0])
			var dz := (heights[i * (n + 1) + j1] - heights[i * (n + 1) + j0]) / (coords[j1] - coords[j0])
			st.set_normal(Vector3(-dx, 1.0, -dz).normalized())
			var place := places[i * (n + 1) + j]
			st.add_vertex(Vector3(place.x, heights[i * (n + 1) + j], place.y))
	for i in n:
		for j in n:
			var a := i * (n + 1) + j
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			if holes[a] and holes[b] and holes[c] and holes[d]:
				continue
			# Clockwise seen from above, which is Godot's front.
			for idx in [a, c, b, c, d, b]:
				st.add_index(idx)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = st.commit()
	ground.material_override = _sand_mat
	add_child(ground)
	return ground


## The ratio each step of the ground's grid grows by past `inner`, so `count` of them, starting
## at `step`, reach `reach`. Found by halving: the sum of a geometric run.
func _growth(inner: float, step: float, reach: float, count: int) -> float:
	var lo := 1.0
	var hi := 2.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		var sum := 0.0
		var s := step
		for k in count:
			s *= mid
			sum += s
		if inner + sum < reach:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Under the tent and its ropes the ground is a hand under the floor (which covers it), so the
## two never share a plane; past that it is whatever the place makes of it.
func _camp_mask(x: float, z: float) -> float:
	var half := live_room_half() + 1.2
	var dx := maxf(absf(x) - half, 0.0)
	var dz := maxf(maxf(Studio.ROOM_FRONT - 1.2 - z, z - LIVE_ROOM_BACK - 1.2), 0.0)
	return smoothstep(0.0, 6.0, sqrt(dx * dx + dz * dz))


func _noise2(x: float, z: float, scale: float) -> float:
	return _noise.get_noise_2d(x * scale, z * scale)


# --- Starlit canyon ----------------------------------------------------------------------------

## How far the canyon's walls stand from the middle of it at depth z, and where its middle is: a
## slot that wanders, closes behind the tent where the canyon bends, and opens ahead onto the
## mesas.
func canyon_half(z: float) -> float:
	var w := live_room_half() + 9.0 + 2.5 * sin(z * 0.05)
	if z < -30.0:
		w += pow(-30.0 - z, 1.35) * 0.55
	return w


func canyon_middle(z: float) -> float:
	return 3.0 * sin(z * 0.035 + 0.4)


func _canyon_height(x: float, z: float) -> float:
	var mask := _camp_mask(x, z)
	var off := absf(x - canyon_middle(z))
	var wall := canyon_half(z)
	# Talus: the floor rising toward the walls' feet, out of fallen rock and blown sand.
	var talus := pow(maxf(off - (wall - 4.0), 0.0), 1.6) * 0.25
	var swells := _noise2(x, z, 0.05) * 0.6 + _noise2(x, z, 0.2) * 0.12
	# Past the mouth the land rolls away toward the mesas.
	var far := smoothstep(-60.0, -300.0, z) * (_noise2(x, z, 0.008) * 6.0 + 2.0)
	return -0.02 + mask * (swells + talus + far)


func _carve_the_canyon() -> void:
	_ground(900.0, _canyon_height)
	var strata := ShaderMaterial.new()
	strata.shader = preload("res://core/venues/shaders/desert_strata.gdshader")
	var wall_mesh := _piece("desert_rocks.glb", "canyon_wall", {"rock": strata})
	# The walls, segment by segment along each side, turned to face the camp, end to end with a
	# little overlap; the bend behind the tent closes the slot.
	var walls: Array = []
	for side: float in [-1.0, 1.0]:
		var z := -125.0
		while z < 60.0:
			var x: float = canyon_middle(z) + side * (canyon_half(z) + 1.0)
			var ahead: float = canyon_middle(z + 1.0) + side * (canyon_half(z + 1.0) + 1.0)
			var tangent := Vector2(ahead - x, 1.0).normalized()
			# Inward: toward the middle of the canyon.
			var inward := Vector2(tangent.y, -tangent.x) * (-side)
			var yaw := atan2(inward.x, inward.y)
			var tall := 1.0 + 0.18 * sin(z * 0.11 + side)
			walls.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.05, tall, 1.0)), Vector3(x, 0.0, z)))
			z += 24.0 * tangent.y
	for i in 3:
		var x := -26.0 + i * 26.0
		walls.append(Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(1.1, 1.1 - 0.08 * i, 1.0)),
				Vector3(x, 0.0, 62.0 + 4.0 * sin(i * 2.0))))
	_many("CanyonWalls", wall_mesh, walls)
	# Mesa country through the mouth: buttes and mesas standing out of the plain, far off.
	var butte := _piece("desert_rocks.glb", "butte", {"rock": strata})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var buttes: Array = []
	for i in 16:
		var a := rng.randf_range(-1.1, 1.1)
		var r := rng.randf_range(260.0, 820.0)
		var at := Vector2(sin(a) * r, -cos(a) * r - 80.0)
		var wide := rng.randf_range(50.0, 240.0)
		var tall := rng.randf_range(40.0, 120.0) * (1.4 if wide < 90.0 else 1.0)
		buttes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide, tall, wide * rng.randf_range(0.6, 1.4))),
				Vector3(at.x, -4.0, at.y)))
	_many("Buttes", butte, buttes)
	# Boulders fallen from the walls, along their feet, and a few nearer in.
	var boulders := ["boulder_a", "boulder_b", "boulder_c"]
	var placed: Array = [[], [], []]
	for i in 70:
		var z := rng.randf_range(-110.0, 55.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x: float = canyon_middle(z) + side * (canyon_half(z) - rng.randf_range(0.5, 6.0))
		if i < 10:
			# Near the camp, out in the floor, clear of the tent and its ropes.
			x = side * rng.randf_range(live_room_half() + 5.0, live_room_half() + 8.0)
			z = rng.randf_range(-20.0, 14.0)
		var s := rng.randf_range(0.6, 2.4)
		placed[i % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(x, _canyon_height(x, z) - 0.15 * s, z)))
	# Boulders are rounded: little sand lies on them.
	var stone := strata.duplicate() as ShaderMaterial
	stone.set_shader_parameter("ledge_sand", 0.2)
	for k in 3:
		_many("Boulders%d" % k, _piece("desert_rocks.glb", boulders[k], {"rock": stone}), placed[k], true)
	_plant_the_desert(rng, _canyon_height, func(x: float, z: float) -> bool:
		return absf(x - canyon_middle(z)) < canyon_half(z) - 2.0 and _camp_mask(x, z) > 0.9, 1.0)
	_light_the_fire(FIRE_AT, true)


## Cacti and dry scrub, wherever `keep` allows: saguaros standing up out of the floor, prickly
## pear and agave under them, scrub everywhere.
func _plant_the_desert(rng: RandomNumberGenerator, height: Callable, keep: Callable, saguaros: float) -> void:
	var cactus := _paint(Color(0.2, 0.3, 0.16), 0.85)
	var agave := _paint(Color(0.32, 0.42, 0.34), 0.8)
	var scrub := _paint(Color(0.3, 0.27, 0.16), 1.0)
	var kinds := [["saguaro", {"cactus": cactus}, int(14 * saguaros), 0.8, 1.2],
			["prickly_pear", {"cactus": cactus}, 26, 0.8, 1.5], ["agave", {"cactus": agave}, 30, 0.8, 1.6],
			["scrub", {"scrub": scrub}, 120, 0.6, 1.8]]
	for kind: Array in kinds:
		var at: Array = []
		var tries := 0
		while at.size() < int(kind[2]) and tries < 4000:
			tries += 1
			var r := sqrt(rng.randf()) * 140.0
			var a := rng.randf() * TAU
			var x := sin(a) * r
			var z := -cos(a) * r + 2.0
			if not bool(keep.call(x, z)):
				continue
			var s := rng.randf_range(kind[3], kind[4])
			at.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(x, float(height.call(x, z)) - 0.05, z)))
		_many(String(kind[0]).to_pascal_case(), _piece("desert_flora.glb", kind[0], kind[1]), at, kind[0] == "saguaro")


## The campfire (desert_props.glb): stones, logs, embers, flames licking out of it, sparks going
## up, and its light on the sand and the front of the tent. `burning` false is last night's fire
## at dawn: embers and smoke.
func _light_the_fire(at: Vector2, burning: bool) -> void:
	var stone := Materials.cached_scanned("desert_stone", "concrete_floor_worn_001", "2k", 0.5, Color(0.5, 0.36, 0.28))
	var logs := _paint(Color(0.16, 0.1, 0.06), 0.9)
	var ember := ZoneKit.glow(Color(1.0, 0.32, 0.08), 1.4 if burning else 0.7)
	var fire := _put(_piece("desert_props.glb", "campfire", {"stone": stone, "log": logs, "ember": ember}),
			Vector3(at.x, 0.0, at.y), 0.4, "Campfire")
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Logs to sit on, either side, and the teapot warming on the stones.
	var seat := CylinderMesh.new()
	seat.top_radius = 0.16
	seat.bottom_radius = 0.17
	seat.height = 1.5
	seat.radial_segments = 10
	for s: float in [-1.0, 1.0]:
		var bench := _put(seat, Vector3(at.x + s * 1.45, 0.16, at.y + s * 0.35), 0.0, "LogSeat")
		bench.rotation = Vector3(0, 0.4 + s * 0.2, PI * 0.5)
		bench.material_override = Materials.cached_scanned("desert_log", "weathered_brown_planks", "2k", 0.5,
				Color(0.42, 0.3, 0.22))
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.5, 0.5, 0.48)
	silver.metallic = 0.9
	silver.roughness = 0.35
	_put(_piece("desert_props.glb", "teapot", {"silver": silver}), Vector3(at.x + 0.48, 0.1, at.y + 0.12), 1.0, "FireKettle")
	if burning:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = preload("res://core/venues/shaders/desert_flame.gdshader")
		for k in 4:
			var q := QuadMesh.new()
			q.size = Vector2(0.55 - k * 0.06, 0.95 - k * 0.1)
			var tongue := _put(q, Vector3(at.x + (k % 2) * 0.05, 0.08 + q.size.y * 0.5, at.y), k * PI / 4.0, "Flame%d" % k)
			tongue.material_override = _flame_mat
			tongue.set_instance_shader_parameter("phase", k * 0.37)
			tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fire_light = OmniLight3D.new()
		_fire_light.name = "Firelight"
		_fire_light.position = Vector3(at.x, 0.6, at.y)
		_fire_light.light_color = Color(1.0, 0.52, 0.22)
		_fire_base = 3.2
		_fire_light.light_energy = _fire_base
		_fire_light.omni_range = 11.0
		_fire_light.omni_attenuation = 1.3
		_fire_light.light_specular = 0.1
		_fire_light.shadow_enabled = rich
		add_child(_fire_light)
	_sparks(Vector3(at.x, 0.3, at.y), burning)


## Sparks going up off the fire, or, from a dead one, a thin smoke.
func _sparks(at: Vector3, burning: bool) -> void:
	var dot := StandardMaterial3D.new()
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if burning else BaseMaterial3D.BLEND_MODE_MIX
	dot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dot.vertex_color_use_as_albedo = true
	dot.albedo_texture = _soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025) if burning else Vector2(0.5, 0.5)
	quad.material = dot
	var p := GPUParticles3D.new()
	p.name = "Sparks" if burning else "Smoke"
	p.position = at
	p.amount = 48 if burning else 24
	p.lifetime = 2.6 if burning else 7.0
	p.preprocess = 4.0
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 9, 6))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.2
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = 0.8 if burning else 0.25
	m.initial_velocity_max = 1.8 if burning else 0.45
	m.gravity = Vector3(0.15, 0.2, 0) if burning else Vector3(0.12, 0.05, -0.05)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 1.5
	var fade := Gradient.new()
	if burning:
		fade.set_color(0, Color(1.0, 0.75, 0.35, 1.0))
		fade.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	else:
		fade.set_color(0, Color(0.5, 0.45, 0.42, 0.18))
		fade.set_color(1, Color(0.6, 0.55, 0.5, 0.0))
		m.scale_min = 0.6
		m.scale_max = 1.0
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.3))
		grow.add_point(Vector2(1, 2.2))
		var gc := CurveTexture.new()
		gc.curve = grow
		m.scale_curve = gc
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	p.process_material = m
	add_child(p)


func _soft_dot() -> GradientTexture2D:
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
	return soft


# --- Dawn dunes --------------------------------------------------------------------------------

## The dunes: long transverse ridges across the wind, gentle up the windward side and steep down
## the slip face, smaller ones crossing them, and the great swell of the erg under all of it.
## Flat where the camp is pitched, in a hollow between them.
func dune_height(x: float, z: float) -> float:
	var mask := smoothstep(14.0, 50.0, Vector2(x, z - 2.0).length())
	var w := WIND.normalized()
	var p := Vector2(x, z)
	var s := p.dot(w) + _noise2(x, z, 0.004) * 60.0
	var t := fposmod(s / 58.0, 1.0)
	var ridge := smoothstep(0.0, 0.8, t) if t < 0.8 else 1.0 - smoothstep(0.8, 1.0, t)
	var big := 10.0 + 6.0 * _noise2(x, z, 0.006)
	var w2 := w.rotated(0.9)
	var t2 := fposmod((p.dot(w2) + _noise2(x, z, 0.01) * 20.0) / 21.0, 1.0)
	var ridge2 := smoothstep(0.0, 0.75, t2) if t2 < 0.75 else 1.0 - smoothstep(0.75, 1.0, t2)
	var swell := (_noise2(x, z, 0.0018) * 0.5 + 0.5) * 30.0 * smoothstep(80.0, 400.0, p.length())
	var near := _noise2(x, z, 0.08) * 0.25
	return -0.02 + _camp_mask(x, z) * (near + mask * (big * ridge + 2.2 * ridge2 + swell))


func _raise_the_dunes() -> void:
	_ground(1400.0, dune_height)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	_plant_the_desert(rng, dune_height, func(x: float, z: float) -> bool:
		return _camp_mask(x, z) > 0.9 and dune_height(x, z) < 3.0, 0.0)
	var strata := ShaderMaterial.new()
	strata.shader = preload("res://core/venues/shaders/desert_strata.gdshader")
	strata.set_shader_parameter("ledge_sand", 0.2)
	var placed: Array = [[], [], []]
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(16.0, 40.0)
		var x := sin(a) * r
		var z := -cos(a) * r + 2.0
		var s := rng.randf_range(0.4, 1.1)
		placed[i % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(x, dune_height(x, z) - 0.25 * s, z)))
	for k in 3:
		_many("Rocks%d" % k, _piece("desert_rocks.glb", ["boulder_a", "boulder_b", "boulder_c"][k], {"rock": strata}),
				placed[k], true)
	_caravan()
	_blow_sand()
	_light_the_fire(FIRE_AT + Vector2(0.6, 0.5), false)


## The highest point near `from` going along the wind and back: a dune's crest.
func _crest_near(from: Vector2) -> Vector3:
	var best := Vector3(from.x, dune_height(from.x, from.y), from.y)
	var w := WIND.normalized()
	for k in range(-40, 41):
		var p := from + w * float(k)
		var h := dune_height(p.x, p.y)
		if h > best.y:
			best = Vector3(p.x, h, p.y)
	return best


## A caravan going along a crest ahead and to the left, against the dawn: camels nose to tail,
## ridden and laden in turn, small with distance.
func _caravan() -> void:
	var hide := _paint(Color(0.3, 0.2, 0.13), 0.95)
	var cloth := _paint(Color(0.1, 0.1, 0.16), 0.95)
	var load_mat := _paint(Color(0.4, 0.3, 0.22), 0.95)
	var swap := {"hide": hide, "cloth": cloth, "load": load_mat}
	var along := WIND.normalized().rotated(PI * 0.5)
	var riders: Array = []
	var packs: Array = []
	var start := Vector2(-75.0, -95.0)
	for k in 7:
		var crest := _crest_near(start + along * (k * 4.2))
		var ahead := _crest_near(start + along * (k * 4.2 - 1.5))
		var dir := Vector2(ahead.x - crest.x, ahead.z - crest.z).normalized()
		# The camels walk along their own -X.
		var yaw := atan2(dir.y, -dir.x)
		var t := Transform3D(Basis(Vector3.UP, yaw), crest - Vector3(0, 0.05, 0))
		(riders if k % 3 == 0 else packs).append(t)
	_many("CaravanRiders", _piece("desert_camel.glb", "camel_rider", swap), riders)
	_many("CaravanPacks", _piece("desert_camel.glb", "camel_pack", swap), packs)


## Sand lifted off the crests by the wind, in streamers along the ridges nearest the camp, and a
## low skein of it running over the hollow the tent stands in.
func _blow_sand() -> void:
	# Lit, not glowing: blown sand is the sand's own colour in the same sun (unshaded, the tone
	# mapping took it to white and the crests looked snowed on).
	var grain := StandardMaterial3D.new()
	grain.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	grain.roughness = 1.0
	grain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grain.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	grain.vertex_color_use_as_albedo = true
	grain.albedo_texture = _soft_dot()
	var w := WIND.normalized()
	var along := w.rotated(PI * 0.5)
	var spots: Array[Vector3] = []
	for k in 7:
		var a := -1.2 + k * 0.4
		var from := Vector2(sin(a), -cos(a)) * (55.0 + 25.0 * (k % 3)) + Vector2(0, 2)
		spots.append(_crest_near(from))
	for i in spots.size():
		var quad := QuadMesh.new()
		# Puffs rather than grains: far off, a crest smokes; it does not sparkle.
		quad.size = Vector2(1.1, 0.7)
		quad.material = grain
		var p := GPUParticles3D.new()
		p.name = "BlownSand%d" % i
		p.position = spots[i] + Vector3(0, 0.2, 0)
		p.rotation.y = atan2(along.x, along.y)
		p.amount = 220
		p.lifetime = 3.5
		p.preprocess = 4.0
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 15, 60))
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(0.6, 0.1, 14.0)
		m.particle_flag_disable_z = false
		var dir := Vector3(w.x, 0.25, w.y)
		# The particles' own direction is in the emitter's frame, which is turned along the crest.
		m.direction = Basis(Vector3.UP, -p.rotation.y) * dir
		m.spread = 10.0
		m.initial_velocity_min = 2.5
		m.initial_velocity_max = 5.0
		m.gravity = Vector3(0, -0.6, 0)
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 0.8
		m.turbulence_noise_scale = 3.0
		m.scale_min = 0.5
		m.scale_max = 2.4
		var fade := Gradient.new()
		fade.set_color(0, Color(0.92, 0.64, 0.42, 0.0))
		fade.add_point(0.2, Color(0.92, 0.62, 0.4, 0.13))
		fade.set_color(1, Color(0.86, 0.58, 0.38, 0.0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		m.color_ramp = ramp
		p.process_material = m
		add_child(p)
	# Over the hollow, ankle high, in front of the tent: a few grains skittering past.
	var drift := GPUParticles3D.new()
	drift.name = "Skitter"
	drift.position = Vector3(0, 0.15, -9.0)
	drift.amount = 160
	drift.lifetime = 4.0
	drift.preprocess = 4.0
	var small := QuadMesh.new()
	small.size = Vector2(0.06, 0.06)
	small.material = grain
	drift.draw_pass_1 = small
	drift.visibility_aabb = AABB(Vector3(-25, -1, -12), Vector3(50, 4, 24))
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(16.0, 0.12, 4.0)
	dm.direction = Vector3(w.x, 0.05, w.y)
	dm.spread = 6.0
	dm.initial_velocity_min = 1.5
	dm.initial_velocity_max = 3.0
	dm.gravity = Vector3(0, -0.2, 0)
	var dfade := Gradient.new()
	dfade.set_color(0, Color(1.0, 0.85, 0.65, 0.0))
	dfade.add_point(0.3, Color(1.0, 0.85, 0.65, 0.35))
	dfade.set_color(1, Color(1.0, 0.85, 0.65, 0.0))
	var dramp := GradientTexture1D.new()
	dramp.gradient = dfade
	dm.color_ramp = dramp
	drift.process_material = dm
	add_child(drift)


# --- Oasis -------------------------------------------------------------------------------------

## How far (x, z) is from the pool's middle, as a fraction of its radii: 1 at the water's rim.
func pool_reach(x: float, z: float) -> float:
	return Vector2((x - POOL.x) / POOL_RADII.x, (z - POOL.y) / POOL_RADII.y).length()


func _oasis_height(x: float, z: float) -> float:
	var rn := pool_reach(x, z)
	# The bank: down from the grass to under the water over the last stretch to the middle.
	var bank := -0.62 * smoothstep(1.12, 0.84, rn)
	var swells := _noise2(x, z, 0.04) * 0.5 * smoothstep(1.4, 2.5, rn)
	var rise := smoothstep(60.0, 300.0, Vector2(x, z).length()) * (_noise2(x, z, 0.006) * 8.0 + 6.0)
	# The bank is the pool's own and is not eased into the camp's floor: its rim is clear of it.
	return -0.02 + bank + _camp_mask(x, z) * (swells + rise)


func _make_the_oasis() -> void:
	# Open under the water, well inside where the bank goes under it.
	_ground(800.0, _oasis_height, func(x: float, z: float) -> bool: return pool_reach(x, z) < 0.8,
			func(x: float, z: float) -> Vector2:
				var off := Vector2(x - POOL.x, z - POOL.y) / POOL_RADII
				return POOL + off.normalized() * 0.8 * POOL_RADII if off.length() > 0.001 else POOL)
	var water := MeshInstance3D.new()
	water.name = "Pool"
	# A disc to the pool's rim, flattened to its oval; its edge runs a little into the bank.
	var sheet := CylinderMesh.new()
	sheet.top_radius = 1.0
	sheet.bottom_radius = 1.0
	sheet.height = 0.001
	sheet.radial_segments = 64
	sheet.rings = 1
	sheet.cap_bottom = false
	water.mesh = sheet
	water.scale = Vector3(POOL_RADII.x, 1.0, POOL_RADII.y)
	water.position = Vector3(POOL.x, WATER, POOL.y)
	var still := ShaderMaterial.new()
	still.shader = preload("res://core/venues/shaders/desert_water.gdshader")
	still.set_shader_parameter("centre", POOL)
	still.set_shader_parameter("extent", POOL_RADII * 0.7)
	water.material_override = still
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# What the water gives back: the world past it, upside down under it (Godot turns the faces
	# of a mirrored node itself). The pool is the only hole in the ground to see it through.
	var mirror := Node3D.new()
	mirror.name = "Reflection"
	mirror.position.y = WATER * 2.0
	mirror.scale = Vector3(1, -1, 1)
	add_child(mirror)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	_plant_palms(rng, mirror)
	_plant_reeds(rng)
	_build_the_village(mirror)
	_light_the_pool(mirror)
	_fireflies()
	_plant_the_desert(rng, _oasis_height, func(x: float, z: float) -> bool:
		return _camp_mask(x, z) > 0.9 and pool_reach(x, z) > 1.6 and absf(x) < 60.0 and z > -60.0, 0.0)


## Date palms: a ring round the water leaning out over it, a grove behind on either side, and
## their reflections in the pool.
func _plant_palms(rng: RandomNumberGenerator, mirror: Node3D) -> void:
	var trunk := Materials.cached_scanned("desert_palm", "weathered_brown_planks", "2k", 0.6, Color(0.5, 0.38, 0.28))
	var frond := _paint(Color(0.16, 0.26, 0.12), 0.85)
	frond.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dates := _paint(Color(0.5, 0.24, 0.08), 0.6)
	var mesh := _piece("desert_flora.glb", "date_palm", {"trunk": trunk, "frond": frond, "dates": dates})
	var at: Array = []
	# Round the pool: every few metres of its rim, a little out from it, leaning over the water.
	for k in 15:
		var a := k * TAU / 15.0 + rng.randf_range(-0.12, 0.12)
		var ring := rng.randf_range(1.12, 1.4)
		var x := POOL.x + sin(a) * POOL_RADII.x * ring
		var z := POOL.y - cos(a) * POOL_RADII.y * ring
		if z > POOL.y and absf(x - POOL.x) < POOL_RADII.x * 0.75:
			# Not between the tent and the water: the view from the desk is over the pool.
			continue
		var toward := Vector3(POOL.x - x, 0, POOL.y - z).normalized()
		var lean := Basis(toward.cross(Vector3.UP).normalized(), -rng.randf_range(0.06, 0.2))
		var s := rng.randf_range(0.75, 1.1)
		at.append(Transform3D(lean * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(x, _oasis_height(x, z) - 0.1, z)))
	# The groves either side of the camp and behind the pool.
	for k in 46:
		var x := rng.randf_range(12.0, 40.0) * (-1.0 if k % 2 == 0 else 1.0)
		var z := rng.randf_range(-34.0, 22.0)
		if k > 36:
			x = rng.randf_range(-22.0, 22.0)
			z = rng.randf_range(-26.0, -19.0)
		var s := rng.randf_range(0.7, 1.2)
		at.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s) * Basis(Vector3.FORWARD,
				rng.randf_range(-0.08, 0.08)), Vector3(x, _oasis_height(x, z) - 0.1, z)))
	_many("Palms", mesh, at, true)
	_many("PalmReflections", mesh, at, false, mirror)


func _plant_reeds(rng: RandomNumberGenerator) -> void:
	var reed := _paint(Color(0.3, 0.36, 0.16), 0.9)
	reed.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := _paint(Color(0.25, 0.14, 0.07), 0.9)
	var at: Array = []
	for k in 30:
		var a := rng.randf() * TAU
		var ring := rng.randf_range(0.9, 1.05)
		var x := POOL.x + sin(a) * POOL_RADII.x * ring
		var z := POOL.y - cos(a) * POOL_RADII.y * ring
		# Thinner on the near side, so the water shows from the tent.
		if z > POOL.y + POOL_RADII.y * 0.5 and rng.randf() < 0.7:
			continue
		at.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)),
				Vector3(x, _oasis_height(x, z), z)))
	_many("Reeds", _piece("desert_flora.glb", "reeds", {"reed": reed, "bulrush": head}), at)


## The village's mud brick: a wall across the far side of the pool with a gate in it, walls down
## either side to the camp, buttressed and crenellated, and a tower over the gate with its windows
## lit. The far wall and the tower are given back by the water too.
func _build_the_village(mirror: Node3D) -> void:
	var adobe := Materials.cached_scanned("desert_adobe", "coast_sand_01", "1k", 1.4, Color(0.64, 0.45, 0.32))
	var lit := ZoneKit.glow(Color(1.0, 0.6, 0.28), 1.3)
	var dark := _paint(Color(0.05, 0.035, 0.03), 1.0)
	for target: Node3D in [self, mirror]:
		var holder := Node3D.new()
		holder.name = "Village"
		target.add_child(holder)
		var far := -27.0
		# The far wall, in two runs either side of the gate.
		# Each run ends inside a gate pier, so its end is never a face of its own beside the pier's.
		for run in [[-42.0, -2.4], [2.6, 42.0]]:
			_mud_wall(holder, Vector3(run[0], 0, far), Vector3(run[1], 0, far), 3.2, adobe)
		# The gate: two piers and a lintel, the dark of the lane through it.
		for s: float in [-1.0, 1.0]:
			ZoneKit.block(holder, Vector3(0.9, 4.2, 1.0), Vector3(0.1 + s * 2.55, 2.1, far), adobe, "GatePier")
		ZoneKit.block(holder, Vector3(4.2, 0.9, 0.96), Vector3(0.1, 4.2 - 0.45 + 0.004, far), adobe, "GateLintel")
		ZoneKit.block(holder, Vector3(4.18, 3.3, 0.2), Vector3(0.1, 1.65, far - 1.8), dark, "Lane")
		# The tower beside the gate: tapering, its parapet stepped, windows lit.
		_tower(holder, Vector2(-7.0, far - 2.2), adobe, lit)
		if target == mirror:
			continue
		# The side walls, back toward the camp, outside the tent's ropes.
		for s: float in [-1.0, 1.0]:
			_mud_wall(holder, Vector3(s * 42.0, 0, far + 0.4), Vector3(s * 42.0, 0, 18.0), 2.8, adobe)
		# A house behind the tent on the left, its door lit.
		var house := Vector3(-(live_room_half() + 11.0), 0, 14.0)
		ZoneKit.block(holder, Vector3(7.0, 3.6, 5.0), house + Vector3(0, 1.8, 0), adobe, "House")
		ZoneKit.block(holder, Vector3(1.0, 1.9, 0.1), house + Vector3(2.0, 0.97, -2.52), lit, "HouseDoor")
		ZoneKit.block(holder, Vector3(0.5, 0.6, 0.1), house + Vector3(-1.6, 2.2, -2.52), lit, "HouseWindow")
		_tower(holder, Vector2(live_room_half() + 16.0, 20.0), adobe, lit)


## A run of mud wall from `a` to `b` (on the ground): the wall, buttresses every few metres on its
## inside face, and stepped merlons along its top, narrower than it so no face is shared.
func _mud_wall(parent: Node3D, a: Vector3, b: Vector3, tall: float, adobe: Material) -> void:
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var yaw := atan2(b.x - a.x, b.z - a.z) - PI * 0.5
	var wall := Node3D.new()
	wall.name = "MudWall"
	wall.position = mid
	wall.rotation.y = yaw
	parent.add_child(wall)
	ZoneKit.block(wall, Vector3(length, tall, 0.6), Vector3(0, tall * 0.5 - 0.1, 0), adobe, "Wall")
	var count := int(length / 4.5)
	# Not at the ends, where another run or a gate pier meets this one.
	for i in range(1, count):
		var x := -length * 0.5 + i * length / maxi(count, 1)
		# Its foot a little deeper than the wall's, so the two bottoms are not one plane.
		ZoneKit.block(wall, Vector3(0.7, tall * 0.8, 0.5), Vector3(x, tall * 0.4 - 0.12, 0.52), adobe, "Buttress")
	var merlons := int(length / 0.9)
	var mm: Array = []
	for i in merlons:
		mm.append(Transform3D(Basis(), Vector3(-length * 0.5 + (i + 0.5) * length / merlons, tall - 0.1 + 0.22, 0)))
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.42, 0.44, 0.52)
	_many("Merlons", tooth, mm, true, wall).material_override = adobe


## A tower: a tapering block (a four-sided frustum), a parapet of merlons, small windows lit.
func _tower(parent: Node3D, at: Vector2, adobe: Material, lit: Material) -> void:
	var body := CylinderMesh.new()
	body.top_radius = 2.6
	body.bottom_radius = 3.3
	body.height = 11.0
	body.radial_segments = 4
	body.rings = 1
	var t := _put(body, Vector3(at.x, 5.5, at.y), PI * 0.25, "Tower", parent)
	t.material_override = adobe
	# The parapet: a merlon at each corner and between.
	var half := 2.6 * 0.7071
	for i in 8:
		var a := i * TAU / 8.0
		var p := Vector3(cos(a), 0, sin(a))
		p = p / maxf(absf(p.x), absf(p.z)) * (half - 0.25)
		ZoneKit.block(parent, Vector3(0.5, 0.7, 0.5), Vector3(at.x + p.x, 11.0 + 0.35, at.y + p.z), adobe, "TowerMerlon")
	# Windows, two up each face toward the camp and one on the sides, set into the batter.
	for spec in [[Vector3(-0.8, 6.5, 1.0)], [Vector3(0.9, 8.6, 1.0)], [Vector3(0.0, 3.6, 1.0)]]:
		var w: Vector3 = spec[0]
		var y := w.y
		var r := lerpf(3.3, 2.6, y / 11.0) * 0.7071
		ZoneKit.block(parent, Vector3(0.38, 0.6, 0.3), Vector3(at.x + w.x, y, at.y + r - 0.05), lit, "TowerWindow")


## Lanterns on iron crooks round the water, the light of each lying in the water under it,
## stretched by the ripples into a column, and two soft lights over the bank.
func _light_the_pool(mirror: Node3D) -> void:
	var iron := _paint(Color(0.06, 0.05, 0.045), 0.6)
	var glow := ZoneKit.glow(Color(1.0, 0.62, 0.28), 1.6)
	var lights := 0
	# Round the far side and the ends: from the tent, their light lies across the water toward you.
	for k in 7:
		var a := -1.7 + k * (3.4 / 6.0)
		var x := POOL.x + sin(a) * POOL_RADII.x * 1.08
		var z := POOL.y - cos(a) * POOL_RADII.y * 1.08
		var ground := _oasis_height(x, z)
		var top := ground + 2.0
		ZoneKit.block(self, Vector3(0.04, 2.0, 0.04), Vector3(x, ground + 1.0, z), iron, "Crook")
		var reach := Vector2(POOL.x - x, POOL.y - z).normalized() * 0.32
		var arm := ZoneKit.block(self, Vector3(0.03, 0.03, 0.34), Vector3(x + reach.x * 0.5, top, z + reach.y * 0.5), iron,
				"CrookArm")
		arm.rotation.y = atan2(reach.x, reach.y)
		var foot := Vector3(x + reach.x, top - 0.08 - LANTERN_RING, z + reach.y)
		_lantern(foot, "PoolLantern%d" % k)
		_lantern(foot, "PoolLanternReflection%d" % k, mirror)
		# Its light in the water: a column of glow, broken by the ripples, under the lantern.
		var column := QuadMesh.new()
		column.size = Vector2(0.18, 1.6)
		var streak := _put(column, Vector3(foot.x, WATER - 0.01 - 0.8 - (foot.y - WATER) * 0.6, foot.z), 0.0,
				"LanternInWater%d" % k)
		var m := glow.duplicate() as StandardMaterial3D
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _soft_dot()
		m.albedo_color = Color(1.0, 0.6, 0.26, 0.55) * Color(1.6, 1.6, 1.6, 1.0)
		streak.material_override = m
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if k % 3 == 0 and lights < 3:
			_lantern_light(foot + Vector3(0, 0.2, 0), 2.2, 6.0)
			lights += 1


## Fireflies and the insects of a summer evening over the reeds: specks of green-gold light that
## wander and wink.
func _fireflies() -> void:
	var dot := StandardMaterial3D.new()
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dot.vertex_color_use_as_albedo = true
	dot.albedo_texture = _soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = dot
	var p := GPUParticles3D.new()
	p.name = "Fireflies"
	p.position = Vector3(POOL.x, 0.9, POOL.y)
	p.amount = 90
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-14, -2, -10), Vector3(28, 6, 20))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(POOL_RADII.x * 1.2, 0.7, POOL_RADII.y * 1.2)
	m.direction = Vector3(0, 1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 0.05
	m.initial_velocity_max = 0.2
	m.gravity = Vector3.ZERO
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.4
	m.turbulence_noise_scale = 2.0
	var wink := Gradient.new()
	wink.set_color(0, Color(0.7, 1.0, 0.3, 0.0))
	wink.add_point(0.15, Color(0.75, 1.0, 0.35, 1.0))
	wink.add_point(0.3, Color(0.7, 1.0, 0.3, 0.0))
	wink.add_point(0.55, Color(0.7, 1.0, 0.3, 0.0))
	wink.add_point(0.7, Color(0.8, 1.0, 0.4, 0.9))
	wink.set_color(wink.get_point_count() - 1, Color(0.7, 1.0, 0.3, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = wink
	m.color_ramp = ramp
	p.process_material = m
	add_child(p)
