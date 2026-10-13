class_name RooftopVenue
extends Venue

## A roof terrace at dusk, high over a city: a deck of hardwood boards inside a brick parapet,
## an iron railing along the front where the view is, and the sky a quarter of an hour after the
## sun went down behind the towers in front. Past the terrace the rest of the roof: the stair
## house with its lamp over the door, two wooden water tanks on their steel legs, the plant. And
## under all of it the city, its windows coming on.
##
## Lit by what is strung over it: festoons of bulbs zig-zagging between poles at the parapet,
## each string throwing a little warm light down, and the last of the day from the west. The
## zones stand on the deck at the back, open to the sky, the booth a glass box of its own.

## The terrace's boards stand on pedestals over the roof's membrane: this much proud of it.
const DECK_LIFT := 0.18
## The parapet round the terrace, brick, to a little over hip height, with a stone coping on it.
const PARAPET := 1.05
const WALL := 0.3
## Where the front railing stands: the footprint's front edge, which is the building's edge too.
const FRONT := Studio.ROOM_FRONT
## How far the rest of the roof reaches past the terrace's sides and its back.
const ROOF_SIDE := 9.0
const ROOF_BACK := 9.0
## How far down the street is. Most of the city's roofs are under you; the tall ones are not.
const STOREYS_DOWN := 40.0
## The festoon poles' height, and how much a string sags between two of them. The lowest bulb
## hangs above every zone's head room (Venue.ZONES): the lattice's 3.4 m stands under them.
const POLE := 4.1
const SAG := 0.45
## Where the strings cross, front to back (z at the left pole, z at the right): straight across
## over the desk, then zig-zagging over the zones.
const STRINGS := [Vector2(-1.4, -1.4), Vector2(1.2, 1.2), Vector2(3.0, 4.6), Vector2(6.6, 3.0),
		Vector2(6.6, 6.6)]
## The stair house on the roof behind the terrace: x, and how far past the back parapet.
const STAIR_HOUSE := Vector2(2.4, 2.6)
## The skylight over the stairwell's landing, on the roof to the left of the terrace (x past
## the parapet, z), and the mushroom vents dotted about (x past the nearer side parapet, z).
const SKYLIGHT := Vector2(-3.2, -0.6)
const VENTS := [Vector2(-1.6, 7.6), Vector2(-6.6, -0.2), Vector2(-2.4, 1.8), Vector2(2.0, 6.4),
		Vector2(1.4, -1.0), Vector2(7.0, 7.4)]
## The tanks, on the roof either side of the terrace: how far out past the side parapet (its
## sign is the side), z, and the yaw that turns its ladder toward the terrace.
const TANKS := [Vector3(-4.6, 4.3, 0.6), Vector3(5.2, 1.4, -0.4)]

const MODELS := "res://assets/models/"

