extends RefCounted

## Composite rack modules (docs/mods.md section 9 step 7, sections 3.5, 4.1 and 10): expansion for the
## engine, the interface, knob routing, nesting, the depth and cycle limits, the cap counted on the
## expansion and the meters. Called from the `_test_*` wrappers in tests/run_tests.gd. The mods are the
## fixtures under tests/fixtures/mods/composite/ (`test.comp`: pluck, pair, stack; `test.bad`: one
## broken composite for each way to be broken, and one fine).

const ROOT := "res://tests/fixtures/mods/composite"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## Runs `body` with a registry of the shipped mods and the fixtures as the game's, then puts the old one back.
func _with_fixtures(body: Callable) -> void:
	var kept := ModRegistry.current
	var reg := ModRegistry.new()
	reg.scan([ModRegistry.SHIPPED_ROOT, ROOT])
	_use(reg)
	body.call(reg)
	_use(kept)
	if kept == null:
		ModRegistry.current = null


func _use(reg: ModRegistry) -> void:
	ModRegistry.current = reg
	RackCatalogue._forget()
	RackSkin._forget()


func _module(type: String, col: int, knobs := {}) -> Dictionary:
	return {"type": type, "at": [col, 0], "knobs": knobs}


## keys -> pl (a pluck) -> out, with the knobs the test gives the pluck.
func _pluck_patch(knobs := {}) -> Dictionary:
	return {"modules": {"keys": _module("builtin.keys", 0), "pl": _module("test.comp.pluck", 1, knobs), "out": _module("builtin.out", 5)},
			"cables": [["keys.pitch", "pl.pitch"], ["keys.gate", "pl.gate"], ["pl.out", "out.l"], ["pl.out", "out.r"]]}


## The fixtures load: the good composites are in the catalogue, the broken ones are not, and the
## problems name each of the broken.
func the_fixture_mods_load() -> void:
	_with_fixtures(func(reg: ModRegistry) -> void:
		check("the good mod is available", reg.is_available("test.comp") and reg.is_available("test.bad"))
		for type in ["test.comp.pluck", "test.comp.pair", "test.comp.stack", "test.bad.fine"]:
			check("%s is a composite in the catalogue" % type, reg.is_composite(type) and RackCatalogue.has(type)
					and RackCatalogue.spec(type)["composite"] and RackCatalogue.engine_type(type) == "")
		check("the engine modules are not composites", not reg.is_composite("builtin.vca") and RackExpansion.cost("builtin.vca") == 1
				and not RackCatalogue.spec("builtin.vca").has("composite"))
		check("the composites come after the engine's own in the palette", RackCatalogue.types().find("test.comp.pluck") > RackCatalogue.types().find("builtin.hand"))
		check("a composite takes its title, group and blurb from its entry", RackCatalogue.spec("test.comp.pluck")["title"] == "PLUCK"
				and RackCatalogue.spec("test.comp.pluck")["group"] == "Voice")
		check("a type nobody provides is no composite and costs one", RackExpansion.cost("nope.nothing") == 1 and not reg.is_composite("nope.nothing"))
	)


