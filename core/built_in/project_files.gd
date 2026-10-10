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


## Where a project with this title is saved when nobody has said where.
static func default_path(title: String) -> String:
	var safe := title.strip_edges().validate_filename()
	return DEFAULT_DIR.path_join("%s.%s" % [safe if not safe.is_empty() else "Untitled", EXTENSION])


static func save(backend: OfflineBackend, path: String) -> PackedStringArray:
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
					rendered[role] = _render_part(role, project.tempo, staging)
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
	backend.project_path = path
	backend.name_project()
	return warnings


static func _render_part(role: String, tempo: float, staging: String) -> Dictionary:
	var wav := DemoSong.cached(role, tempo)
	if wav == null:
		wav = DemoSong.to_stream(DemoSong.render(role, tempo))
	if wav == null:
		return {}
	var source := "audio/demo_%s.wav" % role
	wav.save_to_wav(staging.path_join(source))
	return {"source": source, "seconds": DemoSong.loop_seconds(tempo)}


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
	var refused := ProjectBridge.load(project, backend)
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


static func new_project(backend: OfflineBackend) -> PackedStringArray:
	backend.set_media({})
	var refused := ProjectBridge.load(blank(), backend)
	if refused.is_empty():
		backend.project_path = ""
		backend.name_project()
	return refused


static func _clear(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
