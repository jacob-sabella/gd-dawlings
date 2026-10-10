class_name StationVenue
extends Venue

## A space station in orbit: one module of a ring, its walls flush grey panels on dark ribs, its
## section an octagon -- walls, chamfered corners, a low ceiling -- and a long viewport across
## the front on a planet below, its night side turned toward you, cities lit on its land. Under
## the lattice the deck is glass, and the planet is straight down through it. Through a pressure
## hatch in each side wall the ring's corridor runs on, its floor curving up and away overhead,
## the way a ring's does.
##
## Lit like a ship on its night cycle: cool LED coves along the chamfers, a row of downlights,
## the zones' own fittings, and the sun, low beyond the planet's limb, laying the viewport's
## frames across the deck.

## Floor to the top of the side walls, and to the ceiling between the chamfers. Above every
## zone's head room (Venue.ZONES): the lattice's 3.4 m stands under the ceiling.
const WALL_TOP := 3.3
const CEILING := 4.2
## How far in from the side walls the ceiling starts: the chamfer's run, at 45 degrees.
const CHAMFER := 0.9
const WALL := 0.2
## Where the viewport wall stands, in front of the desk: the footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The viewport: three wide bays across the front.
const SILL := 0.7
const HEAD := 2.7
const BAY := 3.6
const FRONT_BAYS := [-4.4, 0.0, 4.4]
## The hatches: in each side wall, beside the desk. Their outside size, from hatch.glb.
const DOOR_Z := 0.8
const HATCH := Vector2(2.0, 2.7)
const HATCH_OPENING := Vector2(1.4, 2.25)
## The ring: its radius, and the corridor beyond each hatch (its width along z, its height),
## built a step at a time round the ring up to the angle where its own ceiling hides the rest.
const RING := 60.0
const RING_STEP := 2.5
const RING_TO := 80.0
const CORRIDOR := Vector2(2.4, 2.6)
## The frames the module is built on, this far apart.
const RIB_SPACING := 2.4
## The sun, beyond the planet's limb, in front and to the left: what the sky draws and what
## lights the deck through the viewport.
const SUN_DIR := Vector3(-0.85, 0.15, -0.5)

const MODELS := "res://assets/models/"

## How fast the station comes round its orbit, in radians a second: one turn in about a
## quarter of an hour, slow enough that the ground below is only seen to move if watched.
const ORBIT_RATE := 0.007
## How often the sky is turned: each turn redraws it, so not every frame.
const ORBIT_STEP := 0.1

var _sky_mat: ShaderMaterial
var orbit := 0.0
var _orbit_wait := 0.0


func venue_id() -> StringName:
	return &"station"


func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/space_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Turned every tenth of a second (_process): its reflections catch up over a few frames
	# rather than all in one.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.44, 0.62)
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The corridor going away round the ring: a little haze so its far end is not as sharp as
	# its near one. None on the sky: there is no air out there.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.03, 0.04, 0.06)
	env.fog_depth_begin = 15.0
	env.fog_depth_end = 120.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.3

	# The sun, unfiltered: white, hard-edged, low through the viewport.
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 0.75
	key.basis = Basis.looking_at(-SUN_DIR.normalized(), Vector3.UP)
	key.light_specular = 0.3


func lamp_colour(_index: int, authored: Color) -> Color:
	# The station's LEDs: a cool white.
	return authored.lerp(Color(0.86, 0.92, 1.0), 0.35)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.85


## The module is one open floor: the deck either side of the desk joins the far end.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), true)


## The glass in the deck, under the lattice: the matrix zone's floor, a hair inside it.
func glass_floor() -> Rect2:
	var box: AABB = zones()[&"matrix"]
	return Rect2(box.position.x + 0.04, box.position.z + 0.04, box.size.x - 0.08, box.size.z - 0.08)


## Where a point on the corridor's floor centre line is, `degrees` round the ring from a hatch on
## `side` (-1 left, 1 right): level at the hatch, rising as it goes.
func ring_point(side: float, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees)
	# From the hatch frame's outside face, so there is no gap between the two.
	var x0 := live_room_half() + WALL * 0.5 + 0.16
	return Vector3(side * (x0 + RING * sin(a)), RING * (1.0 - cos(a)), DOOR_Z)


