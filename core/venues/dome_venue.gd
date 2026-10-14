class_name DomeVenue
extends Venue

## A habitat on the sea floor, twenty metres down: a glass vault over a teak deck, its long sides
## and its rounded nose all glass on steel arches, the back closed by a steel bulkhead with a
## hatch through it. Round the deck a trench of sand runs to the glass's foot behind a glass
## rail, and the sand runs on outside into a kelp forest that sways in the swell. The light
## comes from above: the sun through the surface, laid across the deck in the arches' shadows
## and in caustics, a moving web of light on the deck and the sand, and in shafts slanting down
## through the water outside. The vocal booth is the sub bay: framed in the yellow of the small
## submersible docked against the glass beside it, its collar run through to the booth's back.
##
## Three arrangements, three sea floors. TWENTY_METRES, as first built. DEEP: the same dome far
## down in the abyss, where no sunlight reaches: black water full of falling marine snow and
## glowing plankton, jellyfish drifting up past the glass lit by their own light, a black smoker
## venting on the floor ahead with tube worms round its feet, and the dome's own floodlights,
## out on its plinth, throwing beams across the sand. WRECK: back up in the light, beside a
## sunken brig lying over in the sand ahead, coral grown over her, fish schooling round her
## standing mast, her debris strewn round her, and the sun's shafts falling through the water
## onto her deck.

## The vault's radius past the live room's half width: the glass stands this far out from the
## deck's edge, and the trench of sand is between.
const CLEARANCE := 0.9
## The sand's depth below the deck, in the trench and outside.
const TRENCH := 0.6
## Where the vault meets its rounded nose: the footprint's front edge.
const NOSE := (Studio.ROOM_FRONT - 0.3)
## The bulkhead's inside face.
const BACK := LIVE_ROOM_BACK + 0.05
const ARCH_SPACING := 2.4
## The rail round the deck's edge.
const RAIL := 1.0
## The sun, overhead and a little ahead: its light's direction is the opposite of this.
const SUN_DIR := Vector3(0.2, 1.0, -0.35)
## The collar from the booth to the sub: its height and radius. The sub's own collar flange is
## this far from its hull's centre (minisub.glb).
const COLLAR_Y := 1.2
const COLLAR_R := 0.62
const SUB_FLANGE := 1.09
## The bulkhead's hatch (hatch.glb's outside).
const HATCH := Vector2(2.0, 2.7)
const MODELS := "res://assets/models/"

## The arrangements (Venue.VARIANTS).
const TWENTY_METRES := 0
const DEEP := 1
const WRECK := 2
## The wreck's sun: lower and from ahead and to the left, so its shafts lean across the view and
## down onto the wreck.
const WRECK_SUN := Vector3(-0.4, 1.0, -0.55)
## The wreck (dome_wreck.glb): where she lies in the clearing ahead of the nose, and how she is
## turned -- across the view, her bow off to the right and a little away, her deck heeled toward
## the glass.
const WRECK_AT := Vector3(1.5, -TRENCH, -21.5)
const WRECK_YAW := PI - 0.3
## The vent field in the deep (dome_vent.glb): ahead and to the left, where the desk sees it past
## the timeline.
const VENT_AT := Vector3(-8.5, -TRENCH, -17.0)
## The floodlights on the vault's plinth in the deep: each (round the vault from the right-hand
## foot, 0..PI; along the side, as a z), throwing its beam out and down onto the sand.
const FLOODS := [[0.0, -1.0], [0.0, 4.0], [PI, -1.0], [PI, 4.0]]
const NOSE_FLOODS := [0.55, 1.57, 2.6]

## Where each kelp stalk stands (studio space), kept for the tests: a headless MultiMesh does not
## keep its instance transforms.
var kelp_spots: Array[Transform3D] = []
var shafts: Array[MeshInstance3D] = []
## The reef: each piece's kind (an object in reef.glb) and where it sits.
var reef: Array = []
## The fish: each one's (start in its sweep, out from the path, height, sweep rate), as
## fish.gdshader reads them.
var fish_paths: Array[Vector4] = []
## The wreck's transform (studio space), and where on her the coral grows, in hers.
var wreck_at := Transform3D.IDENTITY
var wreck_spots: Array[Transform3D] = []
## The path the schools swim: round the nose and down the sides, squared off (`SCHOOL_SQUARE`
## below 1) to keep clear of the glass, swept `SCHOOL_SWEEP` radians either side of the nose.
const SCHOOL_CENTRE := Vector3(0.0, 0.0, -2.3)
const SCHOOL_RADII := Vector2(9.6, 10.8)
const SCHOOL_SQUARE := 0.3
const SCHOOL_SWEEP := 2.1


func venue_id() -> StringName:
	return &"dome"


## Nothing to hang the roll board or the roulette panel on: they stand.
func back_wall_gear_stands() -> bool:
	return true


## Teal-painted plate, verdigris-brushed brass and a soft aqua edge: kit that has lived under
## the water a while.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("blue_metal_plate", 1.2, Color(0.42, 0.7, 0.66))) \
			.with("chassis", GearStyle.paint(Color(0.05, 0.085, 0.09), 0.6, 0.35)) \
			.with("brushed", GearStyle.metal(Color(0.72, 0.58, 0.32), 0.42)) \
			.with("trim", GearStyle.glow(Color(0.3, 1.0, 0.88), 1.0)) \
			.with("end_cheek", GearStyle.metal(Color(0.36, 0.55, 0.46), 0.75)) \
			.with("lamp_shade", GearStyle.metal(Color(0.72, 0.58, 0.32), 0.42)) \
			.with("loom_band", GearStyle.metal(Color(0.72, 0.58, 0.32), 0.42)) \
			.with("knob_cap", GearStyle.metal(Color(0.42, 0.32, 0.16), 0.45))


## Teal plate gone dark under the water, pale aqua lettering, brass arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.scan("blue_metal_plate", 0.6, Color(0.18, 0.32, 0.3))
	board.ink = Color(0.8, 1.0, 0.95)
	board.accent = Color(0.85, 0.68, 0.38)
	board.board_ink_fade = Color(0.35, 0.5, 0.48)


## Where the sun is, this arrangement. In the deep there is none; what little reaches down is
## from straight overhead.
func sun_dir() -> Vector3:
	match variant:
		DEEP:
			return Vector3(0.05, 1.0, -0.1)
		WRECK:
			return WRECK_SUN
	return SUN_DIR


## How hard the caustics play on the deck and the sand: none where the sun does not reach.
func _caustics() -> float:
	return 0.0 if variant == DEEP else 1.0


func dress(env: Environment, key: DirectionalLight3D) -> void:
	if variant == DEEP:
		_dress_deep(env, key)
		return
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://core/venues/shaders/undersea_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", sun_dir())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.55, 0.6)
	env.ambient_light_energy = 0.22
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	# The water: everything past a few metres goes into its teal, the forest's far edge gone.
	# The sky shader draws the water itself, so the fog leaves it alone.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.015, 0.075, 0.1)
	env.fog_depth_begin = 4.0
	env.fog_depth_end = 42.0
	env.fog_depth_curve = 0.8
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2

	# The sun through twenty metres of water: green-blue, soft, from nearly overhead.
	key.light_color = Color(0.7, 0.95, 0.95)
	key.light_energy = 1.1
	key.basis = Basis.looking_at(-sun_dir().normalized(), Vector3.FORWARD)
	key.light_specular = 0.4
	if variant == WRECK:
		# Clearer water over the wreck, a little greener, and further to see: she is twenty
		# metres off.
		sky_mat.set_shader_parameter("horizon", Color(0.02, 0.1, 0.1))
		sky_mat.set_shader_parameter("high", Color(0.07, 0.27, 0.26))
		env.fog_light_color = Color(0.02, 0.095, 0.1)
		env.fog_depth_begin = 6.0
		env.fog_depth_end = 64.0
		key.light_color = Color(0.78, 0.98, 0.9)
		key.light_energy = 1.05


