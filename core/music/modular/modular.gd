class_name Modular
extends RefCounted

## A modular synth's arithmetic (docs/spatial_loop.md part two, slice 51; idea #25): the modules the
## wall has (ModularWall), the patch that joins them, and the sound a patch makes of a player's keys.
##
## THE PATCH. Room state, the room's row `modular` (ROW): {cables: [[from, to], ...], knobs: {id: v}}.
## A cable runs from an output jack (OUTS, `vco1.out`) into an input jack (INS, `vcf.in`); an output
## may feed any number of inputs, and an input takes one cable. A knob (KNOBS, `vcf.cutoff`) is 0..1,
## what it means its own (`knob_text`). It is asked of the host with `modular_patch` [from, to, song]
## (an empty `to` pulls the cable at `from`: an input's one, or every one out of an output) and
## `modular_knob` [id, v, song], each answered here (`answer_patch`, `answer_knob`), on the host, in
## the studio's prediction and in the probe alike. A fresh room has DEFAULT, which sounds at first
## touch: KEYS' pitch into VCO 1, through the VCF and the VCA to OUT, and KEYS' gate into ENV 1,
## which opens the VCA.
##
## THE SOUND. `render(patch, events, from, frames)`: pure and deterministic, at RATE in blocks of
## BLOCK, for recordings and bandmates; and an instance (`run`) for a player's own keys through Godot
## (ModularVoice). native/modular.c is the same arithmetic in C, in the keys' helper, sample for
## sample (the suite checks the helper's `--render` against this within 1e-4), so a player's own
## modular is on the fast path and what everyone else renders of it is what they heard.
##
## THE WORLD (docs/spatial_loop.md part two, slice 53; idea #31). Beside the modules' outputs the patch
## has the world's (WORLD): `world:weather`, `world:drips`, `world:venue`, `world:ring_1` to `_8` and
## `world:marbles`, sockets out in the room (WorldSocket), not on the wall. A cable from one into an
## input is a cable like any other, in the same row and asked with the same verb. Each world socket
## carries two things, a level (0..1) and a gate: an ENV's gate input (GATE_INS) reads its gate, every
## other input its level. What they carry comes as events, WORLD (a level) and TRIG (a gate opened for
## WORLD_GATE_BLOCKS blocks, shut for one first if it is open, so two drops close together are two
## edges), worked out from the song clock and the rows on every machine (ModularWorld), so the world
## plays every copy of the patch alike.
##
## The rules both keep. Every input reads its source as it was one sample before (a cable is one
## sample long), so the order modules run in changes nothing and a patch may loop back on itself.
## Only the modules whose sound reaches OUT run (`_live`): one that does not is frozen where it was
## until a cable brings it in. Events (a note, a knob, a cable) land at the start of the block they
## fall in. What a knob sets that does not move within a block (a time, a level, a rate) is worked
## out once a block; the filter's coefficients, which its CV input can move every sample, every
## sample. Everything is double precision, with the C library's own sin, tan, exp and pow, so the
## two agree to the last few bits.

const RATE := 48000
const BLOCK := 64
## The room's row, and the two verbs that change it.
const ROW := &"modular"
const PATCH_VERB := &"modular_patch"
const KNOB_VERB := &"modular_knob"
## What the keys say played them while they play the modular (GuestMidi's `source`), and its station.
const SOURCE := &"modular"
const STATION := &"modular"

## The modules, as the wall shows them from its left: id, title, knobs, inputs and outputs (each
## jack's short name; the jack's id is `<module>.<name>`).
const MODULES := [
	{"id": &"keys", "title": "KEYS", "knobs": [], "ins": [], "outs": [&"pitch", &"gate", &"vel"]},
	{"id": &"lfo", "title": "LFO", "knobs": [&"rate", &"shape"], "ins": [], "outs": [&"out"]},
	{"id": &"noise", "title": "NOISE", "knobs": [], "ins": [], "outs": [&"out"]},
	{"id": &"vco1", "title": "VCO 1", "knobs": [&"wave", &"tune", &"fm"], "ins": [&"pitch", &"fm"], "outs": [&"out"]},
	{"id": &"vco2", "title": "VCO 2", "knobs": [&"wave", &"tune", &"fm"], "ins": [&"pitch", &"fm"], "outs": [&"out"]},
	{"id": &"mix", "title": "MIX", "knobs": [&"l1", &"l2", &"l3", &"l4"], "ins": [&"in1", &"in2", &"in3", &"in4"], "outs": [&"out"]},
	{"id": &"vcf", "title": "VCF", "knobs": [&"cutoff", &"res", &"cv"], "ins": [&"in", &"cv"], "outs": [&"out"]},
	{"id": &"env1", "title": "ENV 1", "knobs": [&"a", &"d", &"s", &"r"], "ins": [&"gate"], "outs": [&"out"]},
	{"id": &"env2", "title": "ENV 2", "knobs": [&"a", &"d", &"s", &"r"], "ins": [&"gate"], "outs": [&"out"]},
	{"id": &"vca", "title": "VCA", "knobs": [&"level"], "ins": [&"in", &"cv"], "outs": [&"out"]},
	{"id": &"out", "title": "OUT", "knobs": [&"level"], "ins": [&"in"], "outs": []},
]