## The arrangements (Venue.VARIANTS): the same roof at three times of the evening. The terrace
## is the same; the sky, the light off it and how many of the city's windows are lit are not.
const DUSK := 0
const GOLDEN := 1
const NIGHT := 2
## Per time of evening: the sky's bands (zenith, upper, rose, horizon, haze), where the sun is,
## its disc, the stars; the light from everywhere (colour, energy); the haze over the city; the
## key (colour, energy, pitch); and how bright the city's windows are.
const EVENINGS := [
	{"sky": [Color(0.03, 0.04, 0.12), Color(0.16, 0.12, 0.3), Color(0.55, 0.24, 0.32), Color(1.0, 0.48, 0.2),
			Color(0.16, 0.09, 0.1)], "sun": Vector3(0.0, -0.06, -1.0), "disc": 0.0, "stars": 1.0,
			"ambient": [Color(0.5, 0.44, 0.66), 0.16], "fog": Color(0.17, 0.11, 0.13),
			"key": [Color(1.0, 0.56, 0.42), 0.3, -7.0], "windows": 0.8},
	# The sun a hand over the towers in front: it lays the railing's shadow down the deck.
	{"sky": [Color(0.13, 0.19, 0.34), Color(0.29, 0.3, 0.42), Color(0.6, 0.42, 0.33), Color(0.92, 0.56, 0.27),
			Color(0.26, 0.17, 0.14)], "sun": Vector3(0.27, 0.16, -1.0), "disc": 0.03, "stars": 0.0,
			"ambient": [Color(0.72, 0.6, 0.52), 0.17], "fog": Color(0.42, 0.3, 0.22),
			"key": [Color(1.0, 0.7, 0.44), 1.45, -9.0], "windows": 0.35},
	# The sky gone dark: only a little of the city's light comes back off the haze.
	{"sky": [Color(0.006, 0.008, 0.022), Color(0.014, 0.018, 0.045), Color(0.04, 0.035, 0.06),
			Color(0.11, 0.07, 0.07), Color(0.06, 0.04, 0.045)], "sun": Vector3(0.0, -0.4, -1.0), "disc": 0.0,
			"stars": 2.0, "ambient": [Color(0.35, 0.38, 0.55), 0.08], "fog": Color(0.045, 0.035, 0.05),
			"key": [Color(0.6, 0.7, 1.0), 0.14, -40.0], "windows": 1.1},
]

## At night the strings are all the terrace has, and are turned up this much.
const NIGHT_STRINGS := 1.5
## The tanks' aircraft lights: on this long, once in this long.
const BEACON_ON := 0.3
const BEACON_EVERY := 1.6

var _sky_mat: ShaderMaterial
var _city_mat: ShaderMaterial
## The red lights on the tanks' finials, which blink.
var beacons: Array[MeshInstance3D] = []
var _clock := 0.0


func venue_id() -> StringName:
	return &"rooftop"


## Nothing to hang the roll board on: it stands.
func roll_board_free_standing() -> bool:
	return true


## Weathered flight cases: sun-greyed ply, aluminium extrusion and a sodium-orange edge from the
## street lights below.
func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.scan("wood_planks_grey", 0.8, Color(0.62, 0.6, 0.58))) \
			.with("brushed", GearStyle.metal(Color(0.66, 0.67, 0.68), 0.3)) \
			.with("trim", GearStyle.glow(Color(1.0, 0.55, 0.18), 1.2)) \
			.with("end_cheek", GearStyle.scan("wood_planks_grey", 0.6, Color(0.5, 0.48, 0.46)))


func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/dusk_sky.gdshader")
	var evening: Dictionary = EVENINGS[variant]
	for i in 5:
		_sky_mat.set_shader_parameter(["zenith", "upper", "rose", "horizon", "haze"][i], evening["sky"][i])
	_sky_mat.set_shader_parameter("sun_dir", evening["sun"])
	_sky_mat.set_shader_parameter("sun_radius", evening["disc"])
	_sky_mat.set_shader_parameter("stars", evening["stars"])
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# What is left of the day comes from everywhere at once; the rest is the strings.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = evening["ambient"][0]
	env.ambient_light_energy = evening["ambient"][1]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	# The haze over the city: the far towers go into the evening's colour.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = evening["fog"]
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 420.0
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.1

	# From in front, where the sun is or went: low and warm, long shadows off the railing; at
	# night the moon, high and faint.
	key.light_color = evening["key"][0]
	key.light_energy = evening["key"][1]
	key.rotation_degrees = Vector3(evening["key"][2], 195.0, 0.0)
	key.light_specular = 0.15


func lamp_colour(_index: int, authored: Color) -> Color:
	# The same warm filament as the festoons over them.
	return authored.lerp(Color(1.0, 0.68, 0.4), 0.4)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * 0.85


## The terrace is one open floor: the deck either side of the desk joins the far end.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## The festoon poles, at the parapet's inside face on both sides: where each string ends.
func pole_spots() -> Array[Vector2]:
	var x := live_room_half() - 0.12
	var out: Array[Vector2] = []
	for s: Vector2 in STRINGS:
		for spot in [Vector2(-x, s.x), Vector2(x, s.y)]:
			if not out.has(spot):
				out.append(spot)
	return out


