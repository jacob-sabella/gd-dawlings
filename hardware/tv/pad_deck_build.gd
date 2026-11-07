class_name PadDeckBuild
extends RefCounted

## Building the pad console: the sixteen pads, the waveform, the rows of keys, their labels, and the key pages
## (`show_page`). Moved out of `hardware/tv/pad_deck.gd` without change of behaviour; the state stays on the deck, which keeps
## a one-line delegate for each name reached from elsewhere.

var deck: PadDeck


func _init(of: PadDeck) -> void:
	deck = of


func _build() -> void:
	var panel := MeshInstance3D.new()
	panel.name = "Console"
	var box := BoxMesh.new()
	box.size = Vector3(PadDeck.WIDE, PadDeck.TOP - PadDeck.FOOT, TvSurface.DEPTH)
	panel.mesh = box
	panel.position = Vector3(0, (PadDeck.TOP + PadDeck.FOOT) * 0.5, -TvSurface.DEPTH * 0.5)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.11, 0.115, 0.13)
	paint.roughness = 0.6
	panel.material_override = paint
	deck.add_child(panel)
	# The pads, four by four, pad 1 at the bottom left as on an MPC.
	var grid := PadDeck.PAD * 4.0 + PadDeck.PAD_GAP * 3.0
	var left := -PadDeck.WIDE * 0.5 + 0.06
	var bottom := PadDeck.FOOT + (PadDeck.TOP - PadDeck.FOOT - grid) * 0.5
	for i in PadBank.PADS:
		var pad := PadDeck.Pad.new()
		pad.deck = deck
		pad.index = i
		pad.name = "Pad%d" % (i + 1)
		pad.position = Vector3(left + PadDeck.PAD * 0.5 + (i % 4) * (PadDeck.PAD + PadDeck.PAD_GAP),
				bottom + PadDeck.PAD * 0.5 + (i / 4) * (PadDeck.PAD + PadDeck.PAD_GAP), 0.006)
		deck.add_child(pad)
		deck.pads.append(pad)
	# The waveform on the right, the words over it, the keys under it.
	var wave_x := PadDeck.WIDE * 0.5 - 0.06 - PadDeck.WAVE.x * 0.5
	var wave_y := PadDeck.TOP - 0.05 - PadDeck.WAVE.y * 0.5
	var screen := MeshInstance3D.new()
	screen.name = "Waveform"
	var quad := QuadMesh.new()
	quad.size = PadDeck.WAVE
	screen.mesh = quad
	screen.position = Vector3(wave_x, wave_y, 0.002)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	deck._wave_texture = ImageTexture.create_from_image(Image.create(PadDeck.WAVE_PIXELS.x, PadDeck.WAVE_PIXELS.y, false, Image.FORMAT_RGB8))
	lit.albedo_texture = deck._wave_texture
	screen.material_override = lit
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deck.add_child(screen)
	deck._wave_words = _label(0.03, PadDeck.INK)
	deck._wave_words.name = "SampleWords"
	deck._wave_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	deck._wave_words.position = Vector3(wave_x - PadDeck.WAVE.x * 0.5, wave_y + PadDeck.WAVE.y * 0.5 + 0.018, 0.002)
	deck.add_child(deck._wave_words)
	deck._mode_words = _label(0.026, PadDeck.DIM)
	deck._mode_words.name = "ModeWords"
	deck._mode_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	deck._mode_words.position = Vector3(wave_x + PadDeck.WAVE.x * 0.5, wave_y + PadDeck.WAVE.y * 0.5 + 0.018, 0.002)
	deck.add_child(deck._mode_words)
	_build_keys(wave_x, wave_y)


