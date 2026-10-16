class_name MixWire
extends RefCounted

## The project's internal vocabulary for a mix, as flat [key, args] pairs.
##
## It is shaped like Reaper's OSC address space because that is where it came from, and it was
## kept that way on purpose: Reaper's addresses are already a complete, positional, battle-worn
## naming of everything a mixer has, and inventing a second one would have meant translating
## twice on the path that matters most.
##
## It is used for two things that look different and are not:
##
##   PARSING     a backend receiving `/track/3/volume 0.7` hands it here and the cache updates.
##   REPLICATION the same pairs are what a session host sends its guests, and `snapshot()` is
##               the same vocabulary again. A receiver therefore has exactly one code path for
##               "state arrived", and a field added to the parser is replicated the day it is
##               parsed rather than the day someone remembers to add it to a serialiser.
##
## A backend for a DAW whose protocol looks nothing like this has two honest options: translate
## into these keys, or write into MixState directly and leave replication to the base class.
## What it must not do is leak its own vocabulary upward -- see core/daw/daw_backend.gd.

## Reaper's taper (FaderLaw). Static because parsing is a pure function of the message and
## must not need a backend to exist.
static func _taper_to_db(taper: float) -> float:
	return FaderLaw.to_db(taper)


## Route one OSC message into the state cache.
##
## Reaper's addresses are positional (`/track/3/fx/2/fxparam/5/value`), so this splits rather
## than pattern-matches. Unknown addresses are dropped in silence by design: the pattern file
## streams far more than this project draws yet, and logging each one would print thousands of
## lines a second.
static func apply(state: MixState, address: String, args: Array) -> void:
	var p := address.trim_prefix("/").split("/")
	if p.is_empty():
		return

	match p[0]:
		"track":
			_apply_track(state, p, args)
		"master":
			_apply_master(state, p, args)
		"vca":
			# dawlings's own: a group's trim in dB, `/vca/N`.
			if p.size() == 2 and not args.is_empty() and typeof(args[0]) in [TYPE_INT, TYPE_FLOAT] \
					and is_finite(float(args[0])) and p[1].is_valid_int():
				state.set_vca_db(int(p[1]), clampf(float(args[0]), -60.0, 12.0))
		"play":
			state.playing = _as_bool(args)
			state.transport_changed.emit()
		"stop":
			if _as_bool(args):
				state.playing = false
				state.transport_changed.emit()
		"record":
			state.recording = _as_bool(args)
			state.transport_changed.emit()
		"time":
			if p.size() == 1 and args.size() > 0:
				state.position_seconds = float(args[0])
				state.transport_changed.emit()
			elif p.size() > 1 and p[1] == "str" and args.size() > 0:
				state.time_string = str(args[0])
				state.transport_changed.emit()
		"beat":
			# Reaper's own bar/beat string, which knows about tempo changes and time
			# signatures. Preferred over working it out from seconds whenever it is sent.
			if p.size() > 1 and p[1] == "str" and args.size() > 0:
				state.position_string = str(args[0])
				state.transport_changed.emit()
		"repeat":
			state.looping = _as_bool(args)
			state.transport_changed.emit()
		"click":
			# Reaper's METRONOME, which it states as it changes and on a refresh.
			state.metronome = _as_bool(args)
			state.transport_changed.emit()
		"fxchoices":
			# [id, name, id, name, ...]: the plugins a chain can be given on this DAW.
			var choices: Array = []
			for i in range(0, args.size() - 1, 2):
				choices.append([str(args[i]), str(args[i + 1])])
			state.fx_choices = choices
			state.transport_changed.emit()
		"inputs":
			# [id, name, id, name, ...]: what a track can record from on this DAW.
			var pairs: Array = []
			for i in range(0, args.size() - 1, 2):
				pairs.append([str(args[i]), str(args[i + 1])])
			state.inputs = pairs
			state.transport_changed.emit()
		"punch":
			state.punch = _as_bool(args)
			state.transport_changed.emit()
		"countin":
			if p.size() == 1 and args.size() > 0:
				state.count_in_bars = clampi(int(args[0]), 0, MixState.COUNT_IN_MAX)
				state.transport_changed.emit()
			elif p.size() > 1 and p[1] == "to" and args.size() > 0:
				state.count_in_to = float(args[0]) if is_finite(float(args[0])) and float(args[0]) >= 0.0 else -1.0
				state.transport_changed.emit()
			elif p.size() > 1 and p[1] == "play" and args.size() > 0:
				state.count_in_play = _as_bool(args)
				state.transport_changed.emit()
			elif p.size() > 1 and p[1] == "song" and args.size() > 0:
				# dawlings's own: pre-roll (MixState.pre_roll).
				state.pre_roll = _as_bool(args)
				state.transport_changed.emit()
		"loop":
			if p.size() > 2 and p[2] == "time" and args.size() > 0:
				if p[1] == "start":
					state.loop_start = float(args[0])
				elif p[1] == "end":
					state.loop_end = float(args[0])
				state.transport_changed.emit()
		"undo":
			# dawlings's own: how deep the history is, from the bridge.
			if args.size() > 1:
				state.undo_depth = int(args[0])
				state.redo_depth = int(args[1])
				# And what each step is called, after the two counts, when the host says.
				state.undo_names = args.slice(2).map(func(n): return str(n))
				state.transport_changed.emit()
		"project":
			# dawlings's own. OSC says nothing about how big a project is -- only how big the
			# bank is -- so without this a 90-track session is indistinguishable from a
			# 64-track one and the bank buttons have nothing to be enabled or greyed by.
			if p.size() > 1 and p[1] == "tracks" and args.size() > 0:
				# Only on a change. The bridge restates the count every few hundred ms, and a
				# bank_changed per restatement rebuilt the desk under whoever was mid-drag.
				var count := int(args[0])
				var changed := count != state.project_track_count
				state.project_track_count = count
				state.trim_to_project()
				if changed:
					state.bank_changed.emit()
			elif p.size() > 1 and p[1] == "name" and args.size() > 0:
				# dawlings's own: [title, file name].
				state.project_title = str(args[0])
				state.project_file = str(args[1]).get_file() if args.size() > 1 else ""
				state.project_named.emit()
		"bank":
			# Where the current bank starts, in tracks. Also dawlings's own: Reaper is told a
			# bank NUMBER and never says which one it settled on, so the authority states it
			# here and every guest learns it the same way it learns everything else.
			if args.size() > 0:
				state.set_bank(int(args[0]), int(args[1]) if args.size() > 1 else -1)
		"timeline":
			_apply_timeline(state, p, args)
		"timesig":
			if p.size() == 1 and args.size() >= 2:
				var sig := Vector2i(int(args[0]), int(args[1]))
				state.beats_per_bar = DawKitMeter._num(sig.x)
				state.beat_unit = DawKitMeter._den(sig.y)
				state.transport_changed.emit()
			elif p.size() > 1 and p[1] == "map":
				# dawlings's own: the signature's changes, flat [beat, numerator, denominator].
				state.time_signature_points = unpack_meter_points(args)
				state.transport_changed.emit()
		"tempo":
			if p.size() == 1 and args.size() > 0:
				# `n/tempo` is normalised across Reaper's tempo range, not BPM. Only the
				# `/tempo/raw` form is a real number of beats per minute.
				pass
			elif p.size() > 1 and p[1] == "raw" and args.size() > 0:
				state.tempo = float(args[0])
				state.transport_changed.emit()
			elif p.size() > 1 and p[1] == "map":
				# dawlings's own: the tempo's changes, flat [beat, bpm, shape] triples.
				state.tempo_points = unpack_tempo_points(args)
				state.transport_changed.emit()


