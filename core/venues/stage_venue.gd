class_name StageVenue
extends Venue

## A festival's main stage, with the studio set up on it: the desk stands on the stage deck and
## looks out over the front of the stage at the audience. Overhead a ground-support roof of box
## truss on four towers carries the lighting trusses, the moving heads on them and the PA, two
## line arrays flown left and right of the stage. Side-fills and road cases stand on the wings,
## wedges along the lip, a sub arc on the ground under it and a crowd barrier in front of that.
## Behind the zones -- the band's own back of house -- the backline, and behind that an LED wall
## the width of the stage; past it, backstage, more cases, black drapes and the stairs down.
##
## Three arrangements (Venue.VARIANTS):
##  - Headline night: a sea of people out to the trees, phones up, moving heads sweeping through
##    the haze, lasers fanning over the crowd, the LED wall going, everything on the beat.
##  - Soundcheck: late afternoon, an empty field, the front-of-house tent out in it, flags,
##    food stalls and a ferris wheel at the far side, crew cases on the stage, a clear sky.
##  - Arena: the same stage indoors at one end of an arena bowl: tiers of seats all round, a
##    rigging grid in the roof the trusses hang from, the house lights half down, a crowd on the
##    floor and in the stands, coloured washes.

const HEADLINE := 0
const SOUNDCHECK := 1
const ARENA := 2

## The stage deck is the floor (y = 0); the field is this far below it.
const DECK := 1.8
## The deck runs this far in front of the footprint, past either side of the live room, and
## behind the back of house.
const APRON := 1.6
const WING := 4.2
const BACKSTAGE := 4.6
## The ground-support roof's grid, and the lighting trusses under it, above the deck.
const ROOF := 11.0
const RIG := 7.6
## The LED wall behind the backline: how far behind the back of house, and its top.
const WALL_BEHIND := 1.0
const WALL_TOP := 7.0
const WALL_FOOT := 0.55
## The crowd barrier, in front of the stage's front edge.
const PIT := 2.6
## The arena (ARENA): the floor's half-width, how far out it runs in front of the stage, the
## radius of the bowl's corners, and its roof over the deck.
const ARENA_HALF := 26.0
const ARENA_FRONT := -64.0
const ARENA_CORNER := 16.0
const ARENA_ROOF := 30.0
## The bowl's two tiers: rows, each row's depth and rise.
const LOWER_ROWS := 14
const UPPER_ROWS := 16
const ROW_DEEP := 0.85
const LOWER_RISE := 0.42
const UPPER_RISE := 0.58
## The wall round the arena floor up to the first row, and the concourse between the tiers.
const DASHER := 2.4
const CONCOURSE := 3.0
const CONCOURSE_WALL := 3.4
## A truss length (tools/blender/stage_props.py).
const TRUSS := 2.0
const MODELS := "res://assets/models/"
## The moving heads' beams: how far they reach, and their spread.
const BEAM_REACH := 26.0
const BEAM_SPREAD := 5.0
## The ferris wheel out past the field: where, its radius, and one turn in this many seconds.
const WHEEL_AT := Vector3(70.0, 0.0, -125.0)
const WHEEL_RADIUS := 17.0
const WHEEL_TURN := 110.0

## Per arrangement: the beams' colours, the washes', the crowd's rim, and the LED wall's pair.
const LOOKS := [
	{"beams": [Color(1.0, 0.25, 0.75), Color(0.3, 0.55, 1.0), Color(0.95, 0.92, 1.0), Color(0.55, 0.2, 1.0)],
			"wash": [Color(0.75, 0.25, 1.0), Color(0.25, 0.45, 1.0)], "rim": Color(0.55, 0.32, 1.0),
			"wall": [Color(1.0, 0.1, 0.6), Color(0.15, 0.3, 1.0)]},
	{"beams": [Color(1.0, 0.95, 0.85)], "wash": [Color(1.0, 0.85, 0.65), Color(0.9, 0.9, 1.0)],
			"rim": Color(0.0, 0.0, 0.0), "wall": [Color(0.4, 0.4, 0.4), Color(0.4, 0.4, 0.4)]},
	{"beams": [Color(0.2, 0.35, 1.0), Color(1.0, 0.3, 0.12), Color(1.0, 0.7, 0.25), Color(0.15, 0.85, 0.8)],
			"wash": [Color(1.0, 0.45, 0.15), Color(0.25, 0.3, 1.0)], "rim": Color(1.0, 0.45, 0.2),
			"wall": [Color(1.0, 0.35, 0.05), Color(0.1, 0.25, 1.0)]},
]

## The moving heads, each a pan and a tilt node; where they rest; and their beams' materials.
var movers: Array[Dictionary] = []
var _beam_mats: Array[ShaderMaterial] = []
## Everything that pulses with the music.
var _led_mats: Array[ShaderMaterial] = []
var _crowd_mats: Array[ShaderMaterial] = []
var _washes: Array[Dictionary] = []
var _lip_mat: StandardMaterial3D
var _laser_mat: StandardMaterial3D
var _lasers: Array[Node3D] = []
var _wheel: Node3D
var _gondolas: Array[Node3D] = []
var _smoothed := 0.0
var _t := 0.0
## The instanced rig (assets/models/stage_props.glb), and meshes taken from it, by name.
var _kit: Node
var _meshes := {}
## Where the crowd stands, for the walker-free scenery checks and the phones.
var crowd_count := 0


func venue_id() -> StringName:
	return &"stage"


## No wall in front of the desk -- the audience is there -- and none at the side: the roll
## board and the roulette panel stand on posts of their own.
func back_wall_gear_stands() -> bool:
	return true


## Road-case gear: black tolex over ply, the truss's aluminium for the metal, and a blue LED
## edge the colour of a stage between cues; fluoro-pink gaffer round the looms and amber caps.
func gear_style() -> GearStyle:
	var tolex := GearStyle.paint(Color(0.065, 0.068, 0.078), 0.82, 0.0)
	tolex.normal_texture = Materials.grain("tolex", 1.6, 2.4)
	tolex.normal_scale = 0.8
	return GearStyle.new() \
			.with("furniture", tolex) \
			.with("chassis", GearStyle.paint(Color(0.075, 0.075, 0.085), 0.7, 0.25)) \
			.with("brushed", GearStyle.metal(Color(0.74, 0.75, 0.77), 0.28)) \
			.with("trim", GearStyle.glow(Color(0.22, 0.42, 1.0), 1.3)) \
			.with("end_cheek", GearStyle.metal(Color(0.6, 0.61, 0.63), 0.45)) \
			.with("lamp_shade", GearStyle.paint(Color(0.11, 0.115, 0.135), 0.45, 0.55)) \
			.with("loom_band", GearStyle.glow(Color(1.0, 0.18, 0.55), 1.05)) \
			.with("knob_cap", GearStyle.paint(Color(0.92, 0.48, 0.06), 0.38, 0.0))


## A road case's lid: black tolex, white stencil, fluoro-pink gaffer for the arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.paint(Color(0.07, 0.072, 0.085), 0.85, 0.0)
	board.ink = Color(0.96, 0.96, 0.94)
	board.accent = Color(1.0, 0.22, 0.6)
	board.board_ink_fade = Color(0.45, 0.45, 0.47)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_sky_affect = 0.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.1
	match variant:
		SOUNDCHECK:
			_sky(env, [Color(0.16, 0.32, 0.66), Color(0.32, 0.5, 0.8), Color(0.62, 0.66, 0.72),
					Color(0.92, 0.76, 0.55), Color(0.42, 0.4, 0.34)], Vector3(0.42, 0.2, -1.0), 0.024, 0.0, 0.62)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.62, 0.68, 0.82)
			env.ambient_light_energy = 0.15
			env.glow_intensity = 0.45
			env.glow_bloom = 0.02
			env.glow_hdr_threshold = 1.2
			# The far side of the field going soft in the afternoon haze.
			env.fog_light_color = Color(0.46, 0.45, 0.43)
			env.fog_depth_begin = 60.0
			env.fog_depth_end = 520.0
			# Low over the field from in front and to the right: under the stage roof, laying
			# the barrier's and the gear's shadows back across the deck.
			key.light_color = Color(1.0, 0.8, 0.58)
			key.light_energy = 1.0
			key.rotation_degrees = Vector3(-15.0, 200.0, 0.0)
			key.light_specular = 0.2
		ARENA:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.0, 0.0, 0.0)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			# The house lights half down: a little warm light everywhere in the bowl.
			env.ambient_light_color = Color(0.62, 0.5, 0.42)
			env.ambient_light_energy = 0.2
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			env.glow_intensity = 0.75
			env.glow_bloom = 0.05
			env.glow_hdr_threshold = 1.0
			env.fog_light_color = Color(0.05, 0.035, 0.05)
			env.fog_depth_begin = 12.0
			env.fog_depth_end = 160.0
			key.light_color = Color(1.0, 0.85, 0.7)
			key.light_energy = 0.04
			key.shadow_enabled = false
			key.basis = Basis.looking_at(Vector3(0.2, -1.0, 0.3), Vector3.FORWARD)
		_:
			_sky(env, [Color(0.004, 0.005, 0.016), Color(0.01, 0.01, 0.03), Color(0.035, 0.022, 0.05),
					Color(0.13, 0.06, 0.1), Color(0.04, 0.025, 0.045)], Vector3(0.0, -0.3, -1.0), 0.0, 1.6)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.38, 0.32, 0.62)
			env.ambient_light_energy = 0.12
			env.glow_intensity = 0.8
			env.glow_bloom = 0.05
			env.glow_hdr_threshold = 1.0
			# The haze the rig is drawn in, violet with it, closing in on the far crowd.
			env.fog_light_color = Color(0.05, 0.03, 0.075)
			env.fog_depth_begin = 10.0
			env.fog_depth_end = 170.0
			key.light_color = Color(0.6, 0.66, 1.0)
			key.light_energy = 0.1
			key.rotation_degrees = Vector3(-50.0, 160.0, 0.0)
			key.light_specular = 0.1


func _sky(env: Environment, bands: Array, sun: Vector3, disc: float, stars: float, energy := 1.0) -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://core/venues/shaders/dusk_sky.gdshader")
	for i in 5:
		sky_mat.set_shader_parameter(["zenith", "upper", "rose", "horizon", "haze"][i], bands[i])
	sky_mat.set_shader_parameter("sun_dir", sun)
	sky_mat.set_shader_parameter("sun_radius", disc)
	sky_mat.set_shader_parameter("stars", stars)
	sky_mat.set_shader_parameter("energy", energy)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


func lamp_colour(_index: int, authored: Color) -> Color:
	match variant:
		SOUNDCHECK:
			return authored.lerp(Color(1.0, 0.86, 0.7), 0.3)
		ARENA:
			return authored.lerp(Color(1.0, 0.7, 0.45), 0.35)
	# Show night: the desk lamps go a cool blue-white, like the stage's work lights in a cue.
	return authored.lerp(Color(0.75, 0.8, 1.0), 0.4)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * (0.7 if variant == SOUNDCHECK else 0.85)


## No walls: a stage deck, open to the audience.
func has_walls() -> bool:
	return false


