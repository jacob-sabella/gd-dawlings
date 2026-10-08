extends Node
## Drive a live Reaper from the desk's own commands and read every result back from Reaper itself
## through the bridge's GetState -- a different road from the OSC echo the desk listens to.
## Then the other way: change things in Reaper and check the desk's cache follows.
##   godot --headless --path . tools/probe/live_check.tscn -- --reaper-resource DIR
## Prints PASS/FAIL per check and exits non-zero on any failure. Leaves the project as it found it.

var _failures := 0
var _checks := 0
var _bridge: ScriptBridge


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var options := {}
	for i in argv.size():
		if argv[i] == "--reaper-resource" and i + 1 < argv.size():
			options["bridge_dir"] = argv[i + 1].path_join("Scripts/reaper3d_bridge_data")
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


## Read Reaper's state until `cond` holds or `timeout` passes. Returns the last state read, with
## how long it took under "_waited" -- so a slow answer and a wrong one are told apart.
func _until(cond: Callable, timeout := 3.0) -> Dictionary:
	var started := Time.get_ticks_msec()
	var st := {}
	while true:
		st = await _state()
		if not st.is_empty() and cond.call(st):
			break
		if Time.get_ticks_msec() - started > timeout * 1000.0:
			break
		await _wait(0.1)
	st["_waited"] = (Time.get_ticks_msec() - started) / 1000.0
	return st


func _until_marker(present: bool, timeout := 3.0) -> Array:
	var started := Time.get_ticks_msec()
	var marks: Array = []
	while Time.get_ticks_msec() - started < timeout * 1000.0:
		var r = await _reaper("GetTimeline")
		marks = _arr(r.get("markers", [])) if r is Dictionary else []
		if _live_mark(marks) == present:
			break
		await _wait(0.1)
	return marks


static func _live_mark(marks: Array) -> bool:
	for m in marks:
		if m is Dictionary and absf(float(m.get("position", -1.0)) - 3.5) < 0.01 \
				and str(m.get("name", "")) == "LIVE CHECK":
			return true
	return false


func _state() -> Dictionary:
	var r = await _reaper("GetState", [8])
	return r if r is Dictionary else {}


## The bridge's encoder cannot tell an empty list from an empty object, so an empty one arrives
## as {}. Everything read as a list goes through this.
static func _arr(v) -> Array:
	return v if v is Array else []


func _track(st: Dictionary, index: int) -> Dictionary:
	for t in _arr(st.get("tracks", [])):
		if int(t["index"]) == index:
			return t
	# A missing track reads as an empty one, so a bad read fails a check instead of the run.
	return {"index": index, "items": [], "fx": [], "volume": 0.0, "pan": 0.0,
			"mute": false, "solo": false, "arm": false}


