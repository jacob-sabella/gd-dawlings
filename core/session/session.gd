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
## Host: a guest's recording was placed. {peer, track, start, seconds, path, name}.
signal audio_take_placed(info: Dictionary)
## Guest: the host's word on the room arrived; see `room`.
signal room_changed()
## A made item's row arrived (`made`, ItemRoom.mint), or was taken away (`gone`): a guest's word
## from the host, for the room to make it real or let it go.
signal made_changed(id: StringName, gone: bool)
## Host: someone asked to change the room. One of ROOM_VERBS, already checked for shape; the
## studio decides, and says what the room now is with `publish_room`.
signal room_asked(verb: StringName, args: Array, from: int)
## Guest: the host's word on the tour run under way arrived; see `tour`.
signal tour_changed()
## Host: someone asked to act on the run under way. One of TOUR_VERBS, already checked for
## shape; `Tour` decides, and says what the run now is with `publish_tour`.
signal tour_asked(verb: StringName, args: Array, from: int)
## Guest: the host's word on the last Rig Roulette roll arrived; see `roll`.
signal roll_changed()
## Guest: the host's word on what the next Rig Roulette roll is set to arrived; see `roll_setup`.
signal roll_setup_changed()
## Something in the room being pushed right now, by `from`: where it is this moment. Unconfirmed
## and unsaved -- the ask when it is let go is what counts -- and only for drawing it moving.
signal room_motion(piece: StringName, x: float, z: float, heading: float, from: int)
## Something in `from`'s hand, where it is this moment: relative to their head, so it lands in
## their ghost's glove wherever everyone has the ghost. Unreliable, like a head.
signal item_carried(item: StringName, local: Transform3D, from: int)
## Where something somebody is flying is (the radio plane, RcPlaneItem), in the session's frame,
## and how it is flying (its Mode).
signal item_flown(item: StringName, pose: Transform3D, mode: int, from: int)
## Something in `from`'s hand, used: a duck squeezed (`down`) or let go of. Reliable, because a
## squeak is an event, and a lost one is a silence nobody can account for. `take`: which of Foley's
## takes their hand rang (Item.use_take), so everyone hears the sound its player heard and the
## host's sampler catches exactly that (Sampler); -1 for not known.
signal item_used(item: StringName, down: bool, from: int, take: int)
## A key or the pedal on `from`'s keys, as they play it (`send_note`): for anyone patched into
## their keys to play here (TheirKeys), or into their monitor (TheirMonitor). `song`: the song
## position they were hearing as they played it, or -1 with their transport stopped. `source`:
## what of theirs played it (GuestMidi.instruments' names, `&""` for plain keys), so a note can
## be heard from the instrument that played it. Reliable and ordered, because a lost note-off is
## a note that never stops.
signal note_played(kind: int, pitch: int, velocity: int, from: int, song: float, source: StringName)
## An instrument in `from`'s hand shaken into a hit (InstrumentItem), `velocity` 1 to 127: for
## everyone else to hear from their hand. A click on percussion is a use (`item_used`), not this;
## a click on a pitched item (a handbell) is this too. `song`: the song position they played it
## to (the hit's one stamp, InstrumentItem.played's `at`), or -1 when not known, so a pitched item
## rings here the note it rang there, whenever it arrives. `snap`: whether its player snaps their
## hand percussion (GuestMidi.snap_hits), so whoever takes the hit down snaps it by their choice,
## not their own (HitRecorder.hit). `take`: which of Foley's takes their hand rang
## (InstrumentItem.sound_take), so everyone hears the sound its player heard; -1 for not known.
signal item_hit(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int)
## An event down a jack into this player's instrument (docs/spatial_loop.md slice 6): `source`'s
## (an item's id, `harp`, `keys:P`) `kind` (Jack.Kind: NOTE_ON, NOTE_OFF, TRIGGER), sent by `from`
## at song position `song` (-1 for not known), passed on by the host to this player alone (Jacks).
signal jack_played(source: StringName, kind: int, pitch: int, velocity: int, from: int, song: float)

## A control on `from`'s keys, as they move it (`send_control`): `kind` the pitch wheel
## (DawKitClip.PITCH_BEND) or controller 1 (the mod wheel) or 11 (expression), `value` already
## kept in bounds by the host (`control_value`). For whoever plays their keys here (TheirKeys,
## TheirMonitor, the harp), to the one voice they have for that player. Unreliable: a lost one is
## sent again soon, and the wheel goes back to rest at the player's last note-off on every end
## (GuestMidi.control).
signal control_played(kind: int, value: int, from: int, song: float, source: StringName)

## What a `note_played` is.
enum Note { OFF, ON, PEDAL_UP, PEDAL_DOWN }

