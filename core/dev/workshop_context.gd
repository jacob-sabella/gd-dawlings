class_name WorkshopContext
extends RefCounted

## The game's state when a Workshop request was asked, and what the player had just been doing, as
## one readable file Claude is told to read first (docs/workshop.md, "Context"): so "make this
## louder" arrives with what "this" was.
##
## Sections, most useful first: the request; where the player is and what they look at or hold;
## what else is in view; what they did (the journal, newest first); where they walked; the mix;
## the session; the settings; the repo; the log's tail. Each section has a share of MAX_BYTES and
## is cut at its end with a note where it runs over, so a long log cannot crowd out the request.
##
## Nothing secret is written (`scrub`): no session code or ticket, nothing that looks like a token
## or a key, no address but localhost, no environment, and paths outside the repo shortened to `~`.

const MAX_BYTES := 40000
## Each section's most (bytes), by heading; the rest share what is left.
const SHARE := {"What they did": 12000, "Log tail": 6000, "Movement": 3000, "The mix": 6000, "In view": 3000}

## Stands where the repo's section goes until `repo_section` is put there.
const REPO_MARK := "{{workshop:repo}}"

var sections: Array = []


## The context for `request` (its id and text) from `studio` and `journal` (either may be null, as
## in the suite), with `shot` the screenshot's path relative to the repo ("" for none). `extra`
## lets the suite seed values (`session_code`, `log`) without a session.
static func build(studio: Studio, journal: WorkshopJournal, request: Dictionary, repo: String, shot := "",
		extra := {}) -> String:
	var c := WorkshopContext.new()
	if journal != null:
		journal.flush()
	var now := Time.get_ticks_msec()
	c.add("The request", "%s\n\nAsked at %s (id %s).%s" % [request.get("text", ""), Time.get_datetime_string_from_system(),
			request.get("id", ""), ("\nA screenshot of the view as they asked: `%s` (read it)." % shot) if shot != "" else ""])
	c.add("Where the player is", c._player(studio))
	c.add("Looking at and holding", c._focus(studio))
	c.add("In view", c._in_view(studio))
	c.add("What they did", c._journal(journal, now))
	c.add("Movement", c._trail(journal, now))
	c.add("The mix", c._mix())
	c.add("The session", c._session())
	c.add("Settings", c._settings(studio))
	# The repo's part takes git a moment: given (`repo_text`), or REPO_MARK for the Workshop to fill
	# off the main thread (`repo_section`).
	c.add("The repo", str(extra.get("repo_text", REPO_MARK)))
	var tail: PackedStringArray = extra.get("log", journal.log_tail if journal != null else PackedStringArray())
	c.add("Log tail", "```\n%s\n```" % "\n".join(tail.slice(maxi(0, tail.size() - 80))))
	var secrets := PackedStringArray()
	if Session.code != "":
		secrets.append(Session.code)
	for s in extra.get("secrets", []):
		secrets.append(str(s))
	return scrub(c.render(), repo, secrets)


func add(heading: String, body: String) -> void:
	sections.append([heading, body.strip_edges()])


## The sections as markdown, each cut to its share, the whole under MAX_BYTES.
func render() -> String:
	var out := PackedStringArray(["# Workshop context", "",
			"The game's state and the player's recent actions at the moment they asked. Times are seconds before they asked.", ""])
	var spare := MAX_BYTES - 1000
	for s: Array in sections:
		var cap: int = SHARE.get(s[0], 4000)
		var body: String = s[1]
		if body.to_utf8_buffer().size() > cap:
			body = body.left(cap) + "\n… (cut: more than %d bytes)" % cap
		spare -= body.length()
		if spare < 0:
			out.append("## %s\n\n(cut: the context is at its %d-byte limit)\n" % [s[0], MAX_BYTES])
			continue
		out.append("## %s\n\n%s\n" % [s[0], body if body != "" else "(nothing)"])
	return "\n".join(out)


## `text` with nothing secret in it: the `secrets` given, anything after a ticket/token/secret/
## password/key word, long token-like runs, addresses but localhost; the repo's own path as `.`
## and any other home path as `~`.
static func scrub(text: String, repo: String, secrets := PackedStringArray()) -> String:
	var t := text
	for s in secrets:
		if s.length() >= 3:
			t = t.replace(s, "<hidden>")
	if repo != "":
		t = t.replace(repo.trim_suffix("/"), "<repo>")
	var home := OS.get_environment("HOME")
	if home != "" and home != "/":
		t = t.replace(home, "~")
	var rules := [
		["(?i)\\b(ticket|token|secret|password|passwd|api[_-]?key|auth|bearer|cookie|session[_-]?code)(\\s*[:=]\\s*|\\s+)[\"']?[^\\s\"',;]+", "$1$2<hidden>"],
		["/home/[^/\\s]+", "~"],
		["\\b(?!127\\.0\\.0\\.1\\b)(?!0\\.0\\.0\\.0\\b)(\\d{1,3}\\.){3}\\d{1,3}\\b", "<address>"],
		["\\b[A-Za-z0-9_\\-+=]{40,}\\b", "<hidden>"],
	]
	for r: Array in rules:
		var re := RegEx.create_from_string(r[0])
		if re != null:
			t = re.sub(t, r[1], true)
	return t


