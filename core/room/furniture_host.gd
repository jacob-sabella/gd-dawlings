class_name FurnitureHost
extends RefCounted

## The control room's furniture: the trolleys (stage, EQ wall, deck, rack, patch stand), the levels niche, the TV mount, the
## live pieces and the hood signs. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the
## studio, which delegates the calls other code makes.

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


func _build_furniture() -> void:
	# Saved spots that are an older room's defaults go, once, before anything reads them.
	FloorImport.run(Session.layout)
	FloorImport.into_room(Session.layout, studio.room_deltas)
	studio.floor_plan = FloorPlan.new()
	studio.floor_plan.name = "FloorPlan"
	studio.floor_plan.bounds = studio._room_bounds()
	studio.floor_plan.fixtures.append(studio._desk_footprint)
	studio.floor_plan.fixtures.append(studio._door_footprint)
	studio.add_child(studio.floor_plan)

	studio.surface_host._build_lamp_stands()
	# Before the board, whose rows are the stations standing here, the stage table among them.
	_build_stage_trolley()
	_build_eq_wall_trolley()
	_build_levels_niche()
	_build_tv_mount()
	studio.station_host._build_station_board()

	# A trolley for the deck. Two uprights and a shelf on a caster base; a tape machine on a
	# cart is what the right-hand side of a control room looks like, and it is the thing in
	# the room most often wheeled somewhere else.
	studio.deck_trolley = studio._authored("DeckTrolley", &"deck_trolley")
	studio.deck_trolley.footprint_half = Vector2(0.28, 0.21)
	studio.deck_trolley.follow = 10.0
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.56, 0.025, 0.42)
	base.mesh = base_mesh
	base.position = Vector3(0, Caster.HEIGHT + 0.0125, 0)
	base.material_override = Materials.furniture()
	studio.deck_trolley.add_part(base)
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(0.56, 0.04, 0.42)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0, 0.86, 0)
	shelf.material_override = Materials.furniture()
	GearTrim.edges(shelf)
	studio.deck_trolley.add_part(shelf)
	var post_bottom := Caster.HEIGHT + 0.025
	for dx in [-0.22, 0.22]:
		for dz in [-0.16, 0.16]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.03, 0.84 - post_bottom, 0.03)
			post.mesh = post_mesh
			post.position = Vector3(dx, (0.84 + post_bottom) * 0.5, dz)
			post.material_override = Materials.brushed_metal()
			studio.deck_trolley.add_part(post)
	studio.deck_trolley.add_corner_casters()
	_build_platter_leaf()
	# The board was made before the cart, and the platter on it is a station: its rows again.
	if studio.station_board != null:
		studio.station_board.set_venue(studio.venue)
		studio.station_host._fit_board_stand()

	# A plinth under the rack. A floor-standing rack puts its lowest unit at ankle height; every
	# control room that has one has it up on something -- and here the something has wheels,
	# because a rack of outboard is the piece of a studio people actually push about.
	studio.rack_trolley = studio._authored("RackTrolley", &"rack")
	studio.rack_trolley.footprint_centre = Vector2(0, -0.15)
	studio.rack_trolley.footprint_half = Vector2(0.30, 0.17)
	# Heavier than anything else on the floor. It is a cabinet full of steel.
	studio.rack_trolley.follow = 7.5
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(0.60, 0.30 - Caster.HEIGHT, 0.34)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, (0.30 + Caster.HEIGHT) * 0.5, -0.15)
	plinth.material_override = Materials.furniture()
	GearTrim.edges(plinth)
	studio.rack_trolley.add_part(plinth)
	studio.rack_trolley.add_corner_casters(0.05)

	# A stand under the timeline, which until now hung in the air.
	#
	# It is the only thing in the room that did. The rack has a plinth, the deck a trolley, the
	# bay a bridge, the console its own carcass -- and then a metre of lit panel floating at
	# head height with nothing holding it. In a close-up that reads as a screen. In a wide shot
	# of the room it reads as the one object that is software, which is the single thing this
	# project is trying not to be.
	#
	# Two legs and a crossbar, deliberately the same vocabulary as the patch stand rather than
	# a new idea: a room furnished out of three kinds of part looks like a room, and one
	# furnished out of six looks like a kit. The feet are on casters, like a whiteboard's.
	studio.timeline_stand = studio._trolley("TimelineStand", &"timeline_stand",
			Vector3(0, 0, Studio.TIMELINE_STAND_Z), 0.0)
	studio.timeline_stand.footprint_half = Vector2(Studio.TIMELINE_LEG_X + 0.05, 0.11)
	var foot_top := Caster.HEIGHT + 0.022
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.035, Studio.TIMELINE_STAND_TOP - foot_top, 0.05)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * Studio.TIMELINE_LEG_X, (Studio.TIMELINE_STAND_TOP + foot_top) * 0.5, 0)
		leg.material_override = Materials.furniture()
		studio.timeline_stand.add_part(leg)

		# A foot, because a 35mm post standing on a floor is a post that fell over a moment ago.
		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.10, 0.022, 0.22)
		foot.mesh = foot_mesh
		foot.position = Vector3(side * Studio.TIMELINE_LEG_X, Caster.HEIGHT + 0.011, 0)
		foot.material_override = Materials.furniture()
		studio.timeline_stand.add_part(foot)
		for end in [-0.075, 0.075]:
			studio.timeline_stand.add_caster(Vector2(side * Studio.TIMELINE_LEG_X, end))

	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(Studio.TIMELINE_LEG_X * 2.0 + 0.07, 0.028, 0.04)
	crossbar.mesh = crossbar_mesh
	# Behind the panel, all of it: nine centimetres deep and centred on the legs, its front stood
	# out through the panel's face across the scrub rail, and seen from below it was a bright
	# slab cut into the bottom of the timeline.
	crossbar.position = Vector3(0, Studio.TIMELINE_STAND_TOP + 0.012,
			(Studio.TIMELINE_Z - TimelineSurface.DEPTH * Studio.TIMELINE_SCALE - 0.004 - 0.02) - Studio.TIMELINE_STAND_Z)
	crossbar.material_override = Materials.brushed_metal()
	studio.timeline_stand.add_part(crossbar)

	_build_patch_stand()
	_build_live_pieces()


