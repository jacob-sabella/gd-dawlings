extends Node

## Autoload `Reaper`. The one door between this scene and the DAW.
##
## THREE MODES, and the scene cannot tell them apart:
##
##   OFFLINE  no DAW. State is a synthetic mix so the studio can be built, lit and photographed
##            without Reaper running. Not a mock for tests -- a development stand-in, which is
##            why it lives in the shipping class rather than in tests/.
##   HOST     this process owns the OSC socket and is the only one that talks to Reaper.
##   GUEST    someone else is HOST. Reads come from replication; writes become intents sent to
##            the host.
##
## Exactly one HOST per session, always. This is the central constraint of a hybrid room: if
## three headsets and a laptop each opened their own OSC link, Reaper would broadcast every
## change to all four, each would apply it locally, and a grabbed fader would fight its own echo
## three times over. One link, one writer, one authority -- and Reaper itself remains the truth
## above even that.

const Mode := {OFFLINE = 0, HOST = 1, GUEST = 2}

## How many tracks and parameters the device asks Reaper to stream. Sent on connect; Reaper
## otherwise uses whatever the pattern file declares, which defaults to 8 tracks -- a console
## that silently stops at channel 8 on a 30-track project.
const BANK_TRACKS := 64
const BANK_FX_PARAMS := 32
const BANK_SENDS := 8

signal connection_changed()

## Replication tick. 20Hz, deliberately slower than Reaper's ~30Hz meter stream: the buffers
## below are keyed by address, so a faster-arriving value simply overwrites the pending one and
## the tick rate becomes the rate limit for free.
const REPLICATION_HZ := 20.0

var mode: int = Mode.OFFLINE
var state := ReaperState.new()

var _peer: OSCPeer = null
var _bridge: ScriptBridge = null
## Addresses this process wrote within the last few frames, with the value it wrote. Reaper
## echoes every change back, so without this a fader snaps to a stale value for one frame on
## every single drag update -- visible as a fader that fights the hand holding it.
var _echo_guard: Dictionary = {}
const ECHO_GRACE_MSEC := 250

## Pending replication, keyed by OSC address so repeats collapse. Split in two because the two
## halves need opposite delivery guarantees, and sending both the same way is wrong either way:
##
##   DURABLE   names, volumes, mute/solo, FX parameters. Sent RELIABLY. These are edge-triggered
##             -- a value is only resent when it changes -- so a dropped packet loses that change
##             permanently, and a guest would show the wrong track name until someone renamed it
##             again.
##   VOLATILE  meters and the playhead. Sent UNRELIABLY. These are level-triggered and arrive
##             again in 50ms regardless. Spending retransmits on a meter reading that is already
##             stale by the time it lands is how you make the durable half late.
var _repl_durable: Dictionary = {}
var _repl_volatile: Dictionary = {}
var _repl_accumulator := 0.0


func _ready() -> void:
	# An autoload that opens a socket on startup would make `godot --headless` in CI try to talk
	# to a DAW. Nothing happens until a scene asks for it.
	set_process(false)


func start_host(reaper_host: String = "127.0.0.1", send_port: int = 8000, listen_port: int = 9000) -> bool:
	stop()
	_peer = OSCPeer.new()
	if _peer.open(reaper_host, send_port, listen_port) != OK:
		_peer = null
		return false
	mode = Mode.HOST
	_bridge = ScriptBridge.new()
	_bridge.open()
	set_process(true)

	# Tell Reaper how wide this surface is, then ask for a full resend. Without the resend a
	# client that connects after Reaper has started sees nothing until something moves, which
	# looks exactly like a broken link.
	_peer.send("/device/track/count", [BANK_TRACKS])
	_peer.send("/device/fxparam/count", [BANK_FX_PARAMS])
	_peer.send("/device/send/count", [BANK_SENDS])
	_peer.send("/device/track/bank/select", [1])
	connection_changed.emit()
	return true


