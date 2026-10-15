extends Node
## A plugin's own dropdown in the rig's Reaper, worked from here: opens a plugin's window through
## the bridge, sends it the steps given, and saves the picture after each.
##   godot --path . tools/probe/reaper_menu_live.tscn -- --reaper-resource DIR --track NAME \
##       [--fx N] [--out DIR] [--steps "c:X,Y m:X,Y ..."] [--add PLUGIN --index TRACK]
## c is a click, m a move, w a wait, all in the plugin picture's pixels. --add puts a plugin on an
## empty track first (by number), works that, and takes it out again.

func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var options := {}
	var track_name := "Kick In"
	var fx := 0
	var out := "/tmp"
	var steps := ""
	var add := ""
	var index := -1
	for i in argv.size():
		if i + 1 >= argv.size():
			break
		match argv[i]:
			"--reaper-resource": options["bridge_dir"] = argv[i + 1].path_join("Scripts/dawlings_bridge_data")
			"--track": track_name = argv[i + 1]
			"--fx": fx = int(argv[i + 1])
			"--out": out = argv[i + 1]
			"--steps": steps = argv[i + 1]
			"--add": add = argv[i + 1]
			"--index": index = int(argv[i + 1])
	var backend := ReaperBackend.new()
	if not DAW.use(backend, true, options):
		print("FAIL could not open the link")
		get_tree().quit(2)
		return
	await _wait(4.0)
	var track := -1
	for t in DAW.state.track_indices():
		if DAW.state.track(t).name == track_name:
			track = t
	if index >= 0:
		track = index
	print("track %s is %d" % [track_name, track])
	var bridge: ScriptBridge = backend._bridge
	if add != "":
		bridge.call_reaper("AddFx", [track, add], func(r) -> void: print("AddFx said ", r))
		var waited := 0.0
		while waited < 60.0 and DAW.state.track(track).plugins().is_empty():
			await _wait(1.0)
			waited += 1.0
		fx = DAW.state.track(track).plugins()[-1] if not DAW.state.track(track).plugins().is_empty() else 1
		await _wait(3.0)
	for t in DAW.state.track_indices():
		var listed := []
		for f in DAW.state.track(t).plugins():
			listed.append("%d:%s" % [f, DAW.state.fx(t, f).name])
		if not listed.is_empty():
			print("  %d %s %s" % [t, DAW.state.track(t).name, listed])
	var w := DAW.open_plugin_window(track, fx)
	if w == null:
		print("FAIL no window")
		get_tree().quit(1)
		return
	await _settle(w, 3.0)
	print("open %s, %s" % [w.is_open(), w.pixel_size()])
	_save(w, out, 0)
	var n := 1
	for step in steps.split(" ", false):
		var kind := step.substr(0, 1)
		var at := Vector2i.ZERO
		var xy := step.substr(2).split(",")
		if xy.size() == 2:
			at = Vector2i(int(xy[0]), int(xy[1]))
		match kind:
			"c":
				w.pointer_move(at)
				await _settle(w, 0.1)
				w.pointer_down(at)
				await _settle(w, 0.1)
				w.pointer_up(at)
			"m":
				w.pointer_move(at)
			"w":
				await _settle(w, float(step.substr(2)))
		await _settle(w, 0.8)
		_save(w, out, n)
		print("step %d %s" % [n, step])
		n += 1
	w.close()
	await _wait(0.5)
	if add != "":
		bridge.call_reaper("DeleteFx", [track, fx])
		await _wait(2.0)
	backend.close()
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _settle(w: PluginWindow, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		w.poll()
		await get_tree().process_frame
		waited += get_process_delta_time()


func _save(w: PluginWindow, out: String, n: int) -> void:
	if w.texture() != null:
		w.texture().get_image().save_png(out.path_join("menu_%d.png" % n))
		print("saved %d %s" % [n, w.pixel_size()])
