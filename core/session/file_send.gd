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
##
## And the other way, one file at a time (`fetch`, docs/spatial_loop.md part two, slice 25): a guest
## holding an audio cassette to its ear asks the host once for the file the clip plays, by name. The
## host sends it from its project's media folder, on the same channel and a slice at a time, but only
## a file something in the room plays (an item of the song, or a made cassette's clip); the guest
## keeps it in FETCHED for as long as it is a guest there, and plays it from that copy.

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
## Guest: where the host's files it fetched are kept, by their names, while it is a guest.
const FETCHED := "user://fetched"

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

## Guest: a fetch finished, its copy here at `path`; or the host could not send it, and `why`.
signal fetched(file_name: String, path: String)
signal fetch_failed(file_name: String, why: String)

## Guest: each file asked of the host, by name: {state: FETCHING, FETCHED or REFUSED, size, got,
## file (FileAccess while it arrives), why}. A name is asked once: `fetch` again does nothing.
var _fetches := {}
## Guest: how many fetches have been asked of the host, for the suite.
var fetches_asked := 0
## Host: files being sent to guests, oldest first: {peer, fname, file (FileAccess), size}; and how
## many have been sent whole.
var _serving: Array = []
var fetches_served := 0
## For the suite, in place of the network: called (peer, method, args) with what would have gone
## by RPC, the handler's own name (`fetch_asked`, `fetch_began`, ...) and its arguments.
var wire: Callable = Callable()

const FETCHING := &"fetching"
const FETCHED_STATE := &"fetched"
const REFUSED := &"refused"


func _ready() -> void:
	DAW.audio_imported.connect(_on_imported)
	DAW.audio_import_done.connect(_on_import_done)
	Session.role_changed.connect(_on_role_changed)


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
	_serve_some()
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


# --- a host's file, fetched by a guest (docs/spatial_loop.md part two, slice 25) ------------------

## Guest: asks the host for its file `file_name` (a clip's source, by name), once. Answers why not, or
## "": asked now, or already asked, arriving or here.
func fetch(file_name: String) -> String:
	var fname := file_name.get_file()
	if fname.is_empty() or fname.validate_filename() != fname:
		return "%s is not a file name" % file_name
	if _fetches.has(fname):
		return ""
	if Session.role != Session.Role.GUEST:
		return "not in a session as a guest"
	if not wire.is_valid() and not Session._connected():
		return "not connected to the host"
	_fetches[fname] = {"state": FETCHING, "size": 0, "got": 0, "file": null, "why": ""}
	fetches_asked += 1
	_send(1, &"fetch_asked", [fname])
	return ""


## Guest: where `file_name` is if it has been fetched here, or "".
func fetched_path(file_name: String) -> String:
	var fname := file_name.get_file()
	var f: Dictionary = _fetches.get(fname, {})
	if f.get("state") != FETCHED_STATE:
		return ""
	var path := ProjectSettings.globalize_path(FETCHED.path_join(fname))
	return path if FileAccess.file_exists(path) else ""


## Guest: where a fetch of `file_name` is: FETCHING, FETCHED_STATE, REFUSED, or &"" never asked.
func fetch_state(file_name: String) -> StringName:
	return (_fetches.get(file_name.get_file(), {}) as Dictionary).get("state", &"")


## Guest: why the host refused `file_name`, or "".
func fetch_refusal(file_name: String) -> String:
	return str((_fetches.get(file_name.get_file(), {}) as Dictionary).get("why", ""))


## Host: guest `from` asked for `file_name`. Sent from the media folder if something in the room
## plays it (`_plays_here`), a slice at a time (`_serve_some`); refused with why otherwise.
func fetch_asked(file_name: String, from: int) -> void:
	var fname := file_name.get_file()
	for s in _serving:
		if s["peer"] == from and s["fname"] == fname:
			return
	var path := DAW.backend.media_path(fname) if DAW.backend != null else ""
	var why := ""
	if fname.is_empty() or fname != file_name or not _plays_here(fname):
		why = "nothing in the room plays %s" % file_name.get_file()
	elif path.is_empty() or not FileAccess.file_exists(path):
		why = "%s is not on the host's machine either" % fname
	var f := FileAccess.open(path, FileAccess.READ) if why.is_empty() else null
	if why.is_empty() and f == null:
		why = "the host could not read %s" % fname
	elif f != null and (f.get_length() <= 0 or f.get_length() > MAX_BYTES):
		why = "%s is over %d MB" % [fname, MAX_BYTES / (1024 * 1024)]
		f.close()
		f = null
	if not why.is_empty():
		_send(from, &"fetch_refused", [fname, why])
		return
	_serving.append({"peer": from, "fname": fname, "file": f, "size": f.get_length()})
	_send(from, &"fetch_began", [fname, f.get_length()])


## Whether something in the room plays file `fname`: an item of the song, or a made cassette's clip.
## A guest may fetch only those, never whatever else is in the host's folder.
static func _plays_here(fname: String) -> bool:
	if DAW.state != null:
		for index in DAW.state.track_indices():
			for it: MixState.ItemState in DAW.state.track(index).items:
				if it.source.get_file() == fname:
					return true
	for id in Session.made:
		var row: Variant = Session.made[id]
		if row is Array and (row as Array).size() == 3 and row[2] is PackedByteArray:
			var data: Variant = bytes_to_var(row[2])
			if data is Dictionary and data.get("clip") is Dictionary \
					and str((data["clip"] as Dictionary).get("source", "")).get_file() == fname:
				return true
	return false


