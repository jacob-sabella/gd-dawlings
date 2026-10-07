class_name ReaperBackend
extends DAWBackend

## Reaper, over OSC, plus a ReaScript bridge for the things OSC cannot say.
##
## Everything Reaper-specific in this project is here or in its three neighbours (osc.gd,
## osc_peer.gd, script_bridge.gd). The surfaces above know about tracks and faders; the
## translation into `/track/3/volume` happens at this line and nowhere above it. A second DAW
## is a sibling of this file -- see core/daw/daw_backend.gd for the contract it would meet.
##
## ONE LINK PER SESSION, ALWAYS. If three headsets and a laptop each opened their own OSC
## socket, Reaper would broadcast every change to all four, each would apply it locally, and a
## grabbed fader would fight its own echo three times over. The session's host runs this; its
## guests run nothing and receive replicated state. Reaper itself remains the truth above even
## that.

## How many tracks and parameters the device asks Reaper to stream. Sent on connect; Reaper
## otherwise uses whatever the pattern file declares, which defaults to 8 tracks -- a console
## that silently stops at channel 8 on a 30-track project.
const BANK_TRACKS := 64
const BANK_FX_PARAMS := 32
const BANK_SENDS := 8

var _peer: OSCPeer = null
var _bridge: ScriptBridge = null
## Addresses this process wrote within the last few frames, with the value it wrote. Reaper
## echoes every change back, so without this a fader snaps to a stale value for one frame on
## every single drag update -- visible as a fader that fights the hand holding it.
var _echo_guard: Dictionary = {}
const ECHO_GRACE_MSEC := 250


func _ready() -> void:
	# An autoload that opens a socket on startup would make `godot --headless` in CI try to talk
	# to a DAW. Nothing happens until a scene asks for it.
	set_process(false)


## `options`: host (String), send_port (int), listen_port (int). Reaper's own OSC defaults are
## 8000 out and 9000 in, which are the numbers in its device dialog -- a mismatch here is the
## first thing to check when the link stays silent. See docs/transport.md.
func open(options: Dictionary = {}) -> bool:
	close()
	_peer = OSCPeer.new()
	var reaper_host: String = options.get("host", "127.0.0.1")
	var send_port: int = options.get("send_port", 8000)
	var listen_port: int = options.get("listen_port", 9000)
	if _peer.open(reaper_host, send_port, listen_port) != OK:
		_peer = null
		return false
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


func close() -> void:
	if _peer:
		_peer.close()
		_peer = null
	if _bridge:
		_bridge.close()
		_bridge = null
	set_process(false)
	connection_changed.emit()


func is_live() -> bool:
	return _peer != null and _peer.packets_received > 0


func summary() -> String:
	if _peer == null:
		return "reaper: socket closed"
	if _peer.packets_received == 0:
		return "reaper: listening, nothing heard yet"
	var age := (Time.get_ticks_msec() - _peer.last_receive_msec) / 1000.0
	return "reaper: %d in / %d out, last %.1fs ago" % [_peer.packets_received, _peer.packets_sent, age]


## Routing is the one thing Reaper's OSC cannot express at all, so it depends entirely on the
## ReaScript bridge being up. Reported honestly rather than discovered when a drop does nothing.
func can(capability: StringName) -> bool:
	if capability == Capability.ROUTING:
		return _bridge != null and _bridge.is_open()
	return true


func _process(delta: float) -> void:
	if _bridge:
		_bridge.poll()
	if _peer:
		for m in _peer.poll():
			_apply(m["address"], m["args"])

	tick_replication(delta)

	var now := Time.get_ticks_msec()
	for key in _echo_guard.keys():
		if now - int(_echo_guard[key]["t"]) > ECHO_GRACE_MSEC:
			_echo_guard.erase(key)


# --- inbound ------------------------------------------------------------------------------

## Reaper speaks the project's own mix vocabulary almost exactly -- see core/daw/mix_wire.gd
## for why that is not a coincidence -- so inbound parsing is a delegation rather than a second
## implementation. What stays here is the part that IS Reaper's: the echo guard.
func _apply(address: String, args: Array) -> void:
	if _is_echo(address, args):
		return
	record_for_replication(address, args)
	MixWire.apply(state, address, args)


# --- outbound -----------------------------------------------------------------------------

## Every outbound Reaper message funnels through here. A guest never reaches it -- its writes
## are routed to the session host one layer up, in core/daw/daw.gd -- so this only ever runs on
## the participant that owns the socket.
func write(address: String, args: Array = []) -> void:
	if _peer == null:
		# No socket: apply locally so the studio still responds to being touched with Reaper
		# absent. Without it, development and every screenshot would show dead controls.
		_apply(address, args)
		return
	_echo_guard[address] = {"v": args, "t": Time.get_ticks_msec()}
	_peer.send(address, args)


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
func snapshot() -> Array:
	return MixWire.snapshot(state)


func apply_replicated(batch: Array) -> void:
	MixWire.apply_replicated(state, batch)
