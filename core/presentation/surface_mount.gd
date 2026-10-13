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
##
## Was 1.18 -- every SCREEN-mode surface (console, rack, patchbay, timeline) read smaller than
## it needed to (2026-10-11: "everything...is too damn hard to read... all so small"). Lowered
## toward 1.0 rather than all the way to it, so there is still a sliver of edge left for the
## grab handle and the surface does not read as cropped.
const SCREEN_MARGIN := 1.08

## Room left beside the content for the grab handle, in metres.
##
## A fixed allowance rather than part of the measurement, and that is the whole point: the
## handle is placed from the content box, so measuring the handle would grow the box, which
## moves the handle. Its size is a constant, so the space it needs can be one too.
const CHROME_ALLOWANCE := 0.055

## How far from the eye a panel on the monitor actually sits, in metres. See _framed_transform.
const SCREEN_NEAR := 0.42

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


## Surfaces that stand on a piece of furniture in the studio: id -> Callable() -> Transform3D,
## where that furniture holds the surface right now.
##
## A seated surface has no studio placement of its own. It used to, saved beside its stand's,
## and the two drifted apart by every path that moved one and not the other -- RESET put the
## deck back on its authored spot and left the trolley across the room; a drag by the deck's own
## handle saved the deck and not the trolley -- until the timeline floated a metre from its
## stand, square to the room while the stand stood at forty-five degrees. Deriving one from the
## other makes that state unrepresentable instead of merely unlikely.
var seats: Dictionary = {}
## Called with (id, where it was put down) when a seated surface is dragged by its own handle in
## the studio: the furniture is moved under it, because gear does not hang in the air.
var reseat: Callable = Callable()
## Where the room has gear that stands on nothing, when the room is someone else's: id ->
## Transform3D, over this viewer's own studio placement. Their own is kept for later.
var shared_studio: Dictionary = {}
## Called with (id, transform) when a surface that stands on nothing is put down in the studio.
## True means it was dealt with -- sent to whoever keeps the room -- and is not this viewer's to
## remember; false, and it is saved here as usual.
var studio_placed: Callable = Callable()


func seat(surface_id: StringName, where: Callable) -> void:
	seats[surface_id] = where
	# Whatever was saved for it separately is from before it had a seat, and is the drift.
	Session.layout.local_transforms.erase(LayoutProfile._key(surface_id, Presentation.Mode.STUDIO))
	if not _mounted.has(surface_id) or (held.is_valid() and held.call(surface_id)):
		return
	var surface: Surface = _mounted[surface_id]
	if mode_of(surface_id) == Presentation.Mode.STUDIO and surface.get_parent() == studio_set:
		surface.transform = where.call()


func authored_of(surface_id: StringName) -> Transform3D:
	return _authored.get(surface_id, Transform3D.IDENTITY)


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
	surface.set_wide(mode == Presentation.Mode.SCREEN)
	if surface.get_parent() == target:
		return
	surface.get_parent().remove_child(surface)
	target.add_child(surface)
	# Placement is per-mode: a console at arm's reach in the room is not the same object as a
	# panel framed to fill a monitor, so the transform is fetched for the mode being entered --
	# never carried over from the one being left.
	if mode == Presentation.Mode.STUDIO and (seats.has(surface_id) or shared_studio.has(surface_id)):
		surface.transform = studio_home(surface_id)
		return
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
	var by_width := (pitched.size.x * 0.5 + CHROME_ALLOWANCE) / (half_v * aspect) * SCREEN_MARGIN
	var distance := maxf(pitched.size.y * 0.5 / half_v * SCREEN_MARGIN, by_width)
	var lift := 0.0
	if surface.screen_top >= 0.0:
		# Hung from the top of the frame: as close as the band and the width allow, then raised
		# until its top edge is where it was asked to be.
		distance = maxf(pitched.size.y / (2.0 * half_v * surface.screen_band), by_width)
		var half_view := distance * half_v
		lift = half_view * (1.0 - 2.0 * surface.screen_top) - pitched.size.y * 0.5

	# Then the whole framing is shrunk toward the eye until it sits at SCREEN_NEAR. It looks the
	# same -- the same angle at the eye -- but a panel a metre out is IN the room, and a room
	# has a patchbay at that distance: its jacks drew behind the timeline and still took the
	# clicks aimed at it. Nearer than any furniture can stand, nothing comes between.
	var k := minf(1.0, SCREEN_NEAR / distance)
	# The surface's own origin is not its centre -- a console's origin is at the front edge of
	# the desk -- so the centre is what gets put on the axis, and the origin follows from it.
	var centre_in_camera := Vector3(0, lift, -distance) * k
	var scaled := basis.scaled(Vector3.ONE * k)
	var origin_in_camera := centre_in_camera - scaled * bounds.get_center()
	return screen_stage.transform.affine_inverse() * Transform3D(scaled, origin_in_camera)


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
	if mode_of(surface_id) == Presentation.Mode.STUDIO and seats.has(surface_id):
		if reseat.is_valid():
			reseat.call(surface_id, surface.transform)
		surface.transform = studio_home(surface_id)
		_refresh_handle(surface_id)
		return
	if mode_of(surface_id) == Presentation.Mode.STUDIO and studio_placed.is_valid() \
			and studio_placed.call(surface_id, surface.transform):
		return
	Session.layout.set_transform(surface_id, mode_of(surface_id), surface.transform)
	Session.layout.save()


