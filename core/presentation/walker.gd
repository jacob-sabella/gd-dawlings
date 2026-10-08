class_name Walker
extends CharacterBody3D

## You, on foot, on a monitor.
##
## The orbit camera is how this project was photographed and how it was first driven, and it is
## a god's view: it floats, it passes through the console, it swings round the room on a boom.
## That is still the right tool for arranging a room, so it stays, one key away. But a studio is
## a place you WALK around -- to the rack, back to the desk, over to the tape machine -- and the
## floor and the furniture are what make it a place rather than a diagram. So by default you are
## a body: a capsule with weight and momentum, standing on the floor, stopped by the walls and
## by anything standing on them.
##
## Nothing solid here is authored twice. The room's solids are the floor plan's footprints --
## the same rectangles a pushed rack is resolved against -- stood up into boxes and kept in step
## with them every physics tick, so a trolley you just wheeled somewhere is solid where it ended
## up and not where it started.
##
## The look is a right-drag, not a captured mouse. The cursor is how every control in the room is
## reached, and a walker that took it away would make you choose between walking and mixing.

## The layer the room's solids live on. Not the control layer: a ray aimed at a fader must not
## stop on the invisible box that keeps you from walking through the desk the fader sits on.
const SOLID_LAYER := 10
const RADIUS := 0.22
const GRAVITY := 9.8
const WALK_SPEED := 1.7
const SPRINT_SPEED := 3.2
## Metres per second per second. Enough that a tap moves you, little enough that you feel it.
const ACCELERATION := 9.0
const FRICTION := 11.0
const AIR_CONTROL := 0.25
const JUMP_SPEED := 3.1
const LOOK_SPEED := 0.005
## How tall a footprint stands. Above a desk, below a lamp's shade; nobody steps over a console.
const SOLID_HEIGHT := 1.25

var camera: Camera3D
var floor_plan: FloorPlan
## The frame the floor plan's footprints are measured in. The solids live there, so a footprint
## and the box standing on it can never disagree about where the floor is.
var solids_parent: Node3D
## Where the eyes are above the floor. Moved by a visit -- a seat at the bottom of a rack is a
## crouch -- and eased back to standing once you walk off.
var eye_height := 1.62
var standing_eye := 1.62
var yaw := 0.0
var pitch := -0.18
## Off while god mode has the camera. The body stays where it was left, so switching back puts
## you where you stood, not wherever the god happened to be hovering.
var active := true

var _solids: Array[CollisionShape3D] = []
var _solid_body: StaticBody3D
var _travel: Tween
var _bob := 0.0
var _jump_held := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << (SOLID_LAYER - 1)
	floor_snap_length = 0.1
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = 1.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, 0.85, 0)
	add_child(collider)

	# The room, as one static body: the floor, four walls, and a box per footprint, in the frame
	# the footprints are measured in.
	_solid_body = StaticBody3D.new()
	_solid_body.name = "RoomSolids"
	_solid_body.collision_layer = 1 << (SOLID_LAYER - 1)
	_solid_body.collision_mask = 0
	if solids_parent != null:
		solids_parent.add_child(_solid_body)
	else:
		_solid_body.top_level = true
		add_child(_solid_body)
	var ground := CollisionShape3D.new()
	ground.shape = WorldBoundaryShape3D.new()
	_solid_body.add_child(ground)
	_build_walls()
	sync_solids()


## The four walls are the floor plan's bounds. Rebuilt on demand, since a venue or a session size
## can move them; cheap, and nothing calls it every frame.
func _build_walls() -> void:
	for child in _solid_body.get_children():
		if child.has_meta("wall"):
			child.queue_free()
	if floor_plan == null:
		return
	var b := floor_plan.bounds
	var thick := 0.4
	var tall := 4.0
	var walls := [
		[Vector3(b.get_center().x, tall * 0.5, b.position.y - thick * 0.5), Vector3(b.size.x + thick * 2.0, tall, thick)],
		[Vector3(b.get_center().x, tall * 0.5, b.end.y + thick * 0.5), Vector3(b.size.x + thick * 2.0, tall, thick)],
		[Vector3(b.position.x - thick * 0.5, tall * 0.5, b.get_center().y), Vector3(thick, tall, b.size.y)],
		[Vector3(b.end.x + thick * 0.5, tall * 0.5, b.get_center().y), Vector3(thick, tall, b.size.y)],
	]
	for w in walls:
		var box := BoxShape3D.new()
		box.size = w[1]
		var c := CollisionShape3D.new()
		c.shape = box
		c.position = w[0]
		c.set_meta("wall", true)
		_solid_body.add_child(c)


func rebuild_walls() -> void:
	if _solid_body != null:
		_build_walls()


## Stand every footprint up as a box. Shapes are reused across ticks; only their size and pose
## change, which is a handful of assignments for a room with a dozen things in it.
func sync_solids() -> void:
	if floor_plan == null or _solid_body == null:
		return
	var prints := footprints()
	while _solids.size() < prints.size():
		var c := CollisionShape3D.new()
		c.shape = BoxShape3D.new()
		_solid_body.add_child(c)
		_solids.append(c)
	for i in _solids.size():
		var c := _solids[i]
		c.disabled = i >= prints.size()
		if c.disabled:
			continue
		var f: Dictionary = prints[i]
		var half: Vector2 = f["h"]
		var centre: Vector2 = f["c"]
		(c.shape as BoxShape3D).size = Vector3(half.x * 2.0, SOLID_HEIGHT, half.y * 2.0)
		c.transform = Transform3D(Basis(Vector3.UP, f["a"]),
				Vector3(centre.x, SOLID_HEIGHT * 0.5, centre.y))


