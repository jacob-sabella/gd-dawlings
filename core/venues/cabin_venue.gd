class_name CabinVenue
extends Venue

## A log cabin in snowy woods, at night: one room under a steep pitched roof, pine boards on the
## walls and worn planks underfoot, a wood stove in the corner by the desk, and small-paned
## windows on firs and falling snow. Like the loft there is no control room -- the desk stands
## in the room and the floor round it is walkable to the walls -- and the zones fill the far end,
## the keys under the big window on the right where you can watch the snow while you play.
##
## Lit by fire and lanterns: the stove's glow on the floor, lanterns hung from the rafters and
## one on the table, the zones' own fittings, and the moon off the snow through the glass.

## Floor to the top of the side walls, and to the underside of the ridge. Above every zone's head
## room (Venue.ZONES): the lattice's 3.4 m stands under the eaves.
const EAVES := 3.5
const RIDGE := 5.7
## Log walls, thick.
const WALL := 0.24
## Where the front wall stands, in front of the desk: the footprint's front edge.
const FRONT := -Studio.ROOM_DEPTH * 0.5 + 0.3
## Cabin windows: small panes, a deep sill, the head well under the eaves.
const SILL := 0.9
const HEAD := 2.4
const BAY := 1.3
## The front's bays (x) and the right wall's (z): the last is the big one over the keys.
const FRONT_BAYS := [-4.3, -1.6, 1.6, 4.3]
const RIGHT_BAYS := [0.3]
const KEYS_BAY := 2.2
## The left wall has one bay, past the stove.
const LEFT_BAYS := [1.4]
## The stove, in the front-left corner beside the desk, door to the room.
const STOVE_AT := Vector2(-5.35, -1.15)
const STOVE_SIZE := Vector2(0.62, 0.6)
## The rafters, this far apart, and where the two tie beams cross the room: clear of the
## lattice's volume, one over the desk and one at the back.
const RAFTER_SPACING := 1.1
const TIES := [0.5, 6.7]
## Where the ground outside lies: the cabin stands on a sill of logs above the snow.
const GROUND := -0.55

const MODELS := "res://assets/models/"

var _stove_light: SpotLight3D
var _flicker := 0.0


func venue_id() -> StringName:
	return &"cabin"


func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	# A clear night over snow: deep blue, not black, because the snow gives some of it back.
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.46, 0.6)
	env.ambient_light_energy = 0.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The woods going back into the dark.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.065, 0.11)
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 90.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.004
		env.volumetric_fog_albedo = Color(0.8, 0.82, 0.9)
		env.volumetric_fog_length = 10.0
		env.volumetric_fog_ambient_inject = 0.0

	# The moon, high, over the woods in front and to the right: it lights the snow and lays the
	# window bars on the floor, and nothing else.
	key.light_color = Color(0.6, 0.7, 1.0)
	key.light_energy = 0.4
	key.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	key.light_specular = 0.1


func lamp_colour(_index: int, authored: Color) -> Color:
	# Firelight and oil: the warmest of any venue.
	return authored.lerp(Color(1.0, 0.62, 0.32), 0.45)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.8


## One room: the floor either side of the desk joins the far end, as in the loft.
func rooms() -> Array[Rect2]:
	var half := live_room_half()
	var cr := room_width * 0.5
	var depth := Studio.ROOM_DEPTH - 0.05
	var z := FRONT + 0.05
	return [back_of_house(),
			Rect2(-half + 0.05, z, half - cr, depth),
			Rect2(cr - 0.05, z, half - cr, depth)]


func stove_spot() -> Vector2:
	return Vector2(STOVE_AT.x - _grow(), STOVE_AT.y)


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	# The stove and its hearth: hot, and not something to walk through.
	out.append({"c": stove_spot(), "h": STOVE_SIZE * 0.5 + Vector2(0.15, 0.15), "a": 0.0, "top": 0.9})
	return out


## The roof's underside height at `x`: the eaves at the walls, the ridge over the middle.
func roof_at(x: float) -> float:
	return lerpf(RIDGE, EAVES, clampf(absf(x) / live_room_half(), 0.0, 1.0))


