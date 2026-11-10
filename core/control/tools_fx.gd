extends RefCounted

## Control tools: fx (a track's plugin chain), automation (a track's lanes) and look (read-only: meters,
## loudness, transport, a screenshot, where the player is). See core/control/control_tools.gd and
## docs/mcp_assistant.md.
##
## Every write goes through the DAW's public verb (DAW.add_fx, DAW.set_fx_param, DAW.set_automation ...), the
## one the game's own controls use, so undo, the multiplayer authority and the backend's refusals apply.

const T = preload("res://core/control/control_tool.gd")

## The most params, plugins, points or tracks one answer carries unless a limit says otherwise.
const PARAMS_DEFAULT := 40
const POINTS_DEFAULT := 200
const POINTS_MAX := 2000
const SHAPES := ["hold", "linear"]


static func register(api: ControlApi) -> void:
	_register_fx(api)
	_register_automation(api)
	_register_look(api)


# --- shared -------------------------------------------------------------------------------------

## A float for JSON: null for NAN or infinity (silence, not measured), else rounded.
static func _num(x: float, places := 2) -> Variant:
	if not is_finite(x):
		return null
	return snappedf(x, pow(10.0, -places))


static func _state() -> MixState:
	return DAW.state


## A track number for fx, or an error: fx lives on real tracks (not the master).
static func _track(a: Dictionary) -> Dictionary:
	return ControlRefs.track(DAW.state, a["track"])


## The fx number (its key in the track's chain) for `ref` (a number, "#n" or a plugin's name), or an error.
static func _fx(track_index: int, ref: Variant) -> Dictionary:
	var t := DAW.state.track(track_index, false)
	if t == null:
		return T.fail("no track number %d" % track_index)
	var chain := t.plugins()
	if typeof(ref) == TYPE_INT or typeof(ref) == TYPE_FLOAT:
		return _fx_number(t, chain, int(ref))
	var s := str(ref).strip_edges()
	if s.begins_with("#") and s.substr(1).is_valid_int():
		return _fx_number(t, chain, int(s.substr(1)))
	var hits: Array = []
	for i in chain:
		var f: MixState.FXState = t.fx[i]
		if MixState.FXState.bare_name(f.name).to_lower() == s.to_lower():
			hits.append(i)
	if hits.is_empty():
		for i in chain:
			var f: MixState.FXState = t.fx[i]
			if MixState.FXState.bare_name(f.name).to_lower().contains(s.to_lower()) and s != "":
				hits.append(i)
	if hits.size() == 1:
		return {"ok": true, "fx": hits[0]}
	if hits.is_empty():
		return T.fail("track %d has no plugin called '%s'; its chain is: %s" % [track_index, s, _chain_words(t)])
	return T.fail("%d plugins on track %d match '%s' (numbers %s); say '#<number>'" % [hits.size(), track_index, s,
			", ".join(PackedStringArray(hits.map(func(i: int) -> String: return str(i))))])


static func _fx_number(t: MixState.TrackState, chain: Array, n: int) -> Dictionary:
	if chain.has(n):
		return {"ok": true, "fx": n}
	return T.fail("track %d has no plugin number %d; its chain is: %s" % [t.index, n, _chain_words(t)])


static func _chain_words(t: MixState.TrackState) -> String:
	var out := PackedStringArray()
	for i in t.plugins():
		out.append("#%d %s" % [i, MixState.FXState.bare_name((t.fx[i] as MixState.FXState).name)])
	return ", ".join(out) if not out.is_empty() else "(empty)"


static func _param_name(f: MixState.FXState, p: int) -> String:
	var n := str(f.param_names.get(p, ""))
	return n if n != "" else "param %d" % p


## A param index from `ref` (an integer, or a name: exact, else a unique part of one), or an error.
static func _param(f: MixState.FXState, ref: Variant) -> Dictionary:
	if typeof(ref) == TYPE_INT or typeof(ref) == TYPE_FLOAT:
		var p := int(ref)
		if p < 0:
			return T.fail("a param number is 0 or more")
		if not f.param_list.is_empty() and not f.param_list.has(p):
			return T.fail("%s has no param number %d; use fx_get to see its params" % [f.name, p])
		return {"ok": true, "param": p}
	var s := str(ref).strip_edges().to_lower()
	if s.is_valid_int() and not f.param_names.values().any(func(v: Variant) -> bool: return str(v).to_lower() == s):
		return _param(f, int(s))
	var exact: Array = []
	var part: Array = []
	for k in f.param_names:
		var nm := str(f.param_names[k]).to_lower()
		if nm == s:
			exact.append(k)
		elif s != "" and nm.contains(s):
			part.append(k)
	var hits := exact if not exact.is_empty() else part
	if hits.size() == 1:
		return {"ok": true, "param": hits[0]}
	if hits.is_empty():
		return T.fail("%s has no param called '%s'%s" % [f.name, ref, _param_hint(f)])
	hits.sort()
	return T.fail("%d params of %s match '%s' (numbers %s); use the number" % [hits.size(), f.name, ref,
			", ".join(PackedStringArray(hits.map(func(i: Variant) -> String: return str(i))))])


