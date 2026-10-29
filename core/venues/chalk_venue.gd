class_name ChalkVenue
extends Venue

## The chalk zone: the studio stood on a blackboard the size of the world, with everything past
## the edge of the floor drawn in neon chalk and hanging in the dark. Stars and planets and
## lightning bolts float at every distance, bobbing as if they had just been drawn and had not
## quite settled; there is dust in the air, and the working floor is outlined in chalk the way
## a stage is taped.
##
## In the second arrangement the doodles are gathered in: the room the studio would have stands
## round the floor drawn in chalk lines -- its edges, a door, a window with the moon in it, a
## clock, panels, lamps hanging from a ceiling that is only a line -- and behind the zones the
## board itself stands up, a wall of slate taller than any of them, the session written on it.
##
## It moves to the music: the chalk itself glows brighter on a loud passage, and the doodles
## nearest the desk jump a little on the beat.

const FLOOR_EXTENT := 300.0
const DOODLE_COUNT := 64
const SEED := 11
## The arrangements.
const OPEN_SKY := 0
const SKETCHED_ROOM := 1
const CLASSROOM := 2
## The sketched room: its ceiling line (the live room's own height), and the board wall behind
## the zones, standing up past it.
const ROOM_HEIGHT := LIVE_ROOM_HEIGHT
const BOARD_HEIGHT := 5.6
const BOARD_Z := LIVE_ROOM_BACK + 0.15
## The classroom: a tall old schoolroom, its ceiling well over the board, which stands on the back
## wall from the dado rail up; tall sash windows down the left wall, each a pair of z extents.
const CLASS_HEIGHT := 5.4
const CLASS_BOARD_FOOT := 0.97
const CLASS_BOARD_TOP := 4.95
const DADO := 0.9
const SILL := 1.0
const HEAD := 4.4
## Three over the desks pushed to that side, one between the cassette rack and the booth, and one
## behind the booth (no radiator there: see _radiator_under).
const CLASS_WINDOWS: Array[Vector2] = [Vector2(-3.25, -1.95), Vector2(-1.05, 0.25), Vector2(1.15, 2.45),
		Vector2(7.2, 8.5), Vector2(10.1, 11.4)]
## The way the moonlight travels in through them: from high on the left, a little from behind
## the board, so its patches fall across the desks pushed to that side and onto the floor by the
## mix position.
const MOON_WAY := Vector3(1.0, -0.62, -0.3)
## How far the floor runs past the room every way under the open sky. The sketched room is drawn
## round the room's own width, so there it stops at the lines.
const OPEN_FLOOR := 3.0
## The most sections the board has room for across its top.
const BOARD_SECTIONS := 8
## Seconds to rub old writing out (the new is drawn on as it goes), and between looks at the
## session when it has news.
const RUB_OUT := 0.6
const REREAD_EVERY := 0.5

var _floor_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _doodles: Array[Node3D] = []
var _rest: Array[Vector3] = []
var _phase: Array[float] = []
var _smoothed := 0.0
var _clock := 0.0
## Drawings being drawn right now: [node, metres down, metres per second, wipe after].
var _drawing: Array = []
var _art: Array[MeshInstance3D] = []
var _comets: Array = []  # [node, progress, wait]
var _next_redraw := 5.0
## What the board says about the session now (board_from), and the node it is written in.
var board: Dictionary = {}
var _session: Node3D
var _board_stale := false
var _reread_wait := 0.0
var _rewrites := 0
## Old writing being rubbed out: [node, 0..1 gone].
var _rubbing: Array = []
## Seconds since new writing started going on, or -1 when it is all there.
var _writing_in := -1.0
var _rng := RandomNumberGenerator.new()
## The classroom's wall clock: its hour, minute and second hands' pivots.
var _clock_hands: Array[Node3D] = []


func venue_id() -> StringName:
	return &"chalk"


## Nothing to hang the roll board or the roulette panel on: they stand.
func back_wall_gear_stands() -> bool:
	return true


## Slate, with a chalk line drawn round every edge: the gear is part of the drawing.
func gear_style() -> GearStyle:
	var slate := GearStyle.paint(Color(0.1, 0.12, 0.115), 0.95, 0.0)
	return GearStyle.new() \
			.with("furniture", slate) \
			.with("chassis", GearStyle.paint(Color(0.07, 0.085, 0.08), 0.9, 0.05)) \
			.with("brushed", GearStyle.paint(Color(0.62, 0.64, 0.66), 0.95, 0.0)) \
			.with("trim", GearStyle.glow(Color(0.92, 0.94, 1.0), 0.9)) \
			.with("end_cheek", slate) \
			.with("lamp_shade", GearStyle.paint(Color(0.85, 0.87, 0.9), 0.95, 0.0)) \
			.with("loom_band", GearStyle.glow(Color(1.0, 0.25, 0.75), 0.8)) \
			.with("knob_cap", GearStyle.paint(Color(0.18, 0.22, 0.24), 0.95, 0.0))


func roll_board_chalky() -> bool:
	return true



func dress(env: Environment, key: DirectionalLight3D) -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://core/venues/shaders/chalk_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.36, 0.62)
	env.ambient_light_energy = 0.38
	env.glow_intensity = 1.1
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0
	env.set_glow_level(2, 0.8)
	env.set_glow_level(4, 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.04, 0.10)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 160.0
	env.fog_sky_affect = 0.0

	# Moonlight, cold and from high up: enough to model the gear, never enough to compete
	# with the colour the lamps put down.
	key.light_color = Color(0.70, 0.78, 1.0)
	key.light_energy = 0.55
	if variant == CLASSROOM:
		_dress_classroom(env, key)


func lamp_colour(index: int, _authored: Color) -> Color:
	return [Chalk.PINK, Chalk.CYAN, Chalk.LIME, Chalk.VIOLET][index % 4]


func lamp_energy(_index: int, authored: float) -> float:
	# Saturated colour at full strength stained the gear nearest each lamp -- the timeline went
	# lime -- so the chalk lamps are tints, not floods.
	return authored * 0.6


func _ready() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Chalkboard"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_EXTENT, FLOOR_EXTENT)
	ground.mesh = plane
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = preload("res://core/venues/shaders/chalkboard.gdshader")
	ground.material_override = _floor_mat
	add_child(ground)

	_rng.seed = SEED + 1
	_draw_floor()
	if variant == SKETCHED_ROOM:
		_sketch_the_room()
		_stand_the_board()
	elif variant == CLASSROOM:
		# The slate world goes on outside, under the windows, a little below the room's boards.
		ground.position.y = -0.03
		_build_classroom()
		_stand_the_board()
		_scatter_doodles(true)
		_join_constellations()
		_throw_comets()
	else:
		_scatter_doodles()
		_paint_rainbow()
		_join_constellations()
		_throw_comets()
	_draw_zones()
	if variant == CLASSROOM:
		_dust_the_moonlight()
	else:
		_add_dust()
	# Everything drawn on as you arrive, nearest first, the way a person would start with
	# what is in front of them and work outward.
	_art.sort_custom(func(a, b): return a.global_position.length_squared() < b.global_position.length_squared())
	for i in _art.size():
		_draw_on(_art[i], 0.15 + i * 0.045)


## The working footprint outlined, a chalk circle around the mix position, and a few marks
## scrawled near it: a stage taped out by someone who also likes to draw.
func _draw_floor() -> void:
	var lift := Vector3(0, 0.004, 0)
	var c := footprint_corners()
	var outline := PackedVector3Array()
	for i in 5:
		var p := c[i % 4]
		outline.append(Vector3(p.x, 0, p.y) + lift)
	var lines: Array = [_subdivide(outline, 0.25)]
	var ring := PackedVector3Array()
	for p in Chalk.loop(Vector3.ZERO, 1.35, 56):
		ring.append(Vector3(p.x, 0, p.y + 0.55) + lift)
	lines.append(ring)
	var floor_art := Chalk.drawing(lines, Chalk.WHITE * 0.45, 0.02, true, 2, SEED)
	floor_art.name = "FloorChalk"
	add_child(floor_art)

	if variant != OPEN_SKY:
		return
	# Out past the footprint, big floor doodles in colour -- arrows, a star, a spiral -- that
	# you see when you look down past the desk.
	var marks := [[Chalk.star(), Vector3(-5.8, 0, -5.5), 1.1, Chalk.YELLOW],
			[Chalk.spiral(), Vector3(6.0, 0, -5.3), 1.3, Chalk.CYAN],
			# Behind the desk, out past the zones on either side.
			[Chalk.heart(), Vector3(-10.4, 0, 3.0), 0.9, Chalk.PINK],
			[Chalk.lightning(), Vector3(10.4, 0, 2.2), 1.2, Chalk.LIME],
			# And past the back of the floor, behind the lattice and the booth.
			[Chalk.spiral(), Vector3(-6.6, 0, 14.4), 1.0, Chalk.VIOLET],
			[Chalk.star(), Vector3(4.6, 0, 14.2), 0.9, Chalk.ORANGE]]
	for i in marks.size():
		var flat: Array = []
		for line: PackedVector3Array in marks[i][0]:
			var laid := PackedVector3Array()
			for p in line:
				laid.append(marks[i][1] + Vector3(p.x, 0, -p.y) * marks[i][2] + lift)
			flat.append(laid)
		var art := Chalk.drawing(flat, marks[i][3], 0.035, true, 2, SEED + i)
		art.name = "FloorDoodle"
		add_child(art)
		_art.append(art)


## Drawn, like the zones: walked through.
func prop_shelf_solid() -> bool:
	return false


## The board is the whole world, and the floor is wherever you walk on it. Under the open sky it
## runs past the room every way, round the zones and in front of the desk; the sketched room is
## drawn round the zones' width, so there it is the desk, the floor either side of it out to the
## lines, and the zones.
func rooms() -> Array[Rect2]:
	if variant == OPEN_SKY:
		return [open_floor(OPEN_FLOOR)]
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


