class_name RackWallKeys
extends RefCounted

## The rack's touch keys, the legends and key plates, the palette under the modules and the track legend. Moved
## out of `hardware/rack/rack_wall.gd` without change of behaviour; the state stays on the wall.

var wall: RackWall

## Groups with too many modules for keys: their key opens the module finder instead.
const FINDER_GROUPS: Array[String] = ["Airwindows"]


func _init(of: RackWall) -> void:
	wall = of


func _build_touch() -> void:
	var holder := Node3D.new()
	holder.name = "TouchKeys"
	holder.position = Vector3(RackWall.TOUCH_X, RackWall.TOUCH_Y, RackWall.TOUCH_Z)
	wall._adopt(holder)
	var plate := MeshInstance3D.new()
	plate.name = "TouchPlate"
	var board := BoxMesh.new()
	board.size = Vector3(RackWall.TOUCH_SIZE.x * RackWall.TOUCH_COUNT + 0.02, 0.006, RackWall.TOUCH_SIZE.y + 0.02)
	plate.mesh = board
	plate.position = Vector3(0, -0.001, 0)
	plate.material_override = Materials.chassis()
	holder.add_child(plate)
	for n in RackWall.TOUCH_COUNT:
		var key := ModularTouch.new()
		key.name = "Touch%d" % n
		key.step = n
		key.base = wall.touch_base
		key.size = RackWall.TOUCH_SIZE
		key.position = Vector3(-RackWall.TOUCH_SIZE.x * (RackWall.TOUCH_COUNT - 1) * 0.5 + RackWall.TOUCH_SIZE.x * n, 0.002, 0)
		key.pressed.connect(func(p: int, down: bool) -> void: wall.touched.emit(p, down))
		key.octave_asked.connect(_move_octave)
		holder.add_child(key)
		wall.touch_keys.append(key)


func _move_octave(by: int) -> void:
	wall.touch_base = clampi(wall.touch_base + by * 12, 24, 84)
	for key in wall.touch_keys:
		key.set_base(wall.touch_base)


func _letter(text: String, cap: float, at: Vector3, colour: Color, width := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.0002
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	if width > 0.0:
		Lettering.fit(l, width, l.font_size, 24)
	Lettering.range_to_legibility(l)
	return l


## A key on the panel.
func _key(legend: String, size: Vector2, at: Vector3, says: String, press: Callable, lit := false) -> EqWall.WallKey:
	var k := EqWall.WallKey.new()
	k.legend = legend
	k.size = size
	k.says = says
	k.position = at
	k.lit = lit
	k.describe_title = func() -> String: return "RACK  %s" % legend
	k.pressed.connect(press)
	# A legend that is longer than its key is set smaller, to fit.
	k.ready.connect(func() -> void:
		var l := k.get_node_or_null("Legend") as Label3D
		var need := legend.length() * 0.0195
		if l != null and need > size.x - 0.012:
			l.font_size = maxi(8, roundi(l.font_size * (size.x - 0.012) / need)))
	return k


func _build_palette() -> void:
	for n in wall._palette_nodes:
		if is_instance_valid(n):
			wall._drop(n)
	wall._palette_nodes.clear()
	var groups: Array = RackCatalogue.groups()
	groups.append(RackWall.GROUP_PRESETS)
	var key_size := Vector2(RackWall.MODULE_WIDE - 0.008, 0.05)
	for i in groups.size():
		var g: String = groups[i]
		var k := _key(g.to_upper(), key_size,
				Vector3(wall._x_of(i + 0.5), RackWall.PALETTE_TALL - 0.04, 0.0), "show the %s modules" % g.to_lower(),
				(func() -> void: wall.find_asked.emit(g)) if g in FINDER_GROUPS else (func() -> void: wall.shown.show_group(g)),
				g == wall.group)
		wall._palette_nodes.append(k)
		wall.panel.add_child(k)
		k.set_meta("built", true)
	wall._extras.clear()
	var extra := [[9.5, "PLAY", "play the rack from the computer keys", func() -> void: wall.keys_asked.emit(), wall._playing, "play"],
			[11.5, _track_legend(), "choose the track the rack sounds through (round the tracks, then none)",
			func() -> void: wall.track_asked.emit(), wall._track > 0, "track"],
			[13.5, "REC", "record what the rack plays onto its track; again to keep it",
			func() -> void: wall.record_asked.emit(), wall._recording, "rec"],
			[15.5, "TIDY", "lay the modules out as the signal flows, sources at the left and the OUT at the right",
			func() -> void: wall.edit_asked.emit("tidy", []), false, "tidy"],
			[17.5, "FIND", "search every module by name, kind or knob and put one in the case",
			func() -> void: wall.find_asked.emit(""), false, "find"]]
	for e in extra:
		var xk := _key(String(e[1]), key_size, Vector3(wall._x_of(e[0]), RackWall.PALETTE_TALL - 0.04, 0.0), String(e[2]), e[3], e[4])
		wall._palette_nodes.append(xk)
		wall.panel.add_child(xk)
		xk.set_meta("built", true)
		wall._extras[e[5]] = xk
		if e[5] == "play":
			wall.play_key = xk
	# What the cables' colours mean.
	var legend := [["AUDIO", RackSkin.SIGNAL_AUDIO], ["PITCH", RackSkin.SIGNAL_PITCH],
			["GATE", RackSkin.SIGNAL_GATE], ["CV", RackSkin.SIGNAL_CV]]
	for n in legend.size():
		var tag := _letter("o " + String(legend[n][0]), RackWall.LETTER_CAP, Vector3(wall._x_of(19.5 + n * 2.2), RackWall.PALETTE_TALL - 0.04, 0.0), legend[n][1])
		wall._palette_nodes.append(tag)
		wall.panel.add_child(tag)
	var items: Array = []
	if wall.group == RackWall.GROUP_PRESETS:
		for p in RackPatch.presets():
			items.append([String(p), RackPatch.preset_title(p), "preset", [String(p)]])
	else:
		for t in RackCatalogue.in_group(wall.group):
			items.append([t, String(RackCatalogue.spec(t)["title"]), "add", [t, -1, 0]])
	for i in mini(items.size(), RackWall.COLS):
		var it: Array = items[i]
		var says := ("put a %s in the next free place in the case" % it[1]) if it[2] == "add" \
				else "replace the case with the preset %s" % it[1]
		var op: String = it[2]
		var args: Array = it[3]
		var k := _key(String(it[1]).substr(0, 8), key_size, Vector3(wall._x_of(i + 0.5), 0.045, 0.0), says,
				func() -> void: wall.edit_asked.emit(op, args))
		wall._palette_nodes.append(k)
		wall.panel.add_child(k)
		k.set_meta("built", true)
	wall._apply_reach()


func _track_legend() -> String:
	if wall._track <= 0:
		return "TRK -"
	return ("T%d %s" % [wall._track, wall._track_name]).substr(0, 8)
