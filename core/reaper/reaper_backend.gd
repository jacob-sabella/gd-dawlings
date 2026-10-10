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
## Plugin windows on show, closed with the link.
var _windows: Array[ReaperPluginWindow] = []
## Addresses this process wrote within the last few frames, with the value it wrote. Reaper
## echoes every change back, so without this a fader snaps to a stale value for one frame on
## every single drag update -- visible as a fader that fights the hand holding it.
var _echo_guard: Dictionary = {}
const ECHO_GRACE_MSEC := 250

## How often to re-read the arrangement off the bridge.
##
## Two seconds, not a frame: this is a file round trip through a deferred ReaScript, and the
## answer is the whole arrangement rather than a delta. It is also not edge-triggered -- Reaper
## has no notification for "an item moved" on any channel this project can reach -- so a poll
## is the only honest option, and the rate is a straight trade between latency on someone
## else's edit and load on a project with a few thousand items.
const TIMELINE_POLL_SECONDS := 2.0

## How often to re-read the project's SHAPE off the bridge.
##
## Eight seconds against the timeline's two, because the two change on completely different
## clocks: the arrangement moves on every drag of every item, while colour, folder structure and
## routing change when a person reaches for them. This is the slow channel in the system and the
## answer is the whole project, so the request asks for the LIGHT form -- plugin names and
## bypasses but no parameter values, which OSC is already streaming continuously.
const STRUCTURE_POLL_SECONDS := 8.0

var _timeline_due := 0.0
var _timeline_in_flight := false
var _timeline_epoch := 0
var _edits_in_flight := 0
var _structure_due := 0.0
## Wet addresses written from here, and when: see `set_fx_wet`.
var _wet_written := {}
## The same for parameters: when each was last written from here, by address.
var _param_written := {}
const WET_SETTLE_MSEC := 2000
var _structure_in_flight := false
## Seconds after `open` at which to ask Reaper for its whole state again. See `open`.
var _refresh_after: Array = []
var _refresh_clock := 0.0
## What Reaper has said and this has not yet applied, oldest first, and how far through it is.
##
## A control-surface refresh is fifty thousand messages arriving at once -- every parameter of
## every plugin in the bank -- and applied in one frame they froze the room for two seconds.
## They are applied a few milliseconds' worth a frame instead, so a busy project settles over a
## handful of frames rather than stopping the world while it does.
var _inbox: Array[Dictionary] = []
var _inbox_at := 0
const APPLY_BUDGET_USEC := 6000


## Shorter than this, a fade Reaper reports is its own default anti-click fade, not one anyone made.
const FADE_FLOOR := 0.011

func _ready() -> void:
	# An autoload that opens a socket on startup would make `godot --headless` in CI try to talk
	# to a DAW. Nothing happens until a scene asks for it.
	set_process(false)


## `options`: host (String), send_port (int), listen_port (int). Reaper's own OSC defaults are
## 8000 out and 9000 in, which are the numbers in its device dialog -- a mismatch here is the
## first thing to check when the link stays silent. See docs/transport.md.
## Reaper action 41743, "Control surface: Refresh all surfaces".
const REFRESH_SURFACES := 41743


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
	# A Reaper on its own resource path (tools/reaper_rig.sh, or a portable install) keeps
	# its bridge drop there too.
	_bridge.open(options.get("bridge_dir", ScriptBridge.DEFAULT_DIR))
	set_process(true)

	# Tell Reaper how wide this surface is, then ask for a full resend. Without the resend a
	# client that connects after Reaper has started sees nothing until something moves, which
	# looks exactly like a broken link.
	_peer.send("/device/track/count", [BANK_TRACKS])
	_apply("/bank", [0, BANK_TRACKS])
	_peer.send("/device/fxparam/count", [BANK_FX_PARAMS])
	_peer.send("/device/send/count", [BANK_SENDS])
	_peer.send("/device/track/bank/select", [1])
	# And then ask for everything. Reaper sends a surface its whole state when the surface
	# starts and when its bank changes -- never because a client turned up. Selecting bank 1
	# when bank 1 is already selected changes nothing, so a desk opened against a Reaper that
	# was already running came up with whatever trickled in: meters, and almost no names.
	# "Control surface: Refresh all surfaces" is the one message that makes it start over.
	_peer.send("/action", [REFRESH_SURFACES])
	# And again once the app is running. Asked only here, in `open` -- before the studio and
	# the window exist -- a desktop launch received twelve packets of the dump and then
	# nothing, because a stopped Reaper has nothing more to say: four names out of forty, every
	# time. A headless client asking at the same moment gets the lot, even with its main
	# thread stalled, so where the rest goes is not pinned down; asking again once the frames
	# are running is what was measured to fix it.
	_refresh_after = [0.5, 2.5]
	_refresh_clock = 0.0
	connection_changed.emit()
	return true


