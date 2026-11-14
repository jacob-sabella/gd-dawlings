class_name RealmCopy
extends Node

## Copying between realms (docs/realms.md, steps 4 and 5). A visitor asks the realm's owner for:
##
## - RACK: the rack as it is now, kept as one of the visitor's own presets (RackUserPresets);
## - ROOM: the room, when it is one the owner made (MadeRooms), kept as a room of the visitor's own;
## - SONG: the song, the project file with every sound in it (ProjectFiles, saved as a copy), sent a slice at a time
##   and kept in the visitor's projects folder;
##
## and may offer the other way, BRING: one of the visitor's own projects, sent to the owner's projects folder.
##
## The owner's rule (RealmLobby.copy_rule) answers: never, always, or ask (the owner says yes or no in the session
## panel, `pending`). A song brought in always asks: it lands on the owner's disk. Nothing opens by itself: a song
## that arrives is in the projects folder, to open at home.
##
## Files go on FileSend's channel, so they never queue behind a take or a fader. A child of Session ("RealmCopy"),
## built in SessionLife.ready, reached as `Session.realm_copy`.

## Host: the visitors' asks waiting for an answer changed (`pending`).
signal asked()
## Something changed for the panel: an answer, an arrival, a transfer's progress (`status`).
signal changed()

const RACK := "rack"
const ROOM := "room"
const SONG := "song"
const BRING := "bring"
const KINDS := [RACK, ROOM, SONG, BRING]
const CHANNEL := FileSend.FILE_CHANNEL
const SLICE := FileSend.SLICE
const SLICES_PER_FRAME := 4
const MAX_BYTES := FileSend.MAX_BYTES
const OUTGOING := "user://realm/outgoing"
const INCOMING := "user://realm/incoming"
## The most asks a host keeps waiting; more are refused.
const MAX_PENDING := 16

## Host: asks waiting for the owner, oldest first: {peer, kind, title, size}.
var pending: Array[Dictionary] = []
## What is happening, in words, for the panel ("" for nothing).
var status := ""
## Where songs that arrive are kept (ProjectFiles.DEFAULT_DIR); tests point it elsewhere.
var projects_dir := ProjectFiles.DEFAULT_DIR
## Guest: the project offered with BRING, waiting for the owner's yes: its path.
var _offered := ""
## Guest: whether a song was asked for and said yes to (only then are its slices taken).
var _song_expected := false
## Host: the visitors whose BRING was said yes to.
var _bring_accepted: Dictionary = {}
## peer -> {file, path, size, sent, kind, title, temp}
var _out: Dictionary = {}
## peer -> {file, path, size, got, kind, title}
var _in: Dictionary = {}


func _ready() -> void:
	Session.role_changed.connect(_on_role_changed)
	Session.roster_changed.connect(_on_roster_changed)


func _process(_delta: float) -> void:
	for peer in _out.keys():
		_send_some(peer)


# --- asking (a visitor) --------------------------------------------------------------------------------------

## Asks the realm's owner for its rack, room or song. The refusal in words, or "".
func ask(kind: String) -> String:
	if Session.role != Session.Role.GUEST:
		return "you are not visiting anyone"
	if kind not in [RACK, ROOM, SONG]:
		return "there is no such thing to take"
	if kind == SONG and (_song_expected or not _in.is_empty()):
		return "a song is on its way already"
	_tell("Asking %s for their %s…" % [Session.name_of(1), kind])
	_ask.rpc_id(1, kind, "", 0)
	return ""


## Offers one of this player's own projects (`path`, a .dawproject) to the realm's owner. The refusal, or "".
func offer_song(path: String) -> String:
	if Session.role != Session.Role.GUEST:
		return "you are not visiting anyone"
	if not _out.is_empty() or _offered != "":
		return "a song is on its way already"
	if not FileAccess.file_exists(path):
		return "that project is not there"
	var size := _size_of(path)
	if size <= 0 or size > MAX_BYTES:
		return "that project is too big to send (%d MB at most)" % (MAX_BYTES / 1048576)
	_offered = path
	_tell("Offering \"%s\" to %s…" % [path.get_file().get_basename(), Session.name_of(1)])
	_ask.rpc_id(1, BRING, path.get_file().get_basename(), size)
	return ""


## This player's own projects, newest first: [{title, path}].
func own_projects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(projects_dir)
	if d == null:
		return out
	var found: Array = []
	for f in d.get_files():
		if f.get_extension() == ProjectFiles.EXTENSION:
			var p := projects_dir.path_join(f)
			found.append([FileAccess.get_modified_time(p), p])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for f in found:
		out.append({"title": String(f[1]).get_file().get_basename(), "path": f[1]})
	return out