var role: int = Role.SOLO
## {peer_id: Participant}
var participants: Dictionary = {}
var local_peer_id: int = 1
## What this person is called in everyone else's room. Set before hosting or joining.
var local_name: String = ""
## What my ghost wears, as chosen at a mirror. Kept at `look_path` between runs; "" keeps it
## in memory only, which is what the suite does so as not to dress the real one.
var local_look: Dictionary = GhostLook.default_look()
var look_path := GhostLook.PATH
## {control key: peer_id}. Owned by the host and replicated whole, because it is small and a
## guest that missed a release would otherwise see a fader held forever by someone long gone.
var holds: Dictionary = {}
## Whether a hold (by key) can be taken from whoever has it (`take_hold`): the room's items.
## Set by the studio; unset, nothing can.
var takeable: Callable = Callable()
## Who a hold (by key) is kept for, if anyone: `(key, peer_id) -> int`, 0 when `peer_id` may
## have it, else the peer it is kept for, whom a refusal names (`_grant`). The host's word on
## an item marked for one person (Item.bound_to), asked on every claim and take so a hand that
## was not told -- or did not listen -- is refused all the same. Set by the studio; unset,
## anything free is anyone's.
var holdable: Callable = Callable()
## The address this session was joined at, for the panel to say back.
var joined_address: String = ""
var port: int = DEFAULT_PORT
## The hosted session opened to the internet through the router (`open_to_internet`): what the
## host tells someone who is not in the room.
var internet := InternetDoor.new()
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
## A guest's keyboard, played into the host's project. See core/session/guest_midi.gd.
var guest_midi: GuestMidi = null
## This guest's microphone, recorded into the host's project. See core/session/guest_audio.gd.
var guest_audio: GuestAudio = null
## The host's own microphone, on a DAW that does not record its own inputs: the same recorder,
## timed against the host's own playhead (`host_heard`) and kept here.
var host_audio: GuestAudio = null
## Sound files from a guest's machine into the host's project. See core/session/file_send.gd.
var files: FileSend = null
## The ENet channel a guest's recording travels on: its own, so a take in flight never queues a
## fader move or a hold behind it.
const AUDIO_TAKE_CHANNEL := 3
## Things being pushed about the room: unreliable and ordered, on a channel of their own so a
## rack being wheeled is never queued behind anyone's head.
const MOTION_CHANNEL := 4
## Notes as they are played: their own channel, so a key is never queued behind a room update.
const KEYS_CHANNEL := 5
## Pitch bend and the two controllers beside it, as they move: a channel of their own,
## unreliable and ordered, so a lost control never holds a note back behind its resend (the
## head-of-line delay a reliable channel has) and the notes stay reliable on KEYS_CHANNEL.
const CONTROLS_CHANNEL := 6
## The controls a player's keys carry (`send_control`): the pitch wheel, the mod wheel (1) and
## expression (11). The host passes these and refuses any other. A take carries the same
## (MidiTake.CONTROL_KINDS), and so does a jack (Jack.Kind.CC).
const CONTROL_KINDS := MidiTake.CONTROL_KINDS
## Host: how many controls have been refused (a controller not in CONTROL_KINDS), for the probe
## and the suite.
var controls_refused := 0
## The longest a note's source may be (`send_note`): an instrument's name. Anything longer that
## a guest sends is taken as plain keys.
const NOTE_SOURCE_MAX := 24
## Host: the studio's word on a jack's event (`send_jack`): (to, source, from) -> String, empty
## when the room's patch sends `source` into `to` and `from` is the one who plays it
## (Jacks.send_refusal). Unset, nothing is passed: there is no room here to say.
var jack_check: Callable = Callable()
## Host: how many jack events have been refused, for the probe and the suite.
var jacks_refused := 0
## Host: the take each guest is sending now, by peer id -- {id, take, track, start, name, refused}.
var _incoming_takes := {}
## Takes written on this host this run, for naming their files.
var _takes_made := 0
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

## The room everyone is standing in, as the host has it: {"venue": id, "tablets": {stand id:
## [track, fx, plugin name, x, z, heading]}, "floor": {piece id: [x, z, heading]}, "placed":
## {surface id: Transform3D}, "items": {item id: [x, y, z, yaw] on the floor -- and, while it is
## in the air, [..., throws, origin, velocity, spin] -- or [] in a hand, [true] on a head},
## "patches": {peer id: [SEND socket per tablet receiver, "" for none]},
## "jacks": {source: sink}, where each instrument's output jack goes (Jacks)}
## -- the venue, the plugins out on stands, where every stand and
## trolley is, and where gear that stands on nothing (the desk) has been put. A fact about the room, like where the desk is, so
## it is the host's and there is one of it; a guest's own venue and tablets wait in its layout
## for when it is on its own again. Empty until the host has said.
var room: Dictionary = {}
## Every made item's row, {id: [kind, maker, bytes]} (docs/spatial_loop.md part two, slice 23):
## what a cassette carries, var_to_bytes of its data. The host's, as its room mints them
## (ItemRoom.mint, `publish_made`); sent once to everyone on a reliable message of its own
## (`_made`) and all of it to a guest as it is let in, never inside `room`, which names only
## the ids ("made"), so a put-down, a throw or a plug never resends a clip. One Dictionary for
## the whole run, the room's own (ItemRoom.made is this): cleared, never replaced.
var made: Dictionary = {}
## Guest: the number of the last ask sent. The host's room says which it has answered, so
## whatever is newer is still this guest's prediction and is put back on top of the host's word.
var room_seq := 0
## Host: the last ask heard from each guest, sent with the room as "acks".
var _room_acks: Dictionary = {}
var _room_sent := false

## The tour run under way, as `Tour.start_run()` built it (`TourRun.to_dict()`), or `{}` when
## no run is under way. Not DAW/project state -- see core/tour/tour.gd -- so it rides its own
## channel here rather than through `DAW._do`/`apply_intent` or `MixState`. Built identically
## to `room`: host-authoritative, replicated whole, sent again to a guest admitted mid-run.
var tour: Dictionary = {}

## The last Rig Roulette roll, as `Studio._roll_rig` wrote it up, or `{}` before any. What the
## wall board reads. Built like `tour`: host-authoritative, replicated whole, sent again to a
## guest admitted afterwards.
var roll: Dictionary = {}

## What the host has set for the next roll (`RollSettings.to_dict`), or `{}` before it set anything.
## What the setup wall's wheels show a guest. Host-authoritative like `roll`: only the host's
## word is taken, and a guest's own nudge of a wheel is put back.
var roll_setup: Dictionary = {}

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
	## What their ghost wears. See GhostLook.
	var look: Dictionary = GhostLook.default_look()


func _init() -> void:
	# First thing any part of the app does, before anything reads a saved file: this is the
	# first autoload. See DataHome.
	DataHome.migrate()


func _ready() -> void:
	mix_feed = MixFeed.new()
	mix_feed.name = "MixFeed"
	add_child(mix_feed)
	guest_midi = GuestMidi.new()
	guest_midi.name = "GuestMidi"
	add_child(guest_midi)
	guest_audio = GuestAudio.new()
	guest_audio.name = "GuestAudio"
	add_child(guest_audio)
	host_audio = GuestAudio.new()
	host_audio.name = "HostAudio"
	host_audio.for_host = true
	host_audio.heard = host_heard
	add_child(host_audio)
	files = FileSend.new()
	files.name = "FileSend"
	add_child(files)
	layout = LayoutProfile.new()
	local_name = _default_name()
	local_look = GhostLook.load_from(look_path)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Deferred: DAW is an autoload too, and may not be in the tree yet.
	(func():
		DAW.project_replaced.connect(_on_project_replaced)
		DAW.tracks_renumbered.connect(_on_tracks_renumbered)
		DAW.project_saved.connect(func(said): _announce_save(local_name, said))
		DAW.render_finished.connect(_announce_render)).call_deferred()


