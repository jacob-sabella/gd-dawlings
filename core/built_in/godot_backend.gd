class_name GodotBackend
extends OfflineBackend

## The built-in DAW: Godot's own audio engine standing in for Reaper, for anyone who has no
## DAW of their own.
##
## It is the offline stand-in made audible. Everything the stand-in models -- the session, the
## arrangement, undo, the timeline edits, replication to guests -- is inherited unchanged, and
## this class adds the half that was missing: sound.
##
##   - one AudioServer bus per track, routed through its folder's bus to a master bus of our
##     own, so a fader, a pan, a mute or a solo is a real gain change;
##   - Godot's built-in effects (FXCatalogue) as the FX racks, each knob a real parameter;
##   - sends as a second player of the same part on a send bus into the destination, so the
##     reverb return returns reverb. The send bus holds the track's own pan and effect objects
##     (as a cue does), then the send's pan, and the player plays at the send level times the
##     fader: post-effects, post-fader, as Reaper sends by default;
##   - meters read off the buses' peaks rather than synthesised;
##   - a cue per track on request (`set_cues`): a third player of the part, through the track's
##     own effects but not its fader, on a bus that plays to this machine's headphones only;
##   - a demo song (DemoSong), one synthesised part per instrument, played through the
##     timeline's items: an item is a window in which its track's part sounds;
##   - MIDI items played through the built-in instrument (DawKitTine), rendered per item.
##
## It is driven from the state's own signals rather than by overriding each command, so undo,
## redo, a guest's intent and a local hand all reach the speakers by the one path.
##
## Not done: third-party plugins, sample-accurate automation. A send runs the track's effects a
## second time on its own bus rather than tapping the track's output, because Godot routes a bus
## to exactly one place: the same input through the same settings, so the same sound, at the cost
## of the effects' work once per send.

const BUS_PREFIX := "R3D "
const MASTER_BUS := "R3D Master"
const CUE_PREFIX := "R3D Cue "
## How far a player may move from where it started against the song clock before it is put back
## (see `_drift`). Every player and the clock are moved by the same mixer, so this is for a player
## that stalled or was starved, not for steady running; a re-seek is a small click. More than a
## whole mix step: a reading jitters by up to half of one with where in the step it is taken.
const DRIFT_SECONDS := 0.025
## How many MIDI renders are kept before those of items no longer there are let go.
const KEPT_RENDERS := 32
## Where a render of a project never saved goes.
const RENDER_DIR := "user://renders"

## The FX chains the demo opens with: track -> [[kind, {param name: normalised value}]].
const DEMO_FX := {
	2: [[&"eq", {"32 Hz": 0.68, "100 Hz": 0.6, "320 Hz": 0.38}], [&"compressor", {"Thresh": 0.62, "Ratio": 0.35, "Makeup": 0.2}]],
	6: [[&"compressor", {"Thresh": 0.55, "Ratio": 0.3, "Makeup": 0.25}]],
	7: [[&"chorus", {"Wet": 0.45, "Rate": 0.3, "Depth": 0.4}]],
	8: [[&"distortion", {"Drive": 0.25}], [&"delay", {"Time": 0.62, "Feedback": 0.55, "Dry": 1.0}]],
	10: [[&"eq", {"320 Hz": 0.42, "3.2 kHz": 0.62}], [&"compressor", {"Thresh": 0.6, "Ratio": 0.3, "Makeup": 0.2}]],
	12: [[&"filter", {"Cutoff": 0.72, "Resonance": 0.15}]],
	13: [[&"reverb", {"Size": 0.8, "Damping": 0.45, "Wet": 1.0, "Dry": 0.0, "Pre-delay": 0.05}]],
}

## Track index -> bus index.
var _bus := {}
## Track index -> [AudioStreamPlayer...]: the track's own player, then one per send.
var _players := {}
## Track index -> the [slot, destination, key] of each send its buses were built for, so a send
## level moving does not rebuild them and a send patched or pulled does.
var _built_sends := {}
## Track index -> fx index -> FX kind.
var _kinds := {}
## Role -> finished part.
var _parts := {}
## The tempo and signature `_parts` were rendered at, "<tempo>/<sig>".
var _parts_key := ""
## With tempo or signature changes a part does not loop: it plays windows of itself through the
## map and meter (DemoSong.render_window), `window_key` -> [stream, seconds of its first sample], and
## the tasks of those still rendering, by key.
var _windows := {}
var _windows_pending := {}
var _master_bus := -1
var _capture: AudioEffectCapture
## The tracks being cued, in order.
var _cues: Array[int] = []
## The song clock (`_drive_meters`): a silent loop, how many times it has gone round, where it was
## last read, the song position at its zero, and the playhead as it last set it.
const CLOCK_SECONDS := 8.0
## How many times a playing player has been put back on the clock: each is a small click, so
## this should stay near nothing. For the probe.
var reseeks := 0
var _clock: AudioStreamPlayer
var _clock_turns := 0
var _clock_raw := 0.0
var _clock_origin := 0.0
var _clock_said := -1.0
## Recorded take file name -> its sound, or null when the file is not on this machine.
var _take_streams := {}
## How long a window of clicks is when the tempo changes, and how near its end a new one is made.
const CLICK_WINDOW := 32.0
const CLICK_WINDOW_LEAD := 4.0
## Where the click's window starts in the song, in seconds.
var _click_from := 0.0
## The metronome: one bar of clicks (DawKitMetronome), looping, kept on the bar grid like a part.
var _click: AudioStreamPlayer
var _click_for := ""
## A MIDI item's sound, by what is in it (`midi_key`), rendered through the instrument
## (DawKitTine) on a worker thread; and the renders still running, as [task, [result]].
var _midi_streams := {}
var _midi_tasks := {}


## Players sound from the next mix on, so a count begun on its first click would clip it: begun
## this much before, it is heard whole (measured: 5 ms late without).
const COUNT_IN_LEAD := 0.05


func _init() -> void:
	count_in_lead = COUNT_IN_LEAD


