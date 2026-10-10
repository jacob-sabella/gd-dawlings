class_name ClubVenue
extends Venue

## A jazz club after hours, the last set long over. A basement of old brick over a walnut
## wainscot, a pressed-tin ceiling gone dark with smoke, a herringbone floor worn pale where the
## dancing was. The stage is the drum riser, a red velvet curtain behind it, and one spot still
## burning on it from the ceiling, its beam hanging in the haze. Along the left wall, leather
## booths with a marble table in each and a candle guttering; along the right, the bar: a walnut
## counter on a brass foot rail, its stools turned up on top of it, the back bar's bottles lit
## from under their shelves against a mirror. "after hours" in pink neon over the door you came
## in by. No windows: the street is upstairs.

const HEIGHT := 4.2
const WALL := 0.3
## The front wall, in front of the desk: the footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The wainscot's height, and how proud of the brick it stands.
const WAINSCOT := 1.1
## The bar: its counter's front face (x), its ends (z), its height.
const BAR_FRONT := 4.9
const BAR_FROM := -1.6
const BAR_TO := 2.2
const BAR_TOP := 1.08
const COUNTER_DEPTH := 0.6
## The booths along the left wall: each one's centre (z). A booth is two benches facing each
## other across a table, its benches BENCH long out from the wall.
const BOOTHS := [-1.0, 1.4]
const BENCH := 1.3
## How far each bench's seat front is from the booth's centre.
const BENCH_GAP := 0.3
## The spot: where it hangs, and the stage it is on.
const SPOT_AT := Vector3(-2.2, HEIGHT - 0.3, 2.9)
## The upright piano pushed back against the ends of the two booths' back-to-back benches,
## between their openings, its keys to the room; the double bass laid on the floor beside it.
## Both in the side strip: the back of house is kept clear for people.
const PIANO_Z := 0.1
const PIANO_DEPTH := 0.6
const PIANO_WIDTH := 1.5
const BASS_AT := Vector3(-3.5, 0.0, 0.25)
const BASS_YAW := PI * 0.5 + 0.1
const BASS_LENGTH := 1.95
const MOTES := 180
const MODELS := "res://assets/models/"

var spot: SpotLight3D
## The booths' candles, for their flicker.
var candles: Array[OmniLight3D] = []
## Where every bottle on the back bar stands (a MultiMesh's own transforms are not kept headless).
var bottle_spots: Array[Transform3D] = []
## The heights the bottles stand at: the shelves', and the back bar's top.
var bottle_levels: Array[float] = []
## Where each glass was left, on the booth tables and the bar.
var glass_spots: Array[Vector3] = []
## Where each mote of dust in the spot's beam is put (it wanders a little round it).
var motes: Array[Vector3] = []
var _t := 0.0


func venue_id() -> StringName:
	return &"club"


func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.42, 0.3)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	# The haze the last set left behind, enough to soften the room's far corners.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.035, 0.03)
	env.fog_depth_begin = 3.0
	env.fog_depth_end = 30.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.4
	# No sun down here: the key is the room's general light, all but off.
	key.light_color = Color(1.0, 0.8, 0.6)
	key.light_energy = 0.04
	key.shadow_enabled = false
	key.basis = Basis.looking_at(Vector3(0.3, -1.0, 0.4), Vector3.FORWARD)


func lamp_colour(_index: int, authored: Color) -> Color:
	# Tungsten, warmer than the authored lamps: the club's bulbs are old.
	return authored.lerp(Color(1.0, 0.72, 0.45), 0.3)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.85