## The interface: the plate's jacks and knobs are the composite's own names, and a knob has the range,
## curve and units of the inner knob it points at, with the default the composite gave it.
func the_interface_is_the_composites_own() -> void:
	_with_fixtures(func(_reg: ModRegistry) -> void:
		var s := RackCatalogue.spec("test.comp.pluck")
		check("its inputs are pitch and gate", s["ins"] == ["pitch", "gate"] and RackCatalogue.has_in("test.comp.pluck", "gate")
				and not RackCatalogue.has_in("test.comp.pluck", "trig"))
		check("its output is out", s["outs"] == ["out"] and RackCatalogue.has_out("test.comp.pluck", "out"))
		check("its knobs are timbre and decay, in the order given", RackCatalogue.knob_ids("test.comp.pluck") == ["timbre", "decay"])
		var decay := RackCatalogue.knob("test.comp.pluck", "decay")
		var env_d := RackCatalogue.knob("builtin.env", "d")
		check("decay has ENV's D range, curve and units", decay["lo"] == env_d["lo"] and decay["hi"] == env_d["hi"] and decay["curve"] == "exp"
				and decay["names"] == "s" and decay["label"] == "DECAY")
		check("and the default the composite set (position 0.25), not the engine's", is_equal_approx(float(decay["def"]), RackCatalogue.real(env_d, 0.25))
				and is_equal_approx(RackCatalogue.default_position(decay), 0.25) and not decay.has("set") and not is_equal_approx(float(env_d["def"]), float(decay["def"])))
		check("timbre has Plaits' range and its engine default", RackCatalogue.knob("test.comp.pluck", "timbre")["def"] == RackCatalogue.knob("builtin.plaits", "timbre")["def"])
		check("a knob's position reads out as the inner knob's", RackCatalogue.readout(decay, 0.6) == RackCatalogue.readout(env_d, 0.6))
		var pair := RackCatalogue.knob("test.comp.pair", "decay_b")
		check("a knob through a composite in a composite reaches the engine knob's range, with the label it was given",
				pair["label"] == "DECAY B" and pair["hi"] == env_d["hi"] and pair["curve"] == "exp")
		check("the plate's width comes from its counts: two knobs and three jacks fit one column", RackLayout.width_of("test.comp.pluck") == 1)
		check("a new one gets its stem for an id", RackPatch.new_id({"modules": {}}, "test.comp.pluck") == "pluck")
		check("a patch module of the type is filled with the plate's default knobs", RackPatch.add({"modules": {}, "cables": []}, "test.comp.pluck") == "pluck")
		var p := {"modules": {}, "cables": []}
		RackPatch.add(p, "test.comp.pluck", Vector2i(2, 1))
		check("with the defaults of the plate's knobs", p["modules"]["pluck"]["knobs"].keys() == ["timbre", "decay"]
				and is_equal_approx(float(p["modules"]["pluck"]["knobs"]["decay"]), RackCatalogue.default_position(decay)))
		check("cables on its jacks are checked as for any module", RackPatch.is_in(_pluck_patch(), "pl.gate") and RackPatch.is_out(_pluck_patch(), "pl.out")
				and not RackPatch.is_in(_pluck_patch(), "pl.trig"))
	)


## The engine's lines for a patch with a pluck in it, exactly: inner modules namespaced, their knobs, the
## inner cables, then the patch's cables fanned out to the inner jacks.
func expansion_is_exact() -> void:
	_with_fixtures(func(_reg: ModRegistry) -> void:
		var p := _pluck_patch({"timbre": 0.5, "decay": 0.4})
		var want := PackedStringArray([
			"clear",
			"add keys keys", "add out out", "add pl~amp vca", "add pl~env env", "add pl~osc plaits",
			"knob pl~env.a 0.00000", "knob pl~env.d 0.40000", "knob pl~env.s 0.00000", "knob pl~env.r 0.20000",
			"knob pl~osc.engine 0.35000", "knob pl~osc.harm 0.40000", "knob pl~osc.timbre 0.50000",
			"cable pl~env.out pl~amp.cv", "cable pl~osc.out pl~amp.in",
			"cable keys.pitch pl~osc.pitch", "cable keys.gate pl~env.gate", "cable keys.gate pl~osc.trig",
			"cable pl~amp.out out.l", "cable pl~amp.out out.r"])
		var got := RackPatch.lines(p)
		check("the lines are exactly the expansion (%d lines)" % got.size(), got == want)
		if got != want:
			print("got:  ", "\n      ".join(got))
		var e := RackExpansion.expand(p)
		check("the expanded patch has the inner modules by type and no composite", e["modules"].keys().size() == 5
				and e["modules"]["pl~osc"]["type"] == "builtin.plaits" and not e["modules"].has("pl"))
		check("and the patch itself is not changed", p["modules"]["pl"]["type"] == "test.comp.pluck" and p["cables"].size() == 4)
		check("ids with a ~ are never a patch's own: sanitize refuses one", not RackPatch.sanitize({"modules": {"a~b": _module("builtin.vca", 0)}})["modules"].has("a~b"))
		var again := RackPatch.lines(RackPatch.from_dict(JSON.parse_string(RackPatchFile.text_of(RackPatch.to_dict(p)))))
		check("saved and loaded (the loaded rack has every knob filled), the same lines but for those of the plain modules",
				again == RackPatch.lines(RackPatch.sanitize(p)) and Array(want).all(func(l: String) -> bool: return l in again))
		# The default knobs are what the composite says.
		var d := RackPatch.lines(_pluck_patch())
		check("a pluck with no knob values uses the composite's inner values", "knob pl~env.d 0.25000" in d and not "knob pl~osc.timbre 0.50000" in d
				and "knob pl~osc.harm 0.40000" in d)
		var gone := _pluck_patch()
		gone["cables"].append(["pl.nope", "out.l"])
		gone["cables"].append(["keys.pitch", "pl.nope"])
		check("a cable on a jack the plate does not have adds nothing and breaks nothing", RackPatch.lines(gone) == RackPatch.lines(_pluck_patch()))
	)


