class_name LayoutEdit
extends RefCounted

## The edits of a room's layout, as one verb (docs/layouts.md 7): `ask_layout(op, args)` with
##
##   move(id, x, z[, yaw])   rotate(id, yaw)   add(piece, x, z, yaw)   remove(id)   reset(id | "all")
##
## The host is the authority. An op is tried on a copy of the room's `RoomDelta`; the copy is laid over
## the room's layout and checked by `LayoutValidator` against the room's shell, and only if it brings no
## error the room did not already have is it committed (`RoomDeltas.commit`), the studio made to match
## (`RoomSync`, `RoomFloor.follow`) and the room published. A refused op leaves everything as it was and
## answers in words, so an edit is never half done. A guest's ask is answered "host only" (decision 3),
## except `move` of a piece on wheels, which is the push a guest makes by hand: placed here, and told to
## the host as it settles, as it always was.
##
## `ask` is the local side (`Studio.ask_layout`), `answer` the host's, given who asked. Both return the
## refusal, or "" when the op was done.

## What a guest is told.
const HOST_ONLY := "Only the host arranges the room."
## The ops, as asked.
const OPS: Array[String] = ["move", "rotate", "add", "remove", "reset"]
## Room-scale and not in a layout file yet: stood by the studio in every venue but the roulette room, so the
## checks that look for its site and its door still have it.
const ANNEX := {"id": "modular_annex", "piece": "modular_annex", "at": {"anchor": {"x": "annex_edge"}, "pos": [0.0, 0.0], "yaw": 0.0}}
## How far from the middle of the world a piece may be put, in metres (anything farther is a typo).
const FAR := 60.0

var studio: Studio
## The piece the `add` in hand is putting down, for `_nudged`.
var _placing: StringName = &""


func _init(of: Studio) -> void:
	studio = of


## The local side of an ask: the host does it, a guest is told "host only" unless it is a push.
func ask(op: String, args: Array) -> String:
	return answer(op, args, Session.local_peer_id)


## The host's answer to `op` asked by peer `from` (the host's own id for its own hands): "" if done, else why not,
## which `from` is also told. A guest that is not the host answers "host only" without trying anything.
func answer(op: String, args: Array, from: int) -> String:
	var why := HOST_ONLY
	if not Session.is_authority() or from != Session.local_peer_id:
		if op == "move" and _push(args):
			return ""
	if Session.is_authority() and from == Session.local_peer_id:
		why = _edit(op, args)
	if why != "":
		Session.tell(from, why)
	return why


## A guest's `move` of a piece with a trolley: the push, placed here (the settled trolley tells the host).
func _push(args: Array) -> bool:
	if args.size() < 3 or not _numbers(args.slice(1)):
		return false
	var t := studio.room_rows._floor_piece(StringName(args[0]))
	if t == null or not t.visible or RoomDelta.owned_by_player(t.piece_id):
		return false
	t.place(Vector2(float(args[1]), float(args[2])), float(args[3]) if args.size() > 3 else t.rotation.y)
	return true


## The host's edit: validated on a copy, committed whole or not at all.
func _edit(op: String, args: Array) -> String:
	var delta := studio.room_deltas.delta
	var candidate := delta.copy()
	_placing = &""
	var why := ""
	match op:
		"move":
			why = _move(candidate, args)
		"rotate":
			why = _rotate(candidate, args)
		"add":
			why = _add(candidate, args)
		"remove":
			why = _remove(candidate, args)
		"reset":
			why = _reset(candidate, args)
		_:
			why = "Nothing to do for '%s'." % op
	if why == "" and candidate.rev == delta.rev:
		return "Nothing changed."
	if why == "" and not (args.size() > 0 and args[0] is String and args[0] == "all" and op == "reset"):
		why = refusal(candidate)
		if why != "" and op == "add":
			why = _nudged(candidate, why)
	if why != "":
		return why
	studio.room_deltas.commit(candidate)
	RoomFloor.follow(studio, {}, false)
	studio.player_host._publish_room_soon()
	return ""


## An added piece that does not fit where it was asked goes to the nearest clear spot within 3 m, if there is
## one and it passes; `why` otherwise, the first refusal.
func _nudged(d: RoomDelta, why: String) -> String:
	var id := _placing
	var layout := layout_of(d)
	if id == &"" or layout == null:
		return why
	var wanted := Vector2(float(d.transform_of(id).origin.x), float(d.transform_of(id).origin.z))
	var clear: Variant = LayoutValidator.nearest_clear(layout, id, wanted, ShellFacts.of(studio.venue))
	if not clear is Vector2:
		return why
	d.move(id, clear.x, clear.y, d.transform_of(id).basis.get_euler().y)
	return refusal(d)