# --- the owner's side ----------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _ask(kind: String, title: String, size: int) -> void:
	if Session.role != Session.Role.HOST:
		return
	var from := multiplayer.get_remote_sender_id()
	if not Session._is_member(from) or kind not in KINDS:
		return
	asked_by(from, kind, title, size)


## A visitor's ask, as it arrives (the RPC's body; the suite calls it straight).
func asked_by(from: int, kind: String, title: String, size: int) -> void:
	var rule := Session.lobby.copy_rule if Session.lobby != null else RealmLobby.COPY_ASK
	if rule == RealmLobby.COPY_NEVER:
		refuse(from, kind, "%s does not let visitors copy from their realm" % Session.local_name)
		return
	if kind == BRING and (size <= 0 or size > MAX_BYTES):
		refuse(from, kind, "that project is too big (%d MB at most)" % (MAX_BYTES / 1048576))
		return
	if rule == RealmLobby.COPY_ALWAYS and kind != BRING:
		serve(from, kind)
		return
	for p in pending:
		if p["peer"] == from and p["kind"] == kind:
			return
	if pending.size() >= MAX_PENDING:
		refuse(from, kind, "%s has too many asks waiting: try again in a moment" % Session.local_name)
		return
	pending.append({"peer": from, "kind": kind, "title": title.left(80), "size": size})
	Session.notice.emit(ask_words(pending[-1]))
	asked.emit()


## An ask in words, for the owner: "Grace asks to copy your rack."
static func ask_words(p: Dictionary) -> String:
	var who := Session.name_of(int(p["peer"]))
	match str(p["kind"]):
		RACK: return "%s asks to copy your rack." % who
		ROOM: return "%s asks to copy this room." % who
		SONG: return "%s asks to copy your song." % who
		BRING: return "%s offers you their song \"%s\" (%s)." % [who, p["title"], _megabytes(int(p["size"]))]
	return ""


## The owner's answer to the ask at `index` of `pending`.
func decide(index: int, yes: bool) -> void:
	if index < 0 or index >= pending.size():
		return
	var p: Dictionary = pending[index]
	pending.remove_at(index)
	asked.emit()
	if not Session._is_member(int(p["peer"])):
		return
	if yes:
		serve(int(p["peer"]), str(p["kind"]))
	else:
		refuse(int(p["peer"]), str(p["kind"]), "%s said no" % Session.local_name)


func refuse(peer: int, kind: String, why: String) -> void:
	_send(peer, &"_answer", [kind, false, why, {}])


## Gives `peer` what it asked for.
func serve(peer: int, kind: String) -> void:
	match kind:
		RACK:
			var row: Variant = Session.room.get(RackPatch.ROW, {})
			var patch: Variant = row.get("patch") if row is Dictionary else null
			if not patch is Dictionary or (patch.get("modules", {}) as Dictionary).is_empty():
				refuse(peer, kind, "the rack is empty")
				return
			_send(peer, &"_answer", [kind, true, "", {"patch": RackPatch.to_dict(RackPatch.sanitize(patch)),
					"owner": Session.local_name}])
		ROOM:
			_send(peer, &"_answer", [kind, true, "", {"venue": str(Session.room.get("venue", "")),
					"made_room": Session.room.get("made_room", {}), "owner": Session.local_name}])
		SONG:
			var why := _send_song(peer)
			if why != "":
				refuse(peer, kind, why)
		BRING:
			_bring_accepted[peer] = true
			_send(peer, &"_answer", [kind, true, "", {"owner": Session.local_name}])


## Saves a copy of the song (the project as it stands, sounds and all) and starts it on its way.
func _send_song(peer: int) -> String:
	if not DAW.backend is OfflineBackend:
		return "%s's DAW keeps its own files" % Session.local_name
	if _out.has(peer):
		return "a song is on its way already"
	DirAccess.make_dir_recursive_absolute(OUTGOING)
	var title := DAW.project_title()
	var path := OUTGOING.path_join("%d_%s.%s" % [peer, title.validate_filename(), ProjectFiles.EXTENSION])
	ProjectFiles.save(DAW.backend, path, true)
	var size := _size_of(path)
	if size <= 0:
		return "the song could not be saved to send"
	if size > MAX_BYTES:
		DirAccess.remove_absolute(path)
		return "the song is too big to send (%d MB at most)" % (MAX_BYTES / 1048576)
	_send(peer, &"_answer", [SONG, true, "", {"title": title, "size": size, "owner": Session.local_name}])
	_start_sending(peer, path, SONG, title, true)
	return ""


