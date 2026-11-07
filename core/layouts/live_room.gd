class_name LiveRoom
extends RefCounted

## Where the game stands the live room's wheeled pieces (docs/layouts.md section 11 step 5): the
## shipped layouts under `res://layouts/`, scanned once and kept, resolved against a venue's
## anchors. `Venue.default_spot` and `Venue.WHEELED` read this and nothing else; no venue carries
## a position of its own for the cassette rack, the sampler, the Tour case, the prop shelf or the
## hoop. Every venue has a layout file of its own (`res://layouts/venues/<id>.layout.json`, which
## extends the shared `common.control_room` and `common.live_room` fragments; the studio's second
## arrangement moves the shelf); an id with none stands on the live-room fragment alone.

## Where the shipped layouts are searched.
const ROOTS: Array[String] = ["res://layouts"]
## The fragment every live room extends, and the room a venue without a file of its own gets.
const FRAGMENT := "common.live_room"

static var _set: LayoutSet
## "<id>/<variant>" -> the resolved LayoutData, so each room is merged once.
static var _rooms: Dictionary = {}


## The scanned shipped layouts (loaded on first use, then kept).
static func layouts() -> LayoutSet:
	if _set == null:
		_set = LayoutSet.new()
		_set.scan(ROOTS)
	return _set


## The resolved layout of venue `venue_id` in arrangement `variant`: its own file when it has one,
## else the shared live room. Cached.
static func layout(venue_id: StringName, variant: int) -> LayoutData:
	var own := layouts().layouts.has(String(venue_id))
	var id := String(venue_id) if own else FRAGMENT
	# The shared fragment has no arrangements: every venue's are the same live room.
	variant = variant if own else 0
	var key := "%s/%d" % [id, variant]
	if not _rooms.has(key):
		_rooms[key] = layouts().resolve(id, variant)
	return _rooms[key]


## The ids of the pieces the live room wheels about, in the order the studio builds their trolleys.
static func wheeled_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for p: Dictionary in layouts().resolve(FRAGMENT).pieces():
		if p.get("mobility") == "wheeled":
			out.append(StringName(p["id"]))
	return out


## Where each placed piece of the live room stands in a room with `facts` (anchors only are read):
## id -> Transform3D, in studio space. A piece the shell has no room for (the sampler where there is
## no synth zone) is absent. The control room's furniture, which the venue files extend too, is not
## the venue's to stand (`ControlRoom` does, in the room's width), so it is left out: `Venue.default_spot`
## answers null for it, as it always did.
static func spots(facts: ShellFacts) -> Dictionary:
	var out := LayoutResolver.all(layout(facts.venue_id, facts.variant), facts)
	for p: Dictionary in ControlRoom.layout().pieces():
		out.erase(StringName(p["id"]))
	return out
