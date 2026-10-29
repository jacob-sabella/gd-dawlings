class_name Lyrics
extends RefCounted

## The song's words, as LRC (docs/spatial_loop.md part two, slice 56): `[01:23.40]a line` is a line
## sung from 1:23.40, a line with no time in front of it is one not yet timed, and `[ar:...]`,
## `[ti:...]` and `[offset:...]` on lines of their own are the file's tags. The text is the song's own
## (MixState.lyrics, written by DAW.set_lyrics): Reaper keeps it in its project notes inside a
## `[lyrics]` block (`from_notes`, `into_notes`), and .dawproject in its metadata's comment.
##
## This parses that text, writes it back and answers which line is being sung at a time. Lines keep
## the order they were written in, so a verse pasted in and tapped through stays a verse; a blank line
## between verses is kept as a break (one, however many there were), and is never sung or tapped.
## Which line is sung is the latest timed one at or before the time; the order they are sung in
## (`sequence`) is the timed ones by their times, then the untimed ones in the order written, so the
## line TAP stamps next (`next_untimed`) always comes after the last one timed.
##
## `[offset:+250]` (milliseconds) shows every line that much sooner, as LRC players do. The lines
## keep the times written on them; `shown` is a line's time with the offset taken off, and a TAP
## writes the time that shows at the moment heard.

## The most text the song's lyrics may be, and one line of it: what a guest's intent may carry.
const MOST := 20000
const LINE_MOST := 200
## A line not yet timed.
const UNTIMED := -1.0
## The block in Reaper's project notes the lyrics live in, each marker on a line of its own.
const BLOCK_OPEN := "[lyrics]"
const BLOCK_CLOSE := "[/lyrics]"

## {"t": seconds as written, or UNTIMED; "text": the words}, in the order written. A break between
## verses is an untimed line with no words.
var lines: Array = []
## The tags as written ("[ar:Someone]"), in order: written back first.
var tags: PackedStringArray = []
## The `[offset:]` tag's, in seconds: + shows the lines sooner.
var offset := 0.0

## What `sequence` and the counts answer, worked out once (`_index`) and kept until a line changes
## (tap, add, untime): the board asks them every frame, and a song may have a thousand lines. Code
## that changes `lines` or `offset` itself calls `changed`.
var _indexed := false
## The timed lines by when they show, then the untimed ones as written: `sequence`.
var _order: Array = []
## How many of `_order` are timed (they come first).
var _timed := 0
## Each line's place in `_order`, by its index; -1 for a break.
var _place := PackedInt32Array()
var _next_untimed := -1


## `text` read as LRC. Anything unreadable is kept as words: a line beginning `[Chorus]` is a line
## of words, not a tag.
static func parse(text: String) -> Lyrics:
	var out := Lyrics.new()
	var broken := false
	for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			broken = true
			continue
		var times: Array = []
		var tag := ""
		var rest := line
		while rest.begins_with("["):
			var close := rest.find("]")
			if close < 0:
				break
			var inside := rest.substr(1, close - 1)
			var t := time_of(inside)
			if not is_nan(t):
				times.append(t)
				rest = rest.substr(close + 1)
				continue
			if times.is_empty() and _is_tag(inside) and rest.substr(close + 1).strip_edges().is_empty():
				tag = inside
				rest = ""
			break
		if not tag.is_empty():
			out.tags.append("[%s]" % tag)
			var key := tag.get_slice(":", 0).strip_edges().to_lower()
			if key == "offset":
				var ms := tag.substr(tag.find(":") + 1).strip_edges()
				if ms.is_valid_float():
					out.offset = float(ms) / 1000.0
			continue
		if broken and not out.lines.is_empty():
			out.lines.append({"t": UNTIMED, "text": ""})
		broken = false
		var words := rest.strip_edges().left(LINE_MOST)
		if times.is_empty():
			out.lines.append({"t": UNTIMED, "text": words})
		for t in times:
			out.lines.append({"t": t, "text": words})
	return out


