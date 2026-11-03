class_name RackMood
extends RefCounted

## The colours the modular room glows in, by venue: each room's own mood, so the rack in a dim club
## throws magenta and cyan, in a studio a warm amber, and so on. {base: the colour at rest, hit: the
## colour a hit flashes to, glow: how strong its light can be}. Its lights follow the rack's loudness
## and hits (RackWall.glow_with), and the studio lends the same to the room's own lights.

const MOODS := {
	&"studio": {"base": Color(1.0, 0.62, 0.3), "hit": Color(1.0, 0.9, 0.6), "glow": 1.0},
	&"grid": {"base": Color(0.2, 0.9, 1.0), "hit": Color(1.0, 0.3, 0.8), "glow": 1.5},
	&"chalk": {"base": Color(0.95, 0.9, 0.8), "hit": Color(1.0, 1.0, 1.0), "glow": 0.7},
	&"loft": {"base": Color(1.0, 0.55, 0.35), "hit": Color(1.0, 0.85, 0.5), "glow": 1.0},
	&"cabin": {"base": Color(1.0, 0.5, 0.2), "hit": Color(1.0, 0.8, 0.4), "glow": 0.9},
	&"rooftop": {"base": Color(0.45, 0.6, 1.0), "hit": Color(1.0, 0.7, 0.9), "glow": 1.1},
	&"station": {"base": Color(0.5, 0.9, 0.6), "hit": Color(0.9, 1.0, 0.7), "glow": 1.0},
	&"dome": {"base": Color(0.7, 0.55, 1.0), "hit": Color(0.5, 1.0, 1.0), "glow": 1.3},
	&"club": {"base": Color(0.9, 0.2, 0.9), "hit": Color(0.2, 0.9, 1.0), "glow": 1.7},
	&"cave": {"base": Color(0.3, 0.85, 0.75), "hit": Color(0.8, 1.0, 0.6), "glow": 1.2},
	&"greenhouse": {"base": Color(0.55, 1.0, 0.45), "hit": Color(1.0, 1.0, 0.6), "glow": 0.9},
	&"stage": {"base": Color(1.0, 0.3, 0.3), "hit": Color(1.0, 1.0, 1.0), "glow": 1.8},
	&"garden": {"base": Color(1.0, 0.8, 0.5), "hit": Color(1.0, 0.6, 0.8), "glow": 0.8},
	&"desert": {"base": Color(1.0, 0.55, 0.25), "hit": Color(1.0, 0.9, 0.4), "glow": 1.0},
}
const FALLBACK := {"base": Color(1.0, 0.7, 0.4), "hit": Color(1.0, 0.95, 0.8), "glow": 1.0}


static func palette(venue_id: StringName) -> Dictionary:
	return MOODS.get(venue_id, FALLBACK)
