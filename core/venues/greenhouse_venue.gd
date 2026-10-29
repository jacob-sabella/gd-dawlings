class_name GreenhouseVenue
extends Venue

## A Victorian palm house in a botanical garden. One long glass nave over the room, its roof
## stepped the way the great Victorian houses are: glazed walls on a brick dwarf wall, a curved
## aisle roof springing from them, a clerestory carried on a lattice girder and a row of fluted
## cast-iron columns, and over the middle a tall elliptical barrel vault -- all of it white-painted
## iron and thin old glass, the gable ends filled with a sunburst. Underfoot, encaustic tiles.
##
## The walk round the desk and back to the zones is tiled; past a stone kerb on every side lie
## the planted borders (kentia and fan palms, tree ferns, bananas, monstera, ferns, the beds
## mulched dark), with hanging baskets of fern under the aisle roofs, a stone fountain at the
## front-left and an urn at the front-right, and along the back, behind the zones, the potting
## side: tiered staging full of terracotta pots and the potting benches. Outside the glass the
## garden: a gravel walk running away from the front between box hedges and clipped yews, lamp
## posts along it, lawns mown in stripes, and trees.
##
## Three arrangements, three weathers (Venue.VARIANTS): Morning (a low sun through the glass
## laying the bars' shadows over the tiles, haze, dew), Rain (an overcast afternoon, rain falling
## outside and running down the glass, drips, wet tiles, the house's lanterns lit), and Night
## bloom (the moon through the roof, strings of warm lights wound round the columns and through
## the planting, night-blooming flowers glowing pale, and fireflies).

const MORNING := 0
const RAIN := 1
const NIGHT := 2

## The front of the walk: the footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The stone kerb round the walk, and the planted border past it to the dwarf wall.
const KERB := 0.3
const KERB_H := 0.22
const BED := 1.6
## The beds' mulch, a little under the kerb's top.
const SOIL := 0.17
## The brick dwarf wall the glass stands on.
const DWARF := 0.32
const DWARF_H := 0.8
## The section: the side walls' glass to the eaves, the aisle roof curving up to the clerestory
## sill (where the columns and the girder are), the clerestory, and the vault's rise over it.
const EAVES := 3.6
const CLERE_SILL := 5.0
const CLERE_HEAD := 5.8
const GIRDER := 0.42
const VAULT_RISE := 4.4
## About how far apart the main ribs are; the house is cut into whole bays of it.
const RIB_EVERY := 1.45
## The iron: the ribs and the finer glazing bars between them, and how far in from the glass.
const RIB := Vector2(0.07, 0.15)
const BAR := Vector2(0.024, 0.05)
const IN_FROM_GLASS := 0.012
## The fountain's scale (greenhouse_props.glb's is 2.5 m across) and how far in front of the
## walk's front edge its middle stands.
const FOUNTAIN_SCALE := 0.85
const FOUNTAIN_BACK := 0.72
const DOOR_HALF := 0.8
const DOOR_HEAD := 2.7

const PLANTS := "res://assets/models/greenhouse_plants.glb"
const PROPS := "res://assets/models/greenhouse_props.glb"

## Per weather: the sky (zenith, horizon, below, cloud cover, lit and dark cloud, sun disc and
## glow, moon size, stars, energy), the light from everywhere, the haze, the key (colour, energy,
## pitch, yaw), how wet the glass, the tiles and the lawn are, the dew, and the lanterns.
const WEATHERS := [
	{"zenith": Color(0.26, 0.42, 0.68), "horizon": Color(0.74, 0.7, 0.6), "below": Color(0.42, 0.44, 0.36),
			"cover": 0.32, "cloud_lit": Color(1.0, 0.95, 0.86), "cloud_dark": Color(0.66, 0.66, 0.7),
			"sun": 0.022, "glow": 0.4, "moon": 0.0, "stars": 0.0, "energy": 0.34,
			"ambient": [Color(0.72, 0.76, 0.8), 0.15], "fog": Color(0.34, 0.36, 0.32), "fog_end": 300.0,
			"key": [Color(1.0, 0.8, 0.58), 1.7, -19.0, 218.0], "rain": 0.0, "wet": 0.0, "dew": 0.8,
			"lanterns": 0.0, "exposure": 0.66},
	{"zenith": Color(0.3, 0.32, 0.35), "horizon": Color(0.46, 0.48, 0.5), "below": Color(0.25, 0.27, 0.27),
			"cover": 1.0, "cloud_lit": Color(0.55, 0.57, 0.6), "cloud_dark": Color(0.36, 0.38, 0.41),
			"sun": 0.0, "glow": 0.0, "moon": 0.0, "stars": 0.0, "energy": 0.6,
			"ambient": [Color(0.58, 0.63, 0.7), 0.17], "fog": Color(0.22, 0.24, 0.26), "fog_end": 80.0,
			"key": [Color(0.78, 0.82, 0.9), 0.35, -62.0, 200.0], "rain": 1.0, "wet": 1.0, "dew": 0.2,
			"lanterns": 1.0, "exposure": 0.76},
	{"zenith": Color(0.008, 0.012, 0.03), "horizon": Color(0.04, 0.05, 0.08), "below": Color(0.015, 0.02, 0.025),
			"cover": 0.12, "cloud_lit": Color(0.2, 0.22, 0.28), "cloud_dark": Color(0.04, 0.05, 0.07),
			"sun": 0.0, "glow": 0.0, "moon": 0.03, "stars": 1.6, "energy": 1.0,
			"ambient": [Color(0.3, 0.36, 0.55), 0.08], "fog": Color(0.02, 0.03, 0.05), "fog_end": 120.0,
			"key": [Color(0.62, 0.72, 1.0), 0.42, -52.0, 158.0], "rain": 0.0, "wet": 0.0, "dew": 0.0,
			"lanterns": 0.35},
]
## The moon, high and in front: the key light comes from here at night.
const MOON_DIR := Vector3(-0.42, 0.78, -0.47)

var _sky_mat: ShaderMaterial
var _glass_mat: ShaderMaterial
var _firefly_mat: ShaderMaterial
var _string_mat: StandardMaterial3D
var _string_lights: Array[OmniLight3D] = []
var _smoothed := 0.0
## The plants, per kind (an object in greenhouse_plants.glb), where each stands: kept for the
## tests and for the night's flowers, which grow on them.
var planted := {}
var _plant_scene: Node
var _prop_scene: Node


func venue_id() -> StringName:
	return &"greenhouse"


## The walls are glass from a dwarf wall up, and there is no wall at all at the footprint's front
## edge or along its right-hand side -- the planted borders are there, and the glass is past them.
## Nothing to hang the roll board or the roulette panel on: they stand.
func back_wall_gear_stands() -> bool:
	return true


## Glasshouse kit: staging painted Brunswick green, teak cheeks, polished brass, and the white of
## the ironwork for the lamps; terracotta looms and porcelain plant-label caps.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.paint(Color(0.1, 0.19, 0.14), 0.55, 0.15)) \
			.with("chassis", GearStyle.paint(Color(0.06, 0.08, 0.07), 0.55, 0.3)) \
			.with("brushed", GearStyle.metal(Color(0.72, 0.6, 0.36), 0.38)) \
			.with("trim", GearStyle.metal(Color(0.78, 0.64, 0.34), 0.3)) \
			.with("end_cheek", GearStyle.scan("black_walnut_veneer_01", 0.8, Color(0.85, 0.62, 0.42))) \
			.with("lamp_shade", GearStyle.paint(Color(0.82, 0.83, 0.79), 0.45, 0.05)) \
			.with("loom_band", GearStyle.paint(Color(0.68, 0.34, 0.2), 0.8, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.9, 0.88, 0.8), 0.25, 0.0))


## A white-painted plant label writ large: dark green lettering, terracotta arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.paint(Color(0.8, 0.81, 0.76), 0.6, 0.0)
	board.ink = Color(0.1, 0.24, 0.16)
	board.accent = Color(0.72, 0.34, 0.2)
	board.board_ink_fade = Color(0.5, 0.56, 0.5)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	var w: Dictionary = WEATHERS[variant]
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/greenhouse_sky.gdshader")
	for p in ["zenith", "horizon", "below", "cloud_lit", "cloud_dark"]:
		_sky_mat.set_shader_parameter(p, w[p])
	_sky_mat.set_shader_parameter("cover", w["cover"])
	_sky_mat.set_shader_parameter("sun_dir", _key_basis(w).z)
	_sky_mat.set_shader_parameter("sun_radius", w["sun"])
	_sky_mat.set_shader_parameter("sun_glow", w["glow"])
	_sky_mat.set_shader_parameter("moon_dir", MOON_DIR)
	_sky_mat.set_shader_parameter("moon_radius", w["moon"])
	_sky_mat.set_shader_parameter("stars", w["stars"])
	_sky_mat.set_shader_parameter("energy", w["energy"])
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = w["ambient"][0]
	env.ambient_light_energy = w["ambient"][1]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = w.get("exposure", 1.0)
	env.glow_enabled = true
	env.glow_intensity = 0.32 if variant == RAIN else 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.15
	# The garden's air: morning haze, the rain's grey, the dark.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = w["fog"]
	env.fog_depth_begin = 24.0
	env.fog_depth_end = w["fog_end"]
	env.fog_sky_affect = 0.0
	if variant == MORNING:
		env.fog_sun_scatter = 0.08
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.0
		env.ssr_enabled = variant == RAIN
		env.ssr_max_steps = 48
		if variant == MORNING:
			# The low sun in the damp air: shafts through the glass between the bars.
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.005
			env.volumetric_fog_albedo = Color(1.0, 0.95, 0.88)
			env.volumetric_fog_length = 24.0
			env.volumetric_fog_ambient_inject = 0.0
			env.volumetric_fog_anisotropy = 0.6

	key.light_color = w["key"][0]
	key.light_energy = w["key"][1]
	key.basis = _key_basis(w)
	key.light_specular = 0.2


