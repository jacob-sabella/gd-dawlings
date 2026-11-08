extends SessionBase

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


var role: int = Role.SOLO
## On a guest, the host's track spectra as last heard (Spectra): track -> its bands in dB; and when
## (msec, -1 for never). Empty on a host or alone, which measure their own.
var spectra: Dictionary = {}
## Host: the track each guest's keys play into, live (`send_play_track`): peer id -> track. Read
## by GuestPlay, which sounds their notes on that track's instrument plugin.
var play_tracks: Dictionary = {}
## Host: what guests have offered and the host has not answered, {peer: {kind: label}}; and what
## the host has allowed, {peer: {kind: {"track": int}}}.
var share_offers: Dictionary = {}
var shares: Dictionary = {}
## Guest: where each offer stands, {kind: "offered" | "allowed" | "declined"}, and the track the
## host put the audio on (0 for none).
var my_shares: Dictionary = {}
var my_share_track := 0
## Host: how many live packets have been refused, for the probe and the suite.
var live_refused := 0
var spectra_heard_msec := -1
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
## Online by a code instead of an address, through a noray server: the host's registration there,
## or a guest's way in. See core/session/noray_link.gd and docs/multiplayer.md.
var online := NorayLink.new()
## The mix's own way through noray, beside the session's (MixFeed's socket is not the session's):
## the host's registration of it, or a guest's punch or relay to it. See `_mix_by_code`.
var mix_online := NorayLink.new()
## How a guest by code hears the mix: "direct" (its socket punched through), "relayed" (through
## noray's relay), "carried" (over the session's ENet, the last resort), "" otherwise.
var mix_route := ""
var _mix_phase := ""
var _mix_clock := 0.0
## The host's mix code, given with the ticket.
var _mix_code := ""
var _mix_punching: Array = []
## How this guest reached its host: "" by address (or on the LAN), "direct" when noray punched
## through both routers, "relayed" when its server passes the traffic on.
var link_kind := ""
## A guest's way in by a code, while it is under way: "finding", "punching" or "relaying"; "" else.
var link_phase := ""
## The code this guest joined by, as noray has it.
var joined_code := ""
## Straight to noray's relay, without trying the punch: --relay, and the probe's relayed run.
var force_relay := false
## LINK_SECONDS, as a variable for the suite.
var link_seconds := LINK_SECONDS
## The noray server for this run (--noray-server); "" for the kept one (NorayLink.server_setting).
var online_server := ""
## Host: internet addresses noray said a guest is coming from, punched toward for a while:
## [ip, port, seconds left].
var _punching: Array = []
var _punch_clock := 0.0
var _link_clock := 0.0
var _link_door := ""
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
## The host's user mods offered to guests, and a guest's inbox of offers (`ModSend`).
var mod_share: ModSend = null
## This player's own sound into their Discord voice channel. See core/audio/discord_feed.gd.
var discord: DiscordFeed = null
var rooms_published := 0
## Host: how many controls have been refused (a controller not in CONTROL_KINDS), for the probe
## and the suite.
var controls_refused := 0
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
		admitting._apply_listening()
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
## "jacks": {source: sink}, where each instrument's output jack goes (Jacks),
## "weather": whether the venue's weather's switch is on LISTEN (Weather),
## "rack": the modular room's rack, {patch, track} (RackPatch),
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


## Joining and hosting online by a code, the punches and the mix's own link.
var linking := SessionLink.new(self)
## Who is here: connections, hello, admission and the roster.
var admitting := SessionRoster.new(self)
## A guest's intents, saves, listens, arranges and placed takes.
var guest_writes := SessionIntents.new(self)
## A guest's recording on its way to the host.
var take_work := SessionTakes.new(self)
## The room, made items, the tour run and the roulette roll.
var room_work := SessionRoom.new(self)
## Things pushed, carried, flown, used and hit.
var movers := SessionMotion.new(self)
## A guest's own devices offered to the host.
var sharing := SessionShares.new(self)
## Notes, controls and jack events as they are played.
var play_work := SessionPlay.new(self)
## Spectra, state replication, presence and holds.
var replicating := SessionState.new(self)
## Starting solo, hosting, joining, leaving and the autoload's frame.
var life := SessionLife.new(self)

func _init() -> void:
	# First thing any part of the app does, before anything reads a saved file: this is the
	# first autoload. See DataHome.
	DataHome.migrate()

func _ready() -> void: life.ready()
## Quitting while hosting is ending the session, and says so. Blocking, briefly, because there is no next frame to finish the goodbye in: the packet is serviced out by hand until it has had time to land, and only then does the socket close behind it (`SessionLife._exit_tree`).
func _exit_tree() -> void: life.exit_tree()