## The abyss: no sun, no surface overhead, black water going to blacker. A trace of blue from
## above that is less light than the idea of it; everything else is the dome's own lights and
## what glows out there by itself.
func _dress_deep(env: Environment, key: DirectionalLight3D) -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://core/venues/shaders/undersea_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", sun_dir())
	sky_mat.set_shader_parameter("deep", Color(0.0, 0.002, 0.005))
	sky_mat.set_shader_parameter("horizon", Color(0.002, 0.009, 0.017))
	sky_mat.set_shader_parameter("high", Color(0.003, 0.012, 0.022))
	# No window to the surface: it is the same black as the rest.
	sky_mat.set_shader_parameter("window", Color(0.003, 0.011, 0.02))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.32, 0.5)
	env.ambient_light_energy = 0.12
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	# What glows out there blooms: the jellies, the plankton, the vent's throat.
	env.glow_intensity = 0.7
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.003, 0.012, 0.022)
	env.fog_depth_begin = 3.0
	env.fog_depth_end = 34.0
	env.fog_depth_curve = 0.9
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
	key.light_color = Color(0.3, 0.5, 0.9)
	key.light_energy = 0.05
	key.basis = Basis.looking_at(-sun_dir().normalized(), Vector3.FORWARD)
	key.light_specular = 0.1


func lamp_colour(_index: int, authored: Color) -> Color:
	return authored.lerp(Color(0.85, 0.95, 1.0), 0.2)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.9


## The deck: the working footprint and the live room, and the strips either side of the
## footprint out to the rail.
func rooms() -> Array[Rect2]:
	var half := live_room_half()
	var cr := room_width * 0.5
	return [back_of_house(),
			Rect2(-half, NOSE, half - cr, Studio.ROOM_DEPTH),
			Rect2(cr, NOSE, half - cr, Studio.ROOM_DEPTH)]


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), true)


## The vault's radius: out past the deck's edge by CLEARANCE.
func radius() -> float:
	return live_room_half() + CLEARANCE


## Where the sub's hull centre is: beside the booth, outside the glass, its collar flange meeting
## the one run out from the booth's back.
func sub_spot() -> Vector3:
	var booth: AABB = zones()[&"vocals"]
	return Vector3(-(radius() + 0.25) - SUB_FLANGE, COLLAR_Y, booth.get_center().z)


func _ready() -> void:
	_lay_the_deck()
	_lay_the_sand()
	_raise_the_vault()
	_build_bulkhead()
	_run_the_rail()
	_dock_the_sub()
	match variant:
		DEEP:
			_seed_the_reef()
			_raise_the_vent()
			_set_the_jellies_adrift()
			_let_the_snow_fall()
			_light_the_floods()
			_raise_bubbles()
		WRECK:
			_sink_the_wreck()
			_plant_the_kelp()
			_seed_the_reef()
			_school_the_fish()
			_school_round_the_wreck()
			_slant_the_shafts()
			_raise_bubbles()
		_:
			_plant_the_kelp()
			_seed_the_reef()
			_school_the_fish()
			_slant_the_shafts()
			_raise_bubbles()
	_dress_zones()


# --- materials -------------------------------------------------------------------------------

func _ground(id: String, res: String, metres: float, tint: Color, cell: float, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/caustic_ground.gdshader")
	var base := "res://assets/textures/%s/%s_%%s_%s.jpg" % [id, id, res]
	m.set_shader_parameter("albedo_tex", load(base % "diff"))
	m.set_shader_parameter("normal_tex", load(base % "nor_gl"))
	m.set_shader_parameter("arm_tex", load(base % "arm"))
	m.set_shader_parameter("metres", metres)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("strength", strength)
	return m


func _steel() -> StandardMaterial3D:
	return Materials.cached_scanned("dome_steel", "blue_metal_plate", "2k", 2.4, Color(0.75, 0.82, 0.9))


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.albedo_color = Color(0.08, 0.12, 0.13, 0.08)
	glass.roughness = 0.05
	glass.metallic_specular = 0.25
	# No highlights from the lamps: on this much glass, so close, they are white blobs.
	glass.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return glass


func _paint() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.62, 0.05)
	m.roughness = 0.38
	m.metallic_specular = 0.5
	return m


func _dark() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.07, 0.08)
	m.metallic = 0.5
	m.roughness = 0.45
	return m


# --- the floor --------------------------------------------------------------------------------

## The teak deck, its steel skirt down to the sand at its edges, and the step under the hatch.
func _lay_the_deck() -> void:
	var half := live_room_half()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, BACK - NOSE)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, (NOSE + BACK) * 0.5)
	floor_mesh.material_override = _ground("wood_floor_deck", "2k", 2.2, Color(0.66, 0.66, 0.64), 2.2, 1.6 * _caustics())
	add_child(floor_mesh)
	var steel := _steel()
	var skirt := TRENCH - 0.004
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.06, skirt, BACK - NOSE), Vector3(side * (half + 0.03), -0.004 - skirt * 0.5,
				(NOSE + BACK) * 0.5), steel, "Skirt")
	ZoneKit.block(self, Vector3(half * 2.0 + 0.12, skirt, 0.06), Vector3(0, -0.004 - skirt * 0.5, NOSE - 0.03), steel,
			"Skirt")


## The sand: in the trench round the deck and outside the glass, one plain, rippled sea floor.
func _lay_the_sand() -> void:
	var sand := MeshInstance3D.new()
	sand.name = "Sand"
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	sand.mesh = plane
	sand.position = Vector3(0, -TRENCH, 0)
	# In the deep the sand is the grey ooze of the abyss.
	var tint := Color(0.3, 0.33, 0.34) if variant == DEEP else Color(0.72, 0.8, 0.76)
	sand.material_override = _ground("coast_sand_01", "1k", 3.0, tint, 2.6, 1.3 * _caustics())
	add_child(sand)


# --- the vault ------------------------------------------------------------------------------

## A point on the vault's glass: `theta` round from the right-hand foot (0) over the top to the
## left (PI), at `z` along the vault, or, in front of the nose, `alpha` round the nose toward
## its front.
func _on_vault(r: float, theta: float, z: float, alpha := 0.0) -> Vector3:
	return Vector3(r * cos(alpha) * cos(theta), r * cos(alpha) * sin(theta), z - r * sin(alpha))