## Where the stair house and each tank stand, in studio space.
func stair_house_spot() -> Vector2:
	return Vector2(STAIR_HOUSE.x, LIVE_ROOM_BACK + WALL + STAIR_HOUSE.y)


func skylight_spot() -> Vector2:
	return _past_parapet(SKYLIGHT)


func vent_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v: Vector2 in VENTS:
		out.append(_past_parapet(v))
	return out


## `at`.x measured out from the side parapet's outside face on its sign's side.
func _past_parapet(at: Vector2) -> Vector2:
	return Vector2(signf(at.x) * (live_room_half() + WALL) + at.x, at.y)


func tank_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t: Vector3 in TANKS:
		out.append(Vector2(signf(t.x) * (live_room_half() + WALL) + t.x, t.y))
	return out


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	for p in pole_spots():
		out.append({"c": p, "h": Vector2(0.06, 0.06), "a": 0.0, "top": POLE})
	for p in _planter_spots():
		out.append({"c": p, "h": Vector2(0.3, 0.3), "a": 0.0, "top": 0.55})
	return out


## Every bulb on every string, in studio space: each string is a catenary-ish sag between its two
## poles, a bulb every half metre or so.
func bulbs() -> Array[Vector3]:
	var x := live_room_half() - 0.12
	var out: Array[Vector3] = []
	for s: Vector2 in STRINGS:
		var a := Vector3(-x, POLE - 0.06, s.x)
		var b := Vector3(x, POLE - 0.06, s.y)
		var count := int(a.distance_to(b) / 0.5)
		for i in count:
			var t := (i + 0.5) / count
			out.append(a.lerp(b, t) - Vector3(0, SAG * 4.0 * t * (1.0 - t) + 0.05, 0))
	return out


func _ready() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + 0.2, back - FRONT + 0.2)
	deck.mesh = plane
	deck.position.z = (back + FRONT) * 0.5
	# Hardwood decking left to the weather: silver-grey, its grain open, warm only where the
	# strings light it.
	deck.material_override = Materials.scanned(StandardMaterial3D.new(), "wood_planks_grey", "2k", 2.0,
			Color(0.9, 0.88, 0.86))
	add_child(deck)

	var brick := Materials.cached_scanned("rooftop_brick", "red_brick_03", "2k", 1.2, Color(0.5, 0.4, 0.38))
	var steel := _steel()
	_lay_the_roof(brick)
	_build_parapet(brick, steel)
	_build_stair_house(brick, steel)
	_raise_tanks(steel)
	_put_in_plant(steel)
	_dot_the_roof(steel)
	_plant_planters()
	_string_the_lights(steel)
	_raise_city()
	_dress_zones()


func _steel() -> StandardMaterial3D:
	var steel := StandardMaterial3D.new()
	# Black-painted iron, as railings are: a little sheen where the paint is newer.
	steel.albedo_color = Color(0.04, 0.042, 0.045)
	steel.metallic = 0.5
	steel.roughness = 0.5
	return steel


func _coping() -> StandardMaterial3D:
	var stone := Materials.cached_scanned("rooftop_coping", "concrete_floor_worn_001", "2k", 0.6,
			Color(0.62, 0.6, 0.58))
	return stone


# --- the roof -------------------------------------------------------------------------------