func _ready() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 0.2, back - FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (back + FRONT) * 0.5
	# Wide old boards, scrubbed grey-brown where people walk.
	floor_mesh.material_override = Materials.scanned(StandardMaterial3D.new(), "weathered_brown_planks", "2k",
			2.2, Color(0.62, 0.55, 0.5))
	add_child(floor_mesh)

	var pine := _pine()
	var frame := _timber()
	_build_walls(pine, frame)
	_build_roof(pine, frame)
	_light_the_stove()
	_furnish()
	_hang_lanterns()
	_put_up_the_shelf()
	_plant_the_woods()
	_let_it_snow()
	_dress_zones()


func _process(delta: float) -> void:
	if _stove_light == null:
		return
	# A fire breathes: two slow waves and a quick one, never out and never flaring.
	_flicker += delta
	var f := 0.82 + 0.1 * sin(_flicker * 2.3) + 0.06 * sin(_flicker * 5.1 + 1.3) + 0.04 * sin(_flicker * 13.7)
	_stove_light.light_energy = 2.6 * f


## Knotty pine boards, honey-coloured and oiled.
func _pine() -> StandardMaterial3D:
	return Materials.cached_scanned("cabin_pine", "wood_floor_deck", "2k", 1.8, Color(0.72, 0.6, 0.5))


## Rough-sawn timber for the frames, the rafters and the ties: darker, older than the boards.
func _timber() -> StandardMaterial3D:
	return Materials.cached_scanned("cabin_timber", "weathered_brown_planks", "2k", 1.2,
			Color(0.42, 0.34, 0.28))


func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.66, 0.72, 0.08)
	glass.roughness = 0.06
	glass.metallic_specular = 0.7
	return glass


# --- the shell ------------------------------------------------------------------------------

