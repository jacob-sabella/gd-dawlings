class_name AudioFeatures
extends Node

## What the music is doing, in the few numbers a visual needs (docs/visuals.md): how loud it is, its
## bass, mids and treble, a hit when something lands, where the beat is, its wave and a row of bars.
## Every audio-reactive visual reads these and nothing else, so each is worked out once a frame.
##
## Heard on the app's MIX bus (AudioPorts.MIX: the built-in DAW's master, or on a guest the host's mix):
## an AudioEffectSpectrumAnalyzer and a small AudioEffectCapture are hung on its end, after everything
## else, so the ports' own capture loses nothing. Reaper hands Godot no audio, so on Reaper the bus is
## silent and the rack's own loudness and hits (`lend`, from RackHost) are what moves the room.
##
## The values, all floats:
##  - `level`: loudness 0..1, auto-gained, so a quiet mix moves things as much as a loud one;
##  - `bass`, `mid`, `treb`: each band against its own recent average, MilkDrop's way: 1 is typical,
##    2 is a hit, 0 is silence; `bass_att` etc. the same eased, for slower motion;
##  - `hit`: 1 the frame something lands (a spectral-flux onset, weighted to the low end), falling to 0
##    in about a quarter second; `onset` is emitted with the strength as it happens;
##  - `beat` and `beat_phase`: the song's beat and how far through it (0..1) while the transport plays,
##    else the rack's own running clock, else a free clock at 120 BPM;
##  - `bars`: BARS log-spaced bands 40 Hz..16 kHz, 0..1, smoothed with CavaBars;
##  - `wave`: WAVE_POINTS recent samples of the mix, mono, -1..1.

## The one a studio stood up; visuals read it through `now()`.
static var current: AudioFeatures = null

const BARS := 32
const WAVE_POINTS := 128
const LOW_HZ := 40.0
const HIGH_HZ := 16000.0
const BASS_TOP_HZ := 250.0
const MID_TOP_HZ := 2000.0
## The averages `bass` and the others are measured against, and how fast they follow (s).
const AVERAGE_SECONDS := 2.5
## A hit is a flux this many times its own running average, and no sooner than REFRACTORY s after the last.
const HIT_RATIO := 1.6
const REFRACTORY := 0.12

signal onset(strength: float)

var level := 0.0
var bass := 0.0
var mid := 0.0
var treb := 0.0
var bass_att := 0.0
var mid_att := 0.0
var treb_att := 0.0
var hit := 0.0
var beat := 0.0
var beat_phase := 0.0
var bars := PackedFloat32Array()
var wave := PackedFloat32Array()
## Seconds since this started: a clock every visual can share.
var time := 0.0
## False where no analyzer could be hung (no MIX bus) or visuals are off: the values are then the rack's.
var listening := false

## The bands as last heard (linear magnitude), for a test to stand in: `feed` replaces the analyzer.
var _raw := PackedFloat32Array()
var _prev_raw := PackedFloat32Array()
var _avg := Vector3(0.02, 0.02, 0.02)
var _flux_avg := 0.0
var _since_hit := 1.0
var _level_peak := 0.05
var _lent_level := 0.0
var _lent_hit := 0.0
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _capture: AudioEffectCapture
var _cava := CavaBars.new(BARS)
var _ring := PackedFloat32Array()
var _fed := false


## The studio's, or a silent stand-in, so a visual never has to ask whether there is one.
static func now() -> AudioFeatures:
	if current != null and is_instance_valid(current):
		return current
	current = AudioFeatures.new()
	return current


func _init() -> void:
	bars.resize(BARS)
	wave.resize(WAVE_POINTS)
	_raw.resize(BARS)
	_prev_raw.resize(BARS)
	_ring.resize(WAVE_POINTS * 4)
	_cava.monstercat = 1.4
	_cava.smoothing = 0.5


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	listen(VisualBudget.tier() != VisualBudget.Tier.OFF)


## Hang (or take down) the analyzer and capture on the MIX bus.
func listen(on: bool) -> void:
	var bus := AudioServer.get_bus_index(AudioPorts.MIX)
	listening = false
	_analyzer = null
	_capture = null
	if bus < 0:
		return
	var a_slot := -1
	var c_slot := -1
	for i in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, i)
		if e.has_meta(&"audio_features"):
			if e is AudioEffectSpectrumAnalyzer:
				a_slot = i
			elif e is AudioEffectCapture:
				c_slot = i
	if not on:
		for slot in [maxi(a_slot, c_slot), mini(a_slot, c_slot)]:
			if slot >= 0:
				AudioServer.remove_bus_effect(bus, slot)
		return
	if a_slot < 0:
		var a := AudioEffectSpectrumAnalyzer.new()
		a.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		a.buffer_length = 0.1
		a.set_meta(&"audio_features", true)
		AudioServer.add_bus_effect(bus, a)
		a_slot = AudioServer.get_bus_effect_count(bus) - 1
	if c_slot < 0:
		var c := AudioEffectCapture.new()
		c.buffer_length = 0.1
		c.set_meta(&"audio_features", true)
		AudioServer.add_bus_effect(bus, c)
		c_slot = AudioServer.get_bus_effect_count(bus) - 1
	_analyzer = AudioServer.get_bus_effect_instance(bus, a_slot) as AudioEffectSpectrumAnalyzerInstance
	_capture = AudioServer.get_bus_effect(bus, c_slot) as AudioEffectCapture
	listening = _analyzer != null


