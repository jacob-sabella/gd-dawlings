class_name StudioVenue
extends Venue

## The control room: parquet, plaster, acoustic treatment, a ceiling with downlights in it.
##
## The one venue that is a ROOM, and so the one where global illumination earns its cost: light
## bounces off four walls and a ceiling here, and nowhere else does it have anything to bounce off.

## Ceiling fittings: where, and how bright. Over the desk, the rack's corner and the deck's.
const DOWNLIGHTS: Array = [
	[Vector3(-0.55, 0, -0.35), 3.2],
	[Vector3(0.55, 0, -0.35), 3.2],
	[Vector3(-1.45, 0, -0.85), 2.6],
	[Vector3(1.25, 0, -0.65), 2.6],
	[Vector3(0, 0, 1.4), 1.6],
]
## Acoustic treatment: [centre, size, yaw, cloth]. On the back wall either side of where the
## monitors would be, and first-reflection points on both side walls.
const ACOUSTIC_PANELS: Array = [
	[Vector3(-1.95, 1.45, -2.10), Vector3(1.1, 1.3, 0.09), 0.0, "charcoal"],
	[Vector3(-0.62, 1.55, -2.10), Vector3(0.9, 1.0, 0.09), 0.0, "rust"],
	[Vector3(0.62, 1.55, -2.10), Vector3(0.9, 1.0, 0.09), 0.0, "slate"],
	[Vector3(1.95, 1.45, -2.10), Vector3(1.1, 1.3, 0.09), 0.0, "charcoal"],
	[Vector3(-3.10, 1.40, -0.60), Vector3(1.2, 1.2, 0.09), 90.0, "charcoal"],
	[Vector3(-3.10, 1.40, 1.00), Vector3(1.2, 1.2, 0.09), 90.0, "slate"],
	[Vector3(3.10, 1.40, -0.60), Vector3(1.2, 1.2, 0.09), -90.0, "charcoal"],
	[Vector3(3.10, 1.40, 1.00), Vector3(1.2, 1.2, 0.09), -90.0, "rust"],
]


func venue_id() -> StringName:
	return &"studio"



func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.021, 0.024, 0.030)
	if rich:
		_enrich(env)
		# Indoors, with a ceiling: what comes through is a skylight's worth, not a sun's. The
		# room's light comes from its fittings.
		key.light_energy = 0.35
		key.shadow_blur = 1.5


## Everything forward_plus can do that a control room benefits from.
func _enrich(env: Environment) -> void:
	# Bounce light. The room is lit by four lamps and four ceiling fittings, and without global
	# illumination every surface not directly in front of one was the same flat ambient grey --
	# the underside of the desk, the back of the rack, the floor beside the console all one
	# colour. SDFGI is real-time and needs no bake, which matters for a room whose furniture moves.
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_min_cell_size = 0.04
	env.sdfgi_cascades = 4
	env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_energy = 1.1
	env.sdfgi_read_sky_light = false
	# Ambient comes down hard once bounce exists: it was standing in for GI, and leaving it up
	# lights the room twice.
	env.ambient_light_energy = 0.10

	env.ssil_enabled = true
	env.ssil_radius = 1.2
	env.ssil_intensity = 0.8
	env.ssao_radius = 0.25
	env.ssao_intensity = 1.6
	env.ssao_detail = 0.8

	# Reflections in the lacquer and the floor. A glossy desk that reflects nothing is plastic.
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.12

	# A little air. Enough that the lamps throw a visible cone and the far wall sits back,
	# never enough to haze the desk.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(0.82, 0.84, 0.88)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 9.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08