func _run() -> void:
	var s := DAW.state
	check("the desk sees the whole project (%d tracks)" % s.tracks.size(), s.tracks.size() == 40)
	var named := 0
	for i in s.track_indices():
		if not s.track(i).name.begins_with("Track "):
			named += 1
	check("and every track's name (%d of 40)" % named, named == 40)
	var st := await _state()
	check("Reaper answers GetState", not st.is_empty())
	if st.is_empty():
		return
	var original := st.duplicate(true)

	# --- desk -> Reaper ------------------------------------------------------------------
	DAW.transport_stop()
	DAW.set_track_volume(1, 0.5)
	DAW.set_track_pan(2, 0.25)
	DAW.set_track_mute(3, true)
	DAW.set_track_solo(4, true)
	DAW.set_track_rec_arm(5, true)
	await _wait(0.8)
	st = await _state()
	var want_db := DAW.taper_to_db(0.5)
	var got_db := 20.0 * log(float(_track(st, 1)["volume"])) / log(10.0)
	check("fader 1 at %.1f dB on the desk is %.1f dB in Reaper" % [want_db, got_db], absf(want_db - got_db) < 0.6)
	check("pan 2 hard-ish left (%.2f)" % float(_track(st, 2)["pan"]), absf(float(_track(st, 2)["pan"]) + 0.5) < 0.02)
	check("mute 3 is muted in Reaper", _track(st, 3)["mute"])
	check("solo 4 is soloed in Reaper", _track(st, 4)["solo"])
	check("arm 5 is armed in Reaper", _track(st, 5)["arm"])
	check("and the desk agrees with all five", s.track(3).mute and s.track(4).solo and s.track(5).rec_arm)
	# Meters read true: with track 4 soloed and the transport stopped, nothing should meter.
	await _wait(0.6)
	check("meters are dark with the transport stopped (track 1 at %.3f)" % s.track(1).vu_l, s.track(1).vu_l < 0.05)

	# --- Reaper -> desk ------------------------------------------------------------------
	await _reaper("SetTrackValue", [6, "D_VOL", 0.25])
	await _reaper("SetTrackValue", [7, "B_MUTE", 1])
	await _reaper("SetTrackValue", [8, "D_PAN", 0.5])
	await _wait(0.8)
	var desk_db := s.track(6).volume_db
	check("a fader moved in Reaper moves on the desk (%.1f dB, want %.1f)" % [desk_db, 20.0 * log(0.25) / log(10.0)],
			absf(desk_db - 20.0 * log(0.25) / log(10.0)) < 0.6)
	check("a mute in Reaper lights on the desk", s.track(7).mute)
	check("a pan in Reaper turns the desk's knob (%.2f)" % s.track(8).pan, absf(s.track(8).pan - 0.75) < 0.02)

	# --- FX -------------------------------------------------------------------------------
	var fx_track := -1
	for t in st["tracks"]:
		if _arr(t["fx"]).size() > 0:
			fx_track = int(t["index"])
			break
	check("there is a track with plugins (%d)" % fx_track, fx_track > 0)
	if fx_track > 0:
		check("the desk sees its chain (%d plugins)" % s.track(fx_track).plugins().size(),
				s.track(fx_track).plugins().size() == _arr(_track(st, fx_track)["fx"]).size())
		DAW.set_fx_enabled(fx_track, 1, false)
		DAW.set_fx_param(fx_track, 1, 2, 0.3)
		await _wait(0.8)
		st = await _state()
		var f: Dictionary = _track(st, fx_track)["fx"][0]
		check("bypass from the rack bypasses the plugin in Reaper", not f["enabled"])
		check("a parameter turned on the rack is set in Reaper (%.3f)" % float(f["params"][1]),
				absf(float(f["params"][1]) - 0.3) < 0.01)
		DAW.set_fx_enabled(fx_track, 1, true)

	# --- transport ------------------------------------------------------------------------
	DAW.set_track_solo(4, false)
	DAW.seek(30.0)
	await _wait(0.5)
	st = await _state()
	check("seek moves Reaper's cursor to 30 s (%.2f)" % float(st["cursor"]), absf(float(st["cursor"]) - 30.0) < 0.05)
	DAW.set_loop_range(16.0, 24.0)
	DAW.set_looping(true)
	st = await _until(func(x): return absf(float(x["loop_end"]) - 24.0) < 0.05 and x["repeating"])
	print("      (loop read back after %.2fs)" % st["_waited"])
	check("the loop range is Reaper's loop (%.2f-%.2f)" % [float(st["loop_start"]), float(st["loop_end"])],
			absf(float(st["loop_start"]) - 16.0) < 0.05 and absf(float(st["loop_end"]) - 24.0) < 0.05)
	check("loop on is Reaper's repeat", st["repeating"])
	DAW.seek(22.0)
	DAW.transport_play()
	await _wait(3.0)
	st = await _state()
	check("play plays", st["playing"])
	check("and loops: 3 s after 22 s inside 16-24 is ~17 s (%.2f)" % float(st["position"]),
			float(st["position"]) > 16.0 and float(st["position"]) < 19.5)
	check("the desk's counter is bar/beat (%s)" % s.position_string, s.position_string.count(".") >= 1)
	var lit := 0
	for i in s.track_indices():
		if s.track(i).vu_l > 0.01:
			lit += 1
	check("meters move while playing (%d strips lit)" % lit, lit > 0)
	DAW.transport_stop()
	DAW.set_looping(false)
	st = await _until(func(x): return not x["playing"] and not x["repeating"])
	print("      (stop read back after %.2fs)" % st["_waited"])
	check("stop stops", not st["playing"])
	check("loop off", not st["repeating"])

	# Record: arm one track, roll a second, stop, then undo the take away.
	var items_before := _arr(_track(st, 5)["items"]).size()
	# Past the last item: a take recorded over an existing one splits it, and the count goes up
	# by two for a reason that has nothing to do with the desk.
	var clear := 0.0
	for item in _arr(_track(st, 5)["items"]):
		clear = maxf(clear, float(item["start"]) + float(item["length"]))
	DAW.seek(clear + 4.0)
	DAW.transport_record()
	await _wait(1.2)
	st = await _state()
	check("record records", st["recording"])
	check("and the desk says so", s.recording)
	DAW.transport_stop()
	st = await _until(func(x): return _arr(_track(x, 5)["items"]).size() > items_before)
	print("      (take read back after %.2fs)" % st["_waited"])
	var items_after := _arr(_track(st, 5)["items"]).size()
	check("the take landed on the armed track (%d -> %d items)" % [items_before, items_after], items_after == items_before + 1)

	# --- undo -----------------------------------------------------------------------------
	DAW.undo()
	st = await _until(func(x): return _arr(_track(x, 5)["items"]).size() == items_before)
	check("undo takes the recording back (%d items)" % _arr(_track(st, 5)["items"]).size(),
			_arr(_track(st, 5)["items"]).size() == items_before)
	DAW.redo()
	st = await _until(func(x): return _arr(_track(x, 5)["items"]).size() == items_after)
	check("redo puts it back", _arr(_track(st, 5)["items"]).size() == items_after)
	DAW.undo()
	await _wait(0.6)

	# --- editing --------------------------------------------------------------------------
	st = await _state()
	var lane: Array = _arr(_track(st, 7)["items"])
	check("track 7 has items to edit (%d)" % lane.size(), lane.size() >= 2)
	if lane.size() >= 2:
		var first_start := float(lane[0]["start"])
		DAW.select_item(7, 0, false)
		st = await _until(func(x): return _arr(_track(x, 7)["items"])[0]["selected"])
		var others := 0
		for t in _arr(st["tracks"]):
			for it in _arr(t["items"]):
				if it["selected"] and not (int(t["index"]) == 7 and is_equal_approx(float(it["start"]), first_start)):
					others += 1
		check("selecting an item on the desk selects it in Reaper, and only it (%d others)" % others,
				_arr(_track(st, 7)["items"])[0]["selected"] and others == 0)
		DAW.move_item(7, 0, first_start + 1.0)
		check("the desk shows the move at once", is_equal_approx(s.item(7, 0).start, first_start + 1.0))
		st = await _until(func(x): return absf(float(_arr(_track(x, 7)["items"])[0]["start"]) - first_start - 1.0) < 0.001)
		check("and Reaper has it (%.3f)" % float(_arr(_track(st, 7)["items"])[0]["start"]),
				absf(float(_arr(_track(st, 7)["items"])[0]["start"]) - first_start - 1.0) < 0.001)
		await _wait(2.6)
		check("and the desk still has it after Reaper's own timeline comes back (%.3f)" % s.item(7, 0).start,
				is_equal_approx(s.item(7, 0).start, first_start + 1.0) and s.item(7, 0).selected)

		var second: Dictionary = _arr(_track(st, 7)["items"])[1]
		var cut := float(second["start"]) + float(second["length"]) * 0.5
		DAW.select_item(7, 1, false)
		DAW.seek(cut)
		DAW.split_selected(cut)
		st = await _until(func(x): return _arr(_track(x, 7)["items"]).size() == lane.size() + 1)
		check("split on the desk splits the item in Reaper (%d -> %d)" % [lane.size(), _arr(_track(st, 7)["items"]).size()],
				_arr(_track(st, 7)["items"]).size() == lane.size() + 1)
		check("at the playhead (%.3f)" % float(_arr(_track(st, 7)["items"])[2]["start"]),
				absf(float(_arr(_track(st, 7)["items"])[2]["start"]) - cut) < 0.001)
		await _wait(2.6)
		check("and the desk agrees (%d items)" % s.track(7).items.size(), s.track(7).items.size() == lane.size() + 1)

		DAW.undo()
		st = await _until(func(x): return _arr(_track(x, 7)["items"]).size() == lane.size())
		check("undo joins the split in Reaper", _arr(_track(st, 7)["items"]).size() == lane.size())
		DAW.undo()
		st = await _until(func(x): return absf(float(_arr(_track(x, 7)["items"])[0]["start"]) - first_start) < 0.001)
		check("undo takes the move back", absf(float(_arr(_track(st, 7)["items"])[0]["start"]) - first_start) < 0.001)
		await _wait(2.6)
		check("and the desk follows Reaper's undo (%d items, first at %.2f)" % [s.track(7).items.size(), s.item(7, 0).start],
				s.track(7).items.size() == lane.size() and is_equal_approx(s.item(7, 0).start, first_start))
		DAW.clear_item_selection()

	# --- sends and the click --------------------------------------------------------------
	var send_track := 0
	for t in _arr(original["tracks"]):
		if send_track == 0 and not _arr(t.get("sends", [])).is_empty():
			send_track = int(t["index"])
	check("there is a track with a send (%d)" % send_track, send_track > 0)
	if send_track > 0:
		DAW.set_send_volume(send_track, 1, DAW.db_to_taper(-9.0))
		DAW.set_send_pan(send_track, 1, 0.25)
		st = await _until(func(x): return absf(float(_arr(_track(x, send_track)["sends"])[0]["pan"]) + 0.5) < 0.02)
		var sent: Dictionary = _arr(_track(st, send_track)["sends"])[0]
		var sent_db := 20.0 * log(maxf(float(sent["volume"]), 1e-9)) / log(10.0)
		check("a send level from the desk is Reaper's send level (%.2f dB, want -9)" % sent_db, absf(sent_db + 9.0) < 0.3)
		check("and its pan is Reaper's (%.2f)" % float(sent["pan"]), absf(float(sent["pan"]) + 0.5) < 0.02)
	var click_was: bool = original.get("metronome", false)
	DAW.set_metronome(not click_was)
	st = await _until(func(x): return x.get("metronome", click_was) != click_was)
	check("the deck's CLICK switches Reaper's metronome (%s)" % st.get("metronome"), st.get("metronome", click_was) != click_was)
	DAW.set_metronome(click_was)
	st = await _until(func(x): return x.get("metronome", not click_was) == click_was)
	check("and switches it back", st.get("metronome", not click_was) == click_was)

	# --- input monitoring, both ways ----------------------------------------------------------
	var mon_was := int(roundf(float(_track(original, 3).get("monitor", 0))))
	var mon_to := (mon_was + 2) % 3
	DAW.set_track_monitor(3, mon_to)
	st = await _until(func(x): return int(roundf(float(_track(x, 3).get("monitor", -1)))) == mon_to)
	check("the strip's monitor key sets Reaper's input monitoring (%s, want %d)" % [
			_track(st, 3).get("monitor"), mon_to],
			int(roundf(float(_track(st, 3).get("monitor", -1)))) == mon_to)
	var mon_back := (mon_to + 1) % 3
	await _reaper("SetTrackValue", [3, "I_RECMON", mon_back])
	await _wait(0.8)
	check("and monitoring set in Reaper reaches the desk (%d, want %d)" % [s.track(3).monitor, mon_back],
			s.track(3).monitor == mon_back)

	# --- a marker from the locator: read back from Reaper's own marker list ----------------
	check("Reaper can take markers with the bridge up", DAW.can(DAWBackend.Capability.MARKERS))
	DAW.add_marker(3.5, "LIVE CHECK")
	var marks := await _until_marker(true)
	check("MARK puts a marker in Reaper's project (%s)" % [marks], _live_mark(marks))
	DAW.undo()
	marks = await _until_marker(false)
	check("and one undo takes it out again", not _live_mark(marks))

	# --- a plugin off the rack: wet, preset, move, and a key into it ---------------------------
	await _plugin_checks()

	# --- put everything back ----------------------------------------------------------------
	if send_track > 0:
		var was: Dictionary = _arr(_track(original, send_track)["sends"])[0]
		DAW.set_send_volume(send_track, 1, DAW.db_to_taper(20.0 * log(maxf(float(was["volume"]), 1e-9)) / log(10.0)))
		DAW.set_send_pan(send_track, 1, (float(was["pan"]) + 1.0) * 0.5)
	for t in original["tracks"]:
		var i := int(t["index"])
		if i > 8:
			continue
		await _reaper("SetTrackValue", [i, "D_VOL", t["volume"]])
		await _reaper("SetTrackValue", [i, "D_PAN", t["pan"]])
		await _reaper("SetTrackValue", [i, "B_MUTE", 1 if t["mute"] else 0])
		await _reaper("SetTrackValue", [i, "I_SOLO", 1 if t["solo"] else 0])
		await _reaper("SetTrackValue", [i, "I_RECARM", 1 if t["arm"] else 0])
		await _reaper("SetTrackValue", [i, "I_RECMON", int(roundf(float(t.get("monitor", 0))))])
	# Item positions too: a run that failed halfway through an edit must not leave the next run
	# starting from a different arrangement.
	var now_lanes := await _state()
	for t in _arr(original["tracks"]):
		var was: Array = _arr(t["items"])
		var is_now: Array = _arr(_track(now_lanes, int(t["index"]))["items"])
		if was.size() == is_now.size():
			for n in was.size():
				if absf(float(was[n]["start"]) - float(is_now[n]["start"])) > 0.0005:
					await _reaper("MoveItem", [int(t["index"]), n, float(was[n]["start"])])
	if fx_track > 0:
		DAW.set_fx_param(fx_track, 1, 2, float(_track(original, fx_track)["fx"][0]["params"][1]))
	DAW.set_loop_range(float(original["loop_start"]), float(original["loop_end"]))
	DAW.seek(0.0)
	await _wait(0.5)


