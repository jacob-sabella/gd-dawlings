class_name CaveVenue
extends Venue

## A cave under a mountain, its rock lit from within: the venue's own brief is in docs/venues.md.
## A scaffold: a floor, the zones and the shelf. Everything else is still to be built.


func venue_id() -> StringName:
	return &"cave"


func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.paint(Color(0.36, 0.33, 0.38), 0.6, 0.1)) \
			.with("lamp_shade", GearStyle.paint(Color(0.22, 0.2, 0.24), 0.4, 0.2)) \
			.with("loom_band", GearStyle.paint(Color(0.4, 0.75, 0.95), 0.7, 0.0)) \
			.with("knob_cap", GearStyle.paint(Color(0.55, 0.2, 0.75), 0.3, 0.0))


func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.paint(Color(0.1, 0.09, 0.12), 0.7, 0.0)
	board.ink = Color(0.85, 0.92, 1.0)
	board.accent = Color(0.5, 0.85, 1.0)


func back_wall_gear_stands() -> bool:
	return true


func rooms() -> Array[Rect2]:
	var out: Array[Rect2] = [back_of_house()]
	out.append_array(beside_the_desk())
	return out


func zone_solids() -> Array:
	return ZoneKit.solids(zones(), true)


func _ready() -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(live_room_half() * 2.0 + 0.2, LIVE_ROOM_BACK - Studio.ROOM_FRONT + 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.z = (LIVE_ROOM_BACK + Studio.ROOM_FRONT) * 0.5
	floor_mesh.material_override = ZoneKit._paint(Color(0.36, 0.33, 0.38), 0.9)
	add_child(floor_mesh)
	_dress_zones()


func _dress_zones() -> void:
	var z := zones()
	var frame := ZoneKit._paint(Color(0.22, 0.2, 0.24), 0.5, 0.3)
	var top := ZoneKit._paint(Color(0.36, 0.33, 0.38), 0.6)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.7, 0.75, 0.12)
	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	ZoneKit.riser(drums, Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET,
			ZoneKit.RISER_HEIGHT, top, frame)
	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	ZoneKit.booth(vocals, (z[&"vocals"] as AABB).size, ZoneKit.BOOTH_DOOR_SIDE, frame, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.07, frame)
	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, top, frame)
	_dress_prop_shelf(top, frame)
	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, frame, top)


func track_palette() -> Array:
	return [
		Color(0.62, 0.30, 0.42), Color(0.78, 0.50, 0.30), Color(0.80, 0.72, 0.40), Color(0.55, 0.72, 0.42),
		Color(0.30, 0.60, 0.50), Color(0.30, 0.68, 0.72), Color(0.40, 0.60, 0.85), Color(0.38, 0.42, 0.78),
		Color(0.58, 0.42, 0.82), Color(0.75, 0.40, 0.72), Color(0.88, 0.60, 0.78), Color(0.55, 0.55, 0.60),
	]
