extends Node
## Plays a rack preset (or patch file) straight to the speakers for a while and prints how the direct feed did
## (RackVoice.direct_stats): mean and least generator fill, underruns, the worst frame.
## offscreen_run godot --path . tools/rack_pump_probe.tscn -- acid_line 60 [stall_ms_every_second [studio]]
## The window must not be vsynced (see tools/shot.sh's override.cfg), and the sound goes where PULSE_SINK says.
var voice: RackVoice
var t0 := 0
var secs := 60.0
var stall_ms := 0
var last_print := 0
var _pumps := 0
var _fill_sum := 0.0
var _fill_min := 1 << 30
var _worst_ms := 0.0
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "acid_line"
	secs = float(args[1]) if args.size() > 1 else 60.0
	stall_ms = int(args[2]) if args.size() > 2 else 0
	Engine.max_fps = 60
	if args.size() > 3 and args[3] == "studio":
		# The whole studio around the rack: the frame times the game really has.
		DAW.use(OfflineBackend.new())
		var studio := Studio.new()
		studio.medium = Presentation.Medium.SCREEN
		add_child(studio)
		for i in 180:
			await get_tree().process_frame
		voice = studio.rack_voice
		voice.set_track(0)
	else:
		voice = RackVoice.new()
		add_child(voice)
	var p: Dictionary
	if which.ends_with(".json"):
		p = RackPatch.sanitize(JSON.parse_string(FileAccess.get_file_as_string(which)))
	else:
		p = RackPatch.preset(StringName(which))
	voice.set_patch(p)
	print("driver ", AudioServer.get_driver_name(), " mix ", AudioServer.get_mix_rate(), " started ", voice.start())
	voice.transport_override = func(): return {"playing": true, "beats": 0.0, "bpm": 120.0}
	voice.follow_daw = true
	t0 = Time.get_ticks_msec()
var _next_note := 0
var _down := false
var _pitch := 48
func _process(d: float) -> void:
	if voice == null:
		return
	if Time.get_ticks_msec() > _next_note:
		# A note of 350 ms every 700 ms (a gate that falls between, so an envelope fires again).
		_next_note = Time.get_ticks_msec() + 350
		_down = not _down
		if _down:
			_pitch = 48 + (randi() % 4) * 3
			voice.note_on(_pitch, 100)
		else:
			voice.note_off(_pitch)
	var el := Time.get_ticks_msec() - t0
	if stall_ms > 0 and int(el / 1000) != int((el - d*1000) / 1000) :
		OS.delay_msec(stall_ms)
	var st := voice.direct_stats()
	_pumps += 1
	_fill_sum += st["fill"]
	_fill_min = mini(_fill_min, st["fill"])
	_worst_ms = maxf(_worst_ms, d * 1000.0)
	if Time.get_ticks_msec() - last_print > 10000:
		last_print = Time.get_ticks_msec()
		print("t=%.0f " % (el / 1000.0), JSON.stringify(st))
	if el > secs * 1000:
		print("FINAL ", JSON.stringify(st), " mean fill ms %.1f, min fill ms %.1f, worst frame ms %.1f" % [
				_fill_sum / maxf(1.0, _pumps) / 48.0, _fill_min / 48.0, _worst_ms])
		voice.shutdown()
		get_tree().quit()
