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

## The second arrangement (Venue.VARIANTS): the kit and the booth in a room of their own off the
## control room's left side, seen through a window over the riser -- the way a real studio has
## its live room -- and the lattice, the table and the keys in a narrower room behind.
const BESIDE := 1
## How far the side room runs out past the control room's left wall.
const SIDE_ROOM_WIDTH := 6.0
## Along the dividing wall, in z: window from the back wall to WINDOW_TO, a door to DOOR_TO, and
## plaster from there to the opening, where the mirror leans. The window is over the riser, so
## from the desk you see the drummer.
const WINDOW_TO := 0.4
const DOOR_TO := 1.3
## The window's sill and head, and the door's head.
const SILL := 0.95
const HEAD := 2.15
## A door jamb's depth along the wall.
const JAMB := 0.04
## The kit by the window and the booth in the far corner, at the base width; the rest of the
## side room, along its +z side, is the way from the door to both.
const SIDE_ZONES := {
	&"drums": AABB(Vector3(-6.6, 0.0, -2.0), Vector3(2.6, 2.8, 2.6)),
	&"vocals": AABB(Vector3(-9.0, 0.0, -2.0), Vector3(2.2, 2.4, 2.2)),
}

## The third arrangement: the classic tracking studio. The control room's back is closed by a
## thick wall with a big double-glazed window in it and a heavy door beside it, and the live room
## behind -- all five zones where the first arrangement has them -- is a room of its own, seen
## through the glass.
const THROUGH_GLASS := 2
## The wall's control-room face (2 mm into the footprint, so it never lies in the plane of the
## live room's front wall either side) and its live-room face: 40 cm of stud, mass and air gap.
const GLASS_WALL_FRONT := Studio.ROOM_BACK - 0.052
const GLASS_WALL_BACK := Studio.ROOM_BACK + 0.35
## The window's sill and head, the door's head, and how far each pane of the inner glass leans.
const GLASS_SILL := 0.85
const GLASS_HEAD := 2.35
const GLASS_DOOR_HEAD := 2.12
const GLASS_TILT := deg_to_rad(7.0)
## The door, its clear width inside its jambs, in from the right-hand wall; the window runs from
## a metre in from the left wall to a pier short of the door.
const GLASS_DOOR_WIDTH := 0.95
const GLASS_DOOR_JAMB := 0.035


func venue_id() -> StringName:
	return &"studio"


## The ceiling's own downlights, dark or back at what they were built with (the meta `_dress_room`
## stamps on each as it sets `light_energy`) -- the studio's half of `power_flicker`'s strike,
## on top of the practicals every venue dims (scenes/studio.gd's `_lights_out`).
func blackout(on: bool) -> void:
	for spot in find_children("DownlightBeam", "SpotLight3D", true, false):
		spot.light_energy = 0.0 if on else float(spot.get_meta("authored_energy", spot.light_energy))


func zones() -> Dictionary:
	var out := super()
	if variant == BESIDE:
		for id in SIDE_ZONES:
			var box: AABB = SIDE_ZONES[id]
			out[id] = AABB(box.position - Vector3(_grow(), 0, 0), box.size)
	return out


## Beside: the back room starts at the control room's left wall, and the side room meets the
## control room along the whole of that wall -- a doorway to the walker, closed again but for
## the door by the wall's own solids (zone_solids).
func rooms() -> Array[Rect2]:
	if variant != BESIDE:
		return super()
	var cr := room_width * 0.5
	var behind := back_of_house()
	var left := -cr + 0.05
	return [Rect2(left, behind.position.y, behind.end.x - left, behind.size.y),
			Rect2(-cr - SIDE_ROOM_WIDTH + 0.05, Studio.ROOM_FRONT + 0.05, SIDE_ROOM_WIDTH,
					Studio.ROOM_DEPTH - 0.05)]


