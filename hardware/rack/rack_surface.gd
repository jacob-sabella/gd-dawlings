class_name RackSurface
extends Surface

## A standing rack holding every plugin in the project, one unit per FX slot.
##
## Ordering is Reaper's: track order, then slot order within a track. That means the rack is a
## readable picture of the signal flow rather than a pile -- the kick's compressor sits directly
## above the kick's EQ, in the order they process.
##
## A rack fills bottom-up and overflows into a second bay rather than growing taller than a
## person, because in ROOM mode the units above 2m are genuinely unreachable.

const BAY_HEIGHT := 1.1
const BAY_SPACING := 0.56
const RAIL_DEPTH := 0.30


func _ready() -> void:
	surface_kind = &"rack"
	if surface_id == &"":
		surface_id = &"rack"
	super()


func _rebuild() -> void:
	_clear_built()

	var slots: Array = []
	for track_index in DAW.state.track_indices():
		var t := DAW.state.track(track_index)
		var fx_indices: Array = t.fx.keys()
		fx_indices.sort()
		for fx_index in fx_indices:
			slots.append([track_index, fx_index])
	if slots.is_empty():
		return

	var unit_height := RackUnit.U * RackUnit.UNITS_TALL
	var per_bay := int(floor(BAY_HEIGHT / unit_height))
	var bays := int(ceil(float(slots.size()) / float(per_bay)))

	for bay in bays:
		var bay_node := Node3D.new()
		bay_node.position = Vector3(bay * BAY_SPACING, 0, 0)
		_adopt(bay_node)
		_build_frame(bay_node, per_bay * unit_height)

		for row in per_bay:
			var slot_index := bay * per_bay + row
			if slot_index >= slots.size():
				break
			var unit := RackUnit.create(slots[slot_index][0], slots[slot_index][1])
			# Filled from the top down so that the first track's FX are at eye level rather than
			# at the floor: a 20-unit rack read bottom-up puts channel 1 at your ankles.
			unit.position = Vector3(0, per_bay * unit_height - (row + 0.5) * unit_height, 0)
			bay_node.add_child(unit)


func _build_frame(parent: Node3D, inner_height: float) -> void:
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.022, inner_height + 0.05, RAIL_DEPTH)
		post.mesh = post_mesh
		post.position = Vector3(side * (RackUnit.RACK_WIDTH * 0.5 + 0.011), inner_height * 0.5, -RAIL_DEPTH * 0.5)
		post.material_override = Materials.chassis()
		parent.add_child(post)

	for y in [0.0, inner_height + 0.025]:
		var cross := MeshInstance3D.new()
		var cross_mesh := BoxMesh.new()
		cross_mesh.size = Vector3(RackUnit.RACK_WIDTH + 0.044, 0.022, RAIL_DEPTH)
		cross.mesh = cross_mesh
		cross.position = Vector3(0, y, -RAIL_DEPTH * 0.5)
		cross.material_override = Materials.chassis()
		parent.add_child(cross)
