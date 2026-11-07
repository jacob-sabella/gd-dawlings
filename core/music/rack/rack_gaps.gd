class_name RackGaps
extends RefCounted

## What a rack patch holds that this machine cannot show or sound (docs/mods.md 6.2 and 6.3): a module
## no installed mod provides (a plate that names the mod, from the patch's `uses`), and a cable that
## ends on a port a known module no longer has (a dangling cable, a red stub on the wall). Nothing here
## changes a patch; `RackPatch.sanitize` keeps these things and asks this class which cables to keep.

## How one end of a cable stands: a real jack, a module nobody here provides, a port the known module
## has lost, or a port that exists but takes the other direction (a plain mistake: the cable is dropped).
enum End { JACK, ABSENT_MODULE, GONE_PORT, WRONG }


## The cable `from` -> `to` kept by `RackPatch.sanitize` though `connect_cable` refused it: one end is on
## a module that is missing or a port that has gone, and the other is a real jack or the same kind of
## gap. A mistake (a loop onto itself, the wrong direction, a module that is not there, a repeat, a full
## case) is not kept. The cable is appended to `p` when it is.
static func keep_cable(p: Dictionary, from: String, to: String) -> bool:
	var a := from.get_slice(".", 0)
	var b := to.get_slice(".", 0)
	if a == b or from.count(".") != 1 or to.count(".") != 1 or (p["cables"] as Array).size() >= RackPatch.MAX_CABLES:
		return false
	var mods: Dictionary = p["modules"]
	if not mods.has(a) or not mods.has(b):
		return false
	var from_end := end_of(p, from, true)
	var to_end := end_of(p, to, false)
	if from_end == End.WRONG or to_end == End.WRONG or (from_end == End.JACK and to_end == End.JACK):
		return false
	for c in p["cables"]:
		if c[0] == from and c[1] == to:
			return false
	(p["cables"] as Array).append([from, to])
	return true


## How the end `path` ("id.port") of a cable stands in `p`, as an output (`output`) or an input.
static func end_of(p: Dictionary, path: String, output: bool) -> End:
	var id := path.get_slice(".", 0)
	var port := path.get_slice(".", 1)
	if port.is_empty():
		return End.WRONG
	if RackPatch.is_missing(p, id):
		return End.ABSENT_MODULE
	var type := RackPatch.type_of(p, id)
	if (RackCatalogue.has_out(type, port) if output else RackCatalogue.has_in(type, port)):
		return End.JACK
	if RackCatalogue.has_out(type, port) or RackCatalogue.has_in(type, port):
		return End.WRONG
	return End.GONE_PORT


## Whether the cable `c` ([from, to]) ends on a port its known module no longer has.
static func dangling(p: Dictionary, c: Array) -> bool:
	return end_of(p, String(c[0]), true) == End.GONE_PORT or end_of(p, String(c[1]), false) == End.GONE_PORT


## The patch's problems in words, for a list a player can read: each module a mod is missing for (once
## per type) and each dangling cable.
static func problems(p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for id in RackPatch.module_ids(p):
		if RackPatch.is_missing(p, id) and not seen.has(p["modules"][id]["type"]):
			seen[p["modules"][id]["type"]] = true
			out.append(plate_text(p, id))
	for c in p["cables"]:
		if dangling(p, c):
			out.append("the cable %s to %s ends on a port that is gone" % [c[0], c[1]])
	return out


## What a saved patch said about the mod behind module `id`'s type ({mod, version, title}, any may be
## missing), or {}.
static func uses_of(p: Dictionary, id: String) -> Dictionary:
	return (p.get("uses", {}) as Dictionary).get(RackPatch.type_of(p, id), {})


## The title on the plate of a module nobody here provides: its name from `uses`, else its type.
static func plate_title(p: Dictionary, id: String) -> String:
	var name: String = uses_of(p, id).get("title", "")
	return "%s not installed" % (name if name != "" else RackPatch.type_of(p, id))


## The small line under it naming the mod and its version, or "" when the patch did not say.
static func plate_note(p: Dictionary, id: String) -> String:
	var u := uses_of(p, id)
	var mod: String = u.get("mod", "")
	return "" if mod == "" else ("%s %s" % [mod, u.get("version", "")]).strip_edges()


## The plate in one sentence: "PLUCK (dawlings.sample.pluck 0.1.0): not installed".
static func plate_text(p: Dictionary, id: String) -> String:
	var u := uses_of(p, id)
	var name: String = u.get("title", RackPatch.type_of(p, id))
	var note := plate_note(p, id)
	return "%s (%s): not installed" % [name, note] if note != "" else "%s: not installed" % name


## The room row as it goes to the guests: the row with its patch's `uses` filled for every type in it
## from the registry here (`RackPatch.to_dict`), so a guest without a mod can still name it. The row
## itself is not changed.
static func published(row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	if out.get("patch") is Dictionary and (out["patch"] as Dictionary).get("modules") is Dictionary:
		out["patch"]["uses"] = RackPatch.to_dict(out["patch"])["uses"]
	return out
