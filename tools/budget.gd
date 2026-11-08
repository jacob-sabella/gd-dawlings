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
	_no_shadows = args.has("--no-shadows") or args.has("--no-omni-shadows") or args.has("--no-dir-shadows")
	_shadow_kind = "omni" if args.has("--no-omni-shadows") else ("dir" if args.has("--no-dir-shadows") else "")
	_script_costs = args.has("--script-costs")
	# `--without-script res://x.gd`: that script's processing off for the whole sample. One long
	# run against one long run is steadier than --script-costs' short windows.
	var wo := args.find("--without-script")
	if wo >= 0 and wo + 1 < args.size():
		_without_script = args[wo + 1]
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
## With --no-omni-shadows / --no-dir-shadows only that kind of light loses its shadow.
var _shadow_kind := ""

## PER-SCRIPT CPU, by ablation: with each script's _process/_physics_process switched off in turn,
## how much shorter is the frame? The engine's own script-time monitor reads nonsense in an
## autoload (see `_process`), so this measures the same thing the way the wall clock can.
## Windows alternate with an untouched baseline window so drift in the machine is not blamed on
## a script.
var _script_costs := false
var _without_script := ""
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
## Per-frame primitives, draw calls and objects summed over the sample window, with the extremes.
## One frame's count is not the scene's cost: the renderer redraws the lights' shadow maps on a
## rotation (some every frame, some every few), so a single frame is a high one or a low one by
## the phase it lands on (887k or 1096k primitives on the same build, same pose). The mean over
## the window is the number that does not move.
var _prims_total := 0.0
var _draws_total := 0.0
var _objects_total := 0.0
var _prims_lo := 1 << 60
var _prims_hi := 0
var _draws_lo := 1 << 60
## Every sampled frame's draw count, printed as BUDGET.series: a mean hides whether the cost is
## steady or comes in bursts, and the shadow maps' redraws come in bursts.
var _draw_series: Array[int] = []
var _node_series: Array[int] = []
var _draws_hi := 0
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
		if _frames == WARMUP and _without_script != "":
			var off := 0
			for n in get_tree().root.find_children("*", "", true, false):
				var sc: Script = n.get_script()
				if sc != null and sc.resource_path == _without_script and n != self:
					n.set_process(false)
					n.set_physics_process(false)
					off += 1
			print("BUDGET.ablation switched off %d x %s" % [off, _without_script])
		if _frames == WARMUP and OS.get_cmdline_user_args().has("--hide-node"):
			# Ablate subtrees by node name (comma-separated; every node of that name), to find what a cost hangs on.
			var want := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--hide-node") + 1]
			for one in want.split(","):
				for n3 in get_tree().root.find_children(one, "Node3D", true, false):
					(n3 as Node3D).visible = false
					print("BUDGET.ablation hid %s" % n3.get_path())
		if _frames == WARMUP and OS.get_cmdline_user_args().has("--no-interp-node"):
			# Ablation: stop physics interpolation on the named subtrees (comma-separated node names).
			var want2 := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--no-interp-node") + 1]
			for one in want2.split(","):
				for n3 in get_tree().root.find_children(one, "Node", true, false):
					n3.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
					print("BUDGET.ablation interpolation off for %s" % n3.get_path())
		if _frames == WARMUP and OS.get_cmdline_user_args().has("--shadow-off-index"):
			# Ablate ONE light's shadow, by its place in tree order among the shadowed lights.
			var which := int(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shadow-off-index") + 1])
			var at_i := 0
			for l in get_tree().root.find_children("*", "Light3D", true, false):
				if (l as Light3D).shadow_enabled:
					if at_i == which:
						(l as Light3D).shadow_enabled = false
						print("BUDGET.ablation dropped the shadow of %s %s" % [l.get_class(), l.get_path()])
					at_i += 1
		if _frames == WARMUP and _no_shadows:
			var lit := 0
			for l in get_tree().root.find_children("*", "Light3D", true, false):
				if _shadow_kind == "omni" and not l is OmniLight3D:
					continue
				if _shadow_kind == "dir" and not l is DirectionalLight3D:
					continue
				if (l as Light3D).shadow_enabled:
					lit += 1
				(l as Light3D).shadow_enabled = false
			print("BUDGET.ablation dropped shadows from %d lights" % lit)
		return
	if _frames > WARMUP + 1 and OS.get_cmdline_user_args().has("--tree"):
		_watch_movers()
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
	var frame_prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_prims_total += frame_prims
	_prims_lo = mini(_prims_lo, frame_prims)
	_prims_hi = maxi(_prims_hi, frame_prims)
	var frame_draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_draws_total += frame_draws
	_draw_series.append(frame_draws)
	_node_series.append(get_tree().get_node_count())
	_draws_lo = mini(_draws_lo, frame_draws)
	_draws_hi = maxi(_draws_hi, frame_draws)
	_objects_total += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
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
	print("BUDGET tracks=%d prims=%d draws=%d objects=%d prims_lo=%d prims_hi=%d draws_lo=%d draws_hi=%d vram_mb=%.1f frame_ms=%.2f worst_ms=%.2f nodes=%d render_cpu_ms=%.2f render_gpu_ms=%.2f start_ms=%d mem_mb=%.1f peak_mb=%.1f" % [
		tracks,
		roundi(_prims_total / float(SAMPLE)),
		roundi(_draws_total / float(SAMPLE)),
		roundi(_objects_total / float(SAMPLE)),
		_prims_lo,
		_prims_hi,
		_draws_lo,
		_draws_hi,
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

	print("BUDGET.series draws " + " ".join(PackedStringArray(_draw_series.map(func(d): return str(d)))))
	print("BUDGET.series nodes " + " ".join(PackedStringArray(_node_series.map(func(d): return str(d)))))
	if OS.get_cmdline_user_args().has("--tree"):
		_tree_breakdown()
		# Which scripts run every frame, and on how many nodes: the writers of whatever moves.
		var procs := {}
		for n in get_tree().root.find_children("*", "", true, false):
			var sc: Script = n.get_script()
			if sc != null and n != self and (n.is_processing() or n.is_physics_processing()):
				procs[sc.resource_path] = int(procs.get(sc.resource_path, 0)) + 1
		var pk := procs.keys()
		pk.sort()
		for k in pk:
			print("BUDGET.proc %s nodes=%d" % [k, procs[k]])

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


## WHERE THE DRAWS ARE: the visible meshes grouped by the subtree they hang in, so two builds can
## be diffed by owner instead of by total. `--tree-depth N` (default 4) is how many path segments
## make a group, counted from the scene under the root (`Studio/Venue/RackWall`, ...). Per group:
##   meshes   MeshInstance3Ds visible in the tree      hidden  those that are not (built, not drawn)
##   surfs    their surfaces (a surface is a draw)     tris    triangles over visible surfaces
##   casters  visible meshes that cast shadows         dupes   visible meshes whose mesh resource AND
##   lights   Light3Ds under the group                 world position (to 1 mm) match another's:
##            standing twice in the same place
##   inview   surfaces whose bounding box meets the camera's frustum: what the main pass can draw
##   moving   shadow casters whose world transform or visibility changed during the sample window;
##   moves    how many frame-to-frame changes that was in all (a moving caster redraws the shadow maps)
##   lit      caster surfaces within range of a shadow-casting omni light, summed over those
##            lights: what the shadow passes can draw (a surface in two lights' range counts twice)
## Names with an engine-made `@Class@12` form are written by class, so the paths of two runs match.
func _tree_breakdown() -> void:
	var depth := 4
	var args := OS.get_cmdline_user_args()
	var at := args.find("--tree-depth")
	if at >= 0 and at + 1 < args.size():
		depth = int(args[at + 1])
	var root := get_tree().current_scene
	if root == null:
		return
	var cam := get_viewport().get_camera_3d()
	var planes: Array[Plane] = cam.get_frustum() if cam != null else []
	# Shadowed point and spot lights as [position, range, name]; the sphere stands in for a spot's
	# cone, so a spot's count is an upper bound. The sun is left out: it sees the whole room.
	var shadow_lights: Array = []
	for l in root.find_children("*", "Light3D", true, false):
		var lt := l as Light3D
		if not (lt.shadow_enabled and lt.is_visible_in_tree()):
			continue
		if l is OmniLight3D:
			shadow_lights.append([lt.global_position, (l as OmniLight3D).omni_range, "%s/%s" % [l.get_parent().name, l.name]])
		elif l is SpotLight3D:
			shadow_lights.append([lt.global_position, (l as SpotLight3D).spot_range, "%s/%s" % [l.get_parent().name, l.name]])
	var per_light := {}
	var per_light_group := {}
	var groups := {}
	var seen := {}
	var tri_cache := {}
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var key := _group_key(root, mi, depth)
		var g: Dictionary = groups.get(key, {})
		if g.is_empty():
			g = {"meshes": 0, "hidden": 0, "surfs": 0, "tris": 0, "casters": 0, "dupes": 0, "lights": 0, "inview": 0, "lit": 0, "moving": 0, "moves": 0}
			groups[key] = g
		if mi.mesh == null:
			continue
		if not mi.is_visible_in_tree():
			g.hidden += 1
			continue
		g.meshes += 1
		g.surfs += mi.mesh.get_surface_count()
		if not tri_cache.has(mi.mesh):
			tri_cache[mi.mesh] = _mesh_tris(mi.mesh)
		g.tris += tri_cache[mi.mesh]
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			g.casters += 1
		if _watch_moves.has(mi):
			g.moving += 1
			g.moves += _watch_moves[mi]
		var box := mi.global_transform * mi.get_aabb()
		if cam != null and _in_frustum(planes, box):
			g.inview += mi.mesh.get_surface_count()
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			for sl in shadow_lights:
				if _box_in_range(box, sl[0], sl[1]):
					g.lit += mi.mesh.get_surface_count()
					per_light[sl[2]] = int(per_light.get(sl[2], 0)) + mi.mesh.get_surface_count()
					var lk: String = "%s <- %s" % [String(sl[2]).get_slice("/", 0), _group_key(root, mi, depth)]
					per_light_group[lk] = int(per_light_group.get(lk, 0)) + mi.mesh.get_surface_count()
		var o := mi.global_transform.origin
		var sig := "%d|%d,%d,%d|%d" % [mi.mesh.get_instance_id(), roundi(o.x * 1000.0), roundi(o.y * 1000.0), roundi(o.z * 1000.0), mi.get_surface_override_material_count()]
		if seen.has(sig):
			g.dupes += 1
		seen[sig] = true
	for l in root.find_children("*", "Light3D", true, false):
		var key := _group_key(root, l, depth)
		if not groups.has(key):
			groups[key] = {"meshes": 0, "hidden": 0, "surfs": 0, "tris": 0, "casters": 0, "dupes": 0, "lights": 0, "inview": 0, "lit": 0, "moving": 0, "moves": 0}
		groups[key].lights += 1
		var lt := l as Light3D
		print("BUDGET.light %s type=%s shadow=%s visible=%s energy=%.2f range=%.1f" % [
			key + "/" + String(l.name), l.get_class(), str(lt.shadow_enabled), str(lt.is_visible_in_tree()), lt.light_energy,
			(l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range if l is SpotLight3D else 0.0])
	# Everything else that is drawn and is not a MeshInstance3D: lettering, sprites, multimeshes,
	# particles. A draw is a draw whatever made it.
	var other := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D or not (n as GeometryInstance3D).is_visible_in_tree():
			continue
		var k2 := "%s [%s]" % [_group_key(root, n, depth), n.get_class()]
		other[k2] = int(other.get(k2, 0)) + 1
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			other[k2 + " instances"] = int(other.get(k2 + " instances", 0)) + (n as MultiMeshInstance3D).multimesh.visible_instance_count
	var ok := other.keys()
	ok.sort()
	for k in ok:
		print("BUDGET.other %s n=%d" % [k, other[k]])
	for k in per_light_group:
		print("BUDGET.shadowsrc %s surfs=%d" % [k, per_light_group[k]])
	for k in per_light:
		print("BUDGET.shadow %s casters_in_range=%d" % [k, per_light[k]])
	for n in _watch_moves:
		if is_instance_valid(n):
			var near := ""
			for sl in shadow_lights:
				if sl[2].contains("Omni") and (sl[0] as Vector3).distance_to((n as Node3D).global_position) <= sl[1]:
					near += " " + String(sl[2]).get_slice("/", 0)
			var casts: bool = n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("BUDGET.mover %s [%s] moves=%d at=%s casts=%s inrange_of=%s" % [_group_key(root, n, 8) + "/" + String(n.name), n.get_class(), _watch_moves[n], str((n as Node3D).global_position.snappedf(0.01)), str(casts), near])
	for sl in shadow_lights:
		print("BUDGET.shadowlight %s at=%s range=%.1f" % [sl[2], str((sl[0] as Vector3).snappedf(0.01)), sl[1]])
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var g: Dictionary = groups[k]
		print("BUDGET.tree %s meshes=%d hidden=%d surfs=%d tris=%d casters=%d dupes=%d lights=%d inview=%d lit=%d moving=%d moves=%d" % [k, g.meshes, g.hidden, g.surfs, g.tris, g.casters, g.dupes, g.lights, g.inview, g.lit, g.moving, g.moves])


func _group_key(root: Node, n: Node, depth: int) -> String:
	var parts: PackedStringArray = []
	var chain: Array[Node] = []
	var p := n.get_parent()
	while p != null and p != root.get_parent():
		chain.push_front(p)
		p = p.get_parent()
	for c in chain.slice(0, depth):
		parts.append(String(c.name) if not String(c.name).begins_with("@") else c.get_class())
	return "/".join(parts)


func _mesh_tris(mesh: Mesh) -> int:
	var tris := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			tris += indices.size() / 3
		elif arrays[Mesh.ARRAY_VERTEX] != null:
			tris += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return tris


func _in_frustum(planes: Array[Plane], box: AABB) -> bool:
	for pl in planes:
		var near := Vector3(
			box.end.x if pl.normal.x < 0.0 else box.position.x,
			box.end.y if pl.normal.y < 0.0 else box.position.y,
			box.end.z if pl.normal.z < 0.0 else box.position.z)
		if pl.distance_to(near) > 0.0:
			return false
	return true


func _box_in_range(box: AABB, centre: Vector3, radius: float) -> bool:
	var nearest := centre.clamp(box.position, box.end)
	return nearest.distance_to(centre) <= radius


## Shadow maps are cached and redrawn only when a caster in the light's range changes, so the draw
## count of a frame depends on what MOVED (or was shown, hidden or resized) in the frames before it,
## and a static count of casters cannot show that. This remembers each shadow-casting mesh's world
## transform and visibility from frame to frame over the sample window and counts, per mesh, the
## frames in which either changed. `_tree_breakdown` prints the sum per group as `moving` (meshes
## that changed at least once) and `moves` (changes, summed).
var _watch := {}
var _watch_last := {}
var _watch_moves := {}


func _watch_movers() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	if _watch.is_empty():
		for m in root.find_children("*", "GeometryInstance3D", true, false):
			_watch[m] = true
		for l in root.find_children("*", "Light3D", true, false):
			_watch[l] = true
	for m in _watch:
		if not is_instance_valid(m):
			continue
		var state := [(m as Node3D).global_transform, (m as Node3D).is_visible_in_tree()]
		if m is MeshInstance3D and (m as MeshInstance3D).mesh != null:
			# The geometry itself: a mesh rebuilt in place changes without its node moving.
			var mesh := (m as MeshInstance3D).mesh
			state.append([mesh.get_rid(), mesh.get_aabb(), mesh.get_surface_count()])
		elif m is MultiMeshInstance3D and (m as MultiMeshInstance3D).multimesh != null:
			var mm := (m as MultiMeshInstance3D).multimesh
			state.append([mm.visible_instance_count, mm.get_aabb(), mm.get_instance_transform(0) if mm.instance_count > 0 else Transform3D()])
		elif m is Label3D:
			state.append([(m as Label3D).text, (m as Label3D).get_aabb()])
		elif m is GeometryInstance3D:
			state.append((m as GeometryInstance3D).get_aabb())
		elif m is Light3D:
			state.append([(m as Light3D).light_energy, (m as Light3D).shadow_enabled, (m as Light3D).light_color])
		if _watch_last.has(m) and _watch_last[m] != state:
			_watch_moves[m] = int(_watch_moves.get(m, 0)) + 1
		_watch_last[m] = state
