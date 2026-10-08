class_name BankSelector
extends Node3D

## The two buttons at the left end of the desk that say which tracks these faders are.
##
## It exists because of a fact about control surfaces that is easy to forget inside a 3D scene:
## a protocol streams a BANK of tracks, not a project. Reaper's bank is 64 wide, so a 90-track
## session arrives as tracks 1..64 and the rest simply never appear. Nothing errors, nothing is
## logged, and the desk looks like a complete desk for a smaller session than the one that is
## open -- which is the worst shape a missing feature can take.
##
## So the caption is not decoration. "17-32 OF 90" is the whole point; the buttons are what you
## do about it.
##
## Built only when there is more project than bank. A session that fits needs no bank controls,
## and a desk carrying two dead buttons invites the question of what they are for.

const WIDTH := 0.040

signal bank_requested(offset: int)

var bank_offset := 0
var bank_size := 64
var project_count := -1
## How many tracks are actually in the cache behind this desk.
##
## Separate from bank_size, and the display reads from THIS. bank_size is what was asked of the
## protocol; shown_count is what came back, and on the last bank of a project they differ. They
## can also differ for duller reasons -- a bank still filling, a backend that caps lower than it
## was asked -- and in every one of those cases the number a person can count on the desk is
## shown_count. A caption contradicted by the faders in front of it is worth less than none.
var shown_count := -1

var _prev: PanelButton
var _next: PanelButton
var _range_label: Label3D
var _total_label: Label3D
var _window: MeshInstance3D
var _slot_span := 0.0
var _slot_base := 0.0


func _ready() -> void:
	var height := ChannelStrip.HEIGHT

	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(WIDTH - 0.002, height, 0.008)
	plate.mesh = plate_mesh
	plate.position = Vector3(0, height * 0.5, -0.005)
	plate.material_override = Materials.master_plate()
	add_child(plate)

	var caption := _label(14, Vector3(0, height - 0.012, 0.001))
	caption.text = "BANK"
	add_child(caption)

	_range_label = _label(16, Vector3(0, height - 0.040, 0.001))
	add_child(_range_label)

	_total_label = _label(13, Vector3(0, height - 0.056, 0.001))
	_total_label.modulate = Color(0.58, 0.61, 0.66)
	add_child(_total_label)

	# Up is earlier, down is later, matching the way the track list they index runs. A pair
	# labelled left/right would be reversed against the mixer it mirrors.
	_prev = PanelButton.new()
	_prev.led_colour = Color(0.45, 0.68, 0.95)
	_prev.position = Vector3(0, height - 0.082, 0.004)
	_prev.pressed.connect(func(): _step(-1))
	_prev.describe_title = func() -> String: return "BANK  EARLIER TRACKS"
	_prev.describe_value = func(_v: float) -> String: return _range_label.text
	add_child(_prev)

	_next = PanelButton.new()
	_next.led_colour = Color(0.45, 0.68, 0.95)
	_next.position = Vector3(0, height - 0.100, 0.004)
	_next.pressed.connect(func(): _step(1))
	_next.describe_title = func() -> String: return "BANK  LATER TRACKS"
	_next.describe_value = func(_v: float) -> String: return _range_label.text
	add_child(_next)

	_build_position_ladder(height)

	refresh()


## Where this bank sits inside the project, drawn rather than spelled.
##
## The caption already says "17-32 OF 90" and that is the precise answer, but precise is not
## the question you ask of a bank control. The question is "how much further", and reading two
## numbers and dividing them is not how anyone answers it on a desk -- you look at the handle
## and see that you are about a third of the way down. So: a recessed slot the length of the
## project, and a lit block the length of the bank sitting at its offset.
##
## It also fills twenty-five centimetres of panel that was blank. A module with four captions
## crowded into its top inch and nothing below them reads as unfinished, which is a bad thing
## for the one control on the desk that exists to tell you something is missing.
func _build_position_ladder(height: float) -> void:
	_slot_base = 0.022
	_slot_span = height - 0.128 - _slot_base

	var slot := MeshInstance3D.new()
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(0.015, _slot_span, 0.005)
	slot.mesh = slot_mesh
	slot.position = Vector3(0, _slot_base + _slot_span * 0.5, 0.002)
	slot.material_override = Materials.recess()
	add_child(slot)

	# Unit height, scaled in `refresh`, so the bank size can change without rebuilding a mesh.
	_window = MeshInstance3D.new()
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(0.009, 1.0, 0.004)
	_window.mesh = window_mesh
	_window.material_override = Materials.indicator_bar(Color(0.38, 0.60, 0.92))
	add_child(_window)


func refresh() -> void:
	if _range_label == null:
		return
	var last := bank_offset + (shown_count if shown_count >= 0 else bank_size)
	if project_count > 0:
		last = mini(last, project_count)
	_range_label.text = "%d-%d" % [bank_offset + 1, last]
	# "41-48" at full size is wider than the module; fitted, so "1-9" keeps the size it can.
	Lettering.fit(_range_label, WIDTH - 0.004, 64, ConsoleSurface.SMALLEST_FONT)
	_total_label.text = "OF %d" % project_count if project_count > 0 else "OF ?"
	Lettering.fit(_total_label, WIDTH - 0.004, 52, ConsoleSurface.SMALLEST_FONT)
	# Lit means "there is something that way". An unlit bank button at the end of a project is
	# the only thing that tells you that you have reached the end rather than that the button
	# has stopped working.
	_prev.lit = bank_offset > 0
	_next.lit = project_count < 0 or last < project_count

	if _window != null:
		# Unknown project size means the slot cannot say anything honest about proportion, and
		# a full-length block would say the loudest wrong thing available: that this is all of
		# it. Blank is the truthful reading.
		_window.visible = project_count > 0
		if project_count > 0:
			var span := float(maxi(1, last - bank_offset)) / float(project_count)
			var at := float(bank_offset) / float(project_count)
			# A floor on the block, because a twelve-of-ninety window is a tenth of the slot
			# and a tenth of 12cm is a speck that reads as a fault in the panel.
			var tall := maxf(span * _slot_span, 0.012)
			_window.scale = Vector3(1, tall, 1)
			# From the TOP down, because the track list it indexes runs that way and so do the
			# two buttons above it -- up is earlier. Measured from the bottom instead, bank 1
			# of 48 put the lit block at the floor of the slot, which says the opposite of
			# every other indication on the module.
			var down := minf(at * _slot_span, _slot_span - tall)
			_window.position = Vector3(
					0, _slot_base + _slot_span - down - tall * 0.5, 0.005)


func _step(direction: int) -> void:
	var wanted := bank_offset + direction * bank_size
	if wanted < 0:
		return
	if project_count > 0 and wanted >= project_count:
		return
	bank_requested.emit(wanted)


func _label(font_size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size * 4
	l.pixel_size = 0.00018
	l.position = pos
	l.modulate = Color(0.86, 0.88, 0.91)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l
