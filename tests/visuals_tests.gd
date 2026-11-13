extends RefCounted

## The audio-reactive visuals' groundwork (docs/visuals.md), called from tests/run_tests.gd's `_test_visuals_*`:
## cava's bars, the music's features, the scope's beam and the budget that decides what runs.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


func _levels(values: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in values:
		out.append(float(v))
	return out


## CavaBars: a rise is taken at once, a fall accelerates under gravity, neighbours are lifted, the gain
## follows the sound, and the motion is the same at 60 and 144 Hz.
func cava_bars_rise_fast_and_fall_under_gravity() -> void:
	var c := CavaBars.new(3)
	c.auto_sens = false
	c.smoothing = 0.0
	c.step(_levels([1.0, 0.0, 0.0]), 1.0 / 60.0)
	close_to("a rise is taken at once (no smoothing)", c.bars[0], 1.0, 0.001)
	var drops: Array[float] = []
	var last := 1.0
	for i in 6:
		c.step(_levels([0.0, 0.0, 0.0]), 1.0 / 60.0)
		drops.append(last - c.bars[0])
		last = c.bars[0]
	check("a dropped bar falls rather than snapping to the silence", c.bars[0] > 0.5)
	check("and falls faster each frame, as a thrown thing does", drops[5] > drops[1] and drops[1] > 0.0)
	for i in 120:
		c.step(_levels([0.0, 0.0, 0.0]), 1.0 / 60.0)
	close_to("and lands on the silence in the end", c.bars[0], 0.0, 0.001)
	# The same second of falling at two frame rates lands in about the same place.
	var at60 := CavaBars.new(1)
	var at144 := CavaBars.new(1)
	for b in [at60, at144]:
		(b as CavaBars).auto_sens = false
		(b as CavaBars).step(_levels([1.0]), 1.0 / 60.0)
	for i in 15:
		at60.step(_levels([0.0]), 1.0 / 60.0)
	for i in 36:
		at144.step(_levels([0.0]), 1.0 / 144.0)
	close_to("a quarter second of falling is the same at 60 and 144 Hz", at60.bars[0], at144.bars[0], 0.08)
	var m := CavaBars.new(5)
	m.auto_sens = false
	m.smoothing = 0.0
	m.monstercat = 1.5
	m.step(_levels([0, 0, 1, 0, 0]), 1.0 / 60.0)
	check("monstercat lifts a loud bar's neighbours, less with each step away",
			m.bars[1] > m.bars[0] and m.bars[0] > 0.0 and is_equal_approx(m.bars[1], m.bars[3]) and m.bars[2] > m.bars[1])
	var a := CavaBars.new(2)
	a.step(_levels([0.05, 0.05]), 1.0 / 60.0)
	var quiet := a.sensitivity
	for i in 60:
		a.step(_levels([0.05, 0.05]), 1.0 / 60.0)
	check("a quiet sound has its gain raised until it fills the height", a.sensitivity > quiet * 4.0 and a.bars[0] > 0.6)
	for i in 300:
		a.step(_levels([2.0, 2.0]), 1.0 / 60.0)
	check("and an overshooting one has it lowered", a.sensitivity < 1.0)


## AudioFeatures from what it is fed: silence is still, a kick in the low bands is a hit with the bass up,
## the treble rises with the high bands, and the loudness is auto-gained.
func features_hear_a_kick() -> void:
	var f := AudioFeatures.new()
	var silent := PackedFloat32Array()
	silent.resize(AudioFeatures.BARS)
	for i in 30:
		f.feed(silent)
		f.step(1.0 / 60.0)
	check("silence: no level, no bass, no hit", f.level < 0.01 and f.bass == 0.0 and f.hit == 0.0)
	var hits := [0]
	f.onset.connect(func(_s: float) -> void: hits[0] += 1)
	var bed := PackedFloat32Array()
	bed.resize(AudioFeatures.BARS)
	bed.fill(0.01)
	var kick := bed.duplicate()
	for i in 6:
		kick[i] = 0.4
	var bass_on_kick := 0.0
	for beat in 8:
		for frame in 30:
			f.feed(kick if frame < 3 else bed)
			f.step(1.0 / 60.0)
			if frame == 0:
				bass_on_kick = f.bass
	check("eight kicks are heard as hits (%d)" % hits[0], hits[0] >= 6 and hits[0] <= 8)
	check("a kick's bass stands well over its average (%.2f)" % bass_on_kick, bass_on_kick > 1.5)
	check("the bars are 32, each 0..1", f.bars.size() == AudioFeatures.BARS and Array(f.bars).all(func(v: float) -> bool: return v >= 0.0 and v <= 1.0))
	var hiss := bed.duplicate()
	for i in range(24, AudioFeatures.BARS):
		hiss[i] = 0.2
	var treb_before := f.treb
	for i in 3:
		f.feed(hiss)
		f.step(1.0 / 60.0)
	check("a hiss lifts the treble", f.treb > treb_before and f.treb > 1.2)
	f.feed(kick)
	f.step(1.0 / 60.0)
	check("the loudness is auto-gained to its recent peak", f.level > 0.3 and f.level <= 1.0)
	var samples := PackedFloat32Array()
	for i in 1024:
		samples.append(sin(float(i) * 0.05))
	f.feed(kick, samples)
	f.step(1.0 / 60.0)
	check("the wave is the newest samples, 128 of them", f.wave.size() == AudioFeatures.WAVE_POINTS and absf(f.wave[127] - samples[1020]) < 0.001)
	var g := AudioFeatures.new()
	g.lend(0.8, 1.0)
	g.feed(silent)
	g.step(1.0 / 60.0)
	check("on a silent bus the rack's lent level and hit move the room", g.level > 0.1 and g.hit > 0.9)
	f.free()
	g.free()


## The scope's beam: a quad round each segment carrying where a point is along and across it and the
## segment's length, and the shader lights a short segment brighter than a long one.
func scope_beam_quads_carry_the_segment() -> void:
	var screen := ScopeScreen.new()
	t.add_child(screen)
	var wave := PackedFloat32Array()
	wave.resize(ScopeScreen.POINTS)
	for i in wave.size():
		wave[i] = sin(float(i) * 0.3)
	screen.set_wave(wave)
	var im := screen._trace[0].mesh as ImmediateMesh
	var arrays := im.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check("the beam is two triangles a segment", verts.size() == (ScopeScreen.POINTS - 1) * 6)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var hw := screen.size.x * 0.5
	var hh := screen.size.y * 0.5 * 0.92
	var first := Vector2(-hw, 0.0).distance_to(Vector2(-hw + screen.size.x / float(ScopeScreen.POINTS - 1), sin(0.3) * hh))
	close_to("each quad knows its segment's length", uv2[0].x, first, 0.0001)
	check("the beam is drawn by the beam shader", (screen._trace[0].material_override as ShaderMaterial).shader == ScopeScreen.BEAM)
	check("the smears are fainter than the live trace", float((screen._trace[1].material_override as ShaderMaterial).get_shader_parameter(&"fade")) < 1.0)
	var flat := PackedFloat32Array()
	screen.set_wave(flat)
	check("an empty wave is a flat line, still drawn", (screen._trace[0].mesh as ImmediateMesh).get_surface_count() == 1)
	screen.queue_free()


## The budget: OFF grants nothing, LOW one at a time (the nearest on screen), HIGH three; off screen is never
## granted; a far thing steps less often; the tier is chosen by the run's word.
func budget_grants_the_nearest_on_screen() -> void:
	var was := VisualBudget.tier()
	var things: Array[RefCounted] = [RefCounted.new(), RefCounted.new(), RefCounted.new(), RefCounted.new()]
	var distances := [6.0, 2.0, INF, 12.0]
	VisualBudget.set_tier(VisualBudget.Tier.OFF, false)
	VisualBudget.reset()
	check("OFF grants nothing", not VisualBudget.ask(things[1], 1.0) and VisualBudget.slots() == 0)
	for tier in [VisualBudget.Tier.LOW, VisualBudget.Tier.HIGH]:
		VisualBudget.set_tier(tier, false)
		VisualBudget.reset()
		var granted := []
		# Three frames of asking: the ranking is made from the frame before.
		for frame in 3:
			VisualBudget._ranked_frame = -1
			granted.clear()
			for k in things.size():
				if VisualBudget.ask(things[k], distances[k]):
					granted.append(k)
		if tier == VisualBudget.Tier.LOW:
			check("LOW runs only the nearest on screen (%s)" % str(granted), granted == [1])
		else:
			check("HIGH runs the three nearest on screen, never the one off screen (%s)" % str(granted), granted.size() == 3
					and granted.has(1) and granted.has(0) and granted.has(3) and not granted.has(2))
	check("a far thing steps less often than a near one", VisualBudget.rate_hz(12.0) < VisualBudget.rate_hz(5.0)
			and VisualBudget.rate_hz(5.0) < VisualBudget.rate_hz(1.0))
	check("the run's word names a tier", VisualBudget._named("low") == VisualBudget.Tier.LOW and VisualBudget._named("OFF") == VisualBudget.Tier.OFF
			and VisualBudget._named("high") == VisualBudget.Tier.HIGH)
	check("pick follows the tier", VisualBudget.pick(512, 256) == 512)
	VisualBudget.set_tier(VisualBudget.Tier.LOW, false)
	check("and LOW picks the small one", VisualBudget.pick(512, 256) == 256)
	VisualBudget.set_tier(was, false)
	VisualBudget.reset()
	check("headless the visuals are off by default", VisualBudget._decide() == VisualBudget.Tier.OFF
			or OS.get_environment("DAWLINGS_VISUALS") != "")


## The visualizer TV: a click on its glass moves on to the next picture, its FIND key asks for the finder, and
## the finder finds pictures by name or word, puts the one chosen on the TV and can hold it there.
func milk_tv_click_and_find() -> void:
	# Only the built-ins: not whatever this machine has in user://milk.
	var root_was := MilkLibrary.root
	MilkLibrary.root = "user://milk_tests_empty"
	MilkLibrary.reset()
	var was := VisualBudget.tier()
	VisualBudget.set_tier(VisualBudget.Tier.HIGH, false)
	VisualBudget.reset()
	var tv := MilkScreen.new()
	t.add_child(tv)
	check("the TV has a clickable glass and a FIND key", tv.glass_key != null and tv.find_key != null)
	var before := tv.preset_index
	tv.glass_key._on_grab_begin(Vector3.ZERO)
	check("a click on the glass moves on to the next picture", tv.preset_index == posmod(before + 1, MilkLibrary.count()))
	var asked := [false]
	tv.find_asked.connect(func() -> void: asked[0] = true)
	tv.find_key._on_grab_begin(Vector3.ZERO)
	check("FIND asks for the finder", asked[0])
	check("the finder finds by name", MilkFinderScreen.search("vortex").size() == 1)
	check("and by a word of what it does", MilkFinderScreen.search("calm").size() >= 1)
	check("and everything for nothing typed", MilkFinderScreen.search("").size() == MilkLibrary.count())
	check("every picture says what it does", range(MilkPresets.count()).all(
			func(i: int) -> bool: return MilkFinderScreen.ABOUT.has(MilkPresets.preset_name(i))))
	var finder := MilkFinderScreen.new()
	t.add_child(finder)
	finder.open_finder(tv)
	check("the finder opens on the TV's picture", finder.is_open() and finder.chosen() == tv.preset_index)
	var want := MilkFinderScreen.search("vortex")[0]
	finder._list.select(finder._found.find(want))
	finder._choose()
	check("choosing one puts it on the TV", tv.preset_index == want)
	finder._hold.button_pressed = true
	check("HOLD stops it changing by itself", not tv.auto_advance)
	finder.close_finder()
	check("and it closes", not finder.is_open())
	finder.queue_free()
	tv.queue_free()
	VisualBudget.set_tier(was, false)
	VisualBudget.reset()
	MilkLibrary.root = root_was
	MilkLibrary.reset()


## The picture's name is lettered on a change and then fades away whole: its letters and its outline both.
func milk_name_fades_away() -> void:
	var was := VisualBudget.tier()
	VisualBudget.set_tier(VisualBudget.Tier.HIGH, false)
	VisualBudget.reset()
	var tv := MilkScreen.new()
	t.add_child(tv)
	var name := tv.get_node("PictureName") as Label3D
	check("the name is hidden before any change", name.modulate.a == 0.0 and name.outline_modulate.a == 0.0)
	tv.next_preset()
	tv._process(0.1)
	check("a change letters it, outline and all", name.modulate.a > 0.9 and name.outline_modulate.a > 0.9)
	for i in 60:
		tv._process(0.1)
	check("and in a few seconds it has faded away whole", name.modulate.a == 0.0 and name.outline_modulate.a == 0.0)
	tv.queue_free()
	VisualBudget.set_tier(was, false)
	VisualBudget.reset()
