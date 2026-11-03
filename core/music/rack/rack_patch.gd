class_name RackPatch
extends RefCounted

## The modular room's patch, as data: {modules: {id: {type, at: [x, y], knobs: {knob: 0..1}}},
## cables: [[from "id.out", to "id.in"], ...]}. Plain dictionaries so it replicates as the room's row
## `rack` and saves with the song. Every verb here checks against the catalogue (RackCatalogue) and
## says no to what the engine would refuse, so a patch that passes is a patch that plays.

const ROW := &"rack"
const MAX_MODULES := 64
const MAX_CABLES := 160

static func empty() -> Dictionary:
	return {"modules": {}, "cables": []}


## A patch you can play at once: the keys into a Plaits voice, a little echo and reverb, out.
static func default_patch() -> Dictionary:
	return preset(&"keys_voice")


static func presets() -> Array[StringName]:
	return [&"keys_voice", &"acid_line", &"drum_machine", &"ambient_bells", &"fm_bass", &"empty"]


static func preset_title(name: StringName) -> String:
	match name:
		&"keys_voice": return "Keys voice"
		&"acid_line": return "Acid line"
		&"drum_machine": return "Drum machine"
		&"ambient_bells": return "Ambient bells"
		&"fm_bass": return "Wobble bass"
	return "Empty"


static func preset(name: StringName) -> Dictionary:
	var p := empty()
	match name:
		&"keys_voice":
			_put(p, "keys", "keys", 0, 0)
			_put(p, "plaits", "plaits", 1, 0)
			_put(p, "delay", "delay", 2, 0, {"mix": 0.25, "sync": 0.5})
			_put(p, "reverb", "reverb", 3, 0, {"mix": 0.3})
			_put(p, "out", "out", 4, 0)
			_wire(p, [["keys.pitch", "plaits.pitch"], ["keys.gate", "plaits.trig"], ["keys.gate", "plaits.level"],
					["plaits.out", "delay.in"], ["delay.l", "reverb.l"], ["delay.r", "reverb.r"],
					["reverb.l", "out.l"], ["reverb.r", "out.r"]])
		&"acid_line":
			_put(p, "clock", "clock", 0, 0, {"sync": 0.0, "bpm": 0.45})
			_put(p, "seq", "seq", 1, 0, {"s1": 0.35, "s2": 0.0, "s3": 0.4, "s4": 0.35, "s5": 0.5, "s6": 0.0, "s7": 0.35, "s8": 0.42,
					"s9": 0.35, "s10": 0.0, "s11": 0.55, "s12": 0.35, "s13": 0.35, "s14": 0.45, "s15": 0.0, "s16": 0.6, "gate": 0.3})
			_put(p, "vco", "vco", 2, 0, {"wave": 0.5})
			_put(p, "env", "env", 2, 1, {"a": 0.0, "d": 0.35, "s": 0.0, "r": 0.2})
			_put(p, "lfo", "lfo", 0, 1, {"rate": 0.4})
			_put(p, "ladder", "ladder", 3, 0, {"cutoff": 0.45, "res": 0.65, "cv": 0.7})
			_put(p, "vca", "vca", 4, 0)
			_put(p, "delay", "delay", 5, 0, {"sync": 0.5, "fb": 0.45, "mix": 0.3})
			_put(p, "out", "out", 6, 0)
			_wire(p, [["clock.16th", "seq.clk"], ["seq.pitch", "vco.pitch"], ["seq.gate", "env.gate"], ["vco.out", "ladder.in"],
					["env.out", "ladder.cutoff"], ["ladder.out", "vca.in"], ["env.out", "vca.cv"], ["vca.out", "delay.in"],
					["delay.l", "out.l"], ["delay.r", "out.r"]])
		&"drum_machine":
			_put(p, "clock", "clock", 0, 0, {"sync": 0.0, "bpm": 0.5})
			_put(p, "kick", "drum", 1, 0, {"kind": 0.0})
			_put(p, "snare", "drum", 1, 1, {"kind": 0.5})
			_put(p, "hat", "drum", 1, 2, {"kind": 0.99, "decay": 0.15})
			_put(p, "mix", "mix", 2, 0, {"l1": 0.8, "l2": 0.55, "l3": 0.35})
			_put(p, "drive", "drive", 3, 0, {"drive": 0.35})
			_put(p, "out", "out", 4, 0)
			_wire(p, [["clock.beat", "kick.trig"], ["clock.bar", "snare.trig"], ["clock.8th", "hat.trig"], ["kick.out", "mix.in1"],
					["snare.out", "mix.in2"], ["hat.out", "mix.in3"], ["mix.out", "drive.in"], ["drive.out", "out.l"]])
		&"ambient_bells":
			_put(p, "clock", "clock", 0, 0, {"sync": 0.0, "bpm": 0.12})
			_put(p, "noise", "noise", 0, 1)
			_put(p, "rings", "rings", 1, 0, {"structure": 0.5, "damping": 0.8})
			_put(p, "reverb", "reverb", 2, 0, {"time": 0.9, "mix": 0.55})
			_put(p, "out", "out", 3, 0)
			_wire(p, [["clock.beat", "rings.strum"], ["noise.white", "rings.in"], ["rings.odd", "reverb.l"],
					["rings.even", "reverb.r"], ["reverb.l", "out.l"], ["reverb.r", "out.r"]])
		&"fm_bass":
			_put(p, "keys", "keys", 0, 0, {"oct": 0.2})
			_put(p, "lfo", "lfo", 0, 1, {"rate": 0.55})
			_put(p, "vco", "vco", 1, 0, {"wave": 0.5})
			_put(p, "fold", "fold", 2, 0, {"gain": 0.3})
			_put(p, "svf", "svf", 3, 0, {"cutoff": 0.55, "res": 0.4})
			_put(p, "env", "env", 1, 1)
			_put(p, "vca", "vca", 4, 0)
			_put(p, "out", "out", 5, 0)
			_wire(p, [["keys.pitch", "vco.pitch"], ["keys.gate", "env.gate"], ["lfo.out", "svf.cutoff"], ["vco.out", "fold.in"],
					["env.out", "fold.fold"], ["fold.out", "svf.in"], ["svf.lp", "vca.in"], ["env.out", "vca.cv"], ["vca.out", "out.l"]])
	return p


