extends RefCounted

## Control tools: room. See core/control/control_tools.gd and docs/mcp_assistant.md.
##
## Every write is a room verb asked through `Session.ask_room` (the verbs in `Session.ROOM_VERBS`), exactly as the
## controls ask it, so the host's rules, the guests' prediction and the refusals are the game's own. Tools that
## need the room itself (reads, the venue switch, the layout's whole) go through `api.studio`; without one they
## say so. `EXPOSED` and `NOT_EXPOSED` together name every room verb: a verb added to `ROOM_VERBS` is in neither
## until someone decides, and the test fails until then.

## verb -> the tool that asks it.
const EXPOSED := {
	&"tv": "room_tv", &"open_tablet": "room_tablet_open", &"close_tablet": "room_tablet_close",
	&"move_tablet": "room_tablet_move", &"move_piece": "room_piece_move", &"place_surface": "room_surface_place",
	&"put_item": "room_item_put", &"home_item": "room_item_home", &"throw_item": "room_item_throw",
	&"wear_item": "room_item_wear", &"pocket_item": "room_item_pocket", &"patch": "room_patch",
	&"on_air": "room_on_air", &"take_personal": "room_take_personal", &"board_source": "room_board_source",
	&"open_track_rack": "room_track_rack_open", &"close_track_rack": "room_track_rack_close",
	&"plug": "room_plug", &"harmony": "room_harmony", &"rope": "room_rope", &"make": "room_item_make",
	&"slot_item": "room_item_slot", &"give": "room_item_give", &"paste": "room_paste",
	&"sampler": "room_sampler", &"weather": "room_weather", &"scratch": "room_scratch",
	&"looper": "room_looper", &"layout": "room_layout_edit",
}

## verb -> why no tool asks it.
const NOT_EXPOSED := {
	&"looper_layer": "a guest's finished looper layer, written by the host as that guest's track: the looper's own pad sends it, never an assistant",
	&"rack": "the rack has its own domain (rack_* tools), which asks this verb with its own shapes",
	&"look_solo": "driven by where a person looks or holds; an assistant has no gaze to follow (use the mix tools to solo)",
}

const LIST_MAX := 200


# --- plumbing ----------------------------------------------------------------------------------------

static func _studio(api: ControlApi) -> Studio:
	return api.studio as Studio if is_instance_valid(api.studio) else null


static func _need_studio(api: ControlApi) -> Dictionary:
	if _studio(api) == null:
		return ControlTool.fail("there is no running room (no studio) to do that in")
	return {}


## Ask the room for `verb` with `args` (already the verb's typed list). The host answers at once when this
## machine is the host, and says why not (Session.tell, which arrives as `notice`) when it will not: that
## text is the error. A guest's ask is answered later by the host, so only that it was sent is known.
static func ask(verb: StringName, args: Array) -> Dictionary:
	if not SessionRoom.room_ask_is_valid(verb, args):
		return ControlTool.fail("internal: '%s' does not take those argument types" % verb)
	var told: Array[String] = []
	var catch := func(text: String) -> void: told.append(text)
	Session.notice.connect(catch)
	var seq: int = Session.ask_room(verb, args)
	Session.notice.disconnect(catch)
	if not told.is_empty():
		return ControlTool.fail(" ".join(PackedStringArray(told)))
	if not Session.is_authority():
		if seq == 0:
			return ControlTool.fail("not connected to the host, so the room could not be asked")
		return ControlTool.ok({"asked": String(verb), "pending": true, "note": "asked of the host, who decides; read the room to see"})
	return ControlTool.ok({"asked": String(verb)})


static func _verb_tool(api: ControlApi, name: String, summary: String, props: Dictionary, required: Array, tier: int,
		verb: StringName, convert: Callable) -> void:
	var T := ControlTool
	api.add(T.make(name, summary, props, required, tier, func(a: Dictionary) -> Dictionary:
		var args: Variant = convert.call(a)
		if typeof(args) == TYPE_STRING:
			return T.fail(args)
		return ask(verb, args)))


