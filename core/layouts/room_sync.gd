class_name RoomSync
extends RefCounted

## Makes the studio stand what the room's delta says (docs/layouts.md 7): the pieces the room `added` are
## built (`PieceCatalogue`: a copy of a hoop, by `Hoop.new`, on a trolley of the hoop's `PieceDef`), and the
## layout pieces it `removed` are not stood (the rack and the sampler have their node taken down, the
## hoop is hidden and leaves the baskets a ball can go through, each trolley is hidden so the floor plan and a
## cursor ignore it). Called on the host after an edit and by a guest that has adopted the host's `layout`
## row, and when a venue is built; idempotent, so calling it again changes nothing.
##
## The copies' nodes are children of the venue named `Copy_<id>`, so they go with it when the venue changes
## and `venue_built` stands them again in the next; their trolleys are the studio's and stay.

## The meta a copy's trolley carries: the kind it is a copy of.
const COPY_OF := &"copy_of"
## The pieces the studio stands by `PieceHost.stand` and can therefore take down.
const NODES: Array[StringName] = [&"cassette_rack", &"sampler"]


## The copy nodes and the removed hoop for a venue just built (its children are new): before it is stood.
static func venue_built(studio: Studio) -> void:
	if studio.floor_plan == null or studio.venue == null or not studio.venue.is_inside_tree():
		return
	var delta := studio.room_deltas.delta
	_copies(studio, delta)
	_hoop(studio, not delta.is_removed(&"hoop"))


## Everything of the delta: `venue_built`, then the rack and the sampler stood or taken down, the trolleys
## shown or hidden, and the baskets told to the items.
static func sync(studio: Studio) -> void:
	venue_built(studio)
	if studio.floor_plan == null or studio.venue == null or not studio.venue.is_inside_tree():
		return
	for id in PieceCatalogue.REMOVABLE:
		if PieceCatalogue.zoned(id):
			_zoned(studio, id)
			continue
		var t: Trolley = studio.live_pieces.get(id)
		var wanted: bool = studio._live_default(id) != null
		if t != null:
			t.visible = wanted
		if id in NODES:
			var stands := PieceHost._stands(studio.get(PieceDef.of(id).studio_node))
			if stands and not wanted:
				studio.pieces.unstand(id)
			elif wanted and not stands:
				studio.pieces.stand(id)
				studio._carry_live(id)
	_baskets(studio)


## A piece a zone holds, stood or taken down to match the delta: taken down when the room did without it,
## stood again when it is back (and the venue has the zone).
static func _zoned(studio: Studio, id: StringName) -> void:
	var stands := PieceHost._stands(studio.get(PieceDef.of(id).studio_node))
	var wanted: bool = not studio.room_deltas.delta.is_removed(id)
	if stands and not wanted:
		studio.pieces.unstand(id)
	elif wanted and not stands:
		studio.pieces.stand(id)


## Copy `id`'s node moved to where its trolley is, and the baskets told. False for an id that is no copy.
static func carry_copy(studio: Studio, id: StringName) -> bool:
	var t: Trolley = studio.live_pieces.get(id)
	if t == null or not t.has_meta(COPY_OF):
		return false
	var node := studio.venue.get_node_or_null(node_name(id)) as Node3D
	if node != null:
		node.transform = studio._set_to_venue(t.transform)
	_baskets(studio)
	return true


## The name of copy `id`'s node.
static func node_name(id: StringName) -> String:
	return "Copy_%s" % id


## Every basket a ball can go through: the venue's, if it is stood, and each hoop copy's. Same shape as `Venue.hoops`.
static func hoops(studio: Studio) -> Array:
	var out: Array = []
	for shape: Dictionary in studio.venue.hoops():
		var node: Variant = shape.get("node")
		if node == null or (node as Node3D).visible:
			out.append(shape)
	for id: StringName in studio.live_pieces:
		var t: Trolley = studio.live_pieces[id]
		var node := studio.venue.get_node_or_null(node_name(id)) as Node3D
		if t.has_meta(COPY_OF) and node != null and t.visible:
			var shape := Hoop.shape(studio._set_to_venue(t.transform))
			shape["node"] = node
			out.append(shape)
	return out


static func _baskets(studio: Studio) -> void:
	if studio.items != null and studio.venue != null:
		studio.items.hoops = hoops(studio)


## The venue's own hoop shown or hidden (it is the venue's node: it cannot be taken down).
static func _hoop(studio: Studio, shown: bool) -> void:
	var node := studio.venue.get_node_or_null("Hoop") as Node3D
	if node != null:
		node.visible = shown
	_baskets(studio)