## The stage is one open deck: the strips beside the desk join the back of house.
func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 43): a row of tuned cymbals
## and a gong on one rack, in the backline between the kit and the lattice.
func instrument() -> Dictionary:
	return {"kind": &"cymbals", "spot": back_wall_instrument(0.43)}


## The zones, and a road case at the front of each strip beside the desk.
func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	for at in strip_case_spots():
		out.append({"c": Vector2(at.x, at.z), "h": Vector2(0.6, 0.3), "a": 0.0, "top": 0.81})
	return out


func strip_case_spots() -> Array[Vector3]:
	var x := live_room_half() - 0.8
	return [Vector3(-x, 0, Studio.ROOM_FRONT + 0.6), Vector3(x, 0, Studio.ROOM_FRONT + 0.6)]


# --- where things are ------------------------------------------------------------------------

func front_edge() -> float:
	return Studio.ROOM_FRONT - APRON


func back_edge() -> float:
	return LIVE_ROOM_BACK + BACKSTAGE


func deck_half() -> float:
	return live_room_half() + WING


func wall_z() -> float:
	return LIVE_ROOM_BACK + WALL_BEHIND


func barricade_z() -> float:
	return front_edge() - PIT


## The four ground-support towers, at the deck's corners.
func tower_spots() -> Array[Vector2]:
	var x := deck_half() - 0.45
	return [Vector2(-x, front_edge() + 0.45), Vector2(x, front_edge() + 0.45), Vector2(-x, back_edge() - 0.45),
			Vector2(x, back_edge() - 0.45)]


## The lighting trusses: front (over the desk's front edge), mid (over the footprint's back
## edge), each at RIG; the back one carries the LED wall; and one over the middle of the back of
## house, which is twice as deep as it was and lay in the dark between the mid truss and the wall.
func truss_lines() -> Array[Vector3]:
	return [Vector3(0, RIG, Studio.ROOM_FRONT + 0.4), Vector3(0, RIG, Studio.ROOM_BACK - 0.6),
			Vector3(0, WALL_TOP + 0.4, wall_z()), Vector3(0, RIG, (Studio.ROOM_BACK + LIVE_ROOM_BACK) * 0.5)]


## The deck's dressing was first placed by number for a floor 6.3 m either side of centre and 3.2 m
## in front of the seat to 7.3 m behind it: `_wide` and `_deep` take those numbers to the floor now.
const DRAWN_NUMBERS_HALF := 6.3
const DRAWN_FRONT := -3.2


func _wide(x: float) -> float:
	return x * live_room_half() / DRAWN_NUMBERS_HALF


func _deep(z: float) -> float:
	return remap(z, DRAWN_FRONT, DRAWN_BACK, Studio.ROOM_FRONT, LIVE_ROOM_BACK)


# --- building it -----------------------------------------------------------------------------

func _ready() -> void:
	_kit = (load(MODELS + "stage_props.glb") as PackedScene).instantiate()
	_lay_the_deck()
	_skirt_the_stage()
	if variant == ARENA:
		_build_the_arena()
	else:
		_lay_the_field()
		_raise_the_towers()
	_hang_the_trusses()
	_fly_the_pa()
	_hang_the_movers()
	_raise_the_led_wall()
	_stack_the_stage()
	_run_the_cables()
	_light_the_stage()
	match variant:
		HEADLINE:
			_fill_the_field()
			_set_up_the_lasers()
			_build_the_far_side(true)
		SOUNDCHECK:
			_fly_the_flags()
			_crew_the_stage()
			_build_the_far_side(false)
		ARENA:
			_fill_the_arena()
	_dress_zones()
	_kit.free()
	_kit = null


func _process(delta: float) -> void:
	_t += delta
	if variant != SOUNDCHECK:
		# Night sweeps fast and wide; the arena's slower, lower, over the stands.
		var rate := 1.0 if variant == HEADLINE else 0.6
		for m in movers:
			var ph: float = m["phase"]
			(m["pan"] as Node3D).rotation.y = sin(_t * 0.45 * rate + ph) * 0.95
			(m["tilt"] as Node3D).rotation.x = m["rest"] + sin(_t * 0.7 * rate + ph * 1.7) * 0.42
	for i in _lasers.size():
		_lasers[i].rotation.y = sin(_t * 0.6 + i * 2.0) * 0.55
		_lasers[i].rotation.x = 0.12 + sin(_t * 0.9 + i) * 0.08
	if _wheel != null:
		_wheel.rotation.z = -_t * TAU / WHEEL_TURN
		# The gondolas hang plumb as the wheel goes round.
		for g in _gondolas:
			g.rotation.z = -_wheel.rotation.z


func pulse(level: float) -> void:
	# A meter's ballistics: fast up, slow down, so the beat flashes and a gap does not blink.
	var k := 0.5 if level > _smoothed else 0.07
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	var p := _smoothed
	for m in _led_mats + _crowd_mats:
		m.set_shader_parameter("pulse", p)
	for m in _beam_mats:
		m.set_shader_parameter("strength", m.get_meta(&"base", 0.05) * (0.45 + p * 1.4))
	for w in _washes:
		(w["light"] as Light3D).light_energy = w["energy"] * (0.6 + p * w["swing"])
	if _lip_mat != null:
		_lip_mat.albedo_color = _lip_mat.get_meta(&"base", Color.WHITE) * (0.5 + p * 1.5)
	if _laser_mat != null:
		_laser_mat.albedo_color = Color(0.1, 1.0, 0.25) * (0.2 + p * 0.9)


# --- materials -------------------------------------------------------------------------------

func _paint(colour: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m


func _alu() -> StandardMaterial3D:
	return GearStyle.metal(Color(0.7, 0.71, 0.73), 0.35)


func _black() -> StandardMaterial3D:
	return _paint(Color(0.035, 0.035, 0.04), 0.7, 0.1)


## Black wool serge, the drapes and the skirts: it drinks the light.
func _drape() -> StandardMaterial3D:
	var m := _paint(Color(0.025, 0.025, 0.03), 0.95)
	m.normal_enabled = true
	m.normal_texture = Materials.grain("stage_serge", 0.4, 0.5, 6.0)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


func _tolex() -> StandardMaterial3D:
	var m := _paint(Color(0.06, 0.062, 0.07), 0.82)
	m.normal_enabled = true
	m.normal_texture = Materials.grain("tolex", 1.6, 2.4)
	m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	return m


func _lens() -> StandardMaterial3D:
	if variant == SOUNDCHECK:
		return _paint(Color(0.06, 0.07, 0.08), 0.1, 0.6)
	return ZoneKit.glow(Color(0.95, 0.92, 1.0), 2.2)


func _swaps() -> Dictionary:
	var seat := _paint(Color(0.07, 0.1, 0.26), 0.55)
	return {"cab": _paint(Color(0.04, 0.04, 0.045), 0.6, 0.15), "grille": _paint(Color(0.02, 0.02, 0.022), 0.9, 0.3),
			"alu": _alu(), "steel": _paint(Color(0.16, 0.16, 0.17), 0.45, 0.7), "lens": _lens(),
			"pad": _paint(Color(0.04, 0.05, 0.1), 0.7), "case": _tolex(), "rubber": _paint(Color(0.02, 0.02, 0.02), 0.9),
			"body": _paint(Color(0.05, 0.05, 0.055), 0.9), "seat": seat, "ply": _paint(Color(0.3, 0.24, 0.17), 0.8),
			"panel": _paint(Color(0.7, 0.7, 0.72), 0.3, 0.8)}


## One of the rig's meshes, its materials the stage's own.
func _mesh(piece: String) -> Mesh:
	if _meshes.has(piece):
		return _meshes[piece]
	var source := _kit.find_child(piece, true, false) as MeshInstance3D
	var mesh := source.mesh.duplicate() as ArrayMesh
	var swaps := _swaps()
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swaps.has(m.resource_name):
			mesh.surface_set_material(s, swaps[m.resource_name])
	_meshes[piece] = mesh
	return mesh


func _piece(piece: String, at: Transform3D, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = piece
	node.mesh = _mesh(piece)
	node.transform = at
	parent.add_child(node)
	return node


func _many(label: String, mesh: Mesh, spots: Array, material: Material = null, shadows := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	if material != null:
		node.material_override = material
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## Boxes and the like as one mesh: [[mesh, transform], ...]. One draw, and a solid made of
## parts rather than parts the z-fight scan would weigh against each other face by face.
static func _merged(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	for part: Array in parts:
		st.append_from(part[0], 0, part[1])
	return st.commit()


## The surfaces of a primitive as a plain mesh: a beam's cone is light in the haze, not a solid.
static func _plain(mesh: PrimitiveMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.get_mesh_arrays())
	return out


## A basis whose -Z looks along `dir` (flattened), turned by `yaw` more.
static func _facing(dir: Vector3, yaw := 0.0) -> Basis:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	return Basis.looking_at(flat.normalized(), Vector3.UP) * Basis(Vector3.UP, yaw)


## Truss lengths from `a` to `b`, appended to `out`: as many 2 m lengths as fit, stretched a
## little to meet the ends.
static func _truss_run(a: Vector3, b: Vector3, out: Array) -> void:
	var d := b - a
	var n := maxi(1, int(round(d.length() / TRUSS)))
	var x := d.normalized()
	var helper := Vector3.UP if absf(x.y) < 0.9 else Vector3.BACK
	var z := x.cross(helper).normalized()
	var y := z.cross(x)
	var stretch := d.length() / (n * TRUSS)
	for i in n:
		out.append(Transform3D(Basis(x * stretch, y, z), a + d * ((i + 0.5) / n)))


# --- the deck ------------------------------------------------------------------------------

## The deck: black-painted boards from the lip to the back of backstage and out to the wings,
## a white safety line along its front edge, and spike marks taped where the band's gear goes.
func _lay_the_deck() -> void:
	var half := deck_half()
	var deck := MeshInstance3D.new()
	deck.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, back_edge() - front_edge())
	deck.mesh = plane
	deck.position.z = (back_edge() + front_edge()) * 0.5
	# Black paint gone grey with scuffing; a shade darker by day, when the sky is on it too.
	var tone := 0.2 if variant == SOUNDCHECK else 0.3
	deck.material_override = Materials.scanned(StandardMaterial3D.new(), "wood_floor_deck", "2k", 1.6,
			Color(tone, tone * 0.97, tone * 0.97))
	add_child(deck)
	var white := _paint(Color(0.8, 0.8, 0.76), 0.6)
	ZoneKit.block(self, Vector3(half * 2.0 - 0.3, 0.004, 0.05), Vector3(0, 0.0025, front_edge() + 0.08), white,
			"LipLine")
	# Spike marks: little crosses of coloured tape, where the riser and the wedges go.
	var tapes := [Color(1.0, 0.85, 0.1), Color(0.2, 0.9, 0.3), Color(1.0, 0.25, 0.6), Color(0.3, 0.6, 1.0)]
	var spikes := [Vector3(-1.8, 0, Studio.ROOM_FRONT - 0.85), Vector3(0.0, 0, Studio.ROOM_FRONT - 0.85),
			Vector3(1.8, 0, Studio.ROOM_FRONT - 0.85), Vector3(live_room_half() - 0.5, 0, 1.6),
			Vector3(-live_room_half() + 0.5, 0, 1.4), Vector3(-4.2, 0, Studio.ROOM_BACK + 0.4),
			Vector3(4.4, 0, Studio.ROOM_BACK + 0.35)]
	for i in spikes.size():
		var m := _paint(tapes[i % tapes.size()], 0.7)
		# Their faces at heights of their own: not the deck's, not each other's.
		ZoneKit.block(self, Vector3(0.16, 0.003, 0.04), spikes[i] + Vector3(0, 0.0023, 0), m, "Spike")
		ZoneKit.block(self, Vector3(0.04, 0.004, 0.16), spikes[i] + Vector3(0, 0.0035, 0), m, "Spike")


## The deck's skirts down to the ground on every side, black serge; the stairs down at the back;
## black drapes along the wings' back half and across the back, hung from the roof.
func _skirt_the_stage() -> void:
	var half := deck_half()
	var drape := _drape()
	var tall := DECK - 0.004
	var y := -DECK + tall * 0.5
	ZoneKit.block(self, Vector3(half * 2.0 + 0.12, tall, 0.04), Vector3(0, y, front_edge() - 0.02), drape, "Skirt")
	ZoneKit.block(self, Vector3(half * 2.0 + 0.1, tall, 0.04), Vector3(0, y, back_edge() + 0.02), drape, "Skirt")
	var depth := back_edge() - front_edge()
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.04, tall, depth), Vector3(side * (half + 0.02), y, (back_edge() + front_edge()) * 0.5),
				drape, "Skirt")
	# Stairs down off the back corner, stage left, for the band and the crew.
	var steel := _paint(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	var steps := 7
	var rise := DECK / (steps + 1)
	for i in steps:
		var top := -rise * (i + 1)
		ZoneKit.block(self, Vector3(1.2, 0.05, 0.32), Vector3(-half + 1.5, top - 0.025, back_edge() + 0.2 + 0.3 * i + 0.16),
				steel, "Step")
	for side in [-1.0, 1.0]:
		var a := Vector3(-half + 1.5 + side * 0.62, 0.95, back_edge() + 0.05)
		var b := Vector3(-half + 1.5 + side * 0.62, -DECK + 0.95, back_edge() + 0.2 + 0.3 * steps)
		var rail := MeshInstance3D.new()
		rail.name = "StairRail"
		var bar := BoxMesh.new()
		bar.size = Vector3(0.04, 0.04, a.distance_to(b))
		rail.mesh = bar
		rail.material_override = steel
		rail.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)
		add_child(rail)
	# The drapes: the wings' back halves and the back, so the LED wall stands in a black box.
	var from := Studio.ROOM_BACK
	var drop := ROOF - 0.3
	# The wings' stop short of the deck's back edge (a tower's base plate is there) and run into
	# the back one.
	var to := back_edge() - 0.14
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.03, drop, to - from), Vector3(side * (half - 0.08), drop * 0.5 + 0.01,
				(from + to) * 0.5), drape, "WingDrape")
	ZoneKit.block(self, Vector3(half * 2.0 - 0.2, drop, 0.03), Vector3(0, drop * 0.5 + 0.012, back_edge() - 0.12),
			drape, "BackDrape")


