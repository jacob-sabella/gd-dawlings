class_name Trolley
extends ControlAffordance

## A piece of studio furniture that stands on the floor and can be pushed around it.
##
## The rack's plinth, the deck's cart, the timeline's stand, a floor lamp. Take hold of one and
## it follows you across the floor; let go and it rolls to a stop where you left it, and stays
## there next session. Whatever it carries -- a rack of plugins, a tape machine, a lamp's light
## -- goes with it, and so do the cables running out of the back.
##
## IT IS HEAVY, ON PURPOSE. The trolley does not snap to the cursor; it is pulled toward it by a
## spring and carries its own momentum, so a rack gets going a beat after the push and coasts a
## few centimetres after you let go. That lag is most of what makes it read as a thing with mass
## rather than an icon being dragged, and it is tuned per piece: a lamp is quick, a full rack is
## not.
##
## Grabbed by its own structure, never by the gear. The colliders are the plinth, posts, legs and
## casters -- the parts nobody operates -- so the knobs in a rack keep belonging to the knobs.
##
## One contract, as everywhere else: a mouse ray, a tracked controller and a pinch all push it
## the same way, by where their aim crosses the floor-level plane they took hold at. The scroll
## wheel, while holding, turns it; a thumbstick can say the same thing through `nudge`.

signal moved()
signal settled()

## How stiffly it follows the hand. Lower is heavier.
@export var follow := 11.0
## Rolls on casters, or slides on a base. Decides only the sound and whether there are wheels to
## animate; a lamp is shoved, not wheeled.
@export var rolls := true

var piece_id: StringName = &""
var floor_plan: FloorPlan
## The footprint in the trolley's own frame, on the floor: centre and half extents in (x, z).
var footprint_centre := Vector2.ZERO
var footprint_half := Vector2(0.2, 0.2)
## What rides on it. Each is {"get": Callable() -> Transform3D, "set": Callable(Transform3D,
## bool)}, both in the trolley's parent frame; the bool says the move has settled and is worth
## keeping. Callables rather than nodes because a surface on a trolley may be somewhere else
## entirely at the moment -- summoned to the mix position, or on a monitor -- and only the
## studio knows how to move its HOME without moving it.
var riders: Array = []
## Being moved from elsewhere -- someone else's hand, or the room's keeper putting it back. It
## rolls where it is told, and when it comes to rest that is not news to tell anyone.
var steered := false

## Turned this far per wheel notch while held, and this far with the fine modifier.
const TURN_STEP := deg_to_rad(15.0)
const FINE_TURN := deg_to_rad(3.0)
const MAX_SPEED := 2.6
## Further than this from the camera, an aim ray crossing the floor plane at a grazing angle is
## somewhere on the horizon, and following it would fling the rack into the wall.
const MAX_REACH := 12.0
## Aimed flatter than this (the sine of about 12 degrees) at the grip, the level plane through
## it is crossed far off or never: a stand taken by its top bar from eye height flew metres for
## a twitch of the mouse, or stuck. Then the push is read off an upright plane facing you
## instead -- across is across, and up is away -- as if the grip were this far below the eye.
const GRAZING := 0.2
const UPRIGHT_DROP := 0.6

var _casters: Array[Caster] = []
var _target := Vector2.ZERO
var _heading_target := 0.0
var _velocity := Vector2.ZERO
var _grab_height := 0.0
var _grab_from := Vector2.ZERO
var _hand_from := Vector2.ZERO
var _offsets: Array[Transform3D] = []
var _active := false
var _roll: AudioStreamPlayer3D
var _bump_cooldown := 0.0
var _grip := Vector3.ZERO
var _upright := false
var _upright_normal := Vector3.ZERO
var _upright_gain := 1.0


func _ready() -> void:
	collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
	collision_mask = 0
	add_to_group(&"room_furniture")
	add_to_group(&"trolley")
	_heading_target = rotation.y
	_target = Vector2(position.x, position.z)
	# Yielded to summoned gear by being hidden, and a hidden trolley must not be a thing a cursor
	# can still find and push. Off the control layer while it is out of sight.
	visibility_changed.connect(func() -> void:
		collision_layer = (1 << (Interactor.CONTROL_LAYER - 1)) if is_visible_in_tree() else 0)
	set_physics_process(false)


# --- building -------------------------------------------------------------------------------

## Add a piece of the trolley's own structure, and make it something to take hold of.
##
## The collider is the part's box, thickened to a minimum, because a 30mm lamp pole is a fair
## thing to see and an unfair thing to hit with a mouse ray across a room.
func add_part(part: MeshInstance3D, grip := true) -> void:
	add_child(part)
	if not grip or part.mesh == null:
		return
	var box := part.mesh.get_aabb()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05), maxf(box.size.z, 0.05))
	shape.shape = b
	shape.transform = part.transform * Transform3D(Basis.IDENTITY, box.get_center())
	add_child(shape)


