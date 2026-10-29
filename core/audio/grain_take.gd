class_name GrainTake
extends RefCounted

## A take played on the grain cloud, kept as what was played rather than as sound
## (docs/spatial_loop.md part two, slice 55; idea #24): the grain events of one player while the
## song recorded (GrainVoice.event, thirty a second), each with the song position it was made at.
## Its sound is `render`: GrainVoice.render of its events from the cloud's sound, the same Renderer
## the live voice plays them through, so the take of a hand in the cloud is what its player heard,
## sample for sample, on whichever machine renders it.
##
## The player keeps one of their own as they play (GrainTakes.mine), and the host keeps one for each
## player recording on the cloud from what reaches it (Session.send_grains, reliable and in order on
## Session.GESTURE_CHANNEL, between the take's two marks on the same channel). When it ends the host
## renders its own copy and places the WAV (`write`), so no sound ever crosses the wire.
##
## WHERE IT LANDS. An event's song position is what its player was hearing when they made it, moved
## on by the cloud's own figure (GrainVoice.latency_seconds), as a note's is moved on by its synth's:
## the player lines up the grains they hear with the song they hear. The take's sound begins with its
## first event's window, so it is put in at that event's song (`lands`), not where recording began.
## The render keeps the events' own spacing (a window a tick), so a hand let go and put back mid-take
## is a gap of the same length in it.

## The song position the take was begun at (its first event's), and where recording ended.
var start := 0.0
var end := INF
## Its events, in the order they were played, and the song position each was made at.
var events: Array[PackedFloat32Array] = []
var songs := PackedFloat64Array()


## Begun at song position `at`.
func begin(at: float) -> GrainTake:
	start = at
	end = INF
	return self


## Event `e`, made at song position `song`, kept if it is an event, stamped inside the take (from its
## start to its end, AudioTake.MAX_SECONDS at most), and later than the last kept (a tick repeated,
## or one from before, is not). Whether it was kept.
func add(e: PackedFloat32Array, song: float) -> bool:
	if not GrainVoice.is_event(e) or not is_finite(song) or song < start or song > end \
			or song > start + AudioTake.MAX_SECONDS:
		return false
	if not events.is_empty() and e[GrainVoice.TICK] <= events[events.size() - 1][GrainVoice.TICK]:
		return false
	events.append(e)
	songs.append(song)
	return true


## Ended at song position `at`: anything kept that was stamped past it goes, so the player's take
## and the host's, given the same events and the same end, keep the same.
func finish(at: float) -> void:
	end = maxf(at, start)
	while not songs.is_empty() and songs[songs.size() - 1] > end:
		events.remove_at(events.size() - 1)
		songs.resize(songs.size() - 1)


## Where its sound goes on the timeline: its first event's song position.
func lands() -> float:
	return songs[0] if not songs.is_empty() else start


func is_empty() -> bool:
	return events.is_empty()


## The take's sound, mono at GrainVoice.RATE, from `sound` (the cloud's, GrainVoice.mono_of): a window
## a tick from its first event to its last, and on until its last grain has rung. Pure, and safe off
## the main thread.
func render(sound: PackedFloat32Array) -> PackedFloat32Array:
	return GrainVoice.render(sound, events)


## `mono` at GrainVoice.RATE as an audio take holds it, at AudioTake.RATE: twice as many samples, each
## of its own where it was and the one between halfway, so every other sample is the render's own.
static func at_take_rate(mono: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := mono.size()
	if n == 0:
		return out
	var ratio := AudioTake.RATE / GrainVoice.RATE
	out.resize(n * ratio)
	for i in n:
		var a := mono[i]
		var b := mono[mini(i + 1, n - 1)]
		for k in ratio:
			out[i * ratio + k] = lerpf(a, b, float(k) / float(ratio))
	return out


## The take's sound written as a WAV in the project's media folder (AudioTake.DIR) under `file_name`,
## finished, or null if the file cannot be made. Safe off the main thread.
func write(file_name: String, sound: PackedFloat32Array) -> AudioTake:
	var take := AudioTake.create(file_name)
	if take == null:
		return null
	take.append(ModularTake.pcm(at_take_rate(render(sound))))
	take.finish()
	return take
