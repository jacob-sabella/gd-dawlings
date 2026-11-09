class_name RackHelp
extends RefCounted

## The help card of a rack module: what it is, how it works, and what each jack and knob does, for someone who
## has never patched a modular synth. Put together from three sources, so that a change to the engine shows up:
##   - the catalogue (generated from the engine, `modules.json`): the jacks, knobs, ranges and their step names;
##   - `core/music/rack/help/<engine type>.json`, written by hand: `what`, `how`, `try`, and a sentence for every
##     jack and knob (a test holds the ids to the catalogue's, both ways);
##   - for AIRWINDOWS, Chris Johnson's own text for the chosen effect (`airwindows_help.json`, parsed from his
##     Airwindopedia by tools/airwindows_help.py) and the effect's parameter names (`airwindows.json`, from the engine).
## `help/_glossary.json` explains the words of the trade; a card lists the ones its text uses.
## Pure functions over those files; no node.

const DIR := "res://core/music/rack/help/"
const AW_PARAMS := "res://core/music/rack/airwindows.json"
const AW_HELP := "res://core/music/rack/airwindows_help.json"
const AW_TYPE := "builtin.airwindows"
const AW_PREFIX := "builtin.aw."
const AW_JACKS := {"l": "Left channel of the stereo signal.", "r": "Right channel of the stereo signal."}
static var _aw_by_type := {}

static var _cache := {}


static func _json(path: String) -> Variant:
	if not _cache.has(path):
		var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		_cache[path] = JSON.parse_string(text) if text != "" else null
	return _cache[path]


## The hand-written text of an engine module (`vco`), or {}.
static func written(engine_type: String) -> Dictionary:
	var d: Variant = _json(DIR + engine_type + ".json")
	return d if d is Dictionary else {}


## The glossary: term -> explanation.
static func glossary() -> Dictionary:
	var d: Variant = _json(DIR + "_glossary.json")
	return d if d is Dictionary else {}


## What a knob's range is, in words: its steps, or its two ends with the unit.
static func range_text(k: Dictionary) -> String:
	if k["curve"] == "step":
		return String(k["names"]).replace("|", " / ")
	var lo := RackCatalogue.readout(k, 0.0)
	var hi := RackCatalogue.readout(k, 1.0)
	return "%s to %s" % [lo, hi]


## The card of module `type` (`builtin.vco`): {title, group, blurb, what, how, try, ins, outs, knobs, terms}
## with `ins`/`outs` as [{id, text}] and `knobs` as [{id, label, range, text}]. `effect` is the chosen
## Airwindows effect for that module (ignored for others). {} for an unknown type.
static func card(type: String, effect := "") -> Dictionary:
	var spec := RackCatalogue.spec(type)
	if spec.is_empty():
		return {}
	var aw_effect := effect_of(type)
	var w := written(String(spec.get("engine", "")))
	var c := {"type": type, "title": spec["title"], "group": spec["group"], "blurb": spec["blurb"],
			"what": w.get("what", ""), "how": w.get("how", ""), "try": w.get("try", ""),
			"ins": [], "outs": [], "knobs": [], "missing": []}
	for pin in spec["ins"]:
		c["ins"].append({"id": pin, "text": AW_JACKS.get(pin, "") if aw_effect != "" else _line(w, "ins", pin, c)})
	for pout in spec["outs"]:
		c["outs"].append({"id": pout, "text": AW_JACKS.get(pout, "") if aw_effect != "" else _line(w, "outs", pout, c)})
	for k: Dictionary in spec["knobs"]:
		c["knobs"].append({"id": k["id"], "label": k["label"], "range": range_text(k),
				"text": "" if aw_effect != "" else _line(w, "knobs", k["id"], c)})
	if type == AW_TYPE:
		c["airwindows"] = airwindows(effect)
	elif aw_effect != "":
		c["airwindows"] = airwindows(aw_effect)
	c["terms"] = terms_in(c)
	return c