## The leaf off the deck cart's far end, away from the seat, at the shelf's height, on two posts
## and a foot with casters of its own, and the DJ platter on it (Platter.ON_CART, slice 27). The
## cart's footprint grows to take it in, so it is pushed, and stood clear of, as one piece.
func _build_platter_leaf() -> void:
	var leaf_x := Platter.ON_CART.origin.x
	var top := Platter.ON_CART.origin.y
	# From just under the shelf's end, a step below it, so the two never share a face.
	var leaf_from := Platter.LEAF_FROM
	var leaf_to := leaf_x + Platter.LEAF.x * 0.5
	var leaf := MeshInstance3D.new()
	leaf.name = "PlatterLeaf"
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(leaf_to - leaf_from, Platter.LEAF_THICK, Platter.LEAF.y)
	leaf.mesh = leaf_mesh
	leaf.position = Vector3((leaf_from + leaf_to) * 0.5, top - Platter.LEAF_THICK * 0.5, 0)
	leaf.material_override = Materials.furniture()
	GearTrim.edges(leaf)
	studio.deck_trolley.add_part(leaf)
	var outer := leaf_x + Platter.LEAF.x * 0.5 - 0.03
	var post_bottom := Caster.HEIGHT + 0.025
	for dz in [-0.16, 0.16]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.03, top - Platter.LEAF_THICK - post_bottom, 0.03)
		post.mesh = post_mesh
		post.position = Vector3(outer, (top - Platter.LEAF_THICK + post_bottom) * 0.5, dz)
		post.material_override = Materials.brushed_metal()
		studio.deck_trolley.add_part(post)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.06, 0.025, 0.42)
	foot.mesh = foot_mesh
	foot.position = Vector3(outer, Caster.HEIGHT + 0.0125, 0)
	foot.material_override = Materials.furniture()
	studio.deck_trolley.add_part(foot)
	for dz in [-0.165, 0.165]:
		studio.deck_trolley.add_caster(Vector2(outer, dz))
	# From the cart's near end to the leaf's far one.
	var near := -0.28
	var far := leaf_x + Platter.LEAF.x * 0.5
	studio.deck_trolley.footprint_centre = Vector2((near + far) * 0.5, 0)
	studio.deck_trolley.footprint_half = Vector2((far - near) * 0.5, maxf(0.21, Platter.LEAF.y * 0.5))
	studio.platter = Platter.new()
	studio.platter.transform = Platter.ON_CART
	studio.platter.authority = Session.is_authority
	studio.platter.find_file = studio._platter_file
	studio.platter.fetching = func(source: String) -> bool:
		return Session.role == Session.Role.GUEST and Session.files != null \
				and Session.files.fetch_state(source) == FileSend.FETCHING
	studio.platter.scratched.connect(studio._on_scratched)
	studio.deck_trolley.add_child(studio.platter)
	studio.deck_trolley.moved.connect(studio._hold_the_platter)
	studio.deck_trolley.settled.connect(studio._hold_the_platter)


