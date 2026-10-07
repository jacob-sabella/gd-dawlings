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

	var indices := DAW.state.track_indices()
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

	# Before the jacks and in its final place, because a jack claims its slot by converting its
	# own world transform into the bank's. Null when the authored jack will not resolve, in
	# which case every jack falls back to drawing itself and the bay still works.
	var socket_bank := MeshBank.of(
		PatchPoint.MESH_PATH,
		Materials.brushed_metal(),
		{"bore": Materials.recess()},
	)
	if socket_bank != null:
		socket_bank.name = "JackSockets"
		_adopt(socket_bank)

	var x := -width * 0.5 + 0.02 + JACK_PITCH * 0.5
	for index in indices:
		var t := DAW.state.track(index)

		var out_jack := PatchPoint.create(index, PatchPoint.Kind.OUTPUT, t.display_name())
		out_jack.socket_bank = socket_bank
		out_jack.position = Vector3(x, ROW_GAP, 0.004)
		out_jack.patch_requested.connect(_on_patch_requested)
		_adopt(out_jack)
		_outputs[index] = out_jack

		var in_jack := PatchPoint.create(index, PatchPoint.Kind.INPUT, t.display_name())
		in_jack.socket_bank = socket_bank
		in_jack.position = Vector3(x, 0.0, 0.004)
		in_jack.patch_requested.connect(_on_patch_requested)
		_adopt(in_jack)
		_inputs[index] = in_jack

		x += JACK_PITCH

	if socket_bank != null:
		socket_bank.commit()

	# Cables are drawn after both rows exist, because a send names its destination by NAME and
	# the jack for that name may belong to a track built later in this same loop.
	call_deferred("_draw_cables")


func _draw_cables() -> void:
	for cable in _cables:
		cable.queue_free()
	_cables.clear()

	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		for send_index in t.sends:
			var s: MixState.SendState = t.sends[send_index]
			var dest := s.resolve(DAW.state)
			if dest < 0 or not _outputs.has(index) or not _inputs.has(dest):
				continue
			var from_jack: PatchPoint = _outputs[index]
			var to_jack: PatchPoint = _inputs[dest]
			# Seeded from the pair, so a cable keeps its own slack and bow across rebuilds and
			# two sends landing on the same return do not draw as one thick line.
			var cable := PatchCable.create(from_jack.global_transform, to_jack.global_transform,
					t.colour, hash(Vector2i(index, dest)))
			_adopt(cable)
			_cables.append(cable)


## Kept for the OSC-only case, and for the test that pins the ambiguity it cannot fix.
##
## Over OSC a send's destination is a NAME, so this is the only way to resolve one -- and it is
## why two tracks called "Verb" made the bay guess. `SendState.resolve` prefers the index the
## ReaScript bridge supplies and falls back to this, so the bay is exact when the bridge is
## loaded and still roughly right when it is not.
func _index_by_name(track_name: String) -> int:
	if track_name == "":
		return -1
	for index in DAW.state.track_indices():
		if DAW.state.track(index).display_name() == track_name:
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
	if not DAW.create_send(src, dst):
		# Said out loud, for the reason in the class note.
		push_warning("Patchbay: cannot create %d -> %d. The ReaScript bridge is not loaded in Reaper, and OSC has no message for making a send." % [src, dst])
		return
	# Only on the send that actually took. A plug sound on a refused patch would say the cable is
	# in when it is not, which is the one thing the sound is here to be trusted about -- and the
	# two failures above are already said out loud in the log.
	Foley.play(to, Foley.plug_seat(), -6.0)
	mark_dirty()
