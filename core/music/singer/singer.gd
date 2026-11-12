class_name Singer
extends RackVoice

## The vocal booth's singer, sounding: a rack of its own with one VOICE module (CHIMERA, native/rack/modules_voice.cc)
## into OUT, run as an engine process on the host (RackVoice), played through the singer's track and recorded onto
## it like the modular room's rack. What it is set to is the room's row `singer` (SingerRow, `apply_row`); what it
## sings is the song's: the lyrics (MixState.lyrics, as syllables, `set_lyrics`) on the notes of the vocal part
## (`sing_part`), or on keys played at the booth (`play`); and the moments the booth asks for (`say`, `beat_hit`, `grab`,
## `cry`). What its body is doing, the head draws (`body`, VoiceTele), and which syllable it is on, the lyric board
## (`sung`, `syllables`).

## The VOICE module's id in this rack.
const ID := "v"

var _row := {}
var _lyrics_sent := ""
var _part_sent := ""


func _init() -> void:
	patch = RackPatch.sanitize({"modules": {ID: {"type": "builtin.voice", "at": [0, 0]}, "o": {"type": RackPatch.OUT_MODULE, "at": [6, 0]}},
			"cables": [[ID + ".out", "o.l"]]})


## Start the engine (and set it as the row and the lyrics say again: a fresh process knows nothing).
func start() -> bool:
	set_patch(patch)
	if not super.start():
		return false
	var row := _row
	_row = {}
	_lyrics_sent = ""
	_part_sent = ""
	if not row.is_empty():
		apply_row(row)
	return true


## A knob's position on the wire (0..1) for the value `real` of knob `k`: a step knob's middle of its step.
static func position(k: String, real: float) -> float:
	match k:
		"mode": return (clampf(real, 0, 3) + 0.5) / 4.0
		"beast", "call": return (clampf(real, 0, 3) + 0.5) / 4.0
		"sound": return (clampf(real, 0, 9) + 0.5) / 10.0
		"seq": return 0.75 if real > 0.5 else 0.25
	return clampf(real, 0.0, 1.0)


## The voice set as the room's row says: only what changed is sent (a pattern as words, the rest as knobs).
func apply_row(row: Dictionary) -> void:
	var r := SingerRow.sanitize(row)
	var was := _row
	_row = r
	for k in ["mode", "body", "child", "vowel", "open", "vibrato", "sound", "beast", "call"]:
		if not was.has(k) or not is_equal_approx(float(was[k]), float(r[k])):
			knob(ID, k, position(k, float(r[k])))
	if not was.has("seq") or was["seq"] != r["seq"]:
		knob(ID, "seq", position("seq", 1.0 if r["seq"] else 0.0))
	if not was.has("beat") or was["beat"] != r["beat"]:
		engine.say("text %s.beat %s" % [ID, r["beat"]])
	if not was.has("track") or int(was["track"]) != int(r["track"]):
		set_track(int(r["track"]))


## The song's words, sung a syllable a note: the lyrics' lines (LRC times and tags taken off), told again only
## when they change.
func set_lyrics(lrc: String) -> void:
	var words := words_of(lrc)
	if words == _lyrics_sent:
		return
	_lyrics_sent = words
	engine.say("text %s.lyrics %s" % [ID, words])


## The words of LRC text `lrc`, on one line: every line's text in the order sung, tags and times dropped.
static func words_of(lrc: String) -> String:
	var lyrics := Lyrics.parse(lrc)
	var out := PackedStringArray()
	for i: int in lyrics.sequence():
		var t := String(lyrics.lines[i]["text"]).strip_edges()
		if t != "":
			out.append(t)
	return " ".join(out).replace("\n", " ").left(Lyrics.MOST)


## The vocal part from the song: `notes` as [beat, midi, beats] in song order (VocalPart.notes), sung from the
## syllable `first` on at `bpm`. Told again only when it changes; an empty part stops it.
func sing_part(notes: Array, bpm: float, first := 0) -> void:
	var line := VocalPart.song_line(notes, bpm, first)
	if line == _part_sent:
		return
	_part_sent = line
	engine.say("text %s.%s" % [ID, "song_stop" if line == "" else "song " + line])


## A line spoken: English, or IPA with `ipa`.
func say(text: String, ipa := false) -> void:
	engine.say("text %s.%s %s" % [ID, "say_ipa" if ipa else "say", text.replace("\n", " ").left(SingerRow.SAY_MOST)])


## A beatbox sound (its pattern symbol), at `pitch` for the hum.
func beat_hit(sound: String, pitch := 0) -> void:
	engine.say("text %s.hit %s %d" % [ID, sound, pitch])


## A hand on part `name` of the mouth, 0..1 across its travel, or let go (< 0).
func grab(name: String, v: float) -> void:
	engine.say("text %s.artic %s %s" % [ID, name, "off" if v < 0.0 else "%.4f" % clampf(v, 0.0, 1.0)])


## Every hand let go of the mouth.
func let_go() -> void:
	engine.say("text %s.artic off" % ID)


## A key at the booth: the next syllable on (SING), a breath (VOWEL), a hit (BEAT), a call (BEAST).
func play(pitch: int, on: bool) -> void:
	if on:
		note_on(pitch, 100)
	else:
		note_off(pitch)


## The creature's call `index`.
func cry(index: int) -> void:
	engine.say("text %s.call %d" % [ID, index])


## What the body is doing now (VoiceTele.read), `{}` before the engine has said.
func body() -> Dictionary:
	var v: Dictionary = engine.voices.get(ID, {})
	return VoiceTele.read(v.get("tele", PackedFloat32Array()))


## The head's outlines now (RackEngine.frames), `{}` before the engine has said.
func frame() -> Dictionary:
	return engine.frames.get(ID, {})


## The syllable being sung (an index into `syllables`), -1 for none.
func sung() -> int:
	return int((engine.voices.get(ID, {}) as Dictionary).get("syl", -1))


## The lyrics as the voice sings them, a syllable each.
func syllables() -> PackedStringArray:
	return engine.syllables.get(ID, PackedStringArray())
