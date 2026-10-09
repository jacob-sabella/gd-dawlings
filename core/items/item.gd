class_name Item
extends ControlAffordance

## Something a person picks up and carries round the studio: a toy, an instrument, a mic, a
## tablet, a pair of headphones (docs/items_loop.md).
##
## It is always in one of three places. At HOME, on the venue's prop shelf, where it goes back to
## when it is lost or let go somewhere it cannot stay. HELD, in a hand: it rides there, and the
## hand's button USES it (`use`) for as long as it is held down. LOOSE, put down on the floor
## where somebody left it, waiting to be picked up again.
##
## It is taken hold of the way everything else is, through the grab contract: a mouse ray, a
## controller and a pinch all close on it with the same `grab_begin`, which here means "pick me
## up" rather than "drag me", so the grab is over at once and the item stays in the hand after
## the button comes up. What it does in the hand is the subclass's: `use`, `held_pose`,
## `on_picked_up`, `on_put_down`. Nothing about it asks which medium it is in -- where a hand is
## is the interactor's business (`Interactor.carry_pose`).
##
## Every move it makes is a spring, like the gloves': it hops into the hand with an overshoot,
## settles when put down, and floats home on a slow one. At rest it stops ticking, so a shelf of
## toys costs nothing per frame.

enum State { HOME, HELD, LOOSE }

## Into a hand: stiff, a little underdamped, so the pick-up lands with one small bounce and the
## item keeps up with a turning head.
const HELD_STIFFNESS := 520.0
const HELD_DAMPING := 30.0
## Back to the shelf: slow and nearly critical, so it drifts home rather than being thrown there.
const HOME_STIFFNESS := 28.0
const HOME_DAMPING := 9.5
## Onto the floor: quick, with a bounce as it lands.
const DOWN_STIFFNESS := 160.0
const DOWN_DAMPING := 11.0
## How high a homecoming arcs over whatever is between, at its middle.
const HOME_ARC := 0.45
## Close enough to its target, and slow enough, to stop ticking.
const REST_DISTANCE := 0.001
const REST_SPEED := 0.01
## How long a loose item lies untouched before it tidies itself away.
const TIDY_SECONDS := 180.0
const STEP := 1.0 / 120.0

signal state_changed(state: State)
## A hand here used it (`work`): for the session to tell everyone else.
signal used(down: bool)

## Which item this is in the room, the same on every machine: "duck".
var id: StringName
var state := State.HOME
## Where it lives, in its parent's frame: a spot on the venue's prop shelf.
var home := Transform3D.IDENTITY
## Where it lies when LOOSE, in its parent's frame.
var resting := Transform3D.IDENTITY
## The hand that has it, while HELD here.
var carried_by: Interactor = null
## Where it is, while HELD in somebody else's hand: their ghost's palm, asked each frame
## (`follow`). Returns a global pose.
var held_elsewhere := Callable()
## How long it has lain loose and untouched.
var loose_for := 0.0

## What it looks like, under the item: the item's own node only moves.
var body: Node3D
var _velocity := Vector3.ZERO
var _squash := 0.0
var _squash_speed := 0.0
var _arc_from := Vector3.ZERO
var _arc_length := 0.0
var _shape: CollisionShape3D


func _init() -> void:
	collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
	collision_mask = 0
	body = _build_body()
	body.name = "Body"
	add_child(body)
	_shape = CollisionShape3D.new()
	_shape.name = "Grip"
	_shape.shape = _grip_shape()
	add_child(_shape)


## Override: the visible item, origin on its bottom, facing -Z. Built once.
func _build_body() -> Node3D:
	return Node3D.new()


## Override: what a hand closes on. A little bigger than the item, because a small target a
## pointer has to find on a shelf across the room is a frustrating one.
func _grip_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = 0.08
	return s


## Override: the item's name, as the hover card says it: "RUBBER DUCK".
func item_title() -> String:
	return String(id).to_upper()


