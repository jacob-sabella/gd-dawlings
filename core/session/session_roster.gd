class_name SessionRoster
extends RefCounted

## Who is in the room: a peer connecting or leaving, the hello and admission of a guest, the audio ticket, turning
## away, the roster the host broadcasts and its application. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


func _introduce() -> void:
	session._hello.rpc_id(1, session.local_name, session.layout.medium if session.layout != null else 0, session._offered_code, session.local_look)


func _register(peer_id: int, name_hint: String, colour_index: int) -> Session.Participant:
	if session.participants.has(peer_id):
		return session.participants[peer_id]
	var p := Session.Participant.new()
	p.peer_id = peer_id
	p.display_name = name_hint
	p.colour_index = colour_index
	if peer_id == session.local_peer_id:
		p.look = session.local_look.duplicate()
		if session.layout != null:
			p.medium = session.layout.medium
	session.participants[peer_id] = p
	session.participant_joined.emit(peer_id)
	return p


## The lowest colour nobody is wearing. Join order alone would hand the eighth arrival the
## colour of someone still in the room the moment an earlier guest left and came back.
func _free_colour() -> int:
	var used := {}
	for id in session.participants:
		used[session.participants[id].colour_index] = true
	for i in session.PALETTE.size():
		if not used.has(i):
			return i
	return session.participants.size() % session.PALETTE.size()


func _close_peer() -> void:
	session.life._close_beacon()
	if session.internet.state != InternetDoor.State.CLOSED:
		session.internet.close()
	if session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		session.multiplayer.multiplayer_peer.close()
	session.multiplayer.multiplayer_peer = null


func _restore_own_mix() -> void:
	if session.solo_backend.is_valid():
		session.solo_backend.call()
	else:
		DAW.use(OfflineBackend.new())


func _on_peer_connected(peer_id: int) -> void:
	if not is_instance_valid(session):
		return
	# Only the host keeps the roster. A guest is told about the others by it, and registering
	# them here as well would give them a name and colour the host never chose.
	if session.role != session.Role.HOST:
		return
	# At the door, not in the room. They are let in by their hello, which carries the code.
	session._pending[peer_id] = Time.get_ticks_msec()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_instance_valid(session):
		return
	if session.role != session.Role.HOST:
		return
	session._pending.erase(peer_id)
	if session.play_tracks.erase(peer_id):
		session.play_track_changed.emit(peer_id, 0)
	var had_offers := session.share_offers.erase(peer_id)
	if session.shares.erase(peer_id) or had_offers:
		session.shares_changed.emit()
	if session.mix_feed != null:
		session.mix_feed.revoke(peer_id)
	if not session.participants.has(peer_id):
		# Turned away, or never said hello. Nobody was told they arrived, so nobody is told
		# they left.
		return
	var who := session.name_of(peer_id)
	# A take still arriving is kept: what was sung before the line dropped is still a take.
	session.take_work._finish_take(peer_id)
	session.participants.erase(peer_id)
	session.participant_left.emit(peer_id)
	# Whatever they had their hand on is free the moment they are gone. A fader held by an
	# absent person cannot be moved by anybody, which is a broken desk.
	var dropped := false
	for key in session.holds.keys():
		if session.holds[key] == peer_id:
			session.holds.erase(key)
			dropped = true
	if dropped:
		session.replicating._send_holds()
	# And an edit group they left open is closed: their let-go is never coming, and the step it
	# was gathering is a whole step as it stands.
	DAW.close_edits_of(peer_id)
	_broadcast_roster()
	session.notice.emit("%s left the session." % who)


func _on_connected_to_server() -> void:
	if not is_instance_valid(session):
		return
	if session.link_phase == "punching" or session.link_phase == "relaying":
		session.link_kind = "direct" if session.link_phase == "punching" else "relayed"
		session.link_phase = ""
		session.link_changed.emit()
	_introduce()