## `/timeline/length` and `/timeline/markers`. Neither is a Reaper address: Reaper's OSC
## surface says nothing about the arrangement, so these are dawlings's own, filled by whatever
## channel a given backend has for structure -- the ReaScript bridge, for Reaper.
static func _apply_timeline(state: MixState, p: PackedStringArray, args: Array) -> void:
	# An empty list of markers is no markers, and has to be heard: it is how the last one goes.
	if p.size() < 2 or (args.is_empty() and p[1] != "markers"):
		return
	match p[1]:
		"length":
			state.set_project_length(float(args[0]))
		"regions":
			state.regions = unpack_regions(args)
			state.timeline_changed.emit()
		"markers":
			# Flat [position, name, position, name, ...], for the same reason items are flat.
			var out: Dictionary = {}
			var i := 0
			while i + 1 < args.size():
				out[float(args[i])] = str(args[i + 1])
				i += 2
			state.markers = out
			state.timeline_changed.emit()


## `/master/volume`, `/master/pan`, `/master/vu/L`, `/master/vu/R`. All four are in the pattern
## file as MASTER_VOLUME, MASTER_PAN and MASTER_VU_L/R, so none of this is invented.
##
## The mono `/master/vu` is accepted and written to BOTH channels, because a device configured
## with MASTER_VU and not the split pair would otherwise leave the meter dead with no hint why.
static func _apply_master(state: MixState, p: PackedStringArray, args: Array) -> void:
	# `/master/automation/<volume|pan>`, whole; empty is the lane gone.
	if p.size() == 3 and p[1] == "automation":
		if p[2] in MASTER_LANES:
			var points := unpack_automation(p[2], args)
			if points.is_empty():
				state.master.automation.erase(p[2])
			else:
				state.master.automation[p[2]] = points
			state.master_changed.emit(&"automation")
		return
	if p.size() == 2 and p[1] == "automode" and not args.is_empty():
		# dawlings's own, as a track's: the bridge reads and writes the master's I_AUTOMODE.
		state.master.automation_mode = automation_mode_of(args[0])
		state.master_changed.emit(&"automation_mode")
		return
	if p.size() < 2 or args.is_empty():
		return
	match p[1]:
		"volume":
			if p.size() == 2:
				state.set_master_field(&"volume", float(args[0]))
				state.set_master_field(&"volume_db", _taper_to_db(float(args[0])))
			elif p[2] == "db":
				state.set_master_field(&"volume_db", float(args[0]))
		"pan":
			if p.size() == 2:
				state.set_master_field(&"pan", float(args[0]))
		"vu":
			var level := float(args[0])
			if p.size() == 2:
				state.set_master_field(&"vu_l", level)
				state.set_master_field(&"vu_r", level)
			elif p[2] == "L":
				state.set_master_field(&"vu_l", level)
			elif p[2] == "R":
				state.set_master_field(&"vu_r", level)


