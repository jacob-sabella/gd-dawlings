class_name Hoop
extends Node3D

## A mini basketball hoop on a weighted stand, for the room's ball (docs/items_loop.md). It is
## furniture, not an item: it stays where the venue stood it (Venue.hoop_spot), and a thrown ball
## meets it in its flight (Flight.fly's `hoops`, `shape`), off its rim and its board and down
## through its net. Every machine flies the same throw, so every one sees the same basket.
##
## Its origin is on the floor under its pole, its board facing +Z into the room. What it does is
## what a hoop does: its rim clangs and its board smacks when they are hit (`struck`), and a ball
## through it swishes the net and says so for a moment over the rim (`sink`), "SWISH" when it
## touched nothing on the way.

const MODEL := "res://assets/models/hoop.glb"
## tools/blender/hoop.py's sizes.
const RIM_RADIUS := 0.115
const RIM_TUBE := 0.007
const RIM_Y := 1.97
const BOARD_FRONT := 0.002
const RIM_Z := BOARD_FRONT + 0.03 + RIM_RADIUS
const BOARD_HALF := Vector2(0.3, 0.21)
const BOARD_Y := 2.12
const NET_DROP := 0.2
const POLE_Z := -0.1
const POLE_RADIUS := 0.022
const POLE_TOP := BOARD_Y + 0.12
## The base's footprint, half each way, and how far forward of the pole its middle is.
const BASE_HALF := Vector2(0.23, 0.21)
const BASE_Z := POLE_Z + 0.06
const BASE_TOP := 0.07
const ORANGE := Color(0.95, 0.38, 0.08)

## Baskets made in it since it was built, swishes and all.
var made := 0
var net: Node3D
## The net's stretch, and how fast it is changing: kicked by a ball, sprung back.
var _stretch := 0.0
var _stretch_speed := 0.0
var _sway := Vector2.ZERO
var _popup: Label3D = null


## Stood, built in `base` (the base and pole) and `board` (the backboard); the rim, lines and net
## are a hoop's own orange and white everywhere. `drawn`: only drawn, by a venue that draws its
## furniture (the chalk zone), and no model here -- it still sounds and says what went in.
func _init(base: Material = null, board: Material = null, drawn := false,
		lamp := Color(1.0, 0.76, 0.48)) -> void:
	name = "Hoop"
	set_process(false)
	if drawn:
		return
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(model)
	var rim := StandardMaterial3D.new()
	rim.albedo_color = ORANGE
	rim.metallic = 0.6
	rim.roughness = 0.35
	var lines := StandardMaterial3D.new()
	lines.albedo_color = ORANGE * 0.9
	lines.roughness = 0.6
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.86, 0.85, 0.82)
	cord.roughness = 0.9
	if board == null:
		var sheet := StandardMaterial3D.new()
		sheet.albedo_color = Color(0.82, 0.83, 0.84)
		sheet.roughness = 0.3
		board = sheet
	if base == null:
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.12, 0.12, 0.13)
		steel.metallic = 0.7
		steel.roughness = 0.45
		base = steel
	var swap := {"base": base, "pole": base, "board": board, "lines": lines, "rim": rim, "net": cord}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	net = model.find_child("Net", true, false) as Node3D
	_lamp(base, lamp)


## How far out from the board its lamp's arm reaches, over the rim.
const LAMP_REACH := 0.3


## A lamp on an arm over the top of the board, aimed back down at it and the rim: a hoop stands
## at the edge of the room, where the room's own light is thin, and a dark board is no target.
func _lamp(frame: Material, colour: Color) -> void:
	var top := BOARD_Y + BOARD_HALF.y
	ZoneKit.block(self, Vector3(0.016, 0.016, LAMP_REACH), Vector3(0, top - 0.03, BOARD_FRONT + LAMP_REACH * 0.5),
			frame, "HoopLampArm")
	var hood_at := Vector3(0, top - 0.015, BOARD_FRONT + LAMP_REACH + 0.01)
	ZoneKit.block(self, Vector3(0.22, 0.03, 0.05), hood_at, frame, "HoopLampHood")
	var strip := ZoneKit.block(self, Vector3(0.19, 0.004, 0.03), hood_at + Vector3(0, -0.017, 0),
			ZoneKit.glow(colour, 2.5), "HoopLampStrip")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := SpotLight3D.new()
	light.name = "HoopLight"
	light.light_color = colour
	light.light_energy = 1.4
	light.spot_range = 1.1
	light.spot_angle = 45.0
	light.spot_attenuation = 0.8
	light.light_specular = 0.2
	light.shadow_enabled = false
	var at := hood_at + Vector3(0, -0.03, 0)
	light.transform = Transform3D(Basis.looking_at(Vector3(0, RIM_Y + 0.02, RIM_Z * 0.4) - at, Vector3.UP), at)
	add_child(light)