func close() -> void:
	for w in _windows:
		w.close()
	_windows.clear()
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
	if capability == Capability.TRACK_BANKING:
		# Reaper can always be told to move its bank. Whether this surface should offer a
		# button for it depends on knowing the project is bigger than the bank, and only the
		# ReaScript bridge can say that -- a page-forward button that cannot tell you whether
		# there is anything to page to is worse than no button.
		return _bridge != null and _bridge.is_open()
	if capability == Capability.MARKERS:
		# OSC can go to a marker but not make one; the bridge does that.
		return _bridge != null and _bridge.is_open()
	if capability == Capability.TIMELINE:
		# Reaper's OSC surface has no message about media items at all, so this is exactly as
		# true as the ReaScript bridge is loaded. Without it the timeline says it cannot see
		# the arrangement instead of drawing a project with nothing in it.
		return _bridge != null and _bridge.is_open()
	if capability == Capability.FX_CHAIN or capability == Capability.FX_PRESETS:
		# OSC can turn a plugin's knobs but cannot pick it up or name its presets.
		return _bridge != null and _bridge.is_open()
	if capability == Capability.PLUGIN_WINDOW:
		# The bridge opens the window; the display is where it is read from.
		return _bridge != null and _bridge.is_open() and ReaperPluginWindow.available()
	if capability == Capability.MIDI_TAKES or capability == Capability.AUDIO_TAKES:
		# OSC can play notes into Reaper but cannot make an item; only ReaScript can.
		return _bridge != null and _bridge.is_open()
	if capability == Capability.PROJECT_FILES:
		# Reaper's files are on Reaper's machine, opened by Reaper's own dialogs.
		return false
	return true


## Reaper saves its own project, in its own format, where it already is: "File: Save project".
func save_project(path: String) -> PackedStringArray:
	if not path.is_empty():
		return PackedStringArray(["Reaper saves its project where Reaper keeps it; use Save As in Reaper"])
	if _peer == null:
		return PackedStringArray(["Reaper is not connected"])
	_peer.send("/action", [SAVE_ACTION])
	return PackedStringArray()


func _process(delta: float) -> void:
	if _peer and not _refresh_after.is_empty():
		# Clamped: the first frame after a long build reports the whole build as its delta.
		_refresh_clock += minf(delta, 0.1)
		if _refresh_clock >= float(_refresh_after[0]):
			_refresh_after.pop_front()
			_peer.send("/action", [REFRESH_SURFACES])
	if _bridge:
		_bridge.poll()
		_poll_timeline(delta)
		_poll_structure(delta)
	if _peer:
		_inbox.append_array(_peer.poll())
		_apply_inbox()

	tick_replication(delta)

	var now := Time.get_ticks_msec()
	for key in _echo_guard.keys():
		if now - int(_echo_guard[key]["t"]) > ECHO_GRACE_MSEC:
			_echo_guard.erase(key)


# --- inbound ------------------------------------------------------------------------------

func catching_up() -> bool:
	return _inbox_at < _inbox.size()


## Apply what has arrived, oldest first, until this frame's share of time is spent. Checked
## every few dozen messages rather than every one: reading the clock is not free either.
func _apply_inbox() -> void:
	var until := Time.get_ticks_usec() + APPLY_BUDGET_USEC
	while _inbox_at < _inbox.size():
		var m := _inbox[_inbox_at]
		_inbox_at += 1
		_apply(m["address"], m["args"])
		if _inbox_at % 32 == 0 and Time.get_ticks_usec() > until:
			break
	if _inbox_at >= _inbox.size():
		_inbox.clear()
		_inbox_at = 0


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
	# And into the cache now, not when Reaper answers. The echo guard drops Reaper's answer when
	# it agrees with what was sent -- which is the point of it, a fader must not fight its own
	# echo -- so without this the cache never learnt a write the desk made: the control showed
	# it, and every OTHER view of the same track (the second participant, the timeline's mute
	# flag, the hover readout) went on showing the old value.
	record_for_replication(address, args)
	MixWire.apply(state, address, args)


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


