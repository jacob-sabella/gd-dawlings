class_name Assistant
extends Node

## The built-in assistant (docs/mcp_assistant.md): ask the room a question or for a change in words, and Claude Code,
## attached to the game's own MCP server, answers and does it.
##
## One of these on every machine, with two jobs. On the host (or solo) it RUNS: each ask is a run of Claude Code
## (AssistantRunner), one at a time in order, with the host's project as its context, acting as the peer who asked
## (a run token on the server, so a guest's calls are made as that guest and the per-peer rules apply). Every event of
## a run is kept and sent to every guest (Session.say_assistant). On a guest it MIRRORS: asks go to the host
## (Session.ask_assistant), events come back (Session.assistant_said) into the same `runs`. Both show the same panel.
##
## A tier 2 tool (ControlApi.confirm) parks as a confirm card that only the asker or the host may answer; no answer in
## CONFIRM_SECONDS is a no.

## Something in `runs` changed: a panel redraws on it.
signal changed()

const RUNS_KEPT := 30
const EVENTS_KEPT := 300
const CONFIRM_SECONDS := 120.0
const DIR := "user://assistant"

const QUEUED := &"queued"
const RUNNING := &"running"
const DONE := &"done"
const FAILED := &"failed"
const CANCELLED := &"cancelled"

## For the suite: the claude to run (a fake), over PATH's.
static var claude_override := ""

var host: ControlHost
## Runs, oldest first: {id, peer, who, text, status, events: [{kind, text, ...}], cost}.
var runs: Array = []
## Confirm cards waiting: id -> {id, run, tool, args, who, done, yes}.
var cards: Dictionary = {}
var budget := AssistantRunner.BUDGET
var claude := ""
## Claude Code's id of the conversation so far, so the next ask goes on from it.
var conversation := ""

var _runner: AssistantRunner
var _current: Dictionary = {}
var _token := ""
var _next_run := 1
var _next_card := 1


func _ready() -> void:
	claude = find_claude()
	Session.assistant_asked.connect(_on_asked)
	Session.assistant_said.connect(_on_said)
	Session.assistant_did.connect(_on_did)


static func find_claude() -> String:
	if claude_override != "":
		return claude_override
	return Workshop.find_claude()


## Whether this machine can run the assistant, and if not why not (it says so on the panel).
func can_run(why: Array = []) -> bool:
	if not Session.is_authority():
		why.append("the assistant runs on the host's machine")
		return false
	if claude == "":
		why.append("Claude Code (`claude`) is not on PATH; install it and sign in")
		return false
	return true


# --- asking ---------------------------------------------------------------------------------------

## Ask, from this machine: runs here on the host, goes to the host from a guest.
func ask(text: String) -> void:
	Session.ask_assistant(text)


func cancel(run_id: int) -> void:
	Session.act_assistant("cancel", run_id)


func answer(card_id: int, yes: bool) -> void:
	Session.act_assistant("yes" if yes else "no", card_id)


func new_conversation() -> void:
	conversation = ""


func _on_asked(text: String, from: int) -> void:
	var why := []
	var who := _name_of(from)
	if not can_run(why):
		# A host that cannot run it says so to whoever asked.
		var run := _make_run(from, text)
		run["status"] = FAILED
		_emit(run, {"kind": AssistantStream.ERROR, "text": "the assistant is not available here: " + str(why[0])})
		return
	var run := _make_run(from, text)
	run["who"] = who
	_pump()


func _make_run(from: int, text: String) -> Dictionary:
	var run := {"id": _next_run, "peer": from, "who": _name_of(from), "text": text, "status": QUEUED, "events": [], "cost": 0.0}
	_next_run += 1
	runs.append(run)
	while runs.size() > RUNS_KEPT:
		runs.pop_front()
	_emit(run, {"kind": &"ask", "text": text})
	return run


func _name_of(peer: int) -> String:
	var n := Session.name_of(peer)
	return n if n != "" else ("host" if peer == Session.local_peer_id else "peer %d" % peer)


func _pump() -> void:
	if not _current.is_empty():
		return
	for run: Dictionary in runs:
		if run["status"] == QUEUED:
			_start(run)
			return


