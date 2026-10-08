extends Node3D

## A ghost and three loose gloves on a plain floor, acting out a grab, for looking at the hands.
##
##   godot --path . --fixed-fps 60 res://tools/glove_preview.tscn -- OUT_PREFIX FIRST LAST EVERY
##
## Writes OUT_PREFIX_NNNN.png for frames FIRST..LAST, every EVERYth, then quits. The ghost
## points at the desk (frame 30), takes hold and drags (80), lets go (150), points at something
## out of reach (190) and goes idle (260). A real window: run it through tools/offscreen.sh with
## vsync off (override.cfg), as the shot scripts do. Stitch the frames with ffmpeg for a GIF.

var _ghost: Presence.Avatar
var _target: ControlAffordance
var _frames := 0
var _gloves: Array[Glove] = []


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.55)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var desk := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.06, 0.4)
	desk.mesh = box
	desk.position = Vector3(0.35, 0.97, -0.6)
	add_child(desk)
	_ghost = Presence.Avatar.new()
	add_child(_ghost)
	_ghost.dress("Ada", Color(1.0, 0.55, 0.2), 0, true)
	_ghost.snap(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 1.62, 0)))
	_target = ControlAffordance.new()
	add_child(_target)
	_target.position = Vector3(0.35, 1.0, -0.6)
	for i in 3:
		var g := Glove.new(1.0)
		g.set_colour(Color(0.3, 0.75, 1.0))
		g.size = 1.6
		g.pose = [Glove.Pose.OPEN, Glove.Pose.POINT, Glove.Pose.GRIP][i]
		g.target = Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.5), Vector3(-1.3 + i * 0.32, 1.3, -0.3))
		add_child(g)
		_gloves.append(g)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(-1.1, 1.6, -2.1), Vector3(-0.2, 1.2, -0.4))
	cam.fov = 50
	cam.current = true

## A little play: point at the desk, take hold, let go, point at something far off, stand idle.
func _process(_d: float) -> void:
	_frames += 1
	var far := Vector3(-1.6, 1.9, -1.8)
	var spot := _target.global_position + Vector3(0, 0.03, 0)
	if _frames < 30 or _frames >= 260:
		_ghost.point_at(null, Vector3.ZERO, false)
	elif _frames < 80:
		_ghost.point_at(_target, spot, false)
	elif _frames < 150:
		_ghost.point_at(_target, spot + Vector3(0, 0, 0.12 * sin((_frames - 80) * 0.06)), true)
	elif _frames < 190:
		_ghost.point_at(_target, spot, false)
	else:
		_ghost.point_at(_target, far, false)
	# out_prefix [first last every]: frames first..last, every Nth, as out_prefix_NNNN.png.
	var args := OS.get_cmdline_user_args()
	var first := int(args[1]) if args.size() > 1 else 200
	var last := int(args[2]) if args.size() > 2 else first
	var every := int(args[3]) if args.size() > 3 else 1
	if _frames >= first and _frames <= last and (_frames - first) % every == 0:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%04d.png" % [args[0], _frames])
	if _frames > last:
		get_tree().quit()