## Where the key comes from: the low morning sun from the front-left, the grey of the rain from
## high overhead, the moon high in front.
func _key_basis(w: Dictionary) -> Basis:
	if variant == NIGHT:
		return Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
	return Basis.from_euler(Vector3(deg_to_rad(w["key"][2]), deg_to_rad(w["key"][3]), 0.0))


func lamp_colour(_index: int, authored: Color) -> Color:
	# Brass and warm filament: the lanterns' colour.
	return authored.lerp(Color(1.0, 0.76, 0.5), 0.3)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * ([0.75, 0.62, 0.9][variant])


## Fast up, slow down. At night the fireflies light more often and brighter with the music, and
## the strings swell; the rest of the time the house is still.
func pulse(level: float) -> void:
	var k := 0.5 if level > _smoothed else 0.06
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	if _firefly_mat != null:
		_firefly_mat.set_shader_parameter("pulse", _smoothed)
	if _string_mat != null:
		_string_mat.albedo_color = Color(1.0, 0.7, 0.36) * (1.8 + 1.4 * _smoothed)
	for l in _string_lights:
		l.light_energy = 0.55 + 0.45 * _smoothed


## The walk: the floor beside the desk and the back of house, as in the loft; past it, the kerb.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 43): eight terracotta pots
## upside down on a potting bench, at the potting side along the back, between the kit and the
## lattice.
func instrument() -> Dictionary:
	return {"kind": &"pots", "spot": back_wall_instrument(0.2)}


## Its weather (Weather, docs/spatial_loop.md part two, slice 44): in the Rain, the rain on the left
## side's glass, one bay of it beside the desk, and the switch on a cast-iron post at the walk's edge
## in front of it, the planted bed between (the glass is past the bed, out of a hand's reach). No
## weather in the morning or the night.
func weather() -> Dictionary:
	if variant != RAIN:
		return {}
	var half := live_room_half()
	var along := 1.25
	var turn := Basis(Vector3.UP, PI * 0.5)
	# The post's whole foot on the walk, not half over the kerb.
	return {"kind": &"rain", "spot": Transform3D(turn, Vector3(-half + 0.16, 0, along)), "sill": 0.95, "post": true,
			"glass": Transform3D(turn, Vector3(-wall_x() + 0.04, (DWARF_H + EAVES) * 0.5, along)),
			"size": Vector2(RIB_EVERY - 0.2, EAVES - DWARF_H - 0.2), "low": 74}


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	# The fountain's basin stands a little into the walk: you walk up to its rim.
	var f := fountain_spot()
	var r := 1.27 * FOUNTAIN_SCALE * 0.9
	out.append({"c": Vector2(f.x, f.z), "h": Vector2(r, r), "a": 0.0, "top": 0.6 * FOUNTAIN_SCALE})
	return out


# --- the plan ---------------------------------------------------------------------------------

## The line of the columns: on the kerb, a step past the walk's edge.
func column_x() -> float:
	return live_room_half() + KERB * 0.5


## The glass walls' line: the middle of the dwarf wall, past the kerb and the border.
func wall_x() -> float:
	return live_room_half() + KERB + BED + DWARF * 0.5


func front_z() -> float:
	return FRONT - KERB - BED - DWARF * 0.5


func back_z() -> float:
	return LIVE_ROOM_BACK + KERB + BED + DWARF * 0.5


## Where the fountain stands: in the front border at the end of the strip beside the desk on
## the left, its basin's rim reaching into the walk.
func fountain_spot() -> Vector3:
	return Vector3(-(room_width * 0.5 + live_room_half()) * 0.5, 0.0, FRONT - FOUNTAIN_BACK)


func urn_spot() -> Vector3:
	return Vector3((room_width * 0.5 + live_room_half()) * 0.5, 0.0, FRONT - 0.78)


## Every main rib, front to back: the house cut into whole bays. The end ones stand a little in
## from the gable glass.
func rib_z() -> Array[float]:
	var n := maxi(6, roundi((back_z() - front_z()) / RIB_EVERY))
	var bay := (back_z() - front_z()) / n
	var out: Array[float] = []
	for k in n + 1:
		var z := front_z() + bay * k
		if k == 0:
			z += RIB.x * 0.5 + IN_FROM_GLASS
		elif k == n:
			z -= RIB.x * 0.5 + IN_FROM_GLASS
		out.append(z)
	return out


## The columns: under every other rib, both sides, none at the ends.
func column_z() -> Array[float]:
	var ribs := rib_z()
	var out: Array[float] = []
	for k in range(2, ribs.size() - 1, 2):
		out.append(ribs[k])
	return out


## The section through the house, from the right-hand foot of the glass round over the top to
## the left: the wall, the aisle roof, the clerestory and the vault. (x, y) in studio space.
func section() -> PackedVector2Array:
	var w := wall_x()
	var c := column_x()
	var pts := PackedVector2Array()
	pts.append(Vector2(w, DWARF_H))
	var aisle := 8
	for i in aisle + 1:
		var t := PI * 0.5 * i / aisle
		pts.append(Vector2(c + (w - c) * cos(t), EAVES + (CLERE_SILL - EAVES) * sin(t)))
	var vault := 28
	for i in vault + 1:
		var t := PI * i / vault
		pts.append(Vector2(c * cos(t), CLERE_HEAD + VAULT_RISE * sin(t)))
	for i in range(aisle, -1, -1):
		var t := PI * 0.5 * i / aisle
		pts.append(Vector2(-c - (w - c) * cos(t), EAVES + (CLERE_SILL - EAVES) * sin(t)))
	pts.append(Vector2(-w, DWARF_H))
	return pts


## How high the glass is over `x`.
func roof_at(x: float) -> float:
	var ax := absf(x)
	var c := column_x()
	var w := wall_x()
	if ax <= c:
		return CLERE_HEAD + VAULT_RISE * sqrt(maxf(0.0, 1.0 - (ax / c) * (ax / c)))
	if ax <= w:
		var u := (ax - c) / (w - c)
		return EAVES + (CLERE_SILL - EAVES) * sqrt(maxf(0.0, 1.0 - u * u))
	return DWARF_H


func _ready() -> void:
	_plant_scene = (load(PLANTS) as PackedScene).instantiate()
	_prop_scene = (load(PROPS) as PackedScene).instantiate()
	_lay_the_floor()
	_lay_the_garden()
	_build_dwarf_wall()
	_raise_the_glass()
	_raise_the_ironwork()
	_raise_the_columns()
	_plant_the_borders()
	_hang_the_baskets()
	_set_up_the_potting_side()
	_place_the_fountain()
	_hang_the_lanterns()
	match variant:
		MORNING:
			_slant_the_sun()
		RAIN:
			_let_it_rain()
		NIGHT:
			_string_the_lights()
			_open_the_flowers()
			_release_the_fireflies()
	_dress_zones()
	_plant_scene.free()
	_prop_scene.free()


# --- materials -------------------------------------------------------------------------------

## The ironwork: cast iron painted white, the paint thick and a little chalky.
func _white_iron() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.81, 0.78)
	m.roughness = 0.5
	m.metallic_specular = 0.4
	return m


## The staging, the door and the zones' iron: Brunswick green, the gardener's colour.
func _green_iron() -> StandardMaterial3D:
	return GearStyle.paint(Color(0.09, 0.18, 0.13), 0.55, 0.15)


func _stone() -> StandardMaterial3D:
	return Materials.cached_scanned("greenhouse_stone", "concrete_floor_worn_001", "2k", 1.1,
			Color(0.82, 0.79, 0.72))


func _brick() -> StandardMaterial3D:
	return Materials.cached_scanned("greenhouse_brick", "red_brick_03", "2k", 1.2, Color(0.6, 0.48, 0.42))


func _teak() -> StandardMaterial3D:
	return Materials.cached_scanned("greenhouse_teak", "black_walnut_veneer_01", "2k", 0.8, Color(0.95, 0.72, 0.5))


func _gravel(tint: Color) -> StandardMaterial3D:
	var m := Materials.scanned(StandardMaterial3D.new(), "gravel", "1k", 1.4, tint)
	if WEATHERS[variant]["wet"] > 0.0:
		m.albedo_color = tint * 0.62
		m.roughness_texture = null
		m.roughness = 0.35
	return m


func _terracotta() -> StandardMaterial3D:
	var m := GearStyle.paint(Color(0.66, 0.33, 0.2), 0.9, 0.0)
	return m