func _start(run: Dictionary) -> void:
	if not host.ensure_server():
		run["status"] = FAILED
		_emit(run, {"kind": AssistantStream.ERROR, "text": "the control server could not start (no free port)"})
		return
	var dir := ProjectSettings.globalize_path(DIR).path_join("run_%d_%d" % [Time.get_unix_time_from_system(), run["id"]])
	DirAccess.make_dir_recursive_absolute(dir)
	_token = host.server.issue_token(int(run["peer"]))
	var mcp := dir.path_join("mcp.json")
	_write(mcp, JSON.stringify({"mcpServers": {"dawlings": {"type": "http", "url": host.server.url(),
			"headers": {"Authorization": "Bearer " + _token}}}}))
	var prompt := dir.path_join("prompt.txt")
	_write(prompt, prompt_for(run, conversation == ""))
	_runner = AssistantRunner.new()
	_current = run
	run["status"] = RUNNING
	run["dir"] = dir
	if not _runner.start(claude, dir, prompt, mcp, conversation, budget):
		_finish(FAILED, "could not start Claude Code")
		return
	changed.emit()


## What a run is sent: who is asking, what the room is (the first of a conversation), and the ask.
func prompt_for(run: Dictionary, first: bool) -> String:
	var out := ""
	if first:
		out += "The room, as it is now:\n" + context(host.studio) + "\n\n"
	out += "%s asks: %s" % [run["who"], run["text"]]
	return out


## The host's project and room in words, for a conversation's first prompt. Nothing secret: no addresses, paths or codes.
static func context(studio: Node) -> String:
	var out := PackedStringArray()
	out.append("project: " + DAW.summary())
	if DAW.state != null:
		var s: MixState = DAW.state
		out.append("tempo: %s bpm" % str(snappedf(s.tempo, 0.1)) if "tempo" in s else "")
		var rows := PackedStringArray()
		for i in s.track_indices():
			var t: MixState.TrackState = s.track(i, false)
			rows.append("  #%d %s%s%s" % [i, t.name, " (muted)" if t.mute else "", " (solo)" if t.solo else ""])
			if rows.size() >= 40:
				rows.append("  ...")
				break
		out.append("tracks:\n" + "\n".join(rows))
	if studio != null and "venue" in studio and studio.venue != null:
		out.append("venue: " + str(studio.venue.venue_id()))
	if studio != null and "rack_row" in studio and studio.rack_row.has("patch"):
		var patch: Dictionary = studio.rack_row["patch"]
		out.append("rack: %d modules, %d cables" % [patch.get("modules", {}).size(), patch.get("cables", []).size()])
	out.append("people here: " + ", ".join(PackedStringArray(Session.participants.keys().map(func(id: int) -> String: return Session.name_of(id)))))
	return WorkshopContext.scrub("\n".join(out), ProjectSettings.globalize_path("res://"))


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


# --- the run ------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _current.is_empty() or _runner == null:
		return
	for ev: Dictionary in _runner.poll():
		if ev["kind"] == AssistantStream.INIT:
			continue
		# The final result repeats the last thing it said: shown once.
		if ev["kind"] == AssistantStream.RESULT and not _current["events"].is_empty() \
				and _current["events"].any(func(e: Dictionary) -> bool: return e["kind"] == AssistantStream.SAY and e["text"] == ev["text"]):
			continue
		_emit(_current, ev)
	if _runner.finished():
		var st := _runner.stream
		if st.session_id != "" and not st.is_error:
			conversation = st.session_id
		_current["cost"] = st.cost_usd
		_finish(FAILED if st.is_error else DONE, "")


func _finish(status: StringName, why: String) -> void:
	var run := _current
	if why != "":
		_emit(run, {"kind": AssistantStream.ERROR, "text": why})
	if run.get("status") == RUNNING:
		run["status"] = status
	# Anything it left waiting is refused.
	for c: Dictionary in cards.values():
		if c["run"] == run["id"] and not c["done"]:
			c["done"] = true
			c["yes"] = false
	if _token != "":
		host.server.revoke(_token)
		_token = ""
	_emit(run, {"kind": &"end", "text": str(run["status"])})
	_runner = null
	_current = {}
	_pump()


