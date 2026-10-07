class_name OfflineBackend
extends DAWBackend

## No DAW at all: a synthetic session, so the studio can be built, lit, walked around and
## photographed with nothing running behind it.
##
## NOT A MOCK. It is a development stand-in and it ships, which is why it is a backend like any
## other rather than something in tests/. Launching the project with no arguments has to show a
## working control room -- otherwise every screenshot, every lighting change and every piece of
## layout work would need Reaper open, and the first thing anyone sees on opening the project
## would be an empty room.
##
## It is also the cheapest proof that core/daw/daw_backend.gd is a real seam: the console, the
## rack, the bay and the deck are driven by this without knowing, and nothing above the backend
## layer contains a branch for it.

func _process(delta: float) -> void:
	_drive_meters(delta)
	tick_replication(delta)


func open(_options: Dictionary = {}) -> bool:
	_populate()
	set_process(true)
	connection_changed.emit()
	return true


func close() -> void:
	set_process(false)


func is_live() -> bool:
	return true


func summary() -> String:
	return "offline: synthetic mix"


## No DAW means no routing engine to change. The patchbay reads this and declines the gesture
## rather than drawing a cable that stands for nothing.
func can(capability: StringName) -> bool:
	return capability != Capability.ROUTING


# --- the stand-in mix ---------------------------------------------------------------------

## A plausible session. The names are deliberately a real-looking drum/band session: twelve
## tracks called "Track 1" through "Track 12" would hide every layout problem that long names
## cause, which is most of what this stand-in exists to expose.
func _populate() -> void:
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
		t.volume_db = taper_to_db(d["v"])
		t.pan = d["p"]
		t.colour = d["c"]
		t.vu_l = 0.0
		t.vu_r = 0.0
	# A master sitting a little under unity, which is what a mix that has been balanced looks
	# like and what makes the master fader visibly NOT at the top of its travel.
	state.master.volume = 0.69
	state.master.volume_db = taper_to_db(0.69)

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
func _drive_meters(delta: float) -> void:
	state.position_seconds += delta
	var beats := state.position_seconds * state.tempo / 60.0
	state.position_string = "%d.%d.%02d" % [int(beats / 4.0) + 1, int(fmod(beats, 4.0)) + 1, int(fmod(beats, 1.0) * 100.0)]

	var bus_l := 0.0
	var bus_r := 0.0
	for index in state.track_indices():
		var t: MixState.TrackState = state.tracks[index]
		if t.mute:
			t.vu_l = 0.0
			t.vu_r = 0.0
			continue
		var phase := fmod(beats + index * 0.37, 4.0)
		var hit := exp(-phase * 2.2) if index <= 4 else 0.45 + 0.35 * sin(beats * 0.8 + index)
		var level := clampf(t.volume * (0.18 + 0.8 * hit), 0.0, 1.0)
		t.vu_l = level
		t.vu_r = clampf(level * (1.0 - 0.18 * absf(t.pan - 0.5)), 0.0, 1.0)
		# Recorded for replication directly. Meters are written to the cache without a signal,
		# to avoid fanning a storm out to every surface -- but a guest watching a hosted demo
		# should still see them move, so the one step that would have done is done here.
		# Summed as power rather than added, which is what keeps twelve tracks at a sensible
		# level from pinning the bus at 1.0 the moment the mix has more than a few things in it.
		bus_l += t.vu_l * t.vu_l
		bus_r += t.vu_r * t.vu_r
		record_for_replication("/track/%d/vu/L" % index, [t.vu_l])
		record_for_replication("/track/%d/vu/R" % index, [t.vu_r])

	var m := state.master
	m.vu_l = clampf(sqrt(bus_l) * m.volume * 0.46, 0.0, 1.0)
	m.vu_r = clampf(sqrt(bus_r) * m.volume * 0.46, 0.0, 1.0)
	record_for_replication("/master/vu/L", [m.vu_l])
	record_for_replication("/master/vu/R", [m.vu_r])
	record_for_replication("/time/str", [state.position_string])
	state.transport_changed.emit()


# --- commands -----------------------------------------------------------------------------
#
# Applied straight to the cache. There is no DAW to ask and therefore nothing to wait for, so
# unlike a real backend these take effect on the same frame -- the one behavioural difference
# the stand-in has, and the reason a fader never fights its own echo here.

func set_track_volume(index: int, taper: float) -> void:
	var t := state.track(index)
	state.set_track_field(index, &"volume", clampf(taper, 0.0, 1.0))
	state.set_track_field(index, &"volume_db", taper_to_db(t.volume))
	record_for_replication("/track/%d/volume" % index, [t.volume])


func set_track_pan(index: int, pan: float) -> void:
	state.set_track_field(index, &"pan", clampf(pan, 0.0, 1.0))
	record_for_replication("/track/%d/pan" % index, [state.track(index).pan])


func set_track_mute(index: int, muted: bool) -> void:
	state.set_track_field(index, &"mute", muted)
	record_for_replication("/track/%d/mute" % index, [1.0 if muted else 0.0])


func set_track_solo(index: int, soloed: bool) -> void:
	state.set_track_field(index, &"solo", soloed)
	record_for_replication("/track/%d/solo" % index, [1.0 if soloed else 0.0])


func set_track_rec_arm(index: int, armed: bool) -> void:
	state.set_track_field(index, &"rec_arm", armed)
	record_for_replication("/track/%d/recarm" % index, [1.0 if armed else 0.0])


func set_master_volume(taper: float) -> void:
	state.set_master_field(&"volume", clampf(taper, 0.0, 1.0))
	state.set_master_field(&"volume_db", taper_to_db(state.master.volume))
	record_for_replication("/master/volume", [state.master.volume])


func set_master_pan(pan: float) -> void:
	state.set_master_field(&"pan", clampf(pan, 0.0, 1.0))
	record_for_replication("/master/pan", [state.master.pan])


func set_fx_param(track_index: int, fx_index: int, param: int, value: float) -> void:
	var f := state.fx(track_index, fx_index)
	f.params[param] = clampf(value, 0.0, 1.0)
	state.fx_changed.emit(track_index, fx_index)
	record_for_replication("/track/%d/fx/%d/fxparam/%d/value" % [track_index, fx_index, param], [f.params[param]])


func set_fx_enabled(track_index: int, fx_index: int, enabled: bool) -> void:
	var f := state.fx(track_index, fx_index)
	f.enabled = enabled
	state.fx_changed.emit(track_index, fx_index)
	record_for_replication("/track/%d/fx/%d/bypass" % [track_index, fx_index], [1.0 if enabled else 0.0])


func transport_play() -> void:
	state.playing = true
	state.transport_changed.emit()
	record_for_replication("/play", [1.0])


func transport_stop() -> void:
	state.playing = false
	state.recording = false
	state.transport_changed.emit()
	record_for_replication("/play", [0.0])


func transport_record() -> void:
	state.playing = true
	state.recording = true
	state.transport_changed.emit()
	record_for_replication("/record", [1.0])


func snapshot() -> Array:
	return MixWire.snapshot(state)


func apply_replicated(batch: Array) -> void:
	MixWire.apply_replicated(state, batch)
