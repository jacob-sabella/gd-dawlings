class_name FloorPlan
extends Node

## The studio floor: what stands on it, what cannot be walked through, and where the walls are.
##
## A room you can rearrange is only a room if the furniture is SOLID. A rack that slides through
## the console, or out through the wall into the dark, is a picture of a rack being moved, and
## the illusion goes the first time it happens. So every piece on the floor is a footprint -- a
## rectangle at a heading -- and a push is resolved against the others before it is applied.
## Two dimensions, not a physics engine: nothing here falls over or stacks, and a 2D
## separating-axis test is exact for rectangles, cheap, and deterministic enough to test.
##
## ONE PLACE A MOVE IS DECIDED. Today a push is local and the result is saved into this
## participant's layout. When the set is shared, this is the object that has to become the
## authority -- two people shoving the same rack have to agree where it ended up -- and keeping
## the decision in one node rather than in each trolley is what makes that a change to one file.
## Every move already names who made it for the same reason.

signal piece_moved(piece: Node3D, by_participant: int)

## The inside faces of the walls, on the floor, in the set's frame: x and z.
var bounds := Rect2(-3.95, -3.15, 7.90, 5.95)
## More floor past `bounds` that furniture may be pushed onto: the venue's live room behind the
## control room, a side room, the open ground round an open venue (Venue.rooms). Each meets
## `bounds` or another along a shared line, or overlaps it, as the walker's floor does, so a stand
## wheeled through the way into the live room is held by the walls either side of it and nowhere
## else. Empty, the floor is `bounds` alone.
var rooms: Array[Rect2] = []
var pieces: Array[Node3D] = []
## Things that do not move but must not be moved through, each a Callable returning an
## Array of footprints (see `footprint`). A callable rather than a box because the console
## changes width with the project.
var fixtures: Array[Callable] = []
## People: footprints a piece being pushed stops against, each a Callable returning an Array of
## footprints, but which are NOT stood up as walls for the walker (a body is not an obstacle to
## itself). Without them a stand pulled toward you was moved into your own body, the walls threw
## you out of it, your aim went with you, and the stand followed it into you again: a loop that
## pushed you across the room as fast as the frames came. Only for a piece in a hand: a layout
## fitted, or a move played back from the room, puts it where it was put, whoever stands there.
var bodies: Array[Callable] = []
## What a pushed piece stops at that the walker is told about some other way: each a Callable
## returning an Array of footprints. The venue's own fixed things (Venue.solids: the booth, the
## riser, the bricks table, the dividing walls) carry how tall they are for the walker, which
## walks up onto a riser it would stop at as a `fixtures` box; a rack is not walked up onto
## anything, so to the floor plan they are all just in the way.
var stops: Array[Callable] = []


func add_piece(piece: Node3D) -> void:
	if not pieces.has(piece):
		pieces.append(piece)


## A rectangle on the floor: centre, half extents, and heading (the Y rotation of whatever it is
## the footprint of). The shape every collision here is between.
static func footprint(centre: Vector2, half: Vector2, heading: float) -> Dictionary:
	return {"c": centre, "h": half, "a": heading}


## The footprint of a world-space box, flattened onto the floor. For fixtures, which are
## measured from their geometry rather than declared.
static func footprint_of_box(box: AABB) -> Dictionary:
	return footprint(Vector2(box.get_center().x, box.get_center().z),
			Vector2(box.size.x, box.size.z) * 0.5, 0.0)


## Where `piece` may actually go, given where it was asked to.
##
## Returns the position and whether anything was hit. Pushed out along the shallowest axis of
## whatever it overlaps, a few times, because pushing out of one thing can push into another
## and the corner between the console and a wall is exactly where people park racks.
func resolve(piece: Node3D, at: Vector2, heading: float) -> Dictionary:
	var bumped := false
	var others: Array = []
	for other in pieces:
		if other != piece and is_instance_valid(other) and other.is_inside_tree() \
				and other.visible and other.has_method("footprint_at"):
			others.append(other.footprint_at(Vector2(other.position.x, other.position.z),
					other.rotation.y))
	for fixture in fixtures + stops:
		if fixture.is_valid():
			others.append_array(fixture.call())
	for body in bodies:
		if body.is_valid() and piece.get(&"held_by") != null:
			others.append_array(body.call())

	for _pass in 4:
		var mine: Dictionary = piece.footprint_at(at, heading)
		var moved := false
		for other in others:
			var push := separation(mine, other)
			if push != Vector2.ZERO:
				at += push
				mine = piece.footprint_at(at, heading)
				moved = true
		var c: Vector2 = mine["c"]
		var held := _held_on_floor(c, _reach(mine))
		if not held.is_equal_approx(c):
			at += held - c
			moved = true
		bumped = bumped or moved
		if not moved:
			break
	return {"at": at, "bumped": bumped}