## Beside: the room behind is no wider than the control room on the left, so the shelf stands
## against that wall instead, in the corner the booth and the riser left for the side room.
func prop_shelf_spot() -> Transform3D:
	var spot := super()
	if variant == BESIDE:
		spot.origin.x = -room_width * 0.5 + 0.05 + 0.08 + ZoneKit.SHELF.z * 0.5
	return spot


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
	var right := live_room_half() + 0.1
	var left := -room_width * 0.5 - SIDE_ROOM_WIDTH - 0.1 if variant == BESIDE else -right
	plane.size = Vector2(right - left, LIVE_ROOM_BACK - Studio.ROOM_FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3((left + right) * 0.5, 0, (LIVE_ROOM_BACK + Studio.ROOM_FRONT) * 0.5)
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
	var walls := [[Vector3(0, Studio.WALL_HEIGHT * 0.5, Studio.ROOM_FRONT), Vector3(room_width, Studio.WALL_HEIGHT, 0.1)],
			# A hair lower than the back wall, whose ends they overlap: level, the two tops met in
			# one plane at each corner.
			[Vector3(room_width * 0.5, Studio.WALL_HEIGHT * 0.5 - 0.001, Studio.ROOM_MID),
					Vector3(0.1, Studio.WALL_HEIGHT - 0.004, Studio.ROOM_DEPTH)]]
	# Beside, the left wall is the window into the side room, built with it.
	if variant != BESIDE:
		walls.append([Vector3(-room_width * 0.5, Studio.WALL_HEIGHT * 0.5 - 0.001, Studio.ROOM_MID),
				Vector3(0.1, Studio.WALL_HEIGHT - 0.004, Studio.ROOM_DEPTH)])
	for spec in walls:
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
	if variant == BESIDE:
		_build_side_room(wall_mat)
	elif variant == THROUGH_GLASS:
		_build_glass_wall(wall_mat)
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
	ceiling.position = Vector3(0, Studio.WALL_HEIGHT + 0.041, Studio.ROOM_MID)
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
		# Drawn under a 2.8 m ceiling: higher up, as far again past the floor and as bright on it.
		var up := Studio.WALL_HEIGHT / 2.8
		spot.light_energy = spec[1] * up * up
		# Stamped at the energy it was actually built with, for `blackout` to restore to --
		# never a literal, since a venue grows and dims lamps with its ceiling height (`up`).
		spot.set_meta("authored_energy", spot.light_energy)
		spot.spot_range = 4.2 * up
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
	for spec in ACOUSTIC_PANELS:
		# Not on a window.
		if variant == BESIDE and (spec[0] as Vector3).x < -3.0:
			continue
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
		panel.material_override = _cloth(spec[3])
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
##
## Beside, the kit and the booth have a room of their own, and this one starts at the control
## room's left wall.
func _build_live_room(wall_mat: Material) -> void:
	var front := Studio.ROOM_BACK
	var back := LIVE_ROOM_BACK
	var tall := LIVE_ROOM_HEIGHT
	var depth := back - front
	var cr := room_width * 0.5
	var right := live_room_half()
	var left := -cr if variant == BESIDE else -right
	var mid := (left + right) * 0.5
	# How far the room's furnishings spread from its middle, against the room they were placed in.
	var spread := (right - left) * 0.5 / LIVE_ROOM_HALF
	# Beside, the left wall stands on the line of the dividing wall, which is thicker: a little
	# thicker again and a little further out, so the two never share a face.
	var left_wall := [Vector3(left - 0.005, tall * 0.5, front + depth * 0.5), Vector3(0.12, tall - 0.008, depth)] \
			if variant == BESIDE else [Vector3(left, tall * 0.5, front + depth * 0.5), Vector3(0.1, tall - 0.008, depth)]
	# A warmer, darker plaster than the control room's, so the two rooms are told apart by
	# colour as well as by height.
	var live_wall := Materials.painted_wall(Color(0.10, 0.092, 0.085))
	# The side walls and the front wall a hair shorter than the back wall and each other, top
	# and bottom, the way the control room's are: level, two tops (or two bottoms) meet in one
	# plane at every corner.
	var shy := 0.004
	var specs := [
			# The live room's front wall, beside the control room's opening...
			[Vector3((cr + right) * 0.5, tall * 0.5, front), Vector3(right - cr, tall - shy, 0.1),
					live_wall],
			# ...and the header over it, from the control room's ceiling up to this one's, between
			# them and not overlapping them.
			[Vector3(0, (Studio.WALL_HEIGHT + 0.09 + tall - shy * 3.0) * 0.5, front),
					Vector3(room_width, tall - shy * 3.0 - Studio.WALL_HEIGHT - 0.09, 0.1), wall_mat],
			[left_wall[0], left_wall[1], live_wall],
			[Vector3(right, tall * 0.5, front + depth * 0.5), Vector3(0.1, tall - shy * 2.0, depth),
					live_wall],
			[Vector3(mid, tall * 0.5, back), Vector3(right - left, tall, 0.1), live_wall]]
	# Through the glass, the wall between the rooms runs floor to this ceiling: no header.
	if variant == THROUGH_GLASS:
		specs.remove_at(1)
	if -cr - left > 0.01:
		specs.append([Vector3((left - cr) * 0.5, tall * 0.5, front), Vector3(-cr - left, tall - shy, 0.1),
				live_wall])
	for spec in specs:
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
	slab.size = Vector3(right - left + 0.1, 0.08, depth + 0.1)
	lid.mesh = slab
	lid.position = Vector3(mid, tall + 0.041, front + depth * 0.5)
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
	var span := right - left - 3.2
	slats.instance_count = int(span / 0.11)
	for i in slats.instance_count:
		var x := mid - span * 0.5 + i * 0.11
		slats.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				Vector3(x, 0.45 + (tall - 0.9) * 0.5, back - 0.09)))
	var diffuser := MultiMeshInstance3D.new()
	diffuser.name = "Diffuser"
	diffuser.multimesh = slats
	diffuser.material_override = walnut
	add_child(diffuser)

	var brass := _sconce_brass()
	var inside := 0.065 if variant == BESIDE else 0.05
	_hang_sconce(0, Vector3(left + inside, 2.1, 3.7), Vector3(1, 0, 0), brass)
	_hang_sconce(1, Vector3(right - 0.05, 2.1, 3.7), Vector3(-1, 0, 0), brass)
	# On the slats' faces, which stand 12 cm proud of the back wall.
	_hang_sconce(2, Vector3(mid - 2.4 * spread, 2.3, LIVE_ROOM_BACK - 0.121), Vector3(0, 0, -1), brass)
	_hang_sconce(3, Vector3(mid + 2.4 * spread, 2.3, LIVE_ROOM_BACK - 0.121), Vector3(0, 0, -1), brass)

	# Two pendants hung down from the high ceiling over the walkway, where you come through the
	# opening: low and warm, so the room is lit from inside it, not from a grid of cans.
	for x in [-1.9, 2.4]:
		_hang_pendant(Vector3(mid + x * spread, 0, front + 0.75))


