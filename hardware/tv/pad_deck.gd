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

## The bank or a pad's settings changed (the room shares them).
signal changed()
signal struck(pad: int, velocity: int)
signal said(words: String)

const PAD := 0.09
const PAD_GAP := 0.014
const KEY := Vector2(0.13, 0.05)
## The pages of keys: a tab each, and the keys of each page by row.
const PAGES := {
	"CUT": [["SAMPLE", "SRC", "CHOP", "SCALE", "KEY", "MODE"], ["IN-", "IN+", "OUT-", "OUT+"]],
	"PLAY": [["TRIG", "REV", "CHOKE", "LOCK", "FIT"], ["TUNE-", "TUNE+", "VOL-", "VOL+", "PAN<", "PAN>"]],
	"SHAPE": [["ATK", "REL", "FILT"], ["SEND", "FX", "PUNCH"]],
	"MIDI": [["KEYS", "LEARN", "CH", "SEQ"]],
	"STORE": [["SAVE", "LIB", "LOAD", "DEL"], ["KSAVE", "KITS", "KLOAD"]],
}
const PAGE_SAYS := {
	"CUT": "cut a sample and choose where it comes from; trim the selected pad",
	"PLAY": "how the selected pad plays: its pitch, volume, pan, direction, choke group and length",
	"SHAPE": "the selected pad's fade in and out, filter and effect",
	"MIDI": "the computer keys, MIDI keyboard learn and channel, and the track's notes",
	"STORE": "your library: keep a pad's sound or all the pads as a kit, and bring them back",
}
const KEY_GAP := 0.012
## The console's foot and top, under the TV's case.
const FOOT := 0.8
const TOP := 1.24
const WIDE := TvSurface.SCREEN.x + TvSurface.BEZEL * 2.0
## The waveform: its size on the console and in pixels.
const WAVE := Vector2(0.84, 0.12)
const WAVE_PIXELS := Vector2i(640, 91)
const VOICES := 16
## The computer keys' sixteen pads, in the MPC's four by four: pad 1 is Z, the bottom left, and the
## top row is 1 2 3 4.
const PAD_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_A, KEY_S, KEY_D, KEY_F,
		KEY_Q, KEY_W, KEY_E, KEY_R, KEY_1, KEY_2, KEY_3, KEY_4]
const KEY_GAP_Y := 0.008
## The FX send bus and the effects on it, stepped by FX.
const FX_BUS := &"PadFx"
const FX_KINDS := ["REVERB", "DELAY", "BOTH"]
const CYCLES := {"atk": [0.0, 0.005, 0.02, 0.05, 0.15, 0.3], "rel": [0.0, 0.05, 0.15, 0.4, 1.0],
		"filt": [-1.0, -0.6, -0.3, 0.0, 0.3, 0.6, 1.0], "send": [0.0, 0.25, 0.5, 0.75, 1.0]}
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
## The pad the second row of keys edits: the last one struck or pointed at.
var selected := 0
## Whether this player stands at the station: then its pads answer the computer keys (when `keys_on`)
## and a MIDI keyboard's notes (`midi`), which no instrument of theirs hears meanwhile.
var engaged := false
var keys_on := true
## Where SAMPLE takes from (PadCapture.SOURCES), the catcher for the sources that are not the TV.
var source := 0
var capture: PadCapture
## MIDI learn: the next hardware note names the selected pad (the bank's first note moves to fit).
var learning := false
## Which MIDI channel the pads listen to: 0 is every channel, 1 to 16 only that one (so a second
## controller on another channel can play the instrument while this one plays the pads).
var channel := 0
## PUNCH: every pad is sent to the effect while it is held on, whatever its own SEND.
var punch := false
## The page of keys shown (one of PAGES), and the keys of each.
var page_shown := "CUT"
var _page_keys := {}
var _built := false
## The library's cursors (into PadLibrary.samples() and kits()), what was browsed last ("sample" or
## "kit"), and whether DEL has been asked once already.
var lib_sample := -1
var lib_kit := -1
var _browsed := ""
var _del_armed := false
const FITS := [0.0, 0.25, 0.5, 1.0, 2.0, 4.0]
## The pads answer the armed track's recorded notes while the song plays (SEQ).
var follow_on := false
var fx_kind := 0
var _fx_voices: Array[AudioStreamPlayer] = []
var _last_song := -1.0
var _offs: Array = []
var _quiet := false
var _voice_pad: Array[int] = []
var _held: Dictionary = {}
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
	for i in VOICES:
		var f := AudioStreamPlayer.new()
		f.name = "Send%d" % i
		add_child(f)
		_fx_voices.append(f)
	capture = PadCapture.new()
	capture.name = "Capture"
	add_child(capture)
	_lit_until.resize(PadBank.PADS)
	_voice_pad.resize(VOICES)
	_voice_pad.fill(-1)
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
	_build_keys(wave_x, wave_y)


