extends Node
## The Workshop for real (docs/workshop.md): the game (scenes/bootstrap.tscn) run headless with the dev
## flag, a request typed into ASK's own text box, the real claude streaming onto the panel, the
## checks, the reload onto the new code (a new process: this same probe, with --resume), the player
## put back, then UNDO LAST pressed on the panel and the tree checked as it was.
##
##   godot --headless --path . tools/probe/workshop_live.tscn -- --workshop --fresh-layout \
##       [--ask "change the Workshop panel's title colour to a warm amber"] > shots/tmp/workshop_live.log 2>&1
##
## The reloaded process writes to the same log. It prints what it sees, a line at a time, and ends
## with TRIAL DONE (or TRIAL FAILED). The file the request is about is named with --watch (repo-relative),
## so the probe can say it changed and that UNDO put it back.

const ASK := "change the Workshop panel's title colour to a warm amber"
const STATION := &"workshop"

var game: Node
var workshop: Workshop
var _said := 0


func _ready() -> void:
	game = (load("res://scenes/bootstrap.tscn") as PackedScene).instantiate()
	add_child(game)
	await _wait(1.5)
	workshop = game.get_node_or_null("Workshop") as Workshop
	if workshop == null:
		var why: Array = []
		Workshop.enabled(why)
		_say("TRIAL FAILED: no Workshop (%s)" % ", ".join(why))
		get_tree().quit(2)
		return
	if WorkshopResume.resume_path() != "":
		await _after_reload()
	else:
		await _before_reload()


func _before_reload() -> void:
	var studio := workshop.studio
	_say("phase 1: venue %s, %d stations, the Workshop's among them: %s" % [studio.venue.venue_id(), studio.station_ids().size(),
			studio.station_ids().has(STATION)])
	studio.go_to_station(STATION)
	DAW.transport_stop()
	DAW.seek(8.0)
	await _wait(2.5)
	_say("standing at %s, eye %s, yaw %.3f, transport %.2f s" % [studio.station, studio.walker.eye(), studio.walker.yaw, DAW.state.position_seconds])
	_say("watched file before: %s" % _blob())
	# The panel's ASK, then the text typed into the box it opens and Enter.
	var key := workshop.panel.keys["ASK"] as WorkshopPanel.PanelKey
	key.grab_begin(studio.get_node("MouseHand"), key.global_position)
	await get_tree().process_frame
	var prompt: NamePrompt = get_tree().root.get_children().filter(func(n: Node) -> bool: return n is NamePrompt).back()
	var edit := prompt.find_children("*", "LineEdit", true, false)[0] as LineEdit
	edit.text = _arg("--ask", ASK)
	edit.text_submitted.emit(edit.text)
	await get_tree().process_frame
	var req: Dictionary = workshop.history[-1]
	_say("asked %s: \"%s\" (context %d events, screenshot %s)" % [req["id"], req["text"], req["context_events"], req["shot"] if req["shot"] != "" else "none: headless"])
	_say("context file: %s" % workshop.request_dir(req["id"]).path_join("context.md"))
	while req["status"] in [Workshop.QUEUED, Workshop.RUNNING, Workshop.CHECKING]:
		_print_new(req)
		await _wait(0.5)
	_print_new(req)
	_say("status %s, summary \"%s\", files %s, cost $%.3f" % [req["status"], req["summary"], req["files"], req["cost"]])
	_say("watched file after: %s" % _blob())
	_say("panel says: %s" % workshop.panel.current.text)
	if req["status"] != Workshop.READY:
		_say("TRIAL FAILED: not READY, so no reload")
		get_tree().quit(1)
		return
	_say("reloading in %.1f s (the panel counts down)" % workshop.reload_in)
	# Workshop.reload() starts this probe again with --resume and quits this one.


func _after_reload() -> void:
	await _wait(2.0)
	var studio := workshop.studio
	var data := WorkshopResume.load_from(WorkshopResume.resume_path())
	_say("phase 2 (pid %d): reloaded onto \"%s\"; the panel says: %s" % [OS.get_process_id(), workshop.reloaded_onto, workshop.panel.reloaded.text])
	var w: Dictionary = data.get("walker", {})
	var at := studio.walker.global_position
	_say("player: feet %s, yaw %.3f, station %s (saved: %.2f, %.2f, %.2f yaw %.3f station %s)" % [at, studio.walker.yaw, studio.station,
			float(w.get("x", 0)), float(w.get("y", 0)), float(w.get("z", 0)), float(w.get("yaw", 0)), data.get("station", "")])
	_say("venue %s:%d (saved %s:%d), transport %.2f s (saved %.2f)" % [studio.venue.venue_id(), studio.venue.variant, data.get("venue"),
			int(data.get("variant", 0)), DAW.state.position_seconds, float(data.get("transport", {}).get("seconds", 0))])
	var title_ink := WorkshopPanel.TITLE_INK
	_say("the running code's TITLE_INK is %s, the panel's title is lettered %s" % [title_ink, workshop.panel.title.modulate])
	_say("history: %s" % [workshop.history.map(func(r: Dictionary) -> String: return "%s %s" % [r["id"], r["status"]])])
	_say("watched file now: %s" % _blob())
	var key := workshop.panel.keys["UNDO LAST"] as WorkshopPanel.PanelKey
	key.grab_begin(studio.get_node("MouseHand"), key.global_position)
	await workshop.settle()
	await _wait(0.5)
	var last: Dictionary = workshop.history[-1]
	_print_new(last)
	_say("after UNDO LAST: status %s; watched file %s" % [last["status"], _blob()])
	var out := []
	OS.execute("git", ["-C", workshop.repo, "status", "--short", "--", _arg("--watch", "core/dev/workshop_panel.gd")], out)
	_say("git status of it: [%s]" % str(out[0]).strip_edges())
	_say("TRIAL DONE")
	get_tree().quit(0)


func _print_new(req: Dictionary) -> void:
	var lines: Array = req["lines"]
	while _said < lines.size():
		_say("  [%s] %s" % [lines[_said]["kind"], lines[_said]["text"]])
		_said += 1


func _blob() -> String:
	var out := []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "hash-object", _arg("--watch", "core/dev/workshop_panel.gd")], out)
	return str(out[0]).strip_edges().left(12)


func _arg(flag: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


func _say(text: String) -> void:
	print("[workshop_live %s] %s" % [Time.get_time_string_from_system(), text])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
