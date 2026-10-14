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
## What the project is called: not on the desk yet, but in a project file, and it has to survive
## being opened and saved again.
var project_title := "Demo"
## Autosave: once there are changes no save has kept, this many seconds later the host keeps a
## copy of the project in AUTOSAVE_DIR -- never over its own file, which only a save writes. Held
## while the transport runs, so a save's pause never lands in a take or a performance. 0 for
## never (the suite's setting, so a long run does not write one halfway through).
static var autosave_every := 300.0
const AUTOSAVE_DIR := "user://autosave"
## How many earlier copies are kept behind the newest ("Name.1.dawproject" the one before it, up
## to this many), each autosave pushing the others back one: a bad edit that was autosaved is not
## the only thing left.
const AUTOSAVE_KEEP := 4
## When the last copy was kept (Time.get_ticks_msec), or -1 for not yet.
var autosaved_at_msec := -1
var _autosaved_edits := -1
## The copy this run has written or already recovered: not one to offer back.
var _settled_copy := ""
var _autosave_due_msec := -1
## Plugin windows for the suite: the stand-in has no plugins to draw, so it says it cannot show
## their windows unless this is set, and then shows a plain picture that records what was done
## to it (PluginWindow). Never set by anything that ships.
var stand_in_windows := false
## The windows the stand-in has handed out, newest last, for whoever is checking.
var windows_opened: Array[PluginWindow] = []


func _process(delta: float) -> void:
	_drive_meters(delta)
	follow_count_in()
	follow_automation()
	tick_replication(delta)
	_tick_autosave()


## Where this project's copy is kept: by its file's name, or its title before it has one.
func autosave_path() -> String:
	var base := project_path.get_file().get_basename() if not project_path.is_empty() \
			else project_title.strip_edges().validate_filename()
	return AUTOSAVE_DIR.path_join("%s.%s" % [base if not base.is_empty() else "Untitled", ProjectFiles.EXTENSION])


## True when there are changes that neither a save nor the last copy has kept.
func needs_autosave() -> bool:
	return has_unsaved_changes() and _edits != _autosaved_edits


## The path of the copy `generation` autosaves back: 0 the newest, 1 the one before it.
func autosave_generation_path(generation: int) -> String:
	if generation <= 0:
		return autosave_path()
	var newest := autosave_path()
	return newest.get_basename() + ".%d.%s" % [generation, newest.get_extension()]


## The copies kept, newest first, each a path that exists.
func autosave_history() -> PackedStringArray:
	var found := PackedStringArray()
	for g in AUTOSAVE_KEEP + 1:
		var path := autosave_generation_path(g)
		if FileAccess.file_exists(path):
			found.append(path)
	return found


## Pushes each kept copy one place back, the oldest falling off, to make room for a new newest.
func _age_autosaves() -> void:
	if not FileAccess.file_exists(autosave_path()):
		return
	for g in range(AUTOSAVE_KEEP, 0, -1):
		var from := ProjectSettings.globalize_path(autosave_generation_path(g - 1))
		var to := ProjectSettings.globalize_path(autosave_generation_path(g))
		if FileAccess.file_exists(from):
			if FileAccess.file_exists(to):
				DirAccess.remove_absolute(to)
			DirAccess.rename_absolute(from, to)


func autosave() -> PackedStringArray:
	_settled_copy = autosave_path()
	_age_autosaves()
	var said := ProjectFiles.save(self, autosave_path(), true)
	_autosaved_edits = _edits
	autosaved_at_msec = Time.get_ticks_msec()
	_autosave_due_msec = -1
	return said


## Crash recovery: the autosave's copy of this project when an earlier run left one newer than the
## project's own file (or the project has no file yet), else "". Not this run's own copy, nor one
## already recovered.
func recoverable() -> String:
	var copy := autosave_path()
	if copy == _settled_copy or not FileAccess.file_exists(copy):
		return ""
	if not project_path.is_empty() and FileAccess.file_exists(project_path) \
			and FileAccess.get_modified_time(project_path) >= FileAccess.get_modified_time(copy):
		return ""
	return copy


## The recoverable copy opened in the project's place. It is still the same project, saved where
## it was (a save writes its own file, not the copy), and unsaved: what came back is in no file
## of its own yet.
func recover(generation := 0) -> PackedStringArray:
	var copy := recoverable()
	if copy.is_empty():
		return PackedStringArray(["no newer copy is kept"])
	if generation > 0:
		copy = autosave_generation_path(clampi(generation, 0, AUTOSAVE_KEEP))
		if not FileAccess.file_exists(copy):
			return PackedStringArray(["no copy that far back is kept"])
	var own := project_path
	_settled_copy = copy
	var said := ProjectFiles.open(self, copy)
	if project_path != copy:
		return said
	project_path = own
	name_project()
	_edits += 1
	return said


func _tick_autosave() -> void:
	if autosave_every <= 0.0 or not Session.is_authority() or not needs_autosave():
		_autosave_due_msec = -1
		return
	var now := Time.get_ticks_msec()
	if _autosave_due_msec < 0:
		_autosave_due_msec = now + int(autosave_every * 1000.0)
		return
	if now >= _autosave_due_msec and not state.playing and not state.recording:
		var said := autosave()
		if not said.is_empty():
			push_warning("Autosave: %s" % "; ".join(said))


func open(_options: Dictionary = {}) -> bool:
	_populate()
	publish_inputs()
	publish_fx_choices()
	name_project()
	set_process(true)
	connection_changed.emit()
	return true


func close() -> void:
	set_process(false)


func is_live() -> bool:
	return true


func summary() -> String:
	return "offline: synthetic mix"


## Routing is offered: the stand-in keeps its own sends (see `create_send`), and the built-in
## engine that extends it plays them. Banking IS offered once the synthetic project
## is larger than a bank, because at that size the stand-in is modelling exactly the situation
## the bank buttons exist for -- and a 90-track stand-in that silently showed 64 strips would
## reproduce the bug those buttons were written to make visible.
func can(capability: StringName) -> bool:
	if capability == Capability.TRACK_BANKING:
		return state != null and state.project_track_count > state.bank_size
	if capability == Capability.PLUGIN_WINDOW:
		return stand_in_windows
	if capability == Capability.RECORDS_OWN_INPUTS:
		return records_inputs
	if capability == Capability.RENDER:
		# The stand-in makes no sound to write.
		return false
	return true


## Which of the engine's own effects a slot is, or empty when it is only a name. The stand-in's
## FX are names standing for Reaper plugins; the built-in engine's are real.
func fx_kind(_track_index: int, _fx_index: int) -> StringName:
	return &""


## Where each clip's file is, by the name items carry: a project opened from a file unpacks its
## media somewhere of its own. A name not in here is a take, in AudioTake.DIR.
var media := {}
## Whether to stand in for a DAW that records its own inputs, as Reaper does. Off: the built-in
## engine cannot, and the stand-in is its model. The suite turns it on to play a host on Reaper.
var records_inputs := false
## How long before a count-in's first click the transport starts (GodotBackend's is a little, so
## that click is heard whole).
var count_in_lead := 0.0
## Instruments a project file gave a track that the engine cannot run (another DAW's plug-in), by
## track index, in dawkit's plain form: kept so the track saves with it, and played meanwhile
## through the engine's own.
var instruments := {}


## The signature a looped part is rendered in. Here rather than in the engine: a save renders the
## parts from the song alone, whichever backend is hosting.
func parts_signature() -> Vector2i:
	return Vector2i(maxi(state.beats_per_bar, 1), maxi(state.beat_unit, 1))


func set_media(where: Dictionary) -> void:
	media = where.duplicate()


func media_path(source: String) -> String:
	var name := source.get_file()
	if media.has(name):
		return media[name]
	return ProjectSettings.globalize_path(AudioTake.DIR.path_join(name))


## Puts the project's title and file name where the room can read them (MixState.project_title),
## after anything that changes either.
func name_project() -> void:
	if state.project_title == project_title and state.project_file == project_path.get_file():
		return
	state.project_title = project_title
	state.project_file = project_path.get_file()
	record_for_replication("/project/name", [state.project_title, state.project_file])
	state.project_named.emit()