## The keys under the waveform, on pages: a row of tabs (and STOP, always there) and the page's own
## keys in up to two rows, big enough to read. Only the page shown can be seen or pressed.
func _build_keys(wave_x: float, wave_y: float) -> void:
	var rows := [
		[["SAMPLE", "press at the start and again at the end of what to sample: from the TV's sound, or the source SRC names", sample],
		["SRC", "where SAMPLE takes from: the TV, the MIX itself (resampling), the ROOM's sounds, or the audio interface IN", step_source],
		["CHOP", "cut it by its hits, or into 16, 8 or 4 equal slices", step_chop],
		["SCALE", "spread the last pad struck across all sixteen, in a key", toggle_scale],
		["KEY", "the scale's root, a semitone up", func() -> void: step_root(1)],
		["MODE", "the next scale: the seven modes, harmonic and melodic minor, pentatonics, blues, chromatic", step_mode]],
		[["TRIG", "how the selected pad plays: ONE through, GATE while held, LOOP until struck again", func() -> void: _edit("mode", 1.0)],
		["REV", "play the selected pad's slice backwards", func() -> void: _edit("rev", 0.0)],
		["CHOKE", "the selected pad's choke group: pads of one group cut each other off (0 is none)", func() -> void: _edit("choke", 1.0)],
		["TUNE-", "the selected pad a semitone down", func() -> void: _edit("tune", -1.0)],
		["TUNE+", "the selected pad a semitone up", func() -> void: _edit("tune", 1.0)],
		["VOL-", "the selected pad quieter", func() -> void: _edit("vol", -0.1)],
		["VOL+", "the selected pad louder", func() -> void: _edit("vol", 0.1)],
		["KEYS", "the computer keys play the pads when you stand here: ZXCV ASDF QWER 1234, a MIDI keyboard's notes always", toggle_keys]],
		[["IN-", "trim the selected pad's start later", func() -> void: _edit("start", 0.05)],
		["IN+", "trim the selected pad's start earlier", func() -> void: _edit("start", -0.05)],
		["OUT-", "trim the selected pad's end earlier", func() -> void: _edit("end", -0.05)],
		["OUT+", "trim the selected pad's end later", func() -> void: _edit("end", 0.05)],
		["ATK", "the selected pad's fade in: none, then longer", func() -> void: _cycle("atk")],
		["REL", "the selected pad's fade out: none, then longer", func() -> void: _cycle("rel")],
		["FILT", "the selected pad's filter: low pass closing, none, high pass opening", func() -> void: _cycle("filt")],
		["SEND", "how much of the selected pad goes to the effect (FX)", func() -> void: _cycle("send")],
		["LOCK", "key-lock: the selected pad's pitch changes (TUNE, SCALE) without its length changing", func() -> void: _edit("lock", 0.0)]],
		[["PAN<", "the selected pad toward the left", func() -> void: _edit("pan", -0.25)],
		["PAN>", "the selected pad toward the right", func() -> void: _edit("pan", 0.25)],
		["FX", "the effect the SEND goes to: reverb, delay or both", step_fx],
		["LEARN", "then strike a key on a MIDI keyboard: that note is the selected pad (the others follow in order)", toggle_learn],
		["SEQ", "play the armed track's recorded notes through the pads while the song plays", toggle_follow],
		["STOP", "silence every pad", stop_all],
		["FIT", "stretch the selected pad's slice, pitch kept, to a sixteenth, an eighth, a beat, two or four at the song's tempo", step_fit],
		["CH", "the MIDI channel the pads listen to: ALL, then 1 to 16 (so another controller can play the instrument)", step_channel],
		["PUNCH", "send every pad to the effect while this is lit", toggle_punch]],
		[["SAVE", "keep the selected pad's sound in your library of samples", save_to_library],
		["LIB", "browse your library of samples (press again for the next)", step_library],
		["LOAD", "put the sample LIB shows on the selected pad", load_from_library],
		["KSAVE", "keep all sixteen pads, with their settings, as a kit in your library", save_kit],
		["KITS", "browse your kits (press again for the next)", step_kits],
		["KLOAD", "put the kit KITS shows on the pads", load_kit],
		["DEL", "delete the sample or kit just browsed (press twice)", delete_browsed]]]
	var defs := {}
	for row in rows:
		for k in row:
			defs[k[0]] = k
	var top := wave_y - WAVE.y * 0.5 - 0.016
	var tabs := []
	for page in PAGES:
		tabs.append([page, PAGE_SAYS[page], func() -> void: show_page(page)])
	tabs.append(defs["STOP"])
	_place_row(tabs, 0, top, wave_x, "tab")
	_page_keys.clear()
	for page in PAGES:
		var keys_here: Array = []
		var lines: Array = PAGES[page]
		for r in lines.size():
			var row: Array = []
			for legend in lines[r]:
				row.append(defs[legend])
				keys_here.append(legend)
			_place_row(row, r + 1, top, wave_x, "page")
		_page_keys[page] = keys_here
	show_page(page_shown)
	_built = true


