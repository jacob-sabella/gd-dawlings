class_name MadeRooms
extends RefCounted

## The rooms players have made (docs/layouts.md 8 and 9): layout files, `user://layouts/made/<slug>.layout.json`,
## scanned into the same set as the shipped rooms (`LiveRoom.layouts`), so a made room is found by
## `VenueCatalogue` and built by `ShellBuilders` like any other and is there after a restart. Only the
## host writes a file (atomically, with a `.bak`, `RackPatchFile.write_text`). A guest is sent the layout in
## the room-state row (`row_of`) and keeps it in memory only (`adopt`), until it is back in a room of
## its own (`drop_adopted`).
##
## A made room is not one of the cycled venues (it has no `order`): the stage manager lists them apart.

const KIND := "layouts"
const SUB := "made/"
## The longest slug, and what one is made of.
const MAX_SLUG := 40
## The most made rooms a player keeps.
const MAX_ROOMS := 24

## Tests point the folder somewhere of their own; "" is the player's `user://layouts/made/`.
static var dir_override := ""
## True where no made room is read or written (the test runner's default, as `RoomDeltas.disabled`).
static var disabled := false
## id -> true for the layouts a host sent that are held in memory only.
static var _adopted: Dictionary = {}


## The folder, made if missing; "" when it cannot be.
static func dir() -> String:
	var d := dir_override
	if d == "":
		var root := DataHome.dir(KIND)
		if root == "":
			return ""
		d = root + SUB
	if not DirAccess.dir_exists_absolute(d) and DirAccess.make_dir_recursive_absolute(d) != OK:
		return ""
	return d


## Adds the made rooms' files to `set` (after the shipped ones, so a file cannot take a shipped id).
static func scan_into(set: LayoutSet) -> void:
	if disabled:
		return
	var d := dir()
	if d != "":
		set.scan([d])


## True when `id` is a made room (a file of the player's or one a host sent).
static func has(id: StringName) -> bool:
	return VenueCatalogue.builder_of(id) == "BoxVenue"


## The ids of the made rooms, in id order.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in LiveRoom.layouts().layouts:
		if has(StringName(id)):
			out.append(StringName(id))
	out.sort()
	return out


## The ids of the made rooms the player owns (a file of their own), not the ones a host sent.
static func own_ids() -> Array[StringName]:
	return ids().filter(func(id: StringName) -> bool: return not _adopted.has(id))


## The file name stem for `title`: lower case letters, digits and hyphens, at most `MAX_SLUG`; "room" for
## a title with none.
static func slug_of(title: String) -> String:
	var out := ""
	for c in title.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif out != "" and not out.ends_with("-"):
			out += "-"
	out = out.trim_suffix("-").left(MAX_SLUG - 4).trim_suffix("-")
	return out if out != "" else "room"


## `slug_of(title)`, or with `-2`, `-3`... when a room of that id is already there.
static func unique_slug(title: String) -> String:
	var base := slug_of(title)
	var taken: Dictionary = LiveRoom.layouts().layouts
	var out := base
	var n := 2
	while taken.has(out):
		out = "%s-%d" % [base, n]
		n += 1
	return out


## Makes the room `spec` asks for (`MadeRoom`), writes its file and adds it to the set. `{ok, id, errors}`.
static func make(spec: Dictionary) -> Dictionary:
	var made := MadeRoom.build(spec, unique_slug(str(spec.get("title", ""))))
	if not made["ok"]:
		return made
	if own_ids().size() >= MAX_ROOMS:
		made["ok"] = false
		made["errors"].append("You keep at most %d rooms of your own." % MAX_ROOMS)
		return made
	var d := dir()
	if disabled or d == "":
		made["ok"] = false
		made["errors"].append("There is nowhere to keep the room.")
		return made
	var path := "%s%s%s" % [d, made["id"], LayoutSet.SUFFIX]
	if RackPatchFile.write_text(path, made["text"]) != OK:
		made["ok"] = false
		made["errors"].append("The room's file could not be written.")
		return made
	LiveRoom.put(LayoutData.load_file(path))
	return made


## Deletes the made room `id`: its file, its room delta files and its place in the set. False for a room that is
## not the player's. The caller moves everyone out of it first (`RoomMaker.delete_room`).
static func remove(id: StringName) -> bool:
	if not has(id) or _adopted.has(id):
		return false
	var d := dir()
	if d != "":
		for suffix in ["", ".bak"]:
			var path := "%s%s%s%s" % [d, id, LayoutSet.SUFFIX, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	RoomDeltaFile.remove_room(id)
	LiveRoom.drop(id)
	return true


## Renames the made room `id` to `title`: the title in its file is the only thing that changes, so the id (and with
## it the room's delta and every guest that holds the room) stays. `{ok, errors}`; not ok for a room that is not
## the player's, a name that is empty or over `MadeRoom.MAX_TITLE`, or a file that cannot be written.
static func rename(id: StringName, title: String) -> Dictionary:
	var out := {"ok": false, "id": String(id), "errors": []}
	var name := title.strip_edges()
	if not has(id) or _adopted.has(id):
		out["errors"].append("That is not one of your rooms.")
	elif name.is_empty() or name.length() > MadeRoom.MAX_TITLE:
		out["errors"].append("A room needs a name of 1 to %d characters." % MadeRoom.MAX_TITLE)
	else:
		var dict: Dictionary = (LiveRoom.layouts().layouts[String(id)] as LayoutData).to_dict()
		dict["title"] = name
		var text := JSON.stringify(dict, "  ")
		var d := dir()
		if disabled or d == "":
			out["errors"].append("There is nowhere to keep the room.")
		elif RackPatchFile.write_text("%s%s%s" % [d, id, LayoutSet.SUFFIX], text) != OK:
			out["errors"].append("The room's file could not be written.")
		else:
			LiveRoom.put(LayoutData.load_file("%s%s%s" % [d, id, LayoutSet.SUFFIX]))
			out["ok"] = true
	return out


## The room `id` as the row a host sends (the layout file's content), or empty for a room that is not made.
static func row_of(id: StringName) -> Dictionary:
	if not has(id):
		return {}
	var l: LayoutData = LiveRoom.layouts().layouts[String(id)]
	var dict := l.to_dict()
	return dict if JSON.stringify(dict).to_utf8_buffer().size() <= MadeRoom.MAX_BYTES else {}


## Takes a made room a host sent: checked as a file of one would be (`MadeRoom.validate`) and held in memory
## only. True when the room is now there (it was, or has just been added); false for a row that is not a
## room, is too big, or names an id a shipped room or a room of the guest's own has.
static func adopt(row: Variant) -> bool:
	if not row is Dictionary or str((row as Dictionary).get("id", "")) == "":
		return false
	var dict: Dictionary = row
	if JSON.stringify(dict).to_utf8_buffer().size() > MadeRoom.MAX_BYTES:
		return false
	var id := str(dict["id"])
	if str(dict.get("shell", {}).get("builder", "")) != "BoxVenue":
		return false
	var have: LayoutData = LiveRoom.layouts().layouts.get(id)
	if have != null and not _adopted.has(StringName(id)):
		return false
	if not MadeRoom.validate(dict).is_empty():
		return false
	LiveRoom.put(LayoutData.parse(dict, ""))
	_adopted[StringName(id)] = true
	return true


## Forgets the rooms a host sent, but for `keep` (the room the guest is to stand in).
static func drop_adopted(keep: StringName = &"") -> void:
	for id: StringName in _adopted.keys():
		if id != keep:
			LiveRoom.drop(id)
			_adopted.erase(id)
