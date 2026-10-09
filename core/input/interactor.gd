class_name Interactor
extends Node3D

## One hand, or one mouse cursor, reaching into the scene.
##
## Subclasses supply only an aim ray and a press state; everything about finding a control and
## driving it lives here. A session can have several of these active at once and they do not
## coordinate: four people with two hands each is eight interactors, and the arbitration of two
## of them wanting the same fader happens in ControlAffordance, which is the thing that knows
## what being held means.

const RAY_LENGTH := 3.0
## Layer 2 is controls. Separate from the room's geometry so a ray does not stop on the console
## chassis a centimetre in front of the fader it was aimed at.
const CONTROL_LAYER := 2
const GROUP := &"interactors"
## The carrying glove a mouse draws, against a ghost's 1.25: it is half a metre from your eye.
const CARRY_GLOVE_SIZE := 0.75

## This hand closed on a control and the control took it. Not emitted for a dwell, which is a
## press and release in one frame and holds nothing long enough for anyone else to want it.
signal grabbed(control: ControlAffordance)
## `control` is null when the control was freed under the hand rather than let go of.
signal released(control: ControlAffordance)

var held: ControlAffordance = null
var hovered: ControlAffordance = null
## What this hand is carrying (docs/items_loop.md). Not `held`: a control is held for as long as
## the button is down, an item from the moment it is picked up until it is put down, and the
## button meanwhile USES it -- unless the ray is on a control, which it works as ever, so you
## can mix with a duck in your hand.
var carrying: Item = null
## Where on `hovered` the ray landed, in world space. For a control that is one thing to the
## hand and many to the eye -- a lane of items -- the readout depends on which part is under it.
var hover_point := Vector3.ZERO

var _was_pressed := false
var _held_id := 0
var _rim: HoverRim
var _dwelling: ControlAffordance = null
var _dwelt := 0.0
var _dwell_spent := false
var _using := false
var _glove: Glove


## Override: where this interactor is pointing from and in which direction.
func aim() -> Transform3D:
	return global_transform


## Override: a reading along a straight line, for controls that would rather be dragged than
## twisted. A mouse returns its pointer's height in pixels; a hand returns NAN, because a hand
## can actually turn a knob and should.
func drag_reading() -> float:
	return NAN


## Override: is the fine-adjust modifier held. Shift on a keyboard; nothing yet on a hand.
func fine() -> bool:
	return false


## Override: how far this interactor's ray reaches. A hand's ray is for things within a step or
## two; a cursor is aimed at a picture of the whole room, and furniture across it is fair game.
func reach() -> float:
	return RAY_LENGTH


## Override: is the trigger / mouse button / pinch currently down.
func is_pressing() -> bool:
	return false


## Override: where a carried item rides, in world space. A controller carries it where it is; a
## mouse has nowhere to hold anything, so it rides low in the view (MouseInteractor).
func carry_pose() -> Transform3D:
	return aim()


## Override: whether this hand needs drawing to be seen holding something. A controller is
## drawn by the headset's rig; a mouse is nothing, so it gets a glove of its own to carry with.
func draws_own_hand() -> bool:
	return false


## Take `item` into this hand. Whatever it was carrying goes home: one thing at a time, until
## there are pockets.
func pick_up(item: Item) -> void:
	if carrying == item:
		return
	if carrying != null and is_instance_valid(carrying):
		var room := ItemRoom.of(carrying)
		if room != null:
			room.send_home(carrying)
		else:
			carrying.go_home()
	_end_use()
	carrying = item
	item.take_into(self)
	if _glove != null:
		_glove.poke(-0.3)


## Put down what this hand carries, where it is aiming: on the floor if it can stay there,
## otherwise home to its shelf (ItemRoom.put_down).
func put_down() -> void:
	if carrying == null or not is_instance_valid(carrying):
		carrying = null
		return
	_end_use()
	var item := carrying
	var room := ItemRoom.of(item)
	if room != null:
		room.put_down(item, aim())
	else:
		item.go_home()
	if _glove != null:
		_glove.poke(0.3)


