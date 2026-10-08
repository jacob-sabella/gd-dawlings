extends Node

## Autoload `Session`. Who is in the room, what they are each looking through, and who is
## allowed to write to DAW.
##
## The hard problem this project has that a normal DAW front-end does not: FOUR PEOPLE, ONE
## CONSOLE, DIFFERENT EYES. One is at a monitor with a mouse. Two are in passthrough headsets
## standing at the physical spot where the console appears to be. One is in full VR in another
## room entirely. They must all be able to touch the same channel 8 fader and see the same
## result, and only one of them may hold the socket.
##
## Three things are therefore split apart and must stay split:
##
##   AUTHORITY   who may write to DAW. Exactly one peer: the host. See core/reaper.
##   PRESENCE    who is here, where their head is, what they are holding. Replicated to all.
##   PRESENTATION what each participant sees each surface AS -- a screen panel, a thing standing
##               in their actual room, or a thing in a virtual studio. Strictly PER PARTICIPANT
##               and never replicated, because it is the one thing they legitimately disagree
##               about. See core/presentation/layout_profile.gd.
##
## Collapsing presentation into presence is the mistake that makes hybrid impossible: it forces
## everyone into the same view, which is precisely what a mixed screen/AR room is not.

const Role := {SOLO = 0, HOST = 1, GUEST = 2}
const DEFAULT_PORT := 7332
## Where a hosting session says so to the LAN, once a second. One above the game port so a
## firewall rule written for one is easy to widen to the other.
const DISCOVERY_PORT := 7333
## The mix's audio, on a socket of its own. See core/session/mix_feed.gd for why not ENet.
const AUDIO_PORT_OFFSET := 2
const BEACON_SECONDS := 1.0
const GOODBYE_SECONDS := 0.3
## How long a connection may sit unintroduced before the host hangs up on it. Long enough for a
## guest on a slow wifi hop to build its scene and say hello; short enough that a port scan does
## not leave a row of ghosts holding slots.
const ADMIT_SECONDS := 6.0

## Handed out in join order, and the host's is the first. Chosen against every venue rather
## than for one: each has to read as a light on a dark studio AND on the chalk room's pale
## walls, and no two may be confusable by someone with the commonest colour-vision deficits --
## which is why there is a blue and an orange before there is a red and a green.
const PALETTE: Array[Color] = [
	Color(1.00, 0.58, 0.20),  # amber
	Color(0.30, 0.78, 1.00),  # sky
	Color(0.95, 0.38, 0.72),  # magenta
	Color(0.45, 0.90, 0.52),  # mint
	Color(0.72, 0.56, 1.00),  # violet
	Color(1.00, 0.88, 0.34),  # yellow
	Color(0.35, 0.95, 0.88),  # teal
	Color(1.00, 0.45, 0.42),  # coral
]

signal participant_joined(peer_id: int)
signal participant_left(peer_id: int)
signal role_changed()
## Names, colours or mediums changed. Fires on everyone, from the host's word on the matter.
signal roster_changed()
## Who is holding which control changed. See `holds`.
signal holds_changed()
## A grab this participant made was turned down by the host: somebody else got there first.
signal hold_refused(control_key: String, holder: int)
## Something a person in the room should be told in words -- someone came in, the host went
## away. Owned by whoever draws the session's UI; nothing here waits on it being read.
signal notice(text: String)

var role: int = Role.SOLO
## {peer_id: Participant}
var participants: Dictionary = {}
var local_peer_id: int = 1
## What this person is called in everyone else's room. Set before hosting or joining.
var local_name: String = ""
## {control key: peer_id}. Owned by the host and replicated whole, because it is small and a
## guest that missed a release would otherwise see a fader held forever by someone long gone.
var holds: Dictionary = {}
## The address this session was joined at, for the panel to say back.
var joined_address: String = ""
var port: int = DEFAULT_PORT
## The code a guest must give to be let in, or "" for an open session. Host side only.
var code: String = ""
## The code this guest will offer. Kept apart from `code` so that joining with one does not
## turn the next session this process hosts into a locked one.
var _offered_code: String = ""
## Connections the host has heard from the transport but not yet from the person: peer -> msec.
## Nothing reaches them -- no mix, no roster, no faces -- until their hello is accepted.
var _pending: Dictionary = {}

