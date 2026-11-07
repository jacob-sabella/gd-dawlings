class_name RackAutosave
extends Node

## Keeps the host's rack in `user://patches/_current.patch.json` (docs/mods.md 6.1, decision 4): loaded
## when the rack is built, written a moment after it changes. A change only marks the rack dirty and
## (re)starts a timer, so a knob sweep costs nothing per turn; when the timer fires the patch is turned
## into its dictionary on the main thread (a deep copy, well under a millisecond) and the text and the
## file write happen on a worker thread. A guest never writes: the room's row is the guest's rack.

## Seconds the rack must be still before it is written (the default `delay`).
const DEBOUNCE := 1.5

## Tests set this so a studio built under test neither reads nor writes the player's saved rack.
static var disabled := false

## Where autosaves live when an instance has no `path` of its own; "" is `RackPatchFile.current_path()`.
static var default_path := ""

## Where this autosave lives; "" is `default_path`, then `RackPatchFile.current_path()`.
var path := ""
## Seconds the rack must be still before it is written.
var delay := DEBOUNCE
## How long the last write took on the main thread (microseconds): the dictionary and its hash; and the number of
## files written. For the perf notes and the tests.
var last_build_usec := 0
var writes := 0

var _row: Dictionary = {}
var _timer := Timer.new()
var _task := -1
var _last_hash := 0


func _init() -> void:
	name = "RackAutosave"
	_timer.one_shot = true
	_timer.timeout.connect(flush)
	add_child(_timer)


## The saved rack, put into `row` (`{patch, track}`) when there is one that reads; true then. A file that
## is missing or bad leaves `row` alone. The patch just read counts as already saved.
func restore(row: Dictionary) -> bool:
	if disabled:
		return false
	var file := _path()
	if file == "":
		return false
	var got := RackPatchFile.read(file)
	if not got["ok"]:
		return false
	row["patch"] = got["patch"]
	row["track"] = got["track"]
	_last_hash = RackPatch.to_dict(got["patch"], "", int(got["track"])).hash()
	return true


## The rack `row` (`{patch, track}`, held by reference, read when the write comes) has changed. Only the
## host writes. The write follows `DEBOUNCE` seconds after the last change.
func note(row: Dictionary) -> void:
	if disabled or not Session.is_authority():
		return
	_row = row
	if _timer.is_stopped():
		if is_inside_tree():
			_timer.start(delay)
		else:
			flush()
	else:
		_timer.start(delay)


## Writes now if the rack changed since it was last saved, and waits for the file to be on disk.
func flush() -> void:
	_timer.stop()
	if not _row.is_empty():
		var at := Time.get_ticks_usec()
		var d := RackPatch.to_dict(_row["patch"], "", int(_row.get("track", 0)))
		var h := d.hash()
		last_build_usec = Time.get_ticks_usec() - at
		if h != _last_hash and _path() != "":
			_last_hash = h
			wait()
			_task = WorkerThreadPool.add_task(_write.bind(_path(), d))
		_row = {}
	wait()


## Waits for a write under way.
func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _write(file: String, d: Dictionary) -> void:
	RackPatchFile.write_text(file, RackPatchFile.text_of(d))
	writes += 1


func _path() -> String:
	if path != "":
		return path
	return default_path if default_path != "" else RackPatchFile.current_path()


func _exit_tree() -> void:
	flush()
