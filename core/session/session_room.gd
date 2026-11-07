class_name SessionRoom
extends RefCounted

## The room as the host has it: the made items' rows, handing one over, publishing the room, a guest's asks of it,
## and the tour run and the Rig Roulette roll as the host publishes them. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## Every made item's row gone from this machine, and said (`made_changed`), so its item goes too.
## Nothing is saved by it: as a guest, nothing here is this player's to save.
func _forget_made() -> void:
	for id in session.made.keys():
		session.made.erase(id)
		session.made_changed.emit(id, true)


## Host: made item `id`'s row (`made`) to everyone, once, on its own reliable message: before the
## room that will name it, on the same channel, so it is there when the room arrives.
func publish_made(id: StringName) -> void:
	if session.role != session.Role.HOST or not session.made.has(id):
		return
	var row: Array = session.made[id]
	for peer in session.admitting._audience():
		session._made.rpc_id(peer, id, row[0], int(row[1]), row[2])


## Host: made item `id` is gone (the BIN): its row with it, everywhere.
func drop_made(id: StringName) -> void:
	session.made.erase(id)
	if session.role != session.Role.HOST:
		return
	for peer in session.admitting._audience():
		session._unmade.rpc_id(peer, id)


## A made item's row, from the host: kept if it is one, within what a room may carry
## (ItemRoom.MADE_BYTES, MADE_MOST), and said.
func _made(id: StringName, kind: StringName, maker: int, bytes: PackedByteArray) -> void:
	if session.role != session.Role.GUEST or not ItemRoom.is_made(id) or ItemRoom.kind_of(id) != kind \
			or bytes.size() > ItemRoom.MADE_BYTES or (not session.made.has(id) and session.made.size() >= ItemRoom.MADE_MOST):
		return
	session.made[id] = [kind, maker, bytes]
	session.made_changed.emit(id, false)


func _unmade(id: StringName) -> void:
	if session.role != session.Role.GUEST:
		return
	session.made.erase(id)
	session.made_changed.emit(id, true)


## Host: `key` (an item's network key) is in `peer`'s hand now, whoever had it: a give, or a made
## item minted for the guest who asked (docs/spatial_loop.md part two, slice 23). Their hand takes
## it when they hear (the studio's `_take_given`); one that had it lets go (Presence).
func hand_to(peer: int, key: String) -> void:
	if not session.is_authority() or key.is_empty() or (peer != session.local_peer_id and not session._is_member(peer)):
		return
	if session.holds.get(key, 0) == peer:
		return
	session.holds[key] = peer
	session.replicating._send_holds()


## Host: this is the room now. Sent to everyone in it, and to each guest as they come in.
func publish_room(state: Dictionary) -> void:
	if session.role != session.Role.HOST:
		return
	session.room = state
	session._room_sent = true
	session.rooms_published += 1
	for id in session.admitting._audience():
		session._receive_room.rpc_id(id, _room_with_acks())


func _room_with_acks() -> Dictionary:
	var out := session.room.duplicate()
	out["acks"] = session._room_acks.duplicate()
	return out


## Guest: ask the host to change the room, and get back the ask's number -- the guest goes ahead
## and does it, and the number is how it learns the host has answered. 0 when nothing was sent:
## the host's own asks go straight to its studio, and there is nobody to predict for.
func ask_room(verb: StringName, args: Array) -> int:
	if not room_ask_is_valid(verb, args):
		return 0
	if session.is_authority():
		session.room_asked.emit(verb, args, session.local_peer_id)
		return 0
	if not session._connected():
		return 0
	session.room_seq += 1
	session._room_asked.rpc_id(1, session.room_seq, verb, args)
	return session.room_seq


## Host: words for `peer` alone, here if it is the host itself.
func tell(peer: int, text: String) -> void:
	if peer == session.local_peer_id:
		session.notice.emit(text)
	elif session.role == session.Role.HOST and session._connected() and session._is_member(peer):
		session._told.rpc_id(peer, text)


## The round trip to `peer` in milliseconds, as the connection measures it: a host knows it for
## every guest, a guest only for the host. -1 where there is no such connection.
func round_trip_ms(peer: int) -> float:
	var enet := session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or not session._connected():
		return -1.0
	var packet := enet.get_peer(peer) if session.role == session.Role.HOST else enet.get_peer(1)
	if packet == null:
		return -1.0
	return packet.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)


