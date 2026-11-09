class_name RackFinder
extends RefCounted

## Finding a rack module among the many: by what you type (words of the name, the kind, a knob or the blurb), by
## palette group and by kind (an Airwindows effect's kind: reverb, filter, dither, ...). The logic of the finder
## screen (RackFinderScreen), apart from it so it can be tested. Results are ranked: a name that starts with the
## words first, then names that contain them, then kinds and knob names, then the blurb.

## The kind of module `type` (its entry's `kinds`, the first is its main one), or [].
static func kinds_of(type: String) -> Array:
	var e := ModRegistry.ensure_current().rack_module_entry(type)
	var k: Variant = e.get("kinds", [])
	return k if k is Array else []


## Every kind there is, alphabetical.
static func all_kinds() -> Array[String]:
	var seen := {}
	for t in RackCatalogue.types():
		for k in kinds_of(t):
			seen[String(k)] = true
	var out: Array[String] = []
	out.assign(seen.keys())
	out.sort()
	return out


## The types matching `query` (words, all of which must match), in `group` ("" for any) and of `kind` ("" for any),
## best first, then by title.
static func search(query: String, group := "", kind := "") -> Array[String]:
	var words := query.to_lower().split(" ", false)
	var scored: Array = []
	for t in RackCatalogue.types():
		var s := RackCatalogue.spec(t)
		if s.is_empty() or s["group"] == RackCatalogue.HIDDEN_GROUP:
			continue
		if group != "" and s["group"] != group:
			continue
		var kinds := kinds_of(t)
		if kind != "" and not kind in kinds:
			continue
		var score := _score(s, kinds, words)
		if score >= 0:
			scored.append([score, String(s["title"]), t])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[String] = []
	for row in scored:
		out.append(row[2])
	return out


## The rank of a module for the words (lower is better), or -1 when one of them matches nothing.
static func _score(s: Dictionary, kinds: Array, words: PackedStringArray) -> int:
	if words.is_empty():
		return 0
	var title := String(s["title"]).to_lower()
	var kind_text := " ".join(kinds).to_lower()
	var knob_text := ""
	for k: Dictionary in s["knobs"]:
		knob_text += " " + String(k["label"]).to_lower()
	var blurb := String(s["blurb"]).to_lower()
	var total := 0
	for w in words:
		if title.begins_with(w):
			total += 0
		elif title.contains(w):
			total += 1
		elif kind_text.contains(w) or knob_text.contains(w):
			total += 2
		elif blurb.contains(w):
			total += 3
		else:
			return -1
	return total