## Reaper takes the mode as a float on the same address it reports it on -- seen on the rig: 2.0
## set auto and came back as 2.0, and writing the mode it already had brings no answer.
func set_track_monitor(index: int, mode: int) -> void:
	write("/track/%d/monitor" % index, [float(mode)])


func set_fx_param(track_index: int, fx_index: int, param: int, value: float) -> void:
	if param <= BANK_FX_PARAMS:
		_param_written["/track/%d/fx/%d/fxparam/%d/value" % [track_index, fx_index, param]] = Time.get_ticks_msec()
		write("/track/%d/fx/%d/fxparam/%d/value" % [track_index, fx_index, param], [clampf(value, 0.0, 1.0)])
		return
	# Past the parameters OSC carries: by the bridge, into the cache at once like any write, and
	# the time noted so a page read already on its way does not drag the knob back.
	var address := "/track/%d/fx/%d/fxparam/%d/value" % [track_index, fx_index, param]
	_param_written[address] = Time.get_ticks_msec()
	record_for_replication(address, [clampf(value, 0.0, 1.0)])
	MixWire.apply(state, address, [clampf(value, 0.0, 1.0)])
	if _bridge != null and _bridge.is_open():
		_bridge.call_reaper("SetFxParam", [track_index, fx_index, param, clampf(value, 0.0, 1.0)])


## The plugin's floating window, opened by the bridge and read off the display. The bridge says
## what the window's title is and whether it was open already; one that was is left open when
## this is closed, because somebody at Reaper opened it and is perhaps looking at it.
func open_plugin_window(track_index: int, fx_index: int) -> PluginWindow:
	if not can(Capability.PLUGIN_WINDOW):
		return null
	var was := {"answered": false, "open": false}
	var bridge := _bridge
	var hide := func() -> void:
		if not was["open"] and bridge != null and bridge.is_open():
			bridge.call_reaper("ShowFx", [track_index, fx_index, false])
	var w := ReaperPluginWindow.opening(func() -> void:
		if was["answered"]:
			hide.call())
	_bridge.call_reaper("ShowFx", [track_index, fx_index, true], func(result) -> void:
		was["answered"] = true
		if typeof(result) != TYPE_DICTIONARY or not result.get("ok", false):
			w.close()
			return
		was["open"] = bool(result.get("was_open", false))
		if not w.is_open():
			# Put away before Reaper had even opened it.
			hide.call()
			return
		w.start(str(result.get("title", ""))))
	for o in _windows.duplicate():
		if not o.is_open():
			_windows.erase(o)
	_windows.append(w)
	return w


## A plugin's real parameters (no params named), or a page of them: values, names and the
## plugin's own words, onto the addresses OSC would have used, so they replicate like the rest.
func read_fx_params(track_index: int, fx_index: int, params: Array) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	var at := "/track/%d/fx/%d" % [track_index, fx_index]
	if params.is_empty():
		_bridge.call_reaper("ListFxParams", [track_index, fx_index], func(result) -> void:
			if typeof(result) != TYPE_DICTIONARY or not result.get("ok", false):
				return
			var listed := _as_array(result.get("params", []))
			for entry in listed:
				_apply("%s/fxparam/%d/name" % [at, int(entry["index"])], [str(entry["name"])])
			_apply("%s/paramlist" % at, listed.map(func(e): return float(e["index"]))))
		return
	_bridge.call_reaper("GetFxParams", [track_index, fx_index] + params, func(result) -> void:
		if typeof(result) != TYPE_DICTIONARY or not result.get("ok", false):
			return
		var now := Time.get_ticks_msec()
		for entry in _as_array(result.get("params", [])):
			var p := "%s/fxparam/%d" % [at, int(entry["index"])]
			if now - int(_param_written.get(p + "/value", -WET_SETTLE_MSEC)) >= WET_SETTLE_MSEC:
				_apply(p + "/value", [float(entry["value"])])
			_apply(p + "/name", [str(entry["name"])])
			_apply(p + "/value/str", [str(entry["text"]), float(entry["value"])]))


