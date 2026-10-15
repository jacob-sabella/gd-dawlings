extends Node

## What the studio actually costs to draw, measured rather than guessed.
##
##   godot --path . -- --budget --tracks 48
##   tools/budget.sh                      # the whole sweep, as a table
##
## An autoload for the same reason the capture harness is one: it observes whatever happens to
## be running, so measuring needs no cooperation from the scene and cannot accidentally measure
## a different scene from the one that ships. Inert unless --budget is passed.
##
## WHY THIS EXISTS BEFORE ANY OPTIMISATION
##
## The target is a standalone passthrough headset, which has to draw this whole room TWICE --
## once per eye -- at 72Hz or better, on a mobile GPU, with no tether. That is a hard budget and
## this project has never once measured itself against it. "Optimise for mobile" without a
## number is a guess about which of several plausible costs is the real one, and the plausible
## costs here point in different directions: ~100 knobs at 1088 triangles each is a vertex
## problem, while ~100 strips each built from a dozen separate MeshInstance3Ds is a DRAW CALL
## problem, and they have opposite fixes. One of those is nearly always dominant. Measure first.
##
## Reported per track count, because the only interesting question is the SLOPE: what a
## thirteen-track demo costs says nothing about a ninety-track session, and the console is as
## wide as the track count by design.

## TWO NUMBERS, AND THEY ARE NOT THE SAME NUMBER
##
## `draws` is RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME: actual draw calls issued. The renderer
## batches geometry that shares a material, so this falls when things share a finish and rises
## with every DISTINCT material in frame.
##
## `objects` is RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME: per-instance submissions, one per visible
## thing per pass, batched or not. Only instancing removes these.
##
## They are easy to conflate and they move independently. Measured directly, 400 boxes:
##
##   loose, one shared material     draws 7       objects 1100
##   loose, a material each         draws 1100    objects 1100
##   one MultiMesh                  draws 3       objects 3
##
## So a MultiMesh over geometry that already shared a material buys nothing on `draws` and still
## cuts `objects` to almost nothing -- which is exactly what happened to the patchbay's jacks.
## That is not a null result: `objects` is CPU-side submission and culling work, and on a
## standalone headset the CPU is as likely to be the wall as the GPU. Read both.

## Frames to let the scene settle before sampling. The surfaces rebuild on the first frames
## they are told about a project, and measuring during a rebuild measures the rebuild.
const WARMUP := 45
## Frames to average over. Long enough to ride out the meter animation, short enough that a
## sweep of six sizes is not a coffee break.
var SAMPLE := 40

var _active := false
var _frames := 0
var _frame_ms_total := 0.0
var _frame_ms_worst := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_active = args.has("--budget")
	if not _active:
		set_process(false)
		return
	_hide_labels = args.has("--hide-labels")
	_no_shadows = args.has("--no-shadows")
	_script_costs = args.has("--script-costs")
	# Longer, for a profiler to see steady state rather than the load.
	var at := args.find("--sample")
	if at >= 0 and at + 1 < args.size():
		SAMPLE = int(args[at + 1])

	# VSYNC OFF, or this measures the monitor instead of the renderer.
	#
	# With it on, the engine sleeps until the next refresh and the frame time it reports is the
	# PRESENTATION interval, not the work. Every pose came back at 8.33ms on this machine -- a
	# suspiciously round number, and exactly 1/120s -- whether the camera was looking at ninety
	# channel strips or at a wall. A measuring tool that returns the same answer regardless of
	# what it is pointed at is not a conservative measuring tool; it is a broken one, and it is
	# worse than none because its numbers look plausible enough to be written down.
	#
	# tools/shot.sh already does this, through override.cfg, for its own reasons: a window on a
	# workspace nobody is watching is presented about once a second. Same underlying fact, and
	# the budget wanted it more.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The renderer's own timing of its CPU and GPU halves, which frame_ms (the slower of the two,
	# plus everything else) cannot tell apart.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	# Last, so the scene is up and the backend is installed.
	await get_tree().process_frame