func save_project(path: String) -> PackedStringArray:
	return ProjectFiles.save(self, path)


func open_project(path: String) -> PackedStringArray:
	return ProjectFiles.open(self, path)


func new_project(tracks := 4) -> PackedStringArray:
	return ProjectFiles.new_project(self, tracks)


## Called once a whole project has been put into `state` (ProjectBridge.load). `kinds` is
## track index -> fx index -> effect kind. The stand-in has nothing to rebuild; the built-in
## engine lays its buses and effects down again.
func project_loaded(_kinds: Dictionary) -> void:
	pass


## Which of Godot's effects each slot is, by track: the built-in engine's, which the stand-in
## does not run.
func _fx_kinds() -> Dictionary:
	return {}


func open_plugin_window(track_index: int, fx_index: int) -> PluginWindow:
	if not stand_in_windows or not state.tracks.has(track_index) \
			or state.fx(track_index, fx_index, false) == null:
		return null
	var picture := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.12, 0.13, 0.15))
	var w := PluginWindow.showing(picture)
	windows_opened.append(w)
	return w


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
		t.part = DemoSong.role_of(t.name)
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
## The Rhodes part is MIDI, as a keys part mostly is, so the stand-in's timeline has notes on
## it the way a guest's take will: a bar of each chord, played on beat one and pushed on the
## "and" of three. Item-relative, in the wire's five-number layout (see MidiTake).
func _comping(length: float, bar: float) -> PackedFloat32Array:
	# Am7, Fmaj7, C, G -- bass note then three above.
	var chords := [[45, 60, 64, 67], [41, 57, 60, 64], [48, 55, 60, 64], [43, 55, 59, 62]]
	var out := PackedFloat32Array()
	var beat := bar / 4.0
	var bars := int(round(length / bar))
	for b in bars:
		var chord: Array = chords[b % chords.size()]
		for hit in [[0.0, 2.25], [2.5, 1.4]]:
			for pitch in chord:
				var on: float = b * bar + hit[0] * beat
				out.append_array([on, on + hit[1] * beat, pitch, 84 if hit[0] == 0.0 else 70, 0])
	return out


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
			if state.track(index).name == "Rhodes":
				item.notes = _comping(item.length, bar)
			items.append(item)
		state.set_track_items(index, items)

	state.markers.clear()
	state.regions.clear()
	for section in sections:
		state.markers[(sections[section][0] - 1) * bar] = section
	state.set_project_length(96 * bar)

	state.track(2).rec_arm = true
	state.track(10).rec_arm = true
	# Armed tracks monitor as people set them: the vocal on auto, so it is heard on a punch-in,
	# and the other one on, as you would for an instrument you play along with.
	state.track(2).monitor = 2
	state.track(10).monitor = 1
	state.track(4).mute = true
	# No solo. There was one, on the lead vocal, to light a solo lamp in the demo -- and once
	# the meters started reading true, a soloed vocal meant every other strip on the desk sat
	# dead, which is right for a solo and wrong for a picture of a mix.

	# A couple of FX chains, so the racks have something to stand for.
	#
	# PARAMETER COUNTS ARE REALISTIC ON PURPOSE. These were four knobs apiece, and four knobs
	# fit on a faceplate -- so the rack's paging was never exercised by the only session anyone
	# can open without Reaper running, and the fact that it did not exist went unnoticed.
	# A real ReaEQ is four bands of four, a real ReaComp is a dozen and more. The stand-in has
	# to be at least as awkward as the thing it stands in for, or it designs the awkwardness
	# out of the feature. Same lesson as the folder structure.
	var eq_params := ["Band 1 Freq", "Band 1 Gain", "Band 1 Q", "Band 1 Type",
			"Band 2 Freq", "Band 2 Gain", "Band 2 Q", "Band 2 Type",
			"Band 3 Freq", "Band 3 Gain", "Band 3 Q", "Band 3 Type",
			"Band 4 Freq", "Band 4 Gain", "Band 4 Q", "Band 4 Type", "Wet", "Bypass"]
	var comp_params := ["Thresh", "Ratio", "Attack", "Release", "Knee", "RMS Size",
			"Pre-comp", "Makeup", "Dry", "Wet", "Lowpass", "Highpass", "Auto Makeup"]
	var verb_params := ["Size", "Damping", "Wet", "Dry", "Pre-delay", "Width"]
	for spec in [[2, "ReaEQ", eq_params], [2, "ReaComp", comp_params],
			[6, "ReaComp", comp_params], [10, "ReaEQ", eq_params],
			[10, "ReaVerbate", verb_params], [13, "ReaVerbate", verb_params]]:
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
	# Send 1, not 0: sends are numbered from one on the wire, as Reaper's OSC numbers them, and
	# a stand-in that counted from zero would be the one session where a send-level write and
	# the cable it moves disagreed about which send was meant.
	var verb := 13
	for src in [3, 7, 10, 12]:
		var s := state.send(src, 1)
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
	# The clock runs only while the transport does, and wraps round the loop when there is one
	# -- which is what makes a stopped transport, a seek and a loop testable without Reaper.
	if state.playing:
		state.position_seconds += delta
		if state.looping and state.has_loop_range() and state.position_seconds >= state.loop_end:
			state.position_seconds = state.loop_start + fmod(state.position_seconds - state.loop_end,
					state.loop_end - state.loop_start)
	var beats := state.beat_at(state.position_seconds)
	state.position_string = state.bar_beat(state.position_seconds)
	# Solo is exclusive: while anything is soloed, everything that is not is silent. A meter that
	# kept moving on a track you cannot hear is a meter that does not read true.
	var any_solo := false
	for index in state.track_indices():
		if (state.tracks[index] as MixState.TrackState).solo:
			any_solo = true
			break

	var bus_l := 0.0
	var bus_r := 0.0
	for index in state.track_indices():
		var t: MixState.TrackState = state.tracks[index]
		if t.mute or (any_solo and not t.solo) or not state.playing:
			# Falling, not snapping: a real meter's ballistics, and the reason a stop reads as
			# the music stopping rather than as the meters being switched off.
			t.vu_l = maxf(0.0, t.vu_l - delta * 2.5)
			t.vu_r = maxf(0.0, t.vu_r - delta * 2.5)
			bus_l += t.vu_l * t.vu_l * (0.0 if t.mute or (any_solo and not t.solo) else 1.0)
			bus_r += t.vu_r * t.vu_r * (0.0 if t.mute or (any_solo and not t.solo) else 1.0)
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
	record_for_replication("/beat/str", [state.position_string])
	record_for_replication("/time", [state.position_seconds])
	state.transport_changed.emit()


# --- commands -----------------------------------------------------------------------------
#
# Applied straight to the cache. There is no DAW to ask and therefore nothing to wait for, so
# unlike a real backend these take effect on the same frame -- the one behavioural difference
# the stand-in has, and the reason a fader never fights its own echo here.

func set_track_volume(index: int, taper: float) -> void:
	var t := state.track(index)
	if not _writes_lane(index, "volume", taper_to_db(clampf(taper, 0.0, 1.0)), t.volume_db):
		_remember("/track/%d/volume" % index, set_track_volume.bind(index, t.volume),
			set_track_volume.bind(index, taper))
	state.set_track_field(index, &"volume", clampf(taper, 0.0, 1.0))
	state.set_track_field(index, &"volume_db", taper_to_db(t.volume))
	record_for_replication("/track/%d/volume" % index, [t.volume])


func set_track_pan(index: int, pan: float) -> void:
	if not _writes_lane(index, "pan", clampf(pan, 0.0, 1.0) * 2.0 - 1.0, state.track(index).pan * 2.0 - 1.0):
		_remember("/track/%d/pan" % index, set_track_pan.bind(index, state.track(index).pan),
				set_track_pan.bind(index, pan))
	state.set_track_field(index, &"pan", clampf(pan, 0.0, 1.0))
	record_for_replication("/track/%d/pan" % index, [state.track(index).pan])