## Quitting while hosting is ending the session, and says so. Blocking, briefly, because there
## is no next frame to finish the goodbye in: the packet is serviced out by hand until it has
## had time to land, and only then does the socket close behind it.
func _exit_tree() -> void:
	# The router's forwarding comes down with the session, and is waited for: a quit is the
	# last chance, and a port left open on someone's router is not ours to leave.
	if internet.state != InternetDoor.State.CLOSED:
		internet.close()
	internet.finish()
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
	# A guest's made items were the host's room's; a host's own stay with its room. Our own, set
	# aside on joining, are the layout's to give back (Studio._restore_made).
	if role == Role.GUEST:
		_forget_made()
	role = Role.SOLO
	room = {}
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
	room = {}
	_room_acks.clear()
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
	# This player's own made items are set aside, not saved over: the host's room's are the ones
	# here now, and ours would only count against what it may carry (`_made`). Their layout
	# still has them, and gives them back on leaving (Studio._restore_made).
	_forget_made()
	room = {}
	room_seq = 0
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


## Ask the router to forward this session's ports here (UDP: the session's own, and the mix's
## audio beside it), so people outside the room can join at the router's public address. The
## host only, and only when asked: it changes the host's network. `internet.changed` reports.
func open_to_internet() -> void:
	if role != Role.HOST:
		return
	internet.open([port, port + AUDIO_PORT_OFFSET] as Array[int])


func close_to_internet() -> void:
	internet.close()


## Back to being on your own. A host says goodbye first; a guest gets its own mix back.
func leave() -> void:
	if role == Role.SOLO:
		return
	var was_guest := role == Role.GUEST
	# Takes still arriving are placed while this is still the host's mix to place them in.
	for peer_id in _incoming_takes.keys():
		_finish_take(peer_id)
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
		Role.GUEST when _connected(): _introduce()
		_: roster_changed.emit()


## Dress my ghost. Kept for next time, and told to the session the same way a rename is.
func set_look(look: Dictionary) -> void:
	local_look = GhostLook.clean(look)
	GhostLook.save_to(local_look, look_path)
	if participants.has(local_peer_id):
		participants[local_peer_id].look = local_look.duplicate()
	match role:
		Role.HOST: _broadcast_roster()
		Role.GUEST when _connected(): _introduce()
		_: roster_changed.emit()


func _introduce() -> void:
	_hello.rpc_id(1, local_name, layout.medium if layout != null else 0, _offered_code, local_look)


func _register(peer_id: int, name_hint: String, colour_index: int) -> Participant:
	if participants.has(peer_id):
		return participants[peer_id]
	var p := Participant.new()
	p.peer_id = peer_id
	p.display_name = name_hint
	p.colour_index = colour_index
	if peer_id == local_peer_id:
		p.look = local_look.duplicate()
		if layout != null:
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
	if internet.state != InternetDoor.State.CLOSED:
		internet.close()
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
	# A take still arriving is kept: what was sung before the line dropped is still a take.
	_finish_take(peer_id)
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
	# And an edit group they left open is closed: their let-go is never coming, and the step it
	# was gathering is a whole step as it stands.
	DAW.close_edits_of(peer_id)
	_broadcast_roster()
	notice.emit("%s left the session." % who)


func _on_connected_to_server() -> void:
	_introduce()


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
func _hello(display_name: String, medium: int, offered_code: String = "", look: Dictionary = {}) -> void:
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
	p.look = GhostLook.clean(look)
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
	# What the room's made items carry, before the room that names them.
	if _connected():
		for id in made:
			var row: Array = made[id]
			_made.rpc_id(peer_id, id, row[0], int(row[1]), row[2])
	if not room.is_empty() and _connected():
		_receive_room.rpc_id(peer_id, _room_with_acks())
	if not tour.is_empty() and _connected():
		_receive_tour.rpc_id(peer_id, tour)
	if not roll.is_empty() and _connected():
		_receive_roll.rpc_id(peer_id, roll)
	if not roll_setup.is_empty() and _connected():
		_receive_roll_setup.rpc_id(peer_id, roll_setup)
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
		rows.append([p.peer_id, p.display_name, p.medium, p.colour_index, p.look])
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
		# A host from before looks existed sends four columns: everyone in its default.
		p.look = GhostLook.clean(row[4] if row.size() > 4 else {})
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

## For the suite: while true, every intent a guest sends is also kept in `kept_intents` as
## [verb, args], whether or not there is a host to send it to, so what a guest asks can be counted.
var keep_intents := false
var kept_intents: Array = []

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
	if keep_intents:
		kept_intents.append([verb, args])
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
	if verb == &"insert_midi_take":
		_place_take(multiplayer.get_remote_sender_id(), args)
		return
	if verb == &"save_project":
		save_project_for(name_of(multiplayer.get_remote_sender_id()))
		return
	# Whose it is, so their edit group gathers their writes and nobody else's (DAW.open_edit).
	DAW.apply_intent(verb, args, multiplayer.get_remote_sender_id())


## Saves the open project where it is, and tells the whole room how it went: a save is the one
## thing everyone in a session wants to know happened, whoever pressed it. `who` is the name of
## whoever asked, which on the host is the host.
func save_project_for(who: String) -> PackedStringArray:
	var said: PackedStringArray = DAW.backend.save_project("")
	_announce_save(who, said)
	return said


func _announce_save(who: String, said: PackedStringArray) -> void:
	var where: String = DAW.backend.project_path.get_file()
	var text := "%s saved the project%s." % [who, " as " + where if not where.is_empty() else ""]
	if not said.is_empty():
		text = "%s saved the project, but: %s" % [who, "; ".join(said)]
	tell_room(text)


## Said to the room by whoever's DAW rendered: the host.
func _announce_render(files: PackedStringArray, problems: PackedStringArray) -> void:
	if not is_authority():
		return
	var text := "Rendered %s." % ", ".join(Array(files).map(func(f): return str(f).get_file()))
	if files.is_empty():
		text = "Nothing was rendered."
	if not problems.is_empty():
		text = "%s But: %s" % [text, "; ".join(problems)]
	tell_room(text)


## A notice for this participant and every other one.
func tell_room(text: String) -> void:
	notice.emit(text)
	if is_authority():
		for id in _audience():
			_told.rpc_id(id, text)


## A guest's take, placed, and both sides told how it went: the guest because it cannot see a
## refusal any other way, the host because a new item appearing on its timeline unannounced is
## a surprise in the middle of a session.
func _place_take(from: int, args: Array) -> void:
	var who := name_of(from)
	var refusal := DAW.midi_take_refusal(args)
	if not refusal.is_empty():
		notice.emit("%s's take was not placed. %s" % [who, refusal])
		if _connected():
			_told.rpc_id(from, "Your take was not placed. " + refusal)
		return
	# Hers, not the host's: a take landing mid-way through the host's drag is a step of its own.
	DAW.apply_intent(&"insert_midi_take", args, from)
	var cleaned := MidiTake.clean_args(args)
	var track: String = DAW.state.track(cleaned[0]).display_name()
	var at := DAW.state.bar_beat(cleaned[1])
	var count := (cleaned[3] as Array).size()
	var notes := "%d %s" % [count, "note" if count == 1 else "notes"]
	# Not during a Tour run: a part's take is rolled every bar, and a notice a bar per player
	# playing one buries the room; the run's HUD ticks the part instead.
	if tour.is_empty():
		notice.emit("%s played %s onto %s at %s." % [who, notes, track, at])
	if _connected():
		_told.rpc_id(from, "Your take is on %s: %s from %s." % [track, notes, at])