func _on_connection_failed() -> void:
	if not is_instance_valid(session):
		return
	if session.link_phase == "punching":
		session.linking._try_relay()
		return
	if session.link_phase == "relaying":
		session.linking._link_failed("Could not reach the session with code %s, directly or through the noray relay." %
				NorayLink.spoken(session.joined_code))
		return
	var where := session.joined_address
	session.start_solo()
	_restore_own_mix()
	session.notice.emit("Could not join %s -- nobody answered on port %d." % [where, session.port])


func _on_server_disconnected() -> void:
	if not is_instance_valid(session):
		return
	if session.role != session.Role.GUEST:
		return
	var host_name := session.name_of(1)
	session.start_solo()
	_restore_own_mix()
	session.notice.emit("Lost the connection to %s's session. Back on your own mix." % host_name)


## A guest introducing itself, and again whenever it renames. The first one is also the knock.
func _hello(display_name: String, medium: int, offered_code: String = "", look: Dictionary = {}) -> void:
	if session.role != session.Role.HOST:
		return
	var from := session.multiplayer.get_remote_sender_id()
	var p: Session.Participant = session.participants.get(from)
	var first := p == null
	if first:
		var refusal := admission_refusal(offered_code)
		if not refusal.is_empty():
			_turn_away(from, refusal)
			return
		session._pending.erase(from)
		p = _register(from, display_name, _free_colour())
		admit(from)
	p.display_name = display_name.strip_edges().substr(0, 24)
	if p.display_name.is_empty():
		p.display_name = "Guest %d" % session.participants.size()
	p.medium = medium
	p.look = GhostLook.clean(look)
	_broadcast_roster()
	if first:
		session.replicating._send_holds()
		session.notice.emit("%s joined the session." % p.display_name)


## Why a knock with this code is not let in, or "" if it is. Compared case- and space-blind: a
## code is read aloud across a room, and "ab 12" typed for "AB12" is the same code.
func admission_refusal(offered: String) -> String:
	if session.code.is_empty():
		return ""
	var want := session.code.replace(" ", "").to_upper()
	var got := offered.replace(" ", "").to_upper()
	if got.is_empty():
		return "%s's session needs a code. Ask %s for it." % [session.local_name, session.local_name]
	if got != want:
		return "That is not %s's code." % session.local_name
	return ""


## Everything a newly admitted guest needs, in the order it needs it: the mix first, so the
## desk they are about to be shown is never empty; the roster and holds follow from `_hello`.
func admit(peer_id: int) -> void:
	session.replicating._send_snapshot_to(peer_id)
	# What the room's made items carry, before the room that names them.
	if session._connected():
		for id in session.made:
			var row: Array = session.made[id]
			session._made.rpc_id(peer_id, id, row[0], int(row[1]), row[2])
	if not session.room.is_empty() and session._connected():
		session._receive_room.rpc_id(peer_id, session.room_work._room_with_acks())
	if not session.tour.is_empty() and session._connected():
		session._receive_tour.rpc_id(peer_id, session.tour)
	if not session.roll.is_empty() and session._connected():
		session._receive_roll.rpc_id(peer_id, session.roll)
	if not session.roll_setup.is_empty() and session._connected():
		session._receive_roll_setup.rpc_id(peer_id, session.roll_setup)
	if session.mix_feed != null and session.mix_feed.sending and session._connected():
		session._give_audio_ticket.rpc_id(peer_id, session.mix_feed.grant(peer_id), session.mix_feed.port,
				session.mix_online.oid if session.mix_online.is_online() else "")


## The host's leave to listen. Sent over the reliable, admitted channel; the audio socket
## answers nothing that does not carry one.
func _give_audio_ticket(ticket: int, audio_port: int, mix_code: String = "") -> void:
	session._audio_ticket = ticket
	session._audio_port = audio_port
	session._mix_code = mix_code
	_apply_listening()


