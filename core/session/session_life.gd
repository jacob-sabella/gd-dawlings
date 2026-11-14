class_name SessionLife
extends RefCounted

## How a session starts and ends: solo, hosting, joining by an address, leaving, who is the authority, renaming and
## dressing the ghost, registering a peer, and the autoload's ready, exit and process. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## Create and add the autoload's child nodes (mix feed, guest MIDI, audio, ...) and wire their signals. Called from `Session._ready`.
func ready() -> void:
	session.mix_feed = MixFeed.new()
	session.mix_feed.name = "MixFeed"
	session.add_child(session.mix_feed)
	session.guest_midi = GuestMidi.new()
	session.guest_midi.name = "GuestMidi"
	session.add_child(session.guest_midi)
	session.guest_audio = GuestAudio.new()
	session.guest_audio.name = "GuestAudio"
	session.add_child(session.guest_audio)
	session.host_audio = GuestAudio.new()
	session.host_audio.name = "HostAudio"
	session.host_audio.for_host = true
	session.host_audio.heard = session.host_heard
	session.add_child(session.host_audio)
	session.files = FileSend.new()
	session.files.name = "FileSend"
	session.add_child(session.files)
	session.mod_share = ModSend.new()
	session.mod_share.name = "ModSend"
	session.add_child(session.mod_share)
	session.home = RealmHome.new()
	session.home.name = "RealmHome"
	session.add_child(session.home)
	session.lobby = RealmLobby.new()
	session.lobby.name = "RealmLobby"
	session.add_child(session.lobby)
	session.realm_copy = RealmCopy.new()
	session.realm_copy.name = "RealmCopy"
	session.add_child(session.realm_copy)
	session.discord = DiscordFeed.new()
	session.discord.name = "DiscordFeed"
	session.add_child(session.discord)
	session.layout = LayoutProfile.new()
	session.local_name = _default_name()
	session.local_look = GhostLook.load_from(session.look_path)
	session.multiplayer.peer_connected.connect(session.admitting._on_peer_connected)
	session.multiplayer.peer_disconnected.connect(session._on_peer_disconnected)
	session.multiplayer.connected_to_server.connect(session.admitting._on_connected_to_server)
	session.multiplayer.connection_failed.connect(session.admitting._on_connection_failed)
	session.multiplayer.server_disconnected.connect(session.admitting._on_server_disconnected)
	session.multiplayer.peer_packet.connect(_on_peer_packet)
	session.online.changed.connect(session.linking._on_online_changed)
	session.online.punch.connect(session.linking._on_online_punch)
	session.online.relay.connect(session.linking._on_online_relay)
	session.mix_online.changed.connect(session.linking._on_mix_online_changed)
	session.mix_online.punch.connect(session.linking._on_mix_online_punch)
	session.mix_online.relay.connect(session.linking._on_mix_online_relay)
	session.force_relay = OS.get_environment("DAWLINGS_NORAY_RELAY") == "1"
	# Deferred: DAW is an autoload too, and may not be in the tree yet.
	(func():
		DAW.project_replaced.connect(session.replicating._on_project_replaced)
		DAW.tracks_renumbered.connect(session.replicating._on_tracks_renumbered)
		DAW.project_saved.connect(func(said): session.guest_writes._announce_save(session.local_name, said))
		DAW.render_finished.connect(session.guest_writes._announce_render)).call_deferred()