## The song through dawkit's native lanes (LaneEngine), sample-accurate, where the core is built
## and a sound card mixes; null for players started and steered a frame at a time, as before.
var lanes: LaneEngine = null
## Off for the suite's checks of the players themselves.
var lanes_wanted := true


func _start_lanes() -> void:
	if lanes != null:
		lanes.build()
		return
	if not lanes_wanted or not LaneEngine.available() or AudioServer.get_driver_name() == "Dummy":
		return
	lanes = LaneEngine.new()
	lanes.name = "Lanes"
	lanes.backend = self
	add_child(lanes)
	lanes.build()


## Where the first frame mixed after play is pressed now is in the song: with lanes, where the
## playhead stood; with players, wherever the song has got to by the next mix (start_at).
func first_frame_at(expected: float) -> float:
	return expected if lanes != null else start_at(expected)

func summary() -> String:
	var waiting := _waiting_roles().size()
	return "built-in: Godot audio" + (" (rendering %d parts)" % waiting if waiting > 0 else "")


func can(capability: StringName) -> bool:
	if capability == Capability.RENDER:
		return true
	return super(capability)


## The render under way, if one is.
var rendering: MixRender
var _looping_before_render := false


## In real time (MixRender): the song plays the range once. A second render while one runs is
## refused, as is one with no project length to it.
func render(stems: bool) -> void:
	if rendering != null:
		render_finished.emit(PackedStringArray(), PackedStringArray(["a render is already running"]))
		return
	var r := MixRender.new()
	r.name = "Render"
	r.backend = self
	var looped := state.looping and state.loop_end - state.loop_start > 0.01
	r.from = state.loop_start if looped else 0.0
	r.to = state.loop_end if looped else state.timeline_length()
	var title := project_title.strip_edges().validate_filename()
	r.name_stem = title if not title.is_empty() else "Untitled"
	var base := project_path.get_base_dir() if not project_path.is_empty() else ProjectSettings.globalize_path(RENDER_DIR)
	r.folder = base.path_join("%s renders" % r.name_stem)
	if stems:
		r.stems = state.track_indices()
	# Played once through, not round the loop.
	_looping_before_render = state.looping
	state.looping = false
	var problem := r.begin()
	if not problem.is_empty():
		state.looping = _looping_before_render
		render_finished.emit(PackedStringArray(), PackedStringArray([problem]))
		return
	rendering = r
	r.finished.connect(_on_rendered)
	add_child(r)


func _on_rendered(files: PackedStringArray, problems: PackedStringArray) -> void:
	rendering = null
	state.looping = _looping_before_render
	state.transport_changed.emit()
	render_finished.emit(files, problems)


func open(options: Dictionary = {}) -> bool:
	super(options)
	# The stand-in opens rolling, so its photographs show a live desk. An application that
	# starts playing music the moment it opens is a rude one: this one opens at the top,
	# stopped, and waits for play.
	state.playing = false
	state.position_seconds = 0.0
	state.position_string = state.bar_beat(0.0)
	_dress_fx()
	_build_buses()
	_start_lanes()
	_connect_state()
	_render_parts()
	_apply_everything()
	connection_changed.emit()
	return true


func close() -> void:
	_finish_renders()
	super()
	for list in _players.values():
		for p in list:
			(p as Node).queue_free()
	_players.clear()
	_remove_buses()


func _exit_tree() -> void:
	_finish_renders()
	_remove_buses()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_finish_renders()


## Every render still running, waited for: a task left running when the engine goes away runs on
## into freed memory, and one never waited for aborts the program at exit.
func _finish_renders() -> void:
	for key in _midi_tasks:
		WorkerThreadPool.wait_for_task_completion(_midi_tasks[key][0])
	_midi_tasks.clear()
	for key in _windows_pending:
		WorkerThreadPool.wait_for_task_completion(_windows_pending[key][0])
	_windows_pending.clear()


# --- the mix ------------------------------------------------------------------------------

## The stand-in's FX are names standing for Reaper plugins. Here they become Godot effects,
## with the parameter names, ranges and readings of the effects they are.
func _dress_fx() -> void:
	for index in state.track_indices():
		(state.tracks[index] as MixState.TrackState).fx.clear()
	_kinds.clear()
	for index in DEMO_FX:
		if not state.tracks.has(index):
			continue
		for spec in DEMO_FX[index]:
			add_effect(index, spec[0], spec[1])


func fx_kind(track_index: int, fx_index: int) -> StringName:
	return _kinds.get(track_index, {}).get(fx_index, &"")


## A whole project has been put into the cache: its effects, its buses and its players are made
## again from it, and the song's parts rendered at its tempo.
func _fx_kinds() -> Dictionary:
	return _kinds.duplicate(true)


func project_loaded(kinds: Dictionary) -> void:
	_kinds = kinds.duplicate(true)
	_take_streams.clear()
	for list in _players.values():
		for p in list:
			(p as Node).queue_free()
	_players.clear()
	_build_buses()
	_start_lanes()
	_apply_everything()
	_render_parts()


## Puts an effect at the end of a track's chain. `settings` are by parameter name, normalised.
func add_effect(track_index: int, kind: StringName, settings := {}) -> int:
	var t := state.track(track_index)
	var fx_index := t.fx.size()
	var f := state.fx(track_index, fx_index)
	f.name = FXCatalogue.kinds()[kind]["name"]
	var defaults := FXCatalogue.defaults(kind)
	var params := FXCatalogue.params(kind)
	for pi in params.size():
		f.param_names[pi] = params[pi].name
		f.params[pi] = float(settings.get(params[pi].name, defaults[pi]))
	if not _kinds.has(track_index):
		_kinds[track_index] = {}
	_kinds[track_index][fx_index] = kind
	if _bus.has(track_index):
		AudioServer.add_bus_effect(_bus[track_index], FXCatalogue.make(kind))
		_apply_fx(track_index, fx_index)
		_build_sends(track_index)
		if track_index in _cues:
			_build_cues()
	state.fx_changed.emit(track_index, fx_index)
	return fx_index


