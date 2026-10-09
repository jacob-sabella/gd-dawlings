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
## Every item, wherever it is: for a hand looking for one to catch.
const ITEMS := &"items"
## How long a throw is in the air before it can be caught: long enough that it has left the
## hand that threw it, which would otherwise catch it straight back.
const CATCH_AFTER := 0.35

signal state_changed(state: State)
## A hand here used it (`work`): for the session to tell everyone else.
signal used(down: bool)
## A throw has come to rest.
signal landed()
## Put on or taken off a head (`set_worn`).
signal worn_changed()

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
## The throw it is flying, while it flies (`launch`), and how far into it it is.
var flight: Flight = null
var _flight_t := 0.0
var _hits_played := 0
var _baskets_played := 0
## How many times it has been thrown in this room. The room carries it, so a copy that has
## already flown a throw does not fly it again when the room says it was thrown.
var throws := 0
## Where it was thrown from, as the room carries it: [origin, velocity, spin], each a Vector3.
var launched_with: Array = []
## Whether it is to go home when the throw is over, having come down somewhere it cannot stay.
var _home_after := false
## Whether the hand that has it here took it out of somebody else's: a hold to be handed over,
## not claimed (Presence.claim_carries).
var taken := false
## On a head rather than in a hand: here (the hand that put it on still has it, in its `worn`
## slot) or on somebody else's (`held_elsewhere` then rides their ghost's head). Only something
## `wearable`.
var on_head := false
## Where on this person's head it sits, worn here: their mirror ghost's (Presence). Unset, it
## rides the hand, out of sight on its mirror-only layer.
var worn_at: Callable = Callable()
## Its home is a place of its own (a hook, a clip) rather than a spot on the shelf: ItemRoom.
var own_home := false
## How big it is drawn: 1 in a hand, a ghost's head's size on one (worn poses carry a scale).
var _size := 1.0

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


## Override: it has just been thrown.
func on_launch() -> void:
	pass


## Override: it hit something in flight, at `speed` into it (m/s).
func on_bounce(_speed: float) -> void:
	pass


## Override: how high its middle is above its bottom (the origin). It tumbles about its middle.
func centre_height() -> float:
	return 0.04


## Override: how it flies. `bounce` is how much of its speed into a surface it gets back, `roll`
## how quickly it slows sliding along the floor (m/s²), `drag` the air's, per second. A rubber
## duck is mostly a thud; a bouncy ball is mostly bounce. `wing`, for something that glides
## (`Flight.fly`).
func flies() -> Dictionary:
	return {"bounce": 0.35, "roll": 3.0, "drag": 0.08}


## Override: thrown at what is aimed at rather than just along the aim (a dart), wobbling about
## this far (m) at a throw wound up to `wound` (0..1). Negative: not aimed.
func aim_scatter(_wound: float) -> float:
	return -1.0


## Override: whether it goes on a head (`Interactor.wear`).
func wearable() -> bool:
	return false


func title() -> String:
	return item_title()


func readout() -> String:
	match state:
		State.HELD:
			# Whose, when it is somebody else's: the participant the holds say has it.
			var who = claimed_by.get("display_name") if is_held_elsewhere() and claimed_by != null else null
			return "in %s's hand" % who if who is String and not (who as String).is_empty() else "in a hand"
		State.LOOSE:
			return "on the floor"
	return "on the shelf"


func hint() -> String:
	return _hint("click to pick up")


## `loose`, said of it on the shelf or the floor; nothing in your hand; and in somebody else's,
## that it is theirs to be taken from.
func _hint(loose: String) -> String:
	if is_held_elsewhere():
		return "click to take it from them"
	return loose if state != State.HELD else ""


## Part of the room: a pick-up is claimed with the host like a fader (Presence), and somebody
## pointing at it is shown pointing at it.
func personal() -> bool:
	return false


func _enter_tree() -> void:
	super()
	add_to_group(ITEMS)


## In somebody else's hand, it is still there to be reached for: a grab takes it from them (as
## they hold it out to you, or not). Anything else a person holds is theirs alone.
func grab_begin(by: Node, at: Vector3) -> void:
	var was := claimed_by
	if is_held_elsewhere():
		claimed_by = null
	super(by, at)
	if held_by != by:
		claimed_by = was


## In the air and far enough from the hand that threw it to be caught.
func catchable() -> bool:
	return flight != null and _flight_t >= CATCH_AFTER


## Its middle, in global space: what a catching hand closes on.
func middle() -> Vector3:
	return global_transform * (Vector3.UP * centre_height())


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
	taken = held_elsewhere.is_valid()
	carried_by = hand
	held_elsewhere = Callable()
	flight = null
	_home_after = false
	set_rim(Color(0, 0, 0, 0))
	_set_state(State.HELD)
	# Not something to aim at while it is in your hand: it would be under every ray you cast.
	_shape.disabled = true
	# Drawn in your own view, never in a mirror: the mirror's ghost carries a copy of its own.
	_layers(Mirror.NOT_REFLECTED)
	poke(-0.35)
	on_picked_up()


## Out of whatever hand had it and into the air, on `f`, thrown with `launch` ([origin, velocity,
## spin]) for the room to carry. `stays` false: it came down somewhere it cannot lie, and goes
## home once it has.
func launch(f: Flight, with: Array, stays := true) -> void:
	_leave_hand()
	flight = f
	_flight_t = 0.0
	_hits_played = 0
	_baskets_played = 0
	throws += 1
	launched_with = with
	_size = 1.0
	_home_after = not stays
	resting = Transform3D(Basis(f.rest_turn), f.rest) if f.stuck else Transform3D(Basis(Vector3.UP, f.rest_yaw), f.rest)
	loose_for = 0.0
	_velocity = Vector3.ZERO
	_arc_length = 0.0
	_set_state(State.LOOSE)
	on_launch()