static func _apply_track(state: MixState, p: PackedStringArray, args: Array) -> void:
	if p.size() < 3 or not p[1].is_valid_int():
		return
	var idx := int(p[1])
	var field := p[2]
	if not state.in_project(idx):
		return

	# BEFORE the empty-args guard. For every other field an empty argument list is a malformed
	# message, but for a lane it is the message: no arguments means nothing is on this track
	# any more, and dropping it leaves deleted blocks on screen with nothing to clear them.
	# A lane of automation, whole: empty is the lane gone. `/track/N/automation/<target>`.
	if field == "automation":
		if p.size() == 4:
			var points := unpack_automation(p[3], args)
			var t := state.track(idx)
			if points.is_empty():
				t.automation.erase(p[3])
			else:
				t.automation[p[3]] = points
			state.track_changed.emit(idx, &"automation")
		return

	if field == "comp":
		state.set_track_comp(idx, unpack_comp(args))
		return

	# Only that it is frozen: what it held stays with the host.
	if field == "frozen":
		state.track(idx).frozen = {"remote": true} if _as_bool(args) else {}
		state.timeline_changed.emit()
		return

	if field == "items":
		# FLAT, not one address per item field. A forty-item lane would otherwise be a
		# hundred and sixty messages that must all arrive before the lane is drawable, and
		# a lane half-populated from a torn update draws blocks that were never there.
		# One address, one lane, applied whole.
		state.set_track_items(idx, _unpack_items(args))
		return

	if args.is_empty():
		return

	match field:
		"name":
			state.set_track_field(idx, &"name", str(args[0]))
		"volume":
			if p.size() == 3:
				state.set_track_field(idx, &"volume", float(args[0]))
			elif p[3] == "db":
				state.set_track_field(idx, &"volume_db", float(args[0]))
		"pan":
			if p.size() == 3:
				state.set_track_field(idx, &"pan", float(args[0]))
		"mute":
			state.set_track_field(idx, &"mute", _as_bool(args))
		"solo":
			state.set_track_field(idx, &"solo", _as_bool(args))
		"recarm":
			state.set_track_field(idx, &"rec_arm", _as_bool(args))
		"input":
			# NOT a Reaper OSC address: the bridge reads and writes I_RECINPUT.
			if not args.is_empty():
				state.set_track_field(idx, &"input", str(args[0]))
		"monitor":
			# One number, 0 off / 1 on / 2 auto. Reaper's config lists a b/ and an i/ pattern on
			# this address, but what it sends -- checked on the rig -- is the one float.
			if not args.is_empty():
				state.set_track_field(idx, &"monitor", clampi(int(roundf(float(args[0]))), 0, 2))
		"automode":
			# NOT a Reaper OSC address: the bridge reads and writes I_AUTOMODE.
			if not args.is_empty():
				state.set_track_field(idx, &"automation_mode", automation_mode_of(args[0]))
		"group":
			# dawlings's own: Reaper's OSC surface says nothing of track groups.
			if not args.is_empty():
				state.set_track_field(idx, &"group", clampi(int(float(args[0])), 0, 64))
		"select":
			state.set_track_field(idx, &"selected", _as_bool(args))
		"colour":
			# NOT a Reaper address. Reaper's OSC surface has no message for track colour, and a
			# colour chip is how you find the kick on a desk of 32 identical strips -- so
			# dawlings defines one in its own namespace, parsed here and emitted by the host
			# into the same replication stream as everything else. When the ReaScript bridge
			# starts supplying real colours, they reach every guest without another line.
			if args.size() >= 3:
				state.set_track_field(idx, &"colour", Color(float(args[0]), float(args[1]), float(args[2])))
		"folder":
			# Also dawlings's own, for the same reason as colour: Reaper's OSC surface has no
			# message for folder structure, and a 32-strip desk with no breaks in it is a wall.
			# A DELTA, not a level -- see TrackState.folder_depth.
			if args.size() >= 1:
				state.set_track_field(idx, &"folder_depth", int(args[0]))
		"vu":
			# Meters are written straight onto the cache without a changed signal. At 30Hz per
			# channel, emitting per update would fan a signal storm out to every one of the
			# surfaces drawing that track; meters poll the cache in _process instead.
			var t := state.track(idx)
			if p.size() == 3:
				t.vu_l = float(args[0])
				t.vu_r = t.vu_l
			elif p[3] == "L":
				t.vu_l = float(args[0])
			elif p[3] == "R":
				t.vu_r = float(args[0])
		"fx":
			_apply_fx(state, idx, p, args)
		"send":
			_apply_send(state, idx, p, args)
		"sends":
			_apply_send_count(state, idx, int(args[0]))
		"fxs":
			_apply_fx_count(state, idx, int(args[0]))