func _move(d: RoomDelta, args: Array) -> String:
	if args.size() < 3 or args.size() > 4 or not _numbers(args.slice(1)) or not _near(args[1], args[2]):
		return "Move needs a piece and where to: x and z in metres."
	var id := StringName(args[0])
	var why := _movable(d, id)
	if why != "":
		return why
	var here := _spot(id)
	d.move(id, float(args[1]), float(args[2]), float(args[3]) if args.size() > 3 else here[2])
	return ""


func _rotate(d: RoomDelta, args: Array) -> String:
	if args.size() != 2 or not _numbers(args.slice(1)):
		return "Rotate needs a piece and a turn in radians."
	var id := StringName(args[0])
	var why := _movable(d, id)
	if why != "":
		return why
	var here := _spot(id)
	d.move(id, here[0], here[1], wrapf(float(args[1]), -PI, PI))
	return ""


func _add(d: RoomDelta, args: Array) -> String:
	if args.size() != 4 or not (args[0] is String or args[0] is StringName) or not _numbers(args.slice(1)) or not _near(args[1], args[2]):
		return "Add needs a piece and where to: x, z and a turn."
	var kind := StringName(args[0])
	if PieceDef.room_scale(kind):
		return "The %s is a room-scale mod: a room is made with it, not given it from the floor." % LayoutChecks.name_of(kind)
	if kind not in PieceCatalogue.kinds():
		return "The %s cannot be added to a room." % LayoutChecks.name_of(kind)
	var yaw := wrapf(float(args[3]), -PI, PI)
	if d.is_removed(kind):
		if PieceCatalogue.zoned(kind):
			# A zone holds it: no spot to choose, only a zone to have in the room.
			if Stations.spot(studio.venue, kind) == null:
				return "This room has no place for the %s." % LayoutChecks.name_of(kind)
			d.put_back(kind)
			return ""
		d.put_back(kind)
		d.move(kind, float(args[1]), float(args[2]), yaw)
		_placing = kind
		return ""
	var have := _count(d, kind)
	if have >= PieceCatalogue.limit(kind):
		return "The room already has %s." % ("the %s" % LayoutChecks.name_of(kind) if PieceCatalogue.limit(kind) == 1
				else "%d %ss, the most it holds" % [have, LayoutChecks.name_of(kind)])
	if not PieceCatalogue.copies(kind):
		return "The room already has the %s." % LayoutChecks.name_of(kind)
	var def := PieceDef.of(kind)
	var taken: Array = _ids(d)
	_placing = PieceCatalogue.next_id(kind, taken)
	d.add_piece({"id": String(_placing), "piece": String(kind),
			"at": {"pos": [float(args[1]), float(args[2])], "yaw": yaw}, "footprint": [def.foot_half.x, def.foot_half.y]})
	return ""


func _remove(d: RoomDelta, args: Array) -> String:
	if args.size() != 1:
		return "Remove needs a piece."
	var id := StringName(args[0])
	if d.added_index(id) >= 0:
		d.drop_added(id)
		return ""
	if not PieceCatalogue.removable(id):
		return "The %s is part of the room; it stays." % LayoutChecks.name_of(id) if _in_layout(d, id) \
				else "There is no '%s' in this room." % id
	if d.is_removed(id):
		return "The %s is already out of the room." % LayoutChecks.name_of(id)
	if PieceCatalogue.zoned(id) and Stations.spot(studio.venue, id) == null:
		return "This room has no %s to take out." % LayoutChecks.name_of(id)
	d.take_out(id)
	return ""


func _reset(d: RoomDelta, args: Array) -> String:
	if args.size() != 1:
		return "Reset needs a piece, or \"all\"."
	var id := StringName(args[0])
	if id == &"all":
		d.clear()
		return ""
	if d.added_index(id) >= 0:
		d.drop_added(id)
		return ""
	if not _in_layout(d, id) and not d.is_removed(id) and not d.moved.has(String(id)):
		return "There is no '%s' in this room." % id
	d.unmove(id)
	d.put_back(id)
	return ""