## The hoop stood at `at` as a thrown ball meets it (Flight.fly's `hoops`), in `at`'s frame.
static func shape(at: Transform3D) -> Dictionary:
	return {"at": at * Transform3D(Basis.IDENTITY, Vector3(0, RIM_Y, RIM_Z)), "rim": RIM_RADIUS,
			"tube": RIM_TUBE, "net": NET_DROP,
			"board": {"z": RIM_Z - BOARD_FRONT, "y": BOARD_Y - RIM_Y, "half": BOARD_HALF}}


## What of it stops a person, and a ball on the floor, as walker footprints ({c, h, a, top}) in
## `at`'s frame: the base, and the pole up out of it.
static func solids(at: Transform3D) -> Array:
	var yaw := at.basis.get_euler().y
	var base := at * Vector3(0, 0, BASE_Z)
	var pole := at * Vector3(0, 0, POLE_Z)
	return [{"c": Vector2(base.x, base.z), "h": BASE_HALF, "a": yaw, "top": BASE_TOP},
			{"c": Vector2(pole.x, pole.z), "h": Vector2(POLE_RADIUS, POLE_RADIUS), "a": yaw, "top": POLE_TOP}]


## Where the middle of its rim is, in its parent's frame.
func rim_middle() -> Vector3:
	return transform * Vector3(0, RIM_Y, RIM_Z)


## Its rim (`on_rim`) or its board, hit at `speed`.
func struck(on_rim: bool, speed: float) -> void:
	var level := clampf(linear_to_db(speed / 5.0), -24.0, 0.0)
	if on_rim:
		Foley.play(self, Foley.rim_clang(int(speed * 10.0)), level - 2.0, randf_range(0.97, 1.03))
		_kick(0.5, speed)
	else:
		Foley.play(self, Foley.board_thud(int(speed * 10.0)), level)
		_kick(0.15, speed)


## A ball has dropped through it (`clean`: touching nothing): the net swishes and swings, and it
## says so over the rim.
func sink(clean: bool, _item: Node3D = null) -> void:
	made += 1
	Foley.play(self, Foley.net_swish(made), -3.0 if clean else -6.0, randf_range(0.95, 1.05))
	_stretch_speed += 2.6
	_sway += Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
	set_process(true)
	_say("SWISH" if clean else "IN")


func _kick(sway: float, speed: float) -> void:
	_sway += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * sway * minf(speed, 4.0) * 0.25
	set_process(true)


func _say(what: String) -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	var label := Label3D.new()
	label.name = "Said"
	label.text = what
	label.font_size = 72
	label.outline_size = 14
	label.pixel_size = 0.0014
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1.0, 0.72, 0.35)
	label.outline_modulate = Color(0.05, 0.04, 0.03)
	label.position = Vector3(0, BOARD_Y + BOARD_HALF.y + 0.1, RIM_Z)
	add_child(label)
	_popup = label
	var fade := label.create_tween()
	fade.tween_property(label, "position:y", label.position.y + 0.08, 1.6)
	fade.parallel().tween_interval(1.2)
	fade.tween_property(label, "modulate:a", 0.0, 0.5)
	fade.tween_callback(label.queue_free)


## The net on its springs: stretched down by a ball going through and swung by one off the rim,
## settling back. Off once it is still: a hoop at rest costs nothing.
func _process(delta: float) -> void:
	_stretch_speed += (-_stretch * 160.0 - _stretch_speed * 9.0) * delta
	_stretch += _stretch_speed * delta
	_sway -= _sway * minf(1.0, 3.5 * delta)
	if net != null:
		var s := clampf(_stretch, -0.3, 0.6)
		net.scale = Vector3(1.0 - s * 0.25, 1.0 + s, 1.0 - s * 0.25)
		net.rotation = Vector3(_sway.y * 0.2 * sin(Time.get_ticks_msec() * 0.012), 0.0,
				_sway.x * 0.2 * sin(Time.get_ticks_msec() * 0.012))
	if absf(_stretch) < 0.001 and absf(_stretch_speed) < 0.01 and _sway.length() < 0.01:
		_stretch = 0.0
		_stretch_speed = 0.0
		_sway = Vector2.ZERO
		if net != null:
			net.scale = Vector3.ONE
			net.rotation = Vector3.ZERO
		set_process(false)
