class_name RcPlaneItem
extends Item

## A radio-controlled plane (docs/items_loop.md): a little foam trainer and the transmitter you
## fly it with. Picked up, the radio is in your hand and the plane stays where it lay; a click
## runs the motor up and it takes off along the floor, and then it goes where you point -- the
## hand's aim, a mouse's or a controller's, a little past where the plane is now. Another click cuts
## the motor and it glides; down gently on its wheels it has landed, and rolls to a stop; into a
## wall, the gear or the floor too hard it has crashed, and lies nosed in until a click sets it
## back on its wheels.
##
## Flown by the hand that has the radio, here; everybody else sees it where that machine says,
## a few times a second (`flown`, `hear`, Presence). Out of every hand -- put down, thrown, sent
## home -- the plane is back beside its radio (`dock`).

const MODEL := "res://assets/models/rcplane.glb"
## tools/blender/rcplane.py's: how far its middle is above its wheels, and where the prop is.
const WHEELS := 0.059
const NOSE := -0.135
## The radio's half-thickness: how high its middle lies off the floor.
const RADIO_UP := 0.035
## Where the plane sits beside its radio, at home, in the item's frame.
const DOCK := Transform3D(Basis.IDENTITY, Vector3(0.25, WHEELS, -0.06))

## How it flies. Under power about 2.6 m/s, a fast walk, and turning at most 2.4 rad/s: a circle
## a couple of metres across, which the room has. With the motor off it glides a little slower,
## coming down half a metre a second. It climbs no steeper than about one in two, and not above
## CEILING off the floor.
const SPEED := 2.6
const GLIDE_SPEED := 2.1
const SINK := 0.5
const TURN := 2.4
const CLIMB := 0.5
const DIVE := 0.8
const CEILING := 2.3
## Along the floor to take off: how fast it gathers speed and the speed it lifts off at.
const RUN_UP := 2.2
const LIFT := 1.9
## Down on its wheels slower than this, and not banked over: a landing. Faster, a crash.
const LAND_SINK := 1.0
const LAND_BANK := 0.5
## How far past the plane, along where you point, it is steered at: point at it and it flies
## on away from you; point beside it and it turns that way.
const LEAD := 1.5
const FLY_STEP := 1.0 / 120.0
## Its wings and nose, in its own frame: the points it lands, crashes and lies on.
const POINTS: Array[Vector3] = [Vector3(0.17, 0.045, -0.04), Vector3(-0.17, 0.045, -0.04),
		Vector3(0, -0.02, -0.13), Vector3(0.045, -WHEELS, -0.075), Vector3(-0.045, -WHEELS, -0.075),
		Vector3(0, -WHEELS, 0.142), Vector3(0, 0.07, 0.156)]
## How it lies crashed: nosed in, one wing down.
const NOSED_IN := Vector3(-0.42, 0.0, 0.38)

const FOAM := Color(0.86, 0.86, 0.82)
const TRIM := Color(0.85, 0.16, 0.1)

## RUNNING is on its wheels with the motor running, taking off.
enum Mode {DOCKED, LANDED, RUNNING, FLYING, GLIDING, CRASHED}

var plane: Node3D
var prop: Node3D
var radio: Node3D
## The light on the radio: green while the plane is away and flying.
var led: StandardMaterial3D
var mode := Mode.DOCKED
## Flown here: where it is in the room's frame, which way it heads (about the up axis, 0 is -Z),
## how fast, how steeply it is climbing (rise over run), and how far it leans into the turn.
var at := Vector3.ZERO
var heading := 0.0
var speed := 0.0
var slope := 0.0
var bank := 0.0
## Crashed and still coming down, tumbling.
var falling := false
var _fall := Vector3.ZERO
var _tumble := Vector3.ZERO
var _turned := Basis.IDENTITY
var _left := 0.0
var _crashes := 0
var _prop_angle := 0.0
## Heard from the machine flying it.
var _heard := Transform3D.IDENTITY
## Where it was heard to be, kept and played back a moment behind: see PoseTrail.
var _trail := PoseTrail.new()
var _hearing := false
var _motor: AudioStreamPlayer3D


func _init() -> void:
	id = &"rcplane"
	super()
	_shape.position = Vector3(0.12, 0.05, -0.05)
	state_changed.connect(func(to: State) -> void:
		if to != State.HELD:
			dock())


func item_title() -> String:
	return "RADIO PLANE"


func readout() -> String:
	match mode:
		Mode.FLYING:
			return "flying"
		Mode.GLIDING:
			return "gliding in"
		Mode.CRASHED:
			return "crashed"
	return "by the hoop" if state == State.HOME else super()


