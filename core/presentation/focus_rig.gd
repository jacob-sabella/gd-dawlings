class_name FocusRig
extends Node3D

## Brings the thing you are working on to you, and puts everything else where you can still see
## it. The move a control room cannot make.
##
## WHY THIS IS THE POINT OF BEING IN 3D AT ALL. A mixer on a screen shows ninety channels with
## no travel; this room made you walk to them, which is worse. The space has to pay that back,
## and here is the payment: in a volume, "maximise this window" costs nothing and loses nothing.
## The focused surface comes to arm's length at the size your eyes want, and the others do not
## close, minimise or go behind a tab -- they arc out to the edge of vision at full size, still
## live, still readable at a glance, one head turn away. No screen can do that. It is also the
## only arrangement in which a ninety-track desk is navigable without scrolling.
##
## FOCUS IS NOT A MODE. Presentation.Mode says where a surface LIVES -- on a monitor, in the
## physical room, in the virtual set -- and that is a preference someone sets once and keeps.
## Focus is what they are doing this minute. Conflating the two would persist an attention
## state into a layout profile and hand someone back a session with the compressor still in
## their face from last Tuesday.
##
## Everything here is placed in a BodyFrame, never on the head: see body_frame.gd for why that
## distinction is the difference between comfortable and nauseating.

## Where the first pair of unfocused surfaces sits, in degrees either side. Just past the edge
## of a comfortable head turn: present at the corner of your eye, out of the way of the work.
const FIRST_BEARING := 62.0
## How much further round each pair after that goes.
const BEARING_STEP := 34.0
## The furthest anything is ever parked. A shoulder-assisted turn, and a hard stop.
##
## The first version of this spaced the arc by multiples of the head turn and ran off the back
## of the person: with five surfaces it put two of them at 132 degrees, behind the shoulders,
## where "still visible at a glance" is simply false. An arc around a body is bounded by the
## body, and anything that does not fit inside the bound is a sign there are too many surfaces
## out at once -- which is a real answer, not a reason to keep going round.
const MAX_BEARING := 112.0
## How much further out the peripheral arc sits than the focused surface. Things at the edge of
## vision are glanced at, not read, so they go further away and more of them fit.
##
## Applied to a RING, not to each surface's own ideal distance. Scaling each one individually is
## what put a small surface at 0.47m while the focused rack sat at 0.98m -- parked gear nearer
## than the work, which is backwards, and close enough to collide with it.
const PERIPHERAL_PUSH := 1.35

signal focus_changed(surface_id: StringName)

var ergonomics := Ergonomics.new()
var body: BodyFrame
## The surfaces this rig may summon, in the order a cycle walks them.
var surfaces: Array[Surface] = []
## Called with (surface, parent, local_transform). The rig decides WHERE a surface goes and
## WHOSE frame it goes in; it does not decide whether getting there is a cut, a tween or a
## reparent, because that is a comfort setting and belongs to the person.
var move: Callable = Callable()

var focused_id: StringName = &""

## {surface_id: [parent, local Transform3D]} -- where it was before anything was summoned.
var _home: Dictionary = {}


## True while this rig, and not the mount, owns where that surface is.
func holds(surface_id: StringName) -> bool:
	return _home.has(surface_id)


func is_focused() -> bool:
	return focused_id != &""


## Re-place everything whenever any surface changes shape.
##
## Not a refinement. Every distance here is derived from how big a surface is and how small its
## smallest label is, and both of those change when Reaper adds a track -- so a placement
## computed once is a placement computed from a surface that no longer exists. It is also the
## difference between --focus working and not: surfaces are placed at startup, before any of
## them has built its geometry, so the FIRST placement is always made from an empty box. Without
## this, every summoned surface sat bunched at the fallback distance with nothing ever
## correcting it, and the renders looked exactly like a studio where focus had never run.
func _ready() -> void:
	for surface in surfaces:
		surface.rebuilt.connect(_on_surface_rebuilt)


func _on_surface_rebuilt() -> void:
	if is_focused():
		_apply()


## Pull one surface to the working place and arc the rest out around it.
func focus(surface_id: StringName) -> void:
	if surface_id == focused_id:
		return
	focused_id = surface_id
	_apply()
	focus_changed.emit(focused_id)


## Back to wherever everything was before anything was focused.
func release() -> void:
	if not is_focused():
		return
	focused_id = &""
	for surface in surfaces:
		if is_instance_valid(surface) and _home.has(surface.surface_id):
			var home: Array = _home[surface.surface_id]
			surface.compact = false
			_unmark(surface)
			_move(surface, home[0], home[1])
	_home.clear()
	focus_changed.emit(focused_id)


## Step to the next surface, or into the first one if nothing is focused.
func cycle(direction: int) -> void:
	var ids := surfaces.filter(func(s): return is_instance_valid(s)).map(
			func(s): return s.surface_id)
	if ids.is_empty():
		return
	if not is_focused():
		focus(ids[0] if direction >= 0 else ids[ids.size() - 1])
		return
	var at := ids.find(focused_id)
	if at < 0:
		focus(ids[0])
		return
	var next := at + signi(direction if direction != 0 else 1)
	# Off either end releases rather than wrapping. Wrapping a cycle with no exit means the only
	# way back to the room is to know about a second key; walking off the end is discoverable.
	if next < 0 or next >= ids.size():
		release()
		return
	focus(ids[next])


