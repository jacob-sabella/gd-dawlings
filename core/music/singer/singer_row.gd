class_name SingerRow
extends RefCounted

## The vocal booth's singer as the room has it: the room's row `singer` (what every player's booth shows and what the
## host's voice is set to), and every change to it as one ask, `singer` [op, args], answered here on the host.
##
## The row: `mode` (SING, VOWEL, BEAT, BEAST), the body (`body`: man to woman, `child`: toward a child), the vowel pad
## (`vowel`, `open`, 0..1), `vibrato` (0..1 of the knob), the beat pattern (`beat`, CHIMERA's notation) and whether it
## plays with the song (`seq`), the beat SOUND a pad hit makes (`sound`), the creature (`beast`) and its call
## (`call`), the track the voice sounds and records on (`track`, 0 none), the MIDI track whose notes it sings (`part`,
## 0 none) and the power. Asks that are not the row but a moment, the host plays and forgets: `say` [text, ipa] (a
## line spoken), `hit` [sound] (a beatbox sound), `grab` [articulator, 0..1 or -1 to let go] (a hand on the mouth),
## `play` [pitch, on] (a key at the booth), `cry` [call] (the creature's call) and `strike` [stone] (a stone of the
## venue's creature's perch, Bestiary).

## The verb, and the room row's key.
const VERB := &"singer"
const ROW := &"singer"
const MODES := ["SING", "VOWEL", "BEAT", "BEAST"]
enum Mode { SING, VOWEL, BEAT, BEAST }
## The beatbox sounds by their pattern symbols, and what a pad says.
const SOUNDS := ["B", "t", "tss", "Pf", "K", "^K", "!", "P!", "kch", "m"]
const SOUND_NAMES := ["KICK", "HAT", "OPEN HAT", "SNARE", "RIM", "INWARD", "CLICK", "POP", "CRASH", "HUM"]
const BEASTS := ["songbird", "seal", "alligator", "elephant"]
const BEAST_NAMES := ["SONGBIRD", "SEAL", "ALLIGATOR", "ELEPHANT"]
## CHIMERA's beat presets, by name, as the booth's pattern key steps through them.
const PRESETS := ["Boots and cats", "Four on the floor", "Breakbeat", "Rimshot shuffle", "Inward snare",
		"Clicks and pops", "Hum bass"]
## The longest line said or pattern kept (characters), and the most steps a pattern has.
const SAY_MOST := 400
const BEAT_MOST := 200
const STEPS := 16
## What a key here may be (MIDI).
const LOWEST := 24
const HIGHEST := 108
## A row's numbers 0..1 (the knobs and the pad).
const UNIT_KEYS := ["body", "child", "vowel", "open", "vibrato"]
const MOMENTS := ["say", "hit", "grab", "play", "cry", "strike"]


static func fresh() -> Dictionary:
	return {"mode": Mode.SING, "body": 0.0, "child": 0.0, "vowel": 0.5, "open": 0.6, "vibrato": 0.35,
			"beat": PRESETS[0], "seq": false, "sound": 0, "beast": 0, "call": 0, "track": 0, "part": 0, "power": true}


## `raw` as a row: every field there and in range, anything else dropped (a guest's row, an old save).
static func sanitize(raw: Variant) -> Dictionary:
	var out := fresh()
	if not raw is Dictionary:
		return out
	var r: Dictionary = raw
	for k in UNIT_KEYS:
		if r.get(k) is float or r.get(k) is int:
			out[k] = clampf(float(r[k]), 0.0, 1.0)
	for pair in [["mode", MODES.size()], ["sound", SOUNDS.size()], ["beast", BEASTS.size()], ["call", 4]]:
		if r.get(pair[0]) is float or r.get(pair[0]) is int:
			out[pair[0]] = clampi(int(r[pair[0]]), 0, int(pair[1]) - 1)
	for k in ["track", "part"]:
		if r.get(k) is float or r.get(k) is int:
			out[k] = maxi(int(r[k]), 0)
	for k in ["seq", "power"]:
		if r.get(k) is bool:
			out[k] = r[k]
	if r.get("beat") is String:
		out["beat"] = clean_beat(r["beat"])
	return out


## A pattern as the row keeps it: a preset's name, or steps of CHIMERA's notation (`B . t . | Pf . t .`), short.
static func clean_beat(text: String) -> String:
	var t := text.strip_edges().left(BEAT_MOST)
	if t in PRESETS:
		return t
	var kept := PackedStringArray()
	for word in t.replace("|", " | ").split(" ", false):
		if word == "|" or word == "." or SOUNDS.has(word.get_slice(":", 0)):
			kept.append(word)
	return " ".join(kept)


