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
		"loop":
			if p.size() > 2 and p[2] == "time" and args.size() > 0:
				if p[1] == "start":
					state.loop_start = float(args[0])
				elif p[1] == "end":
					state.loop_end = float(args[0])
				state.transport_changed.emit()
		"undo":
			# reaper-3d's own: how deep the history is, from the bridge.
			if args.size() > 1:
				state.undo_depth = int(args[0])
				state.redo_depth = int(args[1])
				state.transport_changed.emit()
		"project":
			# reaper-3d's own. OSC says nothing about how big a project is -- only how big the
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
		"bank":
			# Where the current bank starts, in tracks. Also reaper-3d's own: Reaper is told a
			# bank NUMBER and never says which one it settled on, so the authority states it
			# here and every guest learns it the same way it learns everything else.
			if args.size() > 0:
				state.set_bank(int(args[0]), int(args[1]) if args.size() > 1 else -1)
		"timeline":
			_apply_timeline(state, p, args)
		"tempo":
			if p.size() == 1 and args.size() > 0:
				# `n/tempo` is normalised across Reaper's tempo range, not BPM. Only the
				# `/tempo/raw` form is a real number of beats per minute.
				pass
			elif p.size() > 1 and p[1] == "raw" and args.size() > 0:
				state.tempo = float(args[0])
				state.transport_changed.emit()


## `/timeline/length` and `/timeline/markers`. Neither is a Reaper address: Reaper's OSC
## surface says nothing about the arrangement, so these are reaper-3d's own, filled by whatever
## channel a given backend has for structure -- the ReaScript bridge, for Reaper.
static func _apply_timeline(state: MixState, p: PackedStringArray, args: Array) -> void:
	if p.size() < 2 or args.is_empty():
		return
	match p[1]:
		"length":
			state.set_project_length(float(args[0]))
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
		"monitor":
			# One number, 0 off / 1 on / 2 auto. Reaper's config lists a b/ and an i/ pattern on
			# this address, but what it sends -- checked on the rig -- is the one float.
			if not args.is_empty():
				state.set_track_field(idx, &"monitor", clampi(int(roundf(float(args[0]))), 0, 2))
		"select":
			state.set_track_field(idx, &"selected", _as_bool(args))
		"colour":
			# NOT a Reaper address. Reaper's OSC surface has no message for track colour, and a
			# colour chip is how you find the kick on a desk of 32 identical strips -- so
			# reaper-3d defines one in its own namespace, parsed here and emitted by the host
			# into the same replication stream as everything else. When the ReaScript bridge
			# starts supplying real colours, they reach every guest without another line.
			if args.size() >= 3:
				state.set_track_field(idx, &"colour", Color(float(args[0]), float(args[1]), float(args[2])))
		"folder":
			# Also reaper-3d's own, for the same reason as colour: Reaper's OSC surface has no
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


## [start, length, muted, name, selected] per item, repeating.
const ITEM_WIDTH := 5


## [position, name, position, name, ...], in time order.
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
		out.append(item)
		i += ITEM_WIDTH
	return out


static func _pack_items(items: Array) -> Array:
	var out: Array = []
	for item in items:
		out.append_array([item.start, item.length, 1.0 if item.muted else 0.0, item.name,
				1.0 if item.selected else 0.0])
	return out


static func _apply_fx(state: MixState, track_idx: int, p: PackedStringArray, args: Array) -> void:
	if p.size() < 5 or not p[3].is_valid_int():
		return
	var fx_idx := int(p[3])
	var f := state.fx(track_idx, fx_idx)
	match p[4]:
		"name":
			f.name = str(args[0])
			state.fx_changed.emit(track_idx, fx_idx)
		"bypass":
			# Reaper's `bypass` is sent as ENABLED (1 = running). The name is a trap.
			f.enabled = _as_bool(args)
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
	var before := [s.dest_name, s.dest_track, s.volume, s.pan]
	match p[4]:
		"name": s.dest_name = str(args[0])
		# reaper-3d's own again, and the one that makes the patchbay exact rather than
		# approximate: OSC's `name` cannot tell two tracks called "Verb" apart.
		"dest": s.dest_track = int(args[0])
		"volume": s.volume = float(args[0])
		"pan": s.pan = float(args[0])
	# Told, so a control showing a send level follows it. Only on a change: Reaper restates
	# every slot of every track on a refresh, and most of them are empty.
	if before != [s.dest_name, s.dest_track, s.volume, s.pan]:
		state.track_changed.emit(track_idx, &"sends")


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
		out.append(["/track/%d/select" % index, [1.0 if t.selected else 0.0]])
		out.append(["/track/%d/colour" % index, [t.colour.r, t.colour.g, t.colour.b]])
		out.append(["/track/%d/folder" % index, [float(t.folder_depth)]])
		if not t.items.is_empty():
			out.append(["/track/%d/items" % index, _pack_items(t.items)])

		var fx_indices: Array = t.fx.keys()
		fx_indices.sort()
		for fx_index in fx_indices:
			var f: MixState.FXState = t.fx[fx_index]
			out.append(["/track/%d/fx/%d/name" % [index, fx_index], [f.name]])
			out.append(["/track/%d/fx/%d/bypass" % [index, fx_index], [1.0 if f.enabled else 0.0]])
			var param_indices: Array = f.params.keys()
			param_indices.sort()
			for param in param_indices:
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

	out.append(["/master/volume", [state.master.volume]])
	out.append(["/master/pan", [state.master.pan]])
	out.append(["/tempo/raw", [state.tempo]])
	out.append(["/play", [1.0 if state.playing else 0.0]])
	out.append(["/record", [1.0 if state.recording else 0.0]])
	out.append(["/beat/str", [state.position_string]])
	out.append(["/time", [state.position_seconds]])
	out.append(["/repeat", [1.0 if state.looping else 0.0]])
	out.append(["/click", [1.0 if state.metronome else 0.0]])
	out.append(["/loop/start/time", [state.loop_start]])
	out.append(["/loop/end/time", [state.loop_end]])
	out.append(["/timeline/length", [state.project_length]])
	if not state.markers.is_empty():
		out.append(["/timeline/markers", _pack_markers(state.markers)])
	return out


## State arriving from the host. Deliberately NOT routed through write() or the echo guard --
## this is authority speaking, and a guest has nothing of its own to protect against.
##
## Includes track colour, which is a reaper-3d address rather than a Reaper one -- see the
## "colour" case in _apply_track for why.
static func apply_replicated(state: MixState, batch: Array) -> void:
	for entry in batch:
		if entry is Array and entry.size() == 2:
			apply(state, entry[0], entry[1])