## One row of keys, `r` rows down from `top`, each as wide as fits (never wider than KEY).
func _place_row(row: Array, r: int, top: float, wave_x: float, kind: String) -> void:
	var width := minf(KEY.x, (WAVE.x - (row.size() - 1) * KEY_GAP) / row.size())
	var across := row.size() * width + (row.size() - 1) * KEY_GAP
	for i in row.size():
		var key := EqWall.WallKey.new()
		var legend: String = row[i][0]
		key.name = "Key" + legend.capitalize().replace("+", "Up").replace("-", "Down").replace("<", "Left").replace(">", "Right")
		key.legend = legend
		key.says = row[i][1]
		key.size = Vector2(width, KEY.y)
		var called := "PADS  " + legend
		key.describe_title = func() -> String: return called
		key.position = Vector3(wave_x - across * 0.5 + width * 0.5 + i * (width + KEY_GAP),
				top - KEY.y * 0.5 - r * (KEY.y + KEY_GAP_Y), 0.011)
		key.pressed.connect(row[i][2])
		add_child(key)
		keys[legend] = key


## Page `page` of keys shown (the tabs and STOP always are): the rest hidden and out of reach.
func show_page(page: String) -> void:
	if not PAGES.has(page):
		return
	page_shown = page
	for legend in keys:
		var key := keys[legend] as EqWall.WallKey
		var here: bool = PAGES.has(legend) or legend == "STOP" or (_page_keys.get(page, []) as Array).has(legend)
		key.visible = here
		key.collision_layer = 2 if here else 0
	if _built:
		refresh()


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
	if PadCapture.SOURCES[source] != "TV":
		_sample_live()
		return
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


## SAMPLE from the mix, the room or the interface: the first press starts catching, the second
## ends it and the sound is the sample.
func _sample_live() -> void:
	if capture.recording:
		var sound := capture.stop()
		if sound.size() < int(PadBank.SHORTEST * PadBank.RATE):
			said.emit("Nothing caught: is anything playing?")
		else:
			bank.set_sample(sound)
			chop = 0
		refresh()
		return
	if not capture.start(PadCapture.SOURCES[source]):
		said.emit(capture.why)
	refresh()


func step_source() -> void:
	if capture.recording:
		capture.stop()
	marked = NAN
	source = (source + 1) % PadCapture.SOURCES.size()
	said.emit("Sampling from: " + PadCapture.SOURCES[source])
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
## told (`struck`) for the take. A LOOP pad struck while it loops stops; a pad in a choke group
## cuts the others of its group off first.
func strike(pad: int, velocity := 100) -> void:
	if pad < 0 or pad >= PadBank.PADS:
		return
	var was := selected
	selected = pad
	if was != pad:
		# The pad struck is the one the keys now edit: show it, without telling the room.
		refresh(false)
	var own := bank.params[pad]
	if int(own["mode"]) == 2 and _voice_of(pad) >= 0:
		release(pad, true)
		return
	var made: Array = bank.sound_of(bank.slice_of(pad), bank.pad_semitones(pad), pad)
	var stream: AudioStreamWAV = made[0]
	if stream == null:
		return
	if not bank.scale_on:
		last_pad = pad
	if int(own["choke"]) > 0:
		for other in PadBank.PADS:
			if other != pad and int(bank.params[other]["choke"]) == int(own["choke"]):
				release(other, true)
	var at := _free_voice()
	var voice := _voices[at]
	_voice_pad[at] = pad
	var bus := DAW.monitor_bus(HitRecorder.armed_track())
	voice.bus = bus if bus != &"" and AudioServer.get_bus_index(bus) >= 0 else AudioPorts.MONITOR
	voice.stream = stream
	voice.pitch_scale = made[1]
	voice.volume_db = linear_to_db(maxf(velocity, 1) / 127.0)
	voice.play()
	_send(at, stream, made[1], velocity, float(own["send"]))
	var held := int(own["mode"]) != 0
	_lit_until[pad] = (1 << 60) if held else Time.get_ticks_msec() + int(stream.get_length() / float(made[1]) * 1000.0)
	pads[pad].lit = true
	if not _quiet:
		struck.emit(pad, velocity)


