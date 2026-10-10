class_name FileSend
extends Node

## Sound files from a guest's machine into the host's project.
##
## The guest sends each file as it is, whatever its format, a slice at a time on a channel of its
## own; the host writes the slices to a folder of incoming files, and once every file of a batch
## is in, brings them in as it would its own (DAW.import_audio_files: read on a worker, placed one
## after another from where the guest let them go), says how it went to the guest, and tells the
## room. The original is sent rather than the guest's own decoding of it: an MP3 is a tenth of its
## WAV, and the host reads every format the guest could.

## Each file is checked here for size before a byte is sent, and again by the host as it arrives.
const MAX_BYTES := 256 * 1024 * 1024
## Slice size, and slices per frame: 4 x 32 KB at 60 frames is about 7.5 MB a second, which a
## LAN carries without queueing everything else on the host behind it.
const SLICE := 32 * 1024
const SLICES_PER_FRAME := 4
## The ENet channel files travel on: their own, so a file in flight never holds up a take, a
## fader or the room.
const FILE_CHANNEL := 6
const INCOMING := "user://incoming"

## Guest: how far the batch being sent has got, 0-1, and its files' names.
signal progress(fraction: float, names: PackedStringArray)

## Guest: batches waiting or being sent, the first the one under way.
## {id, paths, track, at, sizes, sent, file (FileAccess of the file being sent), index}.
var _out: Array = []
var _batches_sent := 0
## Host: batches arriving, by "<peer>:<id>": {from, id, track, at, files: [{name, size, path,
## got, file}], current}.
var _in := {}
## Host: an incoming file's path -> [peer, batch key], until it is brought in.
var _incoming_paths := {}


func _ready() -> void:
	DAW.audio_imported.connect(_on_imported)
	DAW.audio_import_done.connect(_on_import_done)


## Guest: sends `paths` for the host to bring in onto `track` from `at`. Answers why not, or "".
func send(paths: PackedStringArray, track: int, at: float) -> String:
	if Session.role != Session.Role.GUEST or not Session._connected():
		return "not in a session as a guest"
	if track <= 0:
		return "no track to put it on"
	var sizes: Array = []
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return "%s could not be read" % path.get_file()
		if f.get_length() > MAX_BYTES:
			return "%s is over %d MB" % [path.get_file(), MAX_BYTES / (1024 * 1024)]
		sizes.append(f.get_length())
	_batches_sent += 1
	var id := _batches_sent
	_out.append({"id": id, "paths": Array(paths), "track": track, "at": maxf(at, 0.0), "sizes": sizes,
			"sent": 0, "file": null, "index": -1})
	_batch_begin.rpc_id(1, id, track, maxf(at, 0.0), paths.size())
	set_process(true)
	return ""


func sending() -> bool:
	return not _out.is_empty()


func _process(_delta: float) -> void:
	if _out.is_empty() or Session.role != Session.Role.GUEST or not Session._connected():
		if not _out.is_empty() and not Session._connected():
			_out.clear()
		return
	var b: Dictionary = _out[0]
	for n in SLICES_PER_FRAME:
		var f: FileAccess = b["file"]
		if f == null or f.eof_reached() or f.get_position() >= f.get_length():
			if f != null:
				_file_end.rpc_id(1, b["id"])
				b["file"] = null
			b["index"] += 1
			if b["index"] >= (b["paths"] as Array).size():
				_out.pop_front()
				progress.emit(1.0, PackedStringArray((b["paths"] as Array).map(func(p): return p.get_file())))
				return
			var path: String = b["paths"][b["index"]]
			b["file"] = FileAccess.open(path, FileAccess.READ)
			_file_begin.rpc_id(1, b["id"], path.get_file(), int(b["sizes"][b["index"]]))
			continue
		var bytes := f.get_buffer(SLICE)
		b["sent"] += bytes.size()
		_file_slice.rpc_id(1, b["id"], bytes)
	var total := 0
	for s in b["sizes"]:
		total += int(s)
	progress.emit(float(b["sent"]) / maxf(float(total), 1.0),
			PackedStringArray((b["paths"] as Array).map(func(p): return p.get_file())))


# --- the host's side ----------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _batch_begin(id: int, track: int, at: float, count: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not Session.is_authority() or not Session._is_member(from) or count <= 0 or count > 64:
		return
	_in["%d:%d" % [from, id]] = {"from": from, "id": id, "track": track, "at": maxf(at, 0.0),
			"count": count, "files": [], "refused": ""}


