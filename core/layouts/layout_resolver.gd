class_name LayoutResolver
extends RefCounted

## Turns a placement in a layout into a Transform3D in studio space (docs/layouts.md section 5.1):
## the anchors of a ShellFacts plus an offset, or another piece's authored frame. Pure: a resolved
## LayoutData and the facts in, transforms out; nothing is built and no Venue is asked.
##
## A placement is `{anchor: {x, z}, pos: [dx, dz], yaw}` (the floor point is each named anchor's value
## plus `pos`; an axis with no anchor is measured from 0) or `{frame: "authored:<id>", local: [x, z],
## yaw}` (the point is in the frame of that piece's own authored placement, never where it was pushed
## to). `yaw` is about +Y, as `Transform3D(Basis(Vector3.UP, yaw), ...)`, or `{toward, snap}`: turned
## to face an anchor from where the piece stands (a line anchor such as `mix` is the point (0, value)),
## rounded to a multiple of `snap` radians (the hand drums face the desk square to the room). A piece
## stands on y = 0 unless it says `up`: a height in metres or an anchor read as one (`height.table`
## for the bricks table's top, `zone.drums.floor` for the riser).
##
## A piece has no transform (null) when it has no `at` (a zone-mounted piece goes where its zone
## rule says), when the shell lacks an anchor it names (the sampler in a room with no synth zone: a
## piece whose zone is missing is skipped, not an error), or when the piece its frame names has none.

## How many frames deep a placement may chain; parsing already rejects loops, this is the guard.
const MAX_CHAIN := 16


## The transform of piece `id` in `layout` (a resolved LayoutData) against `facts`, or null (see above).
static func transform(layout: LayoutData, id: StringName, facts: ShellFacts) -> Variant:
	return _of(layout, String(id), facts, 0)


## Every placed piece: id -> Transform3D, for each piece that has one, in the layout's order.
static func all(layout: LayoutData, facts: ShellFacts) -> Dictionary:
	var out := {}
	for p: Dictionary in layout.pieces():
		var at: Variant = _of(layout, p["id"], facts, 0)
		if at != null:
			out[StringName(p["id"])] = at
	return out


## The floor point (x, z) of an anchor placement, or null if the shell lacks an anchor it names.
## `placement` has no frame. With neither axis anchored it is `pos` from the floor's origin.
static func point(placement: Dictionary, facts: ShellFacts) -> Variant:
	var out := Vector2.ZERO
	var anchors: Dictionary = placement.get("anchor", {})
	for axis: String in ["x", "z"]:
		if not anchors.has(axis):
			continue
		var value: Variant = facts.anchor_axis(StringName(anchors[axis]), axis)
		if value == null:
			return null
		out[0 if axis == "x" else 1] = float(value)
	var pos: Array = placement.get("pos", [0.0, 0.0])
	return out + Vector2(float(pos[0]), float(pos[1]))


static func _of(layout: LayoutData, id: String, facts: ShellFacts, depth: int) -> Variant:
	var piece := layout.piece(StringName(id))
	var at: Variant = piece.get("at")
	if not at is Dictionary or depth > MAX_CHAIN:
		return null
	var up: Variant = _height(at, facts)
	if up == null:
		return null
	if at.has("frame"):
		var base: Variant = _of(layout, (at["frame"] as String).trim_prefix("authored:"), facts, depth + 1)
		if base == null:
			return null
		var local: Array = at.get("local", [0.0, 0.0])
		return (base as Transform3D) * Transform3D(Basis(Vector3.UP, _yaw(at, Vector2.ZERO, facts)),
				Vector3(float(local[0]), float(up), float(local[1])))
	return place(at, facts)


## Where a bare anchor placement (an `at` that belongs to no piece: a group's `banner`) puts a frame,
## or null when the shell lacks an anchor it names. A frame placement needs a piece and is not
## handled here.
static func place(at: Dictionary, facts: ShellFacts) -> Variant:
	var up: Variant = _height(at, facts)
	var xz: Variant = point(at, facts)
	if up == null or xz == null:
		return null
	return Transform3D(Basis(Vector3.UP, _yaw(at, xz, facts)), Vector3((xz as Vector2).x, float(up), (xz as Vector2).y))


## The height a placement stands at: its `up` (a number, or an anchor read as one), 0 without; null
## when it names an anchor the shell lacks.
static func _height(at: Dictionary, facts: ShellFacts) -> Variant:
	var up: Variant = at.get("up", 0.0)
	if up is String:
		return facts.anchor(StringName(up))
	return float(up)


## A placement's turn: its number, or toward the anchor named, from `from`, rounded to `snap`.
static func _yaw(at: Dictionary, from: Vector2, facts: ShellFacts) -> float:
	var yaw: Variant = at.get("yaw", 0.0)
	if not yaw is Dictionary:
		return float(yaw)
	var target: Variant = facts.anchor(StringName(yaw["toward"]))
	var to := Vector2.ZERO
	if target is Vector2:
		to = target
	elif target != null:
		to = Vector2(0.0, float(target))
	var toward := to - from
	var turn := atan2(toward.x, toward.y)
	var snap := float(yaw.get("snap", 0.0))
	return snappedf(turn, snap) if snap > 0.0 else turn