func set_track_mute(index: int, muted: bool) -> void:
	if not _writes_lane(index, "mute", 1.0 if muted else 0.0, 1.0 if state.track(index).mute else 0.0):
		_remember("/track/%d/mute" % index, set_track_mute.bind(index, state.track(index).mute),
				set_track_mute.bind(index, muted), false)
	state.set_track_field(index, &"mute", muted)
	record_for_replication("/track/%d/mute" % index, [1.0 if muted else 0.0])


func set_track_solo(index: int, soloed: bool) -> void:
	_remember("/track/%d/solo" % index, set_track_solo.bind(index, state.track(index).solo),
			set_track_solo.bind(index, soloed), false)
	state.set_track_field(index, &"solo", soloed)
	record_for_replication("/track/%d/solo" % index, [1.0 if soloed else 0.0])


func set_track_rec_arm(index: int, armed: bool) -> void:
	_remember("/track/%d/recarm" % index, set_track_rec_arm.bind(index, state.track(index).rec_arm),
			set_track_rec_arm.bind(index, armed), false)
	state.set_track_field(index, &"rec_arm", armed)
	record_for_replication("/track/%d/recarm" % index, [1.0 if armed else 0.0])


func set_track_automation_mode(index: int, mode: int) -> void:
	if index == 0:
		_remember("/master/automode", set_track_automation_mode.bind(0, state.master.automation_mode),
				set_track_automation_mode.bind(0, mode), false)
		state.master.automation_mode = mode
		state.master_changed.emit(&"automation_mode")
		record_for_replication("/master/automode", [float(mode)])
		if mode == DAW.AUTOMATION_READ:
			_end_passes(true, 0)
		return
	_remember("/track/%d/automode" % index,
			set_track_automation_mode.bind(index, state.track(index).automation_mode),
			set_track_automation_mode.bind(index, mode), false)
	state.set_track_field(index, &"automation_mode", mode)
	record_for_replication("/track/%d/automode" % index, [float(mode)])
	if mode == DAW.AUTOMATION_READ:
		_end_passes(true, index)


func set_track_monitor(index: int, mode: int) -> void:
	_remember("/track/%d/monitor" % index, set_track_monitor.bind(index, state.track(index).monitor),
			set_track_monitor.bind(index, mode), false)
	state.set_track_field(index, &"monitor", mode)
	record_for_replication("/track/%d/monitor" % index, [float(mode)])


func set_track_input(index: int, input: String) -> void:
	_remember("/track/%d/input" % index, set_track_input.bind(index, state.track(index).input),
			set_track_input.bind(index, input), false)
	state.set_track_field(index, &"input", input)
	record_for_replication("/track/%d/input" % index, [input])


## What a track can record from here: the machine's input devices and its keys.
func publish_inputs() -> void:
	# Each device both sides together, and each side alone: an interface's inputs 1 and 2.
	var inputs: Array = [["audio:", "the default microphone"], ["audio:#1", "the default microphone, input 1"],
			["audio:#2", "the default microphone, input 2"]]
	for d in AudioServer.get_input_device_list():
		if d != "Default":
			inputs.append_array([["audio:" + d, d], ["audio:%s#1" % d, "%s, input 1" % d],
					["audio:%s#2" % d, "%s, input 2" % d]])
	inputs.append(["midi", "the keys"])
	state.inputs = inputs
	record_for_replication("/inputs", MixWire.pack_inputs(inputs))


## Stands for Reaper, so it offers Reaper's stock plugins, by the names Reaper adds them by.
const STOCK_FX := [["ReaEQ", "ReaEQ"], ["ReaComp", "ReaComp"], ["ReaXcomp", "ReaXcomp"], ["ReaGate", "ReaGate"],
		["ReaLimit", "ReaLimit"], ["ReaDelay", "ReaDelay"], ["ReaVerbate", "ReaVerbate"], ["ReaPitch", "ReaPitch"]]


func fx_choices() -> Array:
	return STOCK_FX.duplicate(true)


func publish_fx_choices() -> void:
	state.fx_choices = fx_choices()
	record_for_replication("/fxchoices", MixWire.pack_inputs(state.fx_choices))


func set_master_volume(taper: float) -> void:
	if not _writes_lane(0, "volume", taper_to_db(clampf(taper, 0.0, 1.0)), state.master.volume_db):
		_remember("/master/volume", set_master_volume.bind(state.master.volume),
				set_master_volume.bind(taper))
	state.set_master_field(&"volume", clampf(taper, 0.0, 1.0))
	state.set_master_field(&"volume_db", taper_to_db(state.master.volume))
	record_for_replication("/master/volume", [state.master.volume])


func set_master_pan(pan: float) -> void:
	if not _writes_lane(0, "pan", clampf(pan, 0.0, 1.0) * 2.0 - 1.0, state.master.pan * 2.0 - 1.0):
		_remember("/master/pan", set_master_pan.bind(state.master.pan), set_master_pan.bind(pan))
	state.set_master_field(&"pan", clampf(pan, 0.0, 1.0))
	record_for_replication("/master/pan", [state.master.pan])


func set_fx_param(track_index: int, fx_index: int, param: int, value: float) -> void:
	var f := state.fx(track_index, fx_index)
	if not _writes_lane(track_index, "fx:%d:%d" % [fx_index, param], clampf(value, 0.0, 1.0),
			float(f.params.get(param, 0.0))):
		_remember("/track/%d/fx/%d/fxparam/%d" % [track_index, fx_index, param],
				set_fx_param.bind(track_index, fx_index, param, float(f.params.get(param, 0.0))),
				set_fx_param.bind(track_index, fx_index, param, value))
	f.params[param] = clampf(value, 0.0, 1.0)
	state.fx_changed.emit(track_index, fx_index)
	record_for_replication("/track/%d/fx/%d/fxparam/%d/value" % [track_index, fx_index, param], [f.params[param]])


func set_fx_enabled(track_index: int, fx_index: int, enabled: bool) -> void:
	var f := state.fx(track_index, fx_index)
	_remember("/track/%d/fx/%d/bypass" % [track_index, fx_index],
			set_fx_enabled.bind(track_index, fx_index, f.enabled),
			set_fx_enabled.bind(track_index, fx_index, enabled), false)
	f.enabled = enabled
	state.fx_changed.emit(track_index, fx_index)
	record_for_replication("/track/%d/fx/%d/bypass" % [track_index, fx_index], [1.0 if enabled else 0.0])


func set_fx_wet(track_index: int, fx_index: int, wet: float) -> void:
	var f := state.fx(track_index, fx_index, false)
	if f == null:
		return
	_remember("/track/%d/fx/%d/wet" % [track_index, fx_index],
			set_fx_wet.bind(track_index, fx_index, f.wet),
			set_fx_wet.bind(track_index, fx_index, wet))
	var key := "/track/%d/fx/%d/wet" % [track_index, fx_index]
	record_for_replication(key, [clampf(wet, 0.0, 1.0)])
	MixWire.apply(state, key, [clampf(wet, 0.0, 1.0)])


## The stand-in's plugins have no preset files, so they get a handful of named settings each:
## enough that stepping through them visibly changes the plugin, which is what is being tested.
const STAND_IN_PRESETS: Array[String] = ["Default", "Gentle", "Punchy", "Wide", "Extreme"]


func step_fx_preset(track_index: int, fx_index: int, direction: int) -> void:
	var f := state.fx(track_index, fx_index, false)
	if f == null or f.name == "":
		return
	var at := maxi(STAND_IN_PRESETS.find(f.preset), 0)
	var next := STAND_IN_PRESETS[posmod(at + signi(direction), STAND_IN_PRESETS.size())]
	var before := _fx_row(f)
	var after := before.duplicate(true)
	after["preset"] = next
	for param in after["params"]:
		after["params"][param] = 0.5 if next == "Default" \
				else fposmod(sin(float(hash(next + f.name) % 997) + param * 2.3) * 0.5 + 0.5, 1.0)
	_remember("/track/%d/fx/%d/preset" % [track_index, fx_index],
			_write_fx.bind(track_index, fx_index, before),
			_write_fx.bind(track_index, fx_index, after), false)
	_write_fx(track_index, fx_index, after)