func read_fx_param_text(track_index: int, fx_index: int, param: int) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_bridge.call_reaper("GetParamText", [track_index, fx_index, param], func(result) -> void:
		if typeof(result) == TYPE_DICTIONARY and result.has("text"):
			_apply("/track/%d/fx/%d/fxparam/%d/value/str" % [track_index, fx_index, param],
					[str(result["text"]), float(result.get("value", -1.0))]))


## A plugin's wet/dry is not one of its parameters as OSC numbers them, so it goes by the bridge.
## Into the cache at once, like any write, and the time noted: the slow structure poll reports
## the wet too, and an answer read before this write must not drag the knob back.
func set_fx_wet(track_index: int, fx_index: int, wet: float) -> void:
	var address := "/track/%d/fx/%d/wet" % [track_index, fx_index]
	_wet_written[address] = Time.get_ticks_msec()
	record_for_replication(address, [clampf(wet, 0.0, 1.0)])
	MixWire.apply(state, address, [clampf(wet, 0.0, 1.0)])
	if _bridge != null and _bridge.is_open():
		_bridge.call_reaper("SetFxWet", [track_index, fx_index, clampf(wet, 0.0, 1.0)])


func step_fx_preset(track_index: int, fx_index: int, direction: int) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_bridge.call_reaper("StepFxPreset", [track_index, fx_index, signi(direction)], func(result) -> void:
		if typeof(result) == TYPE_DICTIONARY and result.has("preset"):
			_apply("/track/%d/fx/%d/preset" % [track_index, fx_index], [str(result["preset"])]))


## Reaper renumbers both chains, and OSC restates what it sees; the structure poll is asked for
## at once so the slot counts -- which only it knows -- arrive with them rather than eight
## seconds later.
func move_fx(from_track: int, fx_index: int, to_track: int, to_fx: int, copy: bool) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_bridge.call_reaper("MoveFx", [from_track, fx_index, to_track, to_fx, copy],
			func(_result) -> void: _structure_due = 0.0)


func create_sidechain(from_track: int, to_track: int) -> bool:
	if _bridge == null or not _bridge.is_open():
		return false
	return _bridge.call_reaper("CreateSidechain", [from_track, to_track],
			func(_result) -> void: _structure_due = 0.0)


## Both are on Reaper's own OSC surface (TRACK_SEND_VOLUME, TRACK_SEND_PAN), numbered from 1 as
## the bridge's sends are not -- see `_on_structure`.
func set_send_volume(track_index: int, send_index: int, taper: float) -> void:
	write("/track/%d/send/%d/volume" % [track_index, send_index], [clampf(taper, 0.0, 1.0)])


func set_send_pan(track_index: int, send_index: int, pan: float) -> void:
	write("/track/%d/send/%d/pan" % [track_index, send_index], [clampf(pan, 0.0, 1.0)])


func set_fx_enabled(track_index: int, fx_index: int, enabled: bool) -> void:
	write("/track/%d/fx/%d/bypass" % [track_index, fx_index], [1.0 if enabled else 0.0])


## Reaper is addressed in whole banks, not in tracks: `/device/track/bank/select 2` with a bank
## of 64 means "show me tracks 65 to 128". An offset that is not a multiple of the bank width
## therefore cannot be asked for, and is rounded down rather than silently ignored.
func set_track_bank(offset: int) -> void:
	if _peer == null:
		return
	var bank := int(floor(float(maxf(offset, 0)) / float(BANK_TRACKS)))
	_peer.send("/device/track/bank/select", [bank + 1])
	# Stated locally rather than waited for. Reaper acknowledges a bank change by re-sending
	# the tracks in it and never by naming the bank, so nothing would ever tell this cache that
	# its indices now mean something else.
	_apply("/bank", [bank * BANK_TRACKS, BANK_TRACKS])


func transport_play() -> void:
	write("/play", [1.0])


func transport_stop() -> void:
	write("/stop", [1.0])


func transport_record() -> void:
	write("/record", [1.0])


## `/tempo/raw` takes beats per minute as a plain number, unlike `/tempo`, which is normalised
## over a range Reaper does not publish.
func set_tempo(bpm: float) -> void:
	write("/tempo/raw", [bpm])


