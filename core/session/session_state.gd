class_name SessionState
extends RefCounted

## The host's track spectra, the replicated project state, presence (head and pointing) and the holds on controls.
## Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## The host's track spectra (track -> Spectra.BANDS levels in dB) to every guest, as Spectra.pack
## parcels them: a byte a band per track. The host only; Spectra sends them SEND_HZ times a second.
func send_spectra(by_track: Dictionary) -> void:
	if session.role != session.Role.HOST or not session._connected():
		return
	var audience := session.admitting._audience()
	if audience.is_empty():
		return
	for parcel in Spectra.pack(by_track):
		for id in audience:
			session._spectra_from_host.rpc_id(id, parcel)


func _spectra_from_host(parcel: PackedByteArray) -> void:
	if session.role != session.Role.GUEST:
		return
	hear_spectra(parcel)


## A parcel of the host's spectra, taken in: each track in it replaces what was heard for it. A
## parcel that is not whole is dropped.
func hear_spectra(parcel: PackedByteArray) -> void:
	var got := Spectra.unpack(parcel)
	if got.is_empty():
		return
	for t in got:
		session.spectra[t] = got[t]
	session.spectra_heard_msec = Time.get_ticks_msec()
	session.spectra_heard.emit()


func _forget_spectra() -> void:
	session.spectra = {}
	session.spectra_heard_msec = -1


## Host -> guests, once per replication tick.
##
## Two RPCs rather than one, because the two halves of the batch need opposite guarantees and
## sending both reliably makes meter traffic block name changes behind it. See the buffers in
## core/reaper/reaper_link.gd for which is which.
func broadcast_state(durable: Dictionary, volatile: Dictionary) -> void:
	if not session.is_authority() or session.role == session.Role.SOLO:
		return
	var audience := session.admitting._audience()
	if not durable.is_empty():
		var batch := _as_batch(durable)
		for id in audience:
			session._receive_state_durable.rpc_id(id, batch)
	if not volatile.is_empty():
		# In parcels under the MTU. An unreliable packet ENet has to fragment is lost whenever
		# ANY fragment is, so one 1.5KB meter frame on wifi fails several times as often as
		# two small ones -- and forty tracks of meters is more than one packet.
		for parcel in _parcels(_as_batch(volatile)):
			for id in audience:
				session._receive_state_volatile.rpc_id(id, parcel)


static func _parcels(batch: Array) -> Array:
	var out: Array = []
	var parcel: Array = []
	var bytes := 0
	for entry in batch:
		var size := var_to_bytes(entry).size()
		if not parcel.is_empty() and bytes + size > Session.PARCEL_BYTES:
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


func _receive_state_durable(batch: Array) -> void:
	DAW.backend.apply_replicated(batch)


func _receive_state_volatile(batch: Array) -> void:
	DAW.backend.apply_replicated(batch)


## The host opened a different project: every guest gets it whole, the same way a guest that
## has just joined does. Deltas would only describe what changed, and everything did.
func _on_project_replaced() -> void:
	if not is_instance_valid(session):
		return
	for id in session.admitting._audience():
		_send_snapshot_to(id)


## The host's tracks were renumbered. Every track chosen for a take, here and on every guest, and
## every take on its way in, follows its track; one whose track is gone is refused when it lands.
func _on_tracks_renumbered(map: Dictionary) -> void:
	if not is_instance_valid(session):
		return
	if session.role == session.Role.GUEST:
		return
	_follow_renumber(map)
	for entry in session._incoming_takes.values():
		for part in entry["parts"]:
			part["track"] = int(map.get(part["track"], -1))
	if session.role == session.Role.HOST:
		session._tracks_renumbered.rpc(map)


func _tracks_renumbered(map: Dictionary) -> void:
	var clean := {}
	for old in map:
		if typeof(old) == TYPE_INT and typeof(map[old]) == TYPE_INT:
			clean[old] = map[old]
	_follow_renumber(clean)


func _follow_renumber(map: Dictionary) -> void:
	for recorder in [session.guest_audio, session.guest_midi, session.host_audio]:
		if recorder != null:
			recorder.follow_renumber(map)


## A joining guest gets the whole session at once, reliably, before any delta reaches it.
##
## Without this a guest would start empty and fill in only as things were touched -- a console
## that grows a channel each time someone moves a fader, and never shows the tracks nobody
## happens to touch. The deltas are edge-triggered, so there is no second chance.
func _send_snapshot_to(peer_id: int) -> void:
	if not session.is_authority() or session.role == session.Role.SOLO:
		return
	if not session.participants.has(peer_id):
		return
	session._receive_state_durable.rpc_id(peer_id, DAW.backend.snapshot())


## Where this participant's head is and what they are pointing at, a few dozen times a second.
##
## Unreliable and ordered: a pose is superseded by the next one in 50ms, and a lost one is
## better skipped than delivered late and walked back over.
func publish_presence(head_in_session_space: Transform3D, pointing_at: String,
		pointing_local: Vector3) -> void:
	var me: Session.Participant = session.participants.get(session.local_peer_id)
	if me != null:
		me.head = head_in_session_space
		me.pointing_at = pointing_at
		me.pointing_local = pointing_local
	if not session._connected():
		return
	if session.role == session.Role.HOST:
		for id in session.admitting._audience():
			session._presence_of.rpc_id(id, session.local_peer_id, head_in_session_space, pointing_at, pointing_local)
	else:
		session._receive_presence.rpc_id(1, head_in_session_space, pointing_at, pointing_local)