## Rearranging a chain is laying down both chains whole, afterwards, the way a send list is: the
## wire can say what is in a slot and how many slots there are, and that is all a move is.
func move_fx(from_track: int, fx_index: int, to_track: int, to_fx: int, copy: bool) -> void:
	if not state.tracks.has(from_track) or not state.tracks.has(to_track):
		return
	var from_order := state.track(from_track).plugins()
	var at := from_order.find(fx_index)
	if at < 0:
		return
	var to_order := from_order if to_track == from_track else state.track(to_track).plugins()
	# A slot past the end of the chain is the end of the chain.
	var slot := to_order.find(to_fx)
	if slot < 0:
		slot = to_order.size()
	var source := _fx_chain_of(from_track)
	var target := source if to_track == from_track else _fx_chain_of(to_track)
	var before_from := source.duplicate(true)
	var before_to := target.duplicate(true)
	var row: Dictionary = source[at].duplicate(true)
	if not copy:
		source.remove_at(at)
		# The slot was counted with the plugin still in it.
		if to_track == from_track and slot > at:
			slot -= 1
	target.insert(mini(slot, target.size()), row)
	if to_track == from_track and not copy and before_from == source:
		return
	var after_from := source.duplicate(true)
	var after_to := target.duplicate(true)
	_remember("/track/%d/fxs" % from_track,
			_set_fx_chains.bind(from_track, before_from, to_track, before_to),
			_set_fx_chains.bind(from_track, after_from, to_track, after_to), false)
	_set_fx_chains(from_track, after_from, to_track, after_to)


func add_fx(track_index: int, plugin: String, at: int) -> void:
	var row := _new_fx_row(plugin)
	if not state.tracks.has(track_index) or row.is_empty():
		return
	var chain := _fx_chain_of(track_index)
	var order := state.track(track_index).plugins()
	var slot := order.find(at)
	_change_fx_chain(track_index, chain, _inserted(chain, row, slot if slot >= 0 else chain.size()))


func remove_fx(track_index: int, fx_index: int) -> void:
	if not state.tracks.has(track_index):
		return
	var at := state.track(track_index).plugins().find(fx_index)
	if at < 0:
		return
	var chain := _fx_chain_of(track_index)
	var after := chain.duplicate(true)
	after.remove_at(at)
	_change_fx_chain(track_index, chain, after)


static func _inserted(chain: Array, row: Dictionary, at: int) -> Array:
	var out := chain.duplicate(true)
	out.insert(mini(at, out.size()), row)
	return out


func _change_fx_chain(track_index: int, before: Array, after: Array) -> void:
	_remember("/track/%d/fxs" % track_index, _set_fx_chain.bind(track_index, before),
			_set_fx_chain.bind(track_index, after), false)
	_set_fx_chain(track_index, after)


## A new plugin's slot as `_fx_row` has it, for a choice from `fx_choices`; {} for none. The
## stand-in's are names standing for Reaper plugins, with no parameters to show.
func _new_fx_row(plugin: String) -> Dictionary:
	for c in fx_choices():
		if c[0] == plugin:
			return {"name": c[1], "enabled": true, "wet": 1.0, "preset": "", "params": {}, "param_names": {}}
	return {}


func _set_fx_chains(a: int, chain_a: Array, b: int, chain_b: Array) -> void:
	_set_fx_chain(a, chain_a)
	if b != a:
		_set_fx_chain(b, chain_b)


## The stand-in numbers a chain from 0, as the Godot effects it stands for are numbered on their
## bus. Reaper numbers from 1; nothing above the backend may assume either.
const FX_FIRST := 0


## A track's plugins in chain order, each as `_fx_row` says it.
func _fx_chain_of(track_index: int) -> Array:
	var out := []
	var t := state.track(track_index)
	for i in t.plugins():
		out.append(_fx_row(t.fx[i]))
	return out


static func _fx_row(f: MixState.FXState) -> Dictionary:
	return {"name": f.name, "enabled": f.enabled, "wet": f.wet, "preset": f.preset,
			"params": f.params.duplicate(), "param_names": f.param_names.duplicate()}


func _set_fx_chain(track_index: int, rows: Array) -> void:
	for i in rows.size():
		_write_fx(track_index, i + FX_FIRST, rows[i])
	record_for_replication("/track/%d/fxs" % track_index, [float(rows.size())])
	MixWire.apply(state, "/track/%d/fxs" % track_index, [float(rows.size())])


## One slot laid down whole, through the wire so a guest sees exactly the same plugin land.
func _write_fx(track_index: int, fx_index: int, row: Dictionary) -> void:
	var at := "/track/%d/fx/%d/" % [track_index, fx_index]
	var f := state.fx(track_index, fx_index)
	# Words describing the plugin that used to be in this slot would describe the wrong one.
	if f.name != row["name"]:
		f.param_text.clear()
		f.param_text_at.clear()
		for param in f.params.keys():
			if not (row["params"] as Dictionary).has(param):
				f.params.erase(param)
	var writes := [["name", [row["name"]]], ["bypass", [1.0 if row["enabled"] else 0.0]],
			["wet", [float(row["wet"])]], ["preset", [str(row["preset"])]]]
	for param in row["params"]:
		writes.append(["fxparam/%d/value" % param, [float(row["params"][param])]])
	for param in row["param_names"]:
		writes.append(["fxparam/%d/name" % param, [str(row["param_names"][param])]])
	for w in writes:
		record_for_replication(at + w[0], w[1])
		MixWire.apply(state, at + w[0], w[1])
	# A param value arriving tells nobody (it is a value, not a shape); a whole new plugin is.
	state.fx_changed.emit(track_index, fx_index)


## A send that is not there is not created by turning its knob: that is `create_send`'s job, and
## a level on a send that does not exist would draw a cable for it.
func set_send_volume(track_index: int, send_index: int, taper: float) -> void:
	var sd := state.send(track_index, send_index, false)
	if sd == null:
		return
	if sd.key or sd.dest_track <= 0 or not _writes_lane(track_index, "send:%d" % sd.dest_track,
			taper_to_db(clampf(taper, 0.0, 1.0)), taper_to_db(sd.volume)):
		_remember("/track/%d/send/%d/volume" % [track_index, send_index],
				set_send_volume.bind(track_index, send_index, sd.volume),
				set_send_volume.bind(track_index, send_index, taper))
	_write_send(track_index, send_index, "volume", clampf(taper, 0.0, 1.0))


func set_send_pan(track_index: int, send_index: int, pan: float) -> void:
	var sd := state.send(track_index, send_index, false)
	if sd == null:
		return
	_remember("/track/%d/send/%d/pan" % [track_index, send_index],
			set_send_pan.bind(track_index, send_index, sd.pan),
			set_send_pan.bind(track_index, send_index, pan))
	_write_send(track_index, send_index, "pan", clampf(pan, 0.0, 1.0))


func set_send_pre_fader(track_index: int, send_index: int, pre: bool) -> void:
	var sd := state.send(track_index, send_index, false)
	if sd == null or sd.pre_fader == pre:
		return
	_remember("/track/%d/send/%d/pre" % [track_index, send_index],
			set_send_pre_fader.bind(track_index, send_index, sd.pre_fader),
			set_send_pre_fader.bind(track_index, send_index, pre), false)
	_write_send(track_index, send_index, "pre", 1.0 if pre else 0.0)


## Patched the way Reaper patches: a new send goes on the end of the source's list at 0 dB, and
## removing one closes the gap, so every send after it moves down a number. Refused for a track
## into itself and for a pair that is already patched -- Reaper would allow the second, and two
## identical sends is a doubled level nobody meant, not routing.
func create_send(from_track: int, to_track: int) -> bool:
	if from_track == to_track or not state.tracks.has(from_track) or not state.tracks.has(to_track):
		return false
	return _add_send(from_track, to_track, false)


func create_sidechain(from_track: int, to_track: int) -> bool:
	if from_track == to_track or not state.tracks.has(from_track) or not state.tracks.has(to_track):
		return false
	return _add_send(from_track, to_track, true)


