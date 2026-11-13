class_name RackUserPresets
extends RefCounted

## The player's own rack presets: the rack as it was when SAVE was pressed, one file each in
## `user://patches/presets/<name>.patch.json` (the same file as a saved patch, RackPatchFile, with the title
## the player gave it). Each machine keeps its own; a guest who loads one sends the patch itself, and the
## host checks it like any other (RackPatch.answer "load").

const FOLDER := "presets"
const SUFFIX := ".patch.json"
## The longest title kept.
const MOST_TITLE := 48

## Tests point this elsewhere so they neither read nor write the player's presets.
static var dir_override := ""


## The folder the presets are kept in.
static func dir() -> String:
	if dir_override != "":
		return dir_override
	return "user://%s/%s" % [RackPatchFile.KIND, FOLDER]


## The file name a title is kept under: lower case letters, digits and single underscores.
static func name_of(title: String) -> String:
	var out := ""
	for ch in title.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_") and out != "":
			out += "_"
	return out.trim_suffix("_").substr(0, MOST_TITLE)


static func path_of(name: String) -> String:
	return dir().path_join(name + SUFFIX)


## Every preset kept, sorted by title: `{name, title, path}`. A file that cannot be read is left out.
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir())
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(SUFFIX):
			continue
		var name := f.trim_suffix(SUFFIX)
		var got := RackPatchFile.read(path_of(name))
		if not got["ok"]:
			continue
		var title := String(got.get("title", ""))
		out.append({"name": name, "title": title if title != "" else name.replace("_", " ").capitalize(), "path": path_of(name)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["title"]).naturalnocasecmp_to(String(b["title"])) < 0)
	return out


## Whether a preset is kept under `title`'s name.
static func has(title: String) -> bool:
	var name := name_of(title)
	return name != "" and FileAccess.file_exists(path_of(name))


## Keeps `patch` (a room patch) as the preset `title`, replacing one of the same name. The refusal in words,
## or "".
static func save(title: String, patch: Dictionary) -> String:
	title = title.strip_edges().substr(0, MOST_TITLE)
	var name := name_of(title)
	if name == "":
		return "give the preset a name with a letter or a digit in it"
	if (patch.get("modules", {}) as Dictionary).is_empty():
		return "the rack is empty: there is nothing to keep"
	if DirAccess.make_dir_recursive_absolute(dir()) != OK and not DirAccess.dir_exists_absolute(dir()):
		return "the presets folder could not be made"
	var text := RackPatchFile.text_of(RackPatch.to_dict(RackPatch.sanitize(patch), title))
	var err := RackPatchFile.write_text(path_of(name), text)
	return "" if err == OK else "it could not be written (%s)" % error_string(err)


## The preset `name`'s patch as RackPatch.to_dict makes it (what the "load" ask carries), or {} when it
## cannot be read.
static func patch_dict(name: String) -> Dictionary:
	var path := path_of(name)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data


## Forgets the preset `name` (and the `.bak` beside it). True if it is gone.
static func remove(name: String) -> bool:
	var path := path_of(name)
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	return DirAccess.remove_absolute(path) == OK or not FileAccess.file_exists(path)
