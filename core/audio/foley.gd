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
## A rubber duck squeezed (`out`: the air pushed out through the reed) or let go (the air
## drawn back in, softer, lower, breathier). A reed is a buzz, not a whistle: a stack of
## harmonics on a pitch that rises as the squeeze tightens, which is what makes it a squeak
## rather than a beep.
static func squeak(out: bool) -> AudioStreamWAV:
	return _cached("squeak_out" if out else "squeak_in", func() -> AudioStreamWAV:
		var seconds := 0.2 if out else 0.26
		var s := _silence(seconds)
		var from := 1900.0 if out else 1350.0
		var to := 2600.0 if out else 1750.0
		var level := 0.34 if out else 0.2
		var phase := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 31 if out else 37
		for i in s.size():
			var t := float(i) / float(RATE)
			var along := t / seconds
			# Up fast and then holding: a hand closing on rubber.
			var hz := lerpf(from, to, 1.0 - exp(-along * 5.0))
			phase += TAU * hz / float(RATE)
			var env := minf(1.0, t / 0.008) * pow(1.0 - along, 1.6)
			var buzz := sin(phase) + 0.5 * sin(phase * 2.0) + 0.28 * sin(phase * 3.0) + 0.12 * sin(phase * 4.0)
			var breath := rng.randf_range(-1.0, 1.0) * (0.12 if out else 0.35)
			s[i] = level * env * (buzz * 0.55 + breath)
		_lowpass(s, 7000.0)
		return _wav(s, false))


## Something soft and hollow tapped or set down: a rubber toy on a shelf, in a palm.
static func rubber_tap() -> AudioStreamWAV:
	return _cached("rubber_tap", func() -> AudioStreamWAV:
		var s := _silence(0.08)
		_impulse(s, 0.0, 0.4, 0.012, 520.0, 41)
		_impulse(s, 0.0, 0.18, 0.006, 1500.0, 43)
		return _wav(s, false))


## A small, hard rubber ball hitting the floor: a hollow thump that drops in pitch as the ball
## leaves the floor, with the sharp pock of the hit on top.
static func ball_bounce() -> AudioStreamWAV:
	return _cached("ball_bounce", func() -> AudioStreamWAV:
		var seconds := 0.12
		var s := _silence(seconds)
		var phase := 0.0
		for i in s.size():
			var t := float(i) / float(RATE)
			var hz := lerpf(330.0, 190.0, minf(1.0, t / 0.05))
			phase += TAU * hz / float(RATE)
			s[i] = 0.42 * exp(-t / 0.028) * sin(phase)
		_impulse(s, 0.0, 0.3, 0.004, 2300.0, 47)
		_lowpass(s, 6000.0)
		return _wav(s, false))


## Paper leaving a hand: a breathy rush of air, bright, swelling and gone in a third of a
## second.
static func paper_swish() -> AudioStreamWAV:
	return _cached("paper_swish", func() -> AudioStreamWAV:
		var seconds := 0.32
		var s := _noise(seconds, 0.5, 53)
		_highpass(s, 900.0)
		_lowpass(s, 5200.0)
		for i in s.size():
			var t := float(i) / float(RATE) / seconds
			# Up fast, down slow: the arm comes through and the air closes in behind it.
			s[i] *= sin(PI * pow(t, 0.6)) * (1.0 - t)
		return _wav(s, false))


## Folded paper landing: a dry tick and a short scuff, no ring to it at all.
static func paper_tap() -> AudioStreamWAV:
	return _cached("paper_tap", func() -> AudioStreamWAV:
		var s := _noise(0.07, 0.35, 59)
		_highpass(s, 1400.0)
		for i in s.size():
			s[i] *= exp(-float(i) / float(RATE) / 0.014)
		_impulse(s, 0.0, 0.12, 0.003, 3100.0, 61)
		return _wav(s, false))


## How many takes of each hand-percussion sound there are, so a run of hits is not one sample
## said again and again: a shaker played at sixteenths would be a machine gun otherwise.
const TAKES := 4


