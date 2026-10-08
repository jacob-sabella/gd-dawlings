class_name GhostLook
extends RefCounted

## What someone's ghost wears: chosen at a mirror, kept between runs, and carried in the
## session's roster so everyone sees the same ghost.
##
## A look is a plain Dictionary of small indices -- {body, eyes, hat, gloves} -- because it rides
## an RPC and sits in a ConfigFile, and both take a Dictionary of ints as it is. Anything that
## comes from outside (the wire, an old file) goes through `clean`, so a peer running a build
## with more hats than this one gets the nearest thing this one has rather than an error.
##
## Who someone IS stays their session colour -- the glow round them, their name, their beam, the
## rim on what they hold. A look changes what they wear, never who they read as.

const KINDS: Array[String] = ["body", "eyes", "hat", "gloves"]

const BODIES: Array[String] = ["Classic", "Mint", "Peach", "Lilac", "Pale", "Slime", "Midnight", "Bubblegum"]
const BODY_COLOURS: Array[Color] = [
	Color(0.30, 0.55, 0.98),
	Color(0.38, 0.86, 0.70),
	Color(1.00, 0.68, 0.52),
	Color(0.70, 0.56, 0.98),
	Color(0.74, 0.77, 0.84),
	Color(0.56, 0.86, 0.26),
	Color(0.16, 0.20, 0.42),
	Color(1.00, 0.52, 0.76),
]
const EYES: Array[String] = ["Dopey", "Wide", "Sleepy", "Grumpy"]
const HATS: Array[String] = ["None", "Beanie", "Headphones", "Top hat", "Crown", "Propeller"]
const GLOVES: Array[String] = ["White", "Black", "My colour", "Gold"]

const PATH := "user://ghost_look.cfg"


static func default_look() -> Dictionary:
	return {"body": 0, "eyes": 0, "hat": 0, "gloves": 0}


static func names(kind: String) -> Array[String]:
	match kind:
		"body": return BODIES
		"eyes": return EYES
		"hat": return HATS
		"gloves": return GLOVES
	return []


## A look made safe: every kind present, every index in range, nothing else carried.
static func clean(look: Variant) -> Dictionary:
	var out := default_look()
	if not look is Dictionary:
		return out
	for kind in KINDS:
		var v: Variant = look.get(kind, 0)
		if v is int or v is float:
			out[kind] = clampi(int(v), 0, names(kind).size() - 1)
	return out


## The next (step 1) or previous (step -1) choice of one kind, wrapping round.
static func stepped(look: Dictionary, kind: String, step: int) -> Dictionary:
	var out := clean(look)
	var count := names(kind).size()
	out[kind] = posmod(out[kind] + step, count)
	return out


static func label(look: Dictionary, kind: String) -> String:
	return names(kind)[clean(look)[kind]]


static func body_colour(look: Dictionary) -> Color:
	return BODY_COLOURS[clean(look)["body"]]


## Read from `path`, or the default look if there is nothing there yet.
static func load_from(path: String) -> Dictionary:
	var file := ConfigFile.new()
	if path.is_empty() or file.load(path) != OK:
		return default_look()
	var look := {}
	for kind in KINDS:
		look[kind] = file.get_value("look", kind, 0)
	return clean(look)


static func save_to(look: Dictionary, path: String) -> void:
	if path.is_empty():
		return
	var file := ConfigFile.new()
	var tidy := clean(look)
	for kind in KINDS:
		file.set_value("look", kind, tidy[kind])
	file.save(path)