## A caster standing on the floor at `at` (x, z in the trolley's frame).
func add_caster(at: Vector2) -> Caster:
	var caster := Caster.new()
	caster.position = Vector3(at.x, 0, at.y)
	add_child(caster)
	_casters.append(caster)
	# The casters are a handle too: they are the lowest thing on the piece and the first thing
	# anyone reaches for with a foot.
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.06, Caster.HEIGHT, 0.06)
	shape.shape = b
	shape.position = Vector3(at.x, Caster.HEIGHT * 0.5, at.y)
	add_child(shape)
	return caster


## Casters in the four corners of the footprint, inset so they are under the piece rather than
## sticking out of it.
func add_corner_casters(inset := 0.045) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			add_caster(footprint_centre + Vector2(
					sx * (footprint_half.x - inset), sz * (footprint_half.y - inset)))


func casters() -> Array[Caster]:
	return _casters


## The footprint if the trolley stood at `at` facing `heading`. What the floor plan collides.
func footprint_at(at: Vector2, heading: float) -> Dictionary:
	var c := at + _floor_rotate(footprint_centre, heading)
	return FloorPlan.footprint(c, footprint_half, heading)


static func _floor_rotate(v: Vector2, heading: float) -> Vector2:
	# Basis(UP, heading) applied to (x, 0, z), read back as (x, z).
	return Vector2(v.x * cos(heading) + v.y * sin(heading), -v.x * sin(heading) + v.y * cos(heading))


# --- being pushed ---------------------------------------------------------------------------

func _on_grab_begin(at: Vector3) -> void:
	# Taken hold of here: whatever was rolling it from elsewhere, it is this hand's now.
	steered = false
	_grab_height = at.y
	_grip = at
	_upright = false
	var held := held_by as Interactor
	if held != null:
		var aim := held.aim()
		var dir := -aim.basis.z
		var level := Vector3(dir.x, 0.0, dir.z)
		if absf(dir.y) < GRAZING and level.length() > 0.001:
			_upright = true
			_upright_normal = level.normalized()
			# How far a level plane UPRIGHT_DROP under the eye would carry the same nod.
			var reach := Vector2(at.x - aim.origin.x, at.z - aim.origin.z).length()
			_upright_gain = clampf(reach / UPRIGHT_DROP, 1.0, 4.0)
	var hand = _hand_on_floor()
	if hand == null:
		return
	_hand_from = hand
	_grab_from = Vector2(position.x, position.z)
	_target = _grab_from
	_heading_target = rotation.y
	_capture_riders()
	_wake()


func _on_grab_move(_at: Vector3) -> void:
	var hand = _hand_on_floor()
	if hand == null:
		return
	_target = _grab_from + (hand as Vector2 - _hand_from)


func _on_grab_end() -> void:
	# Nothing to do here but let go. The trolley keeps rolling under its own momentum and
	# settles by itself; the spring has its target already.
	pass


## Turned by the wheel while held. Refused while merely hovered: over a plinth the wheel should
## go on meaning zoom, and a rack that spun because the cursor drifted over its feet while
## someone zoomed out would be a rack nobody trusts to stay put.
func _on_nudge(notches: int, fine: bool) -> bool:
	if held_by == null:
		return false
	if not _active:
		_capture_riders()
		_wake()
	_heading_target += float(notches) * (FINE_TURN if fine else TURN_STEP)
	return true


## Where the hand's aim crosses the horizontal plane it took hold at, in the parent's frame.
func _hand_on_floor() -> Variant:
	var hand := held_by as Interactor
	if hand == null or get_parent() == null:
		return null
	var aim := hand.aim()
	if _upright:
		var crossed = Plane(_upright_normal, _upright_normal.dot(_grip)).intersects_ray(aim.origin, -aim.basis.z)
		if crossed == null or (crossed as Vector3).distance_to(aim.origin) > MAX_REACH:
			return null
		var moved: Vector3 = (crossed as Vector3) - _grip
		var pushed := Vector3(moved.x, 0.0, moved.z) + _upright_normal * moved.y * _upright_gain
		var along: Vector3 = (get_parent() as Node3D).global_transform.basis.inverse() * pushed
		return Vector2(along.x, along.z)
	var plane := Plane(Vector3.UP, _grab_height)
	var hit = plane.intersects_ray(aim.origin, -aim.basis.z)
	if hit == null or (hit as Vector3).distance_to(aim.origin) > MAX_REACH:
		return null
	var local: Vector3 = (get_parent() as Node3D).global_transform.affine_inverse() * (hit as Vector3)
	return Vector2(local.x, local.z)


## Put it somewhere outright, as if it had been rolled there: the floor plan still has the
## last word, so a stand moved under gear that was put down inside the desk stops at the desk.
func place(at: Vector2, heading: float) -> void:
	# Riders first, from where they sit now, or they would be told to stay behind.
	_capture_riders()
	var landed := at
	if floor_plan != null:
		landed = floor_plan.resolve(self, at, heading)["at"]
	position = Vector3(landed.x, position.y, landed.y)
	rotation.y = heading
	_target = landed
	_heading_target = heading
	_velocity = Vector2.ZERO
	_settle()


