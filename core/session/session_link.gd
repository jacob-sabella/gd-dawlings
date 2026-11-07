class_name SessionLink
extends RefCounted

## Hosting and joining online by a code (noray), the punched and relayed paths, the roster's route for a guest and the
## mix's own link by a code, carried over the session's ENet when no path opens. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## Ask the router to forward this session's ports here (UDP: the session's own, and the mix's
## audio beside it), so people outside the room can join at the router's public address. The
## host only, and only when asked: it changes the host's network. `internet.changed` reports.
func open_to_internet() -> void:
	if session.role != session.Role.HOST:
		return
	session.internet.open([session.port, session.port + session.AUDIO_PORT_OFFSET] as Array[int])


func close_to_internet() -> void:
	session.internet.close()


## Host online: registered with a noray server, which hands out a short code (`online.oid`) that
## finds this session from anywhere, no router asked. Hosts first if on your own. `online.changed`
## reports; a failure is in `online.why_not`. The session code at the door still applies.
func host_online(at_port: int = session.DEFAULT_PORT, server: String = "") -> bool:
	if session.role == session.Role.GUEST:
		return false
	if session.role == session.Role.SOLO and not session.host(at_port):
		return false
	var enet := session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return false
	session._punching.clear()
	session._mix_punching.clear()
	session.online.open(_server(server), NorayLink.via_enet(enet.host))
	if session.mix_feed != null and session.mix_feed.sending:
		session.mix_online.registrar_port = session.online.registrar_port
		session.mix_online.open(_server(server), session.mix_feed.send_raw)
	session.link_changed.emit()
	return true


## Off noray: the code stops working. Guests already in stay in.
func go_offline() -> void:
	if session.role == session.Role.HOST:
		session.online.close()
		session.mix_online.close()
		session._punching.clear()
		session._mix_punching.clear()
		session.link_changed.emit()


## Join by the code a host read out: noray finds its internet address, both sides punch, and if
## no path opens in LINK_SECONDS, noray's relay carries it instead. `with_code` is the session
## code at the door, if the host asked for one. Reports through `link_changed` and `notice`.
func join_by_code(typed: String, with_code: String = "", server: String = "") -> bool:
	var code := NorayLink.clean_code(typed)
	if code.is_empty():
		session.notice.emit("Type the host's join code first.")
		return false
	if session.role != session.Role.SOLO:
		session.leave()
	_end_link()
	session.joined_code = code
	session._link_door = with_code
	session.link_phase = "finding"
	session._link_clock = 0.0
	session.online.open(_server(server))
	session.link_changed.emit()
	return session.online.state != NorayLink.State.FAILED


## Where a host's guest came in from, for the roster: "relayed" through noray's server, "direct"
## when noray punched it through, "" by address.
func route_of(peer_id: int) -> String:
	if peer_id == session.local_peer_id:
		return session.link_kind
	var enet := session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if session.role != session.Role.HOST or enet == null or not session.online.is_online():
		return ""
	var peer := enet.get_peer(peer_id)
	if peer == null:
		return ""
	var ip := peer.get_remote_address()
	var at := peer.get_remote_port()
	if ip == session.online.server_ip and session.online.relay_ports.has(at):
		return "relayed"
	for p in session._punched:
		if p[0] == ip and int(p[1]) == at:
			return "direct"
	return ""


func _server(asked: String) -> String:
	if not asked.is_empty():
		return asked
	return session.online_server if not session.online_server.is_empty() else NorayLink.server_setting()


func _end_link() -> void:
	var was := session.link_phase != "" or session.link_kind != "" or session.online.state != NorayLink.State.CLOSED
	session.online.close()
	_end_mix_link()
	session._mix_code = ""
	session.link_phase = ""
	session.link_kind = ""
	session.joined_code = ""
	session._punching.clear()
	session._punched.clear()
	session._mix_punching.clear()
	if was:
		session.link_changed.emit()