## The stage table's trolley: four legs under an apron, a shelf low down, casters, and the
## table's plaque on its front under the rail (Stations.plaque). The table itself is a surface
## and rides it (`_ride`, in `_build_surfaces`).
func _build_stage_trolley() -> void:
	studio.stage_trolley = studio._authored("StageTrolley", &"stage_trolley")
	# The table and the rail along its front, on the floor.
	studio.stage_trolley.footprint_centre = Vector2(0, 0.065)
	studio.stage_trolley.footprint_half = Vector2(0.62, 0.53)
	studio.stage_trolley.follow = 9.0
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	var apron_mesh := BoxMesh.new()
	apron_mesh.size = Vector3(1.12, 0.07, 0.82)
	apron.mesh = apron_mesh
	apron.position = Vector3(0, Studio.STAGE_TOP - StageTable.THICK - 0.035, 0)
	apron.material_override = Materials.furniture()
	GearTrim.edges(apron)
	studio.stage_trolley.add_part(apron)
	var shelf := MeshInstance3D.new()
	shelf.name = "Shelf"
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(1.08, 0.025, 0.78)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0, Caster.HEIGHT + 0.12, 0)
	shelf.material_override = Materials.furniture()
	studio.stage_trolley.add_part(shelf)
	var leg_bottom := Caster.HEIGHT
	var leg_top := Studio.STAGE_TOP - StageTable.THICK - 0.07
	for dx in [-0.53, 0.53]:
		for dz in [-0.38, 0.38]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.035, leg_top - leg_bottom, 0.035)
			leg.mesh = leg_mesh
			leg.position = Vector3(dx, (leg_top + leg_bottom) * 0.5, dz)
			leg.material_override = Materials.brushed_metal()
			studio.stage_trolley.add_part(leg)
			studio.stage_trolley.add_caster(Vector2(dx, dz))
	var plaque := Stations.plaque(&"stage_table")
	# Hung by its top edge, which is where a folded plaque's title and key row stay: low enough
	# under the rail that its title key is not in the way of the rail's tags from the seat.
	plaque.position = Vector3(0, Studio.STAGE_PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5,
			StageTable.SIZE.y * 0.5 + 0.135)
	studio.stage_trolley.add_child(plaque)


## Where the EQ wall's trolley stands: against the right-hand side wall in front of the deck, this
## far in from it, turned a little toward the mix position, clear of the deck's cart, the corner's
## lamp and the door to the Rig Roulette room in the front wall. Its x follows the wall out as the
## room widens (`_fit_room_to_session`).
## Off the wall and into the ring since the room grew: against an 11 m room's wall its handle was
## 5.5 px from the seat.
## (The fragment's `eq_wall`: 1.9 m in from the right-hand wall, 1.6 m behind the seat.)