## Override: how it sits in a hand, relative to the hand's carry pose (`Interactor.carry_pose`):
## which way it faces you and how far it sits from the palm.
func held_pose() -> Transform3D:
	return Transform3D.IDENTITY


## Override: the hand's button went down (`down`) or came up while holding this.
func use(_down: bool) -> void:
	pass


## Override: it has just come into a hand.
func on_picked_up() -> void:
	pass


## Override: it has just left one, onto the floor or for home.
func on_put_down() -> void:
	pass


func title() -> String:
	return item_title()


func readout() -> String:
	match state:
		State.HELD:
			return "in a hand"
		State.LOOSE:
			return "on the floor"
	return "on the shelf"


func hint() -> String:
	return "click to pick up"


## Part of the room: a pick-up is claimed with the host like a fader (Presence), and somebody
## pointing at it is shown pointing at it.
func personal() -> bool:
	return false


## Used by a hand here: done, and said, so everyone else's copy squeaks too. A copy being used
## by somebody else's hand is just `use`d.
func work(down: bool) -> void:
	use(down)
	used.emit(down)


## A grab is a pick-up. The interactor still thinks it is dragging something until the button
## comes up, which is harmless: nothing happens on a move.
func _on_grab_begin(_at: Vector3) -> void:
	var hand := held_by as Interactor
	if hand != null:
		hand.pick_up(self)


# --- where it is -------------------------------------------------------------------------------

## Into `hand`. The hand does the bookkeeping (Interactor.pick_up); this is the item's half.
func take_into(hand: Interactor) -> void:
	carried_by = hand
	held_elsewhere = Callable()
	_set_state(State.HELD)
	# Not something to aim at while it is in your hand: it would be under every ray you cast.
	_shape.disabled = true
	# Drawn in your own view, never in a mirror: the mirror's ghost carries a copy of its own.
	_layers(Mirror.NOT_REFLECTED)
	poke(-0.35)
	on_picked_up()


## Into somebody else's hand, wherever `pose` (a Callable giving a global Transform3D) says it
## is: their ghost's palm. Seen by everyone, mirrors too, and not to be taken out of it.
func follow(pose: Callable) -> void:
	_leave_hand()
	held_elsewhere = pose
	_shape.disabled = true
	_set_state(State.HELD)
	poke(-0.35)


## Whether somebody else's hand has it.
func is_held_elsewhere() -> bool:
	return state == State.HELD and held_elsewhere.is_valid()


const RIM_SHADER := preload("res://core/items/item_rim.gdshader")
var _rim: ShaderMaterial = null


## Their colour round its edge while it is in their hand, the way a fader they hold wears it;
## `Color(0, 0, 0, 0)` takes it off.
func set_rim(colour: Color) -> void:
	var on := colour.a > 0.0
	if on and _rim == null:
		_rim = ShaderMaterial.new()
		_rim.shader = RIM_SHADER
	if on:
		_rim.set_shader_parameter("colour", colour)
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.get_surface_override_material_count():
			var m := mesh.get_active_material(i) as BaseMaterial3D
			if m != null:
				m.next_pass = _rim if on else null


## Out of the hand onto the floor at `spot` (in the parent's frame), turned to `yaw`.
func lay_down(spot: Vector3, yaw: float) -> void:
	_leave_hand()
	resting = Transform3D(Basis(Vector3.UP, yaw), spot)
	loose_for = 0.0
	_set_state(State.LOOSE)
	on_put_down()


## Back to the shelf, the long way round: up over whatever is between, and down onto its spot.
func go_home() -> void:
	var was_held := state == State.HELD
	_leave_hand()
	_arc_from = position
	_arc_length = maxf(0.001, _arc_from.distance_to(home.origin))
	_set_state(State.HOME)
	if was_held:
		on_put_down()


## Straight onto its spot, no flight: for building a room, and for a shelf that has moved.
func snap_home() -> void:
	_leave_hand()
	_set_state(State.HOME)
	transform = home
	_velocity = Vector3.ZERO
	_arc_length = 0.0


