class_name LayoutGeometry
extends RefCounted

## The floor geometry the layout validator needs, in plain functions: oriented rectangles
## ("footprints", `{c, h, a, top}` as Walker and FloorPlan use them), the gap between two of them,
## and whether a person fits at a point. Pure; the same arithmetic as the placement tests
## (tests/run_tests.gd `_poly_gap`, `_quad`) and Walker.fits, written once for code that has no Studio.


## The yaw (about +Y) of a basis that is a pure turn about +Y. Unlike `get_euler().y` this is right
## beyond a quarter turn.
static func yaw_of(b: Basis) -> float:
	return atan2(-b.x.z, b.x.x)


## A footprint in the form the walker takes: centre `c` (x, z), half extents `h`, angle `a`, `top`.
static func footprint(c: Vector2, h: Vector2, a: float, top: float) -> Dictionary:
	return {"c": c, "h": h, "a": a, "top": top}


## The four corners of a footprint, in order round it.
static func corners(fp: Dictionary) -> PackedVector2Array:
	var c: Vector2 = fp["c"]
	var h: Vector2 = fp["h"]
	var a: float = fp["a"]
	var ax := Vector2(cos(a), -sin(a))
	var az := Vector2(sin(a), cos(a))
	var out := PackedVector2Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(c + ax * h.x * s.x + az * h.y * s.y)
	return out


## The corners of an axis-aligned rectangle.
static func rect_corners(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## How far apart two convex quads are; negative, how deep they overlap.
static func gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var shallowest := INF
	for poly: PackedVector2Array in [a, b]:
		for i in poly.size():
			var edge := poly[(i + 1) % poly.size()] - poly[i]
			if edge.length() < 1e-9:
				continue
			var n := Vector2(-edge.y, edge.x).normalized()
			var span_a := _span(a, n)
			var span_b := _span(b, n)
			var overlap := minf(span_a.y, span_b.y) - maxf(span_a.x, span_b.x)
			if overlap <= 0.0:
				return _closest(a, b)
			shallowest = minf(shallowest, overlap)
	return -shallowest if shallowest < INF else 0.0


## The distance from point `p` to a footprint (0 on or inside it).
static func point_gap(fp: Dictionary, p: Vector2) -> float:
	var centre: Vector2 = fp["c"]
	var local := Basis(Vector3.UP, fp["a"]).inverse() * Vector3(p.x - centre.x, 0.0, p.y - centre.y)
	var q := Vector2(absf(local.x), absf(local.z)) - (fp["h"] as Vector2)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


## Whether `p` is on one of the rectangles of floor.
static func on_floor(floor: Array[Rect2], p: Vector2) -> bool:
	for r in floor:
		if p.x >= r.position.x - 0.001 and p.x <= r.end.x + 0.001 and p.y >= r.position.y - 0.001 and p.y <= r.end.y + 0.001:
			return true
	return false


## Walker.fits without a walker: a person's body fits at `p` when it and a ring round it (RADIUS plus
## 3 cm) are on the floor and no solid taller than a step comes within that reach.
static func fits(p: Vector2, floor: Array[Rect2], solids: Array) -> bool:
	var reach := Walker.RADIUS + 0.03
	for k in 9:
		if not on_floor(floor, p if k == 8 else p + Vector2.from_angle(TAU * k / 8.0) * reach):
			return false
	for f: Dictionary in solids:
		if f.get("top", Walker.SOLID_HEIGHT) > Walker.STEP_HEIGHT and point_gap(f, p) < reach:
			return false
	return true


static func _span(poly: PackedVector2Array, n: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in poly:
		lo = minf(lo, p.dot(n))
		hi = maxf(hi, p.dot(n))
	return Vector2(lo, hi)


static func _closest(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for pair: Array in [[a, b], [b, a]]:
		var from: PackedVector2Array = pair[0]
		var to: PackedVector2Array = pair[1]
		for p in from:
			for i in to.size():
				best = minf(best, Geometry2D.get_closest_point_to_segment(p, to[i], to[(i + 1) % to.size()]).distance_to(p))
	return best
