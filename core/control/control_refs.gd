class_name ControlRefs
extends RefCounted

## Turning what a client says into what the game holds: "Kick" or "#3" or 3 into a track's index. The tools take
## names and numbers (ControlTool.ref_p) and never make a client work out an index; a name that two tracks share,
## or that none has, is an error that says what to say instead.

## Track `ref` in `state` (a MixState): {ok: true, index} or {ok: false, error}.
static func track(state: MixState, ref: Variant) -> Dictionary:
	if state == null:
		return ControlTool.fail("there is no project")
	if typeof(ref) == TYPE_INT or typeof(ref) == TYPE_FLOAT:
		return _by_index(state, int(ref))
	var s := str(ref).strip_edges()
	if s.begins_with("#") and s.substr(1).is_valid_int():
		return _by_index(state, int(s.substr(1)))
	var hits: Array = []
	for i in state.track_indices():
		if state.track(i, false).name.to_lower() == s.to_lower():
			hits.append(i)
	if hits.size() == 1:
		return {"ok": true, "index": hits[0]}
	if hits.is_empty():
		return ControlTool.fail("no track called '%s'; the tracks are: %s" % [s, names(state)])
	return ControlTool.fail("%d tracks are called '%s' (numbers %s); say '#<number>'" % [hits.size(), s, ", ".join(PackedStringArray(hits.map(func(i: int) -> String: return str(i))))])


static func _by_index(state: MixState, i: int) -> Dictionary:
	if state.track_indices().has(i):
		return {"ok": true, "index": i}
	return ControlTool.fail("no track number %d; the tracks are: %s" % [i, names(state)])


## "1 Kick, 2 Snare, ...", capped, for an error.
static func names(state: MixState) -> String:
	var out := PackedStringArray()
	for i in state.track_indices():
		out.append("#%d %s" % [i, state.track(i, false).name])
		if out.size() >= 24:
			out.append("...")
			break
	return ", ".join(out)