func _leave_hand() -> void:
	if carried_by != null and carried_by.carrying == self:
		carried_by.carrying = null
	carried_by = null
	held_elsewhere = Callable()
	_shape.disabled = false
	_layers(1)


func _set_state(to: State) -> void:
	state = to
	set_physics_process(true)
	state_changed.emit(to)


## A squash (negative) or a stretch, rung out on a spring. A squeeze, a landing, a pick-up.
func poke(amount: float) -> void:
	_squash_speed += amount * 14.0
	set_physics_process(true)


func _layers(mask: int) -> void:
	for node in body.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = mask


# --- moving --------------------------------------------------------------------------------------

func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	var goal := _goal()
	var left := minf(delta, 0.1)
	var at := position
	var k := HELD_STIFFNESS
	var d := HELD_DAMPING
	match state:
		State.HOME:
			k = HOME_STIFFNESS
			d = HOME_DAMPING
		State.LOOSE:
			k = DOWN_STIFFNESS
			d = DOWN_DAMPING
	while left > 0.0:
		var dt := minf(STEP, left)
		left -= dt
		_velocity += ((goal.origin - at) * k - _velocity * d) * dt
		at += _velocity * dt
		_squash_speed += (-_squash * 300.0 - _squash_speed * 12.0) * dt
		_squash += _squash_speed * dt
	var arc := 0.0
	if state == State.HOME and _arc_length > 0.001:
		# Up and over: how far along the way home it is, as a hump.
		var along := clampf(1.0 - Vector2(at.x - goal.origin.x, at.z - goal.origin.z).length()
				/ maxf(0.001, Vector2(_arc_from.x - goal.origin.x, _arc_from.z - goal.origin.z).length()), 0.0, 1.0)
		arc = sin(along * PI) * minf(HOME_ARC, _arc_length * 0.4)
	position = at
	var turned := Quaternion(basis.orthonormalized()).slerp(Quaternion(goal.basis.orthonormalized()),
			1.0 - exp(-delta * (18.0 if state == State.HELD else 7.0)))
	basis = Basis(turned)
	var s := clampf(_squash, -0.45, 0.45)
	var across := 1.0 / sqrt(maxf(0.3, 1.0 + s))
	body.scale = Vector3(across, 1.0 + s, across)
	body.position = Vector3(0, arc, 0)
	if state == State.LOOSE:
		loose_for += delta
		if loose_for > TIDY_SECONDS:
			go_home()
			return
	if state != State.HELD and _at_rest(goal):
		position = goal.origin
		basis = goal.basis
		body.scale = Vector3.ONE
		body.position = Vector3.ZERO
		_arc_length = 0.0
		# A loose item still counts the time it has lain there, but only once a second.
		if state == State.LOOSE:
			set_physics_process(false)
			_tidy_later()
		else:
			set_physics_process(false)


func _at_rest(goal: Transform3D) -> bool:
	return position.distance_to(goal.origin) < REST_DISTANCE and _velocity.length() < REST_SPEED \
			and absf(_squash) < 0.002 and absf(_squash_speed) < 0.02


## Where it is headed, in its parent's frame.
func _goal() -> Transform3D:
	match state:
		State.HELD:
			var parent := get_parent() as Node3D
			var hand: Transform3D
			if held_elsewhere.is_valid():
				hand = held_elsewhere.call()
			elif carried_by != null and is_instance_valid(carried_by):
				hand = carried_by.carry_pose() * held_pose()
			else:
				return transform
			return parent.global_transform.affine_inverse() * hand if parent != null else hand
		State.LOOSE:
			return resting
	return home


## A loose item at rest does not tick; one timer stands in for the count to tidying up.
func _tidy_later() -> void:
	if not is_inside_tree():
		return
	var lay := resting
	get_tree().create_timer(maxf(0.1, TIDY_SECONDS - loose_for)).timeout.connect(func() -> void:
		if is_instance_valid(self) and state == State.LOOSE and resting == lay:
			go_home())
