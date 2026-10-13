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

## Where each kelp stalk stands (studio space), kept for the tests: a headless MultiMesh does not
## keep its instance transforms.
var kelp_spots: Array[Transform3D] = []
var shafts: Array[MeshInstance3D] = []
## The reef: each piece's kind (an object in reef.glb) and where it sits.
var reef: Array = []
## The fish: each one's (start in its sweep, out from the path, height, sweep rate), as
## fish.gdshader reads them.
var fish_paths: Array[Vector4] = []
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


func dress(env: Environment, key: DirectionalLight3D) -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://core/venues/shaders/undersea_sky.gdshader")
	sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
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
	key.basis = Basis.looking_at(-SUN_DIR.normalized(), Vector3.FORWARD)
	key.light_specular = 0.4


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
	floor_mesh.material_override = _ground("wood_floor_deck", "2k", 2.2, Color(0.66, 0.66, 0.64), 2.2, 1.6)
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
	sand.material_override = _ground("coast_sand_01", "1k", 3.0, Color(0.72, 0.8, 0.76), 2.6, 1.3)
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
			place.call(kind, Vector2(side * (half + 0.45 + rng.randf_range(-0.08, 0.08)), z), rng.randf_range(0.7, 1.0))
	# Outside: boulders among the kelp, a few in the clearing ahead.
	for at in [Vector2(-9.5, -12.0), Vector2(6.5, -15.0), Vector2(11.0, -4.0), Vector2(-12.0, 2.0),
			Vector2(-3.5, -17.0), Vector2(13.0, 6.0)]:
		place.call("Rock%d" % (rng.randi() % 3), at, rng.randf_range(2.0, 3.6))
	var source := (load(MODELS + "reef.glb") as PackedScene).instantiate()
	var looks := {"rock": _reef_material(Color(0.36, 0.34, 0.3), 0.9),
			"staghorn": _reef_material(Color(0.95, 0.5, 0.38), 0.6),
			"brain": _reef_material(Color(0.82, 0.68, 0.34), 0.7),
			"fan": _reef_material(Color(0.62, 0.22, 0.55), 0.6)}
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
	while shafts.size() < 24 and tries < 200:
		tries += 1
		var p := Vector2(rng.randf_range(-24, 24), rng.randf_range(-28, 18))
		var out := absf(p.x) - r if p.y > NOSE else Vector2(p.x, p.y - NOSE).length() - r
		if out < 3.0:
			continue
		var m := ShaderMaterial.new()
		m.shader = preload("res://core/venues/shaders/light_shaft.gdshader")
		m.set_shader_parameter("seed", rng.randf())
		m.set_shader_parameter("strength", rng.randf_range(0.06, 0.13))
		var height := rng.randf_range(22.0, 30.0)
		var width := rng.randf_range(1.5, 3.5)
		var up := SUN_DIR.normalized()
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
		shine.albedo_color = Color(0.6, 0.85, 0.9, 0.3)
		ball.material = shine
		stream.draw_pass_1 = ball
		stream.position = at
		stream.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 40, 6))
		add_child(stream)


# --- the zones -------------------------------------------------------------------------------

## The zones: a riser of teak on steel, the booth framed in the sub's yellow (the sub bay), a lit
## square on the deck for the lattice, a teak table on steel, and the keys.
func _dress_zones() -> void:
	var z := zones()
	var steel := _steel()
	var dark := _dark()
	var teak := _ground("wood_floor_deck", "2k", 2.2, Color(0.66, 0.66, 0.64), 2.2, 1.6)

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
