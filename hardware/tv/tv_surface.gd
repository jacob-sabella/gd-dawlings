class_name TvSurface
extends Surface

## The sampling station's TV (docs/sampling_station.md, slice 2): YouTube on the control room's
## front wall, right of the timeline, as LEVELS is left of it; where a venue has no wall to hang it
## on, on a stand of its own.
##
## FIND asks for a search or a link (the studio asks: a box on the monitor, `find_asked`); a search
## lists what it found to choose from (`searched`), a link plays at once. The video is fetched whole
## and its sound decoded (Tube), then plays: the sound on the monitor bus, heard here and not in the
## mix, and the picture (TubeFrames) shown by the sound's position, so the two never part. PLAY
## pauses and plays, ◀ and ▶ go back and on SKIP seconds.
##
## Its frame: the origin is the floor under the screen's middle, +Y up, +Z out of its face.

signal find_asked()
signal searched(query: String, results: Array, error: String)
## A pad struck (PadDeck): the note it is, for the take.
signal pad_struck(note: int, velocity: int, seconds: float)
## Something the pads have to say in a toast.
signal pads_said(words: String)

const SCREEN := Vector2(1.44, 0.81)
## The screen's lower edge from the floor (m): over the pads (PadDeck), its middle a standing eye's.
const BOTTOM := 1.5
const BEZEL := 0.035
const DEPTH := 0.05
## The strip under the screen with the title and the time, and the keys under that.
const STRIP := 0.07
const KEY := Vector2(0.17, 0.07)
const KEY_GAP := 0.02
const SKIP := 5.0
const PIXEL := 0.0004
const TITLE_CAP := 0.03
const SAY_CAP := 0.05
const INK := Color(0.92, 0.92, 0.88)
const DIM := Color(0.6, 0.62, 0.66)
const OFF := Color(0.04, 0.045, 0.06)
## The case's top and foot: the screen, the strip and the keys in one black front; the pads under it.
const TOP := BOTTOM + SCREEN.y + BEZEL
const CASE_FOOT := BOTTOM - BEZEL - STRIP - KEY.y - KEY_GAP * 2.0
const FOOT := PadDeck.FOOT
## Where the plaque's top is, under the pads (the studio's mount puts it there).
const PLAQUE_TOP := FOOT - 0.02

var tube := Tube.new()
## The pads' sample and its slices: here, so a rebuild of the wall keeps them.
var bank := PadBank.new()
var deck: PadDeck
## The song's position (s), for the key the pads' scale follows; the studio's.
var song_position: Callable = func() -> float: return 0.0
## The video showing ("" for none), what it is called, and how long it is (s).
var video := ""
var title := ""
var seconds := 0.0
## What the screen says when there is no picture: "" for the picture.
var says := "FIND: a search, or a YouTube link"
var playing := false
var _held_at := 0.0
var _player: AudioStreamPlayer
var _frames: TubeFrames
var _texture: ImageTexture
var _shown: Image
var _screen: MeshInstance3D
var _screen_paint: StandardMaterial3D
var _say: Label3D
var _title: Label3D
var _time: Label3D
var _play_key: EqWall.WallKey
var _loading := ""
## Its grab tab bigger than a desk's: it is read from the seat 4 m off (SurfaceHandle).
var handle_scale := 1.6


func _ready() -> void:
	surface_kind = &"tv"
	if surface_id == &"":
		surface_id = &"tv"
	parks = false
	super()
	AudioPorts.ensure_buses()
	_player = AudioStreamPlayer.new()
	_player.name = "Sound"
	_player.bus = AudioPorts.MONITOR
	_player.finished.connect(func() -> void:
		playing = false
		_held_at = seconds
		_say_state())
	add_child(_player)
	tube.fetched.connect(_on_fetched)
	tube.searched.connect(func(q: String, rows: Array, error: String) -> void:
		if error != "":
			_tell("NOT FOUND: " + error)
		elif video == "":
			_tell("FIND: a search, or a YouTube link")
		searched.emit(q, rows, error))


func _exit_tree() -> void:
	if _frames != null:
		_frames.close()
	tube.finish()


## Search YouTube for `query`, or play the video a link or an id names.
func find(text: String) -> void:
	var missing := Tube.missing_tool()
	if missing != "":
		_tell(missing.to_upper())
		return
	var id := Tube.video_id(text)
	if id != "":
		watch(id)
		return
	_tell("SEARCHING: " + text.strip_edges())
	tube.search(text)


## Play the video `id` from its start: fetched first if it is not here.
func watch(id: String) -> void:
	if id == "" or id == _loading:
		return
	_stop()
	video = ""
	_loading = id
	_tell("FETCHING…" if not Tube.cached(id) else "LOADING…")
	tube.fetch(id)


func _on_fetched(id: String, ok: bool, error: String) -> void:
	if id != _loading:
		return
	if not ok:
		_loading = ""
		_tell("COULD NOT PLAY IT: " + error)
		return
	# A long video's sound is hundreds of megabytes read: off the main thread.
	var wav := Tube.wav_path(id)
	WorkerThreadPool.add_task(func() -> void:
		var stream := AudioStreamWAV.load_from_file(wav)
		_loaded.call_deferred(id, stream))


func _loaded(id: String, stream: AudioStreamWAV) -> void:
	if id != _loading or not is_inside_tree():
		return
	_loading = ""
	if stream == null:
		_tell("COULD NOT PLAY IT: its sound would not load")
		return
	video = id
	var about := Tube.info(id)
	title = str(about.get("title", id))
	seconds = stream.get_length()
	_frames = TubeFrames.new(id)
	_player.stream = stream
	says = ""
	_held_at = 0.0
	play()


