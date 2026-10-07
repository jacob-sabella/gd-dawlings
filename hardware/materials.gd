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


## Brushed aluminium for rack ears, faceplates, reel hubs.
static func brushed_metal() -> StandardMaterial3D:
	return _cached("brushed", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.56, 0.58, 0.61)
		m.roughness = 0.34
		m.metallic = 0.85
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