## [start, length, muted, name, selected] per item, repeating -- and, for an item that has
## notes, a sixth entry carrying them (see ItemState.notes). Self-describing rather than a wider
## fixed stride: an item's first field is always a number and a note payload never is, so a
## lane from a sender that knows nothing of notes reads exactly as it always did. A recorded
## take carries one more entry the same way, a Dictionary: {source, offset, peaks}.
const ITEM_WIDTH := 5
## Controller events one item can carry across the wire.
const CONTROLS_MAX := 8192
## Take lanes a track can have (DawKitClip.lane), and so what a peer's lane is clamped to.
const LANES_MAX := 15


## [position, name, position, name, ...], in time order.
## An automation mode from anyone: read (0), touch (2) or latch (4), read for anything else --
## Reaper's trim/read (0) and read (1) are both read here, and its write (3), which this desk does
## not offer, is read too.
static func automation_mode_of(v) -> int:
	if typeof(v) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(v)):
		return 0
	var m := int(roundf(float(v)))
	return m if m in [0, 2, 4] else 0


## What the master can be automated by.
const MASTER_LANES := ["volume", "pan"]


## The wire address of a lane: track 0 is the master.
static func automation_address(track_index: int, target: String) -> String:
	if track_index == 0:
		return "/master/automation/%s" % target
	return "/track/%d/automation/%s" % [track_index, target]


## At most this many points in one lane of automation cross the wire.
const AUTOMATION_POINTS_MAX := 8192


## Flat [seconds, value, shape] triples back into points for `target`: in order of seconds, each
## value clamped to what the control takes. Empty when the target names no control or a point is
## not three finite numbers.
static func unpack_automation(target: String, args: Array) -> Array:
	if DawKitAutomation.kind_of(target).is_empty():
		return []
	var out: Array = []
	var last := -1.0
	for i in range(0, mini(args.size(), AUTOMATION_POINTS_MAX * 3) - 2, 3):
		for k in 3:
			if typeof(args[i + k]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(args[i + k])):
				return []
		var at := float(args[i])
		if at < 0.0 or at <= last:
			return []
		out.append([at, DawKitAutomation.clamp_value(target, float(args[i + 1])),
				clampi(int(args[i + 2]), DawKitAutomation.HOLD, DawKitAutomation.LINEAR)])
		last = at
	return out


static func pack_automation(points: Array) -> Array:
	var out: Array = []
	for pt in points:
		out.append_array([float(pt[0]), float(pt[1]), int(pt[2])])
	return out


## At most this many tempo changes cross the wire: more is not a song, it is an attack.
const TEMPO_POINTS_MAX := 1024


static func pack_meter_points(points: Array) -> Array:
	var out: Array = []
	for pt in points:
		out.append_array([float(pt[0]), float(pt[1]), float(pt[2])])
	return out


## Flat triples back into signature changes: each a later beat in a real signature, from beat 0,
## or nothing.
static func unpack_meter_points(args: Array) -> Array:
	var out: Array = []
	var last := -1.0
	for i in range(0, mini(args.size(), TEMPO_POINTS_MAX * 3) - 2, 3):
		if args.slice(i, i + 3).any(func(v): return typeof(v) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(v))):
			return []
		var beat := float(args[i])
		var num := int(args[i + 1])
		var den := int(args[i + 2])
		if beat <= last or num < 1 or num > 64 or den < 1 or den > 64 or (out.is_empty() and beat != 0.0):
			return []
		out.append([beat, DawKitMeter._num(num), DawKitMeter._den(den)])
		last = beat
	return out


static func pack_tempo_points(points: Array) -> Array:
	var out: Array = []
	for pt in points:
		out.append_array([float(pt[0]), float(pt[1]), float(DawKitTempoMap.shape_of(pt[2]))])
	return out


