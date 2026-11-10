class_name ControlApi
extends RefCounted

## The control API (docs/mcp_assistant.md): every tool the game offers to a client (an MCP server over HTTP,
## the in-game assistant, the suite), the rules every call goes through, and the change sets that let a turn be
## taken back.
##
## A call is `invoke(name, args, who)`: the arguments are checked against the tool's schema, a tier 2 tool
## waits for a person (`confirm`), the handler runs as `who` (a peer id, 0 for this machine) through the verbs the
## controls use, and everything it changed is one change set. `batch` is a list of calls that is one change set.
## Nothing here knows a domain: `ControlTools.register_all` puts them in.

## A change set ended: the assistant's panel and the server's log show it.
signal change_set_made(entry: Dictionary)

const HISTORY_MAX := 60
## The most calls one batch may hold.
const BATCH_MAX := 400

var tools: Dictionary = {}
## The studio the tools reach the room and the rack through; null in a suite that needs none.
var studio: Node
## (tool_name, args, who) -> bool or a coroutine giving one: whether the person agrees to a tier 2 call. Unset
## means a tier 2 call is refused (nobody to ask).
var confirm := Callable()
## Change sets, oldest first: {id, who, at, calls: [{tool, args, ok}], daw_depth, snapshots, undone}.
var history: Array = []
## Things that can be put back apart from the DAW's own undo: {name, snap: Callable() -> Variant, restore: Callable(Variant)}.
var snapshotters: Array = []
var _next_id := 1
var _open: Dictionary = {}


func add(tool: ControlTool) -> void:
	assert(not tools.has(tool.name), "control tool registered twice: " + tool.name)
	tools[tool.name] = tool


func has(tool_name: String) -> bool:
	return tools.has(tool_name)


func domains() -> PackedStringArray:
	var out := PackedStringArray()
	for t: ControlTool in tools.values():
		if t.domain not in out:
			out.append(t.domain)
	out.sort()
	return out


## The `tools/list` rows, for `only` domains (all when empty).
func describe(only: PackedStringArray = PackedStringArray()) -> Array:
	var names := tools.keys()
	names.sort()
	var out: Array = []
	for n in names:
		var t: ControlTool = tools[n]
		if only.is_empty() or t.domain in only:
			out.append(t.describe())
	return out


## Tools whose name or summary has every word of `query`, in a domain if given: for a client that does not want
## to carry two hundred schemas.
func search(query: String, domain := "") -> Array:
	var words := query.to_lower().split(" ", false)
	var out: Array = []
	var names := tools.keys()
	names.sort()
	for n in names:
		var t: ControlTool = tools[n]
		if domain != "" and t.domain != domain:
			continue
		var hay := (t.name + " " + t.summary).to_lower()
		var all := true
		for w in words:
			if not hay.contains(w):
				all = false
				break
		if all:
			out.append({"name": t.name, "summary": t.summary, "tier": t.tier})
	return out


# --- calls --------------------------------------------------------------------------------------

## One call, as a coroutine (a tier 2 call waits for a person): `await api.call_tool(...)`.
func call_tool(tool_name: String, args: Dictionary = {}, who := 0) -> Dictionary:
	var t: ControlTool = tools.get(tool_name)
	if t == null:
		return ControlTool.fail("no tool called '%s'" % tool_name)
	if t.tier == ControlTool.DESTRUCTIVE:
		var yes: bool = await _asked(tool_name, args, who)
		if not yes:
			return ControlTool.fail("the player did not confirm %s; nothing was changed" % tool_name)
	return invoke(tool_name, args, who, true)


## A call that does not wait: tier 0 and 1 tools, and tier 2 ones when `confirmed` (the caller has asked). The
## suite and the batch use it.
func invoke(tool_name: String, args: Dictionary = {}, who := 0, confirmed := false) -> Dictionary:
	var t: ControlTool = tools.get(tool_name)
	if t == null:
		return ControlTool.fail("no tool called '%s'" % tool_name)
	if t.tier == ControlTool.DESTRUCTIVE and not confirmed:
		return ControlTool.fail("%s is destructive and needs the player's confirmation" % tool_name)
	var bad := t.check(args)
	if not bad.is_empty():
		return ControlTool.fail("%s: %s" % [tool_name, "; ".join(PackedStringArray(bad))])
	var own := _open.is_empty() and t.tier != ControlTool.READ
	if own:
		_begin(who)
	var box: Array = [{}]
	var run := func() -> void: box[0] = t.handler.call(args)
	if Engine.get_main_loop() != null and who != 0 and t.tier != ControlTool.READ:
		DAW.on_behalf_of(who, run)
	else:
		run.call()
	var result: Variant = box[0]
	if typeof(result) != TYPE_DICTIONARY or not result.has("ok"):
		result = ControlTool.fail("%s returned no result" % tool_name)
	if t.tier != ControlTool.READ:
		_record(tool_name, args, bool(result["ok"]))
	if own:
		_end()
	return result


