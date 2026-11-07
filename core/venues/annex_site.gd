class_name AnnexSite
extends RefCounted

## What the modular annex does to the venue it is built onto (`ModularAnnex`): the scenery that
## stands where the room goes is hidden or shrunk away, and the wall it opens onto is cut round the
## doorway. Both work on whatever meshes the venue made, by their boxes, so no venue says where its
## trees or its wall are.


## The venue's own scenery that stands where the room is built (the dome's plants and rocks, the
## greenhouse's posts): each upright piece whose box falls inside the room, or in the passage, is hidden,
## so the room is clear. Floors, ceilings and sky (flat or very large) are left. Returns how many.
static func clear_the_site(venue: Venue) -> int:
	var h := venue.annex_edge()
	var room := ModularAnnex.inside(h)
	var site := AABB(Vector3(room.position.x - ModularAnnex.WALL - 0.1, ModularAnnex.FLOOR_TOP + 0.05, ModularAnnex.Z_FROM - 0.1),
			Vector3(room.size.x + ModularAnnex.WALL + 0.3, ModularAnnex.HEIGHT, room.size.y + 0.2))
	var cleared := 0
	# Scatter (kelp, rocks, trees, posts) is a MultiMesh: each copy inside the site is shrunk to nothing.
	var flat := Rect2(site.position.x - 0.5, site.position.z - 0.5, site.size.x + 1.0, site.size.z + 1.0)
	var to_venue := venue.global_transform.affine_inverse()
	for node in venue.find_children("*", "MultiMeshInstance3D", true, false):
		var holder := node as MultiMeshInstance3D
		if holder.multimesh == null or not holder.visible or str(holder.get_path()).contains("ModularAnnex"):
			continue
		var mm := holder.multimesh
		var gone := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
		for i in mm.instance_count:
			var placed := to_venue * holder.global_transform * mm.get_instance_transform(i)
			var at: Vector3 = placed.origin
			# Where it stands, or where any of it reaches (a canopy, a rock's shoulder).
			var reach := (placed * mm.mesh.get_aabb()) if mm.mesh != null else AABB(at, Vector3.ZERO)
			if (flat.has_point(Vector2(at.x, at.z)) and at.y < ModularAnnex.HEIGHT) or (site.intersects(reach) and reach.size.y > 0.05):
				mm.set_instance_transform(i, Transform3D(gone.basis, mm.get_instance_transform(i).origin))
				cleared += 1
	# Ground that rises into the room (a cave's floor, a dome's shell) is carved away from it, triangle by
	# triangle: any triangle with a corner up in the room's volume goes.
	var volume := AABB(site.position + Vector3(-0.3, 0.13, -0.3), site.size + Vector3(0.6, -0.1, 0.6))
	for node in venue.find_children("*", "MeshInstance3D", true, false):
		var land := node as MeshInstance3D
		if land.mesh is ArrayMesh and land.visible:
			var whole := venue.global_transform.affine_inverse() * land.global_transform * land.get_aabb()
			if whole.size.x > 6.0 and whole.intersects(volume) and _cut_mesh(land, venue, volume, true):
				cleared += 1
	cleared += _clip_slabs(venue, site)
	for node in venue.find_children("*", "VisualInstance3D", true, false):
		var vi := node as GeometryInstance3D
		if vi == null or not vi.visible or vi.get_parent() == null:
			continue
		var n: Node = vi
		var ours := false
		while n != null and n != venue:
			if n is ModularAnnex:
				ours = true
				break
			n = n.get_parent()
		if ours:
			continue
		var box := venue.global_transform.affine_inverse() * vi.global_transform * vi.get_aabb()
		if box.size.y < 0.4 or maxf(box.size.x, box.size.z) > 6.0 or box.size.y > ModularAnnex.HEIGHT * 2.0:
			continue
		if site.intersects(box):
			vi.visible = false
			cleared += 1
	return cleared


