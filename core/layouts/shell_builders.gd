class_name ShellBuilders
extends RefCounted

## The one list that must stay while the venues' shells are code (docs/layouts.md decision 1): a layout
## file's `shell.builder` names a class here, and `Venue.make` builds that. Adding a venue is its
## layout file plus a line here; the roulette room is the one shell the stage manager does not cycle to.

## builder name -> the shell class (a static var: class names are not constant expressions).
static var BY_NAME: Dictionary = {
	"StudioVenue": StudioVenue,
	"GridVenue": GridVenue,
	"ChalkVenue": ChalkVenue,
	"LoftVenue": LoftVenue,
	"CabinVenue": CabinVenue,
	"RooftopVenue": RooftopVenue,
	"StationVenue": StationVenue,
	"DomeVenue": DomeVenue,
	"ClubVenue": ClubVenue,
	"CaveVenue": CaveVenue,
	"GreenhouseVenue": GreenhouseVenue,
	"StageVenue": StageVenue,
	"GardenVenue": GardenVenue,
	"DesertVenue": DesertVenue,
	"RouletteRoom": RouletteRoom,
	"BoxVenue": BoxVenue,
}


## A new, unbuilt shell for the venue `id` (the studio's for an id with no layout or an unknown
## builder, as `Venue.make` always fell back).
static func make(id: StringName) -> Venue:
	var script: GDScript = BY_NAME.get(VenueCatalogue.builder_of(id), StudioVenue)
	var out: Venue = script.new()
	# A made room is one class set up by its own file: its size, look and zones.
	if out is BoxVenue:
		(out as BoxVenue).from_layout(LiveRoom.layouts().layouts[String(id)])
	return out
