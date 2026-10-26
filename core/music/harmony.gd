class_name Harmony
extends RefCounted

## The song's key and chord at a moment: what an instrument may play now.
##
## They are written in marker names, at the end, in brackets: `Intro [A minor: Am F C G]`. Inside
## is a key (a root, as RigRoll.KEY_NAMES spells it or its other spelling, and a mode from
## RigRoll.MODES; `Am` is A minor, and a root alone is major), then optionally a colon and one
## chord a bar, going round, counted from the bar the marker falls in. `-` holds the chord before
## it another bar. No chords is the key's own tonic triad all along. The harmony holds until the
## next bracketed marker; a plain section marker does not end it, and a marker that is only
## brackets changes the harmony and names no section.
##
## Markers because they are already song state: they replicate, undo, save through Reaper and
## .dawproject, and the 2D ruler edits them. So the chord now is a function of song position,
## never a stream, and every machine reading the same markers gets the same answer (`at`).
##
## A value of this class is one answer: a key and the chord sounding, from `parse` (the first
## chord of a bracket) or from `at` (the chord at a time). The static functions read names.

## Each mode's scale, in semitones from its root.
const SCALES := {
	"major": [0, 2, 4, 5, 7, 9, 11], "dorian": [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10], "lydian": [0, 2, 4, 6, 7, 9, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10], "minor": [0, 2, 3, 5, 7, 8, 10],
	"locrian": [0, 1, 3, 5, 6, 8, 10],
}
## Other names a mode goes by.
const MODE_ALIASES := {"m": "minor", "ionian": "major", "aeolian": "minor"}
## How far above its relative major each mode's root is: where its key signature comes from.
const MODE_OFFSETS := {
	"major": 0, "dorian": 2, "phrygian": 4, "lydian": 5, "mixolydian": 7, "minor": 9, "locrian": 11,
}
## RigRoll.KEY_NAMES's other spelling of each root: the five black keys named the other way.
const OTHER_NAMES := ["C", "Db", "D", "D#", "E", "F", "Gb", "G", "G#", "A", "A#", "B"]
const SHARP_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const FLAT_NAMES := ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
## Relative majors written with flats: F, Bb, Eb, Ab, Db.
const FLAT_MAJORS := [5, 10, 3, 8, 1]
## A chord's quality as written after its root, and its tones in semitones from it, root first.
const QUALITIES := {
	"": [0, 4, 7], "m": [0, 3, 7], "dim": [0, 3, 6], "aug": [0, 4, 8], "+": [0, 4, 8],
	"sus2": [0, 2, 7], "sus4": [0, 5, 7], "sus": [0, 5, 7], "5": [0, 7],
	"7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "M7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
	"dim7": [0, 3, 6, 9], "m7b5": [0, 3, 6, 10], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9],
}
## How far into a bar a time may be short of it and still be counted in it: a marker placed on a
## bar line in seconds can come back a hair before it.
const BAR_SLACK := 0.0001
## A marker at or within this of a time is at it, as TapeDeck.section_at has it.
const AT_SLACK := 0.001

## The key, as it is said: "A minor", the root as it was written.
var key_name := "C major"
## The key's root and mode, a pitch class (C is 0) and one of SCALES's names.
var root := 0
var mode := "major"
## The key's scale as pitch classes, its root first.
var scale := PackedInt32Array([0, 2, 4, 5, 7, 9, 11])
## The chord sounding, as pitch classes, its root first; and its name ("Am").
var chord := PackedInt32Array([0, 4, 7])
var chord_name := "C"
## False for NONE: no bracket has set a key, and C major is only a default to play in.
var named := false
## The bar the chord began on, counted as MixState.bar_at counts (0 is the first), and where it
## began in seconds: the marker itself, in the marker's bar.
var bar := 0
var since := 0.0
## Seconds at which the chord next changes: the next bar with another chord, or the next
## bracketed marker. INF when nothing after it changes it.
var until := INF
## Whether notes in this key are named with flats (`note_name`).
var flats := false
## The brackets' inside as written ("A minor: Am F C G"), "" for NONE.
var text := ""
## The chords a bar, as written: [name, pitch classes] each, ["-", []] for a held bar. Empty when
## the bracket names only a key.
var progression: Array = []