func _build_walls(pine: Material, frame: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var outside := half + WALL * 0.5
	var front_bays := FRONT_BAYS.map(func(x: float) -> float: return x + signf(x) * _grow())
	# The front's right-hand end a few millimetres short of the right wall's outside face.
	_windowed("Front", Vector3(0, 0, FRONT - WALL * 0.5), Vector3.RIGHT, -outside - WALL * 0.5,
			outside + WALL * 0.5 - 0.003, front_bays, BAY, pine, frame)
	# The side walls start a few millimetres past the front's inside face, so no bands overlap.
	_windowed("Left", Vector3(-outside, 0, 0), Vector3.BACK, FRONT + 0.003, back, LEFT_BAYS, BAY, pine,
			frame)
	_windowed("Right", Vector3(outside, 0, 0), Vector3.BACK, FRONT + 0.003, back, RIGHT_BAYS, BAY, pine,
			frame, _keys_window())
	# The back wall: plain boards, a hair inside the side walls' ends.
	ZoneKit.block(self, Vector3(outside * 2.0 - WALL - 0.002, EAVES - 0.008, WALL),
			Vector3(0, EAVES * 0.5, back + WALL * 0.5), pine, "BackWall")
	# The gables over the front and back walls, up into the roof's pitch.
	for g in [[FRONT - WALL * 0.5, "FrontGable"], [back + WALL * 0.5, "BackGable"]]:
		_gable(g[1], g[0], half + WALL, pine)


## The bay over the keys: wider than the others, centred on the synth's zone.
func _keys_window() -> float:
	return (zones()[&"synth"] as AABB).get_center().z


## A wall with windows: ShellKit's bays, each with a cabin window in it -- four panes high, two
## wide, in heavy timber, and a sill board proud of the wall to stand a lantern on. `wide_at`,
## if given, is one more bay KEYS_BAY wide.
func _windowed(label: String, at: Vector3, along: Vector3, from: float, to: float, bays: Array,
		bay: float, pine: Material, frame: Material, wide_at := NAN) -> void:
	var widths: Array = []
	var centres: Array = []
	for c in bays:
		centres.append(c)
		widths.append(bay)
	if not is_nan(wide_at):
		centres.append(wide_at)
		widths.append(KEYS_BAY)
	# ShellKit takes one bay width; a wall with a wide bay is built as its bands and piers by
	# hand from the same pieces.
	var across := Vector3(along.z, 0, along.x).abs()
	var inward := -signf(at.x + at.z)
	var openings: Array[Vector3] = []
	if is_nan(wide_at):
		openings = ShellKit.wall_with_bays(self, label, at, along, from, to, centres, bay, SILL, HEAD, EAVES,
				WALL, pine)
	else:
		openings = _wall_with_mixed_bays(label, at, along, from, to, centres, widths, pine)
	for i in openings.size():
		var w: float = widths[i]
		ShellKit.glazed(self, label + "Window%d" % i, openings[i], along, Vector2(w, HEAD - SILL), frame,
				_glass(), 3 if w < 2.0 else 4, (HEAD - SILL) / 4.0, 0.07)
		# The sill board, on the room side, its top 3 mm proud of the wall's sill.
		ZoneKit.block(self, along.abs() * (w + 0.16) + across * 0.14 + Vector3(0, 0.045, 0),
				openings[i] + Vector3(0, -(HEAD - SILL) * 0.5 - 0.0195, 0) + across * inward * (WALL * 0.5 + 0.05),
				frame, label + "SillBoard%d" % i)


func _wall_with_mixed_bays(label: String, at: Vector3, along: Vector3, from: float, to: float,
		centres: Array, widths: Array, pine: Material) -> Array[Vector3]:
	var across := Vector3(along.z, 0, along.x)
	var place := func(centre: float, y: float) -> Vector3:
		return at * across.abs() + along * centre + Vector3(0, y, 0)
	var sized := func(length: float, tall: float, deep: float) -> Vector3:
		return along.abs() * length + across.abs() * deep + Vector3(0, tall, 0)
	ZoneKit.block(self, sized.call(to - from, SILL, WALL + 0.004), place.call((from + to) * 0.5, SILL * 0.5),
			pine, label + "Sill")
	ZoneKit.block(self, sized.call(to - from, EAVES - HEAD, WALL + 0.004),
			place.call((from + to) * 0.5, (HEAD + EAVES) * 0.5), pine, label + "Head")
	var order := range(centres.size())
	order.sort_custom(func(a: int, b: int) -> bool: return centres[a] < centres[b])
	var edge := from
	var n := 0
	for i: int in order:
		var a: float = centres[i] - widths[i] * 0.5
		if a - edge > 0.01:
			ZoneKit.block(self, sized.call(a - edge, HEAD - SILL, WALL), place.call((a + edge) * 0.5,
					(SILL + HEAD) * 0.5), pine, label + "Pier%d" % n)
			n += 1
		edge = centres[i] + widths[i] * 0.5
	if to - edge > 0.01:
		ZoneKit.block(self, sized.call(to - edge, HEAD - SILL, WALL), place.call((to + edge) * 0.5,
				(SILL + HEAD) * 0.5), pine, label + "Pier%d" % n)
	var out: Array[Vector3] = []
	for c: float in centres:
		out.append(place.call(c, (SILL + HEAD) * 0.5))
	return out


## A gable: the triangle of wall between the eaves and the ridge, `WALL` deep, at depth `z`.
func _gable(label: String, z: float, half: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d := WALL * 0.5
	# Its foot sits a few millimetres into the wall below, its sloped edges just under the roof.
	var base := EAVES - 0.004
	var corners := [Vector3(-half, base, 0), Vector3(half, base, 0), Vector3(0, RIDGE + 0.05, 0)]
	var front := corners.map(func(c: Vector3) -> Vector3: return c + Vector3(0, 0, -d))
	var rear := corners.map(func(c: Vector3) -> Vector3: return c + Vector3(0, 0, d))
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	tri.call(front[0], front[2], front[1])
	tri.call(rear[0], rear[1], rear[2])
	for i in 3:
		var j := (i + 1) % 3
		tri.call(front[i], front[j], rear[j])
		tri.call(front[i], rear[j], rear[i])
	st.generate_normals()
	var gable := MeshInstance3D.new()
	gable.name = label
	gable.mesh = st.commit()
	gable.position.z = z
	gable.material_override = material
	add_child(gable)


## The roof: two boarded slopes from the eaves to the ridge, a ridge beam, rafters under the
## boards every RAFTER_SPACING, and two tie beams across the room at the eaves.
func _build_roof(pine: Material, frame: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var rise := RIDGE - EAVES
	var run := half + WALL
	var pitch := atan2(rise, half)
	var slope := Vector2(run, rise * run / half).length()
	var length := back - FRONT + WALL * 2.0 + 0.6
	var ceiling := Materials.cached_scanned("cabin_ceiling", "wood_floor_deck", "2k", 1.8,
			Color(0.5, 0.4, 0.33))
	for side in [-1.0, 1.0]:
		# The right slope a few millimetres shorter, so where they cross at the ridge their
		# ends are not in one plane.
		var board := ZoneKit.block(self, Vector3(slope, 0.08, length - (0.004 if side > 0 else 0.0)),
				Vector3.ZERO, ceiling,
				"Roof" + ("Left" if side < 0 else "Right"))
		# Its underside on the line from the eaves at the wall to the ridge over the middle.
		var mid := Vector2(side * run * 0.5, RIDGE - rise * run * 0.5 / half)
		var normal := Vector2(-side * sin(pitch), cos(pitch))
		board.position = Vector3(mid.x + normal.x * 0.04, mid.y + normal.y * 0.04, (back + FRONT) * 0.5)
		board.rotation.z = -side * pitch
	ZoneKit.block(self, Vector3(0.2, 0.28, length - 0.02), Vector3(0, RIDGE - 0.1, (back + FRONT) * 0.5),
			frame, "RidgeBeam")
	# Rafters: one MultiMesh a side, each under its board.
	var count := int((back - FRONT) / RAFTER_SPACING) + 1
	for side in [-1.0, 1.0]:
		var rafters := MultiMesh.new()
		rafters.transform_format = MultiMesh.TRANSFORM_3D
		var beam := BoxMesh.new()
		beam.size = Vector3(slope - 0.25, 0.18, 0.1)
		rafters.mesh = beam
		rafters.instance_count = count
		var mid := Vector2(side * (run * 0.5 + 0.05), RIDGE - rise * (run * 0.5 + 0.05) / half)
		var normal := Vector2(-side * sin(pitch), cos(pitch))
		for i in count:
			var z := lerpf(FRONT + 0.2, back - 0.2, float(i) / (count - 1))
			var basis := Basis(Vector3.BACK, -side * pitch)
			rafters.set_instance_transform(i, Transform3D(basis,
					Vector3(mid.x - normal.x * 0.091, mid.y - normal.y * 0.091, z)))
		var holder := MultiMeshInstance3D.new()
		holder.name = "Rafters" + ("Left" if side < 0 else "Right")
		holder.multimesh = rafters
		holder.material_override = frame
		add_child(holder)
	for z: float in TIES:
		ZoneKit.block(self, Vector3(half * 2.0 - 0.02, 0.22, 0.16), Vector3(0, EAVES - 0.11, z), frame,
				"TieBeam")


# --- the fire -------------------------------------------------------------------------------

## A cast-iron stove (assets/models/wood_stove.glb) on a slate hearth, its flue up through the
## roof, the fire behind its door glass the brightest thing in the room.
func _light_the_stove() -> void:
	var at := stove_spot()
	var hearth := StandardMaterial3D.new()
	hearth.albedo_color = Color(0.09, 0.09, 0.1)
	hearth.roughness = 0.75
	ZoneKit.block(self, Vector3(1.1, 0.04, 1.1), Vector3(at.x, 0.021, at.y), hearth, "Hearth")
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.035, 0.035, 0.038)
	iron.metallic = 0.6
	iron.roughness = 0.6
	var fire := ZoneKit.glow(Color(1.0, 0.38, 0.1), 1.7)
	# Turned so its door faces into the room, across the corner.
	var stove := _model("wood_stove.glb", Vector3(at.x, 0.041, at.y), deg_to_rad(55.0),
			{"iron": iron, "fire": fire})
	stove.name = "Stove"
	var top := 0.041 + 0.87
	var flue_top := roof_at(at.x) + 0.3
	var flue := MeshInstance3D.new()
	flue.name = "Flue"
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.075
	pipe.bottom_radius = 0.075
	pipe.height = flue_top - top + 0.04
	pipe.radial_segments = 16
	flue.mesh = pipe
	# The flue collar is 8 cm behind the stove's middle, the door being in front.
	var collar := Basis(Vector3.UP, deg_to_rad(55.0)) * Vector3(0, 0, -0.08)
	flue.position = Vector3(at.x + collar.x, top - 0.04 + pipe.height * 0.5, at.y + collar.z)
	flue.material_override = iron
	add_child(flue)
	# The fire's light, low, out through the door and across the floor.
	_stove_light = SpotLight3D.new()
	_stove_light.name = "Firelight"
	var facing := Basis(Vector3.UP, deg_to_rad(55.0))
	_stove_light.position = Vector3(at.x, 0.45, at.y) + facing * Vector3(0, 0, 0.4)
	_stove_light.basis = facing * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	_stove_light.light_color = Color(1.0, 0.5, 0.2)
	_stove_light.light_energy = 2.6
	_stove_light.spot_angle = 70.0
	_stove_light.spot_range = 5.5
	_stove_light.spot_angle_attenuation = 0.9
	_stove_light.shadow_enabled = rich
	_stove_light.light_specular = 0.1
	add_child(_stove_light)


## A rocking chair by the fire and a stack of split logs against the wall.
func _furnish() -> void:
	var at := stove_spot()
	var chair := _model("rocking_chair.glb", Vector3(at.x + 1.15, 0.0, at.y + 1.2), deg_to_rad(200.0), {})
	chair.name = "RockingChair"
	_lay_rug(Vector2(at.x + 1.15, at.y + 1.2), deg_to_rad(200.0))
	var bark := Materials.cached_scanned("cabin_logs", "weathered_brown_planks", "2k", 0.5,
			Color(0.38, 0.28, 0.2))
	var logs := MultiMesh.new()
	logs.transform_format = MultiMesh.TRANSFORM_3D
	var split := CylinderMesh.new()
	split.top_radius = 0.07
	split.bottom_radius = 0.07
	split.height = 0.45
	split.radial_segments = 7
	logs.mesh = split
	var rows := [5, 4, 3]
	logs.instance_count = 12
	var n := 0
	var wall := -live_room_half() + 0.3
	for r in rows.size():
		for i: int in rows[r]:
			var z: float = at.y + 0.75 + (i - (rows[r] - 1) * 0.5) * 0.145
			var y: float = 0.07 + r * 0.125
			logs.set_instance_transform(n, Transform3D(Basis(Vector3.BACK, PI * 0.5)
					* Basis(Vector3.UP, i * 1.7), Vector3(wall, y, z)))
			n += 1
	var pile := MultiMeshInstance3D.new()
	pile.name = "Logs"
	pile.multimesh = logs
	pile.material_override = bark
	add_child(pile)


## A long shelf on the back wall between the wall lanterns: a plank on iron brackets, a row of
## preserving jars (assets/models/jar.glb) in amber and green, and candles burning in a few of
## them. It is what the back wall is seen by from the desk -- a warm line at shoulder height --
## and two soft lights under the shelf wash the boards below it.
const SHELF_Y := 1.5
const SHELF_DEPTH := 0.24

## Where each jar on the shelf stands, kept here as well as in the MultiMeshes (which a headless
## run does not hold on to).
var shelf_jars: Array[Transform3D] = []

func _put_up_the_shelf() -> void:
	var back := LIVE_ROOM_BACK
	var from := -2.75 - _grow()
	var to := 1.35 + _grow() * 0.5
	var length := to - from
	var plank := _timber()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.04, 0.04, 0.04)
	iron.metallic = 0.6
	iron.roughness = 0.55
	ZoneKit.block(self, Vector3(length, 0.045, SHELF_DEPTH), Vector3((from + to) * 0.5, SHELF_Y,
			back - SHELF_DEPTH * 0.5 - 0.002), plank, "Shelf")
	for x in [from + 0.25, (from + to) * 0.5, to - 0.25]:
		ZoneKit.block(self, Vector3(0.03, 0.2, 0.03), Vector3(x, SHELF_Y - 0.125, back - 0.017), iron, "ShelfBracket")
		var arm := ZoneKit.block(self, Vector3(0.025, 0.025, 0.24), Vector3(x, SHELF_Y - 0.11, back - 0.11), iron,
				"ShelfStay")
		arm.rotation.x = -0.7
	# The jars: one MultiMesh for the preserves, one for the candle jars, each jar scaled a
	# little differently, the way no two batches are the same.
	var source := (load(MODELS + "jar.glb") as PackedScene).instantiate()
	var mesh := ((source.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D).mesh
	source.free()
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.55, 0.3, 0.08)
	amber.roughness = 0.25
	amber.metallic_specular = 0.8
	var green := amber.duplicate() as StandardMaterial3D
	green.albedo_color = Color(0.2, 0.32, 0.12)
	var tin := StandardMaterial3D.new()
	tin.albedo_color = Color(0.45, 0.4, 0.3)
	tin.metallic = 0.8
	tin.roughness = 0.4
	# A candle jar is clear glass lit from inside: its glass glows.
	var candle := ZoneKit.glow(Color(1.0, 0.6, 0.28), 1.3)
	var looks := [[amber, tin], [green, tin], [candle, tin]]
	var placed: Array = [[], [], []]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var x := from + 0.12
	var i := 0
	while x < to - 0.12:
		var kind := 2 if i % 5 == 2 else (rng.randi() % 2)
		var size := rng.randf_range(0.8, 1.25)
		placed[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, size, 1)
				* rng.randf_range(0.9, 1.1)), Vector3(x, SHELF_Y + 0.0226, back - SHELF_DEPTH * 0.5)))
		x += rng.randf_range(0.12, 0.2)
		i += 1
	for k in placed.size():
		shelf_jars.append_array(placed[k])
	for k in looks.size():
		var jars := mesh.duplicate() as Mesh
		jars.surface_set_material(0, looks[k][0])
		jars.surface_set_material(1, looks[k][1])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = jars
		mm.instance_count = placed[k].size()
		for n in placed[k].size():
			mm.set_instance_transform(n, placed[k][n])
		var holder := MultiMeshInstance3D.new()
		holder.name = ["Preserves", "Pickles", "CandleJars"][k]
		holder.multimesh = mm
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(holder)
	# The candles light the boards under the shelf, softly, and the wall above it.
	for t in [0.28, 0.72]:
		var at := Vector3(lerpf(from, to, t), SHELF_Y + 0.12, back - SHELF_DEPTH - 0.05)
		var wash := ZoneKit.spot_down(self, at, Color(1.0, 0.62, 0.3), 1.6, 80.0, 2.6)
		wash.rotation_degrees.x = 20.0
		wash.rotation_degrees.y = 180.0


