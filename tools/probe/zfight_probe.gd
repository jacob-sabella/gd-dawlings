class_name ZFightProbe
extends Node

## Finds faces that will z-fight: two visible surfaces lying in the same plane, facing the same
## way, and overlapping. Run with `godot --headless --path . tools/probe/zfight_probe.tscn`.
##
## A search rather than a squint, because z-fighting is a thing you notice while moving and
## stop seeing in a still -- and a still is what every screenshot here is.

const PLANE_TOLERANCE := 0.0002
const MIN_OVERLAP := 0.0005

static func faces_of(mi: MeshInstance3D) -> Array:
	return faces_of_mesh(mi.mesh, mi.global_transform, mi)


static func faces_of_mesh(mesh: Mesh, xf: Transform3D, who: Variant) -> Array:
	var out := []
	if mesh == null:
		return out
	var box := mesh.get_aabb()
	var axes := [0, 1, 2]
	if mesh is CylinderMesh or mesh is TorusMesh or mesh is CapsuleMesh or mesh is SphereMesh:
		axes = [1] if mesh is CylinderMesh else []
	elif not (mesh is BoxMesh or mesh is QuadMesh or mesh is PlaneMesh):
		return out
	for axis: int in axes:
		if box.size[axis] <= 0.0 and not (mesh is QuadMesh or mesh is PlaneMesh):
			continue
		for side in [-1.0, 1.0]:
			if mesh is QuadMesh and (axis != 2 or side < 0):
				continue
			if mesh is PlaneMesh and (axis != 1 or side < 0):
				continue
			var n := Vector3.ZERO
			n[axis] = side
			var u: int = (axis + 1) % 3
			var v: int = (axis + 2) % 3
			var corners := []
			for cu in [0.0, 1.0]:
				for cv in [0.0, 1.0]:
					var p := box.position
					p[axis] = box.position[axis] + (box.size[axis] if side > 0 else 0.0)
					p[u] += box.size[u] * cu
					p[v] += box.size[v] * cv
					corners.append(xf * p)
			# Corner order round the rectangle.
			corners = [corners[0], corners[1], corners[3], corners[2]]
			var wn: Vector3 = (xf.basis * n).normalized()
			out.append({"n": wn, "d": wn.dot(corners[0]), "c": corners, "who": who})
	return out


static func _overlap(a: Array, b: Array, n: Vector3) -> float:
	var t := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var s := n.cross(t)
	var pa := a.map(func(p): return Vector2(p.dot(t), p.dot(s)))
	var pb := b.map(func(p): return Vector2(p.dot(t), p.dot(s)))
	var least := INF
	for poly in [pa, pb]:
		for i in 4:
			var e: Vector2 = poly[(i + 1) % 4] - poly[i]
			if e.length() < 1e-7:
				continue
			var ax := Vector2(-e.y, e.x).normalized()
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for p in pa:
				amin = minf(amin, p.dot(ax)); amax = maxf(amax, p.dot(ax))
			for p in pb:
				bmin = minf(bmin, p.dot(ax)); bmax = maxf(bmax, p.dot(ax))
			least = minf(least, minf(amax, bmax) - maxf(amin, bmin))
	return least


static func scan(root: Node) -> Array:
	var faces := []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		faces.append_array(faces_of(mi))
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var bank := node as MeshBank
		if bank == null or not bank.is_visible_in_tree() or bank.multimesh == null:
			continue
		for i in bank._transforms.size():
			faces.append_array(faces_of_mesh(bank.multimesh.mesh,
					bank.global_transform * bank._transforms[i], [bank, i]))
	faces.sort_custom(func(a, b): return a["d"] < b["d"])
	var hits := []
	for i in faces.size():
		var a: Dictionary = faces[i]
		for j in range(i + 1, faces.size()):
			var b: Dictionary = faces[j]
			if b["d"] - a["d"] > PLANE_TOLERANCE * 3.0 + 0.002:
				break
			if typeof(a["who"]) == typeof(b["who"]) and a["who"] == b["who"]:
				continue
			if a["n"].dot(b["n"]) < 0.9999:
				continue
			var gap: float = absf(a["n"].dot(b["c"][0]) - a["d"])
			if gap > PLANE_TOLERANCE:
				continue
			if _overlap(a["c"], b["c"], a["n"]) > MIN_OVERLAP:
				hits.append([a["who"], b["who"], gap])
	return hits


static func label(who: Variant) -> String:
	var n: Node = who[0] if who is Array else who
	var parts := [] if not (who is Array) else ["#%d" % who[1]]
	var at := n
	for i in 3:
		if at == null:
			break
		parts.push_front(String(at.name))
		at = at.get_parent()
	return "/".join(parts)


func _ready() -> void:
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://probe_layout.cfg"
	Session.layout.set_mode(&"timeline", Presentation.Mode.STUDIO)
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# VENUE=<id> scans that venue rather than the one the layout last chose.
	if OS.get_environment("VENUE") != "":
		studio.set_venue(StringName(OS.get_environment("VENUE")), false, 0)
	for i in 6:
		await get_tree().process_frame
	var hits := scan(studio)
	var kinds := {}
	for h in hits:
		var key := "%s  <>  %s" % [_shape(h[0]), _shape(h[1])]
		if not kinds.has(key):
			kinds[key] = [0, h]
		kinds[key][0] += 1
	var keys := kinds.keys()
	keys.sort_custom(func(x, y): return kinds[x][0] > kinds[y][0])
	print("ZFIGHT pairs: ", hits.size())
	for k in keys:
		var h: Array = kinds[k][1]
		print("%5d  %s   e.g. %s | %s  gap %.5f" % [kinds[k][0], k, label(h[0]), label(h[1]), h[2]])
		if h[2] < 0.0006 or OS.get_environment("VENUE") != "":
			for m in [h[0], h[1]]:
				var mm: Node3D = m[0] if m is Array else m
				var mesh: Mesh = mm.multimesh.mesh if m is Array else mm.mesh
				var at: Vector3 = mm._transforms[m[1]].origin if m is Array else mm.position
				var sz = mesh.size if "size" in mesh else mesh.get_aabb().size
				var src = mm.get_parent().get_script().resource_path if mm.get_parent().get_script() else "-"
				print("        %s %s at %s in %s (%s)" % [mesh.get_class(), sz, at, mm.get_parent().name, src])
	get_tree().quit()


static func _shape(who: Variant) -> String:
	var n: Node = who[0] if who is Array else who
	var at := n.get_parent()
	var owner_name := ""
	while at != null:
		if at.get_script() != null and at.get_script().get_global_name() != &"":
			owner_name = at.get_script().get_global_name()
			break
		at = at.get_parent()
	return "%s:%s" % [owner_name, String(n.name).rstrip("0123456789@")]