## Godot's own effects, by their catalogue kind.
func fx_choices() -> Array:
	var out: Array = []
	for k in FXCatalogue.kinds():
		out.append([String(k), FXCatalogue.kinds()[k]["name"]])
	return out


func _new_fx_row(plugin: String) -> Dictionary:
	var kind := StringName(plugin)
	if not FXCatalogue.kinds().has(kind):
		return {}
	var params := FXCatalogue.params(kind)
	var defaults := FXCatalogue.defaults(kind)
	var row := {"name": FXCatalogue.kinds()[kind]["name"], "enabled": true, "wet": 1.0, "preset": "",
			"params": {}, "param_names": {}}
	for pi in params.size():
		row["params"][pi] = float(defaults[pi])
		row["param_names"][pi] = params[pi].name
	return row


## Whenever a chain is laid down -- a plugin moved, added or removed, or any of those undone --
## the effects on the bus follow it, by the name each slot now holds: a copy is a new effect of
## the same kind, not the same one.
func _set_fx_chain(track_index: int, rows: Array) -> void:
	super(track_index, rows)
	_restack(track_index)


## Lay a track's bus effects down again in the order its chain now says.
func _restack(track_index: int) -> void:
	var by_name := {}
	for k in FXCatalogue.kinds():
		by_name[FXCatalogue.kinds()[k]["name"]] = k
	var kinds := {}
	for fx_index in state.track(track_index).plugins():
		var name: String = state.fx(track_index, fx_index).name
		if by_name.has(name):
			kinds[fx_index] = by_name[name]
	_kinds[track_index] = kinds
	if not _bus.has(track_index):
		return
	var b: int = _bus[track_index]
	# Everything after the panner, which is the track's own and not a plugin.
	for i in range(AudioServer.get_bus_effect_count(b) - 1, 0, -1):
		AudioServer.remove_bus_effect(b, i)
	var order: Array = kinds.keys()
	order.sort()
	for fx_index in order:
		AudioServer.add_bus_effect(b, FXCatalogue.make(kinds[fx_index]))
	_build_sends(track_index)
	for fx_index in order:
		_apply_fx(track_index, fx_index)
	if track_index in _cues:
		_build_cues()


## Which track's bus each track sends into: its folder's, or the master's.
func parent_of(index: int) -> int:
	var stack: Array = []
	for i in state.track_indices():
		if i == index:
			return stack[-1] if not stack.is_empty() else 0
		var t: MixState.TrackState = state.tracks[i]
		if t.folder_depth > 0:
			stack.append(i)
		elif t.folder_depth < 0:
			for _n in -t.folder_depth:
				if not stack.is_empty():
					stack.pop_back()
	return 0


func _build_buses() -> void:
	_remove_buses()
	# Its master plays into the app's Mix bus, which has to be there first: a bus only sends to
	# one before it.
	AudioPorts.ensure_buses()
	_master_bus = AudioServer.bus_count
	AudioServer.add_bus(_master_bus)
	AudioServer.set_bus_name(_master_bus, MASTER_BUS)
	AudioServer.set_bus_send(_master_bus, AudioPorts.bus(AudioPorts.MIX))
	AudioServer.add_bus_effect(_master_bus, AudioEffectPanner.new())
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.3
	AudioServer.add_bus_effect(_master_bus, limiter)
	# What a host hands its guests' ears: this bus and nothing else, so the studio's own clicks
	# and footsteps stay in the room they were made in. See `mix_source`.
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.25
	AudioServer.add_bus_effect(_master_bus, _capture)

	for index in state.track_indices():
		var b := AudioServer.bus_count
		AudioServer.add_bus(b)
		AudioServer.set_bus_name(b, "%s%d" % [BUS_PREFIX, index])
		_bus[index] = b
		AudioServer.add_bus_effect(b, AudioEffectPanner.new())
		var kinds: Dictionary = _kinds.get(index, {})
		for fx_index in kinds.size():
			AudioServer.add_bus_effect(b, FXCatalogue.make(kinds[fx_index]))
	for index in _bus:
		var parent := parent_of(index)
		AudioServer.set_bus_send(_bus[index],
				AudioServer.get_bus_name(_bus[parent]) if parent > 0 else MASTER_BUS)

	for index in state.track_indices():
		var list: Array = []
		var own := AudioStreamPlayer.new()
		own.bus = AudioServer.get_bus_name(_bus[index])
		add_child(own)
		list.append(own)
		_players[index] = list
	_built_sends.clear()
	for index in state.track_indices():
		_build_sends(index)
	if not _cues.is_empty():
		_build_cues()


static func send_bus(index: int, dest: int) -> String:
	return "%s%d>%d" % [BUS_PREFIX, index, dest]


func _send_shape(index: int) -> Array:
	var out: Array = []
	var t: MixState.TrackState = state.tracks[index]
	var slots: Array = t.sends.keys()
	slots.sort()
	for slot in slots:
		var sd: MixState.SendState = t.sends[slot]
		out.append([slot, sd.resolve(state), sd.key])
	return out


## A track's send buses and players, made again: one bus per send into its destination, holding
## the track's pan, then the track bus's own effect objects (a knob on the rack turns the send's
## too), then the send's pan.
func _build_sends(index: int) -> void:
	if not _bus.has(index):
		return
	var list: Array = _players.get(index, [])
	for p in list.filter(func(p: Node) -> bool: return p.has_meta(&"send")):
		list.erase(p)
		(p as AudioStreamPlayer).stop()
		(p as Node).queue_free()
	var prefix := "%s%d>" % [BUS_PREFIX, index]
	for i in range(AudioServer.bus_count - 1, 0, -1):
		if AudioServer.get_bus_name(i).begins_with(prefix):
			AudioServer.remove_bus(i)
	var b: int = _bus[index]
	_built_sends[index] = _send_shape(index)
	for row in _built_sends[index]:
		var dest: int = row[1]
		# A key goes to a detector, and nothing here listens for one: playing it into the
		# destination's mix would make a sidechain an ordinary send.
		if row[2] or not _bus.has(dest):
			continue
		var sb := AudioServer.bus_count
		AudioServer.add_bus(sb)
		AudioServer.set_bus_name(sb, send_bus(index, dest))
		AudioServer.set_bus_send(sb, AudioServer.get_bus_name(_bus[dest]))
		AudioServer.add_bus_effect(sb, AudioEffectPanner.new())
		for slot in range(1, AudioServer.get_bus_effect_count(b)):
			AudioServer.add_bus_effect(sb, AudioServer.get_bus_effect(b, slot))
			AudioServer.set_bus_effect_enabled(sb, slot, AudioServer.is_bus_effect_enabled(b, slot))
		AudioServer.add_bus_effect(sb, AudioEffectPanner.new())
		var p := AudioStreamPlayer.new()
		p.bus = AudioServer.get_bus_name(sb)
		p.set_meta(&"send", row[0])
		add_child(p)
		list.append(p)
	_players[index] = list
	_apply_tracks()


