class_name LoftVenue
extends Venue

## A converted warehouse at night: one long brick room, concrete underfoot, steel overhead, and
## tall factory windows on a city that is still up. The desk stands in the middle of it rather
## than in a room of its own -- a loft has no control room, only the end you work at -- and the
## activity zones fill the far end, with a steel gallery along the back wall to look down on the
## lattice from.
##
## Lit the way a loft is at night: enamel pendants hung low on long cords, each zone's own
## fitting, and the moon and the city coming in through the glass. Nothing from the ceiling but
## what hangs from it.

## Floor to the underside of the roof deck. A warehouse floor is tall; this is what makes the
## windows tall.
const HEIGHT := 5.6
## Brick, 32 cm: an outside wall of a building this age, and thick enough for a deep reveal.
const WALL := 0.32
## Where the room's front wall stands, in front of the desk. The footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The windows' sill and head, and how wide one bay of glass is.
const SILL := 0.95
const HEAD := 4.6
const BAY := 1.7
## Window bays: centres along the front wall (x) and the left wall (z). The front's middle bay is
## behind the timeline, which is a shame and also what a real loft would make you do.
const FRONT_BAYS := [-4.3, -1.6, 1.6, 4.3]
const LEFT_BAYS := [-0.9, 1.25]
## Iron columns holding the roof up, either side of the desk: [x, z] at the base width.
const COLUMNS := [Vector2(-4.6, -0.6), Vector2(4.6, -0.6), Vector2(-4.6, 2.6), Vector2(4.6, 2.6)]
const COLUMN_RADIUS := 0.13
## The gallery along the back wall: its deck's height, and how far it reaches into the room.
## Above every zone's head room (Venue.ZONES), so the lattice stands under it and is seen from it.
const GALLERY_Y := 3.6
const GALLERY_DEPTH := 0.95
## The gallery's deck boards, on its frame: what you stand on up there.
const DECK_TOP := GALLERY_Y + 0.06
## The stair up to it: a straight flight in front of the gallery's edge, rising toward the right
## wall, each step a riser no taller than the walker steps (Walker.STEP_HEIGHT) and a tread
## deep enough to stand on. It lands at the gallery's right-hand end, where the rail stops short.
const STAIR_STEPS := 12
const STAIR_TREAD := 0.3
const STAIR_WIDTH := 0.62
const LANDING := 1.0
## Steel beams across the room under the roof deck, this far apart.
const BEAM_SPACING := 2.4

var _city_mat: ShaderMaterial


func venue_id() -> StringName:
	return &"loft"


## Industrial: raw steel plate, black iron and reclaimed walnut, the warehouse's own vocabulary.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("blue_metal_plate", 1.6, Color(0.85, 0.8, 0.76))) \
			.with("chassis", GearStyle.paint(Color(0.075, 0.085, 0.095), 0.5, 0.5)) \
			.with("brushed", GearStyle.metal(Color(0.3, 0.29, 0.28), 0.5)) \
			.with("trim", GearStyle.metal(Color(0.2, 0.19, 0.18), 0.55)) \
			.with("end_cheek", GearStyle.scan("black_walnut_veneer_01", 0.8, Color(0.55, 0.42, 0.32))) \
			.with("lamp_shade", GearStyle.paint(Color(0.12, 0.25, 0.18), 0.35, 0.2)) \
			.with("loom_band", GearStyle.paint(Color(0.75, 0.3, 0.15), 0.7, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.06, 0.06, 0.06), 0.3, 0.0))


## Dark steel plate, chalky white lettering, brick-orange arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.scan("blue_metal_plate", 0.6, Color(0.3, 0.3, 0.3))
	board.ink = Color(0.92, 0.9, 0.86)
	board.accent = Color(0.95, 0.5, 0.3)
	board.board_ink_fade = Color(0.45, 0.44, 0.43)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	# The night past the glass: not black, a city sky has light in it from below.
	env.background_color = Color(0.022, 0.03, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.42, 0.55)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	# Distance in the city: the far towers sink into the night.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.06, 0.1)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 220.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.4
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_out = 1.4
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.7, 0.75, 0.85)
		env.volumetric_fog_length = 12.0
		env.volumetric_fog_ambient_inject = 0.0

	# The moon, low over the city in front and to the left, coming in through the glass: cool,
	# faint, and the only thing in the room that casts a window's shape on the floor.
	key.light_color = Color(0.62, 0.72, 1.0)
	key.light_energy = 0.32
	key.rotation_degrees = Vector3(-24.0, -35.0, 0.0)
	key.light_specular = 0.1


