class_name ChannelStrip
extends Node3D

## One channel of the console: name, pan, rec/mute/solo, fader, meter.
##
## Built for a track index and bound to it for life. A rebuild of the console replaces strips
## wholesale rather than re-pointing them, because a strip that changes which track it means
## while someone is holding its fader writes the new track's volume from the old track's hand
## position -- a bug that only appears when a bank scrolls, which is exactly when nobody is
## watching the fader they just let go of.

const WIDTH := 0.055
const HEIGHT := 0.30

var track_index: int = 0

var _fader: Fader
var _pan: Knob
var _mute: PanelButton
var _solo: PanelButton
var _rec: PanelButton
var _name_label: Label3D
var _db_label: Label3D

## Where this strip's repeated geometry gets drawn, if the console gave it somewhere. See
## hardware/mesh_bank.gd -- ninety strips of three buttons is 540 objects otherwise. All seven
## are optional and a strip with none of them builds everything itself, which is what keeps a
## strip usable outside a console surface.
##
## The last two hold the only MOVING geometry on the desk: a knob turns and a cap slides, so
## their slots are rewritten on every value change rather than claimed once. That is the whole
## difference between them and the other five.
var body_bank: MeshBank
var lamp_bank: MeshBank
var plate_bank: MeshBank
var chip_bank: MeshBank
var slot_bank: MeshBank
var knob_bank: MeshBank
var cap_bank: MeshBank

const PLATE_SIZE := Vector3(WIDTH - 0.002, HEIGHT, 0.008)
const PLATE_OFFSET := Vector3(0, HEIGHT * 0.5, -0.005)
const CHIP_SIZE := Vector3(WIDTH - 0.008, 0.004, 0.001)
const CHIP_OFFSET := Vector3(0, HEIGHT - 0.022, 0.0005)

## Slot in `chip_bank`, or -1 when the chip is a mesh of its own. The plate needs no slot kept:
## nothing ever changes it after it is placed.
var _chip_slot := -1


static func create(index: int) -> ChannelStrip:
	var s := ChannelStrip.new()
	s.track_index = index
	s.name = "Strip%d" % index
	return s


func _ready() -> void:
	_claim_or_build(plate_bank, PLATE_SIZE, PLATE_OFFSET, Materials.chassis(), Color.WHITE, "")

	_name_label = _make_label(14, Vector3(0, HEIGHT - 0.012, 0.001))
	add_child(_name_label)

	# A colour chip carrying Reaper's own track colour. It is how you find the kick on a desk of
	# 32 identical strips, and it is the one piece of the DAW's visual language worth keeping.
	_chip_slot = _claim_or_build(
		chip_bank, CHIP_SIZE, CHIP_OFFSET, null, Color.WHITE, "ColourChip")

	_pan = Knob.new()
	_pan.body_bank = knob_bank
	_pan.position = Vector3(0, HEIGHT - 0.048, 0.004)
	_pan.turned.connect(func(v: float): DAW.set_track_pan(track_index, v))
	_pan.describe_title = func() -> String: return _caption_for("PAN")
	_pan.describe_value = Knob.pan_text
	add_child(_pan)

	_rec = PanelButton.new()
	_rec.body_bank = body_bank
	_rec.lamp_bank = lamp_bank
	_rec.led_colour = Ergonomics.current.signal_colour(&"record")
	_rec.lamp_scale = Vector2(1.0, 1.0)
	_rec.position = Vector3(0, HEIGHT - 0.077, 0.004)
	_rec.describe_title = func() -> String: return _caption_for("RECORD ARM")
	_rec.pressed.connect(func(): DAW.set_track_rec_arm(track_index, not _state().rec_arm))
	add_child(_rec)

	_solo = PanelButton.new()
	_solo.body_bank = body_bank
	_solo.lamp_bank = lamp_bank
	_solo.led_colour = Ergonomics.current.signal_colour(&"solo")
	_solo.lamp_scale = Vector2(0.38, 1.0)
	_solo.position = Vector3(0, HEIGHT - 0.095, 0.004)
	_solo.describe_title = func() -> String: return _caption_for("SOLO")
	_solo.pressed.connect(func(): DAW.set_track_solo(track_index, not _state().solo))
	add_child(_solo)

	_mute = PanelButton.new()
	_mute.body_bank = body_bank
	_mute.lamp_bank = lamp_bank
	_mute.led_colour = Ergonomics.current.signal_colour(&"mute")
	_mute.lamp_scale = Vector2(1.0, 0.40)
	_mute.position = Vector3(0, HEIGHT - 0.113, 0.004)
	_mute.describe_title = func() -> String: return _caption_for("MUTE")
	_mute.pressed.connect(func(): DAW.set_track_mute(track_index, not _state().mute))
	add_child(_mute)

	_fader = Fader.new()
	_fader.track_index = track_index
	_fader.slot_bank = slot_bank
	_fader.cap_bank = cap_bank
	_fader.position = Vector3(-0.011, 0.040, 0.004)
	_fader.describe_title = func() -> String: return _caption_for("LEVEL")
	add_child(_fader)

	var meter := VUMeter.new()
	meter.track_index = track_index
	meter.position = Vector3(0.016, 0.042, 0.002)
	add_child(meter)

	_db_label = _make_label(11, Vector3(0, 0.022, 0.001))
	add_child(_db_label)

	DAW.state.track_changed.connect(_on_track_changed)
	refresh()


