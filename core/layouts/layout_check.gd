class_name LayoutCheck
extends RefCounted

## The field-by-field rules of a layout file (docs/layouts.md section 5.1), written once and used by
## LayoutData.parse. Each rule checks only what is present, because a fragment or a variant may carry
## part of an entry; completeness is checked on the merged result (LayoutSet.resolve).
## Nothing here throws: a broken field adds a LayoutProblem to the list it was given.

const MAX_COORD := 200.0
const MOBILITIES: Array[String] = ["wheeled", "fixed"]
const GROW: Array[String] = ["outward", "inward", "none"]
const WIRE_KINDS: Array[String] = ["feeds", "rides", "loom", "opens_onto"]
const PIECE_KEYS: Array[String] = ["id", "piece", "at", "fit", "mobility", "enabled"]
const AT_KEYS: Array[String] = ["anchor", "pos", "frame", "local", "up", "yaw"]
const ZONE_KEYS: Array[String] = ["min", "size", "grow"]
const GROUP_KEYS: Array[String] = ["id", "title", "colour", "lift", "banner", "members"]
const WIRE_KEYS: Array[String] = ["kind", "from", "to", "enabled"]
const SHELL_KEYS: Array[String] = ["builder", "kit", "size", "style"]
const MOOD_KEYS: Array[String] = ["base", "hit", "glow"]
const _ID_RE := "^[a-z][a-z0-9_]{0,39}$"
const _TYPE_RE := "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$"
const _FRAME_RE := "^authored:[a-z][a-z0-9_]{0,39}$"
const _COLOUR_RE := "^#[0-9A-Fa-f]{6}$"

## The layout being checked, for the problems' `layout` field.
var label := ""
## Shared with the caller: problems are appended here.
var problems: Array[LayoutProblem]


func _init(label_: String, problems_: Array[LayoutProblem]) -> void:
	label = label_
	problems = problems_


## Appends an error (or another severity) at `where`.
func bad(where: String, message: String, code: StringName = &"bad_schema",
		severity: StringName = LayoutProblem.ERROR) -> void:
	problems.append(LayoutProblem.make(code, label, message, where, severity))


## Warns about every key of `d` not in `known`.
func unknown_keys(d: Dictionary, known: Array[String], where: String) -> void:
	for key in d.keys():
		if not str(key) in known:
			bad(where, "unknown key '%s' ignored" % key, &"unknown_key", LayoutProblem.WARNING)


## True when `v` is a finite number (not a bool) within +-`limit`.
func is_number(v: Variant, limit: float = MAX_COORD) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and absf(float(v)) <= limit


## True when `v` is an array of `n` numbers; otherwise adds a problem at `where`.
func vector(v: Variant, n: int, where: String) -> bool:
	if v is Array and (v as Array).size() == n and (v as Array).all(func(x: Variant) -> bool: return is_number(x)):
		return true
	bad(where, "must be %d numbers within +-%d" % [n, int(MAX_COORD)])
	return false


## True when `v` is a string matching `pattern`; otherwise adds a problem at `where`.
func text(v: Variant, pattern: String, where: String, what: String) -> bool:
	if v is String and RegEx.create_from_string(pattern).search(v) != null:
		return true
	bad(where, "%s is not valid (%s)" % [what, str(v).left(40)])
	return false


## True when `v` is one of `options`; otherwise adds a problem at `where`.
func one_of(v: Variant, options: Array[String], where: String) -> bool:
	if v is String and v in options:
		return true
	bad(where, "must be one of %s" % ", ".join(options))
	return false


## The `shell` object: strings only. Sizes are not enumerated here (queue slice 8 settles them).
func shell(v: Variant, where: String) -> void:
	if not v is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(v, SHELL_KEYS, where)
	for key in SHELL_KEYS:
		if v.has(key):
			text(v[key], "^[A-Za-z][A-Za-z0-9_.-]{0,39}$", "%s.%s" % [where, key], key)


## The `mood` object: two colours and a glow.
func mood(v: Variant, where: String) -> void:
	if not v is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(v, MOOD_KEYS, where)
	for key in ["base", "hit"]:
		if v.has(key):
			text(v[key], _COLOUR_RE, "%s.%s" % [where, key], "colour")
	if v.has("glow") and not (is_number(v["glow"], 4.0) and float(v["glow"]) >= 0.0):
		bad(where + ".glow", "must be a number from 0 to 4")


## The `zones` object: id -> {min, size, grow}; a null entry removes the zone when merged.
func zones(v: Variant, where: String) -> void:
	if not v is Dictionary:
		bad(where, "must be an object")
		return
	for id in v.keys():
		var at := "%s.%s" % [where, id]
		text(str(id), _ID_RE, at, "zone id")
		var z: Variant = v[id]
		if z == null:
			continue
		if not z is Dictionary:
			bad(at, "must be an object or null")
			continue
		unknown_keys(z, ZONE_KEYS, at)
		if z.has("min"):
			vector(z["min"], 3, at + ".min")
		if z.has("size") and vector(z["size"], 3, at + ".size") \
				and (z["size"] as Array).any(func(x: Variant) -> bool: return float(x) <= 0.0):
			bad(at + ".size", "must be above zero on every side")
		if z.has("grow"):
			one_of(z["grow"], GROW, at + ".grow")


