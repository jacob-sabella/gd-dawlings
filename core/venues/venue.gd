class_name Venue
extends Node3D

## The world the studio stands in.
##
## Everything a person WORKS with -- the gear, the stands it rides on, the lamps, the looms, where
## each of them has been pushed -- belongs to the studio and is the same in every venue. A venue
## is everything else: the floor, what is past the edge of the floor, the sky if there is one,
## the air, and how all of it is lit. Swapping one is a change of scenery, never of setup, which
## is why it is safe to do mid-session and why it is one key.
##
## PER PARTICIPANT, like the layout it is saved in. Two people in one session can stand in two
## different venues around the same console; nothing about the mix depends on what the room
## looks like, so nothing about the venue is replicated.
##
## Every venue keeps the same working footprint (room_width x Studio.ROOM_DEPTH) because the
## furniture's floor plan is that rectangle. A venue with no walls marks it instead -- a lit
## border on the grid, a chalk outline in the chalk zone -- so the edge you will bump a rack
## into is never invisible.

## Registry, in cycling order. The first is the default.
const IDS: Array[StringName] = [&"studio", &"grid", &"chalk"]

## How wide the working footprint is. Set by the studio before the venue enters the tree; the
## room grows with the desk (see SessionLayout), and a venue drawn for the old width would put
## its walls through the rack.
var room_width := Studio.ROOM_WIDTH

## Set by the studio before the venue enters the tree: whether the full desktop renderer is
## running. A venue must look right without it -- a headset runs the mobile renderer.
var rich := false


static func make(id: StringName) -> Venue:
	match id:
		&"grid":
			return GridVenue.new()
		&"chalk":
			return ChalkVenue.new()
		_:
			return StudioVenue.new()


## A venue's name without building one: building the chalk zone to read its title would draw
## sixty-four doodles for a button caption.
static func make_title(id: StringName) -> String:
	match id:
		&"grid":
			return "Grid"
		&"chalk":
			return "Chalk Zone"
		_:
			return "Studio"


static func next_after(id: StringName) -> StringName:
	var at := IDS.find(id)
	return IDS[(at + 1) % IDS.size()]


static func is_known(id: StringName) -> bool:
	return IDS.has(id)


func venue_id() -> StringName:
	return &"studio"


## What a person is told when they arrive.
func title() -> String:
	return make_title(venue_id())


## Set up the sky, the air, the exposure and the key light. `env` arrives fresh, with the
## studio's house defaults (glow on, SSAO on) already in it, so a venue only states what is
## different about it.
func dress(_env: Environment, _key: DirectionalLight3D) -> void:
	pass


## The lamps are furniture and go wherever the venue goes, but what they shine is the venue's
## call: a warm tungsten floor lamp on a neon grid is a lamp from another room.
func lamp_colour(_index: int, authored: Color) -> Color:
	return authored


func lamp_energy(_index: int, authored: float) -> float:
	return authored


## How loud the mix is right now, 0..1, every frame. For venues that move to the music.
func pulse(_level: float) -> void:
	pass


## A lit or drawn outline of the working footprint, at floor level, as a set of corners.
func footprint_corners() -> PackedVector2Array:
	var hw := room_width * 0.5 - 0.05
	var front := Studio.ROOM_DEPTH * 0.5 + 0.3 - 0.05
	var back := -Studio.ROOM_DEPTH * 0.5 + 0.3 + 0.05
	return PackedVector2Array([Vector2(-hw, back), Vector2(hw, back), Vector2(hw, front),
			Vector2(-hw, front)])


## A mirror in this venue's style, where this venue keeps it. See core/venues/mirror.gd.
func make_mirror(env: Environment) -> Mirror:
	var m := Mirror.new()
	m.name = "Mirror"
	m.rich = rich
	m.environment_from = env
	m.transform = mirror_spot(m.glass_size)
	_frame_mirror(m)
	var board := Wardrobe.new()
	board.name = "Wardrobe"
	_dress_wardrobe(board)
	board.transform = wardrobe_spot(m)
	m.add_child(board)
	m.wardrobe = board
	return m


## Where the wardrobe board hangs, in the mirror's frame: beside the glass on its +X side, at
## hand height, turned a little toward whoever is standing in front of the glass.
func wardrobe_spot(mirror: Mirror) -> Transform3D:
	var beside := mirror.glass_size.x * 0.5 + 0.34
	var hand := 1.25 - mirror.position.y
	return Transform3D(Basis(Vector3.UP, -0.4), Vector3(beside, hand, 0.06))


## The board's materials and ink, in the venue's own style. Left plain by default.
func _dress_wardrobe(_board: Wardrobe) -> void:
	pass


## Where the glass's centre stands, facing into the room. By default on the left wall behind
## the treatment, facing across the room: a step back and a turn left from the mix position,
## clear of every piece of gear in the floor plan.
func mirror_spot(glass: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(-room_width * 0.5 + 0.16, 0.14 + glass.y * 0.5, 2.2))


## Build the frame round `mirror`'s glass, as its children. The glass faces +Z and is centred
## on the mirror; a frame stands proud of it, never in front of the glass's face.
func _frame_mirror(_mirror: Mirror) -> void:
	pass


## Four bars round the glass, `bar` wide and `depth` deep, set back so their faces sit `proud`
## in front of the glass, and `inset` over its edge. Shared by the venues whose frames are solid.
static func frame_bars(mirror: Mirror, bar: float, depth: float, proud: float,
		material: Material, inset := 0.0) -> void:
	var w := mirror.glass_size.x - inset * 2.0
	var h := mirror.glass_size.y - inset * 2.0
	for spec in [[Vector3(0, (h + bar) * 0.5, 0), Vector3(w + bar * 2.0, bar, depth)],
			[Vector3(0, -(h + bar) * 0.5, 0), Vector3(w + bar * 2.0, bar, depth)],
			[Vector3((w + bar) * 0.5, 0, 0), Vector3(bar, h, depth)],
			[Vector3(-(w + bar) * 0.5, 0, 0), Vector3(bar, h, depth)]]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		piece.mesh = box
		piece.material_override = material
		piece.position = spec[0] + Vector3(0, 0, proud - depth * 0.5)
		mirror.add_child(piece)