## Quitting while hosting is ending the session, and says so. Blocking, briefly, because there
## is no next frame to finish the goodbye in: the packet is serviced out by hand until it has
## had time to land, and only then does the socket close behind it.
func exit_tree() -> void:
	# The router's forwarding comes down with the session, and is waited for: a quit is the
	# last chance, and a port left open on someone's router is not ours to leave.
	if session.internet.state != InternetDoor.State.CLOSED:
		session.internet.close()
	session.internet.finish()
	session.online.close()
	session.mix_online.close()
	if session.role != session.Role.HOST or not _connected():
		return
	var peer := session.multiplayer.multiplayer_peer
	session._goodbye.rpc()
	var until := Time.get_ticks_msec() + int(session.GOODBYE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < until:
		peer.poll()
		OS.delay_msec(10)
	peer.close()


## One frame of the session's timers: the LAN beacon, admission, the online links, punches and the mix link.
func process(delta: float) -> void:
	_tick_beacon(delta)
	session.admitting._tick_admission()
	session.online.poll(delta)
	session.mix_online.poll(delta)
	session.linking._tick_link(delta)
	session.linking._tick_punches(delta)
	session.linking._tick_mix_link(delta)
	session.linking._carry_mix()
	for peer in session._closing_peers:
		peer.poll()


## The login name, capitalised, as a starting point. Not the machine name: "jsabella" is a
## person and "cachyos-x8664" is furniture.
static func _default_name() -> String:
	var who := OS.get_environment("USER")
	if who.is_empty():
		who = OS.get_environment("USERNAME")
	if who.is_empty():
		return "Engineer"
	return who.substr(0, 1).to_upper() + who.substr(1)


## Start a solo session: no network, this process also owns the Reaper link.
func start_solo() -> void:
	session.admitting._close_peer()
	session.linking._end_link()
	if session.mix_feed != null:
		session.mix_feed.stop()
	session._audio_ticket = 0
	# A guest's made items were the host's room's; a host's own stay with its room. Our own, set
	# aside on joining, are the layout's to give back (Studio._restore_made).
	if session.role == session.Role.GUEST:
		session.room_work._forget_made()
	session.role = session.Role.SOLO
	session.room = {}
	var had_shares := not (session.share_offers.is_empty() and session.shares.is_empty() and session.my_shares.is_empty())
	session.share_offers.clear()
	session.shares.clear()
	session.my_shares.clear()
	session.my_share_track = 0
	if had_shares:
		session.shares_changed.emit()
	session.replicating._forget_spectra()
	session.local_peer_id = 1
	session.participants.clear()
	session.holds.clear()
	session.joined_address = ""
	session._register(1, session.local_name, 0)
	session.role_changed.emit()
	session.roster_changed.emit()


## Open a server on `at_port` and become the host; false, with a notice, if the port cannot be opened.
func host(at_port: int = session.DEFAULT_PORT) -> bool:
	session.admitting._close_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(at_port) != OK:
		push_error("Session: cannot host on %d" % at_port)
		session.notice.emit("Could not open port %d -- is another session already hosting here?" % at_port)
		return false
	session.multiplayer.multiplayer_peer = peer
	# No guest-to-guest traffic through the host's socket behind its back. Everything a guest
	# says to the room goes to the host, which decides who it reaches -- the only way a guest
	# still waiting at the door can be kept from talking to the people already inside.
	session.multiplayer.server_relay = false
	session.role = session.Role.HOST
	session.room = {}
	session.replicating._forget_spectra()
	session._room_acks.clear()
	session.port = at_port
	session.local_peer_id = 1
	session.participants.clear()
	session.holds.clear()
	session._pending.clear()
	session.joined_address = ""
	session._register(1, session.local_name, 0)
	_open_beacon()
	if session.mix_feed != null:
		session.mix_feed.start_sending(at_port + session.AUDIO_PORT_OFFSET,
				session.mix_source.call() if session.mix_source.is_valid() else MixSource.new())
	session.role_changed.emit()
	session.roster_changed.emit()
	return true


## Connect to a host by `address` (or, with `with_code`, as the dial of a join by code); the result arrives later as the connection signals.
func join(address: String, at_port: int = session.DEFAULT_PORT, with_code: String = "",
		local_port: int = 0) -> bool:
	# By address: whatever way in by a code was under way is over. By code, this is its dial.
	if session.link_phase.is_empty():
		session.linking._end_link()
	session.admitting._close_peer()
	session._offered_code = with_code.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, at_port, 0, 0, 0, local_port) != OK:
		push_error("Session: cannot reach %s:%d" % [address, at_port])
		session.notice.emit("Could not reach %s." % address)
		return false
	session.multiplayer.multiplayer_peer = peer
	session.multiplayer.server_relay = false
	session.role = session.Role.GUEST
	# This player's own made items are set aside, not saved over: the host's room's are the ones
	# here now, and ours would only count against what it may carry (`_made`). Their layout
	# still has them, and gives them back on leaving (Studio._restore_made).
	session.room_work._forget_made()
	session.room = {}
	session.replicating._forget_spectra()
	session.room_seq = 0
	session.port = at_port
	session.joined_address = address
	# Same machine, same speakers: the host's Reaper is already audible here. Never so by a code:
	# that is for someone elsewhere, and on one machine the relay's address is the loopback too.
	var local := session.link_phase.is_empty() and (address.begins_with("127.") or address == "localhost"
			or address == "::1")
	session.hear_mix = (not local) if session.listen_choice < 0 else session.listen_choice == 1
	session._has_settled = false
	session.local_peer_id = session.multiplayer.get_unique_id()
	session.participants.clear()
	session.holds.clear()
	# Ourselves only, until the host's roster says who else is here and what colour we are.
	session._register(session.local_peer_id, session.local_name, 0)
	# A guest must NOT open a link to the DAW. Its backend holds the replicated cache and
	# nothing else, and this is the line that keeps the four-way echo storm described in
	# core/reaper/reaper_backend.gd from ever happening.
	DAW.use(OfflineBackend.new(), false)
	session.role_changed.emit()
	session.roster_changed.emit()
	return true