func set_looping(on: bool) -> void:
	# A toggle on Reaper's side, and a toggle is a button: 1 is the press that flips it and 0 is
	# the release, which Reaper ignores -- so "/repeat 0" never turned looping off. It is only
	# sent when it would change something, always as a press, and the cache is told the value
	# that press is for rather than the press itself.
	if state.looping == on:
		return
	var value := [1.0 if on else 0.0]
	if _peer != null:
		_echo_guard["/repeat"] = {"v": value, "t": Time.get_ticks_msec()}
		_peer.send("/repeat", [1.0])
	record_for_replication("/repeat", value)
	MixWire.apply(state, "/repeat", value)


## The same kind of toggle as /repeat, checked against the rig: `/click 1` flips the metronome,
## `/click 0` does nothing at all, and Reaper answers with the state it landed on. So a press is
## sent only when it would change something, and the cache is told the value it is for.
func set_metronome(on: bool) -> void:
	if state.metronome == on:
		return
	var value := [1.0 if on else 0.0]
	if _peer != null:
		_echo_guard["/click"] = {"v": value, "t": Time.get_ticks_msec()}
		_peer.send("/click", [1.0])
	record_for_replication("/click", value)
	MixWire.apply(state, "/click", value)


func seek(seconds: float) -> void:
	write("/time", [maxf(seconds, 0.0)])
	_apply("/time", [maxf(seconds, 0.0)])


func set_loop_range(start: float, end: float) -> void:
	write("/loop/start/time", [start])
	write("/loop/end/time", [end])
	_apply("/loop/start/time", [start])
	_apply("/loop/end/time", [end])


## Reaper's own Edit: Undo and Edit: Redo, so what is undone is whatever Reaper's history says
## was last -- a fader move made on this desk, an edit made with a mouse in Reaper, either.
const UNDO_ACTION := 40029
const REDO_ACTION := 40030
## "File: Save project".
const SAVE_ACTION := 40026


func undo() -> void:
	if _peer != null:
		_peer.send("/action", [UNDO_ACTION])
	# Whatever came back may be an edit, and the timeline is only polled every two seconds.
	_timeline_due = minf(_timeline_due, 0.15)


func redo() -> void:
	if _peer != null:
		_peer.send("/action", [REDO_ACTION])
	_timeline_due = minf(_timeline_due, 0.15)


# --- editing ------------------------------------------------------------------------------
#
# OSC has no message for an item, so every edit goes through the bridge. Each is shown on the
# cache at once (see DAWBackend) and Reaper's own answer arrives with the next timeline poll,
# which an edit brings forward.

func select_item(track_index: int, item_index: int, additive: bool) -> void:
	_locally_select(track_index, item_index, additive)
	_edit("SelectItem", [track_index, item_index, additive])


func clear_item_selection() -> void:
	_locally_clear_selection()
	_edit("ClearItemSelection", [])


func move_item(track_index: int, item_index: int, start: float) -> void:
	_locally_move(track_index, item_index, start)
	_edit("MoveItem", [track_index, item_index, start])


func split_selected(seconds: float) -> void:
	_locally_split(seconds)
	_edit("SplitSelected", [seconds])


func delete_selected() -> void:
	_locally_delete_selected()
	_edit("DeleteSelected", [])


func duplicate_selected() -> void:
	_locally_duplicate_selected()
	_edit("DuplicateSelected", [])


func trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	_locally_trim(track_index, item_index, start, end)
	_edit("TrimItem", [track_index, item_index, start, end])


func set_item_gain(track_index: int, item_index: int, db: float) -> void:
	_locally_shape(track_index, item_index, db, NAN, NAN)
	_edit("SetItemGain", [track_index, item_index, db])


func set_item_fades(track_index: int, item_index: int, fade_in: float, fade_out: float) -> void:
	_locally_shape(track_index, item_index, NAN, fade_in, fade_out)
	_edit("SetItemFades", [track_index, item_index, fade_in, fade_out])


func transpose_item(track_index: int, item_index: int, semitones: int) -> void:
	if _locally_transpose(track_index, item_index, semitones):
		_edit("TransposeItem", [track_index, item_index, semitones])