func _leaf(colour: Color, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Leaves let the light through: lit from behind, they glow green.
	m.backlight_enabled = true
	m.backlight = Color(colour.r * 0.8, colour.g * 1.1, colour.b * 0.5)
	if WEATHERS[variant]["wet"] > 0.0:
		m.roughness = 0.3
	return m


var _looks := {}


func _plant_looks() -> Dictionary:
	if not _looks.is_empty():
		return _looks
	_looks = {"trunk": _leaf(Color(0.3, 0.28, 0.25), 0.9), "fibre": _leaf(Color(0.17, 0.11, 0.07), 0.95),
			"stem": _leaf(Color(0.2, 0.3, 0.12)), "frond": _leaf(Color(0.12, 0.27, 0.08)),
			"leaf": _leaf(Color(0.05, 0.19, 0.06), 0.4), "leaf_pale": _leaf(Color(0.24, 0.4, 0.1), 0.5),
			"petal": _bloom_material(), "heart": ZoneKit.glow(Color(0.95, 0.85, 0.45), 1.2)}
	return _looks


func _bloom_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.95, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.92, 0.96, 0.88)
	m.emission_energy_multiplier = 0.8
	return m


func _glass() -> ShaderMaterial:
	if _glass_mat == null:
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = preload("res://core/venues/shaders/greenhouse_glass.gdshader")
		_glass_mat.set_shader_parameter("rain", WEATHERS[variant]["rain"])
		_glass_mat.set_shader_parameter("dew", WEATHERS[variant]["dew"])
		_glass_mat.set_shader_parameter("glint", 0.15 if variant == RAIN else 0.0)
	return _glass_mat


## Glass under cover (the booth's, the lanterns'): nothing on it.
func _clear_glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.7, 0.66, 0.08)
	glass.roughness = 0.05
	glass.metallic_specular = 0.6
	return glass


# --- meshes ----------------------------------------------------------------------------------

## A mesh out of a glb, its surfaces dressed by material name.
func _mesh(scene: Node, object: String, looks: Dictionary) -> ArrayMesh:
	var mesh := (scene.find_child(object, true, false) as MeshInstance3D).mesh.duplicate() as ArrayMesh
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m != null and looks.has(m.resource_name):
			mesh.surface_set_material(i, looks[m.resource_name])
	return mesh


## Many of one mesh, one draw.
func _bank(label: String, mesh: Mesh, at: Array, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _one(scene: Node, object: String, looks: Dictionary, xf: Transform3D, label := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label if label != "" else object
	mi.mesh = _mesh(scene, object, looks)
	mi.transform = xf
	add_child(mi)
	return mi


## A box into a SurfaceTool: `xf` places a unit box, its basis carrying the size.
var _unit_box: BoxMesh


func _box(st: SurfaceTool, xf: Transform3D) -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
	st.append_from(_unit_box, 0, xf)


## A bar from `a` to `b`, `size` across (x along `side`, y the other way).
func _bar(st: SurfaceTool, a: Vector3, b: Vector3, size: Vector2, side: Vector3) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	var z := along / length
	var x := side - z * side.dot(z)
	if x.length() < 0.01:
		x = z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	var y := z.cross(x).normalized()
	_box(st, Transform3D(Basis(x * size.x, y * size.y, z * length), (a + b) * 0.5))


func _commit(st: SurfaceTool, label: String, material: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = st.commit()
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- the floor and the garden ------------------------------------------------------------------

## The walk's encaustic tiles; the kerb round it; the beds' mulch past the kerb; the gravel of
## the potting side along the back.
func _lay_the_floor() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, back - FRONT)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (back + FRONT) * 0.5
	var tiles := ShaderMaterial.new()
	tiles.shader = preload("res://core/venues/shaders/greenhouse_tiles.gdshader")
	tiles.set_shader_parameter("walk", Vector4(-half, FRONT, half * 2.0, back - FRONT))
	tiles.set_shader_parameter("wet", WEATHERS[variant]["wet"])
	tiles.set_shader_parameter("brightness", 0.75 if variant == MORNING else 1.0)
	floor_mesh.material_override = tiles
	add_child(floor_mesh)

	var stone := _stone()
	var w := wall_x() - DWARF * 0.5
	# The side kerbs run the whole length and take the corners; the front and back run between.
	for side: float in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(KERB, KERB_H, back - FRONT + KERB * 2.0), Vector3(side * (half + KERB * 0.5),
				KERB_H * 0.5, (back + FRONT) * 0.5), stone, "Kerb")
	# The front kerb stops either side of the fountain, whose basin is the edge there.
	var f := fountain_spot()
	var gap := Vector2(f.x - 1.27 * FOUNTAIN_SCALE + 0.15, f.x + 1.27 * FOUNTAIN_SCALE - 0.15)
	for run: Vector2 in [Vector2(-half + 0.002, gap.x), Vector2(gap.y, half - 0.002)]:
		ZoneKit.block(self, Vector3(run.y - run.x, KERB_H - 0.004, KERB - 0.004), Vector3((run.x + run.y) * 0.5,
				(KERB_H - 0.004) * 0.5, FRONT - KERB * 0.5), stone, "Kerb")
	ZoneKit.block(self, Vector3(half * 2.0 - 0.004, KERB_H - 0.004, KERB - 0.004), Vector3(0, (KERB_H - 0.004) * 0.5,
			back + KERB * 0.5), stone, "Kerb")

	# The beds: dark bark mulch, a little under the kerb.
	var mulch := _gravel(Color(0.3, 0.21, 0.15))
	var beds := [
		[Vector2(-w, front_z() + DWARF * 0.5), Vector2(w, FRONT - KERB), SOIL],
		[Vector2(-w, FRONT - KERB), Vector2(-half - KERB, back + KERB), SOIL + 0.002],
		[Vector2(half + KERB, FRONT - KERB), Vector2(w, back + KERB), SOIL + 0.002],
	]
	for bed: Array in beds:
		var lo: Vector2 = bed[0]
		var hi: Vector2 = bed[1]
		var soil := MeshInstance3D.new()
		soil.name = "Bed"
		var p := PlaneMesh.new()
		p.size = hi - lo
		soil.mesh = p
		soil.position = Vector3((lo.x + hi.x) * 0.5, bed[2], (lo.y + hi.y) * 0.5)
		soil.material_override = mulch
		add_child(soil)
		# The bed's sides, down to the floor under it: what you would see past the kerb's top.
		soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var strip := MeshInstance3D.new()
	strip.name = "PottingGravel"
	var sp := PlaneMesh.new()
	sp.size = Vector2(w * 2.0, back_z() - DWARF * 0.5 - back - KERB)
	strip.mesh = sp
	strip.position = Vector3(0, 0.012, (back_z() - DWARF * 0.5 + back + KERB) * 0.5)
	strip.material_override = _gravel(Color(0.7, 0.66, 0.6))
	add_child(strip)


## The botanical garden round the house: lawns, a gravel path round the glass and a walk running
## away from the front between box hedges, yews and lamp posts to an urn in a ring of gravel,
## and trees all round, thinning out to the haze.
func _lay_the_garden() -> void:
	var lawn := MeshInstance3D.new()
	lawn.name = "Lawn"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	lawn.mesh = plane
	lawn.position = Vector3(0, -0.03, 0)
	var grass := ShaderMaterial.new()
	grass.shader = preload("res://core/venues/shaders/greenhouse_lawn.gdshader")
	grass.set_shader_parameter("wet", WEATHERS[variant]["wet"])
	grass.set_shader_parameter("dew", WEATHERS[variant]["dew"])
	lawn.material_override = grass
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lawn)

	var gravel := _gravel(Color(0.74, 0.7, 0.62))
	var w := wall_x() + DWARF * 0.5
	var path := 2.2
	var lo := Vector2(-w - path, front_z() - DWARF * 0.5 - path)
	var hi := Vector2(w + path, back_z() + DWARF * 0.5 + path)
	var round_path := ZoneKit.block(self, Vector3(hi.x - lo.x, 0.04, hi.y - lo.y), Vector3(0, -0.03, (lo.y + hi.y) * 0.5),
			gravel, "PathRound")
	round_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The walk out from the front, straight down the view from the desk.
	var walk_end := -48.0
	var walk_half := 1.6
	var walk := ZoneKit.block(self, Vector3(walk_half * 2.0, 0.04, lo.y - walk_end), Vector3(0, -0.03,
			(lo.y + walk_end) * 0.5), gravel, "Walk")
	walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A ring of gravel at its end, round an urn on the grass.
	var ring_at := Vector3(0, -0.03, walk_end - 4.0)
	var ring := MeshInstance3D.new()
	ring.name = "Circle"
	var disc := CylinderMesh.new()
	disc.top_radius = 5.0
	disc.bottom_radius = 5.0
	disc.height = 0.04
	disc.radial_segments = 48
	ring.mesh = disc
	ring.position = ring_at + Vector3(0, -0.01, 0)
	ring.material_override = gravel
	add_child(ring)
	var round_lawn := MeshInstance3D.new()
	round_lawn.name = "RoundLawn"
	var inner := CylinderMesh.new()
	inner.top_radius = 3.4
	inner.bottom_radius = 3.4
	inner.height = 0.05
	inner.radial_segments = 48
	round_lawn.mesh = inner
	round_lawn.position = ring_at + Vector3(0, 0.002, 0)
	round_lawn.material_override = grass
	add_child(round_lawn)
	var stone := _stone()
	_one(_prop_scene, "Urn", {"stone": stone}, Transform3D(Basis.from_scale(Vector3.ONE * 1.5), ring_at + Vector3(0, 0.03, 0)),
			"GardenUrn")

	# Box hedges along the walk, and a clipped yew every few metres between them and the walk.
	var hedge := _hedge_material()
	for side: float in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.55, 0.6, lo.y - walk_end - 2.0), Vector3(side * (walk_half + 0.6), 0.27,
				(lo.y - 1.0 + walk_end + 1.0) * 0.5), hedge, "Hedge")
	var yews: Array = []
	var posts: Array = []
	var z := lo.y - 3.0
	var k := 0
	while z > walk_end + 3.0:
		for side: float in [-1.0, 1.0]:
			if k % 2 == 0:
				yews.append(Transform3D(Basis.from_scale(Vector3(2.2, 2.6, 2.2)), Vector3(side * (walk_half + 1.5), -0.01, z)))
			else:
				posts.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(side * (walk_half + 0.15), -0.01, z)))
		z -= 4.5
		k += 1
	var looks := {"yew": _leaf(Color(0.06, 0.15, 0.07), 0.85), "bark": _leaf(Color(0.2, 0.15, 0.1), 0.9)}
	_bank("Yews", _mesh(_prop_scene, "Yew", looks), yews)
	var lit: float = WEATHERS[variant]["lanterns"]
	var post_glass := ZoneKit.glow(Color(1.0, 0.78, 0.5), 2.2) if lit > 0.0 else _clear_glass()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.03, 0.04, 0.035)
	iron.metallic = 0.4
	iron.roughness = 0.5
	_bank("LampPosts", _mesh(_prop_scene, "LampPost", {"iron": iron, "glass": post_glass, "brass": iron}), posts)
	if lit > 0.0:
		# The nearest pair throw their light on the gravel; the rest are only points down the walk.
		for i in mini(2, posts.size()):
			var glow := OmniLight3D.new()
			glow.name = "LampPostLight"
			glow.light_color = Color(1.0, 0.75, 0.48)
			glow.light_energy = 1.2
			glow.omni_range = 5.0
			glow.position = (posts[i] as Transform3D).origin + Vector3(0, 3.1, 0)
			add_child(glow)

	# Trees: round and tall, all round the house, none in the walk's view, thinning with distance.
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var round_trees: Array = []
	var tall_trees: Array = []
	var tries := 0
	while round_trees.size() + tall_trees.size() < 150 and tries < 3000:
		tries += 1
		var a := rng.randf() * TAU
		var d := 16.0 + pow(rng.randf(), 0.7) * 90.0
		var p := Vector2(sin(a) * d, cos(a) * d)
		if p.x > lo.x - 8.0 and p.x < hi.x + 8.0 and p.y > lo.y - 8.0 and p.y < hi.y + 8.0:
			continue
		# The view down the walk stays open, widening as it goes.
		if p.y < lo.y and absf(p.x) < 6.0 + (lo.y - p.y) * 0.35:
			continue
		var s := rng.randf_range(7.0, 13.0) * (1.0 + d / 200.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s)),
				Vector3(p.x, -0.02, p.y))
		if rng.randf() < 0.35:
			tall_trees.append(xf)
		else:
			round_trees.append(xf)
	var tree_looks := {"bark": _leaf(Color(0.18, 0.14, 0.1), 0.9), "canopy": _leaf(Color(0.13, 0.24, 0.08), 0.8)}
	_bank("TreesRound", _mesh(_prop_scene, "TreeRound", tree_looks), round_trees)
	var tall_looks := {"bark": tree_looks["bark"], "canopy": _leaf(Color(0.09, 0.19, 0.08), 0.8)}
	_bank("TreesTall", _mesh(_prop_scene, "TreeTall", tall_looks), tall_trees)


