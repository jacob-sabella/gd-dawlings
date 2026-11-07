class_name PieceFeet
extends RefCounted

## What the validator knows about each kind of piece before piece definitions are data (docs/layouts.md
## 4.1; `PieceDef` now holds the wheeled five; the station and the annex move in with the rest of step 6): the floor footprint of a wheeled piece, the seat of a
## station, the claims of the one room-scale piece. Nothing is copied: the footprints are the ones the
## studio's trolleys use (`PieceDef`), the heights are the classes' own, the seat is the
## station row's (`Stations`), the claims are the modular room's constants (`ModularAnnex`).

## The room-scale piece kind (docs/layouts.md 4.3).
const ANNEX := &"modular_annex"
## How much of the live room's side wall in front of the doorway is kept free (claims.clear_in_front_of_door).
const CLEAR_IN_FRONT_OF_DOOR := 1.2


## True for a kind with a known footprint: the wheeled five.
static func known(kind: StringName) -> bool:
	return PieceDef.has(kind) and PieceDef.of(kind).mount == PieceDef.Mount.WHEELED


## True for a piece with no footprint of its own because it is mounted in a zone or by the shell
## (`PieceDef.Mount`), or is control-room furniture (the venue files extend `common.control_room`; those
## pieces stand inside the working footprint, which the validator keeps as one solid block): nothing
## is unknown of it, so the validator does not warn.
static func mounted(kind: StringName) -> bool:
	return (PieceDef.has(kind) and PieceDef.of(kind).mount != PieceDef.Mount.WHEELED) \
			or not ControlRoom.layout().piece(kind).is_empty()


## The footprint of `kind` stood at `spot` (studio space): `{c, h, a, top}`, in the form of the walker.
## Empty for a kind with none known.
static func footprint(kind: StringName, spot: Transform3D) -> Dictionary:
	if not known(kind):
		return {}
	var def := PieceDef.of(kind)
	var middle: Vector3 = spot * Vector3(def.foot_centre.x, 0.0, def.foot_centre.y)
	return LayoutGeometry.footprint(Vector2(middle.x, middle.z), def.foot_half, LayoutGeometry.yaw_of(spot.basis), def.top)


## The station behind a free-standing piece, or an empty dictionary when it is not one: `{seat, look
## (local point it is looked at from), foot (half extents), foot_z}` from its Stations row.
static func station(kind: StringName) -> Dictionary:
	var row := Stations.row(kind)
	if row.is_empty() or not row.has("foot") or row.get("zone", &"") != &"":
		return {}
	return {"seat": float(row.get("seat", Stations.SEAT)), "look": row["at"], "foot": row["foot"], "foot_z": float(row["foot_z"])}


## The most of `kind` that may stand in one room, or 0 for no limit.
static func limit(kind: StringName) -> int:
	return PieceDef.of(kind).limit if PieceDef.has(kind) else 0


## The claims of a room-scale piece whose edge anchor is at x = `edge`, or an empty dictionary for a
## single item: `{site (Rect2 of the ground it takes), door_z, door_width, door_walk (Rect2 kept clear
## in front of the doorway, on the live room's side)}`.
static func claims(kind: StringName, edge: float) -> Dictionary:
	if not PieceDef.room_scale(kind):
		return {}
	var wide := ModularAnnex.DOOR_WIDE
	return {"site": Rect2(edge, ModularAnnex.Z_FROM, ModularAnnex.GAP + ModularAnnex.WALL + ModularAnnex.DEEP,
					ModularAnnex.Z_TO - ModularAnnex.Z_FROM),
			"door_z": ModularAnnex.DOOR_Z, "door_width": wide,
			"door_walk": Rect2(edge - CLEAR_IN_FRONT_OF_DOOR, ModularAnnex.DOOR_Z - wide * 0.5, CLEAR_IN_FRONT_OF_DOOR - 0.15, wide)}
