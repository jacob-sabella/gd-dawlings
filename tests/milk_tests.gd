extends RefCounted

## The MilkDrop-style screen's tests (docs/visuals.md), called from tests/run_tests.gd's `_test_milk_*`:
## every preset works out sane numbers, loud or silent; the screen builds nothing with the visuals OFF and
## stops its buffers when the budget says no; presets crossfade and move on by themselves.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


## Silence, a typical bar and a big hit, as a screen would hand them to a preset.
func _samples(time: float) -> Array[Dictionary]:
	var typical := MilkPresets.quiet(time)
	for k in ["bass", "mid", "treb", "bass_att", "mid_att", "treb_att"]:
		typical[k] = 1.0
	typical["level"] = 0.5
	typical["hit"] = 0.3
	var loud := MilkPresets.quiet(time)
	for k in ["bass", "mid", "treb", "bass_att", "mid_att", "treb_att"]:
		loud[k] = 4.0
	loud["level"] = 1.0
	loud["hit"] = 1.0
	loud["beat_phase"] = 0.0
	return [MilkPresets.quiet(time), typical, loud]


func presets_all_evaluate() -> void:
	var n := MilkPresets.count()
	check("at least eight presets", n >= 8)
	var names := {}
	for i in n:
		names[MilkPresets.preset_name(i)] = true
	check("every preset has its own name", names.size() == n)
	var keys := MilkPresets.defaults().keys()
	for i in n:
		var label := MilkPresets.preset_name(i)
		var ok := true
		var sane := true
		var mem := {}
		var p := {}
		for frame in 40:
			for f in _samples(frame * 0.37):
				p = MilkPresets.evaluate(i, f, mem)
				for k in keys:
					if not p.has(k):
						ok = false
					elif p[k] is float and not is_finite(p[k]):
						ok = false
					elif p[k] is Color and not (is_finite(p[k].r) and is_finite(p[k].g) and is_finite(p[k].b)):
						ok = false
				sane = sane and float(p.zoom) > 0.85 and float(p.zoom) < 1.25 \
						and float(p.decay) >= 0.8 and float(p.decay) <= 1.0 \
						and absf(float(p.rot)) < 0.3 \
						and float(p.cx) >= 0.0 and float(p.cx) <= 1.0 and float(p.cy) >= 0.0 and float(p.cy) <= 1.0 \
						and float(p.wave_alpha) > 0.0 and float(p.wave_alpha) <= 1.0 \
						and float(p.echo) >= 0.0 and float(p.echo) <= 1.0 \
						and float(p.invert) >= 0.0 and float(p.invert) <= 0.6 \
						and float(p.bright) > 0.5 and float(p.bright) < 2.0 \
						and int(p.wave_mode) >= MilkPresets.WAVE_LINE and int(p.wave_mode) <= MilkPresets.WAVE_BLOOM \
						and int(p.shape_kind) >= MilkPresets.SHAPE_NONE and int(p.shape_kind) <= MilkPresets.SHAPE_RAYS
		check("%s: every parameter is there and finite" % label, ok)
		check("%s: the parameters stay in range, silent or loud" % label, sane)
		# Silence still moves: the warp, not just the ink, changes over time.
		var a := MilkPresets.evaluate(i, MilkPresets.quiet(1.0), {})
		var b := MilkPresets.evaluate(i, MilkPresets.quiet(9.0), {})
		var moved := false
		for k in keys:
			if a[k] is float and absf(float(a[k]) - float(b[k])) > 0.0001:
				moved = true
		check("%s: moves under silence" % label, moved)
	# The crossfade's mix: ends exact, numbers in between, the discrete ones switch half way.
	var x := MilkPresets.evaluate(0, MilkPresets.quiet(2.0), {})
	var y := MilkPresets.evaluate(2, MilkPresets.quiet(2.0), {})
	close_to("a blend at 0 is the first", float(MilkPresets.blend(x, y, 0.0).zoom), float(x.zoom))
	close_to("a blend at 1 is the second", float(MilkPresets.blend(x, y, 1.0).zoom), float(y.zoom))
	close_to("half way is half way", float(MilkPresets.blend(x, y, 0.5).decay), (float(x.decay) + float(y.decay)) * 0.5)
	check("a wave mode is not mixed: the first's until half way", MilkPresets.blend(x, y, 0.4).wave_mode == x.wave_mode)
	check("then the second's", MilkPresets.blend(x, y, 0.6).wave_mode == y.wave_mode)
	var red := MilkPresets.blend({"c": Color(1, 0, 0)}, {"c": Color(0, 1, 1)}, 0.5)
	check("colours mix round the wheel, not through grey", (red.c as Color).s > 0.9)


