class_name ConsoleSurface
extends Surface

## The mixing desk: a strip per Reaper track, on a tilted panel, in a chassis.
##
## Rebuilt when the track count changes and at no other time. The panel geometry is sized from
## the strip count rather than being a fixed model, because a 6-track project and a 48-track one
## are different pieces of furniture -- and in ROOM mode a 48-track desk is 2.6m wide, which is
## a fact about the room that the person placing it needs to see honestly rather than scaled to
## fit.

## Degrees off vertical. 60 is a desk you lean over rather than a panel you face: it keeps the
## faders within reach of a standing hand and the legends readable from above.
const PANEL_TILT := 60.0
const PANEL_MARGIN := 0.03

var _panel: Node3D
var strips: Array[ChannelStrip] = []
var master: MasterSection
var bank: BankSelector

## A bank change asked for while a hand is on a control, held until the hand lets go.
##
## THE ONE RULE BANKING MUST NOT BREAK: a strip may never change which track it means while
## someone is holding its fader. Applying immediately would rebuild the desk out from under a
## grab -- the fader is freed mid-drag, the hand is left holding nothing, and the last value
## written went to a track that is no longer there. Worse, nothing about it looks like an error.
var _pending_bank := -1


func _ready() -> void:
	surface_kind = &"console"
	# Compensates the panel's own sixty-degree lay-back, less fifteen, so that on a monitor you
	# are looking slightly DOWN at the desk rather than straight into its face.
	screen_pitch_degrees = 45.0
	if surface_id == &"":
		surface_id = &"console"
	super()
	DAW.state.bank_changed.connect(_on_bank_changed)


func _process(delta: float) -> void:
	super(delta)
	if _pending_bank >= 0 and not _anything_held():
		var wanted := _pending_bank
		_pending_bank = -1
		DAW.set_track_bank(wanted)


func _on_bank_changed() -> void:
	mark_dirty()


## Asked for by the bank buttons. Deferred rather than refused: refusing would mean a press
## that did nothing, and the hand on the fader is usually the other hand.
func _request_bank(offset: int) -> void:
	if _anything_held():
		_pending_bank = offset
		return
	DAW.set_track_bank(offset)


func _anything_held() -> bool:
	for node in find_children("*", "ControlAffordance", true, false):
		if (node as ControlAffordance).is_held():
			return true
	return false


## The width past which a flat desk stops being a desk and starts being a wall.
##
## Below it a console is a thing you stand at; above it the far end is further away than the
## near end by more than the near end is away at all, so the lettering goes glancing and the
## reach goes impossible. 1.6m is about two arm-spans of panel, which is where a real desk
## stops too -- beyond that, real control rooms angle the wings in.
const WRAP_MIN_WIDTH := 1.6

## Vertical space between two rows of a wrapped desk. A seam, not a gap: wide enough that the
## row below is a different row and not a longer strip, narrow enough that a glance crosses it.
const ROW_GAP := 0.012

## The smallest lettering anywhere on the desk, and therefore how far the desk may be pushed
## before it stops being readable.
##
## Declared rather than measured, because the radius has to be chosen BEFORE a single label
## exists -- the radius decides the layout and the layout builds the labels. It can be declared
## safely because every label on this desk is built at the same pixel size and the smallest
## font any of them asks for is 8, and there is a test that fails if that stops being true.
const SMALLEST_CAP := 8.0 * 4.0 * 0.00018

## Arc length of one row, and how many rows. Zero and one when the desk is flat.
var _row_span := 0.0
var _rows := 1
## Half the unrolled width, kept because _seat is given x measured from the desk's centre.
var _half_width := 0.0

var _wrap := 0.0


## Bent around the viewer when it is wide enough to need it and presented at the body.
##
## Not when it is standing in the room: a curved desk you walk up to has its curve centred on
## nobody, which is worse than flat. The bend only means anything when the centre of curvature
## is an actual eye, and the only time this surface knows that is when it has been summoned.
func wrap_radius() -> float:
	return _wrap