func _on_online_changed() -> void:
	if not is_instance_valid(session):
		return
	if session.link_phase == "finding" and session.online.is_online():
		if session.force_relay:
			session.link_phase = "relaying"
			session._link_clock = 0.0
			session.online.ask_relay(session.joined_code)
		else:
			session.online.ask_direct(session.joined_code)
	elif session.online.state == NorayLink.State.FAILED:
		if session.link_phase != "":
			_link_failed(session.online.why_not)
			return
		if session.role == session.Role.HOST:
			session.notice.emit(session.online.why_not)
	session.link_changed.emit()


## noray says where the other side is. A host punches toward a guest; a guest dials the host.
func _on_online_punch(ip: String, at_port: int) -> void:
	if not is_instance_valid(session):
		return
	if session.role == session.Role.HOST:
		session._punching.append([ip, at_port, session.PUNCH_SECONDS])
		session._punched.append([ip, at_port])
		session._punch_clock = 0.0
	elif session.link_phase == "finding":
		session.link_phase = "punching"
		session._link_clock = 0.0
		session.join(ip, at_port, session._link_door, session.online.local_port)
		session.link_changed.emit()


## noray gave a relay port. A host punches toward it (the guest will appear from there); a guest
## dials the noray server at it, from the same registered port.
func _on_online_relay(relay_port: int) -> void:
	if not is_instance_valid(session):
		return
	if session.role == session.Role.HOST:
		session._punching.append([session.online.server_ip, relay_port, session.PUNCH_SECONDS])
		session._punch_clock = 0.0
	elif session.link_phase == "relaying":
		session._link_clock = 0.0
		session.join(session.online.server_ip, relay_port, session._link_door, session.online.local_port)
		session.link_changed.emit()


func _tick_link(delta: float) -> void:
	if session.link_phase != "punching" and session.link_phase != "relaying":
		return
	session._link_clock += delta
	if session._link_clock < session.link_seconds:
		return
	if session.link_phase == "punching":
		_try_relay()
	else:
		_link_failed("Could not reach the session with code %s, directly or through the noray relay." %
				NorayLink.spoken(session.joined_code))


## No punched path: the same registered port, through the server instead.
func _try_relay() -> void:
	if session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		session.multiplayer.multiplayer_peer.close()
	session.multiplayer.multiplayer_peer = null
	session.link_phase = "relaying"
	session._link_clock = 0.0
	session.online.ask_relay(session.joined_code)
	session.link_changed.emit()


func _link_failed(why: String) -> void:
	var was_guest := session.role == session.Role.GUEST
	session.start_solo()
	if was_guest:
		session.admitting._restore_own_mix()
	session.notice.emit(why)


## Sends to an announced address from the ENet server's own socket, so this router has sent
## first and lets the guest's packets in. ENet on the far side ignores what is not ENet.
func _tick_punches(delta: float) -> void:
	if session._punching.is_empty():
		return
	session._punch_clock -= delta
	if session._punch_clock > 0.0:
		return
	session._punch_clock = 0.1
	var enet := session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if session.role != session.Role.HOST or enet == null or enet.host == null:
		session._punching.clear()
		return
	for p in session._punching:
		enet.host.socket_send(p[0], int(p[1]), "dawlings punch".to_ascii_buffer())
		p[2] = float(p[2]) - 0.1
	session._punching = session._punching.filter(func(p): return float(p[2]) > 0.0)
	for p in session._mix_punching:
		session.mix_feed.send_raw(p[0], int(p[1]), "dawlings punch".to_ascii_buffer())
		p[2] = float(p[2]) - 0.1
	session._mix_punching = session._mix_punching.filter(func(p): return float(p[2]) > 0.0)


