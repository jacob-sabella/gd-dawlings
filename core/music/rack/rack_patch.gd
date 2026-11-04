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
	return [&"keys_voice", &"acid_line", &"drum_machine", &"ambient_bells", &"fm_bass", &"big_rig", &"heavy_machine", &"empty"]


static func preset_title(name: StringName) -> String:
	match name:
		&"keys_voice": return "Keys voice"
		&"acid_line": return "Acid line"
		&"drum_machine": return "Drum machine"
		&"ambient_bells": return "Ambient bells"
		&"fm_bass": return "Wobble bass"
		&"big_rig": return "Big rig (33 modules)"
		&"heavy_machine": return "Heavy machine"
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
					"s9": 0.35, "s10": 0.0, "s11": 0.55, "s12": 0.35, "s13": 0.35, "s14": 0.45, "s15": 0.0, "s16": 0.6, "gate": 0.55})
			_put(p, "vco", "vco", 2, 0, {"wave": 0.5})
			_put(p, "env", "env", 2, 1, {"a": 0.0, "d": 0.72, "s": 0.12, "r": 0.5})
			_put(p, "lfo", "lfo", 0, 1, {"rate": 0.4})
			_put(p, "ladder", "ladder", 3, 0, {"cutoff": 0.45, "res": 0.65, "cv": 0.7})
			_put(p, "vca", "vca", 4, 0)
			_put(p, "delay", "delay", 5, 0, {"sync": 0.5, "fb": 0.45, "mix": 0.3})
			_put(p, "out", "out", 6, 0, {"level": 0.75})
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
		&"heavy_machine":
			# A detuned saw pair and a sub through a folder and a screaming ladder, a kick-snare-hat
			# loop under it, all crushed, driven, echoed and washed.
			_put(p, "clk", "clock", 0, 0, {"sync": 0.0, "bpm": 0.40})
			_put(p, "seq", "seq", 1, 0, {"s1": 0.10, "s2": 0.10, "s3": 0.22, "s4": 0.10, "s5": 0.10, "s6": 0.30, "s7": 0.10, "s8": 0.17,
					"s9": 0.10, "s10": 0.10, "s11": 0.22, "s12": 0.10, "s13": 0.35, "s14": 0.10, "s15": 0.28, "s16": 0.17, "gate": 0.6})
			_put(p, "v1", "vco", 2, 0, {"wave": 0.5, "tune": 0.40, "fine": 0.46})
			_put(p, "v2", "vco", 2, 1, {"wave": 0.5, "tune": 0.40, "fine": 0.54})
			_put(p, "env", "env", 3, 0, {"a": 0.0, "d": 0.7, "s": 0.2, "r": 0.5})
			_put(p, "lfo", "lfo", 3, 1, {"rate": 0.35, "depth": 0.7})
			_put(p, "mixv", "mix", 4, 0, {"l1": 0.55, "l2": 0.55, "l3": 0.6})
			_put(p, "fold", "fold", 5, 0, {"gain": 0.1})
			_put(p, "lad", "ladder", 6, 0, {"cutoff": 0.42, "res": 0.7, "drive": 0.4, "cv": 0.75})
			_put(p, "vca", "vca", 7, 0)
			_put(p, "kick", "drum", 4, 1, {"kind": 0.0})
			_put(p, "snare", "drum", 5, 1, {"kind": 0.5})
			_put(p, "hat", "drum", 6, 1, {"kind": 0.99, "decay": 0.12})
			_put(p, "mixd", "mix", 7, 1, {"l1": 0.9, "l2": 0.6, "l3": 0.35})
			_put(p, "mixm", "mix", 8, 0, {"l1": 0.75, "l2": 0.8})
			_put(p, "crush", "crush", 9, 0, {"rate": 0.05, "bits": 0.8, "mix": 0.15})
			_put(p, "drive", "drive", 10, 0, {"drive": 0.35, "level": 0.6})
			_put(p, "dly", "delay", 11, 0, {"sync": 0.5, "fb": 0.5, "mix": 0.3})
			_put(p, "rev", "reverb", 12, 0, {"time": 0.7, "mix": 0.25})
			_put(p, "out", "out", 13, 0, {"level": 0.5})
			_wire(p, [["clk.16th", "seq.clk"], ["seq.pitch", "v1.pitch"], ["seq.pitch", "v2.pitch"], ["seq.gate", "env.gate"],
					["v1.out", "mixv.in1"], ["v2.out", "mixv.in2"], ["v1.sub", "mixv.in3"], ["mixv.out", "fold.in"],
					["env.out", "fold.fold"], ["fold.out", "lad.in"], ["env.out", "lad.cutoff"], ["lfo.uni", "lad.cutoff"],
					["lad.out", "vca.in"], ["env.out", "vca.cv"], ["clk.beat", "kick.trig"], ["clk.bar", "snare.trig"],
					["clk.8th", "hat.trig"], ["kick.out", "mixd.in1"], ["snare.out", "mixd.in2"], ["hat.out", "mixd.in3"],
					["vca.out", "mixm.in1"], ["mixd.out", "mixm.in2"], ["mixm.out", "crush.in"], ["crush.out", "drive.in"],
					["drive.out", "dly.in"], ["dly.l", "rev.l"], ["dly.r", "rev.r"], ["rev.l", "out.l"], ["rev.r", "out.r"]])
		&"big_rig":
			var col0 := 0
			_put(p, "clk", "clock", col0, 0, {"sync": 0.0, "bpm": 0.43})
			col0 += RackLayout.width_of("clock")
			_put(p, "seq1", "seq", col0, 0, {"s1": 0.0132, "s2": 0.0132, "s3": 0.1974, "s4": 0.3290, "s5": 0.2763, "s6": 0.1974, "s7": 0.0921, "s8": 0.1974, "s9": 0.0132, "s10": 0.0132, "s11": 0.1974, "s12": 0.3290, "s13": 0.4079, "s14": 0.3816, "s15": 0.3290, "s16": 0.2763, "len": 0.9688, "gate": 0.4737})
			col0 += RackLayout.width_of("seq")
			_put(p, "seq2", "seq", col0, 0, {"s1": 0.0132, "s2": 0.0132, "s3": 0.0132, "s4": 0.3290, "s5": 0.0132, "s6": 0.0132, "s7": 0.2763, "s8": 0.1974, "s9": 0.0132, "s10": 0.0132, "s11": 0.0132, "s12": 0.3290, "s13": 0.0132, "s14": 0.0132, "s15": 0.2763, "s16": 0.1974, "len": 0.4688, "gate": 0.4210})
			col0 += RackLayout.width_of("seq")
			_put(p, "seq3", "seq", col0, 0, {"s1": 0.0132, "s2": 0.0132, "s3": 0.0921, "s4": 0.0921, "s5": 0.1974, "s6": 0.1974, "s7": 0.1447, "s8": 0.1447, "s9": 0.0132, "s10": 0.0132, "s11": 0.0921, "s12": 0.0921, "s13": 0.1974, "s14": 0.1974, "s15": 0.1447, "s16": 0.1447, "len": 0.4688, "gate": 0.8947})
			col0 += RackLayout.width_of("seq")
			_put(p, "lfo1", "lfo", col0, 0, {"rate": 0.2357, "depth": 0.8000, "shape": 0.1000})
			col0 += RackLayout.width_of("lfo")
			_put(p, "lfo2", "lfo", col0, 0, {"rate": 0.4475, "depth": 0.9000, "shape": 0.3000})
			col0 += RackLayout.width_of("lfo")
			_put(p, "noise", "noise", col0, 0, {})
			col0 += RackLayout.width_of("noise")
			_put(p, "sh1", "sh", col0, 0, {})
			col0 += RackLayout.width_of("sh")
			_put(p, "env1", "env", col0, 0, {"a": 0.1671, "d": 0.6794, "s": 0.1000, "r": 0.5895})
			col0 += RackLayout.width_of("env")
			_put(p, "env2", "env", col0, 0, {"a": 0.1325, "d": 0.6657, "s": 0.5000, "r": 0.5895})
			col0 += RackLayout.width_of("env")
			_put(p, "env3", "env", col0, 0, {"a": 0.0836, "d": 0.6503, "s": 0.2000, "r": 0.5124})
			col0 += RackLayout.width_of("env")
			var col1 := 0
			_put(p, "v1", "vco", col1, 1, {"wave": 0.6250, "tune": 0.4375, "fm": 0.0000})
			col1 += RackLayout.width_of("vco")
			_put(p, "v2", "vco", col1, 1, {"wave": 0.3750, "tune": 0.4375, "fine": 0.5550})
			col1 += RackLayout.width_of("vco")
			_put(p, "v3", "vco", col1, 1, {"wave": 0.3750, "tune": 0.1875})
			col1 += RackLayout.width_of("vco")
			_put(p, "svf", "svf", col1, 1, {"cutoff": 0.3713, "res": 0.4592, "cv": 0.5500})
			col1 += RackLayout.width_of("svf")
			_put(p, "mixL", "mix", col1, 1, {"l1": 0.5333, "l2": 0.4667, "l3": 0.4000})
			col1 += RackLayout.width_of("mix")
			_put(p, "fold", "fold", col1, 1, {"gain": 0.0454})
			col1 += RackLayout.width_of("fold")
			_put(p, "lad", "ladder", col1, 1, {"cutoff": 0.5000, "res": 0.6111, "drive": 0.2000, "cv": 0.6500})
			col1 += RackLayout.width_of("ladder")
			_put(p, "vca1", "vca", col1, 1, {})
			col1 += RackLayout.width_of("vca")
			_put(p, "vca3", "vca", col1, 1, {})
			col1 += RackLayout.width_of("vca")
			var col2 := 0
			_put(p, "pl", "plaits", col2, 2, {"engine": 0.3542, "note": 0.4375, "harm": 0.4000, "timbre": 0.5000, "morph": 0.5000, "decay": 0.7000, "lpg": 0.6000, "tma": 0.7500, "mma": 0.7500})
			col2 += RackLayout.width_of("plaits")
			_put(p, "rg", "rings", col2, 2, {"model": 0.0833, "structure": 0.4500, "bright": 0.6000, "damping": 0.5500, "position": 0.4000, "note": 0.0000})
			col2 += RackLayout.width_of("rings")
			_put(p, "kick", "drum", col2, 2, {"kind": 0.1667, "freq": 0.1273, "decay": 0.5500})
			col2 += RackLayout.width_of("drum")
			_put(p, "snare", "drum", col2, 2, {"kind": 0.5000, "decay": 0.4000})
			col2 += RackLayout.width_of("drum")
			_put(p, "hat", "drum", col2, 2, {"kind": 0.8333, "decay": 0.1200})
			col2 += RackLayout.width_of("drum")
			var col3 := 0
			_put(p, "mixA", "mix", col3, 3, {"l1": 0.5, "l2": 0.6, "l3": 0.55, "l4": 0.4})
			col3 += RackLayout.width_of("mix")
			_put(p, "mixB", "mix", col3, 3, {"l1": 0.6, "l2": 0.5, "l3": 0.35})
			col3 += RackLayout.width_of("mix")
			_put(p, "mixC", "mix", col3, 3, {"l1": 0.9, "l2": 0.9, "master": 1.0})
			col3 += RackLayout.width_of("mix")
			_put(p, "crush", "crush", col3, 3, {"mix": 0.0000})
			col3 += RackLayout.width_of("crush")
			_put(p, "dly", "delay", col3, 3, {"time": 0.6830, "fb": 0.4737, "mix": 0.3000, "pp": 0.7500})
			col3 += RackLayout.width_of("delay")
			_put(p, "cld", "clouds", col3, 3, {"mix": 0.0000, "size": 0.5000, "density": 0.7000, "reverb": 0.2500})
			col3 += RackLayout.width_of("clouds")
			_put(p, "rev", "reverb", col3, 3, {"time": 0.8000, "mix": 0.3000})
			col3 += RackLayout.width_of("reverb")
			_put(p, "out", "out", col3, 3, {"level": 0.4500})
			col3 += RackLayout.width_of("out")
			_put(p, "scope", "scope", col3, 3, {"gain": 0.85})
			col3 += RackLayout.width_of("scope")
			_put(p, "bass_scope", "scope", col2, 2, {"time": 0.45, "gain": 0.8})
			col2 += RackLayout.width_of("scope")
			_wire(p, [["clk.16th", "seq1.clk"], ["clk.8th", "seq2.clk"], ["clk.beat", "seq3.clk"], ["seq1.pitch", "v1.pitch"], ["seq1.pitch", "v2.pitch"], ["v2.out", "v1.fm"], ["seq1.gate", "env1.gate"], ["seq1.gate", "env2.gate"], ["v1.out", "mixL.in1"], ["v2.out", "mixL.in2"], ["v1.sub", "mixL.in3"], ["mixL.out", "fold.in"], ["lfo2.uni", "fold.fold"], ["fold.out", "lad.in"], ["env1.out", "lad.cutoff"], ["lfo1.uni", "lad.cutoff"], ["sh1.out", "lad.cutoff"], ["noise.white", "sh1.in"], ["clk.16th", "sh1.trig"], ["lad.out", "vca1.in"], ["env2.out", "vca1.cv"], ["seq2.pitch", "v3.pitch"], ["seq2.gate", "env3.gate"], ["v3.out", "svf.in"], ["env3.out", "svf.cutoff"], ["svf.lp", "vca3.in"], ["env3.out", "vca3.cv"], ["seq3.pitch", "pl.pitch"], ["seq3.gate", "pl.trig"], ["lfo1.uni", "pl.timbre"], ["lfo2.uni", "pl.morph"], ["seq1.pitch", "rg.pitch"], ["seq2.gate", "rg.strum"], ["vca1.out", "mixA.in1"], ["vca3.out", "mixA.in2"], ["pl.out", "mixA.in3"], ["rg.odd", "mixA.in4"], ["clk.beat", "kick.trig"], ["clk.bar", "snare.trig"], ["clk.16th", "hat.trig"], ["kick.out", "mixB.in1"], ["snare.out", "mixB.in2"], ["hat.out", "mixB.in3"], ["mixA.out", "mixC.in1"], ["mixB.out", "mixC.in2"], ["mixC.out", "crush.in"], ["crush.out", "dly.in"], ["dly.l", "cld.l"], ["dly.r", "cld.r"], ["cld.l", "rev.l"], ["cld.r", "rev.r"], ["rev.l", "out.l"], ["rev.r", "out.r"], ["rev.l", "scope.in"], ["vca1.out", "bass_scope.in"]])
	RackLayout.tidy(p)
	if name != &"big_rig":
		# The big rig is laid out by hand, a row to a job; the small ones read as their own diagrams.
		RackLayout.flow(p)
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