func _hedge_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.17, 0.06)
	m.roughness = 0.9
	m.normal_enabled = true
	m.normal_texture = Materials.grain("hedge", 2.5, 3.0)
	m.normal_scale = 1.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.5
	return m


# --- the house -------------------------------------------------------------------------------

## Brick to waist height all round under the glass, coped in stone, with the doorway at the back.
func _build_dwarf_wall() -> void:
	var brick := _brick()
	var stone := _stone()
	var w := wall_x()
	var f := front_z()
	var b := back_z()
	var y := DWARF_H * 0.5
	for side: float in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(DWARF, DWARF_H, b - f + DWARF), Vector3(side * w, y, (f + b) * 0.5), brick, "DwarfWall")
		ZoneKit.block(self, Vector3(DWARF + 0.06, 0.05, b - f + DWARF + 0.06), Vector3(side * w, DWARF_H + 0.025,
				(f + b) * 0.5), stone, "Coping")
	var inside := w - DWARF * 0.5 - 0.002
	ZoneKit.block(self, Vector3(inside * 2.0, DWARF_H - 0.004, DWARF - 0.004), Vector3(0, y - 0.002, f), brick, "DwarfWall")
	ZoneKit.block(self, Vector3(inside * 2.0 - 0.06, 0.046, DWARF + 0.056), Vector3(0, DWARF_H + 0.021, f), stone,
			"Coping")
	# The back, either side of the doorway to the garden.
	for side: float in [-1.0, 1.0]:
		var run := inside - DOOR_HALF
		ZoneKit.block(self, Vector3(run, DWARF_H - 0.004, DWARF - 0.004), Vector3(side * (DOOR_HALF + run * 0.5), y - 0.002, b),
				brick, "DwarfWall")
		ZoneKit.block(self, Vector3(run - 0.03, 0.046, DWARF + 0.056), Vector3(side * (DOOR_HALF + run * 0.5 + 0.015),
				DWARF_H + 0.021, b), stone, "Coping")


## The glass: the long section run from gable to gable, and each gable filled -- one mesh, one
## material, which is what the weather is drawn on.
func _raise_the_glass() -> void:
	var sec := section()
	var f := front_z()
	var b := back_z()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sec.size() - 1:
		var p0 := sec[i]
		var p1 := sec[i + 1]
		_quad(st, Vector3(p0.x, p0.y, f), Vector3(p1.x, p1.y, f), Vector3(p1.x, p1.y, b), Vector3(p0.x, p0.y, b))
	# The gables: the section closed along the dwarf wall's top, filled. At the back, the doorway
	# is cut out of the bottom, where the door stands instead.
	var outline := PackedVector2Array(sec)
	var tris := Geometry2D.triangulate_polygon(outline)
	for z: float in [f, b]:
		for t in range(0, tris.size(), 3):
			for k in 3:
				var p := outline[tris[t + k]]
				st.add_vertex(Vector3(p.x, p.y, z))
	st.generate_normals()
	var glass := _commit(st, "Glass", _glass(), false)
	glass.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The doorway's glass, from the floor to the dwarf wall's top, behind the door.
	var door_glass := ZoneKit.block(self, Vector3(DOOR_HALF * 2.0, DWARF_H, 0.01), Vector3(0, DWARF_H * 0.5, b), _glass(),
			"DoorGlass")
	door_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## The iron: the main ribs round the section, the glazing bars between them, the purlins along
## the house, the lattice girders over the columns, and the gables' mullions with their sunbursts
## and the back door's frame. One mesh, white.
func _raise_the_ironwork() -> void:
	var sec := section()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inward: Array[Vector2] = []
	for i in sec.size():
		var t := (sec[mini(i + 1, sec.size() - 1)] - sec[maxi(i - 1, 0)]).normalized()
		inward.append(Vector2(-t.y, t.x))
	var ribs := rib_z()
	var bay := ribs[1] - ribs[0]
	# The ribs, and three glazing bars in each bay between them.
	var at_z: Array = []
	for k in ribs.size():
		at_z.append([ribs[k], RIB])
		if k < ribs.size() - 1:
			for j: int in [1, 2, 3]:
				at_z.append([lerpf(ribs[k], ribs[k + 1], j / 4.0), BAR])
	for spec: Array in at_z:
		var z: float = spec[0]
		var size: Vector2 = spec[1]
		for i in sec.size() - 1:
			var n0 := inward[i]
			var n1 := inward[i + 1]
			var seg_n := ((n0 + n1) * 0.5).normalized()
			var off := seg_n * (IN_FROM_GLASS + size.y * 0.5)
			var a := Vector3(sec[i].x + off.x, sec[i].y + off.y, z)
			var b := Vector3(sec[i + 1].x + off.x, sec[i + 1].y + off.y, z)
			# A hair longer than the segment, so the joints close.
			var along := (b - a).normalized()
			_bar(st, a - along * size.y * 0.3, b + along * size.y * 0.3, Vector2(size.x, size.y), Vector3(0, 0, 1))
	# The purlins: along the house at the eaves, the clerestory and up the vault.
	var f := front_z() + IN_FROM_GLASS
	var e := back_z() - IN_FROM_GLASS
	# Eaves, the aisle's middle, the clerestory's sill and head, three up each side of the vault
	# (which starts at index 10 and is 28 segments over) and the ridge.
	var count := sec.size()
	var purlins: Array[int] = []
	for i in [1, 5, 9, 10, 14, 18, 22]:
		purlins.append_array([i, count - 1 - i])
	purlins.append(24)
	for idx in purlins:
		var off := inward[idx] * (IN_FROM_GLASS + RIB.y + 0.02)
		var p := Vector3(sec[idx].x + off.x, sec[idx].y + off.y, 0)
		_bar(st, Vector3(p.x, p.y, f), Vector3(p.x, p.y, e), Vector2(0.06, 0.05), Vector3(inward[idx].x, inward[idx].y, 0))
	# The lattice girders on the columns, under the clerestory: two flanges and a web of crossed
	# diagonals, a panel to every half metre.
	var c := column_x() - IN_FROM_GLASS - 0.08
	for side: float in [-1.0, 1.0]:
		var x: float = side * c
		for y: float in [CLERE_SILL + 0.025, CLERE_SILL + GIRDER - 0.025]:
			_bar(st, Vector3(x, y, f), Vector3(x, y, e), Vector2(0.16, 0.05), Vector3(1, 0, 0))
		var panels := int((e - f) / 0.5)
		var pz := (e - f) / panels
		for k in panels:
			var z0 := f + pz * k
			var z1 := z0 + pz
			_bar(st, Vector3(x, CLERE_SILL + 0.05, z0), Vector3(x, CLERE_SILL + GIRDER - 0.05, z1), Vector2(0.025, 0.04),
					Vector3(1, 0, 0))
			_bar(st, Vector3(x, CLERE_SILL + GIRDER - 0.05, z0), Vector3(x, CLERE_SILL + 0.05, z1), Vector2(0.025, 0.04),
					Vector3(1, 0, 0))
	_gable_iron(st, front_z() + IN_FROM_GLASS, 1.0, false)
	_gable_iron(st, back_z() - IN_FROM_GLASS, -1.0, true)
	_commit(st, "Ironwork", _white_iron())