## Cut the doorway through whatever wall the venue stands at the live room's right-hand side: each
## box piece that crosses the opening is hidden and put back as the pieces round it (either side, and
## the lintel over it). Venues with no wall there are untouched.
static func cut_the_wall(venue: Venue) -> int:
	var h := venue.annex_edge()
	var lo := ModularAnnex.DOOR_Z - ModularAnnex.DOOR_WIDE * 0.5
	var hi := ModularAnnex.DOOR_Z + ModularAnnex.DOOR_WIDE * 0.5
	var cut := 0
	for node in venue.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.get_parent() == null or not mi.visible or mi.name.begins_with("Annex"):
			continue
		var box := mi.mesh as BoxMesh
		if box == null or not mi.global_transform.basis.is_equal_approx(Basis.IDENTITY):
			continue
		var c := venue.to_local(mi.global_position)
		var s := box.size
		# Anything boxy standing in the wall's line that reaches into the opening: a wall, a pier, a sill,
		# a rail, a post. Thin along x, and not wholly above the door or under the floor.
		if s.x > 1.4 or absf(c.x - h) > 0.7:
			continue
		if c.z + s.z * 0.5 <= lo or c.z - s.z * 0.5 >= hi:
			continue
		if c.y - s.y * 0.5 >= ModularAnnex.DOOR_HIGH - 0.05 or c.y + s.y * 0.5 <= 0.02:
			continue
		var parent := mi.get_parent() as Node3D
		var top := c.y + s.y * 0.5
		var bottom := c.y - s.y * 0.5
		var z0 := c.z - s.z * 0.5
		var z1 := c.z + s.z * 0.5
		# Pieces as [z from, z to, y from, y to] in the venue's frame: the wall either side, the lintel.
		var pieces := [[z0, minf(lo, z1), bottom, top], [maxf(hi, z0), z1, bottom, top],
				[maxf(lo, z0), minf(hi, z1), maxf(bottom, ModularAnnex.DOOR_HIGH), top]]
		mi.visible = false
		var index := 0
		for p in pieces:
			if p[1] - p[0] < 0.02 or p[3] - p[2] < 0.02:
				continue
			var part := MeshInstance3D.new()
			part.name = "%s_cut%d" % [mi.name, index]
			var bm := BoxMesh.new()
			bm.size = Vector3(s.x, p[3] - p[2], p[1] - p[0])
			part.mesh = bm
			part.material_override = mi.material_override if mi.material_override != null else mi.get_active_material(0)
			parent.add_child(part)
			part.position = parent.to_local(venue.to_global(Vector3(c.x, (p[2] + p[3]) * 0.5, (p[0] + p[1]) * 0.5)))
			index += 1
		cut += 1
	# Whole-house meshes (a glasshouse's glass and ironwork) are cut triangle by triangle.
	var opening := AABB(Vector3(h - 0.5, -0.5, lo - 0.05), Vector3(1.0, ModularAnnex.DOOR_HIGH + 0.6, ModularAnnex.DOOR_WIDE + 0.1))
	for node in venue.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh is ArrayMesh and mi.visible and not mi.name.begins_with("Annex"):
			var box := venue.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			if box.size.x > 5.0 and box.has_point(Vector3(h, 1.0, ModularAnnex.DOOR_Z)) and _cut_mesh(mi, venue, opening):
				cut += 1
	return cut