func hint() -> String:
	if state == State.HELD and carried_by != null and pocket < 0:
		match mode:
			Mode.LANDED:
				return "click to run the motor up and take off"
			Mode.RUNNING:
				return "point where it should go; click to cut the motor"
			Mode.FLYING:
				return "point where it should fly; click to cut the motor"
			Mode.GLIDING:
				return "bring it down gently on its wheels to land; click for power"
			Mode.CRASHED:
				return "click to set it back on its wheels"
	return _hint("click to pick up the radio, then click to fly the plane")


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	var foam := StandardMaterial3D.new()
	foam.albedo_color = FOAM
	foam.roughness = 0.75
	var trim := StandardMaterial3D.new()
	trim.albedo_color = TRIM
	trim.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.07, 0.08)
	dark.roughness = 0.6
	var case := StandardMaterial3D.new()
	case.albedo_color = Color(0.16, 0.17, 0.19)
	case.roughness = 0.55
	led = StandardMaterial3D.new()
	led.albedo_color = Color(0.2, 0.05, 0.03)
	led.emission_enabled = true
	led.emission = Color(1.0, 0.25, 0.1)
	led.emission_energy_multiplier = 1.5
	var swap := {"foam": foam, "trim": trim, "dark": dark, "metal": Materials.brushed_metal(),
			"case": case, "led": led}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	radio = model.find_child("Radio", true, false) as Node3D
	var airframe := model.find_child("Plane", true, false) as Node3D
	prop = model.find_child("Prop", true, false) as Node3D
	for part: Node3D in [radio, airframe, prop]:
		part.get_parent().remove_child(part)
	model.free()
	radio.name = "Radio"
	# Small, and under a hand or at your feet: its shadow is not worth the draws. The prop's is a
	# blur anyway. The plane's stays: it is how you see how high it is.
	for part: Node3D in [radio, prop]:
		(part as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	radio.transform = Transform3D(Basis.IDENTITY, Vector3(0, RADIO_UP, 0))
	root.add_child(radio)
	# The plane is the item's, not the body's: it is not in the hand with the radio, nor in the
	# pocket, nor drawn only in your own view as what is in your hand is.
	plane = Node3D.new()
	plane.name = "Plane"
	airframe.transform = Transform3D.IDENTITY
	plane.add_child(airframe)
	prop.name = "Prop"
	prop.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.003, NOSE))
	plane.add_child(prop)
	plane.transform = DOCK
	return root


func _ready() -> void:
	super()
	if plane.get_parent() == null:
		add_child(plane)
	_motor = Foley.emitter(Foley.rc_motor(), -12.0)
	_motor.name = "Motor"
	plane.add_child(_motor)


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.52, 0.12, 0.36)
	return s


func centre_height() -> float:
	return RADIO_UP


## The radio in the hand: held flat out in front, a little tipped toward you so its sticks show.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, -RADIO_UP + 0.01, -0.03))


## The radio thrown: plastic, it does not go far.
func flies() -> Dictionary:
	return {"bounce": 0.2, "roll": 8.0, "drag": 0.1}


func _foley_contact() -> AudioStream:
	return Foley.yoyo_catch(1)


## Away from its radio: somewhere in the room, landed, flying or crashed.
func away() -> bool:
	return mode != Mode.DOCKED


## Where the plane is, in the world.
func plane_pose() -> Transform3D:
	return plane.global_transform


# --- docked and away -----------------------------------------------------------------------------

## Back beside its radio, motor off.
func dock() -> void:
	if plane == null:
		return
	mode = Mode.DOCKED
	falling = false
	_hearing = false
	speed = 0.0
	plane.top_level = false
	plane.transform = DOCK
	_sounds()


## Off on its own, where it is: the radio has gone into a hand and the plane stays on the floor.
func _release() -> void:
	if plane == null or away():
		return
	var was := plane.global_transform
	plane.top_level = true
	plane.global_transform = was
	var local := _room_frame().affine_inverse() * was
	at = local.origin
	var ahead := local.basis * Vector3.FORWARD
	heading = atan2(-ahead.x, -ahead.z)
	speed = 0.0
	slope = 0.0
	bank = 0.0
	mode = Mode.LANDED
	_sounds()


func on_picked_up() -> void:
	_release()


func follow(pose: Callable) -> void:
	super(pose)
	_release()


## Into a pocket while it flies: the motor is cut, and it glides down on its own.
func on_stowed() -> void:
	if mode == Mode.FLYING:
		_set_mode(Mode.GLIDING)
	elif mode == Mode.RUNNING:
		_set_mode(Mode.LANDED)


func on_put_down() -> void:
	Foley.play(self, Foley.yoyo_catch(2), -10.0, 0.8)