## The EQ wall's trolley: a plinth on casters and two uprights behind the board's edges, and the
## wall's plaque on the board's right-hand column, under SHOW (Stations.plaque, narrowed to the
## column). The board itself is a surface and rides it (`_ride`, in `_build_surfaces`).
func _build_eq_wall_trolley() -> void:
	studio.eq_wall_trolley = studio._authored("EqWallTrolley", &"eq_wall")
	var wide := EqWall.PLATE_WIDE + EqWall.BORDER * 2.0
	studio.eq_wall_trolley.footprint_centre = Vector2(0, -0.06)
	studio.eq_wall_trolley.footprint_half = Vector2(wide * 0.5, 0.16)
	studio.eq_wall_trolley.follow = 9.0
	# The uprights first: they are its handle, standing up over the deck's reels from the seat,
	# where the plinth at the floor is behind them (and is taken all the same).
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "Upright"
		var post_mesh := BoxMesh.new()
		var high := EqWall.BOTTOM + EqWall.TALL + EqWall.BORDER
		post_mesh.size = Vector3(0.05, high - Caster.HEIGHT, 0.05)
		post.mesh = post_mesh
		post.position = Vector3(side * (wide * 0.5 - 0.06), (high + Caster.HEIGHT) * 0.5, -0.06)
		post.material_override = Materials.brushed_metal()
		studio.eq_wall_trolley.add_part(post)
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(wide, 0.04, 0.3)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, Caster.HEIGHT + 0.02, -0.06)
	plinth.material_override = Materials.furniture()
	GearTrim.edges(plinth)
	studio.eq_wall_trolley.add_part(plinth)
	studio.eq_wall_trolley.add_corner_casters(0.06)
	var plaque := Stations.plaque(&"eq_wall", EqWall.SIDE - 0.02)
	plaque.position = Vector3(EqWall.PLATE_WIDE * 0.5 - EqWall.SIDE * 0.5,
			EqWall.PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, 0.012)
	studio.eq_wall_trolley.add_child(plaque)


## The LEVELS niche (slice 66; 2026-10-30, "its own like divet in the wall so it can be an entire
## wall"): where it is is the venue's (Venue.levels_niche_spot), in the set's frame.
func _levels_niche_at() -> Transform3D:
	return studio._venue_to_set(studio.venue.levels_niche_spot()) if studio.venue != null \
			else Transform3D(Basis.IDENTITY, Vector3(-studio.room_width * 0.5 + Venue.LEVELS_NICHE_FROM_LEFT, 0,
					Studio.ROOM_FRONT + Venue.LEVELS_NICHE_IN))


## The niche LEVELS is set into: a surround either side and over it standing out of the wall, a
## sill under it and a dark back, so the board is sunk in the wall rather than hung on it; a lit
## strip under the lintel. Where the venue has no wall to build into, a cabinet of the same, with
## a back of its own. A Trolley so the floor plan, the stations and the board's ride treat it as
## they treat every piece, but with nothing to take hold of and never rolled: it stays in the wall
## (`_set_levels_niche`), and a board put down by its handle goes back into it (`_reseat`).
func _build_levels_niche() -> void:
	var at := _levels_niche_at()
	studio.levels_niche = studio._trolley("LevelsNiche", &"levels", at.origin, rad_to_deg(at.basis.get_euler().y))
	studio.levels_niche.built_in = true
	studio.levels_niche.follow = 9.0
	_set_levels_niche()