# --- the field (Headline night, Soundcheck) ----------------------------------------------------

func _lay_the_field() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Field"
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	ground.mesh = plane
	ground.position = Vector3(0, -DECK, -120)
	var field := ShaderMaterial.new()
	field.shader = preload("res://core/venues/shaders/stage_field.gdshader")
	field.set_shader_parameter("worn", Vector4(20.0, barricade_z(), -80.0, 0.0))
	if variant == SOUNDCHECK:
		# Not trodden yet: only the walk to the desk tent is worn in.
		field.set_shader_parameter("worn", Vector4(20.0, barricade_z(), -80.0, 0.0))
		field.set_shader_parameter("wear", 0.35)
	if variant == HEADLINE:
		# Trodden flat and dark under the crowd; only the stage's light finds it.
		field.set_shader_parameter("grass_a", Color(0.05, 0.065, 0.035))
		field.set_shader_parameter("grass_b", Color(0.07, 0.08, 0.045))
		field.set_shader_parameter("straw", Color(0.1, 0.09, 0.06))
		field.set_shader_parameter("earth", Color(0.06, 0.05, 0.04))
	ground.material_override = field
	add_child(ground)
	# The barrier along the front, and its returns back to the stage at both ends.
	var spots: Array = []
	var reach := deck_half() + 2.0
	var x := -reach + 0.5
	while x < reach:
		spots.append(Transform3D(Basis.IDENTITY, Vector3(x, -DECK, barricade_z())))
		x += 1.0
	for side in [-1.0, 1.0]:
		var z := barricade_z() + 0.5
		while z < front_edge() - 0.2:
			spots.append(Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(side * (reach + 0.05), -DECK, z)))
			z += 1.0
	_many("Barricade", _mesh("Barricade"), spots, null, true)