func _ready() -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	# Under both rooms, the control room and the live room behind it, and no further: past the
	# walls nobody sees it.
	var half := live_room_half() + 0.1
	plane.size = Vector2(half * 2.0, LIVE_ROOM_BACK + 2.4)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (LIVE_ROOM_BACK - 2.2) * 0.5
	# Parquet, oiled and dark. A studio floor is the biggest surface in every wide shot, and a
	# flat grey plane is what announced this as a 3D scene before anything else did.
	var floor_mat := Materials.scanned(StandardMaterial3D.new(), "herringbone_parquet", "2k",
			1.6, Color(0.42, 0.36, 0.32))
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	# Three walls and no ceiling, which is a corner you are standing in rather than a backdrop
	# the gear is parked in front of.
	#
	# This used to be the back wall alone, on the stated grounds that enclosing the room would
	# bounce every light into the lens and make the desk harder to read. That is true of a
	# renderer with global illumination and false of this one: the environment is
	# AMBIENT_SOURCE_COLOR with no SDFGI, no VoxelGI and no SSIL, so ambient is a flat constant
	# applied the same whether a wall is there or not. Adding walls adds exactly zero bounced
	# light. What it adds is the thing a wide shot was missing -- an edge for the room to stop
	# at, instead of a floor fading into black on both sides.
	#
	# The ceiling stays off, and that reason does survive: the key light is a DirectionalLight3D
	# with shadows on, so a ceiling does not soften the room, it switches the key off.
	# Painted plasterboard: flat colour with a roller's worth of texture. A scanned plaster was
	# tried first and read as a cave wall at any strength that showed at all.
	var wall_mat := Materials.painted_wall(Color(0.105, 0.108, 0.115))

	# Narrower than the floor. A control room is a room, not a hangar, and the walls have to be
	# close enough to read as walls from the working position -- at nine metres apart they are
	# two more grey rectangles in the distance.
	for spec in [[Vector3(0, Studio.WALL_HEIGHT * 0.5, -2.2), Vector3(room_width, Studio.WALL_HEIGHT, 0.1)],
			# A hair lower than the back wall, whose ends they overlap: level, the two tops met in
			# one plane at each corner.
			[Vector3(-room_width * 0.5, Studio.WALL_HEIGHT * 0.5 - 0.001, 0.3),
					Vector3(0.1, Studio.WALL_HEIGHT - 0.004, Studio.ROOM_DEPTH)],
			[Vector3(room_width * 0.5, Studio.WALL_HEIGHT * 0.5 - 0.001, 0.3),
					Vector3(0.1, Studio.WALL_HEIGHT - 0.004, Studio.ROOM_DEPTH)]]:
		var wall := MeshInstance3D.new()
		wall.name = "Wall"
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = spec[1]
		wall.mesh = wall_mesh
		wall.position = spec[0]
		wall.material_override = wall_mat
		add_child(wall)

	_dress_room()
	_build_live_room(wall_mat)
	_dress_zones()