## The voice to play on: an idle one, else the one that has played longest.
func _free_voice() -> int:
	for i in VOICES:
		if not _voices[i].playing:
			_next_voice = (i + 1) % VOICES
			return i
	var at := _next_voice
	_next_voice = (_next_voice + 1) % VOICES
	return at


## Voice `at`'s sound to the effect bus too, `amount` of it.
func _send(at: int, stream: AudioStream, rate: float, velocity: int, amount: float) -> void:
	var fx := _fx_voices[at]
	fx.stop()
	amount = 1.0 if punch else amount
	if amount <= 0.0:
		return
	_ensure_fx_bus()
	fx.bus = FX_BUS
	fx.stream = stream
	fx.pitch_scale = rate
	fx.volume_db = linear_to_db(maxf(velocity, 1) / 127.0 * amount)
	fx.play()


func _voice_of(pad: int) -> int:
	for i in VOICES:
		if _voice_pad[i] == pad and _voices[i].playing:
			return i
	return -1


## Pad `pad` let go: a GATE pad stops (a LOOP pad too, when `force`; a one-shot plays out unless
## forced, as a choke does).
func release(pad: int, force := false) -> void:
	if pad < 0 or pad >= PadBank.PADS:
		return
	var mode := int(bank.params[pad]["mode"])
	if mode == 0 and not force:
		return
	if mode == 2 and not force:
		return
	for i in VOICES:
		if _voice_pad[i] == pad and _voices[i].playing:
			_voices[i].stop()
			_fx_voices[i].stop()
			_voice_pad[i] = -1
	_lit_until[pad] = 0
	pads[pad].lit = false


## Every pad quiet.
func stop_all() -> void:
	for pad in PadBank.PADS:
		release(pad, true)
	_held.clear()


## A pad clicked or touched: struck, and a GATE pad (which has no letting-go here) plays through.
func click(pad: int) -> void:
	strike(pad, 100)
	if pad >= 0 and pad < PadBank.PADS and int(bank.params[pad]["mode"]) == 1:
		var at := _voice_of(pad)
		if at >= 0 and _voices[at].stream != null:
			_lit_until[pad] = Time.get_ticks_msec() + int(_voices[at].stream.get_length() / _voices[at].pitch_scale * 1000.0)


# --- the second row, the keyboard and MIDI ------------------------------------------------------

func _edit(key: String, by: float) -> void:
	var value: Variant = bank.nudge(selected, key, by)
	if value == null:
		return
	var words := ""
	match key:
		"mode": words = "play " + str(PadBank.PLAY_MODES[int(value)])
		"rev": words = "reversed" if bool(value) else "forwards"
		"choke": words = "choke group %d" % int(value) if int(value) > 0 else "no choke group"
		"tune": words = "%+.0f semitones" % float(value)
		"vol": words = "volume %d%%" % roundi(float(value) * 100.0)
		_: words = str(value)
	said.emit("Pad %d: %s" % [selected + 1, words])
	refresh()


## Step setting `key` of the selected pad through its CYCLES.
func _cycle(key: String) -> void:
	var steps: Array = CYCLES[key]
	var now := float(bank.params[selected][key])
	var at := 0
	for i in steps.size():
		if absf(float(steps[i]) - now) < 0.0001:
			at = i
	var next: float = steps[(at + 1) % steps.size()]
	bank.set_param(selected, key, next)
	said.emit("Pad %d: %s %s" % [selected + 1, key, String.num(next, 3)])
	refresh()


func _browsed_words() -> String:
	var all := PadLibrary.kits() if _browsed == "kit" else PadLibrary.samples()
	var at := lib_kit if _browsed == "kit" else lib_sample
	if _browsed == "" or at < 0 or at >= all.size():
		return ""
	return "%s %s" % ["KIT" if _browsed == "kit" else "LIB", all[at]]


func _base_name() -> String:
	return tv.title if tv != null and tv.title != "" else "sample"


