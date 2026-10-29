class_name ModularTakes
extends Node

## Takes played through the modular wall, recorded as audio without a file ever crossing the wire
## (docs/spatial_loop.md part two, slice 52; idea #25). Session's (`Session.modular_takes`).
##
## THE PLAYER'S OWN. While a player's keys record through the modular (GuestMidi's take, its route
## the modular's), GuestMidi begins one here (`begin`) and hands it the notes and the wheel it sends,
## each with the song position it sent them at (`note`, `bend`). The knobs as they are streamed,
## anyone's (`knob`, from Session.send_knob and what Session hears), and the cables the room takes
## (`cable`, from the studio as the room's patch changes) go into it too, each with its `song`. When
## the take ends (`finish`) it is kept as `last_mine`, which renders what the player heard.
##
## THE HOST'S. A guest's take is marked to the host twice, begun and ended, once on the keys'
## channel and once on the gestures' (Session.send_modular_take), so each mark is in order with the
## events on its own channel: the host takes the guest's notes and wheel (`heard_note`,
## `heard_bend`) from the keys' begin to the keys' end, and the knobs and cables from the
## gestures' begin, when it takes the patch as it hears it then (`patch`). A host's own take is the
## player's own, kept here. When both ends are in and SETTLE more has passed, for a cable asked
## on the room's channel to land, the host renders the take and writes it into the project's media
## folder (AudioTake.DIR) as a WAV, both on a worker thread (the render, the 16-bit encode and the
## overview are each a pass over every sample, a third of a second for a minute of take here, and
## a stall on the host's main thread is a dropped frame in a headset), and on the main thread puts
## it in as an audio take named NAME on the take's tracks, at its start (`placed`). The modular
## notes' MIDI take is not put in: the sound is the take. A take longer than an audio take can be
## (AudioTake.MAX_SECONDS) is cut to that, and its player told.
##
## Everything a take holds is stamped with the song position it was made at, so a sweep the host
## heard 80 ms late is where it was turned, and the host's render is the player's own. What the world
## played into the modular's sockets over it (slice 53) goes in when it ends, from `world` (the same
## on every machine, from the song clock and the rows), so the rain on the filter is in the take.

## A placed take, as `Session.audio_take_placed` has one: {peer, tracks, start, seconds, path, name}.
signal placed(info: Dictionary)

## What a modular take is called on its track.
const NAME := "modular"
## After a take's two ends are in, how long the host waits for a cable asked just before the end
## (the room's asks are on a channel of their own), and after one end, the longest it waits for
## the other (s).
const SETTLE := 0.25
const ENDS_WAIT := 2.0

## The patch as this machine hears it now ({cables, knobs}): the room's, with the knobs as they
## are being streamed. Set by the studio (its voice's patch); a fresh room's patch otherwise.
var patch: Callable = Callable()
## What the world played into the modular from one song position to another (ModularWorld.for_take):
## the studio's; nothing otherwise.
var world: Callable = Callable()
## Render a take on a worker thread (false: at once, for the suite).
var threaded := true
## This player's take running now, or null; and the last one, ended.
var mine: ModularTake = null
var last_mine: ModularTake = null
## The tracks the last of mine went onto.
var last_tracks: Array = []
var _mine_id := 0
## Host: the take each player is recording through the modular, by peer: {id, take, keys, gestures
## (each lane's begin heard), ended {lane: true}, tracks, end, due (msec, or -1)}.
var _theirs := {}
## Host: each player's modular notes held now as heard ({peer: {pitch: velocity}}), so a take begun
## with keys down has them from its first moment.
var _held := {}
## Takes being rendered and written on a worker thread: [{task, peer, take, tracks, wav, cut}],
## `wav` a one-slot Array the task fills with the finished AudioTake (or null).
var _rendering: Array = []
## Takes this machine has placed this run, for naming their files.
var takes_placed := 0

enum Lane { KEYS, GESTURES }


func _patch_now() -> Dictionary:
	return Modular.clean(patch.call()) if patch.is_valid() else Modular.default_patch()