## One entry of `pieces`: the parts that are present.
func piece(p: Variant, where: String) -> void:
	if not p is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(p, PIECE_KEYS, where)
	if not p.has("id"):
		bad(where, "has no id")
	else:
		text(p["id"], _ID_RE, where + ".id", "id")
	if p.has("piece"):
		text(p["piece"], _TYPE_RE, where + ".piece", "piece")
	if p.has("mobility"):
		one_of(p["mobility"], MOBILITIES, where + ".mobility")
	if p.has("enabled") and not p["enabled"] is bool:
		bad(where + ".enabled", "must be true or false")
	if p.has("at"):
		placement(p["at"], where + ".at")
	if p.has("fit"):
		fit(p["fit"], where + ".fit")


## A piece's `fit`: where the room puts it once the desk has grown (`at` as [x, z], `yaw` in radians).
func fit(f: Variant, where: String) -> void:
	if not f is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(f, ["at", "yaw"], where)
	if not f.has("at"):
		bad(where, "has no at")
	else:
		vector(f["at"], 2, where + ".at")
	if f.has("yaw") and not is_number(f["yaw"], 1000.0):
		bad(where + ".yaw", "must be a number of radians")


## An `at` object (section 5.1): an anchor form or a frame form, never both.
func placement(at: Variant, where: String) -> void:
	if not at is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(at, AT_KEYS, where)
	var framed: bool = at.has("frame")
	if framed and (at.has("anchor") or at.has("pos")):
		bad(where, "a frame placement has no anchor or pos; use local")
	if not framed and at.has("local"):
		bad(where, "local goes with a frame; use pos")
	if framed:
		text(at["frame"], _FRAME_RE, where + ".frame", "frame")
	if at.has("local"):
		vector(at["local"], 2, where + ".local")
	if at.has("pos"):
		vector(at["pos"], 2, where + ".pos")
	if at.has("yaw"):
		yaw(at["yaw"], where + ".yaw")
	if at.has("up") and not (is_number(at["up"], 200.0) or (at["up"] is String and ShellFacts.is_anchor_name(at["up"]))):
		bad(where + ".up", "must be a height in metres or an anchor name", &"unknown_anchor" if at["up"] is String else &"bad_schema")
	if at.has("anchor"):
		var a: Variant = at["anchor"]
		if not a is Dictionary:
			bad(where + ".anchor", "must be an object with x and z")
			return
		unknown_keys(a, ["x", "z"], where + ".anchor")
		for axis in ["x", "z"]:
			if a.has(axis) and not (a[axis] is String and ShellFacts.is_anchor_name(a[axis])):
				bad("%s.anchor.%s" % [where, axis], "'%s' is not an anchor the shell provides" % str(a[axis]).left(40), &"unknown_anchor")


## A `yaw`: radians, or `{toward: <anchor>, snap: radians}` (turned to face the anchor, rounded to a multiple of snap).
func yaw(v: Variant, where: String) -> void:
	if is_number(v, 1000.0):
		return
	if not v is Dictionary:
		bad(where, "must be a number of radians or {toward, snap}")
		return
	unknown_keys(v, ["toward", "snap"], where)
	if not (v.get("toward") is String and ShellFacts.is_anchor_name(v["toward"])):
		bad(where + ".toward", "'%s' is not an anchor the shell provides" % str(v.get("toward")).left(40), &"unknown_anchor")
	if v.has("snap") and not (is_number(v["snap"], 7.0) and float(v["snap"]) >= 0.0):
		bad(where + ".snap", "must be a number of radians, 0 or more")


## One entry of `groups`.
func group(g: Variant, where: String) -> void:
	if not g is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(g, GROUP_KEYS, where)
	if not g.has("id"):
		bad(where, "has no id")
	else:
		text(g["id"], _ID_RE, where + ".id", "id")
	if g.has("title") and not (g["title"] is String and not str(g["title"]).is_empty()):
		bad(where + ".title", "must be a non-empty string")
	if g.has("colour"):
		text(g["colour"], _COLOUR_RE, where + ".colour", "colour")
	if g.has("lift") and not is_number(g["lift"], 10.0):
		bad(where + ".lift", "must be a number of metres")
	if g.has("banner"):
		placement(g["banner"], where + ".banner")
	if g.has("members"):
		var m: Variant = g["members"]
		if not (m is Array and (m as Array).all(func(x: Variant) -> bool: return x is String)):
			bad(where + ".members", "must be a list of piece ids")


## One entry of `wiring`.
func wire(w: Variant, where: String) -> void:
	if not w is Dictionary:
		bad(where, "must be an object")
		return
	unknown_keys(w, WIRE_KEYS, where)
	for key in ["kind", "from", "to"]:
		if not w.has(key):
			bad(where, "has no %s" % key)
	if w.has("kind"):
		one_of(w["kind"], WIRE_KINDS, where + ".kind")
	for key in ["from", "to"]:
		if w.has(key):
			text(w[key], _ID_RE, "%s.%s" % [where, key], key)
	if w.has("enabled") and not w["enabled"] is bool:
		bad(where + ".enabled", "must be true or false")