## The glass: a half cylinder from the nose back to the bulkhead, and a quarter sphere for the
## nose. Its foot is on the plinth at deck height.
func _raise_the_vault() -> void:
	var r := radius()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around := 40
	for i in around:
		var a0 := PI * i / around
		var a1 := PI * (i + 1) / around
		_quad(st, _on_vault(r, a0, NOSE), _on_vault(r, a1, NOSE), _on_vault(r, a1, BACK), _on_vault(r, a0, BACK))
	var rings := 12
	for j in rings:
		var b0 := PI * 0.5 * j / rings
		var b1 := PI * 0.5 * (j + 1) / rings
		for i in around:
			var a0 := PI * i / around
			var a1 := PI * (i + 1) / around
			_quad(st, _on_vault(r, a0, NOSE, b1), _on_vault(r, a1, NOSE, b1), _on_vault(r, a1, NOSE, b0),
					_on_vault(r, a0, NOSE, b0))
	st.generate_normals()
	var glass := MeshInstance3D.new()
	glass.name = "Vault"
	glass.mesh = st.commit()
	glass.material_override = _glass()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	# The arches: along the vault every ARCH_SPACING, and round the nose as shrinking rings.
	var dark := _dark()
	var arches := SurfaceTool.new()
	arches.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := NOSE
	while z < BACK - 0.5:
		_arch(arches, r, z, 0.0)
		z += ARCH_SPACING
	_arch(arches, r, BACK - 0.08, 0.0)
	for deg in [28.0, 55.0, 76.0]:
		_arch(arches, r, NOSE, deg_to_rad(deg))
	arches.generate_normals()
	var frame := MeshInstance3D.new()
	frame.name = "Arches"
	frame.mesh = arches.commit()
	frame.material_override = dark
	add_child(frame)
	# The spine along the top.
	ZoneKit.block(self, Vector3(0.12, 0.16, BACK - NOSE), Vector3(0, r - 0.1, (NOSE + BACK) * 0.5), dark, "Spine")

	# The plinth the glass stands on: a steel kerb from the sand to deck height, along both
	# sides and round the nose.
	var steel := _steel()
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.4, TRENCH + 0.12, BACK - NOSE), Vector3(side * r, -TRENCH * 0.5 + 0.06,
				(NOSE + BACK) * 0.5), steel, "Plinth")
	var kerb := SurfaceTool.new()
	kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 24
	for i in steps:
		var a0 := PI * i / steps
		var a1 := PI * (i + 1) / steps
		var p0 := Vector3(r * cos(a0), 0, NOSE - r * sin(a0))
		var p1 := Vector3(r * cos(a1), 0, NOSE - r * sin(a1))
		var n0 := Vector3(cos(a0), 0, -sin(a0)) * 0.2
		var n1 := Vector3(cos(a1), 0, -sin(a1)) * 0.2
		var top := Vector3(0, 0.06, 0)
		var foot := Vector3(0, -TRENCH, 0)
		_quad(kerb, p0 - n0 + top, p0 + n0 + top, p1 + n1 + top, p1 - n1 + top)
		_quad(kerb, p0 + n0 + top, p0 + n0 + foot, p1 + n1 + foot, p1 + n1 + top)
		_quad(kerb, p1 - n1 + top, p1 - n1 + foot, p0 - n0 + foot, p0 - n0 + top)
	kerb.generate_normals()
	var nose := MeshInstance3D.new()
	nose.name = "NosePlinth"
	nose.mesh = kerb.commit()
	nose.material_override = steel
	add_child(nose)


## One arch: a steel section 12 cm along the vault and 16 cm deep, just inside the glass.
func _arch(st: SurfaceTool, r: float, z: float, alpha: float) -> void:
	var steps := 40
	var w := 0.06
	var depth := 0.16
	for i in steps:
		var corners := []
		for a in [PI * i / steps, PI * (i + 1) / steps]:
			var outward := _on_vault(1.0, a, 0.0, alpha)
			var along := Vector3(-sin(alpha) * cos(a), -sin(alpha) * sin(a), -cos(alpha))
			var at := _on_vault(r - 0.015, a, z, alpha)
			corners.append([at + along * w, at - along * w, at - along * w - outward * depth, at + along * w - outward * depth])
		var c0: Array = corners[0]
		var c1: Array = corners[1]
		for k in 4:
			_quad(st, c0[k], c0[(k + 1) % 4], c1[(k + 1) % 4], c1[k])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


# --- the back ---------------------------------------------------------------------------------

## The bulkhead: a half disc of steel plate closing the vault, from the sand up, with a pressure
## hatch through it at deck level and a lit lock behind the hatch's glass.
func _build_bulkhead() -> void:
	var r := radius()
	var outline := PackedVector2Array()
	var hw := HATCH.x * 0.5
	outline.append(Vector2(-r, -TRENCH))
	outline.append(Vector2(-hw, -TRENCH))
	outline.append(Vector2(-hw, HATCH.y))
	outline.append(Vector2(hw, HATCH.y))
	outline.append(Vector2(hw, -TRENCH))
	outline.append(Vector2(r, -TRENCH))
	var steps := 40
	for i in steps + 1:
		var a := PI * i / steps
		outline.append(Vector2(r * cos(a), r * sin(a)))
	var tris := Geometry2D.triangulate_polygon(outline)
	var thick := 0.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [0.0, thick]:
		for t in range(0, tris.size(), 3):
			var idx := [tris[t], tris[t + 1], tris[t + 2]]
			if face == 0.0:
				idx.reverse()
			for k in idx:
				st.add_vertex(Vector3(outline[k].x, outline[k].y, BACK + face))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_quad(st, Vector3(b.x, b.y, BACK), Vector3(b.x, b.y, BACK + thick), Vector3(a.x, a.y, BACK + thick),
				Vector3(a.x, a.y, BACK))
	st.generate_normals()
	var wall := MeshInstance3D.new()
	wall.name = "Bulkhead"
	wall.mesh = st.commit()
	wall.material_override = _steel()
	add_child(wall)
	# The step under the hatch, from the sand to the deck.
	ZoneKit.block(self, Vector3(HATCH.x - 0.004, TRENCH - 0.004, thick + 0.2), Vector3(0, -TRENCH * 0.5 - 0.002,
			BACK + thick * 0.5 + 0.1), _steel(), "Threshold")
	var hatch := _model("hatch.glb", Vector3(0, 0, BACK + thick * 0.5), 0.0,
			{"frame": _dark(), "hazard": _hazard(), "lamp": ZoneKit.glow(Color(1.0, 0.6, 0.2), 1.6)})
	hatch.name = "Hatch"
	var door := ZoneKit.block(self, Vector3(1.5, 2.35, 0.03), Vector3(0, 0.06 + 1.125, BACK + thick * 0.5),
			_glass(), "HatchGlass")
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The lock beyond: a short steel room, lit warm, its far door shut.
	var lock_depth := 2.6
	var lz := BACK + thick + lock_depth * 0.5
	var steel := _steel()
	ZoneKit.block(self, Vector3(2.4, 0.1, lock_depth), Vector3(0, -0.05, lz), steel, "LockFloor")
	ZoneKit.block(self, Vector3(2.4, 0.1, lock_depth), Vector3(0, 2.75, lz), steel, "LockCeiling")
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.1, 2.7, lock_depth), Vector3(side * 1.15, 1.35, lz), steel, "LockWall")
	ZoneKit.block(self, Vector3(2.2, 2.7, 0.1), Vector3(0, 1.35, BACK + thick + lock_depth - 0.05), _dark(), "LockDoor")
	# Two washes on the bulkhead from the spine, so the back of the room is not a black wall.
	for x in [-3.2, 3.2]:
		var wash := SpotLight3D.new()
		wash.name = "BulkheadWash"
		wash.light_color = Color(0.85, 0.95, 1.0)
		wash.light_energy = 2.2
		wash.spot_range = 8.0
		wash.spot_angle = 50.0
		wash.position = Vector3(x, radius() - 1.6, BACK - 2.2)
		wash.basis = Basis.looking_at(Vector3(x * 1.1, 1.2, BACK) - wash.position, Vector3.UP)
		add_child(wash)
	var lamp := OmniLight3D.new()
	lamp.name = "LockLight"
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.2
	lamp.omni_range = 3.0
	lamp.position = Vector3(0, 2.4, lz)
	add_child(lamp)


func _hazard() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/hazard.gdshader")
	return m


# --- the rail --------------------------------------------------------------------------------

