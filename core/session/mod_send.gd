class_name ModSend
extends Node

## A host shares its user mods with the guests (docs/mods.md section 13, docs/session.md). The host OFFERS a mod
## folder by what it is (id, name, version, licence, size, file count and a SHA-256 over the file set); a guest who
## lacks it is asked, and only when the player says yes does the host send the files, a slice at a time on the file
## channel like `FileSend`, a couple of slices a frame. The guest keeps nothing until the whole set has arrived,
## the size and count are what the offer said, the hash matches and `ModShare.check` passes; then it installs the
## mod under its own `user://mods`, rescans the registry, and the unavailable plates become the live module.
##
## Declining or ignoring changes nothing: the guest keeps today's unavailable plate and hears the host's sound.
## Only USER mods are offered (the shipped ones are on every machine). A mod holds data and no code, so what travels
## is a fixed list of file kinds (`ModShare.EXTENSIONS`); a plugin file, its state or its licence is never a mod
## and never sent. The host is the authority: it decides what is offered, to whom, and answers one accept with one
## transfer. Nothing here blocks the audio or the frame loop: one mod is read and hashed per frame at most, and a
## transfer is `SLICES_PER_FRAME` slices a frame.

## The ENet channel the slices travel on (`FileSend`'s: files never queue behind a take or a fader).
const FILE_CHANNEL := 6
## Slice size, and slices sent a frame: 2 x 32 KB is about 3.8 MB a second at 60 frames, for any number of guests.
const SLICE := 32 * 1024
const SLICES_PER_FRAME := 2
## Offers a guest keeps waiting at once; the host's open offers per guest are held to the same.
const MAX_OPEN := 8
## States of an offer, on the guest and on the host.
const OFFERED := &"offered"
const RECEIVING := &"receiving"
const INSTALLED := &"installed"
const DECLINED := &"declined"
const FAILED := &"failed"
const HAVE := &"have"

## Guest: the inbox changed (an offer came, was answered, progressed, finished).
signal changed()
## Guest: mod `id` is installed here and the registry has been read again.
signal installed(id: String)

## The registry the offers are made from and installed into; the shared one unless a test sets another.
var registry: ModRegistry = null
## Where an installed mod goes, and the folder that decides what counts as a user mod. "" means `user://mods/`.
var mods_root := ""
## For the suite, in place of the network: called (peer, method, args) with what would have gone by RPC.
var wire: Callable = Callable()

## Guest: the offers, oldest first. Each `{offer, peer, meta, state, why, got, files}`; `meta` is the offer's
## `{id, name, version, licence, size, count, hash}` once checked.
var inbox: Array[Dictionary] = []
## Guest: the bytes of the offer being received: `{offer, files, path, size, held, bytes}`.
var _recv: Dictionary = {}

## Host: file sets read and hashed, by mod id: `{files, meta, mtime}`.
var _bundles := {}
## Host: offers made, by number: `{peer, id, state}`; and the next number.
var _offers := {}
var _next_offer := 0
## Host: peer -> mod ids already offered it, so a mod is offered once a session.
var _asked := {}
## Host: (peer, mod id) pairs waiting for their turn to be read and offered, one a frame.
var _queue: Array[Array] = []
## Host: transfers under way: `{offer, peer, paths, index, pos, open, files}`.
var _serving: Array[Dictionary] = []
## For the suite: transfers finished (host) and mods installed (guest).
var served := 0


func _ready() -> void:
	Session.participant_joined.connect(_on_joined)
	Session.participant_left.connect(forget_peer)
	Session.role_changed.connect(_on_role_changed)


# --- the host: what is offered --------------------------------------------------------------

## The ids of the mods this machine may offer: the available ones in its user mods folder, whose files are all
## plain data (`ModShare`), sorted by id.
func shareable() -> Array[String]:
	var out: Array[String] = []
	var reg := _registry()
	var root := _root()
	for m in reg.mods():
		if m.status == ModManifest.STATUS_OK and m.folder.begins_with(root.trim_suffix("/") + "/"):
			out.append(m.id)
	out.sort()
	return out