func save_to_library() -> void:
	var sound := bank.slice_frames(selected)
	if sound.is_empty():
		said.emit("Pad %d has no sound to keep." % (selected + 1))
		return
	var name := PadLibrary.fresh("%s_pad%d" % [_base_name(), selected + 1], PadLibrary.samples())
	if PadLibrary.save_sample(name, sound):
		lib_sample = PadLibrary.samples().find(name)
		_browsed = "sample"
		said.emit("Kept pad %d as sample \"%s\" (%d in your library)." % [selected + 1, name, PadLibrary.samples().size()])
	else:
		said.emit("The sample could not be saved.")
	refresh()


func step_library() -> void:
	var all := PadLibrary.samples()
	_del_armed = false
	if all.is_empty():
		said.emit("Your library has no samples yet: SAVE keeps the selected pad.")
		return
	lib_sample = (lib_sample + 1) % all.size()
	_browsed = "sample"
	said.emit("Sample %d of %d: \"%s\" (LOAD puts it on pad %d)." % [lib_sample + 1, all.size(), all[lib_sample], selected + 1])
	refresh()


func load_from_library() -> void:
	var all := PadLibrary.samples()
	if lib_sample < 0 or lib_sample >= all.size():
		said.emit("Browse a sample first: LIB.")
		return
	var sound := PadLibrary.load_sample(all[lib_sample])
	if sound.is_empty():
		said.emit("That sample would not load.")
		return
	bank.put(selected, sound)
	said.emit("Pad %d plays \"%s\"." % [selected + 1, all[lib_sample]])
	refresh()


func save_kit() -> void:
	var name := PadLibrary.save_kit(PadLibrary.fresh("kit", PadLibrary.kits()), bank, _base_name())
	if name == "":
		said.emit("There is no sample on the pads to keep as a kit.")
		return
	lib_kit = PadLibrary.kits().find(name)
	_browsed = "kit"
	said.emit("Kept the pads as kit \"%s\" (%d kits)." % [name, PadLibrary.kits().size()])
	refresh()


func step_kits() -> void:
	var all := PadLibrary.kits()
	_del_armed = false
	if all.is_empty():
		said.emit("You have no kits yet: KSAVE keeps the pads as one.")
		return
	lib_kit = (lib_kit + 1) % all.size()
	_browsed = "kit"
	said.emit("Kit %d of %d: \"%s\" (KLOAD puts it on the pads)." % [lib_kit + 1, all.size(), all[lib_kit]])
	refresh()


func load_kit() -> void:
	var all := PadLibrary.kits()
	if lib_kit < 0 or lib_kit >= all.size():
		said.emit("Browse a kit first: KITS.")
		return
	stop_all()
	var filled := PadLibrary.load_kit(all[lib_kit], bank)
	if filled == 0:
		said.emit("That kit would not load (its samples are gone?).")
		return
	said.emit("Kit \"%s\" is on the pads (%d sounds)." % [all[lib_kit], filled])
	refresh()


func delete_browsed() -> void:
	var is_kit := _browsed == "kit"
	var all := PadLibrary.kits() if is_kit else PadLibrary.samples()
	var at := lib_kit if is_kit else lib_sample
	if _browsed == "" or at < 0 or at >= all.size():
		said.emit("Browse a sample (LIB) or a kit (KITS) first.")
		return
	if not _del_armed:
		_del_armed = true
		said.emit("Press DEL again to delete %s \"%s\" for good." % ["kit" if is_kit else "sample", all[at]])
		return
	_del_armed = false
	var ok := PadLibrary.delete_kit(all[at]) if is_kit else PadLibrary.delete_sample(all[at])
	if is_kit:
		lib_kit = mini(lib_kit, PadLibrary.kits().size() - 1)
	else:
		lib_sample = mini(lib_sample, PadLibrary.samples().size() - 1)
	said.emit("Deleted \"%s\"." % all[at] if ok else "Could not delete it.")
	refresh()


func step_fit() -> void:
	var beat := 60.0 / maxf(DAW.state.tempo if DAW.state != null else 120.0, 20.0)
	var now := float(bank.params[selected]["fit"])
	var at := 0
	for i in FITS.size():
		if absf(float(FITS[i]) * beat - now) < 0.0005:
			at = i
	var next: float = FITS[(at + 1) % FITS.size()]
	bank.set_param(selected, "fit", next * beat)
	said.emit("Pad %d: %s" % [selected + 1, "fit to " + String.num(next, 3) + " beat" if next > 0.0 else "no fit"])
	refresh()


