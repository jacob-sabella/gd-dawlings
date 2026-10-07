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

## Where this strip's button bodies and lamps get drawn, if the console gave it somewhere. See
## hardware/mesh_bank.gd -- ninety strips of three buttons is 540 objects otherwise.
var body_bank: MeshBank
var lamp_bank: MeshBank


static func create(index: int) -> ChannelStrip:
	var s := ChannelStrip.new()
	s.track_index = index
	s.name = "Strip%d" % index
	return s


func _ready() -> void:
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(WIDTH - 0.002, HEIGHT, 0.008)
	plate.mesh = plate_mesh
	plate.position = Vector3(0, HEIGHT * 0.5, -0.005)
	plate.material_override = Materials.chassis()
	add_child(plate)

	_name_label = _make_label(14, Vector3(0, HEIGHT - 0.012, 0.001))
	add_child(_name_label)

	# A colour chip carrying Reaper's own track colour. It is how you find the kick on a desk of
	# 32 identical strips, and it is the one piece of the DAW's visual language worth keeping.
	var chip := MeshInstance3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(WIDTH - 0.008, 0.004, 0.001)
	chip.mesh = chip_mesh
	chip.position = Vector3(0, HEIGHT - 0.022, 0.0005)
	chip.name = "ColourChip"
	add_child(chip)

	_pan = Knob.new()
	_pan.position = Vector3(0, HEIGHT - 0.048, 0.004)
	_pan.turned.connect(func(v: float): DAW.set_track_pan(track_index, v))
	add_child(_pan)

	_rec = PanelButton.new()
	_rec.body_bank = body_bank
	_rec.lamp_bank = lamp_bank
	_rec.led_colour = Color(0.95, 0.25, 0.22)
	_rec.position = Vector3(0, HEIGHT - 0.077, 0.004)
	_rec.pressed.connect(func(): DAW.set_track_rec_arm(track_index, not _state().rec_arm))
	add_child(_rec)

	_solo = PanelButton.new()
	_solo.body_bank = body_bank
	_solo.lamp_bank = lamp_bank
	_solo.led_colour = Color(0.98, 0.78, 0.2)
	_solo.position = Vector3(0, HEIGHT - 0.095, 0.004)
	_solo.pressed.connect(func(): DAW.set_track_solo(track_index, not _state().solo))
	add_child(_solo)

	_mute = PanelButton.new()
	_mute.body_bank = body_bank
	_mute.lamp_bank = lamp_bank
	_mute.led_colour = Color(0.35, 0.72, 0.98)
	_mute.position = Vector3(0, HEIGHT - 0.113, 0.004)
	_mute.pressed.connect(func(): DAW.set_track_mute(track_index, not _state().mute))
	add_child(_mute)

	_fader = Fader.new()
	_fader.track_index = track_index
	_fader.position = Vector3(-0.011, 0.040, 0.004)
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
	return l


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
	var chip := get_node_or_null("ColourChip")
	if chip:
		chip.material_override = Materials.led(t.colour, true)
