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

	# --- put everything back ----------------------------------------------------------------
	for t in original["tracks"]:
		var i := int(t["index"])
		if i > 8:
			continue
		await _reaper("SetTrackValue", [i, "D_VOL", t["volume"]])
		await _reaper("SetTrackValue", [i, "D_PAN", t["pan"]])
		await _reaper("SetTrackValue", [i, "B_MUTE", 1 if t["mute"] else 0])
		await _reaper("SetTrackValue", [i, "I_SOLO", 1 if t["solo"] else 0])
		await _reaper("SetTrackValue", [i, "I_RECARM", 1 if t["arm"] else 0])
	if fx_track > 0:
		DAW.set_fx_param(fx_track, 1, 2, float(_track(original, fx_track)["fx"][0]["params"][1]))
	DAW.set_loop_range(float(original["loop_start"]), float(original["loop_end"]))
	DAW.seek(0.0)
	await _wait(0.5)