static func _put(p: Dictionary, id: String, type: String, col: int, row: int, knobs := {}) -> void:
	var k := {}
	for spec_knob in RackCatalogue.spec(type).get("knobs", []):
		k[spec_knob["id"]] = RackCatalogue.default_position(spec_knob)
	for key in knobs:
		k[key] = float(knobs[key])
	p["modules"][id] = {"type": type, "at": [col, row], "knobs": k}


static func _wire(p: Dictionary, cables: Array) -> void:
	for c in cables:
		connect_cable(p, c[0], c[1])


static func module_ids(p: Dictionary) -> Array:
	var ids: Array = (p["modules"] as Dictionary).keys()
	ids.sort()
	return ids


static func type_of(p: Dictionary, id: String) -> String:
	return (p["modules"] as Dictionary).get(id, {}).get("type", "")


## The next free id for a type: "vco", "vco2", "vco3".
static func new_id(p: Dictionary, type: String) -> String:
	if not (p["modules"] as Dictionary).has(type):
		return type
	var n := 2
	while (p["modules"] as Dictionary).has("%s%d" % [type, n]):
		n += 1
	return "%s%d" % [type, n]


## Adds a module. "" when the catalogue has no such type, the rack is full, or it is a second OUT.
static func add(p: Dictionary, type: String, at := Vector2i.ZERO) -> String:
	if not RackCatalogue.has(type) or (p["modules"] as Dictionary).size() >= MAX_MODULES:
		return ""
	if type == "out" and has_type(p, "out"):
		return ""
	var id := new_id(p, type)
	_put(p, id, type, at.x, at.y)
	return id


static func has_type(p: Dictionary, type: String) -> bool:
	for id in p["modules"]:
		if p["modules"][id]["type"] == type:
			return true
	return false


static func remove(p: Dictionary, id: String) -> bool:
	if not (p["modules"] as Dictionary).has(id):
		return false
	(p["modules"] as Dictionary).erase(id)
	var keep: Array = []
	for c in p["cables"]:
		if String(c[0]).get_slice(".", 0) != id and String(c[1]).get_slice(".", 0) != id:
			keep.append(c)
	p["cables"] = keep
	return true


static func move(p: Dictionary, id: String, at: Vector2i) -> void:
	if (p["modules"] as Dictionary).has(id):
		p["modules"][id]["at"] = [at.x, at.y]


## A jack path "id.port" is a real output (or input) of a module in the patch.
static func is_out(p: Dictionary, path: String) -> bool:
	return _port(p, path, true)


