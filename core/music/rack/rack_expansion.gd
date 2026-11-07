class_name RackExpansion
extends RefCounted

## A rack patch as the engine builds it, for the modules a mod builds out of other modules (RackModuleDef;
## docs/mods.md 3.5): a composite instance `pl` becomes its inner modules under namespaced ids (`pl~osc`,
## `pl~env`; `~` cannot be in an instance id, so nothing collides; a composite in a composite gives
## `pl~a~b`) with the inner cables, a patch cable on `pl.pitch` fans out to the inner jacks, and the
## instance's knob values go to the inner knobs they point at. Pure functions over plain patches.

## Between an instance's id and an inner module's id.
const SEP := RackModuleDef.SEP


static func _ids(p: Dictionary) -> Array:
	var ids: Array = (p["modules"] as Dictionary).keys()
	ids.sort()
	return ids


## Whether any module of `p` is a composite.
static func has_composite(p: Dictionary) -> bool:
	var reg := ModRegistry.ensure_current()
	for id in p["modules"]:
		if reg.is_composite(String(p["modules"][id]["type"])):
			return true
	return false


## How many engine modules a rack module of this type is: 1 for an engine module and for a type no mod
## here provides, the number it expands to for a composite. This is what counts against
## `RackPatch.MAX_MODULES`.
static func cost(type: String) -> int:
	return int(ModRegistry.ensure_current().composite_info(type).get("cost", 1))


## The patch as the engine builds it: `p` itself when it holds no composite, else a patch of the same
## shape where every composite instance is replaced by its inner modules (ids `<instance>~<inner>`,
## `at` [0, 0], their knobs from the composite and the instance's knob values routed to the inner knobs
## they point at) and the cables on it are rewired to the inner jacks. The inner cables come before the
## patch's own. Takes a `RackPatch.playable` patch; a cable on a jack the composite does not have is
## left out.
static func expand(p: Dictionary) -> Dictionary:
	if not has_composite(p):
		return p
	var reg := ModRegistry.ensure_current()
	var out := {"modules": {}, "cables": []}
	var ports := {}
	for id in _ids(p):
		var m: Dictionary = p["modules"][id]
		if reg.is_composite(m["type"]):
			ports[id] = _inline(reg, String(id), m["type"], m.get("knobs", {}), out)
		else:
			out["modules"][id] = m.duplicate(true)
	for c in p["cables"]:
		var from := _out_path(ports, String(c[0]))
		if from == "":
			continue
		for to in _in_paths(ports, String(c[1])):
			out["cables"].append([from, to])
	return out


## Puts the inner modules and cables of `type` (instance `prefix`, knob values `values`) in `out` and
## returns its jacks as expanded paths: {ins: {name: [path]}, outs: {name: path}, meter: engine id}.
static func _inline(reg: ModRegistry, prefix: String, type: String, values: Dictionary, out: Dictionary) -> Dictionary:
	var sound: Dictionary = reg.composite_sound(type)
	var ports := {}
	var knob_to: Dictionary = {}
	for name in sound.get("knobs", {}):
		if values.has(name):
			var to := String(sound["knobs"][name]["to"])
			knob_to[to] = clampf(float(values[name]), 0.0, 1.0)
	for id in sound["modules"]:
		var spec: Dictionary = sound["modules"][id]
		var knobs := {}
		for k in spec.get("knobs", {}):
			knobs[k] = clampf(float(spec["knobs"][k]), 0.0, 1.0)
		var routed := {}
		for to in knob_to:
			if String(to).get_slice(".", 0) == id:
				routed[String(to).get_slice(".", 1)] = knob_to[to]
		var at := prefix + SEP + String(id)
		knobs.merge(routed, true)
		if reg.is_composite(spec["type"]):
			ports[id] = _inline(reg, at, spec["type"], knobs, out)
		else:
			out["modules"][at] = {"type": spec["type"], "at": [0, 0], "knobs": knobs}
			ports[id] = null
	for c in sound.get("cables", []):
		var from := _out_path_in(ports, prefix, String(c[0]))
		for to in _in_paths_in(ports, prefix, String(c[1])):
			out["cables"].append([from, to])
	var res := {"ins": {}, "outs": {}}
	for name in sound.get("ins", {}):
		var paths: Array = []
		for t in sound["ins"][name]:
			paths.append_array(_in_paths_in(ports, prefix, String(t)))
		res["ins"][name] = paths
	for name in sound.get("outs", {}):
		res["outs"][name] = _out_path_in(ports, prefix, String(sound["outs"][name]))
	res["meter"] = _meter_of(sound, ports, prefix)
	return res


## The engine id whose meter stands for a composite: `meter_from`, else the module its first output
## comes from.
static func _meter_of(sound: Dictionary, ports: Dictionary, prefix: String) -> String:
	var from: String = sound.get("meter_from", "")
	if from == "":
		var outs: Dictionary = sound.get("outs", {})
		from = String(outs[outs.keys()[0]]).get_slice(".", 0) if not outs.is_empty() else ""
	if from == "" or not ports.has(from):
		return ""
	return ports[from]["meter"] if ports[from] != null else prefix + SEP + from


static func _out_path_in(ports: Dictionary, prefix: String, path: String) -> String:
	var id := path.get_slice(".", 0)
	if ports.get(id) != null:
		return ports[id]["outs"].get(path.get_slice(".", 1), "")
	return prefix + SEP + path


static func _in_paths_in(ports: Dictionary, prefix: String, path: String) -> Array:
	var id := path.get_slice(".", 0)
	if ports.get(id) != null:
		return ports[id]["ins"].get(path.get_slice(".", 1), [])
	return [prefix + SEP + path]


## A patch cable's output end as an expanded path ("" for a jack its composite does not have).
static func _out_path(ports: Dictionary, path: String) -> String:
	var id := path.get_slice(".", 0)
	if ports.has(id):
		return ports[id]["outs"].get(path.get_slice(".", 1), "")
	return path


## A patch cable's input end as the expanded paths it fans out to.
static func _in_paths(ports: Dictionary, path: String) -> Array:
	var id := path.get_slice(".", 0)
	if ports.has(id):
		return ports[id]["ins"].get(path.get_slice(".", 1), [])
	return [path]


## Outer module id -> the engine module whose meter shows it, for the composites of `p` (and only
## them): the room's lamps for a composite plate follow that module.
static func meter_map(p: Dictionary) -> Dictionary:
	var out := {}
	if not has_composite(p):
		return out
	var reg := ModRegistry.ensure_current()
	var scratch := {"modules": {}, "cables": []}
	for id in p["modules"]:
		var type: String = p["modules"][id]["type"]
		if reg.is_composite(type):
			out[id] = String(_inline(reg, String(id), type, {}, scratch)["meter"])
	return out
