class_name PadLibrary
extends RefCounted

## The sampling station's library (docs/sampling_station.md): every sample kept as a WAV, and every
## kit (sixteen pads: which sample each plays, and how) as a JSON, in folders the player can see
## and rename in: `<root>/samples/*.wav` and `<root>/kits/*.json`.
##
## A kit holds its sounds by name, not by value, so a sample used by many kits is kept once; a kit
## saved from the pads writes each pad's slice as a sample of its own (named by what is in it, so the
## same sound is the same file) and is loaded by putting those sounds back on their pads.

## Where the library lives (tests point it somewhere of their own).
static var root := "user://sampling"


static func samples_dir() -> String:
	return root.path_join("samples")


static func kits_dir() -> String:
	return root.path_join("kits")


## The names (no extension) of the files in `dir` ending `ext`, in order.
static func _names(dir: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() == ext:
			out.append(f.get_basename())
	out.sort()
	return out


static func samples() -> PackedStringArray:
	return _names(samples_dir(), "wav")


static func kits() -> PackedStringArray:
	return _names(kits_dir(), "json")


## A name safe as a file's: letters, digits, dash and underscore only.
static func clean(name: String) -> String:
	var out := ""
	for c in name.strip_edges():
		out += c if (c.unicode_at(0) < 128 and c.is_valid_identifier()) or c.is_valid_int() or c == "-" or c == "_" else "_"
	return out.left(40).strip_edges()


## The name for a new item: `base` made safe, and numbered past any already there.
static func fresh(base: String, taken: PackedStringArray) -> String:
	var stem := clean(base)
	if stem.is_empty():
		stem = "sample"
	if not taken.has(stem):
		return stem
	var n := 2
	while taken.has("%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


static func _encode(frames: PackedVector2Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i in frames.size():
		data.encode_s16(i * 4, clampi(roundi(frames[i].x * 32767.0), -32768, 32767))
		data.encode_s16(i * 4 + 2, clampi(roundi(frames[i].y * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = PadBank.RATE
	wav.data = data
	return wav


## `frames` kept as sample `name` (replacing one of that name). Returns whether it was written.
static func save_sample(name: String, frames: PackedVector2Array) -> bool:
	if frames.is_empty() or clean(name).is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(samples_dir())
	return _encode(frames).save_to_wav(samples_dir().path_join(clean(name) + ".wav")) == OK


## Sample `name` as stereo frames at PadBank.RATE; empty if there is none.
static func load_sample(name: String) -> PackedVector2Array:
	var path := samples_dir().path_join(clean(name) + ".wav")
	if not FileAccess.file_exists(path):
		return PackedVector2Array()
	var wav := AudioStreamWAV.load_from_file(path)
	if wav == null:
		return PackedVector2Array()
	if wav.format == AudioStreamWAV.FORMAT_16_BITS and wav.mix_rate == PadBank.RATE:
		# At the library's own rate every frame is read as it was written (cut reads between frames
		# and so drops the last).
		var channels := 2 if wav.stereo else 1
		var out := PackedVector2Array()
		out.resize(wav.data.size() / (2 * channels))
		for i in out.size():
			out[i] = PadBank._frame(wav.data, i, channels)
		return out
	return PadBank.cut(wav, 0.0, wav.get_length())


## Delete the saved sample called `name`; true if the file existed and went.
static func delete_sample(name: String) -> bool:
	var path := samples_dir().path_join(clean(name) + ".wav")
	return FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK


## Delete the saved kit called `name`; true if the file existed and went.
static func delete_kit(name: String) -> bool:
	var path := kits_dir().path_join(clean(name) + ".json")
	return FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK


## The name a slice's sound goes by: of what is in it, so the same sound is the same sample.
static func sound_name(frames: PackedVector2Array, base: String) -> String:
	var stem := clean(base)
	if stem.is_empty():
		stem = "sample"
	return "%s_%06x" % [stem.left(24), hash(frames.to_byte_array()) & 0xffffff]


## `bank`'s kit saved as `name`: each pad's slice a sample (`base` and a hash of the sound), and
## the pads' settings. Returns the kit's name, or "" if there was nothing to keep.
static func save_kit(name: String, bank: PadBank, base := "") -> String:
	var kit := clean(name)
	if kit.is_empty() or bank.frames.is_empty():
		return ""
	var pads: Array = []
	var kept := 0
	for i in PadBank.PADS:
		var s := bank.slices[i]
		var entry := {"params": bank.params[i].duplicate()}
		if s.y > s.x and s.y <= bank.frames.size():
			var sound := bank.frames.slice(s.x, s.y)
			var sample := sound_name(sound, base if base != "" else kit)
			if not FileAccess.file_exists(samples_dir().path_join(sample + ".wav")):
				save_sample(sample, sound)
			entry["sample"] = sample
			kept += 1
		pads.append(entry)
	if kept == 0:
		return ""
	DirAccess.make_dir_recursive_absolute(kits_dir())
	var f := FileAccess.open(kits_dir().path_join(kit + ".json"), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({"kit": 1, "pads": pads, "first": bank.first_note}, "\t"))
	return kit


## Kit `name` put on `bank`: each pad's sound loaded and its settings set. Returns how many pads
## have a sound (0 if there is no such kit, or its samples are gone: the bank is left as it was).
static func load_kit(name: String, bank: PadBank) -> int:
	var path := kits_dir().path_join(clean(name) + ".json")
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not (data as Dictionary).get("pads") is Array:
		return 0
	var pads: Array = data["pads"]
	var sounds: Array = []
	var own: Array = []
	var filled := 0
	for i in PadBank.PADS:
		var entry: Dictionary = pads[i] if i < pads.size() and pads[i] is Dictionary else {}
		var sound := load_sample(str(entry.get("sample", ""))) if entry.has("sample") else PackedVector2Array()
		sounds.append(sound)
		filled += 0 if sound.is_empty() else 1
		var merged := PadBank.default_params()
		var saved: Variant = entry.get("params", {})
		if saved is Dictionary:
			merged.merge(saved, true)
		own.append(merged)
	if filled == 0:
		return 0
	bank.assemble(sounds)
	for i in PadBank.PADS:
		bank.params[i] = own[i]
	bank.first_note = clampi(int(data.get("first", PadBank.FIRST_NOTE)), 0, 127 - PadBank.PADS + 1)
	bank.clear_made()
	return filled
