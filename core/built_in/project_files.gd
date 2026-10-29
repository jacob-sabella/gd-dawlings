class_name ProjectFiles
extends RefCounted

## Saving and opening projects for the engines that own their files (the built-in engine and the
## stand-in), through dawkit's DAWproject support.
##
## What this adds to dawkit is the game's side of the media. A recorded take lives in the takes
## folder by file name; a demo-song item has no file at all, only a part the engine synthesises
## for its track. On save both become real files in the project: the take is copied in, and each
## demo part is rendered to a WAV once and every item that plays it becomes a looped clip of it,
## starting at the point in the loop the song had reached there. So another DAW opening the file
## hears the song, not empty clips. On open, the file's media are unpacked into a folder of their
## own and the engine is told where each one is.

const DEFAULT_DIR := "user://projects"
const STAGING := "user://project_staging"
const OPEN_DIR := "user://open_project"
const EXTENSION := "dawproject"
## What the game keeps in a project that neither DAWproject nor dawkit has a word for, in the
## same zip: each track's width (TrackState.width), by its id (ProjectBridge.id_of), where it is
## not full. Another program ignores an entry it does not know, as it does dawkit's extras.
const EXTRAS := "dawlings/extras.json"


## Where a project with this title is saved when nobody has said where.
static func default_path(title: String) -> String:
	var safe := title.strip_edges().validate_filename()
	return DEFAULT_DIR.path_join("%s.%s" % [safe if not safe.is_empty() else "Untitled", EXTENSION])


## `copy`: an autosave's -- written there, but the project is still where it was and still has
## its unsaved changes.
static func save(backend: OfflineBackend, path: String, copy := false) -> PackedStringArray:
	if path.is_empty():
		path = backend.project_path if not backend.project_path.is_empty() else default_path(backend.project_title)
	var project := ProjectBridge.capture(backend)
	var staging := ProjectSettings.globalize_path(STAGING)
	_clear(staging)
	DirAccess.make_dir_recursive_absolute(staging.path_join("audio"))
	var warnings := PackedStringArray()
	var rendered := {}
	for t in project.tracks:
		# The part the track plays live, by the track, not its name: it may have been renamed.
		var live = backend.state.track(ProjectBridge.index_of(t.id), false)
		var role: String = live.part if live != null else ""
		for c in t.clips:
			if not c.source.is_empty():
				var from := backend.media_path(c.source)
				var name := c.source.get_file()
				if from.is_empty() or not FileAccess.file_exists(from):
					warnings.append("the take %s is not on this machine" % name)
					continue
				DirAccess.copy_absolute(from, staging.path_join("audio").path_join(name))
				c.source = "audio/" + name
			elif c.notes.is_empty() and not role.is_empty():
				if not rendered.has(role):
					rendered[role] = _render_part(role, project.tempo, backend.parts_signature(), staging)
				var part: Dictionary = rendered[role]
				if part.is_empty():
					continue
				c.source = part["source"]
				c.loop_start = 0.0
				c.loop_end = part["seconds"]
				# The engine plays a part locked to the song's bar grid, not to the item's start.
				c.source_offset = fposmod(c.start, part["seconds"])
				# An item on a loop boundary lands a rounding error either side of it: either is
				# the top of the loop.
				if c.source_offset < 0.000001 or part["seconds"] - c.source_offset < 0.000001:
					c.source_offset = 0.0
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	warnings.append_array(DawKitDawproject.save(project, abs_path, staging))
	warnings.append_array(_keep_lyrics(backend.state.lyrics, abs_path))
	warnings.append_array(_keep_extras(backend, abs_path))
	if copy:
		return warnings
	backend.project_path = path
	backend.name_project()
	backend.mark_clean()
	return warnings