## One open floor: the strips either side of the footprint join the back of house.
func rooms() -> Array[Rect2]:
	var half := live_room_half()
	var cr := room_width * 0.5
	var depth := Studio.ROOM_DEPTH - 0.3
	return [back_of_house(),
			Rect2(-half, FRONT, half - cr, depth),
			Rect2(cr, FRONT, half - cr, depth)]


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	var half := live_room_half()
	# The bar's counter, and the back bar behind it.
	out.append({"c": Vector2(bar_front() + COUNTER_DEPTH * 0.5, (BAR_FROM + BAR_TO) * 0.5),
			"h": Vector2(COUNTER_DEPTH * 0.5, (BAR_TO - BAR_FROM) * 0.5), "a": 0.0, "top": BAR_TOP})
	out.append({"c": Vector2(half - 0.25, (BAR_FROM + BAR_TO) * 0.5),
			"h": Vector2(0.25, (BAR_TO - BAR_FROM) * 0.5), "a": 0.0, "top": 0.95})
	for z: float in BOOTHS:
		for side in [-1.0, 1.0]:
			out.append({"c": Vector2(-half + BENCH * 0.5, z + side * (BENCH_GAP + 0.3)), "h": Vector2(BENCH * 0.5, 0.3),
					"a": 0.0, "top": 1.15})
		out.append({"c": Vector2(-half + BENCH * 0.5, z), "h": Vector2(0.33, 0.33), "a": 0.0, "top": 0.74})
	for at in stool_spots():
		out.append({"c": at, "h": Vector2(0.2, 0.2), "a": 0.0, "top": 0.79})
	out.append({"c": Vector2(piano_x(), PIANO_Z), "h": Vector2(PIANO_DEPTH * 0.5 + 0.15, PIANO_WIDTH * 0.5), "a": 0.0,
			"top": 1.25})
	var bass_dir := Vector2(cos(BASS_YAW), -sin(BASS_YAW))
	out.append({"c": Vector2(bass_at().x, bass_at().z) + bass_dir * BASS_LENGTH * 0.5, "h": Vector2(BASS_LENGTH * 0.5, 0.2),
			"a": -BASS_YAW, "top": 0.72})
	return out


## The middle of the piano's case, its back to the booths' bench ends.
## The bar and the bass stand where they were drawn against a room DRAWN_WIDTH wide, moved out
## with its walls as it widens: left where they were, a wider room put them inside it.
func bar_front() -> float:
	return BAR_FRONT + _grow()


func bass_at() -> Vector3:
	return BASS_AT - Vector3(_grow(), 0, 0)


func piano_x() -> float:
	return -live_room_half() + BENCH + 0.05 + PIANO_DEPTH * 0.5


## Where each bar stool stands, in front of the counter.
func stool_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var z := BAR_FROM + 0.45
	while z < BAR_TO - 0.3:
		out.append(Vector2(bar_front() - 0.36, z))
		z += 0.75
	return out


## Where the spot is aimed: the middle of the drum riser's top.
func stage_centre() -> Vector3:
	var stage: AABB = zones()[&"drums"]
	return Vector3(stage.get_center().x, ZoneKit.RISER_HEIGHT, stage.get_center().z)


func _ready() -> void:
	_lay_the_floor()
	_build_walls()
	_build_ceiling()
	_build_the_bar()
	_build_the_booths()
	_hang_the_curtain()
	_hang_the_spot()
	_light_the_sign()
	_leave_the_instruments()
	_leave_the_glasses()
	_dress_zones()


func _process(delta: float) -> void:
	_t += delta
	for i in candles.size():
		var c := candles[i]
		c.light_energy = 0.35 + 0.08 * sin(_t * 7.3 + i * 2.1) * sin(_t * 3.1 + i) + 0.04 * sin(_t * 17.0 + i * 5.0)


# --- materials -------------------------------------------------------------------------------

func _brick() -> StandardMaterial3D:
	return Materials.cached_scanned("club_brick", "red_brick_03", "2k", 1.3, Color(0.42, 0.3, 0.26))


func _walnut() -> StandardMaterial3D:
	return Materials.cached_scanned("club_walnut", "black_walnut_veneer_01", "2k", 1.0, Color(0.3, 0.22, 0.16))


func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.6, 0.32)
	m.metallic = 1.0
	m.roughness = 0.32
	return m


func _black() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03)
	m.roughness = 0.5
	m.metallic = 0.4
	return m


func _leather() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.06, 0.05)
	m.roughness = 0.42
	m.metallic_specular = 0.45
	m.normal_enabled = true
	m.normal_texture = Materials.grain("leather", 0.3, 0.7)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	return m


func _bottle_glass(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	m.roughness = 0.08
	m.metallic_specular = 0.7
	m.rim_enabled = true
	m.rim = 0.4
	return m


func _swaps() -> Dictionary:
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.82, 0.8, 0.76)
	marble.roughness = 0.18
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.82, 0.74, 0.58)
	paper.roughness = 0.8
	return {"marble": marble, "iron": _black(), "wood": _walnut(), "leather": _leather(), "brass": _brass(),
			"glass_green": _bottle_glass(Color(0.1, 0.3, 0.12, 0.75)),
			"glass_amber": _bottle_glass(Color(0.55, 0.28, 0.06, 0.7)),
			"glass_clear": _bottle_glass(Color(0.75, 0.8, 0.8, 0.35)), "label": paper,
			"lacquer": _lacquer(), "ivory": _plain(Color(0.86, 0.82, 0.72), 0.35), "ebony": _plain(Color(0.025, 0.02, 0.02), 0.3),
			"varnish": _varnish(), "string": _brass(), "whisky": _bottle_glass(Color(0.62, 0.3, 0.05, 0.8)),
			"wine": _bottle_glass(Color(0.35, 0.02, 0.05, 0.9)), "wool": _cloth(Color(0.42, 0.33, 0.22)),
			"felt": _cloth(Color(0.12, 0.11, 0.1)), "ribbon": _plain(Color(0.03, 0.03, 0.03), 0.4)}


