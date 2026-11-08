class_name MadeRoom
extends RefCounted

## What a player asks of the new-room maker (docs/layouts.md 8) and the layout file that makes of it.
## A spec is `{title, size, style, zones, pieces, annex}`: a `size` of `SIZES`, a `style` of
## `BoxStyle.IDS`, any subset of the five zones that fit that size, the single items kept
## (`PieceCatalogue.kinds()`: the pieces the maker offers one by one) and whether the room-scale mod,
## the modular annex, is built onto it. Pieces are of two classes (`PieceDef.Kind`): singles are chosen
## here by name; the annex is a room-scale mod, offered on its own line and never among the singles.
##
## `build` answers a layout dictionary (the file's content, `format dawlings.layout`) that has been
## through `LayoutData.parse`, the shape checks and the validator; anything else comes back as
## sentences in `errors`. A room holds at most `LayoutData.MAX_PIECES` pieces and its file at most
## `MAX_BYTES` (decision 7).

## The sizes of a made room, small to large.
const SIZES: Array[StringName] = [&"small", &"standard", &"large"]
## The most of a file, in bytes: the same as a room delta's.
const MAX_BYTES := 16384
## The longest title, in characters.
const MAX_TITLE := 40
## The fragments every made room extends: the control room, and the live room's pieces.
const EXTENDS := ["common.control_room", "common.live_room"]
## The zone each zoned piece stands in; a piece asked for without its zone is an error, and one the room
## has the zone for but was not asked for is switched off.
const NEEDS := {&"wheel": &"bricks", &"sections": &"bricks", &"looper": &"drums", &"lyrics": &"vocals",
		&"sampler": &"synth"}
## The grid a zone's place is on, in metres (every standard place is on it), and how far one nudge in the panel
## moves it.
const ZONE_SNAP := 0.1
const ZONE_STEP := 0.5
## The titles of the zones, for the panel.
const ZONE_TITLES := {&"drums": "Drum riser", &"matrix": "Lattice", &"vocals": "Vocal booth", &"bricks": "Table",
		&"synth": "Keyboard stand"}


## Half the width of a room of `size`, the way `BoxVenue.live_room_half` has it at the base width.
static func half_of(size: StringName) -> float:
	match size:
		&"small":
			return Studio.ROOM_WIDTH * 0.5
		&"large":
			return Venue.LIVE_ROOM_HALF + BoxVenue.LARGE_EXTRA
	return Venue.LIVE_ROOM_HALF


## `v` on the zone grid, as the number the file text gives back.
static func snap(v: float) -> float:
	return String.num(snappedf(v, ZONE_SNAP), 4).to_float()


## The floor a zone's box may stand on in a room of `size`: the live room's, a hand clear of its walls.
static func zone_floor(size: StringName) -> Rect2:
	var half := half_of(size) - 0.05
	return Rect2(-half, Studio.ROOM_BACK, half * 2.0, Venue.LIVE_ROOM_BACK - 0.05 - Studio.ROOM_BACK)


## The box of zone `id` in `spec`: the standard one, with the place `spec["zone_at"]` gives it (the x and z of its
## corner) where it says one.
static func zone_box(spec: Dictionary, id: StringName) -> AABB:
	var box: AABB = Venue.ZONES[id]
	var at: Variant = (spec.get("zone_at", {}) as Dictionary).get(String(id))
	if at is Array and (at as Array).size() >= 2:
		box.position = Vector3(snap(float(at[0])), box.position.y, snap(float(at[1])))
	return box


## Whether `box` lies within the floor a zone may stand on in a room of `size`.
static func zone_fits(size: StringName, box: AABB) -> bool:
	return zone_floor(size).grow(1e-4).encloses(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))


