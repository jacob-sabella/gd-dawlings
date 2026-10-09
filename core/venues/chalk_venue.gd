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
## The sketched room: its ceiling line, and the board wall behind the zones.
const ROOM_HEIGHT := 4.2
const BOARD_HEIGHT := 5.2
const BOARD_Z := LIVE_ROOM_BACK + 0.15
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


func venue_id() -> StringName:
	return &"chalk"



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
	else:
		_scatter_doodles()
		_paint_rainbow()
		_join_constellations()
		_throw_comets()
	_draw_zones()
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

	if variant == SKETCHED_ROOM:
		return
	# Out past the footprint, big floor doodles in colour -- arrows, a star, a spiral -- that
	# you see when you look down past the desk.
	var marks := [[Chalk.star(), Vector3(-4.6, 0, -3.6), 1.1, Chalk.YELLOW],
			[Chalk.spiral(), Vector3(4.8, 0, -3.2), 1.3, Chalk.CYAN],
			# Behind the desk, out past the zones on either side.
			[Chalk.heart(), Vector3(-7.6, 0, 3.4), 0.9, Chalk.PINK],
			[Chalk.lightning(), Vector3(7.8, 0, 2.6), 1.2, Chalk.LIME]]
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


## The room, drawn: its outline on the floor, its corners up to a ceiling that is a line, and
## on its walls what a studio has -- a door, a window with the moon in it, a clock, foam
## panels, a pair of speakers on stands -- and lamps hanging down from the ceiling line.
func _sketch_the_room() -> void:
	var half := live_room_half()
	var z0 := -Studio.ROOM_DEPTH * 0.5
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
	walls.append_array(_on_wall(_rect(1.0, 2.1, Vector2(0, 1.05)) + [Chalk.loop(Vector3(0.36, 1.0, 0), 0.04, 10)],
			Vector3(-half, 0, -0.6), PI * 0.5))
	var window := _rect(2.2, 1.5, Vector2(0, 1.95))
	window.append(PackedVector3Array([Vector3(0, 1.2, 0), Vector3(0, 2.7, 0)]))
	window.append(PackedVector3Array([Vector3(-1.1, 1.95, 0), Vector3(1.1, 1.95, 0)]))
	walls.append_array(_on_wall(window, Vector3(-half, 0, 2.4), PI * 0.5))
	walls.append_array(_on_wall(_scaled(Chalk.moon(), 0.28, Vector2(0.5, 2.35)), Vector3(-half, 0, 2.4), PI * 0.5))
	# The right wall: foam panels in a row, each ruled in wedges.
	for k in 4:
		var panel := _rect(0.9, 1.2, Vector2(0, 2.2))
		for w in [-0.3, 0.0, 0.3]:
			panel.append(PackedVector3Array([Vector3(w, 1.6, 0), Vector3(w, 2.8, 0)]))
		walls.append_array(_on_wall(panel, Vector3(half, 0, -1.2 + k * 1.3), -PI * 0.5))
	# The front wall: a clock, high, its hands at a little past ten, and an on-air light.
	var clock: Array = [Chalk.loop(Vector3.ZERO, 0.38, 32), Chalk.loop(Vector3.ZERO, 0.32, 32),
			PackedVector3Array([Vector3.ZERO, Vector3(-0.15, 0.1, 0)]),
			PackedVector3Array([Vector3.ZERO, Vector3(0.07, 0.27, 0)])]
	for t in 12:
		var a := TAU * t / 12.0
		clock.append(PackedVector3Array([Vector3(cos(a), sin(a), 0) * 0.27, Vector3(cos(a), sin(a), 0) * 0.31]))
	walls.append_array(_on_wall(_scaled(clock, 1.0, Vector2(-2.6, 3.0)), Vector3(0, 0, z0), 0.0))
	walls.append_array(_on_wall(_rect(1.0, 0.36, Vector2(2.6, 3.0)), Vector3(0, 0, z0), 0.0))
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
	# Lamps hanging from the ceiling line, over the desk and over the floor behind it.
	for at in [Vector3(-1.6, 0, 1.0), Vector3(1.6, 0, 1.0), Vector3(-1.6, 0, 3.4), Vector3(1.6, 0, 3.4)]:
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
	box.size = Vector3(half * 2.0, BOARD_HEIGHT, 0.08)
	board.mesh = box
	board.material_override = slate
	board.position = Vector3(0, BOARD_HEIGHT * 0.5, BOARD_Z + 0.04)
	add_child(board)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.14)
	wood.roughness = 0.8
	ZoneKit.block(self, Vector3(half * 2.0 + 0.24, 0.12, 0.1), Vector3(0, BOARD_HEIGHT + 0.06, BOARD_Z + 0.03), wood,
			"BoardFrame")
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.12, BOARD_HEIGHT, 0.1), Vector3(side * (half + 0.06), BOARD_HEIGHT * 0.5, BOARD_Z + 0.03),
				wood, "BoardFrame")
	ZoneKit.block(self, Vector3(half * 2.0, 0.04, 0.12), Vector3(0, 0.9, BOARD_Z - 0.06), wood, "ChalkTray")
	# Picture lights along the top of the frame, washing the slate down its height.
	for i in 4:
		var wash := SpotLight3D.new()
		wash.name = "BoardLight%d" % i
		wash.light_color = Color(0.8, 0.85, 1.0)
		wash.light_energy = 2.5
		wash.spot_range = BOARD_HEIGHT + 1.0
		wash.spot_angle = 50.0
		wash.shadow_enabled = false
		wash.position = Vector3(-half + half * 2.0 * (i + 0.5) / 4.0, BOARD_HEIGHT + 0.1, BOARD_Z - 0.7)
		wash.basis = Basis.looking_at(Vector3(0, -1.0, 0.28), Vector3.FORWARD)
		add_child(wash)
	# What is written on it: the session (rewritten when it changes, see _process), and the
	# doodles that collect round the edges of any board.
	var face := BOARD_Z - 0.005
	self.board = board_from(DAW.state)
	_write_the_session(self.board)
	_watch_the_session()
	var doodles := [[Chalk.beamed_notes(), Vector3(-5.4, 3.5, face), 0.35, Chalk.LIME],
			[Chalk.headphones(), Vector3(5.5, 3.6, face), 0.4, Chalk.VIOLET],
			[Chalk.star(), Vector3(-1.9, 3.75, face), 0.16, Chalk.YELLOW],
			[Chalk.heart(), Vector3(1.6, 3.62, face), 0.15, Chalk.PINK],
			[Chalk.cassette(), Vector3(-5.6, 4.0, face), 0.3, Chalk.ORANGE]]
	for i in doodles.size():
		var drawn: Array = []
		for line: PackedVector3Array in doodles[i][0]:
			drawn.append(_board_line(line, doodles[i][1], Vector2.ONE * doodles[i][2]))
		var art := Chalk.drawing(drawn, doodles[i][3] * 0.7, 0.014, false, 2, SEED * 53 + i)
		art.name = "BoardDoodle"
		add_child(art)
		_art.append(art)


