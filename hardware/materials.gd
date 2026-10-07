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


static func cable(colour: Color) -> StandardMaterial3D:
	var key := "cable_%s" % colour.to_html(false)
	return _cached(key, func():
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.55
		return m)