## Host: queues every mod `shareable` for guest `peer`, the ones `used_first` ahead.
func offer_all_to(peer: int, used_first: Array = []) -> void:
	var ids := shareable()
	ids.sort_custom(func(a: String, b: String) -> bool: return used_first.has(a) and not used_first.has(b))
	for id in ids:
		_want(peer, id)
	set_process(true)


## Host: the mods a patch now uses, to every guest who has not been asked about them (a mod the guest
## declined is not asked again this session).
func offer_used(ids: Array) -> void:
	if not _is_host():
		return
	var mine := shareable()
	for peer in _guests():
		for id in ids:
			if mine.has(id):
				_want(peer, str(id))
	set_process(true)


func _want(peer: int, id: String) -> void:
	var given: Dictionary = _asked.get(peer, {})
	if given.has(id):
		return
	given[id] = true
	_asked[peer] = given
	_queue.append([peer, id])


## Host: what is waiting for a turn, for the suite.
func queued() -> int:
	return _queue.size()


func _process(_delta: float) -> void:
	if not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_make_offer(int(next[0]), str(next[1]))
	_serve_some()
	if _queue.is_empty() and _serving.is_empty():
		set_process(false)


## Host: reads and hashes the mod `id` (once, until its files change) and offers it to `peer`.
func _make_offer(peer: int, id: String) -> void:
	if not _peer_ok(peer):
		return
	var bundle := _bundle(id)
	if bundle.is_empty():
		return
	var open := 0
	for o in _offers.values():
		if int(o["peer"]) == peer and o["state"] == OFFERED:
			open += 1
	if open >= MAX_OPEN:
		return
	_next_offer += 1
	_offers[_next_offer] = {"peer": peer, "id": id, "state": OFFERED}
	_send(peer, &"offered", [_next_offer, bundle["meta"]])


## The file set and offer of mod `id`, or {} when it cannot be shared (its files fail `ModShare.check`).
func _bundle(id: String) -> Dictionary:
	var m := _registry().mod(id)
	if m == null or m.folder.is_empty():
		return {}
	var held: Dictionary = _bundles.get(id, {})
	var stamp := _stamp(m.folder)
	if held.get("stamp") == stamp:
		return held
	var read := ModShare.read_folder(m.folder)
	if read["why"] != "" or ModShare.check(read["files"], id) != "":
		_bundles.erase(id)
		return {}
	var bundle := {"files": read["files"], "meta": ModShare.describe(read["files"]), "stamp": stamp}
	_bundles[id] = bundle
	return bundle


## A cheap fingerprint of a folder (names and modified times, all the way down), so a changed mod is read again.
static func _stamp(folder: String) -> int:
	var h := 0
	for f in DirAccess.get_files_at(folder):
		h = hash([h, f, FileAccess.get_modified_time(folder.path_join(f))])
	for d in DirAccess.get_directories_at(folder):
		h = hash([h, d, _stamp(folder.path_join(d))])
	return h


## Host: guest `from` said yes to offer `offer_id`: the files go to it, once.
func accepted(offer_id: int, from: int) -> void:
	var o: Dictionary = _offers.get(offer_id, {})
	if o.is_empty() or int(o["peer"]) != from or o["state"] != OFFERED:
		return
	for s in _serving:
		if int(s["peer"]) == from:
			_send(from, &"refused", [offer_id, "one mod at a time"])
			return
	var bundle := _bundle(str(o["id"]))
	if bundle.is_empty():
		_send(from, &"refused", [offer_id, "the host's copy changed and cannot be shared now"])
		o["state"] = FAILED
		return
	o["state"] = RECEIVING
	var paths: Array = (bundle["files"] as Dictionary).keys()
	paths.sort()
	_serving.append({"offer": offer_id, "peer": from, "paths": paths, "index": -1, "pos": 0, "open": false, "files": bundle["files"]})
	set_process(true)


## Host: guest `from` said no to offer `offer_id`, or gave up part way.
func declined(offer_id: int, from: int) -> void:
	var o: Dictionary = _offers.get(offer_id, {})
	if o.is_empty() or int(o["peer"]) != from:
		return
	o["state"] = DECLINED
	_serving = _serving.filter(func(s: Dictionary) -> bool: return int(s["offer"]) != offer_id)


