class_name MasterSection
extends Node3D

## The right-hand end of the desk: master fader, master pan, and the stereo bus meter.
##
## WHAT IS DELIBERATELY NOT HERE. A real console's master section also carries monitor level,
## dim, mono, and a speaker selector -- and none of those are in it. They belong to a monitor
## controller, which lives between the interface and the speakers; Reaper does not know the
## level your monitors are at and has no OSC address for it. A knob here labelled MONITOR would
## be a knob that turns and changes nothing, and a control that lies about what it does is worse
## than an absent one on a surface whose entire premise is that the thing is real hardware.
##
## Everything here maps to an address in the pattern file: MASTER_VOLUME, MASTER_PAN,
## MASTER_VU_L and MASTER_VU_R.

const WIDTH := 0.082
## The air between the last channel and the master. On a real desk this is a physical gap, and
## it is the reason you never grab the master when you meant the last channel -- worth keeping
## for exactly the same reason in a headset, where the hand is less precise than a mouse.
const GAP := 0.022

var _fader: Fader
var _pan: Knob
var _db_label: Label3D


func _ready() -> void:
	var height := ChannelStrip.HEIGHT

	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(WIDTH, height, 0.008)
	plate.mesh = plate_mesh
	plate.position = Vector3(0, height * 0.5, -0.005)
	plate.material_override = Materials.master_plate()
	add_child(plate)

	var caption := _label(20, Vector3(0, height - 0.014, 0.001))
	caption.text = "MASTER"
	add_child(caption)

	# A brushed rail under the caption. This is the whole of "set apart by finish" -- enough to
	# find by eye from across the room, not enough to outshine the meters.
	var rail := MeshInstance3D.new()
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(WIDTH - 0.012, 0.0025, 0.001)
	rail.mesh = rail_mesh
	rail.position = Vector3(0, height - 0.023, 0.0005)
	rail.material_override = Materials.brushed_metal()
	add_child(rail)

	_pan = Knob.new()
	_pan.position = Vector3(0, height - 0.048, 0.004)
	_pan.turned.connect(func(v: float): DAW.set_master_pan(v))
	_pan.describe_title = func() -> String: return "MASTER  BALANCE"
	_pan.describe_value = Knob.pan_text
	add_child(_pan)

	var pan_caption := _label(15, Vector3(0, height - 0.068, 0.001))
	pan_caption.text = "BAL"
	add_child(pan_caption)

	_fader = Fader.new()
	_fader.write_value = func(v: float): DAW.set_master_volume(v)
	_fader.describe_title = func() -> String: return "MASTER  LEVEL"
	_fader.position = Vector3(-0.022, 0.040, 0.004)
	add_child(_fader)

	# Two meters, not one. A mono bus meter cannot show the thing a master meter exists to show:
	# that the mix has drifted to one side. The channel strips get away with a summed meter
	# because a single track's balance is already stated by its pan knob.
	for spec in [[0.012, func() -> float: return DAW.state.master.vu_l, "L"],
			[0.030, func() -> float: return DAW.state.master.vu_r, "R"]]:
		var meter := VUMeter.new()
		meter.read_level = spec[1]
		meter.position = Vector3(spec[0], 0.042, 0.002)
		add_child(meter)

		var channel := _label(10, Vector3(spec[0], 0.032, 0.001))
		channel.text = spec[2]
		add_child(channel)

	_db_label = _label(15, Vector3(0, 0.020, 0.001))
	add_child(_db_label)

	DAW.state.master_changed.connect(func(_field: StringName): refresh())
	refresh()


func _label(font_size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size * 4
	l.pixel_size = 0.00018
	l.position = pos
	l.modulate = Color(0.88, 0.89, 0.91)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l


func refresh() -> void:
	var m := DAW.state.master
	_db_label.text = "%+.1f" % m.volume_db if m.volume_db > -150.0 else "-inf"
	_fader.apply_remote(m.volume)
	_pan.apply_remote(m.pan)