## Why piece `id` cannot be moved or turned, or "".
func _movable(d: RoomDelta, id: StringName) -> String:
	if d.is_removed(id):
		return "The %s is out of the room." % LayoutChecks.name_of(id)
	if not _in_layout(d, id) and d.added_index(id) < 0:
		return "There is no '%s' in this room." % id
	var t := studio.room_rows._floor_piece(id)
	if d.added_index(id) >= 0 and not PieceCatalogue.buildable(StringName(d.added[d.added_index(id)]["piece"])):
		return "The %s is not installed here; it can be taken out, not moved." % LayoutChecks.name_of(d.added[d.added_index(id)]["piece"])
	if t == null or RoomDelta.owned_by_player(id) or t.built_in:
		return "The %s is built into the room; it cannot be moved." % LayoutChecks.name_of(id)
	return ""


## Where piece `id` stands now: [x, z, yaw], from its trolley.
func _spot(id: StringName) -> Array:
	var t := studio.room_rows._floor_piece(id)
	return [t.position.x, t.position.z, t.rotation.y] if t != null else [0.0, 0.0, 0.0]


func _in_layout(d: RoomDelta, id: StringName) -> bool:
	return not LiveRoom.layout(d.base, d.variant).piece(id).is_empty() or not ControlRoom.layout().piece(id).is_empty()


## How many of `kind` the room holds with `d` applied: the layout's (unless taken out) and the copies added.
func _count(d: RoomDelta, kind: StringName) -> int:
	var n := 0
	for p: Dictionary in d.apply(LiveRoom.layout(d.base, d.variant).body)["pieces"]:
		if p.get("piece") == String(kind) and p.get("enabled", true):
			n += 1
	return n


## Every piece id of the room with `d` applied.
func _ids(d: RoomDelta) -> Array:
	return d.apply(LiveRoom.layout(d.base, d.variant).body)["pieces"].map(func(p: Dictionary) -> String: return p["id"])


## The first error that `candidate` has and the room as it is does not, as a sentence; "" if it has none. The
## room's own errors (a piece left by hand where the floor plan could take it) do not count against an edit.
func refusal(candidate: RoomDelta) -> String:
	var facts := ShellFacts.of(studio.venue)
	var before := _errors(studio.room_deltas.delta, facts)
	var after := _errors(candidate, facts)
	if after.has("") and not before.has(""):
		return String(after[""].message)
	for key: String in after:
		if not before.has(key):
			return String((after[key] as LayoutIssue).message)
	return ""


## The errors of the room with `d` applied, by "code|piece|other".
func _errors(d: RoomDelta, facts: ShellFacts) -> Dictionary:
	var out := {}
	var layout := layout_of(d)
	if layout == null:
		var why := LayoutIssue.make(&"over_limit", LayoutIssue.ERROR, &"", &"", Vector2.ZERO,
				"A room holds at most %d pieces." % LayoutData.MAX_PIECES)
		out[""] = why
		return out
	for issue in LayoutValidator.validate(layout, facts):
		if issue.is_error():
			out["%s|%s|%s" % [issue.code, issue.piece, issue.other]] = issue
	return out


## The room's resolved layout with `d` applied (and the modular room, in the venues that stand it), or null when
## the result is more than a room may hold.
func layout_of(d: RoomDelta) -> LayoutData:
	var base := LiveRoom.layout(d.base, d.variant)
	var applied := d.apply(base.body)
	if not applied["ok"]:
		return null
	var out := LayoutData.new()
	out.id = base.id
	out.variant = base.variant
	out.chain = base.chain
	out.status = LayoutData.STATUS_OK
	out.body = base.body.duplicate()
	out.body["pieces"] = applied["pieces"]
	out.body["groups"] = applied["groups"]
	out.body["wiring"] = applied["wiring"]
	if _gets_the_annex(d.base, out.body["pieces"]):
		out.body["pieces"].append(ANNEX.duplicate(true))
	return out


## True when the room is to have the modular room added: not the roulette room, and not a room that lists
## the annex itself (a made room that chose it, or chose to go without).
func _gets_the_annex(base: StringName, pieces: Array) -> bool:
	if base == Venue.ROULETTE_ID:
		return false
	if MadeRooms.has(base):
		return false
	for p: Dictionary in pieces:
		if p.get("piece") == String(PieceFeet.ANNEX):
			return false
	return true


static func _numbers(values: Array) -> bool:
	return values.all(func(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v)))


static func _near(x: Variant, z: Variant) -> bool:
	return absf(float(x)) <= FAR and absf(float(z)) <= FAR
