class_name PatchCable
extends MeshInstance3D

## A cable, drawn as a hanging tube between two jacks.
##
## It hangs. That is not ornament: a patchbay with straight lines between jacks is a graph
## diagram, and the reason to render routing as cables at all is that a bundle of them tells you
## at a glance how heavily patched a session is, which way signal is flowing, and which jack is
## the one with four things plugged into it. A straight line conveys none of that, and in 3D two
## straight lines at different depths are indistinguishable from one.
##
## SAG IS PROPORTIONAL TO SPAN, with a floor. A short patch between neighbouring jacks that sagged
## 15cm would loop below the bay and read as a much longer cable than it is.

const SEGMENTS := 18
const RADIAL := 6
const RADIUS := 0.0035
const SAG_RATIO := 0.22
const MIN_SAG := 0.012

var from_point: Vector3 = Vector3.ZERO
var to_point: Vector3 = Vector3.ZERO
var colour: Color = Color(0.82, 0.74, 0.3)


static func create(a: Vector3, b: Vector3, tint: Color) -> PatchCable:
	var c := PatchCable.new()
	c.from_point = a
	c.to_point = b
	c.colour = tint
	return c


func _ready() -> void:
	material_override = Materials.cable(colour)
	rebuild()


func rebuild() -> void:
	# Built in local space from two GLOBAL endpoints, so a cable survives its surface being
	# reparented from a monitor to the room -- which is the one operation this project does that
	# would otherwise leave every cable pointing at where the bay used to be.
	var a := to_local(from_point)
	var b := to_local(to_point)
	var span := a.distance_to(b)
	var sag := maxf(span * SAG_RATIO, MIN_SAG)

	var spine: Array[Vector3] = []
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var point := a.lerp(b, t)
		# A parabola, not a true catenary. Over a 60cm span the two differ by under a
		# millimetre, and the parabola costs no cosh per vertex per cable per rebuild.
		point.y -= sag * 4.0 * t * (1.0 - t)
		spine.append(point)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in spine.size():
		var tangent := (spine[mini(i + 1, spine.size() - 1)] - spine[maxi(i - 1, 0)]).normalized()
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD
		var up := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var side := tangent.cross(up).normalized()
		var other := side.cross(tangent).normalized()
		for r in RADIAL:
			var angle := TAU * float(r) / float(RADIAL)
			var offset := side * cos(angle) * RADIUS + other * sin(angle) * RADIUS
			st.set_normal(offset.normalized())
			st.add_vertex(spine[i] + offset)

	for i in spine.size() - 1:
		for r in RADIAL:
			var r_next := (r + 1) % RADIAL
			var base := i * RADIAL
			var next_base := (i + 1) * RADIAL
			st.add_index(base + r)
			st.add_index(next_base + r)
			st.add_index(base + r_next)
			st.add_index(base + r_next)
			st.add_index(next_base + r)
			st.add_index(next_base + r_next)

	mesh = st.commit()
