class_name TapeDeck
extends Surface

## The transport, as a two-reel machine.
##
## The reels are not decoration and not a skin on a play button. A DAW's transport state is three
## booleans and a float, and on screen that is read from a highlighted triangle and a number. As
## a machine it is read PERIPHERALLY -- you know the thing is rolling from the corner of your eye,
## across the room, while looking at something else, which is precisely the situation this project
## exists for. The reels turn at a rate derived from how fast the song is actually moving, and
## each reel turns at its OWN rate, so the takeup starts fast and slows all song while the supply
## does the opposite. That difference is the signature you read peripherally; two reels sharing
## one rate are two wheels on a common axle.
##
## What this does NOT do is pretend to be tape: there is no wind, no spooling time, no latency
## added anywhere. Reaper's position is the truth and the reels follow it.

const REEL_RADIUS := 0.085
const REEL_SPACING := 0.26
const MESH_PATH := "res://assets/hardware/reel.glb"

## The tape pack, which the flange deliberately does not include: it is a function of how far
## through the song you are, so it is computed rather than authored. Seen only through the
## flange's three windows, which is what the windows are for on a real machine.
const PACK_HUB := 0.0215
const PACK_FULL := 0.0735

## Metres of "tape" drawn past the head per second of song at 1x. Not a real figure -- 15ips is
## 0.38 -- and it does not want to be, because the reels here are a tenth the diameter of real
## ones. It is set so a half-wound reel turns at the 2.4 rad/s this deck turned at when the rate
## was flat, which keeps the look that was already tuned by eye and changes only how it varies.
const TAPE_SPEED := 0.13

## A locate arrives as a position jump, and a jump divided by one frame is an arbitrarily large
## number. Real machines have a spool limit for the same reason, so this is a cap rather than a
## special case: a seek spins the reels hard and briefly, which is what a locate looks like.
const MAX_SPOOL_RATE := 48.0

## How fast the observed song speed catches up, per second.
##
## It has to be smoothed, and the reason is specific rather than cosmetic: position does not
## arrive every frame. A real Reaper link delivers it over the wire at its own rate, so at 60fps
## most frames see the same number as the frame before and read as a dead stop. Unsmoothed, the
## reels stutter to a halt and back several times a second -- which looks like a fault in the
## machine, and a peripheral display that looks faulty is worse than one that is absent.
const SPEED_FOLLOW := 6.0

## Below this, in song-seconds per second, the deck is stopped as far as the motor is concerned.
const MOTOR_FLOOR_SPEED := 0.02

var _left_reel: Node3D
var _right_reel: Node3D
var _left_pack: MeshInstance3D
var _right_pack: MeshInstance3D
var _counter: Label3D
var _tempo_label: Label3D
var _play_lamp: PanelButton
var _rec_lamp: PanelButton
var _song_speed := 0.0
var _last_position := -1.0
var _motor: AudioStreamPlayer3D


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
	_left_pack = _left_reel.get_node_or_null(^"Pack")
	_right_pack = _right_reel.get_node_or_null(^"Pack")

	_counter = Label3D.new()
	_counter.font_size = 72
	_counter.pixel_size = 0.00024
	_counter.position = Vector3(0, 0.105, 0.002)
	_counter.modulate = Color(0.45, 0.95, 0.6)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_counter)
	_adopt(_counter)

	_tempo_label = Label3D.new()
	_tempo_label.font_size = 44
	_tempo_label.pixel_size = 0.00024
	_tempo_label.position = Vector3(0, -0.115, 0.002)
	_tempo_label.modulate = Color(0.7, 0.72, 0.75)
	_tempo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_tempo_label)
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

	# BEHIND the flange, so the only way to see it is through the windows -- which is both the
	# cheapest way to draw a tape pack and the honest one. A pack drawn in front would be a
	# disc sitting on a reel rather than tape wound inside one.
	var pack := MeshInstance3D.new()
	pack.name = "Pack"
	var pack_mesh := CylinderMesh.new()
	pack_mesh.height = 0.008
	pack_mesh.radial_segments = 48
	pack.mesh = pack_mesh
	pack.rotation_degrees = Vector3(90, 0, 0)
	# Pushed up until its face all but touches the back of the flange. A pack sitting deeper is
	# geometrically fine and visually absent: it falls into the shadow the flange casts and the
	# windows read as holes in a plate. The whole feature lives or dies on being lit.
	pack.position = Vector3(0, 0, -0.0065)
	# Lighter than real tape, for the same reason, and lighter than the first attempt at that:
	# 0.21 albedo was still reading as a hole rather than as tape. Oxide is nearly black, and
	# nearly black at the bottom of a recess the flange shadows is just black -- the window
	# then looks like a window with nothing behind it, which is worse than no window at all.
	pack.material_override = Materials.cap_plastic(Color(0.42, 0.27, 0.18))
	hub.add_child(pack)

	var flange := Part.build(
		MESH_PATH,
		Materials.reel_flange(),
		{"hub": Materials.cap_plastic(Color(0.6, 0.18, 0.16))},
	)
	if flange != null:
		# Modelled axis-up; the axis here is the panel normal, which is local Z.
		flange.rotation_degrees = Vector3(90, 0, 0)
		hub.add_child(flange)
	else:
		hub.add_child(_stand_in())
	return hub


