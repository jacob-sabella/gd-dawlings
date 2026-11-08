class_name ModShare
extends RefCounted

## What a user mod looks like as a file set that may travel from a host to a guest, and the checks on
## both ends (docs/mods.md section 13). Pure functions: reading a mod folder into memory, the SHA-256
## the offer carries, the rules a received file set must pass, and installing it under a mods root.
##
## A mod that travels is data and nothing else. Every path must be relative and plain, every file must
## have one of `EXTENSIONS` and not start like a program, and the set must be small: anything else
## rejects the WHOLE mod, on the host (it is never offered) and on the guest (it is never installed).
## A mod never carries native code (docs/mods.md rule 1), and VST/CLAP plugin files are not mods, so
## they are never in a set.

## The only file kinds a shared mod may hold: the manifest and patches, images, sounds, a decorative model,
## and text.
const EXTENSIONS: Array[String] = ["json", "png", "jpg", "ogg", "wav", "glb", "txt", "md"]
## Caps on one mod: files, one file, the whole set, a path's length and how deep it nests.
const MAX_FILES := 64
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_TOTAL_BYTES := 8 * 1024 * 1024
const MAX_PATH := 96
const MAX_DEPTH := 4
## The first bytes (hex) of a program or a library, whatever the file is called: ELF, DOS/PE, Mach-O (both
## byte orders, thin and fat), a `#!` script.
const PROGRAM_MAGICS: Array[String] = ["7f454c46", "4d5a", "cffaedfe", "cefaedfe", "feedfacf", "feedface", "cafebabe", "2321"]


## Reads the mod folder `folder` whole: `{files: {relative path: bytes}, why: ""}`, or `{files: {}, why}` when it
## cannot be shared (a link, a hidden file, more than `MAX_FILES` files or `MAX_TOTAL_BYTES`, an unreadable
## file). The kind of each file is judged by `check`, not here.
static func read_folder(folder: String) -> Dictionary:
	var files := {}
	var why := _walk(folder, "", files, 0)
	return {"files": {} if why != "" else files, "why": why}


## The reason a received or about-to-be-offered file set is not a mod that may be installed, or "" when it is
## one: `files` maps relative path to bytes. Judges paths, extensions, program magics, sizes and counts, then
## the manifest (parses, an id that is not `builtin.`, not a `binary` source). `expect_id` is the id the offer
## named, "" for none.
static func check(files: Dictionary, expect_id := "") -> String:
	if files.is_empty():
		return "no files"
	if files.size() > MAX_FILES:
		return "more than %d files" % MAX_FILES
	var total := 0
	for path: String in files:
		var bad := path_problem(path)
		if bad != "":
			return "%s: %s" % [path.left(40), bad]
		var bytes: PackedByteArray = files[path]
		if bytes.size() > MAX_FILE_BYTES:
			return "%s is over %d MB" % [path, MAX_FILE_BYTES / (1024 * 1024)]
		if is_program(bytes):
			return "%s is a program" % path
		total += bytes.size()
	if total > MAX_TOTAL_BYTES:
		return "over %d MB in all" % (MAX_TOTAL_BYTES / (1024 * 1024))
	return _manifest_problem(files, expect_id)


## Why `path` cannot be a file of a shared mod, or "": it must be relative and plain (no `..`, no leading or doubled
## slash, no backslash or drive colon, no hidden segment, no control character), short and shallow, and end
## in one of `EXTENSIONS`.
static func path_problem(path: String) -> String:
	if path.is_empty() or path.length() > MAX_PATH:
		return "a path of the wrong length"
	if path.begins_with("/") or path.contains("\\") or path.contains(":") or path.contains("//"):
		return "not a relative path"
	var parts := path.split("/")
	if parts.size() > MAX_DEPTH:
		return "nested too deep"
	for part in parts:
		if part.is_empty() or part.begins_with(".") or part.ends_with("."):
			return "a path with a dot segment"
		for i in part.length():
			if part.unicode_at(i) < 32 or part.unicode_at(i) == 127:
				return "a control character in a path"
	if not path.get_extension().to_lower() in EXTENSIONS:
		return "a %s file is not data a mod may carry" % ("." + path.get_extension() if path.get_extension() != "" else "file without an extension")
	return ""


## Whether `bytes` begins like a program or library (`PROGRAM_MAGICS`).
static func is_program(bytes: PackedByteArray) -> bool:
	var head := bytes.slice(0, 4).hex_encode()
	for magic in PROGRAM_MAGICS:
		if head.begins_with(magic):
			return true
	return false


