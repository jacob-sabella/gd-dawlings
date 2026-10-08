extends SceneTree

## Renders the built-in demo song's parts and reports how long each took, so a change to a
## part's synthesis can be judged for cost as well as sound. Writes WAVs next to the cache too:
##
##   godot --headless --path . -s tools/render_demo_song.gd -- [tempo] [out_dir]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tempo := float(args[0]) if args.size() > 0 else 92.0
	var out_dir := args[1] if args.size() > 1 else ""
	var total := 0
	for role in ["kick", "snare", "hat", "overheads", "bass", "rhodes", "guitar", "voice", "double", "strings"]:
		var t0 := Time.get_ticks_msec()
		var samples := DemoSong.render(role, tempo)
		var ms := Time.get_ticks_msec() - t0
		total += ms
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		print("RENDER %-10s %5d ms  %d samples  peak %.2f" % [role, ms, samples.size(), peak])
		if out_dir != "":
			DemoSong.to_stream(samples).save_to_wav(out_dir.path_join(role + ".wav"))
	print("RENDER total %d ms (serial)" % total)
	quit()