## The pre-Blender reel: a plate, three crossing bars and a boss. Kept because a transport you
## cannot see turning is the one failure this surface exists to avoid.
func _stand_in() -> Node3D:
	var holder := Node3D.new()

	var flange := MeshInstance3D.new()
	var flange_mesh := CylinderMesh.new()
	flange_mesh.top_radius = REEL_RADIUS
	flange_mesh.bottom_radius = REEL_RADIUS
	flange_mesh.height = 0.004
	flange_mesh.radial_segments = 32
	flange.mesh = flange_mesh
	flange.rotation_degrees = Vector3(90, 0, 0)
	flange.material_override = Materials.brushed_metal()
	holder.add_child(flange)

	for i in 3:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.012, REEL_RADIUS * 1.7, 0.006)
		spoke.mesh = spoke_mesh
		spoke.rotation_degrees = Vector3(0, 0, i * 60.0)
		spoke.position = Vector3(0, 0, 0.004)
		spoke.material_override = Materials.cap_plastic(Color(0.1, 0.11, 0.12))
		holder.add_child(spoke)

	var centre := MeshInstance3D.new()
	var centre_mesh := CylinderMesh.new()
	centre_mesh.top_radius = 0.016
	centre_mesh.bottom_radius = 0.016
	centre_mesh.height = 0.012
	centre.mesh = centre_mesh
	centre.rotation_degrees = Vector3(90, 0, 0)
	centre.position = Vector3(0, 0, 0.006)
	centre.material_override = Materials.cap_plastic(Color(0.6, 0.18, 0.16))
	holder.add_child(centre)
	return holder


## How much tape is on a reel holding `fraction` of the song, as a radius.
##
## Not linear in the fraction, because tape has thickness: a wound pack grows by AREA, so the
## radius goes as a square root and a reel spends most of a song looking nearly full. Getting
## this wrong is visible -- a linear pack empties far too fast in the first minute and then
## crawls -- and it costs one sqrt to get right.
static func pack_radius(fraction: float) -> float:
	var f := clampf(fraction, 0.0, 1.0)
	return sqrt(PACK_HUB * PACK_HUB + f * (PACK_FULL * PACK_FULL - PACK_HUB * PACK_HUB))


## How fast a reel turns, in radians per second, given the fraction of the song wound ON IT.
##
## This is the whole reason a reel is worth drawing rather than animating. Tape crosses the head
## at one speed whatever the reels are doing, so a reel's angular rate is that speed divided by
## the radius it is paying out at. The consequence is the thing you recognise: a takeup reel is
## fastest when it is empty and slowest when it is full, the supply reel is the mirror of that,
## and the two agree only at the exact middle of the song.
##
## Takes the fraction on ONE reel rather than returning a pair, so there is no tuple whose order
## a caller can get backwards -- which is the mistake this surface is most exposed to, given that
## supply and takeup are otherwise identical objects.
##
## Signed: a negative song speed is a rewind, and turns the reel the other way.
static func reel_rate(on_reel: float, song_speed: float) -> float:
	var radius := pack_radius(on_reel)
	if radius <= 0.0:
		return 0.0
	return clampf(TAPE_SPEED * song_speed / radius, -MAX_SPOOL_RATE, MAX_SPOOL_RATE)