## The roof round the terrace, its membrane a little under the deck, and the building's face
## going down from its front edge to the street: what you see if you look over the railing.
func _lay_the_roof(brick: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var wide := (half + ROOF_SIDE) * 2.0
	var deep := back + ROOF_BACK - FRONT
	# Ballast: grey gravel spread over the membrane to hold it down.
	var membrane := Materials.scanned(StandardMaterial3D.new(), "gravel", "1k", 1.6, Color(0.8, 0.8, 0.82))
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var plane := PlaneMesh.new()
	plane.size = Vector2(wide, deep)
	roof.mesh = plane
	roof.position = Vector3(0, -DECK_LIFT, FRONT + deep * 0.5)
	roof.material_override = membrane
	add_child(roof)
	# The building under it, its top a hair under the membrane so the two never meet in a plane.
	var face := ZoneKit.block(self, Vector3(wide, STOREYS_DOWN, deep), Vector3(0, -DECK_LIFT - 0.004
			- STOREYS_DOWN * 0.5, FRONT + deep * 0.5), brick, "Building")
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The rest of the roof's own parapet, round its edge past the terrace.
	# A hand lower than the terrace's, so its top never meets the terrace's coping.
	var low := PARAPET + DECK_LIFT - 0.1
	var y := -DECK_LIFT + low * 0.5
	var outer_x := half + ROOF_SIDE - WALL * 0.5
	var outer_z := back + ROOF_BACK - WALL * 0.5
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, low, deep), Vector3(side * outer_x, y, FRONT + deep * 0.5), brick,
				"RoofParapet")
		# The front, either side of the terrace's railing.
		var span := ROOF_SIDE - WALL * 2.0 - 0.004
		ZoneKit.block(self, Vector3(span, low, WALL - 0.004), Vector3(side * (half + WALL + 0.002 + span * 0.5), y,
				FRONT - WALL * 0.5 + 0.002), brick, "RoofParapet")
	ZoneKit.block(self, Vector3(wide - WALL * 2.0, low, WALL - 0.004), Vector3(0, y, outer_z), brick,
			"RoofParapet")


## Brick to hip height round the terrace's sides and back, coped in stone; along the front, where
## the view is, an iron railing on a low kerb, so the city is seen through it from the desk.
func _build_parapet(brick: Material, steel: Material) -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var coping := _coping()
	var outside := half + WALL * 0.5
	# The sides take the corners, front and back.
	var run := back + WALL - FRONT + WALL
	var mid := (back + WALL + FRONT - WALL) * 0.5
	# Down to the membrane, so there is no gap under the deck's edge.
	var tall := PARAPET + DECK_LIFT
	var y := -DECK_LIFT + tall * 0.5
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, tall, run), Vector3(side * outside, y, mid), brick, "Parapet")
		ZoneKit.block(self, Vector3(WALL + 0.06, 0.06, run + 0.06), Vector3(side * outside, PARAPET + 0.03, mid),
				coping, "Coping")
	# The back runs between the sides, its coping a hair lower so the corners do not fight.
	ZoneKit.block(self, Vector3(half * 2.0 - 0.004, tall, WALL), Vector3(0, y, back + WALL * 0.5), brick, "Parapet")
	ZoneKit.block(self, Vector3(half * 2.0 - 0.064, 0.058, WALL + 0.06), Vector3(0, PARAPET + 0.029,
			back + WALL * 0.5), coping, "Coping")
	# The front: a kerb, then iron. Posts every metre and a half, a top rail, a mid rail, and
	# thin balusters between, as one MultiMesh.
	var kerb := 0.22
	ZoneKit.block(self, Vector3(half * 2.0 - 0.004, kerb + DECK_LIFT, WALL), Vector3(0, (kerb - DECK_LIFT) * 0.5,
			FRONT - WALL * 0.5), brick, "Kerb")
	ZoneKit.block(self, Vector3(half * 2.0 - 0.008, 0.05, WALL + 0.06), Vector3(0, kerb + 0.025,
			FRONT - WALL * 0.5), coping, "KerbCoping")
	var rail_z := FRONT - WALL * 0.5
	var top := PARAPET + 0.05
	ZoneKit.block(self, Vector3(half * 2.0, 0.05, 0.07), Vector3(0, top, rail_z), steel, "TopRail")
	ZoneKit.block(self, Vector3(half * 2.0, 0.03, 0.03), Vector3(0, kerb + 0.16, rail_z), steel, "BottomRail")
	var bars := MultiMesh.new()
	bars.transform_format = MultiMesh.TRANSFORM_3D
	var bar := BoxMesh.new()
	bar.size = Vector3(0.018, top - kerb - 0.05 - 0.025, 0.018)
	bars.mesh = bar
	var spacing := 0.12
	var count := int(half * 2.0 / spacing)
	bars.instance_count = count
	for i in count:
		var x := -half + spacing * (i + 0.5)
		# Every twelfth a post: heavier.
		var basis := Basis.from_scale(Vector3(3.0, 1.0, 3.0)) if i % 12 == 6 else Basis()
		bars.set_instance_transform(i, Transform3D(basis, Vector3(x, (kerb + 0.05 + top - 0.025) * 0.5, rail_z)))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Balusters"
	holder.multimesh = bars
	holder.material_override = steel
	add_child(holder)


