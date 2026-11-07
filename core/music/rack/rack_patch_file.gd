class_name RackPatchFile
extends RefCounted

## A rack patch on disk (docs/mods.md 6.1): reading one that may be bad, old or newer than this game, and
## writing one atomically with a `.bak` of the file it replaces. Patches live in `user://patches/` and
## only the host writes them. Nothing here throws: a file that cannot be used comes back as an error in
## words and the caller carries on with what it had.

## The folder (under `user://`) patches are kept in.
const KIND := "patches"
## The host's autosave: the rack as it was last left.
const CURRENT := "_current.patch.json"
## Larger files are not read (a patch of the most modules and cables is about 30 kB).
const MAX_BYTES := 262144


## `user://patches/_current.patch.json`, or "" when the folder cannot be made.
static func current_path() -> String:
	var d := DataHome.dir(KIND)
	return "" if d == "" else d + CURRENT


## The bytes a patch dictionary (RackPatch.to_dict) is saved as: sorted keys, so the same patch is always
## the same text.
static func text_of(d: Dictionary) -> String:
	return JSON.stringify(d, "\t", true) + "\n"


## Reads `path`; if that file is missing or unusable, its `.bak`. `{ok, patch, title, track, error}`: when
## `ok` the patch is `RackPatch.from_dict` of the file; otherwise `error` says why (the main file's reason
## when neither reads) and `patch` is empty.
static func read(path: String) -> Dictionary:
	var first := _read_one(path)
	if first["ok"] or not FileAccess.file_exists(path + ".bak"):
		return first
	var second := _read_one(path + ".bak")
	return second if second["ok"] else first


static func _read_one(path: String) -> Dictionary:
	var out := {"ok": false, "patch": RackPatch.empty(), "title": "", "track": 0, "error": ""}
	if not FileAccess.file_exists(path):
		out["error"] = "no file"
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["error"] = "cannot open (%s)" % error_string(FileAccess.get_open_error())
		return out
	if f.get_length() > MAX_BYTES:
		out["error"] = "file too large"
		return out
	var json := JSON.new()
	var raw: Variant = json.data if json.parse(f.get_as_text()) == OK else null
	var why := RackPatch.problem(raw)
	if why != "":
		out["error"] = why if raw is Dictionary else "not JSON"
		return out
	out["ok"] = true
	out["patch"] = RackPatch.from_dict(raw)
	out["title"] = String(raw.get("title", "")) if raw.get("title") is String else ""
	out["track"] = maxi(0, int(raw.get("track", 0))) if raw.get("track") is float or raw.get("track") is int else 0
	return out


## Writes `text` to `path` atomically: to a temp file beside it, the file it replaces kept as `.bak`, then
## the temp file renamed over it. OK, or the error. Safe to call from a worker thread.
static func write_text(path: String, text: String) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	var failed := f.get_error()
	f.close()
	if failed != OK:
		DirAccess.remove_absolute(tmp)
		return failed
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(tmp, path)