## One send of each kind between two tracks: a second identical cable is a mistake, but a track
## both heard on a bus and keying that bus's compressor is an ordinary mix.
func _add_send(from_track: int, to_track: int, key: bool) -> bool:
	var before := _sends_of(from_track)
	for row in before:
		if int(row[0]) == to_track and bool(row[4]) == key:
			return false
	var after := before.duplicate(true)
	after.append([to_track, state.track(to_track).display_name(), FaderLaw.to_taper(0.0), 0.5, key])
	_remember("/track/%d/sends" % from_track, _set_sends.bind(from_track, before),
			_set_sends.bind(from_track, after), false)
	_set_sends(from_track, after)
	return true


func remove_send(from_track: int, send_index: int) -> bool:
	var before := _sends_of(from_track)
	if send_index < 1 or send_index > before.size():
		return false
	var after := before.duplicate(true)
	after.remove_at(send_index - 1)
	_remember("/track/%d/sends" % from_track, _set_sends.bind(from_track, before),
			_set_sends.bind(from_track, after), false)
	_set_sends(from_track, after)
	return true


## A track's sends in order, as [dest_track, dest_name, volume, pan, key] rows.
func _sends_of(track_index: int) -> Array:
	var out := []
	if not state.tracks.has(track_index):
		return out
	var t := state.track(track_index)
	var keys: Array = t.sends.keys()
	keys.sort()
	for k in keys:
		var sd: MixState.SendState = t.sends[k]
		out.append([sd.dest_track, sd.dest_name, sd.volume, sd.pan, sd.key])
	return out


## Lay a track's sends down whole, numbered from one, through the wire like any other change.
func _set_sends(track_index: int, rows: Array) -> void:
	for i in rows.size():
		var at := "/track/%d/send/%d/" % [track_index, i + 1]
		for field in [["dest", float(rows[i][0])], ["name", str(rows[i][1])],
				["volume", float(rows[i][2])], ["pan", float(rows[i][3])],
				["key", 1.0 if rows[i][4] else 0.0]]:
			record_for_replication(at + field[0], [field[1]])
			MixWire.apply(state, at + field[0], [field[1]])
	record_for_replication("/track/%d/sends" % track_index, [float(rows.size())])
	MixWire.apply(state, "/track/%d/sends" % track_index, [float(rows.size())])


## Through the wire vocabulary rather than onto the field, so the change signal and the
## replication are the same ones a send level arriving from Reaper gets.
func _write_send(track_index: int, send_index: int, field: String, v: float) -> void:
	var key := "/track/%d/send/%d/%s" % [track_index, send_index, field]
	record_for_replication(key, [v])
	MixWire.apply(state, key, [v])


# --- history ------------------------------------------------------------------------------
#
# Reaper keeps its own undo history and this backend has to stand in for it, or undo would be
# a feature that only exists with Reaper running -- and untestable without it. What is kept is
# what Reaper keeps: changes to the mix, not the transport. A fader drag is many writes and ONE
# step, the way it is in Reaper: writes to the same control close together in time fold into the
# step that is already open, keeping where it started.

## Writes to one control closer together than this are one gesture.
const GESTURE_MS := 700

var _undo: Array = []
var _redo: Array = []
var _replaying := false
## Counts every edit, undone or redone included, and what it read when the project was last
## saved, opened or started: the two differ exactly when there is something a save would keep.
## Undoing back to the saved point still counts as changed, which errs toward asking for a save.
var _edits := 0
var _clean_at := 0


func has_unsaved_changes() -> bool:
	return _edits != _clean_at


func mark_clean() -> void:
	_clean_at = _edits


func _remember(key: String, back: Callable, again: Callable, folds := true) -> void:
	if _replaying:
		return
	_edits += 1
	var now := Time.get_ticks_msec()
	if folds and not _undo.is_empty():
		var last: Dictionary = _undo[-1]
		if last["key"] == key and now - int(last["t"]) < GESTURE_MS:
			last["again"] = again
			last["t"] = now
			return
	_undo.append({"key": key, "back": back, "again": again, "t": now, "name": acting if acting != "" else _name_of_key(key)})
	_redo.clear()
	_say_depth()


func undo() -> void:
	if _undo.is_empty():
		return
	var step: Dictionary = _undo.pop_back()
	_replaying = true
	(step["back"] as Callable).call()
	_replaying = false
	_edits += 1
	_redo.append(step)
	_say_depth()


func redo() -> void:
	if _redo.is_empty():
		return
	var step: Dictionary = _redo.pop_back()
	_replaying = true
	(step["again"] as Callable).call()
	_replaying = false
	_edits += 1
	# Re-opening a gesture by redoing it would be wrong: the next drag is a new step.
	step["t"] = 0
	_undo.append(step)
	_say_depth()


## A step's name from what it changed, when the edit came without one: "Kick: volume" for
## /track/2/volume, "tracks" for a change of structure.
func _name_of_key(key: String) -> String:
	var p := key.trim_prefix("/").split("/")
	if p.size() >= 3 and p[0] == "track" and p[1].is_valid_int() and state.tracks.has(int(p[1])):
		return "%s: %s" % [state.track(int(p[1])).display_name(), " ".join(p.slice(2))]
	return {"structure": "tracks", "marker": "markers"}.get(key, key.trim_prefix("/").replace("/", " "))


func undo_to(depth: int) -> void:
	while _undo.size() > maxi(depth, 0):
		undo()
	while _undo.size() < depth and not _redo.is_empty():
		redo()


## A different project has been opened: what could be undone belonged to the old one.
func forget_history() -> void:
	_undo.clear()
	_redo.clear()
	mark_clean()
	_say_depth()


func _say_depth() -> void:
	state.undo_depth = _undo.size()
	state.redo_depth = _redo.size()
	var names: Array = _undo.map(func(step): return str(step.get("name", step["key"])))
	for k in range(_redo.size() - 1, -1, -1):
		names.append(str(_redo[k].get("name", _redo[k]["key"])))
	state.undo_names = names
	state.transport_changed.emit()
	record_for_replication("/undo", [_undo.size(), _redo.size()] + names)


# --- editing ------------------------------------------------------------------------------

func select_item(track_index: int, item_index: int, additive: bool) -> void:
	# Not a history step: an undo that only changes what is highlighted looks like one that
	# did nothing. Reaper is told the same -- see the bridge.
	_locally_select(track_index, item_index, additive)


func select_all_items() -> void:
	_locally_select_all()


func select_track_items(track_index: int) -> void:
	_locally_select_track(track_index)


func clear_item_selection() -> void:
	_locally_clear_selection()


func move_item(track_index: int, item_index: int, start: float, to_track := 0) -> void:
	var before := _lanes_snapshot()
	_locally_move(track_index, item_index, start, to_track)
	_remember_edit(before)


func delete_selected() -> void:
	var before := _lanes_snapshot()
	if _locally_delete_selected() > 0:
		_remember_edit(before)


func ripple_delete_selected() -> void:
	var before := _lanes_snapshot()
	if _locally_ripple_delete_selected() > 0:
		_remember_edit(before)


func glue_selected() -> void:
	var before := _lanes_snapshot()
	if _locally_glue_selected() > 0:
		_remember_edit(before)


func nudge_selected(amount: float, unit: int) -> void:
	var before := _lanes_snapshot()
	if not _locally_nudge(amount, unit).is_empty():
		_remember_edit(before)


func copy_selected_to(seconds: float) -> void:
	var before := _lanes_snapshot()
	if _locally_copy_selected_to(seconds) > 0:
		_remember_edit(before)


func duplicate_selected() -> void:
	var before := _lanes_snapshot()
	if _locally_duplicate_selected() > 0:
		_remember_edit(before)


func trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	var before := _lanes_snapshot()
	_locally_trim(track_index, item_index, start, end)
	_remember_edit(before)


func ripple_move_item(track_index: int, item_index: int, start: float) -> void:
	var before := _lanes_snapshot()
	if _locally_ripple_move(track_index, item_index, start):
		_remember_edit(before)


func ripple_trim_item(track_index: int, item_index: int, start: float, end: float) -> void:
	var before := _lanes_snapshot()
	if _locally_ripple_trim(track_index, item_index, start, end):
		_remember_edit(before)


func set_item_gain(track_index: int, item_index: int, db: float) -> void:
	var before := _lanes_snapshot()
	_locally_shape(track_index, item_index, db, NAN, NAN)
	_remember_edit(before)