## The effect id an Airwindows module type stands for (`builtin.aw.galactic` -> "Galactic"), or "".
static func effect_of(type: String) -> String:
	if not type.begins_with(AW_PREFIX):
		return ""
	if _aw_by_type.is_empty():
		var meta: Variant = _json(AW_PARAMS)
		if meta is Dictionary:
			for e: Dictionary in meta["effects"]:
				_aw_by_type[AW_PREFIX + String(e["id"]).to_lower()] = e["id"]
	return String(_aw_by_type.get(type, ""))


static func _line(w: Dictionary, part: String, id: String, c: Dictionary) -> String:
	var t: String = (w.get(part, {}) as Dictionary).get(id, "")
	if t == "":
		(c["missing"] as Array).append("%s.%s" % [part, id])
	return t


## Airwindows effect `id`: {id, title, summary, text: [paragraphs], more, categories, params: [{letter, name, default}],
## known}. Without text of its own (14 effects have none) it still has its parameters.
static func airwindows(id: String) -> Dictionary:
	var out := {"id": id, "title": id, "summary": "", "text": [], "more": false, "categories": [], "params": [], "known": false}
	var meta: Variant = _json(AW_PARAMS)
	if meta is Dictionary:
		for e: Dictionary in meta["effects"]:
			if e["id"] == id:
				out["title"] = e["title"]
				out["known"] = true
				var n := 0
				for p: Dictionary in e["params"]:
					out["params"].append({"letter": char(65 + n), "name": p["name"], "default": p["default"]})
					n += 1
	var h: Variant = _json(AW_HELP)
	if h is Dictionary and (h["effects"] as Dictionary).has(id):
		var e: Dictionary = h["effects"][id]
		out["summary"] = e["summary"]
		out["text"] = e["text"]
		out["more"] = e["more"]
		out["categories"] = e["categories"]
	return out


## The Airwindows effects by category: {category: [ids]}, in alphabetical order, with "All" last.
static func airwindows_categories() -> Dictionary:
	var out := {}
	var h: Variant = _json(AW_HELP)
	if h is Dictionary:
		out = (h["categories"] as Dictionary).duplicate()
	var meta: Variant = _json(AW_PARAMS)
	var every: Array = []
	if meta is Dictionary:
		for e: Dictionary in meta["effects"]:
			every.append(e["id"])
	out["All"] = every
	return out


## The glossary terms a card's text uses, as [[term, explanation]], in the glossary's order.
static func terms_in(c: Dictionary) -> Array:
	var hay := " ".join([c["what"], c["how"], c["try"]]).to_lower()
	for part in ["ins", "outs", "knobs"]:
		for row: Dictionary in c[part]:
			hay += " " + String(row["text"]).to_lower()
	var out: Array = []
	var g := glossary()
	for term: String in g:
		if _uses(hay, term.to_lower()):
			out.append([term, g[term]])
	return out


static func _uses(hay: String, term: String) -> bool:
	var at := hay.find(term)
	while at >= 0:
		var before := hay[at - 1] if at > 0 else " "
		var after := hay[at + term.length()] if at + term.length() < hay.length() else " "
		if not _letter(before) and not _letter(after):
			return true
		at = hay.find(term, at + 1)
	return false


static func _letter(ch: String) -> bool:
	return ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9"


## What is wrong with the help of an engine module, for the test and for `tools`: ids with no text, and text for
## ids the engine does not have. [] when it is complete.
static func problems(type: String) -> Array[String]:
	var spec := RackCatalogue.spec(type)
	var out: Array[String] = []
	if spec.is_empty():
		return out
	var aw_effect := effect_of(type)
	var w := written(String(spec.get("engine", "")))
	if w.is_empty():
		out.append("%s: no help file" % type)
		return out
	for key in ["what", "how", "try"]:
		if String(w.get(key, "")).strip_edges() == "":
			out.append("%s: no %s" % [type, key])
	var have := {"ins": spec["ins"], "outs": spec["outs"], "knobs": (spec["knobs"] as Array).map(func(k: Dictionary) -> String: return k["id"])}
	for part: String in have:
		var told: Dictionary = w.get(part, {})
		for id in have[part]:
			if String(told.get(id, "")).strip_edges() == "":
				out.append("%s: %s %s has no text" % [type, part, id])
		for id: String in told:
			if not (have[part] as Array).has(id):
				out.append("%s: text for %s %s, which the module does not have" % [type, part, id])
	return out
