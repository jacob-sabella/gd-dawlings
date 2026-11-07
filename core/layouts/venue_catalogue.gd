class_name VenueCatalogue
extends RefCounted

## What the game knows about its rooms by name, read from the shipped layout files
## (`res://layouts/venues/<id>.layout.json`, docs/layouts.md section 11 step 7) instead of from tables
## in code: which venues there are and in what order they cycle (`order`), what each is called and what
## its arrangements are called (`title`, `variants`), the colours its modular room glows in (`mood`) and
## the name of the class that builds its shell (`shell.builder`, resolved by `ShellBuilders`).
## `Venue.IDS`, `Venue.variant_titles`, `Venue.make_title`, `Venue.make` and `RackMood.palette` are
## these, so a venue added as a layout file (and a shell class in `ShellBuilders`) appears in the
## stage manager with nothing else edited. The shell geometry itself stays in code (decision 1).

## The room a name that is no room's falls back to: the first of the cycle, as `Venue.make` always did.
const DEFAULT_ID := &"studio"


## The ids of the cycled venues in cycling order; the first is the default. Never empty: a broken
## install with no layouts at all still has the studio.
static func ids() -> Array[StringName]:
	var out := LiveRoom.layouts().venue_ids()
	if out.is_empty():
		out.append(DEFAULT_ID)
	return out


## True when a layout file is shipped for `id` (a venue, the roulette room, or a fragment).
static func has(id: StringName) -> bool:
	return LiveRoom.layouts().layouts.has(String(id))


## The name of `id` for a button caption; the default venue's for an id nobody ships.
static func title_of(id: StringName) -> String:
	var l: LayoutData = LiveRoom.layouts().layouts.get(String(id if has(id) else DEFAULT_ID))
	return l.title if l != null else "Studio"


## The names of `id`'s arrangements in order. A room that lists none (the roulette room, an id nobody
## ships) has its own name as its only one.
static func variant_titles(id: StringName) -> PackedStringArray:
	var l: LayoutData = LiveRoom.layouts().layouts.get(String(id))
	if l == null or l.status != LayoutData.STATUS_OK:
		return PackedStringArray([title_of(id)])
	return PackedStringArray(l.variant_titles())


## The class name `id`'s layout says builds its shell, or "" when it names none.
static func builder_of(id: StringName) -> String:
	var l: LayoutData = LiveRoom.layouts().layouts.get(String(id))
	if l == null or l.status != LayoutData.STATUS_OK:
		return ""
	return str(l.body.get("shell", {}).get("builder", ""))


## The colours the modular room glows in for `id`, {base: Color, hit: Color, glow: float}, with
## whatever the layout leaves out taken from `fallback`; `fallback` itself for a room with no mood.
static func mood_of(id: StringName, fallback: Dictionary) -> Dictionary:
	var l: LayoutData = LiveRoom.layouts().layouts.get(String(id))
	if l == null or l.status != LayoutData.STATUS_OK or not l.body.get("mood") is Dictionary:
		return fallback
	var m: Dictionary = l.body["mood"]
	return {
		"base": Color.html(m["base"]) if m.has("base") else fallback["base"],
		"hit": Color.html(m["hit"]) if m.has("hit") else fallback["hit"],
		"glow": float(m["glow"]) if m.has("glow") else fallback["glow"],
	}