## Host: a frame's worth of the files being fetched, the oldest first, SLICES_PER_FRAME slices in all.
func _serve_some() -> void:
	var budget := SLICES_PER_FRAME
	while budget > 0 and not _serving.is_empty():
		var s: Dictionary = _serving[0]
		var f: FileAccess = s["file"]
		if not wire.is_valid() and (not Session._connected() or not multiplayer.get_peers().has(int(s["peer"]))):
			f.close()
			_serving.pop_front()
			continue
		if f.get_position() >= f.get_length():
			f.close()
			_serving.pop_front()
			_send(int(s["peer"]), &"fetch_ended", [s["fname"]])
			fetches_served += 1
			continue
		_send(int(s["peer"]), &"fetch_got", [s["fname"], f.get_buffer(SLICE)])
		budget -= 1


## Guest: the host is sending `file_name`, `size` bytes, into FETCHED.
func fetch_began(file_name: String, size: int) -> void:
	var f: Dictionary = _fetches.get(file_name, {})
	if f.get("state") != FETCHING or size <= 0 or size > MAX_BYTES:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FETCHED))
	var into := FileAccess.open(ProjectSettings.globalize_path(FETCHED.path_join(file_name + ".part")), FileAccess.WRITE)
	if into == null:
		_refused_here(file_name, "this machine could not write %s to its disk" % file_name)
		return
	f["size"] = size
	f["got"] = 0
	f["file"] = into


## Guest: a slice of `file_name`.
func fetch_got(file_name: String, bytes: PackedByteArray) -> void:
	var f: Dictionary = _fetches.get(file_name, {})
	var into: FileAccess = f.get("file")
	if into == null:
		return
	if int(f["got"]) + bytes.size() > int(f["size"]):
		_refused_here(file_name, "%s was not the size it said" % file_name)
		return
	into.store_buffer(bytes)
	f["got"] = int(f["got"]) + bytes.size()


## Guest: all of `file_name` sent: kept under its own name, and said.
func fetch_ended(file_name: String) -> void:
	var f: Dictionary = _fetches.get(file_name, {})
	var into: FileAccess = f.get("file")
	if into == null:
		return
	into.close()
	f["file"] = null
	var part := ProjectSettings.globalize_path(FETCHED.path_join(file_name + ".part"))
	if int(f["got"]) != int(f["size"]):
		_refused_here(file_name, "%s arrived short" % file_name)
		return
	var path := ProjectSettings.globalize_path(FETCHED.path_join(file_name))
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(part, path)
	f["state"] = FETCHED_STATE
	fetched.emit(file_name, path)


## Guest: the host will not send `file_name`, and why.
func fetch_refused(file_name: String, why: String) -> void:
	if (_fetches.get(file_name, {}) as Dictionary).get("state") == FETCHING:
		_refused_here(file_name, why)


func _refused_here(file_name: String, why: String) -> void:
	var f: Dictionary = _fetches[file_name]
	var into: FileAccess = f.get("file")
	if into != null:
		into.close()
	f["file"] = null
	f["state"] = REFUSED
	f["why"] = why
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FETCHED.path_join(file_name + ".part")))
	fetch_failed.emit(file_name, why)


## No longer a guest: the fetched copies were that host's, and go.
func _on_role_changed() -> void:
	if Session.role == Session.Role.GUEST:
		return
	forget_fetched()


## Every fetch forgotten, and the copies in FETCHED gone.
func forget_fetched() -> void:
	for fname in _fetches:
		var into: FileAccess = (_fetches[fname] as Dictionary).get("file")
		if into != null:
			into.close()
	_fetches.clear()
	var dir := ProjectSettings.globalize_path(FETCHED)
	if DirAccess.dir_exists_absolute(dir):
		for n in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(n))


## What would go by RPC to `peer`: through `wire` for the suite, or the network.
func _send(peer: int, method: StringName, args: Array) -> void:
	if wire.is_valid():
		wire.call(peer, method, args)
		return
	if not Session._connected():
		return
	match method:
		&"fetch_asked": _fetch_ask.rpc_id(peer, args[0])
		&"fetch_began": _fetch_begin.rpc_id(peer, args[0], args[1])
		&"fetch_got": _fetch_slice.rpc_id(peer, args[0], args[1])
		&"fetch_ended": _fetch_end.rpc_id(peer, args[0])
		&"fetch_refused": _fetch_refuse.rpc_id(peer, args[0], args[1])


@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _fetch_ask(file_name: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if Session.is_authority() and Session._is_member(from):
		fetch_asked(file_name, from)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _fetch_begin(file_name: String, size: int) -> void:
	if Session.role == Session.Role.GUEST and multiplayer.get_remote_sender_id() == 1:
		fetch_began(file_name, size)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _fetch_slice(file_name: String, bytes: PackedByteArray) -> void:
	if Session.role == Session.Role.GUEST and multiplayer.get_remote_sender_id() == 1:
		fetch_got(file_name, bytes)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _fetch_end(file_name: String) -> void:
	if Session.role == Session.Role.GUEST and multiplayer.get_remote_sender_id() == 1:
		fetch_ended(file_name)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _fetch_refuse(file_name: String, why: String) -> void:
	if Session.role == Session.Role.GUEST and multiplayer.get_remote_sender_id() == 1:
		fetch_refused(file_name, why.substr(0, 200))