func lamp_colour(_index: int, authored: Color) -> Color:
	# Tungsten, warmer than the studio's: bare bulbs in an old building.
	return authored.lerp(Color(1.0, 0.7, 0.42), 0.4)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.85


## Past the footprint the loft is one room: the floor either side of the desk is as walkable as
## the far end, so two strips beside the footprint join it to the back of house.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


func _column_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c: Vector2 in COLUMNS:
		out.append(Vector2(c.x + signf(c.x) * _grow(), c.y))
	return out


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	for c in _column_spots():
		out.append({"c": c, "h": Vector2.ONE * COLUMN_RADIUS, "a": 0.0, "top": HEIGHT})
	# The stair, a step at a time, and the gallery it climbs to: you walk up one onto the other.
	out.append_array(stair_steps())
	var half := live_room_half()
	var front := LIVE_ROOM_BACK - GALLERY_DEPTH
	out.append({"c": Vector2(0, LIVE_ROOM_BACK - GALLERY_DEPTH * 0.5), "h": Vector2(half, GALLERY_DEPTH * 0.5),
			"a": 0.0, "top": DECK_TOP})
	# And its rail, which keeps you on it except where the stair comes up.
	var gap := _landing_x()
	out.append({"c": Vector2((gap - half) * 0.5, front + 0.03), "h": Vector2((gap + half) * 0.5, 0.03),
			"a": 0.0, "top": DECK_TOP + 1.1})
	return out


## The stair's steps as walker footprints: each a column from the floor to its tread.
func stair_steps() -> Array:
	var out := []
	var half := live_room_half()
	var start := half - 0.05 - STAIR_STEPS * STAIR_TREAD
	var z := LIVE_ROOM_BACK - GALLERY_DEPTH - 0.01 - STAIR_WIDTH * 0.5
	for i in STAIR_STEPS:
		out.append({"c": Vector2(start + STAIR_TREAD * (i + 0.5), z), "h": Vector2(STAIR_TREAD, STAIR_WIDTH) * 0.5,
				"a": 0.0, "top": DECK_TOP * (i + 1) / STAIR_STEPS})
	return out


## Where the gallery's rail stops, so the stair can land: the last LANDING of its length.
func _landing_x() -> float:
	return live_room_half() - LANDING


func _ready() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 0.2, back - FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (back + FRONT) * 0.5
	# Power-floated concrete, worn, a little polished: it takes a soft reflection of every pendant.
	var concrete := Materials.scanned(StandardMaterial3D.new(), "concrete_floor_worn_001", "2k", 2.4,
			Color(0.55, 0.55, 0.56))
	floor_mesh.material_override = concrete
	add_child(floor_mesh)

	var brick := Materials.cached_scanned("loft_brick", "red_brick_03", "2k", 1.6, Color(0.55, 0.42, 0.38))
	var steel := _steel()
	_build_walls(brick, steel)
	_build_roof(steel)
	_raise_columns()
	_build_gallery(steel)
	_hang_pendants()
	_raise_city()
	_dress_zones()


func _steel() -> StandardMaterial3D:
	var steel := StandardMaterial3D.new()
	# Black-painted mild steel, the paint worn thin at the edges nobody can see from here.
	steel.albedo_color = Color(0.045, 0.047, 0.05)
	steel.metallic = 0.55
	steel.roughness = 0.5
	return steel


# --- the shell ------------------------------------------------------------------------------