## Build the niche for this venue and stand it where this venue keeps it. Its boxes overlap where
## they meet rather than touch, the lintel and the sill a step back from the cheeks, so no two faces
## share a plane to flicker between.
func _set_levels_niche() -> void:
	if studio.levels_niche == null:
		return
	for old in studio.levels_niche.get_children():
		if old.has_meta(&"niche"):
			studio.levels_niche.remove_child(old)
			old.queue_free()
	var standing := studio.venue != null and studio.venue.back_wall_gear_stands()
	var out := Studio.NICHE_STANDING_OUT if standing else Studio.NICHE_OUT
	var board := LevelsWall.room_y(LevelsWall.WIDE * 0.5 + LevelsWall.BORDER)
	# Room either side for the board's handle, on its left (LevelsWall.handle_left).
	var open := board + 0.12
	var outer := open + Studio.NICHE_SIDE
	var back := -(Studio.NICHE_STANDING_BACK if standing else Studio.NICHE_INTO_WALL)
	var lintel := LevelsWall.room_y(LevelsWall.BOTTOM + LevelsWall.TALL + LevelsWall.BORDER + 0.08) + 0.06
	var behind_board := -LevelsWall.room_y(0.031) - 0.004
	# Plaster a shade off every venue's walls, so it reads as the wall built out round a hollow and
	# not as one more black cabinet against it.
	var surround := Materials.painted_wall(Studio.NICHE_PLASTER)
	for side in [-1.0, 1.0]:
		# A hair off the floor, which the wall's own foot is on.
		_niche_box("Cheek", Vector3(Studio.NICHE_SIDE, Studio.NICHE_TOP - 0.002, out - back),
				Vector3(side * (open + Studio.NICHE_SIDE * 0.5), Studio.NICHE_TOP * 0.5 + 0.001, (out + back) * 0.5), surround)
	# Into the cheeks either side; a step back from their faces, and short of their tops and backs.
	var span := open * 2.0 + Studio.NICHE_SIDE
	var front := out - Studio.NICHE_STEP
	var rear := back + 0.01
	_niche_box("Lintel", Vector3(span, Studio.NICHE_TOP - 0.01 - lintel, front - rear),
			Vector3(0, (Studio.NICHE_TOP - 0.01 + lintel) * 0.5, (front + rear) * 0.5), surround)
	_niche_box("Sill", Vector3(span, Studio.NICHE_SILL - 0.004, front - rear),
			Vector3(0, (Studio.NICHE_SILL + 0.004) * 0.5, (front + rear) * 0.5), surround)
	_niche_box("Back", Vector3(span - 0.02, lintel - Studio.NICHE_SILL + 0.04, 0.02),
			Vector3(0, (lintel + Studio.NICHE_SILL) * 0.5, behind_board - 0.01), Materials.recess())
	if standing:
		# Its back: behind the cheeks' and a little inside their sides and top.
		_niche_box("Cabinet", Vector3(outer * 2.0 - 0.02, Studio.NICHE_TOP - 0.02, behind_board - 0.02 - (back - 0.01)),
				Vector3(0, Studio.NICHE_TOP * 0.5 - 0.005, (behind_board - 0.02 + back - 0.01) * 0.5), surround)
	# Light along the lintel's underside, to the board.
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(open * 2.0 - 0.1, 0.012, 0.03)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, lintel - 0.007, front - 0.06)
	strip.material_override = Materials.led(Color(1.0, 0.86, 0.66), true)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.set_meta(&"niche", true)
	strip.name = "Strip"
	studio.levels_niche.add_child(strip)
	# On the floor only in front of the wall: what is in the wall is the wall's.
	var foot_back := back - 0.01 if standing else -0.08
	studio.levels_niche.footprint_centre = Vector2(0, (out + foot_back) * 0.5)
	studio.levels_niche.footprint_half = Vector2(outer, (out - foot_back) * 0.5)
	var plaque := Stations.plaque(&"levels", LevelsWall.room_y(LevelsWall.MASTER_WIDE))
	plaque.set_meta(&"niche", true)
	plaque.position = Vector3(LevelsWall.room_y(LevelsWall.master_left() + LevelsWall.MASTER_WIDE * 0.5),
			LevelsWall.PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, front + 0.006)
	studio.levels_niche.add_child(plaque)
	var at := _levels_niche_at()
	studio.levels_niche.place(Vector2(at.origin.x, at.origin.z), at.basis.get_euler().y)


## The TV's bracket (docs/sampling_station.md): where it is is the venue's (Venue.tv_mount_spot), in
## the set's frame.
func _tv_mount_at() -> Transform3D:
	return studio._venue_to_set(studio.venue.tv_mount_spot()) if studio.venue != null \
			else Transform3D(Basis.IDENTITY, Vector3(studio.room_width * 0.5 - Venue.TV_FROM_RIGHT, 0,
					Studio.ROOM_FRONT + Venue.TV_IN))


func _build_tv_mount() -> void:
	var at := _tv_mount_at()
	studio.tv_mount = studio._trolley("TvMount", &"tv", at.origin, rad_to_deg(at.basis.get_euler().y))
	studio.tv_mount.built_in = true
	studio.tv_mount.follow = 9.0
	_set_tv_mount()