## A pendant on a cord from the high ceiling, low and warm, at `at` on the floor plan.
func _hang_pendant(at: Vector3) -> void:
	var tall := LIVE_ROOM_HEIGHT
	var cord := MeshInstance3D.new()
	cord.name = "PendantCord"
	var wire := CylinderMesh.new()
	wire.top_radius = 0.004
	wire.bottom_radius = 0.004
	wire.height = 1.5
	cord.mesh = wire
	# Hung from just under the ceiling's face, not from inside it.
	cord.position = Vector3(at.x, tall - 0.76, at.z)
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


## Beside: the room the kit and the booth stand in, off the control room's left side, and the
## wall between the two -- a window over the riser, a door, and plaster where the mirror leans.
## As tall as the live room behind, and the same warm plaster.
func _build_side_room(wall_mat: Material) -> void:
	var cr := room_width * 0.5
	var tall := LIVE_ROOM_HEIGHT
	var far := -cr - SIDE_ROOM_WIDTH
	# The dividing wall's far face: it is 12 cm thick, thicker than any wall it meets.
	var near := -cr - 0.06
	var z0 := Studio.ROOM_FRONT
	var z1 := Studio.ROOM_BACK
	var mid_z := (z0 + z1) * 0.5
	# Lighter than the live room behind, which is lit from more fittings: this one's walls are
	# what its three sconces have to show, and at the back room's near-black they showed nothing.
	var live_wall := Materials.painted_wall(Color(0.19, 0.17, 0.15))
	var walnut := Materials.cached_scanned("mirror_walnut", "black_walnut_veneer_01", "2k", 0.6,
			Color(0.55, 0.45, 0.38))
	var shy := 0.004
	var specs := [
		# The far wall, and the two ends, a hair shorter top and bottom than it as everywhere.
		["SideRoomWall", Vector3(far, tall * 0.5, mid_z), Vector3(0.1, tall - shy * 2.0, z1 - z0 + 0.1), live_wall],
		["SideRoomWall", Vector3((far + near) * 0.5, tall * 0.5, z0), Vector3(near - far, tall - shy, 0.12), live_wall],
		["SideRoomWall", Vector3((far + near) * 0.5, tall * 0.5, z1), Vector3(near - far, tall - shy, 0.12), live_wall],
		# The dividing wall: a sill under the window...
		# Its foot a millimetre up: the control room's back wall runs into its end, and the two
		# bottoms would otherwise share the floor's plane there.
		["Sill", Vector3(-cr, (SILL + 0.001) * 0.5, (z0 + WINDOW_TO) * 0.5), Vector3(0.1, SILL - 0.001, WINDOW_TO - z0),
				wall_mat],
		# ...plaster from the door to the opening...
		["DividingWall", Vector3(-cr, HEAD * 0.5, (DOOR_TO + z1) * 0.5), Vector3(0.1, HEAD, z1 - DOOR_TO), wall_mat],
		# ...and over all of it, up to the side room's ceiling, the transom. Thicker than the
		# control room's ceiling is long, so the ceiling's end is buried in it.
		# Its top shy of the header's over the opening, which runs into it.
		["Transom", Vector3(-cr, (HEAD + tall - shy * 2.5) * 0.5, mid_z), Vector3(0.12, tall - shy * 2.5 - HEAD, z1 - z0),
				wall_mat],
	]
	for spec in specs:
		ZoneKit.block(self, spec[2], spec[1], spec[3], spec[0])

	var pane := ZoneKit.block(self, Vector3(0.02, HEAD - SILL, WINDOW_TO - z0),
			Vector3(-cr, (SILL + HEAD) * 0.5, (z0 + WINDOW_TO) * 0.5), _glass(), "Window")
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Walnut mullions: one at each end, set in from the pane's edges so no face lies on the
	# pane's, and three between. Shy of sill and head, so their ends are not in the pane's plane.
	var posts := 5
	for i in posts:
		var z := lerpf(z0 + 0.05, WINDOW_TO - 0.05, float(i) / (posts - 1))
		ZoneKit.block(self, Vector3(0.08, HEAD - SILL - 0.004, 0.06), Vector3(-cr, (SILL + HEAD) * 0.5, z),
				walnut, "Mullion%d" % i)
	# The door's jambs, walnut, a little thinner than the wall so their sides are not its sides.
	for z in [WINDOW_TO + JAMB * 0.5, DOOR_TO - JAMB * 0.5]:
		ZoneKit.block(self, Vector3(0.11, HEAD - 0.002, JAMB), Vector3(-cr, (HEAD - 0.002) * 0.5, z),
				walnut, "Jamb")

	var lid := MeshInstance3D.new()
	lid.name = "SideRoomCeiling"
	var slab := BoxMesh.new()
	slab.size = Vector3(near - far + 0.05, 0.08, z1 - z0 + 0.12)
	lid.mesh = slab
	lid.position = Vector3((far - 0.05 + near) * 0.5, tall + 0.041, mid_z)
	lid.material_override = Materials.painted_wall(Color(0.06, 0.058, 0.056))
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lid)

	_treat_side_room(far, near, z0, z1)
	_hang_patch_wall(Vector3((far + near) * 0.5, 3.75, z1 - 0.1))

	# Fill from two sconces: on the far wall past the walkway, and on the walkway's wall between
	# the door and the booth.
	var brass := _sconce_brass()
	# Brighter than the back room's, and further: these walls are all treatment, and fabric
	# drinks light that plaster would throw back.
	_hang_sconce(4, Vector3(far + 0.05, 2.1, 1.6), Vector3(1, 0, 0), brass, 4.0, 4.6)
	_hang_sconce(5, Vector3(far + 1.6, 2.1, z0 + 0.06), Vector3(0, 0, 1), brass, 4.0, 4.6)
	# And one on the back wall in the gap between the booth and the riser, washing both.
	var booth: AABB = zones()[&"vocals"]
	var kit: AABB = zones()[&"drums"]
	_hang_sconce(6, Vector3((booth.end.x + kit.position.x) * 0.5, 2.3, z0 + 0.06), Vector3(0, 0, 1), brass,
			4.0, 4.6)
	# Over the way from the door to both, as the live room behind has over its own.
	_hang_pendant(Vector3((far + near) * 0.5, 0, (kit.end.z + z1) * 0.5))