# --- this player's own ---------------------------------------------------------------------------

## This player's take through the modular begun at song position `start`, the keys `held` down
## ({pitch: velocity}) in it from its first moment. A guest marks it to the host.
func begin(start: float, held := {}) -> void:
	_mine_id += 1
	mine = ModularTake.new().begin(_patch_now(), start, held)
	if Session.is_authority():
		_theirs[Session.local_peer_id] = {"id": _mine_id, "take": mine, "keys": true, "gestures": true,
				"ended": {}, "tracks": [], "end": start, "due": -1}
	else:
		Session.send_modular_take(_mine_id, true, start, start, [])


## A note this player's keys sent through the modular (Session.Note's ON, OFF), at `song`.
func note(kind: int, pitch: int, velocity: int, song: float) -> void:
	if mine != null:
		mine.note(kind, pitch, velocity, song)


## This player's wheel sent through the modular, at `song`. A move the take keeps goes to the host
## as well, reliable on the keys' channel (Session.send_modular_bend): the wheel heard live rides the
## controls' unreliable channel, whose lost move the next resend makes good for the ear, but a take
## rendered from it would differ from the player's own where one was lost.
func bend(value: int, song: float) -> void:
	if mine != null and mine.bend(value, song) and not Session.is_authority():
		Session.send_modular_bend(value, song)


func reach(at: float) -> void:
	if mine != null:
		mine.reach(at)


## This player's take ended at song position `end`, onto `tracks`: kept as `last_mine`, and the host
## (this machine, or told) places it. An empty `tracks`, or a take with no notes, places nothing.
func finish(tracks: Array, end: float) -> void:
	if mine == null:
		return
	mine.reach(end)
	mine.end = maxf(end, mine.start)
	_hear_world(mine)
	last_mine = mine
	last_tracks = tracks.duplicate()
	mine = null
	if Session.is_authority():
		var entry: Dictionary = _theirs.get(Session.local_peer_id, {})
		if not entry.is_empty() and entry["id"] == _mine_id:
			entry["tracks"] = tracks.duplicate()
			entry["end"] = last_mine.end
			entry["ended"] = {Lane.KEYS: true, Lane.GESTURES: true}
			entry["due"] = Time.get_ticks_msec()
	else:
		Session.send_modular_take(_mine_id, false, last_mine.start, last_mine.end, tracks)


## The running take abandoned: nothing is placed.
func cancel() -> void:
	if mine == null:
		return
	mine = null
	if Session.is_authority():
		_theirs.erase(Session.local_peer_id)
	else:
		Session.send_modular_take(_mine_id, false, 0.0, 0.0, [])


# --- everyone's knobs and cables -----------------------------------------------------------------

## Knob `id` at `v` at song position `song`, whoever turned it: in this player's take and every take
## the host holds whose gestures have begun.
func knob(id: StringName, v: float, song: float) -> void:
	for take in _open():
		take.knob(id, v, song)


## A cable the room took, from `from` into `to` (an empty `to` pulls the cable at `from`), at `song`.
func cable(from: StringName, to: StringName, song: float) -> void:
	for take in _open():
		take.cable(from, to, song)


## Every take the room's knobs and cables go into: this player's, and each the host holds with its
## gestures begun, until it is placed. A knob or a cable from a third player can arrive after the
## take's player has ended it, and is stamped where it was made, so it is taken until the take is
## rendered (one past its end changes nothing). Each once, though the host's own is both.
func _open() -> Array[ModularTake]:
	var out: Array[ModularTake] = []
	if mine != null:
		out.append(mine)
	for peer: int in _theirs:
		var entry: Dictionary = _theirs[peer]
		var take: ModularTake = entry["take"]
		if take != mine and entry["gestures"]:
			out.append(take)
	return out


# --- the host's, from what reaches it ------------------------------------------------------------