## A patch with no composite goes through unchanged, line for line.
func a_patch_without_composites_is_unchanged() -> void:
	_with_fixtures(func(_reg: ModRegistry) -> void:
		for name in RackPatch.presets():
			var p := RackPatch.preset(name)
			var plain := PackedStringArray(["clear"])
			for id in RackPatch.module_ids(p):
				plain.append("add %s %s" % [id, RackCatalogue.engine_type(p["modules"][id]["type"])])
			for id in RackPatch.module_ids(p):
				for k in p["modules"][id]["knobs"]:
					plain.append("knob %s.%s %.5f" % [id, k, float(p["modules"][id]["knobs"][k])])
			for c in p["cables"]:
				plain.append("cable %s %s" % [c[0], c[1]])
			check("preset %s: expansion returns the patch itself and the lines are the old ones" % name,
					is_same(RackExpansion.expand(p), p) and RackPatch.lines(p) == plain and not RackExpansion.has_composite(p))
		check("no meter is mapped for a patch without composites", RackExpansion.meter_map(RackPatch.preset(&"keys_voice")).is_empty())
	)


## Knob values on the plate go to the inner knobs they point at; those it does not point at keep the
## composite's own values; a value is clamped to 0..1.
func knobs_are_routed_to_the_inner_modules() -> void:
	_with_fixtures(func(_reg: ModRegistry) -> void:
		var e := RackExpansion.expand(_pluck_patch({"decay": 0.9, "timbre": 0.1, "nope": 0.7}))
		check("decay reaches ENV's D", is_equal_approx(e["modules"]["pl~env"]["knobs"]["d"], 0.9))
		check("timbre reaches Plaits' timbre", is_equal_approx(e["modules"]["pl~osc"]["knobs"]["timbre"], 0.1))
		check("a knob the plate does not have goes nowhere", not e["modules"]["pl~osc"]["knobs"].has("nope") and not e["modules"]["pl~env"]["knobs"].has("nope"))
		check("the others keep the composite's values", e["modules"]["pl~env"]["knobs"]["r"] == 0.2 and e["modules"]["pl~osc"]["knobs"]["engine"] == 0.35)
		var hot := RackExpansion.expand(_pluck_patch({"decay": 7.0}))
		check("a value past the end is clamped", hot["modules"]["pl~env"]["knobs"]["d"] == 1.0)
		# Two instances do not share knobs.
		var p := _pluck_patch({"decay": 0.9})
		p["modules"]["p2"] = _module("test.comp.pluck", 9, {"decay": 0.1})
		var two := RackExpansion.expand(p)
		check("two instances each have their own", is_equal_approx(two["modules"]["pl~env"]["knobs"]["d"], 0.9) and is_equal_approx(two["modules"]["p2~env"]["knobs"]["d"], 0.1))
		# Turning it live: the voice's difference of the expanded patch.
		var voice := RackVoice.new()
		voice.set_patch(_pluck_patch({"decay": 0.9}))
		check("the voice keeps the plate's patch, not the engine's", voice.patch["modules"].has("pl") and not voice.patch["modules"].has("pl~env"))
		voice.knob("pl", "decay", 0.3)
		check("a knob turned on the plate is set on the plate", is_equal_approx(voice.patch["modules"]["pl"]["knobs"]["decay"], 0.3))
		voice.free()
	)


