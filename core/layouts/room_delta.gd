class_name RoomDelta
extends RefCounted

## What one room differs in from its venue's default layout (docs/layouts.md 5.3, 7 and 9): the pieces
## somebody `moved` to another spot, `added` pieces the layout does not have, and the ids `removed`.
## A room is `(venue, arrangement)`, keyed `<venue>.<variant>`; its delta is applied over the resolved
## layout (`apply`), so an empty delta is the default room and a wider room re-stands whatever was
## not moved. Pure data: the file is `RoomDeltaFile`, the keeper in the game `RoomDeltas`.
##
## Nothing is dropped for being unknown. A moved or removed id the layout has no piece for, and an
## added piece no definition is installed for (a mod the player lacks), stay in the delta and come back
## out of `apply` as `flagged`, as a missing mod's plate does; only the result is cut to the room's limits.

## The file's `format` and `version`.
const FORMAT := "dawlings.room-delta"
const VERSION := 1
## The most text a delta may be (decision 8). A bigger file is not read and a bigger delta is not written.
const MAX_BYTES := 16384
## The most pieces of any list: a room holds at most `LayoutData.MAX_PIECES`; `moved` may also name
## trolleys the code places (lamps, the timeline stand).
const MAX_ENTRIES := 128

## `<venue>.<variant>`, the room this is the delta of.
var room := ""
## The venue and arrangement it is over.
var base: StringName = &""
var variant := 0
## Counts every change, so a guest can tell a newer row from the one it has.
var rev := 0
## {piece id: [x, z, yaw]}: floor metres and radians, in the studio set's frame.
var moved: Dictionary = {}
## Pieces the room has that the layout does not: {id, piece, at: {pos: [x, z], yaw}, footprint?}.
var added: Array[Dictionary] = []
## Ids of layout pieces this room does without.
var removed: Array[String] = []
## Ids of pieces the layout left out (a made room that did without one) that this room has back, where the layout
## would have stood them (or at their `moved` spot).
var restored: Array[String] = []


## The key of the room venue `venue_id` in arrangement `variant`.
static func room_key(venue_id: StringName, arrangement: int) -> String:
	return "%s.%d" % [venue_id, arrangement]


## Whether a piece id belongs to a player and not to the room: the plugin stands and track racks a
## player pulls out are rows of their own (`tablets`, `track_racks`) and stay in the profile.
static func owned_by_player(id: StringName) -> bool:
	return String(id).begins_with("tablet_") or String(id).begins_with("track_rack_")


## Whether the code, not the layout, places this trolley (so a delta naming it is not a stranger).
static func placed_by_code(id: StringName) -> bool:
	return id == &"timeline_stand" or String(id).begins_with("lamp_")


## A delta for an empty room.
static func empty(venue_id: StringName, arrangement: int) -> RoomDelta:
	var d := RoomDelta.new()
	d.base = venue_id
	d.variant = arrangement
	d.room = room_key(venue_id, arrangement)
	return d


func is_empty() -> bool:
	return moved.is_empty() and added.is_empty() and removed.is_empty() and restored.is_empty()


## Piece `id` stands at (x, z) turned `yaw`. Rounded to a tenth of a millimetre: the text stays short
## and the same spot is always the same text. True if that is a change (a piece left where it was
## is not a new revision). A piece the room added carries its spot in its own `added` entry.
func move(id: StringName, x: float, z: float, yaw: float) -> bool:
	var spot := [_tenth_mm(x), _tenth_mm(z), _tenth_mm(yaw)]
	var i := added_index(id)
	if i >= 0:
		var at := {"pos": [spot[0], spot[1]], "yaw": spot[2]}
		if added[i].get("at") == at:
			return false
		added[i]["at"] = at
		rev += 1
		return true
	if moved.get(String(id)) == spot:
		return false
	moved[String(id)] = spot
	rev += 1
	return true


## Piece `id` goes back to where the layout puts it. True if it had been moved.
func unmove(id: StringName) -> bool:
	if moved.erase(String(id)):
		rev += 1
		return true
	return false


## Where piece `id` stands in this room, or null where nobody moved it (and it was not added).
func transform_of(id: StringName) -> Variant:
	var i := added_index(id)
	if i >= 0:
		var at: Dictionary = added[i]["at"]
		return Transform3D(Basis(Vector3.UP, float(at.get("yaw", 0.0))), Vector3(float(at["pos"][0]), 0.0, float(at["pos"][1])))
	var m: Variant = moved.get(String(id))
	if m == null:
		return null
	return Transform3D(Basis(Vector3.UP, float(m[2])), Vector3(float(m[0]), 0.0, float(m[1])))


## The index of the `added` entry with id `id`, or -1.
func added_index(id: StringName) -> int:
	for i in added.size():
		if added[i].get("id") == String(id):
			return i
	return -1


