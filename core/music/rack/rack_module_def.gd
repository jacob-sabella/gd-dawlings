class_name RackModuleDef
extends RefCounted

## What a rack module is made of, for the modules a mod builds out of other modules (docs/mods.md 3.5
## and 4.1: `sound.kind` "composite"), and the engine's own description they are checked against.
## Pure functions over plain dictionaries; the registry calls `resolve` once per scan, and the rack
## (RackCatalogue, RackPatch, RackVoice) asks the registry's answer.
##
## A composite's `sound` is {modules: {id: {type, knobs?}}, cables: [[from, to]], ins: {name: [paths]},
## outs: {name: path}, knobs: {name: {to: "id.knob", label?}}, meter_from?: id}. Its own ins, outs and
## knobs ARE its interface: each name is a jack or knob of the plate, and it stands for the inner jack(s)
## or knob it points at. A knob's range, curve and units are the inner knob's, so a position (0..1) means
## the same thing on the plate and inside.
##
## Playing one is RackExpansion's business. This class reads no registry and no patch (so the registry can
## call it while it scans).

## How deep composites may nest: a composite of engine modules is depth 1.
const MAX_DEPTH := 3
## Between an instance's id and an inner module's id.
const SEP := "~"
## The most an inner module's id may hold.
const MAX_ID := 20
## The most engine modules a rack holds (MAX_MODULES) and the most cables (MAX_CABLES);
## a composite alone may not pass either.
const MAX_MODULES := 64
const MAX_CABLES := 160
## Where the engine describes itself.
const PATH := "res://core/music/rack/modules.json"
## A composite may not hold the modules a rack keeps one of (RackPatch.OUT_MODULE and WORLD_MODULE).
const FORBIDDEN_INNER: Array[String] = ["builtin.out", "builtin.world"]

static var _engine_modules: Array = []
static var _engine_by_type := {}


## The engine's `--describe` snapshot (`modules.json`): one dictionary per engine module with its
## jacks and knobs. Read once.
static func engine_modules() -> Array:
	if _engine_modules.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("RackModuleDef: no %s" % PATH)
			return []
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary and data.get("modules") is Array:
			_engine_modules = data["modules"]
			for m in _engine_modules:
				_engine_by_type[m["type"]] = m
	return _engine_modules


## The snapshot's description of an engine module by the engine's own name (`plaits`), or {}.
static func engine_spec(engine_type: String) -> Dictionary:
	engine_modules()
	return _engine_by_type.get(engine_type, {})


# --- checking, at scan time ------------------------------------------------------------------

## Checks every composite among `entries` (rack module type -> its manifest entry; the engine ones too,
## for the composites to name). Returns type -> {ok, reason, depth, cost, spec}: `spec` is {ins, outs,
## knobs} as the catalogue holds a module, for the engine modules and the composites that are fine; for a
## composite that is not, `ok` is false and `reason` says why in one sentence. Never throws.
static func resolve(entries: Dictionary) -> Dictionary:
	var memo := {}
	for type in entries:
		_resolve(String(type), entries, memo, [])
	return memo


static func _resolve(type: String, entries: Dictionary, memo: Dictionary, stack: Array) -> Dictionary:
	if memo.has(type):
		return memo[type]
	if not entries.has(type):
		return _failed("there is no module called %s" % type)
	if stack.has(type):
		return _failed("%s is inside itself (%s)" % [type, " > ".join(stack.slice(stack.find(type)) + [type])])
	var sound: Variant = entries[type].get("sound")
	if not sound is Dictionary:
		memo[type] = _failed("it has no sound")
		return memo[type]
	if sound.get("kind") == "composite":
		stack.append(type)
		memo[type] = _resolve_composite(type, sound, entries, memo, stack)
		stack.pop_back()
	else:
		var e := engine_spec(String(sound.get("type", "")))
		memo[type] = _failed("needs engine module %s" % sound.get("type", "?")) if e.is_empty() else {
				"ok": true, "reason": "", "depth": 0, "cost": 1, "spec": {"ins": e["ins"], "outs": e["outs"], "knobs": e["knobs"]}}
	return memo[type]


static func _failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "depth": 0, "cost": 1, "spec": {}}


