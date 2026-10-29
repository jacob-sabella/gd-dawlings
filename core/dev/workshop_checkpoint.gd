class_name WorkshopCheckpoint
extends RefCounted

## What one Workshop request changed in the repo, and how to take exactly that back
## (docs/workshop.md, "Undo").
##
## The tree is never clean: other work is always in it, uncommitted, and the Workshop must never
## touch it. So a request's change is not `git diff` (which is everybody's), but the difference
## between the tree just before it ran and just after, file by file, by git blob id:
##
## - `before` (just before the run): HEAD's commit, and for every file git calls changed or
##   untracked, its blob id and a copy of it (`<dir>/before/<path>`).
## - `after` (once the run is over): every file changed or untracked now, or before, whose blob id
##   differs from what it was (a file clean before is HEAD's): the request's files. For each, a copy
##   of how it was (from the copy, or from HEAD's blob) and how it is now (`<dir>/after/<path>`), a
##   manifest (`changes.json`) and a readable `patch.diff`.
## - `undo`: each of those files put back as it was before, or deleted if it did not exist, but
##   only where it is still exactly as the request left it; one edited since is left alone and said
##   (a conflict), never overwritten.
##
## Everything is in `dir` (shots/workshop/<id>/checkpoint, ignored by git), so Undo works after a
## reload too. Blocking (git and file copies): the Workshop calls these off the main thread.

const ABSENT := "-"
## Paths never counted as a request's: the Workshop's own working files, and the engine submodule.
const IGNORED_PREFIXES := ["shots/", "vendor/", ".godot/"]

var repo := ""
var dir := ""


func _init(repo_path: String, checkpoint_dir: String) -> void:
	repo = repo_path.trim_suffix("/")
	dir = checkpoint_dir.trim_suffix("/")


## The tree as it is just before the request runs. Answers the manifest it saved.
func before() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir.path_join("before"))
	var head := _git(["rev-parse", "HEAD"]).strip_edges()
	var dirty := dirty_paths()
	var ids := blob_ids(dirty)
	var files := {}
	for p in dirty:
		var id: String = ids.get(p, ABSENT)
		files[p] = id
		if id != ABSENT:
			_copy(repo.path_join(p), dir.path_join("before").path_join(p))
	var manifest := {"head": head, "dirty": files, "at": Time.get_datetime_string_from_system()}
	_save(dir.path_join("before.json"), manifest)
	return manifest


