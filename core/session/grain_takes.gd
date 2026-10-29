class_name GrainTakes
extends Node

## Takes played on the grain cloud, recorded as audio without a sound ever crossing the wire
## (docs/spatial_loop.md part two, slice 55; idea #24). Session's (`Session.grain_takes`).
##
## THE PLAYER'S OWN. Every grain event this player's cloud plays reaches here as it is sent
## (`played`, from Session.send_grains), with the song position it was made at (`song`: what the
## player hears, moved on by the cloud's figure). While the song records as this player hears it
## (GuestMidi.heard: past any count-in, inside any punch range, as GuestMidi's keys take it), the
## first event begins a take (`mine`, a GrainTake) onto the track the keys would take, else the armed
## one (`track`); when recording is heard to stop it ends and is kept as `last_mine`, which renders
## what the player heard. With no track to go onto, the player is told once a recording.
##
## THE HOST'S. A guest's take is marked to the host, begun and ended (Session.send_grain_take), on
## the same reliable channel as its events (Session.GESTURE_CHANNEL), so the host takes exactly the
## events between its marks (`heard_event`, `heard_mark`). A host's own take is the player's own, kept
## here. Ended, the host renders the take from its own copy of the cloud's sound (`sound`, the
## studio's: the same cassette in the same bowl, from the same file) and writes it into the project's
## media folder (AudioTake.DIR) as a WAV, both on a worker thread, and on the main thread puts it in
## as an audio take named NAME on the take's track at its first event's song (GrainTake.lands).
##
## Since the player's cloud plays from the same events (GrainVoice: events, never the hand), the
## host's take is what the player heard, sample for sample.

## A placed take, as `Session.audio_take_placed` has one: {peer, tracks, start, seconds, path, name}.
signal placed(info: Dictionary)

## What a grain cloud take is called on its track. A guest's end mark is behind every event of the
## take on the same channel, so the host places it as soon as the mark arrives.
const NAME := "grains"

## () -> PackedFloat32Array: the grain cloud's sound here now (mono at GrainVoice.RATE), empty for
## none. The studio's.
var sound: Callable = Callable()
## Where the song is as this player hears it: {seconds, playing, recording, valid}. GuestMidi.heard by
## default; the suite gives its own.
var heard_source: Callable = Callable()
## Render a take on a worker thread (false: at once, for the suite).
var threaded := true
## This player's take running now, or null; the last one, ended; and the tracks it went onto.
var mine: GrainTake = null
var last_mine: GrainTake = null
var last_tracks: Array = []
var _mine_id := 0
var _mine_tracks: Array = []
## Told already this recording that the grains have no track to go onto.
var _warned := false
## Host: the take each player is recording on the cloud, by peer: {id, take, tracks, ended, due
## (msec, or -1)}.
var _theirs := {}
## Takes being rendered and written on a worker thread: [{task, peer, take, tracks, wav}], `wav` a
## one-slot Array the task fills with the finished AudioTake (or null).
var _rendering: Array = []
## Takes this machine has placed this run, for naming their files.
var takes_placed := 0


func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	if DAW.state != null:
		return {"seconds": DAW.state.position_seconds, "playing": DAW.state.playing,
				"recording": DAW.state.recording, "valid": true}
	return {"seconds": 0.0, "playing": false, "recording": false, "valid": false}


## The song position to stamp a grain event made now with: what this player hears, moved on by the
## cloud's figure, since they hear its grains that much later; -1 while the song is not playing.
func song() -> float:
	var h := heard()
	if not h.get("valid", false) or not h.get("playing", false):
		return -1.0
	return float(h["seconds"]) + GrainVoice.latency_seconds()


## Whether the song records as this player hears it (`h`, `heard`'s).
static func rolling(h: Dictionary) -> bool:
	return bool(h.get("valid", false)) and bool(h.get("recording", false)) and DAW.state != null \
			and DAW.state.takes_at(float(h["seconds"]))


## The track this player's grains go onto: the one their keys' takes are set to, else the armed one.
static func track() -> int:
	if Session.guest_midi != null and Session.guest_midi.target_track > 0:
		return Session.guest_midi.target_track
	return HitRecorder.armed_track()


