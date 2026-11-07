class_name PadDeckVoices
extends RefCounted

## How a pad sounds: striking and releasing through the voice pool, the track's monitor bus, clicks, MIDI notes
## played as pads and the release of what is due. Moved out of `hardware/tv/pad_deck.gd` without change of behaviour.

var deck: PadDeck


func _init(of: PadDeck) -> void:
	deck = of


## Pad `pad` struck at `velocity`: heard through the armed track's bus, lit while it sounds, and
## told (`struck`) for the take. A LOOP pad struck while it loops stops; a pad in a choke group
## cuts the others of its group off first.
func strike(pad: int, velocity := 100) -> void:
	if pad < 0 or pad >= PadBank.PADS:
		return
	var was := deck.selected
	deck.selected = pad
	if was != pad:
		# The pad struck is the one the keys now edit: show it, without telling the room.
		deck.refresh(false)
	var own := deck.bank.params[pad]
	if int(own["mode"]) == 2 and _voice_of(pad) >= 0:
		release(pad, true)
		return
	var made: Array = deck.bank.sound_of(deck.bank.slice_of(pad), deck.bank.pad_semitones(pad), pad)
	var stream: AudioStreamWAV = made[0]
	if stream == null:
		return
	if not deck.bank.scale_on:
		deck.last_pad = pad
	if int(own["choke"]) > 0:
		for other in PadBank.PADS:
			if other != pad and int(deck.bank.params[other]["choke"]) == int(own["choke"]):
				release(other, true)
	var at := _free_voice()
	var voice := deck._voices[at]
	deck._voice_pad[at] = pad
	var bus := DAW.monitor_bus(HitRecorder.armed_track())
	voice.bus = bus if bus != &"" and AudioServer.get_bus_index(bus) >= 0 else AudioPorts.MONITOR
	voice.stream = stream
	voice.pitch_scale = made[1]
	voice.volume_db = linear_to_db(maxf(velocity, 1) / 127.0)
	voice.play()
	_send(at, stream, made[1], velocity, float(own["send"]))
	var held := int(own["mode"]) != 0
	deck._lit_until[pad] = (1 << 60) if held else Time.get_ticks_msec() + int(stream.get_length() / float(made[1]) * 1000.0)
	deck.pads[pad].lit = true
	if not deck._quiet:
		deck.struck.emit(pad, velocity)


## The voice to play on: an idle one, else the one that has played longest.
func _free_voice() -> int:
	for i in PadDeck.VOICES:
		if not deck._voices[i].playing:
			deck._next_voice = (i + 1) % PadDeck.VOICES
			return i
	var at := deck._next_voice
	deck._next_voice = (deck._next_voice + 1) % PadDeck.VOICES
	return at


## Voice `at`'s sound to the effect bus too, `amount` of it.
func _send(at: int, stream: AudioStream, rate: float, velocity: int, amount: float) -> void:
	var fx := deck._fx_voices[at]
	fx.stop()
	amount = 1.0 if deck.punch else amount
	if amount <= 0.0:
		return
	deck._ensure_fx_bus()
	fx.bus = PadDeck.FX_BUS
	fx.stream = stream
	fx.pitch_scale = rate
	fx.volume_db = linear_to_db(maxf(velocity, 1) / 127.0 * amount)
	fx.play()


func _voice_of(pad: int) -> int:
	for i in PadDeck.VOICES:
		if deck._voice_pad[i] == pad and deck._voices[i].playing:
			return i
	return -1


## Pad `pad` let go: a GATE pad stops (a LOOP pad too, when `force`; a one-shot plays out unless
## forced, as a choke does).
func release(pad: int, force := false) -> void:
	if pad < 0 or pad >= PadBank.PADS:
		return
	var mode := int(deck.bank.params[pad]["mode"])
	if mode == 0 and not force:
		return
	if mode == 2 and not force:
		return
	for i in PadDeck.VOICES:
		if deck._voice_pad[i] == pad and deck._voices[i].playing:
			deck._voices[i].stop()
			deck._fx_voices[i].stop()
			deck._voice_pad[i] = -1
	deck._lit_until[pad] = 0
	deck.pads[pad].lit = false


## Every pad quiet.
func stop_all() -> void:
	for pad in PadBank.PADS:
		release(pad, true)
	deck._held.clear()


## A pad clicked or touched: struck, and a GATE pad (which has no letting-go here) plays through.
func click(pad: int) -> void:
	strike(pad, 100)
	if pad >= 0 and pad < PadBank.PADS and int(deck.bank.params[pad]["mode"]) == 1:
		var at := _voice_of(pad)
		if at >= 0 and deck._voices[at].stream != null:
			deck._lit_until[pad] = Time.get_ticks_msec() + int(deck._voices[at].stream.get_length() / deck._voices[at].pitch_scale * 1000.0)


## A MIDI note meant for the pads: whether the pads took it (a note out of their range is left for
## the player's instrument). Velocity 0 is a note off. Pads 36-51, or in scale mode every note.
func midi(pitch: int, velocity: int, on: bool, from_channel := -1) -> bool:
	if not deck.engaged:
		return false
	if deck.channel > 0 and from_channel >= 0 and from_channel != deck.channel - 1:
		return false
	if deck.learning and on and velocity > 0 and not deck.bank.scale_on:
		deck.bank.first_note = clampi(pitch - deck.selected, 0, 127 - PadBank.PADS + 1)
		deck.learning = false
		deck.said.emit("Pad %d is now note %d; pads %d to %d follow." % [deck.selected + 1, pitch, 1, 16])
		deck.refresh()
		return true
	var pad := deck.bank.pad_of_note(pitch)
	if pad < 0 and not deck.bank.scale_on:
		return false
	if on and velocity > 0:
		if pad >= 0:
			strike(pad, velocity)
		else:
			# A scale-mode note between the pads' own: the spread slice at its pitch.
			_play_pitch(pitch, velocity)
		deck._held[pitch] = pad
	else:
		var was: Variant = deck._held.get(pitch, pad)
		deck._held.erase(pitch)
		if int(was) >= 0:
			release(int(was))
	return true


func _play_pitch(pitch: int, velocity: int) -> void:
	var play: Array = deck.bank.play_of(pitch)
	var made: Array = deck.bank.sound_of(play[0], play[1], deck.bank.scale_pad)
	var stream: AudioStreamWAV = made[0]
	if stream == null:
		return
	var at := _free_voice()
	var voice := deck._voices[at]
	var bus := DAW.monitor_bus(HitRecorder.armed_track())
	voice.bus = bus if bus != &"" and AudioServer.get_bus_index(bus) >= 0 else AudioPorts.MONITOR
	voice.stream = stream
	voice.pitch_scale = made[1]
	voice.volume_db = linear_to_db(maxf(velocity, 1) / 127.0)
	voice.play()
	deck._voice_pad[at] = -1
	_send(at, stream, made[1], velocity, float(deck.bank.params[deck.bank.scale_pad]["send"]))


func _release_due(now: float) -> void:
	var keep: Array = []
	for off in deck._offs:
		if float(off[0]) <= now:
			release(int(off[1]))
		else:
			keep.append(off)
	deck._offs = keep