## A braided rag rug, oval, under the rocking chair: rings of colour, each a hair above the last.
func _lay_rug(at: Vector2, yaw: float) -> void:
	var rings := [[1.0, Color(0.36, 0.12, 0.09)], [0.8, Color(0.55, 0.47, 0.33)], [0.62, Color(0.2, 0.25, 0.3)],
			[0.42, Color(0.42, 0.14, 0.1)], [0.22, Color(0.55, 0.47, 0.33)]]
	for i in rings.size():
		var r: float = rings[i][0]
		var disc := MeshInstance3D.new()
		disc.name = "Rug%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.7 * r
		cyl.bottom_radius = 0.7 * r
		cyl.height = 0.006
		cyl.radial_segments = 32
		cyl.rings = 1
		disc.mesh = cyl
		disc.position = Vector3(at.x, 0.003 + i * 0.0015, at.y)
		disc.rotation.y = yaw
		disc.scale = Vector3(1.0, 1.0, 0.7)
		disc.material_override = Materials.cached_scanned("cabin_rug%d" % i, "wool_boucle", "1k", 0.4, rings[i][1])
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)


## Oil lanterns (assets/models/lantern.glb) hung on chains from the rafters over the walk to the
## zones, and one on the table. Each lantern's glass glows; the hung ones light the floor.
func _hang_lanterns() -> void:
	var half := live_room_half()
	var chain := StandardMaterial3D.new()
	chain.albedo_color = Color(0.05, 0.045, 0.04)
	chain.metallic = 0.7
	chain.roughness = 0.5
	var spots := [Vector3(-half * 0.62, 2.55, 2.95), Vector3(0, 2.7, 1.05), Vector3(half * 0.62, 2.55, 2.95),
			Vector3(-half * 0.62, 2.6, -0.3), Vector3(half * 0.62, 2.6, -0.3)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var hook := roof_at(at.x) - 0.2
		var drop := hook - (at.y + 0.29)
		var link := ZoneKit.block(self, Vector3(0.012, drop, 0.012), Vector3(at.x, at.y + 0.29 + drop * 0.5, at.z),
				chain, "Chain%d" % i)
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lantern("Lantern%d" % i, at)
		ZoneKit.spot_down(self, at + Vector3(0, -0.02, 0), Color(1.0, 0.68, 0.38), 3.4, 75.0, 4.4)
	# Two more on iron brackets on the back wall, between the zones, washing the boards.
	var back := LIVE_ROOM_BACK
	for i in 2:
		var x: float = [-3.3 - _grow(), 2.0 + _grow()][i]
		var at := Vector3(x, 2.05, back - 0.26)
		ZoneKit.block(self, Vector3(0.03, 0.03, 0.26), Vector3(x, at.y + 0.33, back - 0.13), chain,
				"Bracket%d" % i)
		var link := ZoneKit.block(self, Vector3(0.012, 0.04, 0.012), Vector3(x, at.y + 0.305, at.z), chain,
				"BracketChain%d" % i)
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lantern("WallLantern%d" % i, at)
		var wash := ZoneKit.spot_down(self, at + Vector3(0, 0.12, 0), Color(1.0, 0.66, 0.36), 3.0, 70.0, 3.6)
		# Up and down the wall as much as onto the floor.
		wash.rotation_degrees.x = -60.0
		wash.rotation_degrees.y = 180.0


func _lantern(label: String, at: Vector3) -> Node3D:
	var lantern := _model("lantern.glb", at, 0.0, {"Lantern_01_glass": ZoneKit.glow(Color(1.0, 0.66, 0.34), 1.6)})
	lantern.name = label
	# Small, and lit from inside: a shadow apiece would cost more than it shows.
	for mesh: MeshInstance3D in lantern.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lantern


## The woods: firs (assets/models/firs.glb, three shapes) on snow all round, thick close in and
## thinning into the fog, with a clearing round the cabin. One MultiMesh a shape.
func _plant_the_woods() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Snow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(360, 360)
	ground.mesh = plane
	ground.position.y = GROUND
	ground.material_override = Materials.scanned(StandardMaterial3D.new(), "snow_02", "2k", 4.0,
			Color(0.62, 0.66, 0.74))
	add_child(ground)
	var source := load(MODELS + "firs.glb") as PackedScene
	var firs := source.instantiate()
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.035, 0.065, 0.05)
	needles.roughness = 0.9
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.7, 0.75, 0.85)
	snow.roughness = 0.8
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.1, 0.07, 0.05)
	var swap := {"needles": needles, "snow": snow, "bark": bark}
	var shapes: Array[Mesh] = []
	for node in firs.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.surface_set_material(s, swap[m.resource_name])
		shapes.append(mesh)
	firs.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var half := live_room_half()
	var clearing := Rect2(-half - 3.0, FRONT - 3.0, half * 2.0 + 6.0, LIVE_ROOM_BACK - FRONT + 6.0)
	var placed: Array = shapes.map(func(_m): return [])
	for i in 420:
		var r := sqrt(rng.randf()) * 90.0
		var a := rng.randf() * TAU
		var at := Vector2(cos(a) * r, sin(a) * r + 2.5)
		if clearing.grow(1.5).has_point(at):
			continue
		var tall := rng.randf_range(5.0, 13.0) * (1.0 + clampf(r / 90.0, 0, 1) * 0.4)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * tall),
				Vector3(at.x, GROUND, at.y))
		placed[rng.randi() % shapes.size()].append(t)
	for k in shapes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shapes[k]
		mm.instance_count = placed[k].size()
		for i in placed[k].size():
			mm.set_instance_transform(i, placed[k][i])
		var holder := MultiMeshInstance3D.new()
		holder.name = "Firs%d" % k
		holder.multimesh = mm
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(holder)