func _plain(colour: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	return m


## The piano's black lacquer: deep, and glossy enough to carry the spot and the candles.
func _lacquer() -> StandardMaterial3D:
	var m := _plain(Color(0.02, 0.018, 0.018), 0.12)
	m.metallic_specular = 0.8
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	m.clearcoat_roughness = 0.1
	return m


## The bass's varnish over maple: a warm red-brown with a shine.
func _varnish() -> StandardMaterial3D:
	var m := _plain(Color(0.36, 0.13, 0.04), 0.25)
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.normal_enabled = true
	m.normal_texture = Materials.grain("club_varnish", 0.15, 0.4, 4.0)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


func _cloth(colour: Color) -> StandardMaterial3D:
	var m := _plain(colour, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.6
	m.normal_enabled = true
	m.normal_texture = Materials.grain("club_wool", 0.25, 0.6)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	return m


# --- the room --------------------------------------------------------------------------------

func _lay_the_floor() -> void:
	var half := live_room_half()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + WALL, LIVE_ROOM_BACK - FRONT + WALL)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, (FRONT + LIVE_ROOM_BACK) * 0.5)
	floor_mesh.material_override = Materials.cached_scanned("club_floor", "herringbone_parquet", "2k", 2.0,
			Color(0.45, 0.36, 0.28))
	add_child(floor_mesh)


## Brick from the floor to the ceiling, the wainscot over its lower part, a cap rail along the
## wainscot's top, and the door in the front wall with its exit sign.
func _build_walls() -> void:
	var half := live_room_half()
	var brick := _brick()
	var walnut := _walnut()
	var z0 := FRONT
	var z1 := LIVE_ROOM_BACK
	var length := z1 - z0
	var mid := (z0 + z1) * 0.5
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, HEIGHT, length + WALL * 2.0), Vector3(side * (half + WALL * 0.5), HEIGHT * 0.5, mid),
				brick, "SideWall")
		ZoneKit.block(self, Vector3(0.04, WAINSCOT, length - 0.004), Vector3(side * (half - 0.02), WAINSCOT * 0.5, mid),
				walnut, "Wainscot")
		ZoneKit.block(self, Vector3(0.07, 0.05, length - 0.01), Vector3(side * (half - 0.037), WAINSCOT + 0.02, mid),
				walnut, "CapRail")
	for spec in [[z0 - WALL * 0.5, 1.0], [z1 + WALL * 0.5, -1.0]]:
		var z: float = spec[0]
		var inward: float = spec[1]
		ZoneKit.block(self, Vector3(half * 2.0, HEIGHT, WALL), Vector3(0, HEIGHT * 0.5, z), brick, "EndWall")
		ZoneKit.block(self, Vector3(half * 2.0 - 0.1, WAINSCOT, 0.04), Vector3(0, WAINSCOT * 0.5, z + inward * (WALL * 0.5 + 0.02)),
				walnut, "Wainscot")
		ZoneKit.block(self, Vector3(half * 2.0 - 0.144, 0.05, 0.07), Vector3(0, WAINSCOT + 0.02, z + inward * (WALL * 0.5 + 0.037)),
				walnut, "CapRail")
	# The door: in the front wall's left corner, a walnut slab in a black frame, a brass push
	# plate, the exit sign over it.
	var door_x := -half + 1.1
	# (all of it standing proud of the wainscot)
	var face := FRONT + 0.045
	ZoneKit.block(self, Vector3(1.0, 2.16, 0.06), Vector3(door_x, 1.08, face + 0.03), walnut, "Door")
	for spec in [[Vector3(0.06, 2.3, 0.08), Vector3(door_x - 0.53, 1.15, face + 0.04)],
			[Vector3(0.06, 2.3, 0.08), Vector3(door_x + 0.53, 1.15, face + 0.04)],
			[Vector3(1.0, 0.06, 0.07), Vector3(door_x, 2.2, face + 0.035)]]:
		ZoneKit.block(self, spec[0], spec[1], _black(), "DoorFrame")
	ZoneKit.block(self, Vector3(0.1, 0.3, 0.01), Vector3(door_x + 0.32, 1.15, face + 0.065), _brass(), "PushPlate")
	ZoneKit.block(self, Vector3(0.36, 0.14, 0.05), Vector3(door_x, 2.55, face + 0.03), _black(), "ExitBox")
	var exit := Label3D.new()
	exit.name = "Exit"
	exit.text = "EXIT"
	exit.font_size = 64
	exit.pixel_size = 0.0014
	exit.modulate = Color(2.4, 0.25, 0.2)
	exit.shaded = false
	exit.double_sided = false
	exit.position = Vector3(door_x, 2.55, face + 0.056)
	add_child(exit)
	var red := OmniLight3D.new()
	red.name = "ExitGlow"
	red.light_color = Color(1.0, 0.2, 0.15)
	red.light_energy = 0.25
	red.omni_range = 1.6
	red.position = Vector3(door_x, 2.4, face + 0.3)
	add_child(red)
	# Sconces on the brick, a warm pool each: two either side, high on the side walls.
	for side in [-1.0, 1.0]:
		for z in [3.6, 6.4]:
			var at := Vector3(side * (half - 0.08), 2.3, z)
			ZoneKit.block(self, Vector3(0.12, 0.2, 0.12), at, _brass(), "Sconce")
			ZoneKit.block(self, Vector3(0.1, 0.06, 0.1), at + Vector3(0, 0.13, 0), ZoneKit.glow(Color(1.0, 0.7, 0.4), 1.6),
					"SconceBulb")
			var lamp := OmniLight3D.new()
			lamp.name = "SconceLight"
			lamp.light_color = Color(1.0, 0.68, 0.4)
			lamp.light_energy = 1.0
			lamp.omni_range = 3.2
			lamp.position = at + Vector3(-side * 0.15, 0.25, 0)
			add_child(lamp)