## What makes a room a control room rather than a box: a ceiling with light in it, the acoustic
## treatment on the walls, and a rug under the mix position.
##
## The ceiling was left off on purpose while the only light was a shadow-casting sun -- a lid
## switches a sun off. The room is lit from its own fittings now, and an open top is what made
## every wide shot look like a stage set.
func _dress_room() -> void:
	var ceiling := MeshInstance3D.new()
	ceiling.name = "Ceiling"
	var lid := BoxMesh.new()
	# Its ends buried in the back wall and in the live room's front wall, short of their far
	# faces: flush with either, the two would fight along the seam.
	lid.size = Vector3(room_width + 0.1, 0.08, Studio.ROOM_DEPTH + 0.08)
	ceiling.mesh = lid
	ceiling.position = Vector3(0, Studio.WALL_HEIGHT + 0.041, 0.3)
	var lid_mat := Materials.painted_wall(Color(0.075, 0.076, 0.08))
	ceiling.material_override = lid_mat
	# Off the shadow map, so the key still comes through as a skylight would; still in the GI,
	# which is what a ceiling is for -- the light that comes back down off it.
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ceiling)

	# Downlights over the places work happens. Spots, not omnis: a recessed fitting throws a
	# cone, and the pool it leaves on the floor is half of what makes it read as one.
	for spec in DOWNLIGHTS:
		var at: Vector3 = spec[0]
		var fitting := MeshInstance3D.new()
		fitting.name = "Downlight"
		var can := CylinderMesh.new()
		can.top_radius = 0.075
		can.bottom_radius = 0.075
		can.height = 0.012
		can.radial_segments = 24
		fitting.mesh = can
		var spread := SessionLayout.widen(Vector2(at.x, at.z), room_width)
		fitting.position = Vector3(spread.x, Studio.WALL_HEIGHT - 0.005, spread.y)
		fitting.material_override = Materials.brushed_metal()
		add_child(fitting)
		var lens := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.052
		disc.bottom_radius = 0.052
		disc.height = 0.004
		disc.radial_segments = 24
		lens.mesh = disc
		lens.position = Vector3(0, -0.006, 0)
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.93, 0.82) * 3.0
		lens.material_override = glow
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fitting.add_child(lens)

		var spot := SpotLight3D.new()
		spot.name = "DownlightBeam"
		spot.position = Vector3(0, -0.012, 0)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.light_color = Color(1.0, 0.9, 0.78)
		spot.light_energy = spec[1]
		spot.spot_range = 4.2
		spot.spot_angle = 38.0
		spot.spot_angle_attenuation = 0.8
		spot.shadow_enabled = rich
		spot.light_size = 0.09
		spot.shadow_bias = 0.04
		spot.light_volumetric_fog_energy = 1.4
		fitting.add_child(spot)

	# Acoustic panels: fabric over rockwool, framed, standing a few centimetres off the wall.
	# Charcoal with two in the room's warm and cool colours, so the walls have rhythm rather
	# than being one plaster plane from corner to corner.
	var cloth := {
		"charcoal": Color(0.07, 0.07, 0.075),
		"rust": Color(0.22, 0.09, 0.05),
		"slate": Color(0.06, 0.09, 0.13),
	}
	for spec in ACOUSTIC_PANELS:
		var panel := MeshInstance3D.new()
		panel.name = "AcousticPanel"
		var slab := BoxMesh.new()
		slab.size = spec[1]
		panel.mesh = slab
		var p: Vector3 = spec[0]
		# Side-wall panels stay on the side walls; back-wall ones spread with the room.
		var grow := (room_width - SessionLayout.BASE_WIDTH) * 0.5
		panel.position = Vector3(p.x + signf(p.x) * grow * (1.0 if absf(p.x) > 3.0 else 0.6), p.y, p.z)
		panel.rotation_degrees = Vector3(0, spec[2], 0)
		panel.material_override = Materials.cached_scanned("panel_" + spec[3], "rough_linen", "1k",
				0.35, cloth[spec[3]])
		add_child(panel)

	# A rug under the desk and the chair that would be at it: the one soft thing on a hard floor,
	# and what stops the parquet running unbroken under the gear like a showroom.
	var rug := MeshInstance3D.new()
	rug.name = "Rug"
	var mat := BoxMesh.new()
	# Under the desk and the chair, so as wide as the desk is long, with a margin.
	mat.size = Vector3(3.0 + (room_width - SessionLayout.BASE_WIDTH), 0.008, 2.2)
	rug.mesh = mat
	rug.position = Vector3(0, 0.0045, 0.25)
	rug.material_override = Materials.scanned(StandardMaterial3D.new(), "wool_boucle", "1k",
			0.9, Color(0.20, 0.19, 0.19))
	add_child(rug)


