extends RefCounted

## Control tools: project and transport. See core/control/control_tools.gd and docs/mcp_assistant.md.
##
## Everything goes through the DAW's public methods, as the game's own controls do, so undo, the multiplayer
## authority and the game's refusals are inherited. A file is only ever named, never given as a path: projects
## and templates live in the game's own folders (ProjectFiles.DEFAULT_DIR, TEMPLATE_DIR).

const SHAPES := ["hold", "ramp_beats", "ramp_seconds"]
## How many rows a list tool returns at most.
const LIST_MAX := 200

## What the last render said: {files, problems, at}. A render is asynchronous on a DAW that renders in its own
## process, so the answer comes later through DAW.render_finished.
static var _last_render: Dictionary = {}


static func register(api: ControlApi) -> void:
	if not DAW.render_finished.is_connected(_on_render_finished):
		DAW.render_finished.connect(_on_render_finished)
	_project(api)
	_files(api)
	_tempo(api)
	_markers(api)
	_regions(api)
	_lyrics_and_sections(api)
	_history(api)
	_render(api)
	_transport(api)


static func _on_render_finished(files: PackedStringArray, problems: PackedStringArray) -> void:
	_last_render = {"files": Array(files), "problems": Array(problems), "at": Time.get_unix_time_from_system()}


# --- shared ------------------------------------------------------------------------------------------

static func _round(v: float) -> float:
	return snappedf(v, 0.001)


static func _pos(seconds: float) -> Dictionary:
	return {"seconds": _round(seconds), "bar_beat": DAW.state.bar_beat(seconds)}


static func _no_project() -> Dictionary:
	return ControlTool.fail("there is no project")


static func _need(capability: StringName, what: String) -> Dictionary:
	if DAW.backend == null or not DAW.can(capability):
		return ControlTool.fail("this DAW cannot %s: in Reaper, load the dawlings bridge script" % what)
	return {}


static func _num(a: Dictionary, key: String, default: float) -> float:
	return float(a[key]) if a.has(key) else default


# --- project -----------------------------------------------------------------------------------------

static func _project(api: ControlApi) -> void:
	api.add(ControlTool.make("project_get",
			"The project at a glance: title, file name, whether it has unsaved changes, tempo (bpm), time signature, length (seconds), track count, how many markers, regions, tempo-map and time-signature-map points, the loop and the transport settings, and how deep the undo history is. Start here.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				var s := DAW.state
				if s == null:
					return _no_project()
				return ControlTool.ok({
					"title": DAW.project_title(), "file": DAW.project_file_name(), "unsaved": DAW.has_unsaved_changes(),
					"backend": DAW.summary(), "tempo_bpm": _round(s.tempo),
					"time_signature": "%d/%d" % [s.beats_per_bar, s.beat_unit],
					"length_seconds": _round(s.timeline_length()), "tracks": s.track_indices().size(),
					"markers": s.markers.size(), "regions": s.regions.size(),
					"tempo_map_points": s.tempo_points.size(), "time_signature_map_points": s.time_signature_points.size(),
					"has_lyrics": not s.lyrics.is_empty(), "transport": _transport_state(),
					"undo_depth": s.undo_depth, "redo_depth": s.redo_depth,
					"can": {"save": DAW.can(DAWBackend.Capability.PROJECT_SAVE), "files": DAW.can(DAWBackend.Capability.PROJECT_FILES),
							"render": DAW.can(DAWBackend.Capability.RENDER), "markers": DAW.can(DAWBackend.Capability.MARKERS),
							"arrange": DAW.can(DAWBackend.Capability.ARRANGE), "lyrics": DAW.can(DAWBackend.Capability.LYRICS)},
				})))