## The radio's sticks, here. Only the hand that has it flies it; a copy in somebody else's hand
## is flown by what they say (`hear`).
func use(down: bool) -> void:
	poke(-0.08 if down else 0.04)
	if not down or carried_by == null or not away():
		return
	match mode:
		Mode.LANDED:
			_set_mode(Mode.RUNNING)
		Mode.RUNNING:
			_set_mode(Mode.LANDED)
		Mode.FLYING:
			_set_mode(Mode.GLIDING)
		Mode.GLIDING:
			_set_mode(Mode.FLYING)
		Mode.CRASHED:
			if not falling:
				_right_it()


func _set_mode(to: Mode) -> void:
	if to == mode:
		return
	mode = to
	_sounds()


# --- flying it -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if plane == null or not away():
		return
	if carried_by != null and state == State.HELD:
		_left += minf(delta, 0.1)
		while _left >= FLY_STEP:
			_left -= FLY_STEP
			_step(FLY_STEP)
		_place()
	elif _hearing:
		plane.global_transform = _trail.sample(PoseTrail.now())
	var running := _motor_running()
	_prop_angle += delta * (95.0 if running else 0.0)
	prop.rotation.z = _prop_angle
	if _motor != null:
		_motor.pitch_scale = 0.8 + 0.25 * clampf(speed / SPEED, 0.0, 1.4) if carried_by != null else 1.0


func _motor_running() -> bool:
	return mode == Mode.FLYING or mode == Mode.RUNNING


## The room's frame, which the plane is flown in: the floor plan's.
func _room_frame() -> Transform3D:
	var parent := get_parent() as Node3D
	return parent.global_transform if parent != null and parent.is_inside_tree() else Transform3D.IDENTITY


func _ground(p: Vector3) -> float:
	var room := ItemRoom.of(self)
	return room.ground(Vector2(p.x, p.z)) if room != null else 0.0


func _blocked(p: Vector3) -> bool:
	var room := ItemRoom.of(self)
	return room.blocked(p) if room != null else false


## Which way it is going, along the floor.
func _ahead() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


## Where it is pointed, in the room's frame, or null: only a radio in the hand steers.
func _steer_to() -> Variant:
	if not in_hand():
		return null
	var aim := _room_frame().affine_inverse() * carried_by.aim()
	var from := aim.origin
	var way := (aim.basis * Vector3.FORWARD).normalized()
	return from + way * (from.distance_to(at) + LEAD)


## One step of flying it: `dt` seconds.
func _step(dt: float) -> void:
	match mode:
		Mode.LANDED, Mode.RUNNING:
			_roll(dt)
		Mode.FLYING, Mode.GLIDING:
			_air(dt)
		Mode.CRASHED:
			if falling:
				_tumble_down(dt)


## On its wheels: running up to take off, or rolling to a stop.
func _roll(dt: float) -> void:
	if mode == Mode.RUNNING:
		speed = minf(speed + RUN_UP * dt, LIFT + 0.1)
		var to: Variant = _steer_to()
		if to != null:
			_turn_toward(to as Vector3, dt, 0.5 * speed / LIFT)
		if speed >= LIFT:
			slope = 0.3
			_set_mode(Mode.FLYING)
	else:
		speed = maxf(0.0, speed - 2.4 * dt)
	if speed <= 0.0:
		return
	var next := at + _ahead() * speed * dt
	if _blocked(next + _ahead() * 0.14):
		_crash(speed)
		return
	at = next
	at.y = _ground(at) + WHEELS


## Turning toward `to`, up to `most` of its best turn.
func _turn_toward(to: Vector3, dt: float, most := 1.0) -> float:
	var off := to - at
	if Vector2(off.x, off.z).length() < 0.05:
		return 0.0
	var wanted := atan2(-off.x, -off.z)
	var rate := clampf(wrapf(wanted - heading, -PI, PI) * 3.0, -TURN * most, TURN * most)
	heading = wrapf(heading + rate * dt, -PI, PI)
	return rate


func _air(dt: float) -> void:
	var to: Variant = _steer_to()
	var rate := 0.0
	var climb := 0.0 if mode == Mode.FLYING else -SINK / GLIDE_SPEED
	if to != null:
		rate = _turn_toward(to as Vector3, dt)
		var off := (to as Vector3) - at
		climb = clampf(off.y / maxf(0.3, Vector2(off.x, off.z).length()), -DIVE, CLIMB)
	if mode == Mode.GLIDING:
		climb = minf(climb, -SINK / GLIDE_SPEED)
	if at.y - _ground(at) > CEILING:
		climb = minf(climb, 0.0)
	slope = move_toward(slope, climb, 1.4 * dt)
	bank = lerpf(bank, rate / TURN * 0.7, 1.0 - exp(-dt * 6.0))
	# Faster nose down, slower nose up.
	var cruise := (SPEED if mode == Mode.FLYING else GLIDE_SPEED) - slope * 1.2
	speed = move_toward(speed, cruise, 1.5 * dt)
	var run := speed / sqrt(1.0 + slope * slope)
	var v := _ahead() * run + Vector3.UP * run * slope
	var next := at + v * dt
	var ground := _ground(next)
	if next.y - WHEELS <= ground:
		at = Vector3(next.x, ground + WHEELS, next.z)
		if -v.y < LAND_SINK and absf(bank) < LAND_BANK:
			_touch_down(-v.y)
		else:
			_crash(v.length())
		return
	if _blocked(next + v.normalized() * 0.14):
		_crash(v.length())
		return
	at = next


