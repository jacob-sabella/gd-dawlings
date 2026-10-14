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
	for fixture in fixtures:
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
		var reach := _reach(mine)
		var c: Vector2 = mine["c"]
		var lo := bounds.position + reach
		var hi := bounds.end - reach
		var held := Vector2(clampf(c.x, lo.x, maxf(lo.x, hi.x)), clampf(c.y, lo.y, maxf(lo.y, hi.y)))
		if not held.is_equal_approx(c):
			at += held - c
			moved = true
		bumped = bumped or moved
		if not moved:
			break
	return {"at": at, "bumped": bumped}


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