func _process(delta: float) -> void:
	orbit = fmod(orbit + delta * ORBIT_RATE, TAU)
	_orbit_wait -= delta
	if _orbit_wait <= 0.0 and _sky_mat != null:
		_orbit_wait = ORBIT_STEP
		_sky_mat.set_shader_parameter("spin", orbit)


func _ready() -> void:
	var skin := _panels(Color(0.5, 0.52, 0.55), Vector2(1.2, 0.6), 0.04)
	var dark := _ribs()
	_lay_the_deck()
	_build_shell(skin, dark)
	_raise_ribs(dark)
	_build_corridors(dark)
	_light_the_module()
	_dress_zones()


## The station's grey skin (station_panel.gdshader).
func _panels(base: Color, size: Vector2, lights: float, metal := 0.2, roughness := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/station_panel.gdshader")
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("panel", size)
	m.set_shader_parameter("lights", lights)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("roughness_base", roughness)
	return m


func _ribs() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.105, 0.115)
	m.metallic = 0.45
	m.roughness = 0.5
	return m


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.06, 0.07, 0.08, 0.07)
	glass.roughness = 0.04
	# Little shine: the downlights' reflections in it read as white blobs over the planet.
	glass.metallic_specular = 0.1
	return glass


# --- the shell ------------------------------------------------------------------------------

## The deck: dark plates, in four pieces round the glass under the lattice; the glass, the
## deck's own depth showing round the hole, and a lit strip round its edge.
func _lay_the_deck() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var hole := glass_floor()
	var plates := _panels(Color(0.15, 0.16, 0.17), Vector2(0.6, 0.6), 0.0, 0.5, 0.45)
	var x0 := -half - 0.1
	var x1 := half + 0.1
	var z0 := FRONT - 0.1
	var z1 := back + 0.1
	# Front first: it is the piece under the gear, as wide as the room.
	for piece: Rect2 in [Rect2(x0, z0, x1 - x0, hole.position.y - z0),
			Rect2(x0, hole.end.y, x1 - x0, z1 - hole.end.y),
			Rect2(x0, hole.position.y, hole.position.x - x0, hole.size.y),
			Rect2(hole.end.x, hole.position.y, x1 - hole.end.x, hole.size.y)]:
		var floor_mesh := MeshInstance3D.new()
		floor_mesh.name = "Floor"
		var plane := PlaneMesh.new()
		plane.size = piece.size
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(piece.get_center().x, 0, piece.get_center().y)
		floor_mesh.material_override = plates
		add_child(floor_mesh)
	var pane := ZoneKit.block(self, Vector3(hole.size.x, 0.02, hole.size.y),
			Vector3(hole.get_center().x, -0.012, hole.get_center().y), _glass(), "FloorGlass")
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The deck's depth round the hole, 40 cm of structure, and the lit strip at its lip.
	var deep := 0.4
	var dark := _ribs()
	var c := hole.get_center()
	for spec in [[Vector3(hole.size.x + 0.08, deep, 0.04), Vector3(c.x, -deep * 0.5 - 0.003, hole.position.y - 0.02)],
			[Vector3(hole.size.x + 0.08, deep, 0.04), Vector3(c.x, -deep * 0.5 - 0.003, hole.end.y + 0.02)],
			[Vector3(0.04, deep, hole.size.y), Vector3(hole.position.x - 0.02, -deep * 0.5 - 0.003, c.y)],
			[Vector3(0.04, deep, hole.size.y), Vector3(hole.end.x + 0.02, -deep * 0.5 - 0.003, c.y)]]:
		ZoneKit.block(self, spec[0], spec[1], dark, "DeckEdge")
	var strip := ZoneKit.glow(Color(0.35, 0.8, 1.0), 1.4)
	ZoneKit.floor_frame(self, hole.size + Vector2(0.06, 0.06), Vector3(c.x, 0.0, c.y), 0.03, strip)