## The stair house behind the terrace: a brick box with a flat lid, a steel door facing the
## terrace, and a caged bulkhead lamp over the door -- the one light on the roof not on a string.
func _build_stair_house(brick: Material, steel: Material) -> void:
	var at := stair_house_spot()
	var size := Vector3(2.6, 3.0, 3.2)
	var base := -DECK_LIFT
	ZoneKit.block(self, size, Vector3(at.x, base + size.y * 0.5, at.y), brick, "StairHouse")
	ZoneKit.block(self, Vector3(size.x + 0.16, 0.1, size.z + 0.16), Vector3(at.x, base + size.y + 0.05, at.y),
			_coping(), "StairHouseLid")
	var door_z := at.y - size.z * 0.5
	ZoneKit.block(self, Vector3(1.0, 2.1, 0.06), Vector3(at.x, base + 1.05, door_z - 0.03), steel, "Door")
	var lamp_at := Vector3(at.x, base + 2.4, door_z - 0.1)
	ZoneKit.block(self, Vector3(0.16, 0.12, 0.1), lamp_at, ZoneKit.glow(Color(1.0, 0.74, 0.46), 2.0), "Bulkhead")
	var wash := ZoneKit.spot_down(self, lamp_at + Vector3(0, -0.08, -0.04), Color(1.0, 0.72, 0.46), 2.4, 70.0, 4.5)
	wash.name = "DoorLamp"
	# Wired glass in the door's top half, the stairwell lit behind it. Proud of the door's face
	# and sunk into the brick behind, so it shares a plane with neither.
	ZoneKit.block(self, Vector3(0.42, 0.55, 0.07), Vector3(at.x, base + 1.6, door_z - 0.03),
			ZoneKit.glow(Color(1.0, 0.82, 0.55), 0.9), "DoorWindow")


## The tanks (assets/models/water_tank.glb): cedar staves gone grey, black iron, a tarred cap.
func _raise_tanks(steel: Material) -> void:
	var staves := Materials.cached_scanned("rooftop_staves", "weathered_brown_planks", "2k", 1.0,
			Color(0.55, 0.47, 0.42))
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.06, 0.06, 0.065)
	cap.roughness = 0.8
	var spots := tank_spots()
	for i in spots.size():
		var t: Vector3 = TANKS[i]
		var tank := _model("water_tank.glb", Vector3(spots[i].x, -DECK_LIFT, spots[i].y), t.z,
				{"staves": staves, "steel": steel, "cap": cap})
		tank.name = "WaterTank%d" % i
		# A red light on the finial, for the helicopters: tanks are the tallest thing up here.
		var beacon := MeshInstance3D.new()
		beacon.name = "Beacon%d" % i
		var bulb := SphereMesh.new()
		bulb.radius = 0.07
		bulb.height = 0.14
		bulb.radial_segments = 10
		bulb.rings = 5
		beacon.mesh = bulb
		beacon.material_override = ZoneKit.glow(Color(1.0, 0.08, 0.05), 3.0)
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beacon.position = Vector3(spots[i].x, -DECK_LIFT + 6.6 + 0.05, spots[i].y)
		add_child(beacon)
		beacons.append(beacon)