# --- this player's own ---------------------------------------------------------------------------

## Event `e` this player's cloud played, made at song position `at`: into the take, begun with it
## if the song records and this is the first.
func played(e: PackedFloat32Array, at: float) -> void:
	if mine == null:
		if at < 0.0 or not rolling(heard()):
			return
		var onto := track()
		if onto <= 0:
			if not _warned:
				_warned = true
				Session.notice.emit("The grain cloud's grains are not being recorded: arm a track for them.")
			return
		begin(at, [onto])
	mine.add(e, at)


## This player's take begun at song position `at`, onto `tracks`. A guest marks it to the host.
func begin(at: float, tracks: Array) -> void:
	_mine_id += 1
	mine = GrainTake.new().begin(at)
	_mine_tracks = tracks.duplicate()
	if Session.is_authority():
		_theirs[Session.local_peer_id] = {"id": _mine_id, "take": mine, "tracks": _mine_tracks.duplicate(),
				"ended": false, "due": -1}
	else:
		Session.send_grain_take(_mine_id, true, at, at, [])


## This player's take ended at song position `at`: kept as `last_mine`, and the host (this machine,
## or told) places it.
func finish(at: float) -> void:
	if mine == null:
		return
	mine.finish(at)
	last_mine = mine
	last_tracks = _mine_tracks.duplicate()
	mine = null
	if Session.is_authority():
		var entry: Dictionary = _theirs.get(Session.local_peer_id, {})
		if not entry.is_empty() and entry["id"] == _mine_id:
			entry["ended"] = true
			entry["due"] = Time.get_ticks_msec()
	else:
		Session.send_grain_take(_mine_id, false, last_mine.start, last_mine.end, last_tracks)


## The running take abandoned (out of the session): nothing is placed.
func cancel() -> void:
	if mine == null:
		return
	mine = null
	_theirs.erase(Session.local_peer_id)


func _process(_delta: float) -> void:
	var h := heard()
	if not rolling(h):
		_warned = false
		if mine != null:
			finish(float(h["seconds"]) if h.get("valid", false) else mine.start)
	var now := Time.get_ticks_msec()
	for peer: int in _theirs.keys():
		var entry: Dictionary = _theirs[peer]
		if int(entry["due"]) >= 0 and now >= int(entry["due"]):
			place(peer)
	for job: Dictionary in _rendering.duplicate():
		if WorkerThreadPool.is_task_completed(job["task"]):
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_rendering.erase(job)
			_put_in(job["peer"], job["take"], job["tracks"], job["wav"][0])


# --- the host's, from what reaches it ------------------------------------------------------------

## Host: `from`'s grain event `e` made at song position `at`, as Session heard it: in their take
## while it is open.
func heard_event(from: int, e: PackedFloat32Array, at: float) -> void:
	if from == Session.local_peer_id:
		return
	var entry: Dictionary = _theirs.get(from, {})
	if entry.is_empty() or entry["ended"]:
		return
	(entry["take"] as GrainTake).add(e, at)


## Host: a mark of `from`'s take `id`: begun at song position `start`, or ended at `end` onto `tracks`
## (none: abandoned). A begin of a new take places the one before it if it was ended.
func heard_mark(from: int, id: int, begun: bool, start: float, end: float, tracks: Array) -> void:
	if from == Session.local_peer_id or not is_finite(start) or not is_finite(end):
		return
	var entry: Dictionary = _theirs.get(from, {})
	if begun:
		if not entry.is_empty() and entry["id"] != id:
			if entry["ended"]:
				place(from)
			_theirs.erase(from)
			entry = {}
		if entry.is_empty():
			_theirs[from] = {"id": id, "take": GrainTake.new().begin(maxf(start, 0.0)), "tracks": [],
					"ended": false, "due": -1}
		return
	if entry.is_empty() or entry["id"] != id:
		return
	var onto: Array = []
	for t: Variant in tracks:
		if typeof(t) in [TYPE_INT, TYPE_FLOAT] and int(t) > 0 and onto.size() < 8:
			onto.append(int(t))
	var take: GrainTake = entry["take"]
	take.finish(clampf(end, take.start, take.start + AudioTake.MAX_SECONDS))
	entry["tracks"] = onto
	entry["ended"] = true
	entry["due"] = Time.get_ticks_msec()