## Four brick walls, the front and left full of windows. Each wall with windows is built as a
## band under the sills, a band over the heads, and piers between the bays -- the bands a hair
## thicker than the piers so no two pieces share a face.
func _build_walls(brick: Material, steel: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var outside := half + WALL * 0.5
	# Front: in front of the desk, the windows you look out of from the seat.
	# Its right-hand end a few millimetres short of the right wall's outside face, not in it.
	_wall_with_bays("Front", Vector3(0, 0, FRONT - WALL * 0.5), Vector3.RIGHT, -outside - WALL * 0.5,
			outside + WALL * 0.5 - 0.003, _spread(FRONT_BAYS), brick, steel)
	# Left: two more bays beside the desk, on the city side.
	# Starting a few millimetres past the front wall's inside face, so the two walls' bands
	# never overlap and share a top.
	_wall_with_bays("Left", Vector3(-outside, 0, 0), Vector3.BACK, FRONT + 0.003, back, LEFT_BAYS,
			brick, steel)
	# Right and back: plain brick. A hair shorter top and bottom than the walls they run into.
	ZoneKit.block(self, Vector3(WALL, HEIGHT - 0.004, back - FRONT), Vector3(outside, HEIGHT * 0.5,
			(back + FRONT) * 0.5), brick, "RightWall")
	ZoneKit.block(self, Vector3(outside * 2.0 - WALL - 0.002, HEIGHT - 0.008, WALL),
			Vector3(0, HEIGHT * 0.5, back + WALL * 0.5), brick, "BackWall")


## The bay centres along the front wall, spread with the room the way the zones are.
func _spread(bays: Array) -> Array:
	return bays.map(func(x: float) -> float: return x + signf(x) * _grow())


## A brick wall with factory windows in its bays (ShellKit).
func _wall_with_bays(label: String, at: Vector3, along: Vector3, from: float, to: float, bays: Array,
		brick: Material, steel: Material) -> void:
	var openings := ShellKit.wall_with_bays(self, label, at, along, from, to, bays, BAY, SILL, HEAD,
			HEIGHT, WALL, brick)
	for i in openings.size():
		# A factory window: black steel glazing bars every 0.45 m, five uprights to a bay.
		ShellKit.glazed(self, label + "Window%d" % i, openings[i], along, Vector2(BAY, HEAD - SILL),
				steel, _glass())


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Old glass, a little green and a little dirty: it holds a faint reflection of the room.
	glass.albedo_color = Color(0.5, 0.58, 0.56, 0.1)
	glass.roughness = 0.08
	glass.metallic_specular = 0.7
	return glass


## The roof: a dark timber deck on steel beams across the room.
func _build_roof(steel: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var deck := ZoneKit.block(self, Vector3(half * 2.0 + 0.1, 0.12, back - FRONT + 0.1),
			Vector3(0, HEIGHT + 0.061, (back + FRONT) * 0.5),
			Materials.cached_scanned("loft_deck", "black_walnut_veneer_01", "2k", 1.2, Color(0.2, 0.16, 0.13)),
			"RoofDeck")
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beams := MultiMesh.new()
	beams.transform_format = MultiMesh.TRANSFORM_3D
	var beam := BoxMesh.new()
	# Its ends buried in the side walls.
	beam.size = Vector3(half * 2.0 + WALL - 0.02, 0.36, 0.16)
	beams.mesh = beam
	var count := ceili((back - FRONT) / BEAM_SPACING)
	beams.instance_count = count
	for i in count:
		var z := FRONT + BEAM_SPACING * (i + 0.5)
		beams.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.181, z)))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Beams"
	holder.multimesh = beams
	holder.material_override = steel
	add_child(holder)


func _raise_columns() -> void:
	var iron := StandardMaterial3D.new()
	# Cast iron, painted a dark green a long time ago.
	iron.albedo_color = Color(0.07, 0.09, 0.075)
	iron.metallic = 0.4
	iron.roughness = 0.55
	var i := 0
	for c in _column_spots():
		var column := MeshInstance3D.new()
		column.name = "Column%d" % i
		var shaft := CylinderMesh.new()
		shaft.top_radius = COLUMN_RADIUS * 0.85
		shaft.bottom_radius = COLUMN_RADIUS
		# Up to the underside of a beam's line, not into the deck.
		shaft.height = HEIGHT - 0.362
		shaft.radial_segments = 20
		column.mesh = shaft
		column.position = Vector3(c.x, (HEIGHT - 0.362) * 0.5 + 0.001, c.y)
		column.material_override = iron
		add_child(column)
		# A square base plate, so it stands on the floor rather than in it.
		ZoneKit.block(self, Vector3(0.34, 0.03, 0.34), Vector3(c.x, 0.017, c.y), iron, "ColumnBase%d" % i)
		i += 1


