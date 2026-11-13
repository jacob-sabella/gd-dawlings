class_name ControlTools
extends RefCounted

## Puts every domain's tools into a ControlApi, and the few tools that are about the API itself: `batch`,
## `tools_search`, `changes_list`, `changes_undo`. A domain is one file, `core/control/tools_<domain>.gd`, with a
## `static func register(api: ControlApi) -> void`; add a new one to DOMAINS.

const DOMAINS := [
	preload("res://core/control/tools_project.gd"),
	preload("res://core/control/tools_track.gd"),
	preload("res://core/control/tools_fx.gd"),
	preload("res://core/control/tools_item.gd"),
	preload("res://core/control/tools_rack.gd"),
	preload("res://core/control/tools_room.gd"),
	preload("res://core/control/tools_mods.gd"),
	preload("res://core/control/tools_requests.gd"),
]


static func make_api(studio: Node = null) -> ControlApi:
	var api := ControlApi.new()
	api.studio = studio
	register_all(api)
	return api


static func register_all(api: ControlApi) -> void:
	_meta(api)
	for d in DOMAINS:
		d.register(api)


static func _meta(api: ControlApi) -> void:
	var T := ControlTool
	api.add(T.make("batch", "Run several tool calls in order as ONE change set (one undo). Use it for anything of more than a few calls: a whole patch, a set of fader moves. Stops at the first failure unless keep_going.",
			{"calls": T.arr_p("each {tool: string, args: object}", {"type": "object"}), "keep_going": T.bool_p("carry on after a failed call")},
			["calls"], T.EDIT, func(_a: Dictionary) -> Dictionary: return T.fail("batch is run by the server, not as a plain call")))
	api.add(T.make("tools_search", "Find tools by words in their name or summary, optionally in one domain. Domains: project, transport, track, mix, fx, item, note, automation, rack, room, mods, look, help, requests, changes.",
			{"query": T.str_p("words, all of which must match"), "domain": T.str_p("only this domain")}, [], T.READ,
			func(a: Dictionary) -> Dictionary: return T.ok(api.search(str(a.get("query", "")), str(a.get("domain", ""))))))
	api.add(T.make("changes_list", "The change sets made so far (each tool call that changes something, or each batch): id, who, calls, whether undone.",
			{"limit": T.int_p("newest this many", 1, 60)}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				var out: Array = []
				var n := int(a.get("limit", 20))
				for i in range(api.history.size() - 1, maxi(api.history.size() - 1 - n, -1), -1):
					var c: Dictionary = api.history[i]
					out.append({"id": c["id"], "who": c["who"], "undone": c["undone"], "at": c["at"],
							"calls": c["calls"].map(func(x: Dictionary) -> String: return "%s%s" % [x["tool"], "" if x["ok"] else " (failed)"])})
				return T.ok(out)))
	api.add(T.make("changes_undo", "Take back the newest change set that is not already undone (the DAW back to where it was, and the rack's patch). Pass id to say which, it must be the newest.",
			{"id": T.int_p("the change set's id")}, [], T.EDIT,
			func(a: Dictionary) -> Dictionary: return api.undo(int(a.get("id", 0)))))