func _process(delta: float) -> void: life.process(delta)
## Start a solo session: no network, this process also owns the Reaper link (`SessionLife.start_solo`).
func start_solo() -> void: life.start_solo()

## `SessionLife.host`.
func host(at_port: int = DEFAULT_PORT) -> bool: return life.host(at_port)
## `SessionLife.join`.
func join(address: String, at_port: int = DEFAULT_PORT, with_code: String = "", local_port: int = 0) -> bool:
	return life.join(address, at_port, with_code, local_port)

## Ask the router to forward this session's ports here (UDP: the session's own, and the mix's audio beside it), so people outside the room can join at the router's public address. The host only, and only when asked: it changes the host's network. `internet.changed` reports (`SessionLink.open_to_internet`).
func open_to_internet() -> void: linking.open_to_internet()
## `SessionLink.close_to_internet`.
func close_to_internet() -> void: linking.close_to_internet()


# --- online, by a code --------------------------------------------------------------------

## Host online: registered with a noray server, which hands out a short code (`online.oid`) that finds this session from anywhere, no router asked. Hosts first if on your own. `online.changed` reports; a failure is in `online.why_not`. The session code at the door still applies (`SessionLink.host_online`).
func host_online(at_port: int = DEFAULT_PORT, server: String = "") -> bool:
	return linking.host_online(at_port, server)

## Off noray: the code stops working. Guests already in stay in (`SessionLink.go_offline`).
func go_offline() -> void: linking.go_offline()
## Join by the code a host read out: noray finds its internet address, both sides punch, and if no path opens in LINK_SECONDS, noray's relay carries it instead. `with_code` is the session code at the door, if the host asked for one. Reports through `link_changed` and `notice` (`SessionLink.join_by_code`).
func join_by_code(typed: String, with_code: String = "", server: String = "") -> bool:
	return linking.join_by_code(typed, with_code, server)

## Where a host's guest came in from, for the roster: "relayed" through noray's server, "direct" when noray punched it through, "" by address (`SessionLink.route_of`).
func route_of(peer_id: int) -> String: return linking.route_of(peer_id)


## Every address noray announced, for route_of: the punching rows only last PUNCH_SECONDS.
var _punched: Array = []


# --- the mix by a code --------------------------------------------------------------------

## A guest by code hears the mix on its own socket, as every guest does, at an address noray gives: its mix socket registered and punched toward the host's (the host registered its mix socket too, `host_online`), or the relay if the session itself needed one or the punch is not heard in MIX_LINK_SECONDS. Neither: carried over the session's ENet (MixFeed.carried) (`SessionLink._mix_by_code`).
func _mix_by_code() -> void: linking._mix_by_code()
## Back to being on your own. A host says goodbye first; a guest gets its own mix back (`SessionLife.leave`).
func leave() -> void: life.leave()

## `SessionLife.is_authority`.
func is_authority() -> bool: return life.is_authority()
## Up and talking. A guest is a guest from the moment it dials, but for the second or so before the host answers, anything sent is an error rather than a packet (`SessionLife._connected`).
func _connected() -> bool: return life._connected()

## `SessionLife.is_networked`.
func is_networked() -> bool: return life.is_networked()
## `SessionLife.local_participant`.
func local_participant() -> Participant: return life.local_participant()

## `SessionLife.name_of`.
func name_of(peer_id: int) -> String: return life.name_of(peer_id)
## Rename yourself. Before joining it is just a setting; once in a session the host hears it and tells everyone, because a name on an avatar that its owner has changed is a lie (`SessionLife.set_local_name`).
func set_local_name(new_name: String) -> void: life.set_local_name(new_name)

## Dress my ghost. Kept for next time, and told to the session the same way a rename is (`SessionLife.set_look`).
func set_look(look: Dictionary) -> void: life.set_look(look)

func _register(peer_id: int, name_hint: String, colour_index: int) -> Participant:
	return admitting._register(peer_id, name_hint, colour_index)

## The lowest colour nobody is wearing. Join order alone would hand the eighth arrival the colour of someone still in the room the moment an earlier guest left and came back (`SessionRoster._free_colour`).
func _free_colour() -> int: return admitting._free_colour()


# --- arriving and leaving -----------------------------------------------------------------


func _on_peer_disconnected(peer_id: int) -> void: admitting._on_peer_disconnected(peer_id)