## The four towers: a column of truss from the deck to the roof at each corner, a base plate
## under it and a sleeve block at its head; the roof grid between them; a membrane over it all.
func _raise_the_towers() -> void:
	var lengths: Array = []
	var steel := _paint(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	for t in tower_spots():
		_truss_run(Vector3(t.x, 0.3, t.y), Vector3(t.x, ROOF, t.y), lengths)
		ZoneKit.block(self, Vector3(0.9, 0.06, 0.9), Vector3(t.x, 0.03, t.y), steel, "BasePlate")
		ZoneKit.block(self, Vector3(0.22, 0.24, 0.22), Vector3(t.x, 0.18, t.y), steel, "BaseBlock")
		ZoneKit.block(self, Vector3(0.5, 0.7, 0.5), Vector3(t.x, ROOF + 0.05, t.y), steel, "Sleeve")
	var ts := tower_spots()
	var y := ROOF + 0.05
	# Front and back beams, the side beams, and two across between.
	_truss_run(Vector3(ts[0].x + 0.3, y, ts[0].y), Vector3(ts[1].x - 0.3, y, ts[1].y), lengths)
	_truss_run(Vector3(ts[2].x + 0.3, y, ts[2].y), Vector3(ts[3].x - 0.3, y, ts[3].y), lengths)
	for i in 2:
		_truss_run(Vector3(ts[i].x, y + 0.3, ts[i].y + 0.3), Vector3(ts[i + 2].x, y + 0.3, ts[i + 2].y - 0.3), lengths)
	for f in [0.36, 0.7]:
		var z := lerpf(ts[0].y, ts[2].y, f)
		_truss_run(Vector3(ts[0].x + 0.2, y + 0.3, z), Vector3(ts[1].x - 0.2, y + 0.3, z), lengths)
	_many("TowerTruss", _mesh("Truss"), lengths, null, true)
	# The roof: a PVC membrane over the grid, pitched back to shed the rain, its front hung with
	# a header banner.
	var skin := _paint(Color(0.07, 0.07, 0.08), 0.8)
	var span := ts[1].x - ts[0].x + 1.6
	var depth := ts[2].y - ts[0].y + 2.0
	var roof := ZoneKit.block(self, Vector3(span, 0.12, depth), Vector3(0, ROOF + 1.15, (ts[0].y + ts[2].y) * 0.5), skin,
			"Membrane")
	roof.rotation.x = -0.06
	ZoneKit.block(self, Vector3(span - 0.4, 1.6, 0.05), Vector3(0, ROOF + 0.6, ts[0].y - 0.62), skin, "Header")
	var name_board := Label3D.new()
	name_board.name = "StageName"
	name_board.text = "MAIN STAGE"
	name_board.font_size = 128
	name_board.pixel_size = 0.008
	name_board.modulate = Color(0.95, 0.95, 0.95) if variant == SOUNDCHECK else Color(1.6, 0.6, 1.4)
	name_board.shaded = variant == SOUNDCHECK
	name_board.double_sided = false
	name_board.rotation.y = PI
	name_board.position = Vector3(0, ROOF + 0.6, ts[0].y - 0.66)
	add_child(name_board)


# --- the rig ---------------------------------------------------------------------------------

## The lighting trusses across the stage, each on chain hoists from the roof grid (from the
## arena's roof in the arena); and the roof-level perimeter the drapes hang from, flown in the
## arena where there are no towers.
func _hang_the_trusses() -> void:
	var lengths: Array = []
	var x := deck_half() - 1.0
	for line in truss_lines():
		_truss_run(Vector3(-x, line.y, line.z), Vector3(x, line.y, line.z), lengths)
	var top := ARENA_ROOF if variant == ARENA else ROOF
	if variant == ARENA:
		# The stage's own roof line, flown: the PA and the drapes need it.
		var ts := tower_spots()
		_truss_run(Vector3(ts[0].x, ROOF, ts[0].y), Vector3(ts[1].x, ROOF, ts[1].y), lengths)
		_truss_run(Vector3(ts[2].x, ROOF, ts[2].y), Vector3(ts[3].x, ROOF, ts[3].y), lengths)
		for i in 2:
			_truss_run(Vector3(ts[i].x, ROOF, ts[i].y + 0.3), Vector3(ts[i + 2].x, ROOF, ts[i + 2].y - 0.3), lengths)
	_many("Trusses", _mesh("Truss"), lengths, null, true)
	# The chain hoists: a motor body and its chain up to the steel overhead.
	var chains: Array = []
	var motors: Array = []
	var picks: Array[Vector3] = []
	for line in truss_lines():
		for px in [-x + 0.6, 0.0, x - 0.6]:
			picks.append(Vector3(px, line.y + 0.16, line.z))
	if variant == ARENA:
		for t in tower_spots():
			picks.append(Vector3(t.x, ROOF + 0.16, t.y))
	for p in picks:
		var motor_y := p.y + 0.55
		motors.append(Transform3D(Basis.IDENTITY, Vector3(p.x, motor_y, p.z)))
		var up := top - motor_y - 0.2
		chains.append(Transform3D(Basis.from_scale(Vector3(1, up, 1)), Vector3(p.x, motor_y + 0.2 + up * 0.5, p.z)))
		chains.append(Transform3D(Basis.from_scale(Vector3(1, 0.36, 1)), Vector3(p.x + 0.04, p.y + 0.2, p.z)))
	var motor := BoxMesh.new()
	motor.size = Vector3(0.26, 0.42, 0.3)
	_many("Hoists", motor, motors, _paint(Color(0.05, 0.05, 0.055), 0.6, 0.3))
	var chain := BoxMesh.new()
	chain.size = Vector3(0.03, 1.0, 0.03)
	_many("Chains", chain, chains, _paint(Color(0.2, 0.2, 0.21), 0.4, 0.8))


## The main PA: a line array flown either side of the stage from the roof's front beam, and a
## sub arc on the ground under the lip; and two delay towers out in the field.
func _fly_the_pa() -> void:
	var ts := tower_spots()
	var hang := ROOF - 1.3
	for side in [-1.0, 1.0]:
		var at := Vector3(side * (deck_half() - 2.0), hang, ts[0].y)
		# Turned in a little toward the middle of the crowd.
		var array := _piece("LineArray", Transform3D(Basis(Vector3.UP, side * 0.12), at))
		array.name = "LineArray%d" % (0 if side < 0 else 1)
		var chain := BoxMesh.new()
		chain.size = Vector3(0.03, ROOF - hang - 0.1, 0.03)
		for cx in [-0.35, 0.35]:
			var link := MeshInstance3D.new()
			link.name = "ArrayChain"
			link.mesh = chain
			link.material_override = _paint(Color(0.2, 0.2, 0.21), 0.4, 0.8)
			link.position = at + Basis(Vector3.UP, side * 0.12) * Vector3(cx, (ROOF - hang) * 0.5 + 0.05, -0.25)
			add_child(link)
	var subs: Array = []
	var x := -deck_half() + 1.6
	while x < deck_half() - 1.0:
		# In a gentle arc, the middle ones a little further out.
		var z := front_edge() - 0.55 - 0.25 * cos(x / deck_half() * PI * 0.5)
		subs.append(Transform3D(Basis(Vector3.UP, -x / deck_half() * 0.25), Vector3(x, -DECK, z)))
		x += 1.32
	_many("Subs", _mesh("Sub"), subs, null, true)
	if variant == ARENA:
		return
	# Delay towers out in the field: scaffold, and a short array on top facing the far crowd.
	for side in [-1.0, 1.0]:
		var foot := Vector3(side * 13.0, -DECK, -42.0)
		var scaffold := _paint(Color(0.45, 0.46, 0.48), 0.5, 0.7)
		for cx in [-0.8, 0.8]:
			for cz in [-0.8, 0.8]:
				ZoneKit.block(self, Vector3(0.06, 9.0, 0.06), foot + Vector3(cx, 4.5, cz), scaffold, "DelayLeg")
		for h in [3.0, 6.0, 8.95]:
			# Inside the legs' outer faces, so no edge of a deck lies in one of theirs.
			ZoneKit.block(self, Vector3(1.62, 0.05, 1.62), foot + Vector3(0, h, 0), scaffold, "DelayDeck")
		var delay := _piece("LineArray", Transform3D(Basis.from_scale(Vector3.ONE * 0.6), foot + Vector3(0, 11.6, -0.2)))
		delay.name = "DelayArray"
		ZoneKit.block(self, Vector3(0.05, 2.6, 0.05), foot + Vector3(0, 10.3, -0.35), scaffold, "DelayMast")


## The moving heads, along the front and mid trusses and the back truss over the LED wall:
## a base clamped under the truss, a yoke that pans, a head that tilts, and its beam in the haze.
func _hang_the_movers() -> void:
	var look: Dictionary = LOOKS[variant]
	var colours: Array = look["beams"]
	for c: Color in colours:
		var m := ShaderMaterial.new()
		m.shader = preload("res://core/venues/shaders/stage_beam.gdshader")
		m.set_shader_parameter("colour", c)
		var base := 0.05 if variant == HEADLINE else 0.035
		m.set_meta(&"base", base)
		m.set_shader_parameter("strength", base)
		_beam_mats.append(m)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = BEAM_REACH * tan(deg_to_rad(BEAM_SPREAD))
	cone.height = 1.0
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 20
	var cone_mesh := _plain(cone)
	var x := deck_half() - 1.6
	var lines := truss_lines()
	var counts := [8, 6, 8, 6]
	var n := 0
	for li in lines.size():
		var line: Vector3 = lines[li]
		var count: int = counts[li]
		for i in count:
			var at := Vector3(lerpf(-x, x, (i + 0.5) / count), line.y - 0.18, line.z - (0.4 if li == 2 else 0.0))
			var rig := Node3D.new()
			rig.name = "Mover%d" % n
			rig.position = at
			add_child(rig)
			_piece("HeadBase", Transform3D.IDENTITY, rig)
			var pan := Node3D.new()
			pan.name = "Pan"
			pan.position = Vector3(0, -0.2, 0)
			rig.add_child(pan)
			_piece("HeadYoke", Transform3D.IDENTITY, pan)
			var tilt := Node3D.new()
			tilt.name = "Tilt"
			tilt.position = Vector3(0, -0.31, 0)
			pan.add_child(tilt)
			_piece("Head", Transform3D.IDENTITY, tilt)
			# At rest the night's heads point out over the crowd; at the soundcheck, parked
			# straight down; in the arena out and up over the stands.
			var rest := 0.0
			if variant == HEADLINE:
				rest = 1.2
			elif variant == ARENA:
				rest = 1.25
			tilt.rotation.x = rest
			if variant == SOUNDCHECK:
				# Parked, all but one turned at the deck where the lampie is focusing it.
				pan.rotation.y = 0.0
			else:
				var beam := MeshInstance3D.new()
				beam.name = "Beam"
				beam.mesh = cone_mesh
				beam.material_override = _beam_mats[n % _beam_mats.size()]
				beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				beam.transform = Transform3D(Basis.from_scale(Vector3(1, BEAM_REACH, 1)), Vector3(0, -0.17 - BEAM_REACH * 0.5, 0))
				tilt.add_child(beam)
			movers.append({"pan": pan, "tilt": tilt, "rest": rest, "phase": n * 0.61 + li * 1.3})
			n += 1


## The LED wall across the back, hung from the back truss over the backline, in a black frame;
## and in the field, a screen either side of the stage (flown in the arena) for the far crowd.
func _raise_the_led_wall() -> void:
	var look: Dictionary = LOOKS[variant]
	var wall_half := live_room_half() + 0.6
	var tall := WALL_TOP - WALL_FOOT
	_led(Vector2(wall_half * 2.0, tall), Vector3(0, WALL_FOOT + tall * 0.5, wall_z()), Vector2(240, 96), "LedWall",
			[0.55, 0.22, 0.45][variant])
	var frame := _black()
	ZoneKit.block(self, Vector3(wall_half * 2.0 + 0.16, tall + 0.16, 0.12), Vector3(0, WALL_FOOT + tall * 0.5,
			wall_z() + 0.075), frame, "LedFrame")
	# The screens beside the stage: 16:9, on scaffold in the field, flown in the arena.
	for side in [-1.0, 1.0]:
		var at := Vector3(side * (deck_half() + 3.6), 4.0, front_edge() + 0.8)
		# Facing the crowd, turned in a little toward its middle.
		var turn := Basis(Vector3.UP, PI + side * 0.18)
		var screen := _led(Vector2(6.4, 3.6), at, Vector2(128, 72), "SideScreen", 0.45)
		screen.basis = turn
		var back := ZoneKit.block(self, Vector3(6.6, 3.8, 0.1), at + turn * Vector3(0, 0, -0.07), frame, "SideScreenFrame")
		back.basis = turn
		var scaffold := _paint(Color(0.4, 0.41, 0.43), 0.5, 0.7)
		for cx in [-2.6, 2.6]:
			var post := at + turn * Vector3(cx, 0, -0.25)
			if variant == ARENA:
				# Flown: two wires up to the roof.
				ZoneKit.block(self, Vector3(0.02, ARENA_ROOF - at.y - 1.9, 0.02), Vector3(post.x, (ARENA_ROOF + at.y + 1.9) * 0.5,
						post.z), scaffold, "ScreenWire")
			else:
				ZoneKit.block(self, Vector3(0.07, at.y + DECK + 1.9, 0.07), Vector3(post.x, (at.y + 1.9 - DECK) * 0.5, post.z),
						scaffold, "ScreenLeg")
	if variant == SOUNDCHECK:
		# Between the test card and the show, the side screens are dark; the wall is up.
		for m in _led_mats:
			m.set_shader_parameter("mode", 1)
	var colours: Array = look["wall"]
	for m in _led_mats:
		m.set_shader_parameter("colour_a", colours[0])
		m.set_shader_parameter("colour_b", colours[1])


func _led(size: Vector2, at: Vector3, cells: Vector2, label: String, bright: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var face := MeshInstance3D.new()
	face.name = label
	face.mesh = quad
	# The quad faces +Z; turned to face the audience (-Z).
	face.rotation.y = PI
	face.position = at
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/stage_led.gdshader")
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("brightness", bright)
	face.material_override = m
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	_led_mats.append(m)
	return face


## What stands on the deck: side-fill stacks on the wings facing in, wedges along the lip facing
## back at the band, the backline in front of the LED wall, the monitor desk on the stage-right
## wing, road cases on the wings and backstage, and one at the front of each strip beside the desk.
func _stack_the_stage() -> void:
	var half := live_room_half()
	var subs: Array = []
	for side in [-1.0, 1.0]:
		for k in 3:
			subs.append(Transform3D(_facing(Vector3(-side, 0, 0)), Vector3(side * (half + 1.0), 0.6 * k, 0.6)))
	_many("SideFills", _mesh("Sub"), subs, null, true)
	var wedges: Array = []
	for wx in [-1.8, 0.0, 1.8]:
		wedges.append(Transform3D(Basis(Vector3.UP, wx * 0.08), Vector3(wx, 0, Studio.ROOM_FRONT - 0.85)))
	_many("Wedges", _mesh("Wedge"), wedges, null, true)
	# The backline, between the back of house and the wall: a bass rig, two guitar stacks, a
	# keys amp; facing out to the crowd over the band's heads.
	var cabs: Array = []
	var heads: Array = []
	var back := LIVE_ROOM_BACK + 0.32
	for spec in [[-5.0, 2], [-1.6, 2], [1.6, 2], [4.6, 1]]:
		var cx := _wide(spec[0])
		var stack: int = spec[1]
		for k in stack:
			cabs.append(Transform3D(Basis.IDENTITY, Vector3(cx, 0.761 * k, back)))
		heads.append(Transform3D(Basis.IDENTITY, Vector3(cx, 0.761 * stack + 0.001, back)))
	_many("Cabs", _mesh("Cab"), cabs, null, true)
	_many("AmpHeads", _mesh("AmpHead"), heads, null, true)
	# Road cases: on the wings, backstage, and the two in the strips beside the desk.
	var cases: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for at in strip_case_spots():
		cases.append(Transform3D(Basis.IDENTITY, at))
	var wing_spots := [Vector2(-half - 2.2, -2.6), Vector2(-half - 2.6, 3.8), Vector2(-half - 1.6, 5.4),
			Vector2(half + 2.4, 3.6), Vector2(half + 1.8, 5.6), Vector2(half + 3.0, -2.2)]
	if variant == SOUNDCHECK:
		wing_spots.append_array([Vector2(-half - 1.4, -1.2), Vector2(-half - 3.0, 0.4), Vector2(half + 2.6, -0.4),
				Vector2(half + 1.4, 2.0), Vector2(-half - 2.0, 2.2)])
	# Down the wings beside the whole floor, not only its first half.
	wing_spots.append_array([Vector2(-half - 2.4, 9.6), Vector2(-half - 1.8, 11.6), Vector2(half + 2.2, 8.8),
			Vector2(half + 1.6, 11.2)])
	for s: Vector2 in wing_spots:
		cases.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3) + PI * 0.5 * float(rng.randi() % 2)),
				Vector3(s.x, 0, _deep(s.y) if s.y < 8.0 else s.y)))
	var bz := wall_z() + 0.9
	var bx := -half
	while bx < half:
		cases.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), Vector3(bx, 0, bz + rng.randf_range(0.0, 1.6))))
		# Some stacked two high.
		if rng.randf() < 0.4:
			cases.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), Vector3(bx + 0.05, 0.811, bz + 2.4)))
		bx += rng.randf_range(1.4, 2.2)
	_many("RoadCases", _mesh("RoadCase"), cases, null, true)
	# Monitor world: a desk on a case on the stage-right wing, its screen turned to the band.
	var mon := Vector3(half + 1.9, 0, -0.4)
	var desk_frame := _paint(Color(0.05, 0.05, 0.055), 0.6, 0.2)
	ZoneKit.block(self, Vector3(0.7, 0.1, 1.1), mon + Vector3(0, 0.86, 0), desk_frame, "MonitorDesk")
	var screen := ZoneKit.block(self, Vector3(0.04, 0.32, 0.5), mon + Vector3(0.2, 1.1, 0),
			ZoneKit.glow(Color(0.3, 0.55, 1.0), 0.9 if variant == SOUNDCHECK else 1.2), "MonitorScreen")
	screen.rotation.z = 0.2
	ZoneKit.block(self, Vector3(0.6, 0.81, 1.0), mon + Vector3(0, 0.405, 0), _tolex(), "MonitorCase")