func start_guest() -> void:
	stop()
	mode = Mode.GUEST
	set_process(false)
	connection_changed.emit()


func stop() -> void:
	if _peer:
		_peer.close()
		_peer = null
	if _bridge:
		_bridge.close()
		_bridge = null
	mode = Mode.OFFLINE
	set_process(false)
	connection_changed.emit()


func is_connected_to_reaper() -> bool:
	return mode == Mode.HOST and _peer != null and _peer.packets_received > 0


func link_summary() -> String:
	match mode:
		Mode.HOST:
			if _peer == null:
				return "host: socket closed"
			if _peer.packets_received == 0:
				return "host: listening, nothing heard from Reaper yet"
			var age := (Time.get_ticks_msec() - _peer.last_receive_msec) / 1000.0
			return "host: %d in / %d out, last %.1fs ago" % [_peer.packets_received, _peer.packets_sent, age]
		Mode.GUEST:
			return "guest: replicated from host"
		_:
			return "offline: synthetic mix"


func _process(delta: float) -> void:
	# Where state comes from and whether it needs replicating are separate questions, and this
	# used to answer them in one branch: an OFFLINE host returned early, so a session hosted on
	# the stand-in mix replicated nothing at all and every guest sat looking at an empty room.
	# Hosting the demo is exactly how the multi-user path gets demonstrated, so that was the one
	# configuration most likely to be tried first.
	if mode == Mode.OFFLINE:
		_drive_offline_meters(delta)
	else:
		if _bridge:
			_bridge.poll()
		if _peer:
			for m in _peer.poll():
				_apply(m["address"], m["args"])

	_repl_accumulator += delta
	if _repl_accumulator >= 1.0 / REPLICATION_HZ:
		_repl_accumulator = 0.0
		_flush_replication()

	var now := Time.get_ticks_msec()
	for key in _echo_guard.keys():
		if now - int(_echo_guard[key]["t"]) > ECHO_GRACE_MSEC:
			_echo_guard.erase(key)


# --- inbound ------------------------------------------------------------------------------

## Route one OSC message into the state cache.
##
## Reaper's addresses are positional (`/track/3/fx/2/fxparam/5/value`), so this splits rather
## than pattern-matches. Unknown addresses are dropped in silence by design: the pattern file
## streams far more than this project draws yet, and logging each one would print thousands of
## lines a second.
func _apply(address: String, args: Array) -> void:
	if _is_echo(address, args):
		return
	# Recorded BEFORE parsing, not after. A message this build does not yet understand is still
	# a message a guest should receive: the guest runs the same parser, so a surface added there
	# and not here would otherwise be starved of data by its own host.
	# Not `mode == HOST`: an OFFLINE process hosting a session is just as much the authority,
	# and the only mode that must never replicate is the one receiving it.
	if mode != Mode.GUEST:
		if _is_volatile(address):
			_repl_volatile[address] = args
		else:
			_repl_durable[address] = args
	var p := address.trim_prefix("/").split("/")
	if p.is_empty():
		return

	match p[0]:
		"track":
			_apply_track(p, args)
		"master":
			_apply_master(p, args)
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
				state.position_string = str(args[0])
				state.transport_changed.emit()
		"tempo":
			if p.size() == 1 and args.size() > 0:
				# `n/tempo` is normalised across Reaper's tempo range, not BPM. Only the
				# `/tempo/raw` form is a real number of beats per minute.
				pass
			elif p.size() > 1 and p[1] == "raw" and args.size() > 0:
				state.tempo = float(args[0])
				state.transport_changed.emit()


## `/master/volume`, `/master/pan`, `/master/vu/L`, `/master/vu/R`. All four are in the pattern
## file as MASTER_VOLUME, MASTER_PAN and MASTER_VU_L/R, so none of this is invented.
##
## The mono `/master/vu` is accepted and written to BOTH channels, because a device configured
## with MASTER_VU and not the split pair would otherwise leave the meter dead with no hint why.
func _apply_master(p: PackedStringArray, args: Array) -> void:
	if p.size() < 2 or args.is_empty():
		return
	match p[1]:
		"volume":
			if p.size() == 2:
				state.set_master_field(&"volume", float(args[0]))
				state.set_master_field(&"volume_db", ReaperState.taper_to_db(float(args[0])))
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


