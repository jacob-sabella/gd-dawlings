class_name PadCapture
extends Node

## The sampling station's other sources (docs/sampling_station.md, slice 6): what the TV is not.
##
##   MIX   the mix itself, as the player hears it (resampling): the Master bus.
##   ROOM  the room's own sounds, as the old Sampler's mic caught them: the Gear bus (items, tape
##         motors, castors, buttons).
##   IN    an audio input of this machine: a microphone, an interface, or any source the sound server
##         offers (a phone or another device linked in as a source). `device` says which; the default
##         one when it is "". Stepped through with `step_device`.
##
## `start` begins catching, `stop` ends it and hands back the sound, stereo at PadBank.RATE, no
## longer than LONGEST. A bus is caught by an AudioEffectCapture put on it for as long as it takes;
## the input is read with AudioServer's direct capture (as MixSource.Captured), so it is never
## played back out of the speakers on top of itself.

const SOURCES := ["TV", "MIX", "ROOM", "IN"]
const BUSES := {"MIX": &"Master", "ROOM": &"Gear"}
const LONGEST := 30.0

const SILENT := 0.01

var source := ""
var recording := false
## The input IN catches from, as AudioServer names it ("" or "Default" is the system's own).
var device := ""
## The loudest the input has been since it was last asked (`level`), 0 to 1.
var _peak := 0.0
var _frames := PackedVector2Array()
var _effect: AudioEffectCapture
var _bus := -1
var _input: MixSource


func seconds() -> float:
	return _frames.size() / float(PadBank.RATE)


## Begin catching `from` (one of MIX, ROOM, IN). Whether it began; a source that is not there says
## `why`.
var why := ""


func start(from: String) -> bool:
	stop()
	why = ""
	_frames = PackedVector2Array()
	if BUSES.has(from):
		_bus = AudioServer.get_bus_index(BUSES[from])
		if _bus < 0:
			why = "No %s to catch." % from
			return false
		_effect = AudioEffectCapture.new()
		_effect.buffer_length = 1.0
		AudioServer.add_bus_effect(_bus, _effect)
	elif from == "IN":
		_input = MixSource.Captured.new(device, device_label(device))
		if not _input.start():
			why = "No audio input to catch."
			_input = null
			return false
	else:
		why = "Nothing to catch from %s." % from
		return false
	source = from
	recording = true
	return true


## The inputs this machine has: [{"id": what AudioServer calls it, "name": what a person calls it}],
## the default first. A source the sound server describes ("Scarlett 2i2 USB") is named so.
static func devices() -> Array:
	var out: Array = [{"id": "", "name": "the default input"}]
	var names := OfflineBackend.device_names()
	for d in AudioServer.get_input_device_list():
		if d != "Default" and d != "":
			out.append({"id": d, "name": str(names.get(d, d))})
	return out


static func device_label(id: String) -> String:
	for d in devices():
		if d["id"] == id:
			return d["name"]
	return id


## IN's next input, wrapping to the default. What it is now called.
func step_device() -> String:
	var all := devices()
	var at := 0
	for i in all.size():
		if all[i]["id"] == device:
			at = i
	var pick: Dictionary = all[(at + 1) % all.size()]
	device = pick["id"]
	return pick["name"]


## How loud the input has been since the last time this was asked: 0 (silence) to 1 (full scale).
func level() -> float:
	var l := _peak
	_peak = 0.0
	return l


## `s` without the quiet at either end: from the first frame over `threshold` to the last, with a
## little of the lead-in kept so an attack is not clipped. All of it if nothing rises over.
static func trimmed(s: PackedVector2Array, threshold := SILENT) -> PackedVector2Array:
	var first := -1
	var last := -1
	for i in s.size():
		if maxf(absf(s[i].x), absf(s[i].y)) > threshold:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return s
	first = maxi(first - int(0.005 * PadBank.RATE), 0)
	last = mini(last + int(0.02 * PadBank.RATE), s.size() - 1)
	return s.slice(first, last + 1)


## Ends the catch: the sound, or an empty one if none was going.
func stop() -> PackedVector2Array:
	if not recording:
		return PackedVector2Array()
	_pull()
	recording = false
	if _effect != null and _bus >= 0:
		var at := -1
		for i in AudioServer.get_bus_effect_count(_bus):
			if AudioServer.get_bus_effect(_bus, i) == _effect:
				at = i
		if at >= 0:
			AudioServer.remove_bus_effect(_bus, at)
	_effect = null
	_bus = -1
	if _input != null:
		_input.stop()
		_input = null
	var done := _frames
	_frames = PackedVector2Array()
	return done


func _process(_delta: float) -> void:
	if recording:
		_pull()


func _pull() -> void:
	var got := PackedVector2Array()
	if _effect != null:
		var n := _effect.get_frames_available()
		if n > 0:
			got = _effect.get_buffer(n)
	elif _input != null:
		got = _resampled(_input.read(), AudioServer.get_input_mix_rate())
	take(got)


## Frames caught, added to the catch (the longest it keeps is LONGEST) and counted into `level`.
func take(got: PackedVector2Array) -> void:
	for f in got:
		_peak = maxf(_peak, maxf(absf(f.x), absf(f.y)))
	_frames.append_array(got)
	var most := int(LONGEST * PadBank.RATE)
	if _frames.size() > most:
		_frames.resize(most)


## `s` at `rate` as frames at PadBank.RATE, read in a straight line between its own.
static func _resampled(s: PackedVector2Array, rate: float) -> PackedVector2Array:
	if s.is_empty() or is_equal_approx(rate, float(PadBank.RATE)):
		return s
	var step := rate / float(PadBank.RATE)
	var out := PackedVector2Array()
	var n := int((s.size() - 1) / step)
	out.resize(maxi(n, 0))
	for i in out.size():
		var t := i * step
		var j := int(t)
		out[i] = s[j].lerp(s[mini(j + 1, s.size() - 1)], t - j)
	return out