## How this process gets its own mix back when it stops being a guest -- reopen Reaper, or
## bring up the stand-in. Given by whoever started the DAW in the first place, because only
## that knows whether this machine has a Reaper of its own.
var solo_backend: Callable = Callable()
## How a host gets the mix's sound to pass on: returns a MixSource. Set by bootstrap, which
## knows whether this machine has a DAW making any, for the same reason as `solo_backend`.
var mix_source: Callable = Callable()
## The host's programme audio, out to guests or in from the host.
var mix_feed: MixFeed = null
## Whether this guest plays the host's mix. Off for someone in the same room as the host's
## speakers would be right -- the same sound twice, a few dozen ms apart, is a comb filter --
## but nothing can tell from here who is in which room, so it starts on for anyone joining from
## another machine and off for a guest on the host's own machine, and the panel turns it over.
var hear_mix := true:
	set(v):
		hear_mix = v
		_apply_listening()
var _audio_ticket := 0
var _audio_port := 0
## -1 to decide by address when joining, else 0/1: what --listen / --no-listen asked for.
var listen_choice := -1

var layout: LayoutProfile = null

## Whether this guest has had its first roster yet. Everyone on the first one is "arriving",
## and greeting each of them by name would be noise.
var _has_settled := false
var _beacon: PacketPeerUDP = null
## A host's old socket, kept serviced for a moment after it ends a session so the goodbye gets
## out. See leave().
var _closing_peers: Array[MultiplayerPeer] = []
var _beacon_clock := 0.0


class Participant extends RefCounted:
	var peer_id: int = 0
	var display_name: String = ""
	## SCREEN / AR / VR -- what this person is wearing, not what they are looking at. A single
	## AR participant can have some surfaces anchored in the room and others on a tablet.
	var medium: int = 0
	## Head pose in SESSION space, not world space. The distinction is the whole of
	## docs/colocation.md: two people in one physical room have different world origins and the
	## same session origin.
	var head: Transform3D = Transform3D.IDENTITY
	var calibrated: bool = false
	var colour_index: int = 0
	## What they are pointing at, as a control's key and a point in that control's own frame.
	## Never a world position: each viewer has the gear where THEY put it, and a dot sent in
	## the sender's world lands on the sender's rack -- which in my room is a patch of empty
	## floor. Named by control, the dot lands on my rack, which is the one they mean.
	var pointing_at: String = ""
	var pointing_local: Vector3 = Vector3.ZERO
	## Msec of the last presence heard, so a frozen avatar can be told from a still one.
	var heard_msec: int = 0

	var colour: Color:
		get: return PALETTE[colour_index % PALETTE.size()]


func _ready() -> void:
	mix_feed = MixFeed.new()
	mix_feed.name = "MixFeed"
	add_child(mix_feed)
	layout = LayoutProfile.new()
	local_name = _default_name()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Quitting while hosting is ending the session, and says so. Blocking, briefly, because there