## The host gave what this hand picked up to somebody who reached it first: it is theirs, and
## the hand is empty. Where it goes now is for whoever has it (Presence).
func lose_carrying() -> void:
	if carrying == null or not is_instance_valid(carrying):
		carrying = null
		return
	_end_use()
	var item := carrying
	carrying = null
	if item.carried_by == self:
		item.carried_by = null
	if _glove != null:
		_glove.poke(0.3)


func _end_use() -> void:
	if _using and carrying != null and is_instance_valid(carrying):
		carrying.work(false)
	_using = false


func _physics_process(_delta: float) -> void:
	_forget_freed()
	var pressed := is_pressing()
	var origin := aim().origin
	var direction := -aim().basis.z

	var hit := _cast(origin, direction)
	_set_hovered(hit["control"])
	if hit["control"] != null:
		hover_point = hit["point"]

	# Not `carrying != null`: a freed item compares equal to null (see _forget_freed).
	if not is_instance_valid(carrying):
		carrying = null
	if pressed and not _was_pressed:
		if hovered == null and carrying != null:
			# Nothing under the ray, something in the hand: the button is the item's.
			_using = true
			carrying.work(true)
		elif hovered != null:
			hovered.grab_begin(self, hit["point"])
			# Only if it took the hand. A control someone else is holding says no, and a hand
			# that believed it was holding anyway would drag nothing and then "release" a fader
			# out from under the person who really has it.
			if hovered.held_by == self:
				held = hovered
				_held_id = held.get_instance_id()
				grabbed.emit(held)
	elif pressed and held != null:
		# Keeps driving the held control even once the ray has wandered off it. A fader dragged
		# to the end of its travel is no longer under the cursor, and letting the grab lapse
		# there makes long throws impossible.
		held.grab_move(self, _plane_point(origin, direction, held))
	elif not pressed and held != null:
		let_go()
	if not pressed and _using:
		_end_use()

	_was_pressed = pressed
	_show_glove()
	_tick_dwell(hit["point"], _delta)
	_show_rim()


## A control can be freed under the hand: a bank moves, a rack page turns, a desk is rebuilt
## when the project's tracks arrive -- sometimes from inside the very grab_move that changed
## the mix. Whatever it was, it is not held or hovered now. Checked again before anything is
## drawn from them, because the free can land between the top of a tick and the bottom.
##
## By instance id, not `held != null`: a freed object compares equal to null, so that test
## waves exactly the case it exists for straight through.
func _forget_freed() -> void:
	if _held_id != 0 and not is_instance_id_valid(_held_id):
		_held_id = 0
		held = null
		released.emit(null)
	if not is_instance_valid(held):
		held = null
	if not is_instance_valid(hovered):
		hovered = null


## The held control wins over the hovered one: during a long fader throw the cursor is
## somewhere else entirely, and the rim jumping to whatever it is passing over would say the
## grab had let go.
func _show_rim() -> void:
	if _rim == null:
		_rim = HoverRim.new()
		_rim.name = "HoverRim"
		add_child(_rim)
	_forget_freed()
	_rim.show_on(held if held != null else hovered, held != null)


