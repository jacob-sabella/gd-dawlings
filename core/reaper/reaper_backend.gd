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
## The host's own installed plugins, fetched once per connection (see `open`/`_on_installed_fx`)
## rather than polled -- what is installed does not change while Reaper is running, unlike the
## structure and timeline above. Empty until the first answer lands, during which `fx_choices`
## falls back to Reaper's own always-present stock set so the desk is never left offering nothing.
var _installed_fx: Array = []
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
	_apply("/fxchoices", MixWire.pack_inputs(fx_choices()))
	_bridge.call_reaper("ListInstalledFx", [], _on_installed_fx)

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
	_installed_fx = []
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
	if capability == Capability.RENDER:
		# Reaper's own render, which only the bridge can start.
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
	follow_count_in()

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


## Reaper's own plugins' windows can be worked when the Reaper running here was started with
## native/reaper_pointer.c, as tools/reaper_rig.sh starts it.
func works_own_plugin_windows() -> bool:
	return ReaperPluginWindow.reaper_takes_clicks()


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


## Whatever `_on_installed_fx` found on the host's own machine -- real VST/VST3/AU/JS plugins,
## not a curated list -- once the bridge has answered; Reaper's own always-present stock plugins
## (OfflineBackend's list) until then, or if the bridge never answers at all, so the desk is
## never left with nothing to offer.
func fx_choices() -> Array:
	if not _installed_fx.is_empty():
		return _installed_fx.duplicate(true)
	return OfflineBackend.STOCK_FX.duplicate(true)


## Into Reaper's chain through the bridge, then read back by the structure poll and OSC. `at` is
## a slot as Reaper's OSC numbers them, from 1.
func add_fx(track_index: int, plugin: String, at: int) -> void:
	if _bridge == null or not _bridge.is_open() or not fx_choices().any(func(c): return c[0] == plugin):
		return
	_bridge.call_reaper("AddFx", [track_index, plugin, at],
			func(_result) -> void: _structure_due = 0.0)