func _rebuild() -> void:
	_clear_built()
	_wrap = 0.0
	_row_span = 0.0
	_rows = 1
	_half_width = 0.0
	strips.clear()
	master = null
	bank = null

	var indices := DAW.state.track_indices()
	if indices.is_empty():
		return

	# The bank module is only built when there is more project than bank -- a session that fits
	# on the desk needs no bank controls, and two dead buttons invite the question of what they
	# are for. See hardware/console/bank_selector.gd.
	var banking := DAW.can(DAWBackend.Capability.TRACK_BANKING) and DAW.state.has_more_banks()
	var bank_width := (BankSelector.WIDTH + MasterSection.GAP) if banking else 0.0

	# Folder breaks are measured BEFORE the panel is sized, because they make the desk wider.
	# Sizing the plate first and then inserting gaps is how strips end up hanging off the end.
	var breaks := _group_breaks(DAW.state, indices)
	var channels_width := indices.size() * ChannelStrip.WIDTH + breaks.size() * GROUP_GAP
	var width := bank_width + channels_width + MasterSection.GAP + MasterSection.WIDTH \
			+ PANEL_MARGIN * 2.0

	_half_width = width * 0.5

	if compact and width >= WRAP_MIN_WIDTH:
		var erg := Ergonomics.current
		var pitch := _row_pitch()
		_wrap = erg.wrap_radius_for(width, pitch, ChannelStrip.WIDTH, SMALLEST_CAP)
		_rows = erg.wrap_rows(_wrap, pitch)
		_row_span = floor(erg.wrap_span_at(_wrap, -float(_rows - 1) * pitch * 0.5, true)
				/ ChannelStrip.WIDTH) * ChannelStrip.WIDTH
		# Reported, not hidden. The desk is drawn either way -- a mixer that refuses to appear
		# is worse than one you have to turn your head for -- but a session this wide has
		# outgrown the body in front of it and the honest answer is a narrower bank.
		if _row_span * float(_rows) < width:
			push_warning(("console: %.2fm of desk into %.2fm of reachable arc (%d rows at "
					+ "%.2fm); the ends are outside the head-turn. Bank narrower.")
					% [width, _row_span * float(_rows), _rows, _wrap])

	_panel = Node3D.new()
	# A wrapped desk is tilted by the RIG, about the eye, where the tilt costs no translation
	# and keeps every strip equidistant. Tilting the panel here as well would rotate the arc
	# about its own chord and throw the ends out of reach again.
	_panel.rotation_degrees = Vector3(0 if _wrap > 0.0 else -PANEL_TILT, 0, 0)
	_adopt(_panel)

	# Skipped when wrapped. A single 5-metre box cannot follow an arc, and the strips carry
	# their own backing plates -- which is why the bend is possible at all.
	if _wrap <= 0.0:
		_build_slabs(width)


	var x := -width * 0.5 + PANEL_MARGIN
	if banking:
		bank = BankSelector.new()
		bank.name = "Bank"
		bank.bank_offset = DAW.state.bank_offset
		bank.bank_size = DAW.state.bank_size
		bank.project_count = DAW.state.project_track_count
		bank.shown_count = DAW.state.tracks.size()
		bank.transform = _seat(x + BankSelector.WIDTH * 0.5, PANEL_MARGIN, 0.0)
		bank.bank_requested.connect(_request_bank)
		_panel.add_child(bank)
		x += bank_width

	# Built BEFORE the strips and parented to the panel, because a button claims its slot by
	# converting its own world transform into the bank's -- so the bank has to be in the tree,
	# and in its final place, before the first strip exists.
	var body_bank := MeshBank.parts(PanelButton.BODY_SIZE, PanelButton.body_material())
	body_bank.name = "ButtonBodies"
	_panel.add_child(body_bank)
	var lamp_bank := MeshBank.lamps(PanelButton.LAMP_SIZE)
	lamp_bank.name = "ButtonLamps"
	_panel.add_child(lamp_bank)
	var plate_bank := MeshBank.parts(ChannelStrip.PLATE_SIZE, Materials.chassis())
	plate_bank.name = "StripPlates"
	_panel.add_child(plate_bank)
	var slot_bank := MeshBank.parts(Fader.SLOT_SIZE, Materials.recess())
	slot_bank.name = "FaderSlots"
	_panel.add_child(slot_bank)
	# The two authored parts. Null when the asset will not resolve, in which case every knob
	# and cap falls back to building its own mesh and the desk still works -- same contract as
	# the patchbay's jacks.
	var knob_bank := MeshBank.of(
		Knob.MESH_PATH,
		Materials.cap_plastic(Color(0.14, 0.15, 0.17)),
		{"indicator": Materials.legend()},
	)
	if knob_bank != null:
		knob_bank.name = "PanKnobs"
		_panel.add_child(knob_bank)
	var cap_bank := MeshBank.of(
		Fader.MESH_PATH,
		Materials.cap_plastic(Color(0.17, 0.18, 0.2)),
		{"indicator": Materials.legend()},
	)
	if cap_bank != null:
		cap_bank.name = "FaderCaps"
		_panel.add_child(cap_bank)
	# Unshaded like the lamps, because a colour chip is a lit patch and not a painted one -- it
	# has to stay findable on a desk of 32 identical strips in a dim room.
	var chip_bank := MeshBank.lamps(ChannelStrip.CHIP_SIZE)
	chip_bank.name = "ColourChips"
	_panel.add_child(chip_bank)

	x += ChannelStrip.WIDTH * 0.5
	for index in indices:
		if breaks.has(index):
			# A rule in the gap, not just the gap. On a desk tilted away from you a plain space
			# reads as a missing strip; a line reads as a division, which is what it is.
			_group_rule(x - ChannelStrip.WIDTH * 0.5 + GROUP_GAP * 0.5)
			x += GROUP_GAP
		var strip := ChannelStrip.create(index)
		strip.body_bank = body_bank
		strip.lamp_bank = lamp_bank
		strip.plate_bank = plate_bank
		strip.chip_bank = chip_bank
		strip.slot_bank = slot_bank
		strip.knob_bank = knob_bank
		strip.cap_bank = cap_bank
		strip.transform = _seat(x, PANEL_MARGIN, 0.0)
		_panel.add_child(strip)
		strips.append(strip)
		x += ChannelStrip.WIDTH

	# After every claim and before anything can light up. A MultiMesh has to know how many
	# instances it holds before it can hold any, so this is the moment the buffer is sized.
	body_bank.commit()
	lamp_bank.commit()
	plate_bank.commit()
	slot_bank.commit()
	chip_bank.commit()
	if knob_bank != null:
		knob_bank.commit()
	if cap_bank != null:
		cap_bank.commit()

	master = MasterSection.new()
	master.name = "Master"
	master.transform = _seat(x + MasterSection.GAP + MasterSection.WIDTH * 0.5, PANEL_MARGIN, 0.0)
	_panel.add_child(master)