## No key set: C major on C, `named` false. Before the first bracket and in a project with none.
## Shared, so never written to.
static var NONE := Harmony.new()


## The harmony a marker's name sets, with its first chord; or null when it has no brackets, or
## brackets that do not read as a key and chords.
static func parse(marker_name: String) -> Harmony:
	var open := _bracket_open(marker_name)
	if open < 0:
		return null
	var inside := marker_name.strip_edges()
	inside = inside.substr(open + 1, inside.length() - open - 2).strip_edges()
	var colon := inside.find(":")
	var key_part := inside if colon < 0 else inside.left(colon)
	var chords_part := "" if colon < 0 else inside.substr(colon + 1)
	var h := _key(key_part.strip_edges())
	if h == null:
		return null
	h.text = inside
	for word in chords_part.replace("|", " ").split(" ", false):
		if word == "-":
			if h.progression.is_empty():
				# Nothing before it to hold.
				return null
			h.progression.append(["-", PackedInt32Array()])
			continue
		var pcs := _chord(word)
		if pcs.is_empty():
			return null
		h.progression.append([word, pcs])
	if not h.progression.is_empty():
		h.chord_name = h.progression[0][0]
		h.chord = h.progression[0][1]
	return h


## A marker's name without its brackets: the section it names, "" for a marker that is only
## brackets. Brackets that do not read as a key are left in, so a mistyped one is seen where the
## section is shown, not quietly dropped.
static func section_of(marker_name: String) -> String:
	var open := _bracket_open(marker_name)
	if open < 0:
		return marker_name
	return marker_name.strip_edges().left(open).strip_edges()


## The harmony at `seconds` into the song: the latest bracketed marker at or before it, and its
## chord for the bar `seconds` is in, counted with MixState.bar_at so that tempo and meter
## changes are right. NONE (or a copy of it whose `until` is the first bracket) before any.
static func at(state: MixState, seconds: float) -> Harmony:
	if state == null:
		return NONE
	var times: Array = state.markers.keys()
	times.sort()
	var found: Harmony = null
	var from := 0.0
	var next_bracket := INF
	for t in times:
		var h := parse(str(state.markers[t]))
		if h == null:
			continue
		if float(t) <= seconds + AT_SLACK:
			found = h
			from = float(t)
		else:
			next_bracket = float(t)
			break
	if found == null:
		if next_bracket == INF:
			return NONE
		var none := Harmony.new()
		none.until = next_bracket
		return none
	var first := floori(state.bar_at(from) + BAR_SLACK)
	found.bar = first
	found.since = from
	found.until = next_bracket
	var n := found.progression.size()
	if n == 0:
		return found
	var now := maxi(floori(state.bar_at(seconds) + BAR_SLACK), first)
	var here: Array = found._entry(first, now)
	found.chord_name = here[0]
	found.chord = here[1]
	# Back to the bar this chord came in on, and on to the one where another comes. Within one
	# round of the progression, or it never changes.
	var began := now
	while began > first and now - began < n and found._entry(first, began - 1)[0] == here[0]:
		began -= 1
	if now - began >= n:
		began = first
	found.bar = began
	found.since = from if began == first else state.bar_to_seconds(began + 1.0)
	var ahead := 1
	while ahead <= n and found._entry(first, now + ahead)[0] == here[0]:
		ahead += 1
	if ahead <= n:
		found.until = minf(next_bracket, state.bar_to_seconds(now + ahead + 1.0))
	return found


## The chord of bar `b` of a progression that starts at bar `first`, a held bar taking the one
## before it: [name, pitch classes].
func _entry(first: int, b: int) -> Array:
	var i := (b - first) % progression.size()
	# The first entry is never "-" (parse refuses it), so this stops.
	while progression[i][0] == "-":
		i -= 1
	return progression[i]


## The nearest pitch in the key's scale to `pitch`, the lower of two as near.
func snap(pitch: int) -> int:
	for d in 7:
		if scale.has(posmod(pitch - d, 12)):
			return pitch - d
		if scale.has(posmod(pitch + d, 12)):
			return pitch + d
	return pitch


