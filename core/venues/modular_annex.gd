class_name ModularAnnex
extends Node3D

## The modular room: a room of its own, built onto the right-hand side of the live room in every
## venue, with an open doorway cut through the live room's wall to walk in by. Inside, the rack hangs
## on the far wall with its keys below it, the room is dressed in lights that follow what the rack
## plays (a ceiling of tiles, columns up the side walls, an inlaid floor, a light over the doorway)
## in the venue's mood (RackMood), and the doorway shows its glow into the live room.
##
## It is the venue's child: built with it, gone with it. Where the venue has a wall at the doorway
## the wall is cut (`cut_the_wall`: its box pieces split round the opening); where it is open ground
## the room simply stands there. Everything here is in studio space, like the zones.

## The room inside: this far from the live room's wall to its far wall, and across (z).
const DEEP := 8.0
const Z_FROM := 6.0
const Z_TO := 13.0
const HEIGHT := 3.4
const WALL := 0.2
## The outer face of the room's near wall stands this far outside the live room's wall.
const GAP := 0.63
## The doorway, through the live room's wall and the room's: its middle along z, how wide and high.
const DOOR_Z := 9.0
const DOOR_WIDE := 1.9
const DOOR_HIGH := 2.35
## The floor, a little proud of the ground so no venue's ground is in its plane.
const FLOOR_TOP := 0.02
## Where the rack hangs along z, and the case's own height over the floor (RackWall on its legs).
const RACK_Z := 9.6
const COLUMNS := 14
const TILES := Vector2i(5, 3)

var half := 8.8
var mood := RackMood.FALLBACK
var _tile_material := StandardMaterial3D.new()
var _line_material := StandardMaterial3D.new()
var _sign_material := StandardMaterial3D.new()
var _columns: Array[MeshInstance3D] = []
var _column_level: Array[float] = []
var _lights: Array[OmniLight3D] = []
var _level := 0.0
var _hit := 0.0


## The room's near wall's centre along x, for a live room `half` wide.
static func near_x(half_width: float) -> float:
	return half_width + GAP + WALL * 0.5


## The room's inside, x from the near wall's inner face to the far wall's inner face, z from
## Z_FROM to Z_TO.
static func inside(half_width: float) -> Rect2:
	var x0 := near_x(half_width) + WALL * 0.5
	return Rect2(x0, Z_FROM, DEEP, Z_TO - Z_FROM)


## What a person can walk: the room, and the passage through the two walls that joins it to the live
## room (overlapping both, which the walker reads as floor on either side).
static func floors(half_width: float) -> Array[Rect2]:
	var in_room := inside(half_width)
	var passage := Rect2(half_width - 0.6, DOOR_Z - DOOR_WIDE * 0.5 + 0.05, GAP + WALL + 0.9, DOOR_WIDE - 0.1)
	return [in_room, passage]


## Where the rack hangs: on the far wall, facing back across the room (its front -X).
static func rack_spot(half_width: float) -> Transform3D:
	var far := inside(half_width).end.x
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(far - 0.14, 1.26, RACK_Z))


static func build(venue: Venue) -> ModularAnnex:
	var out := ModularAnnex.new()
	out.name = "ModularAnnex"
	out.half = venue.live_room_half()
	out.mood = RackMood.palette(venue.venue_id())
	venue.add_child(out)
	return out