# --- a guest's recording --------------------------------------------------------------------
#
# Not an intent: an intent is a verb with a few arguments, and a take is minutes of sound. The
# guest streams it while it records (GuestAudio), the host writes it to a WAV as it arrives
# (AudioTake), and when it ends the host places the file with its own DAW.insert_audio_take. A
# guest never names a file; the host does.

#
# The host's own recording, on a DAW that does not record its own inputs (the built-in engine),
# comes through the same three calls and is kept the same way, from the host's own id.

## `plan`, the host's own only: [track, channel] for each track the take goes onto, the channel 0
## for both, 1 or 2 for that input channel alone (GuestAudio.take_plan). Empty is `track`, both.
func send_audio_begin(take_id: int, track: int, start: float, take_name: String, plan: Array = []) -> void:
	if role == Role.GUEST and _connected():
		_audio_begin.rpc_id(1, take_id, track, start, take_name)
	elif is_authority():
		_take_begin(local_peer_id, take_id, track, start, take_name, plan)


func send_audio_chunk(take_id: int, pcm: PackedByteArray) -> void:
	if role == Role.GUEST and _connected():
		_audio_chunk.rpc_id(1, take_id, pcm)
	elif is_authority():
		_take_chunk(local_peer_id, take_id, pcm)


## The host's own take, as each input channel its tracks want: {channel: pcm} (see _take_chunk).
func send_audio_channels(take_id: int, by_channel: Dictionary) -> void:
	if is_authority():
		_take_chunk(local_peer_id, take_id, by_channel)


func send_audio_end(take_id: int) -> void:
	if role == Role.GUEST and _connected():
		_audio_end.rpc_id(1, take_id)
	elif is_authority():
		_take_end(local_peer_id, take_id)


