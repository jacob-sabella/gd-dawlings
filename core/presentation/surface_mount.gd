class_name SurfaceMount
extends Node3D

## Puts each surface where this particular viewer wants it, and nowhere else.
##
## The mount owns the three anchors a surface can hang from and does the reparenting. It is the
## only place in the project that reads a LayoutProfile, which is what lets every surface stay
## ignorant of presentation: a surface is a node, and a node's parent is not its business.
##
## Reparenting at runtime is the supported operation, not a trick. Someone at the desk pulls the
## console off their monitor and stands it in the room mid-session; the node moves from
## `screen_stage` to `room_anchor` and keeps every control, every grab, and its state cache.

@export var screen_stage: Node3D
@export var room_anchor: Node3D
@export var studio_set: Node3D

## Framing margin. The surface does not fill the viewport edge to edge, because a console whose
## outermost fader is against the frame reads as cropped even when it is not.
const SCREEN_MARGIN := 1.18

## Room left beside the content for the grab handle, in metres.
##
## A fixed allowance rather than part of the measurement, and that is the whole point: the
## handle is placed from the content box, so measuring the handle would grow the box, which
## moves the handle. Its size is a constant, so the space it needs can be one too.
const CHROME_ALLOWANCE := 0.055

## Which modes a tap on a handle walks through, in order.
const MODE_ORDER := [Presentation.Mode.SCREEN, Presentation.Mode.ROOM, Presentation.Mode.STUDIO]

## {surface_id: Surface}
var _mounted: Dictionary = {}
## {surface_id: SurfaceHandle}
var _handles: Dictionary = {}
## {surface_id: Transform3D} -- where the studio placed it, which is the authored layout and the
## only placement in the project a human wrote by hand. Captured at registration because the
## node's own transform stops being that the moment it is first re-anchored.
var _authored: Dictionary = {}


func register(surface: Surface) -> void:
	_mounted[surface.surface_id] = surface
	_authored[surface.surface_id] = surface.transform
	# Re-framed whenever the surface changes shape. Not a refinement: a surface is registered
	# before it has built anything, so the FIRST frame is the one that has nothing to measure,
	# and a console that gained eight tracks is a wider object that no longer fits where it did.
	surface.rebuilt.connect(_on_surface_rebuilt.bind(surface.surface_id))
	# Built here rather than by the surface: a handle has to ask what mode a surface is in and
	# tell the mount to change it, and a surface that could answer either question would be a
	# surface that knows its own presentation. The mount is the one object allowed to.
	var handle := SurfaceHandle.create(surface, self)
	_handles[surface.surface_id] = handle
	surface.add_child(handle)
	apply(surface.surface_id)


## Only when the viewer has not placed it themselves. Re-framing over someone's own placement
## would undo it every time Reaper added a track.
func _on_surface_rebuilt(surface_id: StringName) -> void:
	if not _mounted.has(surface_id):
		return
	var mode := mode_of(surface_id)
	if mode != Presentation.Mode.SCREEN or Session.layout.has_transform(surface_id, mode):
		return
	var surface: Surface = _mounted[surface_id]
	if surface.get_parent() == screen_stage:
		surface.transform = _framed_transform(surface)


## Re-anchor one surface according to the local profile.
func apply(surface_id: StringName) -> void:
	if not _mounted.has(surface_id):
		return
	# A surface the focus rig has summoned is not in a mode's anchor and must not be dragged back
	# into one. Nothing calls this while a surface is summoned today, so the guard is not fixing
	# a live bug -- it is making the ownership explicit, because the mount and the rig both write
	# surface transforms and the failure when they disagree is silent: the surface simply ends up
	# somewhere, and the render still looks like a studio.
	if held.is_valid() and held.call(surface_id):
		return
	var surface: Surface = _mounted[surface_id]
	var mode := Session.layout.mode_for(surface_id, surface.surface_kind)
	var target := _anchor_for(mode)
	if target == null:
		push_warning("SurfaceMount: no anchor for mode %s; leaving %s where it is." % [Presentation.MODE_NAMES.get(mode, mode), surface_id])
		return
	if surface.get_parent() == target:
		return
	surface.get_parent().remove_child(surface)
	target.add_child(surface)
	# Placement is per-mode: a console at arm's reach in the room is not the same object as a
	# panel framed to fill a monitor, so the transform is fetched for the mode being entered --
	# never carried over from the one being left.
	surface.transform = Session.layout.transform_for(surface_id, mode, _default_transform(surface, mode))


## Where a surface goes in a mode the viewer has not placed it in yet.
func _default_transform(surface: Surface, mode: int) -> Transform3D:
	var authored: Transform3D = _authored.get(surface.surface_id, Transform3D.IDENTITY)
	if mode == Presentation.Mode.SCREEN:
		return _framed_transform(surface)
	# ROOM and STUDIO are both the authored layout, and that is not a shortcut: the default
	# layout was written at real heights -- desk at 0.74m, bay at eye level over it -- precisely
	# so that it describes a believable control room whether the room is virtual or real.
	return authored


