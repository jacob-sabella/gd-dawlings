class_name Wobble
extends RefCounted

## Bend and wobble by tilting (docs/spatial_loop.md part two, slice 15; idea #37): one playing
## hand's roll, turned into the player's pitch wheel while a note it plays sounds.
##
## One per playing hand on each instrument that bends: the keytar's neck hand, the harp's plucking
## hand, the fingertips' own hand, and on a desktop the mouse over the plain keys (MouseInteractor).
## Each physics frame `step` reads its hand's `tilt_angles()` (a bare hand's palm, a controller's
## aim, the mouse's wiggle), and while one of its `sources` owns the player's wheel
## (GuestMidi.wheel_source) it sends one bend through GuestMidi.control with that source, at most
## SENDS_A_SECOND times a second, and only when it has changed. A wheel the hand does not own is
## left alone: the wheel is the newest held note's (docs/spatial_loop.md, "A player has one pitch
## wheel"), and GuestMidi puts it back to rest at the player's last note-off, here and for
## everyone, so nothing here ever sends a rest.
##
## The bend is measured from where the note began: the roll at the moment the source took the
## wheel (its first note's press, or the first after every note let go: GuestMidi.rests), wrapped
## to half a turn either way, as `d` degrees, and bends
## sign(d) * clamp((|d| / TIP - DEAD) / (1 - DEAD), 0, 1) * BEND_MOST semitones (`bend_for`). So a
## hand held tilted before it plays bends nothing, a bare hand palm down and a controller thumb
## up bend alike, and a hand plucking palm sideways bends either way from there.
##
## The wobble is the hand's own shake, not an LFO: the roll band-passed between SHAKE_LOW and
## SHAKE_HIGH (two high-pass steps and a low-pass), so a slow drift is not vibrato and a tremble
## is; past SHAKE_FROM degrees it is vibrato up to VIBRATO_MOST semitones at SHAKE_FULL. The bend
## is read from the roll less that shake, so the shake does not also bend.
##
## "Tilt bends" off (GuestMidi.tilt_bends) and the tilt counts for nothing, but a bend wheel the
## hand holds (`Interactor.bend_wheel`, the desktop's Alt-drag) still bends: that is meant.
##
## With `sending` off it reads the hand and sends nothing: the theremin adds its `semitones` to its
## own glide and sends one bend for both, since a player has one wheel.

## A tilt this far (degrees) from where the note began is the most it bends.
const TIP := 45.0
## The dead zone, as a share of TIP: inside it (3.6 degrees) a hand's roll bends nothing.
const DEAD := 0.08
## The most a bend goes, either way: the keys' bend range (DawKitTine.BEND_SEMITONES).
const BEND_MOST := DawKitTine.BEND_SEMITONES
## The shake that is vibrato, between these (Hz).
const SHAKE_LOW := 3.0
const SHAKE_HIGH := 8.0
## A shake smaller than this (degrees) is nothing, and this one is the most vibrato.
const SHAKE_FROM := 0.75
const SHAKE_FULL := 6.0
## The most the vibrato adds, either way (semitones).
const VIBRATO_MOST := 0.4
## The most bends a second it sends.
const SENDS_A_SECOND := 60.0
## A frame's slack on that, so a send falling due a hair after this frame goes on it.
const SEND_SLACK := 0.002

## Where the bend is played: this player's keys.
var keys: GuestMidi = null
## What it bends for: the sources (GuestMidi.note_on's) whose notes this hand plays.
var sources: Array = []
## The hand: an Interactor (`tilt_angles`, `bend_wheel`) or a bare hand's HandGestures
## (`angles`). Another hand put here measures from its own roll at its next step.
var hand: Object = null:
	set(v):
		if v != hand:
			_engaged = null
		hand = v
## Whether the hand's tilt bends at all here: off, only its bend wheel does (the plain keys').
var tilts := true
## Whether it sends the bend itself. Off, it only reads the hand: what owns it adds `semitones` to a
## bend of its own and sends the sum as one (the theremin, whose glide is the wheel already:
## Theremin, docs/spatial_loop.md part two, slice 50).
var sending := true
## Which of an Interactor's tilt angles is read as its roll: 0 its roll (`tilt_angles().x`), 1 its
## pitch, up and down (`.y`). The theremin's desk reads the cursor's up and down, since across its
## rule is the pitch itself (Theremin).
var axis := 0

## The last frame's bend, vibrato and their sum with the hand's bend wheel (semitones).
var bend := 0.0
var vibrato := 0.0
var semitones := 0.0
## How many bends it has sent: for the suite.
var sends := 0

## The source that had the wheel when it last stepped, null for none (`step`).
var _engaged: Variant = null
## The roll the note began at (radians), and the last read roll, held while the hand is not read.
var _start := 0.0
var _roll := 0.0
## The band-pass's state: the two high-pass steps' last in and out, and the low-pass's out.
var _hp_in := 0.0
var _hp_out := 0.0
var _hp2_in := 0.0
var _hp2_out := 0.0
var _lp_out := 0.0
## GuestMidi.rests when it began: one on since means every note let go in between (a string
## plucked again, a key struck again), and the next note is measured from where it begins.
var _rests := 0
## The last value sent (the wheel's 14 bits, less 8192), and the seconds since.
var _sent := 0
var _since := INF


