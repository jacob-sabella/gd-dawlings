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

## This hand closed on a control and the control took it. Not emitted for a dwell, which is a
## press and release in one frame and holds nothing long enough for anyone else to want it.
signal grabbed(control: ControlAffordance)
## `control` is null when the control was freed under the hand rather than let go of.
signal released(control: ControlAffordance)

var held: ControlAffordance = null
var hovered: ControlAffordance = null
## Where on `hovered` the ray landed, in world space. For a control that is one thing to the
## hand and many to the eye -- a lane of items -- the readout depends on which part is under it.
var hover_point := Vector3.ZERO

var _was_pressed := false
var _held_id := 0
var _rim: HoverRim
var _dwelling: ControlAffordance = null
var _dwelt := 0.0
var _dwell_spent := false


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


func _physics_process(_delta: float) -> void:
	_forget_freed()
	var pressed := is_pressing()
	var origin := aim().origin
	var direction := -aim().basis.z

	var hit := _cast(origin, direction)
	_set_hovered(hit["control"])
	if hit["control"] != null:
		hover_point = hit["point"]

	if pressed and not _was_pressed:
		if hovered != null:
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

	_was_pressed = pressed
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
