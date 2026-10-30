class_name Workshop
extends Node

## The Workshop (docs/workshop.md): ask for a change from inside the running game, Claude Code makes
## it in the repo, the game checks it and reloads itself onto the new code, back where you were.
##
## A request goes: QUEUED (one runs at a time) → RUNNING (WorkshopRunner: the CLI, its stream read
## a little each frame onto the panel) → CHECKING (every changed .gd parse-checked, the tests the run
## names run) → READY (clean: the game reloads, after RELOAD_DELAY unless STAY is pressed) or FAILED
## (it does not reload: UNDO takes the request's files back, FIX asks the same Claude session to fix
## what failed). CANCELLED and ERROR (the CLI stopped) can be undone too. Everything a request
## changed is kept per request (WorkshopCheckpoint), so UNDO LAST works after a reload as well.
##
## Each request is sent with the game's state and the player's last minutes (WorkshopContext from
## the WorkshopJournal, and a screenshot unless turned off), written to a file the prompt names.
##
## Only ever on this machine: `enabled` is a dev flag (`--workshop`, DAWLINGS_WORKSHOP=1, the project
## setting `dawlings/dev/workshop`, or `workshop=true` under [dev] in user://workshop.cfg) and not an
## exported build and `claude` found on PATH and not in a multiplayer session. Nothing of it goes over the network:
## the panel's keys are personal, requests and context stay in the repo's ignored shots/workshop/.

## Where everything is kept, under the repo (shots/ is ignored by git).
const DIR := "res://shots/workshop"
const SETTINGS := "user://workshop.cfg"
const PROJECT_SETTING := "dawlings/dev/workshop"
const RELOAD_DELAY := 4.0
## How many progress lines a request keeps (the panel shows the last few).
const KEEP_LINES := 60
const HISTORY_MAX := 30

const QUEUED := &"queued"
const RUNNING := &"running"
const CHECKING := &"checking"
const READY := &"ready"
const FAILED := &"failed"
const CANCELLED := &"cancelled"
const ERROR := &"error"
const UNDONE := &"undone"
const RELOADED := &"reloaded"

## Something changed: a request's status or lines, the queue. The panel redraws on it.
signal changed()
## Something to tell the player, as a toast.
signal told(text: String)

## For the suite: 1 on, 0 off, -1 decided as usual.
static var forced := -1
## For the suite: the claude to run (a fake), over PATH's.
static var claude_override := ""

var studio: Studio
var journal: WorkshopJournal
var panel: WorkshopPanel
## Requests, oldest first: {id, text, status, summary, lines, files, tests, checks, session, shot,
## context_events, parent, cost}.
var history: Array = []
## Whether a screenshot goes with each request.
var with_screenshot := true
var auto_reload := true
var auto_commit := false
var budget := WorkshopRunner.BUDGET
## Set by restore: what the last reload brought the game onto.
var reloaded_onto := ""
## Counting down to a reload (seconds), or -1.
var reload_in := -1.0
## The repo's absolute path, the CLI's and the engine's (for checks).
var repo := ""
var claude := ""
var godot := ""
## Where its requests are kept (absolute): DIR unless set before it enters the tree (the suite).
var home := ""
## (path: String) -> bool, for the suite: writes the screenshot to `path`. The viewport's unless set.
var screenshot_source := Callable()

var _runner: WorkshopRunner
var _current: Dictionary = {}
var _thread: Thread
var _then: Callable


## Whether the Workshop is on in this process. `why` (optional) gets the reason it is not.
static func enabled(why: Array = []) -> bool:
	# Never in a multiplayer session, hosting or joined, whatever else is said: a change built
	# here would reach this machine only, and its bandmates would play on with the old code.
	var networked := Session.is_networked()
	if forced >= 0 and not networked:
		if forced == 0:
			why.append("turned off")
		return forced == 1
	return allowed(flag_on(), OS.has_feature("template"), networked, find_claude() != "", why)