## A guest's pose, to the host, which keeps it and passes it on to everyone else in the room.
## Relayed by hand rather than by ENet's server relay so the host decides who hears it -- see
## `host()`.
func _receive_presence(head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	if session.role != session.Role.HOST:
		return
	# The sender as the transport saw it, never as the packet claims. A pose arriving with
	# someone else's id would put a stranger's head on a friend's name tag.
	var from := session.multiplayer.get_remote_sender_id()
	if not session._is_member(from):
		return
	_heard_presence(from, head, pointing_at, pointing_local)
	for id in session.admitting._audience():
		if id != from:
			session._presence_of.rpc_id(id, from, head, pointing_at, pointing_local)


## Somebody's pose, from the host. The id is the host's word, which the host got from the
## transport -- a guest cannot put words in another guest's mouth through it.
func _presence_of(peer_id: int, head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	if peer_id == session.local_peer_id:
		return
	_heard_presence(peer_id, head, pointing_at, pointing_local)


func _heard_presence(peer_id: int, head: Transform3D, pointing_at: String, pointing_local: Vector3) -> void:
	var p: Session.Participant = session.participants.get(peer_id)
	# Not registered from here: the roster is the host's, and a pose that outruns the roster
	# by a packet is simply early. The next one lands on a participant that exists.
	if p == null:
		return
	p.head = head
	p.pointing_at = pointing_at
	p.pointing_local = pointing_local
	p.heard_msec = Time.get_ticks_msec()


## Called when this participant's hand closes on a control.
func claim_hold(key: String) -> void:
	if key.is_empty() or not session._connected():
		return
	if session.role == session.Role.HOST:
		_grant(session.local_peer_id, key)
	else:
		session._claim.rpc_id(1, key)


func release_hold(key: String) -> void:
	if key.is_empty() or not session._connected():
		return
	if session.role == session.Role.HOST:
		_release(session.local_peer_id, key)
	else:
		session._release_remote.rpc_id(1, key)


## Called when this participant's hand takes a thing out of somebody else's: handed over, not
## refused. Only for what the host says can be (`takeable`); anything else is claimed as usual.
func take_hold(key: String) -> void:
	if key.is_empty() or not session._connected():
		return
	if session.role == session.Role.HOST:
		_hand_over(session.local_peer_id, key)
	else:
		session._take.rpc_id(1, key)


## Who has their hand on this control, or 0 for nobody.
func holder_of(key: String) -> int:
	return session.holds.get(key, 0)


func _claim(key: String) -> void:
	if session.role == session.Role.HOST and session._is_member(session.multiplayer.get_remote_sender_id()):
		_grant(session.multiplayer.get_remote_sender_id(), key)


func _take(key: String) -> void:
	if session.role == session.Role.HOST and session._is_member(session.multiplayer.get_remote_sender_id()):
		_hand_over(session.multiplayer.get_remote_sender_id(), key)


func _release_remote(key: String) -> void:
	if session.role == session.Role.HOST and session._is_member(session.multiplayer.get_remote_sender_id()):
		_release(session.multiplayer.get_remote_sender_id(), key)


## The arbitration, in full: whoever the host heard from first. Not the lower peer id, not the
## later grab -- a rule nobody in the room can see is a rule that feels like the desk is broken.
## "Sam already had it" is a rule everyone can see, because Sam's hand is on it. The one other
## refusal is `holdable`'s: a thing kept for somebody else is refused the same way, naming them.
func _grant(peer_id: int, key: String) -> void:
	var holder: int = session.holds.get(key, 0)
	if holder == 0 and session.holdable.is_valid():
		var kept_for := int(session.holdable.call(key, peer_id))
		if kept_for != 0 and kept_for != peer_id:
			holder = kept_for
	if holder != 0 and holder != peer_id:
		if peer_id == session.local_peer_id:
			session.hold_refused.emit(key, holder)
		elif session._connected():
			session._refused.rpc_id(peer_id, key, holder)
		return
	if holder == peer_id:
		return
	session.holds[key] = peer_id
	_send_holds()


## A thing in one hand taken by another: the hold moves, and the hand it moved from lets go when
## it hears. Only what `takeable` says -- an item; a fader somebody has is still theirs.
func _hand_over(peer_id: int, key: String) -> void:
	if not session.takeable.is_valid() or not session.takeable.call(key) or session.holds.get(key, 0) == peer_id:
		_grant(peer_id, key)
		return
	if session.holdable.is_valid():
		var kept_for := int(session.holdable.call(key, peer_id))
		if kept_for != 0 and kept_for != peer_id:
			_grant(peer_id, key)
			return
	session.holds[key] = peer_id
	_send_holds()


func _release(peer_id: int, key: String) -> void:
	if session.holds.get(key, 0) != peer_id:
		return
	session.holds.erase(key)
	_send_holds()


func _send_holds() -> void:
	if session.role != session.Role.HOST:
		return
	if session._connected():
		for id in session.admitting._audience():
			session._receive_holds.rpc_id(id, session.holds)
	session.holds_changed.emit()


func _receive_holds(table: Dictionary) -> void:
	session.holds = table
	session.holds_changed.emit()


func _refused(key: String, holder: int) -> void:
	session.hold_refused.emit(key, holder)