## Stand the room's gear where the room says, or, with an empty `placements`, back where this
## viewer had it. Only what is standing in the studio right now moves; the rest goes there when
## it next comes back.
## `seconds` above zero slides it there rather than putting it there.
func share_studio(placements: Dictionary, seconds := 0.0) -> void:
	shared_studio = placements
	for surface_id in _mounted:
		if seats.has(surface_id) or mode_of(surface_id) != Presentation.Mode.STUDIO:
			continue
		if held.is_valid() and held.call(surface_id):
			continue
		var surface: Surface = _mounted[surface_id]
		if surface.get_parent() != studio_set:
			continue
		var to := studio_home(surface_id)
		if surface.transform.is_equal_approx(to):
			continue
		if seconds > 0.0 and surface.is_inside_tree():
			var slide := surface.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			slide.tween_property(surface, "transform", to, seconds)
		else:
			surface.transform = to


## Where a surface stands in the virtual set, whether or not it is there right now: the
## viewer's own placement if they made one, the authored layout if not.
func studio_home(surface_id: StringName) -> Transform3D:
	if seats.has(surface_id):
		return (seats[surface_id] as Callable).call()
	if shared_studio.has(surface_id):
		return shared_studio[surface_id]
	return Session.layout.transform_for(surface_id, Presentation.Mode.STUDIO,
			_authored.get(surface_id, Transform3D.IDENTITY))


func handle_for(surface_id: StringName) -> SurfaceHandle:
	return _handles.get(surface_id)


func _refresh_handle(surface_id: StringName) -> void:
	var handle: SurfaceHandle = _handles.get(surface_id)
	if handle != null:
		handle.refresh()


## The surface mounted as `surface_id`, or null.
func surface(surface_id: StringName) -> Surface:
	return _mounted.get(surface_id)


func mounted_ids() -> Array:
	var ids := _mounted.keys()
	ids.sort()
	return ids


func mode_of(surface_id: StringName) -> int:
	if not _mounted.has(surface_id):
		return Presentation.Mode.STUDIO
	var surface: Surface = _mounted[surface_id]
	return Session.layout.mode_for(surface_id, surface.surface_kind)


## Where this surface would be if nobody had ever tapped its handle: what KEY_ESCAPE in
## scenes/studio.gd puts a surface back to when it finds it filling the screen without that
## being the default -- the handle is a 6x3.4cm bar in a corner, easy to catch by accident
## reaching for something beside it, and once its surface fills the view the handle is off at
## the new edge of a much bigger picture, which is a hard thing to go find to undo the mistake.
func default_mode_of(surface_id: StringName, medium: int) -> int:
	if not _mounted.has(surface_id):
		return Presentation.Mode.STUDIO
	var surface: Surface = _mounted[surface_id]
	return Presentation.default_mode(surface.surface_kind, medium)


## Put a surface back where the studio put it, in the mode it is currently in. The escape hatch
## for a placement dragged somewhere unreachable, which in a headset is a real way to lose a
## console entirely.
func reset_placement(surface_id: StringName) -> void:
	if not _mounted.has(surface_id):
		return
	var surface: Surface = _mounted[surface_id]
	var mode := mode_of(surface_id)
	if mode == Presentation.Mode.STUDIO and not seats.has(surface_id) and studio_placed.is_valid() \
			and studio_placed.call(surface_id, _authored.get(surface_id, surface.transform)):
		return
	Session.layout.local_transforms.erase(LayoutProfile._key(surface_id, mode))
	# On its stand, wherever the stand is: the stand is where it lives.
	surface.transform = studio_home(surface_id) if mode == Presentation.Mode.STUDIO \
			and seats.has(surface_id) else _default_transform(surface, mode)
	Session.layout.save()
	_refresh_handle(surface_id)


func _anchor_for(mode: int) -> Node3D:
	match mode:
		Presentation.Mode.SCREEN: return screen_stage
		Presentation.Mode.ROOM: return room_anchor
		Presentation.Mode.STUDIO: return studio_set
	return null
