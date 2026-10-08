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
## A start is not the song moving. Reaper says it is playing the moment it is asked to, but when
## it starts RECORDING its playhead stands still for a tenth of a second or more while it opens
## its files. A clock that ran from the moment it was told would be that far ahead of the song,
## and spend the next half second being corrected back: every note and every frame of a guest's
## take stamped in that time would land late. So after a start the clock holds at the start
## position, and says it is not rolling yet, until a report shows the playhead has left it.
##
## Read from the mix feed's own thread while the main thread writes it, hence the mutex.

## A report further than this from the running clock is a jump, not drift.
const SNAP_SECONDS := 0.25
## How much of a report's disagreement is taken each time, once the clock has settled. Small,
## because each report carries its own jitter -- Reaper's playhead moves in audio blocks, and a
## report is read on the next frame, not when it arrived -- and the clock it corrects is better
## than any one of them.
const GAIN := 0.04

var _mutex := Mutex.new()
var _valid := false
var _playing := false
var _recording := false
var _anchor_seconds := 0.0
var _anchor_usec := 0
var _last_report := NAN
## Reports since the last jump. The first few after a start are averaged evenly (gain 1/n)
## rather than eased in at GAIN: a clock started from one late report is wrong by that report's
## lateness, and the mean of the next dozen is a far better guess than 4% of each.
var _reports := 0
## Started, and the playhead not yet seen to move. See above.
var _waiting := false
var _started_usec := 0
## A DAW whose playhead is never seen to move -- one that only reports now and then -- is taken
## to be rolling after this long anyway.
const START_WAIT_USEC := 500000


## What the DAW says, whenever the caller has it. Repeats of the same report while rolling are
## no news and are ignored -- otherwise a caller that polls every frame would pin the clock to
## a stale report until the next one arrived.
func observe(position: float, playing: bool, recording: bool, now_usec: int) -> void:
	_mutex.lock()
	var transport_changed := not _valid or playing != _playing
	if not transport_changed and playing and _waiting:
		_recording = recording
		if position == _anchor_seconds and now_usec - _started_usec < START_WAIT_USEC:
			_mutex.unlock()
			return
		# It has moved: the clock runs from here, this report the first of a fresh average.
		_waiting = false
		_anchor_seconds = position
		_anchor_usec = now_usec
		_last_report = position
		_reports = 1
		_mutex.unlock()
		return
	if not transport_changed and playing and position == _last_report:
		_recording = recording
		_mutex.unlock()
		return
	_last_report = position
	if transport_changed or not playing:
		_anchor_seconds = position
		_reports = 1
		_waiting = playing and transport_changed
		_started_usec = now_usec
	else:
		var predicted := _anchor_seconds + (now_usec - _anchor_usec) / 1000000.0
		var error := position - predicted
		if absf(error) > SNAP_SECONDS:
			_anchor_seconds = position
			_reports = 1
		else:
			_reports += 1
			_anchor_seconds = predicted + error * maxf(GAIN, 1.0 / _reports)
	_anchor_usec = now_usec
	_playing = playing
	_recording = recording
	_valid = true
	_mutex.unlock()


## The song position at `now_usec` (Time.get_ticks_usec), extrapolated while rolling.
func at(now_usec: int) -> Dictionary:
	_mutex.lock()
	var seconds := _anchor_seconds
	var rolling := _playing and not _waiting
	if rolling:
		seconds += (now_usec - _anchor_usec) / 1000000.0
	var out := {"seconds": seconds, "playing": rolling, "recording": _recording and rolling,
			"valid": _valid}
	_mutex.unlock()
	return out


func reset() -> void:
	_mutex.lock()
	_valid = false
	_waiting = false
	_last_report = NAN
	_mutex.unlock()
