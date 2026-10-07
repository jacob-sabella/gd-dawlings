class_name TapeDeck
extends Surface

## The transport, as a two-reel machine.
##
## The reels are not decoration and not a skin on a play button. A DAW's transport state is three
## booleans and a float, and on screen that is read from a highlighted triangle and a number. As
## a machine it is read PERIPHERALLY -- you know the thing is rolling from the corner of your eye,
## across the room, while looking at something else, which is precisely the situation this project
## exists for. The reels spin at a rate proportional to playback, so a slow pass and a fast one
## look different.
##
## What this does NOT do is pretend to be tape: there is no wind, no spooling time, no latency
## added anywhere. Reaper's position is the truth and the reels follow it.

const REEL_RADIUS := 0.085
const REEL_SPACING := 0.26

var _left_reel: Node3D
var _right_reel: Node3D
var _counter: Label3D
var _tempo_label: Label3D
var _play_lamp: PanelButton
var _rec_lamp: PanelButton
var _spin := 0.0


func _ready() -> void:
	surface_kind = &"transport"
	if surface_id == &"":
		surface_id = &"tape_deck"
	super()


func _rebuild() -> void:
	_clear_built()

	var chassis := MeshInstance3D.new()
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(0.46, 0.30, 0.05)
	chassis.mesh = chassis_mesh
	chassis.position = Vector3(0, 0, -0.03)
	chassis.material_override = Materials.chassis()
	_adopt(chassis)

	_left_reel = _make_reel(-REEL_SPACING * 0.5)
	_right_reel = _make_reel(REEL_SPACING * 0.5)

	_counter = Label3D.new()
	_counter.font_size = 72
	_counter.pixel_size = 0.00024
	_counter.position = Vector3(0, 0.105, 0.002)
	_counter.modulate = Color(0.45, 0.95, 0.6)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_adopt(_counter)

	_tempo_label = Label3D.new()
	_tempo_label.font_size = 44
	_tempo_label.pixel_size = 0.00024
	_tempo_label.position = Vector3(0, -0.115, 0.002)
	_tempo_label.modulate = Color(0.7, 0.72, 0.75)
	_tempo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_adopt(_tempo_label)

	var play := PanelButton.new()
	play.led_colour = Color(0.35, 0.95, 0.45)
	play.position = Vector3(-0.035, -0.075, 0.028)
	play.scale = Vector3(1.6, 1.6, 1.6)
	play.pressed.connect(func(): DAW.transport_play())
	_adopt(play)
	_play_lamp = play

	var stop := PanelButton.new()
	stop.led_colour = Color(0.8, 0.8, 0.84)
	stop.position = Vector3(0.0, -0.075, 0.028)
	stop.scale = Vector3(1.6, 1.6, 1.6)
	stop.pressed.connect(func(): DAW.transport_stop())
	_adopt(stop)

	var rec := PanelButton.new()
	rec.led_colour = Color(0.98, 0.22, 0.2)
	rec.position = Vector3(0.035, -0.075, 0.028)
	rec.scale = Vector3(1.6, 1.6, 1.6)
	rec.pressed.connect(func(): DAW.transport_record())
	_adopt(rec)
	_rec_lamp = rec

	DAW.state.transport_changed.connect(_refresh)
	_refresh()


func _make_reel(x: float) -> Node3D:
	var hub := Node3D.new()
	hub.position = Vector3(x, 0.0, 0.01)
	_adopt(hub)

	var flange := MeshInstance3D.new()
	var flange_mesh := CylinderMesh.new()
	flange_mesh.top_radius = REEL_RADIUS
	flange_mesh.bottom_radius = REEL_RADIUS
	flange_mesh.height = 0.004
	flange_mesh.radial_segments = 32
	flange.mesh = flange_mesh
	flange.rotation_degrees = Vector3(90, 0, 0)
	flange.material_override = Materials.brushed_metal()
	hub.add_child(flange)

	# Three spokes, so rotation is VISIBLE. A smooth disc spinning is indistinguishable from a
	# disc at rest, which would defeat the entire reason for drawing a reel.
	for i in 3:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.012, REEL_RADIUS * 1.7, 0.006)
		spoke.mesh = spoke_mesh
		spoke.rotation_degrees = Vector3(0, 0, i * 60.0)
		spoke.position = Vector3(0, 0, 0.004)
		spoke.material_override = Materials.cap_plastic(Color(0.1, 0.11, 0.12))
		hub.add_child(spoke)

	var centre := MeshInstance3D.new()
	var centre_mesh := CylinderMesh.new()
	centre_mesh.top_radius = 0.016
	centre_mesh.bottom_radius = 0.016
	centre_mesh.height = 0.012
	centre.mesh = centre_mesh
	centre.rotation_degrees = Vector3(90, 0, 0)
	centre.position = Vector3(0, 0, 0.006)
	centre.material_override = Materials.cap_plastic(Color(0.6, 0.18, 0.16))
	hub.add_child(centre)
	return hub


func _refresh() -> void:
	if _counter == null:
		return
	_counter.text = DAW.state.position_string
	_tempo_label.text = "%.1f BPM" % DAW.state.tempo
	_play_lamp.lit = DAW.state.playing
	_rec_lamp.lit = DAW.state.recording


func _process(delta: float) -> void:
	super(delta)
	if _left_reel == null:
		return
	# Driven by whether Reaper says it is rolling, not by a local animation flag. A deck that
	# keeps spinning after the DAW stopped is worse than no deck at all -- it is a lie told
	# peripherally, which is the hardest kind to catch.
	if DAW.state.playing:
		_spin += delta * 2.4
	_left_reel.rotation.z = -_spin
	_right_reel.rotation.z = -_spin
	_refresh()