## The TV's bracket for this venue, or its stand where the wall is not one to hang it on, and the
## plaque under it; stood where this venue keeps it.
func _set_tv_mount() -> void:
	if studio.tv_mount == null:
		return
	for old in studio.tv_mount.get_children():
		if old.has_meta(&"mount"):
			studio.tv_mount.remove_child(old)
			old.queue_free()
	var standing := studio.venue != null and studio.venue.back_wall_gear_stands()
	var metal := Materials.brushed_metal()
	var back := -TvSurface.DEPTH
	if standing:
		# Two legs from feet on the floor up the case's back, and a bar across them.
		for side in [-1.0, 1.0]:
			var x: float = side * TvSurface.SCREEN.x * 0.3
			# The leg's foot sunk into the foot's top, the foot a hair off the floor: no face shared.
			_mount_box("Leg", Vector3(0.05, TvSurface.TOP - 0.12, 0.05),
					Vector3(x, 0.02 + (TvSurface.TOP - 0.12) * 0.5, back - 0.03), metal)
			_mount_box("Foot", Vector3(0.08, 0.03, 0.62), Vector3(x, 0.017, back - 0.03 + 0.08), metal)
		# Into the legs, short of their far sides.
		_mount_box("Bar", Vector3(TvSurface.SCREEN.x * 0.6 - 0.02, 0.04, 0.03),
				Vector3(0, TvSurface.FOOT + 0.2, back - 0.03), metal)
		studio.tv_mount.footprint_centre = Vector2(0, back + 0.05)
		studio.tv_mount.footprint_half = Vector2(TvSurface.SCREEN.x * 0.3 + 0.05, 0.31)
	else:
		# An arm from the wall to the case's back.
		var wall := -Venue.TV_IN + 0.05
		_mount_box("Arm", Vector3(0.12, 0.12, back - wall - 0.004),
				Vector3(0, (TvSurface.TOP + TvSurface.FOOT) * 0.5, (back - 0.002 + wall) * 0.5), metal)
		studio.tv_mount.footprint_centre = Vector2(0, -0.06)
		studio.tv_mount.footprint_half = Vector2(TvSurface.SCREEN.x * 0.5 + TvSurface.BEZEL, 0.06)
	var plaque := Stations.plaque(&"tv", TvSurface.SCREEN.x * 0.5)
	plaque.set_meta(&"mount", true)
	plaque.position = Vector3(0, TvSurface.PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, 0.006)
	studio.tv_mount.add_child(plaque)
	var at := _tv_mount_at()
	studio.tv_mount.place(Vector2(at.origin.x, at.origin.z), at.basis.get_euler().y)


func _mount_box(of_name: String, size: Vector3, at: Vector3, paint: Material) -> void:
	var box := MeshInstance3D.new()
	box.name = of_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	box.material_override = paint
	box.set_meta(&"mount", true)
	studio.tv_mount.add_part(box, false)


## FIND on the TV: a search or a link asked for on the monitor; a link plays, a search lists what it
## found (`_on_tv_searched`). From a desk: a headset has no keyboard to type a search with yet.
func find_on_tv() -> void:
	if studio.tv == null or not is_instance_valid(studio.tv):
		return
	if studio.get_viewport() != null and studio.get_viewport().use_xr:
		Session.notice.emit("The TV's FIND is typed: from a desk, for now.")
		return
	var prompt := NamePrompt.ask(studio, "YouTube: a search, or paste a link", "", 300)
	prompt.answered.connect(func(text: String) -> void:
		if text.strip_edges() != "" and studio.tv != null and is_instance_valid(studio.tv):
			studio.tv.find(text))


## A pad struck at the sampling station (PadDeck): onto the armed track as a note while the song
## records, as a played key is. The host takes it down; a guest's pads are slice 7's.
func _on_pad_struck(note: int, velocity: int, seconds: float) -> void:
	var track := HitRecorder.armed_track()
	if track <= 0 or studio.hit_recorder == null or not Session.is_authority():
		return
	studio.hit_recorder.note(track, note, velocity, InstrumentItem.MELODIC_CHANNEL, maxf(seconds, 0.05),
			studio.hit_recorder.stamp())


