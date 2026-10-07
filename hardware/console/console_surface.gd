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


func _ready() -> void:
	surface_kind = &"console"
	# Compensates the panel's own sixty-degree lay-back, less fifteen, so that on a monitor you
	# are looking slightly DOWN at the desk rather than straight into its face.
	screen_pitch_degrees = 45.0
	if surface_id == &"":
		surface_id = &"console"
	super()


func _rebuild() -> void:
	_clear_built()
	strips.clear()
	master = null

	var indices := DAW.state.track_indices()
	if indices.is_empty():
		return

	var channels_width := indices.size() * ChannelStrip.WIDTH
	var width := channels_width + MasterSection.GAP + MasterSection.WIDTH + PANEL_MARGIN * 2.0

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

	var x := -width * 0.5 + PANEL_MARGIN + ChannelStrip.WIDTH * 0.5
	for index in indices:
		var strip := ChannelStrip.create(index)
		strip.position = Vector3(x, PANEL_MARGIN, 0.0)
		_panel.add_child(strip)
		strips.append(strip)
		x += ChannelStrip.WIDTH

	master = MasterSection.new()
	master.name = "Master"
	master.position = Vector3(x + MasterSection.GAP + MasterSection.WIDTH * 0.5, PANEL_MARGIN, 0.0)
	_panel.add_child(master)


## The tilted panel, not the desk. The carcass is twice the height of the controls and carries
## nothing; on a monitor it is two thirds of the screen spent on a black box.
func framing_root() -> Node3D:
	return _panel if _panel else self