## Pressed tin, gone dark: the station's panel grid in small squares, in an old brass colour.
func _build_ceiling() -> void:
	var half := live_room_half()
	var tin := ShaderMaterial.new()
	tin.shader = preload("res://core/venues/shaders/station_panel.gdshader")
	tin.set_shader_parameter("base", Color(0.16, 0.12, 0.08))
	tin.set_shader_parameter("seam", Color(0.03, 0.025, 0.02))
	tin.set_shader_parameter("panel", Vector2(0.6, 0.6))
	tin.set_shader_parameter("seam_width", 0.02)
	tin.set_shader_parameter("metal", 0.7)
	tin.set_shader_parameter("roughness_base", 0.45)
	tin.set_shader_parameter("mottle", 0.15)
	ZoneKit.block(self, Vector3(half * 2.0, 0.1, LIVE_ROOM_BACK - FRONT), Vector3(0, HEIGHT + 0.05,
			(FRONT + LIVE_ROOM_BACK) * 0.5), tin, "Ceiling")


# --- the bar ---------------------------------------------------------------------------------

## The counter, its top, its brass foot rail; the back bar against the wall, its shelves of
## bottles lit from under, a mirror behind them; the stools, some turned up on the counter.
func _build_the_bar() -> void:
	var half := live_room_half()
	var walnut := _walnut()
	var length := BAR_TO - BAR_FROM
	var mid := (BAR_FROM + BAR_TO) * 0.5
	var cx := bar_front() + COUNTER_DEPTH * 0.5
	ZoneKit.block(self, Vector3(COUNTER_DEPTH, BAR_TOP - 0.06, length), Vector3(cx, (BAR_TOP - 0.06) * 0.5, mid), walnut,
			"Counter")
	ZoneKit.block(self, Vector3(COUNTER_DEPTH + 0.12, 0.06, length + 0.12), Vector3(cx - 0.04, BAR_TOP - 0.03, mid),
			Materials.cached_scanned("club_top", "black_walnut_veneer_01", "2k", 1.0, Color(0.16, 0.11, 0.08)), "BarTop")
	var rail := MeshInstance3D.new()
	rail.name = "FootRail"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.025
	tube.bottom_radius = 0.025
	tube.height = length - 0.1
	tube.radial_segments = 12
	rail.mesh = tube
	rail.material_override = _brass()
	rail.rotation.x = PI * 0.5
	rail.position = Vector3(bar_front() - 0.14, 0.2, mid)
	add_child(rail)
	for z in [BAR_FROM + 0.2, mid, BAR_TO - 0.2]:
		ZoneKit.block(self, Vector3(0.14, 0.03, 0.03), Vector3(bar_front() - 0.07, 0.2, z), _brass(), "RailBracket")

	# The back bar: a low cabinet, three shelves over it, a mirror behind.
	ZoneKit.block(self, Vector3(0.44, 0.95, length), Vector3(half - 0.26, 0.475, mid), walnut, "BackBar")
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color(0.25, 0.22, 0.2)
	mirror.metallic = 1.0
	mirror.roughness = 0.12
	ZoneKit.block(self, Vector3(0.02, 1.3, length - 0.1), Vector3(half - 0.05, 1.85, mid), mirror, "BarMirror")
	var strip := ZoneKit.glow(Color(1.0, 0.68, 0.36), 1.8)
	var shelves := [1.3, 1.72, 2.14]
	for y: float in shelves:
		ZoneKit.block(self, Vector3(0.24, 0.03, length - 0.1), Vector3(half - 0.18, y, mid), walnut, "Shelf")
		var led := ZoneKit.block(self, Vector3(0.02, 0.012, length - 0.2), Vector3(half - 0.08, y - 0.021, mid), strip,
				"ShelfLight")
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z in [BAR_FROM + 0.8, BAR_TO - 0.8]:
		var glow := OmniLight3D.new()
		glow.name = "BackBarLight"
		glow.light_color = Color(1.0, 0.66, 0.36)
		glow.light_energy = 0.9
		glow.omni_range = 2.2
		glow.position = Vector3(half - 0.3, 1.9, z)
		add_child(glow)
	_line_the_bottles(shelves + [0.95], half - 0.18, length - 0.3, mid)

	# The stools: the first two standing, the rest turned up on the counter.
	var club := load(MODELS + "club.glb") as PackedScene
	var spots := stool_spots()
	for i in spots.size():
		var stool := _piece(club, "Stool")
		if i < 2:
			stool.position = Vector3(spots[i].x, 0, spots[i].y)
			stool.rotation.y = i * 0.7
		else:
			stool.basis = Basis(Vector3.RIGHT, PI)
			stool.position = Vector3(cx - 0.05, BAR_TOP + 0.79, spots[i].y)
		stool.name = "Stool%d" % i
	# A glass left on the bar, and the bar's last candle.
	_candle(Vector3(cx - 0.1, BAR_TOP, BAR_FROM + 0.25))


