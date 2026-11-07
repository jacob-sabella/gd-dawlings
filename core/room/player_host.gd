class_name PlayerHost
extends RefCounted

## The player's own hands and body: the debounced saves and publishes, the headphones, the pockets, putting items down, the
## walker and god mode. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

var _room_publish_due := false

## Where the opening view looks: (metres ahead of the mix position, height). Where a standing
## eye's half-radian glance lands on the console, kept for every other eye height.
const DESK_GAZE := Vector2(0.96, 1.096)

var _made_remember_due := false

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## Where the made items are, kept once at the end of the frame (a rack slot taken, a put-down).
func _remember_made_soon() -> void:
	if _made_remember_due:
		return
	_made_remember_due = true
	_remember_made_due.call_deferred()


func _remember_made_due() -> void:
	_made_remember_due = false
	studio.sampler_host._remember_made()


## A hand here put an item down, or sent it home: a guest asks the host, having done it already.
## A host's room is told by the item moving (`_publish_room_soon`).
func _on_items_asked(verb: StringName, args: Array) -> void:
	if not Session.is_authority():
		studio.room_rows._predict(verb, args)


## The room told once at the end of the frame, however many things in it moved during it.
func _publish_room_soon() -> void:
	if Session.role != Session.Role.HOST or studio._applying_room or _room_publish_due:
		return
	_room_publish_due = true
	# A method and not a lambda: a studio freed before the frame ends is skipped, not called.
	_publish_room_due.call_deferred()


func _publish_room_due() -> void:
	_room_publish_due = false
	studio.room_rows._publish_room()


## Off your head into the mouse's hand, or on from it.
func _toggle_headphones() -> void:
	var hand := studio.get_node_or_null("MouseHand") as Interactor
	if hand == null:
		return
	if hand.worn != null:
		if not hand.take_off():
			Session.notice.emit("Your hand is full: put down what is in it first (Q).")
	elif hand.carrying != null and hand.carrying.wearable():
		hand.wear()


## Pocket `slot` and the mouse's hand: swapped.
func _pocket(slot: int) -> void:
	var hand := studio.get_node_or_null("MouseHand") as Interactor
	if hand == null or hand.pockets == null:
		return
	if hand.swap_pocket(slot):
		_say_pockets(hand)
	else:
		Session.notice.emit("Your %s pocket is empty." % Pockets.NAMES[slot])


func _say_pockets(hand: Interactor) -> void:
	Session.notice.emit("Pockets: %s" % hand.pockets.summary())


## Put down whatever any hand here is carrying, where it is aiming.
func put_down_items() -> void:
	for hand in studio.get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and interactor.carrying != null:
			interactor.put_down()


func _build_walker() -> void:
	studio.walker = Walker.new()
	studio.walker.name = "Walker"
	studio.walker.camera = studio.camera
	studio.walker.floor_plan = studio.floor_plan
	studio.walker.walkable = studio.venue_look._walkable()
	studio.walker.fixed = studio.venue.solids() if studio.venue != null else []
	studio.walker.ceiling = studio.venue_look._ceiling()
	studio.walker.ceiling_at = studio.venue_look._ceiling_at
	studio.walker.solids_parent = studio.studio_set
	studio.walker.standing_eye = studio.ergonomics.eye_height
	studio.walker.eye_height = studio.ergonomics.eye_height
	studio.add_child(studio.walker)
	studio.floor_plan.bodies.append(studio.walker.body_footprint)
	# At the mix position, looking down at the desk. Aimed at a POINT on it rather than set to
	# an angle, because the desk does not move when the eye does: -0.5 rad was right from a
	# standing 1.62 m and, from a seated 1.21 m, put the faders' tops up under the timeline.
	studio.walker.global_position = Vector3(0, 0, Studio.MIX_POSITION_Z)
	studio.walker.pitch = -atan2(studio.ergonomics.eye_height - DESK_GAZE.y, DESK_GAZE.x)
	studio.walker.active = not studio.god_mode
	studio.walker._place_camera()


## Swap between walking and flying. The handover keeps the view: going up, the orbit takes the
## walker's eye and a point in front of it; coming down, the walker lands under wherever the
## camera was, inside the room, facing the same way.
func set_god_mode(on: bool) -> void:
	studio.god_mode = on
	if studio.walker == null:
		return
	studio.walker.active = not on
	if on:
		var forward := -studio.walker.look_basis().z
		var at := studio.walker.eye() + forward * 1.6
		studio.view_host.frame(at, 1.6, studio.walker.yaw, studio.walker.pitch)
	else:
		var from := studio.camera.global_position
		var b := studio.floor_plan.bounds if studio.floor_plan != null else Rect2(-3, -2, 6, 4.8)
		studio.walker.global_position = Vector3(clampf(from.x, b.position.x + 0.3, b.end.x - 0.3), 0.0,
				clampf(from.z, b.position.y + 0.3, b.end.y - 0.3))
		studio.walker.velocity = Vector3.ZERO
		studio.walker.yaw = studio._orbit_yaw
		studio.walker.pitch = clampf(studio._orbit_pitch, -1.2, 0.6)
		studio.walker.eye_height = studio.walker.standing_eye
		studio.walker._place_camera()