## Several calls as one change set, in order. Stops at the first that fails unless `keep_going`. Tier 2 calls in it
## are confirmed once, together, before any runs.
func batch(calls: Array, who := 0, keep_going := false) -> Dictionary:
	return await _batch(calls, who, keep_going)


func _batch(calls: Array, who: int, keep_going: bool) -> Dictionary:
	if calls.size() > BATCH_MAX:
		return ControlTool.fail("a batch holds at most %d calls" % BATCH_MAX)
	var destructive: Array[String] = []
	for c in calls:
		if typeof(c) != TYPE_DICTIONARY or not c.has("tool"):
			return ControlTool.fail("each call is {tool, args}")
		var t: ControlTool = tools.get(str(c["tool"]))
		if t == null:
			return ControlTool.fail("no tool called '%s'" % str(c["tool"]))
		if t.name == "batch":
			return ControlTool.fail("a batch cannot hold a batch")
		if t.tier == ControlTool.DESTRUCTIVE:
			destructive.append(t.name)
	if not destructive.is_empty():
		var yes: bool = await _asked(", ".join(PackedStringArray(destructive)), {"calls": calls.size()}, who)
		if not yes:
			return ControlTool.fail("the player did not confirm %s; nothing was changed" % ", ".join(PackedStringArray(destructive)))
	_begin(who)
	var results: Array = []
	var failed := 0
	for c in calls:
		var args: Dictionary = c.get("args", {})
		var r := invoke(str(c["tool"]), args, who, true)
		results.append(r)
		if not r["ok"]:
			failed += 1
			if not keep_going:
				break
	var made := _end()
	return ControlTool.ok({"results": results, "ran": results.size(), "failed": failed, "change_set": made.get("id", 0)})


func _asked(tool_name: String, args: Dictionary, who: int) -> bool:
	if not confirm.is_valid():
		return false
	var r: Variant = await confirm.call(tool_name, args, who)
	return bool(r)


# --- change sets --------------------------------------------------------------------------------

func _begin(who: int) -> void:
	var depth := -1
	if DAW != null and DAW.state != null:
		depth = DAW.state.undo_depth
	var snaps := {}
	for s: Dictionary in snapshotters:
		snaps[s["name"]] = s["snap"].call()
	_open = {"id": _next_id, "who": who, "at": Time.get_unix_time_from_system(), "calls": [],
			"daw_depth": depth, "snapshots": snaps, "undone": false}
	_next_id += 1


func _record(tool_name: String, args: Dictionary, was_ok: bool) -> void:
	if _open.is_empty():
		return
	_open["calls"].append({"tool": tool_name, "args": args, "ok": was_ok})


func _end() -> Dictionary:
	var made := _open
	_open = {}
	if made.is_empty() or made["calls"].is_empty():
		return {}
	history.append(made)
	while history.size() > HISTORY_MAX:
		history.pop_front()
	change_set_made.emit(made)
	return made


func change_set(id: int) -> Dictionary:
	for c: Dictionary in history:
		if c["id"] == id:
			return c
	return {}


## Take back change set `id` (the last one that is not already undone when 0): the DAW back to where it was, and
## whatever else has a snapshotter. Only the newest not-yet-undone set may be undone, because a DAW undo depth
## and a patch snapshot are only true of the moment before it. Says what it did.
func undo(id := 0) -> Dictionary:
	var target := {}
	for i in range(history.size() - 1, -1, -1):
		if not history[i]["undone"]:
			target = history[i]
			break
	if target.is_empty():
		return ControlTool.fail("nothing to undo")
	if id != 0 and target["id"] != id:
		return ControlTool.fail("only the newest change set (%d) can be undone; later ones first" % target["id"])
	if int(target["daw_depth"]) >= 0 and DAW != null:
		DAW.undo_to(int(target["daw_depth"]))
	for s: Dictionary in snapshotters:
		if target["snapshots"].has(s["name"]):
			s["restore"].call(target["snapshots"][s["name"]])
	target["undone"] = true
	return ControlTool.ok({"undone": target["id"], "calls": target["calls"].size()})
