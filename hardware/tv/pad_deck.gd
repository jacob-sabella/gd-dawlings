class_name PadDeck
extends Node3D

## The sampling station's console, under its TV (docs/sampling_station.md, slices 3 and 5): sixteen
## pads, the sample's waveform with its slices, and the keys that make and cut it.
##
## SAMPLE is pressed twice while the TV plays: from the first press to the second is cut from the
## video's sound exactly (PadBank.cut) and chopped into sixteen equal slices. CHOP steps the cut:
## by its hits, or into 16, 8 or 4 equal slices. SCALE spreads the last pad struck across all
## sixteen in the song's key (KEY and MODE step it). A pad struck is heard through the armed
## track's own bus (DAW.monitor_bus), as a played key is, and lights for as long as it sounds.
##
## Its frame is the TV's: the origin the floor under the screen's middle, +Z out of its face.
## Built by TvSurface, which keeps the bank (a rebuild of the wall keeps the sample).

signal struck(pad: int, velocity: int)
signal said(words: String)

const PAD := 0.09
const PAD_GAP := 0.014
const KEY := Vector2(0.13, 0.06)
const KEY_GAP := 0.012
## The console's foot and top, under the TV's case.
const FOOT := 0.8
const TOP := 1.24
const WIDE := TvSurface.SCREEN.x + TvSurface.BEZEL * 2.0
## The waveform: its size on the console and in pixels.
const WAVE := Vector2(0.84, 0.2)
const WAVE_PIXELS := Vector2i(640, 152)
const VOICES := 8
## CHOP's steps, from 16 (what SAMPLE cuts it into) to its hits first.
const CHOPS := ["16", "HITS", "8", "4"]
const PIXEL := 0.0004
const INK := Color(0.92, 0.92, 0.88)
const DIM := Color(0.6, 0.62, 0.66)
const PAD_OFF := Color(0.2, 0.21, 0.24)
const PAD_FULL := Color(0.55, 0.52, 0.45)
const PAD_LIT := Color(1.0, 0.62, 0.2)

var bank: PadBank
var tv: TvSurface
## The chop last chosen (index into CHOPS).
var chop := 0
## Where SAMPLE's first press was (s into the video), or NAN for none.
var marked := NAN
var last_pad := 0
var pads: Array[Pad] = []
var keys := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _lit_until: Array[int] = []
var _wave_texture: ImageTexture
var _wave_words: Label3D
var _mode_words: Label3D


func _ready() -> void:
	AudioPorts.ensure_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_voices.append(p)
	_lit_until.resize(PadBank.PADS)
	_build()
	refresh()


func _build() -> void:
	var panel := MeshInstance3D.new()
	panel.name = "Console"
	var box := BoxMesh.new()
	box.size = Vector3(WIDE, TOP - FOOT, TvSurface.DEPTH)
	panel.mesh = box
	panel.position = Vector3(0, (TOP + FOOT) * 0.5, -TvSurface.DEPTH * 0.5)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.11, 0.115, 0.13)
	paint.roughness = 0.6
	panel.material_override = paint
	add_child(panel)
	# The pads, four by four, pad 1 at the bottom left as on an MPC.
	var grid := PAD * 4.0 + PAD_GAP * 3.0
	var left := -WIDE * 0.5 + 0.06
	var bottom := FOOT + (TOP - FOOT - grid) * 0.5
	for i in PadBank.PADS:
		var pad := Pad.new()
		pad.deck = self
		pad.index = i
		pad.name = "Pad%d" % (i + 1)
		pad.position = Vector3(left + PAD * 0.5 + (i % 4) * (PAD + PAD_GAP),
				bottom + PAD * 0.5 + (i / 4) * (PAD + PAD_GAP), 0.006)
		add_child(pad)
		pads.append(pad)
	# The waveform on the right, the words over it, the keys under it.
	var wave_x := WIDE * 0.5 - 0.06 - WAVE.x * 0.5
	var wave_y := TOP - 0.05 - WAVE.y * 0.5
	var screen := MeshInstance3D.new()
	screen.name = "Waveform"
	var quad := QuadMesh.new()
	quad.size = WAVE
	screen.mesh = quad
	screen.position = Vector3(wave_x, wave_y, 0.002)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wave_texture = ImageTexture.create_from_image(Image.create(WAVE_PIXELS.x, WAVE_PIXELS.y, false, Image.FORMAT_RGB8))
	lit.albedo_texture = _wave_texture
	screen.material_override = lit
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	_wave_words = _label(0.03, INK)
	_wave_words.name = "SampleWords"
	_wave_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wave_words.position = Vector3(wave_x - WAVE.x * 0.5, wave_y + WAVE.y * 0.5 + 0.018, 0.002)
	add_child(_wave_words)
	_mode_words = _label(0.026, DIM)
	_mode_words.name = "ModeWords"
	_mode_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_words.position = Vector3(wave_x + WAVE.x * 0.5, wave_y + WAVE.y * 0.5 + 0.018, 0.002)
	add_child(_mode_words)
	var row := [["SAMPLE", "press at the start and again at the end of what to sample from the TV", sample],
			["CHOP", "cut it by its hits, or into 16, 8 or 4 equal slices", step_chop],
			["SCALE", "spread the last pad struck across all sixteen, in a key", toggle_scale],
			["KEY", "the scale's root, a semitone up", func() -> void: step_root(1)],
			["MODE", "the next scale: the seven modes, harmonic and melodic minor, pentatonics, blues, chromatic", step_mode]]
	var across := row.size() * KEY.x + (row.size() - 1) * KEY_GAP
	for i in row.size():
		var key := EqWall.WallKey.new()
		var legend: String = row[i][0]
		key.name = "Key" + legend.capitalize()
		key.legend = legend
		key.says = row[i][1]
		key.size = KEY
		var called := "PADS  " + legend
		key.describe_title = func() -> String: return called
		key.position = Vector3(wave_x - across * 0.5 + KEY.x * 0.5 + i * (KEY.x + KEY_GAP),
				wave_y - WAVE.y * 0.5 - 0.02 - KEY.y * 0.5, 0.011)
		key.pressed.connect(row[i][2])
		add_child(key)
		keys[legend] = key


