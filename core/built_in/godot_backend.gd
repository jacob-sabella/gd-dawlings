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
##     reverb return returns reverb;
##   - meters read off the buses' peaks rather than synthesised;
##   - a cue per track on request (`set_cues`): a third player of the part, through the track's
##     own effects but not its fader, on a bus that plays to this machine's headphones only;
##   - a demo song (DemoSong), one synthesised part per instrument, played through the
##     timeline's items: an item is a window in which its track's part sounds.
##
## It is driven from the state's own signals rather than by overriding each command, so undo,
## redo, a guest's intent and a local hand all reach the speakers by the one path.
##
## Not done: recording, third-party plugins, the user's own audio files, sample-accurate
## automation. Sends are taken before the track's effects rather than after them, because
## Godot routes a bus to exactly one place and the send is a second player rather than a tap.

const BUS_PREFIX := "R3D "
const MASTER_BUS := "R3D Master"
const CUE_PREFIX := "R3D Cue "
## How far a part's player may drift from the song clock before it is put back. Under a mix
## buffer of drift is inaudible; a re-seek is a small click, so this errs towards rare.
const DRIFT_SECONDS := 0.06

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
## Track index -> fx index -> FX kind.
var _kinds := {}
## Role -> finished part.
var _parts := {}
var _parts_tempo := 0.0
var _master_bus := -1
var _capture: AudioEffectCapture
## The tracks being cued, in order.
var _cues: Array[int] = []
## Recorded take file name -> its sound, or null when the file is not on this machine.
var _take_streams := {}


func summary() -> String:
	var waiting := _waiting_roles().size()
	return "built-in: Godot audio" + (" (rendering %d parts)" % waiting if waiting > 0 else "")


func can(capability: StringName) -> bool:
	return super(capability)


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
	_connect_state()
	_render_parts()
	_apply_everything()
	connection_changed.emit()
	return true


func close() -> void:
	super()
	for list in _players.values():
		for p in list:
			(p as Node).queue_free()
	_players.clear()
	_remove_buses()


func _exit_tree() -> void:
	_remove_buses()


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
		if track_index in _cues:
			_build_cues()
	state.fx_changed.emit(track_index, fx_index)
	return fx_index


## The chain is rearranged in the cache by the stand-in; the effects on the buses follow it, by
## the name each slot now holds -- a copy is a new effect of the same kind, not the same one.
func move_fx(from_track: int, fx_index: int, to_track: int, to_fx: int, copy: bool) -> void:
	var kind: StringName = _kinds.get(from_track, {}).get(fx_index, &"")
	super(from_track, fx_index, to_track, to_fx, copy)
	if kind == &"":
		return
	for index in [from_track, to_track]:
		_restack(index, kind)


## Lay a track's bus effects down again in the order its chain now says.
func _restack(track_index: int, moved_kind: StringName) -> void:
	var by_name := {}
	for k in FXCatalogue.kinds():
		by_name[FXCatalogue.kinds()[k]["name"]] = k
	by_name[FXCatalogue.kinds()[moved_kind]["name"]] = moved_kind
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
		var t: MixState.TrackState = state.tracks[index]
		for send_index in t.sends:
			var dest: int = (t.sends[send_index] as MixState.SendState).resolve(state)
			# A key goes to a detector, and nothing here listens for one: playing it into the
			# destination's mix would make a sidechain an ordinary send.
			if (t.sends[send_index] as MixState.SendState).key or not _bus.has(dest):
				continue
			var sb := AudioServer.bus_count
			AudioServer.add_bus(sb)
			AudioServer.set_bus_name(sb, "%s%d>%d" % [BUS_PREFIX, index, dest])
			AudioServer.set_bus_send(sb, AudioServer.get_bus_name(_bus[dest]))
			var p := AudioStreamPlayer.new()
			p.bus = AudioServer.get_bus_name(sb)
			p.set_meta(&"send", send_index)
			add_child(p)
			list.append(p)
		_players[index] = list
	if not _cues.is_empty():
		_build_cues()


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


func _on_track_changed(_index: int, _field: StringName) -> void:
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
				AudioServer.set_bus_mute(AudioServer.get_bus_index(p.bus), not audible(index))


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
		var role := DemoSong.role_of(state.tracks[index].name)
		if role != "" and role not in out:
			out.append(role)
	return out


func _waiting_roles() -> Array:
	return _roles().filter(func(r): return not _parts.has(r) or _parts_tempo != _rendering_tempo)


var _rendering_tempo := 0.0


func _render_parts() -> void:
	var tempo := state.tempo
	_rendering_tempo = tempo
	var roles := _roles()
	var fresh := {}
	# All of a tempo's parts change over together. Swapped in one at a time, the drums would
	# be at the new tempo while the bass was still at the old one.
	DemoSong.render_async(roles, tempo, func(role: String, wav: AudioStreamWAV):
		if not is_instance_valid(self) or _rendering_tempo != tempo:
			return
		fresh[role] = wav
		if fresh.size() < roles.size():
			return
		_parts = fresh
		_parts_tempo = tempo
		for index in _players:
			for p in _players[index]:
				(p as AudioStreamPlayer).stop()
		connection_changed.emit())


## A new tempo is a new render. The old parts go on playing until the new ones land, so a
## tempo knob turned mid-song changes the music a moment later rather than stopping it.
func _on_transport_changed() -> void:
	if state.tempo != _rendering_tempo:
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
		var it := item_at(index, pos) if state.playing else null
		var stream: AudioStreamWAV = null
		var expected := 0.0
		var wraps := false
		if it != null and not it.source.is_empty():
			stream = take_stream(it.source)
			expected = pos - it.start + it.source_offset
			if stream != null and expected >= stream.get_length():
				stream = null
		elif it != null:
			stream = _parts.get(DemoSong.role_of(state.tracks[index].name))
			if stream != null:
				expected = fposmod(pos, stream.get_length())
				wraps = true
		for p in _players[index]:
			var player := p as AudioStreamPlayer
			if stream == null:
				if player.playing:
					player.stop()
				continue
			if player.stream != stream or not player.playing:
				player.stream = stream
				player.play(expected)
				continue
			var off := player.get_playback_position() + since - expected
			if wraps:
				var length := stream.get_length()
				off = wrapf(off, -length * 0.5, length * 0.5)
			if absf(off) > DRIFT_SECONDS:
				player.play(expected)


## A recorded take's sound, read from the host's takes folder once and kept.
func take_stream(source: String) -> AudioStreamWAV:
	if not _take_streams.has(source):
		var path := AudioTake.DIR.path_join(source.get_file())
		_take_streams[source] = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	return _take_streams[source]


func _drive_meters(delta: float) -> void:
	if state.playing:
		state.position_seconds += delta
		if state.looping and state.has_loop_range() and state.position_seconds >= state.loop_end:
			state.position_seconds = state.loop_start + fmod(state.position_seconds - state.loop_end,
					state.loop_end - state.loop_start)
	state.position_string = state.bar_beat(state.position_seconds)
	_sync_players()

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