## Host: a frame's worth of the transfers, the oldest first, `SLICES_PER_FRAME` slices in all. A transfer is its
## files in name order: each announced, then sent in `SLICE` pieces, then the end.
func _serve_some() -> void:
	var budget := SLICES_PER_FRAME
	while budget > 0 and not _serving.is_empty():
		var s: Dictionary = _serving[0]
		var peer: int = s["peer"]
		if not _peer_ok(peer):
			_serving.pop_front()
			continue
		var paths: Array = s["paths"]
		var files: Dictionary = s["files"]
		var index: int = s["index"]
		if index < 0 or (s["open"] and int(s["pos"]) >= (files[paths[index]] as PackedByteArray).size()):
			index += 1
			s["index"] = index
			s["pos"] = 0
			s["open"] = false
			if index >= paths.size():
				_serving.pop_front()
				(_offers[s["offer"]] as Dictionary)["state"] = INSTALLED
				_send(peer, &"ended", [s["offer"]])
				served += 1
				continue
		var bytes: PackedByteArray = files[paths[index]]
		if not s["open"]:
			s["open"] = true
			_send(peer, &"file_began", [s["offer"], paths[index], bytes.size()])
			continue
		var upto := mini(int(s["pos"]) + SLICE, bytes.size())
		_send(peer, &"slice", [s["offer"], bytes.slice(int(s["pos"]), upto)])
		s["pos"] = upto
		budget -= 1


## Host: a peer is gone, or the session is: its offers and transfers go.
func forget_peer(peer: int) -> void:
	_asked.erase(peer)
	_queue = _queue.filter(func(q: Array) -> bool: return int(q[0]) != peer)
	_serving = _serving.filter(func(s: Dictionary) -> bool: return int(s["peer"]) != peer)
	for k in _offers.keys():
		if int(_offers[k]["peer"]) == peer:
			_offers.erase(k)


func _on_joined(peer: int) -> void:
	if _is_host() and peer != Session.local_peer_id:
		offer_all_to(peer, _used_by_the_room())


## The mod ids the host's rack patch uses now, read from the room row's `uses`.
func _used_by_the_room() -> Array:
	var row: Variant = Session.room.get(RackPatch.ROW) if Session.room is Dictionary else null
	var out: Array = []
	if row is Dictionary and (row as Dictionary).get("patch") is Dictionary:
		for type in ((row["patch"] as Dictionary).get("uses", {}) as Dictionary):
			out.append(str(((row["patch"]["uses"] as Dictionary)[type] as Dictionary).get("mod", "")))
	return out


# --- the guest: the inbox ---------------------------------------------------------------------

## Guest: the host `from` offers a mod. Checked and put in the inbox if this machine lacks it; ignored if the offer
## is not whole, too many are waiting, or the same mod is already there.
func offered(offer_id: int, meta: Dictionary, from: int) -> void:
	var clean := _clean_meta(meta)
	if clean.is_empty() or inbox.size() >= MAX_OPEN * 4 or _entry(offer_id) != null:
		return
	for e in inbox:
		if e["meta"]["id"] == clean["id"] and e["state"] in [OFFERED, RECEIVING]:
			return
	var have := _registry().mod(clean["id"]) != null or _registry().rejected().any(
			func(r: Dictionary) -> bool: return (r["manifest"] as ModManifest).id == clean["id"])
	inbox.append({"offer": offer_id, "peer": from, "meta": clean, "state": HAVE if have else OFFERED, "why": "", "got": 0})
	changed.emit()