## The bottles: rows of the four kinds on every shelf, each row a MultiMesh, spaced unevenly.
func _line_the_bottles(levels: Array, x: float, length: float, mid: float) -> void:
	var club := (load(MODELS + "club.glb") as PackedScene).instantiate()
	var swaps := _swaps()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var per_kind: Array = [[], [], [], []]
	for y: float in levels:
		bottle_levels.append(y + 0.015)
		var z := mid - length * 0.5
		while z < mid + length * 0.5:
			var kind := rng.randi() % 4
			var spot := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x + rng.randf_range(-0.04, 0.04),
					y + 0.015, z))
			per_kind[kind].append(spot)
			bottle_spots.append(spot)
			z += rng.randf_range(0.09, 0.16)
	for kind in 4:
		var source := club.find_child("Bottle%d" % kind, true, false) as MeshInstance3D
		var mesh := source.mesh.duplicate() as ArrayMesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and swaps.has(m.resource_name):
				mesh.surface_set_material(s, swaps[m.resource_name])
		var rows := MultiMesh.new()
		rows.transform_format = MultiMesh.TRANSFORM_3D
		rows.mesh = mesh
		rows.instance_count = per_kind[kind].size()
		for i in per_kind[kind].size():
			rows.set_instance_transform(i, per_kind[kind][i])
		var node := MultiMeshInstance3D.new()
		node.name = "Bottles%d" % kind
		node.multimesh = rows
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	club.free()


# --- the booths ------------------------------------------------------------------------------

