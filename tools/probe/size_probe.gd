extends Node
## Print how big each piece of gear comes out for a session of N tracks. For deciding what the
## room has to make space for.
##   godot --headless --path . tools/probe/size_probe.tscn -- --tracks 40

func _ready() -> void:
	var n := 13
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--tracks" and i + 1 < argv.size():
			n = int(argv[i + 1])
	var offline := OfflineBackend.new()
	offline.track_count = n
	DAW.use(offline)
	Session.layout.save_path = "user://scratch_layout.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for i in 3:
		for surface in studio.focus.surfaces:
			surface._process(0.0)
		await get_tree().process_frame
	print("tracks=%d fx=%d" % [n, DAW.state.track_indices().reduce(func(a, i): return a + DAW.state.track(i, false).plugins().size(), 0)])
	for surface in studio.focus.surfaces:
		var box: AABB = surface.global_transform * surface.content_aabb()
		print("  %-10s size=%s at=%s" % [surface.surface_id, box.size, box.get_center()])
	print("  desk footprint ", studio._desk_footprint())
	print("  room width %.2f" % studio.room_width)
	for piece in studio.floor_plan.pieces:
		print("  %-14s at (%.2f, %.2f) clear=%s" % [piece.piece_id, piece.position.x, piece.position.z,
				studio.floor_plan.is_clear(piece, Vector2(piece.position.x, piece.position.z), piece.rotation.y)])
	get_tree().quit()