## Cable runs across the deck: from the wings to the riser, the booth, the keys and the desk,
## lying on the boards in loose curves.
func _run_the_cables() -> void:
	var half := live_room_half()
	var z := zones()
	var runs := [
		[Vector3(-half - 1.0, 0, 1.0), Vector3(-half + 0.6, 0, 2.2), (z[&"drums"] as AABB).get_center() * Vector3(1, 0, 1)
				+ Vector3(0, 0, -1.4)],
		[Vector3(-half - 1.0, 0, 1.4), Vector3(-half + 0.3, 0, 3.2), (z[&"vocals"] as AABB).get_center() * Vector3(1, 0, 1)
				+ Vector3(1.2, 0, -0.6)],
		[Vector3(half + 1.0, 0, 1.0), Vector3(half - 0.4, 0, 2.6), (z[&"synth"] as AABB).get_center() * Vector3(1, 0, 1)
				+ Vector3(-0.6, 0, 0)],
		[Vector3(half + 1.4, 0, -0.6), Vector3(half - 0.6, 0, -1.0), Vector3(room_width * 0.5 - 0.2, 0, -1.6)],
		[Vector3(-half - 1.2, 0, -1.2), Vector3(-half + 0.5, 0, -0.6), Vector3(-room_width * 0.5 + 0.2, 0, -0.4)],
	]
	var bits: Array = []
	for run: Array in runs:
		var pts: Array[Vector3] = []
		# A quadratic through the three points, sampled.
		for i in 13:
			var t := i / 12.0
			var a: Vector3 = run[0]
			var b: Vector3 = run[1]
			var c: Vector3 = run[2]
			var p := a * (1 - t) * (1 - t) + b * 2.0 * t * (1 - t) + c * t * t
			pts.append(p + Vector3(0, 0.013, 0))
		for i in pts.size() - 1:
			var from := pts[i]
			var to := pts[i + 1]
			bits.append(Transform3D(Basis.looking_at(to - from, Vector3.UP) * Basis.from_scale(Vector3(1, 1, from.distance_to(to))),
					(from + to) * 0.5))
	var cable := BoxMesh.new()
	cable.size = Vector3(0.022, 0.022, 1.0)
	_many("Cables", cable, bits, _paint(Color(0.02, 0.02, 0.022), 0.5))


## The stage's own light: two washes from the front truss over the desk, one from the mid truss
## on the zones, a spill off the LED wall, and at night and in the arena two out over the crowd.
## Also the little lip lights along the front edge.
func _light_the_stage() -> void:
	var look: Dictionary = LOOKS[variant]
	var washes: Array = look["wash"]
	var front: Vector3 = truss_lines()[0]
	var mid: Vector3 = truss_lines()[1]
	var day := variant == SOUNDCHECK
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_wash(Vector3(side * 2.6, front.y - 0.5, front.z), Vector3(side * 0.6, 0.6, 0.4), washes[i], 0.5 if day else 4.0,
				34.0, 14.0, 0.0 if day else 0.9, "DeskWash")
	# The band's own light, from the mid truss down on the riser and the booth, and the keys.
	var zs := zones()
	var left := ((zs[&"drums"] as AABB).get_center() + (zs[&"vocals"] as AABB).get_center()) * 0.5
	var right := ((zs[&"bricks"] as AABB).get_center() + (zs[&"synth"] as AABB).get_center()) * 0.5
	_wash(Vector3(-3.0, mid.y - 0.5, mid.z), Vector3(left.x, 0.0, left.z), washes[0].lerp(Color.WHITE, 0.35),
			2.5 if day else 14.0, 46.0, 16.0, 0.0 if day else 0.7, "ZoneWash")
	_wash(Vector3(3.0, mid.y - 0.5, mid.z), Vector3(right.x, 0.0, right.z), washes[1].lerp(Color.WHITE, 0.35),
			2.5 if day else 12.0, 46.0, 16.0, 0.0 if day else 0.7, "ZoneWash")
	# And from the truss over the middle of the back of house, down on its far half: the booth
	# and the toys on the left, the lattice in the middle, the synth corner on the right.
	var over: Vector3 = truss_lines()[3]
	var half := live_room_half()
	for spec: Array in [[-0.45, Vector3(-half * 0.7, 0.0, LIVE_ROOM_BACK - 3.0), 0], [0.0, (zs[&"matrix"] as AABB).get_center()
			* Vector3(1, 0, 1), 1], [0.45, Vector3(half * 0.7, 0.0, LIVE_ROOM_BACK - 2.2), 1]]:
		var colour: Color = (washes[spec[2]] as Color).lerp(Color.WHITE, 0.4)
		_wash(Vector3(half * float(spec[0]), over.y - 0.5, over.z), spec[1], colour, 2.0 if day else 10.0, 50.0, 14.0,
				0.0 if day else 0.7, "ZoneWash")
	# And from behind them, off the back truss over the wall: the band's backlight, down over
	# the riser and the lattice's square toward the desk.
	var back: Vector3 = truss_lines()[2]
	_wash(Vector3(0, back.y - 0.6, back.z - 0.5), Vector3(0, 0, 3.6), washes[1].lerp(Color.WHITE, 0.5), 2.0 if day else 9.0,
			55.0, 14.0, 0.0 if day else 1.0, "BackLight")
	if not day:
		var spill := OmniLight3D.new()
		spill.name = "WallSpill"
		spill.light_color = (look["wall"][0] as Color).lerp(look["wall"][1], 0.5)
		spill.light_energy = 1.4
		spill.omni_range = 8.0
		spill.position = Vector3(0, 3.2, wall_z() - 1.6)
		spill.light_specular = 0.1
		add_child(spill)
		_washes.append({"light": spill, "energy": 1.4, "swing": 1.2})
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			_wash(Vector3(side * 4.0, front.y - 0.5, front.z - 0.3), Vector3(side * 9.0, -DECK, -22.0), washes[i], 4.5,
					30.0, 48.0, 1.1, "CrowdWash")
	# Lip lights: small LED battens along the front edge, uplighting the band.
	var spots: Array = []
	var x := -deck_half() + 1.2
	while x < deck_half() - 1.0:
		spots.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.035, front_edge() + 0.32)))
		x += 1.1
	var body := BoxMesh.new()
	body.size = Vector3(0.5, 0.07, 0.1)
	_many("LipLights", body, spots, _black())
	var lit: Array = []
	for s: Transform3D in spots:
		lit.append(s.translated(Vector3(0, 0.0, 0.052)))
	var face := BoxMesh.new()
	face.size = Vector3(0.44, 0.04, 0.006)
	_lip_mat = ZoneKit.glow((washes[0] as Color).lerp(Color.WHITE, 0.2), 1.0 if not day else 0.2)
	_lip_mat.set_meta(&"base", _lip_mat.albedo_color)
	_many("LipLenses", face, lit, _lip_mat)


func _wash(at: Vector3, aim: Vector3, colour: Color, energy: float, angle: float, reach: float, swing: float,
		label: String) -> SpotLight3D:
	var spot := SpotLight3D.new()
	spot.name = label
	spot.light_color = colour
	spot.light_energy = energy
	spot.spot_angle = angle
	spot.spot_range = reach
	spot.spot_angle_attenuation = 1.1
	spot.light_specular = 0.08
	spot.shadow_enabled = false
	spot.transform = Transform3D(Basis.looking_at(aim - at, Vector3.UP), at)
	add_child(spot)
	if swing > 0.0:
		_washes.append({"light": spot, "energy": energy, "swing": swing})
	return spot


# --- the crowd (Headline night) -----------------------------------------------------------------

## A sea of people from the barrier out toward the trees, thick at the front and thinning, all
## turned to the stage; a third with a hand up, some with a phone in it. Three poses, one
## MultiMesh each, swayed and bounced in stage_crowd.gdshader; the phones another.
func _fill_the_field() -> void:
	var keep_out: Array[Rect2] = [Rect2(-5.5, -40.0, 11.0, 8.5), Rect2(-15.0, -44.0, 4.0, 4.0), Rect2(11.0, -44.0, 4.0, 4.0)]
	# As wide at the barrier as the stage, which has grown with the room.
	var spots := _crowd_spots(barricade_z() - 1.0, -78.0, deck_half() + 2.7, 34.0, 0.62, 1.15, keep_out, 47)
	_place_crowd(spots, Vector3(0, -DECK, front_edge()), 1.6, 1.4)
	_build_foh(Vector3(0, -DECK, -36.0))


## Places on the ground from `near` back to `far` (z), widening from `w_near` to `w_far` either
## side, spaced from `s_near` to `s_far`, none in `keep_out`.
func _crowd_spots(near: float, far: float, w_near: float, w_far: float, s_near: float, s_far: float,
		keep_out: Array[Rect2], seed_value: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Vector3] = []
	var z := near
	while z > far:
		var t := clampf((near - z) / (near - far), 0.0, 1.0)
		var s := lerpf(s_near, s_far, t)
		var w := lerpf(w_near, w_far, t)
		var x := -w + rng.randf() * s
		while x < w:
			var p := Vector2(x + rng.randf_range(-0.2, 0.2) * s, z + rng.randf_range(-0.3, 0.3) * s)
			var free := true
			for r in keep_out:
				if r.has_point(p):
					free = false
			# The edges ragged, not ruled.
			if free and (absf(p.x) < w - 2.0 or rng.randf() < 0.5):
				out.append(Vector3(p.x, 0, p.y))
			x += s
		z -= s
	return out