## Each booth: two benches facing across a marble table against the wall, a candle on it.
func _build_the_booths() -> void:
	var half := live_room_half()
	var club := load(MODELS + "club.glb") as PackedScene
	var x := -half + BENCH * 0.5
	for i in BOOTHS.size():
		var z: float = BOOTHS[i]
		for side in [-1.0, 1.0]:
			var bench := _piece(club, "Banquette")
			bench.name = "Bench%d%s" % [i, "a" if side < 0.0 else "b"]
			# The model's seat faces +Z and its back is 0.34 behind the seat front... at -Z.
			bench.position = Vector3(x, 0, z + side * (BENCH_GAP + 0.25))
			bench.rotation.y = 0.0 if side < 0.0 else PI
		var table := _piece(club, "Table")
		table.name = "BoothTable%d" % i
		table.position = Vector3(x, 0, z)
		_candle(Vector3(x + 0.12, 0.74, z + 0.05))
		# A low pendant over each booth, its shade a dark cone, its bulb warm.
		var shade := MeshInstance3D.new()
		shade.name = "BoothShade"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.2
		cone.height = 0.18
		cone.radial_segments = 20
		shade.mesh = cone
		shade.material_override = _brass()
		shade.position = Vector3(x, 1.75, z)
		add_child(shade)
		ZoneKit.block(self, Vector3(0.008, HEIGHT - 1.84, 0.008), Vector3(x, (HEIGHT + 1.84) * 0.5, z), _black(), "Cord")
		var pool := SpotLight3D.new()
		pool.name = "BoothLight"
		pool.light_color = Color(1.0, 0.7, 0.42)
		pool.light_energy = 1.4
		pool.spot_range = 2.4
		pool.spot_angle = 55.0
		pool.position = Vector3(x, 1.68, z)
		pool.rotation.x = -PI * 0.5
		add_child(pool)


## A candle in a short amber glass, and the small light it gives, which flickers (_process).
func _candle(at: Vector3) -> void:
	var glass := MeshInstance3D.new()
	glass.name = "Candle"
	var cup := CylinderMesh.new()
	cup.top_radius = 0.035
	cup.bottom_radius = 0.032
	cup.height = 0.08
	cup.radial_segments = 14
	glass.mesh = cup
	glass.material_override = _bottle_glass(Color(0.75, 0.38, 0.1, 0.6))
	glass.position = at + Vector3(0, 0.04, 0)
	add_child(glass)
	var flame := ZoneKit.block(self, Vector3(0.012, 0.025, 0.012), at + Vector3(0, 0.07, 0), ZoneKit.glow(Color(1.0, 0.7, 0.3), 3.0),
			"Flame")
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "CandleLight"
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 0.35
	light.omni_range = 1.4
	light.position = at + Vector3(0, 0.15, 0)
	add_child(light)
	candles.append(light)


# --- the stage -------------------------------------------------------------------------------

## The velvet behind the stage, drawn the whole width of the back wall.
func _hang_the_curtain() -> void:
	var half := live_room_half()
	var stage: AABB = zones()[&"drums"]
	var x0 := -half + 0.05
	var x1 := half - 0.05
	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain"
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(x1 - x0, HEIGHT - 0.12)
	plane.subdivide_width = int((x1 - x0) * 24.0)
	curtain.mesh = plane
	var velvet := ShaderMaterial.new()
	velvet.shader = preload("res://core/venues/shaders/curtain.gdshader")
	curtain.material_override = velvet
	curtain.position = Vector3((x0 + x1) * 0.5, (HEIGHT - 0.12) * 0.5 + 0.02, LIVE_ROOM_BACK - 0.14)
	# The plane faces +Z; turned round to face the room.
	curtain.rotation.y = PI
	add_child(curtain)
	# Up-lights at its foot, behind the riser: the velvet glowing from below in long folds.
	for i in 5:
		var wash := SpotLight3D.new()
		wash.name = "CurtainWash"
		wash.light_color = Color(1.0, 0.45, 0.3)
		wash.light_energy = 2.2
		wash.spot_range = 4.6
		wash.spot_angle = 38.0
		wash.position = Vector3(x0 + (x1 - x0) * (i + 0.5) / 5.0, 0.08, LIVE_ROOM_BACK - 0.75)
		wash.basis = Basis.looking_at(Vector3(0, 1.0, 0.18), Vector3.FORWARD)
		add_child(wash)
	# The track it hangs from.
	ZoneKit.block(self, Vector3(x1 - x0 + 0.1, 0.05, 0.08), Vector3((x0 + x1) * 0.5, HEIGHT - 0.06, LIVE_ROOM_BACK - 0.14),
			_black(), "CurtainTrack")


