class_name RackSurface
extends Surface

## A standing rack holding one track's plugins, one unit per FX slot: that track's insert rack.
##
## ONE TRACK, not the project. It held every plugin once, and a project of fifty plugins was six
## bays and three and a half metres of gear whose lettering could not be read from anywhere it
## could all be seen -- at twice the frame time, which a headset does not have. A chain is what
## anyone works on at a time, so the rack shows the chain of the track Reaper has selected, and
## the window over the rack scrolls through the tracks that have plugins. Pulling a unit off
## onto a tablet keeps it in reach after the rack has moved on.
##
## Ordering is Reaper's slot order, so the rack is a readable picture of the signal flow rather
## than a pile -- the compressor sits directly above the EQ it feeds.
##
## A rack fills TOP-DOWN and overflows sideways into a second bay rather than growing taller
## than a person, because in ROOM mode the units above 2m are genuinely unreachable. Top-down
## because the alternative puts the first track's plugins at your ankles.
##
## Unused U get blanking panels, which is what a real rack has in them and is also the only
## honest way to draw the gap: a part-filled bay with nothing in the empty rows is a hole you
## can see the far wall through, and it reads as a modelling mistake rather than as space.

## A unit's name strip was pulled: whoever placed this rack decides where the tablet stands.
signal tear_requested(track: int, fx: int, at: Vector3)

const BAY_HEIGHT := 1.1
const BAY_SPACING := 0.56
const RAIL_DEPTH := 0.30
## The track-picking window, set into the front of the frame's top rail like a rack's label
## strip -- on it rather than over it, so it adds nothing to the rack's height for the camera.
const PICKER_SIZE := Vector2(0.30, 0.02)
const PICKER_SCALE := 1.1
const PICKER_RISE := 0.025
## The fewest rows a rack is built with, blanks making up the rest.
const MIN_ROWS := 4

## The track whose plugins are racked, or -1 before one has been chosen.
var track_index := -1

var _picker: TabletSelector
var _empty_label: Label3D
## The racked chain as it was built: a rebuild is for a change to THIS, not for every plugin
## update anywhere in the project.
var _built_chain := ""


func _ready() -> void:
	surface_kind = &"rack"
	if surface_id == &"":
		surface_id = &"rack"
	super()
	DAW.track_changed.connect(_on_track_changed)


## Rack this track's plugins.
func show_track(index: int) -> void:
	if index == track_index or not DAW.state.tracks.has(index):
		return
	track_index = index
	mark_dirty()


## The track to rack when none has been chosen, or the chosen one has gone: Reaper's selected
## track, else the first with plugins, else the first.
func _settle_track() -> void:
	var tracks: Array = DAW.state.track_indices()
	if DAW.state.tracks.has(track_index) or tracks.is_empty():
		return
	for i in tracks:
		if DAW.state.track(i).selected:
			track_index = i
			return
	for i in tracks:
		if not DAW.state.track(i).plugins().is_empty():
			track_index = i
			return
	track_index = tracks[0]


## The chain, as something to compare: which slots, holding what.
func _chain_key() -> String:
	if not DAW.state.tracks.has(track_index):
		return "%d|-" % track_index
	var parts: Array = [track_index]
	for i in DAW.state.track(track_index).plugins():
		parts.append("%d:%s" % [i, DAW.state.fx(track_index, i).name])
	return "|".join(parts)


## A plugin changed. Its unit refreshes itself; the rack is rebuilt only when the racked chain
## has a plugin more, less or different -- not for a preset or a parameter list arriving, and
## not for anything on any other track, which is what made a busy project hitch.
##
## Looked at once a frame: Reaper names a thousand plugins in one refresh.
func _on_fx_shape_changed(_t: int, _fx: int) -> void:
	_once_this_frame(_check_chain)


func _check_chain() -> void:
	if _chain_key() != _built_chain:
		mark_dirty()
	else:
		_refresh_picker()


## Following Reaper's selection: the track selected there is the one racked here.
func _on_track_changed(index: int, field: StringName) -> void:
	if field == &"selected" and DAW.state.tracks.has(index) and DAW.state.track(index).selected:
		show_track(index)
	elif field in [&"name", &"selected"]:
		_once_this_frame(_refresh_picker)


func _refresh_picker() -> void:
	if _picker != null:
		_picker.refresh()
		_picker.lit = _following()


## Whether the rack is showing the track Reaper has selected.
func _following() -> bool:
	return DAW.state.tracks.has(track_index) and DAW.state.track(track_index).selected


