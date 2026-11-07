class_name PadDeckSampling
extends RefCounted

## Making the sample: SAMPLE cut from the video's sound, the source and device it comes from, trim, the chop
## mode and the scale (KEY and MODE). Moved out of `hardware/tv/pad_deck.gd` without change of behaviour.

var deck: PadDeck


func _init(of: PadDeck) -> void:
	deck = of


## SAMPLE: the first press marks where the TV is, the second cuts from there to where it is now.
func sample() -> void:
	if PadCapture.SOURCES[deck.source] != "TV":
		_sample_live()
		return
	if deck.tv == null or deck.tv.video == "" or deck.tv.sound() == null:
		deck.said.emit("Play something on the TV first: SAMPLE takes what it plays.")
		return
	var now := deck.tv.position()
	if is_nan(deck.marked):
		deck.marked = now
		deck.refresh()
		return
	var from := minf(deck.marked, now)
	var to := maxf(deck.marked, now)
	deck.marked = NAN
	if to - from < PadBank.SHORTEST:
		deck.refresh()
		return
	deck.bank.set_sample(PadBank.cut(deck.tv.sound(), from, to))
	_made_here()
	deck.chop = 0
	deck.refresh()


## SAMPLE from the mix, the room or the interface: the first press starts catching, the second
## ends it and the sound is the sample.
func _sample_live() -> void:
	if deck.capture.recording:
		var sound := deck.capture.stop()
		if deck.trim_on:
			sound = PadCapture.trimmed(sound)
		if sound.size() < int(PadBank.SHORTEST * PadBank.RATE):
			deck.said.emit("Nothing caught: is anything playing?")
		else:
			deck.bank.set_sample(sound)
			_made_here()
			deck.chop = 0
		deck.refresh()
		return
	if not deck.capture.start(PadCapture.SOURCES[deck.source]):
		deck.said.emit(deck.capture.why)
	deck.refresh()


func step_source() -> void:
	if deck.capture.recording:
		deck.capture.stop()
	deck.marked = NAN
	deck.source = (deck.source + 1) % PadCapture.SOURCES.size()
	deck.said.emit("Sampling from: " + PadCapture.SOURCES[deck.source])
	deck.refresh()


## A guest's own sound is on the pads: the host's row stops replacing them (SYNC brings it back).
func _made_here() -> void:
	if deck.tv != null and deck.tv.guest and not deck.tv.own_pads:
		deck.tv.own_pads = true
		deck.said.emit("These are your own sounds now: SYNC (STORE) gives the room's pads back.")


## SYNC: a guest takes the room's pads back.
func rejoin() -> void:
	if deck.tv == null or not deck.tv.guest:
		deck.said.emit("SYNC is for a guest: your pads are the room's.")
		return
	if not deck.tv.own_pads:
		deck.said.emit("You already have the room's pads.")
		return
	deck.tv.own_pads = false
	deck.tv.pads_rejoined.emit()
	deck.said.emit("The room's pads are back.")
	deck.refresh()


## DEV: IN's next input.
func step_device() -> void:
	if deck.capture.recording:
		deck.capture.stop()
	var named := deck.capture.step_device()
	deck.source = PadCapture.SOURCES.find("IN")
	deck.said.emit("Sampling from the input: " + named)
	deck.refresh()


func toggle_trim() -> void:
	deck.trim_on = not deck.trim_on
	deck.said.emit("Trim the quiet off a live catch: " + ("on" if deck.trim_on else "off"))
	deck.refresh()


func step_chop() -> void:
	if deck.bank.frames.is_empty():
		return
	deck.chop = (deck.chop + 1) % PadDeck.CHOPS.size()
	if PadDeck.CHOPS[deck.chop] == "HITS":
		if deck.bank.chop_transients() <= 1:
			deck.said.emit("No hits to cut it at: cut into 16 instead.")
			deck.chop = 0
			deck.bank.chop_equal(16)
	else:
		deck.bank.chop_equal(int(PadDeck.CHOPS[deck.chop]))
	deck.refresh()


## SCALE: the last pad struck across all sixteen, in the song's key where it has one.
func toggle_scale() -> void:
	deck.bank.scale_on = not deck.bank.scale_on
	if deck.bank.scale_on:
		deck.bank.scale_pad = deck.last_pad
		var key := Harmony.at(DAW.state, float(deck.tv.song_position.call())) if deck.tv != null and DAW.state != null else null
		if key != null:
			deck.bank.root = key.root
			deck.bank.mode = key.mode
	deck.refresh()


func step_root(by: int) -> void:
	deck.bank.root = posmod(deck.bank.root + by, 12)
	deck.refresh()


func step_mode() -> void:
	var at := PadBank.MODES.find(deck.bank.mode)
	deck.bank.mode = PadBank.MODES[(at + 1) % PadBank.MODES.size()]
	deck.refresh()
