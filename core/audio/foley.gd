class_name Foley
extends Object

## The sound the gear makes. Not the mix.
##
## The mix is already audible: Reaper is playing through the monitors in the room this is
## running in. Rendering it again here would add latency to something the engineer is listening
## critically to, and two copies of the same signal a few milliseconds apart is a comb filter,
## not a feature. So this makes no attempt to reproduce audio -- it makes the noises a room full
## of hardware makes while you work it.
##
## WHY THAT MATTERS MORE IN HERE THAN IT WOULD ON A SCREEN
##
## In a headset there is nothing under your fingers. A fader you have grabbed and a fader you
## are about to grab look nearly identical, and the hand is in the wrong place by a centimetre
## about as often as it is in the right one. Sound is the only channel left that can say
## "contact" at the instant contact happens, and it is positional, so it also says WHICH one.
##
## SYNTHESISED, NOT SAMPLED
##
## Same reason the console sizes itself and the knob is a script: a .wav committed next to all
## of this would be the one thing nobody could read or adjust. These are a few lines of
## arithmetic each, they are deterministic, and the suite can assert on the samples -- which
## matters more than it sounds like, because the two ways synthesised audio goes wrong (a loop
## that clicks at the seam, a one-shot that cuts off before it has decayed) are both perfectly
## visible in a buffer and both completely inaudible to someone who is not listening for them.

const RATE := 44100

## Studio scale. These are small sounds made by small objects; the default unit size carries a
## button click across a concert hall.
const UNIT_SIZE := 0.55
const MAX_DISTANCE := 14.0

static var _cache: Dictionary = {}


## A panel button. Two transients, because a snap-action switch has two: your finger arriving,
## and the dome going over centre a moment later. One transient reads as a tap on plastic.
static func button_click() -> AudioStreamWAV:
	return _cached("button", func() -> AudioStreamWAV:
		var s := _silence(0.045)
		_impulse(s, 0.0, 0.55, 0.0032, 2600.0, 11)
		_impulse(s, 0.0075, 0.42, 0.0120, 1750.0, 13)
		return _wav(s, false))


## A knob passing a detent. Shorter, quieter and higher than a button, because it has to be
## able to fire twenty times a second without becoming a noise.
static func knob_detent() -> AudioStreamWAV:
	return _cached("detent", func() -> AudioStreamWAV:
		var s := _silence(0.018)
		_impulse(s, 0.0, 0.30, 0.0022, 4200.0, 17)
		return _wav(s, false))


## A plug going home. Low and blunt: the sleeve bottoming out in a barrel is a mass hitting a
## stop, not a contact closing.
static func plug_seat() -> AudioStreamWAV:
	return _cached("plug", func() -> AudioStreamWAV:
		var s := _silence(0.075)
		_impulse(s, 0.0, 0.48, 0.0060, 1400.0, 19)
		# Three or four audible cycles, not fourteen. At the decay this started with, 92Hz rang
		# for the better part of a fifth of a second, which stops being the sound of a mass
		# hitting a stop and becomes a bass note -- and a bass note at a fixed pitch, played
		# every time any cable goes in, is a tune.
		_impulse(s, 0.0015, 0.42, 0.0160, 110.0, 23)
		return _wav(s, false))


## A fader cap moving in its slot: filtered noise, held while the hand is moving and scaled by
## how fast. Looping, so it can be started and stopped rather than retriggered.
static func fader_slide() -> AudioStreamWAV:
	return _cached("slide", func() -> AudioStreamWAV:
		var s := _noise(0.70, 0.22, 29)
		_lowpass(s, 1600.0)
		_lowpass(s, 1600.0)
		_highpass(s, 180.0)
		_seam(s, 0.030)
		return _wav(s, true))


## The transport's motor, running while the tape is. A mains hum and its first two harmonics,
## plus a little noise for the bearings.
static func reel_motor() -> AudioStreamWAV:
	return _cached("motor", func() -> AudioStreamWAV:
		# 0.40s is exactly twenty cycles of 50Hz, forty of 100 and sixty of 150. A loop length
		# that is NOT a whole number of cycles for every partial in it puts a discontinuity at
		# the seam, and a discontinuity repeating at 2.5Hz is a tick you cannot stop hearing
		# once you have heard it.
		var s := _noise(0.40, 0.030, 31)
		_lowpass(s, 900.0)
		_tone(s, 50.0, 0.085)
		_tone(s, 100.0, 0.042)
		_tone(s, 150.0, 0.018)
		_seam(s, 0.012)
		return _wav(s, true))


