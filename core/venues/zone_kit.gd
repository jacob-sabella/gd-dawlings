class_name ZoneKit
extends RefCounted

## The shapes every venue dresses its activity zones with (see Venue.ZONES): a riser, a booth, a
## table, a keyboard stand, a mic stand, a box's edges. Venues bring their own materials, so the
## same riser is carpet and oak in the studio and black glass ruled in neon on the grid.
##
## A zone's dressing is one node named "Zone_<id>" under the venue, positioned at the zone's
## floor centre; everything in it is in that local frame.


## The sizes every venue's dressing shares, so what you bump into is where the thing is drawn.
const RISER_INSET := 0.2
const RISER_HEIGHT := 0.3
const TABLE_TOP := Vector3(1.0, 0.05, 2.0)
const TABLE_HEIGHT := 0.92
const STAND_WIDTH := 1.5
const BOOTH_POST := 0.07
const BOOTH_DOOR := 0.8
## Which wall of the booth the door is in: the one facing the middle of the room.
const BOOTH_DOOR_SIDE := Vector3(1, 0, 0)


## What in the zones stops you, as walker footprints ({c, h, a, top}) in studio space: the
## riser (a step: low enough to walk up onto), the table, the keyboard stand and -- when the
## venue builds one with walls -- the booth's four walls, less its doorway. The lattice's zone
## is open floor; you walk into it.
static func solids(zones: Dictionary, booth_walls: bool) -> Array:
	var out: Array = []
	var drums: AABB = zones[&"drums"]
	out.append(_print(drums, Vector2(drums.size.x, drums.size.z) * 0.5 - Vector2.ONE * RISER_INSET * 0.5,
			RISER_HEIGHT))
	out.append(_print(zones[&"bricks"], Vector2(TABLE_TOP.x, TABLE_TOP.z) * 0.5, TABLE_HEIGHT))
	# The stand's feet are half a metre deep and its decks a little over a metre up.
	out.append(_print(zones[&"synth"], Vector2(0.25, STAND_WIDTH * 0.5), 1.05))
	if booth_walls:
		var booth: AABB = zones[&"vocals"]
		var c := Vector2(booth.get_center().x, booth.get_center().z)
		var hx := booth.size.x * 0.5
		var hz := booth.size.z * 0.5
		var t := BOOTH_POST * 0.5
		out.append({"c": c + Vector2(0, -hz + t), "h": Vector2(hx, t), "a": 0.0, "top": booth.size.y})
		out.append({"c": c + Vector2(0, hz - t), "h": Vector2(hx, t), "a": 0.0, "top": booth.size.y})
		out.append({"c": c + Vector2(-hx + t, 0), "h": Vector2(t, hz), "a": 0.0, "top": booth.size.y})
		# The door side: wall from the -Z corner up to the doorway at the +Z end, as `booth` builds it.
		var wall := booth.size.z - BOOTH_DOOR
		out.append({"c": c + Vector2(hx - t, -hz + wall * 0.5), "h": Vector2(t, wall * 0.5), "a": 0.0,
				"top": booth.size.y})
	return out


static func _print(zone: AABB, half: Vector2, top: float) -> Dictionary:
	return {"c": Vector2(zone.get_center().x, zone.get_center().z), "h": half, "a": 0.0, "top": top}


## The node a zone's dressing goes in, added to `venue` and stood at the zone's floor centre.
static func holder(venue: Node3D, id: StringName, box: AABB) -> Node3D:
	var node := Node3D.new()
	node.name = "Zone_" + String(id)
	node.set_meta(&"zone", id)
	node.position = Vector3(box.get_center().x, 0.0, box.get_center().z)
	venue.add_child(node)
	return node


## A box of `size` whose centre is at `at`, in `parent`.
static func block(parent: Node3D, size: Vector3, at: Vector3, material: Material,
		label := "Block") -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.position = at
	piece.material_override = material
	parent.add_child(piece)
	return piece