## The bus a track's cue plays on, by name: whatever its level, it is heard only through a pair
## of headphones (Ears).
static func cue_bus(index: int) -> StringName:
	return StringName(CUE_PREFIX + str(index))


## Play a cue of each of `indices` (track indices), and of nothing else: for a personal mix
## (PersonalMix) that has a channel strip's send patched. A cue is the track as it leaves its
## effects, before its fader and pan -- the pre-fader cue send a console gives a musician, so the
## engineer pulling the vocal down in the mix does not pull it out of the singer's ears. It
## follows the track's mute. It plays in time with the track because it is the same part, kept
## to the same clock by `_sync_players`, not a copy of the track's sound taken off its bus.
func set_cues(indices: Array) -> void:
	var want: Array[int] = []
	for i in indices:
		if state.tracks.has(int(i)) and int(i) not in want:
			want.append(int(i))
	want.sort()
	if want == _cues:
		return
	_cues = want
	_build_cues()


func cues() -> Array[int]:
	return _cues.duplicate()


## The cue buses and their players, made again from `_cues`. Each bus holds the track bus's own
## effect objects, so a knob on the rack turns the cue's too; an effect added, removed or moved
## changes those objects, and comes here again.
func _build_cues() -> void:
	for index in _players:
		var list: Array = _players[index]
		for p in list.filter(func(p: Node) -> bool: return p.has_meta(&"cue")):
			list.erase(p)
			# Stopped now, not when it is freed: for the rest of this frame its bus is gone, and
			# a player whose bus is gone plays to Master.
			(p as AudioStreamPlayer).stop()
			(p as Node).queue_free()
	for i in range(AudioServer.bus_count - 1, 0, -1):
		if AudioServer.get_bus_name(i).begins_with(CUE_PREFIX):
			AudioServer.remove_bus(i)
	for index in _cues:
		if not _bus.has(index):
			continue
		var b: int = _bus[index]
		var cb := AudioServer.bus_count
		AudioServer.add_bus(cb)
		AudioServer.set_bus_name(cb, cue_bus(index))
		AudioServer.set_bus_send(cb, &"Master")
		# Past the panner, which is the track's place in the mix and not its sound.
		for slot in range(1, AudioServer.get_bus_effect_count(b)):
			AudioServer.add_bus_effect(cb, AudioServer.get_bus_effect(b, slot))
			AudioServer.set_bus_effect_enabled(cb, slot - 1, AudioServer.is_bus_effect_enabled(b, slot))
		var p := AudioStreamPlayer.new()
		p.bus = cue_bus(index)
		p.set_meta(&"cue", true)
		add_child(p)
		_players[index].append(p)
	_apply_tracks()


func _remove_buses() -> void:
	if lanes != null:
		lanes.clear()
	for i in range(AudioServer.bus_count - 1, 0, -1):
		if AudioServer.get_bus_name(i).begins_with(BUS_PREFIX):
			AudioServer.remove_bus(i)
	_bus.clear()
	_master_bus = -1
	_capture = null


func _connect_state() -> void:
	if not state.track_changed.is_connected(_on_track_changed):
		state.track_changed.connect(_on_track_changed)
		state.master_changed.connect(func(_f): _apply_master())
		state.fx_changed.connect(_apply_fx)
		state.transport_changed.connect(_on_transport_changed)


func _on_track_changed(index: int, field: StringName) -> void:
	if field == &"sends" and _bus.has(index) and _send_shape(index) != _built_sends.get(index, []):
		_build_sends(index)
		return
	_apply_tracks()


func _apply_everything() -> void:
	_apply_master()
	_apply_tracks()
	for index in _kinds:
		for fx_index in _kinds[index]:
			_apply_fx(index, fx_index)


func _apply_master() -> void:
	if _master_bus < 0:
		return
	AudioServer.set_bus_volume_db(_master_bus, taper_to_db(state.master.volume))
	(AudioServer.get_bus_effect(_master_bus, 0) as AudioEffectPanner).pan = (state.master.pan - 0.5) * 2.0


## Whether a track can be heard, given every mute and solo on the desk. Solo is solo-in-place:
## a soloed track's folder and the returns it sends to stay up, or soloing a snare would
## take away the drum bus it plays through and the reverb it sits in.
func audible(index: int) -> bool:
	var t: MixState.TrackState = state.tracks[index]
	if t.mute:
		return false
	var soloed: Array = state.track_indices().filter(func(i): return state.tracks[i].solo)
	if soloed.is_empty() or t.solo:
		return true
	for s in soloed:
		# Under a soloed folder, or the folder a soloed track plays through.
		var up := parent_of(index)
		while up > 0:
			if up == s:
				return true
			up = parent_of(up)
		up = parent_of(s)
		while up > 0:
			if up == index:
				return true
			up = parent_of(up)
		for send in (state.tracks[s] as MixState.TrackState).sends.values():
			if (send as MixState.SendState).resolve(state) == index:
				return true
	return false