func _process(delta: float) -> void:
	_clock += delta
	# Both together, the way the pair on one roof are wired.
	var lit := fmod(_clock, BEACON_EVERY) < BEACON_ON
	for b in beacons:
		b.visible = lit


## The building's plant on the far side of the roof: two condenser units and a run of duct.
func _put_in_plant(steel: Material) -> void:
	var half := live_room_half()
	var casing := StandardMaterial3D.new()
	casing.albedo_color = Color(0.36, 0.37, 0.38)
	casing.metallic = 0.4
	casing.roughness = 0.6
	for i in 2:
		var at := Vector3(half + WALL + 2.4 + i * 1.6, -DECK_LIFT, LIVE_ROOM_BACK + 4.6)
		ZoneKit.block(self, Vector3(1.2, 1.1, 1.2), at + Vector3(0, 0.55, 0), casing, "Condenser")
		ZoneKit.block(self, Vector3(0.9, 0.02, 0.9), at + Vector3(0, 1.11, 0), steel, "FanGrille")
	ZoneKit.block(self, Vector3(0.5, 0.5, 6.0), Vector3(half + WALL + 4.8, -DECK_LIFT + 0.25, LIVE_ROOM_BACK + 1.0),
			casing, "Duct")


## A glazed skylight on a brick curb, lit from the landing under it, and mushroom vents.
func _dot_the_roof(steel: Material) -> void:
	var sky := skylight_spot()
	var curb := Vector3(2.2, 0.4, 1.6)
	var base := -DECK_LIFT
	ZoneKit.block(self, curb, Vector3(sky.x, base + curb.y * 0.5, sky.y), steel, "SkylightCurb")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.3, 0.32)
	glass.roughness = 0.15
	glass.metallic_specular = 0.8
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.78, 0.5)
	glass.emission_energy_multiplier = 0.16
	# A hipped roof of glass: a four-sided cone squashed to the curb's plan.
	var hip := CylinderMesh.new()
	hip.top_radius = 0.02
	hip.bottom_radius = 0.7071
	hip.height = 0.5
	hip.radial_segments = 4
	hip.rings = 1
	var pane := MeshInstance3D.new()
	pane.name = "Skylight"
	pane.mesh = hip
	pane.material_override = glass
	pane.basis = Basis.from_scale(Vector3(curb.x - 0.08, 1.0, curb.z - 0.08)) * Basis(Vector3.UP, PI * 0.25)
	pane.position = Vector3(sky.x, base + curb.y + 0.25, sky.y)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pane)
	var galvanised := StandardMaterial3D.new()
	galvanised.albedo_color = Color(0.42, 0.43, 0.44)
	galvanised.metallic = 0.7
	galvanised.roughness = 0.45
	for v in vent_spots():
		var stem := CylinderMesh.new()
		stem.top_radius = 0.09
		stem.bottom_radius = 0.09
		stem.height = 0.6
		stem.radial_segments = 12
		var pipe := MeshInstance3D.new()
		pipe.name = "Vent"
		pipe.mesh = stem
		pipe.material_override = galvanised
		pipe.position = Vector3(v.x, base + 0.3, v.y)
		add_child(pipe)
		var hood := CylinderMesh.new()
		hood.top_radius = 0.04
		hood.bottom_radius = 0.2
		hood.height = 0.14
		hood.radial_segments = 12
		var cap := MeshInstance3D.new()
		cap.name = "VentCap"
		cap.mesh = hood
		cap.material_override = galvanised
		cap.position = Vector3(v.x, base + 0.67, v.y)
		add_child(cap)


## Planters of cedar along the parapets beside the desk, with low clipped shrubs in them.
func _planter_spots() -> Array[Vector2]:
	var x := live_room_half() - 0.34
	return [Vector2(-x, -0.2), Vector2(-x, 2.4), Vector2(x, -0.2), Vector2(x, 2.4)]


