extends Node
## Third-party plugins in the built-in engine, with real sound: loads plugins from this machine's
## catalogue onto the demo song's tracks, plays the song through them, and opens each one's own
## window as the tablet would, saving a picture of it.
##   tools/offscreen.sh's offscreen_run godot --path . tools/probe/hosted_plugin_live.tscn -- \
##       [--plugin "NAMix"]... [--out DIR]
## A real window and a sound card, not --headless: headless mixes nothing.

var _failures := 0
var _checks := 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var wanted: Array[String] = []
	var out := "/tmp"
	for i in argv.size():
		if argv[i] == "--plugin" and i + 1 < argv.size():
			wanted.append(argv[i + 1])
		elif argv[i] == "--out" and i + 1 < argv.size():
			out = argv[i + 1]
	if wanted.is_empty():
		wanted = ["NAMix", "LSP Compressor Stereo"]
	var catalogue := PluginCatalogue.shared()
	catalogue.wait()
	check("the catalogue found plugins (%d)" % catalogue.plugins().size(), catalogue.plugins().size() > 0)
	var backend := GodotBackend.new()
	# Each plugin loaded before add_fx answers, so it can be checked at once.
	backend.hosted.threaded = false
	backend.state = MixState.new()
	DAW.use(backend)
	check("the engine plays through lanes, with a sound card", backend.lanes != null)
	var tracks: Array = DAW.state.track_indices()
	var on := {}
	for n in wanted.size():
		var info := {}
		for p in catalogue.plugins():
			if p["name"] == wanted[n]:
				info = p
		if info.is_empty():
			check("%s is installed" % wanted[n], false)
			continue
		var t: int = tracks[n + 1]
		DAW.add_fx(t, GodotBackend.plugin_choice(info))
		var at: int = DAW.state.track(t).plugins()[-1]
		var p = backend.hosted_plugin(t, at)
		check("%s loads onto track %d (%s)" % [wanted[n], t, backend.hosted.last_error], p != null)
		if p != null:
			on[wanted[n]] = [t, at, p]
	DAW.transport_play()
	var before := {}
	for name in on:
		before[name] = on[name][2].blocks_run()
	var clock_before: int = backend.lanes.transport.get_clock()
	await _wait(2.0)
	for name in on:
		var ran: int = on[name][2].blocks_run() - before[name]
		var mixed: int = backend.lanes.transport.get_clock() - clock_before
		# Once a block of the mixer's (512 frames), however many buses it is on.
		check("%s runs once a block as the song plays (%d runs, %d blocks mixed)" % [name, ran, mixed / 512],
				ran > 50 and absi(ran - mixed / 512) <= 4)
	DAW.transport_stop()
	for name in on:
		var t: int = on[name][0]
		var at: int = on[name][1]
		if not DAW.has_plugin_window(t, at):
			print("(no window for %s)" % name)
			continue
		var w := DAW.open_plugin_window(t, at)
		check("%s's window opens" % name, w != null)
		if w == null:
			continue
		var waited := 0.0
		while waited < 5.0 and w.texture() == null:
			w.poll()
			await get_tree().process_frame
			waited += get_process_delta_time()
		check("and shows a picture (%s)" % [w.pixel_size()], w.texture() != null and w.pixel_size().x > 50)
		if w.texture() != null:
			var file := out.path_join("hosted_%s.png" % name.validate_filename().replace(" ", "_"))
			w.texture().get_image().save_png(file)
			print("saved ", file)
		w.close()
	backend.close()
	print("\n%d hosted plugin checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
