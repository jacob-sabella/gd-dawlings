extends RefCounted

## The Workshop's tests (docs/workshop.md), called from tests/run_tests.gd's `_test_workshop_*`. They
## never run the real claude: tests/fixtures/fake_claude.sh prints a recorded stream-json run and does
## what it says to a throwaway git repo under user://, never this one.

const FAKE := "res://tests/fixtures/fake_claude.sh"
const OK_EVENTS := "res://tests/fixtures/workshop_stream_ok.jsonl"
const ERROR_EVENTS := "res://tests/fixtures/workshop_stream_error.jsonl"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## The stream read into progress lines: init, a read, a grep, an edit (its file kept, relative to the
## repo), a command, a test summary, a refused tool, the result with its SUMMARY and TESTS; and a run
## that ends in an error, with a line that is not JSON kept as it is.
func stream() -> void:
	var s := WorkshopStream.new("/repo")
	var lines: Array = []
	for l in FileAccess.get_file_as_string(OK_EVENTS).split("\n"):
		lines.append_array(s.feed(l))
	var kinds := lines.map(func(x: Dictionary) -> StringName: return x["kind"])
	var texts := lines.map(func(x: Dictionary) -> String: return x["text"])
	check("stream: init says the model and keeps the session id",
			kinds[0] == WorkshopStream.INIT and texts[0].contains("claude-opus-5-5") and s.session_id == "0b6f2a1e-5c1d-4c33-9f0e-1a2b3c4d5e6f")
	check("stream: an assistant's text is its first line", texts.has("I'll read the context file first."))
	check("stream: a Read says the file, relative to the repo (%s)" % [texts], texts.has("read shots/workshop/x/context.md"))
	check("stream: a Grep says its pattern", texts.has("grep TITLE_INK"))
	check("stream: an Edit says the file and keeps it", texts.has("edited core/dev/workshop_panel.gd")
			and s.files == PackedStringArray(["core/dev/workshop_panel.gd"]))
	check("stream: a Bash says its command, the repo as .", texts.any(func(x: String) -> bool: return x.begins_with("$ cd . && DAWLINGS_TESTS=_test_workshop_stream")))
	check("stream: a test summary line in a tool result is its own line, and kept",
			texts.has("12 checks, 0 failed") and s.test_lines.has("12 checks, 0 failed"))
	check("stream: a refused tool says so", lines.any(func(x: Dictionary) -> bool:
			return x["kind"] == WorkshopStream.FAILED and str(x["text"]).begins_with("Bash refused: Permission")))
	check("stream: the result is its SUMMARY line, done, not an error, with its cost and turns",
			kinds[-1] == WorkshopStream.RESULT and texts[-1] == "the Workshop panel's title is a warm amber"
			and s.done and not s.is_error and is_equal_approx(s.cost_usd, 0.0412) and s.turns == 6)
	check("stream: TESTS names the tests", s.tests() == PackedStringArray(["_test_workshop_stream"]))
	var e := WorkshopStream.new("/repo")
	var bad: Array = []
	for l in FileAccess.get_file_as_string(ERROR_EVENTS).split("\n"):
		bad.append_array(e.feed(l))
	check("stream: a line that is not JSON is kept raw", bad.any(func(x: Dictionary) -> bool:
			return x["kind"] == WorkshopStream.RAW and str(x["text"]).begins_with("not json")))
	check("stream: SCRIPT ERROR and FAIL in a tool result are failed lines",
			bad.filter(func(x: Dictionary) -> bool: return x["kind"] == WorkshopStream.FAILED).size() == 2)
	check("stream: an error result is an error line, and the run is an error",
			bad[-1]["kind"] == WorkshopStream.ERROR and bad[-1]["text"].contains("error_max_budget_usd") and e.is_error and e.done)
	check("stream: a Write keeps its file too", e.files == PackedStringArray(["tests/fixtures/x.gd"]))
	var long := WorkshopStream.new()
	var cut: Array = long.event({"type": "assistant", "message": {"content": [{"type": "text", "text": "x".repeat(500)}]}})
	check("stream: a long line is cut to LINE_MAX", (cut[0]["text"] as String).length() == WorkshopStream.LINE_MAX)