## Gap inserted at a folder boundary. Narrow on purpose: this is a seam between sections of one
## desk, not a gap between two desks, and anything wider starts to read as the latter.
const GROUP_GAP := 0.013


## Which of `indices` begin a new folder group, as a Dictionary used as a set.
##
## Returned rather than recomputed per strip because `folder_level` is a running sum over every
## track before it -- asking per strip makes laying out a 90-track desk quadratic for an answer
## that does not change during the layout.
##
## The FIRST strip is never a break. It begins a group, but there is nothing before it to be
## divided from, and a rule hanging off the left edge of the panel is just a scratch.
## Takes the state rather than reaching for the DAW autoload, which is not only testable but
## correct: this is arithmetic over a project, and a static helper that reads a global can only
## ever describe the one project that happens to be open.
static func _group_breaks(state: MixState, indices: Array) -> Dictionary:
	var out := {}
	var level := 0
	var previous := 0
	for i in indices.size():
		var index: int = indices[i]
		var depth: int = state.track(index).folder_depth
		if i > 0 and (depth > 0 or level < previous):
			out[index] = true
		previous = level
		level = maxi(level + depth, 0)
	return out


func _group_rule(at_x: float) -> void:
	var rule := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.0014, ChannelStrip.HEIGHT * 0.92, 0.0012)
	rule.mesh = mesh
	rule.transform = _seat(at_x, PANEL_MARGIN + ChannelStrip.HEIGHT * 0.5, 0.0008)
	rule.material_override = Materials.legend()
	_panel.add_child(rule)