## Every output, input and knob by index, in native/modular.c's order (its OUT_NAMES, IN_NAMES and
## KNOB_NAMES), which the `mod` lines name them by.
const OUTS: Array[StringName] = [&"keys.pitch", &"keys.gate", &"keys.vel", &"lfo.out", &"noise.out",
		&"vco1.out", &"vco2.out", &"mix.out", &"vcf.out", &"env1.out", &"env2.out", &"vca.out"]
const INS: Array[StringName] = [&"vco1.pitch", &"vco1.fm", &"vco2.pitch", &"vco2.fm", &"mix.in1", &"mix.in2",
		&"mix.in3", &"mix.in4", &"vcf.in", &"vcf.cv", &"env1.gate", &"env2.gate", &"vca.in", &"vca.cv", &"out.in"]
const KNOBS: Array[StringName] = [&"lfo.rate", &"lfo.shape", &"vco1.wave", &"vco1.tune", &"vco1.fm",
		&"vco2.wave", &"vco2.tune", &"vco2.fm", &"mix.l1", &"mix.l2", &"mix.l3", &"mix.l4", &"vcf.cutoff",
		&"vcf.res", &"vcf.cv", &"env1.a", &"env1.d", &"env1.s", &"env1.r", &"env2.a", &"env2.d", &"env2.s",
		&"env2.r", &"vca.level", &"out.level"]
## Where each knob rests in a fresh room (native/modular.c's KNOB_REST).
const KNOB_REST := {&"lfo.rate": 0.5, &"lfo.shape": 0.0, &"vco1.wave": 0.0, &"vco1.tune": 0.5, &"vco1.fm": 0.0,
		&"vco2.wave": 0.5, &"vco2.tune": 0.5, &"vco2.fm": 0.0, &"mix.l1": 0.5, &"mix.l2": 0.5, &"mix.l3": 0.5,
		&"mix.l4": 0.5, &"vcf.cutoff": 0.55, &"vcf.res": 0.3, &"vcf.cv": 0.7, &"env1.a": 0.1, &"env1.d": 0.4,
		&"env1.s": 0.6, &"env1.r": 0.35, &"env2.a": 0.1, &"env2.d": 0.4, &"env2.s": 0.6, &"env2.r": 0.35,
		&"vca.level": 1.0, &"out.level": 0.7}
## The patch a fresh room has: the keys' pitch through a saw, the filter and the amp to OUT, their
## gate through an envelope opening the amp.
const DEFAULT_CABLES := [[&"keys.pitch", &"vco1.pitch"], [&"vco1.out", &"vcf.in"], [&"vcf.out", &"vca.in"],
		[&"vca.out", &"out.in"], [&"keys.gate", &"env1.gate"], [&"env1.out", &"vca.cv"]]
## What a VCO's WAVE knob picks (its value in thirds), and an LFO's SHAPE (in quarters).
const WAVES := ["SAW", "SQUARE", "SINE"]
const SHAPES := ["SINE", "TRIANGLE", "SQUARE", "SAW"]
## C4, the pitch a KEYS pitch of 0 plays (each 1 an octave up).
const C4_HZ := 261.6255653005986
## How far a full bend moves KEYS' pitch: two semitones, as the keys' tine (DawKitTine.BEND_SEMITONES).
const BEND_SEMITONES := 2.0

## What `render`'s events are: [seconds, kind, a, b]. ON pitch velocity; OFF pitch; BEND value
## (-8192 to 8191); KNOB id value; PATCH from to (an empty `to` pulls the cable at `from`); WORLD socket
## level (a world socket's level, 0..1, slice 53); TRIG socket (its gate opened).
enum Event { ON, OFF, BEND, KNOB, PATCH, WORLD, TRIG }