## Whether the room does without layout piece `id`.
func is_removed(id: StringName) -> bool:
	return String(id) in removed


## A copy to try an edit on: the same room, the same revision.
func copy() -> RoomDelta:
	return RoomDelta.from_dict(to_dict())


## The room has a piece the layout does not: `entry` is `{id, piece, at: {pos, yaw}, footprint?}`.
func add_piece(entry: Dictionary) -> void:
	added.append(entry.duplicate(true))
	rev += 1


## Layout piece `id` is done without, and wherever it was moved to is forgotten. True if it was not already.
func take_out(id: StringName) -> bool:
	if is_removed(id):
		return false
	moved.erase(String(id))
	removed.append(String(id))
	rev += 1
	return true


## Whether the room has back the piece `id` its layout left out.
func is_restored(id: StringName) -> bool:
	return String(id) in restored


## The piece `id`, which the layout left out, is in the room. True if it was not already.
func restore(id: StringName) -> bool:
	if is_restored(id):
		return false
	restored.append(String(id))
	rev += 1
	return true


## The restored piece `id` is left out again, wherever it was moved to forgotten. True if it was in.
func unrestore(id: StringName) -> bool:
	if not restored.has(String(id)):
		return false
	restored.erase(String(id))
	moved.erase(String(id))
	rev += 1
	return true


## Layout piece `id` is in the room again. True if it was out.
func put_back(id: StringName) -> bool:
	if removed.has(String(id)):
		removed.erase(String(id))
		rev += 1
		return true
	return false


## The piece the room added, `id`, is gone again. True if there was one.
func drop_added(id: StringName) -> bool:
	var i := added_index(id)
	if i < 0:
		return false
	added.remove_at(i)
	rev += 1
	return true


## Everything back as the layout has it. True if there was anything to put back.
func clear() -> bool:
	if is_empty():
		return false
	moved.clear()
	added.clear()
	removed.clear()
	restored.clear()
	rev += 1
	return true


## The delta as a dictionary: the file (`with_format`) or the room-state row.
func to_dict(with_format := true) -> Dictionary:
	var out := {"room": room, "base": String(base), "variant": variant, "rev": rev,
			"moved": moved.duplicate(true), "added": added.duplicate(true), "removed": removed.duplicate()}
	# Only a room that has one says so: the file of a room without any stays as the first version wrote it.
	if not restored.is_empty():
		out["restored"] = restored.duplicate()
	if with_format:
		out["format"] = FORMAT
		out["version"] = VERSION
	return out


## The file text: sorted keys, so the same delta is always the same bytes.
func text() -> String:
	return JSON.stringify(to_dict(), "\t", true) + "\n"


## Whether the file text is within `MAX_BYTES`.
func fits() -> bool:
	return text().to_utf8_buffer().size() <= MAX_BYTES


## Why `raw` (parsed JSON, or a row off the wire) cannot be a delta, in words; "" when it can. Wrong
## field types inside an entry do not make it unusable: `from_dict` mends those.
static func problem(raw: Variant) -> String:
	if not raw is Dictionary:
		return "not a delta"
	if raw.has("format") and raw["format"] != FORMAT:
		return "not a room delta (format %s)" % str(raw["format"])
	if _is_number(raw.get("version")) and int(raw["version"]) > VERSION:
		return "made by a newer game (version %s)" % str(raw["version"])
	if raw.get("moved") is Dictionary and (raw["moved"] as Dictionary).size() > MAX_ENTRIES:
		return "too many moved pieces"
	for key in ["added", "removed", "restored"]:
		if raw.get(key) is Array and (raw[key] as Array).size() > LayoutData.MAX_PIECES:
			return "more than %d %s pieces" % [LayoutData.MAX_PIECES, key]
	return ""


## A delta from `raw` (a file's JSON or a row), mending what is the wrong shape: an entry that is not
## readable is left out, everything readable is kept. Not a dictionary: an empty delta.
static func from_dict(raw: Variant) -> RoomDelta:
	var d := RoomDelta.new()
	if not raw is Dictionary:
		return d
	d.base = StringName(raw["base"]) if _is_text(raw.get("base")) else &""
	d.variant = maxi(0, int(raw["variant"])) if _is_number(raw.get("variant")) else 0
	d.room = String(raw["room"]) if _is_text(raw.get("room")) else room_key(d.base, d.variant)
	d.rev = maxi(0, int(raw["rev"])) if _is_number(raw.get("rev")) else 0
	if raw.get("moved") is Dictionary:
		for id in raw["moved"]:
			var m: Variant = raw["moved"][id]
			if _is_id(id) and m is Array and m.size() >= 3 and m.slice(0, 3).all(_is_finite):
				d.moved[String(id)] = [float(m[0]), float(m[1]), float(m[2])]
	if raw.get("added") is Array:
		var seen := {}
		for a in raw["added"]:
			if a is Dictionary and _is_id(a.get("id")) and _is_text(a.get("piece")) and not seen.has(a["id"]) \
					and (a.get("at") is Dictionary and a["at"].get("pos") is Array and a["at"]["pos"].size() >= 2):
				seen[a["id"]] = true
				d.added.append(a.duplicate(true))
	if raw.get("removed") is Array:
		for id in raw["removed"]:
			if _is_id(id) and String(id) not in d.removed:
				d.removed.append(String(id))
	if raw.get("restored") is Array:
		for id in raw["restored"]:
			if _is_id(id) and String(id) not in d.restored:
				d.restored.append(String(id))
	return d


