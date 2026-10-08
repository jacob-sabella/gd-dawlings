extends Node3D

## Six ghosts in a row, one in each hat, with the bodies, eyes and gloves shared out among them:
## for looking at what the mirror's wardrobe can put on someone.
##
##   godot --path . res://tools/look_preview.tscn -- OUT.png [FRAME]
##
## A real window: run it through tools/offscreen.sh with vsync off (override.cfg), as the shot
## scripts do.

var _frames := 0


func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, -0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 8)
	ground.mesh = plane
	add_child(ground)
	for i in GhostLook.HATS.size():
		var ghost := Presence.Avatar.new()
		add_child(ghost)
		var look := {"hat": i, "body": (i * 3) % GhostLook.BODIES.size(),
				"eyes": i % GhostLook.EYES.size(), "gloves": i % GhostLook.GLOVES.size()}
		ghost.dress(GhostLook.HATS[i], Session.PALETTE[i % Session.PALETTE.size()], 0, false, look)
		ghost.snap(Transform3D(Basis(Vector3.UP, PI), Vector3((i - 2.5) * 0.78, 1.62, 0)))
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.75, 3.6), Vector3(0, 1.45, 0))
	cam.fov = 48
	cam.current = true


func _process(_d: float) -> void:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == (int(args[1]) if args.size() > 1 else 90):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
		get_tree().quit()