func _plant_planters() -> void:
	var cedar := Materials.cached_scanned("rooftop_cedar", "weathered_brown_planks", "2k", 0.5,
			Color(0.62, 0.45, 0.34))
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.1, 0.16, 0.08)
	leaves.roughness = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for p in _planter_spots():
		ZoneKit.block(self, Vector3(0.56, 0.5, 0.56), Vector3(p.x, 0.25, p.y), cedar, "Planter")
		for k in 3:
			var bush := MeshInstance3D.new()
			bush.name = "Shrub"
			var ball := SphereMesh.new()
			ball.radius = rng.randf_range(0.16, 0.22)
			ball.height = ball.radius * 1.6
			ball.radial_segments = 10
			ball.rings = 6
			bush.mesh = ball
			bush.material_override = leaves
			bush.position = Vector3(p.x + rng.randf_range(-0.1, 0.1), 0.56 + ball.radius * 0.4,
					p.y + rng.randf_range(-0.1, 0.1))
			add_child(bush)


# --- the lights -----------------------------------------------------------------------------

## Steel poles at the parapet and the strings between them: the bulbs one MultiMesh, the wire a
## thin box from bulb to bulb, and under each string two soft lights where its bulbs hang
## thickest. All the terrace's light, apart from the stair house's lamp and the desk's own.
func _string_the_lights(steel: Material) -> void:
	for p in pole_spots():
		ZoneKit.block(self, Vector3(0.06, POLE, 0.06), Vector3(p.x, POLE * 0.5, p.y), steel, "Pole")
	var all := bulbs()
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.075
	bulb.radial_segments = 10
	bulb.rings = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = all.size()
	for i in all.size():
		mm.set_instance_transform(i, Transform3D(Basis(), all[i]))
	var holder := MultiMeshInstance3D.new()
	holder.name = "Festoons"
	holder.multimesh = mm
	var up := NIGHT_STRINGS if variant == NIGHT else 1.0
	holder.material_override = ZoneKit.glow(Color(1.0, 0.72, 0.4), 1.6 * up)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)
	# The wire: from each bulb's cap to the next, and from the end ones to the poles.
	var x := live_room_half() - 0.12
	var wires: Array[Transform3D] = []
	var at := 0
	for s: Vector2 in STRINGS:
		var points: Array[Vector3] = [Vector3(-x, POLE - 0.06, s.x)]
		var a := Vector3(-x, POLE - 0.06, s.x)
		var b := Vector3(x, POLE - 0.06, s.y)
		var count := int(a.distance_to(b) / 0.5)
		for i in count:
			points.append(all[at + i] + Vector3(0, 0.04, 0))
		at += count
		points.append(b)
		for i in points.size() - 1:
			var from := points[i]
			var to := points[i + 1]
			var length := from.distance_to(to)
			var look := Basis.looking_at(to - from, Vector3.UP) * Basis.from_scale(Vector3(1, 1, length))
			wires.append(Transform3D(look, (from + to) * 0.5))
		# Two soft lights down from the string, a third of the way from each end.
		for t in [0.3, 0.7]:
			var over := a.lerp(b, t) - Vector3(0, SAG * 4.0 * t * (1.0 - t) + 0.1, 0)
			var glow := ZoneKit.spot_down(self, over, Color(1.0, 0.7, 0.42), 2.2 * up, 72.0, 6.0)
			glow.name = "StringLight"
	var wire := BoxMesh.new()
	wire.size = Vector3(0.008, 0.008, 1.0)
	var wm := MultiMesh.new()
	wm.transform_format = MultiMesh.TRANSFORM_3D
	wm.mesh = wire
	wm.instance_count = wires.size()
	for i in wires.size():
		wm.set_instance_transform(i, wires[i])
	var strung := MultiMeshInstance3D.new()
	strung.name = "Wire"
	strung.multimesh = wm
	strung.material_override = steel
	strung.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strung)