## Glass panels on steel posts with a steel handrail, along the deck's front and sides: the edge
## of the floor, where the trench drops to the sand. None where the sub's collar crosses.
func _run_the_rail() -> void:
	var half := live_room_half()
	var dark := _dark()
	var glass := _glass()
	var booth: AABB = zones()[&"vocals"]
	var gap := Vector2(booth.position.z, booth.end.z)
	var runs: Array = [[Vector3(-half, 0, NOSE), Vector3(half, 0, NOSE)],
			[Vector3(half, 0, NOSE), Vector3(half, 0, BACK)],
			[Vector3(-half, 0, NOSE), Vector3(-half, 0, gap.x)],
			[Vector3(-half, 0, gap.y), Vector3(-half, 0, BACK)]]
	# A corner's post is shared by the two runs that meet there: put it up once.
	var posted := {}
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var length := a.distance_to(b)
		if length < 0.3:
			continue
		var dir := (b - a) / length
		var across_x := absf(dir.x) > 0.5
		var posts := maxi(1, ceili(length / 1.6))
		for i in posts + 1:
			var p := a + dir * (length * i / posts)
			var key := Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0))
			if posted.has(key):
				continue
			posted[key] = true
			ZoneKit.block(self, Vector3(0.05, RAIL - 0.03, 0.05), p + Vector3(0, (RAIL - 0.03) * 0.5, 0), dark, "Post")
		var mid := (a + b) * 0.5
		# The side rails a hair slimmer than the front one, so where they cross at the corners
		# their tops are not one plane.
		var rail_size := Vector3(length, 0.05, 0.06) if across_x else Vector3(0.056, 0.046, length)
		ZoneKit.block(self, rail_size, mid + Vector3(0, RAIL - 0.005, 0), dark, "Handrail")
		var pane_size := Vector3(length - 0.06, RAIL - 0.16, 0.012) if across_x else Vector3(0.012, RAIL - 0.16, length - 0.06)
		var pane := ZoneKit.block(self, pane_size, mid + Vector3(0, 0.06 + (RAIL - 0.16) * 0.5, 0), glass,
				"RailGlass%d" % runs.find(run))
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- the sub ---------------------------------------------------------------------------------

## The sub docked beside the booth, outside the glass, and the collar from the booth's back
## through the glass to the sub's own: a steel tube with a flange where it passes the glass.
func _dock_the_sub() -> void:
	var at := sub_spot()
	var sub := _model("minisub.glb", at, PI * 0.5, {"hull": _paint(), "glass": _glass(), "dark": _dark(),
			"steel": Materials.brushed_metal(), "lamp": ZoneKit.glow(Color(1.0, 0.9, 0.7), 2.0)})
	sub.name = "Sub"
	var booth: AABB = zones()[&"vocals"]
	var from_x := booth.position.x + ZoneKit.BOOTH_POST * 0.5
	var to_x := at.x + SUB_FLANGE
	var tube := MeshInstance3D.new()
	tube.name = "Collar"
	var cyl := CylinderMesh.new()
	cyl.top_radius = COLLAR_R
	cyl.bottom_radius = COLLAR_R
	cyl.height = from_x - to_x
	cyl.radial_segments = 32
	tube.mesh = cyl
	tube.material_override = Materials.brushed_metal()
	tube.rotation.z = PI * 0.5
	tube.position = Vector3((from_x + to_x) * 0.5, COLLAR_Y, at.z)
	add_child(tube)
	# The flange where it goes through the vault's glass, and a hazard ring round its mouth.
	var r := radius()
	var through := -sqrt(r * r - COLLAR_Y * COLLAR_Y)
	for spec in [[through, 0.82, 0.08, _dark(), "CollarFlange"], [from_x - 0.03, 0.72, 0.05, _hazard(), "CollarMouth"]]:
		var ring := MeshInstance3D.new()
		ring.name = spec[4]
		var disc := CylinderMesh.new()
		disc.top_radius = spec[1]
		disc.bottom_radius = spec[1]
		disc.height = spec[2]
		disc.radial_segments = 32
		ring.mesh = disc
		ring.material_override = spec[3]
		ring.rotation.z = PI * 0.5
		ring.position = Vector3(spec[0], COLLAR_Y, at.z)
		add_child(ring)
	# Its lamps light the sand in front of it.
	var beam := SpotLight3D.new()
	beam.name = "SubLamp"
	beam.light_color = Color(1.0, 0.92, 0.75)
	beam.light_energy = 3.0
	beam.spot_range = 9.0
	beam.spot_angle = 30.0
	beam.position = at + Vector3(0, 0.42, -1.3)
	beam.rotation = Vector3(-0.45, 0, 0)
	add_child(beam)


# --- outside ---------------------------------------------------------------------------------