func _player(s: Studio) -> String:
	if s == null:
		return "(no studio)"
	var lines := PackedStringArray()
	if s.venue != null:
		lines.append("- venue: %s (`%s`, arrangement %d)" % [s.venue.title(), s.venue.venue_id(), s.venue.variant])
	lines.append("- mode: %s" % ["desktop (screen)", "headset, passthrough (AR)", "headset (VR)"][clampi(s.medium, 0, 2)])
	if s.medium != Presentation.Medium.SCREEN:
		lines.append("- hands: %s" % ("tracked hands" if _hands_tracked(s) else "controllers"))
	var pose := WorkshopJournal.player_pose(s)
	if not pose.is_empty():
		var p: Vector3 = pose["position"]
		lines.append("- eye at (%.2f, %.2f, %.2f) m in the studio's frame (+Z behind the desk's seat, toward the live room); heading %.0f° (0 faces the desk, -Z), pitch %.0f°; eye height %.2f m" % [
				p.x, p.y, p.z, pose["heading_deg"], pose["pitch_deg"], pose["eye_height"]])
	lines.append("- station: %s" % (("%s (`%s`)" % [Stations.row(s.station).get("title", ""), s.station]) if s.station != &"" else "none (at the desk or walking)"))
	lines.append("- focused surface: %s" % (String(s.focus.focused_id) if s.focus != null and s.focus.is_focused() else "none"))
	lines.append("- flying (god mode): %s" % s.god_mode)
	return "\n".join(lines)


static func _hands_tracked(s: Studio) -> bool:
	return s.rig != null and "hands_tracked" in s.rig and bool(s.rig.get("hands_tracked"))


func _focus(s: Studio) -> String:
	if s == null:
		return ""
	var lines := PackedStringArray()
	var look := WorkshopJournal.looking_at(s)
	if not look.is_empty():
		lines.append("Under the cursor / gaze:")
		lines.append(_dict_lines(look))
		var node := s.get_node_or_null(NodePath(str(look.get("path", "")))) if str(look.get("path", "")).begins_with("/") else null
		if node != null:
			var props := _props(node)
			if props != "":
				lines.append("Its script's properties:\n" + props)
	var mouse := s.get_node_or_null("MouseHand") as Interactor
	for hand: Interactor in _interactors(s):
		if hand.held != null and is_instance_valid(hand.held):
			lines.append("Held control (%s): %s" % [hand.name, _dict_lines(WorkshopJournal.describe(hand.held))])
		if hand.carrying != null and is_instance_valid(hand.carrying):
			var d := WorkshopJournal.describe(hand.carrying)
			d["scale"] = snappedf(hand.carrying.scale.x, 0.01)
			lines.append("Carrying (%s):\n%s\nIts script's properties:\n%s" % [hand.name, _dict_lines(d), _props(hand.carrying)])
	if mouse == null and lines.is_empty():
		return "nothing"
	return "\n".join(lines)


static func _interactors(s: Studio) -> Array:
	var out: Array = []
	for n in s.find_children("*", "Interactor", true, false):
		out.append(n)
	return out


func _in_view(s: Studio) -> String:
	if s == null or s.venue == null or s.get_viewport() == null:
		return ""
	var cam := s.get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return ""
	var size := s.get_viewport().get_visible_rect().size
	var rows := PackedStringArray(["| station | distance m | on screen (px) |", "| --- | --- | --- |"])
	var frame := s.venue.global_transform if s.venue.is_inside_tree() else s.venue.transform
	for id in s.station_ids():
		var lp: Variant = Stations.look_point(s.venue, id)
		if lp == null:
			continue
		var g: Vector3 = frame * (lp as Vector3)
		var dist := cam.global_position.distance_to(g)
		var where := "behind"
		if not cam.is_position_behind(g):
			var px := cam.unproject_position(g)
			where = "(%d, %d)%s" % [px.x, px.y, "" if Rect2(Vector2.ZERO, size).has_point(px) else " off screen"]
		rows.append("| %s (`%s`) | %.1f | %s |" % [Stations.row(id).get("title", ""), id, dist, where])
	return "\n".join(rows)


func _journal(j: WorkshopJournal, now: int) -> String:
	if j == null:
		return "(no journal)"
	var list := j.recent(now)
	var lines := PackedStringArray()
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		var extra := ""
		var d: Dictionary = e.get("data", {})
		if d.has("path"):
			extra = "  · `%s`" % d["path"]
		if d.has("script"):
			extra += " `%s`" % d["script"]
		lines.append("- -%.0fs **%s** %s%s" % [(now - int(e["t"])) / 1000.0, e["kind"], e["text"], extra])
	return "%d events in the last %d minutes, newest first:\n%s" % [list.size(), WorkshopJournal.KEEP_MSEC / 60000, "\n".join(lines)]


