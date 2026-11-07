class_name ModularAnnex
extends Node3D

## The modular room: a room of its own, built onto the right-hand side of the live room in every
## venue, with an open doorway cut through the live room's wall to walk in by. Inside, the rack hangs
## on the far wall with its keys below it, the room is dressed in lights that follow what the rack
## plays (a ceiling of tiles, columns up the side walls, an inlaid floor, a light over the doorway)
## in the venue's mood (RackMood), and the doorway shows its glow into the live room.
##
## It is the venue's child: built with it, gone with it. Where the venue has a wall at the doorway
## the wall is cut (`AnnexSite.cut_the_wall`: its box pieces split round the opening); where it is open ground
## the room simply stands there. Everything here is in studio space, like the zones.

## The room inside: this far from the live room's wall to its far wall, and across (z).
const DEEP := 8.0
const Z_FROM := 6.0
const Z_TO := 13.0
const HEIGHT := 4.4
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
const RACK_Z := 9.2
## The rack is hung large, a wall of it (RackWall is 1.8 m of case at 1:1).
const RACK_SCALE := 1.2
const RACK_Y := 1.0
const COLUMNS := 14
const GANTRY_Y := 1.85
const GANTRY_DEEP := 1.3
const TRUSS_Y := 4.0
const TILES := Vector2i(5, 3)

var half := 8.8
var mood := RackMood.FALLBACK
var _tile_material := StandardMaterial3D.new()
var _line_material := StandardMaterial3D.new()
## The TV on the side wall: the wave at the first SCOPE patched in.
var tv: ScopeScreen
## The CV bench's fifteen controls (two knobs and a slider in each of five boxes), in the order of the
## rack's HAND module outputs, and what a hand does to one: (index, 0..1).
var bench: Array[Knob] = []
## A knob of the CV bench was turned: index `k` (0 to 14) and value `v` in 0..1.
signal bench_turned(k: int, v: float)
var _sign_material := StandardMaterial3D.new()
var _columns: Array[MeshInstance3D] = []
## Bars hung from the ceiling truss, each as long as a module is loud (the skyline, seen from above).
var _hangs: Array[MeshInstance3D] = []
var _hang_level: Array[float] = []
var _column_level: Array[float] = []
var _lights: Array[OmniLight3D] = []
var _was_under := false
var _shone_level := 0.0
var _shone_hit := 0.0
var _level := 0.0
var _hit := 0.0
## The venue's weather (rain, snow, dust) put out while the eye is under this roof.
var _hushed: Array[GPUParticles3D] = []


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
static func floors(half_width: float, live_half := -1.0) -> Array[Rect2]:
	var in_room := inside(half_width)
	var from := (half_width if live_half < 0.0 else live_half) - 0.6
	var passage := Rect2(from, DOOR_Z - DOOR_WIDE * 0.5 + 0.05, half_width + GAP + WALL + 0.9 - from, DOOR_WIDE - 0.1)
	return [in_room, passage]


## Where the rack hangs: on the far wall, facing back across the room (its front -X).
static func rack_spot(half_width: float) -> Transform3D:
	var far := inside(half_width).end.x
	return Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * RACK_SCALE), Vector3(far - 0.14, RACK_Y, RACK_Z))