func step_channel() -> void:
	channel = (channel + 1) % 17
	said.emit("The pads listen to %s." % ("every MIDI channel" if channel == 0 else "MIDI channel %d" % channel))
	refresh()


func toggle_punch() -> void:
	punch = not punch
	said.emit("PUNCH: every pad goes to the effect." if punch else "PUNCH off.")
	refresh()


func step_fx() -> void:
	fx_kind = (fx_kind + 1) % FX_KINDS.size()
	_ensure_fx_bus()
	said.emit("Pad effect: " + FX_KINDS[fx_kind])
	refresh()


func toggle_learn() -> void:
	learning = not learning
	if learning:
		said.emit("Strike a note on your MIDI keyboard: it becomes pad %d." % (selected + 1))
	refresh()


func toggle_follow() -> void:
	follow_on = not follow_on
	_last_song = -1.0
	if follow_on:
		said.emit("The pads play the armed track's notes while the song plays; silence that track's own instrument so they are not heard twice.")
	refresh()


## The send bus: a reverb and a delay on it, each in or out by FX; it goes where the pads' own
## sound goes.
func _ensure_fx_bus() -> void:
	var at := AudioServer.get_bus_index(FX_BUS)
	if at < 0:
		at = AudioServer.bus_count
		AudioServer.add_bus(at)
		AudioServer.set_bus_name(at, FX_BUS)
		AudioServer.set_bus_send(at, AudioPorts.bus(AudioPorts.MONITOR))
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.8
		verb.wet = 1.0
		verb.dry = 0.0
		AudioServer.add_bus_effect(at, verb)
		var echo := AudioEffectDelay.new()
		echo.dry = 0.0
		echo.tap1_active = true
		echo.tap1_delay_ms = 250.0
		echo.tap1_level_db = -3.0
		echo.tap2_active = true
		echo.tap2_delay_ms = 500.0
		echo.tap2_level_db = -9.0
		echo.feedback_active = true
		echo.feedback_level_db = -8.0
		AudioServer.add_bus_effect(at, echo)
	AudioServer.set_bus_effect_enabled(at, 0, fx_kind != 1)
	AudioServer.set_bus_effect_enabled(at, 1, fx_kind != 0)


func toggle_keys() -> void:
	keys_on = not keys_on
	refresh()


## The computer keys, while this player stands here: pad down and up.
func _input(event: InputEvent) -> void:
	if not engaged or not keys_on:
		return
	var k := event as InputEventKey
	if k == null or k.echo or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	var pad := PAD_KEYS.find(k.physical_keycode)
	if pad < 0:
		return
	get_viewport().set_input_as_handled()
	if k.pressed:
		_held[pad] = true
		strike(pad, 100)
	elif _held.erase(pad):
		release(pad)


## A MIDI note meant for the pads: whether the pads took it (a note out of their range is left for
## the player's instrument). Velocity 0 is a note off. Pads 36-51, or in scale mode every note.
func midi(pitch: int, velocity: int, on: bool, from_channel := -1) -> bool:
	if not engaged:
		return false
	if channel > 0 and from_channel >= 0 and from_channel != channel - 1:
		return false
	if learning and on and velocity > 0 and not bank.scale_on:
		bank.first_note = clampi(pitch - selected, 0, 127 - PadBank.PADS + 1)
		learning = false
		said.emit("Pad %d is now note %d; pads %d to %d follow." % [selected + 1, pitch, 1, 16])
		refresh()
		return true
	var pad := bank.pad_of_note(pitch)
	if pad < 0 and not bank.scale_on:
		return false
	if on and velocity > 0:
		if pad >= 0:
			strike(pad, velocity)
		else:
			# A scale-mode note between the pads' own: the spread slice at its pitch.
			_play_pitch(pitch, velocity)
		_held[pitch] = pad
	else:
		var was: Variant = _held.get(pitch, pad)
		_held.erase(pitch)
		if int(was) >= 0:
			release(int(was))
	return true


func _play_pitch(pitch: int, velocity: int) -> void:
	var play: Array = bank.play_of(pitch)
	var made: Array = bank.sound_of(play[0], play[1], bank.scale_pad)
	var stream: AudioStreamWAV = made[0]
	if stream == null:
		return
	var at := _free_voice()
	var voice := _voices[at]
	var bus := DAW.monitor_bus(HitRecorder.armed_track())
	voice.bus = bus if bus != &"" and AudioServer.get_bus_index(bus) >= 0 else AudioPorts.MONITOR
	voice.stream = stream
	voice.pitch_scale = made[1]
	voice.volume_db = linear_to_db(maxf(velocity, 1) / 127.0)
	voice.play()
	_voice_pad[at] = -1
	_send(at, stream, made[1], velocity, float(bank.params[bank.scale_pad]["send"]))


