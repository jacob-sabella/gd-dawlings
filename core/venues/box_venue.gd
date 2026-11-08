class_name BoxVenue
extends Venue

## A room a player made (docs/layouts.md 8, `MadeRoom`): one closed box round the control room, running
## from its front wall to the back of the live room's reach as the Rig Roulette room does, in one of
## three sizes, with the zones the maker chose and a look from `BoxStyle`. Its layout file names it
## (`shell.builder` "BoxVenue", `shell.size`, `shell.style`, the `zones` it keeps) and `ShellBuilders.make`
## configures it from that; it is never one of the venues the stage manager cycles (`Venue.IDS`).
##
## The zones are the standard ones where they fit: the small room is the control room's width and keeps
## the rhythm riser and the lattice; the standard room is the live room's width and can keep all five;
## the large one has 3.2 m more room each side and the same five zones to spread in.

## Half a side wall's thickness, and the wall's height (the live room's own).
const WALL := 0.1
## How much wider each side the large room is than the standard live room.
const LARGE_EXTRA := 3.2

## The made room's id (its file's slug).
var room_id: StringName = &"made"
var room_title := "Made room"
## One of `MadeRoom.SIZES`.
var room_size := &"standard"
## One of `BoxStyle.IDS`.
var look := &"warm"
## The zones this room kept, of the standard five.
var zone_ids: Array[StringName] = []
## Whether the modular room is built onto it.
var annex := true
## Where its layout puts each kept zone, at the base width (id -> AABB); a zone it does not say stands at the
## standard place (`Venue.ZONES`).
var zone_boxes: Dictionary = {}


## Configures the room from its layout (the resolved or the as-written one): the id, the title, `shell`
## and the keys of `zones`.
func from_layout(l: LayoutData) -> BoxVenue:
	room_id = StringName(l.id)
	room_title = l.title
	var shell: Dictionary = l.body.get("shell", {})
	room_size = StringName(str(shell.get("size", "standard")))
	look = StringName(str(shell.get("style", "warm")))
	zone_ids.clear()
	zone_boxes.clear()
	for id in l.zones():
		if StringName(id) in ZONE_IDS:
			zone_ids.append(StringName(id))
			var z: Dictionary = l.zones()[id]
			if z.get("min") is Array and z.get("size") is Array and (z["min"] as Array).size() >= 3 and (z["size"] as Array).size() >= 3:
				zone_boxes[StringName(id)] = AABB(Vector3(float(z["min"][0]), float(z["min"][1]), float(z["min"][2])),
						Vector3(float(z["size"][0]), float(z["size"][1]), float(z["size"][2])))
	annex = l.pieces().any(func(p: Dictionary) -> bool: return p.get("piece") == String(PieceFeet.ANNEX))
	return self


## Whether any zone of `zones` (a layout's `zones` table) is somewhere other than where this room built it.
func stands_apart_from(zones: Dictionary) -> bool:
	for id in zones:
		var z: Dictionary = zones[id]
		var box: Variant = zone_boxes.get(StringName(id))
		if z.get("min") is Array and (z["min"] as Array).size() >= 3 and box != null \
				and not (box as AABB).position.is_equal_approx(Vector3(float(z["min"][0]), float(z["min"][1]), float(z["min"][2]))):
			return true
	return false


func venue_id() -> StringName:
	return room_id


func title() -> String:
	return room_title


func has_annex() -> bool:
	return annex


func live_room_half() -> float:
	match room_size:
		&"small":
			return room_width * 0.5
		&"large":
			return super() + LARGE_EXTRA
	return super()


## The zones this room kept that fit inside it (a zone must clear the walls by a hand), where its layout has them
## (the standard places for a zone it does not place), stepped out with the desk as every venue's are.
func zones() -> Dictionary:
	var out := {}
	var half := live_room_half() - 0.05
	for id: StringName in zone_ids:
		if not ZONES.has(id):
			continue
		var base: AABB = zone_boxes.get(id, ZONES[id])
		var box := AABB(base.position + Vector3(_grow() * signf(base.get_center().x), 0, 0), base.size)
		if box.position.x >= -half and box.end.x <= half:
			out[id] = box
	return out


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), false)


func back_of_house() -> Rect2:
	var front := Studio.ROOM_BACK
	var half := live_room_half() - 0.05
	return Rect2(-half, front, half * 2.0, LIVE_ROOM_BACK - 0.05 - front)


func gear_style() -> GearStyle:
	var t := BoxStyle.of(look)
	return GearStyle.new() \
			.with("furniture", GearStyle.paint(Color.html(t["floor"]).lightened(0.1), 0.55, 0.0)) \
			.with("trim", GearStyle.metal(Color.html(t["trim"]), 0.35))


