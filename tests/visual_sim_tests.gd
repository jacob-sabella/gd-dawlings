extends RefCounted

## The GPU simulations' tests (docs/visuals.md): the fluid tank, the physarum sheet and the particle-life
## pane. Headless there is no RenderingDevice, so what is pinned here is what runs without one: each
## builds its glass and frame and touches no RenderingDevice, its sizes follow the tier, it steps only
## when the budget grants it, and the arithmetic that turns the music into what each one does.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func close_to(label: String, a: float, b: float, epsilon := 0.0001) -> void:
	t.close_to(label, a, b, epsilon)


func _sims() -> Array[GpuSim]:
	return [FluidTank.new(), PhysarumSheet.new(), ParticleLifePane.new()]


func _back_to_off() -> void:
	VisualBudget.set_tier(VisualBudget.Tier.OFF, false)
	VisualBudget.reset()


## Headless (or the OFF tier): the object is built, the picture is a dim stand-in, and nothing steps.
func sims_build_still_without_compute() -> void:
	for tier in [VisualBudget.Tier.OFF, VisualBudget.Tier.HIGH]:
		VisualBudget.set_tier(tier, false)
		VisualBudget.reset()
		for sim in _sims():
			var what := "%s (%s)" % [(sim.get_script() as Script).get_global_name(), VisualBudget.tier_name()]
			t.add_child(sim)
			for i in 5:
				sim._process(1.0 / 60.0)
			check("%s: no compute without a RenderingDevice" % what, not sim.compute)
			check("%s: never steps" % what, not sim.stepping and sim.steps == 0)
			check("%s: no kernel made" % what, sim._kernel == null)
			check("%s: its frame is built" % what, sim.find_child("Frame", true, false) != null)
			check("%s: the picture has a mesh" % what, sim.screen.mesh != null and sim.screen.is_inside_tree())
			check("%s: the stand-in glows faintly in the mood colour" % what,
					sim.screen_material.emission_enabled and sim.screen_material.emission == sim.tint)
			sim.tint = Color(1.0, 0.2, 0.1)
			check("%s: a new mood colour reaches the stand-in" % what, sim.screen_material.emission == Color(1.0, 0.2, 0.1))
			sim.free()
	_back_to_off()


## Grid sizes and counts are VisualBudget.pick'ed: HIGH the big ones, LOW the small.
func sim_sizes_follow_the_tier() -> void:
	for tier in [VisualBudget.Tier.HIGH, VisualBudget.Tier.LOW]:
		VisualBudget.set_tier(tier, false)
		var high: bool = tier == VisualBudget.Tier.HIGH
		var tank := FluidTank.new()
		var sheet := PhysarumSheet.new()
		var pane := ParticleLifePane.new()
		for sim: GpuSim in [tank, sheet, pane]:
			t.add_child(sim)
		check("tank grid %s" % VisualBudget.tier_name(), tank.sim_size.x == (256 if high else 128))
		check("tank grid keeps its cells square", absf(float(tank.sim_size.x) / tank.sim_size.y
				- (tank.size.x - FluidTank.FRAME * 2.0) / (tank.size.y - FluidTank.FRAME * 2.0)) < 0.05)
		check("the dye is twice the grid", tank.dye_size == tank.sim_size * 2)
		check("pressure iterations even", tank.iterations % 2 == 0 and tank.iterations >= 14)
		check("sheet agents %s" % VisualBudget.tier_name(), sheet.agent_count == (131072 if high else 32768))
		check("sheet trail %s" % VisualBudget.tier_name(), sheet.trail_size.x == (512 if high else 256))
		check("sheet trail keeps the sheet's shape", absf(float(sheet.trail_size.x) / sheet.trail_size.y
				- sheet.size.x / sheet.size.y) < 0.02)
		check("pane particles %s" % VisualBudget.tier_name(), pane.particle_count == (4096 if high else 1536))
		check("pane particles a whole number of workgroups", pane.particle_count % 256 == 0)
		for sim: GpuSim in [tank, sheet, pane]:
			sim.free()
	_back_to_off()


## The budget's word is final: not granted, or off screen, nothing; granted, no oftener than rate_hz.
func sims_step_only_when_granted() -> void:
	check("not granted: no step", not GpuSim.should_step(false, 1.0, 1.0))
	check("off screen: no step", not GpuSim.should_step(true, INF, 1.0))
	check("close and granted: every 60 Hz frame", GpuSim.should_step(true, 2.0, 1.0 / 60.0))
	check("close: a frame a hair early still steps", GpuSim.should_step(true, 2.0, 1.0 / 60.0 - 0.001))
	check("close: not twice in a 144 Hz frame", not GpuSim.should_step(true, 2.0, 1.0 / 144.0))
	check("across the room: 30 Hz", GpuSim.should_step(true, 6.0, 1.0 / 30.0)
			and not GpuSim.should_step(true, 6.0, 1.0 / 60.0))
	check("far: 15 Hz", GpuSim.should_step(true, 12.0, 1.0 / 15.0)
			and not GpuSim.should_step(true, 12.0, 1.0 / 30.0))
	# A sim the budget turns down never steps, whatever the tier says.
	VisualBudget.set_tier(VisualBudget.Tier.HIGH, false)
	VisualBudget.reset()
	var tank := FluidTank.new()
	t.add_child(tank)
	for i in 3:
		tank._process(1.0 / 60.0)
	check("headless at HIGH, a tank still dispatches nothing", tank.steps == 0 and not tank.stepping)
	tank.free()
	_back_to_off()