@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _file_begin(id: int, file_name: String, size: int) -> void:
	var b := _batch(id)
	if b.is_empty():
		return
	_close_current(b)
	if size <= 0 or size > MAX_BYTES:
		b["refused"] = "%s is over %d MB" % [file_name, MAX_BYTES / (1024 * 1024)]
		return
	DirAccess.make_dir_recursive_absolute(INCOMING)
	var safe := file_name.get_file().validate_filename()
	var path := ProjectSettings.globalize_path(INCOMING.path_join("%d_%d_%d_%s" % [
			b["from"], id, (b["files"] as Array).size(), safe]))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		b["refused"] = "the host could not write %s to its disk" % file_name
		return
	(b["files"] as Array).append({"name": safe, "size": size, "path": path, "got": 0, "file": f})


@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _file_slice(id: int, bytes: PackedByteArray) -> void:
	var b := _batch(id)
	if b.is_empty() or (b["files"] as Array).is_empty():
		return
	var entry: Dictionary = b["files"].back()
	var f: FileAccess = entry["file"]
	if f == null:
		return
	if int(entry["got"]) + bytes.size() > int(entry["size"]):
		# More than it said it was: not this file any more.
		f.close()
		entry["file"] = null
		DirAccess.remove_absolute(entry["path"])
		b["refused"] = "%s was not the size it said" % entry["name"]
		return
	f.store_buffer(bytes)
	entry["got"] = int(entry["got"]) + bytes.size()


@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _file_end(id: int) -> void:
	var b := _batch(id)
	if b.is_empty():
		return
	_close_current(b)
	var done: Array = (b["files"] as Array).filter(func(e): return int(e["got"]) == int(e["size"]))
	if (b["files"] as Array).size() < int(b["count"]) and b["refused"] == "":
		return
	# Every file of the batch is in, or one never will be.
	var from: int = b["from"]
	_in.erase("%d:%d" % [from, id])
	if b["refused"] != "":
		_tell(from, "The host could not take your files: %s." % b["refused"])
	var paths := PackedStringArray(done.map(func(e): return e["path"]))
	for e in b["files"]:
		if not done.has(e):
			DirAccess.remove_absolute(e["path"])
	if paths.is_empty():
		return
	for p in paths:
		_incoming_paths[p] = from
	var refused := DAW.import_audio_files(paths, b["track"], b["at"], Session.name_of(from))
	if not refused.is_empty():
		_tell(from, "The host could not bring in your files: %s." % refused)
		for p in paths:
			_incoming_paths.erase(p)
			DirAccess.remove_absolute(p)


func _batch(id: int) -> Dictionary:
	var from := multiplayer.get_remote_sender_id()
	if not Session.is_authority():
		return {}
	return _in.get("%d:%d" % [from, id], {})


func _close_current(b: Dictionary) -> void:
	if (b["files"] as Array).is_empty():
		return
	var entry: Dictionary = b["files"].back()
	if entry["file"] != null:
		(entry["file"] as FileAccess).close()
		entry["file"] = null


## Host: a file a guest sent is in the project, or could not be. Its copy here goes either way:
## what was brought in is in the takes folder now.
func _on_imported(path: String, result: Dictionary) -> void:
	if not _incoming_paths.has(path):
		return
	var from: int = _incoming_paths[path]
	_incoming_paths.erase(path)
	DirAccess.remove_absolute(path)
	var shown := _shown_name(path)
	if not str(result["error"]).is_empty():
		_tell(from, "Your %s was not brought in: %s." % [shown, result["error"]])


func _on_import_done(brought: PackedStringArray, _failed: PackedStringArray, track: int, who: String) -> void:
	if who.is_empty() or brought.is_empty():
		return
	var where = DAW.state.track(track, false)
	Session.tell_room("%s brought in %s on %s." % [who, ", ".join(Array(brought).map(_shown_name)),
			where.display_name() if where != null else "track %d" % track])


## The name the guest knows a file by: the incoming copy's, less what made it unique here.
static func _shown_name(path: String) -> String:
	var parts := path.get_file().split("_", true, 3)
	return parts[3] if parts.size() == 4 else path.get_file()


func _tell(peer_id: int, text: String) -> void:
	if peer_id == Session.local_peer_id:
		Session.notice.emit(text)
	elif Session._connected() and multiplayer.get_peers().has(peer_id):
		Session._told.rpc_id(peer_id, text)