## The live room: through the control room's open back, a bigger, taller room for everything
## that is played rather than mixed. The control room's ceiling stops where it does and this
## one goes up to LIVE_ROOM_HEIGHT, so turning round from the desk is stepping out from under a
## low lid into height -- the one change in the studio's section that says "a different room".
func _build_live_room(wall_mat: Material) -> void:
	var half := live_room_half()
	var front := Studio.ROOM_DEPTH * 0.5 + 0.3
	var back := LIVE_ROOM_BACK
	var tall := LIVE_ROOM_HEIGHT
	var depth := back - front
	var cr := room_width * 0.5
	# A warmer, darker plaster than the control room's, so the two rooms are told apart by
	# colour as well as by height.
	var live_wall := Materials.painted_wall(Color(0.10, 0.092, 0.085))
	# The side walls and the front wall a hair shorter than the back wall and each other, top
	# and bottom, the way the control room's are: level, two tops (or two bottoms) meet in one
	# plane at every corner.
	var shy := 0.004
	for spec in [
			# The live room's front wall, either side of the control room's opening...
			[Vector3(-(cr + half) * 0.5, tall * 0.5, front), Vector3(half - cr, tall - shy, 0.1),
					live_wall],
			[Vector3((cr + half) * 0.5, tall * 0.5, front), Vector3(half - cr, tall - shy, 0.1),
					live_wall],
			# ...and the header over it, from the control room's ceiling up to this one's, between
			# them and not overlapping them.
			[Vector3(0, (Studio.WALL_HEIGHT + 0.09 + tall - shy * 3.0) * 0.5, front),
					Vector3(room_width, tall - shy * 3.0 - Studio.WALL_HEIGHT - 0.09, 0.1), wall_mat],
			[Vector3(-half, tall * 0.5, front + depth * 0.5), Vector3(0.1, tall - shy * 2.0, depth),
					live_wall],
			[Vector3(half, tall * 0.5, front + depth * 0.5), Vector3(0.1, tall - shy * 2.0, depth),
					live_wall],
			[Vector3(0, tall * 0.5, back), Vector3(half * 2.0, tall, 0.1), live_wall]]:
		var wall := MeshInstance3D.new()
		wall.name = "LiveRoomWall"
		var box := BoxMesh.new()
		box.size = spec[1]
		wall.mesh = box
		wall.position = spec[0]
		wall.material_override = spec[2]
		add_child(wall)

	var lid := MeshInstance3D.new()
	lid.name = "LiveRoomCeiling"
	var slab := BoxMesh.new()
	slab.size = Vector3(half * 2.0 + 0.1, 0.08, depth + 0.1)
	lid.mesh = slab
	lid.position = Vector3(0, tall + 0.041, front + depth * 0.5)
	lid.material_override = Materials.painted_wall(Color(0.06, 0.058, 0.056))
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lid)

	# A slatted walnut diffuser across the back wall: the live room's signature, and what a
	# wall of plaster that size needs to stop being a blank.
	var walnut := Materials.cached_scanned("mirror_walnut", "black_walnut_veneer_01", "2k", 0.6,
			Color(0.55, 0.45, 0.38))
	var slats := MultiMesh.new()
	slats.transform_format = MultiMesh.TRANSFORM_3D
	var slat := BoxMesh.new()
	slat.size = Vector3(0.045, tall - 0.9, 0.06)
	slats.mesh = slat
	# Every 11 cm across the middle of the wall, clear of the corners where the booth and the
	# keys stand.
	var span := half * 2.0 - 3.2
	slats.instance_count = int(span / 0.11)
	for i in slats.instance_count:
		var x := -span * 0.5 + i * 0.11
		slats.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				Vector3(x, 0.45 + (tall - 0.9) * 0.5, back - 0.09)))
	var diffuser := MultiMeshInstance3D.new()
	diffuser.name = "Diffuser"
	diffuser.multimesh = slats
	diffuser.material_override = walnut
	add_child(diffuser)

	# Two pendants hung down from the high ceiling over the walkway, where you come through the
	# opening: low and warm, so the room is lit from inside it, not from a grid of cans.
	for x in [-1.9, 2.4]:
		var cord := MeshInstance3D.new()
		cord.name = "PendantCord"
		var wire := CylinderMesh.new()
		wire.top_radius = 0.004
		wire.bottom_radius = 0.004
		wire.height = 1.5
		cord.mesh = wire
		# Hung from just under the ceiling's face, not from inside it.
		cord.position = Vector3(x * (half / LIVE_ROOM_HALF), tall - 0.76, front + 0.75)
		cord.material_override = Materials.brushed_metal()
		add_child(cord)
		var shade := MeshInstance3D.new()
		shade.name = "PendantShade"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.17
		cone.height = 0.16
		shade.mesh = cone
		shade.position = cord.position + Vector3(0, -0.82, 0)
		shade.material_override = Materials.brushed_metal()
		add_child(shade)
		var bulb := ZoneKit.block(self, Vector3(0.07, 0.03, 0.07), shade.position + Vector3(0, -0.07, 0),
				ZoneKit.glow(Color(1.0, 0.78, 0.5), 2.2), "Bulb")
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ZoneKit.spot_down(self, shade.position + Vector3(0, -0.09, 0), Color(1.0, 0.8, 0.6), 2.0,
				60.0, 4.2)