## The tracks worth racking, for the window: those with plugins, and the one racked now.
func _rackable() -> Array:
	var out: Array = []
	for i in DAW.state.track_indices():
		var t := DAW.state.track(i)
		var count := t.plugins().size()
		if count > 0 or i == track_index:
			out.append([i, "%s   ·   %s" % [t.display_name().to_upper(),
					"%d PLUGIN%s" % [count, "" if count == 1 else "S"] if count > 0 else "NO PLUGINS"]])
	return out


func _rebuild() -> void:
	_clear_built()
	_picker = null
	_empty_label = null
	_settle_track()
	_built_chain = _chain_key()
	if not DAW.state.tracks.has(track_index):
		return

	var slots: Array = []
	for fx_index in DAW.state.track(track_index).plugins():
		slots.append([track_index, fx_index])
	# Never fewer than MIN_ROWS: a two-plugin chain in a two-row frame is a shelf, and a rack
	# that changed size with every track scrolled through would move what you are looking at.
	# An empty chain is still a rack, with its window, so there is somewhere to scroll from.
	var rows := maxi(slots.size(), MIN_ROWS)

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
		var square := int(ceil(sqrt(float(rows) * BAY_SPACING / unit_height)))
		per_bay = clampi(square, 1, mini(per_bay, rows))
	var bays := int(ceil(float(rows) / float(per_bay)))
	var banks := _make_banks()

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
			unit.panel_bank = banks[0]
			unit.knob_bank = banks[1]
			unit.body_bank = banks[2]
			unit.lamp_bank = banks[3]
			unit.tear_requested.connect(func(t: int, f: int, at: Vector3): tear_requested.emit(t, f, at))
			# Filled from the top down so that the first track's FX are at eye level rather than
			# at the floor: a 20-unit rack read bottom-up puts channel 1 at your ankles.
			unit.position = Vector3(0, per_bay * unit_height - (row + 0.5) * unit_height, 0)
			bay_node.add_child(unit)

		_blank_from(bay_node, maxi(slots.size() - bay * per_bay, 0), per_bay, unit_height)

	# After every unit has claimed its slots: a bank is sized once.
	for bank in banks:
		if bank != null:
			bank.commit()
	_build_picker(per_bay * unit_height)
	if slots.is_empty():
		_empty_label = Label3D.new()
		_empty_label.name = "Empty"
		_empty_label.text = "NO PLUGINS ON THIS TRACK"
		_empty_label.font_size = 64
		_empty_label.pixel_size = 0.00019
		_empty_label.modulate = Color(0.62, 0.65, 0.70)
		_empty_label.position = Vector3(0, per_bay * unit_height * 0.5, 0.004)
		Lettering.range_to_legibility(_empty_label)
		_adopt(_empty_label)


## One bank each for the faceplates, knobs, power buttons and their lamps, shared by every unit.
## The two authored parts are null when their asset will not resolve, and a unit then builds its
## own, as it did before there were banks.
func _make_banks() -> Array:
	var panels := MeshBank.of(RackUnit.MESH_PATH, Materials.chassis(), {"screw": Materials.brushed_metal()})
	var knobs := MeshBank.of(Knob.MESH_PATH, Materials.cap_plastic(Color(0.14, 0.15, 0.17)),
			{"indicator": Materials.legend()})
	var bodies := MeshBank.parts(PanelButton.BODY_SIZE, PanelButton.body_material())
	var lamps := MeshBank.lamps(PanelButton.LAMP_SIZE)
	var names := ["Faceplates", "Knobs", "ButtonBodies", "ButtonLamps"]
	var banks := [panels, knobs, bodies, lamps]
	for i in banks.size():
		if banks[i] != null:
			banks[i].name = names[i]
			_adopt(banks[i])
	return banks


## The window over the rack that says whose plugins these are, and scrolls to another track's.
## Lit while it is showing the track Reaper has selected, which is the track it follows.
func _build_picker(bay_height: float) -> void:
	_picker = TabletSelector.new()
	_picker.name = "TrackPicker"
	_picker.size = PICKER_SIZE
	_picker.scale = Vector3.ONE * PICKER_SCALE
	_picker.position = Vector3(0, bay_height + PICKER_RISE, 0.002)
	_picker.options = _rackable
	_picker.choice = track_index
	_picker.hint_text = "scroll to rack another track's plugins  ·  selecting a track in Reaper racks it"
	_picker.describe_title = func() -> String: return "RACK"
	_picker.describe_value = func(_v: float) -> String: return _picker.words()
	_picker.chosen.connect(show_track)
	_adopt(_picker)
	_picker.lit = _following()


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
