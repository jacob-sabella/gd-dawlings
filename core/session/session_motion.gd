class_name SessionMotion
extends RefCounted

## What moves in the room: a piece pushed, an item carried, a plane flown, an item used and an instrument struck or
## shaken, each sent to everyone else. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## Where something being pushed is right now, to everyone else. Often and unreliably, like a head:
## a lost one is overtaken by the next.
func send_motion(piece: StringName, x: float, z: float, heading: float) -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._motion.rpc_id(id, piece, x, z, heading, session.local_peer_id)
	else:
		session._motion_up.rpc_id(1, piece, x, z, heading)


func _motion_up(piece: StringName, x: float, z: float, heading: float) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	session.room_motion.emit(piece, x, z, heading, from)
	for id in session.admitting._audience():
		if id != from:
			session._motion.rpc_id(id, piece, x, z, heading, from)


func _motion(piece: StringName, x: float, z: float, heading: float, from: int) -> void:
	session.room_motion.emit(piece, x, z, heading, from)


## Where the thing in my hand is now, relative to my head, to everyone else. As often as a head.
func send_carry(item: StringName, local: Transform3D) -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._carry.rpc_id(id, item, local, session.local_peer_id)
	else:
		session._carry_up.rpc_id(1, item, local)


func _carry_up(item: StringName, local: Transform3D) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	session.item_carried.emit(item, local, from)
	for id in session.admitting._audience():
		if id != from:
			session._carry.rpc_id(id, item, local, from)


func _carry(item: StringName, local: Transform3D, from: int) -> void:
	session.item_carried.emit(item, local, from)


## Where the thing I am flying is, in the session's frame, and how it flies, to everyone else.
## As often as a head, while it is away from its radio.
func send_flier(item: StringName, pose: Transform3D, mode: int) -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._flier.rpc_id(id, item, pose, mode, session.local_peer_id)
	else:
		session._flier_up.rpc_id(1, item, pose, mode)


func _flier_up(item: StringName, pose: Transform3D, mode: int) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	session.item_flown.emit(item, pose, mode, from)
	for id in session.admitting._audience():
		if id != from:
			session._flier.rpc_id(id, item, pose, mode, from)


func _flier(item: StringName, pose: Transform3D, mode: int, from: int) -> void:
	session.item_flown.emit(item, pose, mode, from)


## The thing in my hand, used, for everyone else to hear and see, with the Foley take my hand
## rang (`take`, Item.use_take; -1 for not known).
func send_item_use(item: StringName, down: bool, take := -1) -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._item_use.rpc_id(id, item, down, session.local_peer_id, take)
	else:
		session._item_use_up.rpc_id(1, item, down, take)


func _item_use_up(item: StringName, down: bool, take: int) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	take = clean_take(take)
	session.item_used.emit(item, down, from, take)
	for id in session.admitting._audience():
		if id != from:
			session._item_use.rpc_id(id, item, down, from, take)


func _item_use(item: StringName, down: bool, from: int, take: int) -> void:
	session.item_used.emit(item, down, from, take)


## A guest's Foley take as the host passes it on: one of Foley's (0 to 2^24), or -1 for not known.
static func clean_take(take: int) -> int:
	return take if take >= 0 and take < 1 << 24 else -1


## A shake of the instrument in my hand, or a strike on one that stands still, to everyone else,
## with the song position it was played to (`song`, -1 for not known), whether I snap my hand
## percussion (`snap`), the Foley take my hand rang (`take`, -1 for not known), and where on a fixed
## one I struck it (`zone`).
func send_item_hit(item: StringName, velocity: int, song := -1.0, snap := false, take := -1, zone := &"") -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._item_hit.rpc_id(id, item, velocity, session.local_peer_id, song, snap, take, zone)
	else:
		session._item_hit_up.rpc_id(1, item, velocity, song, snap, take, zone)


func _item_hit_up(item: StringName, velocity: int, song: float, snap: bool, take: int, zone: StringName) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	var hit := clean_item_hit(velocity, song, take)
	zone = clean_zone(zone)
	session.item_hit.emit(item, hit[0], from, hit[1], snap, hit[2], zone)
	for id in session.admitting._audience():
		if id != from:
			session._item_hit.rpc_id(id, item, hit[0], from, hit[1], snap, hit[2], zone)


func _item_hit(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName) -> void:
	session.item_hit.emit(item, velocity, from, song, snap, take, zone)


## A guest's zone as the host passes it on: a short word of lower-case letters, digits and
## underscores, or &"" for anything else. Whether the instrument has it is its own (InstrumentItem.has_zone).
static func clean_zone(zone: StringName) -> StringName:
	var said := String(zone)
	if said.length() > Session.ZONE_MOST:
		return &""
	for c in said:
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "_":
			return &""
	return zone


## A guest's hit as the host passes it on: [velocity 1 to 127, song (-1 for anything not a song
## position), take (-1 for anything not one of Foley's takes)].
static func clean_item_hit(velocity: int, song: float, take: int) -> Array:
	if not is_finite(song) or song < 0.0:
		song = -1.0
	return [clampi(velocity, 1, 127), song, clean_take(take)]


## A key or the pedal on my keys, to everyone else, as it is played. Notes are a few bytes and
## come in tens a second at most, so they go to everyone rather than being asked for; whoever is
## patched into my keys plays them. `source`: what played it (GuestMidi.instruments).
func send_note(kind: int, pitch: int, velocity: int, song := -1.0, source := &"") -> void:
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._note.rpc_id(id, kind, pitch, velocity, session.local_peer_id, song, source)
	else:
		session._note_up.rpc_id(1, kind, pitch, velocity, song, source)


## The track my keys play into, told to the host (0 for none), so it sounds my notes on that
## track's instrument plugin as I play them. A guest's; on a host there is no one to tell.
func send_play_track(track: int) -> void:
	if session._connected() and session.role == session.Role.GUEST:
		session._play_track_up.rpc_id(1, track)


func _play_track_up(track: int) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	track = maxi(track, 0)
	if int(session.play_tracks.get(from, 0)) == track:
		return
	if track > 0:
		session.play_tracks[from] = track
	else:
		session.play_tracks.erase(from)
	session.play_track_changed.emit(from, track)