## The kelp forest: stalks of kelp.glb in one MultiMesh, standing round the vault from a little
## past the glass out into the murk, thicker at the sides, a clearing ahead so the view from the
## desk runs out into the water, and none where the sub is.
func _plant_the_kelp() -> void:
	var source := (load(MODELS + "kelp.glb") as PackedScene).instantiate()
	var mesh := ((source.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D).mesh.duplicate() as ArrayMesh
	source.free()
	var stipe := ShaderMaterial.new()
	stipe.shader = preload("res://core/venues/shaders/kelp.gdshader")
	stipe.set_shader_parameter("colour", Color(0.24, 0.19, 0.06))
	var blade := ShaderMaterial.new()
	blade.shader = stipe.shader
	mesh.surface_set_material(0, stipe)
	mesh.surface_set_material(1, blade)
	var r := radius()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var sub := sub_spot()
	kelp_spots.clear()
	var tries := 0
	while kelp_spots.size() < 150 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(-32, 32), rng.randf_range(-34, 26))
		# How far outside the glass: from the vault's axis along its length, from the nose's
		# centre in front of it.
		var out := absf(p.x) - r if p.y > NOSE else Vector2(p.x, p.y - NOSE).length() - r
		if out < 1.2:
			continue
		if Vector2(p.x - sub.x, p.y - sub.z).length() < 3.2:
			continue
		# The clearing ahead of the desk.
		if p.y < NOSE - r and absf(p.x) < 3.0 + (NOSE - r - p.y) * 0.25:
			continue
		# Sparser close in, so the glass is not walled in by it.
		if out < 4.0 and rng.randf() < 0.5:
			continue
		# None over the wreck, and a margin of open sand round her.
		if variant == WRECK and _near_the_wreck(p, 4.5):
			continue
		var s := rng.randf_range(0.8, 1.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
		kelp_spots.append(Transform3D(basis, Vector3(p.x, -TRENCH, p.y)))
	var forest := MultiMesh.new()
	forest.transform_format = MultiMesh.TRANSFORM_3D
	forest.mesh = mesh
	forest.instance_count = kelp_spots.size()
	for i in kelp_spots.size():
		forest.set_instance_transform(i, kelp_spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Kelp"
	node.multimesh = forest
	add_child(node)


## Rocks and a little coral in the trench: most of it in the sand in front of the nose, where
## the desk looks down on it over the deck's edge, a few small pieces along the sides, and some
## big boulders out among the kelp. All from reef.glb, one MultiMesh a kind.
func _seed_the_reef() -> void:
	var r := radius()
	var half := live_room_half()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	reef.clear()
	var place := func(kind: String, at: Vector2, size: float) -> void:
		reef.append([kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size),
				Vector3(at.x, -TRENCH, at.y))])
	# The nose: the half disc of sand between the deck's front edge and the glass.
	var kinds := ["Rock0", "Rock1", "Rock2", "CoralBranch", "CoralBranch", "CoralBrain", "CoralFan", "CoralFan"]
	if variant == DEEP:
		# Nothing grows in the dark but the odd pale sea fan: the rest is rock.
		kinds = ["Rock0", "Rock1", "Rock2", "Rock0", "Rock1", "Rock2", "CoralFan", "CoralFan"]
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 34 and tries < 3000:
		tries += 1
		var a := rng.randf_range(PI * 1.05, PI * 1.95)
		var d := sqrt(rng.randf()) * (r - 0.7)
		var p := Vector2(cos(a) * d, NOSE + sin(a) * d)
		if p.y > NOSE - 0.35:
			continue
		if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < 0.55):
			continue
		placed.append(p)
		var kind: String = kinds[rng.randi() % kinds.size()]
		place.call(kind, p, rng.randf_range(0.5, 1.0) if kind.begins_with("Rock") else rng.randf_range(0.8, 1.4))
	# The sides: a narrow strip of sand, so only the small pieces.
	for side in [-1.0, 1.0]:
		var z := NOSE + 0.6
		while z < BACK - 1.0:
			z += rng.randf_range(0.8, 1.8)
			var kind: String = ["CoralBrain", "CoralFan", "CoralBranch"][rng.randi() % 3]
			if variant == DEEP:
				kind = ["Rock0", "CoralFan", "Rock2"][rng.randi() % 3]
			place.call(kind, Vector2(side * (half + 0.45 + rng.randf_range(-0.08, 0.08)), z), rng.randf_range(0.7, 1.0))
	# Outside: boulders among the kelp, a few in the clearing ahead.
	for at in [Vector2(-9.5, -12.0), Vector2(6.5, -15.0), Vector2(11.0, -4.0), Vector2(-12.0, 2.0),
			Vector2(-3.5, -17.0), Vector2(13.0, 6.0)]:
		var kind := "Rock%d" % (rng.randi() % 3)
		var size := rng.randf_range(2.0, 3.6)
		# Not on the wreck, nor on the vent's mound.
		if (variant == WRECK and _near_the_wreck(at, 2.0)) \
				or (variant == DEEP and at.distance_to(Vector2(VENT_AT.x, VENT_AT.z)) < 6.5):
			continue
		place.call(kind, at, size)
	# The coral grown over the wreck, at the spots on her that face up (dome_wreck.glb).
	if variant == WRECK:
		var coral := ["CoralBranch", "CoralBrain", "CoralFan", "CoralBranch", "CoralFan"]
		for spot in wreck_spots:
			var turn := Basis(Vector3.UP, rng.randf() * TAU)
			var on := wreck_at * spot
			reef.append([coral[rng.randi() % coral.size()],
					Transform3D(on.basis * turn * Basis.from_scale(Vector3.ONE * rng.randf_range(1.3, 2.6)), on.origin)])
	var source := (load(MODELS + "reef.glb") as PackedScene).instantiate()
	var looks := {"rock": _reef_material(Color(0.36, 0.34, 0.3), 0.9),
			"staghorn": _reef_material(Color(0.95, 0.5, 0.38), 0.6),
			"brain": _reef_material(Color(0.82, 0.68, 0.34), 0.7),
			"fan": _reef_material(Color(0.62, 0.22, 0.55), 0.6)}
	if variant == DEEP:
		# Basalt, and the deep's fans gone pale, almost white, where the floods find them.
		looks["rock"] = _reef_material(Color(0.13, 0.13, 0.14), 0.85)
		looks["fan"] = _reef_material(Color(0.85, 0.72, 0.62), 0.6)
	var by_kind := {}
	for piece: Array in reef:
		if not by_kind.has(piece[0]):
			by_kind[piece[0]] = []
		by_kind[piece[0]].append(piece[1])
	for kind: String in by_kind:
		var mesh := (source.find_child(kind, true, false) as MeshInstance3D).mesh.duplicate() as ArrayMesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m != null and looks.has(m.resource_name):
				mesh.surface_set_material(i, looks[m.resource_name])
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = mesh
		many.instance_count = by_kind[kind].size()
		for i in by_kind[kind].size():
			many.set_instance_transform(i, by_kind[kind][i])
		var node := MultiMeshInstance3D.new()
		node.name = "Reef" + kind
		node.multimesh = many
		add_child(node)
	source.free()


## Where on the schools' path angle `a` is, `out_by` out from it at height `h`: fish.gdshader's
## path(), for the tests.
static func school_point(a: float, out_by: float, h: float) -> Vector3:
	var c := cos(a)
	var s := sin(a)
	return SCHOOL_CENTRE + Vector3(signf(c) * pow(absf(c), SCHOOL_SQUARE) * (SCHOOL_RADII.x + out_by),
			h + sin(a * 3.0) * 0.35, signf(s) * pow(absf(s), SCHOOL_SQUARE) * (SCHOOL_RADII.y + out_by))


func _reef_material(colour: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.normal_enabled = true
	m.normal_texture = Materials.grain("reef", 0.5, 0.6)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


## Two schools of small fish wheeling round the outside of the vault, one each way round,
## loosely bunched. They swim in fish.gdshader: nothing here moves them.
func _school_the_fish() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	fish_paths.clear()
	for school in [[0.0, 3.4, 0.05, 36], [PI * 0.6, 4.6, -0.042, 28]]:
		for i in school[3]:
			fish_paths.append(Vector4(school[0] + rng.randf_range(-0.05, 0.05), rng.randf_range(-0.4, 0.4),
					school[1] + rng.randf_range(-0.35, 0.35), school[2] * rng.randf_range(0.99, 1.01)))
	var source := (load(MODELS + "reef.glb") as PackedScene).instantiate()
	var mesh := (source.find_child("Fish", true, false) as MeshInstance3D).mesh.duplicate() as ArrayMesh
	source.free()
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://core/venues/shaders/fish.gdshader")
	skin.set_shader_parameter("centre", SCHOOL_CENTRE)
	skin.set_shader_parameter("radii", SCHOOL_RADII)
	skin.set_shader_parameter("square", SCHOOL_SQUARE)
	skin.set_shader_parameter("sweep", SCHOOL_SWEEP)
	mesh.surface_set_material(0, skin)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.mesh = mesh
	many.instance_count = fish_paths.size()
	for i in fish_paths.size():
		var size := rng.randf_range(2.4, 3.2)
		many.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3.ZERO))
		var f := fish_paths[i]
		many.set_instance_custom_data(i, Color(f.x, f.y, f.z, f.w))
	# Where they are is the shader's business, so the box they might be in is given whole.
	many.custom_aabb = AABB(SCHOOL_CENTRE - Vector3(SCHOOL_RADII.x + 1.0, 0.0, SCHOOL_RADII.y + 1.0),
			Vector3(SCHOOL_RADII.x * 2.0 + 2.0, 6.5, SCHOOL_RADII.y * 2.0 + 2.0))
	var node := MultiMeshInstance3D.new()
	node.name = "Fish"
	node.multimesh = many
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Shafts of sunlight slanting down through the water outside, leaning away from the sun.
func _slant_the_shafts() -> void:
	var r := radius()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	shafts.clear()
	var tries := 0
	# Over the wreck: more of them, brighter, and a few falling on her. (Two quads a shaft.)
	var count := 40 if variant == WRECK else 24
	var bright := 1.5 if variant == WRECK else 1.0
	var on_her: Array[Vector2] = []
	if variant == WRECK:
		for along in [-5.0, -1.0, 3.5, 7.0]:
			var at := wreck_at * Vector3(along, 0, 0.5)
			on_her.append(Vector2(at.x, at.z))
	while shafts.size() < count and tries < (300 if variant == WRECK else 200):
		tries += 1
		var p := Vector2(rng.randf_range(-24, 24), rng.randf_range(-28, 18))
		if not on_her.is_empty():
			p = on_her.pop_back()
		var out := absf(p.x) - r if p.y > NOSE else Vector2(p.x, p.y - NOSE).length() - r
		if out < 3.0:
			continue
		var m := ShaderMaterial.new()
		m.shader = preload("res://core/venues/shaders/light_shaft.gdshader")
		m.set_shader_parameter("seed", rng.randf())
		m.set_shader_parameter("strength", rng.randf_range(0.06, 0.13) * bright)
		var height := rng.randf_range(22.0, 30.0)
		var width := rng.randf_range(1.5, 3.5)
		var up := sun_dir().normalized()
		var across := up.cross(Vector3.FORWARD).normalized()
		var through := across.cross(up).normalized()
		for turn in [0, 1]:
			var shaft := MeshInstance3D.new()
			shaft.name = "Shaft"
			shaft.mesh = quad
			shaft.material_override = m
			shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var side := across if turn == 0 else through
			var face := through if turn == 0 else -across
			shaft.transform = Transform3D(Basis(side * width, up * height, face),
					Vector3(p.x, -TRENCH, p.y) + up * height * 0.5)
			add_child(shaft)
			shafts.append(shaft)