## A guest by code hears the mix on its own socket, as every guest does, at an address noray gives:
## its mix socket registered and punched toward the host's (the host registered its mix socket
## too, `host_online`), or the relay if the session itself needed one or the punch is not heard
## in MIX_LINK_SECONDS. Neither: carried over the session's ENet (MixFeed.carried).
func _mix_by_code() -> void:
	if session._mix_code.is_empty():
		_carry_instead()
		return
	session._mix_phase = "finding"
	session._mix_clock = 0.0
	session.mix_online.registrar_port = session.online.registrar_port
	session.mix_online.open(session.online.where())


func _on_mix_online_changed() -> void:
	if not is_instance_valid(session):
		return
	if session._mix_phase == "finding" and session.mix_online.is_online():
		if session.link_kind == "relayed" or session.force_relay:
			session._mix_phase = "relaying"
			session.mix_online.ask_relay(session._mix_code)
		else:
			session.mix_online.ask_direct(session._mix_code)
	elif session.mix_online.state == NorayLink.State.FAILED and session._mix_phase != "":
		_carry_instead()
	elif session.mix_online.state == NorayLink.State.FAILED and session.role == session.Role.HOST:
		session.notice.emit("The mix will reach guests by code over the session itself: %s" % session.mix_online.why_not)


func _on_mix_online_punch(ip: String, at_port: int) -> void:
	if not is_instance_valid(session):
		return
	if session.role == session.Role.HOST:
		session._mix_punching.append([ip, at_port, session.PUNCH_SECONDS])
		session._punch_clock = 0.0
	elif session._mix_phase == "finding":
		session._mix_phase = "punching"
		session._mix_clock = 0.0
		session.mix_feed.listen(ip, at_port, session._audio_ticket, session.mix_online.local_port)


func _on_mix_online_relay(relay_port: int) -> void:
	if not is_instance_valid(session):
		return
	if session.role == session.Role.HOST:
		session._mix_punching.append([session.mix_online.server_ip, relay_port, session.PUNCH_SECONDS])
		session._punch_clock = 0.0
	elif session._mix_phase == "relaying":
		session._mix_clock = 0.0
		session.mix_feed.listen(session.mix_online.server_ip, relay_port, session._audio_ticket, session.mix_online.local_port)


func _tick_mix_link(delta: float) -> void:
	if session._mix_phase != "punching" and session._mix_phase != "relaying":
		return
	if session.mix_feed.listening and session.mix_feed.stats().get("hearing", false):
		session.mix_route = "direct" if session._mix_phase == "punching" else "relayed"
		session._mix_phase = ""
		session.link_changed.emit()
		return
	session._mix_clock += delta
	if session._mix_clock < session.MIX_LINK_SECONDS:
		return
	if session._mix_phase == "punching":
		session.mix_feed.stop()
		session._mix_phase = "relaying"
		session._mix_clock = 0.0
		session.mix_online.ask_relay(session._mix_code)
	else:
		_carry_instead()


## The last way: the mix over the session's own ENet, which reached the host already.
func _carry_instead() -> void:
	session.mix_online.close()
	session._mix_phase = ""
	if session.mix_feed.listening:
		session.mix_feed.stop()
	session.mix_feed.listen_carried(session._audio_ticket)
	session.mix_route = "carried"
	session.link_changed.emit()


func _end_mix_link() -> void:
	session.mix_online.close()
	session._mix_phase = ""
	session.mix_route = ""


## The mix for guests by code, over the session's ENet (MixFeed.carried), flushed at once rather
## than at the next frame's poll.
func _carry_mix() -> void:
	if session.mix_feed == null or not session.mix_feed.carries():
		return
	var out := session.mix_feed.take_outgoing()
	if out.is_empty() or not session._connected():
		return
	for row in out:
		var to: int = row[0]
		if session.role == session.Role.HOST and not session.participants.has(to):
			continue
		session.multiplayer.send_bytes(row[1], to, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, session.MIX_CHANNEL)
	var enet := session.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.host != null:
		enet.host.flush()