## Where a surface goes while `focused_id` is the one in hand. Pure, so the arrangement can be
## checked without a camera, a body or a frame of engine time.
func placement(surface: Surface, index_among_unfocused: int) -> Transform3D:
	var bounds := surface.content_aabb()
	var cap := smallest_cap(surface)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		# Nothing built yet, so there is nothing to measure and no honest place to put it. Left
		# where it is, and the rebuild that follows will place it properly.
		return _local_home(surface)
	if surface.surface_id == focused_id:
		return ergonomics.place(0.0, bounds, true, cap)
	var out := ergonomics.place(bearing_for(index_among_unfocused), bounds, false, cap)
	# Put on the common ring along its own bearing, which keeps it facing the viewer rather than
	# sliding sideways out of square.
	return Transform3D(out.basis, out.origin.normalized() * ring_radius())


## Degrees either side of straight ahead for the nth parked surface, alternating left and right
## so the arc fills outward from the work rather than growing off one shoulder.
static func bearing_for(index: int) -> float:
	var pair := index / 2
	var side := 1.0 if index % 2 == 0 else -1.0
	return side * minf(FIRST_BEARING + pair * BEARING_STEP, MAX_BEARING)


## One distance for every parked surface, far enough out that the largest of them still fits in
## a glance and that none of them is nearer than the work.
##
## A common ring and not a per-surface distance, because the arc is read as an arc: surfaces at
## five different radii do not look parked, they look scattered, and the near ones crowd the
## thing you are actually using.
func ring_radius() -> float:
	var radius := 0.0
	for surface in surfaces:
		radius = maxf(radius, ergonomics.fits_in_sweep(surface.content_aabb().size))
	radius *= PERIPHERAL_PUSH
	if focused_id != &"":
		for surface in surfaces:
			if surface.surface_id == focused_id:
				radius = maxf(radius, ergonomics.place(0.0, surface.content_aabb(),
						true, smallest_cap(surface)).origin.length() * 1.05)
	return radius


## The smallest lettering anywhere on this surface, which is what decides how close it has to
## be. The smallest and not the average: a surface is readable when its worst label is, and the
## worst label on a console is the one naming the track, which is the one you need.
static func smallest_cap(surface: Surface) -> float:
	var smallest := INF
	for node in surface.find_children("*", "Label3D", true, false):
		var label: Label3D = node
		if label.text.is_empty() or not label.visible:
			continue
		smallest = minf(smallest, Lettering.cap_height(label))
	return 0.0 if is_inf(smallest) else smallest


## Put, or update, the corner brackets on a surface this rig is holding.
##
## Owned by the rig and not by the surface, for the same reason `compact` is set from out here:
## a surface has no idea whether it is being presented or merely standing in a room, and the
## brackets mean exactly that difference. Grouped as presentation chrome so `content_aabb` does
## not measure them -- they are sized FROM the box, and counting them would grow the box, which
## would resize them, which would grow the box.
func _mark(surface: Surface, focused: bool) -> void:
	var bounds := surface.content_aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var halo := surface.get_node_or_null("FocusHalo") as FocusHalo
	if halo == null:
		halo = FocusHalo.create(bounds, focused)
		halo.add_to_group(&"presentation_chrome")
		surface.add_child(halo)
		return
	halo.refresh(bounds, focused)


func _unmark(surface: Surface) -> void:
	var halo := surface.get_node_or_null("FocusHalo")
	if halo != null:
		surface.remove_child(halo)
		halo.queue_free()


## Where a surface's home is, expressed in the body's frame.
##
## The conversion matters: home is recorded against the parent it came from, and everything this
## rig hands out is relative to the body. Handing back a studio-space transform as a body-space
## one puts the console wherever the viewer happens to be standing.
func _local_home(surface: Surface) -> Transform3D:
	if not _home.has(surface.surface_id) or body == null:
		return surface.transform
	var home: Array = _home[surface.surface_id]
	var parent := home[0] as Node3D
	var world: Transform3D = home[1]
	if parent != null:
		world = parent.global_transform * world
	return body.global_transform.affine_inverse() * world


func _apply() -> void:
	var others := 0
	for surface in surfaces:
		if not is_instance_valid(surface):
			continue
		# Captured on the way in, once, so a cycle between two focused surfaces does not record
		# the summoned position of the first as the place to put it back.
		if not _home.has(surface.surface_id):
			_home[surface.surface_id] = [surface.get_parent(), surface.transform]
		# Out of the room, so out of its room shape. Set before placement is computed, but the
		# rebuild it triggers is batched to the next frame -- which is why placement has to be
		# redone on `rebuilt` rather than only here.
		surface.compact = true
		_mark(surface, surface.surface_id == focused_id)
		var index := 0
		if surface.surface_id != focused_id:
			index = others
			others += 1
		_move(surface, body, placement(surface, index))


## Reparented into the body frame rather than placed in world space, and that is the whole
## mechanism rather than an implementation detail. A surface merely MOVED to arm's length is at
## arm's length from where you were standing when you summoned it; take one step and it is
## behind you. A surface that is a CHILD of the body frame is at arm's length from you, which
## is what was asked for -- and it inherits the deadzone and the damping for free, so the
## comfort rules are enforced by the scene tree instead of by everyone remembering them.
func _move(surface: Surface, parent: Node3D, local: Transform3D) -> void:
	if move.is_valid():
		move.call(surface, parent, local)
		return
	if parent != null and surface.get_parent() != parent:
		surface.reparent(parent, false)
	surface.transform = local
