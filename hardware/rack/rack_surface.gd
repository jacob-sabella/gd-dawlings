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
## The grip on the track window was pulled: the whole track's chain wants a rack of its own,
## standing where it was let go. Whoever placed this rack decides what stands there.
signal track_tear_requested(track: int, at: Vector3)
## A pulled-out rack's FOLD button: put it back into the rack it came out of.
signal fold_requested()

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
## A rack pulled out of the main one for one track: it racks that track and only that track for
## as long as it stands, so it has no window to scroll to another and does not follow Reaper's
## selection, and it has a FOLD button to go back in instead. Set before it enters the tree.
var pinned := false

var _picker: TabletSelector
var _empty_label: Label3D
## The rack's own OUT, on the top rail past the track's colour chip: the racked track as it leaves
## the whole chain (PersonalMix.rack_socket). Each unit has an OUT of its own for a point inside it.
var out_socket: SendSocket
var _units: Array[RackUnit] = []
## The racked chain as it was built: a rebuild is for a change to THIS, not for every plugin
## update anywhere in the project.
var _built_chain := ""


func _ready() -> void:
	surface_kind = &"rack"
	if surface_id == &"":
		surface_id = &"rack"
	super()
	DAW.track_changed.connect(_on_track_changed)
	if pinned:
		DAW.tracks_renumbered.connect(_on_tracks_renumbered)


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
	if pinned or DAW.state.tracks.has(track_index) or tracks.is_empty():
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
	if pinned:
		if index == track_index and field in [&"name", &"colour"]:
			mark_dirty()
		return
	if field == &"selected" and DAW.state.tracks.has(index) and DAW.state.track(index).selected:
		show_track(index)
	elif field == &"colour" and index == track_index:
		mark_dirty()
	elif field in [&"name", &"selected"]:
		_once_this_frame(_refresh_picker)


func _refresh_picker() -> void:
	if _picker != null:
		_picker.refresh()
		_picker.lit = _following()


## A pulled-out rack's track moved: followed by number, as a tablet follows its plugin's. -1
## when it is gone, and the rack stands empty until whoever placed it folds it.
func _on_tracks_renumbered(map: Dictionary) -> void:
	track_index = int(map.get(track_index, -1))
	mark_dirty()


## Whether the rack is showing the track Reaper has selected.
func _following() -> bool:
	return DAW.state.tracks.has(track_index) and DAW.state.track(track_index).selected


## Every track, for the window: the ones with no plugins too, or there is no way to rack an
## empty track to put its first plugin on it -- the window is the only way to choose a track on
## the built-in engine, which has no Reaper selection to follow.
func _rackable() -> Array:
	var out: Array = []
	for i in DAW.state.track_indices():
		var t := DAW.state.track(i)
		var count := t.plugins().size()
		out.append([i, "%s   ·   %s" % [t.display_name().to_upper(),
				"%d PLUGIN%s" % [count, "" if count == 1 else "S"] if count > 0 else "NO PLUGINS"]])
	return out


func _rebuild() -> void:
	_clear_built()
	_picker = null
	_empty_label = null
	out_socket = null
	_units.clear()
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
			_units.append(unit)
			# Filled from the top down so that the first track's FX are at eye level rather than
			# at the floor: a 20-unit rack read bottom-up puts channel 1 at your ankles.
			unit.position = Vector3(0, per_bay * unit_height - (row + 0.5) * unit_height, 0)
			bay_node.add_child(unit)

		_blank_from(bay_node, maxi(slots.size() - bay * per_bay, 0), per_bay, unit_height)

	# After every unit has claimed its slots: a bank is sized once.
	for bank in banks:
		if bank != null:
			bank.commit()
	if pinned:
		_build_name_strip(per_bay * unit_height)
	else:
		_build_picker(per_bay * unit_height)
		_build_track_grip(per_bay * unit_height)
	_build_adder(per_bay * unit_height)
	_build_find(per_bay * unit_height)
	_build_out(per_bay * unit_height)
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
	var knobs := MeshBank.of(Knob.MESH_PATH, Materials.knob_cap(),
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
	_picker.hint_text = "scroll to rack another track  ·  selecting a track in Reaper racks it"
	_picker.describe_title = func() -> String: return "RACK"
	_picker.describe_value = func(_v: float) -> String: return _picker.words()
	_picker.chosen.connect(show_track)
	_adopt(_picker)
	_picker.lit = _following()
	_adopt(_colour_chip(Vector3(PICKER_SIZE.x * 0.5 * PICKER_SCALE + 0.014, bay_height + PICKER_RISE, 0.003)))


## A square of the racked track's colour at the end of its window or name strip.
func _colour_chip(at: Vector3) -> MeshInstance3D:
	var chip := MeshInstance3D.new()
	chip.name = "TrackChip"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.016, PICKER_SIZE.y * PICKER_SCALE)
	chip.mesh = quad
	chip.position = at
	chip.material_override = Materials.track_stripe(DAW.state.track(track_index).shown_colour())
	chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return chip