## Bubbles: a few streams rising from the sand outside, and from the sub's vent.
func _raise_bubbles() -> void:
	var sub := sub_spot()
	for at in [Vector3(-11.0, -TRENCH, -6.0), Vector3(12.0, -TRENCH, 1.0), Vector3(4.0, -TRENCH, -16.0),
			sub + Vector3(0, 1.0, 1.4)]:
		var stream := GPUParticles3D.new()
		stream.name = "Bubbles"
		stream.amount = 40
		stream.lifetime = 9.0
		stream.preprocess = 9.0
		var motion := ParticleProcessMaterial.new()
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		motion.emission_sphere_radius = 0.15
		motion.gravity = Vector3(0, 0.6, 0)
		motion.direction = Vector3(0, 1, 0)
		motion.spread = 8.0
		motion.initial_velocity_min = 0.4
		motion.initial_velocity_max = 0.8
		motion.turbulence_enabled = true
		motion.turbulence_noise_strength = 0.4
		motion.scale_min = 0.5
		motion.scale_max = 1.5
		stream.process_material = motion
		var ball := SphereMesh.new()
		ball.radius = 0.03
		ball.height = 0.06
		ball.radial_segments = 6
		ball.rings = 3
		var shine := StandardMaterial3D.new()
		shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# In the deep a bubble is only seen where a light catches it: fainter.
		shine.albedo_color = Color(0.6, 0.85, 0.9, 0.1 if variant == DEEP else 0.3)
		ball.material = shine
		stream.draw_pass_1 = ball
		stream.position = at
		stream.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 40, 6))
		add_child(stream)


# --- the wreck ---------------------------------------------------------------------------------

## Whether `p` (studio x, z) is on the wreck or within `margin` of her and her debris.
func _near_the_wreck(p: Vector2, margin: float) -> bool:
	var local := wreck_at.affine_inverse() * Vector3(p.x, -TRENCH, p.y)
	# Her stern's rudder to her bowsprit along x; her fallen mainmast behind her (-z), her deck
	# heeled toward the glass (+z).
	return local.x > -12.5 - margin and local.x < 14.5 + margin and local.z > -11.0 - margin \
			and local.z < 3.2 + margin


## The brig (dome_wreck.glb), lying over in the sand ahead: her planks the weathered boards,
## green with growth; her frames and spars darker and waterlogged; her iron rust. Where the
## coral grows on her is kept for _seed_the_reef.
func _sink_the_wreck() -> void:
	wreck_at = Transform3D(Basis(Vector3.UP, WRECK_YAW), WRECK_AT)
	var planks := Materials.scanned(StandardMaterial3D.new(), "weathered_brown_planks", "2k", 3.0,
			Color(0.78, 0.84, 0.7))
	# Laid along her strakes by the model's own UVs, one plank of the texture to a strake.
	planks.uv1_triplanar = false
	planks.uv1_scale = Vector3.ONE
	planks.cull_mode = BaseMaterial3D.CULL_DISABLED
	var timber := Materials.scanned(StandardMaterial3D.new(), "weathered_brown_planks", "2k", 1.2,
			Color(0.42, 0.45, 0.36))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.24, 0.15, 0.1)
	iron.roughness = 0.9
	iron.normal_enabled = true
	iron.normal_texture = Materials.grain("dome_rust", 1.2, 3.0)
	iron.uv1_triplanar = true
	iron.uv1_scale = Vector3.ONE * 2.0
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.34, 0.33, 0.24)
	rope.roughness = 0.95
	var ship := _model("dome_wreck.glb", WRECK_AT, WRECK_YAW, {"planks": planks, "frame": timber, "iron": iron,
			"rope": rope})
	ship.name = "Wreck"
	wreck_spots.clear()
	for spot: Node3D in ship.find_children("CoralSpot*", "Node3D", true, false):
		wreck_spots.append(_in_model(ship, spot))


## A node's transform in the model it was loaded with, from the model's root.
func _in_model(root: Node3D, node: Node3D) -> Transform3D:
	var at := node.transform
	var up := node.get_parent()
	while up != null and up != root:
		at = (up as Node3D).transform * at
		up = up.get_parent()
	return at


## Two schools round the wreck: a big one wheeling round her standing mast, half way up, and a
## smaller one round the stump of her mainmast. The dome's own fish shader, with the path drawn
## round each mast instead of round the vault.
func _school_round_the_wreck() -> void:
	var ship := get_node("Wreck") as Node3D
	var mast := wreck_at * _in_model(ship, ship.find_child("Mast", true, false) as Node3D)
	var stump := wreck_at * _in_model(ship, ship.find_child("Stump", true, false) as Node3D)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var source := (load(MODELS + "reef.glb") as PackedScene).instantiate()
	var fish_mesh := (source.find_child("Fish", true, false) as MeshInstance3D).mesh
	source.free()
	# (centre, radii, how many, spread of heights, sweep rate, colour, back)
	for school in [[mast.origin + mast.basis.y * 7.5, Vector2(2.6, 2.3), 64, 2.2, 0.11,
				Color(0.98, 0.82, 0.3), Color(0.4, 0.34, 0.12)],
			[stump.origin + Vector3(0, 0.9, 0), Vector2(1.7, 1.5), 22, 0.8, -0.14,
				Color(0.85, 0.9, 0.95), Color(0.2, 0.3, 0.42)]]:
		var centre: Vector3 = school[0]
		var radii: Vector2 = school[1]
		var mesh := fish_mesh.duplicate() as ArrayMesh
		var skin := ShaderMaterial.new()
		skin.shader = preload("res://core/venues/shaders/fish.gdshader")
		skin.set_shader_parameter("centre", centre)
		skin.set_shader_parameter("radii", radii)
		# Round, not squared off: there is no glass to keep clear of out here, and all the way
		# round and back.
		skin.set_shader_parameter("square", 1.0)
		skin.set_shader_parameter("sweep", PI)
		skin.set_shader_parameter("colour", school[5])
		skin.set_shader_parameter("back", school[6])
		mesh.surface_set_material(0, skin)
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.use_custom_data = true
		many.mesh = mesh
		many.instance_count = school[2]
		for i in many.instance_count:
			# Bigger than the dome's: seen from twenty metres they must still read as fish.
			many.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(3.4, 4.4)),
					Vector3.ZERO))
			var spread: float = school[3]
			many.set_instance_custom_data(i, Color(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5),
					rng.randf_range(-spread, spread), float(school[4]) * rng.randf_range(0.97, 1.03)))
		var reach := Vector3(radii.x + 1.5, 0.0, radii.y + 1.5)
		many.custom_aabb = AABB(centre - reach - Vector3(0, school[3] + 1.0, 0),
				reach * 2.0 + Vector3(0, school[3] * 2.0 + 2.0, 0))
		var node := MultiMeshInstance3D.new()
		node.name = "WreckFish"
		node.multimesh = many
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


