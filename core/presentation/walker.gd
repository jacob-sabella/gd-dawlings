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
## The highest edge you walk up onto without jumping: a riser, a stair. A kerb-and-a-bit; below
## anything in the room you should have to go round.
const STEP_HEIGHT := 0.32

var camera: Camera3D
var floor_plan: FloorPlan
## Where you can walk, as rectangles of floor, when that is more than the floor plan's bounds:
## the furniture stays in the working footprint, but a person can walk out of it into a venue's
## live room. Empty means the floor plan's bounds. The walls stand round the union.
var walkable: Array[Rect2] = []
## Things that stand still and stop you, as footprints with a "top": a venue's riser, table,
## booth walls. Stood up with the walls; a footprint whose top is a step or less is one you walk
## up onto rather than into.
var fixed: Array = []
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


## The walls stand round where you can walk (`walkable`, or the floor plan's bounds). Rebuilt
## on demand, since a venue or a session size can move them; cheap, and nothing calls it every
## frame.
func _build_walls() -> void:
	# Gone now, not at the end of the frame: a room rearranged mid-frame would otherwise keep
	# its old walls standing in its new doorways until then.
	for child in _solid_body.get_children():
		if child.has_meta("wall"):
			_solid_body.remove_child(child)
			child.queue_free()
	if floor_plan == null:
		return
	var thick := 0.4
	# Far taller than any room: a gallery or a stair puts you metres up, and a wall a step above
	# your feet is one you would walk over and out of the building.
	var tall := 20.0
	var floor: Array[Rect2] = walkable if not walkable.is_empty() else [floor_plan.bounds]
	for edge in outline(floor):
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var out: Vector2 = edge[2]
		var mid := (a + b) * 0.5 + out * thick * 0.5
		var length := a.distance_to(b)
		var box := BoxShape3D.new()
		box.size = Vector3(length if out.x == 0.0 else thick, tall, length if out.x != 0.0 else thick)
		var c := CollisionShape3D.new()
		c.shape = box
		c.position = Vector3(mid.x, tall * 0.5, mid.y)
		c.set_meta("wall", true)
		_solid_body.add_child(c)
	for f in fixed:
		var half: Vector2 = f["h"]
		var centre: Vector2 = f["c"]
		var top: float = f.get("top", SOLID_HEIGHT)
		var box := BoxShape3D.new()
		box.size = Vector3(half.x * 2.0, top, half.y * 2.0)
		var c := CollisionShape3D.new()
		c.shape = box
		c.transform = Transform3D(Basis(Vector3.UP, f["a"]), Vector3(centre.x, top * 0.5, centre.y))
		c.set_meta("wall", true)
		_solid_body.add_child(c)


## The edges of a union of rectangles that have floor on one side only, each as [from, to,
## outward normal]. An edge, or the part of one, with another rectangle just past it is not a
## wall but a doorway -- the control room's open back into the live room -- and is left out.
## Rectangles that meet must share the line they meet on, or overlap across it.
static func outline(rects: Array[Rect2]) -> Array:
	var out: Array = []
	var nudge := 0.01
	for r in rects:
		var sides := [
			[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(0, -1)],
			[Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(0, 1)],
			[Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), Vector2(-1, 0)],
			[Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(1, 0)],
		]
		for side in sides:
			var a: Vector2 = side[0]
			var b: Vector2 = side[1]
			var normal: Vector2 = side[2]
			var along := (b - a).normalized()
			# The stretch of this edge, as distances along it, still open to the outside.
			var open: Array = [[0.0, a.distance_to(b)]]
			for other in rects:
				if other == r:
					continue
				# Does `other` have floor just past this edge? Then, over the stretch it spans,
				# this is not a wall.
				var probe_a := a + normal * nudge
				var probe_b := b + normal * nudge
				var lo := Vector2(minf(probe_a.x, probe_b.x), minf(probe_a.y, probe_b.y))
				var hi := Vector2(maxf(probe_a.x, probe_b.x), maxf(probe_a.y, probe_b.y))
				if normal.x != 0.0:
					if lo.x <= other.position.x or lo.x >= other.end.x:
						continue
					var from := maxf(lo.y, other.position.y) - a.y
					var to := minf(hi.y, other.end.y) - a.y
					open = _cut(open, from, to)
				else:
					if lo.y <= other.position.y or lo.y >= other.end.y:
						continue
					var from := maxf(lo.x, other.position.x) - a.x
					var to := minf(hi.x, other.end.x) - a.x
					open = _cut(open, from, to)
			for span in open:
				if span[1] - span[0] > 0.001:
					out.append([a + along * span[0], a + along * span[1], normal])
	return out


## `spans` with [from, to] taken out of it.
static func _cut(spans: Array, from: float, to: float) -> Array:
	if to <= from:
		return spans
	var out: Array = []
	for span in spans:
		if to <= span[0] or from >= span[1]:
			out.append(span)
			continue
		if from > span[0]:
			out.append([span[0], from])
		if to < span[1]:
			out.append([to, span[1]])
	return out


func rebuild_walls() -> void:
	if _solid_body != null:
		_build_walls()


