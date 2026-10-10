class_name LaneEngine
extends Node

## The built-in engine's sound, through dawkit's native lanes (DawKitTransport, DawKitLane):
## every track's items played sample for sample against one song clock, rather than by players
## started and steered a frame at a time.
##
## Each track has one lane, played by every player the track has -- its own on its bus, one per
## send into the send's bus, one per cue -- each player a playback of the same lane on the same
## clock, so the bus's fader, pan, effects and sends work on it as before; the click has one on
## the master. Every frame the lanes are given
## their clips -- what each item sounds like, where, from where in its sound, at what gain, with
## what fades -- when anything about them changed, and the transport is told where the song is
## when play is pressed or the playhead moved. The playhead is then the transport's: where the
## lanes have mixed the song to. See dawkit's README, "The native core".
##
## Where items overlap, the newest is heard, as before: each item is cut where a later one lies
## over it, so a take recorded over the song replaces it there.

const MIX_SECONDS_AHEAD := 0.0

var backend: GodotBackend
## DawKitTransport. Untyped: the class is the extension's, absent where it is not built.
var transport: Object = null
## Track index -> DawKitLane (untyped, as the transport).
var _lanes := {}
## [DawKitLane, its player on the master].
var _click: Array = []
## What each lane was last given, to give it again only when it changed.
var _given := {}
## Sound keys -> the ids lanes know them by.
var _ids := {}
var _next_id := 1
## The playhead as last said, so a move by anyone else is seen as one.
var _said := NAN


## Whether dawkit's native core is here: built for this platform and loaded.
static func available() -> bool:
	return ClassDB.class_exists(&"DawKitLane") and ClassDB.class_exists(&"DawKitTransport")


## Lanes for every track bus, and the click's on the master. Again after the buses are rebuilt.
func build() -> void:
	clear()
	transport = ClassDB.instantiate(&"DawKitTransport")
	transport.set_rate(int(AudioServer.get_mix_rate()))
	for index in backend._bus:
		_lanes[index] = _lane(true)
	var click := AudioStreamPlayer.new()
	click.name = "ClickLane"
	click.bus = GodotBackend.MASTER_BUS
	add_child(click)
	_click = [_lane(false), click]
	_said = NAN


func _lane(held: bool) -> Object:
	var lane = ClassDB.instantiate(&"DawKitLane")
	lane.set_transport(transport)
	lane.set_held(held)
	return lane


## Every player a track has plays its lane, from the moment it exists: a send or a cue added
## later is one more playback of it, on the same clock.
func _keep_playing(player: AudioStreamPlayer, lane: Object) -> void:
	if player.stream != lane:
		player.stream = lane
		player.volume_db = 0.0
	if not player.playing:
		player.play()


func clear() -> void:
	for index in backend._players:
		for p in backend._players[index]:
			(p as AudioStreamPlayer).stop()
			(p as AudioStreamPlayer).stream = null
	if not _click.is_empty():
		(_click[1] as AudioStreamPlayer).queue_free()
	_lanes.clear()
	_click = []
	_given.clear()
	if transport != null:
		transport.stop()


## Every frame, from GodotBackend._drive_meters: the transport kept where the song is, the playhead
## moved on by it, and each lane given its clips if they changed.
func drive(delta: float) -> void:
	var s := backend.state
	transport.set_loop(s.loop_start, s.loop_end, s.looping and s.has_loop_range())
	# Nothing but the click before a count-in's end, as in Reaper; the song too with pre-roll.
	transport.set_hold(s.count_in_to if s.count_in_to >= 0.0 and s.playing and not s.pre_roll else -1.0)
	var headless := AudioServer.get_driver_name() == "Dummy"
	if s.playing:
		if not transport.is_playing() or s.position_seconds != _said:
			# Play pressed, or the playhead moved: the song from here, from the next block mixed.
			transport.play_from(s.position_seconds, MIX_SECONDS_AHEAD)
		elif headless:
			# The dummy driver mixes in lumps too coarse to read a playhead from.
			s.position_seconds += delta
		else:
			s.position_seconds = _follow(transport.song_seconds() + minf(AudioServer.get_time_since_last_mix(),
					AudioServer.get_output_latency()), delta)
			if s.looping and s.has_loop_range() and s.position_seconds >= s.loop_end:
				s.position_seconds = s.loop_start + fmod(s.position_seconds - s.loop_end, s.loop_end - s.loop_start)
		_said = s.position_seconds
	else:
		if transport.is_playing():
			transport.stop()
		_said = NAN
	for index in _lanes:
		for p in backend._players.get(index, []):
			_keep_playing(p, _lanes[index])
		_give(_lanes[index], index, clips_for(index))
	_keep_playing(_click[1], _click[0])
	_give(_click[0], 0, click_clips())


## The playhead from the transport's reading: on by the frame's time and eased toward the reading,
## never back. The reading moves in blocks and is read between them, so it wobbles by a fraction
## of a block either way; a playhead that went back with it would take a punch's edge twice.
## A real jump (the loop going round, a seek) is followed at once.
const SNAP_SECONDS := 0.05
const EASE := 0.1


func _follow(reading: float, delta: float) -> float:
	var next := _said + delta
	var off := reading - next
	if absf(off) > SNAP_SECONDS:
		return reading
	return maxf(next + off * EASE, _said)


func _give(lane: Object, key: int, clips: Array) -> void:
	# Compared without the sounds themselves: their ids say which they are.
	var plain := clips.map(func(c: Dictionary) -> Dictionary:
		var d := c.duplicate()
		d.erase("wav")
		return d)
	if _given.get(key) == plain:
		return
	_given[key] = plain
	lane.set_clips(clips)


