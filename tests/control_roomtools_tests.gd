extends RefCounted

## The control API's room tools (docs/mcp_assistant.md), called from tests/run_tests.gd's `_test_control_room`.
## No studio here: what is checked is the verb coverage, that every tool's arguments become the verb's typed list
## the host receives (observed on `Session.room_asked`), that bad arguments are refused, and the tiers.

const Tools := preload("res://core/control/tools_room.gd")

var t: Node
var api: ControlApi
var asked: Array = []


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _record(verb: StringName, args: Array, _from: int) -> void:
	asked.append([verb, args])


## Call `tool` with `args`; the verb and args that reached the host, or [] when none did.
func _through(tool_name: String, args: Dictionary) -> Array:
	asked.clear()
	var r := _call(tool_name, args, true)
	if not r["ok"] or asked.is_empty():
		return []
	return asked[0]


## The tool as ControlApi.invoke runs it: its schema checks the arguments, then its handler answers. (Not through
## `invoke` itself, whose `result` is assigned in a lambda that captures it by value, so it returns "no result".)
func _call(tool_name: String, args: Dictionary = {}, confirmed := false) -> Dictionary:
	var tool: ControlTool = api.tools[tool_name]
	if tool.tier == ControlTool.DESTRUCTIVE and not confirmed:
		return ControlTool.fail("needs confirmation")
	var bad := tool.check(args)
	if not bad.is_empty():
		return ControlTool.fail("; ".join(PackedStringArray(bad)))
	return tool.handler.call(args)


func run() -> void:
	api = ControlApi.new()
	Tools.register(api)
	Session.room_asked.connect(_record)

	_coverage()
	_naming()
	_conversion()
	_refusals()
	_tiers()

	Session.room_asked.disconnect(_record)


func _coverage() -> void:
	var exposed: Array = Tools.EXPOSED.keys()
	var not_exposed: Array = Tools.NOT_EXPOSED.keys()
	var all: Array = Session.ROOM_VERBS.keys()
	var overlap := exposed.filter(func(v: Variant) -> bool: return v in not_exposed)
	check("no verb is both exposed and left out", overlap.is_empty())
	var missing := all.filter(func(v: Variant) -> bool: return v not in exposed and v not in not_exposed)
	check("every room verb is exposed or listed as not (undecided: %s)" % str(missing), missing.is_empty())
	var stale := (exposed + not_exposed).filter(func(v: Variant) -> bool: return v not in all)
	check("nothing is listed that is not a room verb (%s)" % str(stale), stale.is_empty())
	var tools_ok := true
	for v in exposed:
		if not api.has(Tools.EXPOSED[v]):
			tools_ok = false
			print("  missing tool for ", v)
	check("each exposed verb has its tool registered", tools_ok)
	var reasons := true
	for v in not_exposed:
		reasons = reasons and str(Tools.NOT_EXPOSED[v]).length() > 10
	check("each left-out verb says why", reasons)
	check("looper_layer is not exposed", &"looper_layer" in not_exposed and not api.has("room_looper_layer"))


func _naming() -> void:
	var good := true
	for n in api.tools:
		var tool: ControlTool = api.tools[n]
		good = good and tool.domain == "room" and tool.summary.length() > 30
	check("every tool is room_* with a summary", good)
	for n in ["room_get", "room_venue_list", "room_venue_set", "room_layout_get", "room_layout_set", "room_layout_list",
			"room_layout_save", "room_pieces_list", "room_items_list", "room_tablets_list"]:
		check("%s is registered" % n, api.has(n))


func _same(got: Array, verb: StringName, args: Array) -> bool:
	if got.size() != 2 or got[0] != verb or got[1].size() != args.size():
		return false
	for i in args.size():
		if typeof(got[1][i]) != typeof(args[i]) or not is_same(got[1][i], args[i]) and got[1][i] != args[i]:
			return false
	return true