## A composite in a composite expands all the way down, the knobs go through both, and three deep is allowed.
func nesting_expands_all_the_way_down() -> void:
	_with_fixtures(func(reg: ModRegistry) -> void:
		check("pair (two plucks and a mixer) costs seven, stack (a pair) seven, pluck three",
				RackExpansion.cost("test.comp.pair") == 7 and RackExpansion.cost("test.comp.stack") == 7 and RackExpansion.cost("test.comp.pluck") == 3)
		check("depth: pluck 1, pair 2, stack 3", reg.composite_info("test.comp.pluck")["depth"] == 1 and reg.composite_info("test.comp.pair")["depth"] == 2
				and reg.composite_info("test.comp.stack")["depth"] == RackModuleDef.MAX_DEPTH)
		var p := {"modules": {"keys": _module("builtin.keys", 0), "sk": _module("test.comp.stack", 1, {"decay": 0.7}), "out": _module("builtin.out", 6)},
				"cables": [["keys.pitch", "sk.pitch"], ["keys.gate", "sk.gate"], ["sk.out", "out.l"]]}
		var e := RackExpansion.expand(p)
		var ids: Array = e["modules"].keys()
		ids.sort()
		check("seven inner modules, namespaced three deep, and the two outer ones",
				ids == ["keys", "out", "sk~p~a~amp", "sk~p~a~env", "sk~p~a~osc", "sk~p~b~amp", "sk~p~b~env", "sk~p~b~osc", "sk~p~mix"])
		check("stack's decay goes through pair's decay to pluck A's ENV D, and not to B's", is_equal_approx(e["modules"]["sk~p~a~env"]["knobs"]["d"], 0.7)
				and is_equal_approx(e["modules"]["sk~p~b~env"]["knobs"]["d"], 0.25))
		check("pair's inner values reach the Plaits (timbre 0.2 and 0.8)", is_equal_approx(e["modules"]["sk~p~a~osc"]["knobs"]["timbre"], 0.2)
				and is_equal_approx(e["modules"]["sk~p~b~osc"]["knobs"]["timbre"], 0.8))
		var cables: Array = e["cables"]
		for c in [["sk~p~a~env.out", "sk~p~a~amp.cv"], ["sk~p~a~amp.out", "sk~p~mix.in1"], ["sk~p~b~amp.out", "sk~p~mix.in2"],
				["keys.pitch", "sk~p~a~osc.pitch"], ["keys.pitch", "sk~p~b~osc.pitch"], ["keys.gate", "sk~p~b~env.gate"], ["keys.gate", "sk~p~a~osc.trig"],
				["sk~p~mix.out", "out.l"]]:
			check("cable %s -> %s" % [c[0], c[1]], cables.has(c))
		# 2 plucks x (2 inner + 1 fan) etc.: counted rather than listed.
		check("the cable count is 2 x 2 inner, 2 mixer feeds, 2 x 3 fanned in, 1 out (%d)" % cables.size(), cables.size() == 4 + 2 + 6 + 1)
		check("every cable joins two modules that exist", cables.all(func(c: Array) -> bool:
				return e["modules"].has(String(c[0]).get_slice(".", 0)) and e["modules"].has(String(c[1]).get_slice(".", 0))))
		var lines := RackPatch.lines(p)
		check("every module has an engine name in its add line", lines.size() > 0 and Array(lines).filter(func(l: String) -> bool: return l.begins_with("add ")).all(
				func(l: String) -> bool: return l.split(" ").size() == 3 and l.split(" ")[2] != ""))
	)


