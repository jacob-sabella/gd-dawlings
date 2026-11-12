extends Node3D

## The vocal booth's singer on its own: a Singer (the VOICE engine) singing a melody into its head (SingerHead),
## for looking at the head while it sings and for capturing it.
##
##   godot --path . res://tools/singer_preview.tscn -- OUT.png [FRAME] [MODE]
##
## MODE: sing (a phrase of "twinkle twinkle little star", the default), grab (the jaw and tongue held and moved by a
## stand-in hand while it holds a vowel), beast (the songbird). A real window: run it through tools/offscreen.sh.

var _frames := 0
var _out := ""
var _at := 150
var _mode := "sing"
var singer: Singer
var head: SingerHead
var _t0 := 0.0
var _hand := Node.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_at = int(args[1])
	if args.size() > 2:
		_mode = args[2]
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.025)
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	head = SingerHead.new()
	add_child(head)
	add_child(_hand)
	var cam := Camera3D.new()
	cam.fov = 40
	var close := _mode != "wide"
	cam.position = Vector3(0.08, 0.1, 0.42) if close else Vector3(0.06, 0.16, 0.85)
	add_child(cam)
	cam.look_at(Vector3(0.075, 0.07, 0.0) if close else Vector3(0.06, 0.13, 0.0))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	singer = Singer.new()
	singer.transport_override = func() -> Dictionary:
		return {"playing": true, "beats": (Time.get_ticks_msec() * 0.001 - _t0) * 100.0 / 60.0, "bpm": 100.0}
	add_child(singer)
	_t0 = Time.get_ticks_msec() * 0.001
	if not singer.start():
		push_error("singer: no engine")
		return
	singer.set_lyrics("twinkle twinkle little star how I wonder what you are")
	var row := SingerRow.fresh()
	if _mode == "beast":
		row["mode"] = SingerRow.Mode.BEAST
	elif _mode == "grab":
		row["mode"] = SingerRow.Mode.VOWEL
	singer.apply_row(row)
	if _mode == "sing":
		singer.sing_part([[1, 60, 1], [2, 60, 1], [3, 67, 1], [4, 67, 1], [5, 69, 1], [6, 69, 1], [7, 67, 2],
				[9, 65, 1], [10, 65, 1], [11, 64, 1], [12, 64, 1], [13, 62, 1], [14, 62, 1], [15, 60, 2]], 100.0)
	else:
		singer.play(60, true)
	head.moved.connect(func(n: String, cm: float) -> void: singer.engine.say("text v.artic %s =%.4f" % [n, cm]))


func _process(_delta: float) -> void:
	_frames += 1
	head.show_voice(singer.body(), singer.frame())
	if _mode == "grab" and _frames == 60:
		var g: SingerHead.Grip = head.grips["jaw"]
		g.grab_begin(_hand, g.global_position)
	if _mode == "grab" and _frames > 60 and _frames < 130:
		var g2: SingerHead.Grip = head.grips["jaw"]
		g2.grab_move(_hand, head.to_global(SingerHead.at(SingerHead.cm_of(head.to_local(g2.global_position)) + Vector2(0, -0.03))))
	if _mode == "beast" and _frames % 50 == 0:
		singer.cry((_frames / 50) % 3)
	if _frames == _at and _out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("singer_preview: saved ", _out, " tele=", not singer.body().is_empty(), " frame=", not singer.frame().is_empty(),
				" syl=", singer.sung(), " ", singer.syllables())
		singer.shutdown()
		get_tree().quit()