## The rule itself: the dev flag on, not an exported build, not in a multiplayer session, and the
## CLI found.
static func allowed(flag: bool, exported: bool, networked: bool, found: bool, why: Array = []) -> bool:
	if exported:
		why.append("an exported build never has it")
	elif networked:
		why.append("not in a multiplayer session: leave the session to use it")
	elif not flag:
		why.append("the dev flag is off (--workshop, DAWLINGS_WORKSHOP=1, or workshop=true under [dev] in %s)" % SETTINGS)
	elif not found:
		why.append("claude is not on PATH")
	return flag and not exported and not networked and found


## Whether the dev flag is on, by any of its four ways.
static func flag_on() -> bool:
	if OS.get_cmdline_user_args().has("--workshop") or OS.get_environment("DAWLINGS_WORKSHOP") == "1":
		return true
	if ProjectSettings.has_setting(PROJECT_SETTING) and bool(ProjectSettings.get_setting(PROJECT_SETTING)):
		return true
	var cfg := ConfigFile.new()
	return cfg.load(SETTINGS) == OK and bool(cfg.get_value("dev", "workshop", false))


static var _found := "?"


## The claude CLI's path: the override (the suite's), else DAWLINGS_WORKSHOP_CLAUDE (a probe's dry
## run with tests/fixtures/fake_claude.sh), else the first `claude` on PATH, else "". Looked for once.
static func find_claude() -> String:
	if claude_override != "":
		return claude_override
	if OS.get_environment("DAWLINGS_WORKSHOP_CLAUDE") != "":
		return OS.get_environment("DAWLINGS_WORKSHOP_CLAUDE")
	if _found == "?":
		_found = ""
		for d in OS.get_environment("PATH").split(":", false):
			var p := d.path_join("claude")
			if FileAccess.file_exists(p):
				_found = p
				break
	return _found


## The Workshop for `studio`, under `parent`, with its journal; null when it is not enabled.
static func attach(parent: Node, s: Studio) -> Workshop:
	if not enabled():
		return null
	var w := Workshop.new()
	w.name = "Workshop"
	w.studio = s
	parent.add_child(w)
	return w


func _ready() -> void:
	if repo == "":
		repo = ProjectSettings.globalize_path("res://").trim_suffix("/")
	if home == "":
		home = ProjectSettings.globalize_path(DIR)
	claude = find_claude()
	godot = OS.get_executable_path()
	_load_settings()
	DirAccess.make_dir_recursive_absolute(home)
	_load_history()
	journal = WorkshopJournal.new()
	journal.studio = studio
	add_child(journal)
	told.connect(func(text: String) -> void: Session.notice.emit(text))
	if studio != null:
		studio.venue_changed.connect(func(_id: StringName) -> void: stand_panel())
		stand_panel()
	var resume := WorkshopResume.resume_path()
	if resume != "":
		_resume_from.call_deferred(resume)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return
	with_screenshot = bool(cfg.get_value("dev", "screenshot", with_screenshot))
	auto_reload = bool(cfg.get_value("dev", "auto_reload", auto_reload))
	auto_commit = bool(cfg.get_value("dev", "auto_commit", auto_commit))
	budget = float(cfg.get_value("dev", "budget_usd", budget))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("dev", "screenshot", with_screenshot)
	cfg.save(SETTINGS)


## The panel stood again in the studio's venue (a new venue drops the old one with it).
func stand_panel() -> void:
	if studio == null or studio.venue == null:
		return
	var spot: Variant = Stations.spot(studio.venue, WorkshopPanel.STATION)
	if spot == null:
		return
	panel = WorkshopPanel.new()
	panel.workshop = self
	panel.transform = spot
	studio.venue.add_child(panel)


# --- asking ------------------------------------------------------------------------------------