const _ZERO := 12
const _KEYS_PITCH := 0
const _KEYS_GATE := 1
const _KEYS_VEL := 2
const _LFO := 3
const _NOISE := 4
const _VCO1 := 5
const _VCO2 := 6
const _MIX := 7
const _VCF := 8
const _ENV1 := 9
const _ENV2 := 10
const _VCA := 11
## The world's sockets (slice 53), by index after OUTS in native/modular.c's names (its WORLD_NAMES):
## what feeds them is ModularWorld's.
const WORLD: Array[StringName] = [&"world:weather", &"world:drips", &"world:venue", &"world:ring_1",
		&"world:ring_2", &"world:ring_3", &"world:ring_4", &"world:ring_5", &"world:ring_6", &"world:ring_7",
		&"world:ring_8", &"world:marbles"]
## The inputs that read a world socket's gate rather than its level: the ENVs'.
const GATE_INS: Array[StringName] = [&"env1.gate", &"env2.gate"]
## The inputs a world socket's cable steps through (WorldSocket, P at a desk), the ones it is most
## for first: a filter's CV, an ENV's gate, the amp's CV, a VCO's FM, the MIX, and then the rest.
const WORLD_INPUTS: Array[StringName] = [&"vcf.cv", &"env1.gate", &"env2.gate", &"vca.cv", &"vco1.fm",
		&"vco2.fm", &"mix.in1", &"mix.in2", &"mix.in3", &"mix.in4", &"vco1.pitch", &"vco2.pitch", &"vcf.in",
		&"vca.in", &"out.in"]
## How long a world socket's gate stays open after a TRIG: blocks, so 48 ms.
const WORLD_GATE_BLOCKS := 36
const WORLD_GATE := WORLD_GATE_BLOCKS * 64 / 48000.0

## Each module's index in MODULES, by the OUTS index its output is (KEYS for its three).
const _MODULE_OF_OUT := [0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
const _MODULE_OF_IN := [3, 3, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 9, 10]
const _OUT_MODULE := 10
## A world socket's level's slot in the outputs, and its gate's (`_ZERO` + 1 + its WORLD index, and
## after all of those).
const _WORLD_LEVEL := _ZERO + 1
const _WORLD_GATE := _ZERO + 1 + 12


# --- the patch ---------------------------------------------------------------------------------

## A fresh room's patch: DEFAULT_CABLES and every knob at rest.
static func default_patch() -> Dictionary:
	var cables: Array = []
	for c: Array in DEFAULT_CABLES:
		cables.append([c[0], c[1]])
	return {"cables": cables, "knobs": KNOB_REST.duplicate()}


## The patch `row` (from a room, from anyone) as it may be: only cables from a known output into a
## known input, the first into each input, and every knob known and 0..1 (at rest where it is not
## said). Never null.
static func clean(row: Variant) -> Dictionary:
	var out := {"cables": [], "knobs": KNOB_REST.duplicate()}
	if not (row is Dictionary):
		return out
	var taken := {}
	for c: Variant in (row as Dictionary).get("cables", []):
		if not (c is Array) or (c as Array).size() != 2:
			continue
		var from := StringName(str(c[0]))
		var to := StringName(str(c[1]))
		if is_output(from) and INS.has(to) and not taken.has(to):
			taken[to] = true
			(out["cables"] as Array).append([from, to])
	var knobs: Variant = (row as Dictionary).get("knobs", {})
	if knobs is Dictionary:
		for id: Variant in knobs:
			var k := StringName(str(id))
			var v: Variant = (knobs as Dictionary)[id]
			if KNOBS.has(k) and typeof(v) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(v)):
				out["knobs"][k] = clampf(float(v), 0.0, 1.0)
	return out


## Cable [from, to] put into `row` ({cables, knobs}), or with `to` empty the cable at jack `from`
## pulled out (an input's one, or every one from an output): "" when done, or why not, in words, with
## `row` as it was. Refused: an unknown jack, a cable that does not run from an output into an input,
## an input that has a cable in it already, and pulling a jack nothing is plugged into.
static func answer_patch(row: Dictionary, from: StringName, to: StringName) -> String:
	var cables: Array = row.get("cables", [])
	if not is_output(from) and not INS.has(from):
		return "There is no jack %s on the modular." % from
	if to == &"":
		var kept := cables.filter(func(c: Array) -> bool: return c[0] != from and c[1] != from)
		if kept.size() == cables.size():
			return "Nothing is plugged into %s." % jack_title(from)
		row["cables"] = kept
		return ""
	if not is_output(to) and not INS.has(to):
		return "There is no jack %s on the modular." % to
	# Carried from an input to an output is the same cable the other way round.
	if INS.has(from) and is_output(to):
		var swap := from
		from = to
		to = swap
	if not is_output(from) or not INS.has(to):
		return "A cable goes from an output into an input: %s and %s are both %s." % [jack_title(from),
				jack_title(to), "outputs" if is_output(to) else "inputs"]
	for c: Array in cables:
		if c[1] == to:
			return "%s has a cable in it already: pull that one out first." % jack_title(to)
	cables.append([from, to])
	row["cables"] = cables
	return ""


