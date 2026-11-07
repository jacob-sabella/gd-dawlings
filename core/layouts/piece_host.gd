class_name PieceHost
extends RefCounted

## Stands the wheeled pieces of the live room in a Studio and carries what rides with them
## (docs/layouts.md 4.1, 11 step 6). The studio keeps the pieces' trolleys (`live_pieces`) and the
## nodes themselves, which are the venue's children; this reads each piece's `PieceDef` and does the
## two things the studio used to do per piece: `build` makes the trolley from the definition, and
## `carry` moves the piece's node to where its trolley is and runs its followers. The rehoming
## helpers (`rehome_items`, `rehome_spills`, `hold_the_rack`) live here because the followers are
## what call them; the studio calls them too, when a room is built or an item set up.

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## A trolley for each of `Venue.WHEELED`, from its definition, stood where this venue has it and
## registered as a live piece. Pushed across the floor on its own feet, not wheeled.
func build() -> void:
	var venue := studio.venue
	for id: StringName in Venue.WHEELED:
		var def := PieceDef.of(id)
		var spot: Variant = venue.default_spot(id) if venue != null else null
		var at: Transform3D = spot if spot != null else Transform3D.IDENTITY
		var t := studio._trolley(def.trolley_name, id, at.origin, rad_to_deg(at.basis.get_euler().y))
		t.footprint_centre = def.foot_centre
		t.footprint_half = def.foot_half
		t.follow = def.weight
		t.rolls = false
		for grip: Array in def.grips:
			studio._grip(t, grip[0], grip[1])
		if def.body_half != Vector2.ZERO:
			t.body_centre = def.body_centre
			t.body_half = def.body_half
		studio._go_live(t)


## Take piece `id` to where its trolley is now: its node, then each follower in order. Each frame
## the trolley moves, so a shelf's toys ride on it rather than catching up. False when `id` is not
## one of the defined pieces (the caller's own arms handle the rest).
func carry(id: StringName) -> bool:
	var def := PieceDef.of(id)
	if def == null:
		return false
	var venue := studio.venue
	var node: Node3D = _node_of(def)
	var spot: Variant = venue.call(StringName("%s_spot" % id))
	var standing := node != null and spot != null
	if standing:
		node.transform = studio._venue_to_set(spot) if def.node_in_set else spot
	for follower in def.followers:
		match follower:
			PieceDef.HOLD_RACK:
				if standing:
					hold_the_rack()
			PieceDef.SPILLS:
				if standing:
					rehome_spills()
			PieceDef.BOARDS:
				if studio.items != null:
					studio.items.boards = venue.dart_boards()
			PieceDef.HOOPS:
				if studio.items != null:
					studio.items.hoops = venue.hoops()
			PieceDef.ITEMS:
				rehome_items()
			PieceDef.HOLD_RACK_IF_GONE:
				# A cassette lies on the shelf when the rack is gone (`Studio._made_home`).
				if not _stands(studio.cassette_rack):
					hold_the_rack()
	return true


## The node that is piece `def`, or null where it is not built: a variable of the studio (valid
## only while alive) or a child of the venue.
func _node_of(def: PieceDef) -> Node3D:
	if def.studio_node != &"":
		var held: Variant = studio.get(def.studio_node)
		return held as Node3D if _stands(held) else null
	return studio.venue.get_node_or_null(def.venue_child) as Node3D


static func _stands(node: Variant) -> bool:
	return node != null and is_instance_valid(node)


## The items' homes from where the shelf and the hoop now are: one at home goes to its new spot
## (ItemRoom.set_spots).
func rehome_items() -> void:
	if studio.items != null and studio.venue != null:
		studio.items.set_spots(studio.venue.item_spots(), studio._item_homes())


## What the Tour case spilled, homed round where the case now stands (`Studio._spill_home`).
func rehome_spills() -> void:
	var items := studio.items
	if items == null or studio.tour_case == null:
		return
	var spilled := items.spawned_ids()
	for n in spilled.size():
		var item: Item = items.items.get(spilled[n])
		if item != null:
			item.home = studio._spill_home(n)


## The rack's slots and bin as the room's holders, and each made item's home its tray, in the
## room's frame (the venue's, as the shelf's spots are).
func hold_the_rack() -> void:
	var items := studio.items
	if items == null:
		return
	var rack := studio.cassette_rack
	if not _stands(rack):
		items.holders.clear()
		studio._hold_the_platter()
		return
	rack.items = items
	if _stands(studio.sampler):
		studio.sampler.items = items
	var at := rack.transform
	items.set_holder(CassetteRack.RACK, CassetteRack.slots_in(at))
	var bin: Array[Transform3D] = [at * CassetteRack.bin_pose()]
	items.set_holder(CassetteRack.BIN, bin)
	for id in items.made_ids():
		var item: Item = items.items[id]
		item.home = studio._made_home(ItemRoom.kind_of(id), int(String(id).trim_prefix(String(ItemRoom.kind_of(id)))))
		if item.state == Item.State.HOME:
			item.snap_home()
	studio._hold_the_platter()