func play() -> void:
	if video == "" or _player.stream == null:
		return
	if _held_at >= seconds - 0.05:
		_held_at = 0.0
	_player.play(_held_at)
	playing = true
	_say_state()


func pause() -> void:
	if not playing:
		return
	_held_at = position()
	_player.stop()
	playing = false
	_say_state()


func toggle() -> void:
	if playing:
		pause()
	else:
		play()


## To `t` (s) into the video, playing on if it was.
func seek(t: float) -> void:
	if video == "":
		return
	_held_at = clampf(t, 0.0, maxf(seconds - 0.05, 0.0))
	if playing:
		_player.play(_held_at)
	_say_state()


func skip(by: float) -> void:
	seek(position() + by)


## Where the video is (s): the sound's own position, less what is still on its way to the speakers.
func position() -> float:
	if not playing:
		return _held_at
	var t := _player.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
	return clampf(t, 0.0, seconds)


## The video's sound, as it plays (what SAMPLE cuts from); null with none.
func sound() -> AudioStreamWAV:
	return _player.stream as AudioStreamWAV if video != "" else null


func _stop() -> void:
	_player.stop()
	playing = false
	if _frames != null:
		_frames.close()
		_frames = null
	_shown = null


func _process(delta: float) -> void:
	super(delta)
	if _frames == null or _screen_paint == null:
		return
	var image := _frames.frame_at(position())
	if image == null or image == _shown:
		return
	_shown = image
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	_show_picture()
	if _time != null:
		_time.text = _clock(position()) + " / " + _clock(seconds)


func _tell(words: String) -> void:
	says = words
	_shown = null
	_say_state()


## The screen and the strip as things are: the picture or the words, the title, the time, PLAY lit.
func _say_state() -> void:
	if _screen_paint == null:
		return
	if says != "" or _texture == null or video == "":
		_screen_paint.albedo_texture = null
		_screen_paint.albedo_color = OFF
		_say.text = says
		_say.visible = says != ""
	else:
		_show_picture()
	_title.text = title if video != "" else "YOUTUBE"
	Lettering.fit(_title, SCREEN.x * 0.68, roundi(TITLE_CAP / PIXEL), 12)
	_time.text = (_clock(position()) + " / " + _clock(seconds)) if video != "" else ""
	_play_key.lit = playing


func _show_picture() -> void:
	_screen_paint.albedo_texture = _texture
	_screen_paint.albedo_color = Color.WHITE
	_say.visible = false


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]


func _rebuild() -> void:
	_clear_built()
	var case := MeshInstance3D.new()
	case.name = "Case"
	var box := BoxMesh.new()
	box.size = Vector3(SCREEN.x + BEZEL * 2.0, TOP - CASE_FOOT, DEPTH)
	case.mesh = box
	case.position = Vector3(0, (TOP + CASE_FOOT) * 0.5, -DEPTH * 0.5)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.02, 0.02, 0.025)
	black.roughness = 0.35
	case.material_override = black
	_adopt(case)
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = SCREEN
	_screen.mesh = quad
	_screen.position = Vector3(0, BOTTOM + SCREEN.y * 0.5, 0.002)
	_screen_paint = StandardMaterial3D.new()
	_screen_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen.material_override = _screen_paint
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adopt(_screen)
	_say = _label("", SAY_CAP, INK)
	_say.name = "Says"
	_say.position = Vector3(0, BOTTOM + SCREEN.y * 0.5, 0.006)
	_say.width = (SCREEN.x - 0.16) / PIXEL
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_adopt(_say)
	var strip_y := BOTTOM - BEZEL * 0.5 - STRIP * 0.5
	_title = _label("", TITLE_CAP, INK)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.position = Vector3(-SCREEN.x * 0.5, strip_y, 0.002)
	_adopt(_title)
	_time = _label("", TITLE_CAP, DIM)
	_time.name = "Time"
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.position = Vector3(SCREEN.x * 0.5, strip_y, 0.002)
	_adopt(_time)
	var keys_y := BOTTOM - BEZEL - STRIP - KEY_GAP - KEY.y * 0.5
	var row := [["FIND", "search YouTube, or paste a link", func() -> void: find_asked.emit()],
			["◀ %d s" % int(SKIP), "back %d seconds" % int(SKIP), func() -> void: skip(-SKIP)],
			["PLAY", "play or pause", toggle],
			["%d s ▶" % int(SKIP), "on %d seconds" % int(SKIP), func() -> void: skip(SKIP)]]
	var across := row.size() * KEY.x + (row.size() - 1) * KEY_GAP
	for i in row.size():
		var key := EqWall.WallKey.new()
		key.name = "Key" + str(row[i][0]).replace(" ", "").replace("◀", "Back").replace("▶", "On")
		key.legend = row[i][0]
		key.says = row[i][1]
		var called := "TV  " + str(row[i][0])
		key.describe_title = func() -> String: return called
		key.size = KEY
		key.position = Vector3(-across * 0.5 + KEY.x * 0.5 + i * (KEY.x + KEY_GAP), keys_y, 0.011)
		key.pressed.connect(row[i][2])
		_adopt(key)
		if row[i][0] == "PLAY":
			_play_key = key
	_say_state()
	deck = PadDeck.new()
	deck.name = "Pads"
	deck.bank = bank
	deck.tv = self
	deck.struck.connect(func(pad: int, velocity: int) -> void:
		var slice := bank.slice_of(pad)
		var rate: float = pow(2.0, bank.pad_semitones(pad) / 12.0)
		pad_struck.emit(bank.note_of(pad), velocity, (slice.y - slice.x) / float(PadBank.RATE) / rate))
	deck.said.connect(func(words: String) -> void: pads_said.emit(words))
	_adopt(deck)

func _label(words: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.modulate = colour
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l