## is no next frame to finish the goodbye in: the packet is serviced out by hand until it has
## had time to land, and only then does the socket close behind it.
func _exit_tree() -> void:
	if role != Role.HOST or not _connected():
		return
	var peer := multiplayer.multiplayer_peer
	_goodbye.rpc()
	var until := Time.get_ticks_msec() + int(GOODBYE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < until:
		peer.poll()
		OS.delay_msec(10)
	peer.close()


func _process(delta: float) -> void:
	_tick_beacon(delta)
	_tick_admission()
	for peer in _closing_peers:
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
	_close_peer()
	if mix_feed != null:
		mix_feed.stop()
	_audio_ticket = 0
	role = Role.SOLO
	local_peer_id = 1
	participants.clear()
	holds.clear()
	joined_address = ""
	_register(1, local_name, 0)
	role_changed.emit()
	roster_changed.emit()


func host(at_port: int = DEFAULT_PORT) -> bool:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(at_port) != OK:
		push_error("Session: cannot host on %d" % at_port)
		notice.emit("Could not open port %d -- is another session already hosting here?" % at_port)
		return false
	multiplayer.multiplayer_peer = peer
	# No guest-to-guest traffic through the host's socket behind its back. Everything a guest
	# says to the room goes to the host, which decides who it reaches -- the only way a guest
	# still waiting at the door can be kept from talking to the people already inside.
	multiplayer.server_relay = false
	role = Role.HOST
	port = at_port
	local_peer_id = 1
	participants.clear()
	holds.clear()
	_pending.clear()
	joined_address = ""
	_register(1, local_name, 0)
	_open_beacon()
	if mix_feed != null:
		mix_feed.start_sending(at_port + AUDIO_PORT_OFFSET,
				mix_source.call() if mix_source.is_valid() else MixSource.new())
	role_changed.emit()
	roster_changed.emit()
	return true


func join(address: String, at_port: int = DEFAULT_PORT, with_code: String = "") -> bool:
	_close_peer()
	_offered_code = with_code.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, at_port) != OK:
		push_error("Session: cannot reach %s:%d" % [address, at_port])
		notice.emit("Could not reach %s." % address)
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	role = Role.GUEST
	port = at_port
	joined_address = address
	# Same machine, same speakers: the host's Reaper is already audible here.
	var local := address.begins_with("127.") or address == "localhost" or address == "::1"
	hear_mix = (not local) if listen_choice < 0 else listen_choice == 1
	_has_settled = false
	local_peer_id = multiplayer.get_unique_id()
	participants.clear()
	holds.clear()
	# Ourselves only, until the host's roster says who else is here and what colour we are.
	_register(local_peer_id, local_name, 0)
	# A guest must NOT open a link to the DAW. Its backend holds the replicated cache and
	# nothing else, and this is the line that keeps the four-way echo storm described in
	# core/reaper/reaper_backend.gd from ever happening.
	DAW.use(OfflineBackend.new(), false)
	role_changed.emit()
	roster_changed.emit()
	return true


## Back to being on your own. A host says goodbye first; a guest gets its own mix back.
func leave() -> void:
	if role == Role.SOLO:
		return
	var was_guest := role == Role.GUEST
	if role == Role.HOST and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_goodbye.rpc()
		# The socket is shut a moment later rather than now, still serviced in between. Closed
		# on the same frame, the disconnect overtakes the goodbye and every guest is told it
		# LOST the host -- the message for a crash, not for someone saying goodnight.
		var closing := multiplayer.multiplayer_peer
		multiplayer.multiplayer_peer = null
		_closing_peers.append(closing)
		get_tree().create_timer(GOODBYE_SECONDS).timeout.connect(func():
			closing.close()
			_closing_peers.erase(closing))
	start_solo()
	if was_guest:
		_restore_own_mix()


func is_authority() -> bool:
	return role != Role.GUEST


## Up and talking. A guest is a guest from the moment it dials, but for the second or so before
## the host answers, anything sent is an error rather than a packet.
func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return role != Role.SOLO and peer != null \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_networked() -> bool:
	return role != Role.SOLO


func local_participant() -> Participant:
	return participants.get(local_peer_id)


func name_of(peer_id: int) -> String:
	var p: Participant = participants.get(peer_id)
	return p.display_name if p != null else "someone"


## Rename yourself. Before joining it is just a setting; once in a session the host hears it
## and tells everyone, because a name on an avatar that its owner has changed is a lie.
func set_local_name(new_name: String) -> void:
	new_name = new_name.strip_edges().substr(0, 24)
	if new_name.is_empty():
		return
	local_name = new_name
	if participants.has(local_peer_id):
		participants[local_peer_id].display_name = new_name
	match role:
		Role.HOST: _broadcast_roster()
		Role.GUEST when _connected(): _hello.rpc_id(1, new_name, layout.medium if layout != null else 0, _offered_code)
		_: roster_changed.emit()


func _register(peer_id: int, name_hint: String, colour_index: int) -> Participant:
	if participants.has(peer_id):
		return participants[peer_id]
	var p := Participant.new()
	p.peer_id = peer_id
	p.display_name = name_hint
	p.colour_index = colour_index
	if peer_id == local_peer_id and layout != null:
		p.medium = layout.medium
	participants[peer_id] = p
	participant_joined.emit(peer_id)
	return p


## The lowest colour nobody is wearing. Join order alone would hand the eighth arrival the
## colour of someone still in the room the moment an earlier guest left and came back.
func _free_colour() -> int:
	var used := {}
	for id in participants:
		used[participants[id].colour_index] = true
	for i in PALETTE.size():
		if not used.has(i):
			return i
	return participants.size() % PALETTE.size()


func _close_peer() -> void:
	_close_beacon()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _restore_own_mix() -> void:
	if solo_backend.is_valid():
		solo_backend.call()
	else:
		DAW.use(OfflineBackend.new())


