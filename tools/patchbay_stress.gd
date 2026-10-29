## Builds the routing bay at several sizes with random sends and prints what it costs: the build,
## a scroll across the whole matrix, and how many nodes it holds (the pool, not the session).
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
			if DAW.create_send(a, b):
				made += 1
		var bay := PatchbaySurface.new()
		add_child(bay)
		var t0 := Time.get_ticks_usec()
		bay._process(0.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var count := 0
		var stack: Array = [bay]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			count += 1
			stack.append_array(node.get_children())
		# A scroll a row and a column at a time from corner to corner, as a drag across it would.
		var m := bay.matrix
		var t1 := Time.get_ticks_usec()
		var steps := maxi(m.row_count() - m.shown_rows(), m.col_count() - m.shown_cols())
		for k in steps + 1:
			m.scroll_to(k, k)
		var scroll_ms := (Time.get_ticks_usec() - t1) / 1000.0 / maxf(steps + 1, 1)
		print("STRESS tracks=%d sends=%d (made %d) seated=%d window=%dx%d pins=%d nodes=%d build_ms=%.1f scroll_ms_per_step=%.2f" % [
				n, sends, made, bay.seated_count(), m.shown_rows(), m.shown_cols(), m.pins().size(), count, ms, scroll_ms])
		bay.free()
	get_tree().quit()
