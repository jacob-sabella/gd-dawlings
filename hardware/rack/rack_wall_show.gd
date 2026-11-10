class_name RackWallShow
extends RefCounted

## What the rack shows of the room: the patch, knob values, steps, scopes, meters, the keys that are down and the
## cables laid between jacks. Moved out of `hardware/rack/rack_wall.gd` without change of behaviour; the wall never changes
## the patch, it only shows it.

var wall: RackWall


func _init(of: RackWall) -> void:
	wall = of


## The track the rack sounds through (0 for none) and its name, on the TRK key.
func set_track(t: int, track_name := "") -> void:
	if t == wall._track and track_name == wall._track_name:
		return
	wall._track = t
	wall._track_name = track_name
	wall.keys._build_palette()


## Light the POWER key, and rebuild the palette if it changed.
func set_power(on: bool) -> void:
	if on != wall._power:
		wall._power = on
		wall.keys._build_palette()


## Light the REC state on the wall and rebuild the key palette if it changed.
func set_recording(on: bool) -> void:
	if on != wall._recording:
		wall._recording = on
		wall.keys._build_palette()


## Show the palette group `g` and rebuild the key palette.
func show_group(g: String) -> void:
	wall.group = g
	wall.keys._build_palette()


## The room's patch, shown. The modules are rebuilt only when their shape changes (one put in, taken
## out, moved, or a different set of knobs); a cable or a knob value changes in place.
func show_patch(to: Dictionary) -> void:
	wall.patch = RackPatch.sanitize(to)
	var changed := {}
	var first := wall._palette_nodes.is_empty()
	if first:
		wall.modules._clear_modules()
	var shape := _shape_of(wall.patch)
	if shape != wall._shape_key or first:
		wall._shape_key = shape
		changed = wall.modules._sync_modules()
		wall.modules._build_blanks()
		wall.dressing._seat_pillars()
		if first:
			wall.keys._build_palette()
	for key: String in wall.knobs:
		var k: Knob = wall.knobs[key]
		if not k.is_held() and not wall._settle_at.has(key):
			k.apply_remote(RackPatch.knob_of(wall.patch, key.get_slice(".", 0), key.get_slice(".", 1)))
	for key: String in wall.jacks:
		var j: RackJack = wall.jacks[key]
		var path := String(j.jack)
		j.plugged_to.clear()
		for c in wall.patch["cables"]:
			if j.output and c[0] == path:
				j.plugged_to.append(StringName(c[1]))
			elif not j.output and c[1] == path:
				j.plugged_to.append(StringName(c[0]))
	wall.modules._refresh_faces()
	_lay_cables(changed)
	wall._apply_reach()


func _shape_of(p: Dictionary) -> String:
	var parts: Array = []
	for id in RackPatch.module_ids(p):
		parts.append("%s:%s@%s,%s%s" % [id, p["modules"][id]["type"], p["modules"][id]["at"][0], p["modules"][id]["at"][1],
				"!" if RackPatch.is_missing(p, id) else ""])
	return "|".join(parts)


## Set knob `k` of module `id` to `v` in the wall's patch and move the knob node (and a pad's orb) to match.
func show_knob(id: String, k: String, v: float) -> void:
	RackPatch.set_knob(wall.patch, id, k, v)
	var node: Knob = wall.knobs.get("%s.%s" % [id, k])
	if node != null:
		node.apply_remote(v)
	if wall._pads.has(id):
		wall.modules._refresh_faces(id)


## How loud each module is now ({id: peak}), on its lamp.
## The module meters in the order of the modules across the case, for the room's own lights.
func module_levels(meters: Dictionary) -> Array:
	var out := []
	for id in wall._pillar_for:
		out.append(float(meters.get(id, 0.0)) if id != "" else 0.0)
	return out


## The traces of the SCOPE modules' screens: module id -> points.
## The step each sequencer is on, lit on its bars.
func show_steps(on: Dictionary) -> void:
	for id: String in wall._pads:
		var node: Node = wall._pads[id]["node"]
		if node is RackBars and is_instance_valid(node):
			(node as RackBars).set_playhead(int(on.get(id, -1)))


## Give each SCOPE module its wave from `waves` ({module id: samples}).
func show_scopes(waves: Dictionary) -> void:
	for id: String in wall._scopes:
		if is_instance_valid(wall._scopes[id]):
			(wall._scopes[id] as ScopeScreen).set_wave(waves.get(id, PackedFloat32Array()))


