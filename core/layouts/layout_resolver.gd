class_name LayoutResolver
extends RefCounted

## Turns a placement in a layout into a Transform3D in studio space (docs/layouts.md section 5.1):
## the anchors of a ShellFacts plus an offset, or another piece's authored frame. Pure: a resolved
## LayoutData and the facts in, transforms out; nothing is built and no Venue is asked.
##
## A placement is `{anchor: {x, z}, pos: [dx, dz], yaw}` (the floor point is each named anchor's value
## plus `pos`; an axis with no anchor is measured from 0) or `{frame: "authored:<id>", local: [x, z],
## yaw}` (the point is in the frame of that piece's own authored placement, never where it was pushed
## to). `yaw` is about +Y, as `Transform3D(Basis(Vector3.UP, yaw), ...)`. Everything stands on y = 0.
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
	var yaw := float(at.get("yaw", 0.0))
	if at.has("frame"):
		var base: Variant = _of(layout, (at["frame"] as String).trim_prefix("authored:"), facts, depth + 1)
		if base == null:
			return null
		var local: Array = at.get("local", [0.0, 0.0])
		return (base as Transform3D) * Transform3D(Basis(Vector3.UP, yaw), Vector3(float(local[0]), 0.0, float(local[1])))
	var xz: Variant = point(at, facts)
	if xz == null:
		return null
	return Transform3D(Basis(Vector3.UP, yaw), Vector3((xz as Vector2).x, 0.0, (xz as Vector2).y))