## Flat triples back into points: each a later beat at a real tempo, from beat 0, or nothing.
static func unpack_tempo_points(args: Array) -> Array:
	var out: Array = []
	var last := -1.0
	for i in range(0, mini(args.size(), TEMPO_POINTS_MAX * 3) - 2, 3):
		if typeof(args[i]) not in [TYPE_FLOAT, TYPE_INT] or typeof(args[i + 1]) not in [TYPE_FLOAT, TYPE_INT]:
			return []
		var beat := float(args[i])
		var bpm := float(args[i + 1])
		if not is_finite(beat) or not is_finite(bpm) or beat <= last or bpm < 1.0 or bpm > 1000.0:
			return []
		if typeof(args[i + 2]) not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
			return []
		out.append([beat, bpm, DawKitTempoMap.shape_of(int(roundf(float(args[i + 2]))))])
		last = beat
	if not out.is_empty() and out[0][0] != 0.0:
		return []
	return out


## [count, start, end, name, ...]: the count first, so that no regions at all is still a message
## (an empty argument list is not one).
static func pack_regions(regions: Array) -> Array:
	var out: Array = [float(regions.size())]
	for r in regions:
		out.append_array([float(r[0]), float(r[1]), str(r[2])])
	return out


static func unpack_regions(args: Array) -> Array:
	var out: Array = []
	if args.is_empty():
		return out
	var n := int(args[0])
	for i in n:
		var at := 1 + i * 3
		if at + 2 >= args.size():
			break
		var a := float(args[at])
		var b := float(args[at + 1])
		if is_finite(a) and is_finite(b) and b > a:
			out.append([a, b, str(args[at + 2])])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


static func _pack_markers(markers: Dictionary) -> Array:
	var order: Array = markers.keys()
	order.sort()
	var out: Array = []
	for at in order:
		out.append_array([at, markers[at]])
	return out


static func _unpack_items(args: Array) -> Array:
	var out: Array = []
	var i := 0
	while i + ITEM_WIDTH - 1 < args.size():
		var item := MixState.ItemState.new()
		item.index = out.size()
		item.start = float(args[i])
		item.length = float(args[i + 1])
		item.muted = float(args[i + 2]) > 0.5
		item.name = str(args[i + 3])
		item.selected = float(args[i + 4]) > 0.5
		i += ITEM_WIDTH
		if i < args.size() and _is_note_payload(args[i]):
			item.notes = PackedFloat32Array(args[i])
			i += 1
		if i < args.size() and args[i] is Dictionary:
			var audio: Dictionary = args[i]
			item.source = str(audio.get("source", "")).get_file()
			item.source_offset = maxf(float(audio.get("offset", 0.0)), 0.0)
			var peaks = audio.get("peaks", PackedByteArray())
			item.peaks = peaks if peaks is PackedByteArray else PackedByteArray()
			item.fade_in = maxf(float(audio.get("fade_in", 0.0)), 0.0)
			item.fade_out = maxf(float(audio.get("fade_out", 0.0)), 0.0)
			item.fade_shape = DawKitClip.clean_shape(audio.get("fade_shape", 0))
			item.fade_out_shape = DawKitClip.clean_shape(audio.get("fade_out_shape", item.fade_shape))
			item.gain_db = float(audio.get("gain_db", 0.0))
			item.locked = bool(audio.get("locked", false))
			item.lane = clampi(int(audio.get("lane", 0)), 0, LANES_MAX)
			item.reversed = bool(audio.get("reversed", false))
			item.controls = DawKitClip.clean_controls(audio.get("controls", [])).slice(0, CONTROLS_MAX * DawKitClip.CONTROL_WIDTH)
			var loop: Array = audio.get("loop", [])
			if loop.size() == 2:
				item.loop_start = maxf(float(loop[0]), 0.0)
				item.loop_end = maxf(float(loop[1]), item.loop_start)
			i += 1
		out.append(item)
	return out


## A comp's stretches flat, start, end and lane a stretch.
static func pack_comp(comp: Array) -> Array:
	var out: Array = []
	for s in comp:
		out.append_array([float(s[0]), float(s[1]), float(s[2])])
	return out


## The stretches back, from a peer or a file: whole triples of finite numbers, each longer than
## nothing, in order, with a lane that exists.
static func unpack_comp(args: Array) -> Array:
	var out: Array = []
	var i := 0
	while i + 2 < args.size():
		var a := float(args[i])
		var b := float(args[i + 1])
		if is_finite(a) and is_finite(b) and b > a and a >= 0.0:
			out.append([a, b, clampi(int(float(args[i + 2])), 0, LANES_MAX)])
		i += 3
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


static func _is_note_payload(v) -> bool:
	return v is PackedFloat32Array or v is PackedFloat64Array or v is Array


