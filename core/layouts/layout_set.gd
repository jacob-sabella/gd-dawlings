class_name LayoutSet
extends RefCounted

## The layout files found in some folders, by id, and the one operation that turns a file into a
## room: `resolve` (docs/layouts.md section 5). Venues live in `res://layouts/venues/`, shared
## fragments in `res://layouts/common/`, made rooms under `user://layouts/rooms/`; any folder can be
## scanned. Nothing here builds anything and the game does not use it yet (migration steps 1 and 2).

const SUFFIX := ".layout.json"
## How deep fragments may extend fragments.
const MAX_DEPTH := 8

## id -> LayoutData as parsed (valid or not), in discovery order.
var layouts: Dictionary = {}
## Problems of the scan itself (`id_collision`); a file's own problems stay on its LayoutData.
var problems: Array[LayoutProblem] = []


## Parses every `*.layout.json` under `roots` (each searched in sorted order, subfolders too). The
## first file with an id keeps it; a later one is an `id_collision` and is dropped.
func scan(roots: Array[String]) -> void:
	for root in roots:
		for file in _files(root):
			add(LayoutData.load_file(file))


## Adds a parsed layout (also how tests and tools hand in layouts built in memory).
func add(l: LayoutData) -> void:
	if layouts.has(l.id):
		problems.append(LayoutProblem.make(&"id_collision", l.id, "'%s' is already taken by %s; %s is ignored" % [
				l.id, (layouts[l.id] as LayoutData).path, l.path]))
		return
	layouts[l.id] = l


## The ids of the cycled rooms, ordered by their `order` (ties by id).
func venue_ids() -> Array[StringName]:
	var rows: Array = []
	for l: LayoutData in layouts.values():
		if l.status == LayoutData.STATUS_OK and l.order >= 0:
			rows.append([l.order, l.id])
	rows.sort()
	var out: Array[StringName] = []
	for r in rows:
		out.append(StringName(r[1]))
	return out


## The room `id` in arrangement `variant`: its `extends` fragments merged in order, then its own
## body, then the variant, then what `enabled: false` switched off taken out, then checked as a whole
## (every piece names its kind, every zone has a box, at most MAX_PIECES, frames resolve and do not
## loop). Always returns a layout; `status` says whether it is usable and `problems` why not.
func resolve(id: String, variant: int = 0) -> LayoutData:
	var root: LayoutData = layouts.get(id)
	var out := LayoutData.new()
	out.id = id
	if root == null:
		out.problems.append(LayoutProblem.make(&"no_file", id, "no layout '%s'" % id))
		return out
	out.path = root.path
	out.title = root.title
	out.order = root.order
	out.extends_ids = root.extends_ids.duplicate()
	out.variants = root.variants.duplicate(true)
	out.problems.append_array(root.problems)
	if root.status != LayoutData.STATUS_OK:
		return out
	var body := _expand(root, [id], out)
	if variant < 0 or variant >= root.variant_titles().size():
		out.problems.append(LayoutProblem.make(&"bad_variant", id, "'%s' has %d arrangement(s), not %d" % [
				id, root.variant_titles().size(), variant + 1]))
		return out
	out.variant = variant
	if not root.variants.is_empty():
		var over: Dictionary = root.variants[variant].duplicate(true)
		over.erase("title")
		body = LayoutMerge.merge(body, over)
	LayoutMerge.settle(body)
	out.body = body
	_check_whole(out)
	if not out.problems.any(func(p: LayoutProblem) -> bool: return p.is_error()):
		out.status = LayoutData.STATUS_OK
	return out