## A shaker stroke stopping: the beads thrown into the end of the tube, a dense spray of tiny
## clicks over a few tens of milliseconds, all top end. Grains, not a noise burst: a burst is a
## hiss, and the clatter is what says beads.
static func shaker(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("shaker_%d" % take, func() -> AudioStreamWAV:
		var seconds := 0.11
		var s := _silence(seconds)
		var rng := RandomNumberGenerator.new()
		rng.seed = 101 + take * 7
		# Most beads land at once and the rest trail after, thinning out.
		for g in 140:
			var at := pow(rng.randf(), 2.2) * 0.06
			var level := rng.randf_range(0.05, 0.16) * exp(-at / 0.03)
			var start := int(at * RATE)
			var length := int(0.0018 * RATE)
			for i in range(start, mini(start + length, s.size())):
				var t := float(i - start) / float(RATE)
				s[i] += level * exp(-t / 0.0004) * rng.randf_range(-1.0, 1.0)
		_highpass(s, 3200.0)
		_highpass(s, 2400.0)
		_lowpass(s, 12000.0)
		return _wav(s, false))


## Tambourine jingles shaken: pairs of thin metal discs clashing, a bright inharmonic ring over a
## splash, the pairs a few milliseconds apart because no shake moves them all at once.
static func jingle(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("jingle_%d" % take, func() -> AudioStreamWAV:
		return _wav(_jingles(0.32, take, 0.0), false))


## The tambourine's head struck by a hand: a skin's short thump, and the jingles thrown with it.
static func tambourine_hit(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("tambourine_hit_%d" % take, func() -> AudioStreamWAV:
		var s := _jingles(0.34, take + 20, 0.004)
		var phase := 0.0
		for i in s.size():
			var t := float(i) / float(RATE)
			phase += TAU * lerpf(210.0, 150.0, minf(1.0, t / 0.04)) / float(RATE)
			s[i] += 0.32 * exp(-t / 0.035) * sin(phase)
		_impulse(s, 0.0, 0.18, 0.003, 1900.0, 211 + take)
		return _wav(s, false))


## A cowbell struck, or swung onto its beater: two inharmonic partials rung by hand (the same
## mode-loop shape as `_jingles`, not a struck impulse -- a cast bell's walls ring at a few
## unrelated pitches, not one), with the beater's own click on top.
static func cowbell(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("cowbell_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.28)
		var rng := RandomNumberGenerator.new()
		rng.seed = 711 + take * 13
		for mode in [[562.0, 0.14, 0.28], [845.0, 0.09, 0.2]]:
			var hz: float = mode[0] * rng.randf_range(0.98, 1.02)
			var decay: float = mode[1]
			var level: float = mode[2]
			var step := TAU * hz / float(RATE)
			for i in s.size():
				var t := float(i) / float(RATE)
				var env := exp(-t / decay)
				if env < 0.001:
					break
				s[i] += level * env * sin(step * float(i))
		_impulse(s, 0.0, 0.25, 0.003, 2600.0, 701 + take)
		_lowpass(s, 7000.0)
		return _wav(s, false))


## A triangle struck with its beater: several high, closely-spaced inharmonic partials ringing
## long and beating against each other -- the shimmer a bent steel rod's two corners give it,
## not one clean pitch -- over a bright, brief click where the beater lands. The muted voice
## (`CowbellItem`-style second voice, here the choked/mute triangle) gets no separate shape of
## its own, same as every other spilled instrument's second voice: `InstrumentItem.VOICE_PITCH`
## already pitches it down and `pitch()` already records it under its own GM note.
static func triangle(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("triangle_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(1.6)
		var rng := RandomNumberGenerator.new()
		rng.seed = 773 + take * 17
		for mode in [[3800.0, 1.1, 0.18], [4650.0, 0.95, 0.15], [5920.0, 0.7, 0.1], [7400.0, 0.5, 0.07]]:
			var hz: float = mode[0] * rng.randf_range(0.985, 1.015)
			var decay: float = mode[1]
			var level: float = mode[2]
			var step := TAU * hz / float(RATE)
			for i in s.size():
				var t := float(i) / float(RATE)
				var env := exp(-t / decay)
				if env < 0.001:
					break
				s[i] += level * env * sin(step * float(i))
		_impulse(s, 0.0, 0.3, 0.002, 6000.0, 761 + take)
		_highpass(s, 1800.0)
		return _wav(s, false))


## A woodblock knocked, struck or shaken to a stop: one dry resonance and the duller body under
## it, no ring at all -- a solid block, not a shell.
static func woodblock(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("woodblock_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.09)
		var rng := RandomNumberGenerator.new()
		rng.seed = 719 + take * 11
		_impulse(s, 0.0, 0.55, 0.011, 1750.0 * rng.randf_range(0.97, 1.03), 721 + take)
		_impulse(s, 0.0, 0.2, 0.02, 920.0, 731 + take)
		_highpass(s, 300.0)
		return _wav(s, false))


## Two claves struck together: sharper and shorter than the woodblock's own knock, with a
## higher, almost-pitched ring riding the impulse for a beat before it dies -- what a dense
## hardwood stick gives back that a hollow block does not.
static func claves(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("claves_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.12)
		var rng := RandomNumberGenerator.new()
		rng.seed = 787 + take * 13
		_impulse(s, 0.0, 0.5, 0.004, 2700.0 * rng.randf_range(0.97, 1.03), 751 + take)
		var hz := 2450.0 * rng.randf_range(0.98, 1.02)
		var step := TAU * hz / float(RATE)
		for i in s.size():
			var t := float(i) / float(RATE)
			var env := exp(-t / 0.045)
			if env < 0.001:
				break
			s[i] += 0.14 * env * sin(step * float(i))
		_highpass(s, 1200.0)
		return _wav(s, false))


## A drum pad hit: `tambourine_hit`'s swept sine, lower and longer -- a tom's skin dropping in
## pitch as it is struck -- with the beater's click on top.
static func pad(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("pad_%d" % take, func() -> AudioStreamWAV:
		var seconds := 0.32
		var s := _silence(seconds)
		var phase := 0.0
		for i in s.size():
			var t := float(i) / float(RATE)
			phase += TAU * lerpf(190.0, 105.0, minf(1.0, t / 0.05)) / float(RATE)
			s[i] += 0.42 * exp(-t / 0.13) * sin(phase)
		_impulse(s, 0.0, 0.12, 0.003, 1400.0, 741 + take)
		_lowpass(s, 4500.0)
		return _wav(s, false))


## Clay chips on clay chips, one landing: a short bright knock, the dense edge of one disc on
## the face of another, with the faint ring a clay composite chip has and a plastic one does not.
static func chip_clack(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("chip_clack_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.07)
		_chip(s, 0.0, 1.0, 301 + take)
		_highpass(s, 900.0)
		return _wav(s, false))


## A riffle: the two halves of a stack pushed into each other, chip falling on chip from
## alternate sides, quick at first and quicker toward the end, and the stack settling.
static func chip_riffle(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("chip_riffle_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.62)
		var rng := RandomNumberGenerator.new()
		rng.seed = 331 + take * 13
		var at := 0.12
		for i in 11:
			_chip(s, at, rng.randf_range(0.45, 0.75), 341 + take * 29 + i)
			at += lerpf(0.042, 0.022, float(i) / 10.0) * rng.randf_range(0.85, 1.15)
		# Squared up: the whole stack tapped down once.
		_chip(s, at + 0.05, 0.9, 371 + take)
		_impulse(s, at + 0.05, 0.12, 0.012, 420.0, 377 + take)
		_highpass(s, 600.0)
		return _wav(s, false))


## A dart going into a sisal board: the steel point's tick, the thud of the barrel's weight
## stopping in packed fibre, and the shaft's short shiver after.
static func dart_thunk(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("dart_thunk_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.16)
		var rng := RandomNumberGenerator.new()
		rng.seed = 401 + take * 17
		_impulse(s, 0.0, 0.22, 0.0015, rng.randf_range(3800.0, 4400.0), 403 + take)
		_impulse(s, 0.0008, 0.55, 0.014, rng.randf_range(150.0, 185.0), 405 + take)
		_impulse(s, 0.0008, 0.25, 0.008, rng.randf_range(420.0, 520.0), 407 + take)
		# The flight and shaft quivering: a buzz that dies fast.
		var phase := 0.0
		var buzz := rng.randf_range(95.0, 120.0)
		for i in s.size():
			var t := float(i) / float(RATE)
			phase += TAU * buzz / float(RATE)
			s[i] += 0.05 * exp(-t / 0.03) * signf(sin(phase)) * clampf(t / 0.004, 0.0, 1.0)
		_lowpass(s, 5200.0)
		return _wav(s, false))


## A dart that missed, landing on something hard: a light metallic tick and a skitter.
static func dart_clatter(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("dart_clatter_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.12)
		var rng := RandomNumberGenerator.new()
		rng.seed = 431 + take * 19
		var at := 0.0
		for i in 3:
			_impulse(s, at, 0.3 / (i + 1), 0.004, rng.randf_range(2800.0, 3600.0), 433 + take * 7 + i)
			_impulse(s, at, 0.12 / (i + 1), 0.01, rng.randf_range(900.0, 1200.0), 437 + take * 7 + i)
			at += rng.randf_range(0.025, 0.04)
		_highpass(s, 500.0)
		return _wav(s, false))


## A ball dropping through a cord net: the swish, a breath of noise that rises and falls as the
## cords drag over it, bright at the start and darker as it slows.
static func net_swish(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("net_swish_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.32, 1.0, 461 + take * 23)
		var rng := RandomNumberGenerator.new()
		rng.seed = 463 + take * 29
		var peak := rng.randf_range(0.07, 0.1)
		for i in s.size():
			var t := float(i) / float(RATE)
			# Up fast as it goes in, and away as it leaves the bottom of the net.
			var env := clampf(t / peak, 0.0, 1.0) * exp(-maxf(0.0, t - peak) / 0.07)
			s[i] *= 0.3 * env
		_highpass(s, 900.0)
		_lowpass(s, 5500.0)
		return _wav(s, false))


## A ball off a hoop's steel rim: a ring, high and short, with the clank of the bracket under it.
static func rim_clang(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("rim_clang_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.5)
		var rng := RandomNumberGenerator.new()
		rng.seed = 467 + take * 31
		var ring := rng.randf_range(820.0, 900.0)
		# A steel ring's partials are not harmonic: struck, it rings at a few unrelated pitches.
		_impulse(s, 0.0, 0.3, 0.16, ring, 469 + take)
		_impulse(s, 0.0, 0.16, 0.1, ring * 2.76, 471 + take)
		_impulse(s, 0.0, 0.08, 0.05, ring * 5.4, 473 + take)
		_impulse(s, 0.0, 0.35, 0.012, rng.randf_range(260.0, 320.0), 475 + take)
		return _wav(s, false))


## A ball off a hoop's backboard: a flat plastic smack, and the sheet's short boom on its frame.
static func board_thud(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("board_thud_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 479 + take * 37
		_impulse(s, 0.0, 0.45, 0.006, rng.randf_range(1400.0, 1700.0), 481 + take)
		_impulse(s, 0.0, 0.5, 0.04, rng.randf_range(110.0, 140.0), 483 + take)
		_impulse(s, 0.002, 0.2, 0.025, rng.randf_range(330.0, 380.0), 485 + take)
		_lowpass(s, 4000.0)
		return _wav(s, false))


## Something soft and full landing: a beanbag, a foam ball. A dull low thump and the rustle of
## what is inside it settling, no ring and no bounce.
static func soft_thud(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("soft_thud_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.09, 0.22, 503 + take)
		_lowpass(s, 1800.0)
		for i in s.size():
			s[i] *= exp(-float(i) / float(RATE) / 0.022)
		var rng := RandomNumberGenerator.new()
		rng.seed = 505 + take * 43
		_impulse(s, 0.0, 0.5, 0.018, rng.randf_range(95.0, 125.0), 507 + take)
		_lowpass(s, 2500.0)
		return _wav(s, false))


## A snowball landing: the crunch of packed snow giving way, a burst of grains, and the soft
## thump under it.
static func snow_crunch(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("snow_crunch_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.16)
		var rng := RandomNumberGenerator.new()
		rng.seed = 509 + take * 47
		for k in 26:
			var at := 0.07 * pow(rng.randf(), 1.8)
			_impulse(s, at, rng.randf_range(0.04, 0.12) * (1.0 - at / 0.08), 0.0025,
					rng.randf_range(1800.0, 4200.0), 511 + take * 31 + k)
		_impulse(s, 0.0, 0.35, 0.02, rng.randf_range(90.0, 120.0), 513 + take)
		_lowpass(s, 6000.0)
		return _wav(s, false))


## A beach ball bopping off the floor: the boom of a big thin vinyl drum, low and hollow, and
## the slap of the skin.
static func beach_bop(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("beach_bop_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.22)
		var rng := RandomNumberGenerator.new()
		rng.seed = 517 + take * 53
		var phase := 0.0
		var from := rng.randf_range(150.0, 175.0)
		for i in s.size():
			var t := float(i) / float(RATE)
			phase += TAU * lerpf(from, from * 0.7, minf(1.0, t / 0.12)) / float(RATE)
			s[i] = 0.45 * exp(-t / 0.06) * sin(phase)
		_impulse(s, 0.0, 0.2, 0.004, rng.randf_range(900.0, 1100.0), 519 + take)
		_lowpass(s, 3000.0)
		return _wav(s, false))


## Two steel balls of a Newton's cradle meeting: a hard, bright tick and the short ring of the
## steel after it. The sound the toy is for.
static func cradle_click(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("cradle_click_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.09)
		var rng := RandomNumberGenerator.new()
		rng.seed = 491 + take * 41
		_impulse(s, 0.0, 0.5, 0.0012, rng.randf_range(3300.0, 3600.0), 493 + take)
		_impulse(s, 0.0, 0.18, 0.012, rng.randf_range(6900.0, 7300.0), 495 + take)
		_impulse(s, 0.0, 0.08, 0.02, rng.randf_range(10200.0, 10800.0), 497 + take)
		_highpass(s, 1200.0)
		return _wav(s, false))


## A yo-yo asleep at the end of its string: the whirr of the axle in the loop, a hum with a
## rasp of string in it, falling a little as it slows.
static func yoyo_spin(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("yoyo_spin_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.9, 0.12, 499 + take * 43)
		_lowpass(s, 2400.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 501 + take * 47
		var hz := rng.randf_range(190.0, 215.0)
		var phase := 0.0
		for i in s.size():
			var t := float(i) / float(RATE)
			phase += TAU * hz * (1.0 - 0.18 * t) / float(RATE)
			var env := clampf(t / 0.05, 0.0, 1.0) * clampf((0.9 - t) / 0.25, 0.0, 1.0)
			s[i] = (s[i] * (0.6 + 0.4 * sin(phase * 0.5)) + 0.07 * sin(phase) + 0.03 * sin(phase * 2.0)) * env
		_highpass(s, 120.0)
		return _wav(s, false))


## A yo-yo back in the hand: the hollow plastic clack of it landing in the palm.
static func yoyo_catch(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("yoyo_catch_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.1)
		var rng := RandomNumberGenerator.new()
		rng.seed = 503 + take * 53
		_impulse(s, 0.0, 0.45, 0.004, rng.randf_range(1500.0, 1800.0), 505 + take)
		_impulse(s, 0.0, 0.35, 0.02, rng.randf_range(380.0, 440.0), 507 + take)
		_lowpass(s, 6000.0)
		return _wav(s, false))


## A little electric plane's motor and propeller, looping while it runs: the buzz of a small
## motor and its harmonics, chopped by the blades going round, with air through it. Played faster
## as the plane goes faster. 0.25s: forty cycles of 160Hz and eight of the 32Hz chop, so the seam
## is clean.
static func rc_motor() -> AudioStreamWAV:
	return _cached("rc_motor", func() -> AudioStreamWAV:
		var s := _noise(0.25, 0.05, 509)
		_lowpass(s, 3000.0)
		for i in s.size():
			var t := float(i) / float(RATE)
			var buzz := 0.0
			for h in range(1, 7):
				buzz += sin(TAU * 160.0 * h * t) / float(h)
			var chop := 0.7 + 0.3 * sin(TAU * 32.0 * t)
			s[i] = (s[i] + 0.06 * buzz) * chop
		_highpass(s, 90.0)
		_seam(s, 0.01)
		return _wav(s, true))


## A foam plane going into something: the crunch and the plastic clatter of the prop and the
## undercarriage after it.
static func rc_crash(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("rc_crash_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.28, 0.3, 511 + take * 59)
		for i in s.size():
			s[i] *= exp(-float(i) / float(RATE) / 0.05)
		_lowpass(s, 2600.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 513 + take * 61
		_impulse(s, 0.0, 0.5, 0.03, rng.randf_range(120.0, 150.0), 515 + take)
		var at := 0.03
		for i in 4:
			_impulse(s, at, 0.22 / (i + 1), 0.006, rng.randf_range(1800.0, 2600.0), 517 + take * 7 + i)
			at += rng.randf_range(0.03, 0.06)
		return _wav(s, false))


## Its little wheels meeting the floor: a light double bump, and the patter of them rolling.
static func rc_touchdown(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("rc_touchdown_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.35, 0.05, 519 + take * 67)
		for i in s.size():
			var t := float(i) / float(RATE)
			s[i] *= clampf(t / 0.02, 0.0, 1.0) * exp(-t / 0.15)
		_lowpass(s, 900.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 521 + take * 71
		_impulse(s, 0.0, 0.3, 0.012, rng.randf_range(260.0, 320.0), 523 + take)
		_impulse(s, rng.randf_range(0.05, 0.08), 0.2, 0.012, rng.randf_range(260.0, 320.0), 525 + take)
		return _wav(s, false))


static func _chip(s: PackedFloat32Array, at: float, level: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_impulse(s, at, 0.32 * level, 0.0035, rng.randf_range(2300.0, 2700.0), seed_value)
	_impulse(s, at, 0.14 * level, 0.006, rng.randf_range(4100.0, 4600.0), seed_value + 1)
	_impulse(s, at + 0.0004, 0.05 * level, 0.018, rng.randf_range(6900.0, 7400.0), seed_value + 2)


## A riffle shuffle: two halves of a deck let go of under the thumbs, card falling on card fast
## enough to be a purr, and then the bridge -- the deck arched and let fall square.
static func card_riffle(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("card_riffle_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.85)
		var rng := RandomNumberGenerator.new()
		rng.seed = 401 + take * 17
		var at := 0.08
		for i in 40:
			_flick(s, at, rng.randf_range(0.5, 1.0) * lerpf(0.7, 1.0, float(i) / 39.0), rng)
			at += lerpf(0.011, 0.007, float(i) / 39.0) * rng.randf_range(0.7, 1.3)
		# The bridge: a soft rush of all of them at once, then the deck landing.
		var start := int((at + 0.06) * RATE)
		for i in range(start, mini(start + int(0.09 * RATE), s.size())):
			var t := float(i - start) / float(RATE)
			s[i] += 0.07 * sin(PI * t / 0.09) * rng.randf_range(-1.0, 1.0)
		_impulse(s, at + 0.16, 0.16, 0.01, 260.0, 409 + take)
		_highpass(s, 500.0)
		_lowpass(s, 9000.0)
		return _wav(s, false))


## Cards fanned or squared: a quick slide of card over card, a soft papery sweep.
static func card_sweep(take: int) -> AudioStreamWAV:
	take = posmod(take, TAKES)
	return _cached("card_sweep_%d" % take, func() -> AudioStreamWAV:
		var s := _silence(0.3)
		var rng := RandomNumberGenerator.new()
		rng.seed = 451 + take * 7
		var at := 0.01
		for i in 7:
			_flick(s, at, rng.randf_range(0.25, 0.45), rng)
			at += rng.randf_range(0.022, 0.032)
		for i in s.size():
			var t := float(i) / float(RATE)
			s[i] += 0.025 * sin(PI * minf(t / 0.22, 1.0)) * rng.randf_range(-1.0, 1.0)
		_highpass(s, 1200.0)
		_lowpass(s, 8000.0)
		return _wav(s, false))


## The Tour case bursting open: a crack of splintering wood, the chain dropping loose and
## rattling, then a bright three-note stinger -- the moment a run starts, loud enough that
## everyone at the hit's end of the room hears it happen.
static func tour_stinger() -> AudioStreamWAV:
	return _cached("tour_stinger", func() -> AudioStreamWAV:
		var s := _silence(0.9)
		var rng := RandomNumberGenerator.new()
		rng.seed = 601
		for i in int(0.08 * RATE):
			var t := float(i) / float(RATE)
			s[i] += 0.5 * exp(-t / 0.03) * rng.randf_range(-1.0, 1.0)
		_impulse(s, 0.0, 0.4, 0.05, 90.0, 603)
		for k in 10:
			var at: float = 0.04 + rng.randf_range(0.0, 0.22)
			_impulse(s, at, rng.randf_range(0.05, 0.12), 0.01, rng.randf_range(1800.0, 3200.0), 607 + k)
		# A bright rising stinger: G4, C5, E5, each a hair after the last.
		for note_i in range(3):
			var hz: float = [392.0, 523.25, 659.25][note_i]
			var at: float = 0.12 + note_i * 0.07
			var start := int(at * RATE)
			for i in range(start, s.size()):
				var t := float(i - start) / float(RATE)
				var env := exp(-t / 0.35)
				if env < 0.001:
					break
				s[i] += 0.1 * env * sin(TAU * hz * t)
		_lowpass(s, 9000.0)
		return _wav(s, false))


## A run's own end, won: bigger than `tour_stinger`'s three notes -- a four-note rising run
## (C5 E5 G5 C6), each voiced with a fifth stacked on top of it so it reads as a room cheering
## back rather than one horn, the last note held rather than struck and gone.
static func win_fanfare() -> AudioStreamWAV:
	return _cached("win_fanfare", func() -> AudioStreamWAV:
		var s := _silence(1.3)
		var rng := RandomNumberGenerator.new()
		rng.seed = 821
		var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
		for note_i in notes.size():
			var hz: float = notes[note_i]
			var at: float = 0.05 + note_i * 0.09
			var start := int(at * RATE)
			var sustain := note_i == notes.size() - 1
			for i in range(start, s.size()):
				var t := float(i - start) / float(RATE)
				var decay := 0.9 if sustain else 0.22
				var env := exp(-t / decay)
				if env < 0.001:
					break
				s[i] += 0.09 * env * (sin(TAU * hz * t) + 0.6 * sin(TAU * hz * 1.5 * t))
		for k in 8:
			var at: float = 0.02 + rng.randf_range(0.0, 0.1)
			_impulse(s, at, rng.randf_range(0.05, 0.1), 0.02, rng.randf_range(2000.0, 3600.0), 827 + k)
		_lowpass(s, 10000.0)
		return _wav(s, false))


## The other half of the same moment, lost: two notes falling (G4, D4) instead of four rising,
## over almost as soon as they start -- the air coming out of the room instead of a cheer.
static func loss_sting() -> AudioStreamWAV:
	return _cached("loss_sting", func() -> AudioStreamWAV:
		var s := _silence(0.6)
		var notes: Array[float] = [392.0, 293.66]
		for note_i in notes.size():
			var hz: float = notes[note_i]
			var at: float = 0.03 + note_i * 0.12
			var start := int(at * RATE)
			for i in range(start, s.size()):
				var t := float(i - start) / float(RATE)
				var env := exp(-t / 0.18)
				if env < 0.001:
					break
				s[i] += 0.11 * env * sin(TAU * hz * t)
		_lowpass(s, 4000.0)
		return _wav(s, false))


## An instrument falling out of the case, tossed onto the floor: the lid's own low thump and a
## rattle of whatever else is in there, with none of `tour_stinger`'s three-note flourish --
## that moment already has its own sound, the burst itself; this one is smaller and happens
## several times a run.
static func case_toss() -> AudioStreamWAV:
	return _cached("case_toss", func() -> AudioStreamWAV:
		var s := _silence(0.35)
		var rng := RandomNumberGenerator.new()
		rng.seed = 751
		_impulse(s, 0.0, 0.35, 0.04, 120.0, 751)
		for k in 6:
			var at: float = 0.02 + rng.randf_range(0.0, 0.18)
			_impulse(s, at, rng.randf_range(0.05, 0.12), 0.01, rng.randf_range(1500.0, 2800.0), 753 + k)
		_lowpass(s, 8000.0)
		return _wav(s, false))


## A chaos event's telegraph (core/tour/tour_chaos.gd): the mains browning out, a couple of
## seconds of warning. A 50 Hz/100 Hz hum swelling under its own fade envelope, with three bright
## crackles of noise riding on top of it -- something in the room about to go wrong, not yet
## having gone wrong.
static func chaos_warning() -> AudioStreamWAV:
	return _cached("chaos_warning", func() -> AudioStreamWAV:
		var s := _silence(0.7)
		for i in s.size():
			var t := float(i) / float(RATE)
			var env := clampf(t / 0.5, 0.0, 1.0) * exp(-maxf(t - 0.5, 0.0) / 0.15)
			s[i] += env * (0.1 * sin(TAU * 50.0 * t) + 0.07 * sin(TAU * 100.0 * t))
		var rng := RandomNumberGenerator.new()
		rng.seed = 911
		for k in 3:
			var at: float = 0.15 + float(k) * 0.18
			_impulse(s, at, 0.08, 0.02, rng.randf_range(2000.0, 3000.0), 913 + k)
		_lowpass(s, 6000.0)
		return _wav(s, false))


## A chaos event's strike: the breaker going, and a short clatter of whatever that just knocked
## loose. Loud and sudden on purpose -- the telegraph was the warning, this is the thing itself.
static func chaos_strike() -> AudioStreamWAV:
	return _cached("chaos_strike", func() -> AudioStreamWAV:
		var s := _silence(0.45)
		_impulse(s, 0.0, 0.5, 0.06, 80.0, 929)
		var rng := RandomNumberGenerator.new()
		rng.seed = 937
		for k in 5:
			var at: float = 0.02 + rng.randf_range(0.0, 0.18)
			_impulse(s, at, rng.randf_range(0.08, 0.16), 0.015, rng.randf_range(1500.0, 3000.0), 941 + k)
		return _wav(s, false))


## `crowd_throws`'s telegraph, from the house rather than the desk: a low rumble of bodies
## shifting, wobbling in volume the way a crowd actually does, with a couple of dull thuds
## riding under it -- things already landing on the floor before the fader does.
static func crowd_rumble(take: int) -> AudioStreamWAV:
	return _cached("crowd_rumble_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.9, 0.22, 967 + take * 7)
		_highpass(s, 250.0)
		_lowpass(s, 1400.0)
		for i in s.size():
			var t := float(i) / float(RATE)
			s[i] *= 0.6 + 0.4 * sin(TAU * 6.0 * t)
		var rng := RandomNumberGenerator.new()
		rng.seed = 971 + take * 5
		_impulse(s, 0.25 + rng.randf_range(0.0, 0.15), 0.3, 0.05, 180.0, 977 + take)
		_impulse(s, 0.55 + rng.randf_range(0.0, 0.15), 0.26, 0.05, 180.0, 983 + take)
		return _wav(s, false))


## The crowd approving: a flaw the room could hear just got put right. Brighter and shorter than
## `crowd_rumble`'s low mutter of trouble -- filtered noise (a lot of voices at once) swelling
## over the first fifth of a second and falling away by the end, with three short upward whoops
## riding the swell (noise swept up in pitch, the shape an excited shout keeps even blurred into
## a crowd).
static func crowd_cheer(take: int) -> AudioStreamWAV:
	return _cached("crowd_cheer_%d" % take, func() -> AudioStreamWAV:
		var s := _noise(0.55, 0.5, 1013 + take * 11)
		_highpass(s, 500.0)
		_lowpass(s, 3200.0)
		for i in s.size():
			var t := float(i) / float(RATE)
			s[i] *= sin(PI * minf(t / 0.5, 1.0)) * (0.7 + 0.3 * sin(TAU * 9.0 * t))
		var rng := RandomNumberGenerator.new()
		rng.seed = 1019 + take * 7
		for k in 3:
			var at: float = 0.03 + float(k) * 0.14 + rng.randf_range(0.0, 0.04)
			var start := int(at * RATE)
			var dur := 0.1
			for i in range(start, mini(start + int(dur * RATE), s.size())):
				var lt := float(i - start) / dur
				var hz := lerpf(500.0, 1400.0, lt)
				var env := sin(PI * lt)
				s[i] += 0.22 * env * sin(TAU * hz * float(i - start) / float(RATE))
		return _wav(s, false))


## One card's edge flicked off a thumb: a few milliseconds of bright paper.
static func _flick(s: PackedFloat32Array, at: float, level: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var tone := TAU * rng.randf_range(1800.0, 3200.0) / float(RATE)
	for i in range(start, mini(start + int(0.006 * RATE), s.size())):
		var t := float(i - start) / float(RATE)
		var env := exp(-t / 0.0013)
		s[i] += level * env * (0.09 * rng.randf_range(-1.0, 1.0) + 0.05 * sin(tone * float(i - start)))


static func _jingles(seconds: float, take: int, after: float) -> PackedFloat32Array:
	var s := _silence(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 151 + take * 11
	for pair in 5:
		var at := after + rng.randf_range(0.0, 0.009)
		var start := int(at * RATE)
		# A thin disc's modes: inharmonic, high, each its own decay; detuned pair to pair.
		for mode in [[3150.0, 0.16, 0.06], [4870.0, 0.12, 0.1], [6720.0, 0.1, 0.09], [8390.0, 0.07, 0.08],
				[10480.0, 0.05, 0.07]]:
			var hz: float = mode[0] * rng.randf_range(0.95, 1.05)
			var decay: float = mode[1] * rng.randf_range(0.8, 1.2)
			var level: float = mode[2] * rng.randf_range(0.7, 1.0)
			var step := TAU * hz / float(RATE)
			for i in range(start, s.size()):
				var t := float(i - start) / float(RATE)
				var env := exp(-t / decay)
				if env < 0.001:
					break
				s[i] += level * env * sin(step * float(i - start))
		# The clash itself: a few milliseconds of bright noise.
		for i in range(start, mini(start + int(0.012 * RATE), s.size())):
			var t := float(i - start) / float(RATE)
			s[i] += 0.12 * exp(-t / 0.0025) * rng.randf_range(-1.0, 1.0)
	_highpass(s, 1800.0)
	return s


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
