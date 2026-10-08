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

var held: ControlAffordance = null
var hovered: ControlAffordance = null

var _was_pressed := false
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


## Override: is the trigger / mouse button / pinch currently down.
func is_pressing() -> bool:
	return false


func _physics_process(_delta: float) -> void:
	var pressed := is_pressing()
	var origin := aim().origin
	var direction := -aim().basis.z

	var hit := _cast(origin, direction)
	_set_hovered(hit["control"])

	if pressed and not _was_pressed:
		if hovered != null:
			held = hovered
			held.grab_begin(self, hit["point"])
	elif pressed and held != null:
		# Keeps driving the held control even once the ray has wandered off it. A fader dragged
		# to the end of its travel is no longer under the cursor, and letting the grab lapse
		# there makes long throws impossible.
		held.grab_move(self, _plane_point(origin, direction, held))
	elif not pressed and held != null:
		held.grab_end(self)
		held = null

	_was_pressed = pressed
	_tick_dwell(hit["point"], _delta)
	_show_rim()


## The held control wins over the hovered one: during a long fader throw the cursor is
## somewhere else entirely, and the rim jumping to whatever it is passing over would say the
## grab had let go.
func _show_rim() -> void:
	if _rim == null:
		_rim = HoverRim.new()
		_rim.name = "HoverRim"
		add_child(_rim)
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


func _cast(origin: Vector3, direction: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_LENGTH)
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