## The room, drawn: its outline on the floor, its corners up to a ceiling that is a line, and
## on its walls what a studio has -- a door, a window with the moon in it, a clock, foam
## panels, a pair of speakers on stands -- and lamps hanging down from the ceiling line.
func _sketch_the_room() -> void:
	var half := live_room_half()
	var z0 := (Studio.ROOM_FRONT - 0.3)
	var z1 := LIVE_ROOM_BACK
	var h := ROOM_HEIGHT
	var lines: Array = []
	var corners := [Vector3(-half, 0, z0), Vector3(half, 0, z0), Vector3(half, 0, z1), Vector3(-half, 0, z1)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		lines.append(PackedVector3Array([a + Vector3(0, 0.004, 0), b + Vector3(0, 0.004, 0)]))
		lines.append(PackedVector3Array([a + Vector3(0, h, 0), b + Vector3(0, h, 0)]))
		lines.append(PackedVector3Array([a, a + Vector3(0, h, 0)]))
	var walls: Array = []
	# The left wall: a door, and a window with the moon in it.
	# Down the length of the wall beside the desk, clear of the prop shelf and the rack behind.
	walls.append_array(_on_wall(_rect(1.0, 2.1, Vector2(0, 1.05)) + [Chalk.loop(Vector3(0.36, 1.0, 0), 0.04, 10)],
			Vector3(-half, 0, -2.0), PI * 0.5))
	var window := _rect(2.6, 1.8, Vector2(0, 2.3))
	window.append(PackedVector3Array([Vector3(0, 1.4, 0), Vector3(0, 3.2, 0)]))
	window.append(PackedVector3Array([Vector3(-1.3, 2.3, 0), Vector3(1.3, 2.3, 0)]))
	walls.append_array(_on_wall(window, Vector3(-half, 0, 1.6), PI * 0.5))
	walls.append_array(_on_wall(_scaled(Chalk.moon(), 0.32, Vector2(0.6, 2.75)), Vector3(-half, 0, 1.6), PI * 0.5))
	# The right wall: foam panels in a row, each ruled in wedges, beside the desk up to the table.
	for k in 5:
		var panel := _rect(0.9, 1.2, Vector2(0, 2.6))
		for w in [-0.3, 0.0, 0.3]:
			panel.append(PackedVector3Array([Vector3(w, 2.0, 0), Vector3(w, 3.2, 0)]))
		walls.append_array(_on_wall(panel, Vector3(half, 0, -2.8 + k * 1.55), -PI * 0.5))
	# The front wall: a clock, high, its hands at a little past ten, and an on-air light.
	var clock: Array = [Chalk.loop(Vector3.ZERO, 0.38, 32), Chalk.loop(Vector3.ZERO, 0.32, 32),
			PackedVector3Array([Vector3.ZERO, Vector3(-0.15, 0.1, 0)]),
			PackedVector3Array([Vector3.ZERO, Vector3(0.07, 0.27, 0)])]
	for t in 12:
		var a := TAU * t / 12.0
		clock.append(PackedVector3Array([Vector3(cos(a), sin(a), 0) * 0.27, Vector3(cos(a), sin(a), 0) * 0.31]))
	walls.append_array(_on_wall(_scaled(clock, 1.2, Vector2(-3.6, 3.5)), Vector3(0, 0, z0), 0.0))
	walls.append_array(_on_wall(_rect(1.2, 0.42, Vector2(3.6, 3.5)), Vector3(0, 0, z0), 0.0))
	# Speakers on stands in the front corners, angled in.
	for side in [-1.0, 1.0]:
		var at := Vector3(side * (half - 0.9), 0, z0 + 0.8)
		var spk := _box_lines(Vector3(0.36, 0.6, 0.32), Vector3(0, 1.45, 0))
		spk.append(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1.15, 0)]))
		spk.append(PackedVector3Array([Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0)]))
		spk.append(_placed(Chalk.loop(Vector3.ZERO, 0.12, 18), Vector3(0, 1.38, 0.161), 0.0))
		spk.append(_placed(Chalk.loop(Vector3.ZERO, 0.05, 12), Vector3(0, 1.62, 0.161), 0.0))
		var turn := Basis(Vector3.UP, -side * 0.5 + PI)
		for line: PackedVector3Array in spk:
			var placed := PackedVector3Array()
			for p in line:
				placed.append(at + turn * p)
			walls.append(placed)
	# Lamps hanging from the ceiling line, over the desk, over the floor behind it, and over the
	# neighbourhoods either side of the middle further back.
	for at in [Vector3(-2.6, 0, 0.6), Vector3(2.6, 0, 0.6), Vector3(-2.6, 0, 3.8), Vector3(2.6, 0, 3.8),
			Vector3(-5.6, 0, 7.6), Vector3(5.4, 0, 9.0)]:
		var lamp: Array = [PackedVector3Array([Vector3(0, h, 0), Vector3(0, h - 1.1, 0)])]
		lamp.append(Chalk.loop(Vector3.ZERO, 0.22, 20))
		for k in lamp[1].size():
			lamp[1][k] = Vector3(lamp[1][k].x, h - 1.4, lamp[1][k].y)
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			lamp.append(PackedVector3Array([Vector3(0, h - 1.1, 0), Vector3(cos(a) * 0.22, h - 1.4, sin(a) * 0.22)]))
		for line: PackedVector3Array in lamp:
			var placed := PackedVector3Array()
			for p in line:
				placed.append(at + p)
			walls.append(placed)
	var subdivided: Array = []
	for line: PackedVector3Array in lines:
		subdivided.append(_subdivide(line, 0.25))
	var shell := Chalk.drawing(subdivided, Chalk.WHITE * 0.28, 0.014, false, 2, SEED * 41)
	shell.name = "RoomSketch"
	add_child(shell)
	_art.append(shell)
	var fittings: Array = []
	for line: PackedVector3Array in walls:
		fittings.append(_subdivide(line, 0.2))
	var things := Chalk.drawing(fittings, Chalk.WHITE * 0.32, 0.012, false, 2, SEED * 43)
	things.name = "RoomFittings"
	add_child(things)
	_art.append(things)


## The board stood up as a wall behind the zones: slate in a wooden frame with a chalk tray,
## taller than anything in front of it, and the session written on it where it shows over them.
func _stand_the_board() -> void:
	var half := live_room_half()
	var slate := ShaderMaterial.new()
	slate.shader = preload("res://core/venues/shaders/chalkboard.gdshader")
	slate.set_shader_parameter("upright", true)
	slate.set_shader_parameter("smudge", 0.3)
	slate.set_shader_parameter("slate", Color(0.075, 0.095, 0.1))
	var board := MeshInstance3D.new()
	board.name = "BoardWall"
	var box := BoxMesh.new()
	board.mesh = box
	board.material_override = slate
	add_child(board)
	if variant == CLASSROOM:
		# A real board on the back wall: slate from the dado rail to under the ceiling, in an oak
		# frame with a chalk tray, and picture lights on brass arms over it.
		var span := half * 2.0 - 0.7
		box.size = Vector3(span, CLASS_BOARD_TOP - CLASS_BOARD_FOOT, 0.06)
		board.position = Vector3(0, (CLASS_BOARD_TOP + CLASS_BOARD_FOOT) * 0.5, BOARD_Z + 0.03)
		_frame_board(Vector3(0, 0, BOARD_Z), PI, span, CLASS_BOARD_FOOT, CLASS_BOARD_TOP)
		_board_lights(half, CLASS_BOARD_TOP + 0.3, CLASS_BOARD_TOP - CLASS_BOARD_FOOT + 0.6)
	else:
		box.size = Vector3(half * 2.0, BOARD_HEIGHT, 0.08)
		board.position = Vector3(0, BOARD_HEIGHT * 0.5, BOARD_Z + 0.04)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.32, 0.22, 0.14)
		wood.roughness = 0.8
		ZoneKit.block(self, Vector3(half * 2.0 + 0.24, 0.12, 0.1), Vector3(0, BOARD_HEIGHT + 0.06, BOARD_Z + 0.03), wood,
				"BoardFrame")
		for side in [-1.0, 1.0]:
			ZoneKit.block(self, Vector3(0.12, BOARD_HEIGHT, 0.1), Vector3(side * (half + 0.06), BOARD_HEIGHT * 0.5, BOARD_Z + 0.03),
					wood, "BoardFrame")
		ZoneKit.block(self, Vector3(half * 2.0, 0.04, 0.12), Vector3(0, 0.9, BOARD_Z - 0.06), wood, "ChalkTray")
		_board_lights(half, BOARD_HEIGHT + 0.1, BOARD_HEIGHT + 1.0)
	# What is written on it: the session (rewritten when it changes, see _process), and the
	# doodles that collect round the edges of any board.
	var face := BOARD_Z - 0.005
	self.board = board_from(DAW.state)
	_write_the_session(self.board)
	_watch_the_session()
	# Placed for the board as first drawn, and spread with it across the wider one.
	var wide := half / DRAWN_HALF
	var doodles := [[Chalk.beamed_notes(), Vector3(-5.4 * wide, 3.5, face), 0.35, Chalk.LIME],
			[Chalk.headphones(), Vector3(5.5 * wide, 3.6, face), 0.4, Chalk.VIOLET],
			[Chalk.star(), Vector3(-1.9 * wide, 3.75, face), 0.16, Chalk.YELLOW],
			[Chalk.heart(), Vector3(1.6 * wide, 3.62, face), 0.15, Chalk.PINK],
			[Chalk.cassette(), Vector3(-5.6 * wide, 4.0, face), 0.3, Chalk.ORANGE]]
	for i in doodles.size():
		var drawn: Array = []
		for line: PackedVector3Array in doodles[i][0]:
			drawn.append(_board_line(line, doodles[i][1], Vector2.ONE * doodles[i][2]))
		var art := Chalk.drawing(drawn, doodles[i][3] * 0.7, 0.014, false, 2, SEED * 53 + i)
		art.name = "BoardDoodle"
		add_child(art)
		_art.append(art)


## Picture lights along the top of the board, washing the slate down its height: one to every
## three metres or so of it.
func _board_lights(half: float, high: float, reach: float) -> void:
	var count := maxi(4, roundi(half * 2.0 / 3.0))
	for i in count:
		var wash := SpotLight3D.new()
		wash.name = "BoardLight%d" % i
		wash.light_color = Color(0.8, 0.85, 1.0)
		wash.light_energy = 2.5 if variant != CLASSROOM else 1.6
		wash.spot_range = reach
		wash.spot_angle = 50.0
		wash.shadow_enabled = false
		wash.position = Vector3(-half + half * 2.0 * (i + 0.5) / count, high, BOARD_Z - 0.7)
		wash.basis = Basis.looking_at(Vector3(0, -1.0, 0.28), Vector3.FORWARD)
		add_child(wash)


## What the board says about the session: the song's sections from its markers, in order, the
## tempo, how many tracks, and the take -- what the armed track would be on if it were
## recording now, or is on while it is. No take when nothing is armed. A section is its marker's
## name without the harmony's brackets (Harmony.section_of), and a marker that is only brackets
## names no section, nor does a sticky note (a `NOTE ` marker): section_of is "" for both.
static func board_from(state: MixState) -> Dictionary:
	var out := {"sections": PackedStringArray(), "tempo": "", "tracks": "", "take": ""}
	if state == null:
		return out
	var times: Array = state.markers.keys()
	times.sort()
	for t in times:
		var said := Harmony.section_of(str(state.markers[t])).strip_edges().to_upper()
		if said != "" and out["sections"].size() < BOARD_SECTIONS:
			out["sections"].append(said.left(10))
	var bpm := state.tempo
	out["tempo"] = ("%d bpm" % roundi(bpm)) if absf(bpm - roundf(bpm)) < 0.05 else ("%.1f bpm" % bpm)
	var count := 0
	var takes := -1
	for index in state.track_indices():
		if not state.in_project(index):
			continue
		count += 1
		var track: MixState.TrackState = state.track(index, false)
		if track != null and track.rec_arm:
			takes = maxi(takes, track.items.size())
	out["tracks"] = "%d track%s" % [count, "" if count == 1 else "s"]
	if takes >= 0:
		out["take"] = "take %d" % (takes + (0 if state.recording else 1))
	return out