## The command line: print mode, stream-json, restricted, the tools named, dontAsk with no prompts,
## the repo's file tools only, git's writing verbs, rm and the network refused, never a bypass; in
## the repo, in a process group of its own, the prompt on stdin.
func command() -> void:
	var a := WorkshopRunner.claude_args("/repo")
	var joined := " ".join(a)
	var after := func(flag: String) -> String:
		var i := a.find(flag)
		return a[i + 1] if i >= 0 and i + 1 < a.size() else ""
	check("command: -p, stream-json, --verbose", a.has("-p") and after.call("--output-format") == "stream-json" and a.has("--verbose"))
	check("command: restricted, only Read Edit Write Glob Grep Bash", a.has("--restricted") and after.call("--tools") == "Read,Edit,Write,Glob,Grep,Bash")
	check("command: dontAsk, nobody to answer a prompt", after.call("--permission-mode") == "dontAsk" and after.call("--permission-prompts") == "none")
	check("command: no MCP servers, a budget", a.has("--strict-mcp-config") and float(after.call("--max-budget-usd")) > 0.0)
	var allowed := Array(a.slice(a.find("--allowedTools") + 1, a.find("--disallowedTools")))
	var denied := a.slice(a.find("--disallowedTools") + 1)
	check("command: edits only in the repo, Bash only for tests, shots and git's reading verbs (%s)" % [allowed],
			allowed.has("Edit(./**)") and allowed.has("Write(./**)") and allowed.has("Bash(git status*)")
			and allowed.has("Bash(DAWLINGS_TESTS=* timeout * godot --headless --path . *)") and allowed.has("Bash(tools/shot.sh *)")
			and not allowed.any(func(x: String) -> bool: return x == "Bash" or x.begins_with("Bash(git push") or x.begins_with("Bash(rm")))
	check("command: push, commit, reset, checkout, restore, stash, rm, curl and the web refused",
			["Bash(git push*)", "Bash(git commit*)", "Bash(git reset*)", "Bash(git checkout*)", "Bash(git restore*)",
			"Bash(git stash*)", "Bash(rm *)", "Bash(curl *)", "WebFetch", "Edit(vendor/**)"].all(func(x: String) -> bool: return denied.has(x)))
	check("command: never a permission bypass", not joined.contains("dangerously") and not joined.contains("bypassPermissions"))
	check("command: a fresh run resumes nothing; a fix resumes its session",
			not a.has("--resume") and WorkshopRunner.claude_args("/repo", "abc").slice(-2) == PackedStringArray(["--resume", "abc"]))
	var line := WorkshopRunner.shell_line("/usr/bin/claude", "/re po", "/p/prompt.md", "/p/events.jsonl", "/p/err.log")
	check("command: in the repo, the prompt on stdin, stream to a file (%s)" % line,
			line.begins_with("cd '/re po' && exec '/usr/bin/claude' '-p'") and line.ends_with("< '/p/prompt.md' > '/p/events.jsonl' 2> '/p/err.log'"))
	check("command: a quote in a word is quoted", WorkshopRunner.quote("it's") == "'it'\\''s'")