func _ready() -> void:
	var room := inside(half)
	var x0 := room.position.x
	var x1 := room.end.x
	var zc := (Z_FROM + Z_TO) * 0.5
	var floor_paint := _paint(Color(0.09, 0.09, 0.1), 0.3, 0.2)
	var wall_paint := _paint(Color(0.16, 0.16, 0.18), 0.85, 0.0)
	var slat_paint := _paint(Color(0.12, 0.085, 0.06), 0.7, 0.0)
	var metal := _paint(Color(0.3, 0.3, 0.32), 0.35, 0.9)
	for m in [_tile_material, _line_material, _sign_material]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply_mood()

	# Floor, ceiling and the four walls; the near wall is open at the doorway.
	ZoneKit.block(self, Vector3(DEEP + 0.9 + GAP, 0.27, Z_TO - Z_FROM + 0.7),
			Vector3(x1 + 0.45 - (DEEP + 0.9 + GAP) * 0.5, FLOOR_TOP - 0.135, zc), floor_paint, "AnnexFloor")
	ZoneKit.block(self, Vector3(DEEP + 0.7, WALL + 0.06, Z_TO - Z_FROM + 0.8),
			Vector3((x0 + x1) * 0.5 + 0.1, HEIGHT + WALL * 0.5 + 0.03, zc), wall_paint, "AnnexCeiling")
	ZoneKit.block(self, Vector3(WALL + 0.04, HEIGHT + 0.02, Z_TO - Z_FROM + 0.5),
			Vector3(x1 + WALL * 0.5 + 0.02, HEIGHT * 0.5 + 0.01, zc), wall_paint, "AnnexFarWall")
	for z in [Z_FROM - WALL * 0.5, Z_TO + WALL * 0.5]:
		ZoneKit.block(self, Vector3(DEEP + 0.05, HEIGHT + 0.01, WALL + 0.02), Vector3((x0 + x1) * 0.5 - 0.1, HEIGHT * 0.5 - 0.025, z),
				wall_paint, "AnnexSideWall%d" % int(z))
	var near := near_x(half)
	var door_lo := DOOR_Z - DOOR_WIDE * 0.5
	var door_hi := DOOR_Z + DOOR_WIDE * 0.5
	ZoneKit.block(self, Vector3(WALL - 0.03, HEIGHT - 0.01, door_lo - Z_FROM + 0.1), Vector3(near, HEIGHT * 0.5 - 0.055, (Z_FROM - 0.1 + door_lo) * 0.5),
			wall_paint, "AnnexNearWallA")
	ZoneKit.block(self, Vector3(WALL - 0.03, HEIGHT - 0.01, Z_TO + 0.1 - door_hi), Vector3(near, HEIGHT * 0.5 - 0.055, (door_hi + Z_TO + 0.1) * 0.5),
			wall_paint, "AnnexNearWallB")
	ZoneKit.block(self, Vector3(WALL - 0.05, HEIGHT - 0.08 - DOOR_HIGH, DOOR_WIDE + 0.04), Vector3(near, (HEIGHT - 0.08 + DOOR_HIGH) * 0.5, DOOR_Z),
			wall_paint, "AnnexLintel")
	# The doorway's frame, and a sign over it on the live room's side.
	for z in [door_lo - 0.06, door_hi + 0.06]:
		ZoneKit.block(self, Vector3(GAP + WALL + 0.12, DOOR_HIGH - 0.02, 0.1), Vector3(half + (GAP + WALL) * 0.5 - 0.06, DOOR_HIGH * 0.5, z),
				metal, "DoorPost%d" % int(z * 10.0))
	ZoneKit.block(self, Vector3(GAP + WALL + 0.15, 0.093, DOOR_WIDE + 0.213), Vector3(half + (GAP + WALL) * 0.5 - 0.07, DOOR_HIGH + 0.035, DOOR_Z),
			metal, "DoorHead")
	ZoneKit.block(self, Vector3(0.03, 0.05, DOOR_WIDE), Vector3(half - 0.13, DOOR_HIGH + 0.2, DOOR_Z), null, "DoorLight")
	(get_node("DoorLight") as MeshInstance3D).material_override = _sign_material
	var title := Label3D.new()
	title.name = "DoorSign"
	title.text = "MODULAR"
	title.font_size = 64
	title.pixel_size = 0.0035
	title.modulate = Color(1, 1, 1)
	title.shaded = false
	title.rotation_degrees = Vector3(0, -90, 0)
	title.position = Vector3(half - 0.08, DOOR_HIGH + 0.38, DOOR_Z)
	add_child(title)

	# Acoustic slats on the side walls and a lit line along them, a ceiling of tiles, an inlaid floor.
	for z in [Z_FROM + 0.04, Z_TO - 0.04]:
		for n in 24:
			var slat_x := x0 + 0.35 + float(n) * (DEEP - 0.7) / 23.0
			ZoneKit.block(self, Vector3(0.1, 2.2, 0.06), Vector3(slat_x, 1.3, z), slat_paint, "Slat%d_%d" % [int(z), n])
		ZoneKit.block(self, Vector3(DEEP - 0.4, 0.03, 0.03), Vector3((x0 + x1) * 0.5, 2.5, z * 1.0 + (0.02 if z < zc else -0.02)),
				null, "SideLine%d" % int(z)).material_override = _line_material
	for ix in TILES.x:
		for iz in TILES.y:
			var tile_x := x0 + (float(ix) + 0.5) * DEEP / TILES.x
			var tile_z := Z_FROM + (float(iz) + 0.5) * (Z_TO - Z_FROM) / TILES.y
			var tile := ZoneKit.block(self, Vector3(DEEP / TILES.x - 0.3, 0.03, (Z_TO - Z_FROM) / TILES.y - 0.3),
					Vector3(tile_x, HEIGHT - 0.02, tile_z), null, "Tile_%d_%d" % [ix, iz])
			tile.material_override = _tile_material
	for n in 5:
		var line_x := x0 + (float(n) + 0.5) * DEEP / 5.0
		ZoneKit.block(self, Vector3(0.025, 0.006, Z_TO - Z_FROM - 0.2), Vector3(line_x, FLOOR_TOP + 0.003, zc), null,
				"FloorLine%d" % n).material_override = _line_material
	var out_x := x0 + 0.4
	ZoneKit.block(self, Vector3(DEEP - 0.5, 0.016, 0.025), Vector3((x0 + x1) * 0.5, FLOOR_TOP, DOOR_Z), null,
			"FloorWay").material_override = _line_material

	# Columns against the far wall's sides, each as tall as a module is loud (RackWall's pillars follow
	# the same meters out on the floor): a skyline of the patch.
	for n in COLUMNS:
		var side := -1.0 if n < COLUMNS / 2 else 1.0
		var k := float(n % (COLUMNS / 2))
		var col := MeshInstance3D.new()
		col.name = "Column%d" % n
		var b := BoxMesh.new()
		b.size = Vector3(0.12, 1.0, 0.12)
		col.mesh = b
		col.material_override = _emissive_copy()
		col.position = Vector3(x1 - 0.22, 0.0, zc + side * (1.6 + k * 0.5))
		add_child(col)
		_columns.append(col)
		_column_level.append(0.0)
		_grow_column(n, 0.0)

	# The room's lights: two soft washes high in the room, in the mood.
	for z in [Z_FROM + 1.2, (Z_FROM + Z_TO) * 0.5, Z_TO - 1.2]:
		var lamp := OmniLight3D.new()
		lamp.name = "AnnexWash%d" % int(z * 10.0)
		lamp.position = Vector3((x0 + x1) * 0.5, HEIGHT - 0.6, z)
		lamp.omni_range = 9.0
		lamp.omni_attenuation = 1.4
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		lamp.add_to_group(&"presentation_chrome")
		add_child(lamp)
		_lights.append(lamp)
	_shine()


