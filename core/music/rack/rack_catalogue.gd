class_name RackCatalogue
extends RefCounted

## The modules the modular room can hold: their jacks and knobs, as the engine (native/rack) declares
## them. The engine is the source of truth; `modules.json` is its `--describe`, committed so the
## room needs no compiler to be drawn, and a test holds the two to each other.
##
## A module is known by its *type*, the one a mod gives it (`builtin.plaits`); the engine knows it by
## its own name (`plaits`, `engine_type`). A patch and everything on the wall speak types, and only
## the lines sent to the engine speak engine names.

const PATH := RackModuleDef.PATH
## A group no palette key opens: the modules other modules are built on (the engine's AIRWINDOWS under every effect).
const HIDDEN_GROUP := "Internal"

static var _modules := {}
static var _order: Array[String] = []
static var _watching: ModRegistry


static func _load() -> void:
	if not _modules.is_empty():
		return
	var snapshot := RackModuleDef.engine_modules()
	if snapshot.is_empty():
		return
	var reg := ModRegistry.ensure_current()
	if reg != _watching:
		_watching = reg
		reg.changed.connect(_forget)
	for m in snapshot:
		var type := reg.rack_type_of_engine(m["type"])
		if type == "":
			type = m["type"]
		_order.append(type)
		_modules[type] = _from_registry(m, type, reg)
	# The composites a mod builds from these, after the engine's own, in the registry's order.
	for type in reg.composite_types():
		var spec: Dictionary = reg.composite_info(type)["spec"]
		var knobs: Array = []
		for k: Dictionary in spec["knobs"]:
			var own := k.duplicate()
			if own.has("set"):
				own["def"] = real(own, float(own["set"]))
				own.erase("set")
			knobs.append(own)
		var m := {"type": type, "title": type, "group": "Other", "blurb": "", "ins": spec["ins"], "outs": spec["outs"],
				"knobs": knobs}
		_order.append(type)
		_modules[type] = _from_registry(m, type, reg)
		_modules[type]["engine"] = ""
		_modules[type]["composite"] = true


## A module a mod provides takes its title, group and blurb from the manifest. The jacks and knobs
## stay the engine's own (docs/mods.md section 7), and an engine module no mod claims keeps the
## engine snapshot's text.
static func _from_registry(m: Dictionary, type: String, reg: ModRegistry) -> Dictionary:
	var out := m.duplicate()
	out["engine"] = m["type"]
	out["type"] = type
	var e := reg.rack_module_entry(type)
	for f in ["title", "group", "blurb"]:
		if e.get(f) is String:
			out[f] = e[f]
	return out


## The registry rescanned: read the table again the next time it is asked.
static func _forget() -> void:
	_modules.clear()
	_order.clear()


## The palette groups in the order the palette shows them: those the available mods declare.
static func groups() -> Array[String]:
	var out: Array[String] = []
	for g in ModRegistry.ensure_current().groups():
		if g["id"] != HIDDEN_GROUP:
			out.append(g["id"])
	return out


## Every module type, in palette order.
static func types() -> Array[String]:
	_load()
	return _order.duplicate()


## True when a module of this type can be put in the case.
static func has(type: String) -> bool:
	_load()
	return _modules.has(type)


## The module's description: type, engine, title, group, blurb, ins, outs, knobs. Empty for an unknown type.
static func spec(type: String) -> Dictionary:
	_load()
	return _modules.get(type, {})


## The native engine's name for a type (`builtin.vco` -> `vco`), or "" for an unknown type or a composite
## (which is no engine module: `RackExpansion.expand` turns it into some).
static func engine_type(type: String) -> String:
	return spec(type).get("engine", "")


## What a module's type is called without its mod's prefix (`builtin.vco` -> `vco`): the stem of the
## ids it gets in a patch (`vco`, `vco2`).
static func short_name(type: String) -> String:
	return type.get_slice(".", type.count("."))


## The types of a palette group, in palette order.
static func in_group(group: String) -> Array[String]:
	_load()
	var out: Array[String] = []
	for t in _order:
		if _modules[t]["group"] == group:
			out.append(t)
	return out


## The knob ids of module `type`, in the engine's order.
static func knob_ids(type: String) -> Array[String]:
	var out: Array[String] = []
	for k in spec(type).get("knobs", []):
		out.append(k["id"])
	return out


## The description of knob `id` on module `type`; empty if there is none.
static func knob(type: String, id: String) -> Dictionary:
	for k in spec(type).get("knobs", []):
		if k["id"] == id:
			return k
	return {}


static func has_out(type: String, port: String) -> bool:
	return port in spec(type).get("outs", [])


static func has_in(type: String, port: String) -> bool:
	return port in spec(type).get("ins", [])


## A knob's position (0..1) to the value it means, as the engine reads it.
static func real(k: Dictionary, v01: float) -> float:
	var v := clampf(v01, 0.0, 1.0)
	var lo: float = k["lo"]
	var hi: float = k["hi"]
	match k["curve"]:
		"exp":
			return lo * pow(hi / lo, v)
		"step":
			var n := int(hi - lo) + 1
			return lo + mini(int(v * n), n - 1)
	return lo + (hi - lo) * v


## A value to the knob position that means it (a step's centre).
static func position(k: Dictionary, real_value: float) -> float:
	var lo: float = k["lo"]
	var hi: float = k["hi"]
	match k["curve"]:
		"exp":
			return clampf(log(real_value / lo) / log(hi / lo), 0.0, 1.0)
		"step":
			var n := int(hi - lo) + 1
			return clampf((real_value - lo + 0.5) / n, 0.0, 1.0)
	return clampf((real_value - lo) / (hi - lo), 0.0, 1.0)


static func default_position(k: Dictionary) -> float:
	return position(k, k["def"])


## What a knob reads out as: a step's name, or the number and its unit.
static func readout(k: Dictionary, v01: float) -> String:
	var r := real(k, v01)
	if k["curve"] == "step":
		var names: PackedStringArray = String(k["names"]).split("|")
		var i := int(r - float(k["lo"]))
		return names[i] if i >= 0 and i < names.size() else str(int(r))
	var unit: String = k["names"]
	if absf(r) >= 100.0:
		return "%d%s" % [roundi(r), (" " + unit) if unit != "" else ""]
	return ("%.2f" % r).rstrip("0").rstrip(".") + ((" " + unit) if unit != "" else "")
