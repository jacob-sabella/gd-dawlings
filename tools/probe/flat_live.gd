extends Node
## The 2D view (DawKitStudio over FlatHost) against a live Reaper: every edit made through the
## host the 2D view uses, and every result read back from Reaper itself through the bridge's
## GetState and GetTimeline -- not from the desk's cache, which predicts its own edits.
##   tools/reaper_rig.sh up
##   godot --headless --path . tools/probe/flat_live.tscn -- --reaper-resource ~/.cache/dawlings/rig
## Prints PASS/FAIL per check and exits non-zero on any failure. The rig's session is a scratch
## copy, but what can be put back is.

var _failures := 0
var _checks := 0
var _bridge: ScriptBridge
var host: FlatHost


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var options := {}
	for i in argv.size():
		if argv[i] == "--reaper-resource" and i + 1 < argv.size():
			options["bridge_dir"] = argv[i + 1].path_join("Scripts/dawlings_bridge_data")
	var backend := ReaperBackend.new()
	if not DAW.use(backend, true, options):
		print("FAIL could not open the link")
		get_tree().quit(2)
		return
	_bridge = backend._bridge
	await _wait(4.0)
	await _run()
	print("\n%d live checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _reaper(fn: String, args: Array = []) -> Variant:
	var box := [null, false]
	_bridge.call_reaper(fn, args, func(r) -> void:
		box[0] = r
		box[1] = true)
	var waited := 0.0
	while not box[1] and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return box[0]


static func _arr(v) -> Array:
	return v if v is Array else []


## Reads `fn` from Reaper until `cond` holds or `timeout` passes, and returns the last read.
func _until(fn: String, args: Array, cond: Callable, timeout := 4.0) -> Dictionary:
	var started := Time.get_ticks_msec()
	var r := {}
	while true:
		var got = await _reaper(fn, args)
		r = got if got is Dictionary else {}
		if not r.is_empty() and cond.call(r):
			break
		if Time.get_ticks_msec() - started > timeout * 1000.0:
			break
		await _wait(0.15)
	return r


static func _track(st: Dictionary, index: int) -> Dictionary:
	for t in _arr(st.get("tracks", [])):
		if int(t.get("index", 0)) == index:
			return t
	return {}


static func _items(tl: Dictionary, index: int) -> Array:
	return _arr(_track(tl, index).get("items", []))


static func _note_count(tl: Dictionary, index: int, item: int) -> int:
	var items := _items(tl, index)
	return _arr(items[item].get("notes", [])).size() / 5 if item < items.size() else -1


## Whether a note of the clip starts `on` seconds into it at `pitch`.
static func _note_at(tl: Dictionary, index: int, item: int, on: float, pitch: int) -> bool:
	var items := _items(tl, index)
	if item >= items.size():
		return false
	var n := _arr(items[item].get("notes", []))
	for i in range(0, n.size() - 4, 5):
		if absf(float(n[i]) - on) < 0.01 and int(n[i + 2]) == pitch:
			return true
	return false


static func _velocities(tl: Dictionary, index: int, item: int) -> Array:
	var items := _items(tl, index)
	var out := []
	if item < items.size():
		var n := _arr(items[item].get("notes", []))
		for i in range(0, n.size() - 4, 5):
			out.append(int(n[i + 3]))
	return out


static func _has_marker(tl: Dictionary, name: String) -> bool:
	return _arr(tl.get("markers", [])).any(func(m): return m is Dictionary and str(m.get("name", "")) == name)


func _run() -> void:
	var s := DAW.state
	host = FlatHost.new()
	var project := host.project()
	check("the 2D view's project is Reaper's (%d tracks)" % project.tracks.size(), project.tracks.size() == s.tracks.size() and s.tracks.size() >= 10)

	var view := DawKitStudio.new(host)
	add_child(view)
	view.size = Vector2(1600, 900)
	await get_tree().process_frame
	view.refresh()
	check("the 2D view builds over it (%d track headers)" % view.arrange.headers.size(), view.arrange.headers.size() == project.tracks.size())
	for edit in [DawKitHost.MOVE_CLIP, DawKitHost.EDIT_CLIPS, DawKitHost.EFFECTS, DawKitHost.TEMPO_MAP, DawKitHost.NOTES, DawKitHost.MARKERS, DawKitHost.AUTOMATION, DawKitHost.RENDER, DawKitHost.SAVE]:
		check("and offers %s with the bridge up" % edit, host.can(edit))
	check("but not New/Open, whose dialogs are Reaper's", not host.can(DawKitHost.FILES))

	# --- mixer ---------------------------------------------------------------------------
	var id1 := ProjectBridge.id_of(1)
	host.set_volume(id1, -12.0)
	host.set_mute(ProjectBridge.id_of(3), true)
	host.set_pan(ProjectBridge.id_of(2), -0.5)
	var st := await _until("GetState", [8], func(x): return bool(_track(x, 3).get("mute", false)))
	var db := 20.0 * log(maxf(float(_track(st, 1).get("volume", 0.0)), 0.00001)) / log(10.0)
	check("a 2D fader at -12 dB is Reaper's (%.1f dB)" % db, absf(db + 12.0) < 0.6)
	check("a 2D mute mutes in Reaper", bool(_track(st, 3).get("mute", false)))
	check("a 2D pan pans in Reaper (%.2f)" % float(_track(st, 2).get("pan", 0.0)), absf(float(_track(st, 2).get("pan", 0.0)) + 0.5) < 0.03)
	host.set_mute(ProjectBridge.id_of(3), false)

	# --- transport and song -----------------------------------------------------------------
	var tempo_was := s.tempo
	host.set_tempo(111.0)
	# The tempo is in the project's structure, not its state.
	st = await _until("GetProjectStructure", [0], func(x): return absf(float(x.get("tempo", 0.0)) - 111.0) < 0.01)
	check("a 2D tempo is Reaper's (%.2f)" % float(st.get("tempo", 0.0)), absf(float(st.get("tempo", 0.0)) - 111.0) < 0.01)
	host.set_tempo(tempo_was)
	host.set_loop_range(8.0, 16.0)
	host.set_looping(true)
	st = await _until("GetState", [8], func(x): return absf(float(x.get("loop_start", 0.0)) - 8.0) < 0.05 and bool(x.get("repeating", false)))
	check("a loop dragged on the 2D ruler is Reaper's (%.2f-%.2f)" % [float(st.get("loop_start", 0.0)), float(st.get("loop_end", 0.0))],
			absf(float(st.get("loop_start", 0.0)) - 8.0) < 0.05 and absf(float(st.get("loop_end", 0.0)) - 16.0) < 0.05)
	check("and LOOP is Reaper's repeat", bool(st.get("repeating", false)))
	host.set_looping(false)
	host.seek(30.0)
	st = await _until("GetState", [8], func(x): return absf(float(x.get("cursor", 0.0)) - 30.0) < 0.05)
	check("a click on the 2D ruler moves Reaper's cursor (%.2f)" % float(st.get("cursor", 0.0)), absf(float(st.get("cursor", 0.0)) - 30.0) < 0.05)

	host.add_marker(3.5, "FLAT LIVE")
	var tl := await _until("GetTimeline", [], func(x): return _has_marker(x, "FLAT LIVE"))
	check("a marker added in 2D is in Reaper", _has_marker(tl, "FLAT LIVE"))
	await _wait(0.5)
	var at := -1
	for i in host.project().markers.size():
		if host.project().markers[i].name == "FLAT LIVE":
			at = i
	check("and on the 2D ruler", at >= 0)
	if at >= 0:
		host.edit_marker(at, 4.0, "FLAT LIVE 2")
		tl = await _until("GetTimeline", [], func(x): return _has_marker(x, "FLAT LIVE 2"))
		check("renamed in 2D, renamed in Reaper", _has_marker(tl, "FLAT LIVE 2"))
		await _wait(0.5)
		for i in host.project().markers.size():
			if host.project().markers[i].name == "FLAT LIVE 2":
				at = i
		host.remove_marker(at)
		tl = await _until("GetTimeline", [], func(x): return not _has_marker(x, "FLAT LIVE 2"))
		check("removed in 2D, gone from Reaper", not _has_marker(tl, "FLAT LIVE 2"))

	host.add_region(40.0, 48.0, "FLAT REGION")
	tl = await _until("GetTimeline", [], func(x): return _arr(x.get("regions", [])).any(func(r): return str(r.get("name", "")) == "FLAT REGION"))
	check("a region added in 2D is in Reaper", _arr(tl.get("regions", [])).any(func(r): return str(r.get("name", "")) == "FLAT REGION"))

	# --- clips --------------------------------------------------------------------------------
	var clip_track := -1
	for i in s.track_indices():
		if not s.track(i).items.is_empty() and not s.track(i).items[0].locked:
			clip_track = i
			break
	check("there is a clip to move", clip_track > 0)
	if clip_track > 0:
		tl = await _until("GetTimeline", [], func(_x): return true)
		var start := float(_items(tl, clip_track)[0].get("start", 0.0))
		host.move_clip(ProjectBridge.id_of(clip_track), 0, start + 2.0)
		tl = await _until("GetTimeline", [], func(x): return _items(x, clip_track).any(func(it): return absf(float(it.get("start", 0.0)) - start - 2.0) < 0.01))
		check("a clip dragged in 2D moves in Reaper (%.2f -> %.2f)" % [start, start + 2.0],
				_items(tl, clip_track).any(func(it): return absf(float(it.get("start", 0.0)) - start - 2.0) < 0.01))
		host.undo()
		tl = await _until("GetTimeline", [], func(x): return _items(x, clip_track).any(func(it): return absf(float(it.get("start", 0.0)) - start) < 0.01))
		check("and UNDO in 2D is Reaper's undo", _items(tl, clip_track).any(func(it): return absf(float(it.get("start", 0.0)) - start) < 0.01))

	# --- notes --------------------------------------------------------------------------------
	# The rig's session is all audio: a clip of notes is put in Reaper first, as a take recorded
	# on the keytar would be, for the piano roll to open.
	var midi := Vector2i(-1, -1)
	var midi_track := mini(10, s.tracks.size())
	DAW.insert_midi_take(midi_track, 100.0, 104.0, [[100.0, 100.5, 60, 90, 0], [101.0, 101.5, 64, 90, 0], [102.0, 102.5, 67, 90, 0]], "FLAT MIDI")
	var waited := 0.0
	while midi.x < 0 and waited < 6.0:
		await _wait(0.25)
		waited += 0.25
		for j in s.track(midi_track).items.size():
			var it: MixState.ItemState = s.track(midi_track).items[j]
			if absf(it.start - 100.0) < 0.01 and not it.notes.is_empty():
				midi = Vector2i(midi_track, j)
	check("a MIDI clip put in Reaper reaches the 2D view", midi.x > 0 and host.project().track(ProjectBridge.id_of(midi_track)) != null)
	if midi.x > 0:
		tl = await _until("GetTimeline", [], func(x): return _note_count(x, midi.x, midi.y) == 3)
		var notes_were := _note_count(tl, midi.x, midi.y)
		check("Reaper has its three notes (%d)" % notes_were, notes_were == 3)
		var id := ProjectBridge.id_of(midi.x)
		host.insert_note(id, midi.y, 3.0, 3.25, 72)
		tl = await _until("GetTimeline", [], func(x): return _note_count(x, midi.x, midi.y) == notes_were + 1)
		check("a note drawn in the 2D piano roll is in Reaper (%d -> %d)" % [notes_were, _note_count(tl, midi.x, midi.y)],
				_note_count(tl, midi.x, midi.y) == notes_were + 1)
		await _wait(0.5)
		# The first note, C4 at 100 s, dragged up a fifth and half a second later.
		host.move_note(id, midi.y, 0, 0.5, 67)
		tl = await _until("GetTimeline", [], func(x): return _note_at(x, midi.x, midi.y, 0.5, 67))
		check("a note dragged in the piano roll moves in Reaper (C4 at 0 s -> G4 at 0.5 s)", _note_at(tl, midi.x, midi.y, 0.5, 67))
		await _wait(0.5)
		host.set_note_velocity(id, midi.y, 0, 40)
		tl = await _until("GetTimeline", [], func(x): return _velocities(x, midi.x, midi.y).has(40))
		check("a velocity set in the 2D lane is Reaper's (%s)" % [_velocities(tl, midi.x, midi.y)], _velocities(tl, midi.x, midi.y).has(40))
		# Three steps: the note, its move (time and pitch together), its velocity.
		host.undo()
		await _until("GetTimeline", [], func(x): return not _velocities(x, midi.x, midi.y).has(40))
		host.undo()
		tl = await _until("GetTimeline", [], func(x): return _note_at(x, midi.x, midi.y, 0.0, 60))
		check("one undo takes the drag back in time and pitch at once", _note_at(tl, midi.x, midi.y, 0.0, 60) and not _note_at(tl, midi.x, midi.y, 0.5, 67))
		host.undo()
		tl = await _until("GetTimeline", [], func(x): return _note_count(x, midi.x, midi.y) == notes_were and not _velocities(x, midi.x, midi.y).has(40))
		check("and three undos in 2D put the clip back in Reaper", _note_count(tl, midi.x, midi.y) == notes_were and not _velocities(tl, midi.x, midi.y).has(40))

	# --- automation ---------------------------------------------------------------------------
	var points := [[2.0, 0.3, DawKitAutomation.LINEAR], [6.0, 0.9, DawKitAutomation.LINEAR], [10.0, 0.5, DawKitAutomation.LINEAR]]
	host.set_automation(ProjectBridge.id_of(2), "volume", points)
	tl = await _until("GetTimeline", [], func(x): return _arr((_track(x, 2).get("automation", {}) as Dictionary).get("volume", [])).size() > 0)
	var lane := _arr((_track(tl, 2).get("automation", {}) as Dictionary).get("volume", [])) if _track(tl, 2).get("automation", {}) is Dictionary else []
	check("a volume lane drawn in 2D is a Reaper envelope (%d values)" % lane.size(), lane.size() > 0)
	host.set_automation(ProjectBridge.id_of(2), "volume", [])
	tl = await _until("GetTimeline", [], func(x): return not (_track(x, 2).get("automation", {}) is Dictionary and (_track(x, 2).get("automation", {}) as Dictionary).has("volume")))
	check("and cleared in 2D, cleared in Reaper", not (_track(tl, 2).get("automation", {}) is Dictionary and (_track(tl, 2).get("automation", {}) as Dictionary).has("volume")))

	# --- Reaper -> 2D -------------------------------------------------------------------------
	await _reaper("SetTrackValue", [4, "D_VOL", 0.25])
	await _wait(1.0)
	view.refresh()
	var strip_db := host.project().track(ProjectBridge.id_of(4)).volume_db
	check("a fader moved in Reaper is the 2D view's (%.1f dB)" % strip_db, absf(strip_db - 20.0 * log(0.25) / log(10.0)) < 0.6)
	view.queue_free()