func _apply_tracks() -> void:
	for index in _bus:
		var t: MixState.TrackState = state.tracks[index]
		var b: int = _bus[index]
		AudioServer.set_bus_volume_db(b, taper_to_db(t.volume))
		AudioServer.set_bus_mute(b, not audible(index))
		(AudioServer.get_bus_effect(b, 0) as AudioEffectPanner).pan = (t.pan - 0.5) * 2.0
		for p in _players.get(index, []):
			if p.has_meta(&"cue"):
				AudioServer.set_bus_mute(AudioServer.get_bus_index(p.bus), t.mute)
			elif p.has_meta(&"send"):
				var send: MixState.SendState = t.sends.get(p.get_meta(&"send"))
				# Post-fader, the way a reverb send usually is: the track's own fader is folded
				# in, so pulling the vocal down pulls its reverb down with it.
				p.volume_db = taper_to_db(send.volume) + taper_to_db(t.volume) if send != null else -80.0
				var sb := AudioServer.get_bus_index(p.bus)
				AudioServer.set_bus_mute(sb, not audible(index))
				# The track's pan first, as the track bus has it, then the send's own.
				var last := AudioServer.get_bus_effect_count(sb) - 1
				(AudioServer.get_bus_effect(sb, 0) as AudioEffectPanner).pan = (t.pan - 0.5) * 2.0
				if send != null and last > 0:
					(AudioServer.get_bus_effect(sb, last) as AudioEffectPanner).pan = (send.pan - 0.5) * 2.0


func _apply_fx(track_index: int, fx_index: int) -> void:
	if not _bus.has(track_index) or not _kinds.has(track_index) or not _kinds[track_index].has(fx_index):
		return
	var kind: StringName = _kinds[track_index][fx_index]
	var f := state.fx(track_index, fx_index)
	var slot := 1 + fx_index
	var effect := AudioServer.get_bus_effect(_bus[track_index], slot)
	var params := FXCatalogue.params(kind)
	for pi in params.size():
		params[pi].set_on(effect, float(f.params.get(pi, 0.5)))
	AudioServer.set_bus_effect_enabled(_bus[track_index], slot, f.enabled)
	var cue := AudioServer.get_bus_index(cue_bus(track_index))
	if cue >= 0 and slot - 1 < AudioServer.get_bus_effect_count(cue):
		AudioServer.set_bus_effect_enabled(cue, slot - 1, f.enabled)
	for row in _built_sends.get(track_index, []):
		var sb := AudioServer.get_bus_index(send_bus(track_index, row[1]))
		if sb >= 0 and slot < AudioServer.get_bus_effect_count(sb) - 1:
			AudioServer.set_bus_effect_enabled(sb, slot, f.enabled)


## The rack asks what a knob reads in the effect's own units. Answered at once: there is no
## DAW to ask.
func read_fx_param_text(track_index: int, fx_index: int, param: int) -> void:
	if not _kinds.has(track_index) or not _kinds[track_index].has(fx_index):
		return
	var params := FXCatalogue.params(_kinds[track_index][fx_index])
	if param < 0 or param >= params.size():
		return
	var v := float(state.fx(track_index, fx_index).params.get(param, 0.5))
	var address := "/track/%d/fx/%d/fxparam/%d/value/str" % [track_index, fx_index, param]
	var args := [params[param].text(v), v]
	MixWire.apply(state, address, args)
	record_for_replication(address, args)


# --- the song -----------------------------------------------------------------------------

func _roles() -> Array:
	var out: Array = []
	for index in state.track_indices():
		var role: String = state.tracks[index].part
		if role != "" and role not in out:
			out.append(role)
	return out


func _waiting_roles() -> Array:
	if parts_windowed():
		return _roles().filter(func(r): return _part_window(r, state.position_seconds).is_empty())
	return _roles().filter(func(r): return not _parts.has(r) or _parts_key != _rendering_key)


## Whether the parts play windows rendered through the song's tempo and signature changes rather
## than one loop going round: with either kind of change.
func parts_windowed() -> bool:
	return not state.tempo_points.is_empty() or not state.time_signature_points.is_empty()


## The signature a looped part is rendered in.
func parts_signature() -> Vector2i:
	return Vector2i(maxi(state.beats_per_bar, 1), maxi(state.beat_unit, 1))


## The window of `role` that plays at `seconds`, [stream, its first sample's seconds], or empty
## while it renders. Asks for it, and once the playhead is halfway through its first loop, for the
## next one too, so it is there when it is wanted.
func _part_window(role: String, seconds: float) -> Array:
	var map := state.tempo_map()
	var meter := state.meter()
	var bar := meter.bar_at(map.beat_at(seconds))
	var loop := floori(bar / DemoSong.BARS)
	var points := map.to_array()
	var meter_points := meter.to_array()
	var key := window_key(role, loop)
	_ask_window(role, points, meter_points, loop, key)
	if fposmod(bar, DemoSong.BARS) > DemoSong.BARS * 0.5:
		_ask_window(role, points, meter_points, loop + 1, window_key(role, loop + 1))
	return _windows.get(key, [])


## "<role>|<tempo map><meter>|<loop>": a window of a part, for the song's tempo and signature as
## they are now.
func window_key(role: String, loop: int) -> String:
	return "%s|%s%s|%d" % [role, state.tempo_map().to_array(), state.meter().to_array(), loop]


func _ask_window(role: String, points: Array, meter_points: Array, loop: int, key: String) -> void:
	if _windows.has(key):
		return
	if not _windows_pending.has(key):
		var result := [null]
		var task := WorkerThreadPool.add_task(func():
			var made := DemoSong.render_window(role, points, loop, meter_points)
			result[0] = [DemoSong.encode(made[0]), made[1]], false, "render a window of the demo song")
		_windows_pending[key] = [task, result]
		return
	# Collected here, on the main thread, as MIDI renders are (`midi_stream`): every task is
	# waited for, and none outlives the engine.
	var running: Array = _windows_pending[key]
	if not WorkerThreadPool.is_task_completed(running[0]):
		return
	WorkerThreadPool.wait_for_task_completion(running[0])
	_windows_pending.erase(key)
	var made: Array = running[1][0]
	var wav := DemoSong.stream_of(made[0])
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_windows[key] = [wav, made[1]]
	_prune_windows(points, meter_points, loop)


