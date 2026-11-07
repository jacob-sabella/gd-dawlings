class_name PieceFeet
extends RefCounted

## What the validator knows about each kind of piece before piece definitions are data (docs/layouts.md
## 4.1; queue step 6 moves this into them): the floor footprint of a wheeled piece, the seat of a
## station, the claims of the one room-scale piece. Nothing is copied: the footprints are the ones the
## studio's trolleys use (`Studio.LIVE_TROLLEYS`), the heights are the classes' own, the seat is the
## station row's (`Stations`), the claims are the modular room's constants (`ModularAnnex`).

## The room-scale piece kind (docs/layouts.md 4.3).
const ANNEX := &"modular_annex"
## How much of the live room's side wall in front of the doorway is kept free (claims.clear_in_front_of_door).
const CLEAR_IN_FRONT_OF_DOOR := 1.2


## True for a kind with a known footprint: the wheeled five.
static func known(kind: StringName) -> bool:
	return Studio.LIVE_TROLLEYS.has(kind)


## The footprint of `kind` stood at `spot` (studio space): `{c, h, a, top}`, in the form of the walker.
## Empty for a kind with none known.
static func footprint(kind: StringName, spot: Transform3D) -> Dictionary:
	if not known(kind):
		return {}
	var spec: Array = Studio.LIVE_TROLLEYS[kind]
	var middle: Vector3 = spot * Vector3((spec[1] as Vector2).x, 0.0, (spec[1] as Vector2).y)
	return LayoutGeometry.footprint(Vector2(middle.x, middle.z), spec[2], LayoutGeometry.yaw_of(spot.basis), _top(kind))


## The station behind a free-standing piece, or an empty dictionary when it is not one: `{seat, look
## (local point it is looked at from), foot (half extents), foot_z}` from its Stations row.
static func station(kind: StringName) -> Dictionary:
	var row := Stations.row(kind)
	if row.is_empty() or not row.has("foot") or row.get("zone", &"") != &"":
		return {}
	return {"seat": float(row.get("seat", Stations.SEAT)), "look": row["at"], "foot": row["foot"], "foot_z": float(row["foot_z"])}


## The most of `kind` that may stand in one room, or 0 for no limit.
static func limit(kind: StringName) -> int:
	return 1 if kind == ANNEX else 0


## The claims of a room-scale piece whose edge anchor is at x = `edge`, or an empty dictionary for a
## single item: `{site (Rect2 of the ground it takes), door_z, door_width, door_walk (Rect2 kept clear
## in front of the doorway, on the live room's side)}`.
static func claims(kind: StringName, edge: float) -> Dictionary:
	if kind != ANNEX:
		return {}
	var wide := ModularAnnex.DOOR_WIDE
	return {"site": Rect2(edge, ModularAnnex.Z_FROM, ModularAnnex.GAP + ModularAnnex.WALL + ModularAnnex.DEEP,
					ModularAnnex.Z_TO - ModularAnnex.Z_FROM),
			"door_z": ModularAnnex.DOOR_Z, "door_width": wide,
			"door_walk": Rect2(edge - CLEAR_IN_FRONT_OF_DOOR, ModularAnnex.DOOR_Z - wide * 0.5, CLEAR_IN_FRONT_OF_DOOR - 0.15, wide)}


## How tall `kind` stands: the greatest `top` of its class's own solids.
static func _top(kind: StringName) -> float:
	match kind:
		&"prop_shelf":
			return ZoneKit.SHELF.y
		&"cassette_rack":
			return CassetteRack.TOP
		&"sampler":
			return Sampler.TOP
		&"tour_case":
			return TourCase.BODY_H + TourCase.LID_H
		&"hoop":
			return maxf(Hoop.BASE_TOP, Hoop.POLE_TOP)
	return Walker.SOLID_HEIGHT
