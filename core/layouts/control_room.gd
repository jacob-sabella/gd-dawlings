class_name ControlRoom
extends RefCounted

## Where the control room's furniture stands before anybody pushes it (docs/layouts.md section 11
## step 6): the shipped fragment `layouts/common/control_room.layout.json`, resolved against the
## room's width. `Studio` builds each trolley where this says (`_authored`), `SessionLayout.fit`
## reads its authored spots for the rack, the deck and the patch stand from it, and `Neighbourhoods`
## reads the mixing banner from it. A control room has no zones and no venue of its own, so the only
## facts it needs are the control room's width (`room_width`, which grows with the desk) and the
## lines every shell shares (`control_wall.left|right`, `control_rear`, `mix`, `height.control_header`).
##
## Not here, and why: the timeline stand (its z is the timeline's own, `Studio.TIMELINE_Z - 0.04`,
## derived from the surface it holds), the lamp stands (a lamp and its light are one row of
## `Studio.PRACTICALS`) and the LEVELS niche and TV bracket (the venue's: `Venue.levels_niche_spot`
## and `tv_mount_spot` depend on whether the back wall is one to build into, which the shell knows).

## The fragment's id.
const FRAGMENT := "common.control_room"

static var _layout: LayoutData


## The resolved fragment (resolved once, then kept).
static func layout() -> LayoutData:
	if _layout == null:
		_layout = LiveRoom.layouts().resolve(FRAGMENT)
	return _layout


## The facts a control room's placements are written against: its width, nothing else.
static func facts(room_width: float) -> ShellFacts:
	var f := ShellFacts.new()
	f.room_width = room_width
	return f


## Where piece `id` is authored to stand in a control room `room_width` wide, in the studio set's
## frame; null for a piece the fragment gives no place (LEVELS and the TV, whose venue says, and the
## two that ride a trolley, the stage table and the platter).
static func spot(id: StringName, room_width: float) -> Variant:
	return LayoutResolver.transform(layout(), id, facts(room_width))


## `spot(id)`'s floor point and its turn in degrees, as `Studio._trolley` takes them.
static func trolley_args(id: StringName, room_width: float) -> Array:
	var at: Transform3D = spot(id, room_width)
	return [Vector3(at.origin.x, 0.0, at.origin.z), rad_to_deg(heading(at))]


## The turn of `at` about +Y, in radians, in (-pi, pi]. (`Basis.get_euler` can answer a turn past a
## quarter as a flip of the other two axes, so the heading is read off the facing.)
static func heading(at: Transform3D) -> float:
	return atan2(at.basis.z.x, at.basis.z.z)


## Where piece `id` stands when the room is fitted round the desk (`SessionLayout.fit`): its `fit`
## entry in the fragment, else its authored place. {"at": Vector2, "yaw": radians}.
static func fit_of(id: StringName) -> Dictionary:
	var p := layout().piece(id)
	var fit: Dictionary = p.get("fit", {})
	if not fit.is_empty():
		var at: Array = fit["at"]
		return {"at": Vector2(float(at[0]), float(at[1])), "yaw": float(fit.get("yaw", 0.0))}
	var placed: Transform3D = spot(id, Studio.ROOM_WIDTH)
	return {"at": Vector2(placed.origin.x, placed.origin.z), "yaw": heading(placed)}


## Where the MIXING banner hangs in a control room `room_width` wide: the group's `banner` placement.
static func banner(room_width: float) -> Variant:
	for g: Dictionary in layout().body.get("groups", []):
		if g.get("id") == "mixing" and g.has("banner"):
			return LayoutResolver.place(g["banner"], facts(room_width))
	return null