## Only the windows of the map and meter playing, near where the playhead is.
func _prune_windows(points: Array, meter_points: Array, loop: int) -> void:
	var prefix := "|%s%s|" % [points, meter_points]
	for key in _windows.keys():
		var at := int(String(key).get_slice("|", 2))
		if not String(key).contains(prefix) or at < loop - 1 or at > loop + 2:
			_windows.erase(key)


var _rendering_key := ""


func _render_parts() -> void:
	var tempo := state.tempo
	var sig := parts_signature()
	var key := "%s/%s" % [tempo, sig]
	_rendering_key = key
	var roles := _roles()
	var fresh := {}
	# All of a tempo's parts change over together. Swapped in one at a time, the drums would
	# be at the new tempo while the bass was still at the old one.
	DemoSong.render_async(roles, tempo, func(role: String, wav: AudioStreamWAV):
		if not is_instance_valid(self) or _rendering_key != key:
			return
		fresh[role] = wav
		if fresh.size() < roles.size():
			return
		_parts = fresh
		_parts_key = key
		for index in _players:
			for p in _players[index]:
				(p as AudioStreamPlayer).stop()
		connection_changed.emit(), sig)


## A new tempo or signature is a new render. The old parts go on playing until the new ones land,
## so a tempo knob turned mid-song changes the music a moment later rather than stopping it.
func _on_transport_changed() -> void:
	if "%s/%s" % [state.tempo, parts_signature()] != _rendering_key:
		_render_parts()


## The item under the playhead on this track, or null. Muted items are not there. Where items
## overlap, the newest one plays: a take recorded over the song is what you want to hear there.
func item_at(index: int, seconds: float) -> MixState.ItemState:
	var items: Array = (state.tracks[index] as MixState.TrackState).items
	for n in range(items.size() - 1, -1, -1):
		var it := items[n] as MixState.ItemState
		if not it.muted and seconds >= it.start and seconds < it.start + it.length:
			return it
	return null


## Keeps every track's players where the song clock says they should be: playing inside an
## item, silent outside one, and put back when they have drifted. A demo part is locked to the
## song's bar grid rather than to the item's start, so splitting or moving an item never shifts
## the music inside it off the beat. A recorded take is locked to its item instead: it is that
## item's sound, from where in the file the item begins.
func _sync_players() -> void:
	var pos := state.position_seconds
	var since := AudioServer.get_time_since_last_mix()
	for index in _players:
		# Nothing but the click while counting in to a recording, as in Reaper.
		var it := item_at(index, pos) if state.playing and not state.song_held() else null
		var stream: AudioStreamWAV = null
		var expected := 0.0
		var wraps := false
		var loop_length := 0.0
		if it != null and not it.source.is_empty():
			if it.is_looped():
				stream = looped_stream(it.source, it.loop_start, it.loop_end)
				loop_length = it.loop_end - it.loop_start
			else:
				stream = take_stream(it.source)
			expected = it.file_time(pos)
			if stream != null and not it.is_looped() and expected >= stream.get_length():
				stream = null
		elif it != null and not it.notes.is_empty():
			# Silent for the moment it takes to render, then on the item's own clock: its notes are
			# seconds from its left edge.
			stream = midi_stream(it)
			expected = pos - it.start
			if stream != null and expected >= stream.get_length():
				stream = null
		elif it != null and parts_windowed() and state.tracks[index].part != "":
			# Through the tempo's changes: the window holding the playhead, played from its start.
			var window := _part_window(state.tracks[index].part, pos)
			if not window.is_empty():
				stream = window[0]
				expected = pos - float(window[1])
				if expected < 0.0 or expected >= stream.get_length():
					stream = null
		elif it != null:
			stream = _parts.get(state.tracks[index].part)
			if stream != null:
				expected = fposmod(pos, stream.get_length())
				wraps = true
		var level := item_level(it, pos) if it != null else 0.0
		for p in _players[index]:
			var player := p as AudioStreamPlayer
			player.volume_db = level
			if stream == null:
				if player.playing:
					player.stop()
				continue
			if player.stream != stream or not player.playing:
				player.stream = stream
				_start(player, expected)
				continue
			var off := _drift(player, player.get_playback_position() + since - expected)
			if wraps:
				var length := stream.get_length()
				off = wrapf(off, -length * 0.5, length * 0.5)
			elif loop_length > 0.0:
				off = wrapf(off, -loop_length * 0.5, loop_length * 0.5)
			if absf(off) > DRIFT_SECONDS:
				reseeks += 1
				_start(player, expected)


## An item's own level at `seconds`, in dB (MixState.ItemState.level_db). Applied a frame at a
## time, which is smooth for a fade of more than a few frames; a shorter one wants the engine
## mixing its own players (see docs/loop_backlog.md, step 7).
static func item_level(it: MixState.ItemState, seconds: float) -> float:
	return it.level_db(seconds)


## The click, while the transport runs with the metronome on: into the master, so it is in what
## the host hears and what guests are sent (they play to it, and time against it), and on the
## bar grid, a click on every beat.
func _sync_click() -> void:
	if _click == null:
		_click = AudioStreamPlayer.new()
		_click.name = "Click"
		add_child(_click)
	if not (state.playing and state.metronome) or _master_bus < 0:
		if _click.playing:
			_click.stop()
		# Made while stopped, so pressing play does not wait for it.
		if state.metronome and _click_windowed() and _master_bus >= 0:
			_click_window_for(state.position_seconds)
		return
	_click.bus = MASTER_BUS
	if _click_windowed():
		_sync_click_window()
		return
	var wanted := "%s/%d" % [state.tempo, state.beats_per_bar]
	if wanted != _click_for:
		_click.stream = DawKitMetronome.bar(state.tempo, state.beats_per_bar, int(AudioServer.get_mix_rate()))
		_click_for = wanted
		_click.stop()
	var length := _click.stream.get_length()
	var expected := fposmod(state.position_seconds, length)
	if not _click.playing:
		_start(_click, expected)
		return
	var off := wrapf(_drift(_click, _click.get_playback_position() + AudioServer.get_time_since_last_mix() - expected),
			-length * 0.5, length * 0.5)
	if absf(off) > DRIFT_SECONDS:
		reseeks += 1
		_start(_click, expected)