static func _pack_items(items: Array) -> Array:
	var out: Array = []
	for item in items:
		out.append_array([item.start, item.length, 1.0 if item.muted else 0.0, item.name,
				1.0 if item.selected else 0.0])
		if not item.notes.is_empty():
			out.append(item.notes)
		# One optional Dictionary for whatever is not a MIDI payload: a recorded file, and the
		# clip's fades and gain. Absent when there is neither, so an item costs what it did.
		if not item.source.is_empty() or item.has_clip_shape() or item.locked or item.lane != 0 or not item.controls.is_empty():
			var extra := {}
			if not item.source.is_empty():
				extra = {"source": item.source, "offset": item.source_offset, "peaks": item.peaks}
			if item.has_clip_shape():
				extra["fade_in"] = item.fade_in
				extra["fade_out"] = item.fade_out
				extra["gain_db"] = item.gain_db
				if item.fade_shape != DawKitClip.FADE_LINEAR:
					extra["fade_shape"] = item.fade_shape
				# Only when it differs: absent, the fade out runs as the fade in does.
				if item.fade_out_shape != item.fade_shape:
					extra["fade_out_shape"] = item.fade_out_shape
				if item.is_looped():
					extra["loop"] = [item.loop_start, item.loop_end]
			if item.locked:
				extra["locked"] = true
			if item.lane != 0:
				extra["lane"] = item.lane
			if item.reversed:
				extra["reversed"] = true
			if not item.controls.is_empty():
				extra["controls"] = item.controls
			out.append(extra)
	return out


static func _apply_fx(state: MixState, track_idx: int, p: PackedStringArray, args: Array) -> void:
	if p.size() < 5 or not p[3].is_valid_int():
		return
	var fx_idx := int(p[3])
	var f := state.fx(track_idx, fx_idx)
	match p[4]:
		"name":
			f.name = MixState.FXState.bare_name(str(args[0]))
			f.type = MixState.FXState.type_of(str(args[0]))
			state.fx_changed.emit(track_idx, fx_idx)
		# dawlings's own: the plugin's real parameters, listed by the bridge.
		"paramlist":
			var listed: Array = args.map(func(a): return int(a))
			if listed != f.param_list:
				f.param_list = listed
				state.fx_changed.emit(track_idx, fx_idx)
		"presets":
			if p.size() == 5 and f.preset_count != int(args[0]):
				f.preset_count = int(args[0])
				state.fx_changed.emit(track_idx, fx_idx)
		"bypass":
			# Reaper's `bypass` is sent as ENABLED (1 = running). The name is a trap.
			f.enabled = _as_bool(args)
			state.fx_changed.emit(track_idx, fx_idx)
		# dawlings's own, from the bridge: OSC has no word for either.
		"wet":
			if p.size() == 5 and not is_equal_approx(f.wet, float(args[0])):
				f.wet = clampf(float(args[0]), 0.0, 1.0)
				state.fx_changed.emit(track_idx, fx_idx)
		"preset":
			if f.preset != str(args[0]):
				f.preset = str(args[0])
				state.fx_changed.emit(track_idx, fx_idx)
		"fxparam":
			if p.size() >= 7 and p[5].is_valid_int():
				var param := int(p[5])
				if p[6] == "value" and p.size() >= 8 and p[7] == "str":
					f.param_text[param] = str(args[0])
					if args.size() > 1:
						f.param_text_at[param] = float(args[1])
					else:
						f.param_text_at.erase(param)
				elif p[6] == "value":
					f.params[param] = float(args[0])
				elif p[6] == "name" and f.param_names.get(param) != str(args[0]):
					f.param_names[param] = str(args[0])
					# A knob's caption is its name; a rename that told nobody left it saying P3.
					state.fx_changed.emit(track_idx, fx_idx)


static func _apply_send(state: MixState, track_idx: int, p: PackedStringArray, args: Array) -> void:
	if p.size() < 5 or not p[3].is_valid_int():
		return
	var s := state.send(track_idx, int(p[3]))
	# Only the exact field address: `volume/str` and `pan/str` are Reaper's spelling of the same
	# value, and reading "-11.0dB" as a float would zero the level.
	if p.size() > 5:
		return
	var before := [s.dest_name, s.dest_track, s.volume, s.pan, s.key, s.pre_fader]
	match p[4]:
		"name": s.dest_name = str(args[0])
		# dawlings's own again, and the one that makes the patchbay exact rather than
		# approximate: OSC's `name` cannot tell two tracks called "Verb" apart.
		"dest": s.dest_track = int(args[0])
		"volume": s.volume = float(args[0])
		"pan": s.pan = float(args[0])
		# Also dawlings's own: a send into the destination's key input, not its mix.
		"key": s.key = _as_bool(args)
		# And this: taken before the track's fader and pan.
		"pre": s.pre_fader = _as_bool(args)
	# Told, so a control showing a send level follows it. Only on a change: Reaper restates
	# every slot of every track on a refresh, and most of them are empty.
	if before != [s.dest_name, s.dest_track, s.volume, s.pan, s.key, s.pre_fader]:
		state.track_changed.emit(track_idx, &"sends")


