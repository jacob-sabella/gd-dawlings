class_name RackSurface
extends Surface

## A standing rack holding every plugin in the project, one unit per FX slot.
##
## Ordering is Reaper's: track order, then slot order within a track. That means the rack is a
## readable picture of the signal flow rather than a pile -- the kick's compressor sits directly
## above the kick's EQ, in the order they process.
##
## A rack fills TOP-DOWN and overflows sideways into a second bay rather than growing taller
## than a person, because in ROOM mode the units above 2m are genuinely unreachable. Top-down
## because the alternative puts the first track's plugins at your ankles.
##
## Unused U get blanking panels, which is what a real rack has in them and is also the only
## honest way to draw the gap: a part-filled bay with nothing in the empty rows is a hole you
## can see the far wall through, and it reads as a modelling mistake rather than as space.

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
		for fx_index in t.plugins():
			slots.append([track_index, fx_index])
	if slots.is_empty():
		return

	var unit_height := RackUnit.U * RackUnit.UNITS_TALL
	var per_bay := int(floor(BAY_HEIGHT / unit_height))
	if compact:
		# Sized to what is in it, and split into enough bays that the result is wider than it is
		# tall. Not a cosmetic trim: the full-height bay is 1.13m, which needs 0.98m of standoff
		# to fit the eye sweep while its lettering only carries to 0.96m -- the rack literally
		# cannot be both seen and read, and six empty U are most of the reason. A neck yaws much
		# further than it pitches, so trading height for width is trading an expensive axis for
		# a cheap one.
		# Rows per bay that make the result about as wide as it is tall. bays = n/p, so
		# width = (n/p)*BAY_SPACING and height = p*unit_height; setting those equal gives
		# p = sqrt(n * BAY_SPACING / unit_height). Capped at the number of units there actually
		# are, so a rack that fits in one bay gets one bay with no blanks in it.
		var square := int(ceil(sqrt(float(slots.size()) * BAY_SPACING / unit_height)))
		per_bay = clampi(square, 1, mini(per_bay, slots.size()))
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

		_blank_from(bay_node, slots.size() - bay * per_bay, per_bay, unit_height)


## Blanking panels for the rows this bay did not fill.
##
## One banked plate and four banked screws per row, because every blank is the same object in a
## different place and that is exactly what a MeshBank is for -- a twelve-U bay with two units
## in it would otherwise add forty more draws to say nothing.
##
## Deliberately plainer and darker than a faceplate. A blank that looked like a unit would be a
## rack full of dead gear; a blank that looks like a panel is a rack with room in it.
func _blank_from(bay_node: Node3D, filled: int, per_bay: int, unit_height: float) -> void:
	var empty := per_bay - filled
	if empty <= 0:
		return

	var plates := MeshBank.parts(
			Vector3(RackUnit.RACK_WIDTH, unit_height - 0.003, 0.010), Materials.blanking_panel())
	plates.name = "BlankPlates"
	bay_node.add_child(plates)
	var screws := MeshBank.parts(
			Vector3(0.0044, 0.0044, 0.002), Materials.cap_plastic(Color(0.3, 0.31, 0.33)))
	screws.name = "BlankScrews"
	bay_node.add_child(screws)

	for row in range(filled, per_bay):
		var y := per_bay * unit_height - (row + 0.5) * unit_height
		plates.claim(Transform3D(Basis.IDENTITY, Vector3(0, y, -0.005)), Color.WHITE)
		for side in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				screws.claim(Transform3D(Basis.IDENTITY, Vector3(
						side * (RackUnit.RACK_WIDTH * 0.5 - 0.009),
						y + sy * RackUnit.U * 0.5, 0.002)), Color.WHITE)
	plates.commit()
	screws.commit()


## Set back a millimetre behind the faceplates, and the rails a little shallower than the posts.
## Flush, the face of every unit lay in the plane of the frame's front, and the posts and rails
## shared both their front and back planes where they cross -- a rack whose corners flickered.
const FRAME_SETBACK := 0.001


func _build_frame(parent: Node3D, inner_height: float) -> void:
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.022, inner_height + 0.05, RAIL_DEPTH)
		post.mesh = post_mesh
		post.position = Vector3(side * (RackUnit.RACK_WIDTH * 0.5 + 0.011), inner_height * 0.5,
				-RAIL_DEPTH * 0.5 - FRAME_SETBACK)
		post.material_override = Materials.chassis()
		parent.add_child(post)

	for y in [0.0, inner_height + 0.025]:
		var cross := MeshInstance3D.new()
		var cross_mesh := BoxMesh.new()
		cross_mesh.size = Vector3(RackUnit.RACK_WIDTH + 0.040, 0.022, RAIL_DEPTH - 0.004)
		cross.mesh = cross_mesh
		cross.position = Vector3(0, y, -RAIL_DEPTH * 0.5 - FRAME_SETBACK)
		cross.material_override = Materials.chassis()
		parent.add_child(cross)