## The audio devices' patch wall, hung on the side room's back wall facing into the room, its top
## at `top`: the Carla picture of the machine's own sound cards and streams, big enough to read
## from the door. The room's one screen; the side room is where the sound gear's wiring lives.
func _hang_patch_wall(top: Vector3) -> void:
	var wall := PatchWallSurface.new()
	wall.name = "PatchWall"
	wall.position = top
	wall.rotation.y = PI
	# A suite or a render has no sound cards to ask about, and a thread per frame is no help there.
	wall.follow = DisplayServer.get_name() != "headless"
	add_child(wall)


## Through the glass: where the wall's openings are across the room, as [window's left edge,
## window's right edge, door opening's left edge, door opening's right edge]. The door a little in
## from the right-hand wall, so it opens onto the walk in front of the lattice, clear of the table
## and the hoop; the window from a metre in from the left wall to a pier short of the door, so
## from the desk the riser, the lattice and the booth's corner are all behind glass.
func glass_openings() -> PackedFloat32Array:
	var cr := room_width * 0.5
	var dx1 := cr - 0.6
	var dx0 := dx1 - GLASS_DOOR_WIDTH
	return PackedFloat32Array([-cr + 1.0, dx0 - 0.55, dx0, dx1])


## Through the glass: the wall that closes the control room's back. Two skins -- the control
## room's grey plaster on its face, the live room's warmer one behind -- with a walnut-cased
## window in it, double glazed, the inner pane leaning back off true so neither room's light
## bounces straight back at it, and a heavy walnut door, standing open into the live room.
func _build_glass_wall(wall_mat: Material) -> void:
	var cr := room_width * 0.5
	var tall := LIVE_ROOM_HEIGHT
	var at := glass_openings()
	var wx0 := at[0]
	var wx1 := at[1]
	var dx0 := at[2]
	var dx1 := at[3]
	var live_wall := Materials.painted_wall(Color(0.10, 0.092, 0.085))
	var walnut := Materials.cached_scanned("mirror_walnut", "black_walnut_veneer_01", "2k", 0.6,
			Color(0.55, 0.45, 0.38))
	var z0 := GLASS_WALL_FRONT
	var z1 := GLASS_WALL_BACK
	# Piers run full height; the pieces over and under the openings are 2 mm shy of them on every
	# face they share a direction with, so no two faces lie in one plane. Each piece is two skins
	# meeting back to back (the split itself a hair apart between piers and the rest).
	var piece := func(x0: float, x1: float, y0: float, y1: float, shy: float, label: String) -> void:
		var split := (z0 + z1) * 0.5 + shy
		ZoneKit.block(self, Vector3(x1 - x0, y1 - y0, split - (z0 + shy)),
				Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + shy + split) * 0.5), wall_mat, label)
		ZoneKit.block(self, Vector3(x1 - x0, y1 - y0, (z1 - shy) - split),
				Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (split + z1 - shy) * 0.5), live_wall, label)
	var top := tall - 0.012
	piece.call(-cr - 0.04, wx0, 0.003, top, 0.0, "GlassWallPier")
	piece.call(wx1, dx0, 0.003, top, 0.0, "GlassWallPier")
	piece.call(dx1, cr + 0.04, 0.003, top, 0.0, "GlassWallPier")
	piece.call(wx0, wx1, 0.005, GLASS_SILL, 0.002, "GlassWallSill")
	piece.call(wx0, wx1, GLASS_HEAD, top - 0.003, 0.002, "GlassWallHead")
	piece.call(dx0, dx1, GLASS_DOOR_HEAD, top - 0.003, 0.002, "GlassWallHead")

	# The window's walnut casing: a deep sill board and a head board through the wall's whole
	# depth and two centimetres proud of both faces, cheeks between them, and posts dividing it
	# into bays no wider than a pane of that size is made.
	var depth := z1 - z0
	var mid_z := (z0 + z1) * 0.5
	var width := wx1 - wx0
	# Their ends run 15 mm into the piers, past the cheeks' backs, so no end lies in a pier's face.
	ZoneKit.block(self, Vector3(width + 0.03, 0.04, depth + 0.04), Vector3((wx0 + wx1) * 0.5, GLASS_SILL + 0.01, mid_z),
			walnut, "WindowSill")
	ZoneKit.block(self, Vector3(width + 0.03, 0.04, depth + 0.04), Vector3((wx0 + wx1) * 0.5, GLASS_HEAD - 0.01, mid_z),
			walnut, "WindowHead")
	var clear_lo := GLASS_SILL + 0.03
	var clear_hi := GLASS_HEAD - 0.03
	var clear_h := clear_hi - clear_lo
	for x in [wx0 + 0.01, wx1 - 0.01]:
		ZoneKit.block(self, Vector3(0.04, clear_h - 0.002, depth + 0.036), Vector3(x, (clear_lo + clear_hi) * 0.5, mid_z),
				walnut, "WindowCheek")
	var bays := maxi(2, ceili((width - 0.06) / 2.6))
	var bay := (width - 0.06) / bays
	var post := 0.07
	for i in range(1, bays):
		ZoneKit.block(self, Vector3(post, clear_h - 0.004, depth + 0.03),
				Vector3(wx0 + 0.03 + bay * i, (clear_lo + clear_hi) * 0.5, mid_z), walnut, "WindowPost")
	var glass := _glass()
	for i in bays:
		var left := wx0 + 0.03 + bay * i + (post * 0.5 if i > 0 else 0.0)
		var right := wx0 + 0.03 + bay * (i + 1) - (post * 0.5 if i < bays - 1 else 0.0)
		var pane_w := right - left - 0.004
		var cx := (left + right) * 0.5
		# The live room's pane, upright, near its face...
		var outer := ZoneKit.block(self, Vector3(pane_w, clear_h - 0.004, 0.012),
				Vector3(cx, (clear_lo + clear_hi) * 0.5, z1 - 0.07), glass, "WindowPane")
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# ...and the control room's, its head leaning toward the desk: the gap between them wide
		# at the sill and narrow at the head, as real control-room glass is set.
		var inner := ZoneKit.block(self, Vector3(pane_w, (clear_h - 0.006) / cos(GLASS_TILT), 0.012),
				Vector3(cx, (clear_lo + clear_hi) * 0.5, z0 + 0.15), glass, "WindowPaneInner")
		inner.rotation.x = -GLASS_TILT
		inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# The door's casing: jambs and a head through the wall's depth, proud of both faces.
	for x in [dx0 + GLASS_DOOR_JAMB * 0.5 - 0.005, dx1 - GLASS_DOOR_JAMB * 0.5 + 0.005]:
		ZoneKit.block(self, Vector3(GLASS_DOOR_JAMB + 0.01, GLASS_DOOR_HEAD - 0.002, depth + 0.04),
				Vector3(x, (GLASS_DOOR_HEAD - 0.002) * 0.5 + 0.001, mid_z), walnut, "DoorJamb")
	ZoneKit.block(self, Vector3(dx1 - dx0 - GLASS_DOOR_JAMB * 2.0 + 0.02, 0.04, depth + 0.036),
			Vector3((dx0 + dx1) * 0.5, GLASS_DOOR_HEAD - 0.01, mid_z), walnut, "DoorHead")
	_hang_studio_door(dx1 - GLASS_DOOR_JAMB, z1, walnut)
	# A sconce on the live room's face of it, on the pier past the window, so the wall the players
	# look at is a wall and not a black edge round the glass.
	_hang_sconce(4, Vector3((-cr + wx0) * 0.5, 2.1, z1), Vector3(0, 0, 1), _sconce_brass())

	# The on-air light over the door, on both faces: red, unlit until a take -- here always lit,
	# because the room is always ready.
	for side in [-1.0, 1.0]:
		# Its back a millimetre off the plaster.
		var face_z := z0 - 0.031 if side < 0.0 else z1 + 0.031
		var sign_node := Node3D.new()
		sign_node.name = "OnAir"
		sign_node.position = Vector3((dx0 + dx1) * 0.5, GLASS_DOOR_HEAD + 0.27, face_z)
		sign_node.rotation.y = PI if side < 0.0 else 0.0
		add_child(sign_node)
		ZoneKit.block(sign_node, Vector3(0.46, 0.15, 0.05), Vector3(0, 0, -0.005), Materials.chassis(), "OnAirBox")
		var lens := ZoneKit.block(sign_node, Vector3(0.40, 0.10, 0.004), Vector3(0, 0, 0.022),
				ZoneKit.glow(Color(1.0, 0.12, 0.08), 1.6), "OnAirLens")
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var words := Label3D.new()
		words.name = "OnAirWords"
		words.text = "ON AIR"
		words.font_size = 48
		words.pixel_size = 0.0013
		words.outline_size = 0
		words.modulate = Color(1.0, 0.92, 0.85)
		words.position = Vector3(0, 0, 0.0255)
		words.shaded = false
		sign_node.add_child(words)

	# Treatment on the control room's face of it: a panel on the pier left of the window, clear of
	# the mirror, and a slatted walnut fascia over the glass, as the live room's back wall has.
	var pier_mid := (-cr + wx0) * 0.5 + 0.1
	ZoneKit.block(self, Vector3(0.6, 1.3, 0.09), Vector3(pier_mid, 1.55, z0 - 0.045), _cloth("rust"),
			"GlassWallPanel")
	ZoneKit.block(self, Vector3(0.45, 1.3, 0.09), Vector3((wx1 + dx0) * 0.5, 1.55, z0 - 0.046), _cloth("slate"),
			"GlassWallPanel")
	var slats := MultiMesh.new()
	slats.transform_format = MultiMesh.TRANSFORM_3D
	var slat := BoxMesh.new()
	var fascia := Studio.WALL_HEIGHT - 0.06 - (GLASS_HEAD + 0.08)
	slat.size = Vector3(0.045, fascia, 0.05)
	slats.mesh = slat
	slats.instance_count = int((width - 0.1) / 0.11)
	for i in slats.instance_count:
		slats.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				Vector3(wx0 + 0.05 + i * 0.11 + 0.0225, GLASS_HEAD + 0.08 + fascia * 0.5, z0 - 0.04)))
	var fascia_node := MultiMeshInstance3D.new()
	fascia_node.name = "GlassFascia"
	fascia_node.multimesh = slats
	fascia_node.material_override = walnut
	add_child(fascia_node)
	# A strip of warm light under the fascia, grazing down the glass's casing.
	var strip := ZoneKit.block(self, Vector3(width - 0.1, 0.012, 0.02),
			Vector3((wx0 + wx1) * 0.5, GLASS_HEAD + 0.073, z0 - 0.05), ZoneKit.glow(Color(1.0, 0.72, 0.45), 1.2),
			"FasciaGlow")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A heavy studio door, walnut over mass, with a small double-glazed vision panel and a steel pull,