## A guest introducing itself, and again whenever it renames. The first one is also the knock (`SessionRoster._hello`).
@rpc("any_peer", "call_remote", "reliable")
func _hello(display_name: String, medium: int, offered_code: String = "", look: Dictionary = {}) -> void:
	admitting._hello(display_name, medium, offered_code, look)

## Why a knock with this code is not let in, or "" if it is. Compared case- and space-blind: a code is read aloud across a room, and "ab 12" typed for "AB12" is the same code (`SessionRoster.admission_refusal`).
func admission_refusal(offered: String) -> String: return admitting.admission_refusal(offered)

## The host's leave to listen. Sent over the reliable, admitted channel; the audio socket answers nothing that does not carry one (`SessionRoster._give_audio_ticket`).
@rpc("authority", "call_remote", "reliable")
func _give_audio_ticket(ticket: int, audio_port: int, mix_code: String = "") -> void:
	admitting._give_audio_ticket(ticket, audio_port, mix_code)

@rpc("authority", "call_remote", "reliable")
func _turned_away(reason: String) -> void: admitting._turned_away(reason)
## Whether a message claiming to come from `peer_id` is from someone in the room (`SessionRoster._is_member`).
func _is_member(peer_id: int) -> bool: return admitting._is_member(peer_id)

@rpc("authority", "call_remote", "reliable")
func _goodbye() -> void: admitting._goodbye()

func _roster_rows() -> Array: return admitting._roster_rows()

## The host's word on who is here. Applied as a whole -- arrivals, departures, renames -- and heads and pointers carried across, so a rename does not snap someone's avatar to the origin (`SessionRoster._receive_roster`).
@rpc("authority", "call_remote", "reliable")
func _receive_roster(rows: Array) -> void: admitting._receive_roster(rows)

## `SessionRoster.apply_roster`.
func apply_roster(rows: Array) -> void: admitting.apply_roster(rows)


# --- intents ------------------------------------------------------------------------------

## For the suite: while true, every intent a guest sends is also kept in `kept_intents` as
## [verb, args], whether or not there is a host to send it to, so what a guest asks can be counted.
var keep_intents := false
var kept_intents: Array = []

## A guest's write, forwarded to the host (`SessionIntents.send_intent`).
func send_intent(verb: StringName, args: Array) -> void: guest_writes.send_intent(verb, args)

@rpc("any_peer", "call_remote", "reliable")
func _receive_intent(verb: StringName, args: Array) -> void: guest_writes._receive_intent(verb, args)

## Saves the open project where it is, and tells the whole room how it went: a save is the one thing everyone in a session wants to know happened, whoever pressed it. `who` is the name of whoever asked, which on the host is the host (`SessionIntents.save_project_for`).
func save_project_for(who: String) -> PackedStringArray: return guest_writes.save_project_for(who)

## A notice for this participant and every other one (`SessionIntents.tell_room`).
func tell_room(text: String) -> void: guest_writes.tell_room(text)

## Listen from my spot (docs/spatial_loop.md part two, slice 35): the shared transport sought to `seconds` and played -- `seek` and `transport_play`, intents from a guest like any other -- and everyone told who asked and from where, `Ada: listen from 1:23 (CHORUS)`: the song jumping under the whole band's hands is not a thing to do unannounced. A guest's words are the host's to say, from its own markers, after the intents it has already had (`SessionIntents.listen_from`).
func listen_from(seconds: float) -> void: guest_writes.listen_from(seconds)

@rpc("any_peer", "call_remote", "reliable")
func _listen_asked(seconds: float) -> void: guest_writes._listen_asked(seconds)

## What the room is told of a listen from `seconds`: who, the clock there, and the section it is in (Harmony.section_at), upper case, when there is one (`SessionIntents.listen_words`).
static func listen_words(who: String, markers: Dictionary, seconds: float) -> String:
	return SessionIntents.listen_words(who, markers, seconds)

## A guest's rearrangement of the song's sections (DAW.arrange_sections), made as hers, and the room told: the whole song moving under everyone's hands is not a change to make unannounced. A refusal is told to her, as she could not see it any other way (`SessionIntents._arrange_for`).
func _arrange_for(from: int, args: Array) -> void: guest_writes._arrange_for(from, args)

## A guest's take, placed, and both sides told how it went: the guest because it cannot see a refusal any other way, the host because a new item appearing on its timeline unannounced is a surprise in the middle of a session (`SessionIntents._place_take`).
func _place_take(from: int, args: Array) -> void: guest_writes._place_take(from, args)