func set_item_fades(track_index: int, item_index: int, fade_in: float, fade_out: float) -> void:
	var before := _lanes_snapshot()
	_locally_shape(track_index, item_index, NAN, fade_in, fade_out)
	_remember_edit(before)


func set_item_muted(track_index: int, item_index: int, muted: bool) -> void:
	var before := _lanes_snapshot()
	if _locally_mute(track_index, item_index, muted):
		_remember_edit(before)


func crossfade_items(track_index: int, first: int, second: int) -> void:
	var before := _lanes_snapshot()
	if _locally_crossfade(track_index, first, second):
		_remember_edit(before)


func set_item_fade_shape(track_index: int, item_index: int, in_shape: int, out_shape: int) -> void:
	var before := _lanes_snapshot()
	if _locally_fade_shape(track_index, item_index, in_shape, out_shape):
		_remember_edit(before)


func set_item_reversed(track_index: int, item_index: int, reversed: bool) -> void:
	var before := _lanes_snapshot()
	if _locally_reverse(track_index, item_index, reversed):
		_remember_edit(before)


func set_item_locked(track_index: int, item_index: int, locked: bool) -> void:
	var before := _lanes_snapshot()
	if _locally_lock(track_index, item_index, locked):
		_remember_edit(before)


func shift_velocity(track_index: int, item_index: int, by: int) -> void:
	var before := _lanes_snapshot()
	if _locally_shift_velocity(track_index, item_index, by):
		_remember_edit(before)


func set_note_velocity(track_index: int, item_index: int, note_index: int, velocity: int) -> void:
	var before := _lanes_snapshot()
	if _locally_set_note_velocity(track_index, item_index, note_index, velocity):
		_remember_edit(before)


func legato_item(track_index: int, item_index: int) -> void:
	var before := _lanes_snapshot()
	if _locally_legato(track_index, item_index):
		_remember_edit(before)


func staccato_item(track_index: int, item_index: int) -> void:
	var before := _lanes_snapshot()
	if _locally_staccato(track_index, item_index):
		_remember_edit(before)


func rename_item(track_index: int, item_index: int, item_name: String) -> void:
	var before := _lanes_snapshot()
	if _locally_rename_item(track_index, item_index, item_name):
		_remember_edit(before)


func retrograde_item(track_index: int, item_index: int) -> void:
	var before := _lanes_snapshot()
	if _locally_retrograde(track_index, item_index):
		_remember_edit(before)


func transpose_note(track_index: int, item_index: int, note_index: int, semitones: int) -> void:
	var before := _lanes_snapshot()
	if _locally_transpose_note(track_index, item_index, note_index, semitones):
		_remember_edit(before)


func delete_note(track_index: int, item_index: int, note_index: int) -> void:
	var before := _lanes_snapshot()
	if _locally_delete_note(track_index, item_index, note_index):
		_remember_edit(before)


func even_velocity(track_index: int, item_index: int) -> void:
	var before := _lanes_snapshot()
	if _locally_even_velocity(track_index, item_index):
		_remember_edit(before)


func humanise_item(track_index: int, item_index: int, seconds: float, velocity: int) -> void:
	var before := _lanes_snapshot()
	if _locally_humanise(track_index, item_index, seconds, velocity):
		_remember_edit(before)


func transpose_item(track_index: int, item_index: int, semitones: int) -> void:
	var before := _lanes_snapshot()
	if _locally_transpose(track_index, item_index, semitones):
		_remember_edit(before)


func quantize_item(track_index: int, item_index: int, grid_beats: float, strength: float,
		swing := 0.0) -> void:
	var before := _lanes_snapshot()
	if _locally_quantize(track_index, item_index, grid_beats, strength, swing):
		_remember_edit(before)


func add_track(at: int, track_name: String) -> void:
	var count := state.track_indices().size()
	at = clampi(at, 1, count + 1)
	var before := _structure()
	_renumber(_order_adding(count, at))
	state.track(at).name = track_name
	_remember("structure", _restore_structure.bind(before), _restore_structure.bind(_structure()), false)


func duplicate_track(index: int) -> void:
	var count := state.track_indices().size()
	if index < 1 or index > count:
		return
	var before := _structure()
	var kinds := _renumber(_order_adding(count, index + 1), false)
	_locally_copy_track(index, index + 1)
	if kinds.has(index):
		kinds[index + 1] = (kinds[index] as Dictionary).duplicate(true)
	if instruments.has(index):
		instruments[index + 1] = (instruments[index] as Dictionary).duplicate(true) \
				if instruments[index] is Dictionary else instruments[index]
	_structure_changed(kinds)
	_remember("structure", _restore_structure.bind(before), _restore_structure.bind(_structure()), false)


func remove_track(index: int) -> void:
	var count := state.track_indices().size()
	if index < 1 or index > count:
		return
	var before := _structure()
	_renumber(_order_removing(count, index))
	_remember("structure", _restore_structure.bind(before), _restore_structure.bind(_structure()), false)


func rename_track(index: int, track_name: String) -> void:
	if not state.tracks.has(index) or state.tracks[index].name == track_name:
		return
	_remember("/track/%d/name" % index, rename_track.bind(index, state.tracks[index].name),
			rename_track.bind(index, track_name), false)
	state.set_track_field(index, &"name", track_name)
	record_for_replication("/track/%d/name" % index, [track_name])


func set_track_group(index: int, group: int) -> void:
	if not state.tracks.has(index) or state.tracks[index].group == group:
		return
	_remember("/track/%d/group" % index, set_track_group.bind(index, state.tracks[index].group),
			set_track_group.bind(index, group), false)
	state.set_track_field(index, &"group", group)
	record_for_replication("/track/%d/group" % index, [float(group)])


func set_track_colour(index: int, colour: Color) -> void:
	if not state.tracks.has(index) or state.tracks[index].colour.is_equal_approx(colour):
		return
	_remember("/track/%d/colour" % index, set_track_colour.bind(index, state.tracks[index].colour),
			set_track_colour.bind(index, colour), false)
	state.set_track_field(index, &"colour", colour)
	record_for_replication("/track/%d/colour" % index, [colour.r, colour.g, colour.b])


## The tracks renumbered (see `_locally_renumber`), with what is kept beside the mix by index.
## `rebuild` false leaves the engine's rebuild to the caller, which has more to change first.
func _renumber(order: Array, rebuild := true) -> Dictionary:
	var kinds := _fx_kinds()
	var map := _locally_renumber(order)
	var moved_kinds := {}
	var moved_instruments := {}
	for old in map:
		if kinds.has(old):
			moved_kinds[map[old]] = kinds[old]
		if instruments.has(old):
			moved_instruments[map[old]] = instruments[old]
	instruments = moved_instruments
	tracks_renumbered.emit(map)
	if rebuild:
		_structure_changed(moved_kinds)
	return moved_kinds


## Which object is which track, and everything a renumbering changes on it: undo puts the same
## tracks back, as every later step has been undone by then.
func _structure() -> Dictionary:
	var rows: Array = []
	for index in state.track_indices():
		var t: MixState.TrackState = state.tracks[index]
		var sends: Array = []
		for slot in t.sends:
			sends.append([slot, t.sends[slot], t.sends[slot].dest_track])
		rows.append([t, index, t.folder_depth, sends, t.automation.duplicate()])
	return {"rows": rows, "instruments": instruments.duplicate(true), "kinds": _fx_kinds()}


func _restore_structure(saved: Dictionary) -> void:
	var now := {}
	for index in state.tracks:
		now[state.tracks[index]] = index
	var map := {}
	for row in saved["rows"]:
		if now.has(row[0]):
			map[now[row[0]]] = row[1]
	var tracks := {}
	for row in saved["rows"]:
		var t: MixState.TrackState = row[0]
		t.index = row[1]
		t.folder_depth = row[2]
		t.automation = (row[4] as Dictionary).duplicate()
		t.sends = {}
		for send in row[3]:
			var sd: MixState.SendState = send[1]
			sd.index = send[0]
			sd.dest_track = send[2]
			t.sends[send[0]] = sd
		tracks[row[1]] = t
	state.tracks = tracks
	state.project_track_count = tracks.size()
	instruments = saved["instruments"].duplicate(true)
	tracks_renumbered.emit(map)
	_structure_changed(saved["kinds"])