## Knob `id` set to `v` in `row`: "" when done, or why not.
static func answer_knob(row: Dictionary, id: StringName, v: float) -> String:
	if not KNOBS.has(id):
		return "There is no knob %s on the modular." % id
	if not is_finite(v):
		return "That is not a value for %s." % knob_title(id)
	var knobs: Dictionary = row.get("knobs", {})
	knobs[id] = clampf(v, 0.0, 1.0)
	row["knobs"] = knobs
	return ""


## What feeds input `to` in `patch`, or &"" for nothing.
static func source_of(patch: Dictionary, to: StringName) -> StringName:
	for c: Array in patch.get("cables", []):
		if c[1] == to:
			return c[0]
	return &""


## Every input output `from` feeds in `patch`.
static func sinks_of(patch: Dictionary, from: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for c: Array in patch.get("cables", []):
		if c[0] == from:
			out.append(c[1])
	return out


## Whether `id` is something a cable comes out of: a module's output, or a world socket (WORLD).
static func is_output(id: StringName) -> bool:
	return OUTS.has(id) or WORLD.has(id)


static func is_world(id: StringName) -> bool:
	return WORLD.has(id)


## The world socket ring `n` (from 1) of the looper's stack has: `world:ring_3`.
static func ring_socket(n: int) -> StringName:
	return StringName("world:ring_%d" % n)


## The inputs a world socket's cable may step into now in `patch`: WORLD_INPUTS with no cable in them,
## and the one `socket`'s own cable is in.
static func free_inputs(patch: Dictionary, socket: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in WORLD_INPUTS:
		var from := source_of(patch, id)
		if from == &"" or from == socket:
			out.append(id)
	return out


## Where `socket`'s cable goes after one step `way` (1 on, -1 back) in `patch`: from unplugged into
## the first free input, then each next, and past the last unplugged again. &"" for unplugged.
static func step_input(patch: Dictionary, socket: StringName, way: int) -> StringName:
	var free := free_inputs(patch, socket)
	var now := sinks_of(patch, socket)
	var ring: Array[StringName] = [&""]
	ring.append_array(free)
	var at := ring.find(now[0]) if not now.is_empty() else 0
	return ring[posmod(maxi(at, 0) + (1 if way >= 0 else -1), ring.size())]


## The module a jack or a knob is on (`vcf` of `vcf.cv`), and its row in MODULES.
static func module_of(id: StringName) -> StringName:
	return StringName(String(id).get_slice(".", 0))


static func module_row(module: StringName) -> Dictionary:
	for m: Dictionary in MODULES:
		if m["id"] == module:
			return m
	return {}


## A jack as the wall letters it on a card: `VCF CV IN`, `KEYS GATE OUT`; a world socket by what it
## is in the room: `THE WEATHER`, `LOOPER RING 3`.
static func jack_title(id: StringName) -> String:
	if is_world(id):
		return world_title(id)
	var m := module_row(module_of(id))
	var name := String(id).get_slice(".", 1).to_upper()
	var way := "OUT" if OUTS.has(id) else "IN"
	if name == way:
		return "%s %s" % [m.get("title", String(module_of(id)).to_upper()), way]
	return "%s %s %s" % [m.get("title", String(module_of(id)).to_upper()), name, way]


## A world socket's name: `THE WEATHER`, `THE DRIPS`, `THE VENUE'S INSTRUMENT`, `LOOPER RING 3`,
## `THE MARBLE RUN`.
static func world_title(id: StringName) -> String:
	var name := String(id).trim_prefix("world:")
	if name.begins_with("ring_"):
		return "LOOPER RING %s" % name.trim_prefix("ring_")
	return {"weather": "THE WEATHER", "drips": "THE DRIPS", "venue": "THE VENUE'S INSTRUMENT",
			"marbles": "THE MARBLE RUN"}.get(name, name.to_upper())


## A knob as the wall letters it on a card: `VCF CUTOFF`.
static func knob_title(id: StringName) -> String:
	var m := module_row(module_of(id))
	var name := String(id).get_slice(".", 1)
	var words := {&"a": "ATTACK", &"d": "DECAY", &"s": "SUSTAIN", &"r": "RELEASE", &"res": "RESONANCE",
			&"l1": "LEVEL 1", &"l2": "LEVEL 2", &"l3": "LEVEL 3", &"l4": "LEVEL 4", &"fm": "FM DEPTH",
			&"cv": "CV DEPTH"}
	return "%s %s" % [m.get("title", ""), words.get(StringName(name), name.to_upper())]


## A knob's short letter on the panel, under it.
static func knob_letter(id: StringName) -> String:
	var name := String(id).get_slice(".", 1)
	return {"l1": "1", "l2": "2", "l3": "3", "l4": "4", "res": "RES", "cutoff": "CUTOFF"}.get(name, name.to_upper())


## What knob `id` at `v` means, in its own units: `889 Hz`, `+3.4 st`, `SAW`, `120 ms`.
static func knob_text(id: StringName, v: float) -> String:
	var name := String(id).get_slice(".", 1)
	match name:
		"rate":
			return "%.2f Hz" % lfo_hz(v)
		"shape":
			return SHAPES[mini(int(v * 4.0), 3)]
		"wave":
			return WAVES[mini(int(v * 3.0), 2)]
		"tune":
			return "%+.1f st" % ((v - 0.5) * 24.0)
		"cutoff":
			var hz := cutoff_hz(v)
			return "%.0f Hz" % hz if hz < 1000.0 else "%.1f kHz" % (hz / 1000.0)
		"cv":
			return "%+.1f oct" % ((v - 0.5) * 2.0 * 5.0)
		"a", "d", "r":
			var s := env_seconds(v)
			return "%.0f ms" % (s * 1000.0) if s < 1.0 else "%.2f s" % s
	return "%d%%" % roundi(v * 100.0)


static func lfo_hz(v: float) -> float:
	return 0.05 * pow(400.0, v)


static func cutoff_hz(v: float) -> float:
	return 20.0 * pow(1000.0, v)


static func env_seconds(v: float) -> float:
	return 0.001 * pow(5000.0, v)


## Which modules' sound reaches OUT through `src` (each input's source output, _ZERO for none), as
## a mask by MODULES index. KEYS counts as running whenever anything does: it has no sound of its own.
static func _live(src: PackedInt32Array) -> PackedByteArray:
	var live := PackedByteArray()
	live.resize(MODULES.size())
	live[_OUT_MODULE] = 1
	var grew := true
	while grew:
		grew = false
		for i in INS.size():
			if src[i] >= _ZERO or live[_MODULE_OF_IN[i]] == 0:
				continue
			var m: int = _MODULE_OF_OUT[src[i]]
			if live[m] == 0:
				live[m] = 1
				grew = true
	return live


# --- the sound ---------------------------------------------------------------------------------

## Each input's source output (by OUTS index), _ZERO for none.
var _src := PackedInt32Array()
var _live_mask := PackedByteArray()
## Each output as it was a sample ago, and a last slot (_ZERO) that is always 0.
var _o := PackedFloat64Array()
var _k := PackedFloat64Array()
## The keys: what is held, newest last, the newest's velocity, and the wheel (in octaves).
var _held := PackedInt32Array()
var _last_pitch := 60
var _velocity := 0.0
var _bend := 0.0
var _lfo_phase := 0.0
var _noise := 22222
var _vco_phase := PackedFloat64Array([0.0, 0.0])
var _env_stage := PackedInt32Array([0, 0])
var _env_level := PackedFloat64Array([0.0, 0.0])
var _env_gate := PackedInt32Array([0, 0])
var _ic1 := 0.0
var _ic2 := 0.0
## Each world socket's gate: the blocks it has still to stay open, and whether it is shut for this
## block first (a TRIG while it was open).
var _gate_left := PackedInt32Array()
var _gate_rest := PackedByteArray()


func _init() -> void:
	_src.resize(INS.size())
	_src.fill(_ZERO)
	_o.resize(_WORLD_GATE + WORLD.size())
	_gate_left.resize(WORLD.size())
	_gate_rest.resize(WORLD.size())
	_k.resize(KNOBS.size())
	for i in KNOBS.size():
		_k[i] = KNOB_REST[KNOBS[i]]
	_live_mask = _live(_src)


## Every cable and knob as `patch` has them.
func set_patch(patch: Dictionary) -> void:
	_src.fill(_ZERO)
	for c: Array in patch.get("cables", []):
		var to := INS.find(StringName(c[1]))
		var from := _slot(StringName(c[0]), to)
		if from >= 0 and to >= 0:
			_src[to] = from
	var knobs: Dictionary = patch.get("knobs", {})
	for i in KNOBS.size():
		_k[i] = clampf(float(knobs.get(KNOBS[i], KNOB_REST[KNOBS[i]])), 0.0, 1.0)
	_live_mask = _live(_src)


## The slot input `to` (by INS index) reads output `from` at: a module's by its OUTS index, a world
## socket's level, or its gate where `to` is an ENV's gate (GATE_INS). -1 for no output.
static func _slot(from: StringName, to: int) -> int:
	var at := OUTS.find(from)
	if at >= 0:
		return at
	var w := WORLD.find(from)
	if w < 0:
		return -1
	if to >= 0 and GATE_INS.has(INS[to]):
		return _WORLD_GATE + w
	return _WORLD_LEVEL + w


## Whether input slot `slot` reads output `from`.
static func _reads(slot: int, from: StringName) -> bool:
	var at := OUTS.find(from)
	if at >= 0:
		return slot == at
	var w := WORLD.find(from)
	return w >= 0 and (slot == _WORLD_LEVEL + w or slot == _WORLD_GATE + w)


## One cable in, or with `to` empty every cable at `from` out: as native/modular.c's `mod cable` and
## `mod cut`, with no questions asked (the room asked them).
func patch_cable(from: StringName, to: StringName) -> void:
	if to == &"":
		var at_in := INS.find(from)
		var out := is_output(from)
		for i in INS.size():
			if i == at_in or (out and _reads(_src[i], from)):
				_src[i] = _ZERO
	else:
		var b := INS.find(to)
		var a := _slot(from, b)
		if a < 0 or b < 0:
			b = INS.find(from)
			a = _slot(to, b)
		if a >= 0 and b >= 0:
			_src[b] = a
	_live_mask = _live(_src)


## World socket `socket`'s level now (slice 53): what every input but an ENV's gate reads of it.
func world(socket: StringName, level: float) -> void:
	var w := WORLD.find(socket)
	if w >= 0 and is_finite(level):
		_o[_WORLD_LEVEL + w] = clampf(level, -1.0, 1.0)


## World socket `socket`'s gate opened now for WORLD_GATE_BLOCKS blocks, shut for a block first if it
## was open, so an ENV sees an edge each time.
func trig(socket: StringName) -> void:
	var w := WORLD.find(socket)
	if w < 0:
		return
	if _gate_left[w] > 0:
		_gate_rest[w] = 1
	_gate_left[w] = WORLD_GATE_BLOCKS


## What world socket `socket` is at now: [level, gate open].
func world_now(socket: StringName) -> Array:
	var w := WORLD.find(socket)
	if w < 0:
		return [0.0, false]
	return [_o[_WORLD_LEVEL + w], _gate_left[w] > 0]


func knob(id: StringName, v: float) -> void:
	var i := KNOBS.find(id)
	if i >= 0:
		_k[i] = clampf(v, 0.0, 1.0)


func note_on(pitch: int, velocity: int) -> void:
	note_off(pitch)
	_held.append(pitch)
	_last_pitch = pitch
	_velocity = clampf(velocity / 127.0, 0.0, 1.0)


func note_off(pitch: int) -> void:
	var at := _held.find(pitch)
	if at >= 0:
		_held.remove_at(at)
	if not _held.is_empty():
		_last_pitch = _held[_held.size() - 1]


## The pitch wheel, -8192 to 8191: KEYS' pitch bent up to BEND_SEMITONES.
func bend(value: int) -> void:
	_bend = clampf(float(value), -8192.0, 8191.0) / 8192.0 * BEND_SEMITONES / 12.0


func all_off() -> void:
	_held.clear()


func sounding() -> bool:
	return not _held.is_empty() or _env_level[0] > 0.0001 or _env_level[1] > 0.0001


## Whether anything is held on its keys.
func gate() -> bool:
	return not _held.is_empty()


## Its keys' newest note (held, or the last one let go).
func pitch() -> int:
	return _last_pitch


## `frames` (whole blocks: rounded up to BLOCK) of the patch played from where it is now.
func run(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var blocks := ceili(float(frames) / BLOCK)
	out.resize(blocks * BLOCK)
	for b in blocks:
		_block(out, b * BLOCK)
	return out


## The sound of `events` played through `patch` from song time `from` (seconds) for `frames` frames,
## mono, at RATE, from a modular fresh at `from`: each event at the start of the BLOCK it falls in,
## those before `from` at the first. Pure: the same patch and events are the same samples.
static func render(patch: Dictionary, events: Array, from: float, frames: int) -> PackedFloat32Array:
	var m := Modular.new()
	m.set_patch(patch)
	var order: Array = []
	for i in events.size():
		order.append([float(events[i][0]), i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var blocks := ceili(float(frames) / BLOCK)
	var out := PackedFloat32Array()
	out.resize(blocks * BLOCK)
	var next := 0
	for b in blocks:
		while next < order.size() and floori((order[next][0] - from) * RATE / BLOCK + 1e-6) <= b:
			m.apply(events[order[next][1]])
			next += 1
		m._block(out, b * BLOCK)
	out.resize(frames)
	return out


## One of `render`'s events, now.
func apply(e: Array) -> void:
	match int(e[1]):
		Event.ON:
			note_on(int(e[2]), int(e[3]))
		Event.OFF:
			note_off(int(e[2]))
		Event.BEND:
			bend(int(e[2]))
		Event.KNOB:
			knob(StringName(e[2]), float(e[3]))
		Event.PATCH:
			patch_cable(StringName(e[2]), StringName(e[3]))
		Event.WORLD:
			world(StringName(e[2]), float(e[3]))
		Event.TRIG:
			trig(StringName(e[2]))


## One block into `out` from `at`. Locals throughout, and every array copied in and written back once,
## since a packed array written through a second name would be copied on every write.
func _block(out: PackedFloat32Array, at: int) -> void:
	var o := _o
	_o = PackedFloat64Array()
	var k := _k
	var src := _src
	var live := _live_mask
	var gate := 0.0 if _held.is_empty() else 1.0
	o[_KEYS_PITCH] = (_last_pitch - 60) / 12.0 + _bend
	o[_KEYS_GATE] = gate
	o[_KEYS_VEL] = _velocity
	# The world's gates for this block (slice 53): open while they have blocks left, shut for one
	# where a TRIG came while open.
	for w in WORLD.size():
		if _gate_rest[w] == 1:
			_gate_rest[w] = 0
			o[_WORLD_GATE + w] = 0.0
		elif _gate_left[w] > 0:
			_gate_left[w] -= 1
			o[_WORLD_GATE + w] = 1.0
		else:
			o[_WORLD_GATE + w] = 0.0
	# What the knobs set for the whole block.
	var lfo_inc := lfo_hz(k[0]) / RATE
	var lfo_shape := mini(int(k[1] * 4.0), 3)
	var w1 := mini(int(k[2] * 3.0), 2)
	var t1 := (k[3] - 0.5) * 2.0
	var f1 := k[4] * 2.0
	var w2 := mini(int(k[5] * 3.0), 2)
	var t2 := (k[6] - 0.5) * 2.0
	var f2 := k[7] * 2.0
	var cutoff := cutoff_hz(k[12])
	var damp := 2.0 - 1.96 * k[13]
	var cv_oct := (k[14] - 0.5) * 2.0 * 5.0
	var ca1 := 1.0 - exp(-1.0 / (env_seconds(k[15]) * RATE))
	var cd1 := 1.0 - exp(-1.0 / (env_seconds(k[16]) * RATE))
	var s1 := k[17]
	var cr1 := 1.0 - exp(-1.0 / (env_seconds(k[18]) * RATE))
	var ca2 := 1.0 - exp(-1.0 / (env_seconds(k[19]) * RATE))
	var cd2 := 1.0 - exp(-1.0 / (env_seconds(k[20]) * RATE))
	var s2 := k[21]
	var cr2 := 1.0 - exp(-1.0 / (env_seconds(k[22]) * RATE))
	var vca_level := k[23]
	var out_level := k[24]
	var run_lfo := live[1] == 1
	var run_noise := live[2] == 1
	var run_vco1 := live[3] == 1
	var run_vco2 := live[4] == 1
	var run_mix := live[5] == 1
	var run_vcf := live[6] == 1
	var run_env1 := live[7] == 1
	var run_env2 := live[8] == 1
	var run_vca := live[9] == 1
	var s_v1p := src[0]
	var s_v1f := src[1]
	var s_v2p := src[2]
	var s_v2f := src[3]
	var s_m1 := src[4]
	var s_m2 := src[5]
	var s_m3 := src[6]
	var s_m4 := src[7]
	var s_fin := src[8]
	var s_fcv := src[9]
	var s_e1 := src[10]
	var s_e2 := src[11]
	var s_ain := src[12]
	var s_acv := src[13]
	var s_out := src[14]
	# The filter's coefficients, once a block where nothing moves them within it.
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	if s_fcv == _ZERO:
		var g := tan(PI * clampf(cutoff, 10.0, 0.45 * RATE) / RATE)
		a1 = 1.0 / (1.0 + g * (g + damp))
		a2 = g * a1
		a3 = g * a2
	var lfo_phase := _lfo_phase
	var noise := _noise
	var p1 := _vco_phase[0]
	var p2 := _vco_phase[1]
	var es1 := _env_stage[0]
	var es2 := _env_stage[1]
	var el1 := _env_level[0]
	var el2 := _env_level[1]
	var eg1 := _env_gate[0]
	var eg2 := _env_gate[1]
	var ic1 := _ic1
	var ic2 := _ic2
	for i in BLOCK:
		var n_lfo: float = o[_LFO]
		var n_noise: float = o[_NOISE]
		var n_v1: float = o[_VCO1]
		var n_v2: float = o[_VCO2]
		var n_mix: float = o[_MIX]
		var n_vcf: float = o[_VCF]
		var n_e1: float = o[_ENV1]
		var n_e2: float = o[_ENV2]
		var n_vca: float = o[_VCA]
		if run_lfo:
			match lfo_shape:
				0: n_lfo = sin(TAU * lfo_phase)
				1: n_lfo = 4.0 * absf(lfo_phase - 0.5) - 1.0
				2: n_lfo = 1.0 if lfo_phase < 0.5 else -1.0
				_: n_lfo = 2.0 * lfo_phase - 1.0
			lfo_phase += lfo_inc
			lfo_phase -= floorf(lfo_phase)
		if run_noise:
			noise = (noise * 1664525 + 1013904223) & 0xFFFFFFFF
			n_noise = noise / 2147483648.0 - 1.0
		if run_vco1:
			n_v1 = _wave(w1, p1)
			var hz := minf(C4_HZ * pow(2.0, o[s_v1p] + t1 + o[s_v1f] * f1), 20000.0)
			p1 += hz / RATE
			p1 -= floorf(p1)
		if run_vco2:
			n_v2 = _wave(w2, p2)
			var hz2 := minf(C4_HZ * pow(2.0, o[s_v2p] + t2 + o[s_v2f] * f2), 20000.0)
			p2 += hz2 / RATE
			p2 -= floorf(p2)
		if run_mix:
			n_mix = o[s_m1] * k[8] + o[s_m2] * k[9] + o[s_m3] * k[10] + o[s_m4] * k[11]
		if run_vcf:
			if s_fcv != _ZERO:
				var fc := clampf(cutoff * pow(2.0, o[s_fcv] * cv_oct), 10.0, 0.45 * RATE)
				var g := tan(PI * fc / RATE)
				a1 = 1.0 / (1.0 + g * (g + damp))
				a2 = g * a1
				a3 = g * a2
			var v3: float = o[s_fin] - ic2
			var v1 := a1 * ic1 + a2 * v3
			var v2 := ic2 + a2 * ic1 + a3 * v3
			ic1 = 2.0 * v1 - ic1
			ic2 = 2.0 * v2 - ic2
			n_vcf = v2
		if run_env1:
			var g1 := 1 if o[s_e1] > 0.5 else 0
			if g1 == 1 and eg1 == 0:
				es1 = 1
			elif g1 == 0 and eg1 == 1:
				es1 = 3
			eg1 = g1
			if es1 == 1:
				el1 += (1.3 - el1) * ca1
				if el1 >= 1.0:
					el1 = 1.0
					es1 = 2
			elif es1 == 2:
				el1 += (s1 - el1) * cd1
			elif es1 == 3:
				el1 -= el1 * cr1
			n_e1 = el1
		if run_env2:
			var g2 := 1 if o[s_e2] > 0.5 else 0
			if g2 == 1 and eg2 == 0:
				es2 = 1
			elif g2 == 0 and eg2 == 1:
				es2 = 3
			eg2 = g2
			if es2 == 1:
				el2 += (1.3 - el2) * ca2
				if el2 >= 1.0:
					el2 = 1.0
					es2 = 2
			elif es2 == 2:
				el2 += (s2 - el2) * cd2
			elif es2 == 3:
				el2 -= el2 * cr2
			n_e2 = el2
		if run_vca:
			var gain := vca_level
			if s_acv != _ZERO:
				gain = vca_level * maxf(o[s_acv], 0.0)
			n_vca = o[s_ain] * gain
		var x: float = o[s_out] * out_level
		out[at + i] = x / (1.0 + absf(x))
		o[_LFO] = n_lfo
		o[_NOISE] = n_noise
		o[_VCO1] = n_v1
		o[_VCO2] = n_v2
		o[_MIX] = n_mix
		o[_VCF] = n_vcf
		o[_ENV1] = n_e1
		o[_ENV2] = n_e2
		o[_VCA] = n_vca
	_o = o
	_lfo_phase = lfo_phase
	_noise = noise
	_vco_phase[0] = p1
	_vco_phase[1] = p2
	_env_stage[0] = es1
	_env_stage[1] = es2
	_env_level[0] = el1
	_env_level[1] = el2
	_env_gate[0] = eg1
	_env_gate[1] = eg2
	_ic1 = ic1
	_ic2 = ic2


static func _wave(kind: int, phase: float) -> float:
	match kind:
		0: return 2.0 * phase - 1.0
		1: return 1.0 if phase < 0.5 else -1.0
	return sin(TAU * phase)