func _apply_track(p: PackedStringArray, args: Array) -> void:
	if p.size() < 3 or not p[1].is_valid_int():
		return
	var idx := int(p[1])
	var field := p[2]
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
			_apply_fx(idx, p, args)
		"send":
			_apply_send(idx, p, args)


func _apply_fx(track_idx: int, p: PackedStringArray, args: Array) -> void:
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
				if p[6] == "value":
					f.params[param] = float(args[0])
				elif p[6] == "name":
					f.param_names[param] = str(args[0])


func _apply_send(track_idx: int, p: PackedStringArray, args: Array) -> void:
	if p.size() < 5 or not p[3].is_valid_int():
		return
	var s := state.send(track_idx, int(p[3]))
	match p[4]:
		"name": s.dest_name = str(args[0])
		"volume": s.volume = float(args[0])
		"pan": s.pan = float(args[0])


static func _as_bool(args: Array) -> bool:
	if args.is_empty():
		return true  # a bare trigger message, e.g. `t/play`
	match typeof(args[0]):
		TYPE_BOOL: return args[0]
		TYPE_FLOAT, TYPE_INT: return float(args[0]) > 0.5
		TYPE_STRING: return str(args[0]) != "" and str(args[0]) != "0"
	return false


# --- outbound -----------------------------------------------------------------------------

## Every write in the project funnels through here, which is what makes the GUEST case free:
## a channel strip in AR calls `Reaper.write()` exactly as the host's does, and the routing to
## an intent happens below it rather than in the control.
func write(address: String, args: Array = []) -> void:
	match mode:
		Mode.HOST:
			if _peer:
				_echo_guard[address] = {"v": args, "t": Time.get_ticks_msec()}
				_peer.send(address, args)
		Mode.GUEST:
			Session.send_intent(address, args)
		_:
			# Offline: apply locally so the studio still responds to being touched with no DAW
			# behind it. Without this, development and every screenshot would show dead controls.
			_apply(address, args)


func _is_echo(address: String, args: Array) -> bool:
	if not _echo_guard.has(address):
		return false
	var guarded: Array = _echo_guard[address]["v"]
	if guarded.size() != args.size():
		return false
	for i in args.size():
		if typeof(args[i]) == TYPE_FLOAT and is_equal_approx(float(args[i]), float(guarded[i])):
			continue
		if args[i] != guarded[i]:
			return false
	return true


func set_track_volume(index: int, taper: float) -> void:
	write("/track/%d/volume" % index, [clampf(taper, 0.0, 1.0)])


func set_master_volume(taper: float) -> void:
	write("/master/volume", [clampf(taper, 0.0, 1.0)])


func set_master_pan(pan: float) -> void:
	write("/master/pan", [clampf(pan, 0.0, 1.0)])


func set_track_pan(index: int, pan: float) -> void:
	write("/track/%d/pan" % index, [clampf(pan, 0.0, 1.0)])


func set_track_mute(index: int, muted: bool) -> void:
	write("/track/%d/mute" % index, [1.0 if muted else 0.0])


func set_track_solo(index: int, soloed: bool) -> void:
	write("/track/%d/solo" % index, [1.0 if soloed else 0.0])


func set_track_rec_arm(index: int, armed: bool) -> void:
	write("/track/%d/recarm" % index, [1.0 if armed else 0.0])


func set_fx_param(track_index: int, fx_index: int, param: int, value: float) -> void:
	write("/track/%d/fx/%d/fxparam/%d/value" % [track_index, fx_index, param], [clampf(value, 0.0, 1.0)])


