class_name CableSweep
extends Object

## Sweeps a round tube along a polyline. The shared geometry behind every cable in the studio.
##
## It lives on its own because there are two kinds of cable here and they agree on nothing except
## this: a patch cable is 4mm across, spans 20cm, and ends in a plug; a floor loom is 18mm across,
## spans two metres, and ends in a gland on the back of a chassis. What they share is the hard
## part, and the hard part is the frame.
##
## PARALLEL TRANSPORT, and why not the obvious thing. The naive sweep rebuilds the ring at each
## step from the tangent crossed with a fixed up vector. That is one line shorter and visibly
## wrong: where the tangent passes through vertical the cross product degenerates and the ring
## snaps a half turn. On a hanging cable that happens at the bottom of the sag, and on a loom it
## happens twice -- once where it drops to the floor and once where it climbs back out. Both are
## the most-looked-at points on the run. So the frame is carried forward from the previous segment
## by the minimal rotation between the two tangents, and re-orthogonalised each step, because over
## thirty-odd segments a carried frame drifts off perpendicular and the tube tapers to an ellipse.


## A centripetal Catmull-Rom through the waypoints, with the ends duplicated so the curve starts
## and finishes where it was told to rather than one span short.
##
## Catmull-Rom rather than a single Bezier because a loom's route is a list of places the cable
## has to actually be -- out of the gland, down to the floor, along it, up again -- and a Bezier's
## control points are places it merely leans towards. A cable that only leaned towards the floor
## would hover a centimetre above it for its whole length.
##
## CENTRIPETAL, which is not a flourish. The uniform version gives every span the same slice of
## parameter regardless of how long it is, and a loom's spans are wildly unequal: eight
## centimetres out of the gland, then a metre and a quarter across the floor. Uniform knots make
## the curve overshoot hard at the joins between them, and the first floor loom built this way
## dipped 81mm THROUGH the floor on the way down and poked 108mm out of the top of the patchbay
## on the way up. Spacing the knots by the square root of the chord length -- alpha = 0.5, the
## centripetal case -- is the standard cure. Measured on the same loom with everything else held
## still: the overshoot above the bay went from 108mm to 29mm and the dip from 81mm to 39mm.
##
## So it is half a fix, and the half it does not do is the floor. What closes the remaining 39mm
## is rest_on, below, and that is the right division: the overshoot at the bay was a spline
## artefact and deserved a spline fix, while the dip is where a slack cable genuinely wants to
## go. The reason it does not go there is not the maths. It is the floor.
const ALPHA := 0.5

static func smooth(waypoints: PackedVector3Array, per_span: int) -> PackedVector3Array:
	var n := waypoints.size()
	if n < 2 or per_span < 1:
		return waypoints
	var out := PackedVector3Array()
	for i in n - 1:
		var p0: Vector3 = waypoints[maxi(i - 1, 0)]
		var p1: Vector3 = waypoints[i]
		var p2: Vector3 = waypoints[i + 1]
		var p3: Vector3 = waypoints[mini(i + 2, n - 1)]
		var steps := per_span if i < n - 2 else per_span + 1
		for s in steps:
			out.append(_centripetal(p0, p1, p2, p3, float(s) / float(per_span)))
	return out