## A gable's iron, on its inside face: mullions up from the dwarf wall to the glass's edge, a
## transom at the eaves and at the clerestory's head, and over that, filling the vault's end, a
## sunburst round a half-wheel. At the back, a pair of doors in their frame and a fanlight.
func _gable_iron(st: SurfaceTool, z: float, into: float, door: bool) -> void:
	var w := wall_x()
	var c := column_x()
	var depth := Vector2(0.05, 0.06)
	var zz := z + into * (depth.y * 0.5)
	var step := 0.6
	var x := -w + step * 0.5
	while x < w:
		var top := roof_at(x)
		var bottom := DWARF_H
		if absf(x) < c:
			top = CLERE_HEAD
		if door and absf(x) < DOOR_HALF + 0.1:
			bottom = DOOR_HEAD + DOOR_HALF
		if top > bottom + 0.05:
			_bar(st, Vector3(x, bottom, zz), Vector3(x, top, zz), depth, Vector3(1, 0, 0))
		x += step
	# The main posts on the column lines, and the corners.
	for side: float in [-1.0, 1.0]:
		_bar(st, Vector3(side * c, DWARF_H, zz), Vector3(side * c, CLERE_HEAD, zz), Vector2(0.12, 0.1), Vector3(1, 0, 0))
	for y: float in [EAVES, CLERE_SILL, CLERE_HEAD]:
		var reach := w if y <= EAVES else c
		if y > EAVES:
			reach = c if y >= CLERE_HEAD - 0.01 else c + (w - c) * sqrt(maxf(0.0, 1.0 - pow((y - EAVES) / (CLERE_SILL - EAVES), 2.0)))
		_bar(st, Vector3(-reach, y, zz), Vector3(reach, y, zz), Vector2(0.06, 0.07), Vector3(0, 1, 0))
	# The sunburst: rays from a half-wheel at the vault's foot to its edge.
	var hub := Vector3(0, CLERE_HEAD, zz)
	var wheel := 0.9
	var rays := 13
	for i in rays:
		var t := PI * (i + 0.5) / rays
		var dir := Vector3(cos(t) * c, sin(t) * VAULT_RISE, 0)
		var from := hub + Vector3(cos(t), sin(t), 0) * wheel
		_bar(st, from, hub + dir, Vector2(0.04, 0.05), Vector3(0, 0, 1))
	var prev := hub + Vector3(wheel, 0, 0)
	for i in range(1, 17):
		var t := PI * i / 16.0
		var p := hub + Vector3(cos(t), sin(t), 0) * wheel
		_bar(st, prev, p, Vector2(0.06, 0.06), Vector3(0, 0, 1))
		prev = p
	if door:
		var iron := Vector2(0.07, 0.08)
		for x2: float in [-DOOR_HALF, 0.0, DOOR_HALF]:
			_bar(st, Vector3(x2, 0.0, zz), Vector3(x2, DOOR_HEAD, zz), iron, Vector3(1, 0, 0))
		_bar(st, Vector3(-DOOR_HALF, DOOR_HEAD, zz), Vector3(DOOR_HALF, DOOR_HEAD, zz), iron, Vector3(0, 1, 0))
		_bar(st, Vector3(-DOOR_HALF, 1.0, zz), Vector3(DOOR_HALF, 1.0, zz), Vector2(0.05, 0.06), Vector3(0, 1, 0))
		var fan := Vector3(0, DOOR_HEAD, zz)
		prev = fan + Vector3(DOOR_HALF, 0, 0)
		for i in range(1, 13):
			var t := PI * i / 12.0
			var p := fan + Vector3(cos(t), sin(t), 0) * DOOR_HALF
			_bar(st, prev, p, Vector2(0.06, 0.07), Vector3(0, 0, 1))
			prev = p
		for i in 5:
			var t := PI * (i + 1) / 6.0
			_bar(st, fan, fan + Vector3(cos(t), sin(t), 0) * DOOR_HALF, Vector2(0.03, 0.04), Vector3(0, 0, 1))


## The columns on the kerb, under the girders, each with a pierced bracket either side under the
## girder; and a pair of brackets at each gable's end of the girder.
func _raise_the_columns() -> void:
	var iron := _white_iron()
	var looks := {"iron": iron}
	var cols: Array = []
	var brackets: Array = []
	var c := column_x()
	for z in column_z():
		for side: float in [-1.0, 1.0]:
			cols.append(Transform3D(Basis.IDENTITY, Vector3(side * c, 0, z)))
			for along: float in [-1.0, 1.0]:
				# The bracket's +X turned to run along the house, its plane the column line's.
				var yaw := -PI * 0.5 if along > 0.0 else PI * 0.5
				brackets.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(side * (c - 0.08), CLERE_SILL, z + along * 0.2)))
	_bank("Columns", _mesh(_prop_scene, "Column", looks), cols)
	_bank("Spandrels", _mesh(_prop_scene, "Spandrel", looks), brackets)


# --- the planting ----------------------------------------------------------------------------

func _plant(kind: String, at: Vector3, yaw: float, size: float) -> void:
	if not planted.has(kind):
		planted[kind] = []
	(planted[kind] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))


## The borders: palms and tree ferns and bananas beside the desk where the aisle roof is high
## enough; lower things -- monstera, aspidistra, fern -- behind, by the zones; ground cover all
## along the kerb; the tall kentias in the front border under the vault.
func _plant_the_borders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var half := live_room_half()
	var inner := half + KERB
	var outer := wall_x() - DWARF * 0.5
	var mid := (inner + outer) * 0.5
	for side: float in [-1.0, 1.0]:
		# Beside the desk: the big plants, in a loose line down the middle of the bed.
		var z := FRONT + 0.2
		var big := ["TreeFern", "Banana", "FanPalm", "TreeFern", "Banana"]
		var k := 0 if side < 0 else 2
		while z < Studio.ROOM_BACK - 0.3:
			var kind: String = big[k % big.size()]
			_plant(kind, Vector3(side * (mid + rng.randf_range(-0.25, 0.3)), SOIL, z), rng.randf() * TAU,
					rng.randf_range(0.85, 1.05))
			z += rng.randf_range(1.5, 1.9)
			k += 1
		# By the zones: nothing that reaches out over the walk at head height.
		z = Studio.ROOM_BACK + 0.4
		while z < LIVE_ROOM_BACK + 0.2:
			_plant("Monstera", Vector3(side * (mid + rng.randf_range(-0.3, 0.3)), SOIL, z), rng.randf() * TAU,
					rng.randf_range(1.0, 1.35))
			z += rng.randf_range(1.0, 1.4)
		# Ground cover along the kerb, and filling in behind.
		z = FRONT
		while z < LIVE_ROOM_BACK + KERB:
			var kind := "Aspidistra" if rng.randf() < 0.55 else "Fern"
			_plant(kind, Vector3(side * (inner + rng.randf_range(0.2, 0.4)), SOIL, z), rng.randf() * TAU,
					rng.randf_range(0.9, 1.3))
			if rng.randf() < 0.6:
				_plant("Monstera" if rng.randf() < 0.4 else "Aspidistra", Vector3(side * (outer - rng.randf_range(0.3, 0.6)),
						SOIL, z + 0.3), rng.randf() * TAU, rng.randf_range(0.8, 1.2))
			z += rng.randf_range(0.45, 0.7)
	# The front border: the kentias up under the vault behind the desk's view, fan palms and
	# tree ferns toward the corners, and low things along the kerb.
	var fz := FRONT - KERB - BED * 0.5
	for spec: Array in [["Palm", -2.4, 1.05], ["Palm", 2.6, 1.15], ["Palm", 0.2, 0.9], ["FanPalm", -1.0, 1.0],
			["FanPalm", 4.0, 0.95], ["TreeFern", 1.4, 1.0], ["Banana", -3.6, 0.9], ["TreeFern", 7.2, 0.95],
			["Banana", 8.0, 0.85], ["TreeFern", -7.6, 0.9]]:
		# Placed by number along the old house's front (DRAWN_HALF a side): as far along this one's.
		var x: float = spec[1] * live_room_half() / DRAWN_HALF
		_plant(spec[0], Vector3(x, SOIL, fz + rng.randf_range(-0.3, 0.2)), rng.randf() * TAU, spec[2])
	var x2 := -outer + 0.3
	var f := fountain_spot()
	var u := urn_spot()
	while x2 < outer - 0.3:
		if absf(x2 - f.x) > 1.3 and absf(x2 - u.x) > 0.5:
			var kind := "Aspidistra" if rng.randf() < 0.5 else "Fern"
			_plant(kind, Vector3(x2, SOIL, FRONT - KERB - rng.randf_range(0.2, 0.4)), rng.randf() * TAU,
					rng.randf_range(0.9, 1.3))
			if rng.randf() < 0.5:
				_plant("Monstera", Vector3(x2 + 0.2, SOIL, front_z() + DWARF * 0.5 + rng.randf_range(0.4, 0.7)),
						rng.randf() * TAU, rng.randf_range(0.9, 1.2))
		x2 += rng.randf_range(0.45, 0.7)
	var looks := _plant_looks()
	for kind: String in planted:
		_bank("Plants" + kind, _mesh(_plant_scene, kind, looks), planted[kind])