func is_flying() -> bool:
	return flight != null


## Into somebody else's hand, wherever `pose` (a Callable giving a global Transform3D) says it
## is: their ghost's palm. Seen by everyone, mirrors too, and not to be taken out of it.
func follow(pose: Callable) -> void:
	_leave_hand()
	held_elsewhere = pose
	# Still there to grab: reaching for it takes it from them. Not off their head, though.
	_shape.disabled = on_head
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


## On a head or not (`on`). Out of every hand it is off any head too (`_set_state`). Hidden from
## the wearer's own eyes while on their head --
## it is round their camera -- and shown in their mirror; on somebody else's it cannot be
## snatched off.
func set_worn(on: bool) -> void:
	on = on and wearable()
	if on == on_head:
		return
	on_head = on
	if state == State.HELD:
		if carried_by != null:
			_layers(Mirror.SELF_ONLY if on_head else Mirror.NOT_REFLECTED)
		else:
			_shape.disabled = on_head
	set_physics_process(true)
	worn_changed.emit()


## Out of the hand onto the floor at `spot` (in the parent's frame), turned to `yaw`.
func lay_down(spot: Vector3, yaw: float) -> void:
	stick_at(Transform3D(Basis(Vector3.UP, yaw), spot))


## Whether, loose, it is stuck in something rather than lying on the floor: lying, it is always
## upright, only turned.
func is_stuck() -> bool:
	return state == State.LOOSE and not resting.basis.y.is_equal_approx(Vector3.UP)


## Out of the hand to lie at `pose` (in the parent's frame), however it is turned: on the floor,
## or stuck in a board.
func stick_at(pose: Transform3D) -> void:
	_leave_hand()
	resting = pose
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
	# Out of a hand is put down, as it is for go_home: a toy mid-trick does not carry on on the shelf.
	var was_held := state == State.HELD
	_leave_hand()
	_set_state(State.HOME)
	transform = home
	_size = 1.0
	_velocity = Vector3.ZERO
	_arc_length = 0.0
	if was_held:
		on_put_down()


func _leave_hand() -> void:
	if carried_by != null and carried_by.carrying == self:
		carried_by.carrying = null
	if carried_by != null and carried_by.worn == self:
		carried_by.worn = null
	carried_by = null
	held_elsewhere = Callable()
	flight = null
	_shape.disabled = false
	_layers(1)


func _set_state(to: State) -> void:
	state = to
	set_physics_process(true)
	state_changed.emit(to)
	if to != State.HELD:
		set_worn(false)


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
	if flight != null:
		_fly(delta)
		return
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
	# A worn pose carries the size of the head it is on; growing onto it, not jumping.
	var size_wanted := goal.basis.get_scale().x
	_size = lerpf(_size, size_wanted, 1.0 - exp(-delta * 14.0))
	if absf(_size - size_wanted) < 0.002:
		_size = size_wanted
	basis = Basis(turned).scaled(Vector3.ONE * _size)
	var s := clampf(_squash, -0.45, 0.45)
	var across := 1.0 / sqrt(maxf(0.3, 1.0 + s))
	body.scale = Vector3(across, 1.0 + s, across)
	body.position = Vector3(0, arc, 0)
	if state == State.LOOSE:
		loose_for += delta
		if loose_for > TIDY_SECONDS:
			go_home()
			return
	if state != State.HELD and _at_rest(goal) and _size == size_wanted:
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


## Along the throw: exactly where the flight has it, with a bump at each hit, and then down.
func _fly(delta: float) -> void:
	_flight_t += delta
	var pose := flight.at(_flight_t)
	# Turned about its middle, not its bottom, so it tumbles rather than swinging round a point
	# on its skin.
	var middle := Vector3.UP * centre_height()
	basis = pose.basis
	position = pose.origin + middle - pose.basis * middle
	while _hits_played < flight.hits.size() and flight.hits[_hits_played] <= _flight_t:
		var speed := flight.hit_speeds[_hits_played]
		var on := flight.hit_on[_hits_played] if _hits_played < flight.hit_on.size() else Flight.FLOOR
		_hits_played += 1
		poke(-clampf(speed * 0.05, 0.0, 0.4))
		# A hoop's rim or board makes its own noise; the room has the hoop.
		var room := ItemRoom.of(self)
		if on == Flight.FLOOR or room == null or not room.hoop_struck(on, speed, global_position):
			on_bounce(speed)
	while _baskets_played < flight.baskets.size() and flight.baskets[_baskets_played]["t"] <= _flight_t:
		var basket: Dictionary = flight.baskets[_baskets_played]
		_baskets_played += 1
		var room := ItemRoom.of(self)
		if room != null:
			room.basket(self, basket["hoop"], basket["clean"])
	_squash_speed += (-_squash * 300.0 - _squash_speed * 12.0) * delta
	_squash += _squash_speed * delta
	var s := clampf(_squash, -0.45, 0.45)
	var across := 1.0 / sqrt(maxf(0.3, 1.0 + s))
	body.scale = Vector3(across, 1.0 + s, across)
	body.position = Vector3.ZERO
	if _flight_t < flight.seconds():
		return
	# Down. From here the landing spring sets it upright where it came to rest.
	flight = null
	_velocity = Vector3.ZERO
	landed.emit()
	if _home_after:
		_home_after = false
		go_home()


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
				if on_head and worn_at.is_valid():
					hand = worn_at.call()
				else:
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
