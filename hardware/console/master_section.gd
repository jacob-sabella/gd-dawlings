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
## MASTER_VU_L and MASTER_VU_R. Except the two SEND sockets (SendSocket), which are not the DAW's
## at all: a wireless plug from somebody's tablet in one of them puts what it carries into that
## person's own headphones, and nothing else.

const WIDTH := 0.082
## The air between the last channel and the master. On a real desk this is a physical gap, and
## it is the reason you never grab the master when you meant the last channel -- worth keeping
## for exactly the same reason in a headset, where the hand is less precise than a mouse.
const GAP := 0.022
## Where the SEND sockets sit: over the fader's top end stop (its cap's top is 0.151 up) and
## under the flip key, where a desk keeps its headphone and cue sockets.
const SENDS_Y := 0.163

## Pressed to move the faders on to the next return's sends, and from the last back to levels.
## The console decides what that means; the master section only has the key.
signal sends_pressed()

var _fader: Fader
var _pan: Knob
var _db_label: Label3D
var _sends_key: PanelButton
var _sends_label: Label3D
## The SEND sockets, MIX then KEYS: for the studio to show and take plugs.
var sends: Array[SendSocket] = []
## What the sends key says it is showing, for its hover card: "" when the faders are levels.
var _sends_to := ""


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

	# SENDS ON FADERS. Between the balance and the fader, where a desk keeps its flip key: one
	# press puts every strip's send to the first return on its fader and pan, the next press
	# the second return's, and past the last the faders are levels again. The faders are the
	# longest, finest controls on the desk, and a send level is set as finely as a level is.
	var sends_caption := _label(13, Vector3(0, height - 0.084, 0.001))
	sends_caption.text = "SENDS"
	add_child(sends_caption)

	_sends_key = PanelButton.new()
	_sends_key.name = "SendsKey"
	_sends_key.led_colour = ChannelStrip.SEND_INK
	_sends_key.lamp_scale = Vector2(1.0, 0.5)
	_sends_key.position = Vector3(0, height - 0.099, 0.004)
	_sends_key.scale = Vector3(1.3, 1.3, 1.3)
	_sends_key.pressed.connect(func(): sends_pressed.emit())
	_sends_key.describe_title = func() -> String: return "MASTER  SENDS ON FADERS"
	_sends_key.describe_value = func(_v: float) -> String:
		return "levels" if _sends_to == "" else "sends to " + _sends_to
	add_child(_sends_key)

	_sends_label = _label(13, Vector3(0, height - 0.114, 0.001))
	_sends_label.modulate = ChannelStrip.SEND_INK
	add_child(_sends_label)

	# The personal mix's sends: the whole mix, and the keys of whoever is at the desk.
	for spec in [[-0.018, &"mix", "MIX"], [0.018, &"keys", "KEYS"]]:
		var socket := SendSocket.new()
		socket.name = "Send" + spec[2].capitalize()
		socket.source = spec[1]
		socket.label = spec[2]
		socket.position = Vector3(spec[0], SENDS_Y, 0.001)
		add_child(socket)
		sends.append(socket)
		var name_label := _label(10, Vector3(spec[0], SENDS_Y + 0.0115, 0.001))
		name_label.text = spec[2]
		add_child(name_label)

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

	DAW.master_changed.connect(func(_field: StringName): refresh())
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


## What the faders are showing: "" for levels, or the name of the return whose sends they are.
func show_sends(return_name: String) -> void:
	_sends_to = return_name
	_sends_key.lit = return_name != ""
	_sends_label.text = return_name
	Lettering.fit(_sends_label, WIDTH - 0.008, 52, ConsoleSurface.SMALLEST_FONT)


func refresh() -> void:
	var m := DAW.state.master
	_db_label.text = "%+.1f" % m.volume_db if m.volume_db > -150.0 else "-inf"
	_fader.apply_remote(m.volume)
	_pan.apply_remote(m.pan)
