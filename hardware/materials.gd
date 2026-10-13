class_name Materials
extends RefCounted

## One place that decides what the gear is made of.
##
## Centralised because a studio reads as real through CONSISTENCY, not detail: twelve channel
## strips whose caps are three slightly different greys look like twelve models, not one console.
## It also matters for the hybrid case -- the same materials have to hold up under forward_plus
## on a desktop and under the mobile renderer on a standalone headset, and tuning that in one
## file is tractable where tuning it across forty call sites is not.
##
## Materials are cached and SHARED. A console of 12 strips is ~400 meshes; a fresh material per
## mesh would be 400 shader variants for what is really six surfaces.

static var _cache: Dictionary = {}


static func _cached(key: String, factory: Callable) -> StandardMaterial3D:
	if not _cache.has(key):
		_cache[key] = factory.call()
	return _cache[key]


## A scanned surface from assets/textures: colour, normal, and the packed AO/rough/metal map
## read a channel at a time. Triplanar, because nearly everything here is a BoxMesh, whose own
## UVs stretch one copy of the texture across each face however big the face is -- a two-metre
## wall and a two-centimetre cheek would get the same number of planks.
##
## `metres` is how much surface one repeat of the texture covers.
static func scanned(m: StandardMaterial3D, id: String, res: String, metres: float,
		tint := Color.WHITE) -> StandardMaterial3D:
	var base := "res://assets/textures/%s/%s_%%s_%s.jpg" % [id, id, res]
	m.albedo_texture = load(base % "diff")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base % "nor_gl")
	var orm: Texture2D = load(base % "arm")
	m.roughness = 1.0
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Emulsion on plasterboard: matt, nearly flat, with the faint orange-peel a roller leaves.
static func painted_wall(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.88
	m.normal_enabled = true
	m.normal_texture = grain("roller", 0.6, 0.8)
	m.normal_scale = 0.3
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	return m


## scanned(), made once per key and shared.
static func cached_scanned(key: String, id: String, res: String, metres: float,
		tint := Color.WHITE) -> StandardMaterial3D:
	return _cached("scan_" + key, func():
		return scanned(StandardMaterial3D.new(), id, res, metres, tint))


## Fine surface noise as a normal map, for finishes too small to scan: powder coat, the
## grain of brushed aluminium. Made once per kind and shared.
static func grain(key: String, frequency: float, bump: float, stretch := 1.0) -> Texture2D:
	var k := "grain_%s" % key
	if not _cache.has(k):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = frequency
		noise.fractal_octaves = 3
		var tex := NoiseTexture2D.new()
		# Stretched along one axis for brushing: a long thin noise is what a Scotch-Brite pad
		# leaves behind.
		tex.width = 512
		tex.height = maxi(8, int(512.0 / stretch))
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = bump
		tex.noise = noise
		_cache[k] = tex
	return _cache[k]


## The console shell: dark, slightly rough, not quite black. Pure black reads as a hole in the
## scene because it takes no shading at all.
static func chassis() -> StandardMaterial3D:
	return _cached("chassis", _default_chassis)


static func _default_chassis() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.085, 0.09, 0.098)
	m.roughness = 0.62
	m.metallic = 0.35
	m.metallic_specular = 0.4
	# Powder coat: a finish with a tooth to it, which is what keeps a large dark panel from
	# reading as a flat polygon -- the highlight breaks up instead of sliding across it.
	m.normal_enabled = true
	m.normal_texture = grain("powder", 0.35, 1.2)
	m.normal_scale = 0.35
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 9.0
	return m


## What the gear STANDS in or on, as against the faceplates its controls are mounted on: the
## console's body, the rack's frame and plinth, the patchbay's cabinet, the timeline's stand,
## the deck's trolley. Split from `chassis` so a venue's `GearStyle` can make these timber, road
## case or white panel without touching the plate every legend is printed on, which has to stay
## dark for the lettering to read. In the studio it is the chassis's own powder coat.
static func furniture() -> StandardMaterial3D:
	return _cached("furniture", _default_chassis)


## The strips along a piece of furniture's edges (`GearTrim.edges`): plain steel in the studio,
## and where a venue says so (`GearStyle`), a lit edge in its own colour.
static func trim() -> StandardMaterial3D:
	return _cached("trim", _default_brushed)


## Finishes a venue may restyle.
const STYLED: Array[String] = ["chassis", "furniture", "brushed", "end_cheek", "trim"]


## What a styled finish is when the venue says nothing.
static func _default(key: String) -> StandardMaterial3D:
	match key:
		"brushed", "trim":
			return _default_brushed()
		"end_cheek":
			return _default_end_cheek()
	return _default_chassis()