func _structure() -> Array:
	var r = await _reaper("GetProjectStructure", [1])
	return _arr(r.get("tracks", [])) if r is Dictionary else []


static func _chain(tracks: Array, index: int) -> Array:
	for t in tracks:
		if int(t.get("index", 0)) == index:
			return _arr(t.get("fx", []))
	return []


static func _sends_of(tracks: Array, index: int) -> Array:
	for t in tracks:
		if int(t.get("index", 0)) == index:
			return _arr(t.get("sends", []))
	return []


func _until_structure(cond: Callable, timeout := 3.0) -> Array:
	var started := Time.get_ticks_msec()
	var tracks: Array = []
	while Time.get_ticks_msec() - started < timeout * 1000.0:
		tracks = await _structure()
		if cond.call(tracks):
			break
		await _wait(0.15)
	return tracks


func _plugin_checks() -> void:
	check("Reaper can rearrange chains with the bridge up", DAW.can(DAWBackend.Capability.FX_CHAIN))
	var tracks := await _structure()
	var host := -1
	var other := -1
	for t in tracks:
		var n := _chain(tracks, int(t["index"])).size()
		if n >= 2 and host < 0:
			host = int(t["index"])
		elif n == 0 and other < 0 and int(t["index"]) > 1:
			other = int(t["index"])
	check("the rig has a track with two plugins (%d) and one with none (%d)" % [host, other],
			host > 0 and other > 0)
	if host < 0 or other < 0:
		return
	var names_were: Array = _chain(tracks, host).map(func(f): return str(f["name"]))

	# Wet/dry.
	var wet_was := float(_chain(tracks, host)[0].get("wet", 1.0))
	DAW.set_fx_wet(host, 1, 0.4)
	tracks = await _until_structure(func(x): return absf(float(_chain(x, host)[0].get("wet", 1.0)) - 0.4) < 0.02)
	check("the tablet's wet/dry sets the plugin's own (%s)" % _chain(tracks, host)[0].get("wet"),
			absf(float(_chain(tracks, host)[0].get("wet", 1.0)) - 0.4) < 0.02)
	DAW.set_fx_wet(host, 1, wet_was)

	# Move to the end of an empty chain, then back where it was.
	DAW.move_fx(host, 1, other, 1)
	tracks = await _until_structure(func(x): return _chain(x, other).size() == 1)
	check("a plugin moved to another track lands there (%s)" % [_chain(tracks, other).map(func(f): return f["name"])],
			_chain(tracks, other).size() == 1 and str(_chain(tracks, other)[0]["name"]) == names_were[0])
	check("and leaves its own chain", _chain(tracks, host).size() == names_were.size() - 1)
	await _wait(0.6)
	check("the desk's cache saw it go (%s)" % [DAW.state.track(host).plugins().size()],
			DAW.state.track(host).plugins().size() == names_were.size() - 1)
	DAW.move_fx(other, 1, host, 1)
	tracks = await _until_structure(func(x): return _chain(x, other).is_empty())
	check("and moves back to the top of its chain",
			_chain(tracks, host).map(func(f): return str(f["name"])) == names_were)

	# A key from `other` into `host`.
	var sends_were := _sends_of(tracks, other).size()
	DAW.create_sidechain(other, host)
	tracks = await _until_structure(func(x): return _sends_of(x, other).size() > sends_were)
	var made: Array = _sends_of(tracks, other)
	check("a sidechain is a send into channels 3/4 (%s)" % [made],
			made.size() == sends_were + 1 and bool(made[-1].get("key", false)))
	if made.size() > sends_were:
		DAW.remove_send(other, made.size())
		tracks = await _until_structure(func(x): return _sends_of(x, other).size() == sends_were)
		check("and comes out like any other send", _sends_of(tracks, other).size() == sends_were)