func _id_of(key: String) -> int:
	if not _ids.has(key):
		_ids[key] = _next_id
		_next_id += 1
	return _ids[key]


## The clips a track's lane plays now: each item that is not muted, cut where a newer one lies over
## it, as what it sounds like. A sound still being made (a MIDI render, a window of a demo part)
## is left out until it is there.
func clips_for(index: int) -> Array:
	var s := backend.state
	var t: MixState.TrackState = s.tracks.get(index)
	if t == null:
		return []
	var out: Array = []
	var items: Array = t.items
	for n in items.size():
		var it := items[n] as MixState.ItemState
		if it.muted or it.length <= 0.0:
			continue
		var later: Array = []
		for m in range(n + 1, items.size()):
			var o := items[m] as MixState.ItemState
			if not o.muted:
				later.append([o.start, o.end()])
		for seg in visible(it.start, it.end(), later):
			out.append_array(_item_clips(t, it, seg[0], seg[1]))
	return out


## What is left of [a, b) once every span in `covers` is taken out of it, in order.
static func visible(a: float, b: float, covers: Array) -> Array:
	var spans: Array = [[a, b]]
	for c in covers:
		var next: Array = []
		for sp in spans:
			if c[1] <= sp[0] or c[0] >= sp[1]:
				next.append(sp)
				continue
			if c[0] > sp[0]:
				next.append([sp[0], c[0]])
			if c[1] < sp[1]:
				next.append([c[1], sp[1]])
		spans = next
	return spans.filter(func(sp): return sp[1] - sp[0] > 0.000001)


func _item_clips(t: MixState.TrackState, it: MixState.ItemState, a: float, b: float) -> Array:
	var base := {"gain": db_to_linear(it.gain_db),
			"fade_in": it.fade_in if is_equal_approx(a, it.start) else 0.0,
			"fade_out": it.fade_out if is_equal_approx(b, it.end()) else 0.0}
	if not it.source.is_empty():
		var wav := backend.take_stream(it.source)
		if wav == null:
			return []
		var c := _clip(base, "take:" + it.source, wav, a, b, it.source_offset + a - it.start)
		if it.is_looped():
			c["loop_start"] = it.loop_start
			c["loop_end"] = it.loop_end
		return [c]
	if not it.notes.is_empty():
		var midi := backend.midi_stream(it)
		if midi == null:
			return []
		return [_clip(base, "midi:" + GodotBackend.midi_key(it), midi, a, b, a - it.start)]
	if t.part == "":
		return []
	var s := backend.state
	if not backend.parts_windowed():
		# On the song's bar grid, not the item's start: a split or a move keeps the music on the beat.
		# One signature throughout, so the loop is BARS of its bars.
		var part: AudioStreamWAV = backend._parts.get(t.part)
		if part == null:
			return []
		var length := part.get_length()
		var c := _clip(base, "part:%s@%s" % [t.part, backend._parts_key], part, a, b, fposmod(a, length))
		c["loop_start"] = 0.0
		c["loop_end"] = length
		return [c]
	# Through the tempo's and signature's changes, a window of the part at a time: the one the
	# playhead is in and the next, as they are rendered.
	var map := s.tempo_map()
	var meter := s.meter()
	var here := floori(meter.bar_at(map.beat_at(clampf(s.position_seconds, a, b))) / DemoSong.BARS)
	var out: Array = []
	for loop in [here, here + 1]:
		var from := maxf(a, map.seconds_at(meter.beat_of_bar(loop * DemoSong.BARS)))
		var to := minf(b, map.seconds_at(meter.beat_of_bar((loop + 1) * DemoSong.BARS)))
		if to <= from:
			continue
		var window := backend._part_window(t.part, from)
		if window.is_empty():
			continue
		out.append(_clip(base, "win:" + backend.window_key(t.part, loop), window[0], from, to,
				from - float(window[1])))
	return out


func _clip(base: Dictionary, key: String, wav: AudioStreamWAV, a: float, b: float, offset: float) -> Dictionary:
	var c := base.duplicate()
	c["id"] = _id_of(key)
	c["wav"] = wav
	c["start"] = a
	c["length"] = b - a
	c["offset"] = offset
	return c


## The click's clips: none with the metronome off; one bar going round from before the song's
## start with one tempo and signature, else the window of the song's own clicks the playhead is in.
func click_clips() -> Array:
	var s := backend.state
	if not s.metronome:
		return []
	var rate := int(AudioServer.get_mix_rate())
	if not backend._click_windowed():
		var key := "click:%s/%d" % [s.tempo, s.beats_per_bar]
		var bar: AudioStreamWAV = backend.lane_click_bar(key, rate)
		var length := bar.get_length()
		# From far enough before the song's top for the longest count-in to land on it.
		var from := -length * float(MixState.COUNT_IN_MAX + 1)
		return [{"id": _id_of(key), "wav": bar, "start": from, "length": maxf(s.timeline_length(), 1.0) - from + 3600.0,
				"offset": fposmod(from, length), "loop_start": 0.0, "loop_end": length}]
	backend._click_window_for(s.position_seconds)
	# The window is the click player's stream, which with lanes is never played: it holds it.
	var wav: AudioStreamWAV = backend._click.stream if backend._click != null else null
	if wav == null:
		return []
	var key := "clickwin:%s@%s" % [backend._click_for, backend._click_from]
	return [{"id": _id_of(key), "wav": wav, "start": backend._click_from, "length": wav.get_length(), "offset": 0.0}]