## What the board says about the session: the song's sections from its markers, in order, the
## tempo, how many tracks, and the take -- what the armed track would be on if it were
## recording now, or is on while it is. No take when nothing is armed.
static func board_from(state: MixState) -> Dictionary:
	var out := {"sections": PackedStringArray(), "tempo": "", "tracks": "", "take": ""}
	if state == null:
		return out
	var times: Array = state.markers.keys()
	times.sort()
	for t in times:
		var said := str(state.markers[t]).strip_edges().to_upper()
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
	_write(said["tracks"], Vector3(3.6, 3.65, face), 1.0, Chalk.YELLOW, _session)
	_write(said["tempo"], Vector3(-3.4, 3.65, face), 1.0, Chalk.CYAN, _session)
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
func _write(text: String, at: Vector3, scale: float, colour: Color, parent: Node3D = null) -> void:
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
	words.rotation.y = PI
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


func _scatter_doodles() -> void:
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
## will stand there sketched standing up in the air the way every doodle here is -- a riser and
## a kit's two drums, a booth with a mic, the lattice's cube with its cells ruled on the faces,
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


## What stands in zone `id`, as chalk lines in the zone's floor-centred frame.
func _zone_sketch(id: StringName, box: AABB) -> Array:
	var lines: Array = []
	match id:
		&"drums":
			lines.append_array(_box_lines(Vector3(box.size.x - 0.3, 0.3, box.size.z - 0.3), Vector3(0, 0.15, 0)))
			# A kick on its side and a snare: enough of a kit to say "kit".
			var kick := Chalk.loop(Vector3.ZERO, 0.28, 28)
			lines.append(_placed(kick, Vector3(0, 0.6, -0.3), 0.0))
			lines.append(_placed(Chalk.loop(Vector3.ZERO, 0.18, 24), Vector3(0.55, 0.85, 0.1), PI * 0.5,
					true))
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
	if variant == SKETCHED_ROOM:
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
