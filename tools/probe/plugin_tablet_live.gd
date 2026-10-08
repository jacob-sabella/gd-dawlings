extends Node
## Real third-party plugins on real tablets: loads plugins into the rig's Reaper, puts a
## PluginTablet on each, works every control on it, and reads each result back from Reaper
## through the bridge rather than from the desk's own cache.
##   godot --headless --path . tools/probe/plugin_tablet_live.tscn -- --reaper-resource DIR \
##       [--plugin "Archetype Gojira X"]... [--keep]
## Defaults to the Neural DSP plugins. --keep leaves them loaded (for a screenshot); without it
## everything the probe added is deleted again.

var _failures := 0
var _checks := 0
var _bridge: ScriptBridge
var _plugins: Array[String] = []
var _keep := false
## [track, slot] of every plugin this run added, so it can take them all out again.
var _added: Array = []


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var options := {}
	for i in argv.size():
		if argv[i] == "--reaper-resource" and i + 1 < argv.size():
			options["bridge_dir"] = argv[i + 1].path_join("Scripts/reaper3d_bridge_data")
		elif argv[i] == "--plugin" and i + 1 < argv.size():
			_plugins.append(argv[i + 1])
		elif argv[i] == "--keep":
			_keep = true
	if _plugins.is_empty():
		_plugins = ["Archetype Gojira X", "Archetype Tim Henson X", "Mantra"]
	var backend := ReaperBackend.new()
	if not DAW.use(backend, true, options):
		print("FAIL could not open the link")
		get_tree().quit(2)
		return
	_bridge = backend._bridge
	await _wait(4.0)
	await _run()
	print("\n%d plugin tablet checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _reaper(fn: String, args: Array = [], timeout := 5.0) -> Variant:
	var box := [null, false]
	_bridge.call_reaper(fn, args, func(r) -> void:
		box[0] = r
		box[1] = true)
	var waited := 0.0
	while not box[1] and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return box[0]


static func _arr(v) -> Array:
	return v if v is Array else []


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


static func _names(tracks: Array, index: int) -> Array:
	return _chain(tracks, index).map(func(f): return str(f["name"]))


func _until_structure(cond: Callable, timeout := 3.0) -> Array:
	var started := Time.get_ticks_msec()
	var tracks: Array = []
	while Time.get_ticks_msec() - started < timeout * 1000.0:
		tracks = await _structure()
		if cond.call(tracks):
			break
		await _wait(0.15)
	return tracks


## Wait for the desk's own cache to agree, the way a tablet would see it.
func _until_desk(cond: Callable, timeout := 3.0) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout * 1000.0:
		if cond.call():
			return true
		await _wait(0.1)
	return cond.call()


func _param_value(track: int, fx: int, param: int) -> float:
	var r = await _reaper("GetParamText", [track, fx, param])
	return float(r.get("value", -1.0)) if r is Dictionary else -1.0


func _run() -> void:
	check("Reaper can rearrange chains with the bridge up", DAW.can(DAWBackend.Capability.FX_CHAIN))
	var tracks := await _structure()
	var empty: Array = []
	for t in tracks:
		var i := int(t["index"])
		if i > 1 and _chain(tracks, i).is_empty():
			empty.append(i)
	check("the rig has %d empty tracks to load into (%s)" % [_plugins.size() + 1, empty],
			empty.size() >= _plugins.size() + 1)
	if empty.size() < _plugins.size() + 1:
		return

	# --- load them ------------------------------------------------------------------------
	var loaded: Array = []  # [track, plugin]
	for n in _plugins.size():
		var track: int = empty[n]
		# The first plugin through Wine can take longer than the bridge waits for an answer, so
		# the answer is the chain, not the reply.
		await _reaper("AddFx", [track, _plugins[n]], 60.0)
		var chain := await _until_structure(func(x): return _chain(x, track).size() == 1, 60.0)
		var ok := _chain(chain, track).size() == 1
		check("%s loads on track %d" % [_plugins[n], track], ok)
		if ok:
			_added.append([track, 1])
			loaded.append([track, _plugins[n]])
	tracks = await _until_structure(func(x): return loaded.all(func(l): return _chain(x, l[0]).size() == 1), 30.0)

	for l in loaded:
		await _tablet_checks(l[0], l[1], empty[-1])

	# --- the chain: two of them on one track ----------------------------------------------
	if loaded.size() >= 2:
		await _chain_checks(loaded[0][0], loaded[1][1])

	if not _keep:
		await _clean_up()
	else:
		print("KEPT  %s" % [loaded])


func _tablet_checks(track: int, plugin: String, spare: int) -> void:
	print("\n--- %s on track %d" % [plugin, track])
	var ready := await _until_desk(func(): return DAW.state.tracks.has(track) \
			and DAW.state.track(track).plugins().size() == 1 \
			and DAW.state.fx(track, DAW.state.track(track).plugins()[0]).name.contains(plugin), 10.0)
	check("the desk sees %s" % plugin, ready)
	if not ready:
		return
	var slot: int = DAW.state.track(track).plugins()[0]
	var f := DAW.state.fx(track, slot)
	var tracks := await _structure()
	var real: Dictionary = _chain(tracks, track)[0]
	var listed = await _reaper("ListFxParams", [track, slot])
	var real_params: Array = _arr(listed.get("params", [])) if listed is Dictionary else []
	var real_names: Array = real_params.map(func(e): return str(e["name"]))
	print("  name: %s" % f.name)
	check("named without its type ('%s')" % f.name, not f.name.begins_with("VST"))
	print("  %d real parameters; first: %s" % [real_params.size(), real_names.slice(0, 8)])
	print("  preset: '%s' of %s  wet: %s" % [real.get("preset"), real.get("preset_count"), real.get("wet")])

	var tablet := PluginTablet.create(track, slot, f.name)
	add_child(tablet)
	tablet._process(0.0)
	check("the tablet shows it", tablet._title.text == f.name and not tablet.lost)
	var full := await _until_desk(func():
		tablet._process(0.0)
		return tablet._params().size() >= real_params.size() - 2, 5.0)
	check("it reaches every real parameter (%d of %d)" % [tablet._params().size(), real_params.size()], full)
	var captions: Array = tablet._captions.filter(func(c): return c.visible).map(func(c): return c.text)
	print("  captions: %s" % [captions])
	check("its knobs carry the plugin's own names", not captions.is_empty() and captions.all(
			func(c): return not (c as String).begins_with("P") or not (c as String).substr(1).is_valid_int()))
	check("captioned as Reaper names them", not captions.is_empty() \
			and str(real_names[0]).to_upper().ends_with(captions[0]))
	print("  page: '%s'  preset label: '%s'  mix: '%s'  chain: '%s'"
			% [tablet._page_label.text if tablet._page_label.visible else "(one page)",
			tablet._preset_label.text, tablet._mix_label.text, tablet._chain_label.text])
	var count := tablet._params().size()
	if count > PluginTablet.PER_PAGE:
		check("it says there are more parameters than knobs", tablet._page_label.visible)
		check("and how many there really are (%s vs %d)" % [tablet._page_label.text, count],
				tablet._page_label.text.ends_with("OF %d" % count))

	# A knob: pick the first one sitting well inside its range, and turn it.
	var knob := -1
	for i in tablet._knobs.size():
		var v: float = f.params[tablet._param_for(i)]
		if v > 0.15 and v < 0.85:
			knob = i
			break
	if knob < 0:
		knob = 0
	var param := tablet._param_for(knob)
	var was: float = f.params[param]
	var to := 0.25 if was > 0.5 else 0.75
	tablet._knobs[knob].turned.emit(to)
	await _wait(0.6)
	var now := await _param_value(track, slot, param)
	check("turning %s moves it in the plugin (%.2f -> %.2f, wanted %.2f)"
			% [tablet._param_name(knob), was, now, to], absf(now - to) < 0.02)
	var reading := tablet._param_reading(knob, to)
	await _wait(0.4)
	reading = tablet._param_reading(knob, to)
	print("  %s reads '%s'" % [tablet._param_name(knob), reading])
	check("and reads in the plugin's own words ('%s')" % reading, not reading.ends_with("%") \
			or reading == "%d%%" % roundi(to * 100.0))
	tablet._knobs[knob].turned.emit(was)

	# Past the first 32, which only the bridge reaches: the last page.
	while tablet._page_next.lit:
		tablet._step_page(1)
		tablet._process(0.0)
	tablet._process(0.0)
	var sections: Array = []
	print("  last page: '%s'  captions: %s" % [tablet._page_label.text,
			tablet._captions.filter(func(c): return c.visible).map(func(c): return c.text)])
	var deep := tablet._param_for(0)
	check("the last page is past OSC's 32 (P%d)" % deep, deep > 32)
	await _until_desk(func(): return DAW.state.fx(track, slot).params.has(deep), 3.0)
	check("and its values are read in", DAW.state.fx(track, slot).params.has(deep))
	var deep_was: float = DAW.state.fx(track, slot).params.get(deep, 0.5)
	var deep_to := 0.2 if deep_was > 0.5 else 0.8
	tablet._knobs[0].turned.emit(deep_to)
	await _wait(0.6)
	now = await _param_value(track, slot, deep)
	check("turning %s writes it in the plugin (%.2f, wanted %.2f)" % [tablet._caption_for(0), now, deep_to],
			absf(now - deep_to) < 0.02)
	# And the other way: moved in Reaper (its GUI, automation), the tablet follows.
	await _wait(2.2)
	await _reaper("SetFxParam", [track, slot, deep, deep_was])
	var seen := await _until_desk(func(): return absf(float(DAW.state.fx(track, slot).params.get(deep, -1.0)) - deep_was) < 0.02, 3.0)
	check("moved in Reaper, the tablet's knob follows", seen \
			and absf(tablet._knobs[0].value - deep_was) < 0.02)
	while tablet._page_prev.lit:
		tablet._step_page(-1)
		tablet._process(0.0)
	tablet._process(0.0)
	for page in 40:
		sections.append("%s: %s" % [tablet._page_label.text, ", ".join(tablet._captions.filter(
				func(c): return c.visible).map(func(c): return c.text))])
		if not tablet._page_next.lit:
			break
		tablet._step_page(1)
		tablet._process(0.0)
	print("  pages:\n    %s" % "\n    ".join(sections))
	while tablet._page_prev.lit:
		tablet._step_page(-1)
		tablet._process(0.0)

	# Mix.
	tablet._mix.turned.emit(0.5)
	tracks = await _until_structure(func(x): return absf(float(_chain(x, track)[0].get("wet", 1.0)) - 0.5) < 0.02)
	check("MIX sets its wet/dry (%s)" % _chain(tracks, track)[0].get("wet"),
			absf(float(_chain(tracks, track)[0].get("wet", 1.0)) - 0.5) < 0.02)
	tablet._mix.turned.emit(1.0)

	# Power.
	tablet._bypass.pressed.emit()
	tracks = await _until_structure(func(x): return not bool(_chain(x, track)[0].get("enabled", true)))
	check("POWER bypasses it", not bool(_chain(tracks, track)[0].get("enabled", true)))
	await _until_desk(func(): return not DAW.state.fx(track, slot).enabled)
	tablet._bypass.pressed.emit()
	tracks = await _until_structure(func(x): return bool(_chain(x, track)[0].get("enabled", false)))
	check("and back on", bool(_chain(tracks, track)[0].get("enabled", false)))

	# Presets: Reaper's own if it has any, else the plugin's own buttons, else none to show.
	await _until_desk(func(): return DAW.state.fx(track, slot).preset_count >= 0, 3.0)
	tablet.refresh()
	var own := real_names.has(PluginTablet.PRESET_NEXT)
	print("  presets: Reaper holds %d; the plugin's own buttons: %s; label '%s'"
			% [DAW.state.fx(track, slot).preset_count, own, tablet._preset_label.text])
	if DAW.state.fx(track, slot).preset_count == 0 and not own:
		check("with no presets anywhere it says so and hides ◀▶",
				tablet._preset_label.text == "none saved" and not tablet._preset_next.visible)
	elif DAW.state.fx(track, slot).preset_count == 0:
		check("it steps the plugin's own presets", tablet._own_presets() and tablet._preset_next.visible)
		check("and those buttons are not knobs", not tablet._params().has(tablet._named(PluginTablet.PRESET_NEXT)))
		var every: Array = real_params.map(func(e): return int(e["index"])).slice(0, 32)
		var before = await _reaper("GetFxParams", [track, slot] + every)
		tablet._preset_next.pressed.emit()
		await _wait(2.5)
		var after = await _reaper("GetFxParams", [track, slot] + every)
		var moved := 0
		for i in mini(_arr(before.get("params", [])).size(), _arr(after.get("params", [])).size()):
			if absf(float(before["params"][i]["value"]) - float(after["params"][i]["value"])) > 0.001:
				moved += 1
		check("PRESET ▶ loads another of its presets (%d controls moved)" % moved, moved > 0)
		tablet._preset_prev.pressed.emit()
		await _wait(2.5)
	else:
		var preset_was := str(_chain(tracks, track)[0].get("preset", ""))
		tablet._preset_next.pressed.emit()
		tracks = await _until_structure(func(x): return str(_chain(x, track)[0].get("preset", "")) != preset_was, 8.0)
		check("PRESET ▶ steps Reaper's presets", str(_chain(tracks, track)[0].get("preset", "")) != preset_was)
		tablet._preset_prev.pressed.emit()

	# Key in from the spare track.
	var sends_were := _sends_of(tracks, spare).size()
	tablet._key.choice = spare
	tablet._key.pressed.emit(spare)
	tracks = await _until_structure(func(x): return _sends_of(x, spare).size() > sends_were)
	var made: Array = _sends_of(tracks, spare)
	check("KEY IN patches track %d into its sidechain" % spare,
			made.size() == sends_were + 1 and bool(made[-1].get("key", false)))
	await _until_desk(func(): return tablet.keyed_by() == [spare])
	tablet.refresh()
	check("and the window lights", tablet._key.lit)
	tablet._key.pressed.emit(spare)
	tracks = await _until_structure(func(x): return _sends_of(x, spare).size() == sends_were)
	check("pressed again it is pulled", _sends_of(tracks, spare).size() == sends_were)

	# Move to the spare track and back.
	tablet.move_to_track(spare)
	tracks = await _until_structure(func(x): return _chain(x, spare).size() == 1)
	check("MOVE TO takes it to track %d" % spare, _names(tracks, spare).size() == 1 \
			and _names(tracks, track).is_empty())
	var followed := await _until_desk(func(): return tablet.track_index == spare and not tablet.lost)
	check("and the tablet follows it", followed)
	tablet.move_to_track(track)
	tracks = await _until_structure(func(x): return _chain(x, track).size() == 1)
	check("and back", _names(tracks, track).size() == 1 and _chain(tracks, spare).is_empty())
	await _until_desk(func(): return tablet.track_index == track and not tablet.lost)
	remove_child(tablet)
	tablet.free()


## Load `second` after what is already on `track`, then use the second one's tablet to swap them.
func _chain_checks(track: int, second: String) -> void:
	print("\n--- chain: %s after the plugin on track %d" % [second, track])
	var r = await _reaper("AddFx", [track, second], 60.0)
	if not (r is Dictionary and r.get("ok", false)):
		check("a second plugin loads on track %d" % track, false)
		return
	_added.append([track, int(r["fx"])])
	var tracks := await _until_structure(func(x): return _chain(x, track).size() == 2, 30.0)
	var before := _names(tracks, track)
	var bare: Array = before.map(func(n): return MixState.FXState.bare_name(n))
	await _until_desk(func(): return DAW.state.track(track).plugins().size() == 2 \
			and DAW.state.track(track).plugins().map(func(i): return DAW.state.fx(track, i).name) == bare, 10.0)
	var order := DAW.state.track(track).plugins()
	var tablet := PluginTablet.create(track, order[1], DAW.state.fx(track, order[1]).name)
	add_child(tablet)
	tablet._process(0.0)
	check("the second one is 2 OF 2", tablet._chain_label.text == "2 OF 2")
	tablet._shift(-1)
	tracks = await _until_structure(func(x): return _names(x, track) == [before[1], before[0]])
	check("CHAIN ▲ puts it first (%s)" % [_names(tracks, track)], _names(tracks, track) == [before[1], before[0]])
	await _wait(1.0)
	tablet._process(0.0)
	check("and its tablet still shows it, first (%s, %s)" % [tablet.fx_name, tablet._chain_label.text],
			not tablet.lost and tablet.fx().name == bare[1] and tablet._chain_label.text == "1 OF 2")
	tablet._shift(1)
	tracks = await _until_structure(func(x): return _names(x, track) == before)
	check("CHAIN ▼ puts it back", _names(tracks, track) == before)
	remove_child(tablet)
	tablet.free()


func _clean_up() -> void:
	var tracks := await _structure()
	var touched := {}
	for a in _added:
		touched[a[0]] = true
	for t in touched:
		for n in _chain(tracks, t).size():
			await _reaper("DeleteFx", [t, 1])
	tracks = await _until_structure(func(x): return touched.keys().all(func(t): return _chain(x, t).is_empty()))
	check("every plugin the probe added is gone again",
			touched.keys().all(func(t): return _chain(tracks, t).is_empty()))