## What the rack plays, as the room's light: its loudness 0..1 and the hit pulse.
func glow_with(level: float, hit: float) -> void:
	_level = level
	_hit = maxf(_hit * 0.9, hit)
	_shine()


## How loud each module is now, in the order they are across the case (RackWall's pillars): a skyline.
func show_levels(levels: Array) -> void:
	for n in _columns.size():
		var want := clampf(float(levels[n % levels.size()]) if not levels.is_empty() else 0.0, 0.0, 1.0)
		var now := _column_level[n]
		_grow_column(n, lerpf(now, want, 0.5 if want > now else 0.15))


func set_mood(m: Dictionary) -> void:
	mood = m
	_apply_mood()
	_shine()


func _apply_mood() -> void:
	_sign_material.albedo_color = mood["base"]
	_line_material.albedo_color = (mood["base"] as Color) * 0.8
	for col in _columns:
		var m := col.material_override as StandardMaterial3D
		m.albedo_color = mood["base"]


func _shine() -> void:
	var base: Color = mood["base"]
	var flash: Color = mood["hit"]
	var live := clampf(_level * 1.5 + _hit, 0.0, 1.5)
	var colour := base.lerp(flash, clampf(_hit, 0.0, 1.0))
	_tile_material.albedo_color = colour * (0.55 + live * 1.4)
	_line_material.albedo_color = colour * (0.4 + live * 1.2)
	_sign_material.albedo_color = colour * (0.8 + live)
	for lamp in _lights:
		lamp.light_color = colour
		lamp.light_energy = float(mood["glow"]) * (1.1 + _level * 2.0 + _hit * 1.2)