static func _param_hint(f: MixState.FXState) -> String:
	if f.param_names.is_empty():
		return "; none of its params are named yet (a plugin's params are named once the DAW has read them: fx_read_params), use a number"
	var names := PackedStringArray()
	var keys: Array = f.param_names.keys()
	keys.sort()
	for k in keys:
		names.append("%s" % f.param_names[k])
		if names.size() >= 20:
			names.append("...")
			break
	return "; its params are: " + ", ".join(names)


static func _fx_row(t: MixState.TrackState, i: int, with_params: bool, limit := PARAMS_DEFAULT, offset := 0) -> Dictionary:
	var f: MixState.FXState = t.fx[i]
	var row := {"number": i, "slot": t.plugins().find(i), "name": MixState.FXState.bare_name(f.name),
			"type": f.type, "enabled": f.enabled, "wet": _num(f.wet, 3), "preset": f.preset,
			"preset_count": f.preset_count}
	var ctl := f.controls()
	row["param_count"] = ctl.size()
	if with_params:
		var out: Array = []
		for k in range(offset, mini(offset + limit, ctl.size())):
			var p: int = ctl[k]
			var pr := {"index": p, "name": _param_name(f, p)}
			if f.params.has(p):
				pr["value"] = _num(float(f.params[p]), 4)
			if f.param_text.has(p) and str(f.param_text[p]) != "":
				pr["text"] = str(f.param_text[p])
			out.append(pr)
		row["params"] = out
		row["params_range"] = [offset, mini(offset + limit, ctl.size())]
	return row


## [id, name] of a plugin the chain can be given, matched by id or name.
static func _plugin(ref: String) -> Dictionary:
	var s := ref.strip_edges().to_lower()
	var choices: Array = DAW.state.fx_choices
	for c in choices:
		if str(c[0]).to_lower() == s:
			return {"ok": true, "id": str(c[0]), "name": str(c[1])}
	var hits: Array = []
	for c in choices:
		if str(c[1]).to_lower() == s:
			hits.append(c)
	if hits.is_empty():
		for c in choices:
			if s != "" and (str(c[1]).to_lower().contains(s) or str(c[0]).to_lower().contains(s)):
				hits.append(c)
	if hits.size() == 1:
		return {"ok": true, "id": str(hits[0][0]), "name": str(hits[0][1])}
	if hits.is_empty():
		return T.fail("no plugin called '%s' on this DAW; fx_plugins lists them (query narrows it; %d available)" % [ref, choices.size()])
	var names := PackedStringArray()
	for c in hits.slice(0, 12):
		names.append(str(c[0]))
	return T.fail("%d plugins match '%s': %s; say the id" % [hits.size(), ref, ", ".join(names)])


# --- fx -----------------------------------------------------------------------------------------