## A steel gallery along the back wall: a deck on brackets, a rail, and a stair up to it at the
## right-hand end, between the keys and the wall. You can climb it, and stand over the lattice --
## which is made to be looked down on.
func _build_gallery(steel: Material) -> void:
	var half := live_room_half()
	var wall := LIVE_ROOM_BACK
	var front := wall - GALLERY_DEPTH
	var length := half * 2.0 - 0.004
	ZoneKit.block(self, Vector3(length, 0.06, GALLERY_DEPTH - 0.002),
			Vector3(0, GALLERY_Y + 0.03, wall - GALLERY_DEPTH * 0.5 - 0.001),
			Materials.cached_scanned("loft_deck", "black_walnut_veneer_01", "2k", 1.2, Color(0.2, 0.16, 0.13)),
			"GalleryDeck")
	# The edge beam under the deck's front, which is what the deck reads as from below.
	ZoneKit.block(self, Vector3(length - 0.002, 0.24, 0.1), Vector3(0, GALLERY_Y - 0.121, front + 0.05),
			steel, "GalleryBeam")
	# Brackets back to the wall every couple of metres.
	var brackets := int(length / 2.0) + 1
	for i in brackets:
		var x := lerpf(-half + 0.3, half - 0.3, float(i) / (brackets - 1))
		var brace := ZoneKit.block(self, Vector3(0.06, 0.06, GALLERY_DEPTH * 1.25),
				Vector3(x, GALLERY_Y - 0.5, wall - GALLERY_DEPTH * 0.48), steel, "GalleryBrace%d" % i)
		brace.rotation.x = -0.72
	# The rail: posts, a top rail and a mid rail, stopping where the stair lands.
	var gap := _landing_x()
	var railed := gap + half
	var posts := int(railed / 1.2) + 1
	for i in posts:
		var x := lerpf(-half + 0.05, gap, float(i) / (posts - 1))
		ZoneKit.block(self, Vector3(0.04, 1.0, 0.04), Vector3(x, GALLERY_Y + 0.56, front + 0.03), steel,
				"GalleryPost%d" % i)
	for y in [GALLERY_Y + 1.07, GALLERY_Y + 0.58]:
		ZoneKit.block(self, Vector3(railed - 0.06, 0.035, 0.03), Vector3((gap - half) * 0.5 + 0.02, y, front + 0.03),
				steel, "GalleryRail")
	# Lamps clamped under the deck's edge beam, grazing the brick behind: the back wall is what
	# you see from the desk, and grazed brick is what a loft looks like at night.
	var grazers := 4
	for i in grazers:
		var x := lerpf(-half * 0.75, half * 0.75, float(i) / (grazers - 1))
		var lamp := ZoneKit.spot_down(self, Vector3(x, GALLERY_Y - 0.046, wall - 0.35),
				Color(1.0, 0.66, 0.4), 5.5, 38.0, 4.8, steel)
		lamp.rotation_degrees.x = -78.0
	_string_festoon(front + 0.03, GALLERY_Y + 1.07, length)
	_build_stair(steel)


## The stair: a steel plate at each step's height (stair_steps), two stringers along its sides,
## and a handrail on the open side, the room's.
func _build_stair(steel: Material) -> void:
	var steps := stair_steps()
	var first: Dictionary = steps[0]
	var last: Dictionary = steps[-1]
	var z: float = first["c"].y
	for i in steps.size():
		var step: Dictionary = steps[i]
		ZoneKit.block(self, Vector3(STAIR_TREAD - 0.004, 0.03, STAIR_WIDTH - 0.08),
				Vector3(step["c"].x, step["top"] - 0.015, z), steel, "StairTread%d" % i)
	var foot := Vector3(first["c"].x - STAIR_TREAD * 0.5, 0, z)
	var top := Vector3(last["c"].x + STAIR_TREAD * 0.5, DECK_TOP, z)
	var rise := top - foot
	for side in [-1.0, 1.0]:
		var stringer := ZoneKit.block(self, Vector3(rise.length(), 0.2, 0.03),
				(foot + top) * 0.5 + Vector3(0, -0.12, side * (STAIR_WIDTH * 0.5 - 0.022)), steel, "StairStringer")
		stringer.rotation.z = atan2(rise.y, rise.x)
	# The handrail, a metre over the nosings, on two posts.
	var rail_z := z - STAIR_WIDTH * 0.5 + 0.02
	for end in [foot + Vector3(STAIR_TREAD * 0.5, first["top"], 0), top - Vector3(STAIR_TREAD * 0.5, 0, 0)]:
		ZoneKit.block(self, Vector3(0.04, 1.0, 0.04), Vector3(end.x, end.y + 0.5, rail_z), steel, "StairPost")
	var handrail := ZoneKit.block(self, Vector3(rise.length() - STAIR_TREAD, 0.035, 0.035),
			(foot + top) * 0.5 + Vector3(0, 0.98, rail_z - z), steel, "StairRail")
	handrail.rotation.z = atan2(rise.y, rise.x)