## The body of `l` with its fragments merged underneath it. `stack` is the ids being expanded now.
func _expand(l: LayoutData, stack: Array, out: LayoutData) -> Dictionary:
	var merged := {}
	for ext in l.extends_ids:
		var frag: LayoutData = layouts.get(ext)
		if ext in stack:
			out.problems.append(LayoutProblem.make(&"extends_cycle", out.id, "%s extends itself through %s" % [ext, " > ".join(stack)]))
		elif frag == null:
			out.problems.append(LayoutProblem.make(&"extends_missing", out.id, "%s extends '%s', which there is none of" % [l.id, ext]))
		elif frag.status != LayoutData.STATUS_OK:
			out.problems.append(LayoutProblem.make(&"extends_missing", out.id, "%s extends '%s', which cannot be used (%s)" % [
					l.id, ext, frag.errors()[0].message if not frag.errors().is_empty() else "invalid"]))
		elif stack.size() > MAX_DEPTH:
			out.problems.append(LayoutProblem.make(&"extends_cycle", out.id, "extends nests deeper than %d" % MAX_DEPTH))
		else:
			merged = LayoutMerge.merge(merged, _expand(frag, stack + [ext], out))
	if l.id not in out.chain:
		out.chain.append(l.id)
	return LayoutMerge.merge(merged, l.body)


## The checks that need the whole room: what a fragment or variant may leave out, a file may not.
func _check_whole(out: LayoutData) -> void:
	var id := out.id
	var pieces: Array = out.body.get("pieces", [])
	var ids := {}
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		ids[p.get("id")] = i
		if not p.get("piece") is String:
			out.problems.append(LayoutProblem.make(&"bad_schema", id, "'%s' does not say which piece it is" % p.get("id"), "pieces[%d]" % i))
	if pieces.size() > LayoutData.MAX_PIECES:
		out.problems.append(LayoutProblem.make(&"over_limit", id, "%d pieces; a room holds at most %d" % [pieces.size(), LayoutData.MAX_PIECES]))
	for zone_id: String in out.zones():
		for need in ["min", "size"]:
			if not out.zones()[zone_id].has(need):
				out.problems.append(LayoutProblem.make(&"bad_schema", id, "zone '%s' has no %s" % [zone_id, need], "zones." + zone_id))
	_check_frames(out, pieces, ids)
	for i in out.body.get("groups", []).size():
		var g: Dictionary = out.body["groups"][i]
		if not (g.get("title") is String and g.get("members") is Array):
			out.problems.append(LayoutProblem.make(&"bad_schema", id, "group '%s' needs a title and members" % g.get("id"), "groups[%d]" % i))
		for m in g.get("members", []):
			if not ids.has(m):
				out.problems.append(LayoutProblem.make(&"unknown_piece", id, "group '%s' names '%s', which is not in the room" % [g.get("id"), m], "groups[%d]" % i, LayoutProblem.WARNING))
	for w: Dictionary in out.body.get("wiring", []):
		for end in ["from", "to"]:
			if not ids.has(w.get(end)) and w.get(end) not in LayoutMerge.WIRE_AREAS:
				out.problems.append(LayoutProblem.make(&"unknown_piece", id, "a %s wire runs to '%s', which is not in the room" % [w.get("kind"), w.get(end)], "wiring", LayoutProblem.WARNING))


## Every `authored:<id>` frame names a piece of the room, and following them never comes back round.
func _check_frames(out: LayoutData, pieces: Array, ids: Dictionary) -> void:
	var framed := {}
	for i in pieces.size():
		var at: Variant = pieces[i].get("at")
		if at is Dictionary and at.get("frame") is String:
			var target: String = (at["frame"] as String).trim_prefix("authored:")
			framed[pieces[i]["id"]] = target
			if not ids.has(target):
				out.problems.append(LayoutProblem.make(&"unknown_piece", out.id, "'%s' is placed in the frame of '%s', which is not in the room" % [pieces[i]["id"], target], "pieces[%d].at.frame" % i))
	for start: String in framed:
		var at: String = start
		var path: Array = [start]
		while framed.has(at) and path.size() <= framed.size():
			at = framed[at]
			path.append(at)
			# Reported once per loop, from its lowest id.
			if at == start and path.min() == start:
				out.problems.append(LayoutProblem.make(&"cycle", out.id, "'%s' is placed relative to itself" % start, "pieces"))
			if at == start:
				break


func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	var names := Array(da.get_files())
	names.sort()
	for n: String in names:
		if n.ends_with(SUFFIX):
			out.append(dir.path_join(n))
	var subs := Array(da.get_directories())
	subs.sort()
	for s: String in subs:
		if not s.begins_with("."):
			out.append_array(_files(dir.path_join(s)))
	return out