## The chord's tones from `from_pitch` up, the first `count` of them at or above it.
func tones(from_pitch: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if chord.is_empty():
		return out
	var p := from_pitch
	while out.size() < count:
		if chord.has(posmod(p, 12)):
			out.append(p)
		p += 1
	return out


## The chord voiced around `centre`: its root at the one pitch of its class in `centre - 6 ..
## centre + 5`, and the other tones on up from it in chord order (third, fifth, then the seventh
## in a four-note chord, else the octave) until there are `count`. A voicing that jumps with the
## root keeps each note's job the same in every chord: bells at 72 ring A4 C5 E5 A5 in Am and
## F5 A5 C6 F6 in F.
static func voiced(h: Harmony, centre: int, count: int) -> PackedInt32Array:
	var r := h.chord[0] if not h.chord.is_empty() else h.root
	var lowest := centre - 6
	return h.tones(lowest + posmod(r - lowest, 12), count)


## The key's seven chords, the triads on its scale, in fifths order: from the one whose root has
## no fifth below it in the scale, on up by fifths. C major (and A minor) is F C G Dm Am Em Bdim,
## the run a fifths wheel shows round its rim. Spelled as the key is (`note_name`).
static func diatonic(key: Harmony) -> PackedStringArray:
	var out := PackedStringArray()
	var start := 0
	for i in key.scale.size():
		if not key.scale.has(posmod(key.scale[i] - 7, 12)):
			start = i
	var pc := key.scale[start]
	for k in key.scale.size():
		out.append(key._triad_name(pc))
		pc = (pc + 7) % 12
	return out


## The chords that lead well on from `chord` in `key`, in this order: its fifth down (the key's
## chord on the root a fifth below, or a major triad there when that root is out of the key), the
## key's IV (the triad on its fourth degree), the key's vi (on its sixth), and the V of the next:
## a major triad on the chord's own root, which leads into the chord a fifth down. The chord
## itself, and a chord said twice, are left out. In C major, after Am: Dm F A. Empty for a chord
## that does not read.
static func follows(key: Harmony, chord: String) -> PackedStringArray:
	var out := PackedStringArray()
	var tones := _chord(chord)
	if tones.is_empty():
		return out
	var seen: Array = [tones]
	var next := (tones[0] + 5) % 12
	var named := [key._triad_name(next) if key.scale.has(next) else key.note_name(next, false),
			key._triad_name(key.scale[3]), key._triad_name(key.scale[5]), key.note_name(tones[0], false)]
	for said: String in named:
		var pcs := _chord(said)
		if pcs.is_empty() or seen.has(pcs):
			continue
		seen.append(pcs)
		out.append(said)
	return out


## What `chord` is in this key, as a numeral: `IV`, `vi`, `vii°`; "" when it is not one of the
## key's triads.
func numeral(chord: String) -> String:
	var tones := _chord(chord)
	if tones.size() != 3:
		return ""
	var d := scale.find(tones[0])
	if d < 0 or _chord(_triad_name(tones[0])) != tones:
		return ""
	var said: String = ["I", "II", "III", "IV", "V", "VI", "VII"][d]
	var third := posmod(tones[1] - tones[0], 12)
	var fifth := posmod(tones[2] - tones[0], 12)
	if fifth == 6:
		return said.to_lower() + "°"
	if fifth == 8:
		return said + "+"
	return said.to_lower() if third == 3 else said


## A chord's pitch classes from its name ("Am", "Bb7"), root first, or empty when it does not
## read.
static func chord_tones(chord: String) -> PackedInt32Array:
	return _chord(chord)


## A marker's name with `harmony`'s brackets set on it: its section (`section_of`, so old brackets
## go) and then `[key: chords]`, or the brackets alone for a marker with no section (`""`). Kept
## within DAW.MARKER_NAME_MAX by dropping chords off the end, whole ones, and only when the key
## alone does not fit, by shortening the section.
static func written(marker_name: String, harmony: Harmony) -> String:
	var most: int = DAW.MARKER_NAME_MAX
	var section := section_of(marker_name)
	var colon := harmony.text.find(":")
	var key_part := (harmony.text if colon < 0 else harmony.text.left(colon)).strip_edges()
	var words: Array = harmony.progression.map(func(entry: Array) -> String: return entry[0])
	var said := _brackets(section, key_part, words)
	while said.length() > most and not words.is_empty():
		words.pop_back()
		said = _brackets(section, key_part, words)
	if said.length() > most:
		var room := most - _brackets("", key_part, []).length() - 1
		section = section.left(maxi(room, 0)).strip_edges()
		said = _brackets(section, key_part, [])
	return said


static func _brackets(section: String, key_part: String, words: Array) -> String:
	var inside := key_part if words.is_empty() else "%s: %s" % [key_part, " ".join(PackedStringArray(words))]
	return "[%s]" % inside if section == "" else "%s [%s]" % [section, inside]


## The triad on `pc`, a pitch class in the scale, built of the scale's own tones: its name, as
## the key spells it.
func _triad_name(pc: int) -> String:
	var d := scale.find(pc)
	if d < 0:
		return note_name(pc, false)
	var third := posmod(scale[(d + 2) % scale.size()] - pc, 12)
	var fifth := posmod(scale[(d + 4) % scale.size()] - pc, 12)
	var quality := "dim" if fifth == 6 else ("aug" if fifth == 8 else ("m" if third == 3 else ""))
	return note_name(pc, false) + quality


## A MIDI pitch's name, sharp or flat as the key is written, with its octave (60 is C4).
func note_name(pitch: int, octave := true) -> String:
	var said: String = (FLAT_NAMES if flats else SHARP_NAMES)[posmod(pitch, 12)]
	return "%s%d" % [said, floori(pitch / 12.0) - 1] if octave else said


## Where the brackets at the end of a name open, in the name stripped, when they read as a key;
## else -1.
static func _bracket_open(marker_name: String) -> int:
	var said := marker_name.strip_edges()
	if not said.ends_with("]"):
		return -1
	var open := said.rfind("[")
	if open < 0:
		return -1
	var inside := said.substr(open + 1, said.length() - open - 2)
	if inside.contains("]"):
		return -1
	var colon := inside.find(":")
	if _key((inside if colon < 0 else inside.left(colon)).strip_edges()) == null:
		return -1
	return open


## A root's pitch class from its name, in either spelling, or -1.
static func _root(said: String) -> int:
	var i: int = RigRoll.KEY_NAMES.find(said)
	return i if i >= 0 else OTHER_NAMES.find(said)


## A key from what it is written as ("A minor", "Am", "Eb", "F# dorian"), or null.
static func _key(said: String) -> Harmony:
	var words := said.split(" ", false)
	if words.is_empty() or words.size() > 2:
		return null
	var first: String = words[0]
	var spelled := first.left(2) if first.length() >= 2 and first[1] in ["#", "b"] else first.left(1)
	var root_pc := _root(spelled)
	if root_pc < 0:
		return null
	var mode_said := first.substr(spelled.length())
	if words.size() == 2:
		if mode_said != "":
			return null
		mode_said = words[1].to_lower()
	var mode_name: String = MODE_ALIASES.get(mode_said, mode_said)
	if mode_said == "":
		mode_name = "major"
	if not SCALES.has(mode_name):
		return null
	var h := Harmony.new()
	h.named = true
	h.root = root_pc
	h.mode = mode_name
	h.key_name = "%s %s" % [spelled, mode_name]
	h.scale = PackedInt32Array()
	for step in SCALES[mode_name]:
		h.scale.append((root_pc + int(step)) % 12)
	if spelled.ends_with("b"):
		h.flats = true
	elif not spelled.ends_with("#"):
		h.flats = FLAT_MAJORS.has(posmod(root_pc - int(MODE_OFFSETS[mode_name]), 12))
	# No chords written: the key's own tonic triad, on its first, third and fifth.
	h.chord = PackedInt32Array([h.scale[0], h.scale[2], h.scale[4]])
	var third := posmod(h.scale[2] - root_pc, 12)
	var fifth := posmod(h.scale[4] - root_pc, 12)
	h.chord_name = spelled + ("dim" if fifth == 6 else ("m" if third == 3 else ""))
	return h


## A chord's pitch classes from its name ("Am", "Bb7", "F#m7b5"), root first, or empty.
static func _chord(said: String) -> PackedInt32Array:
	var spelled := said.left(2) if said.length() >= 2 and said[1] in ["#", "b"] else said.left(1)
	var root_pc := _root(spelled)
	var quality := said.substr(spelled.length())
	if root_pc < 0 or not QUALITIES.has(quality):
		return PackedInt32Array()
	var out := PackedInt32Array()
	for step in QUALITIES[quality]:
		out.append((root_pc + int(step)) % 12)
	return out