## Every index may mean another track now: the engine rebuilds, and the room gets the whole mix.
func _structure_changed(kinds: Dictionary) -> void:
	state.bank_offset = 0
	state.bank_size = mini(maxi(state.tracks.size(), 1), 64)
	project_loaded(kinds)
	state.bank_changed.emit()
	state.timeline_changed.emit()
	state.project_replaced.emit()


func split_selected(seconds: float) -> void:
	var before := _lanes_snapshot()
	if _locally_split(seconds) > 0:
		_remember_edit(before)


func add_marker(seconds: float, marker_name: String) -> void:
	var before: Dictionary = state.markers.duplicate()
	var after: Dictionary = before.duplicate()
	after[seconds] = marker_name
	_write_markers(after)
	_remember("marker", _write_markers.bind(before), _write_markers.bind(after), false)


func edit_marker(at: float, to: float, marker_name: String) -> void:
	_change_markers(markers_edited(state.markers, at, to, marker_name))


func remove_marker(at: float) -> void:
	_change_markers(markers_edited(state.markers, at, at, "", true))


func add_region(start: float, end: float, region_name: String) -> void:
	_change_regions(regions_added(state.regions, start, end, region_name))


func remove_region(at: float) -> void:
	_change_regions(regions_removed(state.regions, at))


func edit_region(at: float, start: float, end: float, region_name: String) -> void:
	_change_regions(regions_edited(state.regions, at, start, end, region_name))


func _change_regions(after: Array) -> void:
	var before: Array = state.regions.duplicate(true)
	if after == before:
		return
	_write_regions(after)
	_remember("region", _write_regions.bind(before), _write_regions.bind(after), false)


func _change_markers(after: Dictionary) -> void:
	var before: Dictionary = state.markers.duplicate()
	if after == before:
		return
	_write_markers(after)
	_remember("marker", _write_markers.bind(before), _write_markers.bind(after), false)


func insert_midi_take(track_index: int, start: float, end: float, notes: Array,
		take_name: String) -> void:
	var before := _lanes_snapshot()
	_locally_insert_take(track_index, start, end, notes, take_name)
	_remember_edit(before)


func insert_audio_take(track_index: int, start: float, source: String, length: float,
		peaks: PackedByteArray, take_name: String) -> void:
	var before := _lanes_snapshot()
	_locally_insert_audio(track_index, start, source, length, peaks, take_name)
	_remember_edit(before)


## An edit is one step, never folded: two moves in a row are two things you might take back.
func _remember_edit(before: Dictionary) -> void:
	var after := _lanes_snapshot()
	_remember("edit", _restore_lanes.bind(before), _restore_lanes.bind(after), false)


# --- transport ----------------------------------------------------------------------------

func set_looping(on: bool) -> void:
	state.looping = on
	state.transport_changed.emit()
	record_for_replication("/repeat", [1.0 if on else 0.0])


## Not a history step, as it is not in Reaper: the click is how you are listening, not the mix.
func set_metronome(on: bool) -> void:
	state.metronome = on
	state.transport_changed.emit()
	record_for_replication("/click", [1.0 if on else 0.0])


func set_punch(on: bool) -> void:
	state.punch = on
	state.transport_changed.emit()
	record_for_replication("/punch", [1.0 if on else 0.0])


func set_count_in(bars: int) -> void:
	state.count_in_bars = clampi(bars, 0, MixState.COUNT_IN_MAX)
	state.transport_changed.emit()
	record_for_replication("/countin", [float(state.count_in_bars)])


func set_count_in_play(on: bool) -> void:
	state.count_in_play = on
	state.transport_changed.emit()
	record_for_replication("/countin/play", [1.0 if on else 0.0])


func set_pre_roll(on: bool) -> void:
	state.pre_roll = on
	state.transport_changed.emit()
	record_for_replication("/countin/song", [1.0 if on else 0.0])


func set_tempo(bpm: float) -> void:
	_remember("/tempo/raw", set_tempo.bind(state.tempo), set_tempo.bind(bpm))
	state.tempo = bpm
	# The counter is spelled from seconds at the tempo, so it changes with it.
	state.position_string = state.bar_beat(state.position_seconds)
	state.transport_changed.emit()
	record_for_replication("/tempo/raw", [bpm])


## One undo step: the whole lane, drawn or recorded.
func set_automation(track_index: int, target: String, points: Array) -> void:
	var lanes: Dictionary
	if track_index == 0:
		lanes = state.master.automation
	elif state.tracks.has(track_index):
		lanes = state.track(track_index).automation
	else:
		return
	var address := MixWire.automation_address(track_index, target)
	_remember(address, set_automation.bind(track_index, target, (lanes.get(target, []) as Array).duplicate(true)),
			set_automation.bind(track_index, target, points.duplicate(true)), false)
	MixWire.apply(state, address, MixWire.pack_automation(points))
	record_for_replication(address, MixWire.pack_automation(points))
	_followed_at = NAN


## Where automation was last followed to; NAN to follow it again at once.
var _followed_at := NAN


## Every automated control to where its lane says at the playhead, as Reaper's read mode does:
## the control moves on the desk, for everyone, and the mix follows the control. Not history. While
## stopped only when the playhead has moved, so a control can still be set by hand there.
func follow_automation() -> void:
	var at := state.position_seconds
	_tick_passes(at)
	if not state.playing and at == _followed_at:
		return
	_followed_at = at
	for target in state.master.automation:
		if _passes.has([0, target]):
			continue
		var mv := DawKitAutomation.value_in(state.master.automation[target], at)
		if target == "volume" and not is_equal_approx(state.master.volume_db, mv):
			state.set_master_field(&"volume", db_to_taper(mv))
			state.set_master_field(&"volume_db", mv)
			record_for_replication("/master/volume", [state.master.volume])
		elif target == "pan" and not is_equal_approx(state.master.pan, (mv + 1.0) * 0.5):
			state.set_master_field(&"pan", (mv + 1.0) * 0.5)
			record_for_replication("/master/pan", [state.master.pan])
	for index in state.tracks:
		var t: MixState.TrackState = state.tracks[index]
		for target in t.automation:
			if _passes.has([index, target]):
				continue
			var v := DawKitAutomation.value_in(t.automation[target], at)
			var kind := DawKitAutomation.kind_of(target)
			match kind:
				"volume":
					var taper := db_to_taper(v)
					if not is_equal_approx(t.volume_db, v):
						state.set_track_field(index, &"volume", taper)
						state.set_track_field(index, &"volume_db", v)
						record_for_replication("/track/%d/volume" % index, [taper])
				"pan":
					var pan := (v + 1.0) * 0.5
					if not is_equal_approx(t.pan, pan):
						state.set_track_field(index, &"pan", pan)
						record_for_replication("/track/%d/pan" % index, [pan])
				"mute":
					if t.mute != (v >= 0.5):
						state.set_track_field(index, &"mute", v >= 0.5)
						record_for_replication("/track/%d/mute" % index, [1.0 if v >= 0.5 else 0.0])
				"send":
					var to := int(String(target).substr(5))
					for slot in t.sends:
						var sd: MixState.SendState = t.sends[slot]
						if sd.dest_track == to and not sd.key and not is_equal_approx(taper_to_db(sd.volume), v):
							_write_send(index, slot, "volume", db_to_taper(v))
				"fx":
					var parts := String(target).split(":")
					var f := state.fx(index, int(parts[1]), false)
					if f != null and not is_equal_approx(float(f.params.get(int(parts[2]), -1.0)), v):
						f.params[int(parts[2])] = v
						state.fx_changed.emit(index, int(parts[1]))
						record_for_replication("/track/%d/fx/%d/fxparam/%d/value" % [index, int(parts[1]), int(parts[2])], [v])