# --- the deep ----------------------------------------------------------------------------------

## The black smoker (dome_vent.glb) on the floor ahead: its chimneys near black, their throats
## glowing, the tube worms round their feet, its own dull red light on the mound, and smoke
## pouring up out of every chimney into the dark.
func _raise_the_vent() -> void:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.07, 0.065, 0.065)
	rock.roughness = 0.8
	rock.normal_enabled = true
	rock.normal_texture = Materials.grain("dome_sulphide", 1.0, 4.0)
	rock.uv1_triplanar = true
	rock.uv1_scale = Vector3.ONE * 1.5
	var worm := StandardMaterial3D.new()
	worm.albedo_color = Color(0.86, 0.84, 0.78)
	worm.roughness = 0.45
	var plume := StandardMaterial3D.new()
	plume.albedo_color = Color(0.8, 0.07, 0.06)
	plume.roughness = 0.5
	plume.emission_enabled = true
	plume.emission = Color(0.6, 0.04, 0.03)
	plume.emission_energy_multiplier = 0.15
	var vent := _model("dome_vent.glb", VENT_AT, 0.4, {"rock": rock, "glow": ZoneKit.glow(Color(1.0, 0.36, 0.08), 2.6),
			"worm": worm, "plume": plume})
	vent.name = "Vent"
	var heat := OmniLight3D.new()
	heat.name = "VentGlow"
	heat.light_color = Color(1.0, 0.42, 0.15)
	heat.light_energy = 1.6
	heat.omni_range = 7.0
	heat.position = VENT_AT + Vector3(0, 2.2, 0)
	add_child(heat)
	var puff := _soft_spot()
	for mouth: Node3D in vent.find_children("Smoke*", "Node3D", true, false):
		var at := vent.transform * _in_model(vent, mouth).origin
		var smoke := GPUParticles3D.new()
		smoke.name = "Smoke"
		smoke.amount = 48
		smoke.lifetime = 16.0
		smoke.preprocess = 16.0
		var motion := ParticleProcessMaterial.new()
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		motion.emission_sphere_radius = 0.12
		motion.direction = Vector3(0, 1, 0)
		motion.spread = 6.0
		motion.initial_velocity_min = 0.5
		motion.initial_velocity_max = 0.8
		motion.gravity = Vector3(0.03, 0.0, 0.02)
		motion.damping_min = 0.02
		motion.damping_max = 0.04
		motion.turbulence_enabled = true
		motion.turbulence_noise_strength = 0.5
		motion.turbulence_noise_scale = 3.0
		motion.turbulence_influence_min = 0.03
		motion.turbulence_influence_max = 0.08
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.3))
		grow.add_point(Vector2(1.0, 3.0))
		var grow_tex := CurveTexture.new()
		grow_tex.curve = grow
		motion.scale_curve = grow_tex
		var tone := Gradient.new()
		# Hot and lit from below as it leaves the throat, then grey, then gone into the dark.
		tone.set_color(0, Color(0.5, 0.26, 0.12, 0.0))
		tone.set_color(1, Color(0.03, 0.03, 0.035, 0.0))
		tone.add_point(0.05, Color(0.42, 0.22, 0.12, 0.35))
		tone.add_point(0.25, Color(0.1, 0.095, 0.095, 0.4))
		tone.add_point(0.7, Color(0.06, 0.06, 0.065, 0.25))
		var ramp := GradientTexture1D.new()
		ramp.gradient = tone
		motion.color_ramp = ramp
		smoke.process_material = motion
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9, 0.9)
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.vertex_color_use_as_albedo = true
		look.albedo_texture = puff
		quad.material = look
		smoke.draw_pass_1 = quad
		smoke.position = at
		smoke.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 16, 12))
		add_child(smoke)


## A soft round spot, white in the middle and gone at the edge: for smoke, plankton and snow.
func _soft_spot() -> GradientTexture2D:
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
	return spot


## `count` points in the water outside the glass, `out` metres past it at most, between heights
## `low` and `high`, as a texture GPUParticles3D can be told to spawn from: so nothing drifts
## inside the dome.
func _outside(count: int, out: float, low: float, high: float, rng: RandomNumberGenerator) -> ImageTexture:
	var r := radius()
	var image := Image.create(count, 1, false, Image.FORMAT_RGBF)
	var made := 0
	while made < count:
		var p := Vector3(rng.randf_range(-r - out, r + out), rng.randf_range(low, high),
				rng.randf_range(NOSE - r - out, BACK + 4.0))
		# Outside the vault: its half cylinder, its nose, and behind the bulkhead.
		var from_axis := Vector2(p.x, maxf(p.y, 0.0)).length() if p.z > NOSE \
				else Vector3(p.x, maxf(p.y, 0.0), p.z - NOSE).length()
		if from_axis < r + 0.5 and p.z < BACK + 0.6:
			continue
		image.set_pixel(made, 0, Color(p.x, p.y, p.z))
		made += 1
	return ImageTexture.create_from_image(image)