static func build(venue: Venue) -> ModularAnnex:
	var out := ModularAnnex.new()
	out.name = "ModularAnnex"
	out.half = venue.annex_edge()
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
	ZoneKit.block(self, Vector3(DEEP + 0.7, WALL + 0.075, Z_TO - Z_FROM + 0.8),
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
		col.position = Vector3(x1 - 0.22, 0.0, zc + side * (2.4 + k * 0.14))
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
	# Dressing: a bench along one wall, road cases stacked along the other, a cable tray over the room
	# with the rack's leads dropping from it. Kept to the walls and the ceiling, out of the walk.
	var case_paint := _paint(Color(0.07, 0.07, 0.08), 0.6, 0.15)
	var wood := _paint(Color(0.2, 0.14, 0.09), 0.75, 0.0)
	ZoneKit.block(self, Vector3(1.83, 0.06, 0.41), Vector3(x1 - 3.7, 0.47, Z_TO - 0.46), wood, "AnnexBenchTop")
	for dx in [-0.78, 0.78]:
		ZoneKit.block(self, Vector3(0.07, 0.44, 0.33), Vector3(x1 - 3.7 + dx, 0.24, Z_TO - 0.46), metal, "AnnexBenchLeg%d" % int(dx * 10.0))
	var stack := [[Vector3(0.93, 0.57, 0.57), 0.0, 0.0], [Vector3(0.93, 0.53, 0.55), 1.05, 0.0], [Vector3(0.71, 0.47, 0.52), 0.1, 0.59]]
	for n in stack.size():
		var size: Vector3 = stack[n][0]
		var cx := x0 + 4.4 + float(stack[n][1])
		var cy := size.y * 0.5 + 0.02 + float(stack[n][2])
		ZoneKit.block(self, size, Vector3(cx, cy, Z_FROM + 0.47), case_paint, "AnnexCase%d" % n)
		for dz in [-1.0, 1.0]:
			ZoneKit.block(self, Vector3(size.x + 0.03, 0.035, 0.03), Vector3(cx, cy + size.y * 0.5 - 0.1, Z_FROM + 0.47 + dz * (size.z * 0.5 + 0.004)), metal, "AnnexCaseEdge%d_%d" % [n, int(dz)])
	ZoneKit.block(self, Vector3(DEEP - 0.9, 0.05, 0.27), Vector3((x0 + x1) * 0.5 - 0.05, HEIGHT - 0.23, DOOR_Z), metal, "AnnexTray")
	for k in 3:
		var lead_z := DOOR_Z - 0.09 + float(k) * 0.09
		ZoneKit.block(self, Vector3(DEEP - 0.95, 0.025, 0.02), Vector3((x0 + x1) * 0.5 - 0.06, HEIGHT - 0.19, lead_z), case_paint, "AnnexLead%d" % k)
		ZoneKit.block(self, Vector3(0.022, 1.12 + float(k) * 0.07, 0.024), Vector3(x1 - 0.3 - float(k) * 0.045, HEIGHT - 0.2 - (1.12 + float(k) * 0.07) * 0.5, lead_z), case_paint, "AnnexDrop%d" % k)
	_furnish(room, metal, case_paint, wood)
	_shine()


## What the rack plays, as the room's light: its loudness 0..1 and the hit pulse.
func glow_with(level: float, hit: float) -> void:
	# Eased, so the room breathes with the music rather than flashing on every beat.
	_level = lerpf(_level, level, 0.06)
	_hit = lerpf(_hit, hit, 0.05)
	if absf(_level - _shone_level) + absf(_hit - _shone_hit) > 0.01:
		_shone_level = _level
		_shone_hit = _hit
		_shine()


## How loud each module is now, in the order they are across the case (RackWall's pillars): a skyline.
func show_levels(levels: Array) -> void:
	for n in _columns.size():
		var want := clampf(float(levels[n % levels.size()]) if not levels.is_empty() else 0.0, 0.0, 1.0)
		var now := _column_level[n]
		_grow_column(n, lerpf(now, want, 0.5 if want > now else 0.15))
	for n in _hangs.size():
		var want := clampf(float(levels[(n * 3 + 1) % levels.size()]) if not levels.is_empty() else 0.0, 0.0, 1.0)
		var now := _hang_level[n]
		_drop_bar(n, lerpf(now, want, 0.5 if want > now else 0.15))


## Under this roof there is no weather: the venue's particles (rain, snow, drifting dust) are put out
## while the eye is inside the room, and come back when it leaves.
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var local := to_local(cam.global_position)
	var room := inside(half)
	var under := room.has_point(Vector2(local.x, local.z)) and local.y < HEIGHT
	# Only on the way in or out: searching every node of the venue for particles is not a thing to
	# do each frame.
	if under == _was_under:
		return
	_was_under = under
	if under:
		for node in get_parent().find_children("*", "GPUParticles3D", true, false):
			var p := node as GPUParticles3D
			if p.visible and not is_ancestor_of(p):
				p.visible = false
				_hushed.append(p)
	elif not under and not _hushed.is_empty():
		for p in _hushed:
			if is_instance_valid(p):
				p.visible = true
		_hushed.clear()


func _exit_tree() -> void:
	for p in _hushed:
		if is_instance_valid(p):
			p.visible = true
	_hushed.clear()


## Take a new mood (the glow dictionary, see `RackMood`) and repaint the room with it.
func set_mood(m: Dictionary) -> void:
	mood = m
	_apply_mood()
	_shine()


## The TV shows the wave of the SCOPE module that is showing the most (ties by id), or a flat line.
func show_scope(waves: Dictionary) -> void:
	if tv == null:
		return
	var ids := waves.keys()
	ids.sort()
	var best := PackedFloat32Array()
	var best_peak := -1.0
	for id in ids:
		var peak := 0.0
		for v in (waves[id] as PackedFloat32Array):
			peak = maxf(peak, absf(v))
		if peak > best_peak + 0.02:
			best = waves[id]
			best_peak = peak
	tv.set_wave(best)


func _build_tv(x0: float, metal: Material) -> void:
	tv = ScopeScreen.new()
	tv.size = Vector2(2.8, 1.5)
	tv.name = "ScopeTV"
	tv.position = Vector3(x0 + DEEP * 0.5, 2.55, Z_TO - 0.1)
	tv.basis = Basis(Vector3.UP, PI)
	tv.tint = (mood["base"] as Color).lerp(Color(0.3, 1.0, 0.65), 0.7)
	add_child(tv)
	ZoneKit.block(self, Vector3(3.1, 1.75, 0.1), Vector3(x0 + DEEP * 0.5, 2.55, Z_TO - 0.04), metal, "TvBack")
	ZoneKit.block(self, Vector3(0.1, 0.1, 0.1), Vector3(x0 + DEEP * 0.5, 3.45, Z_TO - 0.05), metal, "TvMount")
	ZoneKit.block(self, Vector3(1.2, 0.04, 0.3), Vector3(x0 + DEEP * 0.5, 1.65, Z_TO - 0.2), metal, "TvShelf")


func _apply_mood() -> void:
	if tv != null:
		tv.tint = (mood["base"] as Color).lerp(Color(0.3, 1.0, 0.65), 0.7)
	_sign_material.albedo_color = mood["base"]
	_line_material.albedo_color = (mood["base"] as Color) * 0.8
	for col in _columns + _hangs:
		var m := col.material_override as StandardMaterial3D
		m.albedo_color = mood["base"]


func _shine() -> void:
	var base: Color = mood["base"]
	var flash: Color = mood["hit"]
	var live := clampf(_level * 0.8 + _hit * 0.3, 0.0, 1.0)
	var colour := base.lerp(flash, clampf(_hit * 0.35, 0.0, 1.0))
	_tile_material.albedo_color = colour * (0.6 + live * 0.6)
	_line_material.albedo_color = colour * (0.45 + live * 0.5)
	_sign_material.albedo_color = colour * (0.85 + live * 0.4)
	for lamp in _lights:
		lamp.light_color = colour
		lamp.light_energy = float(mood["glow"]) * (0.7 + _level * 0.35 + _hit * 0.1)


func _grow_column(n: int, level: float) -> void:
	var h := 0.25 + clampf(level, 0.0, 1.0) * 2.2
	_column_level[n] = level
	_columns[n].scale = Vector3(1, h, 1)
	_columns[n].position.y = FLOOR_TOP + h * 0.5


func _drop_bar(n: int, level: float) -> void:
	var h := 0.2 + clampf(level, 0.0, 1.0) * 0.9
	_hang_level[n] = level
	_hangs[n].scale = Vector3(1, h, 1)
	_hangs[n].position.y = TRUSS_Y - 0.06 - h * 0.5


## The room's volume, not only its walls: a gantry along one side (stairs up to it, a rail, a library
## of cases on it), a truss across the ceiling hung with bars that fall as the rack gets loud, free
## standing towers of gear, monitors on stands at ear height by the playing spot, a rug, and cables
## swagged from the truss to the towers and the rack.
func _furnish(room: Rect2, metal: Material, case_paint: Material, wood: Material) -> void:
	var x0 := room.position.x
	var x1 := room.end.x
	var zc := (Z_FROM + Z_TO) * 0.5
	var deck := _paint(Color(0.14, 0.14, 0.16), 0.5, 0.5)
	# The gantry: deck, joists, posts at the open edge, a rail with a lit line, stairs up at the near end.
	var gx0 := x0 + 2.7
	var gx1 := x1 - 1.4
	var gz := Z_FROM + GANTRY_DEEP * 0.5
	ZoneKit.block(self, Vector3(gx1 - gx0, 0.09, GANTRY_DEEP), Vector3((gx0 + gx1) * 0.5, GANTRY_Y, gz), deck, "GantryDeck")
	ZoneKit.block(self, Vector3(gx1 - gx0 - 0.06, 0.2, 0.06), Vector3((gx0 + gx1) * 0.5, GANTRY_Y - 0.14, Z_FROM + GANTRY_DEEP - 0.06), metal, "GantryBeam")
	var rail_z := Z_FROM + GANTRY_DEEP - 0.04
	ZoneKit.block(self, Vector3(gx1 - gx0, 0.04, 0.04), Vector3((gx0 + gx1) * 0.5, GANTRY_Y + 1.0, rail_z), metal, "GantryRail")
	ZoneKit.block(self, Vector3(gx1 - gx0, 0.02, 0.02), Vector3((gx0 + gx1) * 0.5, GANTRY_Y + 0.55, rail_z), null, "GantryLine").material_override = _line_material
	var posts := 7
	for n in posts:
		var px := gx0 + 0.05 + float(n) * (gx1 - gx0 - 0.1) / float(posts - 1)
		ZoneKit.block(self, Vector3(0.05, GANTRY_Y + 1.0, 0.05), Vector3(px, (GANTRY_Y + 1.0) * 0.5, rail_z), metal, "GantryPost%d" % n)
	var steps := 9
	var rise := GANTRY_Y / float(steps)
	var run := (gx0 - (x0 + 0.5)) / float(steps)
	for n in steps:
		var top := rise * float(n + 1)
		ZoneKit.block(self, Vector3(run + 0.02, 0.05, GANTRY_DEEP - 0.25), Vector3(x0 + 0.5 + run * (float(n) + 0.5), top - 0.025, Z_FROM + (GANTRY_DEEP - 0.25) * 0.5 + 0.05), deck, "Stair%d" % n)
	for edge in [Z_FROM + 0.03, Z_FROM + GANTRY_DEEP - 0.22]:
		var slope := Vector3(gx0 - (x0 + 0.5), GANTRY_Y, 0.0)
		var bar := ZoneKit.block(self, Vector3(slope.length(), 0.04, 0.04), Vector3((gx0 + x0 + 0.5) * 0.5, GANTRY_Y * 0.5 + 0.9, edge), metal, "StairRail%d" % int(edge * 10.0))
		bar.rotation.z = atan2(slope.y, slope.x)
	# A library of cases on the gantry, with rows of lights.
	for n in 4:
		var cx := gx0 + 0.7 + float(n) * 1.05
		ZoneKit.block(self, Vector3(0.85, 0.34, 0.5), Vector3(cx, GANTRY_Y + 0.215, Z_FROM + 0.4), case_paint, "GantryCase%d" % n)
		for row in 3:
			ZoneKit.block(self, Vector3(0.7, 0.012, 0.012), Vector3(cx, GANTRY_Y + 0.12 + float(row) * 0.09, Z_FROM + 0.649), null, "GantryCaseLed%d_%d" % [n, row]).material_override = _sign_material
	# The truss: two bars along the room and cross-members, with bars hung that fall with the rack's loudness.
	for dz in [-2.0, 2.0]:
		ZoneKit.block(self, Vector3(DEEP - 0.8, 0.07, 0.07), Vector3((x0 + x1) * 0.5, TRUSS_Y, zc + dz), metal, "TrussBar%d" % int(dz * 10.0))
	for n in 7:
		var tx := x0 + 0.5 + float(n) * (DEEP - 1.0) / 6.0
		ZoneKit.block(self, Vector3(0.05, 0.05, 4.0), Vector3(tx, TRUSS_Y, zc), metal, "TrussCross%d" % n)
	for n in 12:
		var bar := MeshInstance3D.new()
		bar.name = "Hang%d" % n
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 1.0, 0.08)
		bar.mesh = bm
		bar.material_override = _emissive_copy()
		bar.position = Vector3(x0 + 0.9 + float(n / 2) * 0.95, TRUSS_Y, zc + (-2.0 if n % 2 == 0 else 2.0))
		add_child(bar)
		_hangs.append(bar)
		_hang_level.append(0.0)
		_drop_bar(n, 0.0)
	# Two free-standing towers of gear, with their lights, by the door side of the bench wall.
	for t in 2:
		var tx := x0 + 0.9 + float(t) * 0.85
		var tz := Z_TO - 0.5
		ZoneKit.block(self, Vector3(0.6, 1.95, 0.5), Vector3(tx, FLOOR_TOP + 0.975, tz), case_paint, "Tower%d" % t)
		ZoneKit.block(self, Vector3(0.66, 0.05, 0.56), Vector3(tx, FLOOR_TOP + 1.97, tz), metal, "TowerCap%d" % t)
		for row in 8:
			var ry := FLOOR_TOP + 0.3 + float(row) * 0.21
			ZoneKit.block(self, Vector3(0.52, 0.12, 0.012), Vector3(tx, ry, tz - 0.254), metal, "TowerUnit%d_%d" % [t, row])
			ZoneKit.block(self, Vector3(0.36, 0.01, 0.012), Vector3(tx - 0.05, ry + 0.03, tz - 0.262), null, "TowerLed%d_%d" % [t, row]).material_override = _sign_material
	# Monitors on stands at ear height, either side of the playing spot, and a rug between them.
	var spot_x := x1 - 1.5
	for dz in [-2.9, 2.9]:
		var sz: float = zc + dz
		ZoneKit.block(self, Vector3(0.04, 1.15, 0.04), Vector3(spot_x, FLOOR_TOP + 0.575, sz), metal, "MonitorStand%d" % int(dz * 10.0))
		ZoneKit.block(self, Vector3(0.3, 0.025, 0.3), Vector3(spot_x, FLOOR_TOP + 0.015, sz), metal, "MonitorFoot%d" % int(dz * 10.0))
		ZoneKit.block(self, Vector3(0.26, 0.42, 0.28), Vector3(spot_x, FLOOR_TOP + 1.36, sz), case_paint, "Monitor%d" % int(dz * 10.0))
		var cone := MeshInstance3D.new()
		cone.name = "MonitorCone%d" % int(dz * 10.0)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 0.01
		cone.mesh = cm
		cone.material_override = metal
		cone.rotation.z = PI * 0.5
		cone.position = Vector3(spot_x - 0.141, FLOOR_TOP + 1.3, sz)
		add_child(cone)
	ZoneKit.block(self, Vector3(1.8, 0.012, 2.8), Vector3(spot_x - 0.2, FLOOR_TOP + 0.007, zc), _paint(Color(0.05, 0.05, 0.06), 0.95, 0.0), "Rug")
	for dz in [-1.4, 1.4]:
		ZoneKit.block(self, Vector3(1.76, 0.014, 0.03), Vector3(spot_x - 0.2, FLOOR_TOP + 0.0095, zc + dz * 0.96), null, "RugEdge%d" % int(dz * 10.0)).material_override = _line_material
	# The module library and the CV bench are not built for now (_shelves): not wanted in the room.
	_build_tv(x0, metal)
	# Cables swagged overhead: from the truss down to the towers and the monitors, and along it to the rack.
	var swags := [
		[Vector3(x0 + 1.0, TRUSS_Y, zc + 2.0), Vector3(x0 + 0.9, 2.0, Z_TO - 0.5), 0.5],
		[Vector3(x0 + 1.9, TRUSS_Y, zc + 2.0), Vector3(x0 + 1.75, 2.0, Z_TO - 0.5), 0.45],
		[Vector3(x0 + 3.2, TRUSS_Y, zc - 2.0), Vector3(spot_x, 1.6, zc - 2.9), 0.6],
		[Vector3(x0 + 4.4, TRUSS_Y, zc + 2.0), Vector3(spot_x, 1.6, zc + 2.9), 0.6],
		[Vector3(x1 - 2.4, TRUSS_Y, zc - 2.0), Vector3(x1 - 0.12, 3.5, zc - 3.0), 0.35],
		[Vector3(x1 - 2.4, TRUSS_Y, zc + 2.0), Vector3(x1 - 0.12, 3.5, zc + 3.0), 0.35],
		[Vector3(x0 + 2.2, TRUSS_Y, zc - 2.0), Vector3(gx0 + 1.0, GANTRY_Y + 0.6, Z_FROM + GANTRY_DEEP - 0.04), 0.5],
	]
	var cable := MultiMeshInstance3D.new()
	cable.name = "Swags"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var seg := BoxMesh.new()
	seg.size = Vector3(0.02, 0.02, 1.0)
	mm.mesh = seg
	var per := 10
	mm.instance_count = swags.size() * per
	var idx := 0
	for sw in swags:
		var a: Vector3 = sw[0]
		var b: Vector3 = sw[1]
		var sag: float = sw[2]
		var prev := a
		for i in per:
			var u := float(i + 1) / float(per)
			var pt := a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)
			var mid := (prev + pt) * 0.5
			var dir := pt - prev
			var basis := Basis.looking_at(dir.normalized(), Vector3.UP) if dir.length() > 0.001 else Basis.IDENTITY
			basis = basis.scaled_local(Vector3(1, 1, dir.length() * 1.05))
			mm.set_instance_transform(idx, Transform3D(basis, mid))
			idx += 1
			prev = pt
	cable.multimesh = mm
	cable.material_override = case_paint
	add_child(cable)