func _label(cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.modulate = colour
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l


# --- what the keys do ---------------------------------------------------------------------------

## SAMPLE: the first press marks where the TV is, the second cuts from there to where it is now.
func sample() -> void:
	if tv == null or tv.video == "" or tv.sound() == null:
		said.emit("Play something on the TV first: SAMPLE takes what it plays.")
		return
	var now := tv.position()
	if is_nan(marked):
		marked = now
		refresh()
		return
	var from := minf(marked, now)
	var to := maxf(marked, now)
	marked = NAN
	if to - from < PadBank.SHORTEST:
		refresh()
		return
	bank.set_sample(PadBank.cut(tv.sound(), from, to))
	chop = 0
	refresh()


func step_chop() -> void:
	if bank.frames.is_empty():
		return
	chop = (chop + 1) % CHOPS.size()
	if CHOPS[chop] == "HITS":
		if bank.chop_transients() <= 1:
			said.emit("No hits to cut it at: cut into 16 instead.")
			chop = 0
			bank.chop_equal(16)
	else:
		bank.chop_equal(int(CHOPS[chop]))
	refresh()


## SCALE: the last pad struck across all sixteen, in the song's key where it has one.
func toggle_scale() -> void:
	bank.scale_on = not bank.scale_on
	if bank.scale_on:
		bank.scale_pad = last_pad
		var key := Harmony.at(DAW.state, float(tv.song_position.call())) if tv != null and DAW.state != null else null
		if key != null:
			bank.root = key.root
			bank.mode = key.mode
	refresh()


func step_root(by: int) -> void:
	bank.root = posmod(bank.root + by, 12)
	refresh()


func step_mode() -> void:
	var at := PadBank.MODES.find(bank.mode)
	bank.mode = PadBank.MODES[(at + 1) % PadBank.MODES.size()]
	refresh()


# --- the pads ---------------------------------------------------------------------------------

## Pad `pad` struck at `velocity`: heard through the armed track's bus, lit while it sounds, and
## told (`struck`) for the take.
func strike(pad: int, velocity := 100) -> void:
	if pad < 0 or pad >= PadBank.PADS:
		return
	var made: Array = bank.sound_of(bank.slice_of(pad), bank.pad_semitones(pad))
	var stream: AudioStreamWAV = made[0]
	if stream == null:
		return
	if not bank.scale_on:
		last_pad = pad
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	var bus := DAW.monitor_bus(HitRecorder.armed_track())
	voice.bus = bus if bus != &"" and AudioServer.get_bus_index(bus) >= 0 else AudioPorts.MONITOR
	voice.stream = stream
	voice.pitch_scale = made[1]
	voice.volume_db = linear_to_db(velocity / 127.0)
	voice.play()
	_lit_until[pad] = Time.get_ticks_msec() + int(stream.get_length() / float(made[1]) * 1000.0)
	pads[pad].lit = true
	struck.emit(pad, velocity)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in pads.size():
		if pads[i].lit and now >= _lit_until[i]:
			pads[i].lit = false
	if not is_nan(marked) and tv != null and Engine.get_process_frames() % 6 == 0:
		_wave_words.text = "SAMPLING  %.1f s … SAMPLE to end" % absf(tv.position() - marked)


## The waveform, the words and the pads as the bank is.
func refresh() -> void:
	if _wave_words == null:
		return
	if not is_nan(marked):
		_wave_words.text = "SAMPLING … SAMPLE to end"
	elif bank.frames.is_empty():
		_wave_words.text = "NO SAMPLE · play the TV, SAMPLE twice"
	else:
		_wave_words.text = "%.2f s  ·  CHOP %s" % [bank.seconds(), CHOPS[chop]]
	Lettering.fit(_wave_words, WAVE.x * 0.6, roundi(0.03 / PIXEL), 12)
	if bank.scale_on:
		_mode_words.text = "%s %s  ·  PAD %d" % [Harmony.SHARP_NAMES[bank.root], bank.mode.to_upper(), bank.scale_pad + 1]
	else:
		_mode_words.text = ""
	Lettering.fit(_mode_words, WAVE.x * 0.4, roundi(0.026 / PIXEL), 12)
	(keys["SCALE"] as EqWall.WallKey).lit = bank.scale_on
	(keys["SAMPLE"] as EqWall.WallKey).lit = not is_nan(marked)
	for i in pads.size():
		pads[i].full = bank.slice_of(i).y > bank.slice_of(i).x
		pads[i].words = bank.pad_label(i) if bank.scale_on else str(i + 1)
	_wave_texture.update(draw_wave(bank, WAVE_PIXELS))


## The sample drawn: its loudest and quietest in each column, its slices' starts as lines, each
## slice a shade of its own.
static func draw_wave(b: PadBank, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(Color(0.03, 0.035, 0.05))
	var n := b.frames.size()
	if n == 0:
		return image
	var mid := size.y / 2
	var slice_of_column := PackedInt32Array()
	slice_of_column.resize(size.x)
	slice_of_column.fill(-1)
	for s in PadBank.PADS:
		var sl: Vector2i = b.slices[s]
		if sl.y <= sl.x:
			continue
		for x in range(sl.x * size.x / n, mini(sl.y * size.x / n + 1, size.x)):
			slice_of_column[x] = s
	for x in size.x:
		var a := x * n / size.x
		var z := maxi((x + 1) * n / size.x, a + 1)
		var hi := -1.0
		var lo := 1.0
		for i in range(a, mini(z, n), maxi(1, (z - a) / 64)):
			var v := (b.frames[i].x + b.frames[i].y) * 0.5
			hi = maxf(hi, v)
			lo = minf(lo, v)
		var s := slice_of_column[x]
		var colour := Color(0.35, 0.37, 0.42) if s < 0 else \
				(Color(1.0, 0.62, 0.2) if s % 2 == 0 else Color(0.95, 0.82, 0.45))
		var top := clampi(mid - int(hi * mid), 0, size.y - 1)
		var foot := clampi(mid - int(lo * mid), 0, size.y - 1)
		for y in range(top, foot + 1):
			image.set_pixel(x, y, colour)
	for s in PadBank.PADS:
		var sl: Vector2i = b.slices[s]
		if sl.y > sl.x:
			var x := clampi(sl.x * size.x / n, 0, size.x - 1)
			for y in size.y:
				image.set_pixel(x, y, Color(0.9, 0.9, 0.95))
	return image


## A pad: struck by a click or a hand closing on it, lit while it sounds; darker when it has
## nothing to play.
class Pad extends ControlAffordance:
	var deck: PadDeck
	var index := 0
	var lit := false:
		set(v):
			lit = v
			_paint()
	var full := false:
		set(v):
			full = v
			_paint()
	var words := "":
		set(v):
			words = v
			if _words != null:
				_words.text = v
	var _face: MeshInstance3D
	var _words: Label3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(PadDeck.PAD, PadDeck.PAD, 0.02)
		shape.shape = box
		add_child(shape)
		_face = MeshInstance3D.new()
		_face.name = "Face"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(PadDeck.PAD, PadDeck.PAD, 0.012)
		_face.mesh = mesh
		_face.material_override = StandardMaterial3D.new()
		add_child(_face)
		_words = Label3D.new()
		_words.name = "Words"
		_words.pixel_size = PadDeck.PIXEL
		_words.font_size = roundi(0.03 / PadDeck.PIXEL)
		_words.modulate = Color(0.08, 0.08, 0.09)
		_words.double_sided = false
		_words.position = Vector3(0, -PadDeck.PAD * 0.3, 0.0065)
		_words.text = words
		Lettering.range_to_legibility(_words)
		add_child(_words)
		_paint()

	func _paint() -> void:
		if _face == null:
			return
		var m := _face.material_override as StandardMaterial3D
		m.albedo_color = PadDeck.PAD_LIT if lit else (PadDeck.PAD_FULL if full else PadDeck.PAD_OFF)
		m.emission_enabled = lit
		m.emission = PadDeck.PAD_LIT
		m.roughness = 0.85
		# Dark on a pad with a slice, pale on an empty one.
		_words.modulate = Color(0.08, 0.08, 0.09) if lit or full else Color(0.55, 0.56, 0.6)

	func _default_title() -> String:
		return "PAD %d" % (index + 1)

	func _default_readout() -> String:
		return words if words != "" and words != str(index + 1) else ""

	func hint() -> String:
		return "strike it: its slice, through the armed track"

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		deck.strike(index)