## Depth over three, a cycle, an unknown inner type, a bad jack, a bad knob, an OUT inside and too many
## modules each make the composite unavailable with the problem `composite_invalid`, and nothing else.
func bad_composites_are_unavailable_and_never_a_crash() -> void:
	_with_fixtures(func(reg: ModRegistry) -> void:
		var bad := {"test.bad.deep": "deep", "test.bad.unknown": "no module called test.nowhere.thing", "test.bad.loop_a": "inside itself",
				"test.bad.loop_b": "inside itself", "test.bad.self": "inside itself", "test.bad.jack": "amp.nope", "test.bad.knob": "amp.nope",
				"test.bad.out": "cannot be inside", "test.bad.huge": "70 modules"}
		for type in bad:
			var why: String = reg.composite_problem(type)
			check("%s is refused: %s" % [type, why], why != "" and bad[type] in why and not reg.is_composite(type) and not RackCatalogue.has(type)
					and not reg.has_rack_module(type))
		check("the cycle is reported with its path", "test.bad.loop_a" in reg.composite_problem("test.bad.loop_b") or "test.bad.loop_b" in reg.composite_problem("test.bad.loop_a"))
		var problems := reg.problems_with(&"composite_invalid")
		check("one composite_invalid error for each (%d)" % problems.size(), problems.size() == bad.size() and problems.all(func(p: ModProblem) -> bool:
				return p.is_error() and p.mod == "test.bad" and p.entry.begins_with("rack_module:test.bad.")))
		check("the mod itself and its good entry stay", reg.is_available("test.bad") and reg.is_composite("test.bad.fine")
				and reg.mod("test.bad").unavailable_entries["rack_module:test.bad.deep"] == &"composite_invalid")
		check("depth three is fine and four is not", reg.is_composite("test.comp.stack") and not reg.is_composite("test.bad.deep"))
		check("the good mod has no problem", reg.problems().all(func(p: ModProblem) -> bool: return p.mod != "test.comp"))
		# A patch that uses one is an unavailable plate that keeps its place and cables, and the engine never hears it.
		var p := RackPatch.sanitize({"modules": {"keys": _module("builtin.keys", 0), "d": _module("test.bad.deep", 1, {"x": 0.5}), "out": _module("builtin.out", 5)},
				"cables": [["keys.pitch", "d.pitch"], ["d.out", "out.l"]],
				"uses": {"test.bad.deep": {"mod": "test.bad", "version": "0.1.0", "title": "DEEP"}}})
		check("it is kept as a stranger with its cables", RackPatch.is_missing(p, "d") and p["cables"].size() == 2 and p["modules"]["d"]["knobs"]["x"] == 0.5)
		check("the plate says it is unavailable and why", "unavailable" in RackGaps.plate_text(p, "d") and "deep" in RackGaps.plate_text(p, "d"))
		check("the engine hears nothing of it", Array(RackPatch.lines(p)).all(func(l: String) -> bool: return not (" d." in l or " d~" in l or l.begins_with("add d ") or l.ends_with(" d.pitch")))
				and "add keys keys" in RackPatch.lines(p) and RackPatch.lines(p).size() > 3)
		check("it saves and loads back the same", RackPatchFile.text_of(RackPatch.to_dict(RackPatch.from_dict(JSON.parse_string(RackPatchFile.text_of(RackPatch.to_dict(p)))))) == RackPatchFile.text_of(RackPatch.to_dict(p)))
		check("and its title is the entry's even where the catalogue has none", RackPatch.to_dict(p)["uses"]["test.bad.deep"]["title"] == "DEEP"
				and RackPatch.to_dict(RackPatch.sanitize({"modules": {"d": _module("test.bad.deep", 1)}}))["uses"]["test.bad.deep"]["title"] == "DEEP")
		# Junk in the manifest data itself (not a fixture) is a reason, not a crash.
		for junk: Variant in [{"kind": "composite"}, {"kind": "composite", "modules": 3}, {"kind": "composite", "modules": {"a": 1}},
				{"kind": "composite", "modules": {"a": {"type": 4}}}, {"kind": "composite", "modules": {"a b": {"type": "builtin.vca"}}},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca", "knobs": 5}}},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca", "knobs": {"level": "x"}}}},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca"}}, "cables": [[1, 2]], "ins": {}, "outs": {}},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca"}}, "ins": {}, "outs": {}},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca"}}, "ins": {"in": []}, "outs": {"out": "a.out"}},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca"}}, "ins": {"in": ["a.in"]}, "outs": {"out": "a.out"}, "meter_from": "zz"},
				{"kind": "composite", "modules": {"a": {"type": "builtin.vca"}}, "ins": {"in": ["a.in"]}, "outs": {"out": "a.out"}, "knobs": {"x": {}}}]:
			var info: Dictionary = RackModuleDef.resolve({"x.y": {"sound": junk}, "builtin.vca": {"sound": {"kind": "engine", "type": "vca"}}})["x.y"]
			check("junk %s: a reason" % JSON.stringify(junk).left(60), not info["ok"] and info["reason"] != "")
	)