## The room's world sockets (Modular.WORLD, in its order) as outputs of the rack's WORLD module.
const WORLD_OUTS: Array[String] = ["weather", "drips", "venue", "ring1", "ring2", "ring3", "ring4", "ring5",
		"ring6", "ring7", "ring8", "marbles"]
## The inputs that take a gate rather than a level.
const GATE_INS: Array[String] = ["gate", "trig", "strum", "clk", "clock", "reset", "rst", "step"]


## The WORLD module's output a world socket (`world:weather`, `world:ring_3`) is, as a path: its gate
## for an input that takes one, its level for the rest. "" for something that is no socket.
static func world_out(p: Dictionary, socket: StringName, to := "") -> String:
	var at := Modular.WORLD.find(socket)
	var id := ""
	for m in p["modules"]:
		if p["modules"][m]["type"] == "world":
			id = m
			break
	if at < 0 or id == "":
		return ""
	var gate := GATE_INS.has(to.get_slice(".", 1))
	return "%s.%s%s" % [id, WORLD_OUTS[at], "_g" if gate else ""]


## Where a world socket's cable goes now: the input it is in, or "".
static func world_sink(p: Dictionary, socket: StringName) -> String:
	var at := Modular.WORLD.find(socket)
	for c in p["cables"]:
		var id := String(c[0]).get_slice(".", 0)
		if type_of(p, id) != "world" or at < 0:
			continue
		var port := String(c[0]).get_slice(".", 1).trim_suffix("_g")
		if port == WORLD_OUTS[at]:
			return c[1]
	return ""