func dress(env: Environment, key: DirectionalLight3D) -> void:
	var t := BoxStyle.of(look)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html(t["floor"]).darkened(0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.html(t["ambient"])
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	key.light_energy = 0.0
	key.shadow_enabled = false


func track_palette() -> Array:
	return []


func _ready() -> void:
	var t := BoxStyle.of(look)
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var front := Studio.ROOM_FRONT
	var depth := back - front
	var mid := (back + front) * 0.5
	var height := LIVE_ROOM_HEIGHT

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color.html(t["floor"])
	floor_mat.roughness = 0.6
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, depth)
	floor.mesh = plane
	floor.position = Vector3(0, 0, mid)
	floor.material_override = floor_mat
	add_child(floor)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color.html(t["wall"])
	wall_mat.roughness = 0.9
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color.html(t["trim"])
	trim.metallic = 0.7
	trim.roughness = 0.4
	ZoneKit.block(self, Vector3(half * 2.0 + WALL, height, WALL), Vector3(0, height * 0.5, front), wall_mat, "FrontWall")
	ZoneKit.block(self, Vector3(half * 2.0 + WALL, height, WALL), Vector3(0, height * 0.5, back), wall_mat, "BackWall")
	for sx in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, height, depth - WALL), Vector3(sx * half, height * 0.5, mid), wall_mat,
				"SideWall%s" % ("L" if sx < 0 else "R"))
	ZoneKit.block(self, Vector3(half * 2.0 + WALL, WALL, depth + WALL), Vector3(0, height + WALL * 0.5, mid), wall_mat,
			"Ceiling")
	# A trim strip along the back wall's foot, so the box is more than four flat planes.
	ZoneKit.block(self, Vector3(half * 2.0 - WALL, 0.14, 0.03), Vector3(0, 0.07, back - WALL * 0.5 - 0.01), trim, "Skirt")

	_hang_the_lamps(Color.html(t["lamp"]), trim, height)
	_dress_zones(wall_mat, trim)
	_dress_prop_shelf(wall_mat, trim, Color.html(t["lamp"]))


## Three pendant lamps across the room: warm or cool by the look, no shadows.
func _hang_the_lamps(colour: Color, trim: Material, height: float) -> void:
	var half := live_room_half()
	var xs := [-half * 0.5, 0.0, half * 0.5]
	var z := (LIVE_ROOM_BACK + Studio.ROOM_BACK) * 0.5
	for i in xs.size():
		var at := Vector3(xs[i], height - 0.5, z)
		ZoneKit.block(self, Vector3(0.02, 0.5, 0.02), at + Vector3(0, 0.25, 0), trim, "LampCord%d" % i)
		ZoneKit.block(self, Vector3(0.34, 0.12, 0.34), at, trim, "LampShade%d" % i)
		ZoneKit.block(self, Vector3(0.24, 0.02, 0.24), at + Vector3(0, -0.07, 0), ZoneKit.glow(colour, 3.0), "LampBulb%d" % i)
		var light := OmniLight3D.new()
		light.name = "Lamp%d" % i
		light.position = at + Vector3(0, -0.3, 0)
		light.light_color = colour
		light.light_energy = 2.0
		light.omni_range = 7.0
		light.shadow_enabled = false
		add_child(light)


## What each kept zone holds, in the plain: the riser, the booth, the lattice's floor frame, the table
## and the keyboard stand.
func _dress_zones(wood: Material, metal: Material) -> void:
	var z := zones()
	if z.has(&"drums"):
		var box: AABB = z[&"drums"]
		var drums := ZoneKit.holder(self, &"drums", box)
		ZoneKit.riser(drums, Vector2(box.size.x, box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET, ZoneKit.RISER_HEIGHT,
				wood, metal)
		ZoneKit.spot_down(drums, Vector3(0, LIVE_ROOM_HEIGHT - 0.05, 0), Color(1.0, 0.82, 0.62), 4.0, 40.0, 7.0, metal)
	if z.has(&"vocals"):
		var box: AABB = z[&"vocals"]
		var vocals := ZoneKit.holder(self, &"vocals", box)
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(0.55, 0.62, 0.66, 0.12)
		ZoneKit.booth(vocals, box.size, ZoneKit.BOOTH_DOOR_SIDE, wood, glass)
		ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.01, 0), metal, ZoneKit.MIC_YAW)
	if z.has(&"matrix"):
		var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
		ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3.ZERO, 0.03, metal)
		ZoneKit.floor_frame(matrix, Vector2(3.0, 3.0), Vector3(0, 0.001, 0), 0.012, ZoneKit.glow(Color(0.55, 0.72, 1.0), 0.9))
	if z.has(&"bricks"):
		var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
		ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, wood, metal)
		ZoneKit.spot_down(bricks, Vector3(0, 2.4, 0), Color(1.0, 0.8, 0.6), 2.4, 50.0, 4.0)
	if z.has(&"synth"):
		var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
		ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, metal, wood)