## The session's part of the board, built fresh: a box over each section across the top, a
## sweep under them, the tempo, the track count and the take ringed. Drawn on from nothing.
func _write_the_session(said: Dictionary) -> void:
	var half := live_room_half()
	var face := BOARD_Z - 0.005
	_session = Node3D.new()
	_session.name = "BoardSession"
	add_child(_session)
	var lines: Array = []
	var sections: PackedStringArray = said["sections"]
	if sections.is_empty():
		sections = PackedStringArray(["FROM THE TOP"])
	var width := half * 2.0 - 1.6
	var cell := width / sections.size()
	# One hand, one size: as big as the longest name fits its box.
	var longest := 1
	for section in sections:
		longest = maxi(longest, section.length())
	# (a letter of this hand is about 0.15 m wide at scale 1)
	var size := minf(1.0, (cell - 0.25) / (longest * 0.17))
	for i in sections.size():
		# Read from the room, left to right, which on a board facing -Z runs from +X.
		var x := width * 0.5 - cell * (i + 0.5)
		lines.append_array(_board_lines(_rect(cell - 0.12, 0.5, Vector2(-x, 4.55)), face))
		_write(sections[i], Vector3(x, 4.55, face), size, Chalk.WHITE, _session)
	var sweep := [_board_line(Chalk.arc(Vector3(0, 0, 0), width * 0.5, 0.25, PI, -PI, 40), Vector3(0, 4.15, face))]
	var wide := half / DRAWN_HALF
	_write(said["tracks"], Vector3(3.6 * wide, 3.65, face), 1.0, Chalk.YELLOW, _session)
	_write(said["tempo"], Vector3(-3.4 * wide, 3.65, face), 1.0, Chalk.CYAN, _session)
	var ring: Array = []
	if said["take"] != "":
		_write(said["take"], Vector3(-0.2, 3.65, face), 0.8, Chalk.PINK, _session)
		ring.append(_board_line(Chalk.loop(Vector3.ZERO, 0.42, 30), Vector3(-0.2, 3.65, face), Vector2(1.6, 0.6)))
	for part in [["BoardWriting", lines], ["BoardSweep", sweep], ["BoardRing", ring]]:
		if part[1].is_empty():
			continue
		var marks := Chalk.drawing(part[1], Chalk.WHITE * 0.55, 0.014, false, 2, SEED * 47 + _rewrites)
		marks.name = part[0]
		_session.add_child(marks)
		_art.append(marks)


## Told whenever the mix says anything that might change what the board says; it is looked at
## on the next beat of _process, not here, so a flood of news is one rewrite and not fifty.
func _watch_the_session() -> void:
	for news: Signal in [DAW.timeline_changed, DAW.transport_changed, DAW.connection_changed, DAW.bank_changed]:
		news.connect(_session_news)
	DAW.track_added.connect(_session_news.unbind(1))
	DAW.track_changed.connect(_track_news)


func _session_news() -> void:
	_board_stale = true


func _track_news(_index: int, field: StringName) -> void:
	if field in [&"rec_arm", &"items"]:
		_board_stale = true


## The board as the session now is: if it says something different, the old writing is rubbed
## out and the new written in its place.
func _reread_the_session() -> void:
	_board_stale = false
	var said := board_from(DAW.state)
	if said != board:
		rewrite_board(said)


## Rub out what the session part of the board says and write `said` instead. The old writing
## goes the way chalk goes, wiped off from where it was started, its words fading; then the new
## one is drawn on.
func rewrite_board(said: Dictionary) -> void:
	board = said
	_rewrites += 1
	if _session != null:
		var old := _session
		old.name = "BoardRubbedOut%d" % _rewrites
		for art: MeshInstance3D in old.find_children("*", "MeshInstance3D", false, false):
			_art.erase(art)
			for entry in _drawing.duplicate():
				if entry[0] == art:
					_drawing.erase(entry)
		_rubbing.append([old, 0.0])
	_write_the_session(said)
	for art: MeshInstance3D in _session.find_children("*", "MeshInstance3D", false, false):
		_draw_on(art, RUB_OUT)
	for words: Label3D in _session.find_children("*", "Label3D", false, false):
		words.set_meta(&"full", words.modulate.a)
		words.modulate.a = 0.0
	_writing_in = 0.0


## The rubbing out and the writing in, a frame at a time.
func _advance_the_board(delta: float) -> void:
	var i := 0
	while i < _rubbing.size():
		var old: Node3D = _rubbing[i][0]
		_rubbing[i][1] += delta / RUB_OUT
		var gone: float = _rubbing[i][1]
		if gone >= 1.0:
			old.queue_free()
			_rubbing.remove_at(i)
			continue
		for art: MeshInstance3D in old.find_children("*", "MeshInstance3D", false, false):
			var length: float = art.mesh.get_meta(&"length", 0.0)
			art.set_instance_shader_parameter(&"tail", gone * length)
		for words: Label3D in old.find_children("*", "Label3D", false, false):
			words.modulate.a = minf(words.modulate.a, 0.8 * (1.0 - gone))
		i += 1
	if _writing_in >= 0.0 and _session != null:
		_writing_in += delta
		var shown := clampf((_writing_in - RUB_OUT) / 0.8, 0.0, 1.0)
		for words: Label3D in _session.find_children("*", "Label3D", false, false):
			words.modulate.a = float(words.get_meta(&"full", 0.8)) * shown
		if shown >= 1.0:
			_writing_in = -1.0


## Words written on the board in chalk, facing the room.
func _write(text: String, at: Vector3, scale: float, colour: Color, parent: Node3D = null, yaw := PI) -> void:
	var into: Node3D = parent if parent != null else self
	var words := Label3D.new()
	words.name = "BoardWords%d" % into.get_child_count()
	words.text = text
	words.font_size = 96
	words.outline_size = 0
	words.pixel_size = 0.0028 * scale
	words.modulate = Color(colour.r, colour.g, colour.b, 0.8) * Color(0.85, 0.85, 0.85, 1.0)
	words.shaded = false
	words.double_sided = false
	words.position = at
	words.rotation.y = yaw
	into.add_child(words)


## A rectangle `w` by `h` centred on `at` in a wall's own plane (x along it, y up).
static func _rect(w: float, h: float, at: Vector2) -> Array:
	var c := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	var line := PackedVector3Array()
	for k: Vector2 in c:
		line.append(Vector3(at.x + k.x * w * 0.5, at.y + k.y * h * 0.5, 0))
	return [line]


## Lines drawn in a plane (x, y), scaled and moved within it.
static func _scaled(lines: Array, s: float, at: Vector2) -> Array:
	var out: Array = []
	for line: PackedVector3Array in lines:
		var moved := PackedVector3Array()
		for p in line:
			moved.append(Vector3(at.x + p.x * s, at.y + p.y * s, 0))
		out.append(moved)
	return out


## Lines drawn in a wall's plane, stood on the wall through `origin` turned `yaw` (0 is the
## front wall, facing +Z, the room).
static func _on_wall(lines: Array, origin: Vector3, yaw: float) -> Array:
	var turn := Basis(Vector3.UP, yaw)
	var out: Array = []
	for line: PackedVector3Array in lines:
		var placed := PackedVector3Array()
		for p in line:
			placed.append(origin + turn * p)
		out.append(placed)
	return out


## Lines on the board wall (which faces -Z), each scaled by `s` about `at`; x is mirrored so a
## drawing reads the right way round from the room.
static func _board_line(line: PackedVector3Array, at: Vector3, s := Vector2.ONE) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in line:
		out.append(at + Vector3(-p.x * s.x, p.y * s.y, 0))
	return out


static func _board_lines(lines: Array, face: float) -> Array:
	var out: Array = []
	for line: PackedVector3Array in lines:
		out.append(_board_line(line, Vector3(0, 0, face)))
	return out


## `outside`: only those out past the classroom's window wall, where they can be seen through
## the glass and stand in nothing.
func _scatter_doodles(outside := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var shapes := Chalk.all_shapes()
	for i in DOODLE_COUNT:
		var shape: Callable = shapes[i % shapes.size()]
		var colour: Color = Chalk.NEON[rng.randi() % Chalk.NEON.size()]
		# Near ones small, far ones huge, so the space reads as deep from the chair.
		var far := pow(rng.randf(), 0.8)
		var distance := lerpf(6.5, 70.0, far)
		var angle := rng.randf_range(-PI, PI)
		var height := lerpf(1.2, 4.0, rng.randf()) + far * rng.randf_range(2.0, 28.0)
		var size := lerpf(0.35, 9.0, far * far) * rng.randf_range(0.7, 1.3)
		var holder := Node3D.new()
		holder.name = "Doodle"
		holder.position = Vector3(sin(angle) * distance, height, -cos(angle) * distance + 0.3)
		# Never hanging in an activity's space: a star at head height in the drum riser is in
		# the way of whoever will play there. Pushed straight out until it is past them.
		while _in_a_zone(holder.position, size * 0.6):
			holder.position += Vector3(sin(angle), 0, -cos(angle)) * 1.0
		if outside and holder.position.x > -live_room_half() - 3.0 - size:
			holder.free()
			continue
		var art := Chalk.drawing(shape.call(), colour, 0.05, false, 2, SEED * 31 + i)
		holder.add_child(art)
		add_child(holder)
		_art.append(art)
		# Face the room, tipped a little so they do not all look like posters.
		holder.look_at(Vector3(0, 1.5, 0.3), Vector3.UP, true)
		holder.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.5, 0.5))
		holder.scale = Vector3.ONE * size
		_doodles.append(holder)
		_rest.append(holder.position)
		_phase.append(rng.randf() * TAU)


func _in_a_zone(at: Vector3, margin: float) -> bool:
	for box: AABB in zones().values():
		if box.grow(margin).has_point(at):
			return true
	return false