## Casters on a hard floor: a low rumble with the wheels' seams ticking through it. Looping,
## held while a piece of furniture is moving and scaled by how fast, the way the fader slide is.
##
## The ticks are what make it a WHEEL rather than wind. A real caster has a moulding seam and a
## flat or two, and it is the irregular knock of those coming round that says "this is rolling"
## rather than "something is hissing". Irregular on purpose: spaced evenly they are a clock.
static func caster_roll() -> AudioStreamWAV:
	return _cached("roll", func() -> AudioStreamWAV:
		var s := _noise(0.80, 0.30, 37)
		_lowpass(s, 420.0)
		_lowpass(s, 420.0)
		_highpass(s, 45.0)
		for at in [0.031, 0.142, 0.219, 0.356, 0.418, 0.547, 0.633, 0.702]:
			_impulse(s, at, 0.10, 0.0040, 260.0, int(at * 1000.0))
		_seam(s, 0.040)
		return _wav(s, true))


## Furniture meeting something it cannot go through. A heavy, short knock -- the cabinet's mass
## arriving at a stop -- with a little rattle of whatever is mounted in it a moment later.
static func gear_bump() -> AudioStreamWAV:
	return _cached("bump", func() -> AudioStreamWAV:
		var s := _silence(0.16)
		_impulse(s, 0.0, 0.60, 0.0180, 85.0, 41)
		_impulse(s, 0.0, 0.30, 0.0040, 900.0, 43)
		_impulse(s, 0.022, 0.12, 0.0060, 2300.0, 47)
		return _wav(s, false))


## Spawn a one-shot at a node and let it clean itself up.
##
## A player per click rather than a pool, because these fire at the rate a hand can move and
## the allocation is nothing next to the audio frame it starts on. The continuous sounds -- the
## slide, the motor -- are owned by the thing making them instead, because they have a state
## and the thing making them is what knows it.
static func play(on: Node3D, stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	if on == null or stream == null or not on.is_inside_tree():
		return
	var player := emitter(stream, volume_db, pitch)
	on.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## A configured, unparented, unstarted player. The one place the spatial settings live, so a
## held sound and a one-shot carry the same room.
static func emitter(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.bus = AudioPorts.bus(AudioPorts.GEAR)
	return player


# --- Synthesis ------------------------------------------------------------------------------
#
# Everything below works on a PackedFloat32Array of mono samples in -1..1 and is deterministic:
# the noise is seeded per sound, so a build is the same build and the suite can assert on it.


static func _cached(key: String, factory: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = factory.call()
	return _cache[key]


static func _silence(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


static func _noise(seconds: float, amplitude: float, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var s := _silence(seconds)
	for i in s.size():
		s[i] = rng.randf_range(-amplitude, amplitude)
	return s


## A struck transient: noise through a resonance, decaying exponentially. Crude as synthesis
## goes and exactly right for this, because everything being modelled here is a small hard
## object being hit once.
static func _impulse(s: PackedFloat32Array, at: float, amplitude: float, decay: float,
		hz: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var start := int(at * RATE)
	var step := TAU * hz / float(RATE)
	for i in range(start, s.size()):
		var t := float(i - start) / float(RATE)
		var env := exp(-t / maxf(decay, 0.00001))
		if env < 0.0008:
			break
		s[i] += amplitude * env * (sin(step * float(i - start)) * 0.72
				+ rng.randf_range(-0.28, 0.28))


## Added, not mixed to a target level: the caller is stacking partials and wants control of the
## balance between them.
static func _tone(s: PackedFloat32Array, hz: float, amplitude: float) -> void:
	var step := TAU * hz / float(RATE)
	for i in s.size():
		s[i] += amplitude * sin(step * float(i))


static func _lowpass(s: PackedFloat32Array, hz: float) -> void:
	var a := 1.0 - exp(-TAU * hz / float(RATE))
	var y := 0.0
	for i in s.size():
		y += a * (s[i] - y)
		s[i] = y


static func _highpass(s: PackedFloat32Array, hz: float) -> void:
	var a := 1.0 - exp(-TAU * hz / float(RATE))
	var y := 0.0
	for i in s.size():
		y += a * (s[i] - y)
		s[i] -= y


## Cross-fade the tail over the head so the loop point is continuous.
##
## Only needed for the noisy part of a sound; a tone whose loop is a whole number of cycles is
## already continuous, and the two sounds here that loop are both noise plus tones. Without
## this the slide clicks once per loop, which is audible as a rhythm underneath a gesture that
## has no rhythm.
static func _seam(s: PackedFloat32Array, seconds: float) -> void:
	var fade := mini(int(seconds * RATE), s.size() / 3)
	if fade <= 1:
		return
	var tail := s.size() - fade
	for i in fade:
		var k := float(i) / float(fade)
		s[i] = s[i] * k + s[tail + i] * (1.0 - k)
	s.resize(tail)


static func _wav(s: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		var v := int(roundf(clampf(s[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = s.size()
	return wav