## Whether the click is a window of the song's own clicks rather than one bar looping: with tempo
## or signature changes, or a signature not counted in quarters.
func _click_windowed() -> bool:
	return not state.tempo_points.is_empty() or not state.time_signature_points.is_empty() or state.beat_unit != 4


## With tempo changes a bar does not repeat, so the click is a window of the song's own clicks
## (DawKitMetronome.span) from the bar the playhead is in, made again when the playhead nears its
## end or leaves it, or the map changes.
func _sync_click_window() -> void:
	var at := state.position_seconds
	var made := _click_window_for(at)
	var into := at - _click_from
	if made > 0.0:
		# The song went on while the window was made: started where the playhead was before it,
		# the click would be that much behind, and stay there (measured: 4-17 ms late).
		_start(_click, into + made)
		return
	if not _click.playing:
		_start(_click, into)
		return
	if absf(_drift(_click, _click.get_playback_position() + AudioServer.get_time_since_last_mix() - into)) > DRIFT_SECONDS:
		reseeks += 1
		_start(_click, into)


## A window of clicks holding `at`, made unless the one there already does: how long making it
## took, in seconds, or 0 when it was not made.
## One bar of click, looping, for the lanes (LaneEngine.click_clips), made once per tempo and
## signature.
var _lane_click := {}


func lane_click_bar(key: String, rate: int) -> AudioStreamWAV:
	if not _lane_click.has(key):
		_lane_click.clear()
		_lane_click[key] = DawKitMetronome.bar(state.tempo, state.beats_per_bar, rate)
	return _lane_click[key]


func _ensure_click() -> void:
	if _click == null:
		_click = AudioStreamPlayer.new()
		_click.name = "Click"
		add_child(_click)


func _click_window_for(at: float) -> float:
	_ensure_click()
	var key := "%s/%s/%d" % [state.tempo_points, state.time_signature_points, state.beats_per_bar] \
			+ "/%d/%s" % [state.beat_unit, state.tempo]
	var into := at - _click_from
	if key == _click_for and into >= 0.0 and into <= CLICK_WINDOW - CLICK_WINDOW_LEAD:
		return 0.0
	var map := state.tempo_map()
	var meter := state.meter()
	var began := Time.get_ticks_usec()
	_click_from = map.seconds_at(meter.beat_of_bar(floorf(meter.bar_at(map.beat_at(at)) + 0.000001)))
	_click.stream = DawKitMetronome.span(map, meter, _click_from, CLICK_WINDOW,
			int(AudioServer.get_mix_rate()))
	_click_for = key
	return maxf(float(Time.get_ticks_usec() - began) / 1000000.0, 0.000001)


func monitor_bus(track_index: int) -> StringName:
	return AudioServer.get_bus_name(_bus[track_index]) if _bus.has(track_index) else &""


## Seconds of sound the card has mixed since the clock started, to the sample, or NAN where
## nothing is mixed (a headless run).
func audio_time() -> float:
	if AudioServer.get_driver_name() == "Dummy":
		return NAN
	if _clock == null:
		var silence := AudioStreamWAV.new()
		silence.format = AudioStreamWAV.FORMAT_8_BITS
		silence.mix_rate = int(AudioServer.get_mix_rate())
		var data := PackedByteArray()
		data.resize(int(CLOCK_SECONDS * silence.mix_rate))
		silence.data = data
		silence.loop_mode = AudioStreamWAV.LOOP_FORWARD
		silence.loop_end = data.size()
		_clock = AudioStreamPlayer.new()
		_clock.name = "Clock"
		_clock.stream = silence
		add_child(_clock)
		_clock.play()
		_clock_turns = 0
		_clock_raw = 0.0
	if not _clock.playing:
		return NAN
	var raw := _clock.get_playback_position()
	if raw < _clock_raw - CLOCK_SECONDS * 0.5:
		_clock_turns += 1
	_clock_raw = raw
	return _clock_turns * CLOCK_SECONDS + raw + AudioServer.get_time_since_last_mix()


## Where a player told to start now should start: a player sounds from the next mix, by which
## time the song has moved on by what is left until it.
static func start_at(expected: float) -> float:
	return expected + AudioServer.get_time_to_next_mix()


func _start(player: AudioStreamPlayer, expected: float) -> void:
	var from := start_at(expected)
	player.play(from)
	player.set_meta(&"bias", NAN)
	player.set_meta(&"from", from)


## How far a player has moved off the clock since it started. What its position reads against
## the clock right after a start is not zero -- the playback position a player reports is a mix
## step out either way, by where in the step the start fell -- but it is the same from then on, as
## the one mixer moves both; so that first reading is the player's own, and only a change from it
## is drift.
func _drift(player: AudioStreamPlayer, off: float) -> float:
	var bias: float = player.get_meta(&"bias", NAN)
	if is_nan(bias):
		# Not until it has been mixed: before that it reads where it was told to start.
		if is_equal_approx(player.get_playback_position(), float(player.get_meta(&"from", -1.0))):
			return 0.0
		player.set_meta(&"bias", off)
		return 0.0
	return off - bias


## What a MIDI item sounds like depends on nothing but its notes and its length.
static func midi_key(it: MixState.ItemState) -> String:
	return "%d/%s" % [hash(it.notes), it.length]


