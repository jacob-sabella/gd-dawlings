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
## A SECOND structural fact, which the geometry has to answer rather than the protocol: one
## jack takes one plug. Reaper will happily send four tracks to one return, and four cables
## into one bore is not a picture of that -- it is a picture of nothing. Fan-in is drawn
## through a mult hung under the bay; see hardware/patchbay/patch_mult.gd.
##
## See core/reaper/script_bridge.gd and reaper/reaper3d_bridge.lua.

const JACK_PITCH := 0.034
const ROW_GAP := 0.085
## Where the mult strip hangs, measured from the input row. Clear of the meter-bridge crossbar
## the bay is bolted to -- the first placement put it halfway through the bar -- and far enough
## below the input captions to read as separate hardware hung underneath, which is what it is.
## How far above the panel's lower edge the permanent looms enter the back of the bay.
##
## Not at the bottom, which is where a loom would naturally go, because whatever carries a bay
## is bolted across the bottom of it -- in this room a meter-bridge crossbar, and the first
## version of these looms entered at the bottom edge and arrived three centimetres inside it.
## The bay cannot see the furniture holding it up, so this is a clearance it keeps on principle
## rather than a number it derived. What checks it is the studio's own test.
const LOOM_ENTRY_RISE := 0.068
const MULT_ROW_Y := -0.115
const MULT_SPACING := 0.008

var _cables: Array[PatchCable] = []
var _mults: Array[PatchMult] = []
var _panel_width := 0.0
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
	_mults.clear()
	_outputs.clear()
	_inputs.clear()

	var indices := DAW.state.track_indices()
	if indices.is_empty():
		return

	var width := indices.size() * JACK_PITCH + 0.04
	_panel_width = width

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

	# Says so when these jacks are a BANK rather than the bay. Same reason the timeline does:
	# a patchbay is read as every jack there is, and the one thing you cannot do with a jack
	# that was never drawn is notice it is missing.
	var caption := DAW.state.bank_caption()
	if caption != "":
		var notice := Label3D.new()
		notice.text = caption
		notice.font_size = 72
		notice.pixel_size = 0.00024
		notice.modulate = Color(0.72, 0.60, 0.40)
		notice.outline_size = 0
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		notice.position = Vector3(-width * 0.5 + 0.02, ROW_GAP + 0.048, 0.002)
		Lettering.range_to_legibility(notice)
		_adopt(notice)

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
	for mult in _mults:
		mult.queue_free()
	_mults.clear()

	# Gathered before anything is drawn, because the shape of the picture depends on the
	# fan-in: one source into a return is a cable, several is a mult and several cables. That
	# is not known until every send has been read.
	var arrivals: Dictionary = {}
	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		for send_index in t.sends:
			var s: MixState.SendState = t.sends[send_index]
			var dest := s.resolve(DAW.state)
			if dest < 0 or not _outputs.has(index) or not _inputs.has(dest):
				continue
			if not arrivals.has(dest):
				arrivals[dest] = []
			arrivals[dest].append(index)

	var destinations := arrivals.keys()
	destinations.sort()

	var multed: Array[int] = []
	var row_width := 0.0
	for dest in destinations:
		if arrivals[dest].size() < 2:
			continue
		multed.append(dest)
		row_width += PatchMult.width_for(arrivals[dest].size()) + MULT_SPACING

	var mult_bank: MeshBank = null
	if not multed.is_empty():
		row_width -= MULT_SPACING
		mult_bank = MeshBank.of(
			PatchPoint.MESH_PATH,
			Materials.brushed_metal(),
			{"bore": Materials.recess()},
		)
		if mult_bank != null:
			mult_bank.name = "MultSockets"
			_adopt(mult_bank)

	# Packed left to right from a centred row rather than hung under their destination column.
	# Under-the-column would collide the moment two neighbouring returns were both multed, and
	# a mult is a bussed strip -- nothing about it says it has to live beneath the jack it
	# feeds. The trunk cable says that.
	var cursor := -row_width * 0.5
	var mult_for: Dictionary = {}
	for dest in multed:
		var ways: int = arrivals[dest].size()
		var span := PatchMult.width_for(ways)
		var mult := PatchMult.create(DAW.state.track(dest).display_name(), ways, mult_bank)
		# Positioned before it enters the tree: a socket claims its slot in the bank out of its
		# own world transform, and a mult placed after the fact would bank its sockets at the
		# origin and then walk away from them.
		mult.strap_length = _panel_bottom_y() - (MULT_ROW_Y + PatchMult.HEIGHT * 0.5)
		mult.position = Vector3(cursor + span * 0.5, MULT_ROW_Y, 0.004)
		_adopt(mult)
		_mults.append(mult)
		mult_for[dest] = mult
		cursor += span + MULT_SPACING

	if mult_bank != null:
		mult_bank.commit()

	for dest in destinations:
		var sources: Array = arrivals[dest]
		var to_jack: PatchPoint = _inputs[dest]
		if sources.size() < 2:
			var only: int = sources[0]
			_lay(_outputs[only].global_transform, to_jack.global_transform,
					DAW.state.track(only).colour, hash(Vector2i(only, dest)))
			continue
		var mult: PatchMult = mult_for[dest]
		for i in sources.size():
			var src: int = sources[i]
			_lay(_outputs[src].global_transform, mult.jack_transform(i + 1),
					DAW.state.track(src).colour, hash(Vector2i(src, dest)))
		# The one cable that leaves. Tinted like the return it feeds, not like any one source,
		# because by this point it is carrying all of them.
		_lay(mult.trunk_transform(), to_jack.global_transform,
				DAW.state.track(dest).colour, hash(Vector2i(dest, dest)))


## The lower edge of the bay's own panel, which is where a hung mult's straps have to reach.
## Where a permanent loom enters the back of the bay, at a fraction (-1..1) across it.
##
## The bay answers this rather than the room working it out, because the panel is exactly as wide
## as the session has tracks. A room that assumed a width would hang the glands off the end of a
## small session's bay and bury them inside a large one's.
func loom_entry(fraction: float) -> Vector3:
	var half := maxf(_panel_width * 0.5 - 0.05, 0.0)
	return Vector3(clampf(fraction, -1.0, 1.0) * half,
			_panel_bottom_y() + LOOM_ENTRY_RISE, -0.016)


func _panel_bottom_y() -> float:
	return ROW_GAP * 0.5 - (ROW_GAP + 0.075) * 0.5


## Seeded from the pair, so a cable keeps its own slack and bow across rebuilds and two cables
## running between the same two pieces of hardware do not draw as one thick line.
func _lay(from_xform: Transform3D, to_xform: Transform3D, tint: Color, seed_value: int) -> void:
	var cable := PatchCable.create(from_xform, to_xform, tint, seed_value)
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