func set_fx_enabled(track_index: int, fx_index: int, enabled: bool) -> void:
	write("/track/%d/fx/%d/bypass" % [track_index, fx_index], [1.0 if enabled else 0.0])


func transport_play() -> void:
	write("/play", [1.0])


func transport_stop() -> void:
	write("/stop", [1.0])


func transport_record() -> void:
	write("/record", [1.0])


## Routing changes have no OSC pattern -- Reaper streams send VOLUMES but has no message for
## "create a send from 3 to 7". The patchbay therefore writes through the ReaScript bridge, and
## this returns false when that bridge is absent so the surface can show a cable it cannot yet
## plug rather than pretending.
func create_send(from_track: int, to_track: int) -> bool:
	if _bridge == null or not _bridge.is_open():
		push_warning("create_send(%d -> %d) needs the ReaScript bridge; OSC cannot express it." % [from_track, to_track])
		return false
	return _bridge.call_reaper("CreateTrackSend", [from_track, to_track])


func remove_send(from_track: int, send_index: int) -> bool:
	if _bridge == null or not _bridge.is_open():
		return false
	return _bridge.call_reaper("RemoveTrackSend", [from_track, send_index])


# --- replication --------------------------------------------------------------------------

## Meters and the playhead. Everything else is durable.
static func _is_volatile(address: String) -> bool:
	return address.contains("/vu") or address.begins_with("/time")


func _flush_replication() -> void:
	if _repl_durable.is_empty() and _repl_volatile.is_empty():
		return
	if Session.participants.size() <= 1:
		# Solo, or hosting with nobody connected. Buffers are cleared rather than left to grow
		# into a backlog that would be delivered in one burst the moment someone joins.
		_repl_durable.clear()
		_repl_volatile.clear()
		return
	Session.broadcast_state(_repl_durable.duplicate(), _repl_volatile.duplicate())
	_repl_durable.clear()
	_repl_volatile.clear()


## Everything a freshly joined guest needs to draw the session, as OSC messages.
##
## Expressed in the SAME vocabulary as the live stream rather than as a bespoke snapshot struct.
## That is the whole trick: a guest has exactly one code path for "state arrived", the host has
## one for "state left", and a field added to ReaperState is replicated the day it is parsed
## rather than the day someone remembers to add it to a serialiser.
func snapshot() -> Array:
	var out: Array = []
	for index in state.track_indices():
		var t: ReaperState.TrackState = state.tracks[index]
		out.append(["/track/%d/name" % index, [t.name]])
		out.append(["/track/%d/volume" % index, [t.volume]])
		out.append(["/track/%d/volume/db" % index, [t.volume_db]])
		out.append(["/track/%d/pan" % index, [t.pan]])
		out.append(["/track/%d/mute" % index, [1.0 if t.mute else 0.0]])
		out.append(["/track/%d/solo" % index, [1.0 if t.solo else 0.0]])
		out.append(["/track/%d/recarm" % index, [1.0 if t.rec_arm else 0.0]])
		out.append(["/track/%d/select" % index, [1.0 if t.selected else 0.0]])
		out.append(["/track/%d/colour" % index, [t.colour.r, t.colour.g, t.colour.b]])

		var fx_indices: Array = t.fx.keys()
		fx_indices.sort()
		for fx_index in fx_indices:
			var f: ReaperState.FXState = t.fx[fx_index]
			out.append(["/track/%d/fx/%d/name" % [index, fx_index], [f.name]])
			out.append(["/track/%d/fx/%d/bypass" % [index, fx_index], [1.0 if f.enabled else 0.0]])
			var param_indices: Array = f.params.keys()
			param_indices.sort()
			for param in param_indices:
				out.append(["/track/%d/fx/%d/fxparam/%d/value" % [index, fx_index, param], [f.params[param]]])
				if f.param_names.has(param):
					out.append(["/track/%d/fx/%d/fxparam/%d/name" % [index, fx_index, param], [f.param_names[param]]])

		var send_indices: Array = t.sends.keys()
		send_indices.sort()
		for send_index in send_indices:
			var sd: ReaperState.SendState = t.sends[send_index]
			out.append(["/track/%d/send/%d/name" % [index, send_index], [sd.dest_name]])
			out.append(["/track/%d/send/%d/volume" % [index, send_index], [sd.volume]])
			out.append(["/track/%d/send/%d/pan" % [index, send_index], [sd.pan]])

	out.append(["/master/volume", [state.master.volume]])
	out.append(["/master/pan", [state.master.pan]])
	out.append(["/tempo/raw", [state.tempo]])
	out.append(["/play", [1.0 if state.playing else 0.0]])
	out.append(["/record", [1.0 if state.recording else 0.0]])
	out.append(["/time/str", [state.position_string]])
	return out


