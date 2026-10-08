extends Node

## Capture harness: run the real studio in a real window and write frames to PNG.
##
## An autoload so it observes whatever is running rather than being wired into a scene. The
## alternative to this -- reading the scene files and asserting the console probably looks like a
## console -- is not verification of anything. A 3D project in particular cannot be reviewed any
## other way: materials, glow and shadow are the difference between gear and grey boxes, and none
## of the three exist until something renders.
##
##   godot --path . -- --shot /tmp/console.png --shot-frame 30 --quit-after 34
##   godot --path . -- --shot /tmp/wide.png --cam 0.5,-0.3,2.6,0,0.95,0
##
## --cam is yaw,pitch,distance,target_x,target_y,target_z. Framing is a command-line argument
## because a capture nobody can reproduce is not evidence: the numbers that produced a shot
## belong next to the shot.

var _shot_path := ""
var _shot_frame := 24
var _quit_after := -1
var _frames := 0
var _cam: Array = []
var _shot_res := Vector2i.ZERO
var _hover := Vector2(-1, -1)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--shot":
				if i + 1 < args.size(): _shot_path = args[i + 1]
			"--shot-frame":
				if i + 1 < args.size(): _shot_frame = int(args[i + 1])
			"--quit-after":
				if i + 1 < args.size(): _quit_after = int(args[i + 1])
			"--shot-res":
				if i + 1 < args.size(): _shot_res = _parse_res(args[i + 1])
			# Where the cursor is, in viewport pixels. The capture window is on a workspace nobody
			# is looking at, so the real mouse is not over it -- and a hover card is only evidence
			# if the same interactor that a person drives produced it. This parks THAT interactor's
			# pointer rather than drawing a card by hand.
			"--hover":
				if i + 1 < args.size():
					var xy := args[i + 1].split(",")
					if xy.size() == 2: _hover = Vector2(float(xy[0]), float(xy[1]))
			"--cam":
				if i + 1 < args.size(): _cam = Array(args[i + 1].split(",")).map(func(s): return float(s))
	if _shot_path == "" and _quit_after < 0:
		set_process(false)


func _parse_res(spec: String) -> Vector2i:
	var parts := spec.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _process(_delta: float) -> void:
	_frames += 1

	# Framing is applied a few frames in, not at frame 0. The studio builds its surfaces on the
	# first processed frame, so a camera positioned before that is aimed at an empty room.
	if _frames == 4 and _cam.size() == 6:
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.has_method("frame"):
			studio.frame(Vector3(_cam[3], _cam[4], _cam[5]), _cam[2], _cam[0], _cam[1])

	if _hover.x >= 0.0:
		for hand in get_tree().root.find_children("*", "MouseInteractor", true, false):
			(hand as MouseInteractor).pointer_override = _hover

	if _shot_path != "" and _frames == _shot_frame:
		_capture()

	if _quit_after > 0 and _frames >= _quit_after:
		get_tree().quit()


func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	if err != OK:
		push_error("SHOT_FAILED %s: %s" % [_shot_path, error_string(err)])
		return
	# Echoed with the size the engine ACTUALLY rendered. A capture whose dimensions are not
	# stated can be compared against the wrong thing without anyone noticing -- a window manager
	# that packs the window produces a smaller PNG that still looks like a successful shot.
	print("SHOT_SAVED %s %dx%d" % [_shot_path, image.get_width(), image.get_height()])