## Every activity's place, each lit by its own fitting: a carpeted riser for the kit, a glass
## booth with a stand in it, brass set into the floor where the lattice will stand, an oak
## table, and a keyboard stand under a rack of modules waiting for the synth.
func _dress_zones() -> void:
	var z := zones()
	var walnut := Materials.cached_scanned("mirror_walnut", "black_walnut_veneer_01", "2k", 0.6,
			Color(0.78, 0.68, 0.6))
	var metal := Materials.brushed_metal()
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.47, 0.25)
	brass.metallic = 1.0
	brass.roughness = 0.38

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var carpet := Materials.cached_scanned("riser_carpet", "wool_boucle", "1k", 0.7,
			Color(0.20, 0.07, 0.06))
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2(0.2, 0.2), 0.3,
			carpet, walnut)
	# From the high ceiling, so reaching well past the floor: a spot's light runs out AT its
	# range, and one that only just reaches the floor leaves no pool on it.
	ZoneKit.spot_down(drums, Vector3(0, LIVE_ROOM_HEIGHT - 0.05, 0), Color(1.0, 0.82, 0.62), 4.0,
			40.0, 7.0, metal)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.62, 0.66, 0.12)
	glass.roughness = 0.04
	glass.metallic_specular = 0.8
	# The door faces the room's middle, toward the kit.
	ZoneKit.booth(vocals, booth_box.size, Vector3(1, 0, 0), walnut, glass)
	ZoneKit.block(vocals, Vector3(booth_box.size.x - 0.2, 0.01, booth_box.size.z - 0.2),
			Vector3(0, 0.005, 0), Materials.cached_scanned("booth_felt", "rough_linen", "1k", 0.5,
			Color(0.10, 0.10, 0.12)), "BoothFloor")
	# On the felt, not sunk through it.
	ZoneKit.mic_stand(vocals, Vector3(0, 0.01, 0.25), metal)
	# One warm can in the booth's lid, over the singer.
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.68, 0.42),
			1.4, 60.0, 3.2, metal)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var lattice: AABB = z[&"matrix"]
	# Where the lattice's 3 m base will stand: a cool LED strip let into the floor inside a brass
	# border, and a brass cross at its centre. Nothing to walk into, and in a dark room the one
	# line of light on the floor says "something goes here" from anywhere in it.
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3.ZERO, 0.03, brass)
	ZoneKit.floor_frame(matrix, Vector2(3.0, 3.0), Vector3(0, 0.001, 0), 0.012,
			ZoneKit.glow(Color(0.55, 0.72, 1.0), 0.9))
	ZoneKit.block(matrix, Vector3(0.4, 0.004, 0.03), Vector3(0, 0.003, 0), brass, "Cross")
	ZoneKit.block(matrix, Vector3(0.03, 0.004, 0.4), Vector3(0, 0.004, 0), brass, "Cross")
	ZoneKit.spot_down(matrix, Vector3(0, LIVE_ROOM_HEIGHT - 0.05, 0), Color(0.72, 0.82, 1.0), 3.2,
			36.0, LIVE_ROOM_HEIGHT * 1.7, metal)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, Vector3(1.0, 0.05, 2.0), 0.92, 0.06, walnut, metal)
	ZoneKit.spot_down(bricks, Vector3(0, 2.4, 0), Color(1.0, 0.8, 0.6), 2.4, 50.0, 4.0)
	var pendant := MeshInstance3D.new()
	var shade := CylinderMesh.new()
	shade.top_radius = 0.18
	shade.bottom_radius = 0.18
	shade.height = 0.03
	pendant.mesh = shade
	pendant.position = Vector3(0, 2.42, 0)
	pendant.material_override = ZoneKit.glow(Color(1.0, 0.8, 0.55), 1.4)
	pendant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bricks.add_child(pendant)
	var drop := LIVE_ROOM_HEIGHT - 0.01 - 2.435
	var cord := MeshInstance3D.new()
	cord.name = "PendantCord"
	var wire := CylinderMesh.new()
	wire.top_radius = 0.004
	wire.bottom_radius = 0.004
	wire.height = drop
	cord.mesh = wire
	cord.position = Vector3(0, 2.435 + drop * 0.5, 0)
	cord.material_override = metal
	bricks.add_child(cord)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	var keys: AABB = z[&"synth"]
	ZoneKit.keyboard_stand(synth, 1.5, metal, walnut)
	# The modules' rack on the wall above the stand: a dark case, and rows of jack-sized lights
	# that are what a rack wall looks like across a dark room.
	var wall_x := keys.size.x * 0.5 - 0.06
	ZoneKit.block(synth, Vector3(0.1, 0.62, 1.5), Vector3(wall_x, 1.6, 0), Materials.chassis(),
			"ModuleCase")
	var dots := MultiMesh.new()
	dots.transform_format = MultiMesh.TRANSFORM_3D
	dots.use_colors = true
	var dot := BoxMesh.new()
	dot.size = Vector3(0.01, 0.012, 0.012)
	dots.mesh = dot
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	dots.instance_count = 3 * 24
	for i in dots.instance_count:
		var row := i / 24
		var col := i % 24
		dots.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				Vector3(wall_x - 0.055, 1.42 + row * 0.18, -0.66 + col * 0.0575)))
		var lit := rng.randf() < 0.45
		dots.set_instance_color(i, (Color(1.0, 0.35, 0.15) if rng.randf() < 0.5
				else Color(0.3, 0.9, 1.0)) * (2.0 if lit else 0.08))
	var leds := MultiMeshInstance3D.new()
	leds.name = "ModuleLights"
	leds.multimesh = dots
	var led_mat := StandardMaterial3D.new()
	led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led_mat.vertex_color_use_as_albedo = true
	leds.material_override = led_mat
	leds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	synth.add_child(leds)
	ZoneKit.spot_down(synth, Vector3(-0.2, LIVE_ROOM_HEIGHT - 0.05, 0), Color(1.0, 0.82, 0.66), 2.6,
			40.0, 6.0, metal)