# --- a guest's recording --------------------------------------------------------------------
#
# Not an intent: an intent is a verb with a few arguments, and a take is minutes of sound. The
# guest streams it while it records (GuestAudio), the host writes it to a WAV as it arrives
# (AudioTake), and when it ends the host places the file with its own DAW.insert_audio_take. A
# guest never names a file; the host does.

#
# The host's own recording, on a DAW that does not record its own inputs (the built-in engine),
# comes through the same three calls and is kept the same way, from the host's own id.

## `plan`, the host's own only: [track, channel] for each track the take goes onto, the channel 0 for both, 1 or 2 for that input channel alone (GuestAudio.take_plan). Empty is `track`, both (`SessionTakes.send_audio_begin`).
func send_audio_begin(take_id: int, track: int, start: float, take_name: String, plan: Array = []) -> void:
	take_work.send_audio_begin(take_id, track, start, take_name, plan)

## `SessionTakes.send_audio_chunk`.
func send_audio_chunk(take_id: int, pcm: PackedByteArray) -> void: take_work.send_audio_chunk(take_id, pcm)

## The host's own take, as each input channel its tracks want: {channel: pcm} (see _take_chunk) (`SessionTakes.send_audio_channels`).
func send_audio_channels(take_id: int, by_channel: Dictionary) -> void:
	take_work.send_audio_channels(take_id, by_channel)

## `SessionTakes.send_audio_end`.
func send_audio_end(take_id: int) -> void: take_work.send_audio_end(take_id)

@rpc("any_peer", "call_remote", "reliable", AUDIO_TAKE_CHANNEL)
func _audio_begin(take_id: int, track: int, start: float, take_name: String) -> void:
	take_work._audio_begin(take_id, track, start, take_name)

@rpc("any_peer", "call_remote", "reliable", AUDIO_TAKE_CHANNEL)
func _audio_chunk(take_id: int, pcm: PackedByteArray) -> void: take_work._audio_chunk(take_id, pcm)

@rpc("any_peer", "call_remote", "reliable", AUDIO_TAKE_CHANNEL)
func _audio_end(take_id: int) -> void: take_work._audio_end(take_id)

## Where the host's own song is in the host's ears: the playhead, less what the output still holds. What the host's recording is timed against (`host_audio`), as a guest's is against the stream it hears. {seconds, playing, recording, valid} (`SessionTakes.host_heard`).
func host_heard() -> Dictionary: return take_work.host_heard()

## Words from the host for this guest alone (`SessionTakes._told`).
@rpc("authority", "call_remote", "reliable")
func _told(text: String) -> void: take_work._told(text)


# --- the room -----------------------------------------------------------------------------


## Host: made item `id`'s row (`made`) to everyone, once, on its own reliable message: before the room that will name it, on the same channel, so it is there when the room arrives (`SessionRoom.publish_made`).
func publish_made(id: StringName) -> void: room_work.publish_made(id)

## Host: made item `id` is gone (the BIN): its row with it, everywhere (`SessionRoom.drop_made`).
func drop_made(id: StringName) -> void: room_work.drop_made(id)

## A made item's row, from the host: kept if it is one, within what a room may carry (ItemRoom.MADE_BYTES, MADE_MOST), and said (`SessionRoom._made`).
@rpc("authority", "call_remote", "reliable")
func _made(id: StringName, kind: StringName, maker: int, bytes: PackedByteArray) -> void:
	room_work._made(id, kind, maker, bytes)

@rpc("authority", "call_remote", "reliable")
func _unmade(id: StringName) -> void: room_work._unmade(id)

## Host: `key` (an item's network key) is in `peer`'s hand now, whoever had it: a give, or a made item minted for the guest who asked (docs/spatial_loop.md part two, slice 23). Their hand takes it when they hear (the studio's `_take_given`); one that had it lets go (Presence) (`SessionRoom.hand_to`).
func hand_to(peer: int, key: String) -> void: room_work.hand_to(peer, key)

## Host: this is the room now. Sent to everyone in it, and to each guest as they come in (`SessionRoom.publish_room`).
func publish_room(state: Dictionary) -> void: room_work.publish_room(state)

## Guest: ask the host to change the room, and get back the ask's number -- the guest goes ahead and does it, and the number is how it learns the host has answered. 0 when nothing was sent: the host's own asks go straight to its studio, and there is nobody to predict for (`SessionRoom.ask_room`).
func ask_room(verb: StringName, args: Array) -> int: return room_work.ask_room(verb, args)

## Where something being pushed is right now, to everyone else. Often and unreliably, like a head: a lost one is overtaken by the next (`SessionMotion.send_motion`).
func send_motion(piece: StringName, x: float, z: float, heading: float) -> void:
	movers.send_motion(piece, x, z, heading)