static func _files(api: ControlApi) -> void:
	api.add(ControlTool.make("project_list",
			"The project files kept in the game's projects folder, and the templates, by name (what project_open and project_new_from_template take). Also says whether a newer autosave copy of the open project can be recovered.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				var projects: Array = []
				var dir := DirAccess.open(ProjectFiles.DEFAULT_DIR)
				if dir != null:
					for f in dir.get_files():
						if f.get_extension().to_lower() == ProjectFiles.EXTENSION:
							projects.append(f.get_basename())
				projects.sort()
				return ControlTool.ok({"projects": projects.slice(0, LIST_MAX), "templates": Array(ProjectFiles.templates()).slice(0, LIST_MAX),
						"recoverable_autosave": not DAW.recoverable_copy().is_empty()})))

	api.add(ControlTool.make("project_save",
			"Save the open project where it is. With 'as', save it under that name in the game's projects folder instead (it then becomes the open project's file; a file already there is only replaced when overwrite is true). Returns the file and any warnings (a take that is not on this machine).",
			{"as": ControlTool.str_p("a project name, not a path, e.g. 'My song'"), "overwrite": ControlTool.bool_p("replace a file of that name (default false)")},
			[], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				if DAW.state == null:
					return _no_project()
				if a.has("as"):
					var name := str(a["as"]).strip_edges()
					if name.is_empty() or name != name.validate_filename() or name.contains("/"):
						return ControlTool.fail("'as' is a plain project name, not a path")
					if not Session.is_authority():
						return ControlTool.fail("only the host chooses where the project is saved")
					if not DAW.can(DAWBackend.Capability.PROJECT_FILES):
						return ControlTool.fail("this DAW keeps its own project files; use plain project_save")
					var path := ProjectFiles.default_path(name)
					if FileAccess.file_exists(path) and not bool(a.get("overwrite", false)):
						return ControlTool.fail("a project called '%s' already exists; pass overwrite true to replace it" % name)
					var said := DAW.save_project_as(path)
					if DAW.project_file() != path:
						return ControlTool.fail("could not save: %s" % "; ".join(said))
					return ControlTool.ok({"file": DAW.project_file_name(), "warnings": Array(said)})
				if not DAW.can(DAWBackend.Capability.PROJECT_SAVE):
					return ControlTool.fail("this DAW cannot save the project from here")
				var got := {"said": PackedStringArray(), "fired": false}
				var on_saved := func(said: PackedStringArray) -> void:
					got["said"] = said
					got["fired"] = true
				DAW.project_saved.connect(on_saved)
				DAW.save_project()
				DAW.project_saved.disconnect(on_saved)
				return ControlTool.ok({"file": DAW.project_file_name(), "asked": not Session.is_authority(), "warnings": Array(got["said"])})))

	api.add(ControlTool.make("project_open",
			"Open a saved project by name (see project_list), REPLACING the open one; unsaved changes are lost, so save first. Destructive: the player confirms.",
			{"name": ControlTool.str_p("a project name from project_list")}, ["name"], ControlTool.DESTRUCTIVE, func(a: Dictionary) -> Dictionary:
				var name := str(a["name"]).strip_edges()
				if name != name.validate_filename() or name.contains("/") or name.is_empty():
					return ControlTool.fail("'name' is a project name from project_list, not a path")
				if not DAW.can(DAWBackend.Capability.PROJECT_FILES):
					return ControlTool.fail("this DAW keeps its own project files and cannot open one from here")
				var path := ProjectFiles.default_path(name)
				if not FileAccess.file_exists(path):
					return ControlTool.fail("no project called '%s'; see project_list" % name)
				var said := DAW.open_project(path)
				if DAW.project_file() != path:
					return ControlTool.fail("could not open '%s': %s" % [name, "; ".join(said)])
				return ControlTool.ok({"title": DAW.project_title(), "warnings": Array(said)})))

	api.add(ControlTool.make("project_new",
			"Start a new empty project with `tracks` tracks at 120 bpm, REPLACING the open one; unsaved changes are lost. Destructive: the player confirms.",
			{"tracks": ControlTool.int_p("how many tracks to start with (default 4)", 0, 64)}, [], ControlTool.DESTRUCTIVE, func(a: Dictionary) -> Dictionary:
				if not DAW.can(DAWBackend.Capability.PROJECT_FILES):
					return ControlTool.fail("this DAW keeps its own project files and cannot start one from here")
				var said := DAW.new_project(int(a.get("tracks", 4)))
				if not said.is_empty():
					return ControlTool.fail("; ".join(said))
				return ControlTool.ok({"title": DAW.project_title(), "tracks": DAW.state.track_indices().size()})))

	api.add(ControlTool.make("project_new_from_template",
			"Start a new unsaved project laid out as a template (see project_list), REPLACING the open one. Destructive: the player confirms.",
			{"template": ControlTool.str_p("a template name from project_list")}, ["template"], ControlTool.DESTRUCTIVE, func(a: Dictionary) -> Dictionary:
				var name := str(a["template"])
				if not (name in ProjectFiles.templates()):
					return ControlTool.fail("no template called '%s'; the templates are: %s" % [name, ", ".join(ProjectFiles.templates())])
				var said := DAW.new_project_from_template(name)
				if not said.is_empty():
					return ControlTool.fail("; ".join(said))
				return ControlTool.ok({"title": DAW.project_title(), "tracks": DAW.state.track_indices().size()})))

	api.add(ControlTool.make("project_template_add",
			"Keep the open project's layout (tracks, routing, effects, levels, tempo; not clips, automation, markers) as a template under this name, replacing a template of that name.",
			{"name": ControlTool.str_p("template name")}, ["name"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var name := str(a["name"]).strip_edges()
				if name.is_empty():
					return ControlTool.fail("a template needs a name")
				var said := DAW.save_template(name)
				if not (name.validate_filename() in ProjectFiles.templates()):
					return ControlTool.fail("could not keep the template: %s" % "; ".join(said))
				return ControlTool.ok({"template": name, "warnings": Array(said)})))

	api.add(ControlTool.make("project_recover",
			"Open the newest autosave copy kept of the project in its place, unsaved, REPLACING the open one (crash recovery). `generation` 0 is the newest; project_list says whether one exists. Destructive: the player confirms.",
			{"generation": ControlTool.int_p("0 newest, 1 the one before, ...", 0, 20)}, [], ControlTool.DESTRUCTIVE, func(a: Dictionary) -> Dictionary:
				if DAW.recoverable_copy().is_empty():
					return ControlTool.fail("no newer copy is kept")
				var said := DAW.recover_autosave(int(a.get("generation", 0)))
				return ControlTool.ok({"title": DAW.project_title(), "warnings": Array(said)})))

	api.add(ControlTool.make("project_name_get",
			"The project's title and file name.", {}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				return ControlTool.ok({"title": DAW.project_title(), "file": DAW.project_file_name()})))


# --- tempo and time signature --------------------------------------------------------------------------

static func _tempo(api: ControlApi) -> void:
	api.add(ControlTool.make("project_tempo_get",
			"The song's tempo in bpm (the first point's), its time signature, and the tempo map and time-signature map points (empty maps mean one tempo / one signature throughout).",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				return ControlTool.ok(_tempo_data())))

	api.add(ControlTool.make("project_tempo_set",
			"Set the song's tempo in bpm (1 to 960). Changes the first tempo only; later tempo-map points stay.",
			{"bpm": ControlTool.num_p("beats per minute", DAW.TEMPO_MIN, DAW.TEMPO_MAX)}, ["bpm"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				DAW.set_tempo(float(a["bpm"]))
				return ControlTool.ok({"tempo_bpm": _round(DAW.state.tempo)})))

	api.add(ControlTool.make("project_tempo_map_list",
			"The tempo map: points {beat, bpm, shape}, beat counted from 0 in quarter-note beats, shape one of hold (a step), ramp_beats or ramp_seconds (glide to the next point). Empty when the song is at one tempo.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				return ControlTool.ok({"tempo_bpm": _round(DAW.state.tempo), "points": _tempo_points()})))

	api.add(ControlTool.make("project_tempo_map_set",
			"Replace the whole tempo map with these points (one change). The first must be at beat 0 and the beats must strictly increase; bpm 1 to 960. An empty list returns the song to its single tempo. Each point {beat, bpm, shape?} with shape hold (default), ramp_beats or ramp_seconds.",
			{"points": ControlTool.arr_p("[{beat: number, bpm: number, shape?: string}]", {"type": "object"})}, ["points"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var rows: Array = []
				var last := -1.0
				for p in a["points"]:
					if typeof(p) != TYPE_DICTIONARY or not p.has("beat") or not p.has("bpm"):
						return ControlTool.fail("each point is {beat, bpm, shape?}")
					var beat := float(p["beat"])
					var bpm := float(p["bpm"])
					var shape := str(p.get("shape", "hold"))
					if not (shape in SHAPES):
						return ControlTool.fail("shape is one of %s" % ", ".join(SHAPES))
					if not is_finite(beat) or not is_finite(bpm) or beat <= last or bpm < DAW.TEMPO_MIN or bpm > DAW.TEMPO_MAX:
						return ControlTool.fail("points need strictly rising beats and a bpm of %d to %d" % [DAW.TEMPO_MIN, DAW.TEMPO_MAX])
					if rows.is_empty() and beat != 0.0:
						return ControlTool.fail("the first point must be at beat 0")
					rows.append([beat, bpm, SHAPES.find(shape)])
					last = beat
				DAW.set_tempo_map(rows)
				return ControlTool.ok({"points": _tempo_points()})))

	api.add(ControlTool.make("project_time_signature_map_list",
			"The time-signature map: points {beat, numerator, denominator}, beat from 0 in quarter-note beats. Also the song's own signature. Empty points mean one signature throughout.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				return ControlTool.ok({"time_signature": "%d/%d" % [DAW.state.beats_per_bar, DAW.state.beat_unit], "points": _meter_points()})))

	api.add(ControlTool.make("project_time_signature_map_set",
			"Replace the whole time-signature map (one change). The first point must be at beat 0 and is the song's own signature; beats strictly increase; numerator and denominator 1 to 64. An empty list leaves the signature as it is. Each point {beat, numerator, denominator}.",
			{"points": ControlTool.arr_p("[{beat: number, numerator: integer, denominator: integer}]", {"type": "object"})}, ["points"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var rows: Array = []
				var last := -1.0
				for p in a["points"]:
					if typeof(p) != TYPE_DICTIONARY or not p.has("beat") or not p.has("numerator") or not p.has("denominator"):
						return ControlTool.fail("each point is {beat, numerator, denominator}")
					var beat := float(p["beat"])
					var num := int(p["numerator"])
					var den := int(p["denominator"])
					if not is_finite(beat) or beat <= last or num < 1 or num > 64 or den < 1 or den > 64:
						return ControlTool.fail("points need strictly rising beats and a numerator and denominator of 1 to 64")
					if rows.is_empty() and beat != 0.0:
						return ControlTool.fail("the first point must be at beat 0")
					rows.append([beat, num, den])
					last = beat
				DAW.set_time_signature_map(rows)
				return ControlTool.ok({"time_signature": "%d/%d" % [DAW.state.beats_per_bar, DAW.state.beat_unit], "points": _meter_points()})))


static func _tempo_points() -> Array:
	var out: Array = []
	for p in DAW.state.tempo_points:
		out.append({"beat": _round(float(p[0])), "bpm": _round(float(p[1])), "shape": SHAPES[clampi(int(p[2]), 0, 2)]})
	return out


static func _meter_points() -> Array:
	var out: Array = []
	for p in DAW.state.time_signature_points:
		out.append({"beat": _round(float(p[0])), "numerator": int(p[1]), "denominator": int(p[2])})
	return out


static func _tempo_data() -> Dictionary:
	return {"tempo_bpm": _round(DAW.state.tempo), "time_signature": "%d/%d" % [DAW.state.beats_per_bar, DAW.state.beat_unit],
			"tempo_points": _tempo_points(), "time_signature_points": _meter_points()}


# --- markers ------------------------------------------------------------------------------------------

static func _marker_rows() -> Array:
	var keys: Array = DAW.state.markers.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		var row := _pos(float(k))
		row["name"] = str(DAW.state.markers[k])
		out.append(row)
	return out


## The stored position of the marker a client means: by `at` (seconds, within 5 ms) or by `name`.
static func _marker_key(a: Dictionary) -> Variant:
	if a.has("at"):
		for k in DAW.state.markers.keys():
			if absf(float(k) - float(a["at"])) < 0.005:
				return float(k)
		return ControlTool.fail("no marker at %s seconds; see project_marker_list" % a["at"])
	if a.has("name"):
		var hits: Array = []
		for k in DAW.state.markers.keys():
			if str(DAW.state.markers[k]).to_lower() == str(a["name"]).to_lower():
				hits.append(float(k))
		if hits.size() == 1:
			return hits[0]
		if hits.is_empty():
			return ControlTool.fail("no marker called '%s'; see project_marker_list" % a["name"])
		return ControlTool.fail("%d markers are called '%s'; say 'at' (seconds) instead" % [hits.size(), a["name"]])
	return ControlTool.fail("say which marker: 'at' (seconds) or 'name'")


static func _markers(api: ControlApi) -> void:
	api.add(ControlTool.make("project_marker_list",
			"The markers, earliest first: {seconds, bar_beat, name}. A marker is addressed by its position in seconds ('at') or its name.",
			{"limit": ControlTool.int_p("at most this many (default 100)", 1, LIST_MAX), "offset": ControlTool.int_p("skip this many", 0)}, [], ControlTool.READ,
			func(a: Dictionary) -> Dictionary:
				var rows := _marker_rows()
				var off := int(a.get("offset", 0))
				return ControlTool.ok({"total": rows.size(), "markers": rows.slice(off, off + int(a.get("limit", 100)))})))

	api.add(ControlTool.make("project_marker_add",
			"Drop a named marker at a position in seconds. Names are cut at 64 characters.",
			{"at": ControlTool.num_p("seconds from the song's start", 0), "name": ControlTool.str_p("what to call it")}, ["at", "name"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.MARKERS, "keep markers")
				if not bad.is_empty():
					return bad
				DAW.add_marker(float(a["at"]), str(a["name"]))
				return ControlTool.ok(_pos(float(a["at"])))))

	api.add(ControlTool.make("project_marker_set",
			"Rename and/or move a marker. Say which by 'at' (its position now, seconds) or 'name'; then 'to' (new position, seconds) and/or 'new_name'.",
			{"at": ControlTool.num_p("the marker's position now, seconds"), "name": ControlTool.str_p("the marker's name now"),
			"to": ControlTool.num_p("move it to this many seconds", 0), "new_name": ControlTool.str_p("rename it")}, [], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.MARKERS, "keep markers")
				if not bad.is_empty():
					return bad
				var key: Variant = _marker_key(a)
				if typeof(key) == TYPE_DICTIONARY:
					return key
				if not a.has("to") and not a.has("new_name"):
					return ControlTool.fail("say what to change: 'to' and/or 'new_name'")
				var to := float(a.get("to", key))
				DAW.edit_marker(float(key), to, str(a.get("new_name", DAW.state.markers[key])))
				return ControlTool.ok({"markers": _marker_rows()})))

	api.add(ControlTool.make("project_marker_remove",
			"Remove a marker, by 'at' (seconds) or 'name'.",
			{"at": ControlTool.num_p("the marker's position, seconds"), "name": ControlTool.str_p("the marker's name")}, [], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.MARKERS, "keep markers")
				if not bad.is_empty():
					return bad
				var key: Variant = _marker_key(a)
				if typeof(key) == TYPE_DICTIONARY:
					return key
				DAW.remove_marker(float(key))
				return ControlTool.ok({"removed": _pos(float(key))})))


# --- regions ------------------------------------------------------------------------------------------

static func _region_rows() -> Array:
	var out: Array = []
	for i in DAW.state.regions.size():
		var r: Array = DAW.state.regions[i]
		out.append({"number": i, "name": str(r[2]), "start_seconds": _round(float(r[0])), "end_seconds": _round(float(r[1])),
				"start_bar_beat": DAW.state.bar_beat(float(r[0])), "end_bar_beat": DAW.state.bar_beat(float(r[1]))})
	return out


## The index in state.regions of the region `ref` names (its number as list shows it, "#n", or its name).
static func _region_index(ref: Variant) -> Variant:
	var regions: Array = DAW.state.regions
	if typeof(ref) in [TYPE_INT, TYPE_FLOAT] or (typeof(ref) == TYPE_STRING and str(ref).begins_with("#") and str(ref).substr(1).is_valid_int()):
		var i := int(ref) if typeof(ref) != TYPE_STRING else int(str(ref).substr(1))
		if i >= 0 and i < regions.size():
			return i
		return ControlTool.fail("no region number %d; there are %d (numbered from 0)" % [i, regions.size()])
	var hits: Array = []
	for i in regions.size():
		if str(regions[i][2]).to_lower() == str(ref).to_lower():
			hits.append(i)
	if hits.size() == 1:
		return hits[0]
	if hits.is_empty():
		return ControlTool.fail("no region called '%s'; see project_region_list" % str(ref))
	return ControlTool.fail("%d regions are called '%s'; say its number" % [hits.size(), str(ref)])


static func _regions(api: ControlApi) -> void:
	api.add(ControlTool.make("project_region_list",
			"The regions (named spans, the song's sections), in order of their starts: {number, name, start_seconds, end_seconds, start_bar_beat, end_bar_beat}. Numbers count from 0 and are what project_sections_arrange takes. Address a region by number or name.",
			{"limit": ControlTool.int_p("at most this many (default 100)", 1, LIST_MAX), "offset": ControlTool.int_p("skip this many", 0)}, [], ControlTool.READ,
			func(a: Dictionary) -> Dictionary:
				var rows := _region_rows()
				var off := int(a.get("offset", 0))
				return ControlTool.ok({"total": rows.size(), "regions": rows.slice(off, off + int(a.get("limit", 100)))})))

	api.add(ControlTool.make("project_region_add",
			"Add a named region from `start` to `end` seconds. A region starting where another does replaces it.",
			{"start": ControlTool.num_p("seconds", 0), "end": ControlTool.num_p("seconds, after start", 0), "name": ControlTool.str_p("what to call it")},
			["start", "end", "name"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.MARKERS, "keep regions")
				if not bad.is_empty():
					return bad
				if float(a["end"]) <= float(a["start"]):
					return ControlTool.fail("a region ends after it starts")
				DAW.add_region(float(a["start"]), float(a["end"]), str(a["name"]))
				return ControlTool.ok({"regions": _region_rows()})))

	api.add(ControlTool.make("project_region_set",
			"Move, resize or rename a region. `region` is its number (from project_region_list) or name; give any of start, end (seconds) and name.",
			{"region": ControlTool.ref_p("number or name"), "start": ControlTool.num_p("new start, seconds", 0), "end": ControlTool.num_p("new end, seconds", 0),
			"name": ControlTool.str_p("new name")}, ["region"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.MARKERS, "keep regions")
				if not bad.is_empty():
					return bad
				var i: Variant = _region_index(a["region"])
				if typeof(i) == TYPE_DICTIONARY:
					return i
				if not (a.has("start") or a.has("end") or a.has("name")):
					return ControlTool.fail("say what to change: start, end and/or name")
				var r: Array = DAW.state.regions[i]
				var start := _num(a, "start", float(r[0]))
				var end := _num(a, "end", float(r[1]))
				if end <= start:
					return ControlTool.fail("a region ends after it starts")
				DAW.edit_region(float(r[0]), start, end, str(a.get("name", r[2])))
				return ControlTool.ok({"regions": _region_rows()})))

	api.add(ControlTool.make("project_region_remove",
			"Remove a region, by number or name.", {"region": ControlTool.ref_p("number or name")}, ["region"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.MARKERS, "keep regions")
				if not bad.is_empty():
					return bad
				var i: Variant = _region_index(a["region"])
				if typeof(i) == TYPE_DICTIONARY:
					return i
				var r: Array = DAW.state.regions[i]
				DAW.remove_region(float(r[0]))
				return ControlTool.ok({"regions": _region_rows()})))


# --- lyrics and sections ------------------------------------------------------------------------------

static func _lyrics_and_sections(api: ControlApi) -> void:
	api.add(ControlTool.make("project_lyrics_get",
			"The song's lyrics as LRC text ('[mm:ss.xx] words' lines; plain lines are kept too), and the line count. Empty for none.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				var text: String = DAW.state.lyrics
				return ControlTool.ok({"lyrics": text, "lines": 0 if text.is_empty() else text.split("\n").size()})))

	api.add(ControlTool.make("project_lyrics_set",
			"Replace the song's lyrics with this text (LRC: '[mm:ss.xx] words' per line); empty clears them. One undo step. Returns the game's refusal where the DAW cannot keep lyrics.",
			{"text": ControlTool.str_p("the whole lyrics text")}, ["text"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var why := DAW.set_lyrics(str(a["text"]))
				if not why.is_empty():
					return ControlTool.fail(why)
				var text: String = DAW.state.lyrics
				return ControlTool.ok({"lines": 0 if text.is_empty() else text.split("\n").size()})))

	api.add(ControlTool.make("project_sections_arrange",
			"Rearrange the song's sections (regions) into a new order, laid end to end from the first region's start, as one undo step; the items, automation and markers inside move with them. `order` lists region numbers (from project_region_list, counted from 0) in the order they should play, each exactly once: [2, 0, 1] puts the third first. Fails with the game's reason (overlapping sections, a frozen or locked item in the way, a tempo change inside a section, ...).",
			{"order": ControlTool.arr_p("every region number once, in the new order", {"type": "integer"})}, ["order"], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var order: Array = a["order"]
				for k in order:
					if typeof(k) not in [TYPE_INT, TYPE_FLOAT] or float(k) != floorf(float(k)):
						return ControlTool.fail("order is a list of region numbers")
				var why := DAW.arrange_sections(order)
				if not why.is_empty():
					return ControlTool.fail(why)
				return ControlTool.ok({"regions": _region_rows()})))


# --- history ------------------------------------------------------------------------------------------

static func _history(api: ControlApi) -> void:
	api.add(ControlTool.make("project_history_list",
			"The undo history, oldest first: {step, name, done}. `done` steps can be undone; the rest are redoable. depth is how many are done. Empty when the DAW does not say (Reaper keeps its own).",
			{"limit": ControlTool.int_p("newest this many (default 40)", 1, LIST_MAX)}, [], ControlTool.READ, func(a: Dictionary) -> Dictionary:
				var s := DAW.state
				var rows: Array = []
				for i in s.undo_names.size():
					rows.append({"step": i + 1, "name": str(s.undo_names[i]), "done": i < s.undo_depth})
				var n := int(a.get("limit", 40))
				var from := maxi(0, mini(rows.size() - n, maxi(s.undo_depth - n / 2, 0)))
				return ControlTool.ok({"depth": s.undo_depth, "redo": s.redo_depth, "total": rows.size(), "steps": rows.slice(from, from + n)})))

	api.add(ControlTool.make("project_undo",
			"Undo the last `steps` (default 1) steps of the project's history, whoever made them. (changes_undo takes back what this assistant just did; this is the player's own undo.) Fails when there is nothing to undo.",
			{"steps": ControlTool.int_p("how many (default 1)", 1, 50)}, [], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var s := DAW.state
				if s.undo_depth == 0:
					return ControlTool.fail("nothing to undo")
				for i in int(a.get("steps", 1)):
					DAW.undo()
				return ControlTool.ok({"depth": s.undo_depth, "redo": s.redo_depth})))

	api.add(ControlTool.make("project_redo",
			"Redo the last `steps` (default 1) undone steps. Fails when there is nothing to redo.",
			{"steps": ControlTool.int_p("how many (default 1)", 1, 50)}, [], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var s := DAW.state
				if s.redo_depth == 0:
					return ControlTool.fail("nothing to redo")
				for i in int(a.get("steps", 1)):
					DAW.redo()
				return ControlTool.ok({"depth": s.undo_depth, "redo": s.redo_depth})))

	api.add(ControlTool.make("project_undo_to",
			"Jump the history to `depth` steps done (0 is the project as it was opened), back or forward; see project_history_list.",
			{"depth": ControlTool.int_p("steps done, 0 up to the history's length", 0)}, ["depth"], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				var s := DAW.state
				var total: int = s.undo_names.size()
				if int(a["depth"]) > total:
					return ControlTool.fail("the history has %d steps" % total)
				DAW.undo_to(int(a["depth"]))
				return ControlTool.ok({"depth": s.undo_depth, "redo": s.redo_depth})))


# --- render -------------------------------------------------------------------------------------------

static func _render(api: ControlApi) -> void:
	api.add(ControlTool.make("project_render",
			"Bounce the song to WAV (or FLAC) files beside the project: the mix, or with stems true every track's stem. bits 16, 24 (default) or 32 (float); rate 44100, 48000 (default) or 96000; normalise brings the peak to the engine's target. It can take a while and may finish after this returns: read project_render_status. Fails where the DAW cannot render.",
			{"stems": ControlTool.bool_p("one file per track instead of the mix"), "bits": ControlTool.int_p("16, 24 or 32"), "rate": ControlTool.int_p("44100, 48000 or 96000"),
			"normalise": ControlTool.bool_p("normalise the peak"), "flac": ControlTool.bool_p("write FLAC (16 or 24 bit) instead of WAV")}, [], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var bad := _need(DAWBackend.Capability.RENDER, "render")
				if not bad.is_empty():
					return bad
				var bits := int(a.get("bits", DAW.RENDER_BITS_DEFAULT))
				var rate := int(a.get("rate", DAW.RENDER_RATE_DEFAULT))
				if not (bits in DAW.RENDER_BITS):
					return ControlTool.fail("bits is one of %s" % str(DAW.RENDER_BITS))
				if not (rate in DAW.RENDER_RATES):
					return ControlTool.fail("rate is one of %s" % str(DAW.RENDER_RATES))
				_last_render = {}
				DAW.render(bool(a.get("stems", false)), bits, bool(a.get("normalise", false)), rate, bool(a.get("flac", false)))
				return ControlTool.ok({"asked": true, "note": "read project_render_status for the files"})))

	api.add(ControlTool.make("project_render_status",
			"What the last project_render produced: the files written and any problems, or finished false while it is still going (or none was asked).",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary:
				if _last_render.is_empty():
					return ControlTool.ok({"finished": false})
				return ControlTool.ok({"finished": true, "files": _last_render["files"], "problems": _last_render["problems"]})))


# --- transport ----------------------------------------------------------------------------------------

static func _transport_state() -> Dictionary:
	var s := DAW.state
	return {"playing": s.playing, "recording": s.recording, "position": _pos(s.position_seconds),
			"looping": s.looping, "loop_start_seconds": _round(s.loop_start), "loop_end_seconds": _round(s.loop_end),
			"has_loop_range": s.has_loop_range(), "metronome": s.metronome, "count_in_bars": s.count_in_bars,
			"count_in_play": s.count_in_play, "pre_roll": s.pre_roll, "punch": s.punch}


static func _transport(api: ControlApi) -> void:
	api.add(ControlTool.make("transport_get",
			"The transport: playing, recording, position (seconds and bar.beat), loop on/off and its range (seconds), metronome, count-in bars, whether the count-in also precedes playback, pre-roll, punch.",
			{}, [], ControlTool.READ, func(_a: Dictionary) -> Dictionary: return ControlTool.ok(_transport_state())))

	api.add(ControlTool.make("transport_play", "Start playing from the playhead.", {}, [], ControlTool.EDIT, func(_a: Dictionary) -> Dictionary:
		DAW.transport_play()
		return ControlTool.ok(_transport_state())))

	api.add(ControlTool.make("transport_stop", "Stop playing or recording.", {}, [], ControlTool.EDIT, func(_a: Dictionary) -> Dictionary:
		DAW.transport_stop()
		return ControlTool.ok(_transport_state())))

	api.add(ControlTool.make("transport_record",
			"Start recording onto the armed tracks (count-in and punch settings apply). Arm tracks first with the track tools.",
			{}, [], ControlTool.EDIT, func(_a: Dictionary) -> Dictionary:
				DAW.transport_record()
				return ControlTool.ok(_transport_state())))

	api.add(ControlTool.make("transport_seek",
			"Move the playhead: to `seconds`, or to the start of `bar` (counted from 1, through tempo and signature changes), or to a marker by name.",
			{"seconds": ControlTool.num_p("seconds from the start", 0), "bar": ControlTool.num_p("bar number from 1", 1), "marker": ControlTool.str_p("a marker's name")}, [], ControlTool.EDIT,
			func(a: Dictionary) -> Dictionary:
				var given := int(a.has("seconds")) + int(a.has("bar")) + int(a.has("marker"))
				if given != 1:
					return ControlTool.fail("say exactly one of seconds, bar, marker")
				var to := 0.0
				if a.has("seconds"):
					to = float(a["seconds"])
				elif a.has("bar"):
					to = DAW.state.bar_to_seconds(float(a["bar"]))
				else:
					var key: Variant = _marker_key({"name": a["marker"]})
					if typeof(key) == TYPE_DICTIONARY:
						return key
					to = float(key)
				DAW.seek(to)
				return ControlTool.ok(_transport_state())))

	api.add(ControlTool.make("transport_set",
			"Change transport settings, any of them at once: looping (wrap playback round the loop range), loop_start and loop_end (seconds; equal ends mean no range), metronome (click), count_in_bars (0 to 8 bars of click before recording, heard only while the click is on), count_in_play (the count-in before playback too), pre_roll (the song under the count-in), punch (record only inside the loop range). Returns the transport.",
			{"looping": ControlTool.bool_p("loop on or off"), "loop_start": ControlTool.num_p("loop range start, seconds", 0), "loop_end": ControlTool.num_p("loop range end, seconds", 0),
			"metronome": ControlTool.bool_p("click on or off"), "count_in_bars": ControlTool.int_p("bars of count-in", 0, MixState.COUNT_IN_MAX),
			"count_in_play": ControlTool.bool_p("count in before playback as well"), "pre_roll": ControlTool.bool_p("pre-roll on or off"),
			"punch": ControlTool.bool_p("punch in/out on or off")}, [], ControlTool.EDIT, func(a: Dictionary) -> Dictionary:
				if a.is_empty():
					return ControlTool.fail("say what to set; transport_get reads the settings")
				if a.has("loop_start") or a.has("loop_end"):
					DAW.set_loop_range(_num(a, "loop_start", DAW.state.loop_start), _num(a, "loop_end", DAW.state.loop_end))
				if a.has("looping"):
					DAW.set_looping(bool(a["looping"]))
				if a.has("metronome"):
					DAW.set_metronome(bool(a["metronome"]))
				if a.has("count_in_bars"):
					DAW.set_count_in(int(a["count_in_bars"]))
				if a.has("count_in_play"):
					DAW.set_count_in_play(bool(a["count_in_play"]))
				if a.has("pre_roll"):
					DAW.set_pre_roll(bool(a["pre_roll"]))
				if a.has("punch"):
					DAW.set_punch(bool(a["punch"]))
				return ControlTool.ok(_transport_state())))

	api.add(ControlTool.make("transport_loop_selected",
			"Set the loop round the selected items (first start to last end) and switch looping on. Fails when nothing is selected.",
			{}, [], ControlTool.EDIT, func(_a: Dictionary) -> Dictionary:
				if not DAW.loop_selected_items():
					return ControlTool.fail("nothing is selected; select items first")
				return ControlTool.ok(_transport_state())))
