class_name RackCatalogue
extends RefCounted

## The modules the modular room can hold: their jacks and knobs, as the engine (native/rack) declares
## them. The engine is the source of truth; `modules.json` is its `--describe`, committed so the
## room needs no compiler to be drawn, and a test holds the two to each other.

const PATH := "res://core/music/rack/modules.json"
## Groups in the order the palette shows them.
const GROUPS: Array[String] = ["Source", "Voice", "Control", "Filter", "Shape", "Time", "Mix"]

static var _modules := {}
static var _order: Array[String] = []
static var _watching: ModRegistry


static func _load() -> void:
	if not _modules.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("RackCatalogue: no %s" % PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return
	var reg := ModRegistry.ensure_current()
	if reg != _watching:
		_watching = reg
		reg.changed.connect(_forget)
	for m in data["modules"]:
		_order.append(m["type"])
		_modules[m["type"]] = _from_registry(m, reg)


## The mods are asked first: a module a mod provides takes its title, group and blurb from the
## manifest. The jacks and knobs stay the engine's own (docs/mods.md section 7), and every module
## no mod provides yet keeps the engine snapshot's text.
static func _from_registry(m: Dictionary, reg: ModRegistry) -> Dictionary:
	var e := reg.rack_module_entry(m["type"])
	if e.is_empty():
		return m
	var out := m.duplicate()
	for f in ["title", "group", "blurb"]:
		if e.get(f) is String:
			out[f] = e[f]
	return out


## The registry rescanned: read the table again the next time it is asked.
static func _forget() -> void:
	_modules.clear()
	_order.clear()


## Every module type, in palette order.
static func types() -> Array[String]:
	_load()
	return _order.duplicate()


static func has(type: String) -> bool:
	_load()
	return _modules.has(type)


static func spec(type: String) -> Dictionary:
	_load()
	return _modules.get(type, {})


static func in_group(group: String) -> Array[String]:
	_load()
	var out: Array[String] = []
	for t in _order:
		if _modules[t]["group"] == group:
			out.append(t)
	return out


static func knob_ids(type: String) -> Array[String]:
	var out: Array[String] = []
	for k in spec(type).get("knobs", []):
		out.append(k["id"])
	return out


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