## The twelve edges of a box `size` centred on the origin, as bars `thick` square, in one mesh.
## One draw call for a cube outline instead of twelve.
static func edges(size: Vector3, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	var h := size * 0.5
	var bars: Array = []
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			bars.append([Vector3(0, a * h.y, b * h.z), Vector3(size.x + thick, thick, thick)])
			bars.append([Vector3(a * h.x, 0, b * h.z), Vector3(thick, size.y + thick, thick)])
			bars.append([Vector3(a * h.x, b * h.y, 0), Vector3(thick, thick, size.z + thick)])
	for bar in bars:
		var piece := BoxMesh.new()
		piece.size = bar[1]
		st.append_from(piece, 0, Transform3D(Basis.IDENTITY, bar[0]))
	return st.commit()


## A rectangle of tape or inlay on the floor: four strips `width` wide round `size`, centred on
## `at`, standing a hair proud so they never fight the floor for the same plane.
static func floor_frame(parent: Node3D, size: Vector2, at: Vector3, width: float,
		material: Material) -> void:
	var lift := 0.003
	# The long strips take the corners and the short ones stop at them: overlapping, the corner
	# squares would be two coplanar tops fighting.
	for spec in [[Vector3(0, 0, -size.y * 0.5), Vector3(size.x + width, 0.004, width)],
			[Vector3(0, 0, size.y * 0.5), Vector3(size.x + width, 0.004, width)],
			[Vector3(-size.x * 0.5, 0, 0), Vector3(width, 0.004, size.y - width)],
			[Vector3(size.x * 0.5, 0, 0), Vector3(width, 0.004, size.y - width)]]:
		block(parent, spec[1], at + spec[0] + Vector3(0, lift, 0), material, "Tape")


## A riser `size` across and `tall` high, its top `top` and its sides `skirt`.
static func riser(parent: Node3D, size: Vector2, tall: float, top: Material,
		skirt: Material) -> void:
	block(parent, Vector3(size.x, tall - 0.012, size.y), Vector3(0, (tall - 0.012) * 0.5, 0),
			skirt, "Riser")
	block(parent, Vector3(size.x + 0.02, 0.012, size.y + 0.02), Vector3(0, tall - 0.006, 0),
			top, "RiserTop")


## A booth: glass walls in a frame, a lid, and a door gap in the wall facing `door` (+X or -X,
## +Z or -Z as a unit vector along one axis). `size` is the outside; the booth stands on the
## origin.
static func booth(parent: Node3D, size: Vector3, door: Vector3, frame: Material,
		glass: Material) -> void:
	var post := BOOTH_POST
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			# Up to the lid, not through it: a post's face would lie in the lid's edge.
			var under := size.y - 0.08
			block(parent, Vector3(post, under, post), Vector3(cx * (hx - post * 0.5), under * 0.5,
					cz * (hz - post * 0.5)), frame, "Post")
	block(parent, Vector3(size.x, 0.08, size.z), Vector3(0, size.y - 0.04, 0), frame, "Lid")
	# A sill under each pane: glass to the floor reads as a shop window, not a booth.
	var sill := 0.32
	var door_width := BOOTH_DOOR
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along_x := side.x == 0.0
		var span := (size.x if along_x else size.z) - post * 2.0
		var at := Vector3(side.x * (hx - post * 0.5), 0, side.z * (hz - post * 0.5))
		var pane_h := size.y - 0.08 - sill
		var panes: Array = [[0.0, span]]
		if side.is_equal_approx(door):
			# The door is the gap at one end, the pane the rest of the wall.
			var rest := span - door_width
			panes = [[-(span - rest) * 0.5, rest]]
		for pane: Array in panes:
			var shift: Vector3 = (Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)) * pane[0]
			var w: float = pane[1]
			var dims := Vector3(w, sill, post) if along_x else Vector3(post, sill, w)
			block(parent, dims, at + shift + Vector3(0, sill * 0.5, 0), frame, "Sill")
			var glass_dims := Vector3(w, pane_h, 0.012) if along_x else Vector3(0.012, pane_h, w)
			var g := block(parent, glass_dims, at + shift + Vector3(0, sill + pane_h * 0.5, 0), glass,
					"Glass")
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A table: a top `size` (x, thickness, z) at `height`, on four legs `leg` square.
static func table(parent: Node3D, size: Vector3, height: float, leg: float, top: Material,
		legs: Material) -> void:
	block(parent, size, Vector3(0, height - size.y * 0.5, 0), top, "TableTop")
	var under := height - size.y
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			block(parent, Vector3(leg, under, leg), Vector3(cx * (size.x * 0.5 - leg * 1.5),
					under * 0.5, cz * (size.z * 0.5 - leg * 1.5)), legs, "Leg")