## The resolved layout `body` (`LayoutData.body`) with this delta applied: `{ok, pieces, wiring, groups,
## flagged}`. A moved piece stands at its spot (an absolute `pos`, its `up` kept); a removed one is gone,
## with the group members and wires that named it; an added one is appended (marked `unavailable` when no
## piece definition is installed for it). `flagged` lists `{id, code, why}` for every entry the room cannot
## make sense of: `unknown_piece`, `duplicate_piece`, `unavailable_piece`, `over_limit`. A result with more
## than `LayoutData.MAX_PIECES` pieces is refused: `ok` is false and the pieces are the defaults.
func apply(body: Dictionary, left_out := {}) -> Dictionary:
	var pieces: Array = (body.get("pieces", []) as Array).duplicate(true)
	var flagged: Array[Dictionary] = []
	var wiring: Array = (body.get("wiring", []) as Array).duplicate(true)
	var groups: Array = (body.get("groups", []) as Array).duplicate(true)
	if not restored.is_empty():
		var back := {"pieces": pieces, "wiring": wiring, "groups": groups}
		for id in LayoutMerge.restore(back, left_out, restored):
			flagged.append(_flag(id, &"unknown_piece", "this room's layout has no piece '%s' to have put back" % id))
	var at_index := {}
	for i in pieces.size():
		at_index[str(pieces[i].get("id"))] = i
	for id: String in moved:
		if at_index.has(id):
			var p: Dictionary = pieces[at_index[id]]
			var at: Dictionary = (p.get("at", {}) as Dictionary).duplicate(true)
			for key in ["anchor", "frame", "local", "toward", "snap"]:
				at.erase(key)
			at["pos"] = [moved[id][0], moved[id][1]]
			at["yaw"] = moved[id][2]
			p["at"] = at
		elif not placed_by_code(StringName(id)) and not owned_by_player(StringName(id)):
			flagged.append(_flag(id, &"unknown_piece", "this room has no piece '%s' to have moved" % id))
	for id in removed:
		if at_index.has(id):
			pieces[at_index[id]]["enabled"] = false
		else:
			flagged.append(_flag(id, &"unknown_piece", "this room has no piece '%s' to have taken out" % id))
	for a in added:
		var id := str(a["id"])
		if at_index.has(id):
			flagged.append(_flag(id, &"duplicate_piece", "the room already has a piece '%s'" % id))
			continue
		var p := a.duplicate(true)
		if not PieceDef.has(StringName(a["piece"])):
			p["unavailable"] = true
			flagged.append(_flag(id, &"unavailable_piece", "'%s' is not installed here" % a["piece"]))
		at_index[id] = pieces.size()
		pieces.append(p)
	var out := {"ok": true, "pieces": pieces, "wiring": wiring, "groups": groups, "flagged": flagged}
	LayoutMerge.settle(out)
	if (out["pieces"] as Array).size() > LayoutData.MAX_PIECES:
		flagged.append(_flag("", &"over_limit", "%d pieces; a room holds at most %d" % [(out["pieces"] as Array).size(), LayoutData.MAX_PIECES]))
		out["ok"] = false
		out["pieces"] = (body.get("pieces", []) as Array).duplicate(true)
		out["wiring"] = (body.get("wiring", []) as Array).duplicate(true)
		out["groups"] = (body.get("groups", []) as Array).duplicate(true)
	return out


## `v` as the nearest number with four decimals, as the double the file text parses back to (`snappedf` leaves
## 1.2346 as 1.2346000000000001, which the text would not give back).
static func _tenth_mm(v: float) -> float:
	return String.num(v, 4).to_float()


static func _flag(id: String, code: StringName, why: String) -> Dictionary:
	return {"id": id, "code": code, "why": why}


static func _is_number(v: Variant) -> bool:
	return v is float or v is int


static func _is_finite(v: Variant) -> bool:
	return _is_number(v) and is_finite(float(v))


static func _is_text(v: Variant) -> bool:
	return v is String or v is StringName


static func _is_id(v: Variant) -> bool:
	return _is_text(v) and String(v).length() > 0 and String(v).length() <= 40 and String(v).is_valid_identifier()