## The one spot: a black can on a bar from the ceiling, aimed at the middle of the stage, its
## beam drawn in the haze.
func _hang_the_spot() -> void:
	var target := stage_centre()
	ZoneKit.block(self, Vector3(1.2, 0.05, 0.05), Vector3(SPOT_AT.x, HEIGHT - 0.12, SPOT_AT.z), _black(), "LightingBar")
	ZoneKit.block(self, Vector3(0.03, 0.14, 0.03), Vector3(SPOT_AT.x, HEIGHT - 0.2, SPOT_AT.z), _black(), "Yoke")
	var aim := Basis.looking_at(target - SPOT_AT, Vector3.UP)
	var can := MeshInstance3D.new()
	can.name = "SpotCan"
	var body := CylinderMesh.new()
	body.top_radius = 0.1
	body.bottom_radius = 0.12
	body.height = 0.36
	body.radial_segments = 20
	can.mesh = body
	can.material_override = _black()
	# The cylinder's axis is its Y; turn it to lie along the aim (-Z of `aim`).
	can.basis = aim * Basis(Vector3.RIGHT, -PI * 0.5)
	can.position = SPOT_AT
	add_child(can)
	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.86, 0.66)
	spot.light_energy = 14.0
	spot.spot_range = 9.0
	spot.spot_angle = 14.0
	spot.spot_angle_attenuation = 0.4
	spot.shadow_enabled = true
	spot.basis = aim
	spot.position = SPOT_AT + aim * Vector3(0, 0, -0.2)
	add_child(spot)
	# The beam: an open cone from the lens to the stage.
	var length := SPOT_AT.distance_to(target)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = length * tan(deg_to_rad(spot.spot_angle)) * 0.85
	cone.height = 1.0
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 32
	beam.mesh = cone
	var haze := ShaderMaterial.new()
	haze.shader = preload("res://core/venues/shaders/spot_beam.gdshader")
	beam.material_override = haze
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Narrow end (the cylinder's top, +Y) at the lamp, the wide end on the stage.
	beam.basis = aim * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1, length, 1))
	beam.position = SPOT_AT + (target - SPOT_AT) * 0.5
	add_child(beam)
	_raise_the_dust(target, cone.bottom_radius)


## Motes in the beam: put at random through the cone, each wandering round its own place in
## dust.gdshader, lit only while they are in the light.
func _raise_the_dust(target: Vector3, far_radius: float) -> void:
	var aim := (target - SPOT_AT).normalized()
	var reach := SPOT_AT.distance_to(target)
	var spread := (far_radius - 0.1) / reach
	var side := aim.cross(Vector3.UP).normalized()
	var up := side.cross(aim)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.014, 0.014)
	mm.mesh = quad
	mm.instance_count = MOTES
	for i in MOTES:
		var along := rng.randf_range(0.5, reach - 0.4)
		var r := (0.1 + along * spread) * 0.8 * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var at := SPOT_AT + aim * along + (side * cos(a) + up * sin(a)) * r
		motes.append(at)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var dust := MultiMeshInstance3D.new()
	dust.name = "Dust"
	dust.multimesh = mm
	var shine := ShaderMaterial.new()
	shine.shader = preload("res://core/venues/shaders/dust.gdshader")
	shine.set_shader_parameter("lamp", SPOT_AT)
	shine.set_shader_parameter("aim", aim)
	shine.set_shader_parameter("spread", spread)
	shine.set_shader_parameter("reach", reach)
	dust.material_override = shine
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bounds := AABB(motes[0], Vector3.ZERO)
	for at in motes:
		bounds = bounds.expand(at)
	dust.custom_aabb = bounds.grow(0.3)
	add_child(dust)


## "after hours" in pink neon on the front wall, over the view from the desk, and the glow it
## throws on the brick.
func _light_the_sign() -> void:
	var tube := StandardMaterial3D.new()
	tube.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tube.albedo_color = Color(3.2, 0.7, 1.8)
	var sign := _model("neon.glb", Vector3(0.6, 2.95, FRONT + 0.08), 0.0, {"tube": tube, "rail": _black()})
	sign.name = "Neon"
	var glow := OmniLight3D.new()
	glow.name = "NeonGlow"
	glow.light_color = Color(1.0, 0.3, 0.6)
	glow.light_energy = 0.8
	glow.omni_range = 2.4
	glow.position = Vector3(0.6, 3.0, FRONT + 0.5)
	add_child(glow)


# --- what was left behind -------------------------------------------------------------------