## The offer as `offered` accepts it: ids and strings in range, sizes within the caps, a hash of 64 hex digits.
## {} for anything else.
static func _clean_meta(meta: Dictionary) -> Dictionary:
	var id := str(meta.get("id", ""))
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")
	var hash_ok := RegEx.new()
	hash_ok.compile("^[0-9a-f]{64}$")
	var size: Variant = meta.get("size")
	var count: Variant = meta.get("count")
	if id.length() > 64 or re.search(id) == null or id.begins_with("builtin.") or not size is int or not count is int:
		return {}
	if size < 1 or size > ModShare.MAX_TOTAL_BYTES or count < 1 or count > ModShare.MAX_FILES or hash_ok.search(str(meta.get("hash", ""))) == null:
		return {}
	return {"id": id, "name": str(meta.get("name", id)).left(40), "version": str(meta.get("version", "")).left(20),
			"licence": str(meta.get("licence", "")).left(40), "size": size, "count": count, "hash": str(meta["hash"])}


func _entry(offer_id: int) -> Variant:
	for e in inbox:
		if int(e["offer"]) == offer_id:
			return e
	return null


## Guest: the offers still waiting for an answer, oldest first.
func pending() -> Array[Dictionary]:
	return inbox.filter(func(e: Dictionary) -> bool: return e["state"] == OFFERED)


## Guest: yes to offer `offer_id` (the prompt's Accept). The host starts sending.
func accept(offer_id: int) -> void:
	var e: Variant = _entry(offer_id)
	if e == null or e["state"] != OFFERED or not _recv.is_empty():
		return
	e["state"] = RECEIVING
	_recv = {"offer": offer_id, "files": {}, "path": "", "size": 0, "held": 0, "bytes": PackedByteArray(), "total": 0}
	_send(int(e["peer"]), &"accepted", [offer_id])
	changed.emit()


## Guest: no to offer `offer_id` (the prompt's Decline). Nothing changes: the plate stays.
func decline(offer_id: int) -> void:
	var e: Variant = _entry(offer_id)
	if e == null or e["state"] != OFFERED:
		return
	e["state"] = DECLINED
	_send(int(e["peer"]), &"declined", [offer_id])
	changed.emit()


## Guest: the host starts a file of the offer being received.
func file_began(offer_id: int, path: String, size: int) -> void:
	if _recv.is_empty() or int(_recv["offer"]) != offer_id:
		return
	var e: Dictionary = _entry(offer_id)
	_close_file()
	var bad := ModShare.path_problem(path)
	if bad == "" and ((_recv["files"] as Dictionary).has(path) or (_recv["files"] as Dictionary).size() >= int(e["meta"]["count"])):
		bad = "more files than the offer said"
	if bad == "" and (size < 0 or size > ModShare.MAX_FILE_BYTES or int(_recv["total"]) + size > int(e["meta"]["size"])):
		bad = "more bytes than the offer said"
	if bad != "":
		_fail(e, bad)
		return
	_recv["path"] = path
	_recv["size"] = size
	_recv["bytes"] = PackedByteArray()
	if size == 0:
		_close_file()


## Guest: a slice of the file being received.
func slice(offer_id: int, bytes: PackedByteArray) -> void:
	if _recv.is_empty() or int(_recv["offer"]) != offer_id or _recv["path"] == "":
		return
	if (_recv["bytes"] as PackedByteArray).size() + bytes.size() > int(_recv["size"]) or bytes.size() > SLICE:
		_fail(_entry(offer_id), "a file was not the size the host said")
		return
	var held: PackedByteArray = _recv["bytes"]
	held.append_array(bytes)
	_recv["bytes"] = held
	var e: Dictionary = _entry(offer_id)
	e["got"] = int(_recv["total"]) + (_recv["bytes"] as PackedByteArray).size()
	if (_recv["bytes"] as PackedByteArray).size() == int(_recv["size"]):
		_close_file()
	changed.emit()


## Guest: every file has been sent. The set is checked against the offer and, if whole and clean, installed.
func ended(offer_id: int) -> void:
	if _recv.is_empty() or int(_recv["offer"]) != offer_id:
		return
	var e: Dictionary = _entry(offer_id)
	if _recv["path"] != "":
		_fail(e, "a file arrived short")
		return
	var files: Dictionary = _recv["files"]
	_recv.clear()
	var meta: Dictionary = e["meta"]
	var why := ""
	if files.size() != int(meta["count"]):
		why = "fewer files than the offer said"
	elif ModShare.digest(files) != meta["hash"]:
		why = "the files are not the ones offered (the hash differs)"
	else:
		why = ModShare.check(files, str(meta["id"]))
	if why == "":
		why = ModShare.install(files, str(meta["id"]), _root())
	if why != "":
		e["state"] = FAILED
		e["why"] = why
		changed.emit()
		return
	e["state"] = INSTALLED
	_registry().reload()
	installed.emit(str(meta["id"]))
	changed.emit()