## The activity zones, drawn: each one's floor taped out in its own colour, and the thing that
## will stand there sketched standing up in the air the way every doodle here is -- a riser (the
## hand drums stand in their ring on the floor inside it themselves), a booth with a mic, the lattice's cube with its cells ruled on the faces,
## a table, a keyboard on its stand. Drawn on as you arrive with everything else.
func _draw_zones() -> void:
	var z := zones()
	var colour := {&"drums": Chalk.PINK, &"vocals": Chalk.CYAN, &"matrix": Chalk.VIOLET,
			&"bricks": Chalk.YELLOW, &"synth": Chalk.LIME}
	for i in ZONE_IDS.size():
		var id := ZONE_IDS[i]
		var box: AABB = z[id]
		var holder := ZoneKit.holder(self, id, box)
		var half := Vector2(box.size.x, box.size.z) * 0.5
		var tape := PackedVector3Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
			tape.append(Vector3(corner.x * half.x, 0.004, corner.y * half.y))
		var floor_art := Chalk.drawing([_subdivide(tape, 0.25)], colour[id] * 0.6, 0.025, true, 2,
				SEED * 7 + i)
		floor_art.name = "ZoneFloor"
		holder.add_child(floor_art)
		_art.append(floor_art)
		# Faint: these are drawn at arm's length, where full-strength chalk is a bar of light
		# across the eye, and the lattice -- three metres of it -- fainter still.
		var faint := 0.22 if id == &"matrix" else 0.4
		var sketch := Chalk.drawing(_zone_sketch(id, box), colour[id] * faint, 0.012, false, 2,
				SEED * 13 + i)
		sketch.name = "ZoneSketch"
		holder.add_child(sketch)
		_art.append(sketch)
	# The prop shelf, sketched where the other venues stand a real one, its items sitting on
	# its drawn top.
	var shelf := Node3D.new()
	shelf.name = "PropShelf"
	shelf.transform = prop_shelf_spot()
	add_child(shelf)
	var s := ZoneKit.SHELF
	var lines := _box_lines(Vector3(s.x, 0.03, s.z), Vector3(0, s.y - 0.015, 0))
	lines.append_array(_box_lines(Vector3(s.x - 0.08, 0.02, s.z - 0.06), Vector3(0, 0.22, 0)))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			lines.append(PackedVector3Array([Vector3(cx * (s.x * 0.5 - 0.04), 0, cz * (s.z * 0.5 - 0.04)),
					Vector3(cx * (s.x * 0.5 - 0.04), s.y - 0.03, cz * (s.z * 0.5 - 0.04))]))
	var drawn: Array = []
	for line: PackedVector3Array in lines:
		drawn.append(_subdivide(line, 0.2))
	var shelf_art := Chalk.drawing(drawn, Chalk.YELLOW * 0.4, 0.012, false, 2, SEED * 17)
	shelf_art.name = "ShelfSketch"
	shelf.add_child(shelf_art)
	_art.append(shelf_art)
	# The dartboard over it, drawn on the air where the others hang theirs: its rings, its
	# spokes and the square of its panel. The darts stick in it all the same (Venue.dart_boards).
	var face := Vector3(0, ZoneKit.DARTBOARD_Y, ZoneKit.DARTBOARD_FACE_Z)
	var board_lines: Array = []
	for r in [ZoneKit.DARTBOARD_RADIUS, DartItem.DOUBLE_OUT, DartItem.TREBLE_OUT, DartItem.OUTER_BULL]:
		board_lines.append(Chalk.loop(face, r, 48 if r > 0.05 else 16))
	for i in 20:
		var a := deg_to_rad(9.0 + i * 18.0)
		var way := Vector3(sin(a), cos(a), 0)
		board_lines.append(PackedVector3Array([face + way * DartItem.OUTER_BULL, face + way * DartItem.DOUBLE_OUT]))
	var half := ZoneKit.DART_PANEL * 0.5
	var back := Vector3(0, ZoneKit.DARTBOARD_Y, ZoneKit.DART_PANEL_BACK + ZoneKit.DART_PANEL_THICK)
	board_lines.append(PackedVector3Array([back + Vector3(-half, -half, 0), back + Vector3(half, -half, 0),
			back + Vector3(half, half, 0), back + Vector3(-half, half, 0), back + Vector3(-half, -half, 0)]))
	var board_art := Chalk.drawing(board_lines, Chalk.YELLOW * 0.4, 0.008, false, 2, SEED * 19)
	board_art.name = "Dartboard"
	shelf.add_child(board_art)
	_art.append(board_art)
	# The hoop across the room, drawn: its base and pole, its board, its rim and the net hanging
	# from it. A ball goes off it and through it all the same (Venue.hoops).
	var hoop := Hoop.new(null, null, true)
	hoop.transform = hoop_spot()
	add_child(hoop)
	var hoop_lines := _box_lines(Vector3(Hoop.BASE_HALF.x * 2.0, Hoop.BASE_TOP, Hoop.BASE_HALF.y * 2.0),
			Vector3(0, Hoop.BASE_TOP * 0.5, Hoop.BASE_Z))
	hoop_lines.append(PackedVector3Array([Vector3(0, Hoop.BASE_TOP, Hoop.POLE_Z), Vector3(0, Hoop.POLE_TOP, Hoop.POLE_Z)]))
	hoop_lines.append_array(_box_lines(Vector3(Hoop.BOARD_HALF.x * 2.0, Hoop.BOARD_HALF.y * 2.0, 0.012),
			Vector3(0, Hoop.BOARD_Y, Hoop.BOARD_FRONT - 0.006)))
	var rim := PackedVector3Array()
	var bottom := PackedVector3Array()
	var low := 0.65
	for k in 33:
		var a := k * TAU / 32.0
		rim.append(Vector3(sin(a) * Hoop.RIM_RADIUS, Hoop.RIM_Y, Hoop.RIM_Z + cos(a) * Hoop.RIM_RADIUS))
		bottom.append(Vector3(sin(a) * Hoop.RIM_RADIUS * low, Hoop.RIM_Y - Hoop.NET_DROP,
				Hoop.RIM_Z + cos(a) * Hoop.RIM_RADIUS * low))
	hoop_lines.append(rim)
	hoop_lines.append(bottom)
	for k in 12:
		# The net's cords, each slanting a little round as it goes down.
		var a := k * TAU / 12.0
		var b := a + TAU / 24.0
		hoop_lines.append(PackedVector3Array([
				Vector3(sin(a) * Hoop.RIM_RADIUS, Hoop.RIM_Y, Hoop.RIM_Z + cos(a) * Hoop.RIM_RADIUS),
				Vector3(sin(b) * Hoop.RIM_RADIUS * low, Hoop.RIM_Y - Hoop.NET_DROP,
						Hoop.RIM_Z + cos(b) * Hoop.RIM_RADIUS * low)]))
	var hoop_drawn: Array = []
	for line: PackedVector3Array in hoop_lines:
		hoop_drawn.append(_subdivide(line, 0.2))
	var hoop_art := Chalk.drawing(hoop_drawn, Chalk.YELLOW * 0.4, 0.008, false, 2, SEED * 23)
	hoop_art.name = "HoopSketch"
	hoop.add_child(hoop_art)
	_art.append(hoop_art)


## What stands in zone `id`, as chalk lines in the zone's floor-centred frame.
func _zone_sketch(id: StringName, box: AABB) -> Array:
	var lines: Array = []
	match id:
		&"drums":
			# Only the riser: the hand drums stand in their ring inside it (Venue.drum_ring, on the
			# floor here, since a drawn riser is walked through), and a kit drawn among them would
			# say "kit" in the middle of the hand drums.
			lines.append_array(_box_lines(Vector3(box.size.x - 0.3, 0.3, box.size.z - 0.3), Vector3(0, 0.15, 0)))
		&"vocals":
			lines.append_array(_box_lines(box.size - Vector3(0.2, 0, 0.2), Vector3(0, box.size.y * 0.5, 0)))
			# The stand where the other venues stand theirs, boom reaching in, mic at its end.
			var foot := ZoneKit.MIC_AT
			var reach := Basis(Vector3.UP, ZoneKit.MIC_YAW) * Vector3(0, 0, -ZoneKit.MIC_REACH)
			var top := foot + Vector3(0, ZoneKit.MIC_HEIGHT - 0.18, 0)
			lines.append(PackedVector3Array([foot, top]))
			lines.append(PackedVector3Array([top, foot + reach + Vector3(0, ZoneKit.MIC_HEIGHT, 0)]))
			lines.append(_placed(Chalk.loop(Vector3.ZERO, 0.05, 16),
					foot + reach + Vector3(0, ZoneKit.MIC_HEIGHT + 0.06, 0), ZoneKit.MIC_YAW))
		&"matrix":
			var side := 3.0
			lines.append_array(_box_lines(Vector3.ONE * side, Vector3(0, side * 0.5, 0)))
			# Cells ruled on the two faces you see first, thirds of the way across.
			for k in [1.0, 2.0]:
				var t: float = -side * 0.5 + side * k / 3.0
				lines.append(PackedVector3Array([Vector3(t, 0, -side * 0.5), Vector3(t, side, -side * 0.5)]))
				lines.append(PackedVector3Array([Vector3(-side * 0.5, t + side * 0.5, -side * 0.5),
						Vector3(side * 0.5, t + side * 0.5, -side * 0.5)]))
				lines.append(PackedVector3Array([Vector3(-side * 0.5, 0, t), Vector3(-side * 0.5, side, t)]))
				lines.append(PackedVector3Array([Vector3(-side * 0.5, t + side * 0.5, -side * 0.5),
						Vector3(-side * 0.5, t + side * 0.5, side * 0.5)]))
		&"bricks":
			lines.append_array(_box_lines(Vector3(1.0, 0.05, 2.0), Vector3(0, 0.9, 0)))
			for cx in [-0.42, 0.42]:
				for cz in [-0.92, 0.92]:
					lines.append(PackedVector3Array([Vector3(cx, 0, cz), Vector3(cx, 0.88, cz)]))
		&"synth":
			lines.append_array(_box_lines(Vector3(0.36, 0.08, 1.5), Vector3(0, 0.84, 0)))
			for cz in [-0.6, 0.6]:
				lines.append(PackedVector3Array([Vector3(0.1, 0, cz), Vector3(-0.1, 0.8, cz)]))
				lines.append(PackedVector3Array([Vector3(-0.1, 0, cz), Vector3(0.1, 0.8, cz)]))
			# The keys, as quick ticks along the front edge.
			for k in 15:
				var kz := -0.7 + k * 0.1
				lines.append(PackedVector3Array([Vector3(-0.18, 0.88, kz), Vector3(-0.05, 0.88, kz)]))
	var out: Array = []
	for line: PackedVector3Array in lines:
		out.append(_subdivide(line, 0.2))
	return out


## The twelve edges of a box `size` centred on `at`, as separate lines.
static func _box_lines(size: Vector3, at: Vector3) -> Array:
	var h := size * 0.5
	var c := func(x: float, y: float, w: float) -> Vector3: return at + Vector3(x * h.x, y * h.y, w * h.z)
	var out: Array = []
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			out.append(PackedVector3Array([c.call(-1.0, a, b), c.call(1.0, a, b)]))
			out.append(PackedVector3Array([c.call(a, -1.0, b), c.call(a, 1.0, b)]))
			out.append(PackedVector3Array([c.call(a, b, -1.0), c.call(a, b, 1.0)]))
	return out


## A doodle drawn in the XY plane, stood at `at` and turned `yaw` about the vertical, or laid
## onto its side (the drum's head facing up) when `lie` is set.
static func _placed(line: PackedVector3Array, at: Vector3, yaw: float, lie := false) -> PackedVector3Array:
	var turn := Basis(Vector3.UP, yaw)
	if lie:
		turn = turn * Basis(Vector3.RIGHT, PI * 0.5)
	var out := PackedVector3Array()
	for p in line:
		out.append(at + turn * p)
	return out


func _add_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "ChalkDust"
	dust.amount = 600
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.visibility_aabb = AABB(Vector3(-12, -1, -12), Vector3(24, 8, 24))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(10, 3, 10)
	process.gravity = Vector3(0, -0.01, 0)
	process.direction = Vector3(0.3, 0.2, 0.1)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 0.7))
	fade.add_point(0.8, Color(1, 1, 1, 0.7))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	dust.process_material = process
	dust.position = Vector3(0, 3.0, 0.3)
	var speck := QuadMesh.new()
	speck.size = Vector2(0.012, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 0.85, 1.0)
	# Round and soft. A square mote reads as a pixel, which is to say as a bug.
	var mote := GradientTexture2D.new()
	mote.fill = GradientTexture2D.FILL_RADIAL
	mote.fill_from = Vector2(0.5, 0.5)
	mote.fill_to = Vector2(1.0, 0.5)
	mote.width = 32
	mote.height = 32
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	mote.gradient = soft
	mat.albedo_texture = mote
	speck.material = mat
	dust.draw_pass_1 = speck
	add_child(dust)


func _process(delta: float) -> void:
	_clock += delta
	_advance_drawing(delta)
	_advance_comets(delta)
	if variant == CLASSROOM:
		_tick_the_clock()
	if variant != OPEN_SKY:
		_reread_wait -= delta
		if _board_stale and _reread_wait <= 0.0:
			_reread_wait = REREAD_EVERY
			_reread_the_session()
		_advance_the_board(delta)
	# Now and then something is wiped and drawn again, so the zone never sets like a painting.
	_next_redraw -= delta
	if _next_redraw <= 0.0 and not _art.is_empty():
		_next_redraw = _rng.randf_range(1.5, 4.0)
		_draw_on(_art[_rng.randi() % _art.size()], 0.0)
	for i in _doodles.size():
		var bob := sin(_clock * 0.6 + _phase[i]) * 0.08 * _doodles[i].scale.x
		var kick := _smoothed * 0.12 if _rest[i].length() < 14.0 else 0.0
		_doodles[i].position = _rest[i] + Vector3(0, bob + kick, 0)