@rpc("any_peer", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _motion_up(piece: StringName, x: float, z: float, heading: float) -> void:
	movers._motion_up(piece, x, z, heading)

@rpc("authority", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _motion(piece: StringName, x: float, z: float, heading: float, from: int) -> void:
	movers._motion(piece, x, z, heading, from)

## Where the thing in my hand is now, relative to my head, to everyone else. As often as a head (`SessionMotion.send_carry`).
func send_carry(item: StringName, local: Transform3D) -> void: movers.send_carry(item, local)

@rpc("any_peer", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _carry_up(item: StringName, local: Transform3D) -> void: movers._carry_up(item, local)

@rpc("authority", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _carry(item: StringName, local: Transform3D, from: int) -> void: movers._carry(item, local, from)

## Where the thing I am flying is, in the session's frame, and how it flies, to everyone else (`SessionMotion.send_flier`).
func send_flier(item: StringName, pose: Transform3D, mode: int) -> void: movers.send_flier(item, pose, mode)

@rpc("any_peer", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _flier_up(item: StringName, pose: Transform3D, mode: int) -> void: movers._flier_up(item, pose, mode)

@rpc("authority", "call_remote", "unreliable_ordered", MOTION_CHANNEL)
func _flier(item: StringName, pose: Transform3D, mode: int, from: int) -> void:
	movers._flier(item, pose, mode, from)

## The thing in my hand, used, for everyone else to hear and see, with the Foley take my hand rang (`take`, Item.use_take; -1 for not known) (`SessionMotion.send_item_use`).
func send_item_use(item: StringName, down: bool, take := -1) -> void: movers.send_item_use(item, down, take)

@rpc("any_peer", "call_remote", "reliable")
func _item_use_up(item: StringName, down: bool, take: int) -> void: movers._item_use_up(item, down, take)

@rpc("authority", "call_remote", "reliable")
func _item_use(item: StringName, down: bool, from: int, take: int) -> void:
	movers._item_use(item, down, from, take)

## A guest's Foley take as the host passes it on: one of Foley's (0 to 2^24), or -1 for not known (`SessionMotion.clean_take`).
static func clean_take(take: int) -> int: return SessionMotion.clean_take(take)

## A shake of the instrument in my hand, or a strike on one that stands still, to everyone else, with the song position it was played to (`song`, -1 for not known), whether I snap my hand percussion (`snap`), the Foley take my hand rang (`take`, -1 for not known), and where on a fixed one I struck it (`zone`) (`SessionMotion.send_item_hit`).
func send_item_hit(item: StringName, velocity: int, song := -1.0, snap := false, take := -1, zone := &"") -> void:
	movers.send_item_hit(item, velocity, song, snap, take, zone)

@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _item_hit_up(item: StringName, velocity: int, song: float, snap: bool, take: int, zone: StringName) -> void:
	movers._item_hit_up(item, velocity, song, snap, take, zone)

@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _item_hit(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName) -> void:
	movers._item_hit(item, velocity, from, song, snap, take, zone)


## A guest's zone as the host passes it on: a short word of lower-case letters, digits and underscores, or &"" for anything else. Whether the instrument has it is its own (InstrumentItem.has_zone) (`SessionMotion.clean_zone`).
static func clean_zone(zone: StringName) -> StringName: return SessionMotion.clean_zone(zone)

## A guest's hit as the host passes it on: [velocity 1 to 127, song (-1 for anything not a song position), take (-1 for anything not one of Foley's takes)] (`SessionMotion.clean_item_hit`).
static func clean_item_hit(velocity: int, song: float, take: int) -> Array:
	return SessionMotion.clean_item_hit(velocity, song, take)

## A key or the pedal on my keys, to everyone else, as it is played. Notes are a few bytes and come in tens a second at most, so they go to everyone rather than being asked for; whoever is patched into my keys plays them. `source`: what played it (GuestMidi.instruments) (`SessionMotion.send_note`).
func send_note(kind: int, pitch: int, velocity: int, song := -1.0, source := &"") -> void:
	movers.send_note(kind, pitch, velocity, song, source)

## The track my keys play into, told to the host (0 for none), so it sounds my notes on that track's instrument plugin as I play them. A guest's; on a host there is no one to tell (`SessionMotion.send_play_track`).
func send_play_track(track: int) -> void: movers.send_play_track(track)

@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _play_track_up(track: int) -> void: movers._play_track_up(track)


## ---- A guest's own devices, offered to the host --------------------------------------------
## The guest offers one kind (`audio` or `midi`), the host allows or declines it, and either may
## end it at any time. Until it is allowed the host ignores what a guest sends of that kind: no
## live audio is accepted, and keys are not sounded on the host's instruments (GuestPlay).

## Guest: offer a device to the host. `label` is what the host is shown ("Scarlett 2i2") (`SessionShares.offer_share`).
func offer_share(kind: StringName, label := "") -> void: sharing.offer_share(kind, label)

## Guest: take an offer back, or stop what the host allowed (`SessionShares.withdraw_share`).
func withdraw_share(kind: StringName) -> void: sharing.withdraw_share(kind)

@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _share_offer(kind: StringName, label: String) -> void: sharing._share_offer(kind, label)

@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _share_withdraw(kind: StringName) -> void: sharing._share_withdraw(kind)

## Host: allow a guest's offered device (on `track` for audio), or decline it, or end it (`SessionShares.answer_share`).
func answer_share(peer: int, kind: StringName, allow: bool, track := 0) -> void:
	sharing.answer_share(peer, kind, allow, track)

## Host: whether `peer` may use their `kind` of device here (`SessionShares.share_allowed`).
func share_allowed(peer: int, kind: StringName) -> bool: return sharing.share_allowed(peer, kind)

## Host: the track `peer`'s audio was put on, 0 for none (`SessionShares.share_track`).
func share_track(peer: int, kind: StringName = &"audio") -> int: return sharing.share_track(peer, kind)

@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _share_answer(kind: StringName, allow: bool, track: int) -> void:
	sharing._share_answer(kind, allow, track)

## Guest: a packet of live audio to the host, mono 16-bit at 48 kHz (AudioTake.encode). Sent only while the host has allowed it (`SessionShares.send_live_audio`).
func send_live_audio(pcm: PackedByteArray) -> void: sharing.send_live_audio(pcm)

@rpc("any_peer", "call_remote", "unreliable_ordered", LIVE_CHANNEL)
func _live_up(pcm: PackedByteArray) -> void: sharing._live_up(pcm)

@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _note_up(kind: int, pitch: int, velocity: int, song: float, source: StringName) -> void:
	play_work._note_up(kind, pitch, velocity, song, source)

@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _note(kind: int, pitch: int, velocity: int, from: int, song: float, source: StringName) -> void:
	play_work._note(kind, pitch, velocity, from, song, source)

## A control on my keys (`kind` one of CONTROL_KINDS), to everyone else, as it moves, with the song position it went with and what moved it (`source`, as `send_note`'s). On a channel of its own (CONTROLS_CHANNEL), unreliable and ordered: GuestMidi sends one off rest again at least every GuestMidi.CONTROL_EVERY, so a lost one costs a few tens of milliseconds and never a note. Sent as it is asked: the host is the one that refuses and clamps (`_pass_control`) (`SessionPlay.send_control`).
func send_control(kind: int, value: int, song := -1.0, source := &"") -> void:
	play_work.send_control(kind, value, song, source)

@rpc("any_peer", "call_remote", "unreliable_ordered", CONTROLS_CHANNEL)
func _control_up(kind: int, value: int, song: float, source: StringName) -> void:
	play_work._control_up(kind, value, song, source)

## Host: `from`'s control, refused unless it is one of CONTROL_KINDS, its value clamped by kind, heard here (unless it is the host's own) and passed on to everyone else. Whether it passed (`SessionPlay._pass_control`).
func _pass_control(kind: int, value: int, song: float, source: StringName, from: int) -> bool:
	return play_work._pass_control(kind, value, song, source, from)

@rpc("authority", "call_remote", "unreliable_ordered", CONTROLS_CHANNEL)
func _control(kind: int, value: int, from: int, song: float, source: StringName) -> void:
	play_work._control(kind, value, from, song, source)

## `value` kept in bounds for a control of `kind`: the pitch wheel -8192 to 8191, a controller 0 to 127 (`SessionPlay.control_value`).
static func control_value(kind: int, value: int) -> int: return SessionPlay.control_value(kind, value)

## Where a control of `kind` rests, as a keyboard sits untouched: the wheel at its centre, the mod wheel down, expression full. What every end puts it back to at a player's last note-off (`SessionPlay.control_rest`).
static func control_rest(kind: int) -> int: return SessionPlay.control_rest(kind)

## An event down `source`'s jack into player `to`'s instrument, at song position `song` (-1 for not known): up to the host, which checks it (`jack_refusal`) and passes it on to `to` alone. Reliable, on the keys' channel with the notes, because a lost note-off is a note that never stops. docs/spatial_loop.md slice 6 (`SessionPlay.send_jack`).
func send_jack(to: int, source: StringName, kind: int, pitch: int, velocity: int, song := -1.0) -> void:
	play_work.send_jack(to, source, kind, pitch, velocity, song)

@rpc("any_peer", "call_remote", "reliable", KEYS_CHANNEL)
func _jack_up(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float) -> void:
	play_work._jack_up(to, source, kind, pitch, velocity, song)

## Host: `from`'s jack event, checked, and passed on to `to` (or played here, when `to` is the host). Its numbers are kept in bounds by its kind before anyone plays them, and a CC that is not one of CONTROL_KINDS is refused. A CHORD goes only down a chord hand's jack and nothing else does (part two, slice 33), and one naming no quality there is is refused. Whether it passed (`SessionPlay._pass_jack`).
func _pass_jack(to: int, source: StringName, kind: int, pitch: int, velocity: int, song: float, from: int) -> bool:
	return play_work._pass_jack(to, source, kind, pitch, velocity, song, from)

## Host: why `from`'s event down `source`'s jack may not go into `to`, or empty if it may. Both are in the room, they are not the same player, and the room's patch and who plays the source say so (`jack_check`) (`SessionPlay.jack_refusal`).
func jack_refusal(to: int, source: StringName, from: int) -> String:
	return play_work.jack_refusal(to, source, from)

@rpc("authority", "call_remote", "reliable", KEYS_CHANNEL)
func _jack(source: StringName, kind: int, pitch: int, velocity: int, from: int, song: float) -> void:
	play_work._jack(source, kind, pitch, velocity, from, song)

## Host: words for `peer` alone, here if it is the host itself (`SessionRoom.tell`).
func tell(peer: int, text: String) -> void: room_work.tell(peer, text)

## Roughly how long after `peer` plays a key its note reaches this machine: one way to the host, and one way on to here unless this is the host. A guest does not know the other guest's leg, and takes it to be its own (`SessionRoom.note_delay_ms`).
func note_delay_ms(peer: int) -> float: return room_work.note_delay_ms(peer)

## `SessionRoom.room_ask_is_valid`.
static func room_ask_is_valid(verb: StringName, args: Array) -> bool:
	return SessionRoom.room_ask_is_valid(verb, args)

@rpc("authority", "call_remote", "reliable")
func _receive_room(state: Dictionary) -> void: room_work._receive_room(state)

@rpc("any_peer", "call_remote", "reliable")
func _room_asked(seq: int, verb: StringName, args: Array) -> void: room_work._room_asked(seq, verb, args)


# --- the tour run --------------------------------------------------------------------------


## Host: this is the tour run now, or `{}` for none under way. Sent to everyone in the room (`SessionRoom.publish_tour`).
func publish_tour(state: Dictionary) -> void: room_work.publish_tour(state)

## Guest: ask the host to act on the run under way. Unlike `ask_room` there is nothing here for the guest to predict -- a draft pick is resolved once, by the host, and announced -- so this returns nothing; `Tour` reads the run back from `tour_changed` once the host has answered (`SessionRoom.ask_tour`).
func ask_tour(verb: StringName, args: Array) -> void: room_work.ask_tour(verb, args)

## `SessionRoom.tour_ask_is_valid`.
static func tour_ask_is_valid(verb: StringName, args: Array) -> bool:
	return SessionRoom.tour_ask_is_valid(verb, args)

@rpc("authority", "call_remote", "reliable")
func _receive_tour(state: Dictionary) -> void: room_work._receive_tour(state)

@rpc("any_peer", "call_remote", "reliable")
func _tour_asked(verb: StringName, args: Array) -> void: room_work._tour_asked(verb, args)


# --- the rig roulette roll -----------------------------------------------------------------

## Host: this is the roll now. Sent to everyone in the room, and heard here too (`SessionRoom.publish_roll`).
func publish_roll(state: Dictionary) -> void: room_work.publish_roll(state)

@rpc("authority", "call_remote", "reliable")
func _receive_roll(state: Dictionary) -> void: room_work._receive_roll(state)

## Host: this is what the next roll is set to. Sent to everyone in the room, and heard here too (`SessionRoom.publish_roll_setup`).
func publish_roll_setup(state: Dictionary) -> void: room_work.publish_roll_setup(state)

@rpc("authority", "call_remote", "reliable")
func _receive_roll_setup(state: Dictionary) -> void: room_work._receive_roll_setup(state)


# --- spectra (the EQ wall, docs/spatial_loop.md part two, slice 36) ------------------------

## The host's track spectra (track -> Spectra.BANDS levels in dB) to every guest, as Spectra.pack parcels them: a byte a band per track. The host only; Spectra sends them SEND_HZ times a second (`SessionState.send_spectra`).
func send_spectra(by_track: Dictionary) -> void: replicating.send_spectra(by_track)

@rpc("authority", "call_remote", "unreliable_ordered", SPECTRA_CHANNEL)
func _spectra_from_host(parcel: PackedByteArray) -> void: replicating._spectra_from_host(parcel)

## A parcel of the host's spectra, taken in: each track in it replaces what was heard for it. A parcel that is not whole is dropped (`SessionState.hear_spectra`).
func hear_spectra(parcel: PackedByteArray) -> void: replicating.hear_spectra(parcel)


# --- state replication --------------------------------------------------------------------

## Host -> guests, once per replication tick (`SessionState.broadcast_state`).
func broadcast_state(durable: Dictionary, volatile: Dictionary) -> void:
	replicating.broadcast_state(durable, volatile)


static func _parcels(batch: Array) -> Array: return SessionState._parcels(batch)

@rpc("authority", "call_remote", "reliable")
func _receive_state_durable(batch: Array) -> void: replicating._receive_state_durable(batch)

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state_volatile(batch: Array) -> void: replicating._receive_state_volatile(batch)

@rpc("authority", "call_remote", "reliable")
func _tracks_renumbered(map: Dictionary) -> void: replicating._tracks_renumbered(map)


# --- presence -----------------------------------------------------------------------------

## Where this participant's head is and what they are pointing at, a few dozen times a second (`SessionState.publish_presence`).
func publish_presence(head_in_session_space: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	replicating.publish_presence(head_in_session_space, pointing_at, pointing_local)

## A guest's pose, to the host, which keeps it and passes it on to everyone else in the room (`SessionState._receive_presence`).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_presence(head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	replicating._receive_presence(head, pointing_at, pointing_local)

## Somebody's pose, from the host. The id is the host's word, which the host got from the transport -- a guest cannot put words in another guest's mouth through it (`SessionState._presence_of`).
@rpc("authority", "call_remote", "unreliable_ordered")
func _presence_of(peer_id: int, head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	replicating._presence_of(peer_id, head, pointing_at, pointing_local)


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

## Called when this participant's hand closes on a control (`SessionState.claim_hold`).
func claim_hold(key: String) -> void: replicating.claim_hold(key)

## `SessionState.release_hold`.
func release_hold(key: String) -> void: replicating.release_hold(key)

## Called when this participant's hand takes a thing out of somebody else's: handed over, not refused. Only for what the host says can be (`takeable`); anything else is claimed as usual (`SessionState.take_hold`).
func take_hold(key: String) -> void: replicating.take_hold(key)

## Who has their hand on this control, or 0 for nobody (`SessionState.holder_of`).
func holder_of(key: String) -> int: return replicating.holder_of(key)

@rpc("any_peer", "call_remote", "reliable")
func _claim(key: String) -> void: replicating._claim(key)

@rpc("any_peer", "call_remote", "reliable")
func _take(key: String) -> void: replicating._take(key)

@rpc("any_peer", "call_remote", "reliable")
func _release_remote(key: String) -> void: replicating._release_remote(key)

## The arbitration, in full: whoever the host heard from first. Not the lower peer id, not the later grab -- a rule nobody in the room can see is a rule that feels like the desk is broken. "Sam already had it" is a rule everyone can see, because Sam's hand is on it. The one other refusal is `holdable`'s: a thing kept for somebody else is refused the same way, naming them (`SessionState._grant`).
func _grant(peer_id: int, key: String) -> void: replicating._grant(peer_id, key)

## A thing in one hand taken by another: the hold moves, and the hand it moved from lets go when it hears. Only what `takeable` says -- an item; a fader somebody has is still theirs (`SessionState._hand_over`).
func _hand_over(peer_id: int, key: String) -> void: replicating._hand_over(peer_id, key)

func _release(peer_id: int, key: String) -> void: replicating._release(peer_id, key)

@rpc("authority", "call_remote", "reliable")
func _receive_holds(table: Dictionary) -> void: replicating._receive_holds(table)

@rpc("authority", "call_remote", "reliable")
func _refused(key: String, holder: int) -> void: replicating._refused(key, holder)


# --- being found --------------------------------------------------------------------------
#
# A host says it exists to the LAN once a second, so the person across the room can pick it
# from a list instead of being read an IP address. Broadcast, not multicast: a studio LAN is
# one subnet, and broadcast works on every consumer router without anyone configuring IGMP.