func _apply_listening() -> void:
	if session.mix_feed == null or session.role != session.Role.GUEST:
		return
	if session.hear_mix and session._audio_ticket != 0:
		if not session.mix_feed.listening and session._mix_phase.is_empty():
			if session.link_kind.is_empty():
				session.mix_feed.listen(session.joined_address, session._audio_port, session._audio_ticket)
			else:
				# By a code, there is no address of the host's to send to: noray finds one.
				session._mix_by_code()
	elif session.mix_feed.listening or not session._mix_phase.is_empty():
		session.linking._end_mix_link()
		session.mix_feed.stop()


func _turn_away(peer_id: int, reason: String) -> void:
	session._pending.erase(peer_id)
	if session._connected():
		session._turned_away.rpc_id(peer_id, reason)
	session.notice.emit("Someone tried to join without the right code.")
	# Hung up a moment later, for the same reason the host's goodbye is: closed now, the
	# disconnect overtakes the explanation and the guest is left guessing.
	var peer := session.multiplayer.multiplayer_peer
	session.get_tree().create_timer(session.GOODBYE_SECONDS).timeout.connect(func():
		if session.multiplayer.multiplayer_peer == peer and peer is ENetMultiplayerPeer:
			(peer as ENetMultiplayerPeer).disconnect_peer(peer_id))


func _turned_away(reason: String) -> void:
	session.start_solo()
	_restore_own_mix()
	session.notice.emit(reason)


func _tick_admission() -> void:
	if session.role != session.Role.HOST or session._pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for peer_id in session._pending.keys():
		if now - int(session._pending[peer_id]) > int(session.ADMIT_SECONDS * 1000.0):
			session._pending.erase(peer_id)
			if session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(session.multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)


## The people in the room other than me -- who a host's word goes to. Not every connection: a
## guest at the door has a socket and no seat.
func _audience() -> Array:
	if session.role != session.Role.HOST or not session._connected():
		return []
	return session.participants.keys().filter(func(id): return id != 1)


## Whether a message claiming to come from `peer_id` is from someone in the room.
func _is_member(peer_id: int) -> bool:
	return session.participants.has(peer_id)


func _goodbye() -> void:
	var host_name := session.name_of(1)
	session.start_solo()
	_restore_own_mix()
	session.notice.emit("%s ended the session. Back on your own mix." % host_name)


func _roster_rows() -> Array:
	var rows: Array = []
	for id in session.participants:
		var p: Session.Participant = session.participants[id]
		rows.append([p.peer_id, p.display_name, p.medium, p.colour_index, p.look])
	return rows


func _broadcast_roster() -> void:
	if session.role != session.Role.HOST:
		return
	if session._connected():
		var rows := _roster_rows()
		for id in _audience():
			session._receive_roster.rpc_id(id, rows)
	session.roster_changed.emit()


## The host's word on who is here. Applied as a whole -- arrivals, departures, renames -- and
## heads and pointers carried across, so a rename does not snap someone's avatar to the origin.
func _receive_roster(rows: Array) -> void:
	apply_roster(rows)


## Adopt the host's roster rows: register each peer, update names, and drop the participants no longer listed.
func apply_roster(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id: int = row[0]
		seen[id] = true
		var arriving := not session.participants.has(id)
		var p: Session.Participant = _register(id, row[1], row[3])
		p.display_name = row[1]
		p.medium = row[2]
		p.colour_index = row[3]
		# A host from before looks existed sends four columns: everyone in its default.
		p.look = GhostLook.clean(row[4] if row.size() > 4 else {})
		if arriving and id != session.local_peer_id and session._has_settled:
			session.notice.emit("%s joined the session." % p.display_name)
	for id in session.participants.keys():
		if not seen.has(id):
			var who := session.name_of(id)
			session.participants.erase(id)
			session.participant_left.emit(id)
			if id != session.local_peer_id:
				session.notice.emit("%s left the session." % who)
	if not session._has_settled and session.role == session.Role.GUEST:
		session._has_settled = true
		session.notice.emit("Joined %s's session." % session.name_of(1))
	session.roster_changed.emit()
