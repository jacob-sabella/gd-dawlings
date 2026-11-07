class_name RackMood
extends RefCounted

## The colours the modular room glows in, by venue: each room's own mood, so the rack in a dim club
## throws magenta and cyan, in a studio a warm amber, and so on. {base: the colour at rest, hit: the
## colour a hit flashes to, glow: how strong its light can be}. Its lights follow the rack's loudness
## and hits (RackWall.glow_with), and the studio lends the same to the room's own lights.

const FALLBACK := {"base": Color(1.0, 0.7, 0.4), "hit": Color(1.0, 0.95, 0.8), "glow": 0.7}


## The mood of `venue_id`: its layout file's `mood` (hex colours and a glow), or FALLBACK for a room that has none.
static func palette(venue_id: StringName) -> Dictionary:
	return VenueCatalogue.mood_of(venue_id, FALLBACK)