## The lines or the offset were changed by hand: what was worked out from them is worked out again
## when next asked.
func changed() -> void:
	_indexed = false


func _index() -> void:
	if _indexed:
		return
	_indexed = true
	var timed: Array = []
	var untimed: Array = []
	_next_untimed = -1
	for i in lines.size():
		if float(lines[i]["t"]) >= 0.0:
			timed.append(i)
		elif not str(lines[i]["text"]).is_empty():
			untimed.append(i)
			if _next_untimed < 0:
				_next_untimed = i
	var when := PackedFloat64Array()
	when.resize(lines.size())
	for i in lines.size():
		when[i] = shown(i)
	timed.sort_custom(func(a: int, b: int) -> bool:
		return when[a] < when[b] or (when[a] == when[b] and a < b))
	_timed = timed.size()
	_order = timed + untimed
	_place.resize(lines.size())
	_place.fill(-1)
	for k in _order.size():
		_place[_order[k]] = k


## The lyrics as LRC: the tags, then every line in the order written, a timed one with its time in
## front (`stamp`), breaks as blank lines.
func write() -> String:
	var out := PackedStringArray()
	for tag in tags:
		out.append(tag)
	for line: Dictionary in lines:
		var t := float(line["t"])
		out.append((stamp(t) if t >= 0.0 else "") + str(line["text"]))
	return "\n".join(out).strip_edges()


## A time as LRC writes it, to the hundredth: `[01:23.40]`.
static func stamp(seconds: float) -> String:
	var cs := maxi(roundi(seconds * 100.0), 0)
	return "[%02d:%02d.%02d]" % [cs / 6000, (cs / 100) % 60, cs % 100]


## The seconds in a time tag's inside (`01:23.40`, `1:23`, `01:23.4`, `01:23:40`), or NAN when it is
## not one.
static func time_of(inside: String) -> float:
	var parts := inside.strip_edges().split(":")
	if parts.size() < 2 or parts.size() > 3 or not parts[0].is_valid_int():
		return NAN
	var minutes := int(parts[0])
	var sec := parts[1]
	var frac := ""
	if parts.size() == 3:
		frac = parts[2]
	elif sec.contains("."):
		frac = sec.get_slice(".", 1)
		sec = sec.get_slice(".", 0)
	if not sec.is_valid_int() or sec.length() > 2 or int(sec) >= 60 or minutes < 0 \
			or (not frac.is_empty() and (not frac.is_valid_int() or frac.length() > 3 or frac.begins_with("-"))):
		return NAN
	var seconds := minutes * 60.0 + int(sec)
	if not frac.is_empty():
		seconds += int(frac) / pow(10.0, frac.length())
	return seconds


static func _is_tag(inside: String) -> bool:
	var colon := inside.find(":")
	if colon < 1:
		return false
	var key := inside.substr(0, colon)
	for i in key.length():
		var c := key.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 65 and c <= 90) or c == 35):
			return false
	return true


## Line `i`'s time with the offset taken off: when it shows. UNTIMED for one not timed.
func shown(i: int) -> float:
	var t := float(lines[i]["t"])
	return t - offset if t >= 0.0 else UNTIMED


## The line sung at `seconds`: the latest timed one shown at or before it (the later written of two
## at one time), or -1 before the first.
func at(seconds: float) -> int:
	_index()
	# The timed lines lead `_order` by when they show, the later written last of two at one time, so
	# the one sung is the last of them shown by `seconds`.
	var lo := 0
	var hi := _timed
	while lo < hi:
		var mid := (lo + hi) / 2
		if shown(_order[mid]) > seconds + 0.000001:
			hi = mid
		else:
			lo = mid + 1
	return _order[lo - 1] if lo > 0 else -1


## Line `i`'s place in `sequence`, or -1 for a break or a line there is not.
func place(i: int) -> int:
	_index()
	return _place[i] if i >= 0 and i < _place.size() else -1