## A festoon of bare bulbs hung along the gallery's top rail, each a little drop on its wire:
## lit by nothing but themselves, and enough to say where the gallery is from anywhere in the
## room. One MultiMesh.
func _string_festoon(z: float, rail_y: float, length: float) -> void:
	var spacing := 0.55
	var count := int(length / spacing)
	var bulbs := MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	var bulb := SphereMesh.new()
	bulb.radius = 0.028
	bulb.height = 0.06
	bulb.radial_segments = 10
	bulb.rings = 5
	bulbs.mesh = bulb
	bulbs.instance_count = count
	for i in count:
		var x := -length * 0.5 + spacing * (i + 0.5)
		# Every bulb hangs a little lower in the middle of a span, the way wire sags.
		var sag := 0.1 + 0.05 * sin(PI * fposmod(x / 1.2, 1.0))
		bulbs.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, rail_y - sag, z + 0.03)))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Festoon"
	holder.multimesh = bulbs
	holder.material_override = ZoneKit.glow(Color(1.0, 0.7, 0.38), 1.5)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


## Enamel factory shades on long cords from the beams, low over the walkway between the desk and
## the zones: the room's light comes from these, not from the roof.
func _hang_pendants() -> void:
	var enamel := StandardMaterial3D.new()
	enamel.albedo_color = Color(0.09, 0.16, 0.13)
	enamel.roughness = 0.3
	enamel.metallic_specular = 0.7
	var half := live_room_half()
	var spots := [Vector3(-half * 0.68, 3.0, 3.25), Vector3(-half * 0.24, 3.0, 3.25),
			Vector3(half * 0.24, 3.0, 3.25), Vector3(half * 0.68, 3.0, 3.25),
			# And one either side of the desk, over the floor beside it.
			Vector3(-half * 0.72, 3.1, 0.9), Vector3(half * 0.72, 3.1, 0.9)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var drop := HEIGHT - 0.36 - at.y
		var cord := ZoneKit.block(self, Vector3(0.008, drop, 0.008), at + Vector3(0, drop * 0.5 + 0.11, 0),
				steel_cord(), "PendantCord%d" % i)
		cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shade := MeshInstance3D.new()
		shade.name = "Shade%d" % i
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 0.26
		cone.height = 0.2
		cone.radial_segments = 24
		shade.mesh = cone
		shade.position = at
		shade.material_override = enamel
		add_child(shade)
		var bulb := ZoneKit.block(self, Vector3(0.08, 0.04, 0.08), at + Vector3(0, -0.075, 0),
				ZoneKit.glow(Color(1.0, 0.72, 0.42), 2.4), "Bulb%d" % i)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ZoneKit.spot_down(self, at + Vector3(0, -0.11, 0), Color(1.0, 0.74, 0.5), 4.0, 66.0, 5.2)


func steel_cord() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.roughness = 0.7
	return m


## The city past the glass, in front and to the left: dark blocks with their windows lit warm,
## a few cold, near enough at the front to read as the next street. One MultiMesh, one draw.
func _raise_city() -> void:
	_city_mat = ShaderMaterial.new()
	_city_mat.shader = preload("res://core/venues/shaders/tower.gdshader")
	_city_mat.set_shader_parameter("roof_from_custom", true)
	_city_mat.set_shader_parameter("body", Color(0.012, 0.013, 0.02))
	_city_mat.set_shader_parameter("lit_a", Color(1.0, 0.72, 0.4))
	_city_mat.set_shader_parameter("lit_b", Color(0.08, 0.09, 0.12))
	_city_mat.set_shader_parameter("lit_c", Color(0.75, 0.85, 1.0))
	_city_mat.set_shader_parameter("energy", 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var towers: Array[Transform3D] = []
	var roofs: Array[float] = []
	var cell := 10.0
	var keep_clear := Rect2(-live_room_half() - 12.0, FRONT - 12.0, live_room_half() * 2.0 + 24.0,
			LIVE_ROOM_BACK - FRONT + 30.0)
	for gx in range(-14, 15):
		for gz in range(-14, 6):
			var at := Vector2(gx * cell, gz * cell)
			if keep_clear.grow(cell * 0.5).has_point(at) or rng.randf() < 0.2:
				continue
			var w := rng.randf_range(5.0, 8.5)
			var d := rng.randf_range(5.0, 8.5)
			var h := rng.randf_range(12.0, 55.0)
			var centre := Vector3(at.x + rng.randf_range(-0.6, 0.6), h * 0.5 - 6.0,
					at.y + rng.randf_range(-0.6, 0.6))
			# The room is a third-floor loft: the street is six metres down.
			towers.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), centre))
			roofs.append(h - 6.0)
	var city := MultiMesh.new()
	city.transform_format = MultiMesh.TRANSFORM_3D
	city.use_custom_data = true
	city.mesh = BoxMesh.new()
	city.instance_count = towers.size()
	for i in towers.size():
		city.set_instance_transform(i, towers[i])
		city.set_instance_custom_data(i, Color(roofs[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "City"
	mmi.multimesh = city
	mmi.material_override = _city_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Where a fitting clamped under a roof beam hangs.
func _under_beam() -> float:
	return HEIGHT - 0.362 - 0.03


## The roof beam nearest over a zone's middle.
func _beam_z(box: AABB) -> float:
	var i := roundi((box.get_center().z - FRONT) / BEAM_SPACING - 0.5)
	return FRONT + BEAM_SPACING * (i + 0.5)


# --- the zones ------------------------------------------------------------------------------

## The zones in the loft's own materials: a riser of black-stained ply with a rubber top, a booth
## framed in black steel, the lattice's square painted on the concrete in safety yellow, a
## butcher-block workbench on steel legs, and the keys under a module case.
func _dress_zones() -> void:
	var z := zones()
	var steel := _steel()
	var ply := StandardMaterial3D.new()
	# Raw birch ply, sealed and scuffed: what a riser in a warehouse is knocked up from.
	ply.albedo_color = Color(0.42, 0.33, 0.22)
	ply.roughness = 0.72
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.035, 0.035, 0.038)
	rubber.roughness = 0.95
	var block_wood := Materials.cached_scanned("loft_bench", "black_walnut_veneer_01", "2k", 0.8,
			Color(0.72, 0.58, 0.44))

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, rubber, ply)
	# Clamped under the roof beam that crosses the kit's front edge.
	ZoneKit.spot_down(drums, Vector3(0, _under_beam(), _beam_z(drum_box) - drum_box.get_center().z),
			Color(1.0, 0.8, 0.6), 4.2, 40.0, 7.0, steel)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, steel, _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.68, 0.42),
			1.4, 60.0, 3.2, steel)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	# Safety yellow on the concrete, the way a loading bay is marked, and a cross at the middle.
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.66, 0.08)
	paint.roughness = 0.6
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.07, paint)
	ZoneKit.block(matrix, Vector3(0.5, 0.002, 0.06), Vector3(0, 0.002, 0), paint, "Cross")
	ZoneKit.block(matrix, Vector3(0.06, 0.002, 0.5), Vector3(0, 0.0025, 0), paint, "Cross")
	# Lit from the beam over it, cold, down onto the square.
	var lattice: AABB = z[&"matrix"]
	ZoneKit.spot_down(matrix, Vector3(0, _under_beam(), _beam_z(lattice) - lattice.get_center().z),
			Color(0.72, 0.82, 1.0), 7.0, 42.0, 7.0, steel)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, block_wood, steel)
	_dress_prop_shelf(block_wood, steel)
	ZoneKit.spot_down(bricks, Vector3(0, 2.6, 0), Color(1.0, 0.78, 0.55), 2.2, 50.0, 4.2, steel)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	var keys: AABB = z[&"synth"]
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, steel, block_wood)
	ZoneKit.block(synth, Vector3(0.1, 0.62, 1.5), Vector3(keys.size.x * 0.5 - 0.06, 1.6, 0), Materials.chassis(),
			"ModuleCase")
	ZoneKit.spot_down(synth, Vector3(-0.2, 3.0, 0), Color(1.0, 0.8, 0.62), 2.4, 44.0, 4.5, steel)


# --- the mirror -----------------------------------------------------------------------------

## The mirror stands where it does in every venue (Venue.mirror_spot), at the footprint's left
## edge -- open floor here, not a wall -- framed in the loft's black steel.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _steel())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Brick and iron: muted industrial colours, copper and patina, enamel paint gone dull.
func track_palette() -> Array:
	return [
		Color(0.69, 0.29, 0.24), Color(0.75, 0.47, 0.28), Color(0.78, 0.64, 0.31), Color(0.56, 0.60, 0.29),
		Color(0.35, 0.52, 0.35), Color(0.29, 0.54, 0.52), Color(0.35, 0.53, 0.66), Color(0.29, 0.37, 0.54),
		Color(0.43, 0.34, 0.52), Color(0.56, 0.35, 0.47), Color(0.72, 0.48, 0.53), Color(0.60, 0.61, 0.62),
	]