func remove_fx(track_index: int, fx_index: int) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_bridge.call_reaper("RemoveFx", [track_index, fx_index],
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


## Reaper's I_SENDMODE through the bridge: 3, pre-fader (post-FX), or 0, post-fader. Shown at
## once; the structure poll says what Reaper made of it.
func set_send_pre_fader(track_index: int, send_index: int, pre: bool) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_apply("/track/%d/send/%d/pre" % [track_index, send_index], [1.0 if pre else 0.0])
	_bridge.call_reaper("SetSendPreFader", [track_index, send_index - 1, 1.0 if pre else 0.0],
			func(_result) -> void: _structure_due = 0.0)


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


## Reaper's own count-in (the bridge's SetCountIn), which runs its playhead up to the record point
## from before it as the built-in engine does; `follow_count_in` tells the take from the count.
func set_count_in(bars: int) -> void:
	_apply("/countin", [float(clampi(bars, 0, MixState.COUNT_IN_MAX))])
	_edit("SetCountIn", [clampi(bars, 0, MixState.COUNT_IN_MAX), state.count_in_play, state.pre_roll])


## Reaper's "Count-in before playback" (projmetroen &8), through the same handler.
func set_count_in_play(on: bool) -> void:
	_apply("/countin/play", [1.0 if on else 0.0])
	_edit("SetCountIn", [state.count_in_bars, on, state.pre_roll])


## Reaper's own pre-roll ("Pre-roll: Toggle pre-roll on record", and on play with a count before
## playback), in place of its count-in, through the same handler.
func set_pre_roll(on: bool) -> void:
	_apply("/countin/song", [1.0 if on else 0.0])
	_edit("SetCountIn", [state.count_in_bars, state.count_in_play, on])


## A track's record input, as Reaper's I_RECINPUT (the bridge's SetTrackInput). Only what
## `input_code` can say is sent; anything else Reaper keeps as it is.
func set_track_input(index: int, input: String) -> void:
	var code := input_code(input)
	if code == INPUT_UNKNOWN:
		return
	_apply("/track/%d/input" % index, [input])
	_edit("SetTrackInput", [index, code])


## Not an input code Reaper uses.
const INPUT_UNKNOWN := -2
## Reaper's code for MIDI from every device on every channel.
const INPUT_ALL_MIDI := 4096 | (63 << 5)


## The input id for Reaper's I_RECINPUT: "none", "in:N" a mono hardware input (1-based),
## "in:N/M" the stereo pair from N, "midi" all MIDI, and "reaper:<code>" anything else, kept.
static func input_id(code: int) -> String:
	if code < 0:
		return "none"
	if code == INPUT_ALL_MIDI:
		return "midi"
	if code & 4096 or code & 2048 or (code & 1023) >= 512:
		return "reaper:%d" % code
	var first := (code & 511) + 1
	return "in:%d/%d" % [first, first + 1] if code & 1024 else "in:%d" % first


## The other way; INPUT_UNKNOWN for "" (none chosen, which Reaper has no word for) or nonsense.
static func input_code(id: String) -> int:
	if id == "none":
		return -1
	if id == "midi":
		return INPUT_ALL_MIDI
	if id.begins_with("reaper:") and id.trim_prefix("reaper:").is_valid_int():
		return int(id.trim_prefix("reaper:"))
	if id.begins_with("in:"):
		var parts := id.trim_prefix("in:").split("/")
		if parts[0].is_valid_int() and int(parts[0]) >= 1 and int(parts[0]) <= 512:
			if parts.size() == 1:
				return int(parts[0]) - 1
			if parts.size() == 2 and parts[1] == str(int(parts[0]) + 1):
				return (int(parts[0]) - 1) | 1024
	return INPUT_UNKNOWN


## What a track can record from in Reaper: none, each hardware input and stereo pair, all MIDI.
static func reaper_inputs(audio_inputs: int) -> Array:
	var out: Array = [["none", "no input"]]
	for n in range(1, audio_inputs + 1):
		out.append(["in:%d" % n, "input %d" % n])
	for n in range(1, audio_inputs, 2):
		out.append(["in:%d/%d" % [n, n + 1], "inputs %d and %d" % [n, n + 1]])
	out.append(["midi", "all MIDI"])
	return out


## Reaper's record mode, time selection auto-punch or normal (the bridge's SetPunch).
func set_punch(on: bool) -> void:
	_apply("/punch", [1.0 if on else 0.0])
	_edit("SetPunch", [1 if on else 0])


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


## Through the bridge, in line with the edits: over OSC, an undo pressed straight after an edit
## could reach Reaper first and take back the step before, and an edit made straight after an
## undo could be undone in its place. OSC only when the bridge is not there.
func undo() -> void:
	_undo_or_redo("Undo", UNDO_ACTION)


func redo() -> void:
	_undo_or_redo("Redo", REDO_ACTION)


## Reaper's steps one at a time, as far as the depth it last reported says there are.
func undo_to(depth: int) -> void:
	var now := state.undo_depth
	if now < 0:
		return
	for _i in maxi(now - depth, 0):
		undo()
	for _i in clampi(depth - now, 0, maxi(state.redo_depth, 0)):
		redo()


func _undo_or_redo(fn: String, action: int) -> void:
	if _bridge != null and _bridge.is_open():
		_edit(fn, [])
	elif _peer != null:
		_peer.send("/action", [action])
	# Whatever came back may be an edit, and the timeline is only polled every two seconds; or a
	# track, and the structure even less often.
	_timeline_due = minf(_timeline_due, 0.15)
	_structure_due = minf(_structure_due, 0.15)


# --- editing ------------------------------------------------------------------------------
#
# OSC has no message for an item, so every edit goes through the bridge. Each is shown on the
# cache at once (see DAWBackend) and Reaper's own answer arrives with the next timeline poll,
# which an edit brings forward.

func select_all_items() -> void:
	_locally_select_all()
	_edit("SelectAllItems", [])


func select_track_items(track_index: int) -> void:
	if state.tracks.has(track_index):
		_locally_select_track(track_index)
		_edit("SelectTrackItems", [track_index])


func select_item(track_index: int, item_index: int, additive: bool) -> void:
	_locally_select(track_index, item_index, additive)
	_edit("SelectItem", [track_index, item_index, additive])


func clear_item_selection() -> void:
	_locally_clear_selection()
	_edit("ClearItemSelection", [])


func move_item(track_index: int, item_index: int, start: float, to_track := 0) -> void:
	_locally_move(track_index, item_index, start, to_track)
	_edit("MoveItem", [track_index, item_index, start, to_track])


func split_selected(seconds: float) -> void:
	_locally_split(seconds)
	_edit("SplitSelected", [seconds])


func delete_selected() -> void:
	_locally_delete_selected()
	_edit("DeleteSelected", [])


func ripple_delete_selected() -> void:
	if _locally_ripple_delete_selected() > 0:
		_edit("RippleDeleteSelected", [])


## Reaper glues what the desk would and more (any audio, through a new file), so the ask goes
## whenever a track has two selected items; the desk shows what it can until Reaper answers.
func glue_selected() -> void:
	_locally_glue_selected()
	if state.track_indices().any(func(i): return state.track(i).items.filter(
			func(it): return it.selected and not it.locked).size() >= 2):
		_edit("GlueSelected", [])


## Worked out here, along this map, and each item's new start sent: Reaper finds each by its
## track and where it was.
func nudge_selected(amount: float, unit: int) -> void:
	var moved := _locally_nudge(amount, unit)
	if not moved.is_empty():
		var flat: Array = []
		for m in moved:
			flat.append_array(m)
		_edit("NudgeItems", flat)


func copy_selected_to(seconds: float) -> void:
	if _locally_copy_selected_to(seconds) > 0:
		_edit("CopySelectedTo", [seconds])


func duplicate_selected() -> void:
	_locally_duplicate_selected()
	_edit("DuplicateSelected", [])


func trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	_locally_trim(track_index, item_index, start, end)
	_edit("TrimItem", [track_index, item_index, start, end])


func ripple_move_item(track_index: int, item_index: int, start: float) -> void:
	if _locally_ripple_move(track_index, item_index, start):
		_edit("MoveItem", [track_index, item_index, start, 0, 1])


func ripple_trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	if _locally_ripple_trim(track_index, item_index, start, end):
		_edit("TrimItem", [track_index, item_index, start, end, 1])


func set_item_gain(track_index: int, item_index: int, db: float) -> void:
	_locally_shape(track_index, item_index, db, NAN, NAN)
	_edit("SetItemGain", [track_index, item_index, db])


func set_item_muted(track_index: int, item_index: int, muted: bool) -> void:
	if _locally_mute(track_index, item_index, muted):
		_edit("SetItemMuted", [track_index, item_index, 1.0 if muted else 0.0])


func set_item_reversed(track_index: int, item_index: int, reversed: bool) -> void:
	if _locally_reverse(track_index, item_index, reversed):
		_edit("SetItemReversed", [track_index, item_index, 1.0 if reversed else 0.0])


func crossfade_items(track_index: int, first: int, second: int) -> void:
	var x := crossfade_of(track_index, first, second)
	if _locally_crossfade(track_index, first, second):
		_edit("CrossfadeItems", [track_index, x[0], x[1], x[2]])


func set_item_fade_shape(track_index: int, item_index: int, in_shape: int, out_shape: int) -> void:
	if _locally_fade_shape(track_index, item_index, in_shape, out_shape):
		_edit("SetItemFadeShape", [track_index, item_index, in_shape, out_shape])


func set_item_locked(track_index: int, item_index: int, locked: bool) -> void:
	if _locally_lock(track_index, item_index, locked):
		_edit("SetItemLocked", [track_index, item_index, 1.0 if locked else 0.0])


func set_item_fades(track_index: int, item_index: int, fade_in: float, fade_out: float) -> void:
	_locally_shape(track_index, item_index, NAN, fade_in, fade_out)
	_edit("SetItemFades", [track_index, item_index, fade_in, fade_out])


## Shown at once when the whole project is in the bank, then restated by Reaper: OSC for what it
## carries, the structure poll for folders and sends, the timeline for the lanes and the count.
func add_track(at: int, track_name: String) -> void:
	var count := state.track_indices().size()
	at = clampi(at, 1, maxi(state.project_track_count, count) + 1)
	var order := _order_adding(maxi(state.project_track_count, count), at)
	if _whole_project_in_bank():
		_locally_renumber(order)
		state.track(at).name = track_name
		state.bank_changed.emit()
	tracks_renumbered.emit(_map_of(order))
	_restructure("InsertTrack", [at, track_name])


func duplicate_track(index: int) -> void:
	if index < 1:
		return
	var order := _order_adding(maxi(state.project_track_count, state.track_indices().size()), index + 1)
	if _whole_project_in_bank() and state.tracks.has(index):
		_locally_renumber(order)
		_locally_copy_track(index, index + 1)
		state.bank_changed.emit()
	tracks_renumbered.emit(_map_of(order))
	_restructure("DuplicateTrack", [index])


func remove_track(index: int) -> void:
	if index < 1:
		return
	var order := _order_removing(maxi(state.project_track_count, state.track_indices().size()), index)
	if _whole_project_in_bank() and state.tracks.has(index):
		_locally_renumber(order)
		state.bank_changed.emit()
	tracks_renumbered.emit(_map_of(order))
	_restructure("DeleteTrack", [index])


func rename_track(index: int, track_name: String) -> void:
	if state.tracks.has(index):
		state.set_track_field(index, &"name", track_name)
	_edit("RenameTrack", [index, track_name])


## The desk's own, not Reaper's track groups (which link by flag bits per parameter, and which
## the bridge does not read): the desk moves each grouped track itself, so this is kept here and
## sent round the room, but not in Reaper's project.
func set_track_group(index: int, group: int) -> void:
	if state.tracks.has(index) and state.tracks[index].group != group:
		state.set_track_field(index, &"group", group)
		record_for_replication("/track/%d/group" % index, [float(group)])


## The desk's own, like groups: kept and sent round the room, not in Reaper's project.
func set_vca(group: int, db: float) -> void:
	db = clampf(db, -60.0, 12.0)
	if group >= 1 and group <= state.vca.size() and not is_equal_approx(state.vca_db(group), db):
		state.set_vca_db(group, db)
		record_for_replication("/vca/%d" % group, [db])


## Shown at once, and restated by the structure poll, which reads Reaper's own colour back.
func set_track_colour(index: int, colour: Color) -> void:
	if state.tracks.has(index):
		state.set_track_field(index, &"colour", colour)
	_edit("SetTrackColour", [index, colour.r, colour.g, colour.b])


func _whole_project_in_bank() -> bool:
	return state.bank_offset == 0 and state.project_track_count <= state.bank_size \
			and state.track_indices().size() == state.project_track_count


func _restructure(fn: String, args: Array) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_timeline_epoch += 1
	_edits_in_flight += 1
	_bridge.call_reaper(fn, args, func(_result) -> void:
		_structure_due = 0.0
		if _peer != null:
			_peer.send("/action", [REFRESH_SURFACES])
		_edits_in_flight -= 1
		_timeline_due = 0.0)


## Shown at once, then Reaper's markers replaced and read back with the next timeline. Reaper
## ramps only in a straight line in time, so every ramp becomes one, and each marker goes where
## that map puts its beat -- which is where Reaper's own map will put it.
func set_tempo_map(points: Array) -> void:
	var timed: Array = points.map(func(pt): return [float(pt[0]), float(pt[1]),
			DawKitTempoMap.HOLD if DawKitTempoMap.shape_of(pt[2]) == DawKitTempoMap.HOLD else DawKitTempoMap.RAMP_SECONDS])
	state.tempo_points = timed
	if not timed.is_empty():
		state.tempo = float(timed[0][1])
	state.transport_changed.emit()
	var map := state.tempo_map()
	var flat: Array = []
	for pt in (timed if not timed.is_empty() else [[0.0, state.tempo, DawKitTempoMap.HOLD]]):
		flat.append_array([map.seconds_at(float(pt[0])), float(pt[1]), 1.0 if pt[2] != DawKitTempoMap.HOLD else 0.0])
	_edit("SetTempoMap", flat)
	# Which takes every marker away, and Reaper's signatures are on its markers.
	if not state.time_signature_points.is_empty() or state.beats_per_bar != 4 or state.beat_unit != 4:
		var sigs: Array = state.time_signature_points if not state.time_signature_points.is_empty() \
				else [[0.0, state.beats_per_bar, state.beat_unit]]
		_edit("SetTimeSignatures", MixWire.pack_meter_points(sigs))


## Tempo points less those that change nothing: a held point at the tempo already held.
static func _without_held(points: Array) -> Array:
	var out: Array = []
	for pt in points:
		if not out.is_empty() and int(out[-1][2]) == DawKitTempoMap.HOLD and int(pt[2]) == DawKitTempoMap.HOLD \
				and absf(float(out[-1][1]) - float(pt[1])) < 0.0001:
			continue
		out.append(pt)
	return out


## Reaper keeps signatures on its tempo markers (the bridge's SetTimeSignatures).
func set_time_signature_map(points: Array) -> void:
	if points.is_empty():
		return
	_apply("/timesig", [float(points[0][1]), float(points[0][2])])
	_apply("/timesig/map", MixWire.pack_meter_points(points if points.size() > 1 else []))
	_edit("SetTimeSignatures", MixWire.pack_meter_points(points))


func shift_velocity(track_index: int, item_index: int, by: int) -> void:
	if _locally_shift_velocity(track_index, item_index, by):
		_edit("ShiftVelocity", [track_index, item_index, by])


## Reaper rolls its own dice: the preview here is a likeness, and the next timeline is the truth.
func legato_item(track_index: int, item_index: int) -> void:
	if _locally_legato(track_index, item_index):
		_edit("LegatoItem", [track_index, item_index])


func rename_item(track_index: int, item_index: int, item_name: String) -> void:
	if _locally_rename_item(track_index, item_index, item_name):
		_edit("RenameItem", [track_index, item_index, item_name])


func retrograde_item(track_index: int, item_index: int) -> void:
	if _locally_retrograde(track_index, item_index):
		_edit("RetrogradeItem", [track_index, item_index])


func even_velocity(track_index: int, item_index: int) -> void:
	if _locally_even_velocity(track_index, item_index):
		_edit("EvenVelocity", [track_index, item_index])


func staccato_item(track_index: int, item_index: int) -> void:
	if _locally_staccato(track_index, item_index):
		_edit("StaccatoItem", [track_index, item_index])


## Reaper skips muted notes when it counts, so the note goes by where it starts and its pitch.
func set_note_velocity(track_index: int, item_index: int, note_index: int, velocity: int) -> void:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + 4 >= item.notes.size():
		return
	var on: float = item.notes[at]
	var pitch: int = int(item.notes[at + 2])
	if _locally_set_note_velocity(track_index, item_index, note_index, velocity):
		_edit("SetNoteVelocity", [track_index, item_index, on, pitch, clampi(velocity, 1, 127)])


func move_note(track_index: int, item_index: int, note_index: int, by: float) -> void:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + 4 >= item.notes.size():
		return
	var on: float = item.notes[at]
	var pitch: int = int(item.notes[at + 2])
	var before: float = on
	if _locally_move_note(track_index, item_index, note_index, by):
		# The amount it really moved, after being held inside the item.
		_edit("MoveNote", [track_index, item_index, on, pitch, float(state.item(track_index, item_index).notes[at]) - before])


func set_note_end(track_index: int, item_index: int, note_index: int, off: float) -> void:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + 4 >= item.notes.size():
		return
	var on: float = item.notes[at]
	var pitch: int = int(item.notes[at + 2])
	if _locally_set_note_end(track_index, item_index, note_index, off):
		_edit("SetNoteEnd", [track_index, item_index, on, pitch, off])


func insert_note(track_index: int, item_index: int, on: float, off: float, pitch: int) -> void:
	if _locally_insert_note(track_index, item_index, on, off, pitch):
		_edit("InsertNote", [track_index, item_index, on, off, pitch, INSERT_VELOCITY])


func transpose_note(track_index: int, item_index: int, note_index: int, semitones: int) -> void:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + 4 >= item.notes.size():
		return
	var on: float = item.notes[at]
	var pitch: int = int(item.notes[at + 2])
	if _locally_transpose_note(track_index, item_index, note_index, semitones):
		_edit("TransposeNote", [track_index, item_index, on, pitch, semitones])


## By where it starts and its pitch, as the velocity edit is (Reaper skips muted notes when it counts).
func delete_note(track_index: int, item_index: int, note_index: int) -> void:
	var item := state.item(track_index, item_index)
	var at := note_index * MidiTake.NOTE_WIDTH
	if item == null or note_index < 0 or at + 4 >= item.notes.size():
		return
	var on: float = item.notes[at]
	var pitch: int = int(item.notes[at + 2])
	if _locally_delete_note(track_index, item_index, note_index):
		_edit("DeleteNote", [track_index, item_index, on, pitch])


func humanise_item(track_index: int, item_index: int, seconds: float, velocity: int) -> void:
	if _locally_humanise(track_index, item_index, seconds, velocity):
		_edit("HumaniseItem", [track_index, item_index, clampf(seconds, 0.0, HUMANISE_SECONDS_MAX),
				clampi(velocity, 0, HUMANISE_VELOCITY_MAX)])


func transpose_item(track_index: int, item_index: int, semitones: int) -> void:
	if _locally_transpose(track_index, item_index, semitones):
		_edit("TransposeItem", [track_index, item_index, semitones])


## Reaper quantises against its own tempo map, so a song with tempo changes comes back right from
## the next timeline even where the preview, at one tempo, was not.
func quantize_item(track_index: int, item_index: int, grid_beats: float, strength: float,
		swing := 0.0) -> void:
	if _locally_quantize(track_index, item_index, grid_beats, strength, swing):
		_edit("QuantizeItem", [track_index, item_index,
				clampf(grid_beats, QUANTIZE_GRID_MIN, QUANTIZE_GRID_MAX), clampf(strength, 0.0, 1.0),
				clampf(swing, 0.0, SWING_MAX)])


## Shown on the cache at once, like an item edit, and confirmed by the timeline poll the edit
## brings forward.
func add_marker(seconds: float, marker_name: String) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	var markers: Dictionary = state.markers.duplicate()
	markers[seconds] = marker_name
	_write_markers(markers)
	_edit("AddMarker", [seconds, marker_name])


func edit_marker(at: float, to: float, marker_name: String) -> void:
	if _bridge == null or not _bridge.is_open() or is_nan(marker_key(state.markers, at)):
		return
	_write_markers(markers_edited(state.markers, at, to, marker_name))
	_edit("EditMarker", [at, to, marker_name])


func add_region(start: float, end: float, region_name: String) -> void:
	if _bridge == null or not _bridge.is_open():
		return
	_write_regions(regions_added(state.regions, start, end, region_name))
	_edit("AddRegion", [start, end, region_name])


func remove_region(at: float) -> void:
	if _bridge == null or not _bridge.is_open() or regions_removed(state.regions, at).size() == state.regions.size():
		return
	_write_regions(regions_removed(state.regions, at))
	_edit("RemoveRegion", [at])


func edit_region(at: float, start: float, end: float, region_name: String) -> void:
	var after := regions_edited(state.regions, at, start, end, region_name)
	if _bridge == null or not _bridge.is_open() or after == state.regions:
		return
	_write_regions(after)
	_edit("EditRegion", [at, start, end, region_name])


func remove_marker(at: float) -> void:
	if _bridge == null or not _bridge.is_open() or is_nan(marker_key(state.markers, at)):
		return
	_write_markers(markers_edited(state.markers, at, at, "", true))
	_edit("RemoveMarker", [at])


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


## Reaper renders, offline, through the bridge: see the bridge's RenderProject. The files are on
## Reaper's machine, which is this one.
func render(stems: bool, bits := 24, normalise := false, rate := 48000) -> void:
	if _bridge == null or not _bridge.is_open():
		render_finished.emit(PackedStringArray(), PackedStringArray(["rendering needs the ReaScript bridge"]))
		return
	var looped := state.looping and state.loop_end - state.loop_start > 0.01
	var from := state.loop_start if looped else 0.0
	var to := state.loop_end if looped else state.timeline_length()
	_bridge.call_reaper("RenderProject", [from, to, 1 if stems else 0, int(RENDER_TAIL_SECONDS * 1000.0), bits,
			1 if normalise else 0, db_to_linear(RENDER_NORMALISE_DB), rate],
			_on_rendered, RENDER_TIMEOUT_MSEC)


## A render runs as fast as Reaper can, which for a long song with heavy plugins is a while.
const RENDER_TIMEOUT_MSEC := 600000


func _on_rendered(result) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		render_finished.emit(PackedStringArray(), PackedStringArray(["Reaper did not answer the render"]))
		return
	var files := PackedStringArray()
	for f in _as_array(result.get("files", [])):
		files.append(str(f))
	var problems := PackedStringArray()
	if not result.get("ok", false):
		problems.append(str(result.get("error", "Reaper rendered nothing")))
	render_finished.emit(files, problems)


## Shown at once, then written to Reaper's envelope and read back with the next timeline.
func set_automation(track_index: int, target: String, points: Array) -> void:
	_apply(MixWire.automation_address(track_index, target), MixWire.pack_automation(points))
	_edit("SetEnvelope", [track_index, target] + MixWire.pack_automation(points))


func set_track_automation_mode(index: int, mode: int) -> void:
	_apply("/master/automode" if index == 0 else "/track/%d/automode" % index, [float(mode)])
	_edit("SetAutomationMode", [index, mode])


## Reaper's envelope values come back through its own scaling: equal to within that.
static func _same_lane(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(float(a[i][0]) - float(b[i][0])) > 0.0001 or absf(float(a[i][1]) - float(b[i][1])) > 0.001 \
				or int(a[i][2]) != int(b[i][2]):
			return false
	return true


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
	var envelopes: Dictionary = {}
	var automodes: Dictionary = {}
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
				var overview: PackedByteArray = take_peaks[source]
				if item.get("reversed", false):
					overview = overview.duplicate()
					overview.reverse()
					extra["reversed"] = true
				extra.merge({"source": source, "offset": float(item.get("offset", 0.0)), "peaks": overview})
			# The item's fades and its own volume, which the desk can change too.
			var gain := float(item.get("gain", 1.0))
			var shape := {"fade_in": float(item.get("fade_in", 0.0)), "fade_out": float(item.get("fade_out", 0.0)),
					"gain_db": linear_to_db(gain) if gain > 0.0 else DAWBackend.ITEM_GAIN_MIN}
			# Reaper's default fade is a few milliseconds on every item; under that is no fade.
			if shape["fade_in"] > FADE_FLOOR or shape["fade_out"] > FADE_FLOOR or absf(shape["gain_db"]) > 0.001:
				extra.merge(shape)
			# The bridge says each end's shape in the desk's numbering (see its item_shape).
			var in_shape := DawKitClip.clean_shape(item.get("fade_shape", 0))
			var out_shape := DawKitClip.clean_shape(item.get("fade_out_shape", in_shape))
			if in_shape != DawKitClip.FADE_LINEAR:
				extra["fade_shape"] = in_shape
			if out_shape != in_shape:
				extra["fade_out_shape"] = out_shape
			if item.get("locked", false):
				extra["locked"] = true
			if not extra.is_empty():
				packed.append(extra)
		lanes[idx] = packed
		automodes[idx] = MixWire.automation_mode_of(entry.get("automode", 0))
		var reported: Dictionary = {}
		var auto = entry.get("automation", {})
		if typeof(auto) == TYPE_DICTIONARY:
			for target in auto:
				var points := MixWire.unpack_automation(str(target), _as_array(auto[target]))
				if not points.is_empty():
					reported[str(target)] = points
		envelopes[idx] = reported

	for index in state.track_indices():
		var packed: Array = lanes.get(index, [])
		if packed.is_empty() and state.track(index).items.is_empty():
			continue
		_apply("/track/%d/items" % index, packed)

	# Envelopes, like lanes, are reported by presence: a target not reported has none any more.
	for index in state.track_indices():
		var t := state.track(index)
		var reported: Dictionary = envelopes.get(index, {})
		for target in t.automation.keys():
			if not reported.has(target):
				_apply("/track/%d/automation/%s" % [index, target], [])
		for target in reported:
			if not _same_lane(t.automation.get(target, []), reported[target]):
				_apply("/track/%d/automation/%s" % [index, target], MixWire.pack_automation(reported[target]))
		var mode: int = automodes.get(index, 0)
		if mode != t.automation_mode:
			_apply("/track/%d/automode" % index, [float(mode)])
	var master: Dictionary = {}
	var reported_master = result.get("master_automation", {})
	if typeof(reported_master) == TYPE_DICTIONARY:
		for target in reported_master:
			if str(target) in MixWire.MASTER_LANES:
				var points := MixWire.unpack_automation(str(target), _as_array(reported_master[target]))
				if not points.is_empty():
					master[str(target)] = points
	for target in state.master.automation.keys():
		if not master.has(target):
			_apply("/master/automation/%s" % target, [])
	for target in master:
		if not _same_lane(state.master.automation.get(target, []), master[target]):
			_apply("/master/automation/%s" % target, MixWire.pack_automation(master[target]))
	if result.has("project_name"):
		var title := str(result["project_name"])
		var file := str(result.get("project_file", "")).get_file()
		if title != state.project_title or file != state.project_file:
			_apply("/project/name", [title, file])
	if result.has("audio_inputs"):
		var listed := MixWire.pack_inputs(reaper_inputs(int(result["audio_inputs"])))
		if listed != MixWire.pack_inputs(state.inputs):
			_apply("/inputs", listed)
	var codes := _as_array(result.get("inputs", []))
	for i in codes.size():
		var id := input_id(int(codes[i]))
		var t := state.track(i + 1, false)
		if t != null and t.input != id:
			_apply("/track/%d/input" % (i + 1), [id])
	if result.has("punch") and bool(result["punch"]) != state.punch:
		_apply("/punch", [1.0 if result["punch"] else 0.0])
	if result.has("count_in") and int(result["count_in"]) != state.count_in_bars:
		_apply("/countin", [float(result["count_in"])])
	if result.has("count_in_play") and bool(result["count_in_play"]) != state.count_in_play:
		_apply("/countin/play", [1.0 if result["count_in_play"] else 0.0])
	if result.has("pre_roll") and bool(result["pre_roll"]) != state.pre_roll:
		_apply("/countin/song", [1.0 if result["pre_roll"] else 0.0])
	if result.has("master_automode"):
		var master_mode := MixWire.automation_mode_of(result["master_automode"])
		if master_mode != state.master.automation_mode:
			_apply("/master/automode", [float(master_mode)])

	var markers: Array = []
	for m in _as_array(result.get("markers", [])):
		if typeof(m) == TYPE_DICTIONARY:
			markers.append_array([float(m.get("position", 0.0)), str(m.get("name", ""))])
	_apply("/timeline/markers", markers)
	if result.has("regions"):
		var regions: Array = []
		for r in _as_array(result["regions"]):
			if typeof(r) == TYPE_DICTIONARY:
				regions.append([float(r.get("start", 0.0)), float(r.get("end", 0.0)), str(r.get("name", ""))])
		_apply("/timeline/regions", MixWire.pack_regions(regions))
	_apply("/timeline/length", [float(result.get("length", 0.0))])
	if result.has("tempo"):
		var flat: Array = []
		for pt in _as_array(result["tempo"]):
			if pt is Array and pt.size() >= 3:
				# Reaper's gradual change is a straight line in time.
				flat.append_array([float(pt[0]), float(pt[1]),
						float(DawKitTempoMap.RAMP_SECONDS if pt[2] else DawKitTempoMap.HOLD)])
		# A single marker is one tempo, which /tempo/raw already says. A marker that only holds a
		# time signature, at the tempo before it, is no change of tempo.
		var points := _without_held(MixWire.unpack_tempo_points(flat))
		if points.size() <= 1:
			points = []
		if points != state.tempo_points:
			_apply("/tempo/map", MixWire.pack_tempo_points(points))
	if result.has("timesig"):
		var flat: Array = []
		for pt in _as_array(result["timesig"]):
			if pt is Array and pt.size() >= 3:
				flat.append_array([float(pt[0]), float(pt[1]), float(pt[2])])
		var sigs := MixWire.unpack_meter_points(flat)
		if not sigs.is_empty():
			if int(sigs[0][1]) != state.beats_per_bar or int(sigs[0][2]) != state.beat_unit:
				_apply("/timesig", [float(sigs[0][1]), float(sigs[0][2])])
			var changes: Array = sigs if sigs.size() > 1 else []
			if changes != state.time_signature_points:
				_apply("/timesig/map", MixWire.pack_meter_points(changes))
	# The only channel that knows how big the project actually is. OSC reports the bank and
	# nothing else, so without this a 90-track session is indistinguishable from a 64-track one.
	if result.has("track_count"):
		_apply("/project/tracks", [int(result["track_count"])])


# --- the host's own plugins ----------------------------------------------------------------

## `ListInstalledFx`'s answer: `{ok, fx: [{id, label}, ...]}`, `id` being the identifier string
## `TrackFX_AddByName` matches on (not the display name -- a VST2 and a VST3 build of the same
## plugin share a name but not an identifier), `label` what a picker shows. One-shot, not polled
## like the structure/timeline above: fired once from `open`, and re-asked only by a fresh
## connection (`close` clears `_installed_fx`, `open` asks again). Malformed or missing entries
## are skipped rather than failing the whole list, so one odd plugin cannot blank the desk.
func _on_installed_fx(result) -> void:
	if result == null or typeof(result) != TYPE_DICTIONARY or not result.get("ok", false):
		return
	var found: Array = []
	for entry in _as_array(result.get("fx", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id: String = str(entry.get("id", ""))
		var label: String = str(entry.get("label", ""))
		if id.is_empty() or label.is_empty():
			continue
		found.append([id, label])
	if found.is_empty():
		return
	_installed_fx = found
	_apply("/fxchoices", MixWire.pack_inputs(fx_choices()))


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
			if send.has("pre"):
				_apply("/track/%d/send/%d/pre" % [idx, send_idx], [1.0 if send["pre"] else 0.0])
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
