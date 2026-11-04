class_name RackMood
extends RefCounted

## The colours the modular room glows in, by venue: each room's own mood, so the rack in a dim club
## throws magenta and cyan, in a studio a warm amber, and so on. {base: the colour at rest, hit: the
## colour a hit flashes to, glow: how strong its light can be}. Its lights follow the rack's loudness
## and hits (RackWall.glow_with), and the studio lends the same to the room's own lights.

const MOODS := {
	&"studio": {"base": Color(1.0, 0.62, 0.3), "hit": Color(1.0, 0.9, 0.6), "glow": 0.7},
	&"grid": {"base": Color(0.5, 0.9, 1.0), "hit": Color(1.0, 0.55, 0.85), "glow": 0.8},
	&"chalk": {"base": Color(0.95, 0.9, 0.8), "hit": Color(1.0, 1.0, 1.0), "glow": 0.7},
	&"loft": {"base": Color(1.0, 0.55, 0.35), "hit": Color(1.0, 0.85, 0.5), "glow": 0.7},
	&"cabin": {"base": Color(1.0, 0.5, 0.2), "hit": Color(1.0, 0.8, 0.4), "glow": 0.65},
	&"rooftop": {"base": Color(0.45, 0.6, 1.0), "hit": Color(1.0, 0.7, 0.9), "glow": 0.75},
	&"station": {"base": Color(0.5, 0.9, 0.6), "hit": Color(0.9, 1.0, 0.7), "glow": 0.7},
	&"dome": {"base": Color(0.7, 0.55, 1.0), "hit": Color(0.5, 1.0, 1.0), "glow": 0.8},
	&"club": {"base": Color(0.86, 0.5, 0.86), "hit": Color(0.55, 0.9, 1.0), "glow": 0.8},
	&"cave": {"base": Color(0.3, 0.85, 0.75), "hit": Color(0.8, 1.0, 0.6), "glow": 0.8},
	&"greenhouse": {"base": Color(0.55, 1.0, 0.45), "hit": Color(1.0, 1.0, 0.6), "glow": 0.65},
	&"stage": {"base": Color(1.0, 0.55, 0.5), "hit": Color(1.0, 0.95, 0.85), "glow": 0.65},
	&"garden": {"base": Color(1.0, 0.8, 0.5), "hit": Color(1.0, 0.6, 0.8), "glow": 0.8},
	&"desert": {"base": Color(1.0, 0.55, 0.25), "hit": Color(1.0, 0.9, 0.4), "glow": 0.7},
}
const FALLBACK := {"base": Color(1.0, 0.7, 0.4), "hit": Color(1.0, 0.95, 0.8), "glow": 0.7}


static func palette(venue_id: StringName) -> Dictionary:
	return MOODS.get(venue_id, FALLBACK)
