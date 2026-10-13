class_name GearStyle
extends RefCounted

## What a venue makes its gear out of: the finishes `Materials.apply_style` puts on the shared
## materials every console, rack, patchbay, stand and trolley is built from, so the gear belongs
## to the room it stands in rather than being the same black studio kit in every one.
##
## `finishes` maps a key of `Materials.STYLED` to the material that finish becomes; a key left
## out stays as it is in the studio. The faceplates (`chassis`) are only ever tinted, and only
## darkly: every legend on the gear is light lettering printed on them.

var finishes: Dictionary = {}


func with(key: String, m: StandardMaterial3D) -> GearStyle:
	finishes[key] = m
	return self


## A painted or coated surface, with the powder coat's tooth so a large panel still breaks up a
## highlight.
static func paint(colour: Color, roughness: float, metallic := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	m.normal_enabled = true
	m.normal_texture = Materials.grain("powder", 0.35, 1.2)
	m.normal_scale = 0.3
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 9.0
	return m


## A scanned surface from assets/textures, `metres` to a repeat.
static func scan(id: String, metres: float, tint: Color) -> StandardMaterial3D:
	return Materials.scanned(StandardMaterial3D.new(), id, "2k", metres, tint)


## A metal: brushed where `roughness` is low, cast or forged where it is high.
static func metal(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = 0.85
	m.anisotropy_enabled = roughness < 0.5
	m.anisotropy = 0.5
	m.normal_enabled = true
	m.normal_texture = Materials.grain("brushed", 0.9, 0.6, 24.0)
	m.normal_scale = 0.2
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	return m


## A lit edge: unshaded colour that the glow picks up, for a trim that is a light rather than a
## strip of metal.
static func glow(colour: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour * 0.4
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m