## People at `spots` (their feet's height added from `ground`.y unless a spot has its own),
## facing `toward`, in three poses; `rim` how hard the stage picks out their edges.
func _place_crowd(spots: Array[Vector3], toward: Vector3, rim: float, phones: float, own_height := false) -> void:
	var look: Dictionary = LOOKS[variant]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + spots.size()
	var poses: Array = [[], [], []]
	for p in spots:
		var at := p if own_height else Vector3(p.x, toward.y, p.z)
		var roll := rng.randf()
		var kind := 0 if roll < 0.58 else (1 if roll < 0.82 else 2)
		var basis := _facing(Vector3(toward.x, 0, toward.z) - Vector3(at.x, 0, at.z), rng.randf_range(-0.35, 0.35))
		poses[kind].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.9, 1.07)), at))
	var shader := preload("res://core/venues/shaders/stage_crowd.gdshader")
	for kind in 3:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("rim_colour", look["wash"][0])
		m.set_shader_parameter("rim_colour_b", look["wash"][1])
		m.set_shader_parameter("rim", rim)
		_crowd_mats.append(m)
		var node := _many("Crowd%d" % kind, _mesh("Person%d" % kind), poses[kind], m)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crowd_count += spots.size()
	# The phones, in the raised hands of the second pose, as their own MultiMesh of screens.
	var phone := QuadMesh.new()
	phone.size = Vector2(0.06, 0.11)
	phone.center_offset = Vector3(0.2, 1.9, -0.33)
	var screen := ShaderMaterial.new()
	screen.shader = preload("res://core/venues/shaders/stage_phone.gdshader")
	screen.set_shader_parameter("strength", phones)
	_crowd_mats.append(screen)
	_many("Phones", phone, poses[1], screen)


## The front-of-house tent out in the field: a platform, four poles and a peaked canvas roof,
## two consoles on the platform with their screens lit, and the engineers at them.
func _build_foh(at: Vector3) -> void:
	var canvas := _paint(Color(0.78, 0.77, 0.74) if variant == SOUNDCHECK else Color(0.22, 0.22, 0.24), 0.85)
	var steel := _paint(Color(0.5, 0.5, 0.52), 0.45, 0.7)
	ZoneKit.block(self, Vector3(6.0, 0.4, 4.6), at + Vector3(0, 0.2, 0), _tolex(), "FohDeck")
	for cx in [-2.9, 2.9]:
		for cz in [-2.2, 2.2]:
			# A hair off the ground, so its foot is not in the platform's underside.
			ZoneKit.block(self, Vector3(0.07, 2.69, 0.07), at + Vector3(cx, 1.355, cz), steel, "FohPole")
	var hip := CylinderMesh.new()
	hip.top_radius = 0.02
	hip.bottom_radius = 0.7071
	hip.height = 1.3
	hip.radial_segments = 4
	hip.rings = 1
	var roof := MeshInstance3D.new()
	roof.name = "FohRoof"
	roof.mesh = hip
	roof.material_override = canvas
	roof.basis = Basis.from_scale(Vector3(6.3, 1.0, 4.9)) * Basis(Vector3.UP, PI * 0.25)
	roof.position = at + Vector3(0, 2.7 + 0.65, 0)
	add_child(roof)
	# The back wall of the tent (the side away from the stage), a valance round the others.
	ZoneKit.block(self, Vector3(5.8, 2.3, 0.04), at + Vector3(0, 1.55, -2.18), canvas, "FohWall")
	var glow_colour := Color(0.4, 0.7, 1.0)
	for cx in [-1.1, 1.1]:
		ZoneKit.block(self, Vector3(1.6, 0.85, 0.8), at + Vector3(cx, 0.4 + 0.425, 0.6), _tolex(), "FohConsole")
		var face := ZoneKit.block(self, Vector3(1.4, 0.02, 0.6), at + Vector3(cx, 0.4 + 0.86, 0.6),
				ZoneKit.glow(glow_colour, 0.35 if variant == SOUNDCHECK else 0.7), "FohSurface")
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var screen := ZoneKit.block(self, Vector3(0.6, 0.38, 0.03), at + Vector3(cx, 0.4 + 1.25, 1.0),
				ZoneKit.glow(glow_colour, 0.6 if variant == SOUNDCHECK else 1.1), "FohScreen")
		screen.rotation.x = -0.25
	var crew := _crew_material()
	for spec in [[Vector3(-1.1, 0.4, -0.15), 0.1], [Vector3(1.0, 0.4, -0.1), -0.2], [Vector3(2.4, 0.4, -1.2), 0.6]]:
		var person := _piece("Person0", Transform3D(_facing(Vector3(0, 0, 1), spec[1]), at + spec[0]))
		person.material_override = crew
		person.name = "FohCrew"


func _crew_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/stage_crowd.gdshader")
	m.set_shader_parameter("body", Color(0.05, 0.05, 0.055) if variant == HEADLINE else Color(0.09, 0.09, 0.1))
	m.set_shader_parameter("rim", 0.0 if variant == SOUNDCHECK else 0.4)
	m.set_shader_parameter("rim_colour", LOOKS[variant]["rim"])
	m.set_shader_parameter("liveliness", 0.15)
	return m


## Two laser units on the front of the stage, each fanning seven green beams out over the crowd
## and sweeping them side to side (_process); on the beat they burn brighter.
func _set_up_the_lasers() -> void:
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.no_depth_test = false
	_laser_mat.albedo_color = Color(0.1, 1.0, 0.25) * 0.3
	_laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := CylinderMesh.new()
	beam.top_radius = 0.008
	beam.bottom_radius = 0.03
	beam.height = 1.0
	beam.radial_segments = 6
	beam.cap_top = false
	beam.cap_bottom = false
	var beam_mesh := _plain(beam)
	var reach := 80.0
	for side in [-1.0, 1.0]:
		var unit_at := Vector3(side * 4.2, RIG - 0.35, truss_lines()[0].z)
		ZoneKit.block(self, Vector3(0.36, 0.22, 0.4), unit_at + Vector3(0, 0.1, 0), _black(), "LaserUnit")
		var fan := Node3D.new()
		fan.name = "Laser%d" % _lasers.size()
		fan.position = unit_at
		add_child(fan)
		_lasers.append(fan)
		for k in 7:
			var b := MeshInstance3D.new()
			b.name = "LaserBeam"
			b.mesh = beam_mesh
			b.material_override = _laser_mat
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Along the fan's -Z, spread across it; the cylinder's narrow top at the unit.
			var dir := Basis(Vector3.UP, (k - 3) * 0.13) * Vector3(0, 0, -1)
			b.transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
					* Basis.from_scale(Vector3(1, reach, 1)), dir * reach * 0.5)
			fan.add_child(b)


# --- the far side of the field (Headline night, Soundcheck) --------------------------------------

## Past the crowd: food stalls along the back of the field, a ferris wheel turning off to one
## side, and a ring of trees round it all. Lit at night; at the soundcheck, the sun on them.
func _build_the_far_side(night: bool) -> void:
	if not night:
		_build_foh(Vector3(0, -DECK, -36.0))
	_build_stalls(night)
	_build_wheel(night)
	_plant_trees(night)


func _build_stalls(night: bool) -> void:
	var colours := [Color(0.8, 0.2, 0.15), Color(0.95, 0.75, 0.15), Color(0.15, 0.45, 0.8), Color(0.2, 0.6, 0.3),
			Color(0.75, 0.3, 0.6), Color(0.95, 0.5, 0.15)]
	var white := _paint(Color(0.82, 0.8, 0.76), 0.8)
	var bulbs: Array = []
	var i := 0
	var x := -48.0
	while x <= 48.0:
		if absf(x) < 6.0:
			x += 8.0
			continue
		var at := Vector3(x, -DECK, -84.0 + absf(x) * 0.12)
		var stall := Node3D.new()
		stall.name = "Stall%d" % i
		# Its hatch (+Z) toward the stage: its back (-Z) looks away from it.
		stall.transform = Transform3D(_facing(at - Vector3(0, at.y, front_edge())), at)
		add_child(stall)
		var c: Color = colours[i % colours.size()]
		ZoneKit.block(stall, Vector3(4.0, 2.6, 2.4), Vector3(0, 1.3, 0), _paint(c.darkened(0.35), 0.8), "StallBody")
		# The awning out over the hatch, toward the field.
		var awning := ZoneKit.block(stall, Vector3(4.2, 0.06, 1.3), Vector3(0, 2.45, 1.75), _paint(c, 0.7), "Awning")
		awning.rotation.x = 0.25
		ZoneKit.block(stall, Vector3(4.1, 0.5, 0.06), Vector3(0, 2.95, 1.23), white, "StallSign")
		var hatch := ZoneKit.block(stall, Vector3(2.8, 0.9, 0.04), Vector3(0, 1.55, 1.21),
				ZoneKit.glow(Color(1.0, 0.75, 0.45), 1.4) if night else _paint(Color(0.05, 0.05, 0.05), 0.6), "Hatch")
		hatch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if night:
			for k in 9:
				bulbs.append(stall.transform * Vector3(-2.0 + k * 0.5, 2.8 - 0.12 * sin(k / 8.0 * PI), 2.45))
		i += 1
		x += 8.0
	if night:
		var bulb := SphereMesh.new()
		bulb.radius = 0.06
		bulb.height = 0.12
		bulb.radial_segments = 8
		bulb.rings = 4
		var spots: Array = []
		for b: Vector3 in bulbs:
			spots.append(Transform3D(Basis.IDENTITY, b))
		_many("StallBulbs", bulb, spots, ZoneKit.glow(Color(1.0, 0.7, 0.4), 2.2))


