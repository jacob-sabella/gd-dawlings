class_name AudioTake
extends RefCounted

## A recording, written to disk as it arrives: a guest's microphone, streamed up to the host a
## piece at a time while the take is running, so that when recording stops there is almost
## nothing left to send and the take can be placed at once.
##
## Mono, 16-bit, 48kHz: a voice or an instrument through one microphone, at the session wire's
## own rate. A WAV rather than anything compressed, because this is the master copy of
## someone's performance. The header is written first with its sizes left open and patched by
## `finish`, so a take cut short by a crash is still a file most editors will open.
##
## A take also keeps its own overview -- the loudest sample of every 20ms -- which is what the
## timeline draws, and which is small enough to send to every guest with the item.

const RATE := 48000
const PEAKS_PER_SECOND := 50
const FRAMES_PER_PEAK := RATE / PEAKS_PER_SECOND
## Half an hour. A take is held open on the host's disk for as long as it runs; one left running
## by a guest who walked away should not fill it.
const MAX_SECONDS := 30.0 * 60.0
const DIR := "user://takes"
const HEADER_BYTES := 44

var path := ""
var frames := 0
var _file: FileAccess = null
var _peaks := PackedByteArray()
var _run := 0
var _loudest := 0


## A new take at `file_name` in DIR, or null if the file cannot be made.
static func create(file_name: String) -> AudioTake:
	DirAccess.make_dir_recursive_absolute(DIR)
	var take := AudioTake.new()
	take.path = DIR.path_join(file_name)
	take._file = FileAccess.open(take.path, FileAccess.WRITE)
	if take._file == null:
		return null
	take._file.store_buffer(header(0))
	return take


## A RIFF/WAVE header for `data_frames` frames of mono 16-bit at `rate` (RATE; a sample, Sampler,
## is at Foley's own).
static func header(data_frames: int, rate := RATE) -> PackedByteArray:
	var data_bytes := data_frames * 2
	var b := PackedByteArray()
	b.resize(HEADER_BYTES)
	b.encode_u32(0, 0x46464952)      # "RIFF"
	b.encode_u32(4, 36 + data_bytes)
	b.encode_u32(8, 0x45564157)      # "WAVE"
	b.encode_u32(12, 0x20746d66)     # "fmt "
	b.encode_u32(16, 16)
	b.encode_u16(20, 1)              # PCM
	b.encode_u16(22, 1)              # mono
	b.encode_u32(24, rate)
	b.encode_u32(28, rate * 2)
	b.encode_u16(32, 2)
	b.encode_u16(34, 16)
	b.encode_u32(36, 0x61746164)     # "data"
	b.encode_u32(40, data_bytes)
	return b


## Little-endian 16-bit mono from what a capture returns. The two sides are averaged: a
## microphone is one signal, reported twice by most drivers, and averaging is right for the
## odd interface that puts it on one side only less than taking the left would be wrong.
static func encode(stereo: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(stereo.size() * 2)
	for i in stereo.size():
		var v := clampf((stereo[i].x + stereo[i].y) * 0.5, -1.0, 1.0)
		out.encode_s16(i * 2, int(round(v * 32767.0)))
	return out


## As `encode`, one side alone: 1 the left (an interface's input 1), 2 the right; 0 both, averaged.
static func encode_channel(stereo: PackedVector2Array, channel: int) -> PackedByteArray:
	if channel == 0:
		return encode(stereo)
	var out := PackedByteArray()
	out.resize(stereo.size() * 2)
	for i in stereo.size():
		var v := clampf(stereo[i].x if channel == 1 else stereo[i].y, -1.0, 1.0)
		out.encode_s16(i * 2, int(round(v * 32767.0)))
	return out


## The file name a take is kept under: who played it, which of theirs it is, and when, in
## characters every file system takes.
static func file_name_for(who: String, number: int) -> String:
	var safe := ""
	for c in who.left(32):
		safe += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") else "_"
	if safe.is_empty():
		safe = "guest"
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	return "%s-take%d-%s.wav" % [safe, number, stamp]


## Add 16-bit mono to the end. False, and nothing written, once the take is at its limit.
func append(pcm: PackedByteArray) -> bool:
	if _file == null:
		return false
	var n := pcm.size() / 2
	if frames + n > int(MAX_SECONDS * RATE):
		return false
	_file.store_buffer(pcm.slice(0, n * 2))
	for i in n:
		_loudest = maxi(_loudest, absi(pcm.decode_s16(i * 2)))
		_run += 1
		if _run == FRAMES_PER_PEAK:
			_close_peak()
	frames += n
	return true


func _close_peak() -> void:
	_peaks.append(clampi(int(_loudest / 128.5), 0, 255))
	_run = 0
	_loudest = 0


## Sizes into the header, the file closed. The take is a finished WAV from here.
func finish() -> void:
	if _file == null:
		return
	if _run > 0:
		_close_peak()
	_file.seek(0)
	_file.store_buffer(header(frames))
	_file.close()
	_file = null


## Abandoned: nothing of it is kept.
func discard() -> void:
	if _file != null:
		_file.close()
		_file = null
	DirAccess.remove_absolute(path)


func seconds() -> float:
	return float(frames) / RATE


## The overview of the sound file at `sound_path`, as a take's own (PEAKS_PER_SECOND bytes a
## second), read from the sound: for a file the desk did not record as it went, such as one in a
## project being opened. Every sample is looked at; a stereo minute is about a quarter of a second.
## Empty for a file that is not there or cannot be read.
static func overview_of(sound_path: String) -> PackedByteArray:
	if not FileAccess.file_exists(sound_path):
		return PackedByteArray()
	var sound := DawKitAudioFile.read(sound_path)
	if not str(sound["error"]).is_empty():
		return PackedByteArray()
	return DawKitAudioFile.peaks(sound["samples"], int(sound["channels"]), int(sound["rate"]),
			PEAKS_PER_SECOND)


## The loudest sample of every 1/PEAKS_PER_SECOND of the take, 0-255.
func peaks() -> PackedByteArray:
	return _peaks


func file_name() -> String:
	return path.get_file()