func _grow_column(n: int, level: float) -> void:
	var h := 0.25 + clampf(level, 0.0, 1.0) * 2.2
	_column_level[n] = level
	_columns[n].scale = Vector3(1, h, 1)
	_columns[n].position.y = FLOOR_TOP + h * 0.5


func _emissive_copy() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = mood["base"]
	return m


func _paint(colour: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m


## Cut the doorway through whatever wall the venue stands at the live room's right-hand side: each
## box piece that crosses the opening is hidden and put back as the pieces round it (either side, and
## the lintel over it). Venues with no wall there are untouched.
static func cut_the_wall(venue: Venue) -> int:
	var h := venue.live_room_half()
	var lo := DOOR_Z - DOOR_WIDE * 0.5
	var hi := DOOR_Z + DOOR_WIDE * 0.5
	var cut := 0
	for node in venue.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.get_parent() == null or not mi.visible or mi.name.begins_with("Annex"):
			continue
		var box := mi.mesh as BoxMesh
		if box == null or not mi.global_transform.basis.is_equal_approx(Basis.IDENTITY):
			continue
		var c := venue.to_local(mi.global_position)
		var s := box.size
		# A wall: tall and thin along x, standing across the doorway at the live room's side.
		if s.y < 2.0 or s.x > 1.4 or s.z < DOOR_WIDE:
			continue
		if absf(c.x - h) > 0.7 or c.z - s.z * 0.5 > lo or c.z + s.z * 0.5 < hi or c.y - s.y * 0.5 > 1.0:
			continue
		var parent := mi.get_parent() as Node3D
		var top := c.y + s.y * 0.5
		var bottom := c.y - s.y * 0.5
		var z0 := c.z - s.z * 0.5
		var z1 := c.z + s.z * 0.5
		# Pieces as [z from, z to, y from, y to] in the venue's frame: the wall either side, the lintel.
		var pieces := [[z0, lo, bottom, top], [hi, z1, bottom, top], [lo, hi, maxf(bottom, DOOR_HIGH), top]]
		mi.visible = false
		var index := 0
		for p in pieces:
			if p[1] - p[0] < 0.02 or p[3] - p[2] < 0.02:
				continue
			var part := MeshInstance3D.new()
			part.name = "%s_cut%d" % [mi.name, index]
			var bm := BoxMesh.new()
			bm.size = Vector3(s.x, p[3] - p[2], p[1] - p[0])
			part.mesh = bm
			part.material_override = mi.material_override if mi.material_override != null else mi.get_active_material(0)
			parent.add_child(part)
			part.position = parent.to_local(venue.to_global(Vector3(c.x, (p[2] + p[3]) * 0.5, (p[0] + p[1]) * 0.5)))
			index += 1
		cut += 1
	return cut