## The ferris wheel: an A-frame either side of the hub, a double rim on spokes that turns,
## gondolas that hang plumb, and at night bulbs all round the rims and down the spokes.
func _build_wheel(night: bool) -> void:
	var at := WHEEL_AT + Vector3(0, -DECK, 0)
	var hub_y := WHEEL_RADIUS + 3.0
	var white := _paint(Color(0.82, 0.82, 0.84) if not night else Color(0.12, 0.12, 0.14), 0.5, 0.4)
	var holder := Node3D.new()
	holder.name = "FerrisWheel"
	holder.position = at
	# Its face toward the stage.
	holder.basis = _facing(Vector3(-at.x, 0, -at.z) * -1.0)
	add_child(holder)
	# The A-frames: four legs from the ground to the axle, one mesh.
	var legs: Array = []
	for side in [-1.0, 1.0]:
		for lean in [-1.0, 1.0]:
			var foot := Vector3(lean * 7.0, 0, side * 2.2)
			var head := Vector3(0, hub_y, side * 1.1)
			var bar := BoxMesh.new()
			bar.size = Vector3(0.35, 0.35, foot.distance_to(head))
			legs.append([bar, Transform3D(Basis.looking_at(head - foot, Vector3.UP), (foot + head) * 0.5)])
	var frame := MeshInstance3D.new()
	frame.name = "WheelLegs"
	frame.mesh = _merged(legs)
	frame.material_override = white
	holder.add_child(frame)
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	_wheel.position = Vector3(0, hub_y, 0)
	holder.add_child(_wheel)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var drum := CylinderMesh.new()
	drum.top_radius = 0.8
	drum.bottom_radius = 0.8
	drum.height = 2.4
	hub.mesh = drum
	hub.rotation.x = PI * 0.5
	hub.material_override = white
	_wheel.add_child(hub)
	var ring := TorusMesh.new()
	ring.inner_radius = WHEEL_RADIUS - 0.2
	ring.outer_radius = WHEEL_RADIUS + 0.2
	ring.rings = 64
	ring.ring_segments = 6
	for dz in [-0.9, 0.9]:
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		rim.mesh = ring
		rim.rotation.x = PI * 0.5
		rim.position.z = dz
		rim.material_override = white
		_wheel.add_child(rim)
	var spokes := 20
	var lights: Array = []
	var gondola := BoxMesh.new()
	gondola.size = Vector3(1.6, 1.5, 1.4)
	var colours := [Color(0.9, 0.2, 0.2), Color(0.95, 0.8, 0.2), Color(0.2, 0.5, 0.9), Color(0.25, 0.7, 0.35)]
	var bars: Array = []
	for k in spokes:
		var a := TAU * k / spokes
		var dir := Vector3(cos(a), sin(a), 0)
		for dz in [-0.9, 0.9]:
			var bar := BoxMesh.new()
			bar.size = Vector3(0.1, WHEEL_RADIUS, 0.1)
			bars.append([bar, Transform3D(Basis(Vector3.BACK, a - PI * 0.5), dir * WHEEL_RADIUS * 0.5 + Vector3(0, 0, dz))])
			for j in 6:
				lights.append(Transform3D(Basis.IDENTITY, dir * WHEEL_RADIUS * (j + 1) / 6.5 + Vector3(0, 0, dz)))
		for j in 3:
			var b := a + TAU / spokes * j / 3.0
			for dz in [-1.05, 1.05]:
				lights.append(Transform3D(Basis.IDENTITY, Vector3(cos(b), sin(b), 0) * WHEEL_RADIUS + Vector3(0, 0, dz)))
		# The gondola, on a pivot at the rim so it can hang plumb as the wheel turns.
		var hang := Node3D.new()
		hang.name = "Gondola"
		hang.position = dir * WHEEL_RADIUS
		_wheel.add_child(hang)
		var car := MeshInstance3D.new()
		car.name = "Car"
		car.mesh = _merged([[gondola, Transform3D(Basis.IDENTITY, Vector3(0, -1.0, 0))],
				[gondola, Transform3D(Basis.from_scale(Vector3(1.08, 0.08, 1.08)), Vector3(0, -0.22, 0))]])
		car.material_override = _paint(colours[k % colours.size()].darkened(0.2 if not night else 0.7), 0.6)
		hang.add_child(car)
		_gondolas.append(hang)
	var spoke_mesh := MeshInstance3D.new()
	spoke_mesh.name = "Spokes"
	spoke_mesh.mesh = _merged(bars)
	spoke_mesh.material_override = white
	_wheel.add_child(spoke_mesh)
	var bulb := SphereMesh.new()
	bulb.radius = 0.14
	bulb.height = 0.28
	bulb.radial_segments = 6
	bulb.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bulb
	mm.instance_count = lights.size()
	var hues := [Color(1.0, 0.3, 0.5), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.35)]
	for k in lights.size():
		mm.set_instance_transform(k, lights[k])
		mm.set_instance_color(k, hues[(k / 6) % hues.size()])
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.albedo_color = Color(2.6, 2.6, 2.6) if night else Color(0.75, 0.75, 0.72)
	var bulbs := MultiMeshInstance3D.new()
	bulbs.name = "WheelBulbs"
	bulbs.multimesh = mm
	bulbs.material_override = glow
	bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel.add_child(bulbs)


## Trees round the field (firs.glb, its snow turned to needles), in a broken ring.
func _plant_trees(night: bool) -> void:
	var firs := (load(MODELS + "firs.glb") as PackedScene).instantiate()
	var needles := _paint(Color(0.012, 0.016, 0.014) if night else Color(0.07, 0.12, 0.06), 0.9)
	var bark := _paint(Color(0.02, 0.015, 0.012) if night else Color(0.12, 0.09, 0.06), 0.9)
	var swap := {"needles": needles, "snow": needles, "bark": bark}
	var shapes: Array[Mesh] = []
	for node in firs.find_children("*", "MeshInstance3D", true, false):
		var mesh := ((node as MeshInstance3D).mesh as ArrayMesh).duplicate() as ArrayMesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.surface_set_material(s, swap[m.resource_name])
		shapes.append(mesh)
	firs.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var per: Array = []
	for s in shapes:
		per.append([])
	var centre := Vector2(0, -70)
	for k in 420:
		var a := rng.randf() * TAU
		var r := rng.randf_range(150.0, 240.0)
		var p := centre + Vector2(cos(a), sin(a)) * r
		var h := rng.randf_range(9.0, 18.0)
		per[k % shapes.size()].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * 0.8, h, h * 0.8)),
				Vector3(p.x, -DECK, p.y)))
	for s in shapes.size():
		_many("Trees%d" % s, shapes[s], per[s])


# --- the soundcheck -------------------------------------------------------------------------