func _process(_delta: float) -> void:
	_follow_song()
	var now := Time.get_ticks_msec()
	for i in pads.size():
		if pads[i].lit and now >= _lit_until[i]:
			pads[i].lit = false
	if capture != null and capture.recording and Engine.get_process_frames() % 6 == 0:
		_wave_words.text = "CATCHING %s  %.1f s … SAMPLE to end" % [capture.source, capture.seconds()]
	elif not is_nan(marked) and tv != null and Engine.get_process_frames() % 6 == 0:
		_wave_words.text = "SAMPLING  %.1f s … SAMPLE to end" % absf(tv.position() - marked)


## SEQ: the armed track's recorded notes, struck as the song's playhead crosses them (not recorded
## again), and let go where they end.
func _follow_song() -> void:
	_follow_song_for(HitRecorder.armed_track())


func _follow_song_for(armed: int) -> void:
	var st := DAW.state
	if not follow_on or st == null:
		_last_song = -1.0
		return
	var now := st.position_seconds
	if not st.playing:
		_last_song = now
		_release_due(INF)
		return
	var from := _last_song
	_last_song = now
	if from < 0.0 or now < from or now - from > 0.5:
		return
	var track = null
	var tracks: Dictionary = st.tracks
	if armed > 0 and tracks.has(armed):
		track = tracks[armed]
	if track != null:
		for item in track.items:
			if item.muted or item.notes.is_empty():
				continue
			var lo: float = from - item.start
			var hi: float = now - item.start
			if hi < 0.0 or lo > item.length:
				continue
			var notes: PackedFloat32Array = item.notes
			for i in range(0, notes.size() - 4, 5):
				var on := notes[i]
				if on >= lo and on < hi:
					_quiet = true
					var pitch := int(notes[i + 2])
					var pad := bank.pad_of_note(pitch)
					if pad >= 0:
						strike(pad, int(notes[i + 3]))
						_offs.append([item.start + notes[i + 1], pad])
					elif bank.scale_on:
						_play_pitch(pitch, int(notes[i + 3]))
					_quiet = false
	_release_due(now)


func _release_due(now: float) -> void:
	var keep: Array = []
	for off in _offs:
		if float(off[0]) <= now:
			release(int(off[1]))
		else:
			keep.append(off)
	_offs = keep


## The waveform, the words and the pads as the bank is.
func refresh(announce := true) -> void:
	if _wave_words == null:
		return
	if capture != null and capture.recording:
		_wave_words.text = "CATCHING %s … SAMPLE to end" % capture.source
	elif not is_nan(marked):
		_wave_words.text = "SAMPLING … SAMPLE to end"
	elif bank.frames.is_empty():
		_wave_words.text = "NO SAMPLE · press PLAY on the TV, then SAMPLE at the start and again at the end"
	elif page_shown == "CUT":
		_wave_words.text = "%.2f s  ·  CHOP %s  ·  PAD %d" % [bank.seconds(), CHOPS[chop], selected + 1]
	else:
		_wave_words.text = pad_words(selected)
	Lettering.fit(_wave_words, WAVE.x * 0.6, roundi(0.03 / PIXEL), 12)
	if bank.scale_on:
		_mode_words.text = "%s %s  ·  PAD %d" % [Harmony.SHARP_NAMES[bank.root], bank.mode.to_upper(), bank.scale_pad + 1]
	else:
		_mode_words.text = "SRC %s  ·  NOTE %d" % [PadCapture.SOURCES[source], bank.first_note]
	var browsed := _browsed_words()
	if browsed != "":
		_mode_words.text = browsed
	Lettering.fit(_mode_words, WAVE.x * 0.4, roundi(0.026 / PIXEL), 12)
	for page in PAGES:
		(keys[page] as EqWall.WallKey).lit = page == page_shown
	(keys["SCALE"] as EqWall.WallKey).lit = bank.scale_on
	(keys["KEYS"] as EqWall.WallKey).lit = keys_on
	(keys["LEARN"] as EqWall.WallKey).lit = learning
	(keys["SEQ"] as EqWall.WallKey).lit = follow_on
	(keys["PUNCH"] as EqWall.WallKey).lit = punch
	(keys["CH"] as EqWall.WallKey).lit = channel > 0
	(keys["FIT"] as EqWall.WallKey).lit = float(bank.params[selected]["fit"]) > 0.0
	(keys["LOCK"] as EqWall.WallKey).lit = bool(bank.params[selected]["lock"])
	(keys["SRC"] as EqWall.WallKey).lit = PadCapture.SOURCES[source] != "TV"
	(keys["SEND"] as EqWall.WallKey).lit = float(bank.params[selected]["send"]) > 0.0
	(keys["FILT"] as EqWall.WallKey).lit = float(bank.params[selected]["filt"]) != 0.0
	var sel := bank.params[selected]
	(keys["REV"] as EqWall.WallKey).lit = bool(sel["rev"])
	(keys["TRIG"] as EqWall.WallKey).lit = int(sel["mode"]) != 0
	(keys["CHOKE"] as EqWall.WallKey).lit = int(sel["choke"]) > 0
	(keys["SAMPLE"] as EqWall.WallKey).lit = not is_nan(marked)
	for i in pads.size():
		pads[i].full = bank.slice_of(i).y > bank.slice_of(i).x
		pads[i].words = bank.pad_label(i) if bank.scale_on else str(i + 1)
		pads[i].chosen = i == selected
	_wave_texture.update(draw_wave(bank, WAVE_PIXELS, selected))
	if announce:
		changed.emit()