## Puts a venue's finishes on the gear: every cached material in STYLED takes on the style's
## version of it, or its own default where the style has none. In place, because these are
## shared by hundreds of meshes, most of them in MeshBank multimeshes that cannot be re-pointed
## at a new material one by one -- changing the shared one changes them all at once, and a venue
## switch reaches gear that is already built.
static func apply_style(style: GearStyle) -> void:
	for key in STYLED:
		var from: StandardMaterial3D = style.finishes.get(key) if style != null else null
		if from == null:
			from = _default(key)
		_take_on(_cached(key, _default.bind(key)), from)


## Every stored property of `from` copied onto `to`: a material becomes another without being
## replaced.
static func _take_on(to: StandardMaterial3D, from: StandardMaterial3D) -> void:
	for prop in from.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = prop["name"]
		if name.begins_with("resource_") or name == "script":
			continue
		to.set(name, from.get(name))


## The wooden end cheeks on a console, and nothing else in the room.
##
## Deliberately the only warm, non-metal, non-plastic surface in the studio. Every other part
## here is a value of grey chosen for how it behaves under a lamp, which is correct for the
## parts and leaves the room reading as equipment rather than as a place. One pair of timber
## cheeks is what makes a desk furniture, and because nothing else uses this material it also
## does the job of telling you where the desk ends -- the master section no longer trails off
## into whatever is behind it.
##
## Dark walnut rather than anything warmer, and low metallic with high roughness, because the
## cheeks sit at the two points on the desk a practical catches square-on. The first version
## was a mid oak at the sort of saturation that looks right in a swatch; under the lamp it came
## back as a pair of traffic cones, brighter than any control on the desk and the first thing
## the eye went to. Timber in this room has to be the quietest thing in it.
static func end_cheek() -> StandardMaterial3D:
	return _cached("end_cheek", _default_end_cheek)


static func _default_end_cheek() -> StandardMaterial3D:
	var m := scanned(StandardMaterial3D.new(), "black_walnut_veneer_01", "2k", 0.6,
			Color(0.62, 0.55, 0.5))
	m.metallic_specular = 0.3
	return m


## Brushed aluminium for rack ears, faceplates, reel hubs.
static func brushed_metal() -> StandardMaterial3D:
	return _cached("brushed", _default_brushed)


static func _default_brushed() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.56, 0.58, 0.61)
	m.roughness = 0.34
	m.metallic = 0.85
	# Brushed, not merely grey: the grain runs one way and so does the highlight, which is
	# the whole difference between aluminium and grey plastic under a lamp.
	m.anisotropy_enabled = true
	m.anisotropy = 0.6
	m.normal_enabled = true
	m.normal_texture = grain("brushed", 0.9, 0.6, 24.0)
	m.normal_scale = 0.25
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	return m


## A reel flange, which is aluminium but deliberately not a mirror.
##
## brushed_metal() at 0.34 roughness is right for a fader cap or a jack nut: small, and angled
## every which way, so only a few of them catch a highlight at once. A reel flange is a 17cm
## disc on a deck that is angled towards a practical, which puts the whole face near the mirror
## angle at once -- and it blows to flat white, taking the spokes, the hub and the windows with
## it. The same failure master_plate() already documents, at a scale that hides a whole feature.
##
## Blasted rather than brushed is also what the real part is, and for the same reason: the lamp
## over a tape machine is directly above the reels, and an operator watching the pack all day
## does not want to be looking into it.
static func reel_flange() -> StandardMaterial3D:
	return _cached("reel_flange", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.345, 0.365, 0.395)
		m.roughness = 0.58
		m.metallic = 0.70
		return m)


## A rack blanking panel: the plate that fills a U nobody has put anything in.
##
## A SIXTH of the chassis albedo, which looks like far too much written down and is about right
## on screen. Two things conspire. The first attempt reused the chassis albedo with a rougher
## finish -- dimmer in the inspector, brighter in the render, because roughness spreads the
## practicals across the whole panel instead of into one highlight. The second attempt halved
## the albedo and changed almost nothing visible, which is the part worth remembering: the
## thing a blank is compared against is a faceplate that is mostly knobs, lettering and the
## shadows between them, so an unbroken plate of the same paint is simply a brighter object.
##
## Matching a number to a number is the wrong instrument here. The two were A/B'd on screen,
## including one deliberate overshoot to near-black to confirm albedo was the lever at all --
## after halving it twice with no visible effect, that was no longer obvious.
##
## What a blank has to say is "there is room here". A blank finished like a faceplate says
## "this unit is switched off", and a blank brighter than a faceplate says "look at me".
static func blanking_panel() -> StandardMaterial3D:
	return _cached("blanking_panel", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.014, 0.015, 0.017)
		m.roughness = 0.80
		m.metallic = 0.20
		return m)