## Everything on the floor that you cannot walk through, as floor-plan footprints.
func footprints() -> Array:
	var out: Array = []
	if floor_plan == null:
		return out
	for piece in floor_plan.pieces:
		if is_instance_valid(piece) and piece.is_inside_tree() and piece.visible \
				and piece.has_method("footprint_at"):
			out.append(piece.footprint_at(Vector2(piece.position.x, piece.position.z),
					piece.rotation.y))
	for fixture in floor_plan.fixtures:
		if fixture.is_valid():
			out.append_array(fixture.call())
	return out


func eye() -> Vector3:
	return global_position + Vector3(0, eye_height, 0)


func look_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


## Turn the head. Pitch stops short of straight up and down, where yaw stops meaning anything.
func look(relative: Vector2) -> void:
	yaw -= relative.x * LOOK_SPEED
	pitch = clampf(pitch - relative.y * LOOK_SPEED, -1.45, 1.35)


## Go and stand with your eyes at `at`, looking at `target`.
##
## Walked rather than teleported, on a curve, with collision off for the trip: a visit is a
## decision to be somewhere, and being stopped half way by the corner of the rack you were
## asked to go and look at would be the physics winning an argument nobody was having.
func travel_to(at: Vector3, target: Vector3, seconds: float) -> void:
	var feet := Vector3(at.x, 0.0, at.z)
	var to_eye := clampf(at.y, 0.9, 2.0)
	var back := at - target
	var to_yaw := atan2(back.x, back.z)
	var to_pitch := -atan2(back.y, Vector2(back.x, back.z).length())
	if _travel != null and _travel.is_valid():
		_travel.kill()
	velocity = Vector3.ZERO
	if seconds <= 0.01 or not is_inside_tree():
		global_position = feet
		eye_height = to_eye
		yaw = to_yaw
		pitch = to_pitch
		_place_camera()
		return
	var from_pos := global_position
	var from_eye := eye_height
	var from_yaw := yaw
	# The short way round. A visit to something behind you must not spin you through 300 degrees.
	var turn := wrapf(to_yaw - from_yaw, -PI, PI)
	var from_pitch := pitch
	_travel = create_tween()
	_travel.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_travel.tween_method(func(t: float) -> void:
		global_position = from_pos.lerp(feet, t)
		eye_height = lerpf(from_eye, to_eye, t)
		yaw = from_yaw + turn * t
		pitch = lerpf(from_pitch, to_pitch, t)
		_place_camera(), 0.0, 1.0, seconds)


func travelling() -> bool:
	return _travel != null and _travel.is_valid() and _travel.is_running()


func _physics_process(delta: float) -> void:
	sync_solids()
	if not active or travelling():
		return
	var wish := Vector3.ZERO
	# Keyboard only when nothing else has it: a text field taking a track name must not walk
	# you into the wall one letter at a time.
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus_owner == null:
		if Input.is_key_pressed(KEY_W): wish.z -= 1.0
		if Input.is_key_pressed(KEY_S): wish.z += 1.0
		if Input.is_key_pressed(KEY_A): wish.x -= 1.0
		if Input.is_key_pressed(KEY_D): wish.x += 1.0
	wish = (Basis(Vector3.UP, yaw) * wish).normalized() if wish != Vector3.ZERO else Vector3.ZERO
	var sprint := Input.is_key_pressed(KEY_SHIFT) and focus_owner == null
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	step(delta, wish * speed, focus_owner == null and Input.is_key_pressed(KEY_SPACE))


## One tick of the body, with the input already decided. Split out so a test can drive it.
func step(delta: float, wish_velocity: Vector3, jump := false) -> void:
	var grounded := is_on_floor()
	var flat := Vector3(velocity.x, 0, velocity.z)
	var control := 1.0 if grounded else AIR_CONTROL
	if wish_velocity != Vector3.ZERO:
		flat = flat.move_toward(wish_velocity, ACCELERATION * control * delta)
		# Walking off a visit stands you back up.
		eye_height = move_toward(eye_height, standing_eye, delta * 0.8)
	elif grounded:
		flat = flat.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if grounded:
		if jump and not _jump_held:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	_jump_held = jump
	move_and_slide()
	# A step's worth of bob, scaled by how fast you are actually going, so standing still is
	# perfectly still -- a camera that breathes while you are reading a meter is a distraction.
	var pace := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and pace > 0.2:
		_bob += delta * pace * 5.5
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, minf(1.0, delta * 8.0))
	_place_camera()


func _place_camera() -> void:
	if camera == null or not active:
		return
	var pace := clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	var bob := Vector3(cos(_bob) * 0.012, absf(sin(_bob)) * 0.022, 0) * pace
	camera.global_transform = Transform3D(look_basis(), eye() + Basis(Vector3.UP, yaw) * bob)
