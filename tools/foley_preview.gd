extends SceneTree

## Write every synthesised sound out as a .wav you can play and an .svg you can look at.
##
##   godot --headless --path . --script tools/foley_preview.gd
##
## The .wav is the real review: these are sounds and the only test that counts is listening to
## them. The .svg is for the two defects that are easier to SEE than to hear -- a loop that steps
## at the seam and a one-shot that is cut off before it has decayed -- both of which read as a
## cliff at the right-hand edge of the trace.

const OUT := "res://shots/foley"
const COLUMNS := 760
const ROW := 92
const PAD := 10
const LABEL := 118


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sounds := [
		["button", "button click", Foley.button_click()],
		["detent", "knob detent", Foley.knob_detent()],
		["plug", "plug seating", Foley.plug_seat()],
		["slide", "fader slide (loop)", Foley.fader_slide()],
		["motor", "reel motor (loop)", Foley.reel_motor()],
	]

	var rows := ""
	var y := PAD
	for entry in sounds:
		var key: String = entry[0]
		var wav: AudioStreamWAV = entry[2]
		wav.save_to_wav("%s/%s.wav" % [OUT, key])
		rows += _row(entry[1], wav, y)
		y += ROW

	var width := LABEL + COLUMNS + PAD * 2
	var height := y + PAD
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" ' % [width, height]
	svg += 'viewBox="0 0 %d %d">' % [width, height]
	svg += '<rect width="100%%" height="100%%" fill="#14171c"/>' + rows + '</svg>'
	var f := FileAccess.open("%s/waveforms.svg" % OUT, FileAccess.WRITE)
	f.store_string(svg)
	f.close()
	print("wrote %d sounds to %s" % [sounds.size(), OUT])
	quit()


func _row(title: String, wav: AudioStreamWAV, top: int) -> String:
	var samples := _pcm(wav)
	var mid := top + ROW / 2
	var half := float(ROW) / 2.0 - 10.0
	var looping := wav.loop_mode == AudioStreamWAV.LOOP_FORWARD

	# Min/max per column rather than one sample per column: a 30,000-sample buffer decimated to
	# 760 points throws away 97% of the peaks, and what it throws away is precisely the transient
	# this is being drawn to inspect.
	var top_edge := PackedStringArray()
	var bottom_edge := PackedStringArray()
	for c in COLUMNS:
		var from := int(float(c) / COLUMNS * samples.size())
		var to := maxi(int(float(c + 1) / COLUMNS * samples.size()), from + 1)
		var lo := 0.0
		var hi := 0.0
		for i in range(from, mini(to, samples.size())):
			lo = minf(lo, samples[i])
			hi = maxf(hi, samples[i])
		var x := LABEL + PAD + c
		top_edge.append("%d,%.1f" % [x, mid - hi * half])
		bottom_edge.insert(0, "%d,%.1f" % [x, mid - lo * half])

	var colour := "#5bc8a0" if looping else "#6aa6f0"
	var out := '<text x="%d" y="%d" fill="#8d96a5" font-family="monospace" font-size="11">%s</text>' \
			% [PAD, mid + 4, title]
	out += '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#2a2f38"/>' \
			% [LABEL + PAD, mid, LABEL + PAD + COLUMNS, mid]
	out += '<polygon points="%s %s" fill="%s" fill-opacity="0.85"/>' \
			% [" ".join(top_edge), " ".join(bottom_edge), colour]
	# The loop point, which is the thing worth checking on the green traces.
	if looping:
		out += '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#e0a44a" stroke-dasharray="3 3"/>' \
				% [LABEL + PAD + COLUMNS, top + 6, LABEL + PAD + COLUMNS, top + ROW - 6]
	out += '<text x="%d" y="%d" fill="#5d646f" font-family="monospace" font-size="9">%.0f ms</text>' \
			% [LABEL + PAD + COLUMNS - 46, top + 14,
			   float(samples.size()) / float(wav.mix_rate) * 1000.0]
	return out


func _pcm(wav: AudioStreamWAV) -> PackedFloat32Array:
	var bytes := wav.data
	var out := PackedFloat32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		out[i] = float(bytes.decode_s16(i * 2)) / 32767.0
	return out