## Out of anything the room has just put round you. Rooms are not all the same shape: a venue
## changed under your feet can leave you inside its riser, or out past its walls on floor the
## last one had and this one does not -- and the ground goes on for ever out there. If where you
## stand is not on the floor or not clear of what stands on it, you are moved to the nearest spot
## that is, and stood on whatever you can step onto there. True when you were moved.
func unstick() -> bool:
	if floor_plan == null:
		return false
	var plan := _plan_frame()
	var here := plan.affine_inverse() * global_position
	var at := Vector2(here.x, here.z)
	var spot := free_spot(at)
	if spot.is_equal_approx(at):
		return false
	global_position = plan * Vector3(spot.x, ground_at(spot), spot.y)
	velocity = Vector3.ZERO
	return true


## The nearest place to `at` (in the floor plan's frame) where a person fits: on the floor, and
## clear of every solid but those you step up onto. `at` itself when it is one already; `at`
## when there is none within eight metres.
func free_spot(at: Vector2) -> Vector2:
	if fits(at):
		return at
	for ring in range(1, 81):
		var r := ring * 0.1
		var n := maxi(8, int(TAU * r / 0.1))
		for k in n:
			var p := at + Vector2.from_angle(TAU * k / n) * r
			if fits(p):
				return p
	return at


## Whether a person stands clear at `p`: the whole of the body on the floor, nothing too tall to
## step onto within reach of it.
func fits(p: Vector2) -> bool:
	var floor: Array[Rect2] = walkable if not walkable.is_empty() else [floor_plan.bounds]
	var reach := RADIUS + 0.03
	for k in 9:
		var probe := p if k == 8 else p + Vector2.from_angle(TAU * k / 8.0) * reach
		if not floor.any(func(r: Rect2) -> bool: return r.has_point(probe)):
			return false
	for f in fixed:
		if f.get("top", SOLID_HEIGHT) > STEP_HEIGHT and _gap(f, p) < reach:
			return false
	for f in footprints():
		if _gap(f, p) < reach:
			return false
	return true


## How far a hand reaches down to the floor from where a person stands.
const ARM := 0.6


## Whether something small lying at `p` could be picked up again: on the floor or on something
## you step up onto, not inside or under anything, and with somewhere a person fits within arm's
## reach of it. Looser than `fits`, which wants a whole body there: a ball in a corner is still a
## ball you can reach into the corner for.
func reachable(p: Vector2) -> bool:
	var floor: Array[Rect2] = walkable if not walkable.is_empty() else [floor_plan.bounds]
	if not floor.any(func(r: Rect2) -> bool: return r.has_point(p)):
		return false
	for f in fixed:
		if f.get("top", SOLID_HEIGHT) > STEP_HEIGHT and _gap(f, p) <= 0.02:
			return false
	for f in footprints():
		if _gap(f, p) <= 0.02:
			return false
	if fits(p):
		return true
	for ring in range(1, int(ARM / 0.1) + 1):
		var r := ring * 0.1
		var n := maxi(8, int(TAU * r / 0.1))
		for k in n:
			if fits(p + Vector2.from_angle(TAU * k / n) * r):
				return true
	return false


## The floor's height at `p`: the top of anything there you step up onto, or 0.
func ground_at(p: Vector2) -> float:
	var top := 0.0
	for f in fixed:
		var t: float = f.get("top", SOLID_HEIGHT)
		if t <= STEP_HEIGHT and _gap(f, p) <= 0.0:
			top = maxf(top, t)
	return top


## How far `p` is from a footprint's box, 0 inside it.
static func _gap(f: Dictionary, p: Vector2) -> float:
	var centre: Vector2 = f["c"]
	var local := Basis(Vector3.UP, f["a"]).inverse() * Vector3(p.x - centre.x, 0.0, p.y - centre.y)
	var q := Vector2(absf(local.x), absf(local.z)) - (f["h"] as Vector2)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


## The frame the footprints and the floor are measured in.
func _plan_frame() -> Transform3D:
	return solids_parent.global_transform if solids_parent != null and solids_parent.is_inside_tree() \
			else Transform3D.IDENTITY


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
	if grounded and wish_velocity != Vector3.ZERO and is_on_wall():
		_step_up(Vector3(wish_velocity.x, 0, wish_velocity.z).normalized())
	# A step's worth of bob, scaled by how fast you are actually going, so standing still is
	# perfectly still -- a camera that breathes while you are reading a meter is a distraction.
	var pace := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and pace > 0.2:
		_bob += delta * pace * 5.5
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, minf(1.0, delta * 8.0))
	_place_camera()


## Stopped by something you are walking into: if it is no taller than a step and there is room
## on top, you are on it. A body's legs do this without being asked; a capsule has to be told.
func _step_up(toward: Vector3) -> void:
	var up := Vector3(0, STEP_HEIGHT, 0)
	var ahead := toward * (RADIUS * 0.5)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, ahead):
		return
	global_position += up + ahead
	# Down onto whatever is there, now rather than over the next few frames of gravity.
	var drop := KinematicCollision3D.new()
	if test_move(global_transform, -up, drop):
		global_position += drop.get_travel()
	velocity.y = 0.0


func _place_camera() -> void:
	if camera == null or not active:
		return
	var pace := clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	var bob := Vector3(cos(_bob) * 0.012, absf(sin(_bob)) * 0.022, 0) * pace
	camera.global_transform = Transform3D(look_basis(), eye() + Basis(Vector3.UP, yaw) * bob)