func _make_label(font_size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size * 4
	# pixel_size x font_size is the cap height in metres. At 0.00018 a 56px font is ~10mm, which
	# is legible across a room in AR and still sharp with a face against the panel.
	l.pixel_size = 0.00018
	l.position = pos
	l.modulate = Color(0.86, 0.87, 0.89)
	l.outline_size = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.no_depth_test = false
	Lettering.range_to_legibility(l)
	return l


## The hover-card name of one of this strip's controls. Asked at hover time rather than baked
## at build, because a strip is re-pointed when the bank moves and a track can be renamed.
func _caption_for(what: String) -> String:
	return "%s  %s" % [_state().display_name().to_upper(), what]


func _state() -> MixState.TrackState:
	return DAW.state.track(track_index)


func _on_track_changed(index: int, _field: StringName) -> void:
	if index == track_index:
		refresh()


## Pull every displayed value from the cache. Cheap enough to do wholesale rather than per field,
## and a single path means a strip cannot end up showing a mix of two different moments.
func refresh() -> void:
	var t := _state()
	_name_label.text = t.display_name().to_upper()
	_db_label.text = "%+.1f" % t.volume_db if t.volume_db > -150.0 else "-inf"
	_fader.apply_remote(t.volume)
	_pan.apply_remote(t.pan)
	_mute.lit = t.mute
	_solo.lit = t.solo
	_rec.lit = t.rec_arm
	if chip_bank != null:
		# Banked chips are unshaded, so the emission `led()` would have carried has to be
		# expressed as a colour above 1 instead -- gently, because a chip is an identifier and
		# a clipped identifier is no identifier. See Materials.chip_colour.
		chip_bank.set_colour(_chip_slot, Materials.chip_colour(t.colour))
	else:
		var chip := get_node_or_null("ColourChip")
		if chip:
			chip.material_override = Materials.led(t.colour, true)


## Put one box either into a bank or into the strip, depending on whether there is a bank.
##
## Same shape as PanelButton's two branches and worth factoring out here because the strip has
## three of them. A marker node rather than arithmetic for the bank case: the offset is stated
## once, and the bank is handed a transform instead of a position plus an assumption about which
## way the strip is facing.
func _claim_or_build(bank: MeshBank, size: Vector3, offset: Vector3, material: Material,
		tint: Color, mesh_name: String) -> int:
	if bank != null:
		var at := Node3D.new()
		add_child(at)
		at.position = offset
		var slot := bank.place(at, tint)
		at.queue_free()
		return slot
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box.mesh = box_mesh
	box.position = offset
	if material != null:
		box.material_override = material
	if mesh_name != "":
		box.name = mesh_name
	add_child(box)
	return -1