## A pattern's steps, `STEPS` of them: each a sound symbol or "" for a rest (a preset's own steps).
static func steps_of(beat: String) -> PackedStringArray:
	var text := beat
	match beat:
		"Boots and cats": text = "B . t . | Pf . t . | B . t . | Pf . t ."
		"Four on the floor": text = "B . t . | B . tss . | B . t . | B . tss ."
		"Breakbeat": text = "B . t . | Pf . t B | . B t . | Pf . t t"
		"Rimshot shuffle": text = "B . t K | . t B . | t . K t | . B K t"
		"Inward snare": text = "B . t . | ^K . t . | B B t . | ^K . t ."
		"Clicks and pops": text = "B . ! . | P! . ! . | B ! . ! | P! . ! !"
		"Hum bass": text = "B m . m:43 | Pf . m:45 . | B m:40 . m | Pf . t kch"
	var out := PackedStringArray()
	for word in text.split(" ", false):
		if word == "|":
			continue
		out.append("" if word == "." else word)
		if out.size() == STEPS:
			break
	while out.size() < STEPS:
		out.append("")
	return out


## Steps written back as a pattern, four to a bar line.
static func beat_of(steps: PackedStringArray) -> String:
	var words := PackedStringArray()
	for i in steps.size():
		if i > 0 and i % 4 == 0:
			words.append("|")
		words.append("." if steps[i] == "" else steps[i])
	return " ".join(words)


## Whether `op` is a moment (played on the host, not kept in the row).
static func is_moment(op: String) -> bool:
	return op in MOMENTS


## `op` done to the row `row` (a moment only checked); the refusal in words, or "". `tracks`: the song's track
## indices, for `track` and `part`, which step through them (and to none after the last).
static func answer(row: Dictionary, op: String, args: Array, tracks: Array = []) -> String:
	match op:
		"set":
			if args.size() != 2 or not args[0] is String and not args[0] is StringName:
				return "The singer cannot take that."
			var k := String(args[0])
			var v: Variant = args[1]
			if k in UNIT_KEYS and (v is float or v is int):
				row[k] = clampf(float(v), 0.0, 1.0)
			elif k == "mode" and (v is int or v is float):
				row[k] = clampi(int(v), 0, MODES.size() - 1)
			elif k == "sound" and (v is int or v is float):
				row[k] = clampi(int(v), 0, SOUNDS.size() - 1)
			elif k == "beast" and (v is int or v is float):
				row[k] = clampi(int(v), 0, BEASTS.size() - 1)
			elif k == "call" and (v is int or v is float):
				row[k] = clampi(int(v), 0, 3)
			elif (k == "seq" or k == "power") and v is bool:
				row[k] = v
			elif k == "beat" and v is String:
				var b := clean_beat(v)
				if b.is_empty():
					return "That is not a beat: steps like B . t . | Pf . t ."
				row[k] = b
			else:
				return "The singer has no %s." % k
			return ""
		"step":
			# A step on a slot: one of the beat's 16 steps set to a sound (or "" for a rest).
			if args.size() != 2 or not (args[0] is int or args[0] is float) or not args[1] is String:
				return "The singer cannot take that."
			var at := int(args[0])
			if at < 0 or at >= STEPS or not (String(args[1]) == "" or SOUNDS.has(String(args[1]))):
				return "There is no such step."
			var steps := steps_of(String(row["beat"]))
			steps[at] = String(args[1])
			row["beat"] = beat_of(steps)
			return ""
		"track", "part":
			var sorted := tracks.duplicate()
			sorted.sort()
			var now := int(row[op])
			if args.size() > 0 and (args[0] is int or args[0] is float) and (int(args[0]) == 0 or sorted.has(int(args[0]))):
				# named: that track, or 0 for none
				row[op] = int(args[0])
				return ""
			var at := sorted.find(now)
			row[op] = sorted[at + 1] if at + 1 < sorted.size() else (0 if now != 0 or sorted.is_empty() else sorted[0])
			return ""
		"say":
			if args.size() < 1 or not args[0] is String or String(args[0]).strip_edges().is_empty():
				return "Nothing to say."
			return ""
		"hit":
			if args.size() < 1 or not args[0] is String or not SOUNDS.has(String(args[0])):
				return "The singer has no such sound."
			return ""
		"grab":
			if args.size() != 2 or not args[0] is String or not ARTIC_GRABBED.has(String(args[0])) \
					or not (args[1] is float or args[1] is int):
				return "The singer's mouth has no such part."
			return ""
		"play":
			if args.size() != 2 or not (args[0] is int or args[0] is float) or not args[1] is bool \
					or int(args[0]) < LOWEST or int(args[0]) > HIGHEST:
				return "Not a note the singer sings."
			return ""
		"cry":
			if args.size() != 1 or not (args[0] is int or args[0] is float):
				return "The creature has no such call."
			return ""
		"strike":
			if args.size() != 1 or not (args[0] is int or args[0] is float) or int(args[0]) < 0 \
					or int(args[0]) >= Bestiary.STONES:
				return "The creature's perch has no such stone."
			return ""
	return "The singer cannot %s." % op


## The parts of the mouth a hand may take hold of (VoiceTele.ARTIC names).
const ARTIC_GRABBED := ["jaw", "tbX", "tbY", "ttX", "ttY", "lipAp", "lipProt", "velum", "larynx"]