## Centre the surface in front of the camera and push it back until it fits.
##
## Computed rather than chosen, because the thing being framed changes size with the project.
## Falls back to the authored placement if the surface has not built its geometry yet, which is
## the case on the very first frame -- a guessed distance there would be visibly wrong and then
## silently stay wrong, since nothing recomputes it.
func _framed_transform(surface: Surface) -> Transform3D:
	var camera := screen_stage.get_parent() as Camera3D if screen_stage else null
	var bounds := surface.content_aabb()
	if camera == null or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return _authored.get(surface.surface_id, Transform3D.IDENTITY)

	var basis := Basis(Vector3.RIGHT, deg_to_rad(surface.screen_pitch_degrees))
	# Transform3D, not Basis: a Basis cannot transform an AABB, and what is wanted here is the
	# footprint of the box once it has been pitched back.
	var pitched := Transform3D(basis, Vector3.ZERO) * bounds
	var half_v := tan(deg_to_rad(camera.fov) * 0.5)
	var aspect := float(camera.get_viewport().get_visible_rect().size.aspect())
	var distance := maxf(
			pitched.size.y * 0.5 / half_v,
			(pitched.size.x * 0.5 + CHROME_ALLOWANCE) / (half_v * aspect)) * SCREEN_MARGIN

	# The surface's own origin is not its centre -- a console's origin is at the front edge of
	# the desk -- so the centre is what gets put on the axis, and the origin follows from it.
	var centre_in_camera := Vector3(0, 0, -distance)
	var origin_in_camera := centre_in_camera - basis * bounds.get_center()
	return screen_stage.transform.affine_inverse() * Transform3D(basis, origin_in_camera)


## Asked before re-anchoring anything: does something else currently own this surface's
## transform? Left unset when there is no focus rig, in which case the mount owns everything.
var held: Callable = Callable()


func apply_all() -> void:
	for id in _mounted:
		apply(id)


## Move one surface to a different mode and remember it.
func set_mode(surface_id: StringName, mode: int) -> void:
	Session.layout.set_mode(surface_id, mode)
	apply(surface_id)
	Session.layout.save()
	_refresh_handle(surface_id)


## The next mode a tap on this surface's handle will move it to.
##
## Skips modes with no anchor in this session rather than cycling into them: an AR participant
## has no virtual set, and a tap that parked the console in a studio that is not being drawn
## would make it vanish with no way to get it back.
func next_mode(surface_id: StringName) -> int:
	var here := mode_of(surface_id)
	var order := available_modes()
	if order.is_empty():
		return here
	var at := order.find(here)
	return order[(at + 1) % order.size()] if at >= 0 else order[0]


## The modes this session can actually put a surface in, in cycle order.
func available_modes() -> Array:
	var out: Array = []
	for mode in MODE_ORDER:
		if _anchor_for(mode) != null:
			out.append(mode)
	return out


## Move a surface one step round the cycle. What a handle tap does.
func cycle_mode(surface_id: StringName) -> void:
	var next := next_mode(surface_id)
	if next != mode_of(surface_id):
		set_mode(surface_id, next)
	_refresh_handle(surface_id)


## Keep where the viewer just dragged this surface to, for the mode it is currently in.
func remember_placement(surface_id: StringName) -> void:
	if not _mounted.has(surface_id):
		return
	var surface: Surface = _mounted[surface_id]
	Session.layout.set_transform(surface_id, mode_of(surface_id), surface.transform)
	Session.layout.save()


## Where a surface stands in the virtual set, whether or not it is there right now: the
## viewer's own placement if they made one, the authored layout if not.
func studio_home(surface_id: StringName) -> Transform3D:
	return Session.layout.transform_for(surface_id, Presentation.Mode.STUDIO,
			_authored.get(surface_id, Transform3D.IDENTITY))


func handle_for(surface_id: StringName) -> SurfaceHandle:
	return _handles.get(surface_id)


func _refresh_handle(surface_id: StringName) -> void:
	var handle: SurfaceHandle = _handles.get(surface_id)
	if handle != null:
		handle.refresh()


func mounted_ids() -> Array:
	var ids := _mounted.keys()
	ids.sort()
	return ids


func mode_of(surface_id: StringName) -> int:
	if not _mounted.has(surface_id):
		return Presentation.Mode.STUDIO
	var surface: Surface = _mounted[surface_id]
	return Session.layout.mode_for(surface_id, surface.surface_kind)


## Put a surface back where the studio put it, in the mode it is currently in. The escape hatch
## for a placement dragged somewhere unreachable, which in a headset is a real way to lose a
## console entirely.
func reset_placement(surface_id: StringName) -> void:
	if not _mounted.has(surface_id):
		return
	var surface: Surface = _mounted[surface_id]
	var mode := mode_of(surface_id)
	Session.layout.local_transforms.erase(LayoutProfile._key(surface_id, mode))
	surface.transform = _default_transform(surface, mode)
	Session.layout.save()
	_refresh_handle(surface_id)


func _anchor_for(mode: int) -> Node3D:
	match mode:
		Presentation.Mode.SCREEN: return screen_stage
		Presentation.Mode.ROOM: return room_anchor
		Presentation.Mode.STUDIO: return studio_set
	return null