## The game's own extras (EXTRAS) added to the project file just written at `path`: nothing when
## every track is full width.
static func _keep_extras(backend: OfflineBackend, path: String) -> PackedStringArray:
	var widths := {}
	for index in backend.state.track_indices():
		var w: float = backend.state.track(index).width
		if w < 1.0:
			widths[ProjectBridge.id_of(index)] = w
	if widths.is_empty():
		return PackedStringArray()
	var zip := ZIPPacker.new()
	if zip.open(path, ZIPPacker.APPEND_ADDINZIP) != OK:
		return PackedStringArray(["the tracks' widths could not be added to %s" % path.get_file()])
	zip.start_file(EXTRAS)
	zip.write_file(JSON.stringify({"format": 1, "widths": widths}, "  ").to_utf8_buffer())
	zip.close_file()
	zip.close()
	return PackedStringArray()


## The song's lyrics (MixState.lyrics) in the metadata of the project file just written at `path`,
## as its Comment: DAWproject's own field for words about the project, which another program shows
## as the project's comment. dawkit writes only the Title, so the file is written again with
## metadata.xml given the Comment and every other entry as it was. Nothing when there are none.
static func _keep_lyrics(lyrics: String, path: String) -> PackedStringArray:
	if lyrics.strip_edges().is_empty():
		return PackedStringArray()
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return PackedStringArray(["the lyrics could not be added to %s" % path.get_file()])
	var entries := {}
	for name in reader.get_files():
		entries[name] = reader.read_file(name)
	reader.close()
	var meta: DawKitXml = DawKitXml.parse(entries["metadata.xml"]) if entries.has("metadata.xml") else null
	if meta == null:
		meta = DawKitXml.new("MetaData")
	var comment := meta.first("Comment")
	if comment == null:
		comment = meta.add("Comment")
	comment.text = lyrics
	entries["metadata.xml"] = meta.to_text().to_utf8_buffer()
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return PackedStringArray(["the lyrics could not be added to %s" % path.get_file()])
	for name in entries:
		zip.start_file(name)
		zip.write_file(entries[name])
		zip.close_file()
	zip.close()
	return PackedStringArray()


## The lyrics kept in the project file at `path` (its metadata's Comment), or empty: a file without
## them, or from a program that wrote no comment.
static func lyrics_of(path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(path)) != OK:
		return ""
	var out := ""
	if "metadata.xml" in zip.get_files():
		var meta := DawKitXml.parse(zip.read_file("metadata.xml"))
		if meta != null and meta.first("Comment") != null:
			out = Lyrics.clean(meta.first("Comment").text)
	zip.close()
	return out


## The game's extras in the project file at `path` ({"widths": {track id: width}}), or empty for
## a file without them: one from before, or from another program.
static func extras_of(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(path)) != OK:
		return {}
	var out := {}
	if EXTRAS in zip.get_files():
		var parsed = JSON.parse_string(zip.read_file(EXTRAS).get_string_from_utf8())
		if parsed is Dictionary and parsed.get("widths") is Dictionary:
			out["widths"] = parsed["widths"]
	zip.close()
	return out


static func _render_part(role: String, tempo: float, sig: Vector2i, staging: String) -> Dictionary:
	var wav := DemoSong.cached(role, tempo, sig)
	if wav == null:
		wav = DemoSong.to_stream(DemoSong.render(role, tempo, sig))
	if wav == null:
		return {}
	var source := "audio/demo_%s.wav" % role
	wav.save_to_wav(staging.path_join(source))
	return {"source": source, "seconds": DemoSong.loop_seconds(tempo, sig)}