## Host: `from`'s note as Session heard it, with its source: a note played through the modular is
## held, and in their take while its keys' lane is open.
func heard_note(from: int, kind: int, pitch: int, velocity: int, song: float, source: StringName) -> void:
	if source != Modular.SOURCE or from == Session.local_peer_id:
		return
	var held: Dictionary = _held.get(from, {})
	if kind == Session.Note.ON:
		held[pitch] = velocity
	elif kind == Session.Note.OFF:
		held.erase(pitch)
	_held[from] = held
	var take := _their(from, Lane.KEYS)
	if take != null:
		take.note(kind, pitch, velocity, song)


## Host: `from`'s wheel in their take, as they sent it for it (Session.send_modular_bend): reliable,
## behind their notes, each move once.
func heard_bend(from: int, value: int, song: float) -> void:
	var take := _their(from, Lane.KEYS)
	if take != null:
		take.bend(value, song)


func _their(from: int, lane: int) -> ModularTake:
	var entry: Dictionary = _theirs.get(from, {})
	if entry.is_empty() or from == Session.local_peer_id:
		return null
	if not entry["keys" if lane == Lane.KEYS else "gestures"] or (entry["ended"] as Dictionary).has(lane):
		return null
	return entry["take"]


## Host: a mark of `from`'s take `id` on `lane`: begun at song position `start`, or ended at `end`
## onto `tracks` (none: abandoned). The keys' begin puts in what they hold, the gestures' takes the
## patch as it is heard here now; a begin of a new take places the one before it if it was ended.
func heard_mark(from: int, lane: int, id: int, begun: bool, start: float, end: float, tracks: Array) -> void:
	if from == Session.local_peer_id or not is_finite(start) or not is_finite(end):
		return
	var entry: Dictionary = _theirs.get(from, {})
	if begun:
		if not entry.is_empty() and entry["id"] != id:
			# A new take: the one before it is placed now if it was ended, else dropped.
			if not (entry["ended"] as Dictionary).is_empty():
				place(from)
			_theirs.erase(from)
			entry = {}
		if entry.is_empty():
			entry = {"id": id, "take": ModularTake.new().begin(_patch_now(), start), "keys": false,
					"gestures": false, "ended": {}, "tracks": [], "end": start, "due": -1}
			_theirs[from] = entry
		var take: ModularTake = entry["take"]
		if lane == Lane.KEYS and not entry["keys"]:
			entry["keys"] = true
			var held: Dictionary = _held.get(from, {})
			var pitches: Array = held.keys()
			pitches.sort()
			for pitch: int in pitches:
				take.note(Session.Note.ON, pitch, int(held[pitch]), take.start)
		elif lane == Lane.GESTURES and not entry["gestures"]:
			entry["gestures"] = true
			take.patch = _patch_now()
		return
	if entry.is_empty() or entry["id"] != id:
		return
	(entry["ended"] as Dictionary)[lane] = true
	var onto: Array = []
	for t: Variant in tracks:
		if typeof(t) in [TYPE_INT, TYPE_FLOAT] and int(t) > 0 and onto.size() < 8:
			onto.append(int(t))
	entry["tracks"] = onto
	entry["end"] = clampf(end, (entry["take"] as ModularTake).start,
			(entry["take"] as ModularTake).start + MidiTake.MAX_SECONDS)
	var both := (entry["ended"] as Dictionary).size() == 2
	entry["due"] = Time.get_ticks_msec() + int((SETTLE if both else ENDS_WAIT) * 1000.0)


## A player gone: what they were recording is dropped, and what they held let go.
func forget(peer: int) -> void:
	_theirs.erase(peer)
	_held.erase(peer)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for peer: int in _theirs.keys():
		var entry: Dictionary = _theirs[peer]
		if int(entry["due"]) >= 0 and now >= int(entry["due"]):
			place(peer)
	for job: Dictionary in _rendering.duplicate():
		if WorkerThreadPool.is_task_completed(job["task"]):
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_rendering.erase(job)
			_put_in(job["peer"], job["take"], job["tracks"], job["wav"][0], job["cut"])