## Where a footprint centred at `c`, reaching `reach` along each axis, is nearest to `c` with all
## of it on the floor: `c` itself if it is already. Against one rectangle that is a clamp. Against
## several it is the nearest of each one's clamp, and each one's clamp along one axis only -- the
## second is what lets a stand halfway through the way into the live room slide along it, held by
## the walls either side, rather than being thrown wholly into one room or the other.
func _held_on_floor(c: Vector2, reach: Vector2) -> Vector2:
	var floor: Array[Rect2] = [bounds]
	floor.append_array(rooms)
	if floor.size() == 1 or on_floor(floor, c - reach, c + reach):
		if floor.size() == 1:
			return _clamp_into(bounds, c, reach)
		return c
	var best := Vector2.INF
	var nearest := INF
	var fallback := c
	var fallback_d := INF
	for r in floor:
		var both := _clamp_into(r, c, reach)
		if c.distance_to(both) < fallback_d:
			fallback_d = c.distance_to(both)
			fallback = both
		for at in [both, Vector2(both.x, c.y), Vector2(c.x, both.y)]:
			var d: float = c.distance_to(at)
			if d < nearest and on_floor(floor, at - reach, at + reach):
				nearest = d
				best = at
	return best if nearest < INF else fallback


static func _clamp_into(r: Rect2, c: Vector2, reach: Vector2) -> Vector2:
	var lo := r.position + reach
	var hi := r.end - reach
	return Vector2(clampf(c.x, lo.x, maxf(lo.x, hi.x)), clampf(c.y, lo.y, maxf(lo.y, hi.y)))


## Whether the box from `lo` to `hi` is all on `floor`, a set of rectangles that may meet or
## overlap. Cut along every edge of theirs that crosses it, the box is a grid of cells each wholly
## in a rectangle or wholly out of all of them, so the middle of each cell answers for it.
static func on_floor(floor: Array[Rect2], lo: Vector2, hi: Vector2) -> bool:
	const EDGE := 0.0005
	for r in floor:
		if r.position.x <= lo.x + EDGE and r.position.y <= lo.y + EDGE \
				and r.end.x >= hi.x - EDGE and r.end.y >= hi.y - EDGE:
			return true
	var xs: Array[float] = [lo.x, hi.x]
	var zs: Array[float] = [lo.y, hi.y]
	for r in floor:
		for x in [r.position.x, r.end.x]:
			if x > lo.x + EDGE and x < hi.x - EDGE:
				xs.append(x)
		for z in [r.position.y, r.end.y]:
			if z > lo.y + EDGE and z < hi.y - EDGE:
				zs.append(z)
	xs.sort()
	zs.sort()
	for i in xs.size() - 1:
		if xs[i + 1] - xs[i] < EDGE:
			continue
		for j in zs.size() - 1:
			if zs[j + 1] - zs[j] < EDGE:
				continue
			var mid := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
			if not floor.any(func(r: Rect2) -> bool: return r.has_point(mid)):
				return false
	return true


## Is there anything in the way of `piece` standing exactly here.
func is_clear(piece: Node3D, at: Vector2, heading: float) -> bool:
	var result := resolve(piece, at, heading)
	return not result["bumped"]


## Tell the room a piece has moved. Separate from resolving, so a drag can try several
## positions in a frame and only the one it settles on is news.
func report(piece: Node3D, by_participant: int) -> void:
	piece_moved.emit(piece, by_participant)


## How far a footprint reaches along each world axis from its centre.
static func _reach(f: Dictionary) -> Vector2:
	var h: Vector2 = f["h"]
	var a: float = f["a"]
	var cs := absf(cos(a))
	var sn := absf(sin(a))
	return Vector2(cs * h.x + sn * h.y, sn * h.x + cs * h.y)


## The shortest move that takes `a` out of `b`, or zero if they do not overlap.
##
## Separating axes: two rectangles are apart if and only if, along one of their four edge
## normals, their shadows do not overlap. When every axis overlaps, the axis with the least
## overlap is the cheapest way out.
static func separation(a: Dictionary, b: Dictionary) -> Vector2:
	var axes := [_axis_x(a), _axis_z(a), _axis_x(b), _axis_z(b)]
	var best := INF
	var best_axis := Vector2.ZERO
	var between: Vector2 = a["c"] - b["c"]
	for axis in axes:
		var overlap := _shadow(a, axis) + _shadow(b, axis) - absf(between.dot(axis))
		if overlap <= 0.0:
			return Vector2.ZERO
		if overlap < best:
			best = overlap
			best_axis = axis if between.dot(axis) >= 0.0 else -axis
	# A hair more than exact, so the next frame does not find the two touching and call it a
	# collision again.
	return best_axis * (best + 0.0005)


## A footprint's local X and Z, on the floor. Matches Basis(UP, a): local +X goes to
## (cos a, -sin a) and local +Z to (sin a, cos a) in (x, z).
static func _axis_x(f: Dictionary) -> Vector2:
	return Vector2(cos(f["a"]), -sin(f["a"]))


static func _axis_z(f: Dictionary) -> Vector2:
	return Vector2(sin(f["a"]), cos(f["a"]))


static func _shadow(f: Dictionary, axis: Vector2) -> float:
	var h: Vector2 = f["h"]
	return h.x * absf(_axis_x(f).dot(axis)) + h.y * absf(_axis_z(f).dot(axis))
