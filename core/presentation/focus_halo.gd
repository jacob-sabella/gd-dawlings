class_name FocusHalo
extends MeshInstance3D

## Corner brackets around a surface the focus rig is holding.
##
## Two jobs, and the second is why it is not decoration.
##
## It says WHICH surface has your attention. The rig moves five surfaces at once and only one of
## them is the work; from inside the arc, at a glance, the parked ones and the focused one look
## the same, and the only cue was distance. Distance is a bad cue for state -- it is also what
## changes when the surface is a different size, so a small surface close by and a large one
## further out read identically.
##
## And it says the thing is SUMMONED rather than standing in the room. That distinction is real
## and worth drawing: gear on the body frame follows you, gear in the room does not, and a
## person who cannot tell which is which will walk away from a console expecting it to stay put.
##
## Brackets rather than a full border, because a closed rectangle around a panel reads as a
## frame the panel is mounted in -- furniture again -- while four corner marks read as something
## projected over it. They are also a quarter of the geometry.
##
## One mesh and one material per state, so the whole arc costs two draw calls rather than one
## per surface: the brackets are built into a single ArrayMesh and the colour comes from a
## shared material chosen by state.

const THICKNESS := 0.006
const ARM_FRACTION := 0.16
const MAX_ARM := 0.10
const STANDOFF := 0.012

const FOCUSED_COLOUR := Color(0.62, 0.86, 1.0)
const PARKED_COLOUR := Color(0.44, 0.50, 0.58)
## The empty place a summoned surface came out of. Dimmer than parked, because a berth is not
## a thing you can use -- it is a note about where something goes back to.
const BERTH_COLOUR := Color(0.30, 0.34, 0.40)


static func create(bounds: AABB, colour: Color) -> FocusHalo:
	var halo := FocusHalo.new()
	halo.name = "FocusHalo"
	halo.refresh(bounds, colour)
	halo.cast_shadow = SHADOW_CASTING_SETTING_OFF
	return halo


func refresh(bounds: AABB, colour: Color) -> void:
	mesh = brackets(Vector2(bounds.size.x, bounds.size.y))
	position = bounds.get_center() + Vector3(0, 0, bounds.size.z * 0.5 + STANDOFF)
	material_override = Materials.halo(colour)


## Eight bars: two at each corner, running in from it along each edge.
##
## The arm length is a FRACTION of the surface rather than a constant, capped. A fixed arm on a
## patchbay is a border; the same arm on a ninety-track console is a speck. Capped because the
## fraction alone would put a 15cm bracket on the desk, which stops reading as a corner mark and
## starts reading as the two sides of a box that failed to meet.
static func brackets(size: Vector2) -> ArrayMesh:
	var half := size * 0.5
	var arm := Vector2(
			minf(size.x * ARM_FRACTION, MAX_ARM),
			minf(size.y * ARM_FRACTION, MAX_ARM))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx * half.x, sy * half.y)
			# Along the horizontal edge, then along the vertical one. Both start AT the corner
			# and run inward, so the two bars of a corner overlap in a square -- which is what
			# makes it look like one bracket instead of two separate dashes.
			_bar(verts, normals, corner, Vector2(corner.x - sx * arm.x, corner.y), THICKNESS)
			_bar(verts, normals, corner, Vector2(corner.x, corner.y - sy * arm.y), THICKNESS)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _bar(verts: PackedVector3Array, normals: PackedVector3Array,
		from: Vector2, to: Vector2, width: float) -> void:
	var along := (to - from)
	if along.length() < 1e-6:
		return
	# Widened about the line rather than offset from it, so a bracket sits centred on the
	# corner instead of a half-width outside it on two edges and inside it on the other two.
	var across := along.normalized().orthogonal() * width * 0.5
	var a := from - across
	var b := from + across
	var c := to + across
	var d := to - across
	for p in [a, b, c, a, c, d]:
		verts.append(Vector3(p.x, p.y, 0.0))
		normals.append(Vector3.BACK)