## The grip at the left end of the track window: pull it and the whole track's chain comes out
## on a rack of its own (`track_tear_requested`), the way a unit's grip pulls one plugin out onto
## a tablet. Click as well as drag, for the same reason as the unit's.
func _build_track_grip(bay_height: float) -> void:
	var grip := TearTab.new()
	grip.name = "TrackGrip"
	grip.size = Vector2(0.05, PICKER_SIZE.y * PICKER_SCALE)
	grip.ghost_size = Vector2(RackUnit.RACK_WIDTH + 0.044, BAY_HEIGHT * 0.6)
	grip.ghost_colour = Color(0.95, 0.75, 0.35)
	grip.hint_text = "drag it off, or click, to pull this whole track out on a rack of its own"
	grip.describe_title = func() -> String: return "RACK  PULL OUT TRACK"
	grip.position = Vector3(-PICKER_SIZE.x * 0.5 * PICKER_SCALE - 0.05 - 0.004, bay_height + PICKER_RISE, 0.002)
	grip.torn.connect(func(at: Vector3) -> void: track_tear_requested.emit(track_index, at))
	_adopt(grip)


## A pulled-out rack's label where the main rack's track window is: the track's name, which
## does not scroll, and the FOLD button beside it.
func _build_name_strip(bay_height: float) -> void:
	var strip := Label3D.new()
	strip.name = "TrackName"
	var t := DAW.state.track(track_index)
	var count := t.plugins().size()
	strip.text = "%s   ·   %s" % [t.display_name().to_upper(),
			"%d PLUGIN%s" % [count, "" if count == 1 else "S"] if count > 0 else "NO PLUGINS"]
	strip.font_size = 44
	strip.pixel_size = 0.0002 * PICKER_SCALE
	# In the track's own colour: this rack is that track.
	strip.modulate = t.shown_colour().lightened(0.15)
	strip.position = Vector3(0, bay_height + PICKER_RISE, 0.004)
	Lettering.range_to_legibility(strip)
	_adopt(strip)
	Lettering.fit(strip, PICKER_SIZE.x * PICKER_SCALE, 44)
	_adopt(_colour_chip(Vector3(PICKER_SIZE.x * 0.5 * PICKER_SCALE + 0.014, bay_height + PICKER_RISE, 0.003)))

	var fold := PanelButton.new()
	fold.name = "FoldButton"
	fold.led_colour = Color(0.95, 0.75, 0.35)
	fold.scale = Vector3(1.5, 1.5, 1.5)
	fold.position = Vector3(-PICKER_SIZE.x * 0.5 * PICKER_SCALE - 0.03,
			bay_height + PICKER_RISE + PICKER_SIZE.y * PICKER_SCALE * 1.4, 0.004)
	fold.lit = true
	fold.pressed.connect(func() -> void: fold_requested.emit())
	fold.describe_title = func() -> String: return "RACK  FOLD BACK IN"
	fold.describe_value = func(_v: float) -> String: return "put this track back in the main rack"
	_adopt(fold)
	var caption := Label3D.new()
	caption.name = "FoldCaption"
	caption.text = "FOLD"
	caption.font_size = 18 * 4
	caption.pixel_size = 0.000055
	caption.modulate = Color(0.78, 0.80, 0.84)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.position = fold.position + Vector3(0, -0.014, 0.0012)
	Lettering.range_to_legibility(caption)
	_adopt(caption)


## The window over the track's that adds a plugin to the racked chain: scroll through what the
## DAW offers (MixState.fx_choices), click to put it at the end. Over the rack rather than under
## it, where the desk is in the way from the seat.
func _build_adder(bay_height: float) -> void:
	if DAW.state.fx_choices.is_empty():
		return
	var adder := TabletSelector.new()
	adder.name = "PluginAdder"
	adder.size = PICKER_SIZE
	adder.scale = Vector3.ONE * PICKER_SCALE
	adder.position = Vector3(0, bay_height + PICKER_RISE + PICKER_SIZE.y * PICKER_SCALE * 1.4, 0.002)
	adder.options = func() -> Array:
		var out: Array = []
		for i in DAW.state.fx_choices.size():
			out.append([i, "ADD  ·  %s" % str(DAW.state.fx_choices[i][1]).to_upper()])
		return out
	adder.choice = 0
	adder.hint_text = "scroll to choose a plugin  ·  click to add it to this track"
	adder.describe_title = func() -> String: return "RACK  ADD PLUGIN"
	adder.describe_value = func(_v: float) -> String: return adder.words()
	adder.pressed.connect(_add_plugin)
	_adopt(adder)


func _add_plugin(choice: int) -> void:
	if DAW.state.tracks.has(track_index) and choice >= 0 and choice < DAW.state.fx_choices.size():
		DAW.add_fx(track_index, str(DAW.state.fx_choices[choice][0]))


