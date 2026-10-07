extends Node

## Autoload `Session`. Who is in the room, what they are each looking through, and who is
## allowed to write to Reaper.
##
## The hard problem this project has that a normal DAW front-end does not: FOUR PEOPLE, ONE
## CONSOLE, DIFFERENT EYES. One is at a monitor with a mouse. Two are in passthrough headsets
## standing at the physical spot where the console appears to be. One is in full VR in another
## room entirely. They must all be able to touch the same channel 8 fader and see the same
## result, and only one of them may hold the socket.
##
## Three things are therefore split apart and must stay split:
##
##   AUTHORITY   who may write to Reaper. Exactly one peer: the host. See core/reaper.
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

signal participant_joined(peer_id: int)
signal participant_left(peer_id: int)
signal role_changed()

var role: int = Role.SOLO
## {peer_id: Participant}
var participants: Dictionary = {}
var local_peer_id: int = 1

var layout: LayoutProfile = null


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


func _ready() -> void:
	layout = LayoutProfile.new()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Start a solo session: no network, this process also owns the Reaper link.
func start_solo() -> void:
	role = Role.SOLO
	local_peer_id = 1
	participants.clear()
	_register(1, "local")
	role_changed.emit()


func host(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port) != OK:
		push_error("Session: cannot host on %d" % port)
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	local_peer_id = 1
	_register(1, "host")
	role_changed.emit()
	return true


func join(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		push_error("Session: cannot reach %s:%d" % [address, port])
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.GUEST
	local_peer_id = multiplayer.get_unique_id()
	# A guest must NOT open its own OSC link. This is the one line that keeps the four-way echo
	# storm described in core/reaper/reaper_link.gd from ever happening.
	Reaper.start_guest()
	role_changed.emit()
	return true


func is_authority() -> bool:
	return role != Role.GUEST


func _register(peer_id: int, name_hint: String) -> void:
	if participants.has(peer_id):
		return
	var p := Participant.new()
	p.peer_id = peer_id
	p.display_name = name_hint
	participants[peer_id] = p
	participant_joined.emit(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	_register(peer_id, "peer %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	participants.erase(peer_id)
	participant_left.emit(peer_id)


# --- intents ------------------------------------------------------------------------------

## A guest's write, forwarded to the host.
##
## Intents carry the OSC address verbatim rather than a hand-rolled enum of actions. That keeps
## the guest path from drifting behind the host path: anything a control can do locally is
## already expressible, including FX parameters that nothing in this codebase knows the names of.
func send_intent(address: String, args: Array) -> void:
	if is_authority():
		Reaper.write(address, args)
		return
	_receive_intent.rpc_id(1, address, args)


@rpc("any_peer", "call_remote", "reliable")
func _receive_intent(address: String, args: Array) -> void:
	if not is_authority():
		return
	# Trusted-LAN model, stated plainly so nobody mistakes it for a checked one: any peer that
	# reached this session may move any fader. That is correct for four people in a studio and
	# wrong for anything exposed beyond it. See docs/architecture.md.
	Reaper.write(address, args)


# --- presence -----------------------------------------------------------------------------

func publish_head(head_in_session_space: Transform3D) -> void:
	if participants.has(local_peer_id):
		participants[local_peer_id].head = head_in_session_space
	if role == Role.SOLO:
		return
	_receive_head.rpc(local_peer_id, head_in_session_space)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_head(peer_id: int, head: Transform3D) -> void:
	if not participants.has(peer_id):
		_register(peer_id, "peer %d" % peer_id)
	participants[peer_id].head = head
