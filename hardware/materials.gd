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


## The console shell: dark, slightly rough, not quite black. Pure black reads as a hole in the
## scene because it takes no shading at all.
static func chassis() -> StandardMaterial3D:
	return _cached("chassis", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.085, 0.09, 0.098)
		m.roughness = 0.62
		m.metallic = 0.35
		m.metallic_specular = 0.4
		return m)


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
	return _cached("end_cheek", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.105, 0.062, 0.036)
		m.roughness = 0.72
		m.metallic = 0.05
		m.metallic_specular = 0.25
		return m)


## Brushed aluminium for rack ears, faceplates, reel hubs.
static func brushed_metal() -> StandardMaterial3D:
	return _cached("brushed", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.56, 0.58, 0.61)
		m.roughness = 0.34
		m.metallic = 0.85
		return m)


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
		# Darkened and desaturated off the track colour. A cable in full UI-chroma looks like a
		# graph edge; real jacket dye is muted, and the chip on the channel strip is already
		# carrying the saturated version of this colour.
		m.albedo_color = colour.darkened(0.42).lerp(Color(0.1, 0.1, 0.11), 0.22)
		m.roughness = 0.44
		m.metallic = 0.0
		m.clearcoat_enabled = true
		m.clearcoat = 0.55
		m.clearcoat_roughness = 0.22
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
		m.albedo_color = colour.darkened(0.45).lerp(Color(0.08, 0.08, 0.09), 0.15)
		m.roughness = 0.72
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