## Side walls with a hatch in each, the viewport across the front, a plain back, the chamfers
## and the ceiling between them, and the end walls' upper parts closing the octagon.
func _build_shell(skin: Material, dark: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	# The sides take the corners, front and back.
	var z_from := FRONT - WALL
	var z_to := back + WALL
	# The hatch frames: bare machined steel, a step lighter than the panels round them.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.34, 0.37)
	steel.metallic = 0.7
	steel.roughness = 0.35
	for side in [-1.0, 1.0]:
		var x: float = side * (half + WALL * 0.5)
		var a := DOOR_Z - HATCH.x * 0.5
		var b := DOOR_Z + HATCH.x * 0.5
		ZoneKit.block(self, Vector3(WALL, WALL_TOP, a - z_from), Vector3(x, WALL_TOP * 0.5, (z_from + a) * 0.5), skin,
				"SideWall")
		ZoneKit.block(self, Vector3(WALL, WALL_TOP, z_to - b), Vector3(x, WALL_TOP * 0.5, (b + z_to) * 0.5), skin,
				"SideWall")
		ZoneKit.block(self, Vector3(WALL - 0.004, WALL_TOP - HATCH.y, HATCH.x), Vector3(x, (HATCH.y + WALL_TOP) * 0.5,
				DOOR_Z), skin, "OverHatch")
		var hatch := _model("hatch.glb", Vector3(x, 0, DOOR_Z), PI * 0.5,
				{"frame": steel, "hazard": _hazard(), "lamp": ZoneKit.glow(Color(1.0, 0.6, 0.2), 1.6)})
		hatch.name = "HatchLeft" if side < 0.0 else "HatchRight"
		# A pressure door of glass, shut, in the middle of the frame: the corridor is seen, not walked.
		var door := ZoneKit.block(self, Vector3(0.03, HATCH_OPENING.y + 0.1, HATCH_OPENING.x + 0.1),
				Vector3(x, 0.06 + HATCH_OPENING.y * 0.5, DOOR_Z), _glass(),
				"HatchGlassLeft" if side < 0.0 else "HatchGlassRight")
		door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The chamfer, from the wall's top in to the ceiling at 45 degrees, running into the
		# end walls at both ends.
		var run := CHAMFER * sqrt(2.0)
		var slab := ZoneKit.block(self, Vector3(run + 0.1, 0.1, z_to - z_from - 0.02), Vector3.ZERO, skin, "Chamfer")
		var mid := Vector2(side * (half - CHAMFER * 0.5), (WALL_TOP + CEILING) * 0.5)
		var out := Vector2(side, 1.0).normalized() * 0.05
		slab.position = Vector3(mid.x + out.x, mid.y + out.y, (z_from + z_to) * 0.5)
		slab.rotation.z = -side * PI * 0.25
	var ceiling := _panels(Color(0.3, 0.31, 0.33), Vector2(1.2, 0.6), 0.0)
	# The side walls, the chamfers and the ceiling each stop a step shorter into the end walls,
	# so their ends are never one plane.
	ZoneKit.block(self, Vector3((half - CHAMFER) * 2.0 + 0.1, 0.1, z_to - z_from - 0.04),
			Vector3(0, CEILING + 0.05, (z_from + z_to) * 0.5), ceiling, "Ceiling")
	# The viewport.
	var openings := ShellKit.wall_with_bays(self, "Front", Vector3(0, 0, FRONT - WALL * 0.5), Vector3(1, 0, 0),
			-half, half, FRONT_BAYS, BAY, SILL, HEAD, WALL_TOP, WALL, skin)
	for i in openings.size():
		ShellKit.glazed(self, "Viewport%d" % i, openings[i], Vector3(1, 0, 0), Vector2(BAY, HEAD - SILL), dark,
				_glass(), 4, 1.0, 0.06)
	ZoneKit.block(self, Vector3(half * 2.0, WALL_TOP, WALL), Vector3(0, WALL_TOP * 0.5, back + WALL * 0.5), skin,
			"BackWall")
	for z in [FRONT - WALL * 0.5, back + WALL * 0.5]:
		_end_wall_top(z, skin)


## The end wall's part above the side walls' tops: a trapezoid filling the octagon's top.
func _end_wall_top(z: float, material: Material) -> void:
	var half := live_room_half()
	var d := WALL * 0.5
	# Its foot a few millimetres into the wall below, its top just over the ceiling's underside.
	var outline := [Vector2(-half - 0.004, WALL_TOP - 0.004), Vector2(half + 0.004, WALL_TOP - 0.004),
			Vector2(half - CHAMFER + 0.05, CEILING + 0.02), Vector2(-half + CHAMFER - 0.05, CEILING + 0.02)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, e: Vector3) -> void:
		for v in [a, b, c, a, c, e]:
			st.add_vertex(v)
	var front: Array = outline.map(func(p: Vector2) -> Vector3: return Vector3(p.x, p.y, -d))
	var rear: Array = outline.map(func(p: Vector2) -> Vector3: return Vector3(p.x, p.y, d))
	# Both faces both ways round: whichever way the winding falls, each face is seen from inside.
	quad.call(front[0], front[1], front[2], front[3])
	quad.call(front[3], front[2], front[1], front[0])
	quad.call(rear[0], rear[1], rear[2], rear[3])
	quad.call(rear[3], rear[2], rear[1], rear[0])
	st.generate_normals()
	var top := MeshInstance3D.new()
	top.name = "EndWallTop"
	top.mesh = st.commit()
	top.position.z = z
	top.material_override = material
	add_child(top)


func _hazard() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/hazard.gdshader")
	return m


## The frames: a rib round the octagon every RIB_SPACING, proud of the skin -- up each wall, along
## each chamfer, across the ceiling -- except where a hatch is.
func _raise_ribs(dark: Material) -> void:
	var half := live_room_half()
	var z := FRONT + RIB_SPACING * 0.5
	while z < LIVE_ROOM_BACK - 0.3:
		for side in [-1.0, 1.0]:
			if absf(z - DOOR_Z) > HATCH.x * 0.5 + 0.1:
				ZoneKit.block(self, Vector3(0.08, WALL_TOP, 0.14), Vector3(side * (half - 0.04), WALL_TOP * 0.5, z), dark,
						"Rib")
			var run := CHAMFER * sqrt(2.0)
			# A hair thinner than the pieces either side of it, so the faces where they meet are
			# not one plane.
			var rib := ZoneKit.block(self, Vector3(run, 0.08, 0.12), Vector3.ZERO, dark, "Rib")
			var mid := Vector2(side * (half - CHAMFER * 0.5), (WALL_TOP + CEILING) * 0.5)
			var into := Vector2(-side, -1.0).normalized() * 0.04
			rib.position = Vector3(mid.x + into.x, mid.y + into.y, z)
			rib.rotation.z = -side * PI * 0.25
		ZoneKit.block(self, Vector3((half - CHAMFER) * 2.0, 0.08, 0.14), Vector3(0, CEILING - 0.04, z), dark, "Rib")
		z += RIB_SPACING


## The ring's corridor beyond each hatch: floor, ceiling and walls a step at a time round the
## ring, all one MultiMesh of the skin, a light strip down the middle of its ceiling, and a few
## lamps so its floor reads as it climbs away.
func _build_corridors(dark: Material) -> void:
	var skin_pieces: Array[Transform3D] = []
	var strips: Array[Transform3D] = []
	var step_len := RING * deg_to_rad(RING_STEP) + 0.02
	var w := CORRIDOR.x
	var h := CORRIDOR.y
	for side in [-1.0, 1.0]:
		var deg := RING_STEP * 0.5
		while deg < RING_TO:
			var at := ring_point(side, deg)
			var a := deg_to_rad(deg)
			# The corridor's frame here: along it, up (toward the ring's axis), and across (z).
			var along := Vector3(side * cos(a), sin(a), 0)
			var up := Vector3(-side * sin(a), cos(a), 0)
			# Across from the other two, so the frame stays a rotation on both sides.
			var across := along.cross(up)
			var basis := Basis(along, up, across)
			var piece := func(size: Vector3, offset: Vector3) -> Transform3D:
				return Transform3D(basis * Basis.from_scale(size), at + basis * offset)
			skin_pieces.append(piece.call(Vector3(step_len, 0.1, w + 0.2), Vector3(0, -0.05, 0)))
			skin_pieces.append(piece.call(Vector3(step_len, 0.1, w + 0.2), Vector3(0, h + 0.05, 0)))
			skin_pieces.append(piece.call(Vector3(step_len, h, 0.1), Vector3(0, h * 0.5, -w * 0.5 - 0.05)))
			skin_pieces.append(piece.call(Vector3(step_len, h, 0.1), Vector3(0, h * 0.5, w * 0.5 + 0.05)))
			strips.append(piece.call(Vector3(step_len * 0.7, 0.03, 0.18), Vector3(0, h - 0.016, 0)))
			deg += RING_STEP
		# Two lamps down the first stretch of it, where it can be seen from the room.
		for deg_at in [4.0, 12.0]:
			var lamp := OmniLight3D.new()
			lamp.name = "CorridorLight"
			var a := deg_to_rad(deg_at)
			lamp.position = ring_point(side, deg_at) + Vector3(-side * sin(a), cos(a), 0) * (h - 0.3)
			lamp.light_color = Color(0.7, 0.85, 1.0)
			lamp.light_energy = 1.2
			lamp.omni_range = 7.0
			lamp.shadow_enabled = false
			add_child(lamp)
	_multimesh("Corridor", BoxMesh.new(), skin_pieces, _panels(Color(0.45, 0.47, 0.5), Vector2(1.2, 0.6), 0.05))
	_multimesh("CorridorStrips", BoxMesh.new(), strips, ZoneKit.glow(Color(0.75, 0.88, 1.0), 1.3))


func _multimesh(label: String, mesh: Mesh, at: Array[Transform3D], material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
	var holder := MultiMeshInstance3D.new()
	holder.name = label
	holder.multimesh = mm
	holder.material_override = material
	add_child(holder)


## LED coves along the chamfers' feet, and two rows of downlights in the ceiling.
func _light_the_module() -> void:
	var half := live_room_half()
	var length := LIVE_ROOM_BACK - FRONT
	var cove := ZoneKit.glow(Color(0.6, 0.85, 1.0), 1.2)
	for side in [-1.0, 1.0]:
		var strip := ZoneKit.block(self, Vector3(0.03, 0.03, length - 0.2), Vector3(side * (half - 0.1), WALL_TOP - 0.08,
				(FRONT + LIVE_ROOM_BACK) * 0.5), cove, "Cove")
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var can := _ribs()
	for x in [-2.6, 2.6]:
		for z in [-0.8, 1.6, 4.0, 6.4]:
			var light := ZoneKit.spot_down(self, Vector3(x, CEILING - 0.03, z), Color(0.86, 0.92, 1.0), 2.0, 55.0, 6.0, can)
			light.name = "Downlight"


# --- the zones ------------------------------------------------------------------------------

## The zones in the station's own materials: a riser of deck plate edged in light, a booth of
## glass in the ribs' dark frame, the glass floor under the lattice (built with the deck) with
## dust hanging in the air over it, a white composite bench, and the keys.
func _dress_zones() -> void:
	var z := zones()
	var dark := _ribs()
	var plates := _panels(Color(0.18, 0.19, 0.2), Vector2(0.6, 0.6), 0.0, 0.5, 0.45)
	var composite := StandardMaterial3D.new()
	composite.albedo_color = Color(0.72, 0.74, 0.76)
	composite.roughness = 0.35

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var riser := Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, riser, ZoneKit.RISER_HEIGHT, plates, dark)
	# A line of light along its front edge, so the step up is seen.
	ZoneKit.block(drums, Vector3(riser.x, 0.02, 0.02), Vector3(0, ZoneKit.RISER_HEIGHT - 0.03, -riser.y * 0.5 - 0.011),
			ZoneKit.glow(Color(0.35, 0.8, 1.0), 1.2), "EdgeLight")

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, dark, _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(0.86, 0.92, 1.0),
			1.3, 60.0, 3.2, dark)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var lattice: AABB = z[&"matrix"]
	_hang_dust(matrix, lattice.size)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, composite, dark)
	_dress_prop_shelf(composite, dark)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, dark, composite)


## Weightless dust over the glass floor, drifting every way at once and never settling: what
## says there is no down here, before anything is built in the lattice.
func _hang_dust(parent: Node3D, size: Vector3) -> void:
	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 220
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = size * 0.5 - Vector3(0.2, 0.2, 0.2)
	motion.gravity = Vector3.ZERO
	motion.direction = Vector3(0, 1, 0)
	motion.spread = 180.0
	motion.initial_velocity_min = 0.01
	motion.initial_velocity_max = 0.04
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.2
	motion.turbulence_influence_min = 0.01
	motion.turbulence_influence_max = 0.03
	dust.process_material = motion
	var mote := QuadMesh.new()
	mote.size = Vector2(0.016, 0.016)
	# A soft round speck, not a square: a radial fade on the quad.
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
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	shine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shine.albedo_texture = spot
	shine.albedo_color = Color(0.6, 0.85, 1.0, 0.8)
	mote.material = shine
	dust.draw_pass_1 = mote
	dust.position = Vector3(0, size.y * 0.5, 0)
	dust.visibility_aabb = AABB(-size * 0.5, size)
	parent.add_child(dust)


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


## The mirror stands on the open deck at the footprint's left edge, framed like the viewport.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _ribs())
