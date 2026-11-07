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
	"CUT": [["SAMPLE", "SRC", "CHOP", "SCALE", "KEY", "MODE"], ["IN-", "IN+", "OUT-", "OUT+", "DEV", "TRIM"]],
	"PLAY": [["TRIG", "REV", "CHOKE", "LOCK", "FIT"], ["TUNE-", "TUNE+", "VOL-", "VOL+", "PAN<", "PAN>"]],
	"SHAPE": [["ATK", "REL", "FILT"], ["SEND", "FX", "PUNCH"]],
	"MIDI": [["KEYS", "LEARN", "CH", "SEQ"]],
	"STORE": [["SAVE", "LIB", "LOAD", "DEL"], ["KSAVE", "KITS", "KLOAD", "SYNC"]],
}
const PAGE_SAYS := {
	"CUT": "cut a sample and choose where it comes from (SRC, and DEV for which input); trim the selected pad",
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
## SAMPLE from a live source drops the quiet at the start and end of what it caught.
var trim_on := true
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


## Building the deck: pads, keys, labels and pages.
var building := PadDeckBuild.new(self)
## Striking, releasing and playing pads, and MIDI into them.
var voices := PadDeckVoices.new(self)
## Saving, loading and browsing samples and kits.
var library := PadDeckLibrary.new(self)
## Cutting the sample and the keys that step it.
var sampling := PadDeckSampling.new(self)

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


## `PadDeckBuild._build`.
func _build() -> void: building._build()


## The keys under the waveform, on pages: a row of tabs (and STOP, always there) and the page's own keys in up to two rows, big enough to read. Only the page shown can be seen or pressed (`PadDeckBuild._build_keys`).
func _build_keys(wave_x: float, wave_y: float) -> void: building._build_keys(wave_x, wave_y)




## Page `page` of keys shown (the tabs and STOP always are): the rest hidden and out of reach (`PadDeckBuild.show_page`).
func show_page(page: String) -> void: building.show_page(page)


## `PadDeckBuild._label`.
func _label(cap: float, colour: Color) -> Label3D: return building._label(cap, colour)


# --- what the keys do ---------------------------------------------------------------------------

## SAMPLE: the first press marks where the TV is, the second cuts from there to where it is now (`PadDeckSampling.sample`).
func sample() -> void: sampling.sample()




## `PadDeckSampling.step_source`.
func step_source() -> void: sampling.step_source()


## A guest's own sound is on the pads: the host's row stops replacing them (SYNC brings it back) (`PadDeckSampling._made_here`).
func _made_here() -> void: sampling._made_here()


## SYNC: a guest takes the room's pads back (`PadDeckSampling.rejoin`).
func rejoin() -> void: sampling.rejoin()


## DEV: IN's next input (`PadDeckSampling.step_device`).
func step_device() -> void: sampling.step_device()


## `PadDeckSampling.toggle_trim`.
func toggle_trim() -> void: sampling.toggle_trim()


## `PadDeckSampling.step_chop`.
func step_chop() -> void: sampling.step_chop()


## SCALE: the last pad struck across all sixteen, in the song's key where it has one (`PadDeckSampling.toggle_scale`).
func toggle_scale() -> void: sampling.toggle_scale()


## `PadDeckSampling.step_root`.
func step_root(by: int) -> void: sampling.step_root(by)


## `PadDeckSampling.step_mode`.
func step_mode() -> void: sampling.step_mode()


# --- the pads ---------------------------------------------------------------------------------

## Pad `pad` struck at `velocity`: heard through the armed track's bus, lit while it sounds, and told (`struck`) for the take. A LOOP pad struck while it loops stops; a pad in a choke group cuts the others of its group off first (`PadDeckVoices.strike`).
func strike(pad: int, velocity := 100) -> void: voices.strike(pad, velocity)




## Voice `at`'s sound to the effect bus too, `amount` of it (`PadDeckVoices._send`).
func _send(at: int, stream: AudioStream, rate: float, velocity: int, amount: float) -> void:
	voices._send(at, stream, rate, velocity, amount)


## `PadDeckVoices._voice_of`.
func _voice_of(pad: int) -> int: return voices._voice_of(pad)


## Pad `pad` let go: a GATE pad stops (a LOOP pad too, when `force`; a one-shot plays out unless forced, as a choke does) (`PadDeckVoices.release`).
func release(pad: int, force := false) -> void: voices.release(pad, force)


## Every pad quiet (`PadDeckVoices.stop_all`).
func stop_all() -> void: voices.stop_all()


## A pad clicked or touched: struck, and a GATE pad (which has no letting-go here) plays through (`PadDeckVoices.click`).
func click(pad: int) -> void: voices.click(pad)


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






## `PadDeckLibrary.save_to_library`.
func save_to_library() -> void: library.save_to_library()




## `PadDeckLibrary.load_from_library`.
func load_from_library() -> void: library.load_from_library()


## `PadDeckLibrary.save_kit`.
func save_kit() -> void: library.save_kit()


## `PadDeckLibrary.step_kits`.
func step_kits() -> void: library.step_kits()


## `PadDeckLibrary.load_kit`.
func load_kit() -> void: library.load_kit()


## `PadDeckLibrary.delete_browsed`.
func delete_browsed() -> void: library.delete_browsed()


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
	# A text field has the keys (a YouTube search on the TV): they are its letters, not pads.
	if k != null and TextFocus.held(get_viewport()):
		for pad in _held.keys():
			if not k.pressed and pad == PAD_KEYS.find(k.physical_keycode):
				_held.erase(pad)
				release(pad)
		return
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


## A MIDI note meant for the pads: whether the pads took it (a note out of their range is left for the player's instrument). Velocity 0 is a note off. Pads 36-51, or in scale mode every note (`PadDeckVoices.midi`).
func midi(pitch: int, velocity: int, on: bool, from_channel := -1) -> bool:
	return voices.midi(pitch, velocity, on, from_channel)




func _process(_delta: float) -> void:
	_follow_song()
	var now := Time.get_ticks_msec()
	for i in pads.size():
		if pads[i].lit and now >= _lit_until[i]:
			pads[i].lit = false
	if capture != null and capture.recording and Engine.get_process_frames() % 6 == 0:
		_wave_words.text = "CATCHING %s  %.1f s  %s … SAMPLE to end" % [_source_name(), capture.seconds(), _meter(capture.level())]
	elif not is_nan(marked) and tv != null and Engine.get_process_frames() % 6 == 0:
		_wave_words.text = "SAMPLING  %.1f s … SAMPLE to end" % absf(tv.position() - marked)


## The source as the screen says it: IN names the input it is set to.
func _source_name() -> String:
	var name: String = PadCapture.SOURCES[source]
	if name == "IN":
		return "IN · " + PadCapture.device_label(capture.device)
	return name


## A level as a row of bars: how loud the input is right now.
static func _meter(level: float) -> String:
	var bars := clampi(roundi(sqrt(clampf(level, 0.0, 1.0)) * 8.0), 0, 8)
	return "[" + "#".repeat(bars) + "-".repeat(8 - bars) + "]"


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
		voices._release_due(INF)
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
						voices._play_pitch(pitch, int(notes[i + 3]))
					_quiet = false
	voices._release_due(now)




## The waveform, the words and the pads as the bank is.
func refresh(announce := true) -> void:
	if _wave_words == null:
		return
	if capture != null and capture.recording:
		_wave_words.text = "CATCHING %s … SAMPLE to end" % _source_name()
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
		_mode_words.text = "SRC %s  ·  NOTE %d" % [_source_name(), bank.first_note]
	var browsed := library._browsed_words()
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
	(keys["TRIM"] as EqWall.WallKey).lit = trim_on
	(keys["SYNC"] as EqWall.WallKey).lit = tv != null and tv.own_pads
	(keys["DEV"] as EqWall.WallKey).lit = PadCapture.SOURCES[source] == "IN"
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