# --- arriving and leaving -----------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	# Only the host keeps the roster. A guest is told about the others by it, and registering
	# them here as well would give them a name and colour the host never chose.
	if role != Role.HOST:
		return
	# At the door, not in the room. They are let in by their hello, which carries the code.
	_pending[peer_id] = Time.get_ticks_msec()


func _on_peer_disconnected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	_pending.erase(peer_id)
	if mix_feed != null:
		mix_feed.revoke(peer_id)
	if not participants.has(peer_id):
		# Turned away, or never said hello. Nobody was told they arrived, so nobody is told
		# they left.
		return
	var who := name_of(peer_id)
	participants.erase(peer_id)
	participant_left.emit(peer_id)
	# Whatever they had their hand on is free the moment they are gone. A fader held by an
	# absent person cannot be moved by anybody, which is a broken desk.
	var dropped := false
	for key in holds.keys():
		if holds[key] == peer_id:
			holds.erase(key)
			dropped = true
	if dropped:
		_send_holds()
	_broadcast_roster()
	notice.emit("%s left the session." % who)


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, local_name, layout.medium if layout != null else 0, _offered_code)


func _on_connection_failed() -> void:
	var where := joined_address
	start_solo()
	_restore_own_mix()
	notice.emit("Could not join %s -- nobody answered on port %d." % [where, port])


func _on_server_disconnected() -> void:
	if role != Role.GUEST:
		return
	var host_name := name_of(1)
	start_solo()
	_restore_own_mix()
	notice.emit("Lost the connection to %s's session. Back on your own mix." % host_name)


## A guest introducing itself, and again whenever it renames. The first one is also the knock.
@rpc("any_peer", "call_remote", "reliable")
func _hello(display_name: String, medium: int, offered_code: String = "") -> void:
	if role != Role.HOST:
		return
	var from := multiplayer.get_remote_sender_id()
	var p: Participant = participants.get(from)
	var first := p == null
	if first:
		var refusal := admission_refusal(offered_code)
		if not refusal.is_empty():
			_turn_away(from, refusal)
			return
		_pending.erase(from)
		p = _register(from, display_name, _free_colour())
		admit(from)
	p.display_name = display_name.strip_edges().substr(0, 24)
	if p.display_name.is_empty():
		p.display_name = "Guest %d" % participants.size()
	p.medium = medium
	_broadcast_roster()
	if first:
		_send_holds()
		notice.emit("%s joined the session." % p.display_name)


## Why a knock with this code is not let in, or "" if it is. Compared case- and space-blind: a
## code is read aloud across a room, and "ab 12" typed for "AB12" is the same code.
func admission_refusal(offered: String) -> String:
	if code.is_empty():
		return ""
	var want := code.replace(" ", "").to_upper()
	var got := offered.replace(" ", "").to_upper()
	if got.is_empty():
		return "%s's session needs a code. Ask %s for it." % [local_name, local_name]
	if got != want:
		return "That is not %s's code." % local_name
	return ""


## Everything a newly admitted guest needs, in the order it needs it: the mix first, so the
## desk they are about to be shown is never empty; the roster and holds follow from `_hello`.
func admit(peer_id: int) -> void:
	_send_snapshot_to(peer_id)
	if mix_feed != null and mix_feed.sending and _connected():
		_give_audio_ticket.rpc_id(peer_id, mix_feed.grant(peer_id), mix_feed.port)


## The host's leave to listen. Sent over the reliable, admitted channel; the audio socket
## answers nothing that does not carry one.
@rpc("authority", "call_remote", "reliable")
func _give_audio_ticket(ticket: int, audio_port: int) -> void:
	_audio_ticket = ticket
	_audio_port = audio_port
	_apply_listening()


func _apply_listening() -> void:
	if mix_feed == null or role != Role.GUEST:
		return
	if hear_mix and _audio_ticket != 0:
		if not mix_feed.listening:
			mix_feed.listen(joined_address, _audio_port, _audio_ticket)
	elif mix_feed.listening:
		mix_feed.stop()


