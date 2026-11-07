class_name VenueReact
extends RefCounted

## How a venue hears the mix: the level's smoothing and hit finding (`hear`), the clip lift
## (`hear_clip`) and the soft sparks some venues drive with it (`make_sparks`, `drive_sparks`).
## Moved out of `core/venues/venue.gd` without change of behaviour; the state (`heard`, `heard_hit`,
## `lift`, `lifts` and their timers) stays on the venue, which delegates the calls its subclasses make.

var venue: Venue


func _init(of: Venue) -> void:
	venue = of


## Smooths `level` into `venue.heard` and finds the hits in it into `venue.heard_hit`. Nothing here
## allocates, and a mix at rest (or `reactive` off) settles both at 0.
func hear(level: float) -> void:
	var v := venue
	var l := clampf(level, 0.0, 1.0) if v.reactive else 0.0
	v.heard = lerpf(v.heard, l, 0.45 if l > v.heard else 0.08)
	# A hit is the level jumping above where it has been lately.
	v._heard_slow = lerpf(v._heard_slow, l, 0.05)
	v.heard_hit = maxf(v.heard_hit * 0.82, clampf((l - v._heard_slow) * 3.0, 0.0, 1.0))
	if v.heard < 0.002:
		v.heard = 0.0
	if v.heard_hit < 0.002:
		v.heard_hit = 0.0


## One frame of the room hearing whether anything is over (`over`), `delta` seconds on: a clip
## after `Venue.FLASH_GAP` of none starts a lift; the lift falls away over `Venue.LIFT_SECONDS`.
func hear_clip(over: bool, delta: float) -> void:
	var v := venue
	v._since_lift += delta
	v._lift_left = maxf(v._lift_left - delta, 0.0)
	if over and v.reactive and v.lift_on_clip and v._since_lift >= Venue.FLASH_GAP:
		v._since_lift = 0.0
		v._lift_left = Venue.LIFT_SECONDS
		v.lifts += 1
	if not v.reactive or not v.lift_on_clip:
		v._lift_left = 0.0
	v.lift = Venue.LIFT * v._lift_left / Venue.LIFT_SECONDS


## A box of soft additive sparks on the venue, off until `drive_sparks` turns them on. `colours` is
## picked per spark from its left to its right; `rise` sends them up instead of down.
func make_sparks(label: String, at: Vector3, extents: Vector3, seen: AABB, colours: Gradient,
		amount: int, rise := false) -> GPUParticles3D:
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	soft.width = 32
	soft.height = 32
	var dot := StandardMaterial3D.new()
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dot.vertex_color_use_as_albedo = true
	dot.albedo_texture = soft
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = dot
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3(0, 1 if rise else -1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.5
	m.gravity = Vector3(0, 0.12 if rise else -0.25, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.35
	m.turbulence_noise_scale = 2.0
	m.scale_min = 0.5
	m.scale_max = 1.6
	var pick := GradientTexture1D.new()
	pick.gradient = colours
	m.color_initial_ramp = pick
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	var p := GPUParticles3D.new()
	p.name = label
	p.position = at
	p.amount = amount
	p.lifetime = 3.0
	p.local_coords = false
	p.emitting = false
	p.draw_pass_1 = quad
	p.process_material = m
	p.visibility_aabb = seen
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	venue.add_child(p)
	return p


## How many of `p`'s sparks are out, from what the mix is doing: none at rest.
func drive_sparks(p: GPUParticles3D, gain := 1.0) -> void:
	if p == null:
		return
	var rate := clampf((venue.heard * 1.4 + venue.heard_hit) * gain, 0.0, 1.0)
	p.amount_ratio = maxf(rate, 0.01)
	p.emitting = rate > 0.04