## Barry-Goldman evaluation of the non-uniform spline. The knot spacings are floored because the
## duplicated end waypoints make a zero-length span, which would otherwise divide by zero at
## exactly the two points the caller cares most about.
static func _centripetal(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + maxf(pow(p1.distance_to(p0), ALPHA), 1e-4)
	var t2 := t1 + maxf(pow(p2.distance_to(p1), ALPHA), 1e-4)
	var t3 := t2 + maxf(pow(p3.distance_to(p2), ALPHA), 1e-4)
	var t := lerpf(t1, t2, u)

	var a1 := p0.lerp(p1, (t - t0) / (t1 - t0))
	var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
	var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
	var b1 := a1.lerp(a2, (t - t0) / (t2 - t0))
	var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
	return b1.lerp(b2, (t - t1) / (t2 - t1))


## The tube itself. `uv_repeat` scales V by arc length, so a braid or print texture can be added
## later without touching this; a loom wants far fewer repeats per metre than a patch cable.
static func tube(spine: PackedVector3Array, radius: float, radial: int,
		uv_repeat: float = 40.0) -> ArrayMesh:
	var count := spine.size()
	if count < 2 or radius <= 0.0 or radial < 3:
		return null

	var tangents: Array[Vector3] = []
	for i in count:
		var t: Vector3 = spine[mini(i + 1, count - 1)] - spine[maxi(i - 1, 0)]
		tangents.append(t.normalized() if t.length_squared() > 1e-12 else Vector3.FORWARD)

	var frames: Array[Vector3] = []
	var normal := tangents[0].cross(Vector3.UP)
	if normal.length_squared() < 1e-6:
		normal = tangents[0].cross(Vector3.RIGHT)
	normal = normal.normalized()
	frames.append(normal)
	for i in range(1, count):
		var rotation := Quaternion(tangents[i - 1], tangents[i])
		normal = (rotation * normal).normalized()
		normal = (normal - tangents[i] * normal.dot(tangents[i])).normalized()
		frames.append(normal)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length_so_far := 0.0
	for i in count:
		if i > 0:
			length_so_far += spine[i].distance_to(spine[i - 1])
		var binormal := tangents[i].cross(frames[i]).normalized()
		for r in radial + 1:
			var angle := TAU * float(r) / float(radial)
			var offset := frames[i] * cos(angle) + binormal * sin(angle)
			st.set_normal(offset)
			st.set_uv(Vector2(float(r) / float(radial), length_so_far * uv_repeat))
			st.add_vertex(spine[i] + offset * radius)

	var ring := radial + 1
	for i in count - 1:
		for r in radial:
			var a := i * ring + r
			var b := (i + 1) * ring + r
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)

	st.generate_tangents()
	return st.commit()


## Lay a spine on a surface it cannot pass through.
##
## Not a clamp, although a clamp is what it does at the limit. A cable that merely stopped at the
## floor would have a crease where it arrived; a real one flattens into the contact over a few
## centimetres and leaves the same way. So inside `blend` of the level this is a parabola tangent
## to both the free curve and the floor, and outside it the curve is untouched -- which makes the
## whole thing C1 and the touchdown a curve rather than a corner.
##
## This is also the honest model of what a floor is. The route says where the cable goes; the
## floor says how low it may get on the way, and those are different kinds of statement.
static func rest_on(spine: PackedVector3Array, level: float, blend: float) -> PackedVector3Array:
	if blend <= 0.0:
		for i in spine.size():
			spine[i] = Vector3(spine[i].x, maxf(spine[i].y, level), spine[i].z)
		return spine
	for i in spine.size():
		var over := spine[i].y - level
		var lifted := over
		if over <= -blend:
			lifted = 0.0
		elif over < blend:
			lifted = (over + blend) * (over + blend) / (4.0 * blend)
		spine[i] = Vector3(spine[i].x, level + lifted, spine[i].z)
	return spine


## The frame at a point on the spine, for anything that has to sit ON a cable -- a tie, a wrap, a
## label. Returned as a basis whose Y runs along the cable, which is what a CylinderMesh wants.
static func frame_at(spine: PackedVector3Array, index: int) -> Basis:
	var count := spine.size()
	if count < 2:
		return Basis.IDENTITY
	var i := clampi(index, 0, count - 1)
	var along: Vector3 = spine[mini(i + 1, count - 1)] - spine[maxi(i - 1, 0)]
	if along.length_squared() < 1e-12:
		return Basis.IDENTITY
	along = along.normalized()
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = along.cross(Vector3.RIGHT)
	side = side.normalized()
	return Basis(side, along, side.cross(along).normalized())
