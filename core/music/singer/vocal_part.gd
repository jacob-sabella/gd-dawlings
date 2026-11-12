class_name VocalPart
extends RefCounted

## The song's vocal part as the singer sings it: a MIDI track's notes, in beats, one syllable of the lyrics each
## (Singer.sing_part). A gap between notes is a rest, and a rest ends a phrase: the singer breathes there, as
## CHIMERA plans a melody (a phrase a breath). Overlapping notes are sung one after another: the later one starts
## when it starts and the earlier is cut there (a voice sings one note at a time).

## The most notes sent at once (the engine plans them all; a long part is still a few seconds' planning).
const MOST := 2000
## A gap shorter than this (beats) is legato, not a rest.
const GAP := 0.05


## `notes` (each [beat, midi, beats], any order) as one line for the VOICE module's `song` words: FIRST BPM BEAT
## then MIDI BEATS pairs from the first note on, a rest as MIDI 0. "" for no notes.
static func song_line(notes: Array, bpm: float, first := 0) -> String:
	var sorted := monophonic(notes)
	if sorted.is_empty() or bpm <= 0.0:
		return ""
	var parts := PackedStringArray([str(first), "%.4f" % bpm, "%.6f" % float(sorted[0][0])])
	var at := float(sorted[0][0])
	for n: Array in sorted:
		var start := float(n[0])
		if start - at > GAP:
			parts.append("0 %.6f" % (start - at))
			at = start
		parts.append("%d %.6f" % [int(n[1]), float(n[2]) + (start - at)])
		at = start + float(n[2])
	return " ".join(parts)


## `notes` in time order, one at a time: a note that starts under an earlier one cuts that one short.
static func monophonic(notes: Array) -> Array:
	var sorted: Array = []
	for n in notes:
		if n is Array and n.size() >= 3 and float(n[2]) > 0.0 and int(n[1]) > 0:
			sorted.append([float(n[0]), int(n[1]), float(n[2])])
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var out: Array = []
	for n: Array in sorted:
		if not out.is_empty():
			var last: Array = out[-1]
			if n[0] <= last[0] + 1e-6:
				continue  # a chord: the top note is sung
			if last[0] + last[2] > n[0]:
				last[2] = n[0] - last[0]
		out.append(n)
		if out.size() >= MOST:
			break
	return out


## The syllable of the lyrics the note at `beat` sings: how many notes of `notes` start before it.
static func syllable_at(notes: Array, beat: float) -> int:
	var k := -1
	for n: Array in monophonic(notes):
		if n[0] > beat + 1e-6:
			break
		k += 1
	return k


## The notes of track `index` in `state` (MixState) as [beat, midi, beats]: every item's that is not muted, from
## its MIDI notes (ItemState.notes, seconds from the item's left edge), in the song's beats (its tempo map).
static func notes_of(state: MixState, index: int) -> Array:
	var out: Array = []
	if state == null or not state.tracks.has(index):
		return out
	var t: MixState.TrackState = state.tracks[index]
	for it: MixState.ItemState in t.items:
		if it.muted:
			continue
		var n := it.notes
		var i := 0
		while i + MidiTake.NOTE_WIDTH - 1 < n.size() and out.size() < MOST:
			var on := it.start + n[i]
			var off := it.start + n[i + 1]
			if n[i] < it.length + 1e-4:
				var b0 := state.beat_at(on)
				out.append([b0, int(n[i + 2]), maxf(state.beat_at(minf(off, it.start + it.length)) - b0, 0.01)])
			i += MidiTake.NOTE_WIDTH
	return out


## Where syllable `k` of `syllables` (as the voice split the lyrics `lrc`, Singer.words_of) is in the lyrics'
## lines: [line (an index into Lyrics.lines), first character in that line's text, characters], or [] when it
## cannot be found. A syllable is a piece of a word's spelling, found in order along the lines; a held one ("~")
## is the syllable before it again. `k` past the end wraps, as the voice's does.
static func sung_span(lrc: String, syllables: PackedStringArray, k: int) -> PackedInt32Array:
	if syllables.is_empty() or k < 0:
		return PackedInt32Array()
	return spans(lrc, syllables)[k % syllables.size()]


## Every syllable's place (`sung_span`'s shape, [] for one not found), in one pass.
static func spans(lrc: String, syllables: PackedStringArray) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var lyr := Lyrics.parse(lrc)
	var line_of := PackedInt32Array()  # per sung line: its index in lyr.lines
	var starts := PackedInt32Array()  # where it starts in `joined`
	var lead := PackedInt32Array()  # where its stripped words start in its own text
	var joined := ""
	for i: int in lyr.sequence():
		var raw := String(lyr.lines[i]["text"])
		var t := raw.strip_edges()
		if t == "":
			continue
		if joined != "":
			joined += " "
		line_of.append(i)
		starts.append(joined.length())
		lead.append(raw.find(t))
		joined += t
	var low := joined.to_lower()
	var cursor := 0
	var last := PackedInt32Array()
	for j in syllables.size():
		var s := syllables[j].strip_edges().to_lower()
		var p := low.find(s, cursor) if s != "" and s != "~" else -1
		if p >= 0:
			cursor = p + s.length()
			var n := starts.size() - 1
			while n > 0 and starts[n] > p:
				n -= 1
			last = PackedInt32Array([line_of[n], p - starts[n] + lead[n], s.length()])
		out.append(last)
	return out


## Line `line`'s text with its syllable breaks marked by a middle dot (`marks`: the syllables' places, `spans`), and
## where `lit` (a place in the plain line, or empty) falls in the marked text: [text, Vector2i(first, count)].
static func marked(text: String, line: int, marks: Array[PackedInt32Array], lit: PackedInt32Array) -> Array:
	var breaks := {}
	for m in marks:
		if m.size() == 3 and m[0] == line and m[1] > 0 and m[1] < text.length() \
				and text[m[1] - 1] != " " and text[m[1] - 1] != "-":
			breaks[m[1]] = true
	var out := ""
	var shift := PackedInt32Array()
	shift.resize(text.length() + 1)
	var added := 0
	for c in text.length():
		if breaks.has(c):
			out += "·"
			added += 1
		shift[c] = added
		out += text[c]
	shift[text.length()] = added
	var at := Vector2i(-1, 0)
	if lit.size() == 3 and lit[0] == line and lit[1] >= 0 and lit[1] + lit[2] <= text.length():
		at = Vector2i(lit[1] + shift[lit[1]], lit[2])
	return [out, at]