func _turn_away(peer_id: int, reason: String) -> void:
	_pending.erase(peer_id)
	if _connected():
		_turned_away.rpc_id(peer_id, reason)
	notice.emit("Someone tried to join without the right code.")
	# Hung up a moment later, for the same reason the host's goodbye is: closed now, the
	# disconnect overtakes the explanation and the guest is left guessing.
	var peer := multiplayer.multiplayer_peer
	get_tree().create_timer(GOODBYE_SECONDS).timeout.connect(func():
		if multiplayer.multiplayer_peer == peer and peer is ENetMultiplayerPeer:
			(peer as ENetMultiplayerPeer).disconnect_peer(peer_id))


@rpc("authority", "call_remote", "reliable")
func _turned_away(reason: String) -> void:
	start_solo()
	_restore_own_mix()
	notice.emit(reason)


func _tick_admission() -> void:
	if role != Role.HOST or _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for peer_id in _pending.keys():
		if now - int(_pending[peer_id]) > int(ADMIT_SECONDS * 1000.0):
			_pending.erase(peer_id)
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)


## The people in the room other than me -- who a host's word goes to. Not every connection: a
## guest at the door has a socket and no seat.
func _audience() -> Array:
	if role != Role.HOST or not _connected():
		return []
	return participants.keys().filter(func(id): return id != 1)


## Whether a message claiming to come from `peer_id` is from someone in the room.
func _is_member(peer_id: int) -> bool:
	return participants.has(peer_id)


@rpc("authority", "call_remote", "reliable")
func _goodbye() -> void:
	var host_name := name_of(1)
	start_solo()
	_restore_own_mix()
	notice.emit("%s ended the session. Back on your own mix." % host_name)


func _roster_rows() -> Array:
	var rows: Array = []
	for id in participants:
		var p: Participant = participants[id]
		rows.append([p.peer_id, p.display_name, p.medium, p.colour_index])
	return rows


func _broadcast_roster() -> void:
	if role != Role.HOST:
		return
	if _connected():
		var rows := _roster_rows()
		for id in _audience():
			_receive_roster.rpc_id(id, rows)
	roster_changed.emit()


## The host's word on who is here. Applied as a whole -- arrivals, departures, renames -- and
## heads and pointers carried across, so a rename does not snap someone's avatar to the origin.
@rpc("authority", "call_remote", "reliable")
func _receive_roster(rows: Array) -> void:
	apply_roster(rows)