static func _f(v: Variant) -> float:
	return float(v)


static func _vec(v: Variant, fallback := Vector3.ZERO) -> Variant:
	if v == null:
		return fallback
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return null
	for n in v:
		if typeof(n) != TYPE_INT and typeof(n) != TYPE_FLOAT:
			return null
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _item_known(api: ControlApi, id: String) -> String:
	var s := _studio(api)
	if s != null and s.items != null and not s.items.items.has(StringName(id)):
		var ids := PackedStringArray()
		for k in s.items.items.keys():
			ids.append(String(k))
			if ids.size() >= 30:
				break
		return "no item '%s'; the items are: %s" % [id, ", ".join(ids)]
	return ""


static func _piece_known(api: ControlApi, id: String) -> String:
	var s := _studio(api)
	if s != null and s.floor_plan != null and s.room_rows._floor_piece(StringName(id)) == null:
		return "no movable piece '%s'; see room_pieces_list" % id
	return ""


static func _track(ref: Variant) -> Dictionary:
	return ControlRefs.track(DAW.state, ref)


static func _page(rows: Array, a: Dictionary) -> Dictionary:
	var off := int(a.get("offset", 0))
	var lim := int(a.get("limit", 50))
	return {"total": rows.size(), "offset": off, "rows": rows.slice(off, off + lim)}


static func _round(v: float) -> float:
	return snappedf(v, 0.001)


# --- registration -----------------------------------------------------------------------------------------

static func register(api: ControlApi) -> void:
	_reads(api)
	_venue_and_layout(api)
	_pieces(api)
	_items(api)
	_gear(api)


static func _reads(api: ControlApi) -> void:
	var T := ControlTool
	api.add(T.make("room_get",
			"A summary of the room now: the venue and its arrangement, who is here, who is on air, whether the weather listens, the TV, and how many tablets, pieces and items are out. Start here; the room_*_list tools give the detail.",
			{}, [], T.READ, func(_a: Dictionary) -> Dictionary:
				var s := _studio(api)
				var out := {"role": Session.Role.keys()[Session.role], "authority": Session.is_authority(), "me": Session.local_peer_id}
				var who: Array = []
				for peer in Session.participants:
					var p: Variant = Session.participants[peer]
					who.append({"peer": peer, "name": str(p.get("name")) if p is Object and p.get("name") != null else ""})
				out["here"] = who
				if s == null:
					out["rows"] = Session.room.keys()
					out["note"] = "no studio: only the session's last room row is known"
					return T.ok(out)
				var row := s.room_rows.room_state()
				if s.venue != null:
					out["venue"] = {"id": String(s.venue.venue_id()), "title": s.venue.title(), "variant": s.venue.variant,
							"arrangements": Array(Venue.variant_titles(s.venue.venue_id()))}
				out["on_air"] = s.on_air.duplicate()
				out["weather_listening"] = s.weather_listening
				out["tv"] = row.get("tv", {})
				out["board_source"] = String(s.board_source)
				out["counts"] = {"tablets": s.tablets.size(), "track_racks": s.track_racks.size(),
						"items_away_from_home": (row.get("items", {}) as Dictionary).size(),
						"made_items": (row.get("made", []) as Array).size(),
						"pieces": RoomFloor.room_pieces(s).size()}
				out["looper"] = row.get("looper", [])
				out["sampler_armed_by"] = row.get("sampler", 0)
				out["jacks"] = row.get("jacks", {})
				out["patches"] = row.get("patches", {})
				return T.ok(out)))