## The tilted panel, not the desk. The carcass is twice the height of the controls and carries
## nothing; on a monitor it is two thirds of the screen spent on a black box.
func framing_root() -> Node3D:
	return _panel if _panel else self


## Where one module sits on the panel: straight along x when flat, bent onto the arc when not.
##
## Applied HERE, at the moment a module is positioned, and not as a pass over the finished
## panel. The MeshBanks read each instance's transform off the node as it enters the tree, so a
## bend applied afterwards would move the strips and leave every banked knob, cap and lamp
## standing in the flat positions they were claimed at -- a console of floating controls next
## to the console they belong to.
##
## The arc's centre is at local (0, 0, radius), which is where the eye goes. Each module is
## turned by -theta so it faces that centre rather than staying square to the room; without the
## turn the strips stay parallel and the far ones are seen edge-on, which is most of what makes
## a wide flat desk unreadable in the first place.
func _seat(x: float, y: float, z: float) -> Transform3D:
	if _wrap <= 0.0:
		return Transform3D(Basis.IDENTITY, Vector3(x, y, z))
	# `x` arrives as one long ruler across a desk that no longer exists. Cut it into rows first,
	# then bend what is left. The row runs left to right and the rows run bottom to top, because
	# that is the order the strips are in and reading order is the only thing that makes a
	# wrapped desk findable: track 40 is where track 40 would be if you unrolled it.
	var along := x + _half_width
	var row := 0
	if _row_span > 0.0:
		row = clampi(int(floor(along / _row_span)), 0, _rows - 1)
		along -= float(row) * _row_span
	var theta := (along - _row_span * 0.5) / _wrap
	var lift := float(row) * _row_pitch()
	# Tilted, exactly as the flat desk is tilted, and leaving this out is what made the first
	# wrapped console unbearable: upright strips at face height on a closed circle are not a
	# desk you lean over, they are a cell you stand in. The tilt is also what makes the rows
	# affordable -- a panel laid back sixty degrees is half as tall in your field of view, so
	# the tiers stack inside the same glance.
	var lay := Basis(Vector3.RIGHT, -deg_to_rad(PANEL_TILT))
	return Transform3D(Basis(Vector3.UP, -theta) * lay, Vector3(
			sin(theta) * (_wrap - z), y + lift, _wrap - cos(theta) * (_wrap - z)))


## How much height one tier of a wrapped desk costs. The panel's own height, foreshortened by
## its lay-back, plus a seam.
func _row_pitch() -> float:
	return ChannelStrip.HEIGHT * cos(deg_to_rad(PANEL_TILT)) + ROW_GAP


## The three full-width slabs: the panel backing, the desk body and the armrest.
##
## Built only for a flat desk. None of them can follow an arc -- a single 5-metre box bent
## round a viewer is just a box at a jaunty angle -- and a wrapped console has no use for them
## anyway: it is summoned, so it is not furniture, and the strips bring their own backing.
func _build_slabs(width: float) -> void:
	var panel_plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(width, ChannelStrip.HEIGHT + PANEL_MARGIN * 2.0, 0.018)
	panel_plate.mesh = plate_mesh
	panel_plate.position = Vector3(0, ChannelStrip.HEIGHT * 0.5, -0.014)
	panel_plate.material_override = Materials.chassis()
	_panel.add_child(panel_plate)

	# The desk body, which is doing more than decoration: in ROOM mode it is what tells a person
	# in passthrough that they must not walk through this spot.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(width, 0.62, 0.34)
	body.mesh = body_mesh
	body.position = Vector3(0, -0.31, -0.10)
	body.material_override = Materials.chassis()
	_adopt(body)

	# Armrest along the near edge. Real desks have one, and more usefully it gives a hand in AR
	# something to rest against while reaching for a fader -- without it, a 100mm throw in mid-air
	# is done entirely by unsupported arm.
	var rest := MeshInstance3D.new()
	var rest_mesh := BoxMesh.new()
	rest_mesh.size = Vector3(width, 0.022, 0.07)
	rest.mesh = rest_mesh
	rest.position = Vector3(0, 0.005, 0.055)
	rest.material_override = Materials.brushed_metal()
	_adopt(rest)