## No dev flag, no Workshop: no station, no panel, nothing on the card. Never in a multiplayer
## session, hosting or joined; an exported build never, nor without the CLI.
func gating() -> void:
	var saved := Workshop.forced
	check("gating: the rule wants the flag, this machine alone, not exported, the CLI found",
			Workshop.allowed(true, false, false, true) and not Workshop.allowed(false, false, false, true)
			and not Workshop.allowed(true, true, false, true) and not Workshop.allowed(true, false, true, true)
			and not Workshop.allowed(true, false, false, false))
	var why: Array = []
	Workshop.allowed(true, false, true, true, why)
	check("gating: in a session it says why", why.size() == 1 and str(why[0]).contains("multiplayer"))
	# Hosting (or joined) the moment it is asked, or as a request finishes: nothing asked, and a
	# ready change is not reloaded onto under a session.
	var saved_role: int = Session.role
	Workshop.forced = 1
	Session.role = Session.Role.HOST
	check("gating: hosting, the rule is off however it is forced", not Workshop.enabled())
	var hosted := Workshop.new()
	var said: Array = []
	hosted.told.connect(func(text: String) -> void: said.append(text))
	check("gating: hosting, a request is refused and says so",
			hosted.ask("make it amber", "", false).is_empty() and said.size() == 1 and str(said[0]).contains("multiplayer"))
	said.clear()
	hosted.reload()
	check("gating: hosting, a ready change is not reloaded onto, and it says so",
			said.size() == 1 and str(said[0]).contains("RELOAD"))
	hosted.free()
	Session.role = saved_role
	Workshop.forced = 0
	var venue := Venue.make(&"studio")
	check("gating: off, no workshop spot, no station, none on the card",
			venue.workshop_spot() == null and Stations.spot(venue, &"workshop") == null
			and not (Stations.by_area(null)[Stations.CONTROL] as Array).any(func(r: Dictionary) -> bool: return r["id"] == &"workshop"))
	var holder := Node.new()
	t.add_child(holder)
	check("gating: off, attach makes none", Workshop.attach(holder, null) == null and holder.get_child_count() == 0)
	Workshop.forced = 1
	check("gating: on, the station stands on the control room's right wall, facing in",
			venue.workshop_spot() is Transform3D and (venue.workshop_spot() as Transform3D).origin.x > 4.0
			and ((venue.workshop_spot() as Transform3D).basis.z).dot(Vector3.LEFT) > 0.99
			and (Stations.by_area(null)[Stations.CONTROL] as Array).any(func(r: Dictionary) -> bool: return r["id"] == &"workshop"))
	var roulette := Venue.make(Venue.ROULETTE_ID)
	check("gating: never in the Rig Roulette room", roulette.workshop_spot() == null)
	roulette.free()
	venue.free()
	holder.queue_free()
	Workshop.forced = saved


## A throwaway git repo, two files committed, one of them changed and one untracked file beside: the
## other work a request must never touch.
func _scratch_repo(name: String) -> String:
	var root := OS.get_user_data_dir().path_join(name)
	OS.execute("/bin/rm", ["-rf", root])
	DirAccess.make_dir_recursive_absolute(root)
	_put(root, "a.txt", "a at HEAD\n")
	_put(root, "b.txt", "b at HEAD\n")
	OS.execute("git", ["-C", root, "init", "-q"])
	OS.execute("git", ["-C", root, "config", "user.email", "workshop@test"])
	OS.execute("git", ["-C", root, "config", "user.name", "Workshop test"])
	OS.execute("git", ["-C", root, "-c", "user.email=t@t", "-c", "user.name=t", "add", "a.txt", "b.txt"])
	OS.execute("git", ["-C", root, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "start"])
	_put(root, "a.txt", "a with other work\n")
	_put(root, "c.txt", "c untracked, other work\n")
	return root