## The master section's plate. A shade lighter than the chassis and no more: master sections
## have always been set apart by finish, but brushed aluminium next to a dark painted desk under
## a key light reads as a white rectangle and takes the eye off the twelve channels that are
## actually moving.
static func master_plate() -> StandardMaterial3D:
	return _cached("master_plate", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.135, 0.142, 0.155)
		m.roughness = 0.5
		m.metallic = 0.45
		m.metallic_specular = 0.45
		return m)


## Fader slot: darker than the chassis so the travel reads as a recess rather than a stripe.
static func recess() -> StandardMaterial3D:
	return _cached("recess", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.035, 0.038, 0.042)
		m.roughness = 0.85
		return m)


## Fader cap and knob body: matte plastic, which is what nearly everything a hand touches on a
## desk actually is.
static func cap_plastic(tint: Color = Color(0.2, 0.21, 0.23)) -> StandardMaterial3D:
	var key := "cap_%s" % tint.to_html(false)
	return _cached(key, func():
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = 0.72
		m.metallic = 0.05
		return m)


## A lit indicator. `energy` above 1 is what makes glow pick it up, so an LED that is ON reads as
## on in peripheral vision -- which is the entire job of a mute light on a console of 48.
## A lit bar, as against a lit dot.
##
## `led()` runs at 2.4x emission, which is right for a 4mm indicator: a speck has to overdrive
## to read as lit at all, and it is too small to matter that it clips. A twelve-centimetre bar
## at the same energy is a hole punched in the exposure -- it came back pure white, lost its
## colour, and bloomed over the captions beside it. Area and brightness trade off, and this is
## the same note `reel_flange` and `master_plate` are already written in.
static func indicator_bar(colour: Color) -> StandardMaterial3D:
	return _cached("bar_%s" % colour.to_html(false), func():
		var m := StandardMaterial3D.new()
		m.albedo_color = colour.darkened(0.25)
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = 0.85
		m.roughness = 0.4
		return m)


static func led(colour: Color, on: bool) -> StandardMaterial3D:
	var key := "led_%s_%s" % [colour.to_html(false), on]
	return _cached(key, func():
		var m := StandardMaterial3D.new()
		if on:
			m.albedo_color = colour
			m.emission_enabled = true
			m.emission = colour
			m.emission_energy_multiplier = 2.4
			m.roughness = 0.3
		else:
			# An off LED is not the absence of an LED. It keeps its tint at low value so the
			# panel still reads as having a light there, which is how real hardware looks.
			m.albedo_color = colour.darkened(0.82)
			m.roughness = 0.5
		return m)


## Lit segments are driven past 1.0 so the glow pass catches them, which is what `led()` does
## with emission_energy_multiplier and what an unshaded lamp has to do by hand.
const LAMP_LIT_GAIN := 2.4
## An off LED is not the absence of an LED -- it keeps its tint so the panel still reads as
## having a light there. The same figure as `led()`'s darkened(0.82), by construction.
const LAMP_DARK := 0.18


## What an indicator looks like as a COLOUR rather than as a material.
##
## Exists because the cheap way to draw a hundred little lamps is one MultiMesh with per-instance
## colour, and an instance cannot carry a material. So the thing `led()` expresses as emission
## has to be expressed as a number above 1 instead, and both routes have to agree -- an LED that
## looks different depending on whether it was drawn singly or in a bank is worse than either.
static func lamp_colour(colour: Color, on: bool) -> Color:
	return (colour * LAMP_LIT_GAIN) if on else (colour * LAMP_DARK)


## A track's identity colour as a self-lit patch. NOT the same gain as a lamp, and the difference
## is the point.
##
## A lamp is an indicator: what it has to say is on or off, so driving it to 2.4 and letting the
## channels clip costs nothing -- a blown-out red lamp still reads as a red lamp that is lit.
## A colour chip is an IDENTIFIER: the only thing it says is which track this is, and clipping
## is precisely the operation that destroys that. Reaper's palette is largely pastel, so every
## chip at 2.4 came back as the same pale wash and the desk went back to being 32 identical
## strips -- measured as an A/B, not guessed at.
##
## Just above 1.0, so the chip still reads as lit rather than painted.
const CHIP_GAIN := 1.25


