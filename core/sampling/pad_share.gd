class_name PadShare
extends RefCounted

## The sampling station's pads, shared with the room (docs/sampling_station.md, slice 7): the
## sample is the host's, written once as a WAV in the project's media (a file a guest may fetch,
## FileSend.shared), and the room's `pads` row says which file, how it is cut, and how each pad
## plays. A guest fetches the file, cuts it the same, and its pads sound as the host's do.

const ROW := "pads"


## The file a sample is kept as: named by what is in it, so the same sound is the same file.
static func name_of(frames: PackedVector2Array) -> String:
	return "pads_%08x.wav" % (hash(frames.to_byte_array()) & 0xffffffff)


## Host: `bank`'s sample written into the media folder (if it is not there already) and offered to
## guests. The file's name, or "" with no sample or no place to put it.
static func write(bank: PadBank) -> String:
	if bank.frames.is_empty() or DAW.backend == null:
		return ""
	var file := name_of(bank.frames)
	var path := DAW.backend.media_path(file)
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var data := PackedByteArray()
		data.resize(bank.frames.size() * 4)
		for i in bank.frames.size():
			data.encode_s16(i * 4, clampi(roundi(bank.frames[i].x * 32767.0), -32768, 32767))
			data.encode_s16(i * 4 + 2, clampi(roundi(bank.frames[i].y * 32767.0), -32768, 32767))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.stereo = true
		wav.mix_rate = PadBank.RATE
		wav.data = data
		if wav.save_to_wav(path) != OK:
			return ""
	FileSend.shared[file] = true
	return file


## The room's row for `bank`, whose sample is `file`.
static func row(bank: PadBank, file: String) -> Dictionary:
	var cuts := PackedInt32Array()
	for s in bank.slices:
		cuts.append(s.x)
		cuts.append(s.y)
	var own: Array = []
	for p in bank.params:
		own.append(p.duplicate())
	return {"file": file, "cuts": cuts, "params": own,
			"scale": [bank.scale_on, bank.root, bank.mode, bank.scale_pad, bank.sample_note],
			"first": bank.first_note}


## A guest: `bank` made to be what the row says, its sample read from `stream` (the fetched file).
static func apply(bank: PadBank, state: Dictionary, stream: AudioStreamWAV) -> void:
	if stream != null:
		bank.set_sample(PadBank.cut(stream, 0.0, stream.get_length()))
	set_settings(bank, state)


## Everything of the row but the sample: the cuts, each pad's settings, scale mode, the first note.
static func set_settings(bank: PadBank, state: Dictionary) -> void:
	var cuts: PackedInt32Array = state.get("cuts", PackedInt32Array())
	if cuts.size() == PadBank.PADS * 2:
		for i in PadBank.PADS:
			bank.slices[i] = Vector2i(cuts[i * 2], cuts[i * 2 + 1])
	var own: Array = state.get("params", [])
	for i in mini(own.size(), PadBank.PADS):
		var merged := PadBank.default_params()
		merged.merge(own[i], true)
		bank.params[i] = merged
	var scale: Array = state.get("scale", [])
	if scale.size() == 5:
		bank.scale_on = bool(scale[0])
		bank.root = int(scale[1])
		bank.mode = str(scale[2])
		bank.scale_pad = int(scale[3])
		bank.sample_note = int(scale[4])
	bank.first_note = int(state.get("first", PadBank.FIRST_NOTE))
	bank.clear_made()
