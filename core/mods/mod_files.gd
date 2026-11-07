class_name ModFiles
extends RefCounted

## Checks the files a manifest names: that they exist, and that a decorative model stays inside the
## limits (docs/mods.md section 5 `missing_file`, `bad_model`; decision 5: 2 MB, 20k triangles,
## nothing fetched from outside the file). Reads bytes only; nothing is imported or run.

const MAX_MODEL_BYTES := 2 * 1024 * 1024
const MAX_MODEL_TRIANGLES := 20000
const _GLB_MAGIC := 0x46546C67
const _CHUNK_JSON := 0x4E4F534A


## Problems (all warnings) for every file entry or licence in `data` that is missing or unusable.
## `folder` is the mod's folder, `mod_id` names the mod in the messages.
static func check(folder: String, data: Dictionary, mod_id: String) -> Array[ModProblem]:
	var out: Array[ModProblem] = []
	var licence: Variant = data.get("licence")
	if licence is Dictionary and (licence as Dictionary).get("file") is String:
		_need(out, folder, licence["file"], mod_id, "", "licence text")
	var provides: Variant = data.get("provides")
	if not provides is Array:
		return out
	for e in provides:
		if not e is Dictionary:
			continue
		var key := ModEntryCheck.entry_key(e)
		var model: Variant = e.get("model")
		if model is Dictionary and (model as Dictionary).get("glb") is String:
			var path: String = model["glb"]
			if _need(out, folder, path, mod_id, key, "model"):
				var why := model_problem(folder.path_join(path))
				if why != "":
					out.append(ModProblem.make(&"bad_model", mod_id, "%s: %s" % [path, why], key,
							ModProblem.WARNING))
		var patch: Variant = e.get("patch")
		if patch is Dictionary and (patch as Dictionary).get("file") is String:
			_need(out, folder, patch["file"], mod_id, key, "patch")
	return out


static func _need(out: Array[ModProblem], folder: String, rel: String, mod_id: String,
		entry: String, what: String) -> bool:
	# A path that climbs out of the mod's folder is never read.
	if rel.is_absolute_path() or ".." in rel.split("/"):
		out.append(ModProblem.make(&"missing_file", mod_id,
				"%s %s is outside the mod folder" % [what, rel], entry, ModProblem.WARNING))
		return false
	if FileAccess.file_exists(folder.path_join(rel)):
		return true
	out.append(ModProblem.make(&"missing_file", mod_id, "%s %s not found" % [what, rel], entry,
			ModProblem.WARNING))
	return false


## Why the .glb at `path` may not be used, or "" when it is fine. The check reads the file's
## JSON chunk only: header, size, external URIs and the triangle count the accessors declare.
static func model_problem(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "cannot be opened"
	if f.get_length() > MAX_MODEL_BYTES:
		return "is %d bytes, over the %d byte limit" % [f.get_length(), MAX_MODEL_BYTES]
	f.big_endian = false
	if f.get_length() < 20 or f.get_32() != _GLB_MAGIC:
		return "is not a binary glTF (.glb) file"
	f.get_32() # version
	f.get_32() # total length
	var json_len := f.get_32()
	if f.get_32() != _CHUNK_JSON or json_len <= 0 or json_len > f.get_length() - 20:
		return "has no readable JSON chunk"
	var parsed: Variant = JSON.parse_string(f.get_buffer(json_len).get_string_from_utf8())
	if not parsed is Dictionary:
		return "has an unreadable JSON chunk"
	for kind in ["buffers", "images"]:
		for item in parsed.get(kind, []):
			if item is Dictionary and item.has("uri") and not str(item["uri"]).begins_with("data:"):
				return "refers to an external file (%s)" % item["uri"]
	var tris := _triangles(parsed)
	if tris > MAX_MODEL_TRIANGLES:
		return "has %d triangles, over the %d limit" % [tris, MAX_MODEL_TRIANGLES]
	return ""


static func _triangles(gltf: Dictionary) -> int:
	var accessors: Array = gltf.get("accessors", [])
	var meshes: Array = gltf.get("meshes", [])
	var per_mesh: Array[int] = []
	for m in meshes:
		var n := 0
		for prim in (m as Dictionary).get("primitives", []) if m is Dictionary else []:
			var mode: int = int(prim.get("mode", 4))
			if mode < 4:
				continue
			var idx: Variant = prim.get("indices")
			if idx == null:
				idx = (prim.get("attributes", {}) as Dictionary).get("POSITION")
			if idx != null and int(idx) >= 0 and int(idx) < accessors.size():
				n += int(accessors[int(idx)].get("count", 0)) / 3
		per_mesh.append(n)
	var total := 0
	var instanced := false
	for node in gltf.get("nodes", []):
		if node is Dictionary and node.has("mesh") and int(node["mesh"]) < per_mesh.size():
			total += per_mesh[int(node["mesh"])]
			instanced = true
	if not instanced:
		for n in per_mesh:
			total += n
	return total
