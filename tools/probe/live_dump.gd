extends Node
## Open the Reaper link the way the app does, wait, and print what the cache holds. For seeing
## what a live Reaper actually sends before blaming the surface that draws it.
##   godot --headless --path . tools/probe/live_dump.tscn -- --reaper-resource DIR [--wait 3]

var _wait := 3.0


func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var options := {}
	for i in argv.size():
		if argv[i] == "--reaper-resource" and i + 1 < argv.size():
			options["bridge_dir"] = argv[i + 1].path_join("Scripts/dawlings_bridge_data")
		if argv[i] == "--wait" and i + 1 < argv.size():
			_wait = float(argv[i + 1])
	var backend := ReaperBackend.new()
	DAW.use(backend, true, options)
	await get_tree().create_timer(_wait).timeout
	var s := DAW.state
	print(backend.summary())
	print("tracks in cache: %d  project_track_count: %d  bank %d/%d" % [s.tracks.size(),
			s.project_track_count, s.bank_offset, s.bank_size])
	for i in s.track_indices():
		var t = s.track(i, false)
		print("  %2d  %-12s vol=%.3f pan=%.2f mute=%s solo=%s arm=%s vu=%.2f fx=%d items=%d" % [i,
				t.name, t.volume, t.pan, t.mute, t.solo, t.rec_arm, t.vu_l, t.plugins().size(), t.items.size()])
	print("transport playing=%s pos=%s tempo=%s length=%s markers=%d" % [s.playing,
			s.position_string, s.tempo, s.project_length, s.markers.size()])
	get_tree().quit()