# --- answers (a visitor) -------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _answer(kind: String, ok: bool, why: String, payload: Dictionary) -> void:
	if Session.role != Session.Role.GUEST or multiplayer.get_remote_sender_id() != 1:
		return
	answered(kind, ok, why, payload)


## The owner's answer, as it arrives (the RPC's body; the suite calls it straight).
func answered(kind: String, ok: bool, why: String, payload: Dictionary) -> void:
	var owner := str(payload.get("owner", Session.name_of(1)))
	if not ok:
		if kind == BRING:
			_offered = ""
		_tell("Not copied: %s." % why)
		return
	match kind:
		RACK:
			var said := keep_rack(payload.get("patch", {}), "%s's rack" % owner)
			_tell(said)
		ROOM:
			_tell(keep_room(payload, owner))
		SONG:
			_song_expected = true
			_tell("%s's song \"%s\" is on its way (%s)…" % [owner, payload.get("title", ""), _megabytes(int(payload.get("size", 0)))])
		BRING:
			if _offered == "":
				return
			var path := _offered
			_offered = ""
			_start_sending(1, path, BRING, path.get_file().get_basename(), false)
			_tell("Sending \"%s\" to %s…" % [path.get_file().get_basename(), owner])


## Keeps a rack sent as `title` among this player's presets, beside (never over) one of that name. Words for the panel.
func keep_rack(raw: Variant, title: String) -> String:
	if RackPatch.problem(raw) != "":
		return "The rack could not be kept: %s." % RackPatch.problem(raw)
	var named := title
	var n := 2
	while RackUserPresets.has(named):
		named = "%s %d" % [title, n]
		n += 1
	var why := RackUserPresets.save(named, RackPatch.sanitize(raw))
	if why != "":
		return "The rack could not be kept: %s." % why
	return "Kept \"%s\" among your rack presets (PRESETS on the rack)." % named


## Keeps the room an owner sent (`payload`: venue, made_room) as a room of this player's own. Words for the panel.
func keep_room(payload: Dictionary, owner: String) -> String:
	var made: Variant = payload.get("made_room", {})
	if not made is Dictionary or (made as Dictionary).is_empty():
		var venue := StringName(str(payload.get("venue", "")))
		return "This room is one of the game's own (%s): you have it already, in the venue chooser." % \
				(VenueCatalogue.title_of(venue) if VenueCatalogue.has(venue) else str(venue))
	var title := "%s (from %s)" % [str(made.get("title", "Room")), owner]
	var kept := MadeRooms.keep_copy(made, title.left(MadeRoom.MAX_TITLE))
	if not kept["ok"]:
		return "The room could not be kept: %s" % ("; ".join(kept["errors"]) if not kept["errors"].is_empty() else "it would not do")
	return "Kept \"%s\" among your rooms: it is yours at home." % title.left(MadeRoom.MAX_TITLE)


# --- files in slices -----------------------------------------------------------------------------------------

func _start_sending(peer: int, path: String, kind: String, title: String, temp: bool) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_tell("The file could not be read to send.")
		return
	var size := f.get_length()
	_out[peer] = {"file": f, "path": path, "size": size, "sent": 0, "kind": kind, "title": title, "temp": temp}
	_send(peer, &"_begin", [kind, title, size])


func _send_some(peer: int) -> void:
	var o: Dictionary = _out[peer]
	if peer != 1 and not Session._is_member(peer) or Session.role == Session.Role.SOLO:
		_drop_out(peer)
		return
	for i in SLICES_PER_FRAME:
		var f: FileAccess = o["file"]
		if f.get_position() >= int(o["size"]):
			_send(peer, &"_end", [])
			if o["kind"] == BRING:
				_tell("Sent \"%s\" to %s." % [o["title"], Session.name_of(1)])
			_drop_out(peer)
			return
		var bytes := f.get_buffer(SLICE)
		o["sent"] = int(o["sent"]) + bytes.size()
		_send(peer, &"_slice", [bytes])


func _drop_out(peer: int) -> void:
	var o: Dictionary = _out.get(peer, {})
	_out.erase(peer)
	if o.is_empty():
		return
	(o["file"] as FileAccess).close()
	if o["temp"]:
		DirAccess.remove_absolute(o["path"])


