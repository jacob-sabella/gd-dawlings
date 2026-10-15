## Builds the routing bay at several sizes with random sends and prints what it costs.
## `godot --headless --path . res://tools/patchbay_stress.tscn`
extends Node

func _ready() -> void:
	for spec in [[16, 32], [64, 128], [256, 512]]:
		var n: int = spec[0]
		var sends: int = spec[1]
		var offline := OfflineBackend.new()
		offline.track_count = n
		DAW.use(offline)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var made := 0
		var guard := 0
		var idx := DAW.state.track_indices()
		while made < sends and guard < sends * 10:
			guard += 1
			var a: int = idx[rng.randi() % idx.size()]
			var b: int = idx[rng.randi() % idx.size()]
			if a == b:
				continue
			DAW.create_send(a, b)
			made += 1
		var bay := PatchbaySurface.new()
		add_child(bay)
		var t0 := Time.get_ticks_usec()
		bay._process(0.0)
		bay._draw_cables()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var count := 0
		var stack: Array = [bay]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			count += 1
			stack.append_array(node.get_children())
		print("STRESS tracks=%d sends=%d routes=%d plugs=%d cables=%d nodes=%d slots=%d build_ms=%.1f pages=%d" % [n, sends, bay._routes.size(), bay._plugs.size(), bay._cables.size(), count, bay.slots(), ms, bay.page_count()])
		var shared := 0
		for key in bay._routes:
			var r: Dictionary = bay._routes[key]
			if r["out_slot"] == PatchbaySurface.MAX_SLOTS - 1 or r["in_slot"] == PatchbaySurface.MAX_SLOTS - 1:
				shared += 1
		print("STRESS   routes on the last slot (shared bore when a row is fuller): %d" % shared)
		bay.free()
	get_tree().quit()