## Where the song is, as a fraction, or -1 when nobody has said how long the song is.
##
## `timeline_length()` always returns a usable number because it floors at one second, which is
## right for drawing a ruler and wrong for dividing by: against a backend with no timeline it
## would put both reels hard against their stops and call it a reading. -1 means "unknown", and
## the reels then sit half wound and stay there, which is a machine with a tape on it rather
## than a machine making a claim.
static func song_fraction(state: MixState) -> float:
	if state.project_length <= 0.0:
		return -1.0
	return clampf(state.position_seconds / state.project_length, 0.0, 1.0)


func _update_packs() -> void:
	if _left_pack == null or _right_pack == null:
		return
	var played := song_fraction(DAW.state)
	var left := 0.5 if played < 0.0 else 1.0 - played
	var right := 0.5 if played < 0.0 else played
	# Left is the supply reel and empties; right is the takeup and fills. Reversing these is
	# the kind of mistake nobody reports and everybody notices.
	(_left_pack.mesh as CylinderMesh).top_radius = pack_radius(left)
	(_left_pack.mesh as CylinderMesh).bottom_radius = pack_radius(left)
	(_right_pack.mesh as CylinderMesh).top_radius = pack_radius(right)
	(_right_pack.mesh as CylinderMesh).bottom_radius = pack_radius(right)


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
	# Driven by where Reaper says the position IS, not by a local animation flag and not by the
	# playing flag either. Position is the only thing that cannot disagree with the DAW: a deck
	# that keeps spinning after a stop is a lie told peripherally, and so, less obviously, is a
	# deck that sits still through a scrub or a rewind. Both fall out of reading one number.
	_observe_speed(delta)
	var played := song_fraction(DAW.state)
	var on_supply := 0.5 if played < 0.0 else 1.0 - played
	var on_takeup := 0.5 if played < 0.0 else played
	# Left is supply, right is takeup, matching the packs. Each gets its own rate from its own
	# radius; sharing one would undo the point of computing it.
	_left_reel.rotation.z -= reel_rate(on_supply, _song_speed) * delta
	_right_reel.rotation.z -= reel_rate(on_takeup, _song_speed) * delta
	_motor_follows_transport(delta)
	_update_packs()
	_refresh()


## How fast the song is moving, in song-seconds per real second, from watching the position.
##
## Derived rather than asked for because there is nothing to ask: the transport state is three
## booleans and a position, with no rate in it. Differencing the position is therefore the only
## source, and it has the side benefit of being backend-agnostic -- a scrub, a locate and a
## rewind all look like position moving, which is exactly how the deck should treat them.
func _observe_speed(delta: float) -> void:
	var now := DAW.state.position_seconds
	if _last_position < 0.0 or delta <= 0.0:
		_last_position = now
		return
	var observed := (now - _last_position) / delta
	_last_position = now
	_song_speed = lerpf(_song_speed, observed, minf(1.0, delta * SPEED_FOLLOW))


## The deck hums while tape is moving, and the hum fades rather than switching.
##
## Same argument as the reels, and the same source: it follows the observed speed, so it cannot
## outlive a stop, and a rewind is audible because a rewind moves tape. The fade is because a
## motor does not start at speed -- but mostly because a looping sample cut off at full level
## clicks, and the click is louder than the hum.
func _motor_follows_transport(delta: float) -> void:
	if _motor == null:
		_motor = Foley.emitter(Foley.reel_motor(), -80.0)
		_left_reel.add_child(_motor)
		_motor.play()
	var speed := absf(_song_speed)
	var wanted := MOTOR_DB if speed > MOTOR_FLOOR_SPEED else -80.0
	_motor.volume_db = move_toward(_motor.volume_db, wanted, delta * MOTOR_FADE_DB_PER_SEC)
	# A spool-up sounds like one because the pitch rides the speed, 1x landing at unity. Capped
	# well short of 2x: past that a looping hum stops reading as a faster motor and starts
	# reading as a different sound, which loses the thing the pitch was there to tell you.
	_motor.pitch_scale = clampf(0.72 + speed * 0.28, 0.72, 1.9)


## Low: this runs continuously for as long as the transport does, so it sets the noise floor of
## the whole room rather than being an event in it.
const MOTOR_DB := -20.0
const MOTOR_FADE_DB_PER_SEC := 90.0