## Start drawing `art` from nothing after `delay` seconds, at a pace that finishes any drawing
## in about a second and a half: a big drawing is drawn by a fast hand, not a slow one.
func _draw_on(art: MeshInstance3D, delay: float) -> void:
	var length: float = art.mesh.get_meta(&"length", 0.0) if art.mesh != null else 0.0
	if length <= 0.0:
		return
	for entry in _drawing:
		if entry[0] == art:
			return
	art.set_instance_shader_parameter(&"ink", 0.0)
	_drawing.append([art, -delay * length / 1.5, length / 1.5, length])


func _advance_drawing(delta: float) -> void:
	var i := 0
	while i < _drawing.size():
		var entry: Array = _drawing[i]
		entry[1] += entry[2] * delta
		var art: MeshInstance3D = entry[0]
		if entry[1] >= entry[3]:
			art.set_instance_shader_parameter(&"ink", 1e6)
			_drawing.remove_at(i)
			continue
		art.set_instance_shader_parameter(&"ink", maxf(entry[1], 0.0))
		i += 1


## A rainbow in six chalks, enormous and far off, half sunk below the floor's edge.
func _paint_rainbow() -> void:
	var bands := [Chalk.VIOLET, Chalk.CYAN, Chalk.LIME, Chalk.YELLOW, Chalk.ORANGE, Chalk.PINK]
	var lines: Array = []
	var colours: Array = []
	for i in bands.size():
		lines.append(Chalk.arc(Vector3.ZERO, 1.0 + i * 0.07, 1.0 + i * 0.07, PI, -PI, 64))
		colours.append(bands[i])
	var holder := Node3D.new()
	holder.name = "Rainbow"
	holder.position = Vector3(-55, -4, -80)
	for i in lines.size():
		var art := Chalk.drawing([lines[i]], colours[i], 0.022, false, 2, SEED + 300 + i)
		holder.add_child(art)
		_art.append(art)
	add_child(holder)
	holder.look_at(Vector3(0, 1.5, 0.3), Vector3.UP, true)
	holder.scale = Vector3.ONE * 38.0


## Star maps high overhead: a few dots, joined, the way they are in a child's book.
func _join_constellations() -> void:
	for c in 5:
		var centre := Vector3(_rng.randf_range(-40, 40), _rng.randf_range(28, 45),
				_rng.randf_range(-50, 30))
		var stars := PackedVector3Array()
		var at := Vector3.ZERO
		for k in _rng.randi_range(5, 8):
			stars.append(at)
			at += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0).normalized() * _rng.randf_range(1.5, 3.0)
		var lines: Array = [stars]
		for s in stars:
			lines.append(Chalk.loop(s, 0.18, 10))
		var holder := Node3D.new()
		holder.name = "Constellation"
		holder.position = centre
		var art := Chalk.drawing(lines, Chalk.WHITE * 0.8, 0.05, false, 1, SEED + 400 + c)
		holder.add_child(art)
		add_child(holder)
		holder.look_at(Vector3(0, 1.5, 0.3), Vector3.UP, true)
		holder.scale = Vector3.ONE * 1.8
		_art.append(art)


## Shooting stars: a curve drawn fast and wiped from behind as fast, so all you ever see is the
## stroke in flight.
func _throw_comets() -> void:
	for i in 4:
		var line := Chalk.arc(Vector3(0, -6, 0), 8.0, 6.0, PI * 0.8, -PI * 0.5, 30)
		var art := Chalk.drawing([line], Chalk.NEON[i % Chalk.NEON.size()], 0.06, false, 1, SEED + 500 + i)
		art.name = "Comet"
		art.set_instance_shader_parameter(&"ink", 0.0)
		add_child(art)
		_comets.append([art, 0.0, _rng.randf_range(0.5, 4.0)])


func _advance_comets(delta: float) -> void:
	for comet in _comets:
		var art: MeshInstance3D = comet[0]
		if comet[2] > 0.0:
			comet[2] -= delta
			if comet[2] <= 0.0:
				# Somewhere new each time, high up and well out from the room.
				var a := _rng.randf_range(-PI, PI)
				var r := _rng.randf_range(25.0, 60.0)
				art.position = Vector3(sin(a) * r, _rng.randf_range(16, 32), -cos(a) * r)
				art.look_at(Vector3(0, 1.5, 0.3), Vector3.UP, true)
				art.rotate_object_local(Vector3.FORWARD, _rng.randf_range(-0.6, 0.6))
				art.scale = Vector3.ONE * _rng.randf_range(1.0, 2.2)
				comet[1] = 0.0
			continue
		var length: float = art.mesh.get_meta(&"length", 1.0)
		comet[1] += delta * length / 0.9
		art.set_instance_shader_parameter(&"ink", comet[1])
		art.set_instance_shader_parameter(&"tail", comet[1] - length * 0.35)
		if comet[1] - length * 0.35 > length:
			art.set_instance_shader_parameter(&"ink", 0.0)
			comet[2] = _rng.randf_range(1.0, 5.0)


func pulse(level: float) -> void:
	var k := 0.5 if level > _smoothed else 0.06
	_smoothed = lerpf(_smoothed, clampf(level, 0.0, 1.0), k)
	Chalk.material().set_shader_parameter("pulse", _smoothed)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("pulse", _smoothed)


static func _subdivide(line: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in line.size() - 1:
		var n := maxi(1, int(line[i].distance_to(line[i + 1]) / step))
		for k in n:
			out.append(line[i].lerp(line[i + 1], float(k) / float(n)))
	out.append(line[line.size() - 1])
	return out



## A mirror drawn in chalk: a wobbly ornate frame gone over twice, curls at the corners, a star
## or two, and glass with a little chalk dust on it. It stands on nothing, like everything here.
## A little slate, written on in chalk.
func _dress_wardrobe(board: Wardrobe) -> void:
	var slate := StandardMaterial3D.new()
	slate.albedo_color = Color(0.16, 0.22, 0.2)
	slate.roughness = 0.95
	board.board_material = slate
	board.ink = Chalk.WHITE
	board.accent = Chalk.YELLOW


func _frame_mirror(mirror: Mirror) -> void:
	mirror.haze = 0.035
	mirror.haze_colour = Color(0.55, 0.58, 0.62)
	var w := mirror.glass_size.x * 0.5 + 0.03
	var h := mirror.glass_size.y * 0.5 + 0.03
	var z := 0.01
	var lines: Array = []
	for grow in [0.0, 0.055]:
		var a: float = w + grow
		var b: float = h + grow
		lines.append(PackedVector3Array([Vector3(-a, -b, z), Vector3(a, -b, z), Vector3(a, b, z),
				Vector3(-a, b, z), Vector3(-a, -b - 0.02, z)]))
	# Curls at the four corners, between the two lines.
	for cx in [-1.0, 1.0]:
		for cy in [-1.0, 1.0]:
			var at := Vector3(cx * (w + 0.028), cy * (h + 0.028), z)
			lines.append(Chalk.arc(at, 0.045, 0.045, 0.0, TAU * 1.15, 20))
	# A crest on top: an arch with a star in it.
	lines.append(Chalk.arc(Vector3(0, h + 0.055, z), 0.16, 0.13, 0.0, PI, 24))
	var frame := Chalk.drawing(lines, Chalk.WHITE * 0.9, 0.007, false, 2, SEED * 7)
	frame.name = "ChalkFrame"
	mirror.add_child(frame)
	var crest := Chalk.drawing(Chalk.star(), Chalk.YELLOW, 0.006, false, 2, SEED * 13)
	crest.scale = Vector3.ONE * 0.06
	crest.position = Vector3(0, h + 0.11, z)
	mirror.add_child(crest)
	for side in [-1.0, 1.0]:
		var twinkle := Chalk.drawing(Chalk.star(4), Chalk.PINK if side < 0 else Chalk.CYAN, 0.005,
				false, 2, SEED * 17 + int(side))
		twinkle.scale = Vector3.ONE * 0.05
		twinkle.position = Vector3(side * (w + 0.16), h * 0.55, z)
		mirror.add_child(twinkle)



# ---- The classroom ---------------------------------------------------------------------------

## A schoolroom at night, the lights at the back left on: moonlight through the tall windows, the
## board lit, the room otherwise its own colour in the dark.
func _dress_classroom(env: Environment, key: DirectionalLight3D) -> void:
	key.basis = Basis.looking_at(MOON_WAY.normalized(), Vector3.UP)
	key.light_color = Color(0.62, 0.72, 1.0)
	key.light_energy = 1.25
	# Indoors the chalk's own glow is turned down: a room has walls to throw it back off, and the
	# open sky's bloom, in here, made the desk a lightbox.
	env.ambient_light_color = Color(0.42, 0.40, 0.55)
	env.ambient_light_energy = 0.2
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.tonemap_exposure = 0.85
	env.adjustment_saturation = 1.0


## The room's long side, its front (behind the desk) and its back (the board's wall).
func _class_front() -> float:
	return Studio.ROOM_FRONT - 0.3


func _class_back() -> float:
	return BOARD_Z + 0.065


## A material from the scanned shelf, kept for every classroom built.
func _oak() -> StandardMaterial3D:
	return Materials.cached_scanned("chalk_oak", "black_walnut_veneer_01", "2k", 0.7, Color(1.0, 0.78, 0.52))


func _cream() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.63, 0.55)
	m.roughness = 0.55
	return m


func _slate() -> ShaderMaterial:
	var slate := ShaderMaterial.new()
	slate.shader = preload("res://core/venues/shaders/chalkboard.gdshader")
	slate.set_shader_parameter("upright", true)
	slate.set_shader_parameter("smudge", 0.35)
	slate.set_shader_parameter("slate", Color(0.075, 0.095, 0.1))
	return slate


func _build_classroom() -> void:
	var half := live_room_half()
	var front := _class_front()
	var back := _class_back()
	var mid := (front + back) * 0.5
	var long := back - front
	var tall := CLASS_HEIGHT
	var thick := 0.25

	# Boards underfoot, old and oiled.
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "ClassroomFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, long)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, mid)
	floor_mesh.material_override = Materials.cached_scanned("chalk_floor", "wood_floor_deck", "2k", 2.2,
			Color(0.62, 0.48, 0.36))
	add_child(floor_mesh)

	# Walls in the institutional green of every school built before anyone asked, over an oak dado.
	var paint := Materials.painted_wall(Color(0.19, 0.27, 0.19))
	var specs := [
		[Vector3(0, tall * 0.5, front - thick * 0.5), Vector3(half * 2.0 + thick * 2.0, tall, thick)],
		[Vector3(0, tall * 0.5, back + thick * 0.5), Vector3(half * 2.0 + thick * 2.0, tall, thick)],
		[Vector3(half + thick * 0.5, tall * 0.5, mid), Vector3(thick, tall, long)],
		# The window wall: under the sills, over the heads, and the piers between.
		[Vector3(-half - thick * 0.5, SILL * 0.5, mid), Vector3(thick, SILL, long)],
		[Vector3(-half - thick * 0.5, (HEAD + tall) * 0.5, mid), Vector3(thick, tall - HEAD, long)],
	]
	var edges: Array[float] = [front]
	for w in CLASS_WINDOWS:
		edges.append_array([w.x, w.y])
	edges.append(back)
	for i in range(0, edges.size(), 2):
		specs.append([Vector3(-half - thick * 0.5, (SILL + HEAD) * 0.5, (edges[i] + edges[i + 1]) * 0.5),
				Vector3(thick, HEAD - SILL, edges[i + 1] - edges[i])])
	for spec in specs:
		ZoneKit.block(self, spec[1], spec[0], paint, "ClassroomWall")
	var ceiling := ZoneKit.block(self, Vector3(half * 2.0, 0.1, long), Vector3(0, tall + 0.05, mid),
			Materials.painted_wall(Color(0.30, 0.30, 0.28)), "ClassroomCeiling")
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_panel_the_dado(half, front, back)
	_glaze_the_windows(half)
	_hang_the_boards(half, front)
	_hang_the_clock(Vector3(0, 3.72, front))
	_pin_the_alphabet(half, front)
	_hang_the_lights(half, front, back)
	_push_the_desks()
	_stand_the_teachers_desk()
	_raise_the_moon()