## Every input of the rack's modules with nothing cabled into it, in the case's order (not the WORLD
## module's own, which has none).
static func free_inputs(p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var taken := {}
	for c in p["cables"]:
		taken[c[1]] = true
	var ids := module_ids(p)
	ids.sort_custom(func(a, b) -> bool:
		var pa: Array = p["modules"][a]["at"]
		var pb: Array = p["modules"][b]["at"]
		return (pa[1] < pb[1]) or (pa[1] == pb[1] and pa[0] < pb[0]))
	for id in ids:
		var t: String = p["modules"][id]["type"]
		for port in RackCatalogue.spec(t).get("ins", []):
			var path := "%s.%s" % [id, port]
			if not taken.has(path) and t != "out":
				out.append(path)
	return out


## The input a world socket's cable steps to, `way` on from where it is: none, then each free input.
static func step_world(p: Dictionary, socket: StringName, way: int) -> String:
	var now := world_sink(p, socket)
	# The ring is the free inputs as they are with this socket's cable out, so the input it is in is
	# one of them and the press goes on from there.
	var bare := p.duplicate(true)
	if now != "":
		for c in (bare["cables"] as Array).duplicate():
			if c[1] == now and type_of(bare, String(c[0]).get_slice(".", 0)) == "world" \
					and String(c[0]).get_slice(".", 1).trim_suffix("_g") == WORLD_OUTS[Modular.WORLD.find(socket)]:
				(bare["cables"] as Array).erase(c)
	var ring: Array[String] = [""]
	ring.append_array(free_inputs(bare))
	var at := ring.find(now) if now != "" else 0
	return ring[posmod(maxi(at, 0) + (1 if way >= 0 else -1), ring.size())]


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
		_put(p, sid, type, clampi(col, 0, RackLayout.COLS - RackLayout.width_of(type)), clampi(row, 0, RackLayout.ROWS - 1))
		var knobs: Variant = m.get("knobs", {})
		if knobs is Dictionary:
			for k in knobs:
				set_knob(p, sid, String(k), float(knobs[k]))
	var cables: Variant = raw.get("cables", [])
	if cables is Array:
		for c in cables:
			if c is Array and c.size() == 2:
				connect_cable(p, String(c[0]), String(c[1]))
	RackLayout.tidy(p)
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


## The room's asks of the patch, one verb: `op` is add [type, col, row], remove [id], move [id, col, row],
## cable [from, to], pull [to], pull_one [from, to], knob [id, knob, v] or preset [name]. Done to `p`;
## the refusal in words if it cannot be, "" when done.
static func answer(p: Dictionary, op: String, args: Array) -> String:
	match op:
		"add":
			var type := String(args[0])
			var at := Vector2i(int(args[1]), int(args[2]))
			if not RackCatalogue.has(type):
				return "there is no module called %s" % type
			if type == "out" and has_type(p, "out"):
				return "the rack has its OUT already: one sound leaves the room"
			if (p["modules"] as Dictionary).size() >= MAX_MODULES:
				return "the case is full: take something out first"
			if at.x < 0:
				at = RackLayout.free_slot(p, type)
			if not RackLayout.fits(p, type, at):
				return "that does not fit there"
			return "" if add(p, type, at) != "" else "that module could not be added"
		"remove":
			if type_of(p, String(args[0])) == "out":
				return "the OUT stays: without it nothing leaves the room"
			return "" if remove(p, String(args[0])) else "there is no such module"
		"move":
			var id := String(args[0])
			if not (p["modules"] as Dictionary).has(id):
				return "there is no such module"
			var to := Vector2i(int(args[1]), int(args[2]))
			if not RackLayout.fits(p, type_of(p, id), to, id):
				return "that does not fit there"
			move(p, id, to)
			return ""
		"cable":
			if not is_out(p, String(args[0])) or not is_in(p, String(args[1])):
				return "a cable goes from an output to an input"
			if String(args[0]).get_slice(".", 0) == String(args[1]).get_slice(".", 0):
				return "a module cannot patch into itself"
			return "" if connect_cable(p, String(args[0]), String(args[1])) else "that cable is already there, or the case has no more room for cables"
		"pull":
			return "" if pull(p, String(args[0])) else "there was no cable there"
		"pull_one":
			return "" if pull_one(p, String(args[0]), String(args[1])) else "there was no such cable"
		"knob":
			return "" if set_knob(p, String(args[0]), String(args[1]), float(args[2])) else "there is no such knob"
		"tidy":
			return "" if RackLayout.flow(p) else "the case is too full to lay out in a line: take something out"
		"preset":
			if not presets().has(StringName(args[0])):
				return "there is no such preset"
			var fresh := preset(StringName(args[0]))
			p["modules"] = fresh["modules"]
			p["cables"] = fresh["cables"]
			return ""
	return "the rack does not know %s" % op