## Ask for `text`: the context taken now (and the screenshot), the request queued, run when its turn
## comes. Answers the request.
func ask(text: String, parent_id := "", run := true) -> Dictionary:
	text = text.strip_edges()
	# Hosting or joined since it started: not in a multiplayer session.
	if text != "" and Session.is_networked():
		told.emit("Workshop: not in a multiplayer session. Leave the session to ask for a change.")
		return {}
	if text == "" or not enabled():
		return {}
	var id := "%s-%03d" % [Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-"), history.size() + 1]
	var req := {"id": id, "text": text, "status": QUEUED, "summary": "", "lines": [], "files": [], "tests": [],
			"checks": [], "session": "", "shot": "", "context_events": 0, "parent": parent_id, "cost": 0.0}
	var dir := request_dir(id)
	DirAccess.make_dir_recursive_absolute(dir)
	if with_screenshot:
		req["shot"] = _screenshot(dir)
	var context := WorkshopContext.build(studio, journal, req, repo, for_claude(req["shot"]))
	req["context_events"] = journal.recent().size() if journal != null else 0
	_write(dir.path_join("context.md"), context)
	history.append(req)
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	_save_history()
	told.emit("Workshop: asked \"%s\"%s" % [text.left(60), " (queued)" if busy() else ""])
	changed.emit()
	if run:
		_next()
	return req


## What a request would be sent with, now, without asking: the context file's text.
func preview() -> String:
	return WorkshopContext.build(studio, journal, {"id": "(preview)", "text": "(what you type)"}, repo,
			"shots/workshop/<id>/shot.png" if with_screenshot else "", {"repo_text": "(the branch, the uncommitted files and the last commits, taken at send)"})


## The prompt the CLI is given for `req`, whose context is at `context_path` (repo-relative).
static func prompt_for(req: Dictionary, context_path: String, fix_of := "", shot_path := "") -> String:
	var lines := PackedStringArray()
	if fix_of != "":
		lines.append("The checks after your last change failed:\n\n%s\n\nFix it: the smallest change that makes them pass." % fix_of)
	else:
		lines.append("You are changing the dawlings game (Godot 4 GDScript, a VR and desktop music game) from inside the running game: the player asked for this on its Workshop panel.")
		lines.append("")
		lines.append("THE REQUEST: " + str(req.get("text", "")))
	lines.append("")
	lines.append("Read %s first: it is the game's state and the player's recent actions when they asked (where they stood, what they looked at, held and had just touched, the mix, the log). Use it to work out what \"this\", \"that\" and \"here\" mean." % context_path)
	if shot_path != "":
		lines.append("A screenshot of their view as they asked is at %s: read it." % shot_path)
	lines.append("")
	lines.append("Rules:")
	lines.append("- Work only in this repo. docs/architecture.md says how things are built; find the code before changing it.")
	lines.append("- House style: plain ## doc comments that say why; follow the code around you.")
	lines.append("- It must work on a desktop (mouse and keys) and in a headset (hands and controllers).")
	lines.append("- Targeted tests only, never the whole suite: DAWLINGS_TESTS=_test_a,_test_b timeout 900 godot --headless --path . tests/tests.tscn 2>&1 | grep -E \"SCRIPT ERROR|Parse Error|checks, |FAIL\"")
	lines.append("- A new class_name needs: godot --headless --path . --editor --quit")
	lines.append("- Do not commit, push, stash, reset, checkout or restore. Never touch vendor/. The uncommitted work already in the tree is not yours: leave it as it is.")
	lines.append("- The smallest change that does what was asked. Never ask a question: decide, and say what you decided.")
	lines.append("")
	lines.append("End your reply with exactly these two lines:")
	lines.append("SUMMARY: <one short line saying what changed, for the panel>")
	lines.append("TESTS: <the _test_ functions that cover this, comma-separated, or none>")
	return "\n".join(lines)


func busy() -> bool:
	return not _current.is_empty()


## The request with this id, or empty.
func find(id: String) -> Dictionary:
	for r: Dictionary in history:
		if r["id"] == id:
			return r
	return {}


func request_dir(id: String) -> String:
	return home.path_join(id)


## `path` as the CLI is told it: relative to the repo where it is in it.
func for_claude(path: String) -> String:
	return path.substr(repo.length() + 1) if path.begins_with(repo + "/") else path


func _next() -> void:
	if busy() or _thread != null:
		return
	for r: Dictionary in history:
		if r["status"] == QUEUED:
			_begin(r)
			return


func _begin(req: Dictionary, resume_session := "", fix_of := "") -> void:
	_current = req
	req["status"] = RUNNING
	req["lines"].append({"kind": WorkshopStream.INIT, "text": "taking a checkpoint of the tree"})
	changed.emit()
	var dir := request_dir(req["id"])
	var context_path := for_claude(dir.path_join("context.md"))
	var shot_path := for_claude(str(req["shot"]))
	var work := func() -> Dictionary:
		WorkshopCheckpoint.new(repo, dir.path_join("checkpoint")).before()
		var ctx_file := dir.path_join("context.md")
		var ctx := FileAccess.get_file_as_string(ctx_file)
		if ctx.contains(WorkshopContext.REPO_MARK):
			_write(ctx_file, ctx.replace(WorkshopContext.REPO_MARK, WorkshopContext.scrub(WorkshopContext.repo_section(repo), repo)))
		_write(dir.path_join("prompt.md"), prompt_for(req, context_path, fix_of, shot_path))
		return {}
	var then := func(_r: Dictionary) -> void:
		_runner = WorkshopRunner.new()
		if not _runner.start(claude, repo, dir.path_join("prompt.md"), dir, resume_session, budget):
			_finish(ERROR, "the CLI could not be started")
			return
		req["lines"].append({"kind": WorkshopStream.INIT, "text": "claude started (pid %d)" % _runner.pid})
		changed.emit()
	_off_thread(work, then)


func _process(delta: float) -> void:
	_poll_thread()
	if _runner != null and not _current.is_empty() and _current["status"] == RUNNING:
		var fresh := _runner.poll()
		if not fresh.is_empty():
			_current["lines"].append_array(fresh)
			if _current["lines"].size() > KEEP_LINES:
				_current["lines"] = _current["lines"].slice(_current["lines"].size() - KEEP_LINES)
			changed.emit()
		if _runner.finished():
			_ran()
	if reload_in >= 0.0:
		reload_in -= delta
		if reload_in < 0.0:
			reload()


## The run is over: what it changed found, then checked, off the main thread.
func _ran() -> void:
	var req := _current
	var s := _runner.stream
	req["session"] = s.session_id
	req["summary"] = s.summary()
	req["tests"] = Array(s.tests())
	req["cost"] = s.cost_usd
	var failed_run := s.is_error
	_runner = null
	req["status"] = CHECKING
	req["lines"].append({"kind": WorkshopStream.INIT, "text": "checking what it changed"})
	changed.emit()
	var dir := request_dir(req["id"])
	var tests: PackedStringArray = PackedStringArray(req["tests"])
	var work := func() -> Dictionary:
		var changes := WorkshopCheckpoint.new(repo, dir.path_join("checkpoint")).after()
		var files := PackedStringArray()
		for c: Dictionary in changes:
			files.append(c["path"])
		var checks := check(godot, repo, files, tests) if not failed_run else {"ok": false, "lines": PackedStringArray(["the run stopped before it finished"])}
		checks["files"] = files
		return checks
	_off_thread(work, _checked.bind(req, failed_run))


func _checked(r: Dictionary, req: Dictionary, failed_run: bool) -> void:
	req["files"] = Array(r["files"])
	req["checks"] = Array(r["lines"])
	for l in r["lines"]:
		req["lines"].append({"kind": WorkshopStream.TESTS if r["ok"] else WorkshopStream.FAILED, "text": l})
	if failed_run:
		_finish(ERROR, "stopped: %s" % (req["summary"] if req["summary"] != "" else "see the lines above"))
	elif not r["ok"]:
		_finish(FAILED, "checks failed: not reloading. UNDO takes it back, FIX asks Claude to fix it.")
	elif (r["files"] as Array).is_empty():
		_finish(READY, "nothing changed in the repo")
	else:
		if auto_commit:
			_commit_to_branch(req)
		_finish(READY, "clean: %s" % req["summary"])
		if auto_reload:
			reload_in = RELOAD_DELAY
			changed.emit()


func _finish(status: StringName, said: String) -> void:
	var req := _current
	req["status"] = status
	req["lines"].append({"kind": WorkshopStream.RESULT if status == READY else WorkshopStream.ERROR, "text": said})
	_current = {}
	_save_history()
	told.emit("Workshop: " + said)
	changed.emit()
	_next()


## Checks on `files` (repo-relative) before a reload: a reimport where a script is new (its
## class_name), each .gd parse-checked, then the `tests` run. {ok, lines}. Blocking.
static func check(engine: String, repo_path: String, files: PackedStringArray, tests: PackedStringArray) -> Dictionary:
	var lines := PackedStringArray()
	var ok := true
	var scripts := PackedStringArray()
	var fresh := false
	for f in files:
		if f.ends_with(".gd") and FileAccess.file_exists(repo_path.path_join(f)):
			scripts.append(f)
			if not FileAccess.file_exists(repo_path.path_join(f + ".uid")):
				fresh = true
	if fresh:
		var out := []
		OS.execute(engine, ["--headless", "--path", repo_path, "--editor", "--quit"], out, true)
	for f in scripts:
		var out := []
		OS.execute(engine, ["--headless", "--path", repo_path, "--check-only", "--script", "res://" + f], out, true)
		var text := str(out[0]) if out.size() > 0 else ""
		var problems := parse_problems(text)
		if not problems.is_empty():
			ok = false
			for l in problems:
				lines.append("%s: %s" % [f, l])
		else:
			lines.append("%s parses" % f)
	if ok and not tests.is_empty():
		var out := []
		var line := "cd %s && DAWLINGS_TESTS=%s timeout 900 %s --headless --path . tests/tests.tscn 2>&1" % [
				WorkshopRunner.quote(repo_path), WorkshopRunner.quote(",".join(tests)), WorkshopRunner.quote(engine)]
		OS.execute("/bin/sh", ["-c", line], out)
		var text := str(out[0]) if out.size() > 0 else ""
		var summary := ""
		for l in text.split("\n"):
			var t := l.strip_edges()
			if t.contains(" checks, ") and t.ends_with("failed"):
				summary = t
			elif t.begins_with("FAIL") or t.contains("SCRIPT ERROR") or t.contains("Parse Error"):
				lines.append(t.left(WorkshopStream.LINE_MAX))
				ok = false
		if summary == "":
			ok = false
			lines.append("tests %s: no result line" % ",".join(tests))
		else:
			lines.append("tests %s: %s" % [",".join(tests), summary])
			if not summary.ends_with(" 0 failed"):
				ok = false
	return {"ok": ok, "lines": lines}


## What a `--check-only` run says is wrong: its Parse Errors (the analyzer's too) with where, and any
## Compile Error but the ones a check-only run always has, which loads no autoloads (DAW, Session):
## "Identifier not found" for an autoload, and "Failed to compile depended scripts" after one. Not
## the exit code: a script that is no MainLoop exits 1 parsed or not.
static func parse_problems(text: String) -> PackedStringArray:
	var autoloads := PackedStringArray()
	for p: Dictionary in ProjectSettings.get_property_list():
		var n := str(p["name"])
		if n.begins_with("autoload/"):
			autoloads.append(n.trim_prefix("autoload/"))
	var out := PackedStringArray()
	var lines := text.split("\n")
	for i in lines.size():
		var l := lines[i].strip_edges()
		var real := l.contains("Parse Error")
		if l.contains("Compile Error") and not l.contains("Failed to compile depended scripts"):
			real = true
			for a in autoloads:
				if l.ends_with("Identifier not found: " + a):
					real = false
		if real:
			var at := lines[i + 1].strip_edges() if i + 1 < lines.size() and lines[i + 1].contains("at: ") else ""
			out.append(l.trim_prefix("SCRIPT ERROR: ") + ((" " + at.trim_prefix("at: GDScript::reload ")) if at != "" else ""))
	return out


# --- after -------------------------------------------------------------------------------------

## Stop the request running now; what it had changed is found, so it can be undone.
func cancel() -> void:
	if reload_in >= 0.0:
		reload_in = -1.0
		told.emit("Workshop: staying on this code. RELOAD when you are ready.")
		changed.emit()
		return
	if _runner == null or _current.is_empty():
		return
	_runner.cancel()
	var req := _current
	_runner = null
	var dir := request_dir(req["id"])
	var work := func() -> Dictionary:
		var changes := WorkshopCheckpoint.new(repo, dir.path_join("checkpoint")).after()
		return {"files": changes.map(func(c: Dictionary) -> String: return c["path"])}
	var then := func(r: Dictionary) -> void:
		req["files"] = r["files"]
		_finish(CANCELLED, "cancelled%s" % (" (%d files changed: UNDO takes them back)" % r["files"].size() if not r["files"].is_empty() else ""))
	_off_thread(work, then)


## The last request that can be undone (READY, FAILED, CANCELLED, ERROR or RELOADED with files), or empty.
func last_undoable() -> Dictionary:
	for i in range(history.size() - 1, -1, -1):
		var r: Dictionary = history[i]
		if r["status"] in [READY, FAILED, CANCELLED, ERROR, RELOADED] and not (r["files"] as Array).is_empty():
			return r
	return {}


## Take request `id`'s files back as they were before it ran (only those it changed, only where they
## are still as it left them). The last undoable one when no id is given.
func undo(id := "") -> void:
	var req := find(id) if id != "" else last_undoable()
	if req.is_empty() or busy() or _thread != null:
		told.emit("Workshop: nothing to undo" if req.is_empty() else "Workshop: wait for the request running now")
		return
	reload_in = -1.0
	var was_running_code: bool = req["status"] == RELOADED
	var dir := request_dir(req["id"])
	var work := func() -> Dictionary:
		return WorkshopCheckpoint.new(repo, dir.path_join("checkpoint")).undo()
	var then := func(r: Dictionary) -> void:
		req["status"] = UNDONE
		var said := "undid \"%s\": %d file%s back" % [str(req["text"]).left(40), r["restored"].size(), "" if r["restored"].size() == 1 else "s"]
		if not r["conflicts"].is_empty():
			said += "; left %s alone (changed since)" % ", ".join(r["conflicts"])
		if was_running_code:
			said += ". RELOAD to run the code without it."
		req["lines"].append({"kind": WorkshopStream.RESULT, "text": said})
		_save_history()
		told.emit("Workshop: " + said)
		changed.emit()
	_off_thread(work, then)


## Ask the same Claude session to fix what failed in request `id` (the last FAILED one by default).
func fix(id := "") -> void:
	var req := find(id)
	if req.is_empty():
		for i in range(history.size() - 1, -1, -1):
			if history[i]["status"] in [FAILED, ERROR]:
				req = history[i]
				break
	if req.is_empty() or busy():
		told.emit("Workshop: nothing to fix" if req.is_empty() else "Workshop: wait for the request running now")
		return
	var fix_req := ask("fix: " + str(req["text"]).left(80), req["id"], false)
	if fix_req.is_empty():
		return
	# Resuming the failed one's session, so it knows what it did.
	_begin(fix_req, str(req.get("session", "")), "\n".join(PackedStringArray(req["checks"])))


## Reload onto the code as it is now: the resume snapshot saved, this game started again with
## `--resume`, this one quit. Guests are told first.
func reload() -> void:
	reload_in = -1.0
	# A session begun while the request ran: the change stays ready, and is reloaded onto once the
	# session is left (RELOAD on the panel).
	if Session.is_networked():
		told.emit("Workshop: ready, but not reloading in a multiplayer session. Leave it, then press RELOAD.")
		return
	var last := ""
	for i in range(history.size() - 1, -1, -1):
		if history[i]["status"] == READY:
			history[i]["status"] = RELOADED
			last = history[i]["summary"]
			break
	_save_history()
	WorkshopResume.save(WorkshopResume.snapshot(studio, history, last))
	var args := WorkshopResume.this_restart()
	var pid := OS.create_instance(args)
	if pid <= 0:
		told.emit("Workshop: could not start the new instance; staying")
		return
	get_tree().quit()


func _resume_from(path: String) -> void:
	# After the room has stood and the walker settled where the venue lets it.
	await get_tree().process_frame
	await get_tree().process_frame
	var data := WorkshopResume.load_from(path)
	if data.is_empty():
		return
	var saved: Array = data.get("history", [])
	if not saved.is_empty():
		history = saved
	reloaded_onto = str(data.get("reloaded_onto", ""))
	WorkshopResume.restore(studio, data)
	told.emit("Workshop: reloaded onto %s" % (reloaded_onto if reloaded_onto != "" else "the code as it is"))
	changed.emit()


func _commit_to_branch(req: Dictionary) -> void:
	var files := PackedStringArray(req["files"])
	var message := "Workshop: %s\n\n%s" % [req["summary"], req["text"]]
	var dir := request_dir(req["id"])
	var work := func() -> Dictionary:
		return {"ok": WorkshopCheckpoint.new(repo, dir.path_join("checkpoint")).commit_to_branch("workshop", files, message)}
	var then := func(r: Dictionary) -> void:
		req["lines"].append({"kind": WorkshopStream.RESULT, "text": "committed to the workshop branch" if r["ok"] else "could not commit to the workshop branch"})
		changed.emit()
	_off_thread(work, then)


func _unhandled_input(event: InputEvent) -> void:
	# F9 at a desk: ask from wherever you are, about whatever you are looking at.
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F9:
		get_viewport().set_input_as_handled()
		ask_by_typing()


## The line asked for: on the monitor, or in a headset on a typing pad under the panel.
func ask_by_typing() -> void:
	var title := "Ask the Workshop: Enter sends it, Escape leaves it"
	if get_viewport() != null and get_viewport().use_xr and panel != null and is_instance_valid(panel):
		var old := panel.get_node_or_null("TypingPad")
		if old != null:
			old.queue_free()
		var pad := TypingPad.ask(panel, "Ask the Workshop: OK sends it", "", WorkshopPanel.PAD_AT)
		pad.limit = WorkshopPanel.ASK_MAX
		pad.answered.connect(func(text: String) -> void: ask(text))
		return
	var prompt := NamePrompt.ask(self, title, "", WorkshopPanel.ASK_MAX)
	prompt.answered.connect(func(text: String) -> void: ask(text))


# --- the thread ---------------------------------------------------------------------------------

## `work` (() -> Dictionary) on a thread of its own, then `then` (Dictionary -> void) back on the main
## one. One at a time; a second waits for the first.
func _off_thread(work: Callable, then: Callable) -> void:
	if _thread != null:
		await _thread_done
	_thread = Thread.new()
	_then = then
	_thread.start(work)


signal _thread_done()


func _poll_thread() -> void:
	if _thread == null or _thread.is_alive():
		return
	var r: Variant = _thread.wait_to_finish()
	_thread = null
	var then := _then
	_then = Callable()
	if then.is_valid():
		then.call(r if r is Dictionary else {})
	_thread_done.emit()


## Waits for whatever is on the thread (the suite, and quitting).
func settle() -> void:
	while _thread != null:
		await get_tree().process_frame
		_poll_thread()


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


# --- files --------------------------------------------------------------------------------------

func _screenshot(dir: String) -> String:
	var path := dir.path_join("shot.png")
	if screenshot_source.is_valid():
		return path if screenshot_source.call(path) else ""
	var vp := get_viewport()
	if vp == null or DisplayServer.get_name() == "headless":
		return ""
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return ""
	if img.get_width() > 1600:
		img.resize(1600, int(1600.0 * img.get_height() / img.get_width()))
	return path if img.save_png(path) == OK else ""


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


func _save_history() -> void:
	_write(home.path_join("history.json"), JSON.stringify({"history": history}, "  "))


func _load_history() -> void:
	var path := home.path_join("history.json")
	if not FileAccess.file_exists(path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		history = d.get("history", [])
		# A request that was running when the game went away did not finish.
		for r: Dictionary in history:
			if r["status"] in [QUEUED, RUNNING, CHECKING]:
				r["status"] = CANCELLED
