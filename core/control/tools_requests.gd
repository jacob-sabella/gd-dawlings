extends RefCounted

## Control tools: requests. The assistant writes down what the players asked for that the game cannot do yet (a
## feature, a bug, an idea), so a developer can read it later and build it. One Markdown file on the host's machine,
## `user://feature_requests.md` (on Linux ~/.local/share/godot/app_userdata/dawlings/feature_requests.md), an entry
## appended per request: when, who, the kind, a title, what they want and why, and their own words. Nothing else is
## written and nothing is sent anywhere.

const FILE := "user://feature_requests.md"
const TITLE_MAX := 120
const DETAILS_MAX := 4000
const ASKED_MAX := 1000
## A file this big takes no more (a guard against a run that loops).
const FILE_MAX := 1048576
const KINDS := ["feature", "bug", "idea"]
const HEAD := "# Feature requests\n\nWritten by the in-game assistant (`requests_add`) when a player asks for something the game does not do. Newest last.\n"

## The suite points this at a scratch file.
static var path_override := ""


static func path() -> String:
	return path_override if path_override != "" else FILE


static func register(api: ControlApi) -> void:
	api.add(ControlTool.make("requests_add",
			"Write down a feature request, bug or idea for the game's developers, in a file on the host's machine that they read later. Use it when the player asks for something the game cannot do (after checking with tools_search that it really cannot), says something is broken, or asks you to note a request. Give a short title, what they want and why in plain words (enough for a developer who was not there), and their own words. Then tell them it is noted. Check requests_list first so the same request is not written twice.",
			{"title": ControlTool.str_p("a short title, e.g. 'Undo for the rack's TIDY UP'"),
			"details": ControlTool.str_p("what they want, why, and anything you found (which tools fall short, what happened)"),
			"kind": ControlTool.str_p("feature (the default), bug or idea", KINDS),
			"asked": ControlTool.str_p("the player's own words, quoted")},
			["title", "details"], ControlTool.EDIT, _add))
	api.add(ControlTool.make("requests_list",
			"The requests already written down (newest first): when, who, kind and title. To avoid writing one twice.",
			{"limit": ControlTool.int_p("at most this many (default 30)", 1, 200)}, [], ControlTool.READ, _list))


static func _add(a: Dictionary) -> Dictionary:
	var title := _one_line(str(a.get("title", ""))).left(TITLE_MAX)
	var details := str(a.get("details", "")).strip_edges().left(DETAILS_MAX)
	if title == "" or details == "":
		return ControlTool.fail("a request needs a title and details")
	var kind := str(a.get("kind", "feature"))
	if kind not in KINDS:
		kind = "feature"
	var asked := _one_line(str(a.get("asked", ""))).left(ASKED_MAX)
	var p := path()
	var had := FileAccess.file_exists(p)
	if had and FileAccess.open(p, FileAccess.READ).get_length() > FILE_MAX:
		return ControlTool.fail("the requests file is full (over 1 MB): ask the host to read and clear it")
	var f := FileAccess.open(p, FileAccess.READ_WRITE if had else FileAccess.WRITE)
	if f == null:
		return ControlTool.fail("the requests file could not be opened (%s)" % error_string(FileAccess.get_open_error()))
	if not had:
		f.store_string(HEAD)
	f.seek_end()
	var who := _who()
	var when := Time.get_datetime_string_from_system(false, true)
	var entry := "\n## %s · %s · %s\n\n**%s**\n\n%s\n" % [when, kind, who, title, details]
	if asked != "":
		entry += "\n> %s\n" % asked
	f.store_string(entry)
	f.close()
	return ControlTool.ok({"noted": title, "kind": kind, "who": who, "at": when,
			"file": ProjectSettings.globalize_path(p).get_file()})


static func _list(a: Dictionary) -> Dictionary:
	var out: Array = []
	for e in entries():
		out.push_front(e)
	return ControlTool.ok({"requests": out.slice(0, int(a.get("limit", 30))), "count": out.size()})


## Every request in the file, oldest first: {at, kind, who, title}.
static func entries() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path()):
		return out
	var lines := FileAccess.get_file_as_string(path()).split("\n")
	for i in lines.size():
		var l := lines[i]
		if not l.begins_with("## "):
			continue
		var parts := l.substr(3).split(" · ")
		var title := ""
		for j in range(i + 1, mini(i + 4, lines.size())):
			if lines[j].begins_with("**") and lines[j].ends_with("**"):
				title = lines[j].trim_prefix("**").trim_suffix("**")
				break
		out.append({"at": parts[0] if parts.size() > 0 else "", "kind": parts[1] if parts.size() > 1 else "",
				"who": parts[2] if parts.size() > 2 else "", "title": title})
	return out


## Who is asking: the run's asker, by name.
static func _who() -> String:
	var who := ControlApi.caller
	if who == 0 or Engine.get_main_loop() == null:
		return "host"
	var n := Session.name_of(who)
	return n if n != "" else ("host" if who == Session.local_peer_id else "peer %d" % who)


## One line: no newlines and no Markdown heading or quote marks at the start, so an entry cannot break the file.
static func _one_line(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").strip_edges().lstrip("#>").strip_edges()