## A MIDI item's sound, or null while it is still being rendered (`wait` waits for it). The render
## is the item's notes through the instrument, each on its own sample, as a 16-bit stereo stream.
func midi_stream(it: MixState.ItemState, wait := false) -> AudioStreamWAV:
	var key := midi_key(it)
	if _midi_streams.has(key):
		return _midi_streams[key]
	if not _midi_tasks.has(key):
		var result := [null]
		var notes := PackedFloat64Array(Array(it.notes))
		var seconds := it.length
		var rate := int(AudioServer.get_mix_rate())
		var task := WorkerThreadPool.add_task(func(): result[0] = render_midi(notes, seconds, rate),
				false, "render a MIDI item")
		_midi_tasks[key] = [task, result]
	var running: Array = _midi_tasks[key]
	if not wait and not WorkerThreadPool.is_task_completed(running[0]):
		return null
	WorkerThreadPool.wait_for_task_completion(running[0])
	_midi_tasks.erase(key)
	_midi_streams[key] = running[1][0]
	if _midi_streams.size() > KEPT_RENDERS:
		prune_renders()
	return _midi_streams[key]


## Renders of what is no longer on the timeline let go: every edit to a MIDI item is a new one.
func prune_renders() -> void:
	var wanted := {}
	for index in state.track_indices():
		for it in state.track(index).items:
			if not it.notes.is_empty():
				wanted[midi_key(it)] = true
	for key in _midi_streams.keys():
		if not wanted.has(key):
			_midi_streams.erase(key)


## Notes through the instrument, as a stream. Safe off the main thread.
static func render_midi(notes: PackedFloat64Array, seconds: float, rate: int) -> AudioStreamWAV:
	var frames := DawKitTine.render_notes(notes, seconds, float(rate))
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i in frames.size():
		data.encode_s16(i * 4, int(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = rate
	wav.data = data
	return wav


## A recorded take's sound, read from the host's takes folder once and kept.
func take_stream(source: String) -> AudioStreamWAV:
	if not _take_streams.has(source):
		var path := media_path(source)
		_take_streams[source] = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	return _take_streams[source]


## The same sound set to loop between two points in the file, made once per loop asked for:
## the player then goes round on its own, and the clock only has to check it now and then.
func looped_stream(source: String, from: float, to: float) -> AudioStreamWAV:
	var key := "%s@%s-%s" % [source, from, to]
	if not _take_streams.has(key):
		var base := take_stream(source)
		var looped: AudioStreamWAV = null
		if base != null:
			looped = base.duplicate() as AudioStreamWAV
			looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
			looped.loop_begin = int(from * base.mix_rate)
			looped.loop_end = mini(int(to * base.mix_rate), int(base.get_length() * base.mix_rate))
		_take_streams[key] = looped
	return _take_streams[key]


## The song clock. The playhead is moved by the sound card, not by the frame: a silent player
## runs all the time, and while the song plays the playhead is where it was when play (or a
## seek) began plus how far that player has been mixed since, to the sample. Every other player
## is started against this clock and kept to it, so the playhead, the click and every part are
## the same time. Without a sound card to mix (the Dummy driver of a headless run) the frame
## moves it, as it did.
func _drive_meters(delta: float) -> void:
	if lanes != null:
		lanes.drive(delta)
		state.position_string = state.bar_beat(state.position_seconds)
		_drive_levels()
		return
	if state.playing:
		var now := audio_time()
		if is_nan(now):
			state.position_seconds += delta
		else:
			if state.position_seconds != _clock_said:
				# Play pressed, or the playhead moved by someone: the clock starts from here.
				_clock_origin = state.position_seconds - now
			state.position_seconds = _clock_origin + now
		if state.looping and state.has_loop_range() and state.position_seconds >= state.loop_end:
			state.position_seconds = state.loop_start + fmod(state.position_seconds - state.loop_end,
					state.loop_end - state.loop_start)
			if not is_nan(now):
				_clock_origin = state.position_seconds - now
		_clock_said = state.position_seconds
	else:
		_clock_said = -1.0
	state.position_string = state.bar_beat(state.position_seconds)
	_sync_players()
	_sync_click()
	_drive_levels()


## The meters, and the playhead, to the room.
func _drive_levels() -> void:
	for index in _bus:
		var t: MixState.TrackState = state.tracks[index]
		t.vu_l = meter(AudioServer.get_bus_peak_volume_left_db(_bus[index], 0))
		t.vu_r = meter(AudioServer.get_bus_peak_volume_right_db(_bus[index], 0))
		record_for_replication("/track/%d/vu/L" % index, [t.vu_l])
		record_for_replication("/track/%d/vu/R" % index, [t.vu_r])
	if _master_bus >= 0:
		var m := state.master
		m.vu_l = meter(AudioServer.get_bus_peak_volume_left_db(_master_bus, 0))
		m.vu_r = meter(AudioServer.get_bus_peak_volume_right_db(_master_bus, 0))
		record_for_replication("/master/vu/L", [m.vu_l])
		record_for_replication("/master/vu/R", [m.vu_r])
	record_for_replication("/beat/str", [state.position_string])
	record_for_replication("/time", [state.position_seconds])
	state.transport_changed.emit()


## A peak in dB as the meters read it: on the fader's own law, the way Reaper's OSC meters are.
func meter(db: float) -> float:
	return clampf(db_to_taper(db), 0.0, 1.0) if db > -90.0 else 0.0


## What a host passes on to guests while this is its DAW: the master bus, captured.
func mix_source() -> MixSource:
	return BusSource.new(self)


class BusSource extends MixSource:
	var _backend: GodotBackend
	var _resampler := Resampler.new()

	func _init(backend: GodotBackend) -> void:
		_backend = backend

	func start() -> bool:
		return _backend._capture != null

	func read() -> PackedVector2Array:
		var c := _backend._capture
		if c == null:
			return PackedVector2Array()
		var n := c.get_frames_available()
		var got := c.get_buffer(n) if n > 0 else PackedVector2Array()
		return resample(got, AudioServer.get_mix_rate())

	func resample(got: PackedVector2Array, from_rate: float) -> PackedVector2Array:
		return _resampler.resample(got, from_rate, MixFeed.RATE)

	func describe() -> String:
		return "The built-in mix"

	func latency_ms() -> float:
		return AudioServer.get_time_to_next_mix() * 1000.0
