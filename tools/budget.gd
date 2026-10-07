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
const SAMPLE := 40

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

	# Last, so the scene is up and the backend is installed.
	await get_tree().process_frame


## An ABLATION, not a feature. Hiding every Label3D and re-reading the counters is the only way
## to find out what the lettering actually costs, as opposed to what counting nodes suggests it
## costs. Applied after the warmup so the surfaces have finished building the labels first.
var _hide_labels := false


func _ablate() -> void:
	var n := 0
	for node in get_tree().root.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
		n += 1
	print("BUDGET.ablation hid %d labels" % n)


var _delta_ms := 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	_delta_ms = delta * 1000.0
	_frames += 1
	if _frames <= WARMUP:
		if _frames == WARMUP and _hide_labels:
			_ablate()
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
	_frame_ms_worst = maxf(_frame_ms_worst, ms)
	if _frames >= WARMUP + SAMPLE:
		_report()
		get_tree().quit()


func _report() -> void:
	var tracks := DAW.state.track_indices().size() if DAW.state else 0
	var info := func(what): return RenderingServer.get_rendering_info(what)

	# One machine-readable line, because the sweep is a shell loop and a table assembled by awk
	# is less wrong than one assembled by eye.
	print("BUDGET tracks=%d prims=%d draws=%d objects=%d vram_mb=%.1f frame_ms=%.2f worst_ms=%.2f nodes=%d" % [
		tracks,
		info.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		info.call(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		float(info.call(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
		_frame_ms_total / float(SAMPLE),
		_frame_ms_worst,
		get_tree().get_node_count(),
	])

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