## Oak boarding to the dado rail round the room, the rail a moulding standing proud of it.
func _panel_the_dado(half: float, front: float, back: float) -> void:
	var oak := _oak()
	var rail_y := DADO - 0.02
	var low := DADO - 0.04
	for z in [front, back]:
		var into := 1.0 if z == front else -1.0
		ZoneKit.block(self, Vector3(half * 2.0, low, 0.02), Vector3(0, low * 0.5, z + into * 0.01), oak, "Dado")
		ZoneKit.block(self, Vector3(half * 2.0, 0.04, 0.04), Vector3(0, rail_y, z + into * 0.02), oak, "DadoRail")
	for side in [-1.0, 1.0]:
		var x: float = side * half
		var run := back - front - 0.08
		ZoneKit.block(self, Vector3(0.02, low, run), Vector3(x - side * 0.01, low * 0.5, (front + back) * 0.5), oak,
				"Dado")
		ZoneKit.block(self, Vector3(0.04, 0.04, run), Vector3(x - side * 0.02, rail_y, (front + back) * 0.5), oak,
				"DadoRail")


## Tall sash windows down the left wall: painted frames set in the wall's depth, glazing bars in
## sixes, a deep oak sill inside, and a cast-iron radiator under each.
func _glaze_the_windows(half: float) -> void:
	var cream := _cream()
	var wx := -half - 0.125
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.62, 0.7, 0.08)
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	var meet := SILL + (HEAD - SILL) * 0.45
	var bars := MultiMesh.new()
	bars.transform_format = MultiMesh.TRANSFORM_3D
	bars.mesh = BoxMesh.new()
	var placed: Array[Transform3D] = []
	for i in CLASS_WINDOWS.size():
		var w: Vector2 = CLASS_WINDOWS[i]
		var width := w.y - w.x
		var zc := (w.x + w.y) * 0.5
		var inner := width - 0.14
		for z in [w.x + 0.035, w.y - 0.035]:
			ZoneKit.block(self, Vector3(0.08, HEAD - SILL, 0.07), Vector3(wx, (SILL + HEAD) * 0.5, z), cream, "WindowJamb")
		ZoneKit.block(self, Vector3(0.08, 0.07, inner), Vector3(wx, HEAD - 0.035, zc), cream, "WindowHead")
		ZoneKit.block(self, Vector3(0.08, 0.07, inner), Vector3(wx, SILL + 0.035, zc), cream, "WindowSill")
		ZoneKit.block(self, Vector3(0.07, 0.06, inner), Vector3(wx, meet, zc), cream, "MeetingRail")
		# Its edges let into the frame all round, so none of them lies in a frame's face.
		var pane := ZoneKit.block(self, Vector3(0.006, HEAD - SILL - 0.1, inner + 0.04), Vector3(wx, (SILL + HEAD) * 0.5, zc),
				glass, "WindowGlass")
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Glazing bars: two upright in each sash, and across, three panes high below the meeting
		# rail and four above it.
		for sash in [[SILL + 0.07, meet - 0.03, 3], [meet + 0.03, HEAD - 0.07, 4]]:
			var y0: float = sash[0]
			var y1: float = sash[1]
			for k in [1, 2]:
				placed.append(Transform3D(Basis.from_scale(Vector3(0.032, y1 - y0, 0.024)),
						Vector3(wx, (y0 + y1) * 0.5, w.x + 0.07 + inner * k / 3.0)))
			for k in range(1, sash[2]):
				var y := y0 + (y1 - y0) * k / float(sash[2])
				placed.append(Transform3D(Basis.from_scale(Vector3(0.028, 0.022, inner)), Vector3(wx, y, zc)))
		# The sill inside, deep enough for a pot plant.
		ZoneKit.block(self, Vector3(0.17, 0.035, width + 0.1), Vector3(-half - 0.0, SILL + 0.0125, zc), _oak(),
				"InnerSill")
		if _radiator_under(w):
			var radiator := _model("chalk_radiator.glb", Vector3(-half + RADIATOR_IN, 0, zc), PI * 0.5,
					{"iron": _iron(), "brass": _brass()})
			radiator.name = "Radiator%d" % i
	bars.instance_count = placed.size()
	for i in placed.size():
		bars.set_instance_transform(i, placed[i])
	var holder := MultiMeshInstance3D.new()
	holder.name = "GlazingBars"
	holder.multimesh = bars
	holder.material_override = cream
	add_child(holder)

	# The moonlight coming through each, as the dust in the air shows it.
	var way := MOON_WAY.normalized()
	var shaft := ShaderMaterial.new()
	shaft.shader = preload("res://core/venues/shaders/chalk_shaft.gdshader")
	for i in CLASS_WINDOWS.size():
		var w: Vector2 = CLASS_WINDOWS[i]
		var corners := [Vector3(-half, SILL + 0.08, w.x + 0.08), Vector3(-half, SILL + 0.08, w.y - 0.08),
				Vector3(-half, HEAD - 0.08, w.y - 0.08), Vector3(-half, HEAD - 0.08, w.x + 0.08)]
		var ends := []
		for c: Vector3 in corners:
			ends.append(c + way * (c.y / -way.y))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in [[0, 1], [1, 2], [2, 3], [3, 0]]:
			var a: Vector3 = corners[f[0]]
			var b: Vector3 = corners[f[1]]
			var ea: Vector3 = ends[f[0]]
			var eb: Vector3 = ends[f[1]]
			var n := (b - a).cross(ea - a).normalized()
			for v in [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [eb, Vector2(1, 1)],
					[a, Vector2(0, 0)], [eb, Vector2(1, 1)], [ea, Vector2(0, 1)]]:
				st.set_normal(n)
				st.set_uv(v[1])
				st.add_vertex(v[0])
		var beam := MeshInstance3D.new()
		beam.name = "MoonShaft%d" % i
		beam.mesh = st.commit()
		beam.material_override = shaft
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)


## How far in from the window wall a radiator's middle stands: its back a hand off the plaster.
const RADIATOR_IN := 0.16


## Whether the window over `w` has a radiator under it: not where it would stand in an activity's
## space (the booth is drawn round the back of that wall, and a singer does not want one at their
## back).
func _radiator_under(w: Vector2) -> bool:
	return not _in_a_zone(Vector3(-live_room_half() + RADIATOR_IN, 0.4, (w.x + w.y) * 0.5), 0.3)


func _iron() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.48, 0.44)
	m.roughness = 0.6
	m.metallic = 0.3
	return m


func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.55, 0.28)
	m.metallic = 1.0
	m.roughness = 0.35
	return m