## Reaper quantises against its own tempo map, so a song with tempo changes comes back right from
## the next timeline even where the preview, at one tempo, was not.
func quantize_item(track_index: int, item_index: int, grid_beats: float, strength: float) -> void:
	if _locally_quantize(track_index, item_index, grid_beats, strength):
		_edit("QuantizeItem", [track_index, item_index,
				clampf(grid_beats, QUANTIZE_GRID_MIN, QUANTIZE_GRID_MAX), clampf(strength, 0.0, 1.0)])


## Shown on the cache at once, like an item edit, and confirmed by the timeline poll the edit
## brings forward.
func add_marker(seconds: float, marker_name: String) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	var markers: Dictionary = state.markers.duplicate()
	markers[seconds] = marker_name
	_write_markers(markers)
	_edit("AddMarker", [seconds, marker_name])


## A take, as one bridge call: a MIDI item created at `start` and filled note by note, inside one
## undo block. Shown on the cache at once like every other edit; the next timeline poll brings
## back Reaper's own copy, notes and all.
func insert_midi_take(track_index: int, start: float, end: float, notes: Array,
		take_name: String) -> void:
	if _bridge == null or not _bridge.is_open():
		push_warning("insert_midi_take needs the ReaScript bridge; OSC cannot create an item.")
		return
	_locally_insert_take(track_index, start, end, notes, take_name)
	_edit("InsertMidiTake", midi_take_request(track_index, start, end, notes, take_name))


## The file, by its absolute path, since Reaper is on this machine; the bridge copies it into a
## saved project's media folder. Shown on the cache at once, like every edit.
func insert_audio_take(track_index: int, start: float, source: String, length: float,
		peaks: PackedByteArray, take_name: String) -> void:
	if _bridge == null or not _bridge.is_open():
		push_warning("insert_audio_take needs the ReaScript bridge; OSC cannot create an item.")
		return
	_locally_insert_audio(track_index, start, source, length, peaks, take_name)
	var path := ProjectSettings.globalize_path(AudioTake.DIR.path_join(source))
	_edit("InsertAudioTake", [track_index, start, path, MidiTake.clean_name(take_name)])


## The bridge's argument list for a take. Flat, because the bridge's request decoder reads one
## flat list of numbers and strings: track, start, end, name, note count, then five numbers per
## note -- on and off in project seconds, pitch, velocity, channel.
static func midi_take_request(track_index: int, start: float, end: float, notes: Array,
		take_name: String) -> Array:
	var out: Array = [track_index, start, end, MidiTake.clean_name(take_name), notes.size()]
	for n in notes:
		out.append_array([float(n[0]), float(n[1]), int(n[2]), int(n[3]), int(n[4])])
	return out


## Send one edit, and keep the timeline poll from undoing it on screen.
##
## A GetTimeline already on its way when the edit is made can come back with the lanes as they
## were, and laying that over the cache would snap the block back to where it was dragged from
## until the next poll. So polls wait while any edit is outstanding, and an answer to a poll that
## was sent before the latest edit is thrown away.
func _edit(fn: String, args: Array) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_timeline_epoch += 1
	_edits_in_flight += 1
	_bridge.call_reaper(fn, args, func(_result) -> void:
		_edits_in_flight -= 1
		_timeline_due = 0.0)


## Routing changes have no OSC pattern -- Reaper streams send VOLUMES but has no message for
# --- the arrangement ----------------------------------------------------------------------

func _poll_timeline(delta: float) -> void:
	if not _bridge.is_open() or _timeline_in_flight:
		return
	_timeline_due -= delta
	if _timeline_due > 0.0 or _edits_in_flight > 0:
		return
	_timeline_due = TIMELINE_POLL_SECONDS
	_timeline_in_flight = _bridge.call_reaper("GetTimeline", [],
			_on_timeline.bind(_timeline_epoch))