## Host: `peer`'s ended take rendered and written (on a worker thread, or at once) and put in.
## Now, whatever it is still waiting for; for the suite. Past AudioTake.MAX_SECONDS it is cut there.
func place(peer: int) -> void:
	var entry: Dictionary = _theirs.get(peer, {})
	_theirs.erase(peer)
	if entry.is_empty():
		return
	var take: ModularTake = entry["take"]
	take.end = float(entry["end"])
	var cut := take.end - take.start > AudioTake.MAX_SECONDS
	if cut:
		take.end = take.start + AudioTake.MAX_SECONDS
	var tracks: Array = entry["tracks"]
	if tracks.is_empty() or not take.has_notes() or take.frames() == 0:
		return
	_hear_world(take)
	var who := Session._who(peer)
	var refusal := DAW.audio_take_refusal(int(tracks[0]), take.seconds())
	if not refusal.is_empty():
		Session.tell(peer, "Your modular take was not placed. " + refusal)
		if peer != Session.local_peer_id:
			Session.notice.emit("%s's modular take was not placed. %s" % [who, refusal])
		return
	takes_placed += 1
	var file_name := AudioTake.file_name_for(who + "_modular", takes_placed)
	if not threaded:
		_put_in(peer, take, tracks, take.write(file_name), cut)
		return
	# Everything that passes over every sample is the worker's: the take is the host's alone from
	# here (out of `_theirs`, and no longer `mine`), so nothing else touches it while it runs.
	var wav := [null]
	var task := WorkerThreadPool.add_task(func() -> void: wav[0] = take.write(file_name), false,
			"Modular take")
	_rendering.append({"task": task, "peer": peer, "take": take, "tracks": tracks, "wav": wav, "cut": cut})


## What the world played into the modular over `take`'s span, into it, once (on the main thread: the
## world reads the song and the rows).
func _hear_world(take: ModularTake) -> void:
	if world.is_valid() and not take.heard_world():
		take.hear_world(world.call(take.start, take.end))


## Whether a take is still being rendered or waits to be.
func busy() -> bool:
	return not _rendering.is_empty() or _theirs.values().any(func(e: Dictionary) -> bool: return int(e["due"]) >= 0)


## `peer`'s take `take`, rendered and written as the WAV `wav` (null: it could not be), put in on
## each of `tracks` at its start as an audio take named NAME, one step each, done on their behalf;
## both sides told, and with `cut`, that it was cut at AudioTake.MAX_SECONDS. On the main thread.
func _put_in(peer: int, take: ModularTake, tracks: Array, wav: AudioTake, cut := false) -> void:
	var who := Session._who(peer)
	if wav == null:
		Session.tell(peer, "Your modular take was not placed: the host could not write it to its disk.")
		return
	var onto: Array = []
	for track: int in tracks:
		if not DAW.audio_take_refusal(track, wav.seconds()).is_empty():
			continue
		DAW.on_behalf_of(peer, func() -> void:
			DAW.insert_audio_take(track, take.start, wav.file_name(), wav.seconds(), wav.peaks(), NAME))
		onto.append(track)
	if onto.is_empty():
		# The tracks went while it rendered: nothing refers to the file.
		wav.discard()
		Session.tell(peer, "Your modular take was not placed: its track is gone.")
		return
	var track_name: String = DAW.state.track(int(onto[0])).display_name()
	var at := DAW.state.bar_beat(take.start)
	var length := "%.1fs" % wav.seconds()
	var cut_note := " It ran past %d minutes, so only its first %d are kept." % [
			int(AudioTake.MAX_SECONDS / 60.0), int(AudioTake.MAX_SECONDS / 60.0)] if cut else ""
	if peer != Session.local_peer_id:
		Session.notice.emit("%s played the modular onto %s at %s: %s.%s" % [who, track_name, at, length, cut_note])
	Session.tell(peer, "Your modular take is on %s: %s from %s.%s" % [track_name, length, at, cut_note])
	placed.emit({"peer": peer, "tracks": onto, "start": take.start, "seconds": wav.seconds(),
			"path": wav.path, "name": NAME})