static func _register_fx(api: ControlApi) -> void:
	var track_ref := T.ref_p("the track: its name, '#<number>' or its number (see track_list)")
	var fx_ref := T.ref_p("the plugin on that track: its number from fx_list, '#<number>', or its name")

	api.add(T.make("fx_plugins", "List the plugins that can be added to a track's chain on this DAW: id (what fx_add takes) and name. Optional query filters by a word of the id or name; limit/offset page the result.",
			{"query": T.str_p("a word of the plugin's id or name"), "limit": T.int_p("at most this many (default 60)", 1, 500),
			"offset": T.int_p("skip this many", 0)}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				var q := str(a.get("query", "")).to_lower()
				var all: Array = []
				for c in DAW.state.fx_choices:
					if q == "" or str(c[0]).to_lower().contains(q) or str(c[1]).to_lower().contains(q):
						all.append({"id": str(c[0]), "name": str(c[1])})
				var off := int(a.get("offset", 0))
				var lim := int(a.get("limit", 60))
				return T.ok({"total": all.size(), "offset": off, "plugins": all.slice(off, off + lim)})))

	api.add(T.make("fx_list", "A track's plugin chain in order: each plugin's number (what the other fx tools take), slot (0-based position), name, enabled, wet (0..1, 1 = all plugin), preset, and how many params it has. Params are not listed here, see fx_get.",
			{"track": track_ref}, ["track"], T.READ,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var t := DAW.state.track(r["index"], false)
				var rows: Array = []
				for i in t.plugins():
					rows.append(_fx_row(t, i, false))
				return T.ok({"track": r["index"], "track_name": t.name, "frozen": t.is_frozen(), "fx": rows})))

	api.add(T.make("fx_get", "One plugin with its params BY NAME: index, name, value (normalised 0..1, the plugin's own scale; the DAW's reading of it in the plugin's units, such as '-12.0 dB', is `text` where the DAW has told us), plus enabled, wet, preset. Params are paged with limit/offset (default 40). A plugin whose params are not named yet needs fx_read_params first.",
			{"track": track_ref, "fx": fx_ref, "limit": T.int_p("params per page (default 40)", 1, 500),
			"offset": T.int_p("skip this many params", 0)}, ["track", "fx"], T.READ,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var x := _fx(r["index"], a["fx"])
				if not x["ok"]:
					return x
				var t := DAW.state.track(r["index"], false)
				var row := _fx_row(t, x["fx"], true, int(a.get("limit", PARAMS_DEFAULT)), int(a.get("offset", 0)))
				row["track"] = r["index"]
				row["has_window"] = DAW.has_plugin_window(r["index"], x["fx"])
				return T.ok(row)))

	api.add(T.make("fx_add", "Add a plugin to a track's chain, by id or name from fx_plugins. It goes at the end, or before the plugin `before` when given. Plugin numbers are places in the chain, so adding before one renumbers those after it: read the numbers from the chain this returns. Returns the chain afterwards and, where the DAW has already placed it, the new plugin's number (a remote DAW may take a moment: call fx_list).",
			{"track": track_ref, "plugin": T.str_p("a plugin id or name from fx_plugins"),
			"before": fx_ref}, ["track", "plugin"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var p := _plugin(str(a["plugin"]))
				if not p["ok"]:
					return p
				var at := -1
				if a.has("before"):
					var x := _fx(r["index"], a["before"])
					if not x["ok"]:
						return x
					at = x["fx"]
				var t := DAW.state.track(r["index"], false)
				var had: Array = t.plugins().duplicate()
				var pos: int = had.find(at) if at >= 0 and had.has(at) else had.size()
				DAW.add_fx(r["index"], p["id"], at)
				t = DAW.state.track(r["index"], false)
				# Plugin numbers are places in the chain: putting one in front renumbers those behind it.
				var added: Variant = null
				if t.plugins().size() == had.size() + 1:
					added = t.plugins()[pos]
				var rows: Array = []
				for i in t.plugins():
					rows.append(_fx_row(t, i, false))
				return T.ok({"track": r["index"], "added": added, "plugin": p["name"], "fx": rows})))

	api.add(T.make("fx_remove", "Remove a plugin from a track's chain (its settings are lost; the player confirms first).",
			{"track": track_ref, "fx": fx_ref}, ["track", "fx"], T.DESTRUCTIVE,
			func(a: Dictionary) -> Dictionary:
				var r := _track(a)
				if not r["ok"]:
					return r
				var x := _fx(r["index"], a["fx"])
				if not x["ok"]:
					return x
				var name_was := MixState.FXState.bare_name((DAW.state.track(r["index"], false).fx[x["fx"]] as MixState.FXState).name)
				DAW.remove_fx(r["index"], x["fx"])
				return T.ok({"removed": name_was, "track": r["index"],
						"fx": DAW.state.track(r["index"], false).plugins().size()})))

	var move_props := {"track": track_ref, "fx": fx_ref,
			"to_track": T.ref_p("the track to put it on (default: the same track, to reorder)"),
			"before": T.ref_p("the plugin on the destination track to put it before (its number or name); omit for the end of the chain")}
	api.add(T.make("fx_move", "Move a plugin to another place in its chain, or to another track's chain (before a given plugin there, or at the end). With copy true it is copied and the original stays. Plugin numbers are places in the chain and shift when one is moved: read them again from the chain this returns. Needs a DAW that can rearrange chains.",
			_with(move_props, {"copy": T.bool_p("copy instead of move (default false)")}), ["track", "fx"], T.EDIT,
			func(a: Dictionary) -> Dictionary: return _move(a, bool(a.get("copy", false)))))
	api.add(T.make("fx_copy", "Copy a plugin, with its settings, to another place in its chain or to another track (the original stays). Same arguments as fx_move.",
			move_props, ["track", "fx"], T.EDIT,
			func(a: Dictionary) -> Dictionary: return _move(a, true)))

	api.add(T.make("fx_set_enabled", "Turn a plugin on (true) or bypass it (false).",
			{"track": track_ref, "fx": fx_ref, "enabled": T.bool_p("true = on, false = bypassed")}, ["track", "fx", "enabled"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _resolve(a)
				if not f["ok"]:
					return f
				DAW.set_fx_enabled(f["track"], f["fx"], bool(a["enabled"]))
				return T.ok({"enabled": (DAW.state.fx(f["track"], f["fx"], false) as MixState.FXState).enabled})))

	api.add(T.make("fx_set_wet", "Set a plugin's wet/dry mix: 0 = all dry (as if bypassed) to 1 = all plugin. Not one of its own params.",
			{"track": track_ref, "fx": fx_ref, "wet": T.num_p("0..1", 0.0, 1.0)}, ["track", "fx", "wet"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _resolve(a)
				if not f["ok"]:
					return f
				DAW.set_fx_wet(f["track"], f["fx"], float(a["wet"]))
				return T.ok({"wet": _num((DAW.state.fx(f["track"], f["fx"], false) as MixState.FXState).wet, 3)})))

	api.add(T.make("fx_set_param", "Set one parameter of a plugin, by name (exact, or a part of it that is unique) or by its index from fx_get. `value` is NORMALISED 0..1 across the plugin's own range (so 0.5 is the middle of the knob, not 50 of anything); read the `text` of fx_get after to see it in the plugin's units.",
			{"track": track_ref, "fx": fx_ref, "param": T.ref_p("the param's name or index (fx_get)"),
			"value": T.num_p("normalised, 0..1", 0.0, 1.0)}, ["track", "fx", "param", "value"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _resolve(a)
				if not f["ok"]:
					return f
				var st: MixState.FXState = DAW.state.fx(f["track"], f["fx"], false)
				var p := _param(st, a["param"])
				if not p["ok"]:
					return p
				DAW.set_fx_param(f["track"], f["fx"], p["param"], clampf(float(a["value"]), 0.0, 1.0))
				return T.ok({"param": p["param"], "name": _param_name(st, p["param"]),
						"value": _num(float(st.params.get(p["param"], a["value"])), 4)})))

	api.add(T.make("fx_set_params", "Set several parameters of one plugin at once. `params` is an object of param name (or index as a string) to normalised 0..1 value, e.g. {\"Threshold\": 0.4, \"Ratio\": 0.6}. Checked first: if any name is unknown nothing is set.",
			{"track": track_ref, "fx": fx_ref, "params": T.obj_p("{param name or index: value 0..1}")},
			["track", "fx", "params"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _resolve(a)
				if not f["ok"]:
					return f
				var st: MixState.FXState = DAW.state.fx(f["track"], f["fx"], false)
				var todo: Array = []
				for k in (a["params"] as Dictionary):
					var v: Variant = a["params"][k]
					if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
						return T.fail("the value of '%s' must be a number 0..1" % k)
					if float(v) < 0.0 or float(v) > 1.0:
						return T.fail("the value of '%s' must be between 0 and 1, it is normalised" % k)
					var p := _param(st, k)
					if not p["ok"]:
						return p
					todo.append([p["param"], float(v)])
				for pair in todo:
					DAW.set_fx_param(f["track"], f["fx"], pair[0], pair[1])
				return T.ok({"set": todo.size()})))

	api.add(T.make("fx_read_params", "Ask the DAW to read a plugin's parameter names, values and display text (a remote DAW answers a moment later: call fx_get after). With `params` (names or indices) reads just those, else lists every real parameter. Only does anything on a DAW that can name params.",
			{"track": track_ref, "fx": fx_ref, "params": T.arr_p("param indices to read; omit to list them all", {"type": "integer"}),
			"text_of": T.int_p("read only the display text of this one param index", 0)}, ["track", "fx"], T.READ,
			func(a: Dictionary) -> Dictionary:
				var f := _resolve(a)
				if not f["ok"]:
					return f
				if not DAW.can(DAWBackend.Capability.FX_PARAM_NAMES):
					return T.fail("this DAW does not report plugin parameter names")
				if a.has("text_of"):
					DAW.read_fx_param_text(f["track"], f["fx"], int(a["text_of"]))
				else:
					var ps: Array = a.get("params", [])
					if ps.size() > DAW.READ_PARAMS_MAX:
						return T.fail("name at most %d params at once" % DAW.READ_PARAMS_MAX)
					DAW.read_fx_params(f["track"], f["fx"], ps)
				return T.ok({"asked": true, "note": "answers arrive in the state; call fx_get to read them"})))

	api.add(T.make("fx_step_preset", "Step a plugin to its next (direction 1) or previous (-1) preset; returns the preset it is on. Only a DAW that knows the plugin's presets can; fx_get shows the current preset and how many there are.",
			{"track": track_ref, "fx": fx_ref, "direction": T.int_p("1 = next, -1 = previous", -1, 1)},
			["track", "fx", "direction"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var f := _resolve(a)
				if not f["ok"]:
					return f
				if int(a["direction"]) == 0:
					return T.fail("direction is 1 (next) or -1 (previous)")
				if not DAW.can(DAWBackend.Capability.FX_PRESETS):
					return T.fail("this DAW cannot step a plugin's presets")
				DAW.step_fx_preset(f["track"], f["fx"], int(a["direction"]))
				var st: MixState.FXState = DAW.state.fx(f["track"], f["fx"], false)
				return T.ok({"preset": st.preset, "preset_count": st.preset_count})))


static func _with(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b)
	return out


## {ok, track, fx} for the `track` and `fx` arguments, or an error.
static func _resolve(a: Dictionary) -> Dictionary:
	var r := _track(a)
	if not r["ok"]:
		return r
	var x := _fx(r["index"], a["fx"])
	if not x["ok"]:
		return x
	return {"ok": true, "track": r["index"], "fx": x["fx"]}


static func _move(a: Dictionary, copy: bool) -> Dictionary:
	var src := _resolve(a)
	if not src["ok"]:
		return src
	if not DAW.can(DAWBackend.Capability.FX_CHAIN):
		return T.fail("this DAW cannot rearrange plugin chains")
	var to_track: int = src["track"]
	if a.has("to_track"):
		var tr := ControlRefs.track(DAW.state, a["to_track"])
		if not tr["ok"]:
			return tr
		to_track = tr["index"]
	var to_fx := 1 << 20  # past the end: the end of the chain
	if a.has("before"):
		var x := _fx(to_track, a["before"])
		if not x["ok"]:
			return x
		to_fx = x["fx"]
	var dest := DAW.state.track(to_track, false)
	var had: Array = dest.plugins().duplicate()
	var pos: int = had.find(to_fx) if had.has(to_fx) else had.size()
	DAW.move_fx(src["track"], src["fx"], to_track, to_fx, copy)
	var rows: Array = []
	for i in DAW.state.track(to_track, false).plugins():
		rows.append(_fx_row(DAW.state.track(to_track, false), i, false))
	var landed: Variant = null
	var now: Array = DAW.state.track(to_track, false).plugins()
	if (copy or to_track != src["track"]) and now.size() == had.size() + 1:
		landed = now[pos]
	elif to_track == src["track"] and not copy:
		landed = now[clampi(pos - (1 if had.find(src["fx"]) < pos else 0), 0, now.size() - 1)]
	return T.ok({"track": to_track, "copied": copy, "new_number": landed, "fx": rows})


# --- automation ---------------------------------------------------------------------------------

## The track a lane is on: a track, or "master"/0 (the master's volume and pan only).
static func _lane_track(ref: Variant) -> Dictionary:
	if (typeof(ref) in [TYPE_INT, TYPE_FLOAT] and int(ref) == 0) or str(ref).strip_edges().to_lower() in ["master", "#0", "0"]:
		return {"ok": true, "index": 0}
	return ControlRefs.track(DAW.state, ref)


static func _lanes_of(index: int) -> Dictionary:
	if index == 0:
		return DAW.state.master.automation
	return DAW.state.track(index, false).automation


static func _target_words() -> String:
	return "'volume' (dB), 'pan' (-1 left to 1 right), 'mute' (0 or 1), 'send:<destination track number>' (dB), 'fx:<plugin number>:<param index>' (normalised 0..1), 'enable:<plugin number>' (0 or 1)"


## Why `target` is not a lane on track `index`, or "".
static func _target_problem(index: int, target: String) -> String:
	var kind := DawKitAutomation.kind_of(target)
	if kind == "":
		return "'%s' is not an automatable target; they are %s" % [target, _target_words()]
	if index == 0 and kind not in ["volume", "pan"]:
		return "the master's lanes are 'volume' and 'pan' only"
	if kind in ["fx", "enable"] and index > 0:
		var n := int(target.split(":")[1])
		if not DAW.state.track(index, false).plugins().has(n):
			return "track %d has no plugin number %d (its chain: %s)" % [index, n, _chain_words(DAW.state.track(index, false))]
	if kind == "send" and index > 0:
		if not target.substr(5).is_valid_int() or not DAW.state.track_indices().has(int(target.substr(5))):
			return "'send:<n>' names the destination track by number (see track_list)"
	return ""


static func _shape_of(v: Variant) -> int:
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return DawKitAutomation.HOLD if int(v) == 0 else DawKitAutomation.LINEAR
	return DawKitAutomation.HOLD if str(v).to_lower() == "hold" else DawKitAutomation.LINEAR


## [seconds, value, shape] points from what a client sent, in time order, or an error String.
static func _points_in(target: String, raw: Array) -> Variant:
	if raw.size() > MixWire.AUTOMATION_POINTS_MAX:
		return "a lane holds at most %d points" % MixWire.AUTOMATION_POINTS_MAX
	var out: Array = []
	for n in raw.size():
		var p: Variant = raw[n]
		var s: Variant
		var v: Variant
		var sh: Variant = "linear"
		if typeof(p) == TYPE_ARRAY and p.size() >= 2:
			s = p[0]
			v = p[1]
			if p.size() > 2:
				sh = p[2]
		elif typeof(p) == TYPE_DICTIONARY and p.has("seconds") and p.has("value"):
			s = p["seconds"]
			v = p["value"]
			sh = p.get("shape", "linear")
		else:
			return "point %d must be [seconds, value, shape] or {seconds, value, shape}" % n
		if typeof(s) not in [TYPE_INT, TYPE_FLOAT] or typeof(v) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(s)) or not is_finite(float(v)):
			return "point %d: seconds and value must be numbers" % n
		if float(s) < 0.0:
			return "point %d: seconds cannot be negative" % n
		out.append([float(s), DawKitAutomation.clamp_value(target, float(v)), _shape_of(sh)])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	# One point per instant: the later one given wins.
	var clean: Array = []
	for p in out:
		if not clean.is_empty() and is_equal_approx(clean[-1][0], p[0]):
			clean[-1] = p
		else:
			clean.append(p)
	return clean


static func _points_out(points: Array, offset: int, limit: int) -> Array:
	var out: Array = []
	for p in points.slice(offset, offset + limit):
		out.append({"seconds": _num(float(p[0]), 4), "value": _num(float(p[1]), 4), "shape": SHAPES[clampi(int(p[2]), 0, 1)]})
	return out


static func _register_automation(api: ControlApi) -> void:
	var track_ref := T.ref_p("the track (name, '#<number>' or number), or 'master' for the master's volume and pan")
	var target_p := T.str_p("the lane: " + _target_words())
	var points_p := T.arr_p("points as [seconds, value, shape] or {seconds, value, shape}; shape is 'linear' (ramp to the next point) or 'hold' (stay until the next). Value units by lane: volume dB, pan -1..1, mute/enable 0 or 1, send dB, fx 0..1.", {})

	api.add(T.make("automation_list", "The automated lanes of a track (or the master): target, how many points, the time span they cover, and the value range. Points are in automation_get. The track's automation MODE (read, write, touch) is in the track domain.",
			{"track": track_ref}, ["track"], T.READ,
			func(a: Dictionary) -> Dictionary:
				var r := _lane_track(a["track"])
				if not r["ok"]:
					return r
				var lanes := _lanes_of(r["index"])
				var keys: Array = lanes.keys()
				keys.sort()
				var rows: Array = []
				for k in keys:
					var pts: Array = lanes[k]
					if pts.is_empty():
						continue
					var lo := INF
					var hi := -INF
					for p in pts:
						lo = minf(lo, float(p[1]))
						hi = maxf(hi, float(p[1]))
					rows.append({"target": k, "points": pts.size(), "from_seconds": _num(float(pts[0][0]), 3),
							"to_seconds": _num(float(pts[-1][0]), 3), "min": _num(lo, 3), "max": _num(hi, 3)})
				return T.ok({"track": r["index"], "mode": DAW.state.master.automation_mode if r["index"] == 0 \
						else DAW.state.track(r["index"], false).automation_mode, "lanes": rows})))

	api.add(T.make("automation_get", "One lane's points in time order: seconds, value (in the lane's units), shape. Paged by limit/offset (default 200).",
			{"track": track_ref, "target": target_p, "limit": T.int_p("points per page", 1, POINTS_MAX),
			"offset": T.int_p("skip this many", 0)}, ["track", "target"], T.READ,
			func(a: Dictionary) -> Dictionary:
				var r := _lane_track(a["track"])
				if not r["ok"]:
					return r
				var bad := _target_problem(r["index"], str(a["target"]))
				if bad != "":
					return T.fail(bad)
				var pts: Array = _lanes_of(r["index"]).get(str(a["target"]), [])
				var off := int(a.get("offset", 0))
				var lim := int(a.get("limit", POINTS_DEFAULT))
				return T.ok({"track": r["index"], "target": a["target"], "total": pts.size(), "offset": off,
						"points": _points_out(pts, off, lim)})))

	api.add(T.make("automation_set", "REPLACE a whole lane with these points (one undo step). Points are sorted by time; two at the same instant keep the later; values are clamped to the lane's range. An empty list removes the lane (like automation_clear). To add points to an existing lane use automation_add.",
			{"track": track_ref, "target": target_p, "points": points_p}, ["track", "target", "points"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var had := _existing(a)
				if had.has("error") or not had["ok"]:
					return had
				var pts: Variant = _points_in(str(a["target"]), a["points"])
				if typeof(pts) == TYPE_STRING:
					return T.fail(pts)
				if (pts as Array).is_empty() and not (had["data"] as Array).is_empty():
					return T.fail("that would delete the lane; use automation_clear (it asks the player first)")
				return _write(had["track"], str(a["target"]), pts)))

	api.add(T.make("automation_add", "Merge points into a lane: a point at the same time as an existing one replaces it, the rest are kept. Creates the lane if it is new. Same point forms as automation_set.",
			{"track": track_ref, "target": target_p, "points": points_p}, ["track", "target", "points"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var had := _existing(a)
				if had.has("error") or not had["ok"]:
					return had
				var add: Variant = _points_in(str(a["target"]), a["points"])
				if typeof(add) == TYPE_STRING:
					return T.fail(add)
				var merged: Array = []
				for p in (had["data"] as Array):
					merged.append([float(p[0]), float(p[1]), int(p[2])])
				for p in (add as Array):
					var done := false
					for m in merged:
						if is_equal_approx(m[0], p[0]):
							m[1] = p[1]
							m[2] = p[2]
							done = true
					if not done:
						merged.append(p)
				merged.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
				return _write(had["track"], str(a["target"]), merged)))

	api.add(T.make("automation_remove_points", "Remove the points of a lane that lie between from_seconds and to_seconds (inclusive), keeping the rest. Removing every point removes the lane (the player confirms that, see automation_clear).",
			{"track": track_ref, "target": target_p, "from_seconds": T.num_p("start of the span, seconds", 0.0),
			"to_seconds": T.num_p("end of the span, seconds", 0.0)}, ["track", "target", "from_seconds", "to_seconds"], T.EDIT,
			func(a: Dictionary) -> Dictionary:
				var had := _existing(a)
				if had.has("error") or not had["ok"]:
					return had
				var keep: Array = []
				for p in (had["data"] as Array):
					if float(p[0]) < float(a["from_seconds"]) - 0.0000001 or float(p[0]) > float(a["to_seconds"]) + 0.0000001:
						keep.append([float(p[0]), float(p[1]), int(p[2])])
				if keep.is_empty() and not (had["data"] as Array).is_empty():
					return T.fail("that removes every point; use automation_clear to remove the whole lane")
				return _write(had["track"], str(a["target"]), keep)))

	api.add(T.make("automation_clear", "Take a whole lane of automation away (the control then holds its current value). The player confirms first.",
			{"track": track_ref, "target": target_p}, ["track", "target"], T.DESTRUCTIVE,
			func(a: Dictionary) -> Dictionary:
				var had := _existing(a)
				if had.has("error") or not had["ok"]:
					return had
				if (had["data"] as Array).is_empty():
					return T.ok({"cleared": 0, "note": "there was no such lane"})
				var n := (had["data"] as Array).size()
				var r := _write(had["track"], str(a["target"]), [])
				if r["ok"]:
					r["data"]["cleared"] = n
				return r))


## {ok, track, data: the lane's points so far} for a track and target argument, or an error.
static func _existing(a: Dictionary) -> Dictionary:
	var r := _lane_track(a["track"])
	if not r["ok"]:
		return r
	var bad := _target_problem(r["index"], str(a["target"]))
	if bad != "":
		return T.fail(bad)
	return {"ok": true, "track": r["index"], "data": _lanes_of(r["index"]).get(str(a["target"]), [])}


static func _write(track_index: int, target: String, points: Array) -> Dictionary:
	DAW.set_automation(track_index, target, points)
	var now: Array = _lanes_of(track_index).get(target, [])
	return T.ok({"track": track_index, "target": target, "points": now.size()})


# --- look ---------------------------------------------------------------------------------------

static func _register_look(api: ControlApi) -> void:
	api.add(T.make("look_levels", "Level meters now, per track and the master: vu_l / vu_r are the DAW's peak meter, 0..1 on the fader's scale (not dB), and the track's fader volume_db, mute and solo. With signal true each track also gets its signal-graph readings where the DAW measures them (the built-in engine): peak/rms in dBFS at its input and after each plugin, gain reduction in dB, the peak each send carries; null means silence or not measured. Paged by limit/offset over tracks (default 32); track narrows to one.",
			{"track": T.ref_p("only this track"), "signal": T.bool_p("include the per-plugin signal-graph peaks (default false)"),
			"limit": T.int_p("tracks per page (default 32)", 1, 200), "offset": T.int_p("skip this many tracks", 0)}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				var st := DAW.state
				var m := st.master
				var out := {"master": {"vu_l": _num(m.vu_l, 3), "vu_r": _num(m.vu_r, 3), "volume_db": _num(m.volume_db)}}
				var idx: Array = st.track_indices()
				if a.has("track"):
					var r := ControlRefs.track(st, a["track"])
					if not r["ok"]:
						return r
					idx = [r["index"]]
				var off := int(a.get("offset", 0))
				var lim := int(a.get("limit", 32))
				var rows: Array = []
				for i in idx.slice(off, off + lim):
					rows.append(_level_row(st.track(i, false), bool(a.get("signal", false))))
				out["tracks"] = rows
				out["total_tracks"] = idx.size()
				out["playing"] = st.playing
				return T.ok(out)))

	api.add(T.make("look_loudness", "The master's loudness, where the DAW measures it (the built-in engine does, Reaper does not): momentary / short-term / integrated LUFS, true peak (dBTP) overall and over the last 3 s, left-right correlation (-1..1) and how many seconds were measured. `measured` false means the figures mean nothing. null is silence. Use transport/reset_loudness elsewhere to restart the integration.",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var m := DAW.state.master
				if not m.loudness_measured:
					return T.ok({"measured": false})
				return T.ok({"measured": true, "lufs_momentary": _num(m.lufs_m, 1), "lufs_short_term": _num(m.lufs_s, 1),
						"lufs_integrated": _num(m.lufs_i, 1), "true_peak_db": _num(m.true_peak_db, 1),
						"true_peak_recent_db": _num(m.true_peak_recent_db, 1), "correlation": _num(m.correlation, 2),
						"seconds": _num(m.loudness_seconds, 1)})))

	api.add(T.make("look_transport", "Where the song is: playing, recording, the playhead in seconds and as the DAW spells it (bar.beat.hundredths), tempo in bpm, time signature, loop on and its span in seconds, metronome, the project's length in seconds.",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var st := DAW.state
				return T.ok({"playing": st.playing, "recording": st.recording, "position_seconds": _num(st.position_seconds, 3),
						"position": st.position_string, "time": st.time_string, "tempo_bpm": _num(st.tempo, 2),
						"time_signature": "%d/%d" % [st.beats_per_bar, st.beat_unit], "looping": st.looping,
						"loop_start_seconds": _num(st.loop_start, 3), "loop_end_seconds": _num(st.loop_end, 3),
						"metronome": st.metronome, "project_length_seconds": _num(st.project_length, 2),
						"punch": st.punch, "count_in_bars": st.count_in_bars})))

	api.add(T.make("look_where", "Where the player is and what room they are in: the venue, the station last gone to, the head position in the room (metres), whether this machine hosts or is a guest, the player's name and how many people are in the session. Needs the running game; in a bare suite it says only what the session knows.",
			{}, [], T.READ,
			func(_a: Dictionary) -> Dictionary:
				var out := {"is_authority": Session.is_authority(), "name": Session.local_name,
						"people": Session.participants.size()}
				var room: Dictionary = Session.room if Session.room is Dictionary else {}
				if room.has("venue"):
					out["room_venue"] = str(room["venue"])
				var studio := api.studio
				if studio == null:
					out["studio"] = false
					return T.ok(out)
				out["studio"] = true
				if studio.get("venue") != null:
					out["venue"] = str((studio.get("venue") as Object).get("id")) if (studio.get("venue") as Object).get("id") != null else ""
				if studio.get("station") != null:
					out["station"] = str(studio.get("station"))
				var rig: Variant = studio.get("rig")
				if rig is Node3D:
					var head: Variant = (rig as Object).get("head")
					var at: Vector3 = (head as Node3D).global_position if head is Node3D else (rig as Node3D).global_position
					out["position"] = {"x": _num(at.x), "y": _num(at.y), "z": _num(at.z)}
					out["heading_degrees"] = _num(rad_to_deg((head as Node3D).global_rotation.y if head is Node3D else (rig as Node3D).global_rotation.y), 1)
				return T.ok(out)))

	api.add(T.make("look_screenshot", "Take a picture of what the player sees now (the game's viewport) and save it as a PNG; returns its path (under user://, and the real file path) and size. Fails where there is no window (a headless run).",
			{"max_width": T.int_p("shrink to at most this wide (default 1280)", 64, 4096)}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				if DisplayServer.get_name() == "headless":
					return T.fail("there is no window to take a picture of (the game runs headless)")
				var loop := Engine.get_main_loop()
				var vp: Viewport = (loop as SceneTree).root.get_viewport() if loop is SceneTree else null
				if vp == null:
					return T.fail("there is no viewport to take a picture of")
				var tex := vp.get_texture()
				var img: Image = tex.get_image() if tex != null else null
				if img == null or img.is_empty():
					return T.fail("the viewport has nothing drawn yet")
				var maxw := int(a.get("max_width", 1280))
				if img.get_width() > maxw:
					img.resize(maxw, int(float(maxw) * img.get_height() / img.get_width()))
				DirAccess.make_dir_recursive_absolute("user://control_shots")
				var path := "user://control_shots/shot_%d.png" % Time.get_ticks_msec()
				var err := img.save_png(path)
				if err != OK:
					return T.fail("could not save the picture (error %d)" % err)
				return T.ok({"path": path, "file": ProjectSettings.globalize_path(path),
						"width": img.get_width(), "height": img.get_height()})))


static func _level_row(t: MixState.TrackState, with_signal: bool) -> Dictionary:
	var row := {"number": t.index, "name": t.name, "vu_l": _num(t.vu_l, 3), "vu_r": _num(t.vu_r, 3),
			"volume_db": _num(t.volume_db), "mute": t.mute, "solo": t.solo}
	if with_signal:
		if t.meter_peak.is_empty():
			row["signal"] = null
		else:
			var chain := t.plugins()
			var stages: Array = [{"at": "input", "peak_db": _num(t.meter_peak[0]),
					"rms_db": _num(t.meter_rms[0]) if t.meter_rms.size() > 0 else null}]
			for k in chain.size():
				var s := {"at": "after #%d %s" % [chain[k], MixState.FXState.bare_name((t.fx[chain[k]] as MixState.FXState).name)]}
				s["peak_db"] = _num(t.meter_peak[k + 1]) if t.meter_peak.size() > k + 1 else null
				s["rms_db"] = _num(t.meter_rms[k + 1]) if t.meter_rms.size() > k + 1 else null
				if t.meter_gr.size() > k:
					s["gain_reduction_db"] = _num(t.meter_gr[k])
				stages.append(s)
			var sends: Array = []
			for k in t.meter_sends.size():
				sends.append(_num(t.meter_sends[k]))
			row["signal"] = {"stages": stages, "send_peaks_db": sends}
	return row