## A keyboard stand, empty: two uprights and a deck at playing height, `width` long along Z,
## with an upper tier for a second board set back toward +X (the wall).
static func keyboard_stand(parent: Node3D, width: float, metal: Material, deck: Material) -> void:
	for cz in [-1.0, 1.0]:
		# Standing on its foot, which is a little deeper than it, so no two faces line up.
		block(parent, Vector3(0.05, 0.92, 0.05), Vector3(0.02, 0.04 + 0.46, cz * (width * 0.5 - 0.06)),
				metal, "Upright")
		block(parent, Vector3(0.5, 0.04, 0.07), Vector3(0.0, 0.02, cz * (width * 0.5 - 0.06)),
				metal, "Foot")
	block(parent, Vector3(0.36, 0.025, width), Vector3(-0.04, 0.80, 0), deck, "Deck")
	block(parent, Vector3(0.28, 0.025, width * 0.9), Vector3(0.14, 1.02, 0), deck, "UpperDeck")


## A mic stand with nothing in its clip: a round base, a pole, a boom reaching toward -Z.
static func mic_stand(parent: Node3D, at: Vector3, metal: Material) -> void:
	var stand := Node3D.new()
	stand.name = "MicStand"
	stand.position = at
	parent.add_child(stand)
	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.14
	disc.bottom_radius = 0.15
	disc.height = 0.03
	base.mesh = disc
	base.position.y = 0.015
	base.material_override = metal
	stand.add_child(base)
	var pole := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.011
	rod.bottom_radius = 0.013
	rod.height = 1.45
	pole.mesh = rod
	pole.position.y = 0.75
	pole.material_override = metal
	stand.add_child(pole)
	var boom := MeshInstance3D.new()
	var arm := CylinderMesh.new()
	arm.top_radius = 0.009
	arm.bottom_radius = 0.009
	arm.height = 0.7
	boom.mesh = arm
	# Up and out at forty degrees from just below the top of the pole, toward the singer.
	var tilt := deg_to_rad(-50.0)
	boom.rotation = Vector3(tilt, 0, 0)
	boom.position = Vector3(0, 1.40, 0) + Vector3(0, cos(tilt), sin(tilt)) * arm.height * 0.5
	boom.material_override = metal
	stand.add_child(boom)


## A light that belongs to a zone: soft, shadowless (they would cost a shadow map apiece and the
## room's fittings already throw the shadows that matter), and short-ranged so it stays where
## it is.
##
## A light in a room is at a place and needs something AT that place, so `fitting` -- when
## given -- is the can it shines out of: a short cylinder above `at` with a lit lens under it.
static func spot_down(parent: Node3D, at: Vector3, colour: Color, energy: float,
		angle: float, reach: float, fitting: Material = null) -> SpotLight3D:
	if fitting != null:
		var can := MeshInstance3D.new()
		can.name = "ZoneFitting"
		var body := CylinderMesh.new()
		body.top_radius = 0.06
		body.bottom_radius = 0.06
		body.height = 0.045
		body.radial_segments = 20
		can.mesh = body
		can.position = at + Vector3(0, 0.0225, 0)
		can.material_override = fitting
		parent.add_child(can)
		var lens := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.042
		disc.bottom_radius = 0.042
		disc.height = 0.004
		disc.radial_segments = 20
		lens.mesh = disc
		# Hanging a millimetre below the can, so its face is not in the can's.
		lens.position = Vector3(0, -0.0245, 0)
		lens.material_override = glow(colour, 1.8)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		can.add_child(lens)
	var spot := SpotLight3D.new()
	spot.name = "ZoneLight"
	spot.position = at
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = colour
	spot.light_energy = energy
	spot.spot_angle = angle
	spot.spot_range = reach
	spot.spot_angle_attenuation = 1.2
	spot.shadow_enabled = false
	# Mostly diffuse: straight down onto oiled parquet a spot's own highlight is a white disc
	# that follows you round the room, which is glare, not a pool of light.
	spot.light_specular = 0.04
	spot.light_size = 0.25
	parent.add_child(spot)
	return spot


static func glow(colour: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour * strength
	return m