func screen_builds_and_idles_off() -> void:
	VisualBudget.reset()
	VisualBudget.set_tier(VisualBudget.Tier.OFF, false)
	var off := MilkScreen.new()
	t.add_child(off)
	var subs := 0
	for c in off.get_children():
		if c is SubViewport:
			subs += 1
	check("visuals OFF: no buffers at all", off.buffers().is_empty() and subs == 0)
	await t.get_tree().process_frame
	check("visuals OFF: it never runs", not off.is_running())
	off.queue_free()

	VisualBudget.set_tier(VisualBudget.Tier.HIGH, false)
	var screen := MilkScreen.new()
	screen.features = AudioFeatures.new()
	t.add_child(screen)
	check("HIGH: two buffers", screen.buffers().size() == 2)
	check("HIGH: 512 wide, the screen's shape", screen.buffers()[0].size == Vector2i(512, roundi(512 * 1.5 / 2.8)))
	screen.build()
	var count := 0
	for c in screen.get_children():
		if c is SubViewport:
			count += 1
	check("building again builds nothing more", count == 2)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	check("off screen (no eye here) it is not granted", not screen.is_running())
	check("and its buffers are still", screen.buffers().all(func(v: SubViewport) -> bool:
			return v.render_target_update_mode == SubViewport.UPDATE_DISABLED))

	screen.eye_distance = 2.0
	# Long enough for a 60 Hz step however fast the frames run here.
	await t.get_tree().create_timer(0.1).timeout
	check("in view and near it runs", screen.is_running())
	check("and has worked out a frame", not screen.params().is_empty())

	# LOW: one slot, and something nearer takes it.
	VisualBudget.set_tier(VisualBudget.Tier.LOW, false)
	var nearer := RefCounted.new()
	for i in 5:
		VisualBudget.ask(nearer, 0.5)
		await t.get_tree().process_frame
	check("LOW rebuilds smaller buffers", screen.buffers().size() == 2 and screen.buffers()[0].size.x == 256)
	check("a nearer visual takes LOW's one slot", not screen.is_running())
	check("and the screen's buffers stop", screen.buffers().all(func(v: SubViewport) -> bool:
			return v.render_target_update_mode == SubViewport.UPDATE_DISABLED))
	nearer = null
	await t.get_tree().create_timer(0.1).timeout
	check("once it is gone the screen gets the slot", screen.is_running())

	var gone := screen.features
	screen.queue_free()
	await t.get_tree().process_frame
	gone.free()
	VisualBudget.reset()
	VisualBudget.set_tier(VisualBudget.Tier.OFF, false)


func preset_crossfade_and_advance() -> void:
	VisualBudget.reset()
	VisualBudget.set_tier(VisualBudget.Tier.HIGH, false)
	var screen := MilkScreen.new()
	var a := AudioFeatures.new()
	screen.features = a
	t.add_child(screen)
	screen.use_preset(3)
	check("use_preset picks it", screen.preset_index == 3)
	check("and fades to it", screen.fading())
	var p0 := MilkPresets.evaluate(0, MilkPresets.quiet(0.5), {})
	var p3 := MilkPresets.evaluate(3, MilkPresets.quiet(0.5), {})
	screen.step_frame(0.5)
	var mid := float(screen.params().warp)
	check("a quarter in, the warp is between the two looks' warps",
			mid > minf(float(p0.warp), float(p3.warp)) - 0.01 and mid < maxf(float(p0.warp), float(p3.warp)) + 0.01)
	screen.step_frame(0.5)
	check("half way it is still fading", screen.fading())
	screen.step_frame(1.1)
	check("after the fade's two seconds it is done", not screen.fading())
	screen.use_preset(-1)
	check("use_preset wraps", screen.preset_index == MilkPresets.count() - 1)
	screen.next_preset()
	check("next_preset wraps to the first", screen.preset_index == 0)
	screen.step_frame(2.5)

	# By itself every half minute.
	for i in 27:
		screen.step_frame(1.0)
	check("before the half minute it holds", screen.preset_index == 0)
	screen.step_frame(1.0)
	check("after it, another preset", screen.preset_index != 0 and screen.fading())

	# Or on a big hit, but not before 20 s.
	var held := screen.preset_index
	a.hit = 1.0
	for i in 19:
		screen.step_frame(1.0)
	check("a big hit before 20 s does not move it", screen.preset_index == held)
	screen.step_frame(1.0)
	check("a big hit after 20 s does", screen.preset_index != held)
	a.hit = 0.0

	screen.auto_advance = false
	held = screen.preset_index
	for i in 40:
		screen.step_frame(1.0)
	check("auto_advance off holds it", screen.preset_index == held)

	# A SCOPE's wave is drawn while it is fresh; an empty one hands back to the mix.
	var w := PackedFloat32Array()
	w.resize(10)
	w.fill(0.5)
	screen.set_wave(w)
	close_to("the SCOPE's wave is drawn", screen.current_wave()[48], 0.5, 0.001)
	screen.set_wave(PackedFloat32Array())
	check("an empty one is not", absf(screen.current_wave()[48] - 0.5) > 0.01)

	screen.queue_free()
	await t.get_tree().process_frame
	a.free()
	VisualBudget.reset()
	VisualBudget.set_tier(VisualBudget.Tier.OFF, false)