static func open(backend: OfflineBackend, path: String) -> PackedStringArray:
	var media := ProjectSettings.globalize_path(OPEN_DIR)
	_clear(media)
	var result := DawKitDawproject.open(ProjectSettings.globalize_path(path), media)
	var project: DawKitProject = result["project"]
	if project == null:
		return PackedStringArray([result["error"]])
	# The game names a clip's file by name alone (a guest learns nothing of the host's disk),
	# so a file is known by its name and the engine is told where each name is.
	var where := {}
	for t in project.tracks:
		for c in t.clips:
			if c.source.is_empty():
				continue
			var name := c.source.get_file()
			# A file the project plays from outside itself comes with its own path.
			var full := c.source if c.source.is_absolute_path() else media.path_join(c.source)
			var n := 2
			while where.has(name) and where[name] != full:
				name = "%s_%d.%s" % [c.source.get_file().get_basename(), n, c.source.get_extension()]
				n += 1
			where[name] = full
			c.source = name
	backend.set_media(where)
	var refused := ProjectBridge.load(project, backend, {}, extras_of(path).get("widths", {}), lyrics_of(path))
	if not refused.is_empty():
		return refused
	backend.project_path = path
	backend.name_project()
	return result["warnings"]


## An empty project: a few tracks to start in, at a common tempo.
static func blank(title := "Untitled", tracks := 4) -> DawKitProject:
	var p := DawKitProject.new()
	p.title = title
	p.tempo = 120.0
	p.length = 60.0 * 4
	for i in tracks:
		p.add_track("Track %d" % (i + 1))
	return p


static func new_project(backend: OfflineBackend, tracks := 4) -> PackedStringArray:
	backend.set_media({})
	var refused := ProjectBridge.load(blank("Untitled", tracks), backend)
	if refused.is_empty():
		backend.project_path = ""
		backend.name_project()
	return refused


## Where project templates are kept: DAWproject files like any other, with the sound taken out.
const TEMPLATE_DIR := "user://templates"


static func template_path(template_name: String) -> String:
	var safe := template_name.strip_edges().validate_filename()
	return TEMPLATE_DIR.path_join("%s.%s" % [safe if not safe.is_empty() else "Template", EXTENSION])


## The templates there are, by name, in order.
static func templates() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir != null:
		for file in dir.get_files():
			if file.get_extension().to_lower() == EXTENSION:
				out.append(file.get_basename())
	out.sort()
	return out


## A project's layout without its content: the tracks, folders, groups, VCAs, routing, effects (with
## their saved state), levels, tempo and click stay; clips, comps, freezes, automation, markers and
## regions go.
static func layout_of(project: DawKitProject) -> DawKitProject:
	for t in project.tracks:
		if t.is_frozen():
			t.unfreeze()
		t.clips.clear()
		t.comp = []
		t.automation.clear()
	project.master.automation.clear()
	project.markers.clear()
	project.regions.clear()
	project.length = 60.0 * 4
	project.loop_on = false
	return project


## Keeps the project's layout as a template called `template_name`. The project itself is untouched.
static func save_template(backend: OfflineBackend, template_name: String) -> PackedStringArray:
	var project := layout_of(ProjectBridge.capture(backend))
	project.title = template_name
	var path := ProjectSettings.globalize_path(template_path(template_name))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var staging := ProjectSettings.globalize_path(STAGING)
	_clear(staging)
	return DawKitDawproject.save(project, path, staging)


## A new, unsaved project laid out as the template.
static func new_from_template(backend: OfflineBackend, template_name: String) -> PackedStringArray:
	var path := template_path(template_name)
	if not FileAccess.file_exists(path):
		return PackedStringArray(["there is no template called %s" % template_name])
	var said := open(backend, path)
	backend.project_path = ""
	backend.project_title = "Untitled"
	backend.name_project()
	return said


## Empty `dir`, making it if it is not there. Through DirAccess rather than `rm -rf`, which is not
## there to run on Windows or on a standalone headset (Android has no shell for a game to use).
static func _clear(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)


static func _remove_tree(dir: String) -> void:
	var at := DirAccess.open(dir)
	if at == null:
		return
	# Dotfiles too, or the folder is not empty and stays.
	at.include_hidden = true
	for sub in at.get_directories():
		_remove_tree(dir.path_join(sub))
	for file in at.get_files():
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
