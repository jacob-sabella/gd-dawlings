extends RefCounted

## Control tools: rack (docs/mcp_assistant.md). The modules, cables and knobs of the modular room's patch, the
## module catalogue and finder, help cards, presets and saved patches, and a quick offline render.
##
## Every write is a RackPatch.answer op: it is tried first on a copy of the patch (so the game's own refusal
## text comes back as the error, and a guest's asynchronous ask is not left unanswered), then sent through the
## studio's `rack_host.ask_rack(op, args)`, the path the wall's own hands use. Replacing a whole patch has no op
## of its own in RackPatch.answer, so `_plan` turns "make the patch this" into the ops that get there (remove
## what differs, add, knobs, cables); the same plan puts a snapshot back for `changes_undo`.
##
## No studio (a suite): the patch is `ToolsRack.test_patch`, a plain RackPatch dictionary kept here; reads and writes
## act on it directly. Set it before a call (`ToolsRack.test_patch = RackPatch.empty()`).


static var test_patch: Dictionary = {}

const NAME_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-"
const SAVED_SUFFIX := ".patch.json"
const RENDER_MAX_SECONDS := 30.0
const RENDER_DIR := "rack_renders"


static func register(api: ControlApi) -> void:
	var mod := ControlTool.str_p("module id as rack_list shows it (e.g. 'vco', 'vco2')")
	var jack_from := ControlTool.str_p("an output jack as module.jack, e.g. 'vco.out' (rack_module_help lists a type's jacks)")
	var jack_to := ControlTool.str_p("an input jack as module.jack, e.g. 'filter.in'")

	api.add(ControlTool.make("rack_list",
			"The modules in the modular rack's patch: id, type, title, column/row (the case is 40 columns x 4 rows), width, every knob by label (id, position 0..1 and display text with its unit), and jacks. Also returns the cable count, the case's cost against its limit and the sounding track. Bounded: use limit/offset for a big patch.",
			{"limit": ControlTool.int_p("at most this many modules (default 60)", 1, 200), "offset": ControlTool.int_p("skip this many", 0)},
			[], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _list(api, a)))
	api.add(ControlTool.make("rack_get",
			"One module in full: type, title, group, place, knobs (id, label, position 0..1, display, range), jacks (ins/outs), the cables on it, and its help card summary (blurb, what, how, try).",
			{"module": mod}, ["module"], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _module_get(api, a)))
	api.add(ControlTool.make("rack_add",
			"Put a module in the rack. type is a module type from rack_modules_find or rack_module_types (e.g. 'builtin.vco'). Without col/row it goes in the first free place. Returns the new id, which is what every other rack tool takes. Refused in the game's own words when the case is full, the spot is taken, or it would be a second OUT.",
			{"type": ControlTool.str_p("the module type, e.g. 'builtin.plaits'"), "col": ControlTool.int_p("column 0..39 (give with row)", 0, 39), "row": ControlTool.int_p("row 0..3 (give with col)", 0, 3)},
			["type"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary: return _add(api, a)))
	api.add(ControlTool.make("rack_remove",
			"Take one module out of the rack with every cable on it. The OUT cannot be removed (nothing would leave the room). Undoable.",
			{"module": mod}, ["module"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary: return _remove(api, a)))
	api.add(ControlTool.make("rack_move",
			"Move a module to a column and row of the case (40 x 4). Refused when it does not fit there.",
			{"module": mod, "col": ControlTool.int_p("column 0..39", 0, 39), "row": ControlTool.int_p("row 0..3", 0, 3)},
			["module", "col", "row"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary: return _move(api, a)))
	api.add(ControlTool.make("rack_set_knob",
			"Set a knob of a module. knob is its label or id/letter as rack_list shows (case does not matter). Give value as the knob position 0..1, or real as the value the knob means in its own unit (Hz, seconds, dB, a choice number of a stepped knob); real is converted by the knob's own curve. Returns the new position and display text.",
			{"module": mod, "knob": ControlTool.str_p("knob label or id"), "value": ControlTool.num_p("knob position 0..1", 0, 1), "real": ControlTool.num_p("the value in the knob's unit (see its range in rack_get)")},
			["module", "knob"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary: return _set_knob(api, a)))
	api.add(ControlTool.make("rack_cables_list",
			"Every cable in the patch as {from, to} jack paths (module.jack), with jack names from the catalogue.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary: return _cables(api)))
	api.add(ControlTool.make("rack_cable_add",
			"Patch a cable from an output to an input, e.g. from 'vco.out' to 'filter.in'. Refused with the engine's own reason: unknown module or jack (the error lists the real ones), not an output/input, a module patched into itself, the cable already there, or the case's cable limit. An input may be fed by several cables: the result notes when it already was.",
			{"from": jack_from, "to": jack_to}, ["from", "to"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary: return _cable_add(api, a)))
	api.add(ControlTool.make("rack_cable_remove",
			"Pull a cable: the one from 'from' to 'to', or, without from, every cable into the input 'to'.",
			{"from": jack_from, "to": jack_to}, ["to"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary: return _cable_remove(api, a)))
	api.add(ControlTool.make("rack_tidy",
			"Lay the modules out in signal-flow order in the case. Refused when the case is too full to lay out in a line.",
			{}, [], ControlTool.EDIT, func(_a: Dictionary) -> Dictionary: return _one(api, "tidy", [], {})))
	api.add(ControlTool.make("rack_clear",
			"Empty the rack: every module and cable goes, except the OUT (which cannot be removed). Destructive. A change set can take it back.",
			{}, [], ControlTool.DESTRUCTIVE, func(_a: Dictionary) -> Dictionary: return _clear(api)))
	api.add(ControlTool.make("rack_track_set",
			"Choose the song track the rack sounds through: a track name or number, or 'none'. Needs the running game (a project open).",
			{"track": ControlTool.ref_p("track name, '#3' or number; 'none' for no track")}, ["track"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary: return _track(api, a)))

	api.add(ControlTool.make("rack_power",
			"Turn the whole rack on or off, like the big ON/OFF key on its wall. Off: it makes no sound and uses no processor; the patch is kept. Omit `on` to read the state. Needs the running game.",
			{"on": ControlTool.bool_p("true to switch the rack on, false to switch it off")}, [], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary: return _power(api, a)))

	api.add(ControlTool.make("rack_patch_get",
			"The whole patch as JSON ({format, version, modules: {id: {type, at: [col,row], w, knobs: {knobId: 0..1}}}, cables: [[from, to]], track}), the same file shape rack_patch_set takes.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary: return _patch_get(api)))
	api.add(ControlTool.make("rack_patch_set",
			"Replace the whole patch from JSON in the shape rack_patch_get returns: {modules: {id: {type, at: [col,row], knobs: {knobId: 0..1}}}, cables: [[\"vco.out\", \"filter.in\"], ...]}. Knobs not named keep their defaults. Module ids in your JSON are names you choose; the game may give a module a different id (the result maps yours to theirs). Validated first: an unknown type, a bad jack or too many modules/cables refuses the whole call and changes nothing. Destructive: it replaces what is there. Use it to build a patch in one call; use batch of rack_add/rack_cable_add to edit.",
			{"patch": ControlTool.obj_p("{modules, cables} as rack_patch_get gives")}, ["patch"], ControlTool.DESTRUCTIVE,
			func(a: Dictionary) -> Dictionary: return _patch_set(api, a)))
	api.add(ControlTool.make("rack_presets_list",
			"The rack's presets (mod-provided starting patches: name, title) and the patches saved by name under user://patches.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary: return _presets_list()))
	api.add(ControlTool.make("rack_preset_load",
			"Replace the patch with a preset, by name from rack_presets_list. Destructive.",
			{"name": ControlTool.str_p("preset name")}, ["name"], ControlTool.DESTRUCTIVE, func(a: Dictionary) -> Dictionary: return _preset_load(api, a)))
	api.add(ControlTool.make("rack_patch_save",
			"Save the current patch under user://patches by a name of letters, digits, space, '_' and '-'. Refuses to overwrite unless overwrite is true.",
			{"name": ControlTool.str_p("file name, letters digits space _ -"), "overwrite": ControlTool.bool_p("replace a saved patch of that name")}, ["name"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary: return _patch_save(api, a)))
	api.add(ControlTool.make("rack_patch_load",
			"Replace the patch with one saved by rack_patch_save (by name). Destructive.",
			{"name": ControlTool.str_p("the saved name")}, ["name"], ControlTool.DESTRUCTIVE, func(a: Dictionary) -> Dictionary: return _patch_load(api, a)))

	api.add(ControlTool.make("rack_modules_find",
			"Search the module catalogue (about 570 types, 532 of them Airwindows effects: this is how to find one). query is words that must all match the name, kind, a knob name or the blurb ('reverb', 'tape saturation'); group and kind narrow it (rack_module_types lists the groups). Ranked best first. Returns type, title, group, kinds, blurb; limit bounds it.",
			{"query": ControlTool.str_p("words, all must match; empty for all"), "group": ControlTool.str_p("palette group, e.g. 'Effects'"), "kind": ControlTool.str_p("an effect kind, e.g. 'reverb'"),
			"limit": ControlTool.int_p("at most this many (default 20)", 1, 100), "offset": ControlTool.int_p("skip this many", 0)},
			[], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _find(a)))
	api.add(ControlTool.make("rack_module_types",
			"The module catalogue by palette group, compact. Without group: each group's name, count and its first few types. With group: every type in it as {type, title}. The big Airwindows group is searched with rack_modules_find, not listed.",
			{"group": ControlTool.str_p("one group to list in full")}, [], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _types(a)))
	api.add(ControlTool.make("rack_module_help",
			"The in-game help card of a module type: title, group, blurb, what it does, how to use it, something to try, each jack and knob explained with its range, and (for an Airwindows effect) its parameters.",
			{"type": ControlTool.str_p("module type, e.g. 'builtin.vco'")}, ["type"], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _help(a)))
	api.add(ControlTool.make("rack_render",
			"Render the current patch offline for a few seconds and return its stats (peak, peak_db, rms, duration), not the audio; the wav is kept under user:// and its path returned. Optional notes play the patch's keyboard input: [{pitch: 0..127, velocity: 1..127, start: s, length: s}]. Needs the built rack engine; says so if it is missing.",
			{"seconds": ControlTool.num_p("length to render, 0.1..30 (default 2)", 0.1, RENDER_MAX_SECONDS),
			"notes": ControlTool.arr_p("notes to play: {pitch, velocity, start, length} (seconds)", {"type": "object"}), "bpm": ControlTool.num_p("tempo for the clocks (default 120)", 20, 300)},
			[], ControlTool.READ, func(a: Dictionary) -> Dictionary: return _render(api, a)))

	api.snapshotters.append({"name": "rack",
			"snap": func() -> Variant: return _patch(api).duplicate(true),
			"restore": func(p: Variant) -> void:
				if typeof(p) == TYPE_DICTIONARY:
					var done := _replace(api, p, false)
					if done != "":
						push_warning("control: could not put the rack back: " + done)})


# --- the patch --------------------------------------------------------------------------------

## The patch the tools act on: the studio's rack row, or `test_patch` with no studio.
static func _patch(api: ControlApi) -> Dictionary:
	if api.studio != null and "rack_row" in api.studio:
		var row: Variant = api.studio.get("rack_row")
		if row is Dictionary and (row as Dictionary).get("patch") is Dictionary:
			return row["patch"]
	if not test_patch.has("modules") or not test_patch.has("cables"):
		test_patch = RackPatch.empty()
	return test_patch


static func _live(api: ControlApi) -> bool:
	return api.studio != null and "rack_host" in api.studio and api.studio.get("rack_host") != null


static func _track_of(api: ControlApi) -> int:
	if api.studio != null and "rack_row" in api.studio:
		return int((api.studio.get("rack_row") as Dictionary).get("track", 0))
	return 0


## Try `ops` ([[op, args], ...]) on a copy of the patch; the first refusal in words ("" when all go), and
## then do them through the game's path (or on `test_patch` with no studio).
static func _run(api: ControlApi, ops: Array) -> String:
	var sim := _patch(api).duplicate(true)
	var n := 0
	for o: Array in ops:
		n += 1
		var why := RackPatch.answer(sim, String(o[0]), o[1])
		if why != "":
			return why if ops.size() == 1 else "step %d (%s): %s" % [n, o[0], why]
	_commit(api, sim, ops)
	return ""


static func _commit(api: ControlApi, sim: Dictionary, ops: Array) -> void:
	if _live(api):
		var host: Variant = api.studio.get("rack_host")
		for o: Array in ops:
			host.ask_rack(String(o[0]), o[1])
	else:
		test_patch = sim


static func _one(api: ControlApi, op: String, args: Array, data: Dictionary) -> Dictionary:
	var why := _run(api, [[op, args]])
	if why != "":
		return ControlTool.fail(why)
	return ControlTool.ok(data)


## Module `ref` (an id, any case, or a type that only one module has) as its id: {ok, id} or a failure that lists the ids.
static func _module(p: Dictionary, ref: Variant) -> Dictionary:
	var s := str(ref).strip_edges()
	var mods: Dictionary = p["modules"]
	if mods.has(s):
		return {"ok": true, "id": s}
	for id: String in mods:
		if id.to_lower() == s.to_lower():
			return {"ok": true, "id": id}
	var by_type: Array = []
	for id: String in mods:
		if String(mods[id]["type"]) == s:
			by_type.append(id)
	if by_type.size() == 1:
		return {"ok": true, "id": by_type[0]}
	return ControlTool.fail("no module '%s' in the rack; the modules are: %s" % [s, ", ".join(PackedStringArray(RackPatch.module_ids(p)))])


static func _title(type: String) -> String:
	return String(RackCatalogue.spec(type).get("title", type))


static func _knob_row(k: Dictionary, v: float) -> Dictionary:
	return {"id": k["id"], "label": k["label"], "value": snappedf(v, 0.0001), "display": RackCatalogue.readout(k, v),
			"range": RackHelp.range_text(k)}


static func _module_row(p: Dictionary, id: String, full: bool) -> Dictionary:
	var m: Dictionary = p["modules"][id]
	var type := String(m["type"])
	var spec := RackCatalogue.spec(type)
	var knobs := {}
	for k: Dictionary in spec.get("knobs", []):
		var v := RackPatch.knob_of(p, id, String(k["id"]))
		if full:
			knobs[String(k["label"])] = _knob_row(k, v)
		else:
			knobs[String(k["label"])] = {"id": k["id"], "value": snappedf(v, 0.0001), "display": RackCatalogue.readout(k, v)}
	return {"id": id, "type": type, "title": _title(type), "col": int(m["at"][0]), "row": int(m["at"][1]),
			"width": RackLayout.width_of(type), "knobs": knobs,
			"ins": spec.get("ins", []), "outs": spec.get("outs", []), "missing": bool(m.get("missing", false))}


static func _list(api: ControlApi, a: Dictionary) -> Dictionary:
	var p := _patch(api)
	var ids := RackPatch.module_ids(p)
	var off := int(a.get("offset", 0))
	var lim := int(a.get("limit", 60))
	var rows: Array = []
	for i in range(off, mini(off + lim, ids.size())):
		rows.append(_module_row(p, ids[i], false))
	return ControlTool.ok({"modules": rows, "total": ids.size(), "cables": (p["cables"] as Array).size(),
			"cost": RackPatch.cost(p), "max_modules": RackPatch.MAX_MODULES, "max_cables": RackPatch.MAX_CABLES,
			"track": _track_of(api), "grid": {"cols": RackLayout.COLS, "rows": RackLayout.ROWS}})


static func _module_get(api: ControlApi, a: Dictionary) -> Dictionary:
	var p := _patch(api)
	var r := _module(p, a["module"])
	if not r["ok"]:
		return r
	var id: String = r["id"]
	var row := _module_row(p, id, true)
	var cables: Array = []
	for c in p["cables"]:
		if String(c[0]).get_slice(".", 0) == id or String(c[1]).get_slice(".", 0) == id:
			cables.append({"from": c[0], "to": c[1]})
	row["cables"] = cables
	var card := RackHelp.card(String(row["type"]))
	row["group"] = card.get("group", "")
	row["help"] = {"blurb": card.get("blurb", ""), "what": card.get("what", ""), "how": card.get("how", ""), "try": card.get("try", "")}
	return ControlTool.ok(row)


static func _add(api: ControlApi, a: Dictionary) -> Dictionary:
	var type := String(a["type"])
	if not RackCatalogue.has(type):
		var hint := RackFinder.search(type.get_slice(".", type.count(".")).replace("_", " "))
		return ControlTool.fail("there is no module called %s%s" % [type, ("; did you mean " + ", ".join(PackedStringArray(hint.slice(0, 5)))) if not hint.is_empty() else " (rack_modules_find searches the catalogue)"])
	if a.has("col") != a.has("row"):
		return ControlTool.fail("give col and row together, or neither for the first free place")
	var p := _patch(api)
	var sim := p.duplicate(true)
	var id := RackPatch.new_id(sim, type)
	var args := [type, int(a.get("col", -1)), int(a.get("row", 0))]
	var why := RackPatch.answer(sim, "add", args)
	if why != "":
		return ControlTool.fail(why)
	_commit(api, sim, [["add", args]])
	var m: Dictionary = sim["modules"][id]
	return ControlTool.ok({"id": id, "type": type, "title": _title(type), "col": int(m["at"][0]), "row": int(m["at"][1])})


static func _remove(api: ControlApi, a: Dictionary) -> Dictionary:
	var r := _module(_patch(api), a["module"])
	if not r["ok"]:
		return r
	return _one(api, "remove", [r["id"]], {"removed": r["id"]})


static func _move(api: ControlApi, a: Dictionary) -> Dictionary:
	var r := _module(_patch(api), a["module"])
	if not r["ok"]:
		return r
	return _one(api, "move", [r["id"], int(a["col"]), int(a["row"])], {"module": r["id"], "col": int(a["col"]), "row": int(a["row"])})


static func _set_knob(api: ControlApi, a: Dictionary) -> Dictionary:
	var p := _patch(api)
	var r := _module(p, a["module"])
	if not r["ok"]:
		return r
	var id: String = r["id"]
	var type := RackPatch.type_of(p, id)
	var want := str(a["knob"]).strip_edges().to_lower()
	var found := {}
	for k: Dictionary in RackCatalogue.spec(type).get("knobs", []):
		if String(k["id"]).to_lower() == want:
			found = k
			break
	if found.is_empty():
		for k: Dictionary in RackCatalogue.spec(type).get("knobs", []):
			if String(k["label"]).to_lower() == want:
				found = k
				break
	if found.is_empty():
		var labels := PackedStringArray()
		for k: Dictionary in RackCatalogue.spec(type).get("knobs", []):
			labels.append("%s (%s)" % [k["label"], k["id"]])
		return ControlTool.fail("module %s has no knob '%s'; its knobs are: %s" % [id, a["knob"], ", ".join(labels)])
	if a.has("value") == a.has("real"):
		return ControlTool.fail("give exactly one of value (position 0..1) or real (the value in the knob's unit)")
	var v := float(a["value"]) if a.has("value") else RackCatalogue.position(found, float(a["real"]))
	if a.has("real") and str(found["curve"]) == "exp" and float(a["real"]) <= 0.0:
		return ControlTool.fail("this knob is exponential: real must be above 0 (range %s)" % RackHelp.range_text(found))
	var why := _run(api, [["knob", [id, String(found["id"]), v]]])
	if why != "":
		return ControlTool.fail(why)
	var now := RackPatch.knob_of(_patch(api), id, String(found["id"]))
	if not _live(api):
		now = RackPatch.knob_of(test_patch, id, String(found["id"]))
	return ControlTool.ok({"module": id, "knob": _knob_row(found, now)})


static func _cables(api: ControlApi) -> Dictionary:
	var out: Array = []
	for c in _patch(api)["cables"]:
		out.append({"from": c[0], "to": c[1]})
	return ControlTool.ok({"cables": out, "total": out.size(), "max": RackPatch.MAX_CABLES})


## A jack written module.jack as its path with the module resolved, or a failure naming the real jacks.
static func _jack(p: Dictionary, text: String, output: bool) -> Dictionary:
	var s := text.strip_edges()
	if s.count(".") != 1:
		return ControlTool.fail("a jack is written module.jack, e.g. vco.out; got '%s'" % s)
	var r := _module(p, s.get_slice(".", 0))
	if not r["ok"]:
		return r
	var id: String = r["id"]
	var port := s.get_slice(".", 1)
	var spec := RackCatalogue.spec(RackPatch.type_of(p, id))
	var mine: Array = spec.get("outs" if output else "ins", [])
	var other: Array = spec.get("ins" if output else "outs", [])
	if port in mine:
		return {"ok": true, "path": "%s.%s" % [id, port]}
	if port in other:
		return ControlTool.fail("%s.%s is an %s; a cable goes from an output to an input. %s's %s are: %s" % [id, port, "input" if output else "output", id, "outputs" if output else "inputs", ", ".join(PackedStringArray(mine))])
	return ControlTool.fail("module %s has no %s '%s'; its %ss are: %s" % [id, "output" if output else "input", port, "output" if output else "input", ", ".join(PackedStringArray(mine))])


static func _cable_add(api: ControlApi, a: Dictionary) -> Dictionary:
	var p := _patch(api)
	var f := _jack(p, str(a["from"]), true)
	if not f["ok"]:
		return f
	var t := _jack(p, str(a["to"]), false)
	if not t["ok"]:
		return t
	for c in p["cables"]:
		if c[0] == f["path"] and c[1] == t["path"]:
			return ControlTool.fail("that cable is already there")
	if (p["cables"] as Array).size() >= RackPatch.MAX_CABLES:
		return ControlTool.fail("the case has no more room for cables (the limit is %d)" % RackPatch.MAX_CABLES)
	var fed: Array = []
	for c in p["cables"]:
		if c[1] == t["path"]:
			fed.append(c[0])
	var why := _run(api, [["cable", [f["path"], t["path"]]]])
	if why != "":
		return ControlTool.fail(why)
	var data := {"from": f["path"], "to": t["path"]}
	if not fed.is_empty():
		data["note"] = "%s was already fed by %s; it is now fed by both" % [t["path"], ", ".join(PackedStringArray(fed))]
	return ControlTool.ok(data)


static func _cable_remove(api: ControlApi, a: Dictionary) -> Dictionary:
	var p := _patch(api)
	var t := _jack(p, str(a["to"]), false)
	if not t["ok"]:
		return t
	if a.has("from"):
		var f := _jack(p, str(a["from"]), true)
		if not f["ok"]:
			return f
		return _one(api, "pull_one", [f["path"], t["path"]], {"removed": [[f["path"], t["path"]]]})
	var gone: Array = []
	for c in p["cables"]:
		if c[1] == t["path"]:
			gone.append([c[0], c[1]])
	return _one(api, "pull", [t["path"]], {"removed": gone})


static func _clear(api: ControlApi) -> Dictionary:
	var p := _patch(api)
	var ops: Array = []
	var kept := 0
	for id: String in RackPatch.module_ids(p):
		if RackPatch.type_of(p, id) == RackPatch.OUT_MODULE:
			kept += 1
		else:
			ops.append(["remove", [id]])
	if ops.is_empty():
		return ControlTool.ok({"removed": 0, "kept_out": kept})
	var why := _run(api, ops)
	if why != "":
		return ControlTool.fail(why)
	return ControlTool.ok({"removed": ops.size(), "kept_out": kept})


static func _power(api: ControlApi, a: Dictionary) -> Dictionary:
	if not _live(api):
		return ControlTool.fail("there is no running game with a rack to switch")
	var host: Variant = api.studio.get("rack_host")
	if a.has("on"):
		host.ask_rack("power", [bool(a["on"])])
	return ControlTool.ok({"on": bool(host.rack_on())})


static func _track(api: ControlApi, a: Dictionary) -> Dictionary:
	if not _live(api):
		return ControlTool.fail("there is no running game with a rack to choose a track for")
	var step := -1
	if str(a["track"]).to_lower() != "none":
		var r := ControlRefs.track(DAW.state, a["track"])
		if not r["ok"]:
			return r
		step = int(r["index"])
	var host: Variant = api.studio.get("rack_host")
	host.ask_rack("track", [step])
	return ControlTool.ok({"track": _track_of(api)})


# --- whole patches ------------------------------------------------------------------------------

static func _patch_get(api: ControlApi) -> Dictionary:
	var p := RackPatch.sanitize(_patch(api))
	return ControlTool.ok(RackPatch.to_dict(p, "", _track_of(api)))


static func _same_at(a: Variant, b: Variant) -> bool:
	return a is Array and b is Array and a.size() >= 2 and b.size() >= 2 and int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])


## The ops that make the patch `cur` into `target` (a sanitized patch): what is the same stays, what differs is taken
## out and put in again (the OUT is moved, never removed), then knobs and cables. Every op is tried on a copy as it is
## planned. {ok, ops, ids} (ids: the target's module ids to the ids they have), or a failure in words. With `strict`
## a module type nobody here provides is an error, otherwise it is left out.
static func _plan(cur: Dictionary, target: Dictionary, strict: bool) -> Dictionary:
	var sim := cur.duplicate(true)
	var ops: Array = []
	var ids := {}
	var tm: Dictionary = target["modules"]
	var keep := {}
	for id: String in tm:
		var have: Dictionary = (sim["modules"] as Dictionary).get(id, {})
		if not have.is_empty() and have["type"] == tm[id]["type"] and _same_at(have["at"], tm[id]["at"]):
			ids[id] = id
			keep[id] = true
	var t_out := ""
	for id: String in tm:
		if tm[id]["type"] == RackPatch.OUT_MODULE:
			t_out = id
	for id: String in RackPatch.module_ids(sim):
		if keep.has(id) or RackPatch.type_of(sim, id) == RackPatch.OUT_MODULE:
			continue
		ops.append(["remove", [id]])
		RackPatch.answer(sim, "remove", [id])
	if t_out != "" and not ids.has(t_out):
		for id: String in RackPatch.module_ids(sim):
			if RackPatch.type_of(sim, id) == RackPatch.OUT_MODULE:
				ids[t_out] = id
				if not _same_at(sim["modules"][id]["at"], tm[t_out]["at"]):
					var mv := [id, int(tm[t_out]["at"][0]), int(tm[t_out]["at"][1])]
					if RackPatch.answer(sim, "move", mv) == "":
						ops.append(["move", mv])
	for tid: String in RackPatch.module_ids(target):
		if ids.has(tid):
			continue
		var type := String(tm[tid]["type"])
		if not RackCatalogue.has(type):
			if strict:
				return ControlTool.fail("module '%s': there is no module type called %s" % [tid, type])
			continue
		var fresh := RackPatch.new_id(sim, type)
		var args := [type, int(tm[tid]["at"][0]), int(tm[tid]["at"][1])]
		var why := RackPatch.answer(sim, "add", args)
		if why == "that does not fit there":
			args = [type, -1, 0]
			why = RackPatch.answer(sim, "add", args)
		if why != "":
			return ControlTool.fail("module '%s' (%s): %s" % [tid, type, why])
		ops.append(["add", args])
		ids[tid] = fresh
	for tid: String in RackPatch.module_ids(target):
		if not ids.has(tid) or not RackCatalogue.has(String(tm[tid]["type"])):
			continue
		var knobs: Dictionary = tm[tid]["knobs"]
		for k: String in knobs:
			var kargs := [ids[tid], k, float(knobs[k])]
			if absf(float(knobs[k]) - RackPatch.knob_of(sim, ids[tid], k)) > 0.00001 and RackPatch.answer(sim, "knob", kargs) == "":
				ops.append(["knob", kargs])
	var want := {}
	for c in target["cables"]:
		var f := String(c[0]).get_slice(".", 0)
		var t := String(c[1]).get_slice(".", 0)
		if not ids.has(f) or not ids.has(t):
			if strict:
				return ControlTool.fail("cable %s -> %s: a module it names is not in the patch" % [c[0], c[1]])
			continue
		want[[String(ids[f]) + "." + String(c[0]).get_slice(".", 1), String(ids[t]) + "." + String(c[1]).get_slice(".", 1)]] = true
	for c: Array in (sim["cables"] as Array).duplicate():
		if not want.has([c[0], c[1]]):
			ops.append(["pull_one", [c[0], c[1]]])
			RackPatch.answer(sim, "pull_one", [c[0], c[1]])
	for w: Array in want:
		var have_it := false
		for c: Array in sim["cables"]:
			if c[0] == w[0] and c[1] == w[1]:
				have_it = true
		if not have_it:
			var why2 := RackPatch.answer(sim, "cable", [w[0], w[1]])
			if why2 != "":
				return ControlTool.fail("cable %s -> %s: %s" % [w[0], w[1], why2])
			ops.append(["cable", [w[0], w[1]]])
	return {"ok": true, "ops": ops, "ids": ids, "result": sim}


## Make the patch `target`: "" when done, else why not. Nothing is changed on a failure.
static func _replace(api: ControlApi, target: Dictionary, strict: bool) -> String:
	var plan := _plan(_patch(api), RackPatch.sanitize(target), strict)
	if not plan["ok"]:
		return str(plan["error"])
	_commit(api, plan["result"], plan["ops"])
	return ""


static func _patch_set(api: ControlApi, a: Dictionary) -> Dictionary:
	var raw: Dictionary = a["patch"]
	var bad := RackPatch.problem(raw)
	if bad != "":
		return ControlTool.fail("patch not applied: %s (give {modules: {id: {type, at, knobs}}, cables: [[from, to]]})" % bad)
	var clean := RackPatch.sanitize(raw)
	var lost: Array = []
	for id in raw["modules"]:
		if not (clean["modules"] as Dictionary).has(str(id)):
			lost.append("module %s" % id)
	var cables: Array = []
	for c in clean["cables"]:
		cables.append("%s>%s" % [c[0], c[1]])
	var raw_cables: Variant = raw.get("cables", [])
	if raw_cables is Array:
		for c in raw_cables:
			if not (c is Array and c.size() == 2 and ("%s>%s" % [c[0], c[1]]) in cables):
				lost.append("cable %s" % str(c))
	if not lost.is_empty():
		return ControlTool.fail("patch not applied; the game would drop: %s (an unknown module type, a bad id, a jack that does not exist, a repeated or over-limit cable, or too many modules)" % ", ".join(PackedStringArray(lost.slice(0, 12))))
	var plan := _plan(_patch(api), clean, true)
	if not plan["ok"]:
		return ControlTool.fail("patch not applied: " + str(plan["error"]))
	_commit(api, plan["result"], plan["ops"])
	var names := {}
	for tid: String in plan["ids"]:
		if plan["ids"][tid] != tid:
			names[tid] = plan["ids"][tid]
	return ControlTool.ok({"modules": (clean["modules"] as Dictionary).size(), "cables": (clean["cables"] as Array).size(), "steps": (plan["ops"] as Array).size(), "renamed": names})


# --- presets and saved patches ------------------------------------------------------------------

static func _presets_list() -> Dictionary:
	var presets: Array = []
	for n in RackPatch.presets():
		presets.append({"name": String(n), "title": RackPatch.preset_title(n)})
	return ControlTool.ok({"presets": presets, "saved": _saved_names()})


static func _saved_names() -> Array:
	var out: Array = []
	var dir := DataHome.dir(RackPatchFile.KIND)
	if dir == "":
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(SAVED_SUFFIX) and not f.begins_with("_"):
			out.append(f.trim_suffix(SAVED_SUFFIX))
	out.sort()
	return out


static func _preset_load(api: ControlApi, a: Dictionary) -> Dictionary:
	var name := str(a["name"])
	if not RackPatch.presets().has(StringName(name)):
		var names := PackedStringArray()
		for n in RackPatch.presets():
			names.append(String(n))
		return ControlTool.fail("there is no such preset '%s'; the presets are: %s" % [name, ", ".join(names)])
	return _one(api, "preset", [name], {"loaded": name})


static func _name_problem(name: String) -> String:
	if name.is_empty() or name.length() > 60:
		return "a name is 1 to 60 characters"
	if name.begins_with("_") or name.begins_with(" ") or name.ends_with(" "):
		return "a name may not start with '_' or start or end with a space"
	for ch in name:
		if not NAME_CHARS.contains(ch):
			return "a name holds only letters, digits, space, '_' and '-' (not '%s')" % ch
	return ""


static func _file_of(name: String) -> String:
	var dir := DataHome.dir(RackPatchFile.KIND)
	return "" if dir == "" else dir + name + SAVED_SUFFIX


static func _patch_save(api: ControlApi, a: Dictionary) -> Dictionary:
	var name := str(a["name"])
	var bad := _name_problem(name)
	if bad != "":
		return ControlTool.fail(bad)
	var path := _file_of(name)
	if path == "":
		return ControlTool.fail("the patches folder cannot be made")
	if FileAccess.file_exists(path) and not bool(a.get("overwrite", false)):
		return ControlTool.fail("a patch called '%s' is already saved; pass overwrite: true to replace it" % name)
	var text := RackPatchFile.text_of(RackPatch.to_dict(RackPatch.sanitize(_patch(api)), name, _track_of(api)))
	var err := RackPatchFile.write_text(path, text)
	if err != OK:
		return ControlTool.fail("could not save: " + error_string(err))
	return ControlTool.ok({"saved": name, "path": ProjectSettings.globalize_path(path)})


static func _patch_load(api: ControlApi, a: Dictionary) -> Dictionary:
	var name := str(a["name"])
	var bad := _name_problem(name)
	if bad != "":
		return ControlTool.fail(bad)
	var path := _file_of(name)
	if path == "" or not FileAccess.file_exists(path):
		return ControlTool.fail("no saved patch called '%s'; the saved ones are: %s" % [name, ", ".join(PackedStringArray(_saved_names()))])
	var read := RackPatchFile.read(path)
	if not read["ok"]:
		return ControlTool.fail("the saved patch cannot be read: %s" % read["error"])
	var why := _replace(api, read["patch"], false)
	if why != "":
		return ControlTool.fail(why)
	return ControlTool.ok({"loaded": name, "modules": (read["patch"]["modules"] as Dictionary).size()})


# --- the catalogue ------------------------------------------------------------------------------

static func _find_row(t: String) -> Dictionary:
	var s := RackCatalogue.spec(t)
	return {"type": t, "title": s.get("title", t), "group": s.get("group", ""), "kinds": RackFinder.kinds_of(t), "blurb": s.get("blurb", "")}


## `word` as the spelling in `choices` (any case), or `word` itself when none matches.
static func _canon(word: String, choices: Array) -> String:
	for c in choices:
		if String(c).to_lower() == word.strip_edges().to_lower():
			return String(c)
	return word


static func _find(a: Dictionary) -> Dictionary:
	var group := _canon(str(a.get("group", "")), RackCatalogue.groups())
	var kind := _canon(str(a.get("kind", "")), RackFinder.all_kinds())
	var hits := RackFinder.search(str(a.get("query", "")), group, kind)
	var off := int(a.get("offset", 0))
	var lim := int(a.get("limit", 20))
	var rows: Array = []
	for i in range(off, mini(off + lim, hits.size())):
		rows.append(_find_row(hits[i]))
	return ControlTool.ok({"modules": rows, "total": hits.size(), "kinds": RackFinder.all_kinds() if hits.size() > lim and a.get("kind", "") == "" and a.get("query", "") == "" else []})


static func _types(a: Dictionary) -> Dictionary:
	if a.has("group"):
		var g := _canon(str(a["group"]), RackCatalogue.groups())
		var all := RackCatalogue.in_group(g)
		if all.is_empty():
			return ControlTool.fail("no group '%s'; the groups are: %s" % [g, ", ".join(PackedStringArray(RackCatalogue.groups()))])
		var rows: Array = []
		for t in all:
			rows.append({"type": t, "title": _title(t)})
		return ControlTool.ok({"group": g, "count": rows.size(), "types": rows})
	var out: Array = []
	for g in RackCatalogue.groups():
		var all := RackCatalogue.in_group(g)
		out.append({"group": g, "count": all.size(), "types": all.slice(0, 12), "more": maxi(all.size() - 12, 0)})
	return ControlTool.ok({"groups": out})


static func _help(a: Dictionary) -> Dictionary:
	var card := RackHelp.card(str(a["type"]))
	if card.is_empty():
		return ControlTool.fail("there is no module called %s (rack_modules_find searches the catalogue)" % str(a["type"]))
	return ControlTool.ok(card)


# --- render -------------------------------------------------------------------------------------

static func _render(api: ControlApi, a: Dictionary) -> Dictionary:
	# The engine's binary: never built from here (a build can take minutes); only used when it is already there.
	var told := OS.get_environment("DAWLINGS_RACK")
	var exe := told if told != "" and FileAccess.file_exists(told) else ProjectSettings.globalize_path("res://build/rack/rack")
	var shipped := RackEngine.shipped_dir().path_join("rack.exe" if OS.get_name() == "Windows" else "rack")
	if (told == "" or not FileAccess.file_exists(told)) and OS.has_feature("template") and FileAccess.file_exists(shipped):
		exe = shipped  # a release's own engine, beside the game
	if not FileAccess.file_exists(exe):
		return ControlTool.fail("the rack engine is not built on this machine (build/rack/rack is missing; tools/rack_build.sh builds it), so nothing can be rendered")
	if not RackEngine.available():
		return ControlTool.fail("the rack engine is not available on this machine, so nothing can be rendered")
	var secs := clampf(float(a.get("seconds", 2.0)), 0.1, RENDER_MAX_SECONDS)
	var events: Array = []
	for n: Variant in a.get("notes", []):
		if typeof(n) != TYPE_DICTIONARY:
			return ControlTool.fail("each note is {pitch, velocity, start, length}")
		var start := maxf(float(n.get("start", 0.0)), 0.0)
		var pitch := clampi(int(n.get("pitch", 60)), 0, 127)
		events.append([start, 1, pitch, clampi(int(n.get("velocity", 100)), 1, 127)])
		events.append([start + maxf(float(n.get("length", 0.5)), 0.01), 0, pitch, 0])
	events.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var play := PackedStringArray()
	var at := 0.0
	for e: Array in events:
		if float(e[0]) >= secs:
			break
		if float(e[0]) > at:
			play.append("run %.4f" % (float(e[0]) - at))
			at = float(e[0])
		play.append(("note_on %d %d" % [e[2], e[3]]) if int(e[1]) == 1 else ("note_off %d" % e[2]))
	if secs > at:
		play.append("run %.4f" % (secs - at))
	var frames := RackEngine.render(_patch(api), play, float(a.get("bpm", 120.0)))
	if frames.is_empty():
		return ControlTool.fail("the engine rendered nothing (the patch may have no OUT, or the engine failed)")
	var peak := 0.0
	var sq := 0.0
	for f in frames:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		sq += (f.x * f.x + f.y * f.y) * 0.5
	var rms := sqrt(sq / frames.size())
	var data := {"peak": snappedf(peak, 0.0001), "peak_db": snappedf(20.0 * log(maxf(peak, 0.00001)) / log(10.0), 0.1),
			"rms": snappedf(rms, 0.0001), "duration": snappedf(float(frames.size()) / RackEngine.RATE, 0.001), "frames": frames.size()}
	var dir := DataHome.dir(RENDER_DIR)
	if dir != "":
		var path := dir + "render_%d.wav" % Time.get_ticks_msec()
		if RackEngine.write_wav(path, frames):
			data["wav"] = ProjectSettings.globalize_path(path)
	return ControlTool.ok(data)