## State arriving from the host. Deliberately NOT routed through write() or the echo guard --
## this is authority speaking, and a guest has nothing of its own to protect against.
##
## Includes track colour, which is a reaper-3d address rather than a Reaper one -- see the
## "colour" case in _apply_track for why.
func apply_replicated(batch: Array) -> void:
	for entry in batch:
		if entry is Array and entry.size() == 2:
			_apply(entry[0], entry[1])


# --- offline stand-in ---------------------------------------------------------------------

## Fill the cache with a plausible session so the room can be built without Reaper. The names
## are deliberately a real-looking drum/band session: a console of eight tracks called "Track 1"
## through "Track 8" hides every layout problem that long names cause.
func populate_offline_demo() -> void:
	mode = Mode.OFFLINE
	var demo := [
		{"n": "Kick", "v": 0.78, "p": 0.5, "c": Color(0.86, 0.33, 0.28)},
		{"n": "Snare", "v": 0.72, "p": 0.5, "c": Color(0.88, 0.52, 0.24)},
		{"n": "Hat", "v": 0.61, "p": 0.63, "c": Color(0.84, 0.74, 0.3)},
		{"n": "OH L/R", "v": 0.67, "p": 0.5, "c": Color(0.55, 0.72, 0.35)},
		{"n": "Bass DI", "v": 0.74, "p": 0.5, "c": Color(0.33, 0.66, 0.6)},
		{"n": "Rhodes", "v": 0.69, "p": 0.38, "c": Color(0.35, 0.56, 0.82)},
		{"n": "Gtr Amp", "v": 0.71, "p": 0.66, "c": Color(0.55, 0.45, 0.82)},
		{"n": "Lead Vox", "v": 0.80, "p": 0.5, "c": Color(0.82, 0.42, 0.66)},
		{"n": "Vox Dbl", "v": 0.55, "p": 0.3, "c": Color(0.74, 0.46, 0.74)},
		{"n": "Strings", "v": 0.64, "p": 0.5, "c": Color(0.46, 0.62, 0.78)},
		{"n": "Drum Bus", "v": 0.76, "p": 0.5, "c": Color(0.6, 0.6, 0.64)},
		{"n": "Verb Rtn", "v": 0.58, "p": 0.5, "c": Color(0.42, 0.68, 0.72)},
	]
	for i in demo.size():
		var d: Dictionary = demo[i]
		var t := state.track(i + 1)
		t.name = d["n"]
		t.volume = d["v"]
		t.volume_db = ReaperState.taper_to_db(d["v"])
		t.pan = d["p"]
		t.colour = d["c"]
		t.vu_l = 0.0
		t.vu_r = 0.0
	# A master sitting a little under unity, which is what a mix that has been balanced looks
	# like and what makes the master fader visibly NOT at the top of its travel.
	state.master.volume = 0.69
	state.master.volume_db = ReaperState.taper_to_db(0.69)

	state.track(1).rec_arm = true
	state.track(8).rec_arm = true
	state.track(3).mute = true
	state.track(8).solo = true

	# A couple of FX chains, so the racks have something to stand for.
	for spec in [[1, "ReaEQ", ["Freq", "Gain", "Q", "Type"]], [1, "ReaComp", ["Thresh", "Ratio", "Attack", "Release"]],
			[5, "ReaComp", ["Thresh", "Ratio", "Attack", "Release"]], [8, "ReaEQ", ["Freq", "Gain", "Q", "Type"]],
			[8, "ReaVerbate", ["Size", "Damping", "Wet", "Dry"]], [12, "ReaVerbate", ["Size", "Damping", "Wet", "Dry"]]]:
		var track_index: int = spec[0]
		var f := state.fx(track_index, state.track(track_index).fx.size())
		f.name = spec[1]
		var names: Array = spec[2]
		for pi in names.size():
			f.param_names[pi] = names[pi]
			f.params[pi] = 0.3 + 0.5 * fmod(float(track_index * 7 + pi * 3) / 11.0, 1.0)

	# Sends into the reverb return, so the patchbay has real cables.
	for src in [2, 6, 8, 10]:
		var s := state.send(src, 0)
		s.dest_name = "Verb Rtn"
		s.volume = 0.4 + 0.1 * src / 10.0

	state.tempo = 92.0
	state.position_string = "17.1.00"
	state.playing = true
	# The stand-in mix is ROLLING. A still studio photographs as a dead one: meters dark, reels
	# stopped, every LED off. That is an accurate picture of nothing happening and a useless one
	# for judging whether the gear reads as gear.
	set_process(true)
	connection_changed.emit()