## Wire baskets of fern on chains from the aisle roofs, over the beds, between the columns.
func _hang_the_baskets() -> void:
	var looks := {"iron": _green_iron(), "moss": _leaf(Color(0.16, 0.2, 0.08), 0.95)}
	var ribs := rib_z()
	var baskets: Array = []
	var ferns: Array = []
	var chains: Array = []
	var x := live_room_half() + KERB + 0.55
	for k in range(1, ribs.size() - 1, 2):
		for side: float in [-1.0, 1.0]:
			var at := Vector3(side * x, 3.35, ribs[k])
			baskets.append(Transform3D(Basis(Vector3.UP, k * 0.7), at))
			ferns.append(Transform3D(Basis(Vector3.UP, k * 1.3).scaled(Vector3.ONE * 1.1), at - Vector3(0, 0.6, 0)))
			var top := roof_at(at.x) - IN_FROM_GLASS - RIB.y
			chains.append(Transform3D(Basis.from_scale(Vector3(0.01, top - at.y, 0.01)), at + Vector3(0, (top - at.y) * 0.5, 0)))
	_bank("Baskets", _mesh(_prop_scene, "Basket", looks), baskets)
	_bank("BasketFerns", _mesh(_plant_scene, "Fern", _plant_looks()), ferns)
	var chained := _bank("BasketChains", BoxMesh.new(), chains, false)
	chained.material_override = _green_iron()
	_baskets = baskets


var _baskets: Array = []


## The potting side, behind the zones on the gravel: tiered staging full of pots, two potting
## benches at the ends with pots stacked on them and a watering can, and the heating pipes along
## the dwarf wall behind.
func _set_up_the_potting_side() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var wood := Materials.cached_scanned("greenhouse_staging", "weathered_brown_planks", "2k", 0.9,
			Color(0.62, 0.55, 0.48))
	var green := _green_iron()
	var wall := back_z() - DWARF * 0.5
	var outer := wall_x() - DWARF * 0.5
	var stagings: Array = []
	var benches: Array = []
	var pots: Array = []
	var potted := {"Aspidistra": [], "Fern": [], "Monstera": []}
	for side: float in [-1.0, 1.0]:
		var bench_x: float = side * (outer - 1.1)
		benches.append(Transform3D(Basis(Vector3.UP, PI), Vector3(bench_x, 0.012, wall - 0.36)))
		var span := absf(bench_x) - 1.1 - DOOR_HALF - 0.25
		var units := maxi(1, int(span / 2.45))
		for u in units:
			var sx: float = side * (DOOR_HALF + 0.25 + span * (u + 0.5) / units)
			stagings.append(Transform3D(Basis(Vector3.UP, PI), Vector3(sx, 0.012, wall - 0.57)))
			# Three steps, rising to the wall (staging's steps, turned to face the room).
			for step: Array in [[0.5, -0.37], [0.85, 0.0], [1.2, 0.37]]:
				var px := -1.1
				while px < 1.1:
					var s := rng.randf_range(0.6, 0.85)
					var at := Vector3(sx + px, 0.012 + step[0] + 0.0125, wall - 0.57 + step[1])
					pots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), at))
					var kind: String = ["Aspidistra", "Fern", "Monstera"][rng.randi() % 3]
					var ps := {"Aspidistra": 0.42, "Fern": 0.5, "Monstera": 0.32}[kind] as float
					(potted[kind] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * ps * s),
							at + Vector3(0, 0.25 * s, 0)))
					px += rng.randf_range(0.26, 0.34)
		# On the bench: stacks of empty pots, a few planted up, and the can.
		var top := 0.012 + 0.85
		for i in 3:
			for j in 4:
				pots.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.62), Vector3(bench_x - 0.7 + i * 0.22, top + j * 0.07,
						wall - 0.45 + (i % 2) * 0.05)))
		for i in 3:
			var at := Vector3(bench_x + 0.1 + i * 0.25, top, wall - 0.3 - (i % 2) * 0.12)
			pots.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.7), at))
			(potted["Fern"] as Array).append(Transform3D(Basis(Vector3.UP, i).scaled(Vector3.ONE * 0.38), at + Vector3(0, 0.17, 0)))
		_one(_prop_scene, "WateringCan", {"zinc": GearStyle.metal(Color(0.62, 0.64, 0.62), 0.55)},
				Transform3D(Basis(Vector3.UP, 0.6 * side), Vector3(bench_x + 0.75, top, wall - 0.42)), "WateringCan")
	_bank("Staging", _mesh(_prop_scene, "Staging", {"wood": wood, "iron": green}), stagings)
	_bank("Benches", _mesh(_prop_scene, "Bench", {"wood": wood, "iron": green}), benches)
	_bank("Pots", _mesh(_prop_scene, "Pot", {"terracotta": _terracotta(), "soil": _leaf(Color(0.12, 0.08, 0.05), 0.95)}), pots)
	var looks := _plant_looks()
	for kind: String in potted:
		_bank("Potted" + kind, _mesh(_plant_scene, kind, looks), potted[kind])
	_pots = pots
	# The heating: two cast-iron hot-water pipes along the back wall, as every palm house has.
	var pipe := StandardMaterial3D.new()
	pipe.albedo_color = Color(0.08, 0.075, 0.07)
	pipe.metallic = 0.5
	pipe.roughness = 0.6
	for y: float in [0.1, 0.24]:
		var run := MeshInstance3D.new()
		run.name = "HeatingPipe"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = outer * 2.0 - 0.02
		cyl.radial_segments = 12
		run.mesh = cyl
		run.rotation.z = PI * 0.5
		run.position = Vector3(0, y, wall - 0.08)
		run.material_override = pipe
		add_child(run)


var _pots: Array = []


## The fountain, front-left, its water standing in its bowls and falling from rim to rim; the
## urn front-right with a fern trailing from it.
func _place_the_fountain() -> void:
	var stone := _stone()
	var f := fountain_spot()
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * FOUNTAIN_SCALE), f)
	_one(_prop_scene, "Fountain", {"stone": stone}, xf, "Fountain")
	var water := ShaderMaterial.new()
	water.shader = preload("res://core/venues/shaders/greenhouse_water.gdshader")
	_one(_prop_scene, "FountainWater", {"water": water}, xf, "FountainWater")
	var veil := ShaderMaterial.new()
	veil.shader = preload("res://core/venues/shaders/greenhouse_veil.gdshader")
	veil.set_shader_parameter("shine", 0.25 if variant == NIGHT else 0.0)
	var falling := _one(_prop_scene, "FountainVeil", {"veil": veil}, xf, "FountainVeil")
	falling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var u := urn_spot()
	_one(_prop_scene, "Urn", {"stone": stone}, Transform3D(Basis.IDENTITY, u + Vector3(0, SOIL - 0.02, 0)), "Urn")
	_one(_plant_scene, "Fern", _plant_looks(), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.3),
			u + Vector3(0, SOIL + 1.18, 0)), "UrnFern")


# --- the lights ------------------------------------------------------------------------------