func _init(on_keys: GuestMidi = null, for_sources: Array = [], by: Object = null) -> void:
	keys = on_keys
	sources = for_sources
	hand = by


## The bend a roll of `degrees` from where the note began gives, in semitones.
static func bend_for(degrees: float) -> float:
	var reach := clampf((absf(degrees) / TIP - DEAD) / (1.0 - DEAD), 0.0, 1.0)
	return signf(degrees) * reach * BEND_MOST


## A bend of `st` semitones as the wheel's value, -8192..8191.
static func value_of(st: float) -> int:
	return clampi(roundi(st / BEND_MOST * 8192.0), -8192, 8191)


## A bend as the wheel's value, back in semitones.
static func semitones_of(value: int) -> float:
	return value / 8192.0 * BEND_MOST


## The bend in words, for what shows it (the keytar's tag, the glove's letters): `+1.3`, or ""
## for one too small to see.
static func words(st: float) -> String:
	return "%+.1f" % st if absf(st) >= 0.05 else ""


## A hand's roll now (radians, unclamped), NAN when there is nothing to read; `axis` 1 reads an
## Interactor's tilt up and down instead (`axis`).
static func roll_of(by: Variant, axis_ := 0) -> float:
	if by == null or not is_instance_valid(by):
		return NAN
	if by is Interactor:
		var a := (by as Interactor).tilt_angles()
		return a.y if axis_ == 1 else a.x
	if by is HandGestures:
		var g := by as HandGestures
		return g.angles.x if g.tracked else NAN
	return NAN


## Whether it is bending now: a source of its own has the wheel.
func engaged() -> bool:
	return _engaged != null


## One physics frame, `delta` seconds on, at song position `at` (NAN for now): the hand read, and
## the bend sent if one of `sources` owns the wheel and it is due. Whether it sent one.
func step(delta: float, at := NAN) -> bool:
	var owner: Variant = keys.wheel_source() if keys != null and is_instance_valid(keys) else null
	if owner == null or not sources.has(owner):
		_let_go()
		return false
	var alive := hand != null and is_instance_valid(hand)
	var roll := roll_of(hand, axis) if alive else NAN
	if is_nan(roll):
		roll = _roll
	_roll = roll
	if _engaged != owner or keys.rests != _rests:
		# The note began: its roll is where the bend is measured from.
		_engaged = owner
		_rests = keys.rests
		_start = roll
		_hp_in = 0.0
		_hp_out = 0.0
		_hp2_in = 0.0
		_hp2_out = 0.0
		_lp_out = 0.0
		_sent = 0
		_since = INF
	var d := rad_to_deg(wrapf(roll - _start, -PI, PI))
	var shake := _band(d, delta)
	var tilting := tilts and (keys.tilt_bends if keys != null else true)
	bend = bend_for(d - shake) if tilting else 0.0
	vibrato = _vibrato_for(shake) if tilting else 0.0
	var wheel := (hand as Interactor).bend_wheel() if alive and hand is Interactor else 0.0
	semitones = clampf(bend + vibrato + wheel, -BEND_MOST, BEND_MOST)
	if not sending:
		return false
	_since += delta
	var value := value_of(semitones)
	if value == _sent or _since < 1.0 / SENDS_A_SECOND - SEND_SLACK:
		return false
	_sent = value
	_since = 0.0
	sends += 1
	keys.control(DawKitClip.PITCH_BEND, value, owner, at)
	return true


## Not bending: forgotten, so the next note measures from where it begins.
func _let_go() -> void:
	_engaged = null
	bend = 0.0
	vibrato = 0.0
	semitones = 0.0


## The roll's shake, `d` degrees band-passed SHAKE_LOW..SHAKE_HIGH: two one-pole high-pass steps,
## so a slow drift is gone, then a one-pole low-pass, so a frame's jitter is.
func _band(d: float, delta: float) -> float:
	if delta <= 0.0:
		return _lp_out
	var high := 1.0 / (TAU * SHAKE_LOW)
	var a := high / (high + delta)
	_hp_out = a * (_hp_out + d - _hp_in)
	_hp_in = d
	_hp2_out = a * (_hp2_out + _hp_out - _hp2_in)
	_hp2_in = _hp_out
	var low := 1.0 / (TAU * SHAKE_HIGH)
	_lp_out += (_hp2_out - _lp_out) * delta / (low + delta)
	return _lp_out


## The vibrato a shake of `degrees` gives: none under SHAKE_FROM, VIBRATO_MOST at SHAKE_FULL.
static func _vibrato_for(degrees: float) -> float:
	var reach := clampf((absf(degrees) - SHAKE_FROM) / (SHAKE_FULL - SHAKE_FROM), 0.0, 1.0)
	return signf(degrees) * reach * VIBRATO_MOST
