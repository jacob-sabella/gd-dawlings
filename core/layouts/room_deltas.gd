class_name RoomDeltas
extends Node

## The studio's keeper of the room's delta (docs/layouts.md 5.3, 7, 9): the `RoomDelta` of the room it is
## in, loaded from `user://layouts/rooms/` when a venue is built (`enter`), changed when a piece settles
## somewhere (`settle`), and written a moment later. The host owns it: only the authority writes, and a
## guest `adopt`s the host's `layout` row instead and never touches a file. Positions are per room, so
## the same hoop pushed in the studio and in the rooftop is two deltas.
##
## The write is `RackAutosave`'s: a change only marks the delta dirty and restarts a timer, so a push
## costs nothing more, and when it fires the text is made on the main thread and written, atomically with a
## `.bak`, on a worker. A file that will not read leaves the room at its defaults, is set aside as `.bad`,
## and says so (`Session.notice`).

## Seconds the delta must be still before it is written.
const DEBOUNCE := 1.0

## Tests set this so a studio under test neither reads nor writes the player's saved rooms.
static var disabled := false

## The delta of the room the studio is in (never null).
var delta := RoomDelta.empty(&"", 0)
## What `RoomDelta.apply` made of it over the room's default layout: `{ok, pieces, wiring, groups, flagged}`.
var applied: Dictionary = {}
## Why the last file was not used, in words ("" when it was or there was none).
var last_problem := ""
## Files written, for the tests.
var writes := 0
## Seconds the delta must be still before it is written.
var delay := DEBOUNCE
## Whether this is the host's delta, adopted: then nothing is read or written.
var following := false

## The deltas of the rooms visited since the studio was built, by key: leaving a room and coming back
## finds it as it was left even where nothing can be written.
var _rooms: Dictionary = {}
var _timer := Timer.new()
var _task := -1
## The hash of each room's delta as last read from or written to its file.
var _saved: Dictionary = {}


func _init() -> void:
	name = "RoomDeltas"
	_timer.one_shot = true
	_timer.timeout.connect(flush)
	add_child(_timer)


## The studio is now in room `venue_id` / `arrangement`: the previous room's delta is written if it
## changed, and this one's is read (or empty). A guest that is showing the host's room keeps it.
func enter(venue_id: StringName, arrangement: int) -> void:
	if following:
		return
	var key := RoomDelta.room_key(venue_id, arrangement)
	if key == delta.room:
		return
	flush()
	last_problem = ""
	if _rooms.has(key):
		delta = _rooms[key]
		_resolve()
		return
	delta = RoomDelta.empty(venue_id, arrangement)
	_rooms[key] = delta
	var path := "" if disabled else RoomDeltaFile.path_of(key)
	if path != "":
		var got := RoomDeltaFile.read(path)
		if got["ok"]:
			delta = got["delta"]
			delta.room = key
			delta.base = venue_id
			delta.variant = arrangement
			_rooms[key] = delta
		elif not got["missing"]:
			last_problem = "The saved layout of this room could not be read (%s); it is as it was made." % got["error"]
			RoomDeltaFile.set_aside(path)
			Session.notice.emit(last_problem)
	_saved[key] = delta.to_dict().hash()
	_resolve()


## This player's own room again, after the host's: the venue the profile names.
func enter_own(profile: LayoutProfile) -> void:
	following = false
	var id: StringName = profile.venue if profile != null and Venue.is_known(profile.venue) else Venue.IDS[0]
	delta = RoomDelta.empty(&"", 0)
	enter(id, Venue.known_variant(id, profile.venue_variant if profile != null else 0))


## Where piece `id` is saved to stand in this room: the room's delta; for a stand or rack a player pulled out,
## their own `profile`. Null where nobody moved it.
func saved(id: StringName, profile: LayoutProfile) -> Variant:
	if RoomDelta.owned_by_player(id):
		var key := StringName("floor/%s" % id)
		if profile != null and profile.has_transform(key, Presentation.Mode.STUDIO):
			return profile.transform_for(key, Presentation.Mode.STUDIO, Transform3D.IDENTITY)
		return null
	return delta.transform_of(id)


## Piece `id` has settled at `at`. In the host's delta it is saved as moved, or forgotten when it
## `is_default` (so the next venue or a wider room stands it where that does). A player's own stand or
## rack is saved to their `profile` as it always was.
func settle(id: StringName, at: Transform3D, is_default: bool, profile: LayoutProfile) -> void:
	if RoomDelta.owned_by_player(id):
		if profile != null:
			profile.set_transform(StringName("floor/%s" % id), Presentation.Mode.STUDIO, at)
			profile.save()
		return
	if following:
		return
	if delta.unmove(id) if is_default else delta.move(id, at.origin.x, at.origin.z, ControlRoom.heading(at)):
		_note()


## The host's `layout` row, adopted by a guest: the room as the host has it, kept in memory only. A row that
## is not a delta is ignored.
func adopt(row: Variant) -> void:
	if RoomDelta.problem(row) != "" or (row as Dictionary).is_empty():
		return
	if not following:
		flush()
	following = true
	delta = RoomDelta.from_dict(row)
	_resolve()


## Piece `id` put to where the layout has it (forgotten as moved) and the change written. True if it was moved.
func reset(id: StringName) -> bool:
	var did := delta.unmove(id)
	if did:
		_note()
	return did


## The delta over the room's default layout again (after a change, a load or an adopted row).
func _resolve() -> void:
	var id := delta.base if delta.base != &"" else Venue.IDS[0]
	applied = delta.apply(LiveRoom.layout(id, delta.variant).body)
	if not (applied["flagged"] as Array).is_empty():
		last_problem = "; ".join((applied["flagged"] as Array).map(func(f: Dictionary) -> String: return f["why"]))


## The delta changed: write it after the pause (the host only).
func _note() -> void:
	_resolve()
	if disabled or following or not Session.is_authority():
		return
	if _timer.is_stopped():
		if is_inside_tree():
			_timer.start(delay)
		else:
			flush()
	else:
		_timer.start(delay)


## Writes now if the delta changed since it was last saved, and waits for the file to be on disk.
func flush() -> void:
	_timer.stop()
	wait()
	if disabled or following or delta.room == "" or not Session.is_authority():
		return
	var h := delta.to_dict().hash()
	var path := RoomDeltaFile.path_of(delta.room)
	if h == _saved.get(delta.room, 0) or path == "":
		return
	_saved[delta.room] = h
	if delta.is_empty() and not FileAccess.file_exists(path):
		return
	if not delta.fits():
		last_problem = "This room's layout is too big to save (more than %d bytes)." % RoomDelta.MAX_BYTES
		Session.notice.emit(last_problem)
		return
	_task = WorkerThreadPool.add_task(_write.bind(path, delta.text()))
	wait()


## Waits for a write under way.
func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _write(path: String, text: String) -> void:
	if RackPatchFile.write_text(path, text) == OK:
		writes += 1


func _exit_tree() -> void:
	flush()