func _on_peer_packet(from: int, packet: PackedByteArray) -> void:
	if not is_instance_valid(session):
		return
	if session.mix_feed != null and (session.role == session.Role.HOST and session.participants.has(from) or session.role == session.Role.GUEST and from == 1):
		session.mix_feed.hear_carried(from, packet)


## Back to being on your own. A host says goodbye first; a guest gets its own mix back.
func leave() -> void:
	if session.role == session.Role.SOLO:
		return
	var was_guest := session.role == session.Role.GUEST
	# Takes still arriving are placed while this is still the host's mix to place them in.
	for peer_id in session._incoming_takes.keys():
		session.take_work._finish_take(peer_id)
	if session.role == session.Role.HOST and session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		session._goodbye.rpc()
		# The socket is shut a moment later rather than now, still serviced in between. Closed
		# on the same frame, the disconnect overtakes the goodbye and every guest is told it
		# LOST the host -- the message for a crash, not for someone saying goodnight.
		var closing := session.multiplayer.multiplayer_peer
		session.multiplayer.multiplayer_peer = null
		session._closing_peers.append(closing)
		session.get_tree().create_timer(session.GOODBYE_SECONDS).timeout.connect(func():
			closing.close()
			session._closing_peers.erase(closing))
	start_solo()
	if was_guest:
		session.admitting._restore_own_mix()


func is_authority() -> bool:
	return session.role != session.Role.GUEST


## Up and talking. A guest is a guest from the moment it dials, but for the second or so before
## the host answers, anything sent is an error rather than a packet.
func _connected() -> bool:
	var peer := session.multiplayer.multiplayer_peer
	return session.role != session.Role.SOLO and peer != null \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_networked() -> bool:
	return session.role != session.Role.SOLO


func local_participant() -> Session.Participant:
	return session.participants.get(session.local_peer_id)


## The display name of `peer_id`; "someone" if unknown.
func name_of(peer_id: int) -> String:
	var p: Session.Participant = session.participants.get(peer_id)
	return p.display_name if p != null else "someone"


## Rename yourself. Before joining it is just a setting; once in a session the host hears it
## and tells everyone, because a name on an avatar that its owner has changed is a lie.
func set_local_name(new_name: String) -> void:
	new_name = new_name.strip_edges().substr(0, 24)
	if new_name.is_empty():
		return
	session.local_name = new_name
	if session.participants.has(session.local_peer_id):
		session.participants[session.local_peer_id].display_name = new_name
	match session.role:
		session.Role.HOST: session.admitting._broadcast_roster()
		session.Role.GUEST when _connected(): session.admitting._introduce()
		_: session.roster_changed.emit()


## Dress my ghost. Kept for next time, and told to the session the same way a rename is.
func set_look(look: Dictionary) -> void:
	session.local_look = GhostLook.clean(look)
	GhostLook.save_to(session.local_look, session.look_path)
	if session.participants.has(session.local_peer_id):
		session.participants[session.local_peer_id].look = session.local_look.duplicate()
	match session.role:
		session.Role.HOST: session.admitting._broadcast_roster()
		session.Role.GUEST when _connected(): session.admitting._introduce()
		_: session.roster_changed.emit()


func _open_beacon() -> void:
	_close_beacon()
	session._beacon = PacketPeerUDP.new()
	session._beacon.set_broadcast_enabled(true)
	session._beacon_clock = session.BEACON_SECONDS


func _close_beacon() -> void:
	if session._beacon != null:
		session._beacon.close()
	session._beacon = null


func _tick_beacon(delta: float) -> void:
	if session._beacon == null or session.role != session.Role.HOST:
		return
	session._beacon_clock += delta
	if session._beacon_clock < session.BEACON_SECONDS:
		return
	session._beacon_clock = 0.0
	var packet := JSON.stringify(beacon_payload()).to_utf8_buffer()
	# The LAN, and this machine. Loopback is not reliably on the broadcast's path, and two
	# windows on one desk is how a session is first tried.
	for address in ["255.255.255.255", "127.0.0.1"]:
		session._beacon.set_dest_address(address, session.DISCOVERY_PORT)
		session._beacon.put_packet(packet)


## What the LAN beacon announces: app, version, host name, port, head count and whether a door code is set.
func beacon_payload() -> Dictionary:
	return {
		"app": "dawlings",
		"v": 1,
		"name": session.local_name,
		"port": session.port,
		"people": session.participants.size(),
		"locked": not session.code.is_empty(),
		"tracks": DAW.state.project_track_count if DAW.state != null else 0,
	}