## Taken along by someone else's push, as it is played back from what they sent (PoseTrail): it
## goes where it is told each frame rather than springing after it, which would add a second
## lag to the one already in what they sent. roll_to, or a hand, hands it back to the spring.
var driven := false


func drive_to(at: Vector2, heading: float) -> void:
	steered = true
	if not _active:
		_capture_riders()
		_wake()
	driven = true
	_target = at
	_heading_target = rotation.y + wrapf(heading - rotation.y, -PI, PI)


## Roll it to `at`, the way a push would: the spring takes it there, so a stand moved by someone
## across the room glides after their hand instead of jumping to wherever the last word put it.
func roll_to(at: Vector2, heading: float) -> void:
	steered = true
	driven = false
	if not _active:
		_capture_riders()
		_wake()
	_target = at
	# The short way round, as the spring reads the heading by the angle between.
	_heading_target = rotation.y + wrapf(heading - rotation.y, -PI, PI)


## Remember where everything riding on the trolley sits relative to it, as of now.
##
## Every push, not once at build time: a surface carried off its trolley with its own handle and
## put back somewhere else on it should ride from where it was put, not from where it started.
func _capture_riders() -> void:
	_offsets.clear()
	var inverse := transform.affine_inverse()
	for rider in riders:
		_offsets.append(inverse * (rider["get"] as Callable).call())


func _wake() -> void:
	_active = true
	set_physics_process(true)
	if rolls and _roll == null:
		_roll = Foley.emitter(Foley.caster_roll(), -80.0)
		add_child(_roll)
		_roll.play()


func _physics_process(delta: float) -> void:
	if not _active or delta <= 0.0:
		return
	var at := Vector2(position.x, position.z)
	# A critically damped spring: gets there as fast as it can without overshooting, which is
	# what a person walking a heavy cart does. Overshoot would read as the rack bouncing.
	var heading: float
	var want: Vector2
	if driven:
		want = _target
		heading = _heading_target
		_velocity = (want - at) / delta
	else:
		var pull := (_target - at) * follow * follow - _velocity * 2.0 * follow
		_velocity += pull * delta
		if _velocity.length() > MAX_SPEED:
			_velocity = _velocity.normalized() * MAX_SPEED
		heading = lerp_angle(rotation.y, _heading_target, 1.0 - exp(-follow * 0.9 * delta))
		want = at + _velocity * delta

	var landed := want
	var bumped := false
	if floor_plan != null:
		var result := floor_plan.resolve(self, want, heading)
		landed = result["at"]
		bumped = result["bumped"]
	if bumped:
		# A knock, once, and only if it arrived with some speed. Leaning on the console with the
		# cursor would otherwise thud every frame.
		if _velocity.length() > 0.35 and _bump_cooldown <= 0.0:
			Foley.play(self, Foley.gear_bump(), linear_to_db(clampf(_velocity.length() / 2.0, 0.15, 1.0)))
			_bump_cooldown = 0.25
		_velocity = (landed - at) / delta
		# The hand keeps pushing into the obstacle; the target stays with the piece so that
		# letting go does not spring it back through the thing it just hit.
		if held_by == null:
			_target = landed
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)

	var before := transform
	position = Vector3(landed.x, position.y, landed.y)
	rotation.y = heading
	_roll_casters(before, delta)
	_carry_riders(false)
	moved.emit()

	var speed := (landed - at).length() / delta
	if _roll != null:
		_roll.volume_db = linear_to_db(clampf(speed / 1.4, 0.0001, 1.0)) - 6.0
		_roll.pitch_scale = clampf(0.75 + speed * 0.25, 0.75, 1.4)

	var resting := held_by == null and speed < 0.004 and _velocity.length() < 0.01 \
			and absf(wrapf(_heading_target - rotation.y, -PI, PI)) < 0.0015
	if resting:
		rotation.y = _heading_target
		_settle()


func _settle() -> void:
	_active = false
	_velocity = Vector2.ZERO
	set_physics_process(false)
	if _roll != null:
		_roll.queue_free()
		_roll = null
	_carry_riders(true)
	if floor_plan != null:
		floor_plan.report(self, Session.local_peer_id if Session != null else 0)
	settled.emit()


## Each caster is told how far the floor moved under IT, which is the piece's travel plus the
## sweep of the turn at that caster's distance from the middle.
func _roll_casters(before: Transform3D, delta: float) -> void:
	if _casters.is_empty():
		return
	var into_piece := transform.basis.inverse()
	for caster in _casters:
		var was := before * caster.position
		var now := transform * caster.position
		var travel := into_piece * (now - was)
		caster.roll(Vector2(travel.x, travel.z), delta)


func _carry_riders(settled_now: bool) -> void:
	for i in mini(riders.size(), _offsets.size()):
		(riders[i]["set"] as Callable).call(transform * _offsets[i], settled_now)


# --- saying what it is ----------------------------------------------------------------------

func _default_title() -> String:
	return String(piece_id).replace("_", " ").to_upper() if piece_id != &"" else "FURNITURE"


func _default_readout() -> String:
	return ""


func hint() -> String:
	return "drag to push  ·  scroll while holding to turn"
