class_name SessionShares
extends RefCounted

## A guest's devices offered to the host, allowed or declined one kind at a time, and a guest's live audio sent up.
## Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## Guest: offer a device to the host. `label` is what the host is shown ("Scarlett 2i2").
func offer_share(kind: StringName, label := "") -> void:
	if session.role != session.Role.GUEST or not session._connected() or not session.SHARE_KINDS.has(kind):
		return
	session.my_shares[kind] = "offered"
	session.shares_changed.emit()
	session._share_offer.rpc_id(1, kind, label)


## Guest: take an offer back, or stop what the host allowed.
func withdraw_share(kind: StringName) -> void:
	if session.role != session.Role.GUEST:
		return
	session.my_shares.erase(kind)
	if kind == &"audio":
		session.my_share_track = 0
	session.shares_changed.emit()
	if session._connected():
		session._share_withdraw.rpc_id(1, kind)


func _share_offer(kind: StringName, label: String) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from) or not session.SHARE_KINDS.has(kind):
		return
	(session.shares.get(from, {}) as Dictionary).erase(kind)
	var mine: Dictionary = session.share_offers.get(from, {})
	mine[kind] = MidiTake.clean_name(label).left(48)
	session.share_offers[from] = mine
	session.shares_changed.emit()
	session.notice.emit("%s offers %s. Open the session panel (M) to answer." % [session.name_of(from), "their audio input" if kind == &"audio" else "their keys and MIDI"])


func _share_withdraw(kind: StringName) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from):
		return
	var changed := (session.share_offers.get(from, {}) as Dictionary).erase(kind)
	changed = (session.shares.get(from, {}) as Dictionary).erase(kind) or changed
	if changed:
		session.shares_changed.emit()


## Host: allow a guest's offered device (on `track` for audio), or decline it, or end it.
func answer_share(peer: int, kind: StringName, allow: bool, track := 0) -> void:
	if session.role != session.Role.HOST or not session.SHARE_KINDS.has(kind):
		return
	(session.share_offers.get(peer, {}) as Dictionary).erase(kind)
	var mine: Dictionary = session.shares.get(peer, {})
	if allow:
		mine[kind] = {"track": maxi(track, 0)}
		session.shares[peer] = mine
	else:
		mine.erase(kind)
	session.shares_changed.emit()
	if session._is_member(peer) and session._connected():
		session._share_answer.rpc_id(peer, kind, allow, maxi(track, 0) if allow else 0)


## Host: whether `peer` may use their `kind` of device here.
func share_allowed(peer: int, kind: StringName) -> bool:
	return (session.shares.get(peer, {}) as Dictionary).has(kind)


## Host: the track `peer`'s audio was put on, 0 for none.
func share_track(peer: int, kind: StringName = &"audio") -> int:
	return int(((session.shares.get(peer, {}) as Dictionary).get(kind, {}) as Dictionary).get("track", 0))


func _share_answer(kind: StringName, allow: bool, track: int) -> void:
	if not session.SHARE_KINDS.has(kind):
		return
	if allow:
		session.my_shares[kind] = "allowed"
		if kind == &"audio":
			session.my_share_track = maxi(track, 0)
	elif session.my_shares.has(kind):
		session.my_shares[kind] = "declined"
		if kind == &"audio":
			session.my_share_track = 0
	session.shares_changed.emit()


## Guest: a packet of live audio to the host, mono 16-bit at 48 kHz (AudioTake.encode). Sent only
## while the host has allowed it.
func send_live_audio(pcm: PackedByteArray) -> void:
	if session.role == session.Role.GUEST and session._connected() and session.my_shares.get(&"audio", "") == "allowed":
		session._live_up.rpc_id(1, pcm)


func _live_up(pcm: PackedByteArray) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if session.role != session.Role.HOST or not session._is_member(from) or not share_allowed(from, &"audio") \
			or pcm.size() > session.LIVE_PACKET_MAX or pcm.size() % 2 != 0:
		session.live_refused += 1
		return
	session.live_audio_heard.emit(from, pcm)