## hinged at `hinge_x` on the live room's face of the wall and swung open flat into that room.
func _hang_studio_door(hinge_x: float, face_z: float, walnut: Material) -> void:
	var door := Node3D.new()
	door.name = "StudioDoor"
	var leaf := GLASS_DOOR_WIDTH - GLASS_DOOR_JAMB * 2.0 - 0.01
	var thick := 0.07
	var tall := GLASS_DOOR_HEAD - 0.025
	# Open 90 degrees: its face along the room's depth, its hinge edge at the jamb.
	door.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(hinge_x - thick * 0.5 - 0.004, 0.012, face_z + 0.012))
	add_child(door)
	# In the door's frame the leaf runs from x 0 (hinge) to -leaf (open edge), as it stood shut.
	var win_lo := 1.3
	var win_hi := 1.75
	var win_x0 := -leaf * 0.5 - 0.14
	var win_x1 := -leaf * 0.5 + 0.14
	ZoneKit.block(door, Vector3(leaf, win_lo, thick), Vector3(-leaf * 0.5, win_lo * 0.5, 0), walnut, "DoorLeaf")
	ZoneKit.block(door, Vector3(leaf, tall - win_hi, thick), Vector3(-leaf * 0.5, (win_hi + tall) * 0.5, 0),
			walnut, "DoorLeaf")
	ZoneKit.block(door, Vector3(win_x0 + leaf, win_hi - win_lo, thick), Vector3((-leaf + win_x0) * 0.5, (win_lo + win_hi) * 0.5, 0),
			walnut, "DoorLeaf")
	ZoneKit.block(door, Vector3(-win_x1, win_hi - win_lo, thick), Vector3(win_x1 * 0.5, (win_lo + win_hi) * 0.5, 0),
			walnut, "DoorLeaf")
	for z in [-0.018, 0.018]:
		var pane := ZoneKit.block(door, Vector3(win_x1 - win_x0 - 0.004, win_hi - win_lo - 0.004, 0.008),
				Vector3(-leaf * 0.5, (win_lo + win_hi) * 0.5, z), _glass(), "DoorPane")
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A steel pull on each face, near the open edge.
	for side in [-1.0, 1.0]:
		ZoneKit.block(door, Vector3(0.025, 0.42, 0.025), Vector3(-leaf + 0.09, 1.02, side * (thick * 0.5 + 0.045)),
				Materials.brushed_metal(), "DoorPull")
		for y in [0.84, 1.2]:
			ZoneKit.block(door, Vector3(0.016, 0.016, 0.045), Vector3(-leaf + 0.09, y, side * (thick * 0.5 + 0.0225)),
					Materials.brushed_metal(), "DoorPullPost")