## The city, forty storeys down and all round: dark slabs going violet in the dusk, their windows
## coming on warm, the odd one cold. The tall ones stand over the roof; most are under it. One
## MultiMesh, one draw.
func _raise_city() -> void:
	_city_mat = ShaderMaterial.new()
	_city_mat.shader = preload("res://core/venues/shaders/tower.gdshader")
	_city_mat.set_shader_parameter("roof_from_custom", true)
	_city_mat.set_shader_parameter("body", Color(0.035, 0.032, 0.05))
	_city_mat.set_shader_parameter("lit_a", Color(1.0, 0.7, 0.4))
	_city_mat.set_shader_parameter("lit_b", Color(0.09, 0.08, 0.1))
	_city_mat.set_shader_parameter("lit_c", Color(0.42, 0.48, 0.6))
	_city_mat.set_shader_parameter("energy", EVENINGS[variant]["windows"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var towers: Array[Transform3D] = []
	var roofs: Array[float] = []
	var cell := 16.0
	var half := live_room_half()
	var keep_clear := Rect2(-half - ROOF_SIDE - 10.0, FRONT - 10.0, (half + ROOF_SIDE) * 2.0 + 20.0,
			LIVE_ROOM_BACK + ROOF_BACK - FRONT + 20.0)
	for gx in range(-16, 17):
		for gz in range(-16, 10):
			var at := Vector2(gx * cell, gz * cell)
			if keep_clear.grow(cell * 0.5).has_point(at) or rng.randf() < 0.18:
				continue
			var w := rng.randf_range(8.0, 13.0)
			var d := rng.randf_range(8.0, 13.0)
			# Near, the roofs are under this one -- the view is over them to the sunset -- and the
			# towers that stand over it are further off, more of them the further you look.
			var far := at.length() / (cell * 16.0)
			var h := rng.randf_range(12.0, 34.0) * lerpf(0.8, 1.2, far)
			# None of the tall ones stands in the way of the sunset, straight out over the railing.
			var into_sunset := absf(atan2(at.x, -at.y)) < 0.5 and at.y < 0.0
			if far > 0.4 and not into_sunset and rng.randf() < far * 0.3:
				h += rng.randf_range(10.0, 45.0)
			var foot := -DECK_LIFT - STOREYS_DOWN
			towers.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), Vector3(at.x + rng.randf_range(-1.0, 1.0),
					foot + h * 0.5, at.y + rng.randf_range(-1.0, 1.0))))
			roofs.append(foot + h)
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


# --- the zones ------------------------------------------------------------------------------

## The zones out on the deck: a riser decked in the terrace's boards, a booth of glass in a black
## iron frame, the lattice's square chalked on the deck, a teak table, and the keys against the
## parapet. Lit by the strings over them; only the booth, which has a lid, has a light inside.
func _dress_zones() -> void:
	var z := zones()
	var steel := _steel()
	var boards := Materials.cached_scanned("rooftop_riser", "wood_planks_grey", "2k", 0.8, Color(0.9, 0.88, 0.86))
	var skirt := StandardMaterial3D.new()
	skirt.albedo_color = Color(0.06, 0.055, 0.05)
	skirt.roughness = 0.85
	var teak := Materials.cached_scanned("rooftop_teak", "black_walnut_veneer_01", "2k", 0.8, Color(0.85, 0.66, 0.46))

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, boards, skirt)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.62, 0.7, 0.1)
	glass.roughness = 0.05
	glass.metallic_specular = 0.8
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, steel, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.68, 0.42),
			1.4, 60.0, 3.2, steel)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var chalk := StandardMaterial3D.new()
	chalk.albedo_color = Color(0.78, 0.76, 0.72)
	chalk.roughness = 0.9
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.05, chalk)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, teak, steel)
	_dress_prop_shelf(teak, steel)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, steel, teak)


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


## The mirror stands on the open deck at the footprint's left edge, framed in the railing's iron.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _steel())