## The house's lanterns, on long chains from the roof: over the walk between the desk and the
## zones, either side of the desk, and over each zone. Lit in the rain, low at night, dark on a
## bright morning.
func _hang_the_lanterns() -> void:
	var z := zones()
	var lit: float = WEATHERS[variant]["lanterns"]
	var side := (room_width * 0.5 + live_room_half()) * 0.5
	var spots: Array = [Vector3(-2.8, 3.2, Studio.ROOM_BACK + 0.45), Vector3(2.8, 3.2, Studio.ROOM_BACK + 0.45),
			Vector3(-side, 3.2, -2.4), Vector3(side, 3.2, -2.4), Vector3(-side, 3.2, 1.6), Vector3(side, 3.2, 1.6)]
	# The back of house is twice the floor it was: a lantern over each walk between the
	# neighbourhoods as well as over the zones, clear of every banner.
	for at: Vector3 in [Vector3(-4.4, 3.6, 6.4), Vector3(4.4, 3.6, 6.6), Vector3(-3.6, 3.8, 10.6),
			Vector3(4.6, 3.8, 9.0)]:
		spots.append(Vector3(at.x * live_room_half() / LIVE_ROOM_HALF, at.y, at.z))
	# Each lantern's ring: the body hangs 0.76 m under it, clear of every zone's head room.
	var over := {&"drums": 3.65, &"matrix": 4.25, &"bricks": 2.75, &"synth": 3.0}
	for id: StringName in over:
		var box: AABB = z[id]
		spots.append(Vector3(box.get_center().x, over[id], box.get_center().z))
	var iron := _green_iron()
	var brass := GearStyle.metal(Color(0.72, 0.58, 0.32), 0.4)
	var glass := ZoneKit.glow(Color(1.0, 0.78, 0.5), 1.6 + 1.2 * lit) if lit > 0.0 else _clear_glass()
	var lanterns: Array = []
	var chains: Array = []
	for at: Vector3 in spots:
		lanterns.append(Transform3D(Basis.IDENTITY, at))
		var top := roof_at(at.x) - IN_FROM_GLASS - RIB.y
		chains.append(Transform3D(Basis.from_scale(Vector3(0.012, top - at.y, 0.012)), at + Vector3(0, (top - at.y) * 0.5, 0)))
		if lit > 0.0:
			var light := SpotLight3D.new()
			light.name = "Lantern"
			light.light_color = Color(1.0, 0.74, 0.46)
			light.light_energy = 2.4 * lit
			light.spot_range = 5.5
			light.spot_angle = 68.0
			light.spot_angle_attenuation = 1.1
			light.light_specular = 0.08
			light.shadow_enabled = false
			light.position = at + Vector3(0, -0.5, 0)
			light.rotation_degrees = Vector3(-90, 0, 0)
			add_child(light)
	_bank("Lanterns", _mesh(_prop_scene, "Lantern", {"iron": iron, "glass": glass, "brass": brass}), lanterns)
	var chained := _bank("LanternChains", BoxMesh.new(), chains, false)
	chained.material_override = iron


## Morning: shafts of the low sun through the glass, in the damp air over the beds.
func _slant_the_sun() -> void:
	var w: Dictionary = WEATHERS[MORNING]
	var toward := _key_basis(w).z.normalized()
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/light_shaft.gdshader")
	m.set_shader_parameter("colour", Color(1.0, 0.86, 0.62))
	m.set_shader_parameter("strength", 0.03)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var across := toward.cross(Vector3.UP).normalized()
	# Their feet in the beds the sun reaches, across the house from it; each runs back up toward
	# the sun, over the walk, out through the glass it came in by.
	var inner := wall_x() - DWARF * 0.5
	for i in 7:
		var foot := Vector3(rng.randf_range(live_room_half() + KERB + 0.2, inner - 0.2), SOIL,
				rng.randf_range(FRONT - 1.0, LIVE_ROOM_BACK))
		var length := 12.0
		for turn: int in [0, 1]:
			var shaft := MeshInstance3D.new()
			shaft.name = "SunShaft"
			shaft.mesh = quad
			var mat := m.duplicate() as ShaderMaterial
			mat.set_shader_parameter("seed", rng.randf())
			shaft.material_override = mat
			shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var side := across if turn == 0 else across.cross(toward).normalized()
			var face := side.cross(toward).normalized()
			shaft.transform = Transform3D(Basis(side * rng.randf_range(0.6, 1.2), toward * length, face),
					foot + toward * length * 0.5)
			add_child(shaft)


## Rain: falling outside the glass all round, and a few drips coming through the old roof into
## the beds.
func _let_it_rain() -> void:
	var streak := StandardMaterial3D.new()
	streak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.albedo_color = Color(0.75, 0.8, 0.86, 0.22)
	streak.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.008, 0.45)
	quad.material = streak
	var w := wall_x() + DWARF * 0.5
	var f := front_z() - DWARF * 0.5
	var b := back_z() + DWARF * 0.5
	var depth := 9.0
	for spec: Array in [["RainFront", Vector3(0, 7.0, f - 0.8 - depth * 0.5), Vector3(w + depth, 7.0, depth * 0.5)],
			["RainBack", Vector3(0, 7.0, b + 0.8 + depth * 0.5), Vector3(w + depth, 7.0, depth * 0.5)],
			["RainLeft", Vector3(-w - 0.8 - depth * 0.5, 7.0, (f + b) * 0.5), Vector3(depth * 0.5, 7.0, (b - f) * 0.5)],
			["RainRight", Vector3(w + 0.8 + depth * 0.5, 7.0, (f + b) * 0.5), Vector3(depth * 0.5, 7.0, (b - f) * 0.5)]]:
		var fall := GPUParticles3D.new()
		fall.name = spec[0]
		fall.position = spec[1]
		fall.amount = 2400
		fall.lifetime = 1.6
		fall.preprocess = 2.0
		fall.draw_pass_1 = quad
		var ext: Vector3 = spec[2]
		fall.visibility_aabb = AABB(-ext - Vector3(0, 8, 0), ext * 2.0 + Vector3(0, 8, 0))
		var drift := ParticleProcessMaterial.new()
		drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		drift.emission_box_extents = ext
		drift.direction = Vector3(0.05, -1, 0)
		drift.spread = 1.5
		# Straight down and quick: nothing drifts in through the glass.
		drift.initial_velocity_min = 8.0
		drift.initial_velocity_max = 9.5
		drift.gravity = Vector3(0, -2.0, 0)
		fall.process_material = drift
		add_child(fall)
	# Drips: from the aisle roofs' bars into the beds, one at a time.
	var drop := StandardMaterial3D.new()
	drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.albedo_color = Color(0.8, 0.85, 0.9, 0.5)
	drop.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	var bead := QuadMesh.new()
	bead.size = Vector2(0.012, 0.05)
	bead.material = drop
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (live_room_half() + KERB + rng.randf_range(0.4, 1.3))
		var at := Vector3(x, roof_at(x) - 0.25, rng.randf_range(FRONT, LIVE_ROOM_BACK))
		var drip := GPUParticles3D.new()
		drip.name = "Drip"
		drip.position = at
		drip.amount = 2
		drip.lifetime = 1.4
		drip.explosiveness = 0.0
		drip.randomness = 0.5
		drip.draw_pass_1 = bead
		drip.visibility_aabb = AABB(Vector3(-0.5, -6, -0.5), Vector3(1, 6.5, 1))
		var fall := ParticleProcessMaterial.new()
		fall.direction = Vector3(0, -1, 0)
		fall.spread = 0.0
		fall.initial_velocity_min = 0.2
		fall.initial_velocity_max = 0.4
		fall.gravity = Vector3(0, -9.8, 0)
		drip.process_material = fall
		add_child(drip)
	# The wet tiles want something to mirror where the screen-space reflections cannot run.
	var probe := ReflectionProbe.new()
	probe.name = "WetFloorProbe"
	probe.size = Vector3(live_room_half() * 2.0 + 2.0, 6.0, LIVE_ROOM_BACK - FRONT + 2.0)
	probe.position = Vector3(0, 1.6, (LIVE_ROOM_BACK + FRONT) * 0.5)
	probe.box_projection = true
	probe.intensity = 0.6
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)


## Night: strings of warm bulbs wound up every column and looped between them along the beds,
## and two across the nave, with a few soft lights where they hang thickest.
func _string_the_lights() -> void:
	var bulbs: Array[Vector3] = []
	var c := column_x()
	var cz := column_z()
	for z in cz:
		for side: float in [-1.0, 1.0]:
			# A spiral up the shaft, five turns.
			var turns := 5.0
			var n := 52
			for i in n:
				var t := float(i) / n
				var a := t * turns * TAU + side
				bulbs.append(Vector3(side * c + cos(a) * 0.15, 0.6 + t * 3.9, z + sin(a) * 0.15))
	# Looped between the columns along each bed, through the fronds, and from the gable posts.
	var ends: Array[float] = [front_z() + 0.3]
	ends.append_array(cz)
	ends.append(back_z() - 0.3)
	for side: float in [-1.0, 1.0]:
		for i in ends.size() - 1:
			var a := Vector3(side * (c + 0.05), 4.4, ends[i])
			var b := Vector3(side * (c + 0.05), 4.4, ends[i + 1])
			_catenary(bulbs, a, b, 1.1, 0.32)
			var low := a.lerp(b, 0.5) - Vector3(0, 1.0, 0)
			var glow := OmniLight3D.new()
			glow.name = "StringLight"
			glow.light_color = Color(1.0, 0.7, 0.4)
			glow.light_energy = 0.55
			glow.omni_range = 4.0
			glow.omni_attenuation = 1.4
			glow.position = low + Vector3(-side * 0.4, 0, 0)
			add_child(glow)
			_string_lights.append(glow)
	# Across the nave, high over the walk and the zones.
	for i: int in [0, cz.size() - 1]:
		var z: float = cz[i]
		var a := Vector3(-c, 4.9, z)
		var b := Vector3(c, 4.9, z)
		_catenary(bulbs, a, b, 0.6, 0.35)
	_string_mat = ZoneKit.glow(Color(1.0, 0.7, 0.36), 1.0)
	_string_mat.albedo_color = Color(1.0, 0.7, 0.36) * 1.8
	var ball := SphereMesh.new()
	ball.radius = 0.022
	ball.height = 0.044
	ball.radial_segments = 8
	ball.rings = 4
	var at: Array = []
	for p in bulbs:
		at.append(Transform3D(Basis.IDENTITY, p))
	var fairy := _bank("FairyLights", ball, at, false)
	fairy.material_override = _string_mat