# --- writing automation ----------------------------------------------------------------------
#
# A control moved while the song plays, on a track in touch or latch, is written to its lane
# rather than set: a "pass" collects where it went, the lane stops moving it meanwhile, and when
# the pass ends it replaces that stretch of the lane, as one undo step. Touch ends a pass when
# the control has been still for `GESTURE_MS` (there is no "let go" on the wire), and the lane
# then glides back to what it was over `RETURN_SECONDS`; latch holds the last value until the
# transport stops.

## How long a touched control takes to go back to its lane once let go.
const RETURN_SECONDS := 0.25

## [track, target] -> {start, last (seconds), ms (when last written), before (the value when
## the pass began), points, latch}
var _passes := {}


## Whether a write of `value` to `target` on `track_index` is part of a pass (and so not an
## undo step of its own): the song is playing, and the track is in touch or latch. Track 0 is
## the master.
func _writes_lane(track_index: int, target: String, value: float, was: float) -> bool:
	if _replaying or not state.playing or (track_index != 0 and not state.tracks.has(track_index)):
		return false
	var mode := state.master.automation_mode if track_index == 0 else state.track(track_index).automation_mode
	if mode != DAW.AUTOMATION_TOUCH and mode != DAW.AUTOMATION_LATCH:
		return false
	var at := state.position_seconds
	var key := [track_index, target]
	if not _passes.has(key):
		_passes[key] = {"start": at, "last": at, "ms": 0, "before": was, "points": [],
				"latch": mode == DAW.AUTOMATION_LATCH}
	var run: Dictionary = _passes[key]
	var points: Array = run["points"]
	var shape := DawKitAutomation.HOLD if target == "mute" else DawKitAutomation.LINEAR
	# One point per moment: a second write in the same frame replaces the first.
	if not points.is_empty() and at <= float(points[-1][0]) + 0.0005:
		points[-1][1] = value
	else:
		points.append([at, value, shape])
	run["last"] = at
	run["ms"] = Time.get_ticks_msec()
	return true


## Touch passes let go, latch passes kept up with the playhead, and every pass ended when the
## transport has stopped some way other than `transport_stop`.
func _tick_passes(at: float) -> void:
	if _passes.is_empty():
		return
	if not state.playing:
		_end_passes(true)
		return
	var now := Time.get_ticks_msec()
	for key in _passes.keys():
		var run: Dictionary = _passes[key]
		if run["latch"]:
			run["last"] = maxf(float(run["last"]), at)
		elif now - int(run["ms"]) > GESTURE_MS:
			_end_pass(key)


## Ends every pass (or every pass on `track_index`). `all` includes latch passes.
func _end_passes(all: bool, track_index := -1) -> void:
	for key in _passes.keys():
		if _passes[key]["latch"] and state.playing:
			_passes[key]["last"] = maxf(float(_passes[key]["last"]), state.position_seconds)
		if (track_index < 0 or key[0] == track_index) and (all or not _passes[key]["latch"]):
			_end_pass(key)


## The pass's points over that stretch of the lane, and back to the lane after it.
func _end_pass(key: Array) -> void:
	var run: Dictionary = _passes[key]
	_passes.erase(key)
	var index: int = key[0]
	var target: String = key[1]
	if (index != 0 and not state.tracks.has(index)) or (run["points"] as Array).is_empty():
		return
	var lanes: Dictionary = state.master.automation if index == 0 else state.track(index).automation
	var old: Array = lanes.get(target, [])
	var before: float = run["before"]
	var start: float = run["start"]
	var recorded: Array = run["points"]
	var end := maxf(float(run["last"]), float(recorded[-1][0]))
	var shape := DawKitAutomation.HOLD if target == "mute" else DawKitAutomation.LINEAR
	if run["latch"] and end > float(recorded[-1][0]) + 0.0005:
		recorded.append([end, recorded[-1][1], shape])
	var back := end + RETURN_SECONDS
	var out: Array = []
	for pt in old:
		if float(pt[0]) < start - 0.0005 or float(pt[0]) > back + 0.0005:
			out.append(pt.duplicate())
	# Where the lane was just before the pass, so what came before it does not change.
	if start > 0.001:
		out.append([start - 0.001, DawKitAutomation.value_in(old, start - 0.001, before), shape])
	for pt in recorded:
		out.append([float(pt[0]), DawKitAutomation.clamp_value(target, float(pt[1])), int(pt[2])])
	out.append([back, DawKitAutomation.value_in(old, back, before), shape])
	out.sort_custom(func(a, b): return a[0] < b[0])
	var lane: Array = []
	for pt in out:
		if lane.is_empty() or float(pt[0]) > float(lane[-1][0]) + 0.000001:
			lane.append(pt)
		else:
			lane[-1] = pt
	set_automation(index, target, lane)


## One undo step: the whole map, as a tempo knob turned is the whole tempo.
func set_tempo_map(points: Array) -> void:
	_remember("/tempo/map", set_tempo_map.bind(state.tempo_points.duplicate(true)),
			set_tempo_map.bind(points.duplicate(true)), false)
	state.tempo_points = points.duplicate(true)
	if not points.is_empty():
		state.tempo = float(points[0][1])
	state.position_string = state.bar_beat(state.position_seconds)
	state.transport_changed.emit()
	record_for_replication("/tempo/map", MixWire.pack_tempo_points(points))
	record_for_replication("/tempo/raw", [state.tempo])


func set_time_signature_map(points: Array) -> void:
	var was: Array = state.time_signature_points.duplicate(true)
	if was.is_empty():
		was = [[0.0, state.beats_per_bar, state.beat_unit]]
	_remember("/timesig/map", set_time_signature_map.bind(was), set_time_signature_map.bind(points.duplicate(true)), false)
	if not points.is_empty():
		state.beats_per_bar = int(points[0][1])
		state.beat_unit = int(points[0][2])
	state.time_signature_points = points.duplicate(true) if points.size() > 1 else []
	state.position_string = state.bar_beat(state.position_seconds)
	state.transport_changed.emit()
	record_for_replication("/timesig", [float(state.beats_per_bar), float(state.beat_unit)])
	record_for_replication("/timesig/map", MixWire.pack_meter_points(state.time_signature_points))


func seek(seconds: float) -> void:
	state.position_seconds = maxf(seconds, 0.0)
	state.position_string = state.bar_beat(state.position_seconds)
	state.transport_changed.emit()
	record_for_replication("/time", [state.position_seconds])


func set_loop_range(start: float, end: float) -> void:
	state.loop_start = start
	state.loop_end = end
	state.transport_changed.emit()
	record_for_replication("/loop/start/time", [start])
	record_for_replication("/loop/end/time", [end])


## With a count-in due before playback too, from a standstill: as transport_record counts in.
func transport_play() -> void:
	if not state.playing and state.counts_in_playing():
		var at := state.position_seconds
		_set_count_in_to(at)
		state.position_seconds = state.count_in_start(at) - count_in_lead
		record_for_replication("/time", [state.position_seconds])
	state.playing = true
	state.transport_changed.emit()
	record_for_replication("/play", [1.0])


func transport_stop() -> void:
	_end_passes(true)
	if state.counting_in():
		# Stopped before the take or the song began: back where it would have, as if never started.
		state.position_seconds = state.count_in_to
		record_for_replication("/time", [state.position_seconds])
		_set_count_in_to(-1.0)
	state.playing = false
	state.recording = false
	state.transport_changed.emit()
	record_for_replication("/play", [0.0])
	# Said as well as implied: a guest only learns the take is over from this, and a guest
	# still believing the host records is a guest still recording.
	record_for_replication("/record", [0.0])


## With a count-in due, from a standstill, the transport starts that many bars back with only
## the click to hear (the engine plays nothing else while counting in, unless with pre-roll), and the take begins
## where it stood: as Reaper does it, so a playhead reads the same on either.
func transport_record() -> void:
	if not state.playing and state.counts_in():
		var at := state.position_seconds
		_set_count_in_to(at)
		state.position_seconds = state.count_in_start(at) - count_in_lead
		record_for_replication("/time", [state.position_seconds])
	state.playing = true
	state.recording = true
	state.transport_changed.emit()
	record_for_replication("/record", [1.0])


func snapshot() -> Array:
	return MixWire.snapshot(state)


func apply_replicated(batch: Array) -> void:
	MixWire.apply_replicated(state, batch)