## `mi`'s mesh without the triangles whose middle is in `opening` (venue space). Whether any went.
## Long thin pieces of a venue (a parapet, a backdrop, a beam, a bulkhead: boxes, or the few quads of one)
## that run through the site are shortened to what lies outside it, in as many boxes as that takes, so
## the room is not crossed by a wall that belongs to the live room. Only pieces standing square to the
## venue's axes are cut; a rotated one is hidden where its middle is in the site.
static func _clip_slabs(venue: Venue, site: AABB) -> int:
	var cleared := 0
	var to_venue := venue.global_transform.affine_inverse()
	for node in venue.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null or mi.get_parent() == null:
			continue
		var n: Node = mi
		var ours := false
		while n != null and n != venue:
			if n is ModularAnnex:
				ours = true
				break
			n = n.get_parent()
		if ours:
			continue
		var boxy := mi.mesh is BoxMesh
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() == 1:
			var arrays: Array = mi.mesh.surface_get_arrays(0)
			boxy = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() <= 24
		if not boxy:
			continue
		var local := to_venue * mi.global_transform
		var whole := local * mi.get_aabb()
		if not site.intersects(whole) or whole.size.y < 0.04:
			continue
		var long := maxf(whole.size.x, whole.size.z)
		if long < 2.0 or long > 60.0:
			continue
		var b := local.basis
		var square := true
		for axis in [b.x, b.y, b.z]:
			var a: Vector3 = (axis as Vector3).abs()
			square = square and maxf(a.x, maxf(a.y, a.z)) > (axis as Vector3).length() * 0.999
		if not square:
			continue
		# Subtract the site's footprint from this box's, in x and z: up to four boxes remain.
		var x0 := whole.position.x
		var x1 := whole.end.x
		var z0 := whole.position.z
		var z1 := whole.end.z
		var sx0 := site.position.x
		var sx1 := site.end.x
		var sz0 := site.position.z
		var sz1 := site.end.z
		var rects: Array[Rect2] = []
		if z0 < sz0:
			rects.append(Rect2(x0, z0, x1 - x0, sz0 - z0))
		if z1 > sz1:
			rects.append(Rect2(x0, sz1, x1 - x0, z1 - sz1))
		var mz0 := maxf(z0, sz0)
		var mz1 := minf(z1, sz1)
		if x0 < sx0:
			rects.append(Rect2(x0, mz0, sx0 - x0, mz1 - mz0))
		if x1 > sx1:
			rects.append(Rect2(sx1, mz0, x1 - sx1, mz1 - mz0))
		var material: Material = mi.material_override
		if material == null:
			material = mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null
		for r in rects:
			if r.size.x < 0.02 or r.size.y < 0.02:
				continue
			var piece := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(r.size.x, whole.size.y, r.size.y)
			piece.mesh = box
			piece.material_override = material
			piece.cast_shadow = mi.cast_shadow
			piece.name = mi.name + "_clip"
			mi.get_parent().add_child(piece)
			piece.global_transform = venue.global_transform * Transform3D(Basis.IDENTITY,
					Vector3(r.position.x + r.size.x * 0.5, whole.position.y + whole.size.y * 0.5, r.position.y + r.size.y * 0.5))
		mi.visible = false
		cleared += 1
	return cleared


static func _cut_mesh(mi: MeshInstance3D, venue: Venue, opening: AABB, any_corner := false) -> bool:
	var src := mi.mesh as ArrayMesh
	var to_venue := venue.global_transform.affine_inverse() * mi.global_transform
	var out := ArrayMesh.new()
	var any := false
	for surface in src.get_surface_count():
		var arrays := src.surface_get_arrays(surface)
		if src.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if index.is_empty():
				index.resize(verts.size())
				for i in verts.size():
					index[i] = i
			var kept := PackedInt32Array()
			for t in range(0, index.size() - 2, 3):
				var a := to_venue * verts[index[t]]
				var b := to_venue * verts[index[t + 1]]
				var c := to_venue * verts[index[t + 2]]
				var inside := opening.has_point(a) or opening.has_point(b) or opening.has_point(c) if any_corner \
						else opening.has_point((a + b + c) / 3.0)
				if inside:
					any = true
				else:
					kept.append(index[t])
					kept.append(index[t + 1])
					kept.append(index[t + 2])
			arrays[Mesh.ARRAY_INDEX] = kept
		var at := out.get_surface_count()
		out.add_surface_from_arrays(src.surface_get_primitive_type(surface), arrays)
		out.surface_set_material(at, src.surface_get_material(surface))
	if any:
		mi.mesh = out
	return any
