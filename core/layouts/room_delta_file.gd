class_name RoomDeltaFile
extends RefCounted

## A room's delta on disk (docs/layouts.md 9): `user://layouts/rooms/<venue>.<variant>.delta.json`, read
## with a `.bak` fallback and written atomically with a `.bak` of the file it replaces (the same
## write as the rack patch, `RackPatchFile.write_text`). Only the host writes. Nothing here throws: a
## file that cannot be used comes back with the reason in words and the room stays at its defaults.
##
## Named `.delta.json`, not `.layout.json`: the made rooms of the maker (step 12) are layout files in
## the same folder and a scan of the folder for layouts must not meet a delta.

const KIND := "layouts"
const SUB := "rooms/"
const SUFFIX := ".delta.json"

## Tests point the folder somewhere of their own; "" is the player's `user://layouts/rooms/`.
static var dir_override := ""


## The folder, made if missing; "" when it cannot be.
static func dir() -> String:
	var d := dir_override
	if d == "":
		var root := DataHome.dir(KIND)
		if root == "":
			return ""
		d = root + SUB
	if not DirAccess.dir_exists_absolute(d) and DirAccess.make_dir_recursive_absolute(d) != OK:
		return ""
	return d


## The file of room `key`, or "" when there is no folder.
static func path_of(key: String) -> String:
	var d := dir()
	return "" if d == "" else d + key + SUFFIX


## Reads `path`, else its `.bak`. `{ok, delta, error, missing}`: `missing` is a room that has no file
## (nothing wrong); otherwise `error` says why a file was not used (too big, not JSON, not a delta).
static func read(path: String) -> Dictionary:
	var first := _read_one(path)
	if first["ok"] or not FileAccess.file_exists(path + ".bak"):
		return first
	var second := _read_one(path + ".bak")
	return second if second["ok"] else first


static func _read_one(path: String) -> Dictionary:
	var out := {"ok": false, "delta": null, "error": "", "missing": false}
	if not FileAccess.file_exists(path):
		out["error"] = "no file"
		out["missing"] = true
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["error"] = "cannot open (%s)" % error_string(FileAccess.get_open_error())
		return out
	if f.get_length() > RoomDelta.MAX_BYTES:
		out["error"] = "file too large"
		return out
	var json := JSON.new()
	var raw: Variant = json.data if json.parse(f.get_as_text()) == OK else null
	var why := RoomDelta.problem(raw)
	if why != "":
		out["error"] = why if raw is Dictionary else "not JSON"
		return out
	out["ok"] = true
	out["delta"] = RoomDelta.from_dict(raw)
	return out


## Writes `delta` to `path` atomically. OK, or `ERR_FILE_CANT_WRITE` when it is over the size limit.
## Safe to call from a worker thread.
static func write(path: String, delta: RoomDelta) -> Error:
	var text := delta.text()
	if text.to_utf8_buffer().size() > RoomDelta.MAX_BYTES:
		return ERR_FILE_CANT_WRITE
	return RackPatchFile.write_text(path, text)


## Sets a file nobody can read aside as `<path>.bad`, so the next write does not shadow it.
static func set_aside(path: String) -> void:
	for p in [path, path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.rename_absolute(p, path + ".bad")


## Deletes every delta file of the made room `base` (any arrangement, with its `.bak` and `.bad`): a room that is
## gone leaves none behind for a new room of the same name to find.
static func remove_room(base: StringName) -> void:
	var d := dir()
	if d == "":
		return
	for file in DirAccess.get_files_at(d):
		if file.begins_with("%s." % base) and (SUFFIX in file):
			DirAccess.remove_absolute(d + file)