## The treatment's fabric, in the room's three colours.
func _cloth(colour: String) -> Material:
	var cloth := {
		"charcoal": Color(0.07, 0.07, 0.075),
		"rust": Color(0.22, 0.09, 0.05),
		"slate": Color(0.06, 0.09, 0.13),
	}
	return Materials.cached_scanned("panel_" + colour, "rough_linen", "1k", 0.35, cloth[colour])


## The side room's treatment: a live room for a kit is the most treated room in a studio. Bass
## traps up the corners the booth and the riser leave free, a run of panels behind the kit, and
## two on the walkway wall in the room's warm and cool colours, so the walls have something on
## them for the sconces to light.
func _treat_side_room(far: float, near: float, z0: float, z1: float) -> void:
	# A square column turned 45 degrees and stood on the corner: what shows is a triangle of
	# fabric filling it, floor to just under the sconces.
	# (None at the back corners: the patch wall fills that wall.)
	for corner in [Vector2(near, z0)]:
		# Its foot 6 mm up, clear of the walls' feet (2 mm) it runs into.
		var trap := ZoneKit.block(self, Vector3(0.5, 2.4, 0.5), Vector3(corner.x, 1.206, corner.y),
				_cloth("charcoal"), "BassTrap")
		trap.rotation.y = PI * 0.25
	var kit: AABB = zones()[&"drums"]
	var face_back := z0 + 0.06
	var panels := [
		# Behind the kit, high: the riser's cymbals are what the back wall hears first.
		[Vector3(kit.get_center().x - 0.62, 2.0, face_back + 0.045), Vector3(1.1, 1.0, 0.09), "rust"],
		[Vector3(kit.get_center().x + 0.62, 2.0, face_back + 0.045), Vector3(1.1, 1.0, 0.09), "slate"],
		# (The back wall's own is the patch wall's.)
	]
	for i in panels.size():
		var spec: Array = panels[i]
		ZoneKit.block(self, spec[1], spec[0], _cloth(spec[2]), "SideRoomPanel%d" % i)


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.62, 0.66, 0.12)
	glass.roughness = 0.04
	glass.metallic_specular = 0.8
	return glass