## Snow falling past the windows, in front and on the right: GPU particles, a few hundred flakes
## drifting down in boxes outside the glass. Nothing falls indoors.
func _let_it_snow() -> void:
	var half := live_room_half()
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.albedo_color = Color(0.8, 0.84, 0.95, 0.85)
	flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.billboard_keep_scale = true
	# A soft round flake, not a square one.
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = fade
	soft.width = 32
	soft.height = 32
	flake.albedo_texture = soft
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	quad.material = flake
	# Each box a metre and more clear of the walls, and the drift too gentle to carry a flake
	# that far, so nothing falls indoors.
	for side in [["SnowFront", Vector3(0, 4.0, FRONT - 6.5), Vector3(half + 6.0, 4.5, 5.0)],
			["SnowRight", Vector3(half + 5.6, 4.0, 2.6), Vector3(4.0, 4.5, 6.5)],
			["SnowLeft", Vector3(-half - 5.6, 4.0, 2.6), Vector3(4.0, 4.5, 6.5)]]:
		var fall := GPUParticles3D.new()
		fall.name = side[0]
		fall.position = side[1]
		fall.amount = 700
		fall.lifetime = 12.0
		fall.preprocess = 12.0
		fall.draw_pass_1 = quad
		fall.visibility_aabb = AABB(-side[2] - Vector3(0, 6, 0), side[2] * 2.0 + Vector3(0, 6, 0))
		var drift := ParticleProcessMaterial.new()
		drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		drift.emission_box_extents = side[2]
		drift.direction = Vector3(0, -1, 0)
		# Straight down, with only a little sway: a flake that starts a metre and a half out from
		# the wall in twelve seconds must still be outside it.
		drift.spread = 2.0
		drift.initial_velocity_min = 0.4
		drift.initial_velocity_max = 0.8
		drift.gravity = Vector3(0, -0.15, 0)
		drift.turbulence_enabled = true
		drift.turbulence_noise_strength = 0.12
		drift.turbulence_influence_min = 0.01
		drift.turbulence_influence_max = 0.04
		drift.turbulence_noise_scale = 4.0
		drift.scale_min = 0.6
		drift.scale_max = 1.4
		fall.process_material = drift
		add_child(fall)