## An ABLATION, not a feature. Hiding every Label3D and re-reading the counters is the only way
## to find out what the lettering actually costs, as opposed to what counting nodes suggests it
## costs. Applied after the warmup so the surfaces have finished building the labels first.
var _hide_labels := false
## The same, for shadows: what the shadow passes add to the draw count.
var _no_shadows := false

## PER-SCRIPT CPU, by ablation: with each script's _process/_physics_process switched off in turn,
## how much shorter is the frame? The engine's own script-time monitor reads nonsense in an
## autoload (see `_process`), so this measures the same thing the way the wall clock can.
## Windows alternate with an untouched baseline window so drift in the machine is not blamed on
## a script.
var _script_costs := false
const COST_WINDOW := 40
var _cost_scripts: Array[String] = []
var _cost_nodes: Dictionary = {}
var _cost_step := -1
var _cost_frames := 0
var _cost_total := 0.0
var _cost_base: Array[float] = []
var _cost_results: Array = []


func _ablate() -> void:
	var n := 0
	for node in get_tree().root.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
		n += 1
	print("BUDGET.ablation hid %d labels" % n)


var _delta_ms := 0.0
var _render_cpu_total := 0.0
var _render_gpu_total := 0.0
## Milliseconds from the process starting to the first frame drawn: what starting the game costs.
var _first_frame_ms := -1


func _process(delta: float) -> void:
	if not _active:
		return
	_delta_ms = delta * 1000.0
	if _cost_step >= 0:
		_cost_tick(_delta_ms)
		return
	_frames += 1
	if _first_frame_ms < 0:
		_first_frame_ms = Time.get_ticks_msec()
	if _frames <= WARMUP:
		if _frames == WARMUP and _hide_labels:
			_ablate()
		if _frames == WARMUP and _no_shadows:
			var lit := 0
			for l in get_tree().root.find_children("*", "Light3D", true, false):
				if (l as Light3D).shadow_enabled:
					lit += 1
				(l as Light3D).shadow_enabled = false
			print("BUDGET.ablation dropped shadows from %d lights" % lit)
		return
	# WALL CLOCK, from delta.
	#
	# NOT Performance.TIME_PROCESS, which was the first thing this tool reported and which was
	# wrong by a hundredfold: it read 177ms per frame on a scene the wall clock timed at 1.85ms,
	# which would have been a 6fps crisis that does not exist. Whatever that monitor is
	# accumulating in an autoload, it is not this frame's script time. Delta is unambiguous,
	# cross-checks against the frame rate, and sees every cause of a slow frame rather than one.
	#
	# Engine.get_frames_per_second() went the same way, for the same reason: it averages over a
	# wall second and this tool samples forty frames, so on a fast scene it was still reporting
	# the startup. Two derived monitors measured wrong here and the raw delta measured right --
	# which is the argument for a measuring tool reporting as few numbers as it can defend.
	var ms := _delta_ms
	_frame_ms_total += ms
	var vp := get_viewport().get_viewport_rid()
	_render_cpu_total += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_render_gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_frame_ms_worst = maxf(_frame_ms_worst, ms)
	if _frames >= WARMUP + SAMPLE:
		_report()
		if _script_costs:
			_start_costs()
		else:
			get_tree().quit()


func _start_costs() -> void:
	for n in get_tree().root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc == null or n == self:
			continue
		if not (n.is_processing() or n.is_physics_processing()):
			continue
		var path: String = sc.resource_path
		if not _cost_nodes.has(path):
			_cost_nodes[path] = []
			_cost_scripts.append(path)
		_cost_nodes[path].append(n)
	_cost_step = 0
	_cost_frames = 0
	_cost_total = 0.0
	set_process(false)
	set_process(true)


func _set_cost_nodes(path: String, on: bool) -> void:
	for n in _cost_nodes[path]:
		if is_instance_valid(n):
			n.set_process(on)
			n.set_physics_process(on)


