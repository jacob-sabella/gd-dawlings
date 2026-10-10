class_name DataHome
extends RefCounted

## The app was called reaper-3d before it was dawlings, and Godot keeps an app's saved data in a
## folder named after it. Renamed, it would open with none of it: no room layout, no ghost, no
## takes. So, once, everything in the old folder that the new one does not already have is
## copied across. Copied rather than moved, and the old folder is left alone, so going back to
## an older build still finds its data where it left it.

const OLD_NAME := "reaper-3d"
const DONE := ".copied_from_reaper-3d"
## Rebuilt on their own, and not worth the disk. `bin` especially: its helpers are compiled from
## source when they are missing, and a stale copy of one would look newer than its source.
const SKIP := ["logs", "shader_cache", "vulkan", "objectdb_snapshots", "bin"]


## Returns how many files were copied: 0 when there was nothing to do.
static func migrate(new_dir: String = OS.get_user_data_dir(), old_dir: String = "") -> int:
	if old_dir.is_empty():
		old_dir = new_dir.get_base_dir().path_join(OLD_NAME)
	if old_dir == new_dir or not DirAccess.dir_exists_absolute(old_dir):
		return 0
	if FileAccess.file_exists(new_dir.path_join(DONE)):
		return 0
	DirAccess.make_dir_recursive_absolute(new_dir)
	var copied := _copy_missing(old_dir, new_dir, true)
	var mark := FileAccess.open(new_dir.path_join(DONE), FileAccess.WRITE)
	if mark != null:
		mark.store_line("Copied from %s on %s" % [old_dir, Time.get_datetime_string_from_system()])
	return copied


static func _copy_missing(from: String, to: String, top: bool) -> int:
	var dir := DirAccess.open(from)
	if dir == null:
		return 0
	var copied := 0
	for name in dir.get_directories():
		if top and name in SKIP:
			continue
		DirAccess.make_dir_recursive_absolute(to.path_join(name))
		copied += _copy_missing(from.path_join(name), to.path_join(name), false)
	for name in dir.get_files():
		var target := to.path_join(name)
		if FileAccess.file_exists(target):
			continue
		# With its permissions: a script or a program that loses its executable bit in the copy
		# fails later, somewhere that does not mention the rename.
		var mode := FileAccess.get_unix_permissions(from.path_join(name))
		if DirAccess.copy_absolute(from.path_join(name), target, mode if mode > 0 else -1) == OK:
			copied += 1
	return copied