## Synthesise meter movement and a clock for the offline stand-in.
##
## Deliberately crude -- per-track phase offsets over a shared bar clock, so the drums hit
## together and the pads sit still. Anything more elaborate would be a music generator, and the
## only question this has to answer is whether twelve meters moving at once look like a mix.
func _drive_offline_meters(delta: float) -> void:
	state.position_seconds += delta
	var beats := state.position_seconds * state.tempo / 60.0
	state.position_string = "%d.%d.%02d" % [int(beats / 4.0) + 1, int(fmod(beats, 4.0)) + 1, int(fmod(beats, 1.0) * 100.0)]

	var bus_l := 0.0
	var bus_r := 0.0
	for index in state.track_indices():
		var t: ReaperState.TrackState = state.tracks[index]
		if t.mute:
			t.vu_l = 0.0
			t.vu_r = 0.0
			continue
		var phase := fmod(beats + index * 0.37, 4.0)
		var hit := exp(-phase * 2.2) if index <= 4 else 0.45 + 0.35 * sin(beats * 0.8 + index)
		var level := clampf(t.volume * (0.18 + 0.8 * hit), 0.0, 1.0)
		t.vu_l = level
		t.vu_r = clampf(level * (1.0 - 0.18 * absf(t.pan - 0.5)), 0.0, 1.0)
		# Pushed straight into the volatile buffer. These never go through _apply -- that is
		# deliberate, since meters are written to the cache without a signal to avoid fanning a
		# storm out to every surface -- but a guest watching a hosted demo should still see
		# meters move, so the one thing _apply would have done for them is done here.
		# Summed as power rather than added, which is what keeps twelve tracks at a sensible
		# level from pinning the bus at 1.0 the moment the mix has more than a few things in it.
		bus_l += t.vu_l * t.vu_l
		bus_r += t.vu_r * t.vu_r
		if mode != Mode.GUEST:
			_repl_volatile["/track/%d/vu/L" % index] = [t.vu_l]
			_repl_volatile["/track/%d/vu/R" % index] = [t.vu_r]

	var m := state.master
	m.vu_l = clampf(sqrt(bus_l) * m.volume * 0.46, 0.0, 1.0)
	m.vu_r = clampf(sqrt(bus_r) * m.volume * 0.46, 0.0, 1.0)
	if mode != Mode.GUEST:
		_repl_volatile["/master/vu/L"] = [m.vu_l]
		_repl_volatile["/master/vu/R"] = [m.vu_r]
		_repl_volatile["/time/str"] = [state.position_string]
	state.transport_changed.emit()
