class_name SessionTakes
extends RefCounted

## A guest's recording: the begin, chunks and end sent to the host, the host writing them as they arrive and placing
## the take with its own DAW. Moved out of `core/session/session.gd` without change of behaviour; the state stays on the autoload, which keeps a
## one-line delegate (with its `@rpc` line where it has one) for each name another file, a string or the network reaches.

var session: Session


func _init(of: Session) -> void:
	session = of


## `plan`, the host's own only: [track, channel] for each track the take goes onto, the channel 0
## for both, 1 or 2 for that input channel alone (GuestAudio.take_plan). Empty is `track`, both.
func send_audio_begin(take_id: int, track: int, start: float, take_name: String, plan: Array = []) -> void:
	if session.role == session.Role.GUEST and session._connected():
		session._audio_begin.rpc_id(1, take_id, track, start, take_name)
	elif session.is_authority():
		_take_begin(session.local_peer_id, take_id, track, start, take_name, plan)


func send_audio_chunk(take_id: int, pcm: PackedByteArray) -> void:
	if session.role == session.Role.GUEST and session._connected():
		session._audio_chunk.rpc_id(1, take_id, pcm)
	elif session.is_authority():
		_take_chunk(session.local_peer_id, take_id, pcm)


## The host's own take, as each input channel its tracks want: {channel: pcm} (see _take_chunk).
func send_audio_channels(take_id: int, by_channel: Dictionary) -> void:
	if session.is_authority():
		_take_chunk(session.local_peer_id, take_id, by_channel)


func send_audio_end(take_id: int) -> void:
	if session.role == session.Role.GUEST and session._connected():
		session._audio_end.rpc_id(1, take_id)
	elif session.is_authority():
		_take_end(session.local_peer_id, take_id)


func _audio_begin(take_id: int, track: int, start: float, take_name: String) -> void:
	var from := session.multiplayer.get_remote_sender_id()
	if not session.is_authority() or not session._is_member(from):
		return
	_take_begin(from, take_id, track, start, take_name)


func _audio_chunk(take_id: int, pcm: PackedByteArray) -> void:
	_take_chunk(session.multiplayer.get_remote_sender_id(), take_id, pcm)


func _audio_end(take_id: int) -> void:
	_take_end(session.multiplayer.get_remote_sender_id(), take_id)


func _take_begin(from: int, take_id: int, track: int, start: float, take_name: String, plan: Array = []) -> void:
	# One take at a time from each guest: a begin while one is open ends that one first.
	_finish_take(from)
	if plan.is_empty():
		plan = [[track, 0]]
	var entry := {"id": take_id, "start": maxf(start, 0.0), "name": MidiTake.clean_name(take_name),
			"parts": []}
	session._incoming_takes[from] = entry
	for step in plan:
		var refusal := DAW.audio_take_refusal(int(step[0]), 1.0)
		var take: AudioTake = null
		if refusal.is_empty():
			session._takes_made += 1
			take = AudioTake.create(AudioTake.file_name_for(_who(from), session._takes_made))
			if take == null:
				refusal = "The host could not write the recording to its disk."
		if not refusal.is_empty():
			if from == session.local_peer_id:
				session.notice.emit("Your recording is not being kept. " + refusal)
			else:
				session.notice.emit("%s's recording was not kept. %s" % [_who(from), refusal])
				session._told.rpc_id(from, "Your recording is not being kept. " + refusal)
			continue
		(entry["parts"] as Array).append({"take": take, "track": int(step[0]), "channel": int(step[1])})


## `pcm` for every part of the take, or, from the host's own recorder, a Dictionary of it by
## channel (0 both sides, 1 and 2 each alone; see send_audio_channels).
func _take_chunk(from: int, take_id: int, pcm: Variant) -> void:
	var entry: Dictionary = session._incoming_takes.get(from, {})
	if entry.is_empty() or entry["id"] != take_id:
		return
	for part in entry["parts"]:
		var bytes: PackedByteArray = pcm.get(part["channel"], PackedByteArray()) if pcm is Dictionary else pcm
		if not (part["take"] as AudioTake).append(bytes):
			# At its limit: placed as it stands, and the rest of it ignored.
			_finish_take(from)
			return


func _take_end(from: int, take_id: int) -> void:
	var entry: Dictionary = session._incoming_takes.get(from, {})
	if not entry.is_empty() and entry["id"] == take_id:
		_finish_take(from)


## A guest's take closed and placed, and both sides told: the guest because a recording that
## vanished would be a disaster they could not see, the host because a new item appearing on its
## timeline unannounced is a surprise in the middle of a session. A take that went onto several
## tracks is placed on each.
func _finish_take(from: int) -> void:
	var entry: Dictionary = session._incoming_takes.get(from, {})
	session._incoming_takes.erase(from)
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
	var still_here := from != session.local_peer_id and session._connected() and session.multiplayer.get_peers().has(from)
	if not refusal.is_empty():
		session.notice.emit("%s's recording was not placed. %s It is kept at %s." % [who, refusal,
				ProjectSettings.globalize_path(take.path)])
		if still_here:
			session._told.rpc_id(from, "Your recording was not placed. " + refusal)
		return
	DAW.on_behalf_of(from, func() -> void:
		DAW.insert_audio_take(track, entry["start"], take.file_name(), take.seconds(),
				take.peaks(), entry["name"]))
	var track_name: String = DAW.state.track(track).display_name()
	var at := DAW.state.bar_beat(entry["start"])
	var length := "%.1fs" % take.seconds()
	session.notice.emit("%s recorded %s onto %s at %s." % [who, length, track_name, at])
	if still_here:
		session._told.rpc_id(from, "Your recording is on %s: %s from %s." % [track_name, length, at])
	session.audio_take_placed.emit({"peer": from, "track": track, "start": entry["start"],
			"seconds": take.seconds(), "path": take.path, "name": entry["name"]})


## A name for whoever a take is from: this machine's own name for its own, which a host alone
## (with no roster) still has.
func _who(peer_id: int) -> String:
	return session.local_name if peer_id == session.local_peer_id else session.name_of(peer_id)


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
func _told(text: String) -> void:
	session.notice.emit(text)