## The zones a room of `size` has room for, in the standard order.
static func zones_fitting(size: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var half := half_of(size) - 0.05
	for id in Venue.ZONE_IDS:
		var box: AABB = Venue.ZONES[id]
		if box.position.x >= -half and box.end.x <= half:
			out.append(id)
	return out


## A spec for the plainest room of `size`: every zone that fits, every single that has its zone, the annex.
static func default_spec(size: StringName = &"standard") -> Dictionary:
	var zones := zones_fitting(size)
	var pieces: Array = []
	for kind in PieceCatalogue.kinds():
		if not NEEDS.has(kind) or NEEDS[kind] in zones:
			pieces.append(String(kind))
	return {"title": "New room", "size": String(size), "style": "warm", "zones": zones.map(func(z: StringName) -> String: return String(z)),
			"pieces": pieces, "annex": true, "zone_at": {}}


## What is wrong with `spec`, as sentences; empty when it is a room that can be made.
static func problems(spec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var title := str(spec.get("title", "")).strip_edges()
	if title.is_empty() or title.length() > MAX_TITLE:
		out.append("A room needs a name of 1 to %d characters." % MAX_TITLE)
	var size := StringName(str(spec.get("size", "")))
	if size not in SIZES:
		out.append("A room is small, standard or large.")
		return out
	if not BoxStyle.has(StringName(str(spec.get("style", "")))):
		out.append("There is no such look for a room.")
	var kept: Array[StringName] = []
	var fits := zones_fitting(size)
	var placed: Variant = spec.get("zone_at", {})
	if not placed is Dictionary:
		out.append("The zones' places are not a list.")
		placed = {}
	for z in spec.get("zones", []):
		var id := StringName(str(z))
		if id not in Venue.ZONE_IDS:
			out.append("There is no zone called %s." % id)
		elif id not in fits:
			out.append("The %s does not fit a %s room." % [ZONE_TITLES[id], size])
		elif id in kept:
			out.append("The %s is listed twice." % ZONE_TITLES[id])
		else:
			kept.append(id)
	for z in placed:
		var id := StringName(str(z))
		var at: Variant = placed[z]
		if id not in kept:
			out.append("The %s has no place to move: the room does not have it." % ZONE_TITLES.get(id, str(id)))
		elif not (at is Array and (at as Array).size() == 2 and (at as Array).all(func(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v)))):
			out.append("The %s needs an x and a z." % ZONE_TITLES[id])
		elif not zone_fits(size, zone_box(spec, id)):
			out.append("The %s would stand outside the room." % ZONE_TITLES[id])
	for p in spec.get("pieces", []):
		var kind := StringName(str(p))
		if PieceDef.room_scale(kind):
			out.append("The %s is a room-scale mod: it is ticked on its own, not among the pieces." % LayoutChecks.name_of(kind))
		elif kind not in PieceCatalogue.kinds():
			out.append("The %s is not a piece a room is made with." % LayoutChecks.name_of(kind))
		elif NEEDS.has(kind) and NEEDS[kind] not in kept:
			out.append("The %s needs the %s." % [LayoutChecks.name_of(kind), ZONE_TITLES[NEEDS[kind]].to_lower()])
	return out


## The layout file's content for `spec` as room `id` (no checks: `build` does those).
static func layout_dict(spec: Dictionary, id: String) -> Dictionary:
	var size := StringName(str(spec.get("size", "standard")))
	var style := StringName(str(spec.get("style", "warm")))
	var kept: Array = spec.get("pieces", [])
	var zones := {}
	for z in spec.get("zones", []):
		var box := zone_box(spec, StringName(str(z)))
		zones[str(z)] = {"min": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]}
	var pieces: Array = []
	# A single the room was not asked for is switched off, so the shared live room's own is out of it.
	for kind in PieceCatalogue.kinds():
		if String(kind) not in kept:
			pieces.append({"id": String(kind), "enabled": false})
	# In the small room the shelf's neighbourhood runs into the middle of the room, where the riser is: the
	# case and the hoop stand against the other wall.
	if size == &"small":
		pieces.append({"id": "tour_case", "at": {"anchor": {"x": "wall.right", "z": "control_rear"}, "pos": [-0.7, 1.6], "yaw": -PI * 0.5}})
		if "hoop" in kept:
			pieces.append({"id": "hoop", "at": {"anchor": {"x": "wall.right", "z": "live_back"}, "pos": [-0.7, -1.2], "yaw": -PI * 0.5}})
	if spec.get("annex", false):
		pieces.append(LayoutEdit.ANNEX.duplicate(true))
	return {"format": LayoutData.FORMAT, "version": LayoutData.VERSION, "id": id,
			"title": str(spec.get("title", "")).strip_edges(), "extends": EXTENDS.duplicate(),
			"shell": {"builder": "BoxVenue", "kit": "box", "size": String(size), "style": String(style)},
			"mood": BoxStyle.mood(style), "zones": zones, "pieces": pieces}


## The made room: `{ok, id, dict, text, errors}`. Not ok when the spec has problems, the file is over
## `MAX_BYTES`, or what it makes does not validate or has more than `LayoutData.MAX_PIECES` pieces.
static func build(spec: Dictionary, id: String) -> Dictionary:
	var out := {"ok": false, "id": id, "dict": {}, "text": "", "errors": problems(spec)}
	if not out["errors"].is_empty():
		return out
	var dict := layout_dict(spec, id)
	var text := JSON.stringify(dict, "  ")
	out["dict"] = dict
	out["text"] = text
	if text.to_utf8_buffer().size() > MAX_BYTES:
		out["errors"].append("The room is over %d kB." % (MAX_BYTES / 1024))
		return out
	out["errors"].append_array(validate(dict))
	out["ok"] = out["errors"].is_empty()
	return out


## What `LayoutData.parse` and the validator say against `dict`, as sentences. The room is checked
## as the venue it makes, in a set that has the shipped fragments and itself.
static func validate(dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var l := LayoutData.parse(dict, "")
	for p in l.errors():
		out.append(str(p))
	if not out.is_empty():
		return out
	var set := LayoutSet.new()
	set.scan(LiveRoom.ROOTS)
	set.layouts.erase(l.id)
	set.add(l)
	var resolved := set.resolve(l.id)
	if resolved.status != LayoutData.STATUS_OK:
		for p in resolved.errors():
			out.append(str(p))
		return out
	if resolved.pieces().size() > LayoutData.MAX_PIECES:
		out.append("A room holds at most %d pieces." % LayoutData.MAX_PIECES)
		return out
	var venue := BoxVenue.new().from_layout(l)
	for issue in LayoutValidator.validate(resolved, ShellFacts.of(venue)):
		if issue.severity == LayoutIssue.ERROR:
			out.append("%s [%s %s %s]" % [issue.message, issue.code, issue.other, issue.at])
	venue.free()
	return out