@rpc("any_peer", "call_remote", "reliable", AUDIO_TAKE_CHANNEL)
func _audio_begin(take_id: int, track: int, start: float, take_name: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if not is_authority() or not _is_member(from):
		return
	_take_begin(from, take_id, track, start, take_name)


@rpc("any_peer", "call_remote", "reliable", AUDIO_TAKE_CHANNEL)
func _audio_chunk(take_id: int, pcm: PackedByteArray) -> void:
	_take_chunk(multiplayer.get_remote_sender_id(), take_id, pcm)


@rpc("any_peer", "call_remote", "reliable", AUDIO_TAKE_CHANNEL)
func _audio_end(take_id: int) -> void:
	_take_end(multiplayer.get_remote_sender_id(), take_id)


func _take_begin(from: int, take_id: int, track: int, start: float, take_name: String, plan: Array = []) -> void:
	# One take at a time from each guest: a begin while one is open ends that one first.
	_finish_take(from)
	if plan.is_empty():
		plan = [[track, 0]]
	var entry := {"id": take_id, "start": maxf(start, 0.0), "name": MidiTake.clean_name(take_name),
			"parts": []}
	_incoming_takes[from] = entry
	for step in plan:
		var refusal := DAW.audio_take_refusal(int(step[0]), 1.0)
		var take: AudioTake = null
		if refusal.is_empty():
			_takes_made += 1
			take = AudioTake.create(AudioTake.file_name_for(_who(from), _takes_made))
			if take == null:
				refusal = "The host could not write the recording to its disk."
		if not refusal.is_empty():
			if from == local_peer_id:
				notice.emit("Your recording is not being kept. " + refusal)
			else:
				notice.emit("%s's recording was not kept. %s" % [_who(from), refusal])
				_told.rpc_id(from, "Your recording is not being kept. " + refusal)
			continue
		(entry["parts"] as Array).append({"take": take, "track": int(step[0]), "channel": int(step[1])})


## `pcm` for every part of the take, or, from the host's own recorder, a Dictionary of it by
## channel (0 both sides, 1 and 2 each alone; see send_audio_channels).
func _take_chunk(from: int, take_id: int, pcm: Variant) -> void:
	var entry: Dictionary = _incoming_takes.get(from, {})
	if entry.is_empty() or entry["id"] != take_id:
		return
	for part in entry["parts"]:
		var bytes: PackedByteArray = pcm.get(part["channel"], PackedByteArray()) if pcm is Dictionary else pcm
		if not (part["take"] as AudioTake).append(bytes):
			# At its limit: placed as it stands, and the rest of it ignored.
			_finish_take(from)
			return


func _take_end(from: int, take_id: int) -> void:
	var entry: Dictionary = _incoming_takes.get(from, {})
	if not entry.is_empty() and entry["id"] == take_id:
		_finish_take(from)


## A guest's take closed and placed, and both sides told: the guest because a recording that
## vanished would be a disaster they could not see, the host because a new item appearing on its
## timeline unannounced is a surprise in the middle of a session. A take that went onto several
## tracks is placed on each.
func _finish_take(from: int) -> void:
	var entry: Dictionary = _incoming_takes.get(from, {})
	_incoming_takes.erase(from)
	for part in entry.get("parts", []):
		_place_part(from, entry, part)


func _place_part(from: int, entry: Dictionary, part: Dictionary) -> void:
	var take: AudioTake = part["take"]
	var track: int = part["track"]
	take.finish()
	if take.frames == 0:
		take.discard()
		return
	var who := _who(from)
	var refusal := DAW.audio_take_refusal(track, take.seconds())
	var still_here := from != local_peer_id and _connected() and multiplayer.get_peers().has(from)
	if not refusal.is_empty():
		notice.emit("%s's recording was not placed. %s It is kept at %s." % [who, refusal,
				ProjectSettings.globalize_path(take.path)])
		if still_here:
			_told.rpc_id(from, "Your recording was not placed. " + refusal)
		return
	DAW.on_behalf_of(from, func() -> void:
		DAW.insert_audio_take(track, entry["start"], take.file_name(), take.seconds(),
				take.peaks(), entry["name"]))
	var track_name: String = DAW.state.track(track).display_name()
	var at := DAW.state.bar_beat(entry["start"])
	var length := "%.1fs" % take.seconds()
	notice.emit("%s recorded %s onto %s at %s." % [who, length, track_name, at])
	if still_here:
		_told.rpc_id(from, "Your recording is on %s: %s from %s." % [track_name, length, at])
	audio_take_placed.emit({"peer": from, "track": track, "start": entry["start"],
			"seconds": take.seconds(), "path": take.path, "name": entry["name"]})


## A name for whoever a take is from: this machine's own name for its own, which a host alone
## (with no roster) still has.
func _who(peer_id: int) -> String:
	return local_name if peer_id == local_peer_id else name_of(peer_id)


## Where the host's own song is in the host's ears: the playhead, less what the output still
## holds. What the host's recording is timed against (`host_audio`), as a guest's is against
## the stream it hears. {seconds, playing, recording, valid}.
func host_heard() -> Dictionary:
	var s := DAW.state
	if s == null:
		return {"seconds": 0.0, "playing": false, "recording": false, "valid": false}
	var heard := s.position_seconds - AudioServer.get_output_latency()
	return {"seconds": heard, "playing": s.playing,
			"recording": s.recording and s.playing and s.takes_at(heard), "valid": true}


## Words from the host for this guest alone.
@rpc("authority", "call_remote", "reliable")
func _told(text: String) -> void:
	notice.emit(text)


# --- the room -----------------------------------------------------------------------------

## What a guest may ask of the room. Not the venue: whose room it is decides what it looks like.
const ROOM_VERBS := {&"open_tablet": [TYPE_INT, TYPE_INT, TYPE_STRING, TYPE_FLOAT, TYPE_FLOAT],
		&"close_tablet": [TYPE_STRING_NAME], &"move_tablet": [TYPE_STRING_NAME, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT],
		&"move_piece": [TYPE_STRING_NAME, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT],
		&"place_surface": [TYPE_STRING_NAME, TYPE_TRANSFORM3D],
		&"put_item": [TYPE_STRING_NAME, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT], &"home_item": [TYPE_STRING_NAME],
		&"throw_item": [TYPE_STRING_NAME, TYPE_VECTOR3, TYPE_VECTOR3, TYPE_VECTOR3],
		&"wear_item": [TYPE_STRING_NAME, TYPE_BOOL], &"pocket_item": [TYPE_STRING_NAME, TYPE_INT], &"patch": [TYPE_INT, TYPE_STRING_NAME],
		&"on_air": [TYPE_BOOL], &"take_personal": [TYPE_STRING_NAME], &"board_source": [TYPE_STRING_NAME],
		&"open_track_rack": [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT], &"close_track_rack": [TYPE_STRING_NAME],
		# An instrument's output jack into a sink (Jack), or unplugged (an empty sink).
		&"plug": [TYPE_STRING_NAME, TYPE_STRING_NAME],
		# The fifths wheel's SET: the bar it writes at and the brackets' inside (FifthsWheel).
		&"harmony": [TYPE_INT, TYPE_STRING],
		# A stage table's rope tied or cut, and whether it added the compressor it keys: the room's
		# `ropes` row (StageTable.ropes; docs/spatial_loop.md slice 20).
		&"rope": [TYPE_STRING, TYPE_BOOL, TYPE_BOOL],
		# Made while playing (docs/spatial_loop.md part two, slice 23): a made item of a kind, of
		# something the host has ("clip:<track>:<item>"), never its data, which the host packs;
		# an item into a holder's slot (ItemRoom.holders: the cassette rack, its bin); and an
		# item handed to a bandmate, into their hand.
		&"make": [TYPE_STRING_NAME, TYPE_STRING],
		&"slot_item": [TYPE_STRING_NAME, TYPE_STRING_NAME, TYPE_INT],
		&"give": [TYPE_STRING_NAME, TYPE_INT],
		# A cassette in the asker's hand pasted onto a track at a song time (slice 24): named by
		# its id, never its clip, which the host pastes from its own row (DAW.paste_item).
		&"paste": [TYPE_STRING_NAME, TYPE_INT, TYPE_FLOAT],
		# The sampler's REC pressed on (for the asker's next sound) or off (slice 26): the room's
		# `sampler` row, the peer it is armed for or 0 (Sampler.armed_by).
		&"sampler": [TYPE_BOOL]}


## Every made item's row gone from this machine, and said (`made_changed`), so its item goes too.
## Nothing is saved by it: as a guest, nothing here is this player's to save.
func _forget_made() -> void:
	for id in made.keys():
		made.erase(id)
		made_changed.emit(id, true)


## Host: made item `id`'s row (`made`) to everyone, once, on its own reliable message: before the
## room that will name it, on the same channel, so it is there when the room arrives.
func publish_made(id: StringName) -> void:
	if role != Role.HOST or not made.has(id):
		return
	var row: Array = made[id]
	for peer in _audience():
		_made.rpc_id(peer, id, row[0], int(row[1]), row[2])


## Host: made item `id` is gone (the BIN): its row with it, everywhere.
func drop_made(id: StringName) -> void:
	made.erase(id)
	if role != Role.HOST:
		return
	for peer in _audience():
		_unmade.rpc_id(peer, id)


## A made item's row, from the host: kept if it is one, within what a room may carry
## (ItemRoom.MADE_BYTES, MADE_MOST), and said.
@rpc("authority", "call_remote", "reliable")
func _made(id: StringName, kind: StringName, maker: int, bytes: PackedByteArray) -> void:
	if role != Role.GUEST or not ItemRoom.is_made(id) or ItemRoom.kind_of(id) != kind \
			or bytes.size() > ItemRoom.MADE_BYTES or (not made.has(id) and made.size() >= ItemRoom.MADE_MOST):
		return
	made[id] = [kind, maker, bytes]
	made_changed.emit(id, false)


@rpc("authority", "call_remote", "reliable")
func _unmade(id: StringName) -> void:
	if role != Role.GUEST:
		return
	made.erase(id)
	made_changed.emit(id, true)


## Host: `key` (an item's network key) is in `peer`'s hand now, whoever had it: a give, or a made
## item minted for the guest who asked (docs/spatial_loop.md part two, slice 23). Their hand takes
## it when they hear (the studio's `_take_given`); one that had it lets go (Presence).
func hand_to(peer: int, key: String) -> void:
	if not is_authority() or key.is_empty() or (peer != local_peer_id and not _is_member(peer)):
		return
	if holds.get(key, 0) == peer:
		return
	holds[key] = peer
	_send_holds()


## Host: this is the room now. Sent to everyone in it, and to each guest as they come in.
func publish_room(state: Dictionary) -> void:
	if role != Role.HOST:
		return
	room = state
	_room_sent = true
	for id in _audience():
		_receive_room.rpc_id(id, _room_with_acks())


func _room_with_acks() -> Dictionary:
	var out := room.duplicate()
	out["acks"] = _room_acks.duplicate()
	return out


## Guest: ask the host to change the room, and get back the ask's number -- the guest goes ahead
## and does it, and the number is how it learns the host has answered. 0 when nothing was sent:
## the host's own asks go straight to its studio, and there is nobody to predict for.
func ask_room(verb: StringName, args: Array) -> int:
	if not room_ask_is_valid(verb, args):
		return 0
	if is_authority():
		room_asked.emit(verb, args, local_peer_id)
		return 0
	if not _connected():
		return 0
	room_seq += 1
	_room_asked.rpc_id(1, room_seq, verb, args)
	return room_seq


## Where something being pushed is right now, to everyone else. Often and unreliably, like a head:
## a lost one is overtaken by the next.
func send_motion(piece: StringName, x: float, z: float, heading: float) -> void:
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_motion.rpc_id(id, piece, x, z, heading, local_peer_id)
	else:
		_motion_up.rpc_id(1, piece, x, z, heading)


@rpc("any_peer", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _motion_up(piece: StringName, x: float, z: float, heading: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	room_motion.emit(piece, x, z, heading, from)
	for id in _audience():
		if id != from:
			_motion.rpc_id(id, piece, x, z, heading, from)


@rpc("authority", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _motion(piece: StringName, x: float, z: float, heading: float, from: int) -> void:
	room_motion.emit(piece, x, z, heading, from)


## Where the thing in my hand is now, relative to my head, to everyone else. As often as a head.
func send_carry(item: StringName, local: Transform3D) -> void:
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_carry.rpc_id(id, item, local, local_peer_id)
	else:
		_carry_up.rpc_id(1, item, local)


@rpc("any_peer", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _carry_up(item: StringName, local: Transform3D) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	item_carried.emit(item, local, from)
	for id in _audience():
		if id != from:
			_carry.rpc_id(id, item, local, from)


@rpc("authority", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _carry(item: StringName, local: Transform3D, from: int) -> void:
	item_carried.emit(item, local, from)


## Where the thing I am flying is, in the session's frame, and how it flies, to everyone else.
## As often as a head, while it is away from its radio.
func send_flier(item: StringName, pose: Transform3D, mode: int) -> void:
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_flier.rpc_id(id, item, pose, mode, local_peer_id)
	else:
		_flier_up.rpc_id(1, item, pose, mode)


@rpc("any_peer", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _flier_up(item: StringName, pose: Transform3D, mode: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	item_flown.emit(item, pose, mode, from)
	for id in _audience():
		if id != from:
			_flier.rpc_id(id, item, pose, mode, from)


@rpc("authority", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _flier(item: StringName, pose: Transform3D, mode: int, from: int) -> void:
	item_flown.emit(item, pose, mode, from)


## The thing in my hand, used, for everyone else to hear and see, with the Foley take my hand
## rang (`take`, Item.use_take; -1 for not known).
func send_item_use(item: StringName, down: bool, take := -1) -> void:
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_item_use.rpc_id(id, item, down, local_peer_id, take)
	else:
		_item_use_up.rpc_id(1, item, down, take)


@rpc("any_peer", "call_remote", "reliable")
func _item_use_up(item: StringName, down: bool, take: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	take = clean_take(take)
	item_used.emit(item, down, from, take)
	for id in _audience():
		if id != from:
			_item_use.rpc_id(id, item, down, from, take)


@rpc("authority", "call_remote", "reliable")
func _item_use(item: StringName, down: bool, from: int, take: int) -> void:
	item_used.emit(item, down, from, take)


## A guest's Foley take as the host passes it on: one of Foley's (0 to 2^24), or -1 for not known.
static func clean_take(take: int) -> int:
	return take if take >= 0 and take < 1 << 24 else -1


## A shake of the instrument in my hand, to everyone else, with the song position it was played
## to (`song`, -1 for not known), whether I snap my hand percussion (`snap`), and the Foley take my
## hand rang (`take`, -1 for not known).
func send_item_hit(item: StringName, velocity: int, song := -1.0, snap := false, take := -1) -> void:
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_item_hit.rpc_id(id, item, velocity, local_peer_id, song, snap, take)
	else:
		_item_hit_up.rpc_id(1, item, velocity, song, snap, take)


@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _item_hit_up(item: StringName, velocity: int, song: float, snap: bool, take: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	var hit := clean_item_hit(velocity, song, take)
	item_hit.emit(item, hit[0], from, hit[1], snap, hit[2])
	for id in _audience():
		if id != from:
			_item_hit.rpc_id(id, item, hit[0], from, hit[1], snap, hit[2])


@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _item_hit(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int) -> void:
	item_hit.emit(item, velocity, from, song, snap, take)


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
	if not _connected():
		return
	if role == Role.HOST:
		for id in _audience():
			_note.rpc_id(id, kind, pitch, velocity, local_peer_id, song, source)
	else:
		_note_up.rpc_id(1, kind, pitch, velocity, song, source)


@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _note_up(kind: int, pitch: int, velocity: int, song: float, source: StringName) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	if String(source).length() > NOTE_SOURCE_MAX:
		source = &""
	note_played.emit(kind, pitch, velocity, from, song, source)
	for id in _audience():
		if id != from:
			_note.rpc_id(id, kind, pitch, velocity, from, song, source)


@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _note(kind: int, pitch: int, velocity: int, from: int, song: float, source: StringName) -> void:
	note_played.emit(kind, pitch, velocity, from, song, source)


## A control on my keys (`kind` one of CONTROL_KINDS), to everyone else, as it moves, with the
## song position it went with and what moved it (`source`, as `send_note`'s). On a channel of its
## own (CONTROLS_CHANNEL), unreliable and ordered: GuestMidi sends one off rest again at least
## every GuestMidi.CONTROL_EVERY, so a lost one costs a few tens of milliseconds and never a note.
## Sent as it is asked: the host is the one that refuses and clamps (`_pass_control`).
func send_control(kind: int, value: int, song := -1.0, source := &"") -> void:
	if not _connected():
		return
	if role == Role.HOST:
		_pass_control(kind, value, song, source, local_peer_id)
	else:
		_control_up.rpc_id(1, kind, value, song, source)


@rpc("any_peer", "call_remote", "unreliable_ordered", CONTROLS_CHANNEL)
func _control_up(kind: int, value: int, song: float, source: StringName) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	_pass_control(kind, value, song, source, from)


## Host: `from`'s control, refused unless it is one of CONTROL_KINDS, its value clamped by kind,
## heard here (unless it is the host's own) and passed on to everyone else. Whether it passed.
func _pass_control(kind: int, value: int, song: float, source: StringName, from: int) -> bool:
	if not CONTROL_KINDS.has(kind):
		controls_refused += 1
		return false
	value = control_value(kind, value)
	if not is_finite(song) or song < 0.0:
		song = -1.0
	if String(source).length() > NOTE_SOURCE_MAX:
		source = &""
	if from != local_peer_id:
		control_played.emit(kind, value, from, song, source)
	for id in _audience():
		if id != from:
			_control.rpc_id(id, kind, value, from, song, source)
	return true


@rpc("authority", "call_remote", "unreliable_ordered", CONTROLS_CHANNEL)
func _control(kind: int, value: int, from: int, song: float, source: StringName) -> void:
	control_played.emit(kind, value, from, song, source)


## `value` kept in bounds for a control of `kind`: the pitch wheel -8192 to 8191, a controller 0
## to 127.
static func control_value(kind: int, value: int) -> int:
	if kind == DawKitClip.PITCH_BEND:
		return clampi(value, int(DawKitClip.BEND_MIN), int(DawKitClip.BEND_MAX))
	return clampi(value, 0, 127)


## Where a control of `kind` rests, as a keyboard sits untouched: the wheel at its centre, the mod
## wheel down, expression full. What every end puts it back to at a player's last note-off.
static func control_rest(kind: int) -> int:
	return 127 if kind == 11 else 0


## An event down `source`'s jack into player `to`'s instrument, at song position `song` (-1 for
## not known): up to the host, which checks it (`jack_refusal`) and passes it on to `to` alone.
## Reliable, on the keys' channel with the notes, because a lost note-off is a note that never
## stops. docs/spatial_loop.md slice 6.
func send_jack(to: int, source: StringName, kind: int, pitch: int, velocity: int, song := -1.0) -> void:
	if not _connected():
		return
	if role == Role.HOST:
		_pass_jack(to, source, kind, pitch, velocity, song, local_peer_id)
	else:
		_jack_up.rpc_id(1, to, source, kind, pitch, velocity, song)


@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _jack_up(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	_pass_jack(to, source, kind, pitch, velocity, song, from)


## Host: `from`'s jack event, checked, and passed on to `to` (or played here, when `to` is the
## host). Its numbers are kept in bounds by its kind before anyone plays them, and a CC that is
## not one of CONTROL_KINDS is refused. Whether it passed.
func _pass_jack(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float,
		from: int) -> bool:
	if kind < Jack.Kind.NOTE_ON or kind > Jack.Kind.CC or jack_refusal(to, source, from) != "" \
			or (kind == Jack.Kind.CC and not CONTROL_KINDS.has(pitch)):
		jacks_refused += 1
		return false
	# Clamped by kind: a note's pitch and velocity are MIDI's 0-127, a control's `pitch` is its
	# controller and its `velocity` its value, the bend's -8192 to 8191 (`control_value`).
	if kind == Jack.Kind.CC:
		velocity = control_value(pitch, velocity)
	else:
		pitch = clampi(pitch, 0, 127)
		velocity = clampi(velocity, 0, 127)
	if not is_finite(song) or song < 0.0:
		song = -1.0
	if to == local_peer_id:
		jack_played.emit(source, kind, pitch, velocity, from, song)
	else:
		_jack.rpc_id(to, source, kind, pitch, velocity, from, song)
	return true


## Host: why `from`'s event down `source`'s jack may not go into `to`, or empty if it may. Both
## are in the room, they are not the same player, and the room's patch and who plays the source
## say so (`jack_check`).
func jack_refusal(to: int, source: StringName, from: int) -> String:
	if not _is_member(to):
		return "player %d is not in the room" % to
	if not _is_member(from):
		return "player %d is not in the room" % from
	if to == from:
		return "a jack goes into a bandmate, not into yourself"
	if not Jack.valid_source(source):
		return "there is no such jack"
	if not jack_check.is_valid():
		return "there is no room here to say where it goes"
	return str(jack_check.call(to, source, from))


@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _jack(source: StringName, kind: int, pitch: int, velocity: int, from: int, song: float) -> void:
	jack_played.emit(source, kind, pitch, velocity, from, song)


## Host: words for `peer` alone, here if it is the host itself.
func tell(peer: int, text: String) -> void:
	if peer == local_peer_id:
		notice.emit(text)
	elif role == Role.HOST and _connected() and _is_member(peer):
		_told.rpc_id(peer, text)


## The round trip to `peer` in milliseconds, as the connection measures it: a host knows it for
## every guest, a guest only for the host. -1 where there is no such connection.
func round_trip_ms(peer: int) -> float:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or not _connected():
		return -1.0
	var packet := enet.get_peer(peer) if role == Role.HOST else enet.get_peer(1)
	if packet == null:
		return -1.0
	return packet.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)


## Roughly how long after `peer` plays a key its note reaches this machine: one way to the host,
## and one way on to here unless this is the host. A guest does not know the other guest's leg,
## and takes it to be its own.
func note_delay_ms(peer: int) -> float:
	if role == Role.HOST:
		var rtt := round_trip_ms(peer)
		return rtt * 0.5 if rtt >= 0.0 else -1.0
	var mine := round_trip_ms(1)
	if mine < 0.0:
		return -1.0
	return mine * 0.5 if peer == 1 else mine


static func room_ask_is_valid(verb: StringName, args: Array) -> bool:
	if not ROOM_VERBS.has(verb) or args.size() != ROOM_VERBS[verb].size():
		return false
	for i in args.size():
		if typeof(args[i]) != ROOM_VERBS[verb][i]:
			return false
	return true


@rpc("authority", "call_remote", "reliable")
func _receive_room(state: Dictionary) -> void:
	room = state
	room_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _room_asked(seq: int, verb: StringName, args: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	# Answered even when refused: the answer to an ask the host will not do is the room as it
	# is, and that is what takes the guest's prediction back.
	_room_acks[from] = maxi(int(_room_acks.get(from, 0)), seq)
	_room_sent = false
	if room_ask_is_valid(verb, args):
		# Whatever the host does to answer it is the asker's to undo, not folded into the host's
		# own open edit (DAW.on_behalf_of).
		DAW.on_behalf_of(from, func() -> void: room_asked.emit(verb, args, from))
	if not _room_sent:
		publish_room(room)


# --- the tour run --------------------------------------------------------------------------

## What a guest may ask of a run under way. Starting a run (breaking the case) and ending one
## are host-only and never asked: only the host can break the case, and only the host calls a
## run off. `draft_pick` is the one thing a guest originates.
const TOUR_VERBS := {&"draft_pick": [TYPE_INT]}


## Host: this is the tour run now, or `{}` for none under way. Sent to everyone in the room.
func publish_tour(state: Dictionary) -> void:
	if role != Role.HOST:
		return
	tour = state
	for id in _audience():
		_receive_tour.rpc_id(id, tour)


## Guest: ask the host to act on the run under way. Unlike `ask_room` there is nothing here for
## the guest to predict -- a draft pick is resolved once, by the host, and announced -- so this
## returns nothing; `Tour` reads the run back from `tour_changed` once the host has answered.
func ask_tour(verb: StringName, args: Array) -> void:
	if not tour_ask_is_valid(verb, args):
		return
	if is_authority():
		tour_asked.emit(verb, args, local_peer_id)
		return
	if not _connected():
		return
	_tour_asked.rpc_id(1, verb, args)


static func tour_ask_is_valid(verb: StringName, args: Array) -> bool:
	if not TOUR_VERBS.has(verb) or args.size() != TOUR_VERBS[verb].size():
		return false
	for i in args.size():
		if typeof(args[i]) != TOUR_VERBS[verb][i]:
			return false
	return true


@rpc("authority", "call_remote", "reliable")
func _receive_tour(state: Dictionary) -> void:
	tour = state
	tour_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _tour_asked(verb: StringName, args: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not _is_member(from):
		return
	if tour_ask_is_valid(verb, args):
		tour_asked.emit(verb, args, from)


# --- the rig roulette roll -----------------------------------------------------------------

## Host: this is the roll now. Sent to everyone in the room, and heard here too.
func publish_roll(state: Dictionary) -> void:
	if not is_authority():
		return
	roll = state
	roll_changed.emit()
	for id in _audience():
		_receive_roll.rpc_id(id, roll)


@rpc("authority", "call_remote", "reliable")
func _receive_roll(state: Dictionary) -> void:
	roll = state
	roll_changed.emit()


## Host: this is what the next roll is set to. Sent to everyone in the room, and heard here too.
func publish_roll_setup(state: Dictionary) -> void:
	if not is_authority():
		return
	roll_setup = state
	roll_setup_changed.emit()
	for id in _audience():
		_receive_roll_setup.rpc_id(id, roll_setup)


@rpc("authority", "call_remote", "reliable")
func _receive_roll_setup(state: Dictionary) -> void:
	roll_setup = state
	roll_setup_changed.emit()


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


## The host opened a different project: every guest gets it whole, the same way a guest that
## has just joined does. Deltas would only describe what changed, and everything did.
func _on_project_replaced() -> void:
	for id in _audience():
		_send_snapshot_to(id)


## The host's tracks were renumbered. Every track chosen for a take, here and on every guest, and
## every take on its way in, follows its track; one whose track is gone is refused when it lands.
func _on_tracks_renumbered(map: Dictionary) -> void:
	if role == Role.GUEST:
		return
	_follow_renumber(map)
	for entry in _incoming_takes.values():
		for part in entry["parts"]:
			part["track"] = int(map.get(part["track"], -1))
	if role == Role.HOST:
		_tracks_renumbered.rpc(map)


@rpc("authority", "call_remote", "reliable")
func _tracks_renumbered(map: Dictionary) -> void:
	var clean := {}
	for old in map:
		if typeof(old) == TYPE_INT and typeof(map[old]) == TYPE_INT:
			clean[old] = map[old]
	_follow_renumber(clean)


func _follow_renumber(map: Dictionary) -> void:
	for recorder in [guest_audio, guest_midi, host_audio]:
		if recorder != null:
			recorder.follow_renumber(map)


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


## Called when this participant's hand takes a thing out of somebody else's: handed over, not
## refused. Only for what the host says can be (`takeable`); anything else is claimed as usual.
func take_hold(key: String) -> void:
	if key.is_empty() or not _connected():
		return
	if role == Role.HOST:
		_hand_over(local_peer_id, key)
	else:
		_take.rpc_id(1, key)


## Who has their hand on this control, or 0 for nobody.
func holder_of(key: String) -> int:
	return holds.get(key, 0)


@rpc("any_peer", "call_remote", "reliable")
func _claim(key: String) -> void:
	if role == Role.HOST and _is_member(multiplayer.get_remote_sender_id()):
		_grant(multiplayer.get_remote_sender_id(), key)


@rpc("any_peer", "call_remote", "reliable")
func _take(key: String) -> void:
	if role == Role.HOST and _is_member(multiplayer.get_remote_sender_id()):
		_hand_over(multiplayer.get_remote_sender_id(), key)


@rpc("any_peer", "call_remote", "reliable")
func _release_remote(key: String) -> void:
	if role == Role.HOST and _is_member(multiplayer.get_remote_sender_id()):
		_release(multiplayer.get_remote_sender_id(), key)


## The arbitration, in full: whoever the host heard from first. Not the lower peer id, not the
## later grab -- a rule nobody in the room can see is a rule that feels like the desk is broken.
## "Sam already had it" is a rule everyone can see, because Sam's hand is on it. The one other
## refusal is `holdable`'s: a thing kept for somebody else is refused the same way, naming them.
func _grant(peer_id: int, key: String) -> void:
	var holder: int = holds.get(key, 0)
	if holder == 0 and holdable.is_valid():
		var kept_for := int(holdable.call(key, peer_id))
		if kept_for != 0 and kept_for != peer_id:
			holder = kept_for
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


## A thing in one hand taken by another: the hold moves, and the hand it moved from lets go when
## it hears. Only what `takeable` says -- an item; a fader somebody has is still theirs.
func _hand_over(peer_id: int, key: String) -> void:
	if not takeable.is_valid() or not takeable.call(key) or holds.get(key, 0) == peer_id:
		_grant(peer_id, key)
		return
	if holdable.is_valid():
		var kept_for := int(holdable.call(key, peer_id))
		if kept_for != 0 and kept_for != peer_id:
			_grant(peer_id, key)
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
		"app": "dawlings",
		"v": 1,
		"name": local_name,
		"port": port,
		"people": participants.size(),
		"locked": not code.is_empty(),
		"tracks": DAW.state.project_track_count if DAW.state != null else 0,
	}