## Shelves on the door wall's two halves: spare modules in little cases on the far side (a library of
## what can go in the rack), and on the near side a bench of CV sources (LFO, envelope, random, slew
## boxes, each with its knobs and a light that follows the room's mood and loudness).
func _shelves(x0: float, case_paint: Material, metal: Material) -> void:
	var board := _paint(Color(0.2, 0.14, 0.09), 0.75, 0.0)
	var knob_mm := MultiMesh.new()
	knob_mm.transform_format = MultiMesh.TRANSFORM_3D
	var knob_mesh := CylinderMesh.new()
	knob_mesh.top_radius = 0.016
	knob_mesh.bottom_radius = 0.018
	knob_mesh.height = 0.02
	knob_mm.mesh = knob_mesh
	var knob_at: Array[Transform3D] = []
	var led_mm := MultiMesh.new()
	led_mm.transform_format = MultiMesh.TRANSFORM_3D
	var led_mesh := BoxMesh.new()
	led_mesh.size = Vector3(0.012, 0.012, 0.006)
	led_mm.mesh = led_mesh
	var led_at: Array[Transform3D] = []
	var tints := [Color(0.5, 0.2, 0.15), Color(0.15, 0.3, 0.45), Color(0.2, 0.35, 0.2), Color(0.4, 0.35, 0.15), Color(0.3, 0.2, 0.4), Color(0.12, 0.12, 0.14)]
	var face_x := x0 + 0.16
	# Library (door wall, far half): three shelves of cases.
	for lvl in 3:
		var y := 0.85 + float(lvl) * 0.62
		ZoneKit.block(self, Vector3(0.3, 0.04, 2.5), Vector3(x0 + 0.17, y, 11.45), board, "LibShelf%d" % lvl)
		for br in [10.3, 12.6]:
			ZoneKit.block(self, Vector3(0.22, 0.04, 0.04), Vector3(x0 + 0.13, y - 0.1, br), metal, "LibBrace%d_%d" % [lvl, int(br)])
		for c in 3:
			var cz := 10.55 + float(c) * 0.78
			ZoneKit.block(self, Vector3(0.1, 0.27, 0.72), Vector3(face_x, y + 0.155, cz), case_paint, "LibCase%d_%d" % [lvl, c])
			for m in 4:
				var mz := cz - 0.27 + float(m) * 0.18
				var panel := ZoneKit.block(self, Vector3(0.012, 0.24, 0.165), Vector3(face_x + 0.056, y + 0.155, mz), _paint(tints[(lvl * 5 + c * 2 + m) % tints.size()], 0.5, 0.4), "LibPanel%d_%d_%d" % [lvl, c, m])
				panel.set_meta(&"lib", true)
				for k in 2:
					knob_at.append(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(face_x + 0.07, y + 0.2 + float(k) * 0.08, mz)))
				led_at.append(Transform3D(Basis.IDENTITY, Vector3(face_x + 0.064, y + 0.08, mz)))
	# CV bench (door wall, near half): a long board with five boxes of knobs and sliders.
	var by := 0.95
	ZoneKit.block(self, Vector3(0.5, 0.05, 1.7), Vector3(x0 + 0.27, by, 7.05), board, "CvBench")
	for lg in [6.3, 7.8]:
		ZoneKit.block(self, Vector3(0.45, by - FLOOR_TOP, 0.05), Vector3(x0 + 0.27, (by + FLOOR_TOP) * 0.5, lg), metal, "CvBenchLeg%d" % int(lg * 10.0))
	for b in 5:
		var bz := 6.35 + float(b) * 0.33
		ZoneKit.block(self, Vector3(0.28, 0.1, 0.29), Vector3(x0 + 0.3, by + 0.075, bz), _paint(tints[b % tints.size()], 0.5, 0.4), "CvBox%d" % b)
		for k in 2:
			_bench_knob(b * 3 + k, Vector3(x0 + 0.3 + (-0.06 + float(k) * 0.12), by + 0.125, bz - 0.06))
		_bench_knob(b * 3 + 2, Vector3(x0 + 0.3, by + 0.13, bz + 0.07))
		ZoneKit.block(self, Vector3(0.18, 0.006, 0.014), Vector3(x0 + 0.3, by + 0.127, bz + 0.07), metal, "CvSlot%d" % b)
		ZoneKit.block(self, Vector3(0.025, 0.012, 0.03), Vector3(x0 + 0.3 - 0.05 + 0.02 * float(b % 4), by + 0.133, bz + 0.07), metal, "CvSlide%d" % b)
		ZoneKit.block(self, Vector3(0.02, 0.014, 0.014), Vector3(x0 + 0.3 + 0.1, by + 0.13, bz - 0.09), null, "CvLed%d" % b).material_override = _sign_material
	# A shelf over the bench with the labels of what is below.
	var tag := Label3D.new()
	tag.name = "CvTag"
	tag.text = "CV"
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.modulate = Color(0.9, 0.9, 0.9)
	tag.shaded = false
	tag.rotation_degrees = Vector3(0, 90, 0)
	tag.position = Vector3(x0 + 0.075, by + 0.5, 7.05)
	add_child(tag)
	var lib_tag := tag.duplicate() as Label3D
	lib_tag.name = "LibTag"
	lib_tag.text = "MODULES"
	lib_tag.position = Vector3(x0 + 0.075, 2.95, 11.45)
	add_child(lib_tag)
	knob_mm.instance_count = knob_at.size()
	for i in knob_at.size():
		knob_mm.set_instance_transform(i, knob_at[i])
	led_mm.instance_count = led_at.size()
	for i in led_at.size():
		led_mm.set_instance_transform(i, led_at[i])
	var knobs := MultiMeshInstance3D.new()
	knobs.name = "ShelfKnobs"
	knobs.multimesh = knob_mm
	knobs.material_override = metal
	add_child(knobs)
	var leds := MultiMeshInstance3D.new()
	leds.name = "ShelfLeds"
	leds.multimesh = led_mm
	leds.material_override = _sign_material
	add_child(leds)


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


## One control of the CV bench: a knob a hand turns (the slider's too), at rest in the middle.
func _bench_knob(k: int, at: Vector3) -> void:
	var knob := Knob.new()
	knob.name = "BenchKnob%d" % k
	knob.position = at
	knob.value = 0.0
	knob.describe_title = func() -> String: return "CV BENCH  %s%d" % [["A", "B", "SLIDE"][k % 3], k / 3 + 1]
	knob.describe_value = func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	knob.turned.connect(func(v: float) -> void: bench_turned.emit(k, v))
	add_child(knob)
	bench.append(knob)
	# A lit collar under it, so the knob reads in the dark: the box's own colour, in the room's light.
	var collar := ZoneKit.block(self, Vector3(0.05, 0.004, 0.05), at + Vector3(0, -0.012, 0), null, "BenchCollar%d" % k)
	collar.material_override = _sign_material