## The band's gone home: the upright against the booths, the double bass laid down by it,
## a coat thrown over a booth's bench and a hat left on the other one.
func _leave_the_instruments() -> void:
	var club := load(MODELS + "club.glb") as PackedScene
	var piano := _piece(club, "Piano")
	piano.name = "Piano"
	# The model's keys face +Z; turned to face the room (+X).
	piano.rotation.y = PI * 0.5
	piano.position = Vector3(piano_x(), 0, PIANO_Z)
	# A brass lamp on the piano's lid, left on, bent over the keys.
	var lamp_at := Vector3(piano_x() + 0.12, 1.25, PIANO_Z - 0.45)
	ZoneKit.block(self, Vector3(0.12, 0.015, 0.12), lamp_at + Vector3(0, 0.008, 0), _brass(), "PianoLampBase")
	ZoneKit.block(self, Vector3(0.012, 0.3, 0.012), lamp_at + Vector3(0, 0.16, 0), _brass(), "PianoLampStem")
	var shade := MeshInstance3D.new()
	shade.name = "PianoLampShade"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.035
	cone.bottom_radius = 0.09
	cone.height = 0.11
	cone.radial_segments = 18
	shade.mesh = cone
	shade.material_override = _brass()
	shade.position = lamp_at + Vector3(0.08, 0.31, 0)
	shade.rotation.z = -0.6
	add_child(shade)
	var lamp := SpotLight3D.new()
	lamp.name = "PianoLamp"
	lamp.light_color = Color(1.0, 0.72, 0.45)
	lamp.light_energy = 1.6
	lamp.spot_range = 3.0
	lamp.spot_angle = 60.0
	lamp.position = shade.position + Vector3(0.03, -0.04, 0)
	lamp.basis = Basis.looking_at(Vector3(0.75, -1.0, 0.25), Vector3.UP)
	add_child(lamp)
	var bass := _piece(club, "Bass")
	bass.name = "Bass"
	# Its scroll is the model's +X end: laid along the piano's front toward the door, belly to the room.
	bass.rotation.y = BASS_YAW
	bass.position = bass_at()
	var bench := find_child("Bench1a", false, false) as Node3D
	var coat := _piece(club, "Coat")
	coat.name = "Coat"
	coat.transform = bench.transform
	var hat := _piece(club, "Hat")
	hat.name = "Hat"
	hat.transform = bench.transform * Transform3D(Basis(Vector3.UP, 0.7), Vector3(-0.38, 0.34, 0.04))


## Glasses no one cleared: two on each booth table, a couple on the bar.
func _leave_the_glasses() -> void:
	var club := load(MODELS + "club.glb") as PackedScene
	var x := -live_room_half() + BENCH * 0.5
	var cx := bar_front() + COUNTER_DEPTH * 0.5
	var left := [[0, Vector3(x - 0.12, 0.74, BOOTHS[0] - 0.14)], [1, Vector3(x + 0.16, 0.74, BOOTHS[0] + 0.12)],
			[2, Vector3(x - 0.08, 0.74, BOOTHS[1] + 0.15)], [0, Vector3(x + 0.1, 0.74, BOOTHS[1] - 0.16)],
			[0, Vector3(cx - 0.12, BAR_TOP, BAR_FROM + 0.6)], [2, Vector3(cx - 0.15, BAR_TOP, 0.4)]]
	for spec in left:
		var glass := _piece(club, "Glass%d" % spec[0])
		glass.name = "LeftGlass%d" % glass_spots.size()
		glass.position = spec[1]
		glass.rotation.y = glass_spots.size() * 1.3
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass_spots.append(spec[1])


# --- the zones -------------------------------------------------------------------------------

## The zones: the stage is the drum riser, walnut on black; the booth framed in black; a brass
## square on the floor for the lattice; a walnut table; the keys.
func _dress_zones() -> void:
	var z := zones()
	var walnut := _walnut()
	var black := _black()

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var riser := Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, riser, ZoneKit.RISER_HEIGHT, walnut, black)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := _bottle_glass(Color(0.4, 0.4, 0.4, 0.08))
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, black, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.75, 0.5),
			1.1, 60.0, 3.2, black)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.03, _brass())

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, walnut, black)
	_dress_prop_shelf(walnut, black)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, Materials.brushed_metal(), black)


## One named piece from club.glb, its materials swapped for the club's own.
func _piece(scene: PackedScene, piece: String) -> Node3D:
	var all := scene.instantiate()
	var node := all.find_child(piece, true, false) as MeshInstance3D
	node.get_parent().remove_child(node)
	all.free()
	node.transform = Transform3D.IDENTITY
	var swaps := _swaps()
	for s in node.mesh.get_surface_count():
		var m := node.mesh.surface_get_material(s)
		if m != null and swaps.has(m.resource_name):
			node.set_surface_override_material(s, swaps[m.resource_name])
	add_child(node)
	return node


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
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _walnut())