## Flags on poles along both sides of the field and round the desk tent, flying in the breeze.
func _fly_the_flags() -> void:
	var poles: Array = []
	var flags: Array = []
	var colours := [Color(0.9, 0.2, 0.25), Color(1.0, 0.8, 0.15), Color(0.2, 0.55, 0.95), Color(0.95, 0.45, 0.75),
			Color(0.3, 0.75, 0.4), Color(1.0, 0.55, 0.15)]
	var spots: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var z := -12.0
		while z > -76.0:
			spots.append(Vector3(side * (28.0 + absf(z) * 0.08), -DECK, z))
			z -= 9.0
	for cx in [-4.5, 4.5]:
		spots.append(Vector3(cx, -DECK, -33.0))
	var tall := 7.0
	for p in spots:
		poles.append(Transform3D(Basis.IDENTITY, p + Vector3(0, tall * 0.5, 0)))
		# The flag flies off the pole downwind (+X), its top at the pole's top.
		flags.append(Transform3D(Basis(Vector3.UP, 0.3), p + Vector3(0.05, tall - 0.5, 0)))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.05
	pole.height = tall
	pole.radial_segments = 8
	_many("FlagPoles", pole, poles, _paint(Color(0.75, 0.75, 0.77), 0.4, 0.7), true)
	var cloth := QuadMesh.new()
	cloth.size = Vector2(1.6, 1.0)
	cloth.subdivide_width = 10
	cloth.subdivide_depth = 2
	cloth.center_offset = Vector3(0.8, 0, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cloth
	mm.instance_count = flags.size()
	for i in flags.size():
		mm.set_instance_transform(i, flags[i])
		mm.set_instance_color(i, colours[i % colours.size()])
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/stage_flag.gdshader")
	m.set_shader_parameter("size_x", 1.6)
	var node := MultiMeshInstance3D.new()
	node.name = "Flags"
	node.multimesh = mm
	node.material_override = m
	add_child(node)


## The crew about the stage between checks: a tech on each wing, one at the barrier, and a
## work light on a stand left on at the stage-left wing.
func _crew_the_stage() -> void:
	var crew := _crew_material()
	var half := live_room_half()
	for spec in [[Vector3(-half - 2.0, 0, 0.8), Vector3(1, 0, 0)], [Vector3(half + 1.3, 0, -1.2), Vector3(-1, 0, 0.3)],
			[Vector3(3.0, -DECK, barricade_z() - 0.7), Vector3(0, 0, 1)], [Vector3(-6.5, -DECK, front_edge() - 1.4), Vector3(0.3, 0, 1)]]:
		var person := _piece("Person0", Transform3D(_facing(spec[1]), spec[0]))
		person.material_override = crew
		person.name = "Crew"
	var steel := _paint(Color(0.2, 0.2, 0.21), 0.5, 0.6)
	var stand := Vector3(-half - 1.2, 0, -2.2)
	ZoneKit.block(self, Vector3(0.04, 1.8, 0.04), stand + Vector3(0, 0.9, 0), steel, "WorkLightStand")
	var head := ZoneKit.block(self, Vector3(0.4, 0.3, 0.08), stand + Vector3(0, 1.9, 0), steel, "WorkLight")
	head.rotation = Vector3(-0.3, -0.8, 0)
	var lens := ZoneKit.block(self, Vector3(0.34, 0.24, 0.01), stand + Vector3(0, 1.9, 0) + Basis.from_euler(head.rotation) * Vector3(0, 0, -0.045),
			ZoneKit.glow(Color(1.0, 0.95, 0.85), 1.6), "WorkLightLens")
	lens.rotation = head.rotation


# --- the arena ------------------------------------------------------------------------------

## The arena: its floor, the bowl of seats round it in two tiers with a concourse between, the
## walls behind the stage, the roof with its rigging grid and house lights, and the screens
## flown beside the stage.
func _build_the_arena() -> void:
	var end_z := back_edge() + 3.0
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "ArenaFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_HALF * 2.0 + 2.0, end_z - ARENA_FRONT + 2.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -DECK, (end_z + ARENA_FRONT) * 0.5)
	floor_mesh.material_override = Materials.cached_scanned("stage_arena_floor", "concrete_floor_worn_001", "2k", 3.0,
			Color(0.22, 0.22, 0.24))
	add_child(floor_mesh)
	var concrete := Materials.cached_scanned("stage_bowl", "concrete_floor_worn_001", "2k", 4.0, Color(0.4, 0.39, 0.38))
	var bowl := _bowl_mesh(end_z)
	var stands := MeshInstance3D.new()
	stands.name = "Bowl"
	stands.mesh = bowl
	var m := concrete.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	stands.material_override = m
	add_child(stands)
	# The end wall behind the stage, closing the bowl.
	var outer := ARENA_HALF + _bowl_depth() + 2.0
	ZoneKit.block(self, Vector3(outer * 2.0, ARENA_ROOF + DECK, 0.6), Vector3(0, (ARENA_ROOF - DECK) * 0.5, end_z + 0.3),
			_paint(Color(0.06, 0.06, 0.07), 0.9), "EndWall")
	# The roof: a dark deck over everything, a grid of steel under it, catwalks, house lights.
	var front := ARENA_FRONT - _bowl_depth() - 2.0
	var roof_y := ARENA_ROOF + 1.2
	ZoneKit.block(self, Vector3(outer * 2.0, 0.4, end_z - front + 1.0), Vector3(0, roof_y + 0.2, (end_z + front) * 0.5),
			_paint(Color(0.05, 0.05, 0.055), 0.9), "ArenaRoof")
	var beams: Array = []
	var steel := _paint(Color(0.16, 0.16, 0.17), 0.6, 0.5)
	var step := 6.0
	var gx := -outer + 3.0
	while gx < outer:
		beams.append(Transform3D(Basis.from_scale(Vector3(1, 1, end_z - front)), Vector3(gx, roof_y - 0.5, (end_z + front) * 0.5)))
		gx += step
	var gz := front + 3.0
	while gz < end_z:
		beams.append(Transform3D(Basis.from_scale(Vector3(outer * 2.0, 1, 1)), Vector3(0, roof_y - 0.9, gz)))
		gz += step
	var beam := BoxMesh.new()
	beam.size = Vector3(1.0, 0.6, 1.0)
	# A unit box scaled per beam: long the way it runs, 0.3 m across.
	var runs_z: Array = []
	var runs_x: Array = []
	for b: Transform3D in beams:
		if b.basis.get_scale().z > 1.5:
			runs_z.append(Transform3D(Basis.from_scale(Vector3(0.3, 1, b.basis.get_scale().z)), b.origin))
		else:
			runs_x.append(Transform3D(Basis.from_scale(Vector3(b.basis.get_scale().x, 1, 0.3)), b.origin))
	_many("GridZ", beam, runs_z, steel)
	_many("GridX", beam, runs_x, steel)
	# The house lights in the roof, half down: rows of warm discs.
	var lamps: Array = []
	gx = -outer + 6.0
	while gx < outer:
		gz = front + 6.0
		while gz < end_z - 4.0:
			lamps.append(Transform3D(Basis.IDENTITY, Vector3(gx, roof_y - 0.02, gz)))
			gz += 9.0
		gx += 9.0
	var disc := CylinderMesh.new()
	disc.top_radius = 0.35
	disc.bottom_radius = 0.35
	disc.height = 0.04
	disc.radial_segments = 12
	_many("HouseLights", disc, lamps, ZoneKit.glow(Color(1.0, 0.78, 0.5), 0.9))
	# The barrier, and the floor's own two side screens flown either side of the stage.
	var spots: Array = []
	var reach := deck_half() + 2.0
	var x := -reach + 0.5
	while x < reach:
		spots.append(Transform3D(Basis.IDENTITY, Vector3(x, -DECK, barricade_z())))
		x += 1.0
	_many("Barricade", _mesh("Barricade"), spots, null, true)
	# A few warm downlights still on over the stands, and coloured washes on the floor crowd.
	var look: Dictionary = LOOKS[variant]
	for side in [-1.0, 1.0]:
		_wash(Vector3(side * 12.0, ARENA_ROOF - 2.0, -30.0), Vector3(side * 6.0, -DECK, -28.0), look["wash"][0 if side < 0 else 1],
				7.0, 34.0, 50.0, 1.0, "FloorWash")


## How deep the whole bowl is, floor's edge to its back wall.
func _bowl_depth() -> float:
	return (LOWER_ROWS + UPPER_ROWS) * ROW_DEEP + CONCOURSE


## The line round the arena floor `out` metres past its edge: up the right side from the end
## wall, round the front corners, and back down the left side. Pairs of [point, outward normal].
func _bowl_line(out: float, end_z: float) -> Array:
	var pts: Array = []
	var r := ARENA_CORNER
	var cx := ARENA_HALF - r
	var cz := ARENA_FRONT + r
	pts.append([Vector2(ARENA_HALF + out, end_z), Vector2(1, 0)])
	for k in 13:
		var a := -PI * 0.5 * k / 12.0
		var n := Vector2(cos(a), sin(a))
		pts.append([Vector2(cx, cz) + n * (r + out), n])
	for k in 13:
		var a := -PI * 0.5 - PI * 0.5 * k / 12.0
		var n := Vector2(cos(a), sin(a))
		pts.append([Vector2(-cx, cz) + n * (r + out), n])
	pts.append([Vector2(-ARENA_HALF - out, end_z), Vector2(-1, 0)])
	return pts


## The row heights: the dasher wall, then the lower tier, the concourse, the upper tier.
func _row(i: int) -> Dictionary:
	var lower := i < LOWER_ROWS
	var y := -DECK + DASHER
	var out := float(i) * ROW_DEEP
	if lower:
		y += i * LOWER_RISE
	else:
		y += LOWER_ROWS * LOWER_RISE + CONCOURSE_WALL + (i - LOWER_ROWS) * UPPER_RISE
		out += CONCOURSE
	return {"y": y, "out": out, "rise": LOWER_RISE if lower else UPPER_RISE}


## The bowl as one mesh: each row's tread and the riser up to the next, the dasher wall round
## the floor, the concourse and its wall, and the back wall up to the roof.
func _bowl_mesh(end_z: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var band := func(o0: float, y0: float, o1: float, y1: float) -> void:
		var a := _bowl_line(o0, end_z)
		var b := _bowl_line(o1, end_z)
		for k in a.size() - 1:
			var p0 := Vector3(a[k][0].x, y0, a[k][0].y)
			var p1 := Vector3(a[k + 1][0].x, y0, a[k + 1][0].y)
			var q0 := Vector3(b[k][0].x, y1, b[k][0].y)
			var q1 := Vector3(b[k + 1][0].x, y1, b[k + 1][0].y)
			for v in [p0, p1, q1, p0, q1, q0]:
				st.add_vertex(v)
	var floor_y := -DECK
	band.call(0.0, floor_y, 0.0, floor_y + DASHER)
	var rows := LOWER_ROWS + UPPER_ROWS
	for i in rows:
		var r := _row(i)
		var y: float = r["y"]
		var o: float = r["out"]
		band.call(o, y, o + ROW_DEEP, y)
		if i == LOWER_ROWS - 1:
			# The concourse, level, then its wall up to the upper tier.
			band.call(o + ROW_DEEP, y, o + ROW_DEEP + CONCOURSE, y)
			band.call(o + ROW_DEEP + CONCOURSE, y, o + ROW_DEEP + CONCOURSE, (_row(i + 1)["y"] as float))
		elif i < rows - 1:
			band.call(o + ROW_DEEP, y, o + ROW_DEEP, (_row(i + 1)["y"] as float))
		else:
			band.call(o + ROW_DEEP, y, o + ROW_DEEP, ARENA_ROOF + 1.2)
	st.generate_normals()
	return st.commit()


## The seats along every row, a share of them filled -- fuller near the stage -- and a crowd on
## the floor from the barrier back to the mixing desk riser and past it.
func _fill_the_arena() -> void:
	var end_z := back_edge() + 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seats: Array = []
	var sat: Array[Vector3] = []
	var rows := LOWER_ROWS + UPPER_ROWS
	for i in rows:
		var r := _row(i)
		var line := _bowl_line(float(r["out"]) + 0.38, end_z)
		var carry := 0.0
		for k in line.size() - 1:
			var a: Vector2 = line[k][0]
			var b: Vector2 = line[k + 1][0]
			var n: Vector2 = line[k][1]
			var length := a.distance_to(b)
			var d := carry
			while d < length:
				var p := a.lerp(b, d / length)
				var at := Vector3(p.x, r["y"], p.y)
				seats.append(Transform3D(_facing(Vector3(-n.x, 0, -n.y)), at))
				# Nobody sits behind the stage line; fuller toward the stage end and low down.
				var fill := 0.0 if p.y > front_edge() - 2.0 else lerpf(0.75, 0.3, clampf(-p.y / 70.0, 0.0, 1.0))
				fill *= lerpf(1.0, 0.7, float(i) / rows)
				if rng.randf() < fill:
					sat.append(at + Vector3(0, 0.0, 0))
				d += 0.62
			carry = d - length
	_many("Seats", _mesh("Seat"), seats)
	_place_crowd(sat, Vector3(0, 6.0, front_edge()), 1.0, 1.4, true)
	var keep_out: Array[Rect2] = [Rect2(-4.0, -38.0, 8.0, 6.0)]
	var floor_spots := _crowd_spots(barricade_z() - 1.0, ARENA_FRONT + 6.0, 16.0, ARENA_HALF - 3.0, 0.62, 0.95, keep_out, 13)
	_place_crowd(floor_spots, Vector3(0, -DECK, front_edge()), 1.6, 1.4)
	# The desk riser on the floor, its engineers.
	var at := Vector3(0, -DECK, -35.0)
	ZoneKit.block(self, Vector3(6.0, 0.6, 4.0), at + Vector3(0, 0.3, 0), _tolex(), "FohRiser")
	for cx in [-1.1, 1.1]:
		ZoneKit.block(self, Vector3(1.6, 0.85, 0.8), at + Vector3(cx, 0.6 + 0.425, 0.4), _tolex(), "FohConsole")
		var face := ZoneKit.block(self, Vector3(1.4, 0.02, 0.6), at + Vector3(cx, 0.6 + 0.86, 0.4),
				ZoneKit.glow(Color(0.4, 0.7, 1.0), 0.7), "FohSurface")
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Exit signs over the vomitories in the concourse wall.
	var wall := _row(LOWER_ROWS - 1)
	var line := _bowl_line(float(wall["out"]) + ROW_DEEP + CONCOURSE - 0.05, end_z)
	var signs: Array = []
	var doors: Array = []
	for k in range(2, line.size() - 1, 4):
		var p: Vector2 = line[k][0]
		var n: Vector2 = line[k][1]
		var y: float = wall["y"]
		var face := _facing(Vector3(-n.x, 0, -n.y))
		doors.append(Transform3D(face, Vector3(p.x, y + 1.2, p.y) - Vector3(n.x, 0, n.y) * 0.02))
		signs.append(Transform3D(face, Vector3(p.x, y + 2.7, p.y) - Vector3(n.x, 0, n.y) * 0.06))
	var door := BoxMesh.new()
	door.size = Vector3(2.4, 2.4, 0.02)
	_many("Vomitories", door, doors, _paint(Color(0.01, 0.01, 0.012), 0.9))
	var sign := BoxMesh.new()
	sign.size = Vector3(0.6, 0.22, 0.04)
	_many("ExitSigns", sign, signs, ZoneKit.glow(Color(0.15, 1.0, 0.35), 1.6))


# --- the zones ------------------------------------------------------------------------------

## The zones in the stage's own kit: a rolling riser skirted in serge with a drum rug on it, a
## booth of clear acrylic shields in a black frame, the lattice's square in fluoro gaffer, a
## road-case table on aluminium legs, the keys on a truss-aluminium stand.
func _dress_zones() -> void:
	var z := zones()
	var frame := _paint(Color(0.05, 0.05, 0.055), 0.5, 0.3)
	var top := _tolex()
	var alu := _alu()

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var rug := _paint(Color(0.22, 0.06, 0.07), 0.95)
	rug.normal_enabled = true
	rug.normal_texture = Materials.grain("stage_rug", 2.0, 0.8)
	rug.uv1_triplanar = true
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, rug, _drape())

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var acrylic := StandardMaterial3D.new()
	acrylic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	acrylic.albedo_color = Color(0.7, 0.75, 0.8, 0.1)
	acrylic.roughness = 0.04
	acrylic.metallic_specular = 0.9
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, frame, acrylic)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), _paint(Color(0.04, 0.04, 0.045), 0.4, 0.6),
			ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(0.95, 0.9, 1.0), 1.2, 60.0, 3.2,
			frame)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	var tape: StandardMaterial3D = _paint(Color(0.3, 1.0, 0.35), 0.6) if variant == SOUNDCHECK \
			else ZoneKit.glow(Color(0.3, 1.0, 0.4), 0.9)
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.05, tape)

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, top, alu)
	_dress_prop_shelf(top, alu, Color(0.85, 0.88, 1.0) if variant == HEADLINE else Color(1.0, 0.8, 0.55))

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, alu, top)


## The mirror on the open deck at the footprint's edge, framed in truss aluminium.
func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.04, 0.012, _alu())


## The tracks' colours here (TrackColours), in its STANDARD order.
## Stage gels and LED: saturated and bright, a touch cold, the magentas and blues pushed.
func track_palette() -> Array:
	return [
		Color(0.95, 0.18, 0.28), Color(1.00, 0.48, 0.12), Color(1.00, 0.84, 0.16), Color(0.62, 0.95, 0.18),
		Color(0.16, 0.88, 0.42), Color(0.10, 0.84, 0.82), Color(0.22, 0.62, 1.00), Color(0.32, 0.32, 1.00),
		Color(0.62, 0.26, 1.00), Color(0.95, 0.20, 0.82), Color(1.00, 0.50, 0.74), Color(0.68, 0.70, 0.76),
	]
