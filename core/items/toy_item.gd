class_name ToyItem
extends Item

## The venue's own toy (docs/items_loop.md): something to throw that belongs to the room you are
## in, lying on the floor by the hoop. A hacky sack in the studio, a neon ball on the grid, a ball
## of paper in the chalk zone, a tennis ball in the loft, a snowball in the cabin, a beach ball on
## the roof, a foam planet on the station, a rubber starfish under the sea, the eight ball in the
## club.
##
## One item, whose look and whose flight are the venue's (`TOYS`): the room changes it when the
## venue changes (`set_venue`), and since the venue is the host's, every machine has the same toy
## and flies it the same. A click squeezes it, as it does the ball, and each says so its own way.

const MODEL := "res://assets/models/toys.glb"
## tools/blender/toys.py's starfish thickness.
const STAR_THICK := 0.018

## By venue: the model's object, what it is called, how big it is (its radius, or a starfish's
## reach), how it flies, and what it sounds like landing (`_landing`). Round ones go through a
## hoop.
const TOYS := {
	&"studio": {"model": "Sack", "title": "HACKY SACK", "size": 0.03, "sound": &"thud",
			"flies": {"bounce": 0.05, "roll": 9.0, "drag": 0.08}},
	&"grid": {"model": "Glow", "title": "NEON BALL", "size": 0.035, "sound": &"ball",
			"flies": {"bounce": 0.8, "roll": 0.6, "drag": 0.05, "round": true}},
	&"chalk": {"model": "Paper", "title": "BALL OF PAPER", "size": 0.035, "sound": &"paper",
			"flies": {"bounce": 0.25, "roll": 4.0, "drag": 0.35, "round": true}},
	&"loft": {"model": "Tennis", "title": "TENNIS BALL", "size": 0.033, "sound": &"ball",
			"flies": {"bounce": 0.7, "roll": 0.9, "drag": 0.06, "round": true}},
	&"cabin": {"model": "Snowball", "title": "SNOWBALL", "size": 0.04, "sound": &"snow",
			"flies": {"bounce": 0.0, "roll": 14.0, "drag": 0.06, "round": true}},
	&"rooftop": {"model": "Beach", "title": "BEACH BALL", "size": 0.2, "sound": &"beach",
			"flies": {"bounce": 0.6, "roll": 0.8, "drag": 0.9, "round": true}},
	&"station": {"model": "Planet", "title": "FOAM PLANET", "size": 0.04, "sound": &"foam",
			"flies": {"bounce": 0.45, "roll": 2.0, "drag": 0.12, "round": true}},
	&"dome": {"model": "Starfish", "title": "RUBBER STARFISH", "size": 0.075, "sound": &"squeak",
			"flies": {"bounce": 0.3, "roll": 6.0, "drag": 0.25}},
	&"club": {"model": "Eight", "title": "EIGHT BALL", "size": 0.028, "sound": &"clack",
			"flies": {"bounce": 0.3, "roll": 1.2, "drag": 0.02, "round": true}},
}
## What each toy is made of, by the model's material names.
const SKINS := {
	"knit_a": [Color(0.86, 0.3, 0.12), 0.95], "knit_b": [Color(0.16, 0.45, 0.62), 0.95],
	"shell": [Color(0.03, 0.025, 0.05), 0.75],
	"paper": [Color(0.8, 0.79, 0.74), 0.85],
	"felt": [Color(0.8, 0.9, 0.18), 0.95], "seam": [Color(0.93, 0.93, 0.88), 0.7],
	"snow": [Color(0.7, 0.74, 0.8), 0.9],
	"gore_a": [Color(0.9, 0.16, 0.14), 0.35], "gore_b": [Color(0.98, 0.78, 0.12), 0.35],
	"gore_c": [Color(0.12, 0.46, 0.86), 0.35], "cap": [Color(0.96, 0.95, 0.92), 0.35],
	"sea": [Color(0.1, 0.32, 0.62), 0.6], "land": [Color(0.3, 0.55, 0.22), 0.8],
	"ice": [Color(0.92, 0.95, 0.98), 0.7],
	"star": [Color(0.95, 0.42, 0.2), 0.55], "dots": [Color(0.98, 0.84, 0.6), 0.6],
	"black": [Color(0.02, 0.02, 0.025), 0.12], "spot": [Color(0.95, 0.94, 0.9), 0.15],
}
## The neon ball's bands: the grid's own magenta.
const NEON := Color(1.0, 0.25, 0.85)

## The toy shown by a ghost carrying one (`ItemRoom.look_of`): this machine's venue's.
static var shown: StringName = &"studio"

## Which venue's toy this is.
var venue: StringName = &""


func _init() -> void:
	id = &"toy"
	venue = shown
	super()
	_shape.position.y = centre_height()


## Turn into `which` venue's toy, if it is not that already; one unknown is the studio's.
func set_venue(which: StringName) -> void:
	if not TOYS.has(which):
		which = &"studio"
	shown = which
	if which == venue:
		return
	venue = which
	var rim := _rim.get_shader_parameter("colour") as Color if _rim != null else Color(0, 0, 0, 0)
	remove_child(body)
	body.queue_free()
	body = _build_body()
	body.name = "Body"
	add_child(body)
	_shape.shape = _grip_shape()
	_shape.position.y = centre_height()
	if state == State.HELD and rim.a > 0.0:
		set_rim(rim)