func _touch_down(sink: float) -> void:
	slope = 0.0
	bank = 0.0
	_set_mode(Mode.LANDED)
	Foley.play(plane, Foley.rc_touchdown(_crashes), clampf(linear_to_db(sink + 0.4), -18.0, -4.0))


## Into something at `how_fast`: it bounces back off it a little and falls, tumbling.
func _crash(how_fast: float) -> void:
	_crashes += 1
	var v := _ahead() * speed + Vector3.UP * speed * slope
	_fall = -v * 0.25 + Vector3.UP * 0.6
	_turned = _basis()
	_tumble = Vector3(6.0, 2.0 * (1 if _crashes % 2 == 0 else -1), 4.0) * clampf(how_fast / SPEED, 0.3, 1.2)
	falling = true
	speed = 0.0
	slope = 0.0
	bank = 0.0
	_set_mode(Mode.CRASHED)
	Foley.play(plane, Foley.rc_crash(_crashes), clampf(linear_to_db(how_fast / 3.0), -14.0, 0.0))


func _tumble_down(dt: float) -> void:
	_fall.y -= 9.8 * dt
	var next := at + _fall * dt
	if _blocked(next):
		_fall.x = 0.0
		_fall.z = 0.0
		next = at + _fall * dt
	at = next
	if _tumble.length() > 0.0:
		_turned = Basis(_tumble.normalized(), _tumble.length() * dt) * _turned
	if at.y - 0.03 <= _ground(at):
		falling = false
		_turned = Basis(Vector3.UP, heading) * Basis.from_euler(NOSED_IN)
		at.y = _ground(at) + _lift(_turned)
		Foley.play(plane, Foley.soft_thud(_crashes), -10.0, 1.4)


## Upright on its wheels where it lies, with a hop.
func _right_it() -> void:
	at.y = _ground(at) + WHEELS
	slope = 0.0
	bank = 0.0
	speed = 0.0
	_set_mode(Mode.LANDED)
	_place()
	poke(-0.1)
	Foley.play(plane, Foley.rc_touchdown(_crashes + 1), -10.0)


## Turned `b`, how high its middle is with its lowest point on the floor.
static func _lift(b: Basis) -> float:
	var low := INF
	for p in POINTS:
		low = minf(low, (b * p).y)
	return -low


## How it is turned flying here: its heading, its nose up or down the slope, leaning into the turn.
func _basis() -> Basis:
	return Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, atan(slope)) * Basis(Vector3.BACK, bank)


func _place() -> void:
	var b := _turned if mode == Mode.CRASHED else _basis()
	plane.global_transform = _room_frame() * Transform3D(b, at)


# --- heard ----------------------------------------------------------------------------------------

## Somebody else is flying it: it is at `pose` (the world's), `as_mode` (Mode).
func hear(pose: Transform3D, as_mode: int) -> void:
	if carried_by != null or plane == null:
		return
	if as_mode == Mode.DOCKED:
		if away():
			dock()
		return
	if not away():
		_release()
	_heard = pose
	if not _hearing:
		_hearing = true
		_trail.clear()
		plane.global_transform = pose
	_trail.push(PoseTrail.now(), pose)
	var was := mode
	mode = as_mode as Mode
	if was != mode:
		if mode == Mode.CRASHED:
			_crashes += 1
			Foley.play(plane, Foley.rc_crash(_crashes), -4.0)
		elif mode == Mode.LANDED and (was == Mode.GLIDING or was == Mode.FLYING):
			Foley.play(plane, Foley.rc_touchdown(_crashes), -8.0)
	_sounds()


## The motor, running or not; the light on the radio, green while it flies.
func _sounds() -> void:
	var running := _motor_running()
	if led != null:
		led.emission = Color(0.2, 1.0, 0.3) if away() and mode != Mode.CRASHED else Color(1.0, 0.25, 0.1)
	if _motor == null or not _motor.is_inside_tree():
		return
	if running and not _motor.playing:
		_motor.play()
	elif not running and _motor.playing:
		_motor.stop()