func apply_roster(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var id: int = row[0]
		seen[id] = true
		var arriving := not participants.has(id)
		var p: Participant = _register(id, row[1], row[3])
		p.display_name = row[1]
		p.medium = row[2]
		p.colour_index = row[3]
		if arriving and id != local_peer_id and _has_settled:
			notice.emit("%s joined the session." % p.display_name)
	for id in participants.keys():
		if not seen.has(id):
			var who := name_of(id)
			participants.erase(id)
			participant_left.emit(id)
			if id != local_peer_id:
				notice.emit("%s left the session." % who)
	if not _has_settled and role == Role.GUEST:
		_has_settled = true
		notice.emit("Joined %s's session." % name_of(1))
	roster_changed.emit()



# --- intents ------------------------------------------------------------------------------

## A guest's write, forwarded to the host.
##
## Intents name a VERB from the DAW vocabulary -- `set_track_volume`, `transport_play` -- and
## not a wire message. That is what keeps a guest DAW-agnostic: the host may be driving Reaper
## over OSC and the guest need not contain a single OSC address to take part, which is the same
## reason the surfaces do not contain one either. See core/daw/daw.gd.
func send_intent(verb: StringName, args: Array) -> void:
	if is_authority():
		DAW.apply_intent(verb, args)
		return
	if not _connected():
		return
	_receive_intent.rpc_id(1, verb, args)


@rpc("any_peer", "call_remote", "reliable")
func _receive_intent(verb: StringName, args: Array) -> void:
	if not is_authority() or not _is_member(multiplayer.get_remote_sender_id()):
		return
	# Anyone the host let in may move any fader. With a session code that means anyone who was
	# told the code; without one, anyone on the network. The code is a door, not encryption:
	# right for a studio LAN, not for anything exposed to the internet. The verb is still checked against the vocabulary --
	# see DAW.apply_intent -- because trusting a peer with a fader is not the same as letting it
	# name any method on an object.
	DAW.apply_intent(verb, args)


# --- state replication --------------------------------------------------------------------

## Host -> guests, once per replication tick.
##
## Two RPCs rather than one, because the two halves of the batch need opposite guarantees and
## sending both reliably makes meter traffic block name changes behind it. See the buffers in
## core/reaper/reaper_link.gd for which is which.
func broadcast_state(durable: Dictionary, volatile: Dictionary) -> void:
	if not is_authority() or role == Role.SOLO:
		return
	var audience := _audience()
	if not durable.is_empty():
		var batch := _as_batch(durable)
		for id in audience:
			_receive_state_durable.rpc_id(id, batch)
	if not volatile.is_empty():
		# In parcels under the MTU. An unreliable packet ENet has to fragment is lost whenever
		# ANY fragment is, so one 1.5KB meter frame on wifi fails several times as often as
		# two small ones -- and forty tracks of meters is more than one packet.
		for parcel in _parcels(_as_batch(volatile)):
			for id in audience:
				_receive_state_volatile.rpc_id(id, parcel)


const PARCEL_BYTES := 1100


static func _parcels(batch: Array) -> Array:
	var out: Array = []
	var parcel: Array = []
	var bytes := 0
	for entry in batch:
		var size := var_to_bytes(entry).size()
		if not parcel.is_empty() and bytes + size > PARCEL_BYTES:
			out.append(parcel)
			parcel = []
			bytes = 0
		parcel.append(entry)
		bytes += size
	if not parcel.is_empty():
		out.append(parcel)
	return out


static func _as_batch(by_address: Dictionary) -> Array:
	var batch: Array = []
	for address in by_address:
		batch.append([address, by_address[address]])
	return batch


@rpc("authority", "call_remote", "reliable")
func _receive_state_durable(batch: Array) -> void:
	DAW.backend.apply_replicated(batch)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state_volatile(batch: Array) -> void:
	DAW.backend.apply_replicated(batch)


## A joining guest gets the whole session at once, reliably, before any delta reaches it.
##
## Without this a guest would start empty and fill in only as things were touched -- a console
## that grows a channel each time someone moves a fader, and never shows the tracks nobody
## happens to touch. The deltas are edge-triggered, so there is no second chance.
func _send_snapshot_to(peer_id: int) -> void:
	if not is_authority() or role == Role.SOLO:
		return
	if not participants.has(peer_id):
		return
	_receive_state_durable.rpc_id(peer_id, DAW.backend.snapshot())


# --- presence -----------------------------------------------------------------------------

## Where this participant's head is and what they are pointing at, a few dozen times a second.
##
## Unreliable and ordered: a pose is superseded by the next one in 50ms, and a lost one is
## better skipped than delivered late and walked back over.
func publish_presence(head_in_session_space: Transform3D, pointing_at: String,
		pointing_local: Vector3) -> void:
	var me: Participant = participants.get(local_peer_id)
	if me != null:
		me.head = head_in_session_space
		me.pointing_at = pointing_at
		me.pointing_local = pointing_local
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_presence_of.rpc_id(id, local_peer_id, head_in_session_space, pointing_at, pointing_local)
	else:
		_receive_presence.rpc_id(1, head_in_session_space, pointing_at, pointing_local)


func publish_head(head_in_session_space: Transform3D) -> void:
	var me: Participant = participants.get(local_peer_id)
	publish_presence(head_in_session_space,
			me.pointing_at if me != null else "", me.pointing_local if me != null else Vector3.ZERO)


## A guest's pose, to the host, which keeps it and passes it on to everyone else in the room.
## Relayed by hand rather than by ENet's server relay so the host decides who hears it -- see
## `host()`.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_presence(head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	if role != Role.HOST:
		return
	# The sender as the transport saw it, never as the packet claims. A pose arriving with
	# someone else's id would put a stranger's head on a friend's name tag.
	var from := multiplayer.get_remote_sender_id()
	if not _is_member(from):
		return
	_heard_presence(from, head, pointing_at, pointing_local)
	for id in _audience():
		if id != from:
			_presence_of.rpc_id(id, from, head, pointing_at, pointing_local)


## Somebody's pose, from the host. The id is the host's word, which the host got from the
## transport -- a guest cannot put words in another guest's mouth through it.
@rpc("authority", "call_remote", "unreliable_ordered")
func _presence_of(peer_id: int, head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	if peer_id == local_peer_id:
		return
	_heard_presence(peer_id, head, pointing_at, pointing_local)


func _heard_presence(peer_id: int, head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	var p: Participant = participants.get(peer_id)
	# Not registered from here: the roster is the host's, and a pose that outruns the roster
	# by a packet is simply early. The next one lands on a participant that exists.
	if p == null:
		return
	p.head = head
	p.pointing_at = pointing_at
	p.pointing_local = pointing_local
	p.heard_msec = Time.get_ticks_msec()


# --- holds --------------------------------------------------------------------------------
#
# A control is held by at most one person in the whole session. Locally that was always true --
# ControlAffordance refuses a second hand -- but two people on two machines each have exactly
# one hand on their own copy of the fader, and each copy says yes. So the host keeps the one
# table that matters and everyone asks it.
#
# The grab is optimistic: a hand moves its fader the instant it closes, because a desk that
# waits a round trip before it responds feels broken. If the host then says someone else got
# there first, the hand is made to let go, and the fader snaps to whatever the winner set.

## Called when this participant's hand closes on a control.
func claim_hold(key: String) -> void:
	if key.is_empty() or not _connected():
		return
	if role == Role.HOST:
		_grant(local_peer_id, key)
	else:
		_claim.rpc_id(1, key)


func release_hold(key: String) -> void:
	if key.is_empty() or not _connected():
		return
	if role == Role.HOST:
		_release(local_peer_id, key)
	else:
		_release_remote.rpc_id(1, key)


## Who has their hand on this control, or 0 for nobody.
func holder_of(key: String) -> int:
	return holds.get(key, 0)


@rpc("any_peer", "call_remote", "reliable")
func _claim(key: String) -> void:
	if role == Role.HOST and _is_member(multiplayer.get_remote_sender_id()):
		_grant(multiplayer.get_remote_sender_id(), key)


@rpc("any_peer", "call_remote", "reliable")
func _release_remote(key: String) -> void:
	if role == Role.HOST and _is_member(multiplayer.get_remote_sender_id()):
		_release(multiplayer.get_remote_sender_id(), key)


## The arbitration, in full: whoever the host heard from first. Not the lower peer id, not the
## later grab -- a rule nobody in the room can see is a rule that feels like the desk is broken.
## "Sam already had it" is a rule everyone can see, because Sam's hand is on it.
func _grant(peer_id: int, key: String) -> void:
	var holder: int = holds.get(key, 0)
	if holder != 0 and holder != peer_id:
		if peer_id == local_peer_id:
			hold_refused.emit(key, holder)
		elif _connected():
			_refused.rpc_id(peer_id, key, holder)
		return
	if holder == peer_id:
		return
	holds[key] = peer_id
	_send_holds()


func _release(peer_id: int, key: String) -> void:
	if holds.get(key, 0) != peer_id:
		return
	holds.erase(key)
	_send_holds()


func _send_holds() -> void:
	if role != Role.HOST:
		return
	if _connected():
		for id in _audience():
			_receive_holds.rpc_id(id, holds)
	holds_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_holds(table: Dictionary) -> void:
	holds = table
	holds_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _refused(key: String, holder: int) -> void:
	hold_refused.emit(key, holder)


# --- being found --------------------------------------------------------------------------
#
# A host says it exists to the LAN once a second, so the person across the room can pick it
# from a list instead of being read an IP address. Broadcast, not multicast: a studio LAN is
# one subnet, and broadcast works on every consumer router without anyone configuring IGMP.

func _open_beacon() -> void:
	_close_beacon()
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon_clock = BEACON_SECONDS


func _close_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null


func _tick_beacon(delta: float) -> void:
	if _beacon == null or role != Role.HOST:
		return
	_beacon_clock += delta
	if _beacon_clock < BEACON_SECONDS:
		return
	_beacon_clock = 0.0
	var packet := JSON.stringify(beacon_payload()).to_utf8_buffer()
	# The LAN, and this machine. Loopback is not reliably on the broadcast's path, and two
	# windows on one desk is how a session is first tried.
	for address in ["255.255.255.255", "127.0.0.1"]:
		_beacon.set_dest_address(address, DISCOVERY_PORT)
		_beacon.put_packet(packet)


func beacon_payload() -> Dictionary:
	return {
		"app": "reaper-3d",
		"v": 1,
		"name": local_name,
		"port": port,
		"people": participants.size(),
		"locked": not code.is_empty(),
		"tracks": DAW.state.project_track_count if DAW.state != null else 0,
	}