## The keys under the waveform, on pages: a row of tabs (and STOP, always there) and the page's own
## keys in up to two rows, big enough to read. Only the page shown can be seen or pressed.
func _build_keys(wave_x: float, wave_y: float) -> void:
	var rows := [
		[["SAMPLE", "press at the start and again at the end of what to sample: from the TV's sound, or the source SRC names", deck.sample],
		["SRC", "where SAMPLE takes from: the TV, the MIX itself (resampling), the ROOM's sounds, or an audio input IN (a microphone, an interface, a phone linked in)", deck.step_source],
		["CHOP", "cut it by its hits, or into 16, 8 or 4 equal slices", deck.step_chop],
		["SCALE", "spread the last pad struck across all sixteen, in a key", deck.toggle_scale],
		["KEY", "the scale's root, a semitone up", func() -> void: deck.step_root(1)],
		["MODE", "the next scale: the seven modes, harmonic and melodic minor, pentatonics, blues, chromatic", deck.step_mode]],
		[["TRIG", "how the selected pad plays: ONE through, GATE while held, LOOP until struck again", func() -> void: deck._edit("mode", 1.0)],
		["REV", "play the selected pad's slice backwards", func() -> void: deck._edit("rev", 0.0)],
		["CHOKE", "the selected pad's choke group: pads of one group cut each other off (0 is none)", func() -> void: deck._edit("choke", 1.0)],
		["TUNE-", "the selected pad a semitone down", func() -> void: deck._edit("tune", -1.0)],
		["TUNE+", "the selected pad a semitone up", func() -> void: deck._edit("tune", 1.0)],
		["VOL-", "the selected pad quieter", func() -> void: deck._edit("vol", -0.1)],
		["VOL+", "the selected pad louder", func() -> void: deck._edit("vol", 0.1)],
		["KEYS", "the computer keys play the pads when you stand here: ZXCV ASDF QWER 1234, a MIDI keyboard's notes always", deck.toggle_keys]],
		[["IN-", "trim the selected pad's start later", func() -> void: deck._edit("start", 0.05)],
		["IN+", "trim the selected pad's start earlier", func() -> void: deck._edit("start", -0.05)],
		["OUT-", "trim the selected pad's end earlier", func() -> void: deck._edit("end", -0.05)],
		["OUT+", "trim the selected pad's end later", func() -> void: deck._edit("end", 0.05)],
		["DEV", "which input IN samples from: the default, then each microphone, interface or source this machine has", deck.step_device],
		["TRIM", "cut the quiet off the ends of what a live source catches (lit: on)", deck.toggle_trim],
		["ATK", "the selected pad's fade in: none, then longer", func() -> void: deck._cycle("atk")],
		["REL", "the selected pad's fade out: none, then longer", func() -> void: deck._cycle("rel")],
		["FILT", "the selected pad's filter: low pass closing, none, high pass opening", func() -> void: deck._cycle("filt")],
		["SEND", "how much of the selected pad goes to the effect (FX)", func() -> void: deck._cycle("send")],
		["LOCK", "key-lock: the selected pad's pitch changes (TUNE, SCALE) without its length changing", func() -> void: deck._edit("lock", 0.0)]],
		[["PAN<", "the selected pad toward the left", func() -> void: deck._edit("pan", -0.25)],
		["PAN>", "the selected pad toward the right", func() -> void: deck._edit("pan", 0.25)],
		["FX", "the effect the SEND goes to: reverb, delay or both", deck.step_fx],
		["LEARN", "then strike a key on a MIDI keyboard: that note is the selected pad (the others follow in order)", deck.toggle_learn],
		["SEQ", "play the armed track's recorded notes through the pads while the song plays", deck.toggle_follow],
		["STOP", "silence every pad", deck.stop_all],
		["FIT", "stretch the selected pad's slice, pitch kept, to a sixteenth, an eighth, a beat, two or four at the song's tempo", deck.step_fit],
		["CH", "the MIDI channel the pads listen to: ALL, then 1 to 16 (so another controller can play the instrument)", deck.step_channel],
		["PUNCH", "send every pad to the effect while this is lit", deck.toggle_punch]],
		[["SAVE", "keep the selected pad's sound in your library of samples", deck.save_to_library],
		["LIB", "browse your library of samples (press again for the next)", deck.library.step_library],
		["LOAD", "put the sample LIB shows on the selected pad", deck.load_from_library],
		["KSAVE", "keep all sixteen pads, with their settings, as a kit in your library", deck.save_kit],
		["KITS", "browse your kits (press again for the next)", deck.step_kits],
		["KLOAD", "put the kit KITS shows on the pads", deck.load_kit],
		["DEL", "delete the sample or kit just browsed (press twice)", deck.delete_browsed],
		["SYNC", "a guest's: take the room's pads back, as the host has them, in place of sounds of your own", deck.rejoin]]]
	var defs := {}
	for row in rows:
		for k in row:
			defs[k[0]] = k
	var top := wave_y - PadDeck.WAVE.y * 0.5 - 0.016
	var tabs := []
	for page in PadDeck.PAGES:
		tabs.append([page, PadDeck.PAGE_SAYS[page], func() -> void: show_page(page)])
	tabs.append(defs["STOP"])
	_place_row(tabs, 0, top, wave_x, "tab")
	deck._page_keys.clear()
	for page in PadDeck.PAGES:
		var keys_here: Array = []
		var lines: Array = PadDeck.PAGES[page]
		for r in lines.size():
			var row: Array = []
			for legend in lines[r]:
				row.append(defs[legend])
				keys_here.append(legend)
			_place_row(row, r + 1, top, wave_x, "page")
		deck._page_keys[page] = keys_here
	show_page(deck.page_shown)
	deck._built = true


## One row of keys, `r` rows down from `top`, each as wide as fits (never wider than KEY).
func _place_row(row: Array, r: int, top: float, wave_x: float, kind: String) -> void:
	var width := minf(PadDeck.KEY.x, (PadDeck.WAVE.x - (row.size() - 1) * PadDeck.KEY_GAP) / row.size())
	var across := row.size() * width + (row.size() - 1) * PadDeck.KEY_GAP
	for i in row.size():
		var key := EqWall.WallKey.new()
		var legend: String = row[i][0]
		key.name = "Key" + legend.capitalize().replace("+", "Up").replace("-", "Down").replace("<", "Left").replace(">", "Right")
		key.legend = legend
		key.says = row[i][1]
		key.size = Vector2(width, PadDeck.KEY.y)
		var called := "PADS  " + legend
		key.describe_title = func() -> String: return called
		key.position = Vector3(wave_x - across * 0.5 + width * 0.5 + i * (width + PadDeck.KEY_GAP),
				top - PadDeck.KEY.y * 0.5 - r * (PadDeck.KEY.y + PadDeck.KEY_GAP_Y), 0.011)
		key.pressed.connect(row[i][2])
		deck.add_child(key)
		deck.keys[legend] = key


## Page `page` of keys shown (the tabs and STOP always are): the rest hidden and out of reach.
func show_page(page: String) -> void:
	if not PadDeck.PAGES.has(page):
		return
	deck.page_shown = page
	for legend in deck.keys:
		var key := deck.keys[legend] as EqWall.WallKey
		var here: bool = PadDeck.PAGES.has(legend) or legend == "STOP" or (deck._page_keys.get(page, []) as Array).has(legend)
		key.visible = here
		key.collision_layer = 2 if here else 0
	if deck._built:
		deck.refresh()


func _label(cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = PadDeck.PIXEL
	l.font_size = roundi(cap / PadDeck.PIXEL)
	l.modulate = colour
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l
