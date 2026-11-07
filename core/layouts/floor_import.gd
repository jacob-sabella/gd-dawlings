class_name FloorImport
extends RefCounted

## The one import step from the old floor positions (docs/layouts.md section 11 step 6).
##
## Before the layouts were data, a player's profile saved every piece of furniture once it settled,
## moved or not (`floor/<id>`), so a profile holds spots of the older, smaller rooms that nobody chose.
## Each build used to look every saved spot up in three tables in `Studio` (OLD_FLOOR_DEFAULTS,
## OLD_FIT_LINES, OLD_EQ_WALL) and let the piece take the new default instead. Now that happens once:
## `run` forgets the saved spots that are one of those old defaults, and marks the profile
## (`LayoutProfile.floor_import`) so it never looks again. A piece somebody did move keeps its place,
## and one they push back to an old default later is theirs.
##
## Then `into_room` (docs/layouts.md 7): the spots that remain are somebody's choices, and positions are
## per room now, so they become the `moved` entries of the room the player is in, and the profile
## forgets them.
##
## The tables are data, `res://layouts/import/floor_v1.json`, frozen: the answer for 4536 probes is
## pinned in tests/fixtures/layouts/control_room_legacy.json.

## The import this code does; a profile marked with this or more is left as it is.
const VERSION := 1
const TABLE := "res://layouts/import/floor_v1.json"

static var _table: Dictionary = {}


## Forget the saved studio floor spots of `profile` that are an old room's defaults, once. Returns
## how many were forgotten. Saves the profile only if there were any (a fresh one has nothing to save).
static func run(profile: LayoutProfile) -> int:
	if profile == null or profile.floor_import >= VERSION:
		return 0
	var forgotten := 0
	for key in profile.local_transforms.keys():
		var parts := String(key).split("/")
		if parts.size() != 3 or parts[0] != "floor" or int(parts[2]) != Presentation.Mode.STUDIO:
			continue
		if was_old_default(StringName(parts[1]), profile.local_transforms[key]):
			profile.local_transforms.erase(key)
			forgotten += 1
	profile.floor_import = VERSION
	if forgotten > 0:
		profile.save()
	return forgotten


## The saved studio floor spots of `profile` that are left (`run` has taken the old defaults) become
## `moved` entries of the room `deltas` is in, once; the profile forgets them. A player's own plugin
## stands and track racks stay where they are, and the LEVELS niche and the TV bracket (built into the
## wall, they have no pushed spot) are forgotten. A spot the room's delta already has is not overwritten.
## Returns how many were moved. Does nothing, and does not mark the profile, for a guest (it is not the
## host of any room to keep a delta for).
static func into_room(profile: LayoutProfile, deltas: RoomDeltas) -> int:
	if profile == null or deltas == null or profile.floor_moved >= 1 or not Session.is_authority():
		return 0
	var moved := 0
	for key in profile.local_transforms.keys():
		var parts := String(key).split("/")
		if parts.size() != 3 or parts[0] != "floor" or int(parts[2]) != Presentation.Mode.STUDIO:
			continue
		var id := StringName(parts[1])
		if RoomDelta.owned_by_player(id):
			continue
		var at: Transform3D = profile.local_transforms[key]
		profile.local_transforms.erase(key)
		if id in [&"levels", &"tv"] or deltas.delta.moved.has(String(id)):
			continue
		deltas.settle(id, at, false, null)
		moved += 1
	profile.floor_moved = 1
	profile.save()
	return moved


## Whether a saved floor spot `saved` for piece `id` is one of the defaults an older room stood it at
## (the table's `defaults`, `fit_lines` and `eq_wall`), rather than somewhere a player pushed it.
static func was_old_default(id: StringName, saved: Transform3D) -> bool:
	var t := table()
	var at := Vector2(saved.origin.x, saved.origin.z)
	for was: Array in t["defaults"].get(String(id), []):
		if at.distance_to(Vector2(was[0], was[1])) < 0.02:
			return true
	var heading := rad_to_deg(saved.basis.get_euler().y)
	if t["fit_lines"].has(String(id)):
		var line: Array = t["fit_lines"][String(id)]
		if absf(at.y - float(line[0])) < 0.02 and absf(wrapf(heading - float(line[1]), -180.0, 180.0)) < 0.5:
			return true
	var eq: Dictionary = t["eq_wall"]
	if id == &"eq_wall" and absf(at.y - float(eq["off"][1])) < 0.02 \
			and absf(wrapf(heading - float(eq["heading"]), -180.0, 180.0)) < 0.5:
		# Its x followed the old room's right-hand wall out, in 0.8 m steps.
		var off := at.x + float(eq["off"][0])
		return absf(off / SessionLayout.WIDTH_STEP * 2.0 - roundf(off / SessionLayout.WIDTH_STEP * 2.0)) < 0.03
	return false


## The frozen table, read once.
static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(TABLE, FileAccess.READ)
		_table = JSON.parse_string(f.get_as_text()) if f != null else {}
		for k in ["defaults", "fit_lines", "eq_wall"]:
			if not _table.has(k):
				_table[k] = {}
		if not _table["eq_wall"].has("off"):
			_table["eq_wall"] = {"off": [0.0, 1.0e9], "heading": 0.0}
	return _table