func _trail(j: WorkshopJournal, now: int) -> String:
	if j == null or j.trail.is_empty():
		return "(none)"
	var lines := PackedStringArray()
	for i in range(j.trail.size() - 1, -1, -1):
		var p: Dictionary = j.trail[i]
		if now - int(p["t"]) > WorkshopJournal.KEEP_MSEC:
			break
		lines.append("-%.0fs (%.2f, %.2f, %.2f) heading %.0f°" % [(now - int(p["t"])) / 1000.0, p["x"], p["y"], p["z"], p["heading"]])
	return "Eye positions, newest first, kept on a %.1f m move or a %.0f° turn:\n%s" % [WorkshopJournal.MOVE_M, WorkshopJournal.TURN_DEG, "\n".join(lines)]


func _mix() -> String:
	var s := DAW.state
	if s == null:
		return "(no DAW)"
	var lines := PackedStringArray()
	lines.append("- backend: %s" % DAW.summary())
	lines.append("- project: %s%s" % [s.project_title if s.project_title != "" else "(untitled)",
			(" (`%s`)" % s.project_file) if s.project_file != "" else ""])
	lines.append("- transport: %s%s at %s (%.2f s), tempo %.1f, %d/%d, loop %s" % ["playing" if s.playing else "stopped",
			", recording" if s.recording else "", s.bar_beat(s.position_seconds), s.position_seconds, s.tempo,
			s.beats_per_bar, s.beat_unit, ("%.1f-%.1f s" % [s.loop_start, s.loop_end]) if s.looping else "off"])
	var armed := PackedStringArray()
	var rows := PackedStringArray(["| # | name | dB | pan | mute | solo | arm | fx | sends |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"])
	var keys := s.tracks.keys()
	keys.sort()
	for k in keys:
		var t = s.tracks[k]
		if t.rec_arm:
			armed.append(t.name)
		rows.append("| %d | %s | %.1f | %.2f | %s | %s | %s | %d | %d |" % [k, t.name, t.volume_db, t.pan, "M" if t.mute else "",
				"S" if t.solo else "", "R" if t.rec_arm else "", t.fx.size(), t.sends.size()])
	lines.append("- armed: %s" % (", ".join(armed) if not armed.is_empty() else "none"))
	var regions := PackedStringArray()
	for r in s.regions:
		if r is Array and r.size() >= 3:
			regions.append("%s at %s" % [r[2], s.bar_beat(float(r[0]))])
	lines.append("- sections: %s" % (", ".join(regions) if not regions.is_empty() else "none"))
	lines.append("- markers: %d" % s.markers.size())
	lines.append("")
	lines.append("\n".join(rows))
	return "\n".join(lines)


func _session() -> String:
	var role: String = ["alone", "hosting", "a guest"][clampi(Session.role, 0, 2)]
	var names := PackedStringArray()
	for id in Session.participants:
		names.append(Session.name_of(id))
	return "- %s; %d in the session (%s)\n- this player: %s" % [role, Session.participants.size(), ", ".join(names), Session.local_name]


func _settings(s: Studio) -> String:
	var lines := PackedStringArray()
	if s != null and s.ergonomics != null:
		lines.append("Ergonomics:\n" + _props(s.ergonomics))
	var win := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	lines.append("- window: %dx%d, viewport %s" % [win.x, win.y, s.get_viewport().get_visible_rect().size if s != null and s.get_viewport() != null else Vector2.ZERO])
	var v := Engine.get_version_info()
	lines.append("- Godot %s, renderer %s, %s" % [v.get("string", ""), RenderingServer.get_current_rendering_method(), OS.get_name()])
	if FileAccess.file_exists("res://VERSION"):
		lines.append("- dawlings %s" % FileAccess.get_file_as_string("res://VERSION").strip_edges())
	return "\n".join(lines)


## The repo's section: its branch, what is uncommitted, the last commits. Blocking (git).
static func repo_section(repo: String) -> String:
	if repo == "":
		return ""
	var branch := _run(["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"]).strip_edges()
	var status := _run(["-C", repo, "status", "--short"]).strip_edges().split("\n")
	var log := _run(["-C", repo, "log", "--oneline", "-5"]).strip_edges()
	var shown := "\n".join(status.slice(0, 40)) + ("\n… and %d more" % (status.size() - 40) if status.size() > 40 else "")
	return "- branch: %s\n- uncommitted (not this request's; never touch them):\n```\n%s\n```\n- last commits:\n```\n%s\n```" % [branch, shown, log]


static func _run(args: Array) -> String:
	var out := []
	OS.execute("git", args, out)
	return str(out[0]) if out.size() > 0 else ""


## An object's script variables of plain kinds, a line each.
static func _props(o: Object) -> String:
	var lines := PackedStringArray()
	for p: Dictionary in o.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = o.get(p["name"])
		if typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]:
			lines.append("  - %s: %s" % [p["name"], v])
		if lines.size() >= 40:
			break
	return "\n".join(lines)


static func _dict_lines(d: Dictionary) -> String:
	var lines := PackedStringArray()
	for k in d:
		lines.append("  - %s: %s" % [k, d[k]])
	return "\n".join(lines)