static func is_in(p: Dictionary, path: String) -> bool:
	return _port(p, path, false)


static func _port(p: Dictionary, path: String, output: bool) -> bool:
	var id := path.get_slice(".", 0)
	var port := path.get_slice(".", 1)
	var t := type_of(p, id)
	if t == "" or path.count(".") != 1:
		return false
	return RackCatalogue.has_out(t, port) if output else RackCatalogue.has_in(t, port)


## Puts a cable in. False for an unknown jack, a repeat, an output into the same module's input, or a
## full rack. (A loop through other modules is allowed: it carries last block's sound.)
static func connect_cable(p: Dictionary, from: String, to: String) -> bool:
	if not is_out(p, from) or not is_in(p, to) or (p["cables"] as Array).size() >= MAX_CABLES:
		return false
	if from.get_slice(".", 0) == to.get_slice(".", 0):
		return false
	for c in p["cables"]:
		if c[0] == from and c[1] == to:
			return false
	(p["cables"] as Array).append([from, to])
	return true


## Pulls every cable into an input; true if there was any.
static func pull(p: Dictionary, to: String) -> bool:
	var keep: Array = []
	for c in p["cables"]:
		if c[1] != to:
			keep.append(c)
	var had := keep.size() != (p["cables"] as Array).size()
	p["cables"] = keep
	return had


static func pull_one(p: Dictionary, from: String, to: String) -> bool:
	for i in (p["cables"] as Array).size():
		if p["cables"][i][0] == from and p["cables"][i][1] == to:
			(p["cables"] as Array).remove_at(i)
			return true
	return false


static func set_knob(p: Dictionary, id: String, knob: String, v01: float) -> bool:
	var t := type_of(p, id)
	if t == "" or RackCatalogue.knob(t, knob).is_empty():
		return false
	p["modules"][id]["knobs"][knob] = clampf(v01, 0.0, 1.0)
	return true


static func knob_of(p: Dictionary, id: String, knob: String) -> float:
	var t := type_of(p, id)
	var k := RackCatalogue.knob(t, knob)
	if k.is_empty():
		return 0.0
	return float(p["modules"].get(id, {}).get("knobs", {}).get(knob, RackCatalogue.default_position(k)))


## A patch from anywhere (a guest's ask, a saved song) made safe: only known modules, jacks and knobs,
## clamped, within the limits. What cannot be kept is dropped.
static func sanitize(raw: Variant) -> Dictionary:
	var p := empty()
	if not raw is Dictionary or not (raw as Dictionary).get("modules") is Dictionary:
		return p
	for id in raw["modules"]:
		var m: Variant = raw["modules"][id]
		var sid := String(id)
		if p["modules"].size() >= MAX_MODULES or not m is Dictionary or not RackCatalogue.has(String(m.get("type", ""))):
			continue
		if not sid.is_valid_identifier() or sid.length() > 20:
			continue
		var type := String(m["type"])
		if type == "out" and has_type(p, "out"):
			continue
		var at: Variant = m.get("at", [0, 0])
		var col := int(at[0]) if at is Array and at.size() >= 2 else 0
		var row := int(at[1]) if at is Array and at.size() >= 2 else 0
		_put(p, sid, type, clampi(col, 0, 15), clampi(row, 0, 7))
		var knobs: Variant = m.get("knobs", {})
		if knobs is Dictionary:
			for k in knobs:
				set_knob(p, sid, String(k), float(knobs[k]))
	var cables: Variant = raw.get("cables", [])
	if cables is Array:
		for c in cables:
			if c is Array and c.size() == 2:
				connect_cable(p, String(c[0]), String(c[1]))
	return p


## The engine's lines for a whole patch: clear, every module and its knobs, every cable.
static func lines(p: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["clear"])
	for id in module_ids(p):
		out.append("add %s %s" % [id, p["modules"][id]["type"]])
	for id in module_ids(p):
		var knobs: Dictionary = p["modules"][id]["knobs"]
		for k in knobs:
			out.append("knob %s.%s %.5f" % [id, k, float(knobs[k])])
	for c in p["cables"]:
		out.append("cable %s %s" % [c[0], c[1]])
	return out


static func knob_line(id: String, knob: String, v01: float) -> String:
	return "knob %s.%s %.5f" % [id, knob, clampf(v01, 0.0, 1.0)]