func _model(file: String, at: Vector3, yaw: float, swap: Dictionary) -> Node3D:
	var node := (load("res://assets/models/" + file) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	add_child(node)
	return node


## The mesh in a model, with its surfaces' materials swapped by name, for a MultiMesh.
func _model_mesh(file: String, swap: Dictionary) -> Mesh:
	var scene := (load("res://assets/models/" + file) as PackedScene).instantiate()
	var source := (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var mesh := source.duplicate() as ArrayMesh
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swap.has(m.resource_name):
			mesh.surface_set_material(s, swap[m.resource_name])
	scene.free()
	return mesh


## A board's oak frame and chalk tray, round a slate whose face is at `at` (on the floor under its
## middle), turned `yaw` so its front faces into the room. With `slab`, the slate itself too.
func _frame_board(at: Vector3, yaw: float, span: float, foot: float, top: float, slab := false) -> Node3D:
	var holder := Node3D.new()
	holder.name = "BoardFrame"
	holder.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(holder)
	var oak := _oak()
	if slab:
		ZoneKit.block(holder, Vector3(span, top - foot, 0.06), Vector3(0, (top + foot) * 0.5, -0.03), _slate(), "Slate")
	ZoneKit.block(holder, Vector3(span + 0.2, 0.1, 0.06), Vector3(0, top + 0.05, -0.01), oak, "FrameTop")
	for side in [-1.0, 1.0]:
		ZoneKit.block(holder, Vector3(0.1, top - foot, 0.06), Vector3(side * (span * 0.5 + 0.05), (top + foot) * 0.5, -0.01),
				oak, "FrameSide")
	# The tray: a ledge with a lip, the length of the board, under it.
	ZoneKit.block(holder, Vector3(span + 0.2, 0.04, 0.12), Vector3(0, foot - 0.02, 0.02), oak, "ChalkTray")
	ZoneKit.block(holder, Vector3(span + 0.19, 0.025, 0.015), Vector3(0, foot + 0.0115, 0.075), oak, "TrayLip")
	# In it, sticks of chalk in the zone's colours, worn to different lengths, and a felt duster.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(at.x * 13.0 + at.z * 7.0)) + 5
	var sticks := [Chalk.WHITE, Chalk.WHITE, Chalk.PINK, Chalk.YELLOW, Chalk.CYAN, Chalk.WHITE, Chalk.LIME]
	for i in sticks.size():
		var stick := MeshInstance3D.new()
		stick.name = "Chalk"
		var bar := CylinderMesh.new()
		bar.top_radius = 0.0055
		bar.bottom_radius = 0.0055
		bar.height = rng.randf_range(0.03, 0.08)
		bar.radial_segments = 8
		bar.rings = 1
		stick.mesh = bar
		var m := StandardMaterial3D.new()
		m.albedo_color = (sticks[i] as Color).lerp(Color.WHITE, 0.45)
		m.roughness = 1.0
		stick.material_override = m
		stick.position = Vector3(rng.randf_range(-span * 0.45, span * 0.45), foot + 0.0056, rng.randf_range(0.0, 0.045))
		stick.rotation = Vector3(0, rng.randf_range(-0.4, 0.4), PI * 0.5)
		holder.add_child(stick)
	var duster := Node3D.new()
	duster.name = "Duster"
	# Clear of the slate's foot, which is in the plane of the duster's.
	duster.position = Vector3(span * 0.3, foot, 0.035)
	duster.rotation.y = 0.05
	holder.add_child(duster)
	ZoneKit.block(duster, Vector3(0.15, 0.03, 0.055), Vector3(0, 0.026, 0), oak, "DusterBack")
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.6, 0.6, 0.62)
	felt.roughness = 1.0
	ZoneKit.block(duster, Vector3(0.148, 0.011, 0.053), Vector3(0, 0.0055, 0), felt, "DusterFelt")
	return holder


## Lines drawn in a board's own plane (x along it, y up), put on that board: a holder made by
## _frame_board, its face at local z 0, front +Z.
## Each drawing a little further off the slate than the last, so two that cross never lie in one
## plane.
func _draw_on_board(board: Node3D, lines: Array, colour: Color, width: float, seed: int, label: String) -> void:
	var off := 0.003 + 0.0015 * (board.get_meta(&"drawings", 0) as int)
	board.set_meta(&"drawings", (board.get_meta(&"drawings", 0) as int) + 1)
	var faced: Array = []
	for line: PackedVector3Array in lines:
		var placed := PackedVector3Array()
		for p in line:
			placed.append(board.transform * Vector3(p.x, p.y, off))
		faced.append(_subdivide(placed, 0.15) if placed.size() == 2 else placed)
	var art := Chalk.drawing(faced, colour, width, false, 2, seed)
	art.name = label
	add_child(art)
	_art.append(art)


## The front board, behind the desk, has the music lesson on it -- a stave ruled across, a clef,
## and the scale climbing it -- and the right-hand wall's has the solar system, a rocket on its
## way out past the rings.
func _hang_the_boards(half: float, front: float) -> void:
	var front_board := _frame_board(Vector3(0, 0, front + 0.065), 0.0, 7.6, CLASS_BOARD_FOOT, 3.0, true)
	var stave: Array = []
	for k in 5:
		stave.append(PackedVector3Array([Vector3(-3.4, 1.55 + k * 0.13, 0), Vector3(3.4, 1.55 + k * 0.13, 0)]))
	# A treble clef, in a hurry: a loop round the second line and its long stroke.
	var clef := PackedVector3Array()
	for k in 40:
		var t := float(k) / 39.0
		var a := -PI * 0.5 + t * TAU * 1.25
		var r := lerpf(0.06, 0.2, t)
		clef.append(Vector3(-3.05 + cos(a) * r * 0.8, 1.73 + sin(a) * r + t * 0.28, 0))
	clef.append(Vector3(-3.1, 1.32, 0))
	stave.append(clef)
	_draw_on_board(front_board, stave, Chalk.WHITE * 0.32, 0.01, SEED * 61, "StaveChalk")
	var notes: Array = []
	for k in 8:
		var y := 1.55 - 0.065 + k * 0.065
		var x := -2.3 + k * 0.72
		notes.append(_scaled_at(Chalk.arc(Vector3.ZERO, 0.075, 0.055, 0.0, TAU + 0.3, 16), Vector2(x, y)))
		notes.append(PackedVector3Array([Vector3(x + 0.07, y, 0), Vector3(x + 0.07, y + 0.4, 0)]))
	_draw_on_board(front_board, notes, Chalk.YELLOW * 0.5, 0.012, SEED * 67, "ScaleChalk")
	for i in 8:
		_write(["do", "re", "mi", "fa", "so", "la", "ti", "do"][i], front_board.transform * Vector3(-2.3 + i * 0.72, 1.25, 0.006),
				0.75, Chalk.WHITE, null, 0.0)
	_write("Monday", front_board.transform * Vector3(-3.0, 2.72, 0.006), 0.9, Chalk.WHITE, null, 0.0)
	_draw_on_board(front_board, _scaled_at(Chalk.beamed_notes(), Vector2(3.1, 2.5), 0.28), Chalk.PINK * 0.6, 0.012,
			SEED * 71, "BoardDoodle")
	_draw_on_board(front_board, _scaled_at(Chalk.star(), Vector2(2.2, 2.7), 0.12), Chalk.YELLOW * 0.6, 0.012,
			SEED * 73, "BoardDoodle")

	# The right-hand wall's board, over the desks pushed against it.
	var right := _frame_board(Vector3(half - 0.065, 0, 0.7), -PI * 0.5, 5.2, CLASS_BOARD_FOOT, 3.1, true)
	var sky: Array = []
	sky.append_array(_scaled_at(Chalk.sun(), Vector2(-2.05, 2.05), 0.42))
	for k in 4:
		sky.append(_scaled_at(Chalk.arc(Vector3.ZERO, 0.75 + k * 0.48, 0.35 + k * 0.2, -0.6, 1.5, 24), Vector2(-2.05, 2.05)))
	_draw_on_board(right, sky, Chalk.WHITE * 0.32, 0.01, SEED * 79, "OrbitChalk")
	var planets := [[Vector2(-1.35, 2.25), 0.08, Chalk.ORANGE], [Vector2(-0.85, 1.9), 0.1, Chalk.CYAN],
			[Vector2(-0.3, 2.3), 0.09, Chalk.PINK], [Vector2(0.4, 1.75), 0.2, Chalk.YELLOW]]
	for k in planets.size():
		var pl: Array = planets[k]
		var drawn: Array = [_scaled_at(Chalk.loop(Vector3.ZERO, pl[1], 20), pl[0])]
		if k == 3:
			drawn.append(_scaled_at(Chalk.arc(Vector3.ZERO, 0.36, 0.09, 0.0, TAU, 28), pl[0]))
		_draw_on_board(right, drawn, (pl[2] as Color) * 0.6, 0.012, SEED * 83 + k, "BoardDoodle")
	_draw_on_board(right, _scaled_at(Chalk.rocket(), Vector2(1.7, 2.3), 0.35), Chalk.LIME * 0.6, 0.012, SEED * 89,
			"BoardDoodle")
	_write("homework: practise your scales", right.transform * Vector3(0.6, 1.3, 0.006), 0.8, Chalk.WHITE, null, -PI * 0.5)


## Lines in a plane, scaled by `s` and moved to `at` within it.
static func _scaled_at(lines: Variant, at: Vector2, s := 1.0) -> Variant:
	if lines is PackedVector3Array:
		var moved := PackedVector3Array()
		for p in lines:
			moved.append(Vector3(at.x + p.x * s, at.y + p.y * s, 0))
		return moved
	var out: Array = []
	for line: PackedVector3Array in lines:
		out.append(_scaled_at(line, at, s))
	return out


## A schoolroom clock high on the front wall, over the board: a black bezel, a white face with its
## minutes ticked, and the real time on its hands.
func _hang_the_clock(at: Vector3) -> void:
	var clock := Node3D.new()
	clock.name = "WallClock"
	clock.position = at
	add_child(clock)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.03)
	black.roughness = 0.35
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.85, 0.83, 0.76)
	face.roughness = 0.6
	for spec in [[0.29, 0.06, 0.03, black, "Bezel"], [0.26, 0.05, 0.03 + 0.008, face, "Face"]]:
		var disc := MeshInstance3D.new()
		disc.name = spec[4]
		var cyl := CylinderMesh.new()
		cyl.top_radius = spec[0]
		cyl.bottom_radius = spec[0]
		cyl.height = spec[1]
		cyl.radial_segments = 48
		cyl.rings = 1
		disc.mesh = cyl
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(0, 0, spec[2])
		disc.material_override = spec[3]
		clock.add_child(disc)
	var front_z := 0.03 + 0.008 + 0.025
	for k in 60:
		var a := TAU * k / 60.0
		var long := k % 5 == 0
		var tick := ZoneKit.block(clock, Vector3(0.012 if long else 0.005, 0.04 if long else 0.018, 0.002),
				Vector3(sin(a), cos(a), 0) * (0.225 if long else 0.234) + Vector3(0, 0, front_z + 0.001), black, "Tick")
		tick.rotation.z = -a
	var hands := [[0.13, 0.018, black], [0.2, 0.011, black], [0.22, 0.004, ZoneKit.glow(Color(0.8, 0.1, 0.08), 1.0)]]
	_clock_hands.clear()
	for k in hands.size():
		var pivot := Node3D.new()
		pivot.name = "Hand%d" % k
		pivot.position = Vector3(0, 0, front_z + 0.004 + k * 0.004)
		clock.add_child(pivot)
		var spec: Array = hands[k]
		ZoneKit.block(pivot, Vector3(spec[1], spec[0] + 0.04, 0.003), Vector3(0, spec[0] * 0.5 - 0.02, 0), spec[2], "Hand")
		_clock_hands.append(pivot)
	_tick_the_clock()


func _tick_the_clock() -> void:
	if _clock_hands.size() < 3:
		return
	var now := Time.get_time_dict_from_system()
	var sec := float(now["second"])
	var mins := float(now["minute"]) + sec / 60.0
	var hours := fmod(float(now["hour"]), 12.0) + mins / 60.0
	_clock_hands[0].rotation.z = -TAU * hours / 12.0
	_clock_hands[1].rotation.z = -TAU * mins / 60.0
	_clock_hands[2].rotation.z = -TAU * sec / 60.0


## The alphabet along the top of the front wall, a card a letter, the way an infant class has it,
## each letter in one of the chalk's colours.
func _pin_the_alphabet(half: float, front: float) -> void:
	var card := StandardMaterial3D.new()
	card.albedo_color = Color(0.7, 0.66, 0.56)
	card.roughness = 0.9
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var pitch := minf(0.5, (half * 2.0 - 1.0) / letters.length())
	for i in letters.length():
		var x := (i - (letters.length() - 1) * 0.5) * pitch
		var y := 4.42 + (0.03 if i % 2 == 0 else -0.02)
		var c := ZoneKit.block(self, Vector3(pitch * 0.8, 0.46, 0.006), Vector3(x, y, front + 0.003), card, "AlphabetCard")
		c.rotation.z = (float((i * 7) % 5) - 2.0) * 0.012
		var words := Label3D.new()
		words.name = "Letter"
		words.text = "%s%s" % [letters[i], letters[i].to_lower()]
		words.font_size = 96
		words.outline_size = 0
		words.pixel_size = 0.0024
		var ink: Color = Chalk.NEON[i % Chalk.NEON.size()]
		words.modulate = Color(ink.r * 0.5, ink.g * 0.5, ink.b * 0.5)
		words.shaded = true
		words.double_sided = false
		words.position = Vector3(x, y, front + 0.008)
		add_child(words)


## Opal globes on rods from the high ceiling, four rows of three down the room, hung high enough
## to clear the lattice's head room. Those over the zones are on; the front row, over the desk, is
## off, as someone left it.
func _hang_the_lights(half: float, front: float, back: float) -> void:
	var rod_mat := _brass()
	var off_glass := StandardMaterial3D.new()
	off_glass.albedo_color = Color(0.55, 0.55, 0.52)
	off_glass.roughness = 0.2
	var on_glass := ZoneKit.glow(Color(1.0, 0.88, 0.7), 1.1)
	var spread := minf(5.6, half - 3.0)
	for z in [-1.4, 2.6, 6.6, 10.6]:
		for side in [-1.0, 0.0, 1.0]:
			var on: bool = z > 0.0
			var at := Vector3(side * spread, 4.0, z)
			ZoneKit.block(self, Vector3(0.025, CLASS_HEIGHT - at.y - 0.18, 0.025),
					Vector3(at.x, (CLASS_HEIGHT + at.y + 0.18) * 0.5, at.z), rod_mat, "LightRod")
			var shade := MeshInstance3D.new()
			shade.name = "Globe"
			var ball := SphereMesh.new()
			ball.radius = 0.2
			ball.height = 0.36
			ball.radial_segments = 24
			ball.rings = 12
			shade.mesh = ball
			shade.position = at
			shade.material_override = on_glass if on else off_glass
			shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(shade)
			if on:
				var lamp := OmniLight3D.new()
				lamp.name = "SchoolLight"
				lamp.position = at + Vector3(0, -0.25, 0)
				lamp.light_color = Color(1.0, 0.86, 0.66)
				lamp.light_energy = 0.9
				lamp.omni_range = 7.0
				lamp.omni_attenuation = 1.2
				lamp.shadow_enabled = false
				add_child(lamp)