## What the request changed, now it is over: [{path, before, after}] (blob ids, ABSENT for no file),
## saved as changes.json with copies and patch.diff beside it.
func after() -> Array:
	var manifest := _load(dir.path_join("before.json"))
	if manifest.is_empty():
		return []
	var head: String = manifest.get("head", "")
	var was: Dictionary = manifest.get("dirty", {})
	var candidates := dirty_paths()
	for p: String in was:
		if not candidates.has(p):
			candidates.append(p)
	var now := blob_ids(candidates)
	var changes: Array = []
	for p in candidates:
		var before_id: String = was[p] if was.has(p) else head_blob(head, p)
		var after_id: String = now.get(p, ABSENT)
		if before_id == after_id:
			continue
		if not was.has(p) and before_id != ABSENT:
			# Clean before: how it was is HEAD's.
			_cat_blob(before_id, dir.path_join("before").path_join(p))
		if after_id != ABSENT:
			_copy(repo.path_join(p), dir.path_join("after").path_join(p))
		changes.append({"path": p, "before": before_id, "after": after_id})
	_save(dir.path_join("changes.json"), {"changes": changes})
	var diff := PackedStringArray()
	for c: Dictionary in changes:
		diff.append(_diff_of(c))
	var f := FileAccess.open(dir.path_join("patch.diff"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(diff))
	return changes


## The request's changes as saved, or [] before `after` has run.
func changes() -> Array:
	return _load(dir.path_join("changes.json")).get("changes", [])


## Each changed file put back as it was before the request, where it is still as the request left
## it. {restored: [path], conflicts: [path]}.
func undo() -> Dictionary:
	var restored := PackedStringArray()
	var conflicts := PackedStringArray()
	var list := changes()
	var paths := PackedStringArray()
	for c: Dictionary in list:
		paths.append(c["path"])
	var now := blob_ids(paths)
	for c: Dictionary in list:
		var p: String = c["path"]
		if now.get(p, ABSENT) != c["after"]:
			conflicts.append(p)
			continue
		var target := repo.path_join(p)
		if c["before"] == ABSENT:
			DirAccess.remove_absolute(target)
		else:
			_copy(dir.path_join("before").path_join(p), target)
		restored.append(p)
	_save(dir.path_join("undone.json"), {"restored": restored, "conflicts": conflicts,
			"at": Time.get_datetime_string_from_system()})
	return {"restored": restored, "conflicts": conflicts}


## The request's `files` as they are now, committed onto `branch` (made from HEAD the first time)
## without touching the working tree, the index or the branch checked out: a private index
## (GIT_INDEX_FILE) read from the branch's tip, the files added to it, a tree and a commit made
## from it, the branch moved to it. Off by default (Workshop.auto_commit). False if git refused.
func commit_to_branch(branch: String, files: PackedStringArray, message: String) -> bool:
	var tip := _git(["rev-parse", "--verify", "--quiet", "refs/heads/" + branch]).strip_edges()
	# The ref's old value for update-ref: its tip, or empty where it is made now.
	var old := tip
	if tip == "":
		tip = _git(["rev-parse", "HEAD"]).strip_edges()
	if tip == "":
		return false
	var index := dir.path_join("commit.index")
	var msg_file := dir.path_join("commit_message.txt")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(msg_file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(message)
	f.close()
	var with_index := func(args: Array) -> Array:
		var out := []
		var code := OS.execute("/usr/bin/env", ["GIT_INDEX_FILE=" + index, "git", "-C", repo] + args, out, true)
		return [code, str(out[0]).strip_edges() if out.size() > 0 else ""]
	var steps: Array = [with_index.call(["read-tree", tip])]
	if steps[-1][0] == 0:
		steps.append(with_index.call(["add", "-A", "--"] + Array(files)))
	if steps[-1][0] == 0:
		steps.append(with_index.call(["write-tree"]))
	var tree: String = steps[-1][1] if steps[-1][0] == 0 else ""
	var made := ""
	if tree != "":
		var out := []
		if OS.execute("git", ["-C", repo, "commit-tree", tree, "-p", tip, "-F", msg_file], out, true) == 0:
			made = str(out[0]).strip_edges()
		else:
			push_warning("Workshop: commit-tree said %s" % str(out[0]).strip_edges() if out.size() > 0 else "")
	elif OS.get_environment("WT_DEBUG") != "":
		print("Workshop: commit_to_branch steps ", steps)
	DirAccess.remove_absolute(index)
	if made == "":
		return false
	var update := ["-C", repo, "update-ref", "refs/heads/" + branch, made]
	if old != "":
		update.append(old)
	return OS.execute("git", update) == 0


## Every path git calls changed or untracked (not ignored), repo-relative, but IGNORED_PREFIXES
## and directories (a submodule).
func dirty_paths() -> PackedStringArray:
	var out := PackedStringArray()
	# Not -z: a String cannot hold the NULs it separates with. Unquoted paths, one a line.
	var raw := _git(["-c", "core.quotePath=false", "status", "--porcelain", "-uall"])
	for entry in raw.split("\n", false):
		if entry.length() < 4:
			continue
		var p := entry.substr(3)
		if p.contains(" -> "):
			p = p.get_slice(" -> ", 1)
		if p.begins_with("\"") and p.ends_with("\""):
			p = p.substr(1, p.length() - 2).c_unescape()
		if _ignored(p) or DirAccess.dir_exists_absolute(repo.path_join(p)):
			continue
		out.append(p)
	return out


## {path: blob id} for `paths` as they are on disk; ABSENT for one that is not there.
func blob_ids(paths: PackedStringArray) -> Dictionary:
	var out := {}
	var present := PackedStringArray()
	for p in paths:
		if FileAccess.file_exists(repo.path_join(p)):
			present.append(p)
		else:
			out[p] = ABSENT
	# In batches, so a long list stays inside the command line's limit.
	var at := 0
	while at < present.size():
		var batch := present.slice(at, at + 200)
		var ids := _git(PackedStringArray(["hash-object", "--"]) + batch).strip_edges().split("\n")
		for k in batch.size():
			out[batch[k]] = ids[k].strip_edges() if k < ids.size() else ABSENT
		at += 200
	return out


## The blob id of `path` in commit `head`, or ABSENT where it has none.
func head_blob(head: String, path: String) -> String:
	if head == "":
		return ABSENT
	var out := []
	var code := OS.execute("git", ["-C", repo, "rev-parse", "--verify", "--quiet", "%s:%s" % [head, path]], out)
	var id := str(out[0]).strip_edges() if out.size() > 0 else ""
	return id if code == 0 and id != "" else ABSENT


func _diff_of(c: Dictionary) -> String:
	var p: String = c["path"]
	var a := dir.path_join("before").path_join(p) if c["before"] != ABSENT else "/dev/null"
	var b := dir.path_join("after").path_join(p) if c["after"] != ABSENT else "/dev/null"
	var out := []
	OS.execute("git", ["diff", "--no-index", "--no-color", "--", a, b], out)
	var text := str(out[0]) if out.size() > 0 else ""
	# Said as the repo's paths, not the checkpoint's copies (git writes an absolute path as
	# `a/home/...`, its leading slash folded into the prefix's).
	for side in ["before", "after"]:
		text = text.replace(dir.path_join(side).trim_prefix("/") + "/", "")
	return text


func _ignored(p: String) -> bool:
	for prefix: String in IGNORED_PREFIXES:
		if p.begins_with(prefix):
			return true
	return false


func _git(args: PackedStringArray) -> String:
	var out := []
	OS.execute("git", PackedStringArray(["-C", repo]) + args, out)
	return str(out[0]) if out.size() > 0 else ""


func _cat_blob(id: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	OS.execute("/bin/sh", ["-c", "git -C %s cat-file blob %s > %s" % [WorkshopRunner.quote(repo), id,
			WorkshopRunner.quote(to)]])


static func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	DirAccess.copy_absolute(from, to)


static func _save(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))


static func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