## What pad `pad` plays as, in words: only what is not as it comes (a pad never touched is "plain").
func pad_words(pad: int) -> String:
	var p := bank.params[pad]
	var def := PadBank.default_params()
	var out: Array[String] = ["PAD %d" % (pad + 1)]
	if int(p["mode"]) != 0:
		out.append(PadBank.PLAY_MODES[int(p["mode"])])
	if float(p["vol"]) != float(def["vol"]):
		out.append("VOL %d%%" % roundi(float(p["vol"]) * 100.0))
	if float(p["tune"]) != 0.0:
		out.append("TUNE %s%s" % ["+" if float(p["tune"]) > 0.0 else "", String.num(float(p["tune"]), 2)])
	if float(p["pan"]) != 0.0:
		out.append("PAN %s%d" % ["L" if float(p["pan"]) < 0.0 else "R", roundi(absf(float(p["pan"])) * 100.0)])
	if bool(p["rev"]):
		out.append("REV")
	if bool(p["lock"]):
		out.append("LOCK")
	if int(p["choke"]) > 0:
		out.append("CHOKE %d" % int(p["choke"]))
	if float(p["start"]) > 0.0 or float(p["end"]) < 1.0:
		out.append("TRIM %d-%d%%" % [roundi(float(p["start"]) * 100.0), roundi(float(p["end"]) * 100.0)])
	if float(p["atk"]) > 0.0:
		out.append("ATK %dms" % roundi(float(p["atk"]) * 1000.0))
	if float(p["rel"]) > 0.0:
		out.append("REL %dms" % roundi(float(p["rel"]) * 1000.0))
	if float(p["filt"]) != 0.0:
		out.append("%s %d%%" % ["LOW" if float(p["filt"]) < 0.0 else "HIGH", roundi(absf(float(p["filt"])) * 100.0)])
	if float(p["send"]) > 0.0:
		out.append("FX %d%%" % roundi(float(p["send"]) * 100.0))
	if float(p["fit"]) > 0.0:
		out.append("FIT %.2fs" % float(p["fit"]))
	if out.size() == 1:
		out.append("plain")
	return "  ·  ".join(out)


## The sample drawn: its loudest and quietest in each column, its slices' starts as lines, each
## slice a shade of its own.
static func draw_wave(b: PadBank, size: Vector2i, chosen := -1) -> Image:
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
		if chosen >= 0 and s >= 0:
			# The selected pad's slice at full colour, trimmed-away ends dim; the rest dimmed.
			if s != chosen:
				colour = colour.darkened(0.55)
			else:
				var sl: Vector2i = b.slices[s]
				var t := float(a - sl.x) / maxf(sl.y - sl.x, 1.0)
				if t < float(b.params[s]["start"]) or t > float(b.params[s]["end"]):
					colour = colour.darkened(0.6)
				else:
					colour = colour.lightened(0.25)
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
	## The pad the keys edit: it glows blue, so the one being edited is never a guess.
	var chosen := false:
		set(v):
			chosen = v
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
		m.emission_enabled = lit or chosen
		m.emission = PadDeck.PAD_LIT if lit else Color(0.35, 0.65, 1.0)
		m.emission_energy_multiplier = 1.0 if lit else 0.55
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
		deck.selected = index
		deck.refresh()
		var hand := held_by
		grab_end(hand)
		deck.click(index)