## Where the pupils' desks stand, pushed to the sides out of the way: each [centre, yaw, chair],
## chair 0 none, 1 standing behind it, 2 upturned on it. Two deep against each long wall beside
## the desk, the left run all the way from the front wall to short of the prop shelf, the right's
## starting past the teacher's desk and stopping short of the bricks table's harmony row.
func _desk_spots() -> Array:
	var half := live_room_half()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 97
	var out: Array = []
	for side in [-1.0, 1.0]:
		var rows: Array = [-3.2, -2.25, -1.3, -0.35, 0.6, 1.55, 2.5] if side < 0 else [-1.2, -0.25, 0.7, 1.65, 2.6]
		for col in 2:
			var x: float = side * (half - 0.65 - col * 0.66)
			for z in rows:
				var chair := 2 if rng.randf() < 0.55 else 1
				out.append([Vector3(x + rng.randf_range(-0.03, 0.03), 0, z + rng.randf_range(-0.04, 0.04)),
						rng.randf_range(-0.06, 0.06), chair])
	return out


func _push_the_desks() -> void:
	var oak := _oak()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.4, 0.38)
	steel.metallic = 0.6
	steel.roughness = 0.5
	var desks := MultiMesh.new()
	desks.transform_format = MultiMesh.TRANSFORM_3D
	desks.mesh = _model_mesh("chalk_desk.glb", {"wood": oak, "steel": steel})
	var chairs := MultiMesh.new()
	chairs.transform_format = MultiMesh.TRANSFORM_3D
	chairs.mesh = _model_mesh("chalk_chair.glb", {"wood": oak, "steel": steel})
	var spots := _desk_spots()
	var chair_at: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 101
	desks.instance_count = spots.size()
	for i in spots.size():
		var at: Vector3 = spots[i][0]
		var desk := Transform3D(Basis(Vector3.UP, spots[i][1]), at)
		desks.set_instance_transform(i, desk)
		match spots[i][2]:
			1:
				chair_at.append(desk * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)),
						Vector3(rng.randf_range(-0.05, 0.05), 0, 0.44)))
			2:
				# Upside down on the lid, its seat flat on it and its back hanging over the edge on
				# the pupil's side, the way the cleaner leaves them.
				chair_at.append(desk * Transform3D(Basis(Vector3.FORWARD, PI) * Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)),
						Vector3(0, 0.74 + 0.441, 0.075)))
	chairs.instance_count = chair_at.size()
	for i in chair_at.size():
		chairs.set_instance_transform(i, chair_at[i])
	for pair in [["PupilDesks", desks], ["PupilChairs", chairs]]:
		var holder := MultiMeshInstance3D.new()
		holder.name = pair[0]
		holder.multimesh = pair[1]
		add_child(holder)


## Where the teacher's desk stands: the front right-hand corner, between the board and the
## class, its drawers to the board.
func _teachers_desk_spot() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(live_room_half() - 1.35, 0, _class_front() + 1.25))


func _stand_the_teachers_desk() -> void:
	var at := _teachers_desk_spot()
	var oak := Materials.cached_scanned("chalk_oak_dark", "black_walnut_veneer_01", "2k", 0.7, Color(0.75, 0.55, 0.38))
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.12, 0.22, 0.14)
	leather.roughness = 0.5
	var desk := _model("chalk_teacher_desk.glb", at.origin, 0.0, {"wood": oak, "top": leather, "brass": _brass()})
	desk.name = "TeachersDesk"
	var chair := _model("chalk_chair.glb", at * Vector3(0.15, 0, -0.62), PI - 0.2, {"wood": oak, "steel": _iron()})
	chair.name = "TeachersChair"
	# The globe, at the end nearest the room.
	var globe_mat := ShaderMaterial.new()
	globe_mat.shader = preload("res://core/venues/shaders/chalk_globe.gdshader")
	var globe := _model("chalk_globe.glb", at * Vector3(-0.42, 0.761, 0.05), 0.5,
			{"wood": oak, "brass": _brass(), "globe": globe_mat})
	globe.name = "Globe"
	# A pile of exercise books, a register, and an apple.
	var covers := [Color(0.55, 0.16, 0.12), Color(0.16, 0.28, 0.5), Color(0.5, 0.42, 0.16), Color(0.2, 0.38, 0.22)]
	var y := 0.761
	for k in covers.size():
		var cover := StandardMaterial3D.new()
		cover.albedo_color = covers[k]
		cover.roughness = 0.85
		var thick := 0.012 + 0.004 * (k % 2)
		var book := ZoneKit.block(self, Vector3(0.21, thick, 0.29), at * Vector3(0.25 + k * 0.006, y + thick * 0.5, 0.02 - k * 0.004),
				cover, "ExerciseBook")
		book.rotation.y = (k - 1.5) * 0.06
		y += thick + 0.0005
	var apple := MeshInstance3D.new()
	apple.name = "Apple"
	var fruit := SphereMesh.new()
	fruit.radius = 0.04
	fruit.height = 0.075
	apple.mesh = fruit
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.62, 0.06, 0.05)
	skin.roughness = 0.3
	apple.material_override = skin
	apple.position = at * Vector3(0.0, 0.761 + 0.0375, 0.15)
	add_child(apple)


## The moon the light comes from, drawn big in the sky past the windows.
func _raise_the_moon() -> void:
	var holder := Node3D.new()
	holder.name = "ChalkMoon"
	# Lower in the sky than the light it throws, so that it is in the windows from the room: from
	# the desk the glass ends a little over twenty degrees up.
	holder.position = Vector3(-1.0, 0.3, 0.25).normalized() * 60.0
	var disc := Chalk.drawing([Chalk.loop(Vector3.ZERO, 1.0, 48), Chalk.loop(Vector3(0.3, 0.25, 0), 0.18, 14),
			Chalk.loop(Vector3(-0.35, -0.2, 0), 0.24, 16), Chalk.loop(Vector3(0.1, -0.5, 0), 0.12, 12)],
			Chalk.WHITE, 0.05, false, 2, SEED * 103)
	holder.add_child(disc)
	_art.append(disc)
	# Rubbed in with a thumb inside the outline: a pale disc, flat, behind the lines.
	var glow := MeshInstance3D.new()
	glow.name = "MoonGlow"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.97
	disc_mesh.bottom_radius = 0.97
	disc_mesh.height = 0.01
	disc_mesh.radial_segments = 48
	disc_mesh.rings = 1
	glow.mesh = disc_mesh
	glow.rotation.x = PI * 0.5
	glow.position = Vector3(0, 0, -0.05)
	glow.material_override = ZoneKit.glow(Color(0.5, 0.55, 0.68), 0.75)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glow)
	add_child(holder)
	holder.look_at(Vector3(0, 1.5, 0.3), Vector3.UP, true)
	holder.scale = Vector3.ONE * 7.0


## Chalk dust drifting in the moonlight: a cloud of motes along each window's beam, each lit only
## while the light reaching it has come in through the glass (chalk_motes.gdshader).
func _dust_the_moonlight() -> void:
	var half := live_room_half()
	var way := MOON_WAY.normalized()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var speck := QuadMesh.new()
	speck.size = Vector2(0.011, 0.011)
	mm.mesh = speck
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 107
	mm.instance_count = 1400
	for i in mm.instance_count:
		var w: Vector2 = CLASS_WINDOWS[i % CLASS_WINDOWS.size()]
		var start := Vector3(-half, rng.randf_range(SILL, HEAD), rng.randf_range(w.x, w.y))
		var t := rng.randf_range(0.15, 0.85) * start.y / -way.y
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, start + way * t))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var motes := MultiMeshInstance3D.new()
	motes.name = "ChalkDust"
	motes.multimesh = mm
	var shine := ShaderMaterial.new()
	shine.shader = preload("res://core/venues/shaders/chalk_motes.gdshader")
	shine.set_shader_parameter("light_way", way)
	shine.set_shader_parameter("wall_x", -half)
	shine.set_shader_parameter("sill", SILL)
	shine.set_shader_parameter("head", HEAD)
	var spans := PackedVector2Array()
	for k in 6:
		spans.append(CLASS_WINDOWS[k] if k < CLASS_WINDOWS.size() else Vector2.ZERO)
	shine.set_shader_parameter("windows", spans)
	motes.material_override = shine
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.custom_aabb = AABB(Vector3(-half - 1.0, -1.0, _class_front() - 1.0), Vector3(half * 2.0 + 2.0, CLASS_HEIGHT + 2.0,
			_class_back() - _class_front() + 2.0))
	add_child(motes)


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 42): a xylophone drawn in
## chalk in the air at the back of the floor, between the kit and the lattice, as everything here is
## drawn; its bars are struck all the same.
func instrument() -> Dictionary:
	return {"kind": &"chalk", "spot": back_wall_instrument(0.2)}


## What stops a person in the classroom: the desks pushed together on each side (one block each,
## chairs and all), the teacher's desk and the radiators under the windows. The zones themselves
## are still only drawn.
func zone_solids() -> Array:
	if variant != CLASSROOM:
		return []
	var out := []
	var half := live_room_half()
	var blocks: Array[Rect2] = []
	for side in [-1.0, 1.0]:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for spot: Array in _desk_spots():
			var at: Vector3 = spot[0]
			if signf(at.x) != side:
				continue
			lo = Vector2(minf(lo.x, at.x - 0.34), minf(lo.y, at.z - 0.25))
			hi = Vector2(maxf(hi.x, at.x + 0.34), maxf(hi.y, at.z + 0.25 + (0.62 if spot[2] == 1 else 0.0)))
		# Out to the wall (the floor's edge), so nothing slips behind them: the radiators under
		# the windows behind them are inside the block.
		if side < 0:
			lo.x = -half + 0.06
		else:
			hi.x = half - 0.06
		blocks.append(Rect2(lo, hi - lo))
		out.append({"c": (lo + hi) * 0.5, "h": (hi - lo) * 0.5, "a": 0.0, "top": 1.2})
	var desk := _teachers_desk_spot().origin
	out.append({"c": Vector2(desk.x, desk.z - 0.15), "h": Vector2(0.72, 0.6), "a": 0.0, "top": 0.8})
	for w in CLASS_WINDOWS:
		var at := Vector2(-half + RADIATOR_IN, (w.x + w.y) * 0.5)
		if not _radiator_under(w) or blocks.any(func(b: Rect2) -> bool: return b.has_point(at)):
			continue
		out.append({"c": at, "h": Vector2(0.1, 0.56), "a": 0.0, "top": 0.72})
	return out

## The tracks' colours here (TrackColours), in its STANDARD order.
## Chalk on slate: pastel sticks, light and soft, never a full saturation.
func track_palette() -> Array:
	return [
		Color(1.00, 0.56, 0.56), Color(1.00, 0.70, 0.48), Color(1.00, 0.89, 0.54), Color(0.84, 0.94, 0.54),
		Color(0.62, 0.94, 0.66), Color(0.56, 0.94, 0.86), Color(0.56, 0.85, 1.00), Color(0.62, 0.69, 1.00),
		Color(0.78, 0.65, 1.00), Color(0.94, 0.65, 0.94), Color(1.00, 0.65, 0.78), Color(0.86, 0.86, 0.86),
	]
