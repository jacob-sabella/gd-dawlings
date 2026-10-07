class_name PatchbaySurface
extends Surface

## The routing bay: every track's output on the top row, every track's input on the bottom, and
## a cable for every send Reaper currently has.
##
## THE HONEST LIMITATION, stated here because it is structural rather than a gap to be filled in
## later. Reaper's OSC surface streams send LEVELS but has no message that creates or destroys a
## send; that is only reachable from ReaScript. So this bay DISPLAYS routing from OSC and CHANGES
## routing through the file bridge, and when the bridge is not loaded in Reaper it says so rather
## than dropping the gesture. A patchbay that silently fails to patch is worse than one that
## admits it cannot: with the former you spend twenty minutes assuming you missed the jack.
##
## See core/reaper/script_bridge.gd and reaper/reaper3d_bridge.lua.

const JACK_PITCH := 0.034
const ROW_GAP := 0.085

var _cables: Array[PatchCable] = []
var _outputs: Dictionary = {}
var _inputs: Dictionary = {}


func _ready() -> void:
	surface_kind = &"patchbay"
	if surface_id == &"":
		surface_id = &"patchbay"
	super()


func _rebuild() -> void:
	_clear_built()
	_cables.clear()
	_outputs.clear()
	_inputs.clear()

	var indices := Reaper.state.track_indices()
	if indices.is_empty():
		return

	var width := indices.size() * JACK_PITCH + 0.04

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(width, ROW_GAP + 0.075, 0.014)
	panel.mesh = panel_mesh
	panel.position = Vector3(0, ROW_GAP * 0.5, -0.008)
	panel.material_override = Materials.chassis()
	_adopt(panel)

	var x := -width * 0.5 + 0.02 + JACK_PITCH * 0.5
	for index in indices:
		var t := Reaper.state.track(index)

		var out_jack := PatchPoint.create(index, PatchPoint.Kind.OUTPUT, t.display_name())
		out_jack.position = Vector3(x, ROW_GAP, 0.004)
		out_jack.patch_requested.connect(_on_patch_requested)
		_adopt(out_jack)
		_outputs[index] = out_jack

		var in_jack := PatchPoint.create(index, PatchPoint.Kind.INPUT, t.display_name())
		in_jack.position = Vector3(x, 0.0, 0.004)
		in_jack.patch_requested.connect(_on_patch_requested)
		_adopt(in_jack)
		_inputs[index] = in_jack

		x += JACK_PITCH

	# Cables are drawn after both rows exist, because a send names its destination by NAME and
	# the jack for that name may belong to a track built later in this same loop.
	call_deferred("_draw_cables")


func _draw_cables() -> void:
	for cable in _cables:
		cable.queue_free()
	_cables.clear()

	for index in Reaper.state.track_indices():
		var t := Reaper.state.track(index)
		for send_index in t.sends:
			var s: ReaperState.SendState = t.sends[send_index]
			var dest := _index_by_name(s.dest_name)
			if dest < 0 or not _outputs.has(index) or not _inputs.has(dest):
				continue
			var from_jack: PatchPoint = _outputs[index]
			var to_jack: PatchPoint = _inputs[dest]
			var cable := PatchCable.create(from_jack.global_position, to_jack.global_position, t.colour)
			_adopt(cable)
			_cables.append(cable)


## Reaper identifies a send's destination by the track's NAME over OSC, not by index, so this is
## the only way to resolve one. It is also why two tracks called "Verb" make the bay ambiguous --
## worth knowing before blaming the cable.
func _index_by_name(track_name: String) -> int:
	if track_name == "":
		return -1
	for index in Reaper.state.track_indices():
		if Reaper.state.track(index).display_name() == track_name:
			return index
	return -1


func _on_patch_requested(from: PatchPoint, to: PatchPoint) -> void:
	if from.kind == to.kind:
		push_warning("Patchbay: %s to %s is output-to-output; a send needs an output and an input." % [from.label_text, to.label_text])
		return
	var src := from.track_index if from.kind == PatchPoint.Kind.OUTPUT else to.track_index
	var dst := to.track_index if from.kind == PatchPoint.Kind.OUTPUT else from.track_index
	if src == dst:
		return
	if not Reaper.create_send(src, dst):
		# Said out loud, for the reason in the class note.
		push_warning("Patchbay: cannot create %d -> %d. The ReaScript bridge is not loaded in Reaper, and OSC has no message for making a send." % [src, dst])
		return
	mark_dirty()