## The lines in the order they are sung: the timed ones by when they show (the order written between
## two at one time), then the untimed ones as written. Breaks are not in it. The array is the one
## kept (`_order`): read it, never change it.
func sequence() -> Array:
	_index()
	return _order


## The first line written that has words and no time: the one TAP stamps. -1 when every line is timed.
func next_untimed() -> int:
	_index()
	return _next_untimed


## How many lines have words and no time yet.
func untimed_count() -> int:
	_index()
	return _order.size() - _timed


## TAP: the next untimed line stamped to show at `seconds` (to the hundredth). Its index, or -1 when
## there is none to time.
func tap(seconds: float) -> int:
	var i := next_untimed()
	if i < 0:
		return -1
	lines[i]["t"] = maxf(snappedf(maxf(seconds, 0.0) + offset, 0.01), 0.0)
	changed()
	return i


## A line of words added at the end, untimed: TAP times it in its turn.
func add(words: String) -> void:
	var said := words.replace("\n", " ").strip_edges().left(LINE_MOST)
	if not said.is_empty():
		lines.append({"t": UNTIMED, "text": said})
		changed()


## Every line's time taken off, so the song can be tapped through again.
func untime() -> void:
	for line: Dictionary in lines:
		line["t"] = UNTIMED
	changed()


## Whether there are any words at all.
func is_empty() -> bool:
	return sequence().is_empty()


## How far through line `i` the song is at `seconds`, 0 to 1, against when the next one in `sequence`
## shows; NAN when nothing timed follows it (the next is yet to be tapped, or it is the last).
func through(i: int, seconds: float) -> float:
	var order := sequence()
	var k := place(i)
	if k < 0 or k + 1 >= order.size() or float(lines[order[k + 1]]["t"]) < 0.0:
		return NAN
	var from := shown(i)
	var to := shown(order[k + 1])
	if to - from < 0.001:
		return 1.0
	return clampf((seconds - from) / (to - from), 0.0, 1.0)


## `text` as the song may keep it: newlines made plain, the notes block's own markers taken out (a
## line saying `[/lyrics]` would end the block Reaper keeps them in), each line and the whole kept
## to LINE_MOST and MOST, and the ends trimmed.
static func clean(text: String) -> String:
	var out := PackedStringArray()
	for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var lower := raw.strip_edges().to_lower()
		if lower == BLOCK_OPEN or lower == BLOCK_CLOSE:
			continue
		out.append(raw.strip_edges(false, true).left(LINE_MOST + 24))
	return "\n".join(out).strip_edges().left(MOST)


## The lyrics kept in a project's notes: what is between a line saying BLOCK_OPEN and the next
## saying BLOCK_CLOSE (or the end), trimmed; empty where there is no block.
static func from_notes(notes: String) -> String:
	var rows := notes.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var inside := PackedStringArray()
	var open := false
	for row in rows:
		var lower := row.strip_edges().to_lower()
		if not open:
			open = lower == BLOCK_OPEN
			continue
		if lower == BLOCK_CLOSE:
			break
		inside.append(row)
	return "\n".join(inside).strip_edges() if open else ""


## `notes` with its lyrics block made `lrc`: the old block taken out, wherever it was, and the new one
## put at the end after a blank line; nothing of it when `lrc` is empty. Everything else in the notes
## is left as it was. The bridge's SetLyrics does the same in Reaper.
static func into_notes(notes: String, lrc: String) -> String:
	var rows := notes.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var kept := PackedStringArray()
	var open := false
	for row in rows:
		var lower := row.strip_edges().to_lower()
		if open:
			open = lower != BLOCK_CLOSE
			continue
		if lower == BLOCK_OPEN:
			open = true
			continue
		kept.append(row)
	var rest := "\n".join(kept).strip_edges()
	var words := clean(lrc)
	if words.is_empty():
		return rest
	var block := "%s\n%s\n%s" % [BLOCK_OPEN, words, BLOCK_CLOSE]
	return block if rest.is_empty() else "%s\n\n%s" % [rest, block]