func _toy() -> Dictionary:
	return TOYS.get(venue, TOYS[&"studio"])


func item_title() -> String:
	return _toy()["title"]


func readout() -> String:
	return "by the hoop" if state == State.HOME else super()


func hint() -> String:
	return _hint("click to pick up; hold R and let go to throw")


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	var mesh := model.find_child(_toy()["model"], true, false) as MeshInstance3D
	mesh.get_parent().remove_child(mesh)
	model.free()
	mesh.transform = Transform3D(Basis.IDENTITY, Vector3(0, centre_height(), 0))
	root.add_child(mesh)
	for s in mesh.mesh.get_surface_count():
		var m := mesh.mesh.surface_get_material(s)
		if m != null:
			mesh.set_surface_override_material(s, _skin(m.resource_name))
	if venue == &"club":
		# The 8, in its white circle.
		var eight := Label3D.new()
		eight.name = "Number"
		eight.text = "8"
		eight.font_size = 48
		eight.outline_size = 0
		eight.pixel_size = 0.00042
		eight.modulate = Color(0.02, 0.02, 0.02)
		eight.double_sided = false
		eight.position = Vector3(0, 0, _toy()["size"] * 1.004)
		mesh.add_child(eight)
	return root


func _skin(what: String) -> Material:
	var m := StandardMaterial3D.new()
	if what == "glow":
		m.albedo_color = NEON
		m.emission_enabled = true
		m.emission = NEON
		m.emission_energy_multiplier = 3.0
		return m
	var skin: Array = SKINS.get(what, [Color(0.6, 0.6, 0.6), 0.6])
	m.albedo_color = skin[0]
	m.roughness = skin[1]
	match what:
		"black", "spot", "gore_a", "gore_b", "gore_c", "cap":
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
	return m


func _grip_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = maxf(0.07, float(_toy()["size"]) + 0.03)
	return s


func centre_height() -> float:
	return STAR_THICK * 0.5 if venue == &"dome" else float(_toy()["size"])


## In the palm, as the bouncy ball is; the beach ball, too big to be held there, out in front of
## the hand and a little below it, both hands round it as it were, where it does not fill the view.
func held_pose() -> Transform3D:
	var size := float(_toy()["size"])
	if size < 0.1:
		return Transform3D.IDENTITY
	return Transform3D(Basis.IDENTITY, Vector3(0.06, -0.12, -size - 0.3))


func flies() -> Dictionary:
	var how: Dictionary = _toy()["flies"].duplicate()
	if how.get("round", false):
		# Round, so it goes off a hoop's rim and through its net (Flight.fly's `hoops`).
		how["radius"] = float(_toy()["size"])
	how.erase("round")
	return how


func use(down: bool) -> void:
	poke(-0.25 if down else 0.15)
	if down:
		_landing(1.0, -8.0)


func on_bounce(speed: float) -> void:
	_landing(speed, clampf(linear_to_db(speed / 5.0), -24.0, 0.0))
	if venue == &"cabin" and speed > 1.0:
		_puff(clampf(speed / 6.0, 0.3, 1.0))


func on_put_down() -> void:
	_landing(1.0, -12.0)


func _foley_contact() -> AudioStream:
	return Foley.rubber_tap()


## The sound of it meeting something at `speed`.
func _landing(speed: float, level: float) -> void:
	var take := int(speed * 10.0)
	match _toy()["sound"]:
		&"thud":
			Foley.play(self, Foley.soft_thud(take), level, randf_range(0.9, 1.1))
		&"snow":
			Foley.play(self, Foley.snow_crunch(take), level)
		&"paper":
			Foley.play(self, Foley.paper_tap(), level, randf_range(0.8, 1.0))
		&"beach":
			Foley.play(self, Foley.beach_bop(take), level)
		&"foam":
			Foley.play(self, Foley.soft_thud(take), level, 1.5)
		&"squeak":
			Foley.play(self, Foley.squeak(true), level - 4.0, randf_range(0.9, 1.15))
		&"clack":
			Foley.play(self, Foley.board_thud(take), level, 1.8)
		_:
			Foley.play(self, Foley.ball_bounce(), level, randf_range(0.95, 1.06) * (0.85 if venue == &"loft" else 1.1))


## A snowball bursting a little where it lands: a puff of powder, once, gone in a second.
func _puff(amount: float) -> void:
	var puff := CPUParticles3D.new()
	puff.name = "Puff"
	puff.one_shot = true
	puff.emitting = true
	puff.amount = int(lerpf(10.0, 28.0, amount))
	puff.lifetime = 0.8
	puff.explosiveness = 0.95
	puff.direction = Vector3.UP
	puff.spread = 70.0
	puff.initial_velocity_min = 0.4 * amount
	puff.initial_velocity_max = 1.1 * amount
	puff.gravity = Vector3(0, -2.5, 0)
	puff.damping_min = 1.5
	puff.damping_max = 2.5
	puff.scale_amount_min = 0.6
	puff.scale_amount_max = 1.4
	var grain := SphereMesh.new()
	grain.radius = 0.006
	grain.height = 0.012
	grain.radial_segments = 6
	grain.rings = 3
	var white := StandardMaterial3D.new()
	white.albedo_color = SKINS["snow"][0]
	white.roughness = 0.8
	grain.material = white
	puff.mesh = grain
	puff.top_level = true
	add_child(puff)
	puff.global_position = global_position
	puff.finished.connect(puff.queue_free)
