class_name Part
extends Object

## Loading an authored mesh: one place, because an asset can fail in ways procedural geometry
## cannot, and each of those failures wants the same answer every time.
##
## MISSING. The asset can be absent, unexported, or present and not yet imported -- a headless
## run against a cold .godot/ is the ordinary way that happens. The caller gets null and is
## expected to draw something, because a control with no mesh still has working collision, and
## an invisible control is far worse than a plain one.
##
## SHARED. There are around a hundred knobs and a dozen fader caps on a full desk and each
## family is one object. The mesh is loaded once and handed out; the per-instance state lives
## in the node, not the geometry.
##
## PAINTED BY NAME. Surfaces are matched against the authored material's name, never its index.
## The order the glTF exporter emits primitives in is its business, not ours; an index that
## silently swaps paints a knob's body white and its indicator black, which is a part that
## looks perfectly plausible and is wrong. Names come from tools/blender/*.py and are the
## contract between the two halves.

static var _cache: Dictionary = {}


## The mesh at `path`, or null. Cached including the misses, so a missing asset costs one
## failed lookup rather than one per control on the desk.
static func mesh(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	var found: Mesh = null
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var root := packed.instantiate()
			for child in root.find_children("*", "MeshInstance3D", true, false):
				found = (child as MeshInstance3D).mesh
				break
			# Not queue_free: this node never entered a tree, so there is no frame to free it on.
			root.free()
	_cache[path] = found
	return found


## A ready-to-add MeshInstance3D, or null if the asset will not resolve.
##
## `named` maps a fragment of an authored material name, matched case-insensitively, to the
## material to paint that surface with. Everything unmatched gets `fallback`.
static func build(path: String, fallback: Material, named: Dictionary = {}) -> MeshInstance3D:
	var found := mesh(path)
	if found == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = found
	for i in found.get_surface_count():
		mi.set_surface_override_material(i, paint_for(found, i, fallback, named))
	return mi


## Which material surface `i` of `source` should wear, by the rule described above.
##
## Out here because `MeshBank` has to answer the same question and cannot use the same mechanism:
## a MultiMeshInstance3D has no per-surface override, so it bakes the answer into a duplicate of
## the mesh instead. Two call sites, one rule -- a bank whose jacks were painted by a slightly
## different rule from the loose ones would be a bay with two kinds of jack in it.
static func paint_for(source: Mesh, i: int, fallback: Material, named: Dictionary) -> Material:
	var authored := source.surface_get_material(i)
	var id := authored.resource_name if authored != null else ""
	for fragment in named:
		if String(id).containsn(String(fragment)):
			return named[fragment]
	return fallback