## A new matrix arrives eased in; a hit's shake fades out of it.
func particle_life_matrix_blends() -> void:
	var a := PackedFloat32Array([0.0, 1.0, -1.0, 0.5])
	var b := PackedFloat32Array([1.0, -1.0, 1.0, 0.5])
	var at0 := ParticleLifePane.blend_matrix(a, b, 0.0)
	var at1 := ParticleLifePane.blend_matrix(a, b, 1.0)
	var mid := ParticleLifePane.blend_matrix(a, b, 0.5)
	var quarter := ParticleLifePane.blend_matrix(a, b, 0.25)
	check("blend 0 is the old matrix", at0 == a)
	check("blend 1 is the new one", at1 == b)
	close_to("half way is the middle", mid[0], 0.5)
	close_to("eased: a quarter of the time is less than a quarter of the way", quarter[0], 0.15625)
	check("past 1 stays at the new one", ParticleLifePane.blend_matrix(a, b, 3.0) == b)
	close_to("an entry both share does not move", mid[3], 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var m := ParticleLifePane.random_matrix(rng)
	check("a matrix is 6 x 6", m.size() == 36)
	var inside := true
	var diagonal := true
	for i in 6:
		for j in 6:
			inside = inside and absf(m[i * 6 + j]) <= 1.0
		diagonal = diagonal and m[i * 7] > 0.0
	check("every entry -1..1", inside)
	check("each species holds itself together", diagonal)
	var pane := ParticleLifePane.new()
	pane._choose_sizes()
	var before := pane.matrix.duplicate()
	pane.advance_matrix(ParticleLifePane.MATRIX_SECONDS - 0.01, 0.0)
	check("the matrix holds still between new ones", pane.matrix == before)
	pane.advance_matrix(0.02, 0.0)
	check("a new one is on its way", pane._to != before)
	var jump := 0.0
	for i in before.size():
		jump = maxf(jump, absf(pane.matrix[i] - before[i]))
	check("a new matrix starts where the old one was", jump < 0.02)
	pane.advance_matrix(ParticleLifePane.BLEND_SECONDS, 0.0)
	check("and is all there after the blend", pane.matrix == pane._to)
	var settled := pane.matrix.duplicate()
	pane.advance_matrix(0.01, 1.0)
	var shaken := 0.0
	for i in settled.size():
		shaken = maxf(shaken, absf(pane.matrix[i] - settled[i]))
	check("a hit shakes the matrix", shaken > 0.01)
	for i in 30:
		pane.advance_matrix(0.5, 0.0)
	var left := 0.0
	for i in settled.size():
		left = maxf(left, absf(pane.matrix[i] - settled[i]))
	check("and the shake fades", left < 0.01)
	pane.free()


## Each species hears its own part of the spectrum: the first the bass, the last the treble.
func particle_life_species_hear_their_band() -> void:
	var bars := PackedFloat32Array()
	bars.resize(32)
	var quiet := ParticleLifePane.species_drive(bars)
	check("six species", quiet.size() == 6)
	close_to("silence: a gentle drive", quiet[0], 0.6)
	close_to("silence: the treble species too", quiet[5], 0.6)
	for i in 5:
		bars[i] = 1.0
	var bass := ParticleLifePane.species_drive(bars)
	close_to("the bass drives the first species fully", bass[0], 2.0)
	close_to("not the last", bass[5], 0.6)
	bars.fill(0.0)
	for i in range(26, 32):
		bars[i] = 1.0
	var treble := ParticleLifePane.species_drive(bars)
	close_to("the treble drives the last species", treble[5], 2.0)
	close_to("not the first", treble[0], 0.6)
	bars.fill(2.0)
	close_to("a bar past 1 counts as 1", ParticleLifePane.species_drive(bars)[2], 2.0)


## A hit's ink: harder with more bass, its colour round the mood's; the veins' colour turns with the bass.
func fluid_splats_follow_the_music() -> void:
	check("no hit, no push", FluidTank.splat_force(2.0, 0.0, 100.0) == 0.0)
	check("more bass, a harder push", FluidTank.splat_force(3.0, 1.0, 100.0) > FluidTank.splat_force(0.5, 1.0, 100.0))
	check("a harder hit, a harder push", FluidTank.splat_force(1.0, 1.0, 100.0) > FluidTank.splat_force(1.0, 0.4, 100.0))
	close_to("the push scales with the tank", FluidTank.splat_force(1.0, 1.0, 200.0), FluidTank.splat_force(1.0, 1.0, 100.0) * 2.0, 0.01)
	check("bass past 3 adds nothing", FluidTank.splat_force(9.0, 1.0, 100.0) == FluidTank.splat_force(3.0, 1.0, 100.0))
	var mood := Color(0.2, 0.4, 1.0)
	var soft := FluidTank.splat_colour(mood, 0.0, 0.2)
	var hard := FluidTank.splat_colour(mood, 0.0, 1.0)
	check("a harder hit, brighter ink", hard.get_luminance() > soft.get_luminance())
	var near := true
	for k in 12:
		var c := FluidTank.splat_colour(mood, k * 0.137, 1.0)
		var d := absf(c.h - mood.h)
		near = near and minf(d, 1.0 - d) < 0.2 and c.s > 0.5
	check("the ink's hue stays round the mood's, and saturated", near)
	check("the hue steps turn the colour", not FluidTank.splat_colour(mood, 0.0, 1.0).is_equal_approx(FluidTank.splat_colour(mood, 0.25, 1.0)))
	var calm := PhysarumSheet.vein_colours(mood, 1.0, 0.0)
	var heavy := PhysarumSheet.vein_colours(mood, 3.0, 0.0)
	check("the veins have a faint and a bright colour", calm.size() == 2)
	check("the bass turns the veins' hue", absf(calm[0].h - heavy[0].h) > 0.05)
	check("a flash brightens the veins", PhysarumSheet.vein_colours(mood, 1.0, 1.0)[0].a > calm[0].a)