static func _put(root: String, path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(root.path_join(path).get_base_dir())
	var f := FileAccess.open(root.path_join(path), FileAccess.WRITE)
	f.store_string(text)


static func _read(root: String, path: String) -> String:
	return FileAccess.get_file_as_string(root.path_join(path)) if FileAccess.file_exists(root.path_join(path)) else "<absent>"


## A request's undo puts back exactly its own files, as they were just before it (a file with other
## work in it to that, not to HEAD), deletes what it made, and leaves the other work alone; a file
## edited since is a conflict, left as it is. The workshop branch takes a commit without touching the
## tree, the index or the branch checked out.
func undo() -> void:
	var root := _scratch_repo("workshop_test_repo")
	var cp := WorkshopCheckpoint.new(root, root.path_join("shots/workshop/r1/checkpoint"))
	var before := cp.before()
	check("undo: before keeps the dirty files' ids, not the clean ones (%s)" % [before["dirty"]],
			(before["dirty"] as Dictionary).has("a.txt") and (before["dirty"] as Dictionary).has("c.txt")
			and not (before["dirty"] as Dictionary).has("b.txt"))
	# The request: on top of a's other work, b (clean before) and a new d. c untouched.
	_put(root, "a.txt", "a with other work\nand the request's line\n")
	_put(root, "b.txt", "b changed by the request\n")
	_put(root, "sub/d.txt", "d made by the request\n")
	var changes := cp.after()
	var paths := changes.map(func(c: Dictionary) -> String: return c["path"])
	paths.sort()
	check("undo: the request's files are a, b and d, not c nor its own checkpoint (%s)" % [paths], paths == ["a.txt", "b.txt", "sub/d.txt"])
	var diff := FileAccess.get_file_as_string(root.path_join("shots/workshop/r1/checkpoint/patch.diff"))
	check("undo: a readable patch, in the repo's paths", diff.contains("+and the request's line") and diff.contains("b changed by the request")
			and not diff.contains("checkpoint/before") and diff.contains("--- a/a.txt") and diff.contains("+++ b/a.txt"))
	var r := cp.undo()
	check("undo: all three back (%s)" % [r], (r["restored"] as PackedStringArray).size() == 3 and (r["conflicts"] as PackedStringArray).is_empty())
	check("undo: a is back to its other work, not HEAD", _read(root, "a.txt") == "a with other work\n")
	check("undo: b is back to HEAD, d is gone, c untouched", _read(root, "b.txt") == "b at HEAD\n"
			and _read(root, "sub/d.txt") == "<absent>" and _read(root, "c.txt") == "c untracked, other work\n")
	# Edited since: left alone.
	var cp2 := WorkshopCheckpoint.new(root, root.path_join("shots/workshop/r2/checkpoint"))
	cp2.before()
	_put(root, "b.txt", "b changed by request two\n")
	_put(root, "a.txt", "a with other work\nrequest two\n")
	cp2.after()
	_put(root, "b.txt", "b edited by hand after request two\n")
	var r2 := cp2.undo()
	check("undo: a file edited since the request is a conflict and left as it is (%s)" % [r2],
			(r2["conflicts"] as PackedStringArray) == PackedStringArray(["b.txt"]) and _read(root, "b.txt") == "b edited by hand after request two\n"
			and _read(root, "a.txt") == "a with other work\n")
	# The workshop branch.
	var head_before := _git(root, ["rev-parse", "HEAD"])
	_put(root, "e.txt", "e for the branch\n")
	var ok := cp2.commit_to_branch("workshop", PackedStringArray(["e.txt"]), "Workshop: e")
	check("undo: a commit onto the workshop branch, HEAD, the index and the tree as they were",
			ok and _git(root, ["rev-parse", "HEAD"]) == head_before and _git(root, ["diff", "--cached", "--name-only"]) == ""
			and _git(root, ["show", "workshop:e.txt"]) == "e for the branch" and _read(root, "c.txt") == "c untracked, other work\n"
			and _git(root, ["ls-tree", "--name-only", "workshop"]).split("\n") == PackedStringArray(["a.txt", "b.txt", "e.txt"])
			and _git(root, ["show", "workshop:a.txt"]) == "a at HEAD")
	OS.execute("/bin/rm", ["-rf", root])


static func _git(root: String, args: Array) -> String:
	var out := []
	OS.execute("git", ["-C", root] + args, out)
	return str(out[0]).strip_edges() if out.size() > 0 else ""


## The resume snapshot: saved, the restart's arguments carry --resume (once), and restored into a new
## studio it puts the venue, the player and the song back.
func resume() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_workshop_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().process_frame
	studio.set_venue(&"loft", false, 0)
	await t.get_tree().process_frame
	var w := studio.walker
	w.global_position = Vector3(1.25, 0.0, 2.5)
	w.yaw = 0.8
	w.pitch = -0.3
	studio.station = &"harp"
	DAW.transport_stop()
	DAW.seek(12.0)
	await t.get_tree().process_frame
	var data := WorkshopResume.snapshot(studio, [{"id": "x", "status": Workshop.READY, "text": "t"}], "a summary")
	check("resume: the snapshot says the venue, the walker, the station, the song (%s)" % [data],
			data["venue"] == "loft" and is_equal_approx(float(data["walker"]["x"]), 1.25) and data["station"] == "harp"
			and is_equal_approx(float(data["transport"]["seconds"]), 12.0) and data["medium"] == Presentation.Medium.SCREEN)
	var path := "user://test_workshop_resume.json"
	check("resume: saved and read back the same", WorkshopResume.save(data, path)
			and JSON.stringify(WorkshopResume.load_from(path)) == JSON.stringify(JSON.parse_string(JSON.stringify(data))))
	var args := WorkshopResume.restart_args(PackedStringArray(["tools/probe/x.tscn"]),
			PackedStringArray(["--workshop", "--resume", "old.json", "--venue", "grid"]), path, "/repo", true)
	check("resume: the restart's arguments are this run's, the engine's it took back, --resume once (%s)" % [args],
			args == PackedStringArray(["--headless", "--path", "/repo", "tools/probe/x.tscn", "--", "--workshop", "--venue", "grid", "--resume", path]))
	check("resume: a windowed run stays windowed, its --path kept", WorkshopResume.restart_args(PackedStringArray(["--path", "/x"]),
			PackedStringArray(), path, "/repo", false) == PackedStringArray(["--path", "/x", "--", "--resume", path]))
	check("resume: --resume is read back", WorkshopResume.resume_path(PackedStringArray(["--xr", "--resume", path])) == path
			and WorkshopResume.resume_path(PackedStringArray(["--xr"])) == "")
	studio.queue_free()
	await t.get_tree().process_frame
	DAW.use(OfflineBackend.new())
	var again := Studio.new()
	again.medium = Presentation.Medium.SCREEN
	t.add_child(again)
	await t.get_tree().process_frame
	DAW.transport_stop()
	WorkshopResume.restore(again, WorkshopResume.load_from(path))
	await t.get_tree().process_frame
	var w2 := again.walker
	check("resume: restored, the venue is the loft again", again.venue.venue_id() == &"loft")
	check("resume: the player is back where they stood, facing the same way (%s yaw %.2f)" % [w2.global_position, w2.yaw],
			Vector2(w2.global_position.x, w2.global_position.z).distance_to(Vector2(1.25, 2.5)) < 0.05
			and is_equal_approx(w2.yaw, 0.8) and is_equal_approx(w2.pitch, -0.3) and again.station == &"harp")
	check("resume: the song is back where it was (%.2f)" % DAW.state.position_seconds, absf(DAW.state.position_seconds - 12.0) < 0.05)
	again.queue_free()
	await t.get_tree().process_frame
	Session.layout = saved_layout


## Before a reload: a script that does not parse refuses it, one that does passes.
func check_before_reload() -> void:
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := "shots/tmp/workshop_test"
	_put(repo, dir + "/broken.gd", "extends Node\nfunc f() -> void:\n\tvar x := \n")
	_put(repo, dir + "/broken.gd.uid", "uid://workshoptestbroken\n")
	_put(repo, dir + "/fine.gd", "extends Node\n\n## Fine.\nfunc f() -> int:\n\treturn 1\n")
	_put(repo, dir + "/fine.gd.uid", "uid://workshoptestfine\n")
	var engine := OS.get_executable_path()
	var bad := Workshop.check(engine, repo, PackedStringArray([dir + "/broken.gd"]), PackedStringArray())
	check("check: a script that does not parse refuses the reload, and says where (%s)" % [bad["lines"]],
			not bad["ok"] and (bad["lines"] as PackedStringArray).size() > 0
			and "\n".join(bad["lines"]).contains("broken.gd") and "\n".join(bad["lines"]).contains("Parse Error"))
	var good := Workshop.check(engine, repo, PackedStringArray([dir + "/fine.gd", "core/dev/workshop.gd", "notes.txt"]), PackedStringArray())
	check("check: ones that parse pass, autoloads and all (%s)" % [good["lines"]], good["ok"]
			and (good["lines"] as PackedStringArray) == PackedStringArray([dir + "/fine.gd parses", "core/dev/workshop.gd parses"]))
	OS.execute("/bin/rm", ["-rf", repo.path_join(dir)])


## The journal: a station visit, a control's change from and to, an item grabbed, a toast, the
## player's moves on the trail; its shape; and it never keeps more than MAX_EVENTS.
func journal() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_workshop_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().process_frame
	var j := WorkshopJournal.new()
	j.studio = studio
	t.add_child(j)
	await t.get_tree().process_frame
	j.tick()
	var first_trail := j.trail.size()
	studio.go_to_station(&"harp")
	j.tick()
	var visit: Array = j.events.filter(func(e: Dictionary) -> bool: return e["kind"] == &"station")
	check("journal: a station visit is an event with its id (%s)" % [visit],
			not visit.is_empty() and visit[-1]["data"]["id"] == "harp" and str(visit[-1]["text"]).contains("CHORD HARP"))
	var c: ControlAffordance = null
	for n in t.get_tree().get_nodes_in_group(ControlAffordance.GROUP):
		if n is Fader and studio.is_ancestor_of(n):
			c = n
			break
	if c == null:
		c = t.get_tree().get_nodes_in_group(ControlAffordance.GROUP)[0]
	c.value = 0.25
	c.grab_started.emit(null)
	c.value = 0.75
	c.grab_ended.emit(null)
	var touched: Dictionary = j.events.filter(func(e: Dictionary) -> bool: return e["kind"] == &"control")[-1]
	check("journal: a control's grab is one event, from and to, its title, path and script (%s)" % [touched],
			is_equal_approx(float(touched["data"]["from"]), 0.25) and is_equal_approx(float(touched["data"]["to"]), 0.75)
			and str(touched["data"]["path"]) == str(c.get_path()) and str(touched["data"].get("script", "")).ends_with(".gd")
			and str(touched["text"]).contains("0.250 → 0.750"))
	var item: Item = null
	for n in WorkshopJournal._all_items(studio):
		item = n
		break
	if item != null:
		item.state_changed.emit(Item.State.HELD)
	var grabbed: Array = j.events.filter(func(e: Dictionary) -> bool: return e["kind"] == &"item")
	check("journal: an item grabbed is an event naming it (%s)" % [grabbed], item != null and not grabbed.is_empty()
			and str(grabbed[-1]["text"]) == "grabbed %s" % item.id)
	Session.notice.emit("A toast for the journal")
	check("journal: a toast is an event", j.events.any(func(e: Dictionary) -> bool: return e["kind"] == &"notice" and e["text"] == "A toast for the journal"))
	# go_to_station eases the walker: put it down further on and look round.
	studio.walker.global_position += Vector3(2.0, 0, 0)
	j.tick()
	check("journal: a move of more than MOVE_M is on the trail (%d -> %d)" % [first_trail, j.trail.size()],
			j.trail.size() > first_trail and j.trail[-1].has("heading") and j.trail[-1].has("x"))
	check("journal: every event is {t, kind, text, data}", j.events.all(func(e: Dictionary) -> bool:
			return e.has("t") and e["kind"] is StringName and e["text"] is String and e["data"] is Dictionary))
	for i in WorkshopJournal.MAX_EVENTS + 50:
		j.record(&"test", "event %d" % i)
	check("journal: never more than MAX_EVENTS, the oldest dropped",
			j.events.size() == WorkshopJournal.MAX_EVENTS and j.events[-1]["text"] == "event %d" % (WorkshopJournal.MAX_EVENTS + 49))
	j.queue_free()
	studio.queue_free()
	await t.get_tree().process_frame
	Session.layout = saved_layout


## The context: its sections, the journal in it, under its size; no ticket, token, address, code or
## home path seeded into it survives; the prompt names its file; and the screenshot only when SHOT is on.
func context() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_workshop_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	t.add_child(studio)
	await t.get_tree().process_frame
	var j := WorkshopJournal.new()
	j.studio = studio
	t.add_child(j)
	await t.get_tree().process_frame
	j.record(&"control", "TRACK 2 FADER: 0.500 → 0.800", {"path": "/root/x"})
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var log := PackedStringArray(["connecting to 192.168.1.40:9000 with ticket=abcdEFGH1234",
			"token: sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
			"noray at 10.0.0.7 said TICKET-abc123secret", "local at 127.0.0.1:8910",
			"config in /home/someone/.config/dawlings and %s/core/x.gd" % repo])
	var text := WorkshopContext.build(studio, j, {"id": "r1", "text": "make this louder"}, repo, "",
			{"secrets": ["TICKET-abc123secret"], "log": log, "repo_text": "- branch: test"})
	for heading in ["## The request", "## Where the player is", "## Looking at and holding", "## In view", "## What they did",
			"## Movement", "## The mix", "## The session", "## Settings", "## The repo", "## Log tail"]:
		check("context: has %s" % heading, text.contains(heading))
	check("context: the request and the journal's events are in it", text.contains("make this louder") and text.contains("TRACK 2 FADER: 0.500 → 0.800"))
	check("context: the mix's tracks are in it", text.contains("| # | name | dB |"))
	for secret in ["192.168.1.40", "10.0.0.7", "abcdEFGH1234", "sk-ant-", "TICKET-abc123secret", "/home/someone", repo]:
		check("context: nothing secret: %s is not in it" % secret, not text.contains(secret))
	check("context: localhost stays, the repo is <repo>", text.contains("127.0.0.1") and text.contains("<repo>/core/x.gd"))
	check("context: under MAX_BYTES (%d)" % text.to_utf8_buffer().size(), text.to_utf8_buffer().size() <= WorkshopContext.MAX_BYTES + 2000)
	var prompt := Workshop.prompt_for({"text": "make this louder"}, "shots/workshop/r1/context.md")
	check("context: the prompt says to read the context file first, and has no screenshot line",
			prompt.contains("Read shots/workshop/r1/context.md first") and prompt.contains("THE REQUEST: make this louder")
			and not prompt.contains("screenshot") and prompt.contains("SUMMARY:") and prompt.contains("TESTS:"))
	check("context: with a screenshot, the prompt names it", Workshop.prompt_for({"text": "x"}, "c.md", "", "shots/workshop/r1/shot.png").contains("shots/workshop/r1/shot.png: read it"))
	# The SHOT toggle, through a Workshop with a screenshot of its own.
	var saved := Workshop.forced
	Workshop.forced = 1
	var w := Workshop.new()
	w.home = OS.get_user_data_dir().path_join("workshop_test_home")
	OS.execute("/bin/rm", ["-rf", w.home])
	w.auto_reload = false
	var shots := [0]
	w.screenshot_source = func(path: String) -> bool:
		shots[0] += 1
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		return img.save_png(path) == OK
	t.add_child(w)
	w.with_screenshot = false
	var off := w.ask("no shot please", "", false)
	w.with_screenshot = true
	var on := w.ask("with a shot", "", false)
	check("context: SHOT off sends none, SHOT on one (%s, %s)" % [off["shot"], on["shot"]],
			off["shot"] == "" and FileAccess.file_exists(on["shot"]) and shots[0] == 1)
	check("context: each request's context is a file beside it", FileAccess.file_exists(w.request_dir(on["id"]).path_join("context.md"))
			and FileAccess.get_file_as_string(w.request_dir(on["id"]).path_join("context.md")).contains("with a shot"))
	w.queue_free()
	j.queue_free()
	studio.queue_free()
	await t.get_tree().process_frame
	OS.execute("/bin/rm", ["-rf", OS.get_user_data_dir().path_join("workshop_test_home")])
	Workshop.forced = saved
	Session.layout = saved_layout


## A whole request through the fake claude in a scratch repo: queued, run in the repo with the
## prompt on its stdin naming its context, streamed onto the panel's lines, checked, READY with the
## file it changed; then UNDO LAST puts the file back. And CANCEL stops a slow one.
func run() -> void:
	var root := _scratch_repo("workshop_test_run")
	var saved := Workshop.forced
	Workshop.forced = 1
	var fake := ProjectSettings.globalize_path(FAKE)
	Workshop.claude_override = fake
	var args_file := OS.get_user_data_dir().path_join("workshop_fake_args.txt")
	var events := OS.get_user_data_dir().path_join("workshop_fake_events.jsonl")
	var recorded := FileAccess.get_file_as_string(OK_EVENTS).replace("TESTS: _test_workshop_stream", "TESTS: none").replace("/repo", root)
	_put(events.get_base_dir(), events.get_file(), recorded)
	OS.set_environment("FAKE_CLAUDE_EVENTS", events)
	OS.set_environment("FAKE_CLAUDE_ARGS", args_file)
	OS.set_environment("FAKE_CLAUDE_WRITE", root.path_join("notes.txt"))
	OS.set_environment("FAKE_CLAUDE_BODY", "made by the request\\n")
	var w := Workshop.new()
	w.repo = root
	w.home = root.path_join("shots/workshop")
	w.auto_reload = false
	w.with_screenshot = false
	t.add_child(w)
	var req := w.ask("write some notes")
	var lines_seen := 0
	for i in 600:
		await t.get_tree().process_frame
		lines_seen = maxi(lines_seen, (req["lines"] as Array).size())
		if req["status"] in [Workshop.READY, Workshop.FAILED, Workshop.ERROR]:
			break
	await w.settle()
	check("run: the request ran, was checked and is READY (%s: %s)" % [req["status"], req["lines"]], req["status"] == Workshop.READY)
	check("run: its stream came onto its lines (%d)" % lines_seen, (req["lines"] as Array).any(func(l: Dictionary) -> bool:
			return l["text"] == "edited core/dev/workshop_panel.gd") and req["summary"] == "the Workshop panel's title is a warm amber")
	check("run: the file it changed is found by the checkpoint, not the other work (%s)" % [req["files"]], req["files"] == ["notes.txt"])
	check("run: the session is kept for FIX", req["session"] == "0b6f2a1e-5c1d-4c33-9f0e-1a2b3c4d5e6f")
	var argv := Array(FileAccess.get_file_as_string(args_file).split("\n"))
	check("run: the CLI ran in the repo (%s)" % argv[0], argv[0] == root)
	check("run: with the restricted flags", argv.has("--restricted") and argv.has("dontAsk") and argv.has("stream-json"))
	var stdin := FileAccess.get_file_as_string(args_file).get_slice("--stdin--", 1)
	check("run: the prompt on its stdin is the request, naming its context file",
			stdin.contains("THE REQUEST: write some notes") and stdin.contains("Read shots/workshop/%s/context.md first" % req["id"]))
	check("run: the history is saved beside the requests", FileAccess.get_file_as_string(w.home.path_join("history.json")).contains("write some notes"))
	w.undo()
	await w.settle()
	check("run: UNDO LAST takes the request's file back, and leaves the other work",
			req["status"] == Workshop.UNDONE and _read(root, "notes.txt") == "<absent>" and _read(root, "a.txt") == "a with other work\n")
	OS.set_environment("FAKE_CLAUDE_SLEEP", "1")
	OS.set_environment("FAKE_CLAUDE_WRITE", "")
	var slow := w.ask("a slow one")
	var other := w.ask("queued behind it")
	for i in 300:
		await t.get_tree().process_frame
		if w._runner != null and w._runner.running():
			break
	var pid: int = w._runner.pid if w._runner != null else -1
	check("run: one at a time, the second queued", slow["status"] == Workshop.RUNNING and other["status"] == Workshop.QUEUED)
	w.cancel()
	await w.settle()
	for i in 60:
		await t.get_tree().process_frame
	check("run: CANCEL stops it and its process (%d)" % pid, slow["status"] == Workshop.CANCELLED and pid > 0 and _gone(pid))
	# The queued one starts once the first is cancelled; stop it too.
	for i in 300:
		await t.get_tree().process_frame
		if w._runner != null and w._runner.running():
			break
	w.cancel()
	await w.settle()
	for i in 30:
		await t.get_tree().process_frame
	w.queue_free()
	await t.get_tree().process_frame
	for k in ["FAKE_CLAUDE_EVENTS", "FAKE_CLAUDE_ARGS", "FAKE_CLAUDE_WRITE", "FAKE_CLAUDE_BODY", "FAKE_CLAUDE_SLEEP"]:
		OS.unset_environment(k)
	Workshop.claude_override = ""
	Workshop.forced = saved
	OS.execute("/bin/rm", ["-rf", root])


## Whether process `pid` has stopped: not there, or a zombie nobody has reaped yet.
static func _gone(pid: int) -> bool:
	var out := []
	OS.execute("/bin/sh", ["-c", "ps -o stat= -p %d" % pid], out)
	var stat := str(out[0]).strip_edges() if out.size() > 0 else ""
	return stat == "" or stat.begins_with("Z")