## The SHA-256 (hex) over a file set: for each path in sorted order, the path, a zero, the byte count in
## decimal, a zero and the bytes. The same set always gives the same string; any change to a name or a byte
## gives another.
static func digest(files: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var paths: Array = files.keys()
	paths.sort()
	for path: String in paths:
		var bytes: PackedByteArray = files[path]
		ctx.update(path.to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		ctx.update(str(bytes.size()).to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		ctx.update(bytes)
	return ctx.finish().hex_encode()


## What an offer says about a file set that passed `check`: `{id, name, version, licence, size, count, hash}`.
static func describe(files: Dictionary) -> Dictionary:
	var data := _manifest_of(files)
	var size := 0
	for path: String in files:
		size += (files[path] as PackedByteArray).size()
	return {"id": str(data.get("id", "")), "name": str(data.get("name", "")).left(40),
			"version": str(data.get("version", "")), "licence": str((data.get("licence", {}) as Dictionary).get("spdx", "")).left(40),
			"size": size, "count": files.size(), "hash": digest(files)}


## Writes `files` (already judged by `check`) as the mod `id` under the folder `root`, all or nothing: into a hidden
## sibling first, then renamed into place. Answers why not, or "". An id already installed is left alone.
static func install(files: Dictionary, id: String, root: String) -> String:
	var target := root.path_join(id)
	if DirAccess.dir_exists_absolute(target):
		return "%s is already installed" % id
	var staging := root.path_join(".incoming_" + id)
	_remove_tree(staging)
	for path: String in files:
		var at := staging.path_join(path)
		DirAccess.make_dir_recursive_absolute(at.get_base_dir())
		var f := FileAccess.open(at, FileAccess.WRITE)
		if f == null:
			_remove_tree(staging)
			return "this machine could not write %s" % path
		f.store_buffer(files[path])
		f.close()
	if DirAccess.rename_absolute(staging, target) != OK:
		_remove_tree(staging)
		return "this machine could not put %s in place" % id
	return ""


## Removes the folder `dir` and everything in it (used for staging and by tests).
static func remove_tree(dir: String) -> void:
	_remove_tree(dir)


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func _walk(root: String, rel: String, files: Dictionary, depth: int) -> String:
	var here := root.path_join(rel) if rel != "" else root
	if depth > MAX_DEPTH:
		return "nested too deep"
	var dir := DirAccess.open(here)
	if dir == null:
		return "the folder cannot be read"
	dir.include_hidden = true
	for sub in dir.get_directories():
		var sub_rel := sub if rel == "" else rel + "/" + sub
		if dir.is_link(sub) or sub.begins_with("."):
			return "%s is a link or hidden" % sub_rel
		var why := _walk(root, sub_rel, files, depth + 1)
		if why != "":
			return why
	for name in dir.get_files():
		var path := name if rel == "" else rel + "/" + name
		if dir.is_link(name) or name.begins_with("."):
			return "%s is a link or hidden" % path
		if files.size() >= MAX_FILES:
			return "more than %d files" % MAX_FILES
		var f := FileAccess.open(here.path_join(name), FileAccess.READ)
		if f == null:
			return "%s cannot be read" % path
		if f.get_length() > MAX_FILE_BYTES:
			return "%s is over %d MB" % [path, MAX_FILE_BYTES / (1024 * 1024)]
		files[path] = f.get_buffer(f.get_length())
	return ""


static func _manifest_of(files: Dictionary) -> Dictionary:
	if not files.has("mod.json"):
		return {}
	var json := JSON.new()
	if json.parse((files["mod.json"] as PackedByteArray).get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func _manifest_problem(files: Dictionary, expect_id: String) -> String:
	if not files.has("mod.json"):
		return "no mod.json"
	var data := _manifest_of(files)
	if data.is_empty():
		return "mod.json is not a JSON object"
	var m := ModManifest.parse(data)
	if m.status != ModManifest.STATUS_OK:
		return "mod.json: %s" % (m.errors()[0].message if not m.errors().is_empty() else "not a valid manifest")
	if m.id.begins_with("builtin."):
		return "%s is a name only the game's own mods use" % m.id
	if expect_id != "" and m.id != expect_id:
		return "mod.json names %s, not the %s offered" % [m.id, expect_id]
	if str(m.source.get("kind", "")) == "binary":
		return "a mod with a binary source carries native code"
	return ""
