extends Node
## The assistant for real (docs/mcp_assistant.md): the game (scenes/bootstrap.tscn) run headless, a question asked of
## the room's assistant, the real claude working the game through the MCP server, and the mix checked after.
##
##   godot --headless --path . tools/probe/assistant_live.tscn -- [--ask "mute the Hat track"] > shots/tmp/assistant_live.log 2>&1
##
## Prints what it sees, a line at a time, and ends with TRIAL DONE (or TRIAL FAILED).

const ASK := "mute the Hat track, then say in one line what you changed"

var game: Node


func _ready() -> void:
	game = (load("res://scenes/bootstrap.tscn") as PackedScene).instantiate()
	add_child(game)
	await _wait(2.0)
	var host := game.get_node_or_null("ControlHost") as ControlHost
	if host == null:
		_end("no ControlHost")
		return
	var question := ASK
	var args := OS.get_cmdline_user_args()
	if args.has("--ask") and args.find("--ask") + 1 < args.size():
		question = args[args.find("--ask") + 1]
	var why := []
	_say("can run: %s %s · server: %s" % [host.assistant.can_run(why), why, host.server != null and host.server.listening()])
	var hat: int = ControlRefs.track(DAW.state, "Hat").get("index", -1)
	_say("Hat is track %d, muted before: %s" % [hat, DAW.state.track(hat, false).mute if hat >= 0 else "?"])
	host.assistant.ask(question)
	var waited := 0.0
	while waited < 240.0:
		await _wait(1.0)
		waited += 1.0
		if not host.assistant.runs.is_empty() and not host.assistant.runs[0]["status"] in [Assistant.QUEUED, Assistant.RUNNING]:
			break
	var run: Dictionary = host.assistant.runs[0] if not host.assistant.runs.is_empty() else {}
	for ev: Dictionary in run.get("events", []):
		_say("  %s: %s" % [ev["kind"], str(ev.get("text", "")).left(160)])
	_say("status %s, cost $%.3f" % [run.get("status", "none"), float(run.get("cost", 0.0))])
	_say("the board shows:")
	for row: Dictionary in AssistantPanel.board_rows(host.assistant, 15):
		_say("  | " + row["text"])
	var after: bool = DAW.state.track(hat, false).mute if hat >= 0 else false
	_say("Hat muted after: %s" % after)
	var changes := host.api.history.size()
	_say("change sets: %d" % changes)
	if changes > 0:
		_say("undo: %s" % host.api.undo()["ok"])
		_say("Hat muted after undo: %s" % DAW.state.track(hat, false).mute)
	_end("" if run.get("status", "") == Assistant.DONE and after else "the run did not finish or the Hat is not muted")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _say(s: String) -> void:
	print("[assistant_live] ", s)


func _end(failure: String) -> void:
	print("TRIAL DONE" if failure == "" else "TRIAL FAILED: " + failure)
	get_tree().quit(0 if failure == "" else 2)
