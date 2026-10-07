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


func _rebuild() -> void:
	_clear_built()
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

	_panel = Node3D.new()
	_panel.rotation_degrees = Vector3(-PANEL_TILT, 0, 0)
	_adopt(_panel)

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

	var x := -width * 0.5 + PANEL_MARGIN
	if banking:
		bank = BankSelector.new()
		bank.name = "Bank"
		bank.bank_offset = DAW.state.bank_offset
		bank.bank_size = DAW.state.bank_size
		bank.project_count = DAW.state.project_track_count
		bank.position = Vector3(x + BankSelector.WIDTH * 0.5, PANEL_MARGIN, 0.0)
		bank.bank_requested.connect(_request_bank)
		_panel.add_child(bank)
		x += bank_width

	x += ChannelStrip.WIDTH * 0.5
	for index in indices:
		if breaks.has(index):
			# A rule in the gap, not just the gap. On a desk tilted away from you a plain space
			# reads as a missing strip; a line reads as a division, which is what it is.
			_group_rule(x - ChannelStrip.WIDTH * 0.5 + GROUP_GAP * 0.5)
			x += GROUP_GAP
		var strip := ChannelStrip.create(index)
		strip.position = Vector3(x, PANEL_MARGIN, 0.0)
		_panel.add_child(strip)
		strips.append(strip)
		x += ChannelStrip.WIDTH

	master = MasterSection.new()
	master.name = "Master"
	master.position = Vector3(x + MasterSection.GAP + MasterSection.WIDTH * 0.5, PANEL_MARGIN, 0.0)
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
	rule.position = Vector3(at_x, PANEL_MARGIN + ChannelStrip.HEIGHT * 0.5, 0.0008)
	rule.material_override = Materials.legend()
	_panel.add_child(rule)


## The tilted panel, not the desk. The carcass is twice the height of the controls and carries
## nothing; on a monitor it is two thirds of the screen spent on a black box.
func framing_root() -> Node3D:
	return _panel if _panel else self