func _on_tv_searched(query: String, rows: Array, error: String) -> void:
	if error != "" or rows.is_empty() or studio.tv == null or not is_instance_valid(studio.tv):
		return
	if studio.get_viewport() != null and studio.get_viewport().use_xr:
		return
	var choices: Array = []
	for row: Dictionary in rows:
		var long := TvSurface._clock(float(row.seconds)) if float(row.seconds) > 0.0 else "live"
		var by := ("  ·  " + str(row.channel)) if str(row.channel) != "" else ""
		choices.append([str(row.id), "%s  ·  %s%s" % [row.title, long, by]])
	var picker := PluginPicker.ask(studio, "YouTube: " + query.strip_edges(), choices)
	picker.chosen.connect(func(id: String) -> void:
		if studio.tv != null and is_instance_valid(studio.tv):
			studio.tv.watch(id))


func _niche_box(of_name: String, size: Vector3, at: Vector3, paint: Material) -> void:
	var box := MeshInstance3D.new()
	box.name = of_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	box.material_override = paint
	box.set_meta(&"niche", true)
	studio.levels_niche.add_part(box, false)


## The bay's own cabinet: a plinth on casters, a carcass under the panel and a cheek either side
## running up past its top, so the bay stands in a frame rather than on a post. The carcass and
## cheeks are sized to the bay once it knows how many rows it has (`_fit_stand_to_bay`).
func _build_patch_stand() -> void:
	studio.patch_stand = studio._authored("PatchStand", &"patch_stand")
	studio.patch_stand.footprint_centre = Vector2(0, -0.03)
	studio.patch_stand.footprint_half = Vector2(0.62, 0.15)
	studio.patch_stand.follow = 9.0
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(1.20, 0.03, 0.28)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, Caster.HEIGHT + 0.015, -0.03)
	plinth.material_override = Materials.furniture()
	studio.patch_stand.add_part(plinth)
	studio._patch_cabinet = MeshInstance3D.new()
	studio._patch_cabinet.name = "Cabinet"
	studio._patch_cabinet.mesh = BoxMesh.new()
	studio._patch_cabinet.material_override = Materials.furniture()
	studio.patch_stand.add_part(studio._patch_cabinet)
	for side in [-1.0, 1.0]:
		var cheek := MeshInstance3D.new()
		cheek.name = "Cheek"
		cheek.mesh = BoxMesh.new()
		cheek.material_override = Materials.end_cheek()
		studio.patch_stand.add_part(cheek)
		studio._patch_cheeks.append(cheek)
	studio.patch_stand.add_corner_casters(0.06)
	studio._fit_stand_to_bay()


# --- what stands out in the venue on its own ------------------------------------------------
#
# The cassette rack, the sampler, the Tour case, the prop shelf and
# the hoop stand on the floor by themselves, the way the rack and the deck's cart do, so they are
# pushed about the same way: a trolley each, saved where it was left (the room's delta, `RoomDeltas`) and shared
# with the room like the rest. What is built into a venue -- its walls and doors, the riser, the
# booth, the bricks table and the wheel on it, the lattice's frame, the screens on the walls --
# stays where the venue put it, and is what a pushed piece stops at (FloorPlan.stops).
#
# The things themselves are still the venue's children, built with each venue in its own
# materials; their trolley is the studio's and says where they stand (Venue._spot_of), so moving
# it moves them (`_carry_live`), and everything that is measured from them -- a station's seat
# and the board's rows, the items' homes on the shelf, the rack's slots, the
# baskets a ball goes through, the dartboard on the shelf's posts -- goes with them.

## A wheeled piece's trolley for each of Venue.WHEELED (`PieceHost.build`, from its `PieceDef`), and the patch wall's legs; stood where
## this venue has them (`RoomSync.wheel_in`) and what stands on them taken there.
func _build_live_pieces() -> void:
	studio.floor_plan.rooms = studio.venue.rooms() if studio.venue != null else []
	studio.floor_plan.stops.append(studio._venue_stops)
	studio.pieces.build()
	_build_patch_wall_legs()
	RoomSync.wheel_in(studio)
	_carry_all_live()