## Looking at something long enough to mean it.
##
## Reads its timing from the person rather than from a constant, and is off at zero, which is
## the default -- an always-on dwell would fire at anything the eye rests on.
##
## Cancelled by a press rather than racing it: someone who dwells half way and then presses has
## pressed, and the dwell must not fire a second time a moment later. The same reasoning kills
## the dwell when the ray moves to a different control, because a dwell that survives looking
## away is not measuring attention any more.
func _tick_dwell(at: Vector3, delta: float) -> void:
	var seconds: float = Ergonomics.current.dwell_seconds
	var target: ControlAffordance = hovered
	if seconds <= 0.0 or held != null or is_pressing() \
			or target == null or not target.dwell_activates():
		target = null

	if target != _dwelling:
		if _dwelling != null and is_instance_valid(_dwelling):
			_dwelling.set_dwell_progress(0.0)
		_dwelling = target
		_dwelt = 0.0
		_dwell_spent = false
	# Spent until the gaze leaves. Without this latch the count simply restarts the frame after
	# it fires and the button holds itself down -- which is what happened, and is a far worse
	# failure than not firing at all, because it is a command repeating at the frame rate.
	if _dwelling == null or _dwell_spent:
		return

	_dwelt += delta
	if _dwelt < seconds:
		_dwelling.set_dwell_progress(_dwelt / seconds)
		return

	# Fired. A press and a release, because that is what the control is expecting -- a dwell is
	# a different way to say the same thing, not a different thing to say.
	_dwell_spent = true
	_dwelt = 0.0
	_dwelling.set_dwell_progress(0.0)
	_dwelling.grab_begin(self, at)
	_dwelling.grab_end(self)


## The glove a mouse carries with, low in the view, palm up under whatever it holds. Only drawn
## in your own view: the mirror shows your ghost's glove instead.
func _show_glove() -> void:
	if not draws_own_hand():
		return
	var holding := carrying != null and is_instance_valid(carrying)
	if _glove == null:
		if not holding:
			return
		_glove = Glove.new(-1.0)
		_glove.name = "CarryGlove"
		_glove.size = CARRY_GLOVE_SIZE
		add_child(_glove)
		for node in _glove.find_children("*", "VisualInstance3D", true, false):
			(node as VisualInstance3D).layers = Mirror.NOT_REFLECTED
			if node is GeometryInstance3D:
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glove.visible = holding
	if not holding:
		return
	var at := carry_pose()
	# Palm up, fingers forward and in toward the middle of the view, the heel of the hand under
	# the item and a little behind it.
	var fingers := (at.basis * Vector3(0.45, 0.0, -1.0)).normalized()
	var palm := at.basis * Vector3.UP
	var z := -fingers
	var y := -palm - z * (-palm).dot(z)
	y = y.normalized()
	_glove.target = Transform3D(Basis(y.cross(z), y, z),
			at.origin + at.basis * Vector3(0.0, -0.028, 0.02) * CARRY_GLOVE_SIZE)
	_glove.pose = Glove.Pose.GRIP if _using else Glove.Pose.OPEN


func _set_hovered(control: ControlAffordance) -> void:
	if control == hovered:
		return
	if hovered != null and is_instance_valid(hovered):
		hovered.hover_exit(self)
	hovered = control
	if hovered != null:
		hovered.hover_enter(self)


## Let go of everything this interactor is touching, for when it stops existing or stops being
## the way in -- a headset put on, a window losing the mouse. A highlight left behind by a
## cursor that has gone is a control claiming attention nobody is paying.
func _exit_tree() -> void:
	_set_hovered(null)


func _enter_tree() -> void:
	add_to_group(GROUP)


## Open the hand. Also how the session takes a control back from someone who reached for it a
## moment after somebody else did -- see Session.hold_refused.
func let_go() -> void:
	if _held_id == 0 and not is_instance_valid(held):
		return
	var was = held
	held = null
	_held_id = 0
	if is_instance_valid(was):
		was.grab_end(self)
		released.emit(was)
	else:
		released.emit(null)


func _cast(origin: Vector3, direction: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach())
	query.collision_mask = 1 << (CONTROL_LAYER - 1)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return {"control": null, "point": Vector3.ZERO}
	var collider = result["collider"]
	return {"control": collider if collider is ControlAffordance else null, "point": result["position"]}


## Where the aim ray meets the plane the held control moves in. Without this, a grab would need a
## surface to hit, and a fader has none once the cap has moved out from under the cursor.
func _plane_point(origin: Vector3, direction: Vector3, control: ControlAffordance) -> Vector3:
	var basis := control.global_transform.basis
	var plane := Plane(basis.z.normalized(), control.global_position)
	var hit = plane.intersects_ray(origin, direction)
	return hit if hit != null else control.global_position
