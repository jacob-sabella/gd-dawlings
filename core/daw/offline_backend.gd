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

## Pad the synthetic session out to this many tracks. 0 means the authored thirteen.
##
## Set before open(). It exists so the two questions a thirteen-track demo cannot answer -- what
## does the studio COST at session scale, and does the bank paging work -- can be asked without
## Reaper running, which is the whole point of having a stand-in at all.
var track_count: int = 0


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
## No routing engine to change, so no patching. Banking IS offered once the synthetic project
## is larger than a bank, because at that size the stand-in is modelling exactly the situation
## the bank buttons exist for -- and a 90-track stand-in that silently showed 64 strips would
## reproduce the bug those buttons were written to make visible.
func can(capability: StringName) -> bool:
	if capability == Capability.ROUTING:
		return false
	if capability == Capability.TRACK_BANKING:
		return state != null and state.project_track_count > state.bank_size
	return true


# --- the stand-in mix ---------------------------------------------------------------------

## A plausible session. The names are deliberately a real-looking drum/band session: twelve
## tracks called "Track 1" through "Track 12" would hide every layout problem that long names
## cause, which is most of what this stand-in exists to expose.
func _populate() -> void:
	# "f" is Reaper's I_FOLDERDEPTH: 1 opens a folder on this track, -1 closes one, 0 stays.
	#
	# PARENT FIRST, which is the part that is easy to get wrong. In Reaper the track carrying
	# the 1 IS the folder -- it is the submix bus, and it sits at the OUTER level with its
	# children indented under it. A tree that puts the 1 on "Kick" is legal and is what this
	# demo had, but it reads as a desk that has divided the kick off from its own drums.
	#
	# The stand-in has a real tree at all because the console now draws group breaks from it,
	# and a demo at depth zero throughout would make that invisible in the only session anybody
	# can open without Reaper running.
	var demo := [
		{"n": "DRUMS", "v": 0.76, "p": 0.5, "c": Color(0.78, 0.40, 0.32), "f": 1},
		{"n": "Kick", "v": 0.78, "p": 0.5, "c": Color(0.86, 0.33, 0.28)},
		{"n": "Snare", "v": 0.72, "p": 0.5, "c": Color(0.88, 0.52, 0.24)},
		{"n": "Hat", "v": 0.61, "p": 0.63, "c": Color(0.84, 0.74, 0.3)},
		{"n": "OH L/R", "v": 0.67, "p": 0.5, "c": Color(0.55, 0.72, 0.35), "f": -1},
		{"n": "Bass DI", "v": 0.74, "p": 0.5, "c": Color(0.33, 0.66, 0.6)},
		{"n": "Rhodes", "v": 0.69, "p": 0.38, "c": Color(0.35, 0.56, 0.82)},
		{"n": "Gtr Amp", "v": 0.71, "p": 0.66, "c": Color(0.55, 0.45, 0.82)},
		{"n": "VOX", "v": 0.77, "p": 0.5, "c": Color(0.80, 0.40, 0.60), "f": 1},
		{"n": "Lead Vox", "v": 0.80, "p": 0.5, "c": Color(0.82, 0.42, 0.66)},
		{"n": "Vox Dbl", "v": 0.55, "p": 0.3, "c": Color(0.74, 0.46, 0.74), "f": -1},
		{"n": "Strings", "v": 0.64, "p": 0.5, "c": Color(0.46, 0.62, 0.78)},
		{"n": "Verb Rtn", "v": 0.58, "p": 0.5, "c": Color(0.42, 0.68, 0.72)},
	]
	# The authored project is thirteen tracks because that is a readable demo. It is NOT what a
	# session costs: a real desk is forty or ninety strips, and the only honest way to ask what
	# the studio draws at that size -- or how a 90-track bank behaves -- is to be able to make
	# one without Reaper open. Extra tracks cycle the authored list with the group pattern
	# continuing, so a scaled project is still a project rather than a wall of clones.
	if track_count > demo.size():
		var authored := demo.size()
		for i in range(authored, track_count):
			var source: Dictionary = demo[i % authored].duplicate()
			source["n"] = "%s %d" % [source["n"], 1 + i / authored]
			# Hue-rotated per cycle, so two tracks with the same role are not the same colour.
			var c: Color = source["c"]
			source["c"] = Color.from_hsv(fposmod(c.h + 0.11 * (i / authored), 1.0), c.s, c.v)
			demo.append(source)

	for i in demo.size():
		var d: Dictionary = demo[i]
		var t := state.track(i + 1)
		t.name = d["n"]
		t.volume = d["v"]
		t.volume_db = taper_to_db(d["v"])
		t.pan = d["p"]
		t.colour = d["c"]
		t.folder_depth = int(d.get("f", 0))
		t.vu_l = 0.0
		t.vu_r = 0.0
	# A master sitting a little under unity, which is what a mix that has been balanced looks
	# like and what makes the master fader visibly NOT at the top of its travel.
	state.master.volume = 0.69
	state.master.volume_db = taper_to_db(0.69)
	# The BANK is what a control surface streams and Reaper's is 64 wide. Below that the bank is
	# the project; above it the desk has to page, which is the case the bank buttons exist for
	# and which a thirteen-track stand-in could never reach.
	state.bank_size = mini(demo.size(), 64)
	state.project_track_count = demo.size()
	# AFTER the tempo is known. The arrangement is laid out in bars converted to seconds, so
	# arranging first put every section boundary at 120bpm spacing under a 92bpm ruler, and
	# "Chorus 1" landed three bars away from the bar its marker named.
	state.tempo = 92.0
	_arrange()