## The copies the delta adds stood, the ones it no longer has taken down.
static func _copies(studio: Studio, delta: RoomDelta) -> void:
	var wanted := {}
	for entry in delta.added:
		if PieceCatalogue.copies(StringName(entry["piece"])):
			wanted[StringName(entry["id"])] = StringName(entry["piece"])
	for id: StringName in studio.live_pieces.keys():
		var t: Trolley = studio.live_pieces[id]
		if t.has_meta(COPY_OF) and not wanted.has(id):
			_take_down(studio, id, t)
	_gaps(studio, delta)
	for id: StringName in wanted:
		var t: Trolley = studio.live_pieces.get(id)
		if t == null:
			t = _build(studio, id, wanted[id], delta)
		if studio.venue.get_node_or_null(node_name(id)) == null:
			var node: Node3D = _node_of(wanted[id])
			node.name = node_name(id)
			studio.venue.add_child(node)
			node.transform = studio._set_to_venue(t.transform)
		t.visible = true


## The plates for the pieces the delta adds that this build cannot make (`PieceGap`): one in each's place,
## and any a delta no longer has taken down. They are nodes of the venue only; no trolley, nothing in the
## floor plan.
static func _gaps(studio: Studio, delta: RoomDelta) -> void:
	var wanted := {}
	for entry in delta.added:
		if not PieceCatalogue.buildable(StringName(entry["piece"])):
			wanted[node_name(StringName(entry["id"]))] = entry
	for child in studio.venue.get_children():
		if child is PieceGap and not wanted.has(child.name):
			studio.venue.remove_child(child)
			child.queue_free()
	for node_id: String in wanted:
		var entry: Dictionary = wanted[node_id]
		var gap := studio.venue.get_node_or_null(node_id) as PieceGap
		if gap == null:
			gap = PieceGap.for_entry(entry)
			studio.venue.add_child(gap)
		gap.transform = studio._set_to_venue(delta.transform_of(StringName(entry["id"])))


## The trolley of a copy of `kind`, a hoop's: its footprint, weight and grips from the `PieceDef`, as the hoop's own.
static func _build(studio: Studio, id: StringName, kind: StringName, delta: RoomDelta) -> Trolley:
	var at: Transform3D = delta.transform_of(id)
	var t := studio._trolley("Copy%sTrolley" % String(id).capitalize().replace(" ", ""), id, at.origin, rad_to_deg(at.basis.get_euler().y))
	t.set_meta(COPY_OF, kind)
	studio.pieces.equip(t, PieceDef.of(kind))
	studio._go_live(t)
	return t


## The node of a copy of `kind`, made by the builder the venue uses for its own.
static func _node_of(kind: StringName) -> Node3D:
	match kind:
		&"hoop":
			return Hoop.new()
	return Node3D.new()


static func _take_down(studio: Studio, id: StringName, t: Trolley) -> void:
	var node := studio.venue.get_node_or_null(node_name(id)) if studio.venue != null else null
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()
	studio.live_pieces.erase(id)
	studio._authored_floor.erase(id)
	studio.floor_plan.pieces.erase(t)
	if t.get_parent() != null:
		t.get_parent().remove_child(t)
	t.queue_free()


## Every piece of `live_pieces` stood for the venue just built: hidden, and out of everyone's way, where it
## has no room for it (or the room does without it); else where this player last left it, or, never moved,
## where the venue stands it. Then each is settled against the others and the venue's own solids, so a spot
## left in one venue that is a wall in this one is the nearest clear place to it. Not saved: none of this
## was anyone's push. (Was `Studio._wheel_in_live_pieces`.)
static func wheel_in(studio: Studio) -> void:
	if studio.floor_plan == null or studio.venue == null or studio.live_pieces.is_empty():
		return
	studio.floor_plan.rooms = studio.venue.rooms()
	venue_built(studio)
	var placing: Array[Trolley] = []
	for id: StringName in studio.live_pieces:
		var t: Trolley = studio.live_pieces[id]
		var spot: Variant = studio._live_default(id)
		t.visible = spot != null
		# Where the venue only draws the shelf, what stands about with it is drawn to walk through.
		t.walk_through = Venue.WHEELED.has(id) and not studio.venue.prop_shelf_solid()
		if spot == null or t.held_by != null:
			continue
		var at: Transform3D = spot
		var left: Variant = studio.room_deltas.saved(id, null)
		if left != null:
			at = left
		t.position = Vector3(at.origin.x, 0, at.origin.z)
		t.rotation = Vector3(0, at.basis.get_euler().y, 0)
		placing.append(t)
	var was: bool = studio._fitting
	studio._fitting = true
	for t in placing:
		t.place(Vector2(t.position.x, t.position.z), t.rotation.y)
	studio._fitting = was