func _conversion() -> void:
	check("on_air asks on_air [bool]", _same(_through("room_on_air", {"on": true}), &"on_air", [true]))
	check("room_tv converts a whole second to a float", _same(_through("room_tv", {"video": "a", "playing": true, "seconds": 3}), &"tv", ["a", true, 3.0]))
	check("room_tv defaults the position", _same(_through("room_tv", {"video": "a", "playing": false}), &"tv", ["a", false, 0.0]))
	check("move_piece: a StringName and floats", _same(_through("room_piece_move", {"piece": "rack", "x": 1, "z": 2, "yaw": 0}), &"move_piece", [&"rack", 1.0, 2.0, 0.0]))
	check("tablet move", _same(_through("room_tablet_move", {"tablet": "tablet_1", "x": 0.5, "z": -1, "yaw": 1.5}), &"move_tablet", [&"tablet_1", 0.5, -1.0, 1.5]))
	check("tablet close", _same(_through("room_tablet_close", {"tablet": "tablet_1"}), &"close_tablet", [&"tablet_1"]))
	var got := _through("room_surface_place", {"surface": "console", "x": 1, "y": 0.5, "z": 2, "yaw": 0})
	check("place_surface gives a Transform3D at the point", got.size() == 2 and got[0] == &"place_surface"
			and got[1][1] is Transform3D and (got[1][1] as Transform3D).origin.is_equal_approx(Vector3(1, 0.5, 2)))
	check("put_item: x, z, yaw", _same(_through("room_item_put", {"item": "duck", "x": 1, "z": 2}), &"put_item", [&"duck", 1.0, 2.0, 0.0]))
	check("home_item", _same(_through("room_item_home", {"item": "duck"}), &"home_item", [&"duck"]))
	got = _through("room_item_throw", {"item": "ball", "origin": [0, 1, 0], "velocity": [1, 2, 3]})
	check("throw_item gives three Vector3s, spin none", got.size() == 2 and got[0] == &"throw_item" and got[1][1] == Vector3(0, 1, 0)
			and got[1][2] == Vector3(1, 2, 3) and got[1][3] == Vector3.ZERO)
	check("wear_item", _same(_through("room_item_wear", {"item": "headphones", "on": true}), &"wear_item", [&"headphones", true]))
	check("pocket_item", _same(_through("room_item_pocket", {"item": "duck", "pocket": -1}), &"pocket_item", [&"duck", -1]))
	check("give", _same(_through("room_item_give", {"item": "duck", "to": 5}), &"give", [&"duck", 5]))
	check("slot_item", _same(_through("room_item_slot", {"item": "c", "holder": "cassette_rack", "slot": 2}), &"slot_item", [&"c", &"cassette_rack", 2]))
	check("take_personal", _same(_through("room_take_personal", {"kind": "mic"}), &"take_personal", [&"mic"]))
	check("board_source empty is allowed", _same(_through("room_board_source", {"source": ""}), &"board_source", [&""]))
	check("patch a known socket", _same(_through("room_patch", {"receiver": 1, "socket": "mix"}), &"patch", [1, &"mix"]))
	check("patch unplug", _same(_through("room_patch", {"receiver": 0, "socket": ""}), &"patch", [0, &""]))
	check("plug", _same(_through("room_plug", {"source": "a", "sink": ""}), &"plug", [&"a", &""]))
	check("harmony counts bars from 1", _same(_through("room_harmony", {"bar": 1, "key": "C major"}), &"harmony", [0, "C major"]))
	check("rope is Strings and bools", _same(_through("room_rope", {"table": "stage", "tied": true}), &"rope", ["stage", true, false]))
	check("sampler", _same(_through("room_sampler", {"armed": true}), &"sampler", [true]))
	check("weather", _same(_through("room_weather", {"listening": false}), &"weather", [false]))
	got = _through("room_scratch", {"cassette": "c", "path": [0, 0.5, 1]})
	check("scratch path is a PackedFloat32Array", got.size() == 2 and got[1][1] is PackedFloat32Array and (got[1][1] as PackedFloat32Array).size() == 3)
	check("looper arm", _same(_through("room_looper", {"action": "arm", "from_bar": -1, "bars": 4}), &"looper", [-1, 4]))
	check("looper clear", _same(_through("room_looper", {"action": "clear"}), &"looper", [0, 0]))
	check("layout move with a heading", _same(_through("room_layout_edit", {"op": "move", "piece": "rack", "x": 1, "z": 2, "yaw": 0.5}), &"layout", [&"move", ["rack", 1.0, 2.0, 0.5]]))
	check("layout add by kind", _same(_through("room_layout_edit", {"op": "add", "piece": "hoop"}), &"layout", [&"add", ["hoop"]]))
	check("layout reset all", _same(_through("room_layout_edit", {"op": "reset", "piece": "all"}), &"layout", [&"reset", ["all"]]))
	var ok := _call("room_on_air", {"on": false})
	check("a solo ask answers ok and says which verb", ok["ok"] and ok["data"]["asked"] == "on_air")


func _refusals() -> void:
	check("a missing argument is refused", not _call("room_piece_move", {"piece": "rack"})["ok"])
	check("an unknown argument is refused", not _call("room_on_air", {"on": true, "loud": 1})["ok"])
	check("the wrong type is refused", not _call("room_on_air", {"on": "yes"})["ok"])
	check("an enum is held to", not _call("room_looper", {"action": "spin"})["ok"])
	check("a range is held to", not _call("room_patch", {"receiver": 9, "socket": "mix"})["ok"])
	asked.clear()
	check("a socket that does not exist is refused", not _call("room_patch", {"receiver": 0, "socket": "nonsense"})["ok"] and asked.is_empty())
	check("a bad vector is refused", not _call("room_item_throw", {"item": "b", "origin": [1, 2], "velocity": [0, 0, 0]})["ok"] and asked.is_empty())
	check("move without a place is refused", not _call("room_layout_edit", {"op": "move", "piece": "rack"})["ok"] and asked.is_empty())
	check("arm without bars is refused", not _call("room_looper", {"action": "arm"})["ok"] and asked.is_empty())
	check("reads that need the studio say so", _call("room_pieces_list")["error"].contains("studio"))
	check("the venue cannot be set without a studio", not _call("room_venue_set", {"venue": "studio"})["ok"])
	check("room_layout_get fails clearly without a studio", not _call("room_layout_get")["ok"])
	check("room_venue_list works without a studio", _call("room_venue_list")["ok"])
	var r := _call("room_get")
	check("room_get works without a studio", r["ok"] and r["data"].has("here"))
	# A refusal the host tells the asker (Session.tell) comes back as the error.
	var told := func(_v: StringName, _a: Array, _f: int) -> void: Session.notice.emit("Not now.")
	Session.room_asked.connect(told)
	var refused := _call("room_on_air", {"on": true})
	Session.room_asked.disconnect(told)
	check("the host's own words come back as the error", not refused["ok"] and refused["error"] == "Not now.")


func _tiers() -> void:
	check("replacing the whole layout is destructive", (api.tools["room_layout_set"] as ControlTool).tier == ControlTool.DESTRUCTIVE)
	check("destructive is refused unconfirmed", not _call("room_layout_set", {"delta": {}})["ok"])
	for n in ["room_get", "room_venue_list", "room_layout_get", "room_layout_list", "room_pieces_list", "room_items_list", "room_tablets_list"]:
		check("%s only reads" % n, (api.tools[n] as ControlTool).tier == ControlTool.READ)
	check("room_on_air edits", (api.tools["room_on_air"] as ControlTool).tier == ControlTool.EDIT)