## Steps: even = a baseline window, odd = a window with script (step/2) off.
func _cost_tick(ms: float) -> void:
	_cost_frames += 1
	if _cost_frames <= 5:
		return
	_cost_total += ms
	if _cost_frames < 5 + COST_WINDOW:
		return
	var mean := _cost_total / float(COST_WINDOW)
	var i := _cost_step / 2
	if _cost_step % 2 == 0:
		_cost_base.append(mean)
		if i < _cost_scripts.size():
			_set_cost_nodes(_cost_scripts[i], false)
	else:
		_set_cost_nodes(_cost_scripts[i], true)
		var base := (_cost_base[i] + _cost_base[i + 1 if i + 1 < _cost_base.size() else i]) * 0.5
		_cost_results.append([_cost_scripts[i], base - mean, (_cost_nodes[_cost_scripts[i]] as Array).size()])
	_cost_step += 1
	_cost_frames = 0
	_cost_total = 0.0
	if _cost_step >= _cost_scripts.size() * 2 + 1:
		_cost_results.sort_custom(func(a, b): return a[1] > b[1])
		for r in _cost_results:
			print("BUDGET.script %s saved_ms=%.2f nodes=%d" % [r[0], r[1], r[2]])
		get_tree().quit()


func _report() -> void:
	var tracks := DAW.state.track_indices().size() if DAW.state else 0
	var info := func(what): return RenderingServer.get_rendering_info(what)

	# One machine-readable line, because the sweep is a shell loop and a table assembled by awk
	# is less wrong than one assembled by eye.
	print("BUDGET tracks=%d prims=%d draws=%d objects=%d vram_mb=%.1f frame_ms=%.2f worst_ms=%.2f nodes=%d render_cpu_ms=%.2f render_gpu_ms=%.2f start_ms=%d mem_mb=%.1f peak_mb=%.1f" % [
		tracks,
		info.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		info.call(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		float(info.call(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
		_frame_ms_total / float(SAMPLE),
		_frame_ms_worst,
		get_tree().get_node_count(),
		_render_cpu_total / float(SAMPLE),
		_render_gpu_total / float(SAMPLE),
		_first_frame_ms,
		float(OS.get_static_memory_usage()) / 1048576.0,
		float(OS.get_static_memory_peak_usage()) / 1048576.0,
	])

	# Where the loose meshes hang: the busiest parents, so the next fix goes at the real source.
	var by_parent := {}
	for m in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if not (m as MeshInstance3D).is_visible_in_tree():
			continue
		var key := "%s/%s" % [m.get_parent().name, m.get_parent().get_script().resource_path.get_file() if m.get_parent().get_script() else m.get_parent().get_class()]
		by_parent[key] = int(by_parent.get(key, 0)) + 1
	var keys := by_parent.keys()
	keys.sort_custom(func(a, b): return by_parent[a] > by_parent[b])
	for k in keys.slice(0, 15):
		print("BUDGET.parent %s meshes=%d" % [k, by_parent[k]])

	# And a breakdown by surface, because a total says there is a problem and nothing about
	# where it is. Counted off the live tree rather than from the classes' own arithmetic: the
	# question is what was BUILT, and a surface that builds more than it means to is exactly
	# the bug this would otherwise miss.
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if not (node is Surface):
			continue
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		var labels := node.find_children("*", "Label3D", true, false)
		var tris := 0
		for m in meshes:
			var mesh: Mesh = (m as MeshInstance3D).mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(i)
				if arrays.is_empty():
					continue
				var indices = arrays[Mesh.ARRAY_INDEX]
				if indices != null and indices.size() > 0:
					tris += indices.size() / 3
				elif arrays[Mesh.ARRAY_VERTEX] != null:
					tris += arrays[Mesh.ARRAY_VERTEX].size() / 3
		print("BUDGET.surface %s meshes=%d labels=%d tris=%d" % [
			node.name, meshes.size(), labels.size(), tris])