## A searchable alternative to the wheel above, beside it: scrolling one at a time is fine for
## the built-in engine's own handful of kinds, and stops being fine once a live Reaper
## connection has turned that handful into however many VSTs happen to be installed
## (2026-10-11: "i have so many plugins there needs to be a more elegant way to choose a
## plugin"). PluginPicker is a 2D overlay (CanvasLayer), the same as NamePrompt, so it is
## desktop-only -- built only outside XR, where the wheel is left as the only way in, same as
## NamePrompt gives way to TypingPad there.
func _build_find(bay_height: float) -> void:
	if DAW.state.fx_choices.size() <= 1 or (is_inside_tree() and get_viewport().use_xr):
		return
	var find_button := PanelButton.new()
	find_button.name = "FindPlugin"
	find_button.led_colour = Color(0.4, 0.75, 0.95)
	find_button.scale = Vector3(1.5, 1.5, 1.5)
	find_button.position = Vector3(PICKER_SIZE.x * 0.5 * PICKER_SCALE + 0.03,
			bay_height + PICKER_RISE + PICKER_SIZE.y * PICKER_SCALE * 1.4, 0.004)
	find_button.lit = true
	find_button.pressed.connect(_open_plugin_search)
	find_button.describe_title = func() -> String: return "RACK  FIND A PLUGIN"
	find_button.describe_value = func(_v: float) -> String: return "search by name"
	_adopt(find_button)
	var caption := Label3D.new()
	caption.name = "FindPluginCaption"
	caption.text = "FIND"
	caption.font_size = 18 * 4
	caption.pixel_size = 0.000055
	caption.modulate = Color(0.78, 0.80, 0.84)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.position = find_button.position + Vector3(0, -0.014, 0.0012)
	Lettering.range_to_legibility(caption)
	_adopt(caption)


## OUT on the top rail, right of the colour chip: anyone's wireless plug goes in it to hear the
## track as the whole rack leaves it.
func _build_out(bay_height: float) -> void:
	out_socket = SendSocket.new()
	out_socket.name = "RackOut"
	out_socket.source = PersonalMix.rack_socket(track_index)
	out_socket.kind = "OUT"
	out_socket.label = "%s RACK" % DAW.state.track(track_index).display_name().to_upper()
	out_socket.position = Vector3(PICKER_SIZE.x * 0.5 * PICKER_SCALE + 0.036, bay_height + PICKER_RISE, 0.002)
	_adopt(out_socket)
	# On a dark plate of its own: the rail glows in the track's colour, which an amber word on it
	# disappears into.
	var plate := MeshInstance3D.new()
	plate.name = "RackOutPlate"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.044, PICKER_SIZE.y * PICKER_SCALE)
	plate.mesh = quad
	plate.material_override = Materials.cap_plastic(Color(0.05, 0.05, 0.06))
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = out_socket.position + Vector3(0.012, 0, -0.0005)
	_adopt(plate)
	var caption := Label3D.new()
	caption.name = "RackOutCaption"
	caption.text = "OUT"
	caption.font_size = 40
	caption.pixel_size = 0.00019
	caption.modulate = SendSocket.LAMP
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.position = out_socket.position + Vector3(0.010, 0, 0.001)
	Lettering.range_to_legibility(caption)
	_adopt(caption)


## Every OUT on this rack: its own, and each unit's, for the studio to put plugs in.
func out_sockets() -> Array[SendSocket]:
	var out: Array[SendSocket] = []
	if out_socket != null and is_instance_valid(out_socket):
		out.append(out_socket)
	for u in _units:
		if is_instance_valid(u) and u.out_socket != null:
			out.append(u.out_socket)
	return out


func _open_plugin_search() -> void:
	if not DAW.state.tracks.has(track_index):
		return
	var picker := PluginPicker.ask(self, "Add a plugin to %s" % DAW.state.track(track_index).name,
			DAW.state.fx_choices)
	picker.chosen.connect(_add_plugin_by_id)


func _add_plugin_by_id(id: String) -> void:
	if DAW.state.tracks.has(track_index):
		DAW.add_fx(track_index, id)


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


## The frame glows in the racked track's colour, as the venue shows it: the whole bracket says
## which track this is, from anywhere in the room. Plain furniture with no track to rack.
func _frame_material() -> Material:
	if DAW.state.tracks.has(track_index):
		return Materials.track_glow(DAW.state.track(track_index).shown_colour())
	return Materials.furniture()


func _build_frame(parent: Node3D, inner_height: float) -> void:
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.022, inner_height + 0.05, RAIL_DEPTH)
		post.mesh = post_mesh
		post.position = Vector3(side * (RackUnit.RACK_WIDTH * 0.5 + 0.011), inner_height * 0.5,
				-RAIL_DEPTH * 0.5 - FRAME_SETBACK)
		post.material_override = _frame_material()
		parent.add_child(post)

	for y in [0.0, inner_height + 0.025]:
		var cross := MeshInstance3D.new()
		var cross_mesh := BoxMesh.new()
		cross_mesh.size = Vector3(RackUnit.RACK_WIDTH + 0.040, 0.022, RAIL_DEPTH - 0.004)
		cross.mesh = cross_mesh
		cross.position = Vector3(0, y, -RAIL_DEPTH * 0.5 - FRAME_SETBACK)
		cross.material_override = _frame_material()
		parent.add_child(cross)
