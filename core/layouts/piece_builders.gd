class_name PieceBuilders
extends RefCounted

## The one list that must stay while the pieces' nodes are code (the pieces' twin of `ShellBuilders`,
## docs/layouts.md decision 1): a `PieceDef`'s `builder` names a class here. Adding a piece is its
## `PieceDef` and a line here; a layout file never carries a class name of its own.

## builder name -> the node class (a static var: class names are not constant expressions).
static var BY_NAME: Dictionary = {
	"CassetteRack": CassetteRack,
	"Sampler": Sampler,
	"Hoop": Hoop,
	"TourCase": TourCase,
	"ModularAnnex": ModularAnnex,
}


## True when `piece` names a builder this build has.
static func can_build(piece: StringName) -> bool:
	return PieceDef.has(piece) and BY_NAME.has(PieceDef.of(piece).builder)


## The class that builds `piece`, or null for a piece the venue or a zone stands.
static func script_of(piece: StringName) -> GDScript:
	if not PieceDef.has(piece):
		return null
	return BY_NAME.get(PieceDef.of(piece).builder)