## The rack's own loudness and hit, lent each frame by RackHost: on Reaper (nothing on the MIX bus) or a
## rack nobody routed to a track, the room still moves with what the rack plays.
func lend(rack_level: float, rack_hit: float) -> void:
	_lent_level = clampf(rack_level, 0.0, 1.0)
	_lent_hit = clampf(rack_hit, 0.0, 1.0)


## A band's centre edges: BARS log-spaced from LOW_HZ to HIGH_HZ.
static func band_edges(i: int) -> Vector2:
	var r := HIGH_HZ / LOW_HZ
	return Vector2(LOW_HZ * pow(r, float(i) / BARS), LOW_HZ * pow(r, float(i + 1) / BARS))


## For a test (or a recorded run): take these BARS magnitudes and these samples as this frame's sound.
func feed(raw: PackedFloat32Array, samples := PackedFloat32Array()) -> void:
	_fed = true
	for i in BARS:
		_raw[i] = raw[i] if i < raw.size() else 0.0
	if not samples.is_empty():
		_push_samples(samples)


func _process(delta: float) -> void:
	step(delta)


## One frame: read (unless fed), then work every value out.
func step(delta: float) -> void:
	time += delta
	if not _fed:
		_read()
	_fed = false
	_bands(delta)
	_onset(delta)
	_clock(delta)
	_cava.step(_scaled(), delta)
	bars = _cava.bars


func _read() -> void:
	if _analyzer == null:
		_raw.fill(0.0)
		return
	for i in BARS:
		var e := band_edges(i)
		var m := _analyzer.get_magnitude_for_frequency_range(e.x, e.y, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
		_raw[i] = maxf(m.x, m.y)
	if _capture != null:
		var n := _capture.get_frames_available()
		if n > 0:
			var frames := _capture.get_buffer(mini(n, _ring.size()))
			var mono := PackedFloat32Array()
			mono.resize(frames.size())
			for k in frames.size():
				mono[k] = (frames[k].x + frames[k].y) * 0.5
			_push_samples(mono)


func _push_samples(mono: PackedFloat32Array) -> void:
	var n := _ring.size()
	if mono.size() >= n:
		_ring = mono.slice(mono.size() - n)
	else:
		_ring = _ring.slice(mono.size()) + mono
	# Every fourth sample of the newest stretch: the wave, as MilkDrop draws it.
	for k in WAVE_POINTS:
		wave[k] = clampf(_ring[k * 4], -1.0, 1.0)


func _bands(delta: float) -> void:
	var sums := Vector3.ZERO
	var loud := 0.0
	for i in BARS:
		var hz := band_edges(i).x
		var v := _raw[i]
		loud = maxf(loud, v)
		if hz < BASS_TOP_HZ:
			sums.x += v
		elif hz < MID_TOP_HZ:
			sums.y += v
		else:
			sums.z += v
	var follow := clampf(delta / AVERAGE_SECONDS, 0.0, 1.0)
	_avg = _avg.lerp(sums, follow).max(Vector3(0.0005, 0.0005, 0.0005))
	var rel := Vector3(sums.x / _avg.x, sums.y / _avg.y, sums.z / _avg.z).clampf(0.0, 4.0)
	# Silence is 0, not "as loud as its own average of silence".
	if sums.length() < 0.0002:
		rel = Vector3.ZERO
	bass = rel.x
	mid = rel.y
	treb = rel.z
	var ease := clampf(delta * 6.0, 0.0, 1.0)
	bass_att = lerpf(bass_att, bass, ease)
	mid_att = lerpf(mid_att, mid, ease)
	treb_att = lerpf(treb_att, treb, ease)
	# Loudness against its own recent peak, which falls slowly: auto-gain.
	_level_peak = maxf(loud, _level_peak * pow(0.5, delta / 4.0))
	_level_peak = maxf(_level_peak, 0.01)
	var heard := clampf(loud / _level_peak, 0.0, 1.0) if loud > 0.0005 else 0.0
	var want := maxf(heard, _lent_level)
	level = lerpf(level, want, clampf(delta * (14.0 if want > level else 5.0), 0.0, 1.0))


func _onset(delta: float) -> void:
	var flux := 0.0
	for i in BARS:
		var rise := _raw[i] - _prev_raw[i]
		if rise > 0.0:
			# The low end counts most: the kick and the bass are what a room moves to.
			flux += rise * (2.0 if i < BARS / 4 else 1.0)
		_prev_raw[i] = _raw[i]
	_flux_avg = lerpf(_flux_avg, flux, clampf(delta * 3.0, 0.0, 1.0))
	_since_hit += delta
	hit = maxf(hit - delta * 4.0, 0.0)
	var strength := 0.0
	if flux > 0.002 and flux > _flux_avg * HIT_RATIO and _since_hit > REFRACTORY:
		strength = clampf(flux / maxf(_flux_avg * HIT_RATIO * 2.0, 0.0001), 0.3, 1.0)
	if _lent_hit > 0.95 and _since_hit > REFRACTORY:
		strength = maxf(strength, _lent_hit)
	_lent_hit = 0.0
	if strength > 0.0:
		_since_hit = 0.0
		hit = maxf(hit, strength)
		onset.emit(strength)


func _clock(delta: float) -> void:
	var state := DAW.state if DAW != null else null
	if state != null and state.playing:
		beat = state.beat_at(state.position_seconds)
	else:
		beat += delta * 2.0
	beat_phase = fposmod(beat, 1.0)


## The bands for the bars, each brought into 0..1 by its own place in the spectrum: a mix's treble sits
## far under its bass, so the high bars are lifted to read.
func _scaled() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BARS)
	for i in BARS:
		out[i] = _raw[i] * (1.0 + float(i) * 0.18)
	return out