## A tall walnut floor mirror, leant against the left wall the way one is in every live room:
## top a few centimetres off the plaster, a backboard, and two feet on the parquet.
func mirror_spot(glass: Vector2) -> Transform3D:
	var lean := 0.06
	var wall := -room_width * 0.5 + 0.05
	var centre_y := 0.16 + glass.y * 0.5 * cos(lean)
	# Bottom edge stood 13cm off the wall, the top leaning in by the lean.
	var x := wall + 0.13 - glass.y * 0.5 * sin(lean)
	return Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -lean),
			Vector3(x, centre_y, 2.2))


func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = Materials.cached_scanned("mirror_walnut", "black_walnut_veneer_01", "2k",
			0.6, Color(0.78, 0.68, 0.6))
	# Light wood: the lettering is burnt in, dark, and the arrows are brass.
	board.ink = Color(0.12, 0.07, 0.04)
	board.board_ink_fade = Color(0.45, 0.32, 0.22)
	board.accent = Color(0.95, 0.72, 0.38)


func _frame_mirror(mirror: Mirror) -> void:
	var walnut := Materials.cached_scanned("mirror_walnut", "black_walnut_veneer_01", "2k", 0.6,
			Color(0.78, 0.68, 0.6))
	Venue.frame_bars(mirror, 0.065, 0.045, 0.012, walnut)
	var back := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(mirror.glass_size.x + 0.1, mirror.glass_size.y + 0.1, 0.012)
	back.mesh = board
	back.material_override = walnut
	back.position = Vector3(0, 0, -0.03)
	mirror.add_child(back)
	# A thin brass fillet inside the wood, which is what makes a frame a frame and not a box.
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.6, 0.32)
	brass.metallic = 1.0
	brass.roughness = 0.32
	# Lapped 2mm over the glass, so its inner face is never in the wood's plane.
	Venue.frame_bars(mirror, 0.01, 0.02, 0.016, brass, 0.002)