## Wall sconces: a brass box throwing light up and down the wall it is on. The live rooms' fill
## comes from these rather than more cans in the ceiling: a wall lit from a fitting on it reads as
## a room at night, and grazing the walnut slats is what makes them slats from across the room.
func _sconce_brass() -> StandardMaterial3D:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.5, 0.38, 0.2)
	brass.metallic = 1.0
	brass.roughness = 0.42
	return brass


## One sconce, its back to the wall at `at`, facing `facing` into the room.
func _hang_sconce(i: int, at: Vector3, facing: Vector3, brass: Material, energy := 2.4,
		reach := 3.8) -> void:
	var sconce := Node3D.new()
	sconce.name = "Sconce%d" % i
	sconce.transform = Transform3D(Basis.looking_at(facing, Vector3.UP, true), at)
	add_child(sconce)
	ZoneKit.block(sconce, Vector3(0.12, 0.24, 0.07), Vector3(0, 0, 0.035), brass, "SconceBody")
	# Light leaks from the top and bottom edges only.
	for y in [0.121, -0.121]:
		var slit := ZoneKit.block(sconce, Vector3(0.1, 0.002, 0.05), Vector3(0, y, 0.035),
				ZoneKit.glow(Color(1.0, 0.75, 0.5), 2.0), "SconceGlow")
		slit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for dir in [1.0, -1.0]:
		var wash := SpotLight3D.new()
		wash.name = "SconceWash"
		wash.position = Vector3(0, dir * 0.13, 0.05)
		# Up or down, leaning a little off the wall so the wall catches the light at a graze.
		wash.rotation = Vector3(dir * (PI * 0.5 + 0.12), 0, 0)
		wash.light_color = Color(1.0, 0.76, 0.52)
		wash.light_energy = energy
		wash.spot_angle = 62.0
		wash.spot_range = reach
		wash.spot_angle_attenuation = 0.9
		wash.light_specular = 0.05
		wash.shadow_enabled = false
		sconce.add_child(wash)


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
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT,
			carpet, walnut)
	# From the high ceiling, so reaching well past the floor: a spot's light runs out AT its
	# range, and one that only just reaches the floor leaves no pool on it.
	ZoneKit.spot_down(drums, Vector3(0, LIVE_ROOM_HEIGHT - 0.05, 0), Color(1.0, 0.82, 0.62), 4.0,
			40.0, 7.0, metal)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := _glass()
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, walnut, glass)
	ZoneKit.block(vocals, Vector3(booth_box.size.x - 0.2, 0.01, booth_box.size.z - 0.2),
			Vector3(0, 0.005, 0), Materials.cached_scanned("booth_felt", "rough_linen", "1k", 0.5,
			Color(0.10, 0.10, 0.12)), "BoothFloor")
	# On the felt, not sunk through it.
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.01, 0), metal, ZoneKit.MIC_YAW)
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
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, walnut, metal)
	_dress_prop_shelf(walnut, metal)
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
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, metal, walnut)
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