static func _venue_and_layout(api: ControlApi) -> void:
	var T := ControlTool
	api.add(T.make("room_venue_list",
			"The venues the room can be in: id, title, the names of its arrangements (variant 0, 1, 2), and which one is current.",
			{}, [], T.READ, func(_a: Dictionary) -> Dictionary:
				var s := _studio(api)
				var out: Array = []
				for id in VenueCatalogue.ids():
					out.append({"id": String(id), "title": VenueCatalogue.title_of(id),
							"arrangements": Array(Venue.variant_titles(id)),
							"current": s != null and s.venue != null and s.venue.venue_id() == id})
				return T.ok(out)))
	api.add(T.make("room_venue_set",
			"Move the room to another venue (an id from room_venue_list) and arrangement; the room is rebuilt round the player. Only the host (or someone alone) can.",
			{"venue": T.str_p("a venue id from room_venue_list"), "variant": T.int_p("arrangement number, 0 first", 0, 8)},
			["venue"], T.EDIT, func(a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				if not Session.is_authority():
					return T.fail("only the host chooses the venue")
				var id := StringName(str(a["venue"]))
				if not Venue.is_known(id):
					return T.fail("no venue '%s'; the venues are: %s" % [id, ", ".join(PackedStringArray(VenueCatalogue.ids().map(func(x: StringName) -> String: return String(x))))])
				var s := _studio(api)
				s.set_venue(id, true, Venue.known_variant(id, int(a.get("variant", 0))))
				return T.ok({"venue": String(id), "variant": s.venue.variant if s.venue != null else 0})))

	api.add(T.make("room_layout_list",
			"The rooms' layouts that exist: every venue (with its arrangements) and the rooms this player made, and the key of the one standing now.",
			{}, [], T.READ, func(_a: Dictionary) -> Dictionary:
				var s := _studio(api)
				var out := {"venues": [], "made": MadeRooms.ids().map(func(x: StringName) -> String: return String(x))}
				for id in VenueCatalogue.ids():
					(out["venues"] as Array).append({"id": String(id), "arrangements": Array(Venue.variant_titles(id))})
				if s != null:
					out["current"] = s.room_deltas.delta.room
				return T.ok(out)))
	api.add(T.make("room_layout_get",
			"This room's layout as changed from the venue's own: pieces moved, added, removed (the room delta), plus the problem the last save had, if any. Piece positions are metres, yaw radians.",
			{}, [], T.READ, func(_a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				var s := _studio(api)
				return T.ok({"room": s.room_deltas.delta.room, "delta": RoomFloor.row(s), "last_problem": s.room_deltas.last_problem})))
	api.add(T.make("room_layout_set",
			"Replace the room's whole layout change set with `delta` (the shape room_layout_get returns: moved, added, removed, restored). Refused, with the reason, if the result would not stand (pieces overlapping, off the floor). Host only.",
			{"delta": T.obj_p("a room delta: {moved: {id: [x, z, yaw]}, added: [...], removed: [ids], restored: [ids]}")},
			["delta"], T.DESTRUCTIVE, func(a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				var s := _studio(api)
				if not Session.is_authority():
					return T.fail(LayoutEdit.HOST_ONLY)
				var raw: Dictionary = (a["delta"] as Dictionary).duplicate(true)
				if not raw.has("format"):
					raw["format"] = RoomDelta.FORMAT
				if not raw.has("version"):
					raw["version"] = RoomDelta.VERSION
				var d := s.room_deltas.delta
				raw["room"] = d.room
				raw["base"] = String(d.base)
				raw["variant"] = d.variant
				var why := RoomDelta.problem(raw)
				if why != "":
					return T.fail(why)
				var candidate := RoomDelta.from_dict(raw)
				if candidate == null:
					return T.fail("that is not a room delta")
				why = s.layout_edit.refusal(candidate)
				if why != "":
					return T.fail(why)
				candidate.rev = d.rev + 1
				s.room_deltas.commit(candidate)
				RoomFloor.follow(s, {}, false)
				s.player_host._publish_room_soon()
				return T.ok({"room": candidate.room, "moved": candidate.moved.size(), "added": candidate.added.size(), "removed": candidate.removed.size()})))
	api.add(T.make("room_layout_save",
			"Write the room's layout changes to disk now (they are otherwise written a second after the last edit).",
			{}, [], T.EDIT, func(_a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				_studio(api).room_deltas.flush()
				return T.ok({"saved": _studio(api).room_deltas.delta.room})))

	_verb_tool(api, "room_layout_edit",
			"Edit the room's layout the way the layout editor does, one op at a time: move (piece, x, z, optional yaw), rotate (piece, yaw), add (kind, optionally x, z, yaw), remove (piece), reset (piece, or 'all'). Metres and radians. The game refuses an arrangement that would not stand and says why. Host only (a guest may only push a piece on wheels).",
			{"op": T.str_p("what to do", ["move", "rotate", "add", "remove", "reset"]),
			"piece": T.str_p("piece id (room_pieces_list) or, for add, the kind of piece (hoop ...); 'all' for reset"),
			"x": T.num_p("metres, room frame"), "z": T.num_p("metres, room frame"), "yaw": T.num_p("radians")},
			["op", "piece"], T.EDIT, &"layout", _layout_args)


static func _layout_args(a: Dictionary) -> Variant:
	var piece := str(a["piece"])
	var has_at: bool = a.has("x") and a.has("z")
	match str(a["op"]):
		"move":
			if not has_at:
				return "move needs x and z"
			var args: Array = [piece, _f(a["x"]), _f(a["z"])]
			if a.has("yaw"):
				args.append(_f(a["yaw"]))
			return [&"move", args]
		"rotate":
			if not a.has("yaw"):
				return "rotate needs yaw"
			return [&"rotate", [piece, _f(a["yaw"])]]
		"add":
			if a.has("x") != a.has("z"):
				return "add takes both x and z, or neither"
			if has_at:
				return [&"add", [piece, _f(a["x"]), _f(a["z"]), _f(a.get("yaw", 0.0))]]
			return [&"add", [piece]]
		"remove":
			return [&"remove", [piece]]
		_:
			return [&"reset", [piece]]


static func _pieces(api: ControlApi) -> void:
	var T := ControlTool
	api.add(T.make("room_pieces_list",
			"The furniture that stands on the floor and can be moved (trolleys: rack, deck, stage table, TV mount ...) with where each is, and the gear that is placed in the room (surfaces). Ids are what room_piece_move, room_surface_place and room_layout_edit take.",
			{}, [], T.READ, func(_a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				var s := _studio(api)
				var pieces: Array = []
				for t in RoomFloor.room_pieces(s):
					pieces.append({"id": String(t.piece_id), "x": _round(t.position.x), "z": _round(t.position.z),
							"yaw": _round(t.rotation.y), "at_default": RoomFloor.at_default(s, t), "visible": t.visible})
				var surfaces: Array = []
				if s.mount != null:
					for sid in s.mount.mounted_ids():
						var home: Variant = s.mount.studio_home(sid)
						var row := {"id": String(sid), "seated": s.mount.seats.has(sid)}
						if home is Transform3D:
							row["x"] = _round((home as Transform3D).origin.x)
							row["y"] = _round((home as Transform3D).origin.y)
							row["z"] = _round((home as Transform3D).origin.z)
						surfaces.append(row)
				return T.ok({"pieces": pieces, "surfaces": surfaces})))
	_verb_tool(api, "room_piece_move",
			"Push a piece of furniture (a trolley from room_pieces_list) to x, z metres and a heading in radians; it rolls there and the floor plan may settle it clear of its neighbours.",
			{"piece": T.str_p("piece id"), "x": T.num_p("metres"), "z": T.num_p("metres"), "yaw": T.num_p("radians")},
			["piece", "x", "z", "yaw"], T.EDIT, &"move_piece", func(a: Dictionary) -> Variant:
				var why := _piece_known(api, str(a["piece"]))
				if why != "":
					return why
				return [StringName(str(a["piece"])), _f(a["x"]), _f(a["z"]), _f(a["yaw"])])
	_verb_tool(api, "room_surface_place",
			"Stand a piece of gear (a surface from room_pieces_list: the console, ...) somewhere in the studio: position x, y, z in metres and yaw in radians. Becomes the host's own placement for that room.",
			{"surface": T.str_p("surface id"), "x": T.num_p("metres"), "y": T.num_p("metres, up"), "z": T.num_p("metres"),
			"yaw": T.num_p("radians")},
			["surface", "x", "y", "z"], T.EDIT, &"place_surface", func(a: Dictionary) -> Variant:
				return [StringName(str(a["surface"])),
						Transform3D(Basis(Vector3.UP, _f(a.get("yaw", 0.0))), Vector3(_f(a["x"]), _f(a["y"]), _f(a["z"])))])

	api.add(T.make("room_tablets_list",
			"The plugin tablets standing in the room (a plugin lifted out to a stand) and the track racks pulled out: id, track, fx, position.",
			{}, [], T.READ, func(_a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				var s := _studio(api)
				var tablets: Array = []
				for id in s.tablets:
					var stand: Trolley = s.tablets[id][0]
					var t: PluginTablet = s.tablets[id][1]
					tablets.append({"id": String(id), "track": t.track_index, "fx": t.fx_index, "plugin": t.fx_name,
							"x": _round(stand.position.x), "z": _round(stand.position.z), "yaw": _round(stand.rotation.y)})
				var racks: Array = []
				for id in s.track_racks:
					var stand: Trolley = s.track_racks[id][0]
					racks.append({"id": String(id), "track": (s.track_racks[id][1] as RackSurface).track_index,
							"x": _round(stand.position.x), "z": _round(stand.position.z)})
				return T.ok({"tablets": tablets, "track_racks": racks})))
	_verb_tool(api, "room_tablet_open",
			"Lift a plugin out of a track's FX chain onto a stand in the room, at x, z metres. The track is a name or '#number'; fx is its place in the chain, 0 first (fx_list shows them). One tablet per plugin: asking again moves it.",
			{"track": T.ref_p("track name or number"), "fx": T.int_p("position in the track's FX chain, 0 first", 0), "x": T.num_p("metres"), "z": T.num_p("metres")},
			["track", "fx", "x", "z"], T.EDIT, &"open_tablet", func(a: Dictionary) -> Variant:
				var r := _track(a["track"])
				if not r["ok"]:
					return r["error"]
				var f: Variant = DAW.state.fx(int(r["index"]), int(a["fx"]), false)
				if f == null:
					return "track %s has no plugin at position %d" % [a["track"], int(a["fx"])]
				return [int(r["index"]), int(a["fx"]), str(f.name), _f(a["x"]), _f(a["z"])])
	_verb_tool(api, "room_tablet_close",
			"Put a plugin tablet away (its id from room_tablets_list); the plugin stays in the chain.",
			{"tablet": T.str_p("tablet id")}, ["tablet"], T.EDIT, &"close_tablet",
			func(a: Dictionary) -> Variant: return [StringName(str(a["tablet"]))])
	_verb_tool(api, "room_tablet_move",
			"Push a plugin tablet's stand to x, z metres with a heading in radians.",
			{"tablet": T.str_p("tablet id"), "x": T.num_p("metres"), "z": T.num_p("metres"), "yaw": T.num_p("radians")},
			["tablet", "x", "z", "yaw"], T.EDIT, &"move_tablet",
			func(a: Dictionary) -> Variant: return [StringName(str(a["tablet"])), _f(a["x"]), _f(a["z"]), _f(a["yaw"])])
	_verb_tool(api, "room_track_rack_open",
			"Pull a track's own rack out onto a stand at x, z metres (a track by name or '#number').",
			{"track": T.ref_p("track name or number"), "x": T.num_p("metres"), "z": T.num_p("metres")},
			["track", "x", "z"], T.EDIT, &"open_track_rack", func(a: Dictionary) -> Variant:
				var r := _track(a["track"])
				if not r["ok"]:
					return r["error"]
				return [int(r["index"]), _f(a["x"]), _f(a["z"])])
	_verb_tool(api, "room_track_rack_close",
			"Put a pulled-out track rack away (its id from room_tablets_list).",
			{"rack": T.str_p("track rack id")}, ["rack"], T.EDIT, &"close_track_rack",
			func(a: Dictionary) -> Variant: return [StringName(str(a["rack"]))])


static func _items(api: ControlApi) -> void:
	var T := ControlTool
	api.add(T.make("room_items_list",
			"The things people carry round the room (toys, instruments, mics, tablets, cassettes): id, title, whether it is at home on its shelf, held, or loose, and who holds it. Ids are what the room_item_* tools take. Bounded: limit and offset.",
			{"limit": T.int_p("rows, default 50", 1, LIST_MAX), "offset": T.int_p("skip this many", 0)}, [], T.READ,
			func(a: Dictionary) -> Dictionary:
				var no := _need_studio(api)
				if not no.is_empty():
					return no
				var s := _studio(api)
				if s.items == null:
					return T.ok({"total": 0, "offset": 0, "rows": []})
				var away: Dictionary = s.items.state()
				var rows: Array = []
				for id in s.items.items:
					var it: Item = s.items.items[id]
					var row := {"id": String(id), "title": it.item_title(), "state": Item.State.keys()[it.state],
							"holder": Session.holder_of(it.network_key())}
					if away.has(id):
						row["where"] = away[id]
					rows.append(row)
				return T.ok(_page(rows, a))))
	_verb_tool(api, "room_item_put",
			"Put an item down at x, z metres (floor frame) with a heading in radians. It lies there only if a person could reach it again; otherwise it goes home to its shelf. Only whoever holds it (or anyone, if nobody) may.",
			{"item": T.str_p("item id"), "x": T.num_p("metres"), "z": T.num_p("metres"), "yaw": T.num_p("radians")},
			["item", "x", "z"], T.EDIT, &"put_item", func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				if why != "":
					return why
				return [StringName(str(a["item"])), _f(a["x"]), _f(a["z"]), _f(a.get("yaw", 0.0))])
	_verb_tool(api, "room_item_home",
			"Send an item back to its shelf spot.",
			{"item": T.str_p("item id")}, ["item"], T.EDIT, &"home_item", func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				return why if why != "" else [StringName(str(a["item"]))])
	_verb_tool(api, "room_item_throw",
			"Throw an item from a point, with a velocity (m/s) and optionally a spin (rad/s), each [x, y, z] in the room's frame.",
			{"item": T.str_p("item id"), "origin": T.arr_p("[x, y, z] metres", {"type": "number"}),
			"velocity": T.arr_p("[x, y, z] metres per second", {"type": "number"}),
			"spin": T.arr_p("[x, y, z] radians per second, default none", {"type": "number"})},
			["item", "origin", "velocity"], T.EDIT, &"throw_item", func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				if why != "":
					return why
				var o: Variant = _vec(a["origin"])
				var v: Variant = _vec(a["velocity"])
				var sp: Variant = _vec(a.get("spin"))
				if o == null or v == null or sp == null:
					return "origin, velocity and spin are each three numbers [x, y, z]"
				return [StringName(str(a["item"])), o, v, sp])
	_verb_tool(api, "room_item_wear",
			"Put an item on (or take it off) the head: headphones, glasses. It must be in the asker's hand.",
			{"item": T.str_p("item id"), "on": T.bool_p("true to wear it, false to take it off")},
			["item", "on"], T.EDIT, &"wear_item", func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				return why if why != "" else [StringName(str(a["item"])), bool(a["on"])])
	_verb_tool(api, "room_item_pocket",
			"Put an item (in hand) into a pocket, numbered from 0; -1 takes it out of its pocket.",
			{"item": T.str_p("item id"), "pocket": T.int_p("pocket number, 0 first; -1 out", -1, 7)},
			["item", "pocket"], T.EDIT, &"pocket_item", func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				return why if why != "" else [StringName(str(a["item"])), int(a["pocket"])])
	_verb_tool(api, "room_item_give",
			"Hand the item the asker holds to a bandmate (their peer id, from room_get's `here`), into their hand.",
			{"item": T.str_p("item id"), "to": T.int_p("peer id of the bandmate")}, ["item", "to"], T.EDIT, &"give",
			func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				return why if why != "" else [StringName(str(a["item"])), int(a["to"])])
	_verb_tool(api, "room_item_slot",
			"Stand an item in a numbered slot of a holder (the cassette rack, its BIN, the platter). The game says why when it will not fit.",
			{"item": T.str_p("item id"), "holder": T.str_p("holder id, e.g. the cassette rack's"), "slot": T.int_p("slot number, 0 first", 0)},
			["item", "holder", "slot"], T.EDIT, &"slot_item", func(a: Dictionary) -> Variant:
				var why := _item_known(api, str(a["item"]))
				return why if why != "" else [StringName(str(a["item"])), StringName(str(a["holder"])), int(a["slot"])])
	_verb_tool(api, "room_item_make",
			"Make an item while playing. A cassette of a clip: kind 'cassette' with track (name or '#number') and item (the clip's number on that track). It arrives in the asker's hand.",
			{"kind": T.str_p("kind of item to make", ["cassette"]), "track": T.ref_p("track name or number"),
			"item": T.int_p("the clip's number on the track", 0)},
			["track", "item"], T.EDIT, &"make", func(a: Dictionary) -> Variant:
				var r := _track(a["track"])
				if not r["ok"]:
					return r["error"]
				return [StringName(str(a.get("kind", "cassette"))), "clip:%d:%d" % [int(r["index"]), int(a["item"])]])
	_verb_tool(api, "room_paste",
			"Paste the cassette the asker holds onto a track at a song time in seconds. The game says why when it cannot.",
			{"cassette": T.str_p("the cassette's item id"), "track": T.ref_p("track name or number"), "seconds": T.num_p("song time", 0)},
			["cassette", "track", "seconds"], T.EDIT, &"paste", func(a: Dictionary) -> Variant:
				var r := _track(a["track"])
				if not r["ok"]:
					return r["error"]
				return [StringName(str(a["cassette"])), int(r["index"]), _f(a["seconds"])])
	_verb_tool(api, "room_take_personal",
			"Take your own copy of a personal item (mic, headphones, glasses, tablet) from its dispenser into the hand.",
			{"kind": T.str_p("which one", Array(ItemRoom.PERSONAL_KINDS).map(func(k: StringName) -> String: return String(k)))},
			["kind"], T.EDIT, &"take_personal", func(a: Dictionary) -> Variant: return [StringName(str(a["kind"]))])


static func _gear(api: ControlApi) -> void:
	var T := ControlTool
	_verb_tool(api, "room_tv",
			"Drive the room's TV: a video (file name or search words, as its FIND takes), whether it plays, and the position in seconds.",
			{"video": T.str_p("video to show"), "playing": T.bool_p("playing or paused"), "seconds": T.num_p("position in the video", 0)},
			["video", "playing"], T.EDIT, &"tv", func(a: Dictionary) -> Variant:
				return [str(a["video"]), bool(a["playing"]), _f(a.get("seconds", 0.0))])
	_verb_tool(api, "room_on_air",
			"Go on air (or off): a performer on air can be heard through the monitors and patched into.",
			{"on": T.bool_p("true on air")}, ["on"], T.EDIT, &"on_air", func(a: Dictionary) -> Variant: return [bool(a["on"])])
	_verb_tool(api, "room_board_source",
			"Choose what the big board shows: a surface id (see room_pieces_list surfaces), or empty for nothing.",
			{"source": T.str_p("surface id, or empty")}, ["source"], T.EDIT, &"board_source",
			func(a: Dictionary) -> Variant: return [StringName(str(a["source"]))])
	_verb_tool(api, "room_patch",
			"Patch one of the personal-mix receivers (0 to 3, lettered A to D) to a source: 'mix', 'keys', a track's 'track_<n>', a bandmate's 'keys_<peer>' or 'monitor_<peer>'; empty unplugs it. Only what exists is accepted.",
			{"receiver": T.int_p("receiver number, 0 first", 0, PersonalMix.RECEIVERS - 1), "socket": T.str_p("socket name, or empty")},
			["receiver", "socket"], T.EDIT, &"patch", func(a: Dictionary) -> Variant:
				var sock := StringName(str(a["socket"]))
				if not PersonalMix.valid_socket(sock):
					return "'%s' is not a socket; use mix, keys, track_<n>, keys_<peer>, monitor_<peer> or empty" % sock
				return [int(a["receiver"]), sock])
	_verb_tool(api, "room_plug",
			"Plug an instrument's output jack (source) into a sink: a track's MIDI input or a bandmate; an empty sink unplugs it. The game refuses, with the reason, a plug nobody may make.",
			{"source": T.str_p("the jack's id"), "sink": T.str_p("the sink's id, or empty to unplug")},
			["source", "sink"], T.EDIT, &"plug", func(a: Dictionary) -> Variant:
				return [StringName(str(a["source"])), StringName(str(a.get("sink", "")))] if a.has("sink") else "sink is required (empty to unplug)")
	_verb_tool(api, "room_harmony",
			"Set the key on the fifths wheel as written at a bar: `bar` counted from 1, `key` like 'C major' or 'A minor' (what the wheel's SET writes).",
			{"bar": T.int_p("bar number, 1 first", 1), "key": T.str_p("key and mode, e.g. 'C major'")},
			["bar", "key"], T.EDIT, &"harmony", func(a: Dictionary) -> Variant: return [int(a["bar"]) - 1, str(a["key"])])
	_verb_tool(api, "room_rope",
			"Tie or cut the rope on a stage table; tying can also add the compressor it keys.",
			{"table": T.str_p("the stage table's id"), "tied": T.bool_p("true tie, false cut"), "add_compressor": T.bool_p("also add the compressor it keys, default false")},
			["table", "tied"], T.EDIT, &"rope", func(a: Dictionary) -> Variant:
				return [str(a["table"]), bool(a["tied"]), bool(a.get("add_compressor", false))])
	_verb_tool(api, "room_sampler",
			"Arm the sampler's REC (for the asker's next sound) or disarm it.",
			{"armed": T.bool_p("true arms")}, ["armed"], T.EDIT, &"sampler", func(a: Dictionary) -> Variant: return [bool(a["armed"])])
	_verb_tool(api, "room_weather",
			"Switch the weather to LISTEN (it plays from the music) or OFF, for everyone.",
			{"listening": T.bool_p("true listens")}, ["listening"], T.EDIT, &"weather", func(a: Dictionary) -> Variant: return [bool(a["listening"])])
	_verb_tool(api, "room_scratch",
			"Scratch the cassette in the DJ platter's slot for the sampler: the cassette's id and the scratch's path, a list of numbers (the platter's varispeed path). Only rendered if the sampler's REC is on.",
			{"cassette": T.str_p("the cassette's item id"), "path": T.arr_p("the scratch path", {"type": "number"})},
			["cassette", "path"], T.EDIT, &"scratch", func(a: Dictionary) -> Variant:
				var path := PackedFloat32Array()
				for n in a["path"]:
					if typeof(n) != TYPE_INT and typeof(n) != TYPE_FLOAT:
						return "path must be numbers"
					path.append(float(n))
				return [StringName(str(a["cassette"])), path])
	_verb_tool(api, "room_looper",
			"Arm the looper for the asker (action 'arm': from a bar, or -1 to start the transport, for so many bars) or clear their loop (action 'clear'). Refused while somebody else is looping.",
			{"action": T.str_p("what to do", ["arm", "clear"]), "from_bar": T.int_p("bar to start from, -1 starts the transport"),
			"bars": T.int_p("length in bars", 1, 64)},
			["action"], T.EDIT, &"looper", func(a: Dictionary) -> Variant:
				if str(a["action"]) == "clear":
					return [0, 0]
				if not a.has("bars"):
					return "arm needs bars"
				return [int(a.get("from_bar", -1)), int(a["bars"])])