## A box to take a trolley by, of `size` centred at `at` in its frame, with nothing drawn: the
## piece's own plinth or feet are drawn by the piece.
func _grip(t: Trolley, size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	t.add_child(shape)
	return shape


## Known as one of `live_pieces`, and what stands on it carried along as it moves.
func _go_live(t: Trolley) -> void:
	studio.live_pieces[t.piece_id] = t
	t.moved.connect(_carry_live.bind(t.piece_id))
	t.settled.connect(_carry_live.bind(t.piece_id))


## The patch wall's two legs, on a trolley; the screen is the venue's child (`_stand_a_patch_wall`),
## and goes where the legs are.
func _build_patch_wall_legs() -> void:
	var legs := studio._authored("PatchWallLegs", &"patch_wall")
	legs.footprint_centre = Vector2(0, Studio.PATCH_WALL_LEG_Z)
	legs.footprint_half = Vector2(Studio.PATCH_WALL_LEG_X + 0.06, 0.06)
	legs.follow = 8.0
	legs.rolls = false
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.name = "PatchWallLeg"
		var post := BoxMesh.new()
		post.size = Vector3(0.06, 1.6, 0.06)
		leg.mesh = post
		leg.position = Vector3(side * Studio.PATCH_WALL_LEG_X, 0.8, Studio.PATCH_WALL_LEG_Z)
		leg.material_override = Materials.furniture()
		legs.add_part(leg)
	_go_live(legs)


## Where piece `id` of `live_pieces` stands in this venue until somebody moves it, in the set's
## frame; null where this venue has no room for it: the Rig Roulette room has no booth for the
## sampler to stand against, and a venue that hangs its own patch wall needs no legs for one.
func _live_default(id: StringName) -> Variant:
	if studio.venue == null or studio.room_deltas.delta.is_removed(id):
		return null
	var added: Variant = studio.room_deltas.delta.transform_of(id) if studio.room_deltas.delta.added_index(id) >= 0 else null
	if added != null:
		return added
	match id:
		&"station_board":
			return ControlRoom.spot(&"station_board", studio.room_width)
		&"patch_wall":
			var hung := studio.venue.get_node_or_null("PatchWall")
			if hung != null and not hung.has_meta(&"on_legs"):
				return null
			return ControlRoom.spot(&"patch_wall", studio.room_width)
	var spot: Variant = studio.venue.default_spot(id)
	return studio._venue_to_set(spot) if spot != null else null


func _carry_all_live() -> void:
	for id: StringName in studio.live_pieces:
		_carry_live(id)


## Take what stands on piece `id` to where its trolley is now: the thing itself, and whatever is
## measured from it. Each frame it moves, so a shelf's toys ride on it rather than catching up.
func _carry_live(id: StringName) -> void:
	if studio.venue == null or not studio.venue.is_inside_tree():
		return
	# The five defined pieces carry through their definitions (PieceDef); the rest are the studio's own.
	if not studio.pieces.carry(id):
		match id:
			&"mini_table":
				studio.pieces.rehome_items()
			&"station_board":
				if studio.station_board != null and is_instance_valid(studio.station_board):
					studio.station_board.transform = (studio.live_pieces[id] as Trolley).transform
			&"patch_wall":
				var wall := studio.venue.get_node_or_null("PatchWall") as Node3D
				if wall != null and wall.has_meta(&"on_legs"):
					wall.transform = studio._patch_wall_frame()
	_place_hood_signs()


## The neighbourhoods' banners (Neighbourhoods), the venue's children, one on the wall by each
## neighbourhood that stands here: built with the venue, and moved with what they name
## (`_place_hood_signs`).
func _hang_hood_signs() -> void:
	if studio.venue == null or studio.medium == Presentation.Medium.AR:
		return
	for r: Dictionary in Neighbourhoods.all():
		if Neighbourhoods.sign_spot(studio.venue, r["id"]) == null:
			continue
		studio.venue.add_child(Neighbourhoods.make_sign(r["id"]))
	_place_hood_signs()


## Each banner on its wall by its neighbourhood's middle as it stands now: a piece wheeled across
## the room takes its neighbourhood's middle, and so its banner, some of the way along the wall with
## it, or round to another wall.
func _place_hood_signs() -> void:
	if studio.venue == null or not is_instance_valid(studio.venue):
		return
	for r: Dictionary in Neighbourhoods.all():
		var sign := studio.venue.get_node_or_null("Sign_%s" % r["id"]) as Node3D
		if sign == null:
			continue
		var at: Variant = Neighbourhoods.sign_spot(studio.venue, r["id"])
		sign.visible = at != null
		if at != null:
			sign.transform = at