@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _begin(kind: String, title: String, size: int) -> void:
	begun(multiplayer.get_remote_sender_id(), kind, title, size)


@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _slice(bytes: PackedByteArray) -> void:
	got(multiplayer.get_remote_sender_id(), bytes)


@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _end() -> void:
	ended(multiplayer.get_remote_sender_id())


## A file starts arriving from `from`: taken only when it was asked for (a song from the owner) or said yes to (a
## visitor's song brought in).
func begun(from: int, kind: String, title: String, size: int) -> void:
	var wanted := (kind == SONG and Session.role == Session.Role.GUEST and from == 1 and _song_expected) \
			or (kind == BRING and Session.role == Session.Role.HOST and _bring_accepted.has(from))
	if not wanted or size <= 0 or size > MAX_BYTES or _in.has(from):
		return
	_song_expected = false
	_bring_accepted.erase(from)
	DirAccess.make_dir_recursive_absolute(INCOMING)
	var path := INCOMING.path_join("%d.part" % from)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_tell("There is nowhere to keep the song arriving.")
		return
	_in[from] = {"file": f, "path": path, "size": size, "got": 0, "kind": kind, "title": title.left(80)}


func got(from: int, bytes: PackedByteArray) -> void:
	var i: Dictionary = _in.get(from, {})
	if i.is_empty():
		return
	if int(i["got"]) + bytes.size() > int(i["size"]):
		_drop_in(from)
		_tell("The song arriving was bigger than it said: it was not kept.")
		return
	(i["file"] as FileAccess).store_buffer(bytes)
	i["got"] = int(i["got"]) + bytes.size()
	status = "\"%s\": %d%%" % [i["title"], roundi(100.0 * int(i["got"]) / maxf(float(i["size"]), 1.0))]
	changed.emit()


func ended(from: int) -> void:
	var i: Dictionary = _in.get(from, {})
	if i.is_empty():
		return
	(i["file"] as FileAccess).close()
	_in.erase(from)
	if int(i["got"]) != int(i["size"]):
		DirAccess.remove_absolute(i["path"])
		_tell("The song arrived short: it was not kept.")
		return
	var who := Session.name_of(from)
	DirAccess.make_dir_recursive_absolute(projects_dir)
	var name := ("%s (from %s)" % [i["title"], who]).validate_filename()
	var to := RealmHome.free_path(projects_dir.path_join("%s.%s" % [name, ProjectFiles.EXTENSION]))
	if DirAccess.rename_absolute(i["path"], to) != OK:
		DirAccess.remove_absolute(i["path"])
		_tell("The song could not be kept.")
		return
	if i["kind"] == SONG:
		_tell("Kept %s's song as \"%s\" in your projects: open it at home." % [who, to.get_file().get_basename()])
	else:
		_tell("%s's song is in your projects as \"%s\"." % [who, to.get_file().get_basename()])


func _drop_in(from: int) -> void:
	var i: Dictionary = _in.get(from, {})
	_in.erase(from)
	if i.is_empty():
		return
	(i["file"] as FileAccess).close()
	DirAccess.remove_absolute(i["path"])


# --- housekeeping --------------------------------------------------------------------------------------------

func _on_role_changed() -> void:
	if Session.role == Session.Role.GUEST:
		return
	# Back on your own (or hosting anew): whatever was on its way to or from a realm is over.
	for peer in _out.keys():
		_drop_out(peer)
	for peer in _in.keys():
		_drop_in(peer)
	_offered = ""
	_song_expected = false
	_bring_accepted.clear()
	if not pending.is_empty():
		pending.clear()
		asked.emit()


func _on_roster_changed() -> void:
	if Session.role != Session.Role.HOST:
		return
	var before := pending.size()
	pending = pending.filter(func(p: Dictionary) -> bool: return Session.participants.has(int(p["peer"])))
	for peer in _in.keys():
		if not Session.participants.has(peer):
			_drop_in(peer)
	for peer in _bring_accepted.keys():
		if not Session.participants.has(peer):
			_bring_accepted.erase(peer)
	if pending.size() != before:
		asked.emit()


func _tell(text: String) -> void:
	status = text
	Session.notice.emit(text)
	changed.emit()


func _send(peer: int, method: StringName, args: Array) -> void:
	if peer != 1 and not Session.participants.has(peer):
		return
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	callv(&"rpc_id", [peer, method] + args)


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else -1


static func _megabytes(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0)