# --- the zones ------------------------------------------------------------------------------

## The zones in the cabin's own materials: a plank riser on a rag rug, a booth framed in timber,
## the lattice's square as a braided rug's border, a farmhouse table with a lantern on it, and
## the keys under the big window.
func _dress_zones() -> void:
	var z := zones()
	var frame := _timber()
	var pine := _pine()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.04, 0.04, 0.04)
	iron.metallic = 0.6
	iron.roughness = 0.55
	var wool := Materials.cached_scanned("cabin_wool", "wool_boucle", "1k", 0.6, Color(0.5, 0.16, 0.12))

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, wool, pine)
	ZoneKit.spot_down(drums, Vector3(0, roof_at(drum_box.get_center().x) - 0.4, 0), Color(1.0, 0.72, 0.45),
			3.4, 46.0, 5.5, iron)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, frame, _glass())
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.66, 0.4),
			1.3, 60.0, 3.2, iron)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var lattice: AABB = z[&"matrix"]
	# A braided rug's border, deep red and cream, the floor inside it bare boards.
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.003, 0), 0.14, wool)
	ZoneKit.floor_frame(matrix, Vector2(2.82, 2.82), Vector3(0, 0.004, 0), 0.05,
			Materials.cached_scanned("cabin_cream", "wool_boucle", "1k", 0.6, Color(0.7, 0.64, 0.52)))
	ZoneKit.spot_down(matrix, Vector3(0, roof_at(0.0) - 0.45, 0), Color(0.95, 0.8, 0.62), 4.2, 40.0, 6.5,
			iron)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	var bench: AABB = z[&"bricks"]
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.08, pine, frame)
	var on_table := Vector3(0.25, ZoneKit.TABLE_HEIGHT + 0.001, -0.75)
	_lantern("TableLantern", bench.get_center() * Vector3(1, 0, 1) + on_table)
	ZoneKit.spot_down(bricks, Vector3(0, roof_at(bench.get_center().x) - 0.5, 0), Color(1.0, 0.72, 0.45),
			2.2, 50.0, 4.4, iron)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, iron, frame)
	ZoneKit.spot_down(synth, Vector3(-0.3, EAVES - 0.3, 0), Color(1.0, 0.74, 0.5), 2.0, 46.0, 4.0, iron)


## A model from assets/models, stood at `at` turned `yaw`, with its materials swapped by name.
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
	Venue.frame_bars(mirror, 0.06, 0.04, 0.014, _timber())