func _on_did(kind: String, id: int, from: int) -> void:
	match kind:
		"cancel":
			for run: Dictionary in runs:
				if run["id"] == id and (from == run["peer"] or from == Session.local_peer_id):
					if run["status"] == QUEUED:
						run["status"] = CANCELLED
						_emit(run, {"kind": &"end", "text": "cancelled"})
					elif run == _current and _runner != null:
						run["status"] = CANCELLED
						_runner.cancel()
		"yes", "no":
			var c: Dictionary = cards.get(id, {})
			if not c.is_empty() and not c["done"] and (from == c["who"] or from == Session.local_peer_id):
				c["done"] = true
				c["yes"] = kind == "yes"
				_emit(_run_of(c["run"]), {"kind": &"confirmed", "card": id, "yes": c["yes"], "text": ("allowed " if c["yes"] else "refused ") + c["tool"]})


func _run_of(id: int) -> Dictionary:
	for r: Dictionary in runs:
		if r["id"] == id:
			return r
	return {}


## The ControlApi's confirm: a card for the asker, and a wait for their answer (or the host's).
func confirm(tool_name: String, args: Dictionary, who: int) -> bool:
	var run := _current
	if run.is_empty() or int(run["peer"]) != who:
		# Not made by an assistant run (an outside client): no card to show, so the server's own rule applies.
		return host != null and host.auto_confirm
	var card := {"id": _next_card, "run": run["id"], "tool": tool_name, "args": args, "who": who, "done": false, "yes": false}
	_next_card += 1
	cards[card["id"]] = card
	_emit(run, {"kind": &"confirm", "card": card["id"], "tool": tool_name, "args": args, "who": who,
			"text": "wants to %s: allow?" % AssistantStream.row(tool_name, args)})
	var until := Time.get_ticks_msec() + int(CONFIRM_SECONDS * 1000.0)
	while not card["done"] and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	if not card["done"]:
		card["done"] = true
		_emit(run, {"kind": &"confirmed", "card": card["id"], "yes": false, "text": "no answer: refused " + tool_name})
	cards.erase(card["id"])
	return bool(card["yes"])


# --- events: kept, shown, sent -----------------------------------------------------------------------

func _emit(run: Dictionary, ev: Dictionary) -> void:
	ev["run"] = run["id"]
	ev["who"] = run["who"]
	ev["peer"] = run["peer"]
	ev["status"] = str(run["status"])
	run["events"].append(ev)
	while run["events"].size() > EVENTS_KEPT:
		run["events"].pop_front()
	changed.emit()
	if Session.role == Session.Role.HOST:
		Session.say_assistant(ev)


## Guest: the host's assistant did something. Kept in the same `runs`.
func _on_said(ev: Dictionary) -> void:
	if Session.role != Session.Role.GUEST:
		return
	var id := int(ev.get("run", 0))
	var run := _run_of(id)
	if run.is_empty():
		run = {"id": id, "peer": int(ev.get("peer", 0)), "who": str(ev.get("who", "")), "text": "", "status": QUEUED, "events": [], "cost": 0.0}
		runs.append(run)
		while runs.size() > RUNS_KEPT:
			runs.pop_front()
	if ev.get("kind") == &"ask" or str(ev.get("kind")) == "ask":
		run["text"] = str(ev.get("text", ""))
	run["status"] = StringName(str(ev.get("status", run["status"])))
	if str(ev.get("kind")) == "confirm":
		cards[int(ev["card"])] = {"id": int(ev["card"]), "run": id, "tool": str(ev.get("tool", "")), "args": ev.get("args", {}),
				"who": int(ev.get("who", 0)) if typeof(ev.get("who")) == TYPE_INT else int(ev.get("peer", 0)), "done": false, "yes": false}
	if str(ev.get("kind")) == "confirmed":
		cards.erase(int(ev.get("card", 0)))
	run["events"].append(ev)
	while run["events"].size() > EVENTS_KEPT:
		run["events"].pop_front()
	changed.emit()