## Guest: the host will not send offer `offer_id`.
func refused(offer_id: int, why: String) -> void:
	var e: Variant = _entry(offer_id)
	if e != null and e["state"] in [OFFERED, RECEIVING]:
		_fail(e, why.left(120))


func _close_file() -> void:
	if _recv.is_empty() or _recv["path"] == "":
		return
	if (_recv["bytes"] as PackedByteArray).size() != int(_recv["size"]):
		return
	(_recv["files"] as Dictionary)[_recv["path"]] = _recv["bytes"]
	_recv["total"] = int(_recv["total"]) + int(_recv["size"])
	_recv["path"] = ""
	_recv["bytes"] = PackedByteArray()


func _fail(e: Dictionary, why: String) -> void:
	e["state"] = FAILED
	e["why"] = why
	_recv.clear()
	_send(int(e["peer"]), &"declined", [e["offer"]])
	changed.emit()


func _on_role_changed() -> void:
	if Session.role != Session.Role.HOST:
		_bundles.clear()
		_offers.clear()
		_asked.clear()
		_queue.clear()
		_serving.clear()
	if Session.role != Session.Role.GUEST:
		inbox.clear()
		_recv.clear()
		changed.emit()


# --- plumbing -----------------------------------------------------------------------------------

func _registry() -> ModRegistry:
	return registry if registry != null else ModRegistry.ensure_current()


func _root() -> String:
	return mods_root if mods_root != "" else DataHome.dir("mods")


func _is_host() -> bool:
	return Session.role == Session.Role.HOST


func _guests() -> Array:
	var out: Array = []
	for id in Session.participants:
		if int(id) != Session.local_peer_id:
			out.append(int(id))
	return out


func _peer_ok(peer: int) -> bool:
	return wire.is_valid() or (Session._connected() and multiplayer.get_peers().has(peer))


## What would go by RPC to `peer`: through `wire` for the suite, or the network.
func _send(peer: int, method: StringName, args: Array) -> void:
	if wire.is_valid():
		wire.call(peer, method, args)
		return
	if not Session._connected():
		return
	match method:
		&"offered": _rpc_offer.rpc_id(peer, args[0], args[1])
		&"file_began": _rpc_file.rpc_id(peer, args[0], args[1], args[2])
		&"slice": _rpc_slice.rpc_id(peer, args[0], args[1])
		&"ended": _rpc_end.rpc_id(peer, args[0])
		&"refused": _rpc_refuse.rpc_id(peer, args[0], args[1])
		&"accepted": _rpc_accept.rpc_id(peer, args[0])
		&"declined": _rpc_decline.rpc_id(peer, args[0])


func _from_host() -> bool:
	return Session.role == Session.Role.GUEST and multiplayer.get_remote_sender_id() == 1


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_offer(offer_id: int, meta: Dictionary) -> void:
	if _from_host():
		offered(offer_id, meta, 1)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_file(offer_id: int, path: String, size: int) -> void:
	if _from_host():
		file_began(offer_id, path, size)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_slice(offer_id: int, bytes: PackedByteArray) -> void:
	if _from_host():
		slice(offer_id, bytes)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_end(offer_id: int) -> void:
	if _from_host():
		ended(offer_id)


@rpc("authority", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_refuse(offer_id: int, why: String) -> void:
	if _from_host():
		refused(offer_id, why)


@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_accept(offer_id: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _is_host() and Session._is_member(from):
		accepted(offer_id, from)


@rpc("any_peer", "call_remote", "reliable", FILE_CHANNEL)
func _rpc_decline(offer_id: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _is_host() and Session._is_member(from):
		declined(offer_id, from)