## The jellyfish (dome_jelly.glb), drifting up through the dark round the vault in one MultiMesh,
## lit by their own light (dome_jelly.gdshader): a few close enough to the glass to look into,
## most out in the murk. None in the sub's way.
func _set_the_jellies_adrift() -> void:
	var source := (load(MODELS + "dome_jelly.glb") as PackedScene).instantiate()
	var mesh := ((source.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D).mesh
	source.free()
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://core/venues/shaders/dome_jelly.gdshader")
	glow.set_shader_parameter("strength", 1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var r := radius()
	var sub := sub_spot()
	var spots: Array[Transform3D] = []
	var shades: Array[Color] = []
	var tries := 0
	while spots.size() < 46 and tries < 2000:
		tries += 1
		var near := spots.size() < 10
		var a := rng.randf_range(-PI, PI)
		var away := rng.randf_range(1.0, 3.0) if near else rng.randf_range(3.0, 20.0)
		# Round the vault's axis, or round its nose in front of it.
		var p := Vector2(cos(a) * (r + away), sin(a) * (r + away) * 1.6 - 4.0)
		if p.y > BACK:
			continue
		var out := absf(p.x) - r if p.y > NOSE else Vector2(p.x, p.y - NOSE).length() - r
		if out < 1.0 or Vector2(p.x - sub.x, p.y - sub.z).length() < 3.5:
			continue
		var s := rng.randf_range(0.8, 1.7) if near else rng.randf_range(0.9, 2.2)
		var tilt := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		spots.append(Transform3D(tilt.scaled(Vector3.ONE * s), Vector3(p.x, 4.0, p.y)))
		shades.append(Color(rng.randf(), rng.randf_range(0.06, 0.14), rng.randf_range(11.0, 15.0),
				rng.randf() * (0.35 if rng.randf() < 0.7 else 1.0)))
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.mesh = mesh
	many.instance_count = spots.size()
	for i in spots.size():
		many.set_instance_transform(i, spots[i])
		many.set_instance_custom_data(i, shades[i])
	# Where each is is the shader's business: the whole volume they rise through.
	many.custom_aabb = AABB(Vector3(-40, -12, -45), Vector3(80, 32, 80))
	var node := MultiMeshInstance3D.new()
	node.name = "Jellies"
	node.multimesh = many
	node.material_override = glow
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Marine snow, falling slowly through the water all round the vault, seen where the lights
## catch it; and plankton, sparking blue-green in the dark and going out again.
func _let_the_snow_fall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var spot := _soft_spot()
	for spec in [["Snow", 1600, 26.0, 0.03, 9.0, false], ["Plankton", 700, 4.0, 0.035, 16.0, true]]:
		var count: int = spec[1]
		var drift := GPUParticles3D.new()
		drift.name = spec[0]
		drift.amount = count
		drift.lifetime = spec[2]
		drift.preprocess = spec[2]
		var motion := ParticleProcessMaterial.new()
		motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		motion.emission_point_texture = _outside(count, spec[4], -0.4, 10.0, rng)
		motion.emission_point_count = count
		motion.direction = Vector3(0, -1, 0)
		motion.spread = 40.0
		motion.initial_velocity_min = 0.01
		motion.initial_velocity_max = 0.04
		motion.gravity = Vector3(0, 0.0 if spec[5] else -0.05, 0)
		motion.turbulence_enabled = true
		motion.turbulence_noise_strength = 0.3
		motion.turbulence_influence_min = 0.01
		motion.turbulence_influence_max = 0.03
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * float(spec[3])
		var look := StandardMaterial3D.new()
		look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		look.albedo_texture = spot
		if spec[5]:
			# Plankton: its own light, blinking on and off over its short life.
			var blink := Gradient.new()
			blink.set_color(0, Color(0.3, 1.0, 0.85, 0.0))
			blink.set_color(1, Color(0.2, 0.7, 1.0, 0.0))
			blink.add_point(0.2, Color(0.3, 1.0, 0.85, 1.0))
			blink.add_point(0.45, Color(0.25, 0.9, 1.0, 0.25))
			blink.add_point(0.6, Color(0.25, 0.85, 1.0, 0.9))
			var ramp := GradientTexture1D.new()
			ramp.gradient = blink
			motion.color_ramp = ramp
			look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			look.vertex_color_use_as_albedo = true
			look.albedo_color = Color(2.2, 2.2, 2.2)
		else:
			# Snow: grey flecks, lit by whatever light finds them and otherwise all but unseen.
			look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			look.albedo_color = Color(0.75, 0.78, 0.8, 0.8)
			look.emission_enabled = true
			look.emission = Color(0.6, 0.7, 0.8)
			look.emission_energy_multiplier = 0.025
		look.disable_receive_shadows = true
		quad.material = look
		drift.process_material = motion
		drift.draw_pass_1 = quad
		drift.visibility_aabb = AABB(Vector3(-40, -4, -45), Vector3(80, 20, 80))
		drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drift)


## The dome's floodlights, out on its plinth past the glass: two down each side and three round
## the nose, each a lamp in a dark housing throwing a warm beam out and down across the sand, the
## beam itself hanging in the water. The middle one of the nose's reaches out to the vent.
func _light_the_floods() -> void:
	# Just past the plinth's outer edge, clear of the glass, each on a post from the sand.
	var r := radius() + 0.26
	var housing := _dark()
	var lens := ZoneKit.glow(Color(1.0, 0.92, 0.78), 2.2)
	var warm := Color(1.0, 0.9, 0.76)
	var aims: Array = []
	for spec: Array in FLOODS:
		var side := cos(float(spec[0]))
		var at := Vector3(side * r, 0.2, float(spec[1]))
		aims.append([at, Vector3(side, -0.32, 0.12).normalized(), 30.0, 14.0, 5.0])
	for a: float in NOSE_FLOODS:
		var at := Vector3(cos(a) * r, 0.2, NOSE - sin(a) * r)
		var aim := Vector3(cos(a), -0.3, -sin(a)).normalized()
		if absf(a - PI * 0.5) < 0.01:
			# The one on the vent: long and narrow.
			aim = (VENT_AT + Vector3(0, 2.5, 0) - at).normalized()
			aims.append([at, aim, 13.0, 26.0, 7.0])
		else:
			aims.append([at, aim, 30.0, 14.0, 5.0])
	for spec: Array in aims:
		var at: Vector3 = spec[0]
		var aim: Vector3 = spec[1]
		var turn := Basis.looking_at(aim, Vector3.UP)
		var lamp := ZoneKit.block(self, Vector3(0.34, 0.24, 0.3), at, housing, "FloodHousing")
		lamp.basis = turn
		var face := ZoneKit.block(lamp, Vector3(0.26, 0.17, 0.01), Vector3(0, 0, -0.156), lens, "FloodLens")
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var post := at.y - 0.1 + TRENCH
		ZoneKit.block(self, Vector3(0.07, post, 0.07), Vector3(at.x, -TRENCH + post * 0.5, at.z), housing, "FloodPost")
		var beam := SpotLight3D.new()
		beam.name = "Flood"
		beam.light_color = warm
		beam.light_energy = spec[4]
		beam.spot_angle = spec[2]
		beam.spot_range = spec[3]
		beam.spot_angle_attenuation = 1.4
		beam.shadow_enabled = false
		beam.light_specular = 0.2
		beam.transform = Transform3D(turn, at + aim * 0.2)
		add_child(beam)
		# The beam in the water: two crossed quads down its axis, brightest at the lamp.
		var length: float = spec[3] * 0.8
		var width := 2.0 * tan(deg_to_rad(spec[2])) * length * 0.5
		var m := ShaderMaterial.new()
		m.shader = preload("res://core/venues/shaders/light_shaft.gdshader")
		m.set_shader_parameter("colour", Color(0.9, 0.8, 0.62))
		m.set_shader_parameter("strength", 0.14)
		m.set_shader_parameter("seed", at.x * 0.37 + at.z * 0.11)
		var quad := QuadMesh.new()
		var across := aim.cross(Vector3.UP).normalized()
		var other := aim.cross(across).normalized()
		for side_axis: Vector3 in [across, other]:
			var glow := MeshInstance3D.new()
			glow.name = "FloodBeam"
			glow.mesh = quad
			glow.material_override = m
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var normal := side_axis.cross(-aim).normalized()
			glow.transform = Transform3D(Basis(side_axis * width, -aim * length, normal), at + aim * (length * 0.5 + 0.2))
			add_child(glow)
	# A line of blue light along the plinth's top inside the glass, each side: the deck's edge
	# from outside, and its own small light inside.
	var strip := ZoneKit.glow(Color(0.3, 0.75, 1.0), 1.4)
	for side in [-1.0, 1.0]:
		var line := ZoneKit.block(self, Vector3(0.03, 0.02, BACK - NOSE - 0.2), Vector3(side * (radius() - 0.17), 0.135,
				(NOSE + BACK) * 0.5), strip, "PlinthLight")
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- the zones -------------------------------------------------------------------------------

## The zones: a riser of teak on steel, the booth framed in the sub's yellow (the sub bay), a lit
## square on the deck for the lattice, a teak table on steel, and the keys.
func _dress_zones() -> void:
	var z := zones()
	var steel := _steel()
	var dark := _dark()
	var teak := _ground("wood_floor_deck", "2k", 2.2, Color(0.66, 0.66, 0.64), 2.2, 1.6 * _caustics())

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var riser := Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, riser, ZoneKit.RISER_HEIGHT, teak, steel)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, _paint(), _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.9, 0.75),
			1.3, 60.0, 3.2, dark)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.03, ZoneKit.glow(Color(0.35, 0.9, 0.85), 1.2))

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, teak, steel)
	_dress_prop_shelf(teak, steel)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, Materials.brushed_metal(), dark)


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
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _dark())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Under the sea: coral and sand, kelp and sea glass, the blues of deep water.
func track_palette() -> Array:
	return [
		Color(1.00, 0.44, 0.38), Color(1.00, 0.62, 0.37), Color(0.91, 0.82, 0.48), Color(0.66, 0.83, 0.42),
		Color(0.31, 0.75, 0.54), Color(0.18, 0.78, 0.72), Color(0.25, 0.72, 0.88), Color(0.23, 0.50, 0.85),
		Color(0.42, 0.42, 0.88), Color(0.69, 0.42, 0.82), Color(1.00, 0.50, 0.66), Color(0.78, 0.83, 0.82),
	]