func _catenary(out: Array[Vector3], a: Vector3, b: Vector3, sag: float, spacing: float) -> void:
	var count := int(a.distance_to(b) / spacing)
	for i in count:
		var t := (i + 0.5) / count
		out.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))


## Night: the flowers that open only now -- under every basket, over the ground cover along the
## kerb, and over the staging's pots -- glowing pale, and a little of their light on the leaves.
func _open_the_flowers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var at: Array = []
	var face_out := func(p: Vector3, toward: Vector3) -> Transform3D:
		var d := (toward - p)
		d.y = 0.0
		var yaw := atan2(-d.x, -d.z)
		return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.2))
				.scaled(Vector3.ONE * rng.randf_range(0.5, 0.75)), p)
	for xf: Transform3D in _baskets:
		for i in 4:
			var a := TAU * i / 4.0 + rng.randf()
			var p := xf.origin + Vector3(cos(a) * 0.3, -0.75 - rng.randf() * 0.3, sin(a) * 0.3)
			at.append(face_out.call(p, Vector3(0, p.y, p.z)))
	for kind: String in ["Aspidistra", "Monstera"]:
		for xf: Transform3D in planted.get(kind, []):
			if rng.randf() < 0.55:
				var p := xf.origin + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.45, 0.85), rng.randf_range(-0.15, 0.15))
				at.append(face_out.call(p, Vector3(0, p.y, p.z)))
	for i in range(0, _pots.size(), 3):
		var p: Vector3 = (_pots[i] as Transform3D).origin + Vector3(0, 0.45, 0)
		at.append(face_out.call(p, Vector3(p.x, p.y, 0.0)))
	var mesh := _mesh(_plant_scene, "Bloom", _plant_looks())
	_bank("NightFlowers", mesh, at, false)
	# Their glow on the beds: a cool white, faint, where they are thickest.
	for side: float in [-1.0, 1.0]:
		for z: float in [Studio.ROOM_BACK + 1.5, -0.5]:
			var glow := OmniLight3D.new()
			glow.name = "BloomGlow"
			glow.light_color = Color(0.85, 0.95, 1.0)
			glow.light_energy = 0.35
			glow.omni_range = 2.6
			glow.position = Vector3(side * (live_room_half() + 0.9), 0.9, z)
			add_child(glow)


## Night: fireflies drifting over the beds and the walk, and out in the garden past the glass.
func _release_the_fireflies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	mm.mesh = quad
	var spots: Array = []
	var half := live_room_half()
	var w := wall_x()
	for i in 110:
		# Inside: mostly over the beds, some over the walk.
		var x := rng.randf_range(-w + 0.3, w - 0.3)
		var z := rng.randf_range(front_z() + 0.3, back_z() - 0.3)
		if absf(x) < half and rng.randf() < 0.6:
			x = signf(x if x != 0.0 else 1.0) * rng.randf_range(half + 0.3, w - 0.3)
		spots.append(Vector3(x, rng.randf_range(0.4, 3.0), z))
	for i in 160:
		var a := rng.randf() * TAU
		var d := w + 3.0 + rng.randf() * 28.0
		spots.append(Vector3(sin(a) * d, rng.randf_range(0.3, 2.6), (front_z() + back_z()) * 0.5 + cos(a) * d * 1.3))
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.3, 0.9), rng.randf(), 0))
	var node := MultiMeshInstance3D.new()
	node.name = "Fireflies"
	node.multimesh = mm
	_firefly_mat = ShaderMaterial.new()
	_firefly_mat.shader = preload("res://core/venues/shaders/greenhouse_firefly.gdshader")
	node.material_override = _firefly_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm.custom_aabb = AABB(Vector3(-50, -1, -50), Vector3(100, 6, 110))
	add_child(node)


# --- the zones ------------------------------------------------------------------------------

## The zones in the house's own materials: a teak-topped riser on green iron, the booth a
## Wardian case (white iron and glass, a pitched glass roof on it), the lattice's square inlaid
## in black and buff tile round a brass rose, a teak potting table on green legs, and the keys on
## a green stand -- each under its lantern.
func _dress_zones() -> void:
	var z := zones()
	var white := _white_iron()
	var green := _green_iron()
	var teak := _teak()

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, teak, green)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := _clear_glass()
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, white, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.76, 0.5),
			1.3, 60.0, 3.2, white)
	# The case's glass roof: two panes pitched to a ridge along it, with a finial at each end.
	var hx := booth_box.size.x * 0.5
	var rise := 0.45
	var slope := atan2(rise, hx)
	var pane := sqrt(hx * hx + rise * rise)
	for s: float in [-1.0, 1.0]:
		# Panes and bars stop short of the ridge, under the ridge beam, so the two sides never meet.
		var short := Vector3(s * cos(slope), -sin(slope), 0) * 0.04
		var roof := ZoneKit.block(vocals, Vector3(pane - 0.08, 0.012, booth_box.size.z - 0.02),
				Vector3(s * hx * 0.5, booth_box.size.y + rise * 0.5 + 0.006, 0) + short, glass, "CaseRoof%d" % [int(s)])
		roof.rotation.z = -s * slope
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rafter := ZoneKit.block(vocals, Vector3(pane - 0.08, 0.04, 0.04), Vector3(s * hx * 0.5, booth_box.size.y + rise * 0.5
				- 0.0215, 0) + short, white, "CaseRafter%d" % [int(s)])
		rafter.rotation.z = -s * slope
		for e: float in [-1.0, 1.0]:
			var edge := ZoneKit.block(vocals, Vector3(pane - 0.08, 0.035, 0.035), Vector3(s * hx * 0.5, booth_box.size.y + rise * 0.5
					- 0.0205, e * (booth_box.size.z * 0.5 - 0.03)) + short, white, "CaseEave%d%d" % [int(s), int(e)])
			edge.rotation.z = -s * slope
	ZoneKit.block(vocals, Vector3(0.05, 0.05, booth_box.size.z + 0.06), Vector3(0, booth_box.size.y + rise + 0.03, 0), white,
			"CaseRidge")
	for e: float in [-1.0, 1.0]:
		var finial := MeshInstance3D.new()
		finial.name = "CaseFinial"
		var knob := SphereMesh.new()
		knob.radius = 0.045
		knob.height = 0.11
		knob.radial_segments = 12
		knob.rings = 6
		finial.mesh = knob
		finial.material_override = white
		finial.position = Vector3(0, booth_box.size.y + rise + 0.1, e * (booth_box.size.z * 0.5 + 0.03))
		vocals.add_child(finial)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var black := ZoneKit._paint(Color(0.06, 0.055, 0.05), 0.6)
	var buff := ZoneKit._paint(Color(0.72, 0.6, 0.42), 0.65)
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.1, black)
	ZoneKit.floor_frame(matrix, Vector2(2.84, 2.84), Vector3(0, 0.0015, 0), 0.05, buff)
	var rose := MeshInstance3D.new()
	rose.name = "Rose"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.32
	disc.bottom_radius = 0.32
	disc.height = 0.006
	disc.radial_segments = 32
	rose.mesh = disc
	rose.position = Vector3(0, 0.0035, 0)
	rose.material_override = GearStyle.metal(Color(0.75, 0.6, 0.32), 0.35)
	matrix.add_child(rose)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, teak, green)
	_dress_prop_shelf(teak, green)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, green, teak)


# --- the mirror -----------------------------------------------------------------------------

## The mirror stands at the footprint's left edge on the tiles, framed in the house's white
## iron, with a little arched cresting over it.
func _frame_mirror(mirror: Mirror) -> void:
	var white := _white_iron()
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, white)
	var crest := MeshInstance3D.new()
	crest.name = "Cresting"
	var arc := TorusMesh.new()
	arc.inner_radius = mirror.glass_size.x * 0.5 - 0.02
	arc.outer_radius = mirror.glass_size.x * 0.5 + 0.02
	arc.rings = 24
	arc.ring_segments = 8
	crest.mesh = arc
	crest.material_override = white
	crest.rotation.x = PI * 0.5
	crest.scale = Vector3(1.0, 1.0, 0.5)
	crest.position = Vector3(0, mirror.glass_size.y * 0.5 + 0.05, -0.006)
	mirror.add_child(crest)


## The tracks' colours here (TrackColours), in its STANDARD order.
## The glasshouse in flower: geranium, nasturtium, primrose, new growth, fern, verdigris,
## plumbago, delphinium, lavender, fuchsia, camellia, and the grey of stone.
func track_palette() -> Array:
	return [
		Color(0.86, 0.26, 0.24), Color(0.95, 0.52, 0.2), Color(0.95, 0.82, 0.36), Color(0.62, 0.8, 0.3),
		Color(0.26, 0.62, 0.32), Color(0.3, 0.66, 0.58), Color(0.5, 0.7, 0.9), Color(0.3, 0.42, 0.82),
		Color(0.6, 0.5, 0.82), Color(0.82, 0.3, 0.6), Color(0.96, 0.62, 0.68), Color(0.68, 0.68, 0.64),
	]