## How many sends a track has, which is the only way a send that was REMOVED stops being drawn.
## Every other send address can only say what a send is; none can say it is gone, and a pulled
## patch cable that stayed on the bay is the bay lying. Reaper renumbers a track's sends when one
## is removed, so the count is enough: anything numbered past it no longer exists.
static func _apply_send_count(state: MixState, track_idx: int, count: int) -> void:
	var t := state.track(track_idx)
	var gone := false
	for send_index in t.sends.keys():
		if int(send_index) > count:
			t.sends.erase(send_index)
			gone = true
	if gone:
		state.track_changed.emit(track_idx, &"sends")


## How many plugins a track's chain holds, for the same reason as the send count: a plugin moved
## to another track leaves its old slot, and only a count can say that slot is now empty. The
## slots past the count are emptied rather than erased, because OSC goes on restating every slot
## its device is set up for and an erased one would come straight back.
##
## Counted along the slots in order rather than compared with the slot numbers, because Reaper
## numbers a chain from 1 and the built-in engine from 0.
static func _apply_fx_count(state: MixState, track_idx: int, count: int) -> void:
	var t := state.track(track_idx)
	var order: Array = t.fx.keys()
	order.sort()
	for at in order.size():
		var fx_index: int = order[at]
		var f: MixState.FXState = t.fx[fx_index]
		if at >= count and f.name != "":
			f.name = ""
			f.type = ""
			f.params.clear()
			f.param_names.clear()
			f.param_text.clear()
			f.param_text_at.clear()
			f.wet = 1.0
			f.preset = ""
			f.preset_count = -1
			f.param_list = []
			state.fx_changed.emit(track_idx, int(fx_index))


static func _as_bool(args: Array) -> bool:
	if args.is_empty():
		return true  # a bare trigger message, e.g. `t/play`
	match typeof(args[0]):
		TYPE_BOOL: return args[0]
		TYPE_FLOAT, TYPE_INT: return float(args[0]) > 0.5
		TYPE_STRING: return str(args[0]) != "" and str(args[0]) != "0"
	return false