## An arrangement for the stand-in: a 96-bar song with a real structure.
##
## Structured rather than random, because a timeline is the one surface where random is
## instantly recognisable as wrong -- a drummer who stops for the chorus and a vocal that
## starts at bar 17 is what an arrangement looks like, and a field of noise is what a
## placeholder looks like.
func _arrange() -> void:
	var bar := 4.0 * 60.0 / state.tempo
	# (first bar, last bar) windows per section, named the way a session is.
	var sections := {
		"Intro": [1, 9], "Verse 1": [9, 25], "Chorus 1": [25, 41],
		"Verse 2": [41, 57], "Chorus 2": [57, 73], "Outro": [73, 89],
	}
	# Which sections each track plays in, by track index. This is the arrangement.
	var plays := {
		# 1 and 9 are the DRUMS and VOX buses, and a bus carries no media -- the items it
		# appears to have are its children's, summed. Giving them blocks would draw a lane
		# that does not exist in the project.
		2: ["Verse 1", "Chorus 1", "Verse 2", "Chorus 2", "Outro"],
		3: ["Verse 1", "Chorus 1", "Verse 2", "Chorus 2", "Outro"],
		4: ["Verse 1", "Chorus 1", "Verse 2", "Chorus 2"],
		5: ["Chorus 1", "Chorus 2", "Outro"],
		6: ["Verse 1", "Chorus 1", "Verse 2", "Chorus 2", "Outro"],
		7: ["Intro", "Verse 1", "Verse 2", "Outro"],
		8: ["Chorus 1", "Verse 2", "Chorus 2", "Outro"],
		10: ["Verse 1", "Chorus 1", "Verse 2", "Chorus 2"],
		11: ["Chorus 1", "Chorus 2"],
		12: ["Intro", "Chorus 1", "Chorus 2", "Outro"],
		# 13 is the reverb RETURN, which has no media either -- it has a plugin.
	}
	for index in plays:
		var items: Array = []
		for section in plays[index]:
			var window: Array = sections[section]
			var item := MixState.ItemState.new()
			item.index = items.size()
			item.start = (window[0] - 1) * bar
			item.length = (window[1] - window[0]) * bar
			item.name = "%s %s" % [state.track(index).name, section]
			items.append(item)
		state.set_track_items(index, items)

	state.markers.clear()
	for section in sections:
		state.markers[(sections[section][0] - 1) * bar] = section
	state.set_project_length(96 * bar)

	state.track(2).rec_arm = true
	state.track(10).rec_arm = true
	state.track(4).mute = true
	state.track(10).solo = true

	# A couple of FX chains, so the racks have something to stand for.
	for spec in [[2, "ReaEQ", ["Freq", "Gain", "Q", "Type"]], [2, "ReaComp", ["Thresh", "Ratio", "Attack", "Release"]],
			[6, "ReaComp", ["Thresh", "Ratio", "Attack", "Release"]], [10, "ReaEQ", ["Freq", "Gain", "Q", "Type"]],
			[10, "ReaVerbate", ["Size", "Damping", "Wet", "Dry"]], [13, "ReaVerbate", ["Size", "Damping", "Wet", "Dry"]]]:
		var track_index: int = spec[0]
		var f := state.fx(track_index, state.track(track_index).fx.size())
		f.name = spec[1]
		var names: Array = spec[2]
		for pi in names.size():
			f.param_names[pi] = names[pi]
			f.params[pi] = 0.3 + 0.5 * fmod(float(track_index * 7 + pi * 3) / 11.0, 1.0)

	# Sends into the reverb return, so the patchbay has real cables. BOTH the name and the
	# index are set, which is what a session with the ReaScript bridge loaded looks like: the
	# index is what the bay resolves against and the name is the fallback for OSC-only.
	var verb := 13
	for src in [3, 7, 10, 12]:
		var s := state.send(src, 0)
		s.dest_name = "Verb Rtn"
		s.dest_track = verb
		s.volume = 0.4 + 0.1 * src / 10.0

	# Bar 17, set as SECONDS and left for the clock to spell. Setting the string directly --
	# which this did -- put the tape deck's counter at bar 17 and the timeline's playhead at
	# bar 1 in the same photograph, because they read different fields of the same transport.
	state.position_seconds = 16.0 * 4.0 * 60.0 / state.tempo
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