## Brightened by CHIP_GAIN, or by whatever headroom is left -- whichever is less.
##
## The cap is the part that matters. A flat multiply clips the brightest channel first, and a
## colour with one channel clipped and two scaled is a colour whose HUE HAS MOVED: 0.9/0.5/0.2
## at 1.25 becomes 1.0/0.63/0.25, less red and more orange than the track is. Scaling by the
## headroom instead moves every channel by the same factor, so the hue is exactly preserved for
## any input and a colour already at full brightness is simply left alone.
static func chip_colour(colour: Color) -> Color:
	var peak := maxf(colour.r, maxf(colour.g, colour.b))
	var gain := CHIP_GAIN if peak <= 0.0 else minf(CHIP_GAIN, 1.0 / peak)
	return Color(colour.r * gain, colour.g * gain, colour.b * gain, colour.a)


## Screen-printed legend on a panel.
static func legend() -> StandardMaterial3D:
	return _cached("legend", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.79, 0.81)
		m.roughness = 0.9
		return m)


## Cable jacket: rubber, not plastic and not paint.
##
## The clearcoat is what sells it. Bare roughness gives a matte noodle that reads as a drawn
## line; a thin glossy layer over a rough base is exactly what a rubber jacket does under
## studio practicals -- a soft specular streak runs the length of the cable and follows its
## curve, which is most of how the eye reads a cable as round and hanging.
static func cable(colour: Color) -> StandardMaterial3D:
	var key := "cable_%s" % colour.to_html(false)
	return _cached(key, func():
		var m := StandardMaterial3D.new()
		# Deep and SATURATED, which is the opposite of where this started. The first version
		# darkened the track colour and then lerped it toward grey, on the theory that full
		# UI-chroma looks like a graph edge. That theory is right about chroma and wrong about
		# which end to take it out of: a pastel track colour darkened and desaturated lands on
		# a pale muddy mid-tone, and a 4mm tube of pale muddy mid-tone under a diffuse room is
		# a plastic drinking straw. Dyed PVC is dark and vivid at once -- low value, high
		# saturation -- and that is a corner of the space that "darken it a bit" never reaches.
		var jacket := colour
		jacket.s = maxf(jacket.s, 0.62)
		jacket.v = 0.27
		m.albedo_color = jacket

		# A rough body under a tight clearcoat, rather than one middling gloss. A 4mm cylinder
		# is almost all grazing angle, so a broad highlight covers most of its apparent width
		# and the cable reads as the colour of its own sheen -- which is what made these look
		# pastel even before the albedo was addressed. Narrow the specular and the tube gets
		# its shading back: a dark body, a bright line along the top, a visible round.
		m.roughness = 0.58
		m.metallic = 0.0
		m.clearcoat_enabled = true
		m.clearcoat = 0.85
		m.clearcoat_roughness = 0.12
		return m)


## Plug barrel and tip. Nickel rather than chrome -- a mirror-bright plug picks up the whole
## room and reads as a chrome bead rather than as hardware.
static func plug_metal() -> StandardMaterial3D:
	return _cached("plug_metal", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.70, 0.71, 0.73)
		# Nickel, not chrome. A mirror-smooth metal in a dim control room has nothing to
		# reflect and renders near-black, which is how the plugs vanished the first time;
		# roughing it up lets the key light make a highlight instead.
		m.roughness = 0.28
		m.metallic = 0.88
		return m)


## The insulating rings that separate tip from sleeve on a TS plug. Two thin dark bands, and
## they are the detail that makes a plug a PLUG rather than a metal pin.
static func plug_insulator() -> StandardMaterial3D:
	return _cached("plug_insulator", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.035, 0.035, 0.04)
		m.roughness = 0.55
		return m)


## Strain-relief boot behind the plug: same dye as the jacket, softer and a shade darker.
static func cable_boot(colour: Color) -> StandardMaterial3D:
	var key := "boot_%s" % colour.to_html(false)
	return _cached(key, func():
		var m := StandardMaterial3D.new()
		# Darker than the jacket it strain-reliefs, because a boot is moulded rubber and the
		# jacket is extruded PVC, and because a boot the same value as the cable makes the
		# plug look like it grew out of it.
		var rubber := colour
		rubber.s = maxf(rubber.s, 0.45)
		rubber.v = 0.14
		m.albedo_color = rubber
		m.roughness = 0.78
		return m)


## The corner brackets the focus rig draws. Unshaded, because they are not in the room's light
## -- they are drawn over it, and a bracket that dimmed when the lamp was far away would be a
## state indicator that stopped indicating in exactly the corner of the room where you need it.
static func halo(colour: Color) -> StandardMaterial3D:
	return _cached("halo_%s" % colour.to_html(false), func():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colour
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = 1.6
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)