static func _resolve_composite(type: String, sound: Dictionary, entries: Dictionary, memo: Dictionary, stack: Array) -> Dictionary:
	var modules: Variant = sound.get("modules")
	if not modules is Dictionary or (modules as Dictionary).is_empty():
		return _failed("it has no modules")
	var inner := {}  # inner id -> resolved info of its type
	var depth := 0
	var cost := 0
	for id in modules:
		var m: Variant = modules[id]
		var sid := String(id)
		if not sid.is_valid_identifier() or sid.length() > MAX_ID:
			return _failed("'%s' is not an id an inner module can have" % sid)
		if not m is Dictionary or not m.get("type") is String:
			return _failed("module %s has no type" % sid)
		var it: String = m["type"]
		if it in FORBIDDEN_INNER:
			return _failed("module %s: %s cannot be inside another module" % [sid, it])
		var info := _resolve(it, entries, memo, stack)
		if not info["ok"]:
			return _failed("module %s (%s): %s" % [sid, it, info["reason"]])
		inner[sid] = info
		depth = maxi(depth, int(info["depth"]))
		cost += int(info["cost"])
		var kn: Variant = m.get("knobs", {})
		if not kn is Dictionary:
			return _failed("module %s: knobs must be an object" % sid)
		for k in kn:
			if _knob_of(info, String(k)).is_empty() or not (kn[k] is float or kn[k] is int):
				return _failed("module %s has no knob %s, or it is not a number" % [sid, k])
	depth += 1
	if depth > MAX_DEPTH:
		return _failed("modules inside modules go %d deep; %d is the most" % [depth, MAX_DEPTH])
	if cost > MAX_MODULES:
		return _failed("it holds %d modules; a rack holds %d" % [cost, MAX_MODULES])
	var cables: Variant = sound.get("cables", [])
	if not cables is Array or (cables as Array).size() > MAX_CABLES:
		return _failed("cables must be a list of at most %d" % MAX_CABLES)
	for c in cables:
		if not c is Array or c.size() != 2 or not _jack(inner, c[0], true) or not _jack(inner, c[1], false):
			return _failed("cable %s is not from an output to an input of its modules" % JSON.stringify(c))
	var ins := {}
	var ins_in: Variant = sound.get("ins", {})
	var outs_in: Variant = sound.get("outs", {})
	var knobs_in: Variant = sound.get("knobs", {})
	if not ins_in is Dictionary or not outs_in is Dictionary or not knobs_in is Dictionary:
		return _failed("ins, outs and knobs must be objects")
	for name in ins_in:
		var targets: Variant = ins_in[name]
		if not String(name).is_valid_identifier() or not targets is Array or (targets as Array).is_empty():
			return _failed("in %s must name one or more inner inputs" % name)
		for path in targets:
			if not _jack(inner, path, false):
				return _failed("in %s: %s is not an input of its modules" % [name, path])
		ins[String(name)] = true
	var outs := {}
	for name in outs_in:
		if not String(name).is_valid_identifier() or not _jack(inner, outs_in[name], true):
			return _failed("out %s: %s is not an output of its modules" % [name, outs_in[name]])
		outs[String(name)] = true
	if ins.is_empty() and outs.is_empty():
		return _failed("it has no jacks")
	var knobs: Array = []
	for name in knobs_in:
		var k: Variant = knobs_in[name]
		if not String(name).is_valid_identifier() or not k is Dictionary or not k.get("to") is String:
			return _failed("knob %s must say where it goes ('to': 'id.knob')" % name)
		var target := _knob_spec(inner, modules, k["to"])
		if target.is_empty():
			return _failed("knob %s: %s is not a knob of its modules" % [name, k["to"]])
		target["id"] = String(name)
		if k.get("label") is String and not String(k["label"]).is_empty():
			target["label"] = String(k["label"])
		knobs.append(target)
	var meter: Variant = sound.get("meter_from")
	if meter != null and not (meter is String and inner.has(meter)):
		return _failed("meter_from must be one of its modules")
	return {"ok": true, "reason": "", "depth": depth, "cost": cost,
			"spec": {"ins": ins.keys(), "outs": outs.keys(), "knobs": knobs}}


## The knob dictionary of `info`'s spec with this id, or {}.
static func _knob_of(info: Dictionary, id: String) -> Dictionary:
	for k in info["spec"]["knobs"]:
		if k["id"] == id:
			return k
	return {}


## Whether `path` ("id.port") is an output (`output`) or input of one of the inner modules.
static func _jack(inner: Dictionary, path: Variant, output: bool) -> bool:
	if not path is String or (path as String).count(".") != 1:
		return false
	var id := (path as String).get_slice(".", 0)
	return inner.has(id) and (path as String).get_slice(".", 1) in inner[id]["spec"]["outs" if output else "ins"]


## A copy of the inner knob `to` ("id.knob") for the plate: its range and curve, with `set` (a position)
## where the composite gives that inner module a value in place of the engine's default; the catalogue
## turns it into the knob's `def`.
static func _knob_spec(inner: Dictionary, modules: Dictionary, to: String) -> Dictionary:
	if to.count(".") != 1 or not inner.has(to.get_slice(".", 0)):
		return {}
	var id := to.get_slice(".", 0)
	var k := _knob_of(inner[id], to.get_slice(".", 1)).duplicate()
	if k.is_empty():
		return {}
	var set: Dictionary = modules[id].get("knobs", {})
	if set.has(k["id"]):
		k["set"] = clampf(float(set[k["id"]]), 0.0, 1.0)
	return k