## Applied through `_apply` rather than written onto the cache, so the arrangement rides the
## normal replication stream and a guest gets it without a second code path.
func _on_timeline(result, asked_at_epoch := -1) -> void:
	_timeline_in_flight = false
	if result == null or typeof(result) != TYPE_DICTIONARY:
		return
	if asked_at_epoch >= 0 and asked_at_epoch != _timeline_epoch:
		# Asked before the latest edit; see _edit.
		_timeline_due = 0.0
		return

	# Every lane is cleared first and then refilled. The bridge omits tracks with nothing on
	# them -- see the Lua -- so a track whose last item was just deleted is reported by its
	# ABSENCE, and a merge would leave that item on screen forever.
	var lanes: Dictionary = {}
	for entry in _as_array(result.get("tracks", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var idx := int(entry.get("index", 0))
		if idx <= 0:
			continue
		var packed: Array = []
		for item in _as_array(entry.get("items", [])):
			if typeof(item) != TYPE_DICTIONARY:
				continue
			packed.append_array([
				float(item.get("start", 0.0)),
				float(item.get("length", 0.0)),
				1.0 if item.get("muted", false) else 0.0,
				str(item.get("name", "")),
				1.0 if item.get("selected", false) else 0.0,
			])
			# A MIDI item's notes, relative to its start; see the bridge's GetTimeline.
			var notes = item.get("notes", [])
			if notes is Array and not notes.is_empty():
				packed.append(PackedFloat32Array(notes))
			# One of the takes recorded through this desk: its file and its overview, so it
			# is drawn as the sound it is wherever Reaper has put it since.
			var source := str(item.get("source", "")).get_file()
			var extra := {}
			if take_peaks.has(source):
				extra = {"source": source, "offset": float(item.get("offset", 0.0)),
						"peaks": take_peaks[source]}
			# The item's fades and its own volume, which the desk can change too.
			var gain := float(item.get("gain", 1.0))
			var shape := {"fade_in": float(item.get("fade_in", 0.0)), "fade_out": float(item.get("fade_out", 0.0)),
					"gain_db": linear_to_db(gain) if gain > 0.0 else DAWBackend.ITEM_GAIN_MIN}
			# Reaper's default fade is a few milliseconds on every item; under that is no fade.
			if shape["fade_in"] > FADE_FLOOR or shape["fade_out"] > FADE_FLOOR or absf(shape["gain_db"]) > 0.001:
				extra.merge(shape)
			if not extra.is_empty():
				packed.append(extra)
		lanes[idx] = packed

	for index in state.track_indices():
		var packed: Array = lanes.get(index, [])
		if packed.is_empty() and state.track(index).items.is_empty():
			continue
		_apply("/track/%d/items" % index, packed)

	var markers: Array = []
	for m in _as_array(result.get("markers", [])):
		if typeof(m) == TYPE_DICTIONARY:
			markers.append_array([float(m.get("position", 0.0)), str(m.get("name", ""))])
	_apply("/timeline/markers", markers)
	_apply("/timeline/length", [float(result.get("length", 0.0))])
	# The only channel that knows how big the project actually is. OSC reports the bank and
	# nothing else, so without this a 90-track session is indistinguishable from a 64-track one.
	if result.has("track_count"):
		_apply("/project/tracks", [int(result["track_count"])])


# --- the project's shape ------------------------------------------------------------------

func _poll_structure(delta: float) -> void:
	if not _bridge.is_open() or _structure_in_flight:
		return
	_structure_due -= delta
	if _structure_due > 0.0:
		return
	_structure_due = STRUCTURE_POLL_SECONDS
	# 1 == light; see the Lua.
	_structure_in_flight = _bridge.call_reaper("GetProjectStructure", [1], _on_structure)


## The three things OSC cannot say.
##
## Colour, folder depth and a send's destination INDEX are each a property Reaper will hand over
## for the asking and will never volunteer on its control surface. Everything here goes through
## `_apply` onto addresses the wire already understands, so it rides the normal replication
## stream and a guest gets all of it without a second code path -- which is exactly what the
## "colour" case in mix_wire.gd was written in anticipation of.
##
## Nothing here touches volume, pan, mute, solo or FX parameters, even though the bridge reports
## some of them. Those arrive over OSC at 30Hz and are the authority; writing an eight-second-old
## copy over the top of them would make every fader stutter backwards once per poll.
func _on_structure(result) -> void:
	_structure_in_flight = false
	if result == null or typeof(result) != TYPE_DICTIONARY:
		return

	var seen := 0
	for entry in _as_array(result.get("tracks", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var idx := int(entry.get("index", 0))
		if idx <= 0:
			continue
		seen += 1

		var colour = entry.get("colour", null)
		if colour is Array and colour.size() >= 3:
			# Reaper hands back pure black for a track whose colour has never been set, and
			# black is not a colour -- it is the absence of one, and painting a chip with it
			# makes an unassigned track look deliberately marked. Left at the default grey.
			var c := Color(float(colour[0]), float(colour[1]), float(colour[2]))
			if c.r + c.g + c.b > 0.02:
				_apply("/track/%d/colour" % idx, [c.r, c.g, c.b])

		if entry.has("folder_depth"):
			_apply("/track/%d/folder" % idx, [float(entry["folder_depth"])])

		var sends := _as_array(entry.get("sends", []))
		for send in sends:
			if typeof(send) != TYPE_DICTIONARY:
				continue
			# +1: ReaScript counts a track's sends from 0 and OSC from 1. Written 0-based, the
			# bridge's destination landed on a send OSC never mentions and OSC's level on one
			# the bridge never placed -- two half-sends for every real one, and the patchbay
			# drew both, as a mult fed twice by the same track.
			var send_idx := int(send.get("index", -1)) + 1
			if send_idx < 1:
				continue
			_apply("/track/%d/send/%d/dest" % [idx, send_idx],
					[float(int(send.get("dest_track", -1)))])
			if send.has("key"):
				_apply("/track/%d/send/%d/key" % [idx, send_idx], [1.0 if send["key"] else 0.0])
			if send.has("dest_name"):
				_apply("/track/%d/send/%d/name" % [idx, send_idx], [str(send["dest_name"])])
		# The bridge lists every send a track has, so a send it no longer lists has been removed.
		if entry.has("sends"):
			_apply("/track/%d/sends" % idx, [float(sends.size())])

		# OSC names only the selected track's parameters (see the Lua). Written onto the same
		# address OSC would have used, so a guest's rack is named by the ordinary stream.
		var chain := _as_array(entry.get("fx", []))
		if entry.has("fx"):
			_apply("/track/%d/fxs" % idx, [float(chain.size())])
		for fx in chain:
			if typeof(fx) != TYPE_DICTIONARY:
				continue
			var fx_idx := int(fx.get("index", -1)) + 1
			if fx.has("name") and str(fx["name"]) != "":
				_apply("/track/%d/fx/%d/name" % [idx, fx_idx], [str(fx["name"])])
			if fx.has("preset"):
				_apply("/track/%d/fx/%d/preset" % [idx, fx_idx], [str(fx["preset"])])
			if fx.has("preset_count"):
				_apply("/track/%d/fx/%d/presets" % [idx, fx_idx], [float(fx["preset_count"])])
			var wet_at := "/track/%d/fx/%d/wet" % [idx, fx_idx]
			if fx.has("wet") and Time.get_ticks_msec() - int(_wet_written.get(wet_at, -WET_SETTLE_MSEC)) >= WET_SETTLE_MSEC:
				_apply(wet_at, [float(fx["wet"])])
			var names := _as_array(fx.get("param_names", []))
			for p in names.size():
				_apply("/track/%d/fx/%d/fxparam/%d/name" % [idx, fx_idx, p + 1], [str(names[p])])

	# Same channel as the timeline's, and for the same reason: OSC reports the BANK, so without
	# a count from somewhere a 90-track session is indistinguishable from a 64-track one. Two
	# sources rather than one is deliberate -- whichever of the two polls is running keeps the
	# bank buttons honest.
	var count := int(result.get("track_count", seen))
	if count > 0:
		_apply("/project/tracks", [count])


## The bridge's Lua encoder cannot tell an empty list from an empty object, so an empty table
## arrives as `{}`. Everywhere this project reads a list off the bridge, it may be handed a
## dictionary meaning "nothing", and treating that as one malformed entry would be worse.
static func _as_array(value) -> Array:
	return value if value is Array else []


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
	# 1-based here as everywhere above the bridge; the Lua takes ReaScript's 0-based index.
	return _bridge.call_reaper("RemoveTrackSend", [from_track, send_index - 1])


# --- replication --------------------------------------------------------------------------

## Meters and the playhead. Everything else is durable.
func snapshot() -> Array:
	return MixWire.snapshot(state)


func apply_replicated(batch: Array) -> void:
	MixWire.apply_replicated(state, batch)