## A player gone: what they were recording is dropped.
func forget(peer: int) -> void:
	_theirs.erase(peer)


## Whether a take is still being rendered or waits to be.
func busy() -> bool:
	return not _rendering.is_empty() or _theirs.values().any(func(e: Dictionary) -> bool: return e["ended"])


## Host: `peer`'s ended take rendered and written (on a worker thread, or at once) and put in. Now,
## whatever it is still waiting for; for the suite.
func place(peer: int) -> void:
	var entry: Dictionary = _theirs.get(peer, {})
	_theirs.erase(peer)
	if entry.is_empty():
		return
	var take: GrainTake = entry["take"]
	var tracks: Array = entry["tracks"]
	if tracks.is_empty() or take.is_empty():
		return
	var from: PackedFloat32Array = sound.call() if sound.is_valid() else PackedFloat32Array()
	if from.size() <= 1:
		Session.tell(peer, "Your grain cloud take was not placed: the host's cloud has no sound in its bowl.")
		return
	var refusal := DAW.audio_take_refusal(int(tracks[0]), 1.0 / GrainVoice.EVENT_HZ)
	if not refusal.is_empty():
		Session.tell(peer, "Your grain cloud take was not placed. " + refusal)
		if peer != Session.local_peer_id:
			Session.notice.emit("%s's grain cloud take was not placed. %s" % [Session._who(peer), refusal])
		return
	takes_placed += 1
	var file_name := AudioTake.file_name_for(Session._who(peer) + "_grains", takes_placed)
	if not threaded:
		_put_in(peer, take, tracks, take.write(file_name, from))
		return
	# The render and the write each pass over every sample: the worker's. The take is the host's alone
	# from here (out of `_theirs`, and no longer `mine`), and so is its copy of the sound.
	var wav := [null]
	var task := WorkerThreadPool.add_task(func() -> void: wav[0] = take.write(file_name, from), false,
			"Grain cloud take")
	_rendering.append({"task": task, "peer": peer, "take": take, "tracks": tracks, "wav": wav})


## `peer`'s take `take`, rendered and written as the WAV `wav` (null: it could not be), put in on each
## of `tracks` at its first event's song as an audio take named NAME, one step each, done on their
## behalf; both sides told. On the main thread.
func _put_in(peer: int, take: GrainTake, tracks: Array, wav: AudioTake) -> void:
	if wav == null:
		Session.tell(peer, "Your grain cloud take was not placed: the host could not write it to its disk.")
		return
	var at := take.lands()
	var onto: Array = []
	for t: int in tracks:
		if not DAW.audio_take_refusal(t, wav.seconds()).is_empty():
			continue
		DAW.on_behalf_of(peer, func() -> void:
			DAW.insert_audio_take(t, at, wav.file_name(), wav.seconds(), wav.peaks(), NAME))
		onto.append(t)
	if onto.is_empty():
		wav.discard()
		Session.tell(peer, "Your grain cloud take was not placed: its track is gone.")
		return
	var track_name: String = DAW.state.track(int(onto[0])).display_name()
	var where := DAW.state.bar_beat(at)
	var length := "%.1fs" % wav.seconds()
	if peer != Session.local_peer_id:
		Session.notice.emit("%s played the grain cloud onto %s at %s: %s." % [Session._who(peer), track_name, where, length])
	Session.tell(peer, "Your grain cloud take is on %s: %s from %s." % [track_name, length, where])
	placed.emit({"peer": peer, "tracks": onto, "start": at, "seconds": wav.seconds(), "path": wav.path, "name": NAME})


func _exit_tree() -> void:
	for job: Dictionary in _rendering:
		WorkerThreadPool.wait_for_task_completion(job["task"])
	_rendering.clear()