## The zones' dressing and, beside, the wall between the control room and the side room: the
## walker sees the two rooms meet along all of it, so the wall's window and plaster have to be
## solid here, leaving the door.
func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	if variant == BESIDE:
		var x := -room_width * 0.5
		var z0 := Studio.ROOM_FRONT
		var z1 := Studio.ROOM_BACK
		var shut := WINDOW_TO + JAMB
		var open := DOOR_TO - JAMB
		out.append({"c": Vector2(x, (z0 + shut) * 0.5), "h": Vector2(0.06, (shut - z0) * 0.5), "a": 0.0,
				"top": LIVE_ROOM_HEIGHT})
		out.append({"c": Vector2(x, (open + z1) * 0.5), "h": Vector2(0.06, (z1 - open) * 0.5), "a": 0.0,
				"top": LIVE_ROOM_HEIGHT})
		# The bass traps up the side room's free corners (_treat_side_room).
		for corner in [Vector2(x - SIDE_ROOM_WIDTH, z1), Vector2(x - 0.06, z1), Vector2(x - 0.06, z0)]:
			out.append({"c": corner, "h": Vector2(0.25, 0.25), "a": PI * 0.25, "top": 2.4})
	elif variant == THROUGH_GLASS:
		# The wall between the rooms, either side of the door's clear opening, and the door stood
		# open against the live room's side of it.
		var at := glass_openings()
		var cr := room_width * 0.5
		var z := (GLASS_WALL_FRONT + GLASS_WALL_BACK) * 0.5
		var half := (GLASS_WALL_BACK - GLASS_WALL_FRONT) * 0.5
		var shut := at[2] + GLASS_DOOR_JAMB
		var open := at[3] - GLASS_DOOR_JAMB
		out.append({"c": Vector2((-cr - 0.05 + shut) * 0.5, z), "h": Vector2((shut + cr + 0.05) * 0.5, half),
				"a": 0.0, "top": LIVE_ROOM_HEIGHT})
		out.append({"c": Vector2((open + cr + 0.05) * 0.5, z), "h": Vector2((cr + 0.05 - open) * 0.5, half),
				"a": 0.0, "top": LIVE_ROOM_HEIGHT})
		var leaf := GLASS_DOOR_WIDTH - GLASS_DOOR_JAMB * 2.0 - 0.01
		out.append({"c": Vector2(open - 0.039, GLASS_WALL_BACK + 0.012 + leaf * 0.5), "h": Vector2(0.035, leaf * 0.5),
				"a": 0.0, "top": GLASS_DOOR_HEAD})
	return out


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
