class_name SongClock
extends RefCounted

## Where the song is, now, to well under a millisecond -- from a DAW that only says so now and
## then.
##
## Reaper reports its playhead over OSC a few dozen times a second, and each report is late by
## however long it spent in a socket. The stand-in steps its playhead once a frame. Neither is a
## clock you can stamp audio with: a packet of the mix leaves every 2.7ms, and stamping it with
## the last report would put a staircase of up to 30ms into every guest's take. So the reports
## are treated as corrections to a clock that runs on its own between them -- the wall clock,
## at one second per second while the transport rolls -- and a report that disagrees by more
## than a jump's worth (a seek, a loop wrapping, a stop) is taken as a jump rather than as
## drift.
##
## Read from the mix feed's own thread while the main thread writes it, hence the mutex.

## A report further than this from the running clock is a jump, not drift.
const SNAP_SECONDS := 0.25
## How much of a report's disagreement is taken each time. Small, because each report carries
## its own transport jitter, and the clock it corrects is better than any one of them.
const GAIN := 0.15

var _mutex := Mutex.new()
var _valid := false
var _playing := false
var _recording := false
var _anchor_seconds := 0.0
var _anchor_usec := 0
var _last_report := NAN


## What the DAW says, whenever the caller has it. Repeats of the same report while rolling are
## no news and are ignored -- otherwise a caller that polls every frame would pin the clock to
## a stale report until the next one arrived.
func observe(position: float, playing: bool, recording: bool, now_usec: int) -> void:
	_mutex.lock()
	var transport_changed := not _valid or playing != _playing
	if not transport_changed and playing and position == _last_report:
		_recording = recording
		_mutex.unlock()
		return
	_last_report = position
	if transport_changed or not playing:
		_anchor_seconds = position
	else:
		var predicted := _anchor_seconds + (now_usec - _anchor_usec) / 1000000.0
		var error := position - predicted
		_anchor_seconds = position if absf(error) > SNAP_SECONDS else predicted + error * GAIN
	_anchor_usec = now_usec
	_playing = playing
	_recording = recording
	_valid = true
	_mutex.unlock()


## The song position at `now_usec` (Time.get_ticks_usec), extrapolated while rolling.
func at(now_usec: int) -> Dictionary:
	_mutex.lock()
	var seconds := _anchor_seconds
	if _playing:
		seconds += (now_usec - _anchor_usec) / 1000000.0
	var out := {"seconds": seconds, "playing": _playing, "recording": _recording and _playing,
			"valid": _valid}
	_mutex.unlock()
	return out


func reset() -> void:
	_mutex.lock()
	_valid = false
	_last_report = NAN
	_mutex.unlock()