## The rack holds 64 modules, and a composite is as many as it expands to.
func the_cap_is_counted_on_the_expansion() -> void:
	_with_fixtures(func(_reg: ModRegistry) -> void:
		var p := {"modules": {}, "cables": []}
		var n := 0
		while RackPatch.add(p, "test.comp.pluck") != "":
			n += 1
		check("21 plucks of 3 fill 63 of 64 (%d)" % n, n == 21 and RackPatch.cost(p) == 63 and p["modules"].size() == 21)
		check("another pluck is refused, in words", RackPatch.answer(p, "add", ["test.comp.pluck", 0, 0]) != "" and "full" in RackPatch.answer(p, "add", ["test.comp.pluck", -1, 0]))
		check("a plain module still fits in the last place", RackPatch.add(p, "builtin.vca") != "" and RackPatch.cost(p) == 64)
		check("and then the rack is full", RackPatch.add(p, "builtin.vca") == "" and RackPatch.answer(p, "add", ["builtin.vca", -1, 0]) != "")
		var raw := {"modules": {}, "cables": []}
		for i in 30:
			raw["modules"]["p%d" % i] = {"type": "test.comp.pluck", "at": [i, 0], "knobs": {}}
		var kept := RackPatch.sanitize(raw)
		check("a patch of 30 plucks is cut at the cap on load (%d kept)" % kept["modules"].size(), kept["modules"].size() == 21 and RackPatch.cost(kept) <= RackPatch.MAX_MODULES)
		var big := {"modules": {}, "cables": []}
		for i in 9:
			big["modules"]["s%d" % i] = {"type": "test.comp.stack", "at": [i, 0], "knobs": {}}
		var nine := RackPatch.sanitize(big)
		check("nine stacks (7 each = 63) fit, a tenth does not, a plain module does", nine["modules"].size() == 9 and RackPatch.add(nine, "test.comp.stack") == ""
				and RackPatch.add(nine, "builtin.vca") != "")
		# Without the mod, the same file counts each stranger as one.
		var bare := ModRegistry.new()
		bare.scan([ModRegistry.SHIPPED_ROOT])
		_use(bare)
		var lone := RackPatch.sanitize(raw)
		check("where the mod is absent a stranger counts one, so the file is kept whole", lone["modules"].size() == 30)
	)


## A composite plate's lamp follows the inner module `meter_from` names, else the one its first output
## comes from; the voice folds the engine's meters that way.
func meters_follow_the_inner_module() -> void:
	_with_fixtures(func(_reg: ModRegistry) -> void:
		var p := _pluck_patch()
		p["modules"]["pr"] = _module("test.comp.pair", 9)
		p["modules"]["sk"] = _module("test.comp.stack", 15)
		var map := RackExpansion.meter_map(p)
		check("pluck: meter_from amp", map["pl"] == "pl~amp")
		check("pair: meter_from mix", map["pr"] == "pr~mix")
		check("stack has none, so the module its first output comes from, through the pair", map["sk"] == "sk~p~mix")
		check("a plain module has none", not map.has("keys") and map.size() == 3)
		var voice := RackVoice.new()
		voice.set_patch(p)
		var folded := voice._fold_meters({"pl~amp": 0.7, "pr~mix": 0.2, "keys": 0.4})
		check("the plate shows the inner module's meter", is_equal_approx(folded["pl"], 0.7) and is_equal_approx(folded["pr"], 0.2) and folded["sk"] == 0.0)
		check("and the others are the engine's", folded["keys"] == 0.4)
		var plain := RackVoice.new()
		plain.set_patch(RackPatch.preset(&"keys_voice"))
		var raw := {"keys": 0.5}
		check("with no composite the meters pass through untouched", is_same(plain._fold_meters(raw), raw))
		voice.free()
		plain.free()
	)


## The engine plays it, if there is an engine here: a pluck renders finite sound, and the composite
## sounds like the three modules it stands for placed by hand.
func a_composite_plays() -> void:
	if not RackEngine.available():
		check("(no engine binary here: the render check is skipped)", true)
		return
	_with_fixtures(func(_reg: ModRegistry) -> void:
		var play := PackedStringArray(["note_on 60 100", "run 0.3", "note_off 60", "run 0.1"])
		var frames := RackEngine.render(_pluck_patch({"decay": 0.5}), play)
		var peak := 0.0
		var finite := true
		for f in frames:
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
			finite = finite and is_finite(f.x) and is_finite(f.y)
		check("0.4 s of finite sound comes out (%d frames, peak %.3f)" % [frames.size(), peak], frames.size() > 0 and finite and peak > 0.001)
		var by_hand := {"modules": {"keys": _module("builtin.keys", 0), "osc": _module("builtin.plaits", 1, {"engine": 0.35, "harm": 0.4, "timbre": 0.5}),
				"env": _module("builtin.env", 2, {"a": 0.0, "d": 0.5, "s": 0.0, "r": 0.2}), "amp": _module("builtin.vca", 3), "out": _module("builtin.out", 5)},
				"cables": [["keys.pitch", "osc.pitch"], ["keys.gate", "env.gate"], ["keys.gate", "osc.trig"], ["env.out", "amp.cv"], ["osc.out", "amp.in"],
				["amp.out", "out.l"], ["amp.out", "out.r"]]}
		var hand := RackEngine.render(by_hand, play)
		var same := hand.size() == frames.size()
		if same:
			for i in frames.size():
				same = same and frames[i].is_equal_approx(hand[i])
		check("and it is the same sound as the same three modules patched by hand", same)
	)