## Everything a freshly joined guest needs to draw the session, as OSC messages.
##
## Expressed in the SAME vocabulary as the live stream rather than as a bespoke snapshot struct.
## That is the whole trick: a guest has exactly one code path for "state arrived", the host has
## one for "state left", and a field added to ReaperState is replicated the day it is parsed
## rather than the day someone remembers to add it to a serialiser.
static func snapshot(state: MixState) -> Array:
	# FIRST, before a single track message. A bank statement redefines what every index after
	# it means, and applying one clears the cache -- so a snapshot that stated the bank at the
	# end would deliver a full project and then throw it away, leaving a guest with an empty
	# desk and nothing in the log.
	var out: Array = [
		["/bank", [state.bank_offset, state.bank_size]],
		["/project/tracks", [state.project_track_count]],
	]
	if not state.project_title.is_empty() or not state.project_file.is_empty():
		out.append(["/project/name", [state.project_title, state.project_file]])
	for index in state.track_indices():
		var t: MixState.TrackState = state.tracks[index]
		out.append(["/track/%d/name" % index, [t.name]])
		out.append(["/track/%d/volume" % index, [t.volume]])
		out.append(["/track/%d/volume/db" % index, [t.volume_db]])
		out.append(["/track/%d/pan" % index, [t.pan]])
		out.append(["/track/%d/mute" % index, [1.0 if t.mute else 0.0]])
		out.append(["/track/%d/solo" % index, [1.0 if t.solo else 0.0]])
		out.append(["/track/%d/recarm" % index, [1.0 if t.rec_arm else 0.0]])
		out.append(["/track/%d/monitor" % index, [float(t.monitor)]])
		if t.input != "":
			out.append(["/track/%d/input" % index, [t.input]])
		if t.automation_mode != 0:
			out.append(["/track/%d/automode" % index, [float(t.automation_mode)]])
		out.append(["/track/%d/select" % index, [1.0 if t.selected else 0.0]])
		out.append(["/track/%d/colour" % index, [t.colour.r, t.colour.g, t.colour.b]])
		# Always, none too: a renumbering resends the mix onto tracks a guest already has.
		out.append(["/track/%d/group" % index, [float(t.group)]])
		out.append(["/track/%d/folder" % index, [float(t.folder_depth)]])
		if not t.items.is_empty():
			out.append(["/track/%d/items" % index, _pack_items(t.items)])
		if not t.comp.is_empty():
			out.append(["/track/%d/comp" % index, pack_comp(t.comp)])
		if t.is_frozen():
			out.append(["/track/%d/frozen" % index, [1.0]])
		for target in t.automation:
			out.append(["/track/%d/automation/%s" % [index, target], pack_automation(t.automation[target])])

		var fx_indices: Array = t.fx.keys()
		fx_indices.sort()
		for fx_index in fx_indices:
			var f: MixState.FXState = t.fx[fx_index]
			out.append(["/track/%d/fx/%d/name" % [index, fx_index],
					[("%s: %s" % [f.type, f.name]) if f.type != "" else f.name]])
			out.append(["/track/%d/fx/%d/bypass" % [index, fx_index], [1.0 if f.enabled else 0.0]])
			out.append(["/track/%d/fx/%d/wet" % [index, fx_index], [f.wet]])
			if f.preset != "":
				out.append(["/track/%d/fx/%d/preset" % [index, fx_index], [f.preset]])
			if f.preset_count >= 0:
				out.append(["/track/%d/fx/%d/presets" % [index, fx_index], [float(f.preset_count)]])
			if not f.param_list.is_empty():
				out.append(["/track/%d/fx/%d/paramlist" % [index, fx_index], f.param_list.map(func(i): return float(i))])
			for param in f.controls():
				if f.params.has(param):
					out.append(["/track/%d/fx/%d/fxparam/%d/value" % [index, fx_index, param], [f.params[param]]])
				if f.param_names.has(param):
					out.append(["/track/%d/fx/%d/fxparam/%d/name" % [index, fx_index, param], [f.param_names[param]]])
				if f.param_text.has(param):
					var words: Array = [f.param_text[param]]
					if f.param_text_at.has(param):
						words.append(f.param_text_at[param])
					out.append(["/track/%d/fx/%d/fxparam/%d/value/str" % [index, fx_index, param], words])

		var send_indices: Array = t.sends.keys()
		send_indices.sort()
		for send_index in send_indices:
			var sd: MixState.SendState = t.sends[send_index]
			out.append(["/track/%d/send/%d/name" % [index, send_index], [sd.dest_name]])
			out.append(["/track/%d/send/%d/dest" % [index, send_index], [float(sd.dest_track)]])
			out.append(["/track/%d/send/%d/volume" % [index, send_index], [sd.volume]])
			out.append(["/track/%d/send/%d/pan" % [index, send_index], [sd.pan]])
			out.append(["/track/%d/send/%d/key" % [index, send_index], [1.0 if sd.key else 0.0]])
			out.append(["/track/%d/send/%d/pre" % [index, send_index], [1.0 if sd.pre_fader else 0.0]])
		# After them, so a guest that still holds a send the host has since removed drops it.
		out.append(["/track/%d/sends" % index, [float(send_indices.max() if not send_indices.is_empty() else 0)]])

	out.append(["/master/volume", [state.master.volume]])
	out.append(["/master/pan", [state.master.pan]])
	for target in state.master.automation:
		out.append(["/master/automation/%s" % target, pack_automation(state.master.automation[target])])
	if state.master.automation_mode != 0:
		out.append(["/master/automode", [float(state.master.automation_mode)]])
	out.append(["/tempo/raw", [state.tempo]])
	out.append(["/tempo/map", pack_tempo_points(state.tempo_points)])
	out.append(["/timesig", [float(state.beats_per_bar), float(state.beat_unit)]])
	out.append(["/timesig/map", pack_meter_points(state.time_signature_points)])
	out.append(["/play", [1.0 if state.playing else 0.0]])
	out.append(["/record", [1.0 if state.recording else 0.0]])
	out.append(["/beat/str", [state.position_string]])
	out.append(["/time", [state.position_seconds]])
	out.append(["/repeat", [1.0 if state.looping else 0.0]])
	out.append(["/click", [1.0 if state.metronome else 0.0]])
	for g in state.vca.size():
		if not is_zero_approx(float(state.vca[g])):
			out.append(["/vca/%d" % (g + 1), [float(state.vca[g])]])
	out.append(["/countin", [float(state.count_in_bars)]])
	out.append(["/countin/play", [1.0 if state.count_in_play else 0.0]])
	out.append(["/countin/song", [1.0 if state.pre_roll else 0.0]])
	if not state.inputs.is_empty():
		out.append(["/inputs", pack_inputs(state.inputs)])
		out.append(["/fxchoices", pack_inputs(state.fx_choices)])
	out.append(["/punch", [1.0 if state.punch else 0.0]])
	out.append(["/countin/to", [state.count_in_to]])
	out.append(["/loop/start/time", [state.loop_start]])
	out.append(["/loop/end/time", [state.loop_end]])
	out.append(["/timeline/length", [state.project_length]])
	out.append(["/timeline/markers", _pack_markers(state.markers)])
	out.append(["/timeline/regions", pack_regions(state.regions)])
	return out


## State arriving from the host. Deliberately NOT routed through write() or the echo guard --
## this is authority speaking, and a guest has nothing of its own to protect against.
##
## Includes track colour, which is a dawlings address rather than a Reaper one -- see the
## "colour" case in _apply_track for why.
static func apply_replicated(state: MixState, batch: Array) -> void:
	for entry in batch:
		if entry is Array and entry.size() == 2:
			apply(state, entry[0], entry[1])


static func pack_inputs(inputs: Array) -> Array:
	var out: Array = []
	for pair in inputs:
		out.append_array([str(pair[0]), str(pair[1])])
	return out