## Roughly how long after `peer` plays a key its note reaches this machine: one way to the host,
## and one way on to here unless this is the host. A guest does not know the other guest's leg,
## and takes it to be its own.
func note_delay_ms(peer: int) -> float:
	if session.role == session.Role.HOST:
		var rtt := round_trip_ms(peer)
		return rtt * 0.5 if rtt >= 0.0 else -1.0
	var mine := round_trip_ms(1)
	if mine < 0.0:
		return -1.0
	return mine * 0.5 if peer == 1 else mine


## True if `verb` is in `ROOM_VERBS` and `args` have the declared count and types.
static func room_ask_is_valid(verb: StringName, args: Array) -> bool:
	if not Session.ROOM_VERBS.has(verb) or args.size() != Session.ROOM_VERBS[verb].size():
		return false
	for i in args.size():
		if typeof(args[i]) != Session.ROOM_VERBS[verb][i]:
			return false
	return true


func _receive_room(state: Dictionary) -> void:
	session.room = state
	session.room_changed.emit()


func _room_asked(seq: int, verb: StringName, args: Array) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	# Answered even when refused: the answer to an ask the host will not do is the room as it
	# is, and that is what takes the guest's prediction back.
	session._room_acks[from] = maxi(int(session._room_acks.get(from, 0)), seq)
	session._room_sent = false
	if room_ask_is_valid(verb, args):
		# Whatever the host does to answer it is the asker's to undo, not folded into the host's
		# own open edit (DAW.on_behalf_of).
		DAW.on_behalf_of(from, func() -> void: session.room_asked.emit(verb, args, from))
	if not session._room_sent:
		publish_room(session.room)


## Host: this is the tour run now, or `{}` for none under way. Sent to everyone in the room.
func publish_tour(state: Dictionary) -> void:
	if session.role != session.Role.HOST:
		return
	session.tour = state
	for id in session.admitting._audience():
		session._receive_tour.rpc_id(id, session.tour)


## Guest: ask the host to act on the run under way. Unlike `ask_room` there is nothing here for
## the guest to predict -- a draft pick is resolved once, by the host, and announced -- so this
## returns nothing; `Tour` reads the run back from `tour_changed` once the host has answered.
func ask_tour(verb: StringName, args: Array) -> void:
	if not tour_ask_is_valid(verb, args):
		return
	if session.is_authority():
		session.tour_asked.emit(verb, args, session.local_peer_id)
		return
	if not session._connected():
		return
	session._tour_asked.rpc_id(1, verb, args)


## True if `verb` is in `TOUR_VERBS` and `args` have the declared count and types.
static func tour_ask_is_valid(verb: StringName, args: Array) -> bool:
	if not Session.TOUR_VERBS.has(verb) or args.size() != Session.TOUR_VERBS[verb].size():
		return false
	for i in args.size():
		if typeof(args[i]) != Session.TOUR_VERBS[verb][i]:
			return false
	return true


func _receive_tour(state: Dictionary) -> void:
	session.tour = state
	session.tour_changed.emit()


func _tour_asked(verb: StringName, args: Array) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	if tour_ask_is_valid(verb, args):
		session.tour_asked.emit(verb, args, from)


## Host: this is the roll now. Sent to everyone in the room, and heard here too.
func publish_roll(state: Dictionary) -> void:
	if not session.is_authority():
		return
	session.roll = state
	session.roll_changed.emit()
	for id in session.admitting._audience():
		session._receive_roll.rpc_id(id, session.roll)


func _receive_roll(state: Dictionary) -> void:
	session.roll = state
	session.roll_changed.emit()


## Host: this is what the next roll is set to. Sent to everyone in the room, and heard here too.
func publish_roll_setup(state: Dictionary) -> void:
	if not session.is_authority():
		return
	session.roll_setup = state
	session.roll_setup_changed.emit()
	for id in session.admitting._audience():
		session._receive_roll_setup.rpc_id(id, session.roll_setup)


func _receive_roll_setup(state: Dictionary) -> void:
	session.roll_setup = state
	session.roll_setup_changed.emit()