## Move the level pillars and lamps to the engine's `meters` ({module id: 0..1}), rising fast and falling slowly.
func show_meters(meters: Dictionary) -> void:
	for n in wall._pillars.size():
		var id: String = wall._pillar_for[n]
		var want := clampf(float(meters.get(id, 0.0)), 0.0, 1.0) if id != "" else 0.0
		var now := wall._pillar_level[n]
		wall.dressing._grow_pillar(n, lerpf(now, want, 0.5 if want > now else 0.15))
	for id: String in wall._lamps:
		var on := float(meters.get(id, 0.0)) > 0.02
		var lamp: MeshInstance3D = wall._lamps[id]
		if is_instance_valid(lamp):
			var want := wall._lamp_hot if on else wall._lamp_cold
			if lamp.material_override != want:
				lamp.material_override = want
		var band: StandardMaterial3D = wall._bands.get(id)
		if band != null:
			band.emission_enabled = on
			band.emission_energy_multiplier = 0.8 + clampf(float(meters.get(id, 0.0)), 0.0, 1.0) * 1.6
	# Each cable glows with what its source is putting out, so the signal can be followed by eye.
	for cable in wall.cables:
		if is_instance_valid(cable):
			var ends: Array = cable.get_meta(&"cable", [])
			if ends.size() == 2:
				cable.set_glow(clampf(float(meters.get(String(ends[0]).get_slice(".", 0), 0.0)) * 1.6, 0.0, 1.0))


## The knobs a hand is holding or that are still settling after one: {"id.knob": value}.
func turning() -> Dictionary:
	var out := {}
	for key: String in wall.knobs:
		var k: Knob = wall.knobs[key]
		if k.is_held() or wall._settle_at.has(key):
			out[key] = k.value
	return out


## The cables the patch has, each stood between its two plugs. A cable already stood and unchanged is
## kept: only those that are new, whose plug-in module is in `touching` (one moved, put in or lifted), or
## whose fan-out place changed are made again, so a module let go costs its own cables and not the case's.
func _lay_cables(touching := {}) -> void:
	var standing := {}
	for c in wall.cables:
		if is_instance_valid(c):
			var ends: Array = c.get_meta(&"cable", [])
			if ends.size() == 2 and wall.is_inside_tree():
				standing[String(ends[0]) + ">" + String(ends[1])] = c
				continue
			# Out of the tree at once, so a laid-again cable never stands over its predecessor.
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	wall.cables.clear()
	if not wall.is_inside_tree():
		return
	var fanned := {}
	for c: Array in wall.patch["cables"]:
		var a: RackJack = wall.jacks.get(wall._jack_key(c[0], true))
		var b: RackJack = wall.jacks.get(wall._jack_key(c[1], false))
		var fan: int = fanned.get(c[0], 0)
		fanned[c[0]] = fan + 1
		if a == null or b == null:
			continue
		var key := String(c[0]) + ">" + String(c[1])
		var old: PatchCable = standing.get(key)
		if old != null and int(old.get_meta(&"fan", 0)) == fan \
				and not touching.has(String(c[0]).get_slice(".", 0)) and not touching.has(String(c[1]).get_slice(".", 0)):
			standing.erase(key)
			wall.cables.append(old)
			continue
		var tint := RackSkin.signal_of(String(c[0]).get_slice(".", 1))
		# A second cable from one output stands its plug further out, so the plugs never share a face.
		var from_plug := a.plug_transform()
		from_plug.origin += from_plug.basis.z.normalized() * 0.014 * fan
		var cable := PatchCable.create(from_plug, b.plug_transform(), tint, hash(c))
		cable.name = "Cable_%s_%s" % [c[0], c[1]]
		# Lit from within and drawn thicker than life: the wall is dark and seen from across the room.
		cable.lit = true
		cable.flow = true
		cable.thickness = 2.0
		var span := a.plug_transform().origin.distance_to(b.plug_transform().origin)
		cable.sag_ratio = RackWall.CABLE_SAG if absf(a.global_position.x - b.global_position.x) < RackWall.MODULE_WIDE * 2.0 \
				else clampf(0.25 / maxf(span, 0.05), RackWall.CABLE_SAG, 0.6)
		cable.set_meta(&"cable", [c[0], c[1]])
		cable.set_meta(&"fan", fan)
		if old != null:
			standing.erase(key)
			wall._drop(old)
		wall.add_child(cable)
		wall.cables.append(cable)
	for gone: PatchCable in standing.values():
		wall._drop(gone)
	if wall._stubs.get_parent() == null:
		wall._stubs.pull_asked.connect(func(from: String, to: String) -> void: wall.edit_asked.emit("pull_one", [from, to]))
		wall.add_child(wall._stubs)
	wall._stubs.lay(wall.patch, wall.jacks, func(legend: String, at: Vector3, says: String, press: Callable) -> Node3D:
		var k := wall._key(legend, Vector2(0.02, 0.02), at, says, press)
		return k)


## Light the play key to the gate of a played note.
func show_keys(pitch: int, gate: bool) -> void:
	if wall.play_key != null:
		wall.play_key.lit = gate


## Light the play key while the rack is being played from the computer keys.
func show_playing(on: bool) -> void:
	wall._playing = on
	if wall.play_key != null:
		wall.play_key.lit = on
