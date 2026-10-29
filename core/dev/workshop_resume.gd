class_name WorkshopResume
extends RefCounted

## The game reloading itself onto new code and coming back where the player was (docs/workshop.md,
## "Reload").
##
## Live script reload with the room standing is fragile (half the room built by the old code, half
## by the new), so a reload is a new process: `snapshot` says where the player is (venue and its
## arrangement, the walker's feet, heading, pitch and eye, the station, the transport, the project
## file, desktop or headset) and what the Workshop's panel had (its history); `save` writes it to
## PATH; `this_restart` is this process's own command line with `--resume PATH` (and any old one
## taken out); the Workshop starts that (OS.create_instance) and quits. On the new one's start,
## `--resume` (`resume_path`) says to `restore`: the venue set again, the walker put back facing
## the same way, the station gone to again in a headset, the song back where it was and playing if
## it was, the project opened again if it was a file the new one did not open itself.

const PATH := "user://workshop_resume.json"
const FLAG := "--resume"


## What to come back to, from `studio` (may be null, in the suite) and the Workshop's `history`.
static func snapshot(studio: Studio, history: Array, reloaded_onto := "") -> Dictionary:
	var out := {"version": 1, "at": Time.get_datetime_string_from_system(), "history": history,
			"reloaded_onto": reloaded_onto}
	if studio != null:
		out["medium"] = studio.medium
		if studio.venue != null:
			out["venue"] = String(studio.venue.venue_id())
			out["variant"] = studio.venue.variant
		out["station"] = String(studio.station)
		if studio.walker != null:
			var w := studio.walker
			out["walker"] = {"x": w.global_position.x, "y": w.global_position.y, "z": w.global_position.z,
					"yaw": w.yaw, "pitch": w.pitch, "eye": w.eye_height}
		out["god_mode"] = studio.god_mode
	var s := DAW.state
	if s != null:
		out["transport"] = {"seconds": s.position_seconds, "playing": s.playing}
		out["project"] = s.project_file
	return out


static func save(data: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	return true


static func load_from(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## The command line for the new process: this one's engine arguments (OS.get_cmdline_args, which
## leaves out what the engine took for itself, so `--path` and `--headless` are put back where they
## were in force), then `--` and this one's own (OS.get_cmdline_user_args) with `--resume path`; any
## earlier --resume taken out, so reloading twice does not pile them up.
static func restart_args(engine: PackedStringArray, user: PackedStringArray, path := PATH, project := "",
		headless := false) -> PackedStringArray:
	var out := PackedStringArray()
	if headless and not engine.has("--headless"):
		out.append("--headless")
	if project != "" and not engine.has("--path"):
		out.append("--path")
		out.append(project)
	for a in engine:
		if a == "--" or a == "++":
			break
		out.append(a)
	out.append("--")
	var i := 0
	while i < user.size():
		if user[i] == FLAG:
			i += 2
			continue
		out.append(user[i])
		i += 1
	out.append(FLAG)
	out.append(path)
	return out


## This process's own restart line (`restart_args` of what it was started with).
static func this_restart(path := PATH) -> PackedStringArray:
	return restart_args(OS.get_cmdline_args(), OS.get_cmdline_user_args(), path,
			ProjectSettings.globalize_path("res://").trim_suffix("/"), DisplayServer.get_name() == "headless")


## The path after `--resume` in this process's own arguments, or "" for none.
static func resume_path(user_args := OS.get_cmdline_user_args()) -> String:
	var at := user_args.find(FLAG)
	return user_args[at + 1] if at >= 0 and at + 1 < user_args.size() else ""


## Put `studio` back as `data` says: the venue, then the walker (or, in a headset, the station), then
## the song. The project first, where it was a file this process has not opened.
static func restore(studio: Studio, data: Dictionary) -> void:
	if data.is_empty() or studio == null:
		return
	var project := str(data.get("project", ""))
	if project != "" and DAW.state != null and DAW.state.project_file != project and FileAccess.file_exists(project) \
			and Session.is_authority():
		DAW.open_project(project)
	var id := StringName(str(data.get("venue", "")))
	var variant := int(data.get("variant", 0))
	if id != &"" and studio.venue != null and (studio.venue.venue_id() != id or studio.venue.variant != variant):
		studio.set_venue(id, false, variant)
	var station := StringName(str(data.get("station", "")))
	var w: Dictionary = data.get("walker", {})
	if studio.medium == Presentation.Medium.SCREEN and studio.walker != null and not w.is_empty():
		if bool(data.get("god_mode", false)) != studio.god_mode:
			studio.set_god_mode(bool(data.get("god_mode", false)))
		studio.station = station
		var walker := studio.walker
		walker.global_position = Vector3(float(w["x"]), float(w["y"]), float(w["z"]))
		walker.yaw = float(w["yaw"])
		walker.pitch = float(w["pitch"])
		walker.eye_height = float(w.get("eye", walker.eye_height))
		walker.velocity = Vector3.ZERO
		walker._place_camera()
	elif station != &"" and studio.station_ids().has(station):
		studio.go_to_station(station)
	var t: Dictionary = data.get("transport", {})
	if not t.is_empty() and Session.is_authority():
		# Stopped where it was stopped: a new game may start the song playing.
		if not bool(t.get("playing", false)) and DAW.state.playing:
			DAW.transport_stop()
		DAW.seek(float(t.get("seconds", 0.0)))
		if bool(t.get("playing", false)) and not DAW.state.playing:
			DAW.transport_play()
