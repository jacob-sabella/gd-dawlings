class_name CardsItem
extends FidgetItem

## A deck of cards, to shuffle and fan while you wait (docs/items_loop.md). Three tricks, in turn:
## a riffle shuffle (cut into two halves side by side, tipped up at their inside edges, the cards
## let fall together and the deck pushed back square), a fan (the top seven cards spread out from
## the near end, face up, a hand dealt to yourself), and a square-up (the fan folded back face
## down onto the deck).
##
## The deck is two blocks, the bottom and top halves, and eight loose cards on them that the
## tricks move one by one; that is all a hand sees of a riffle. Which cards a fan shows comes from
## how many tricks have been done (FidgetItem.tricks_done), so everybody's copy deals the same
## hand.

const MODEL := "res://assets/models/card.glb"
const FACES := "res://assets/textures/card_faces.png"
const BACK := "res://assets/textures/card_back.png"
## tools/blender/table_games.py's card.
const WIDTH := 0.0635
const LENGTH := 0.0889
const THICK := 0.0003
## Cards in each of the two blocks, and loose on top of them.
const BLOCK := 22
const LOOSE := 8
const BLOCK_H := BLOCK * THICK
## How many a fan spreads, and how wide (rad, either side).
const FAN := 7
const FAN_ANGLE := 0.55
## The halves of a shuffle, either side of the middle, nearly touching.
const SIDE := WIDTH * 0.5 + 0.004
## The faces texture (tools/make_cards.sh): ranks across, suits down.
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUITS := ["♠", "♥", "♦", "♣"]

var lower: Node3D
var upper: Node3D
## The loose cards, by index, and which is where on the deck, bottom first.
var cards: Array[Node3D] = []
var order: Array[int] = []
## The cards the last fan dealt, 0 to 51 (suit * 13 + rank), bottom of the fan first.
var dealt: Array[int] = []
var _faces: Array[StandardMaterial3D] = []
var _from: Array[Vector3] = []


func _init() -> void:
	id = &"cards"
	super()
	_shape.position.y = 0.025


func item_title() -> String:
	return "DECK OF CARDS"


func tricks() -> int:
	return 3


func trick_name(k: int) -> String:
	return ["shuffle", "fan them out", "square them up"][k]


## How long each trick takes, and what it rings when (FidgetItem.trick_sounds): the riffle and
## the deck knocked square, the fan's sweep, and the square-up's sweep and knock.
const SECONDS := [1.1, 0.7, 0.5]
const SOUNDS := [
	[[0.32, &"card_riffle", -4.0, 1.0], [0.92, &"chip_clack", -22.0, 0.6]],
	[[0.05, &"card_sweep", -6.0, 1.0]],
	[[0.0, &"card_sweep", -8.0, 1.25], [0.9, &"chip_clack", -22.0, 0.6]],
]


func trick_seconds(k: int) -> float:
	return SECONDS[k]


func trick_sounds(k: int) -> Array:
	return SOUNDS[k]


func trick_kind() -> StringName:
	return &"cards_trick"


## Trick `take` heard whole (Foley.take_of's `cards_trick`): what the sampler keeps of one.
static func trick_take(take: int) -> AudioStreamWAV:
	return FidgetItem.trick_stream("cards_trick", SOUNDS, SECONDS, take)


## A card's name: "Q♥".
static func card_name(card: int) -> String:
	return RANKS[card % 13] + SUITS[card / 13]


func _build_body() -> Node3D:
	var root := Node3D.new()
	var scene := load(MODEL) as PackedScene
	var back := StandardMaterial3D.new()
	back.albedo_texture = load(BACK)
	back.roughness = 0.5
	back.albedo_color = Color(0.85, 0.85, 0.85)
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.72, 0.7, 0.66)
	edge.roughness = 0.8
	var blank := StandardMaterial3D.new()
	blank.albedo_color = Color(0.96, 0.95, 0.92)
	blank.roughness = 0.6
	lower = _card(scene, {"back": back, "face": blank, "edge": edge}, "Lower")
	lower.scale.y = BLOCK
	root.add_child(lower)
	upper = _card(scene, {"back": back, "face": blank, "edge": edge}, "Upper")
	upper.scale.y = BLOCK
	root.add_child(upper)
	var atlas := load(FACES) as Texture2D
	for i in LOOSE:
		var face := StandardMaterial3D.new()
		face.albedo_texture = atlas
		face.roughness = 0.45
		# Paper is not a light: under the work light a white face only glares.
		face.albedo_color = Color(0.78, 0.78, 0.78)
		face.uv1_scale = Vector3(1.0 / 13.0, 1.0 / 4.0, 1.0)
		_faces.append(face)
		var card := _card(scene, {"back": back, "face": face, "edge": edge}, "Card%d" % i)
		root.add_child(card)
		cards.append(card)
		_show(i, i)
	order.clear()
	for i in LOOSE:
		order.append(i)
	_place()
	return root


func _card(scene: PackedScene, swap: Dictionary, named: String) -> Node3D:
	var card := Node3D.new()
	card.name = named
	var model := scene.instantiate() as Node3D
	card.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return card


## Loose card `i`'s face shows `card`.
func _show(i: int, card: int) -> void:
	_faces[i].uv1_offset = Vector3(float(card % 13) / 13.0, float(card / 13) / 4.0, 0.0)


## Squared up, face down: the blocks, and the loose cards on them as `order` says.
func _place() -> void:
	lower.position = Vector3.ZERO
	lower.rotation = Vector3.ZERO
	upper.position = Vector3(0, BLOCK_H, 0)
	upper.rotation = Vector3.ZERO
	for slot in LOOSE:
		var card := cards[order[slot]]
		card.transform = Transform3D(Basis.IDENTITY, Vector3(0, 2.0 * BLOCK_H + slot * THICK, 0))


func rest() -> void:
	_place()


func begin(k: int) -> void:
	_from.resize(LOOSE)
	for i in LOOSE:
		_from[i] = cards[i].position
	match k:
		0:
			# The bottom four from the left half and the top four from the right, falling in
			# turn, the left's first.
			var was := order.duplicate()
			order.clear()
			for j in LOOSE / 2:
				order.append(was[j])
				order.append(was[LOOSE / 2 + j])
		1:
			_deal()


## The fan's hand: FAN cards none the same, the same on every copy for the same count of tricks.
func _deal() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * tricks_done + 13
	var deck: Array[int] = []
	for c in 52:
		deck.append(c)
	dealt.clear()
	for f in FAN:
		var c: int = deck.pop_at(rng.randi_range(0, deck.size() - 1))
		dealt.append(c)
		_show(order[LOOSE - FAN + f], c)


func pose(k: int, p: float) -> void:
	match k:
		0:
			_shuffle(p)
		1:
			_fan(p)
		2:
			_fan(1.0 - p)


func end(k: int) -> void:
	if k != 1:
		_place()


## Split (to 0.3): the top block and its four cards across to the right, the bottom block and the
## lower four to the left, each across before it goes down. Riffled (to 0.85): both halves tipped
## up at their inside edges, the cards dropping into the middle one at a time, a side each in
## turn, as the blocks slide back together. Then square.
func _shuffle(p: float) -> void:
	var split := span(p, 0.0, 0.3)
	var across := span(split, 0.0, 0.6)
	var down := span(split, 0.4, 1.0)
	var lift := sin(span(p, 0.3, 0.8) * PI)
	# Back together once every card has fallen, the top block lifted onto the bottom's height first.
	var up := span(p, 0.55, 0.72)
	var close := span(p, 0.72, 0.95)
	lower.position = Vector3(lerpf(-SIDE * across, 0.0, close), 0, 0)
	lower.rotation.z = -0.18 * lift
	upper.position = Vector3(lerpf(SIDE * across, 0.0, close), lerpf(BLOCK_H * (1.0 - down), BLOCK_H, up), 0)
	upper.rotation.z = 0.18 * lift
	var half := LOOSE / 2
	for i in LOOSE:
		var k := int(roundf((_from[i].y - 2.0 * BLOCK_H) / THICK))
		var right := k >= half
		var j := k - half if right else k
		var x := (SIDE if right else -SIDE) * across
		# On its half, riding the top block up as it rises.
		var y := lerpf(_from[i].y, BLOCK_H + j * THICK, down) + lift * (0.004 + j * 0.0008)
		if right:
			y += BLOCK_H * up
		# Falling into the middle, in its turn.
		var slot := 2 * j + (1 if right else 0)
		var fall := span(p, 0.33 + slot * 0.04, 0.43 + slot * 0.04)
		var card := cards[i]
		card.position = Vector3(lerpf(x, 0.0, fall), lerpf(y, 2.0 * BLOCK_H + slot * THICK, fall)
				+ sin(fall * PI) * 0.006, 0)
		card.rotation = Vector3(0, 0, (0.18 if right else -0.18) * lift * (1.0 - fall))


## The top FAN cards turned face up and spread about the deck's near end, `p` of the way out.
func _fan(p: float) -> void:
	var pivot := Vector3(0, 0, LENGTH * 0.5 - 0.012)
	var top := 2.0 * BLOCK_H + LOOSE * THICK
	for f in FAN:
		var card := cards[order[LOOSE - FAN + f]]
		var rest_y := 2.0 * BLOCK_H + (LOOSE - FAN + f) * THICK
		# Each a moment after the one under it.
		var q := span(p, f * 0.05, 0.7 + f * 0.05)
		var flip := span(q, 0.0, 0.7)
		var angle := lerpf(-FAN_ANGLE, FAN_ANGLE, float(f) / float(FAN - 1)) * span(q, 0.3, 1.0)
		var y := lerpf(rest_y, top + 0.001 + f * 0.0004, flip) + sin(flip * PI) * (WIDTH * 0.5 + 0.004)
		var spread := Transform3D(Basis(Vector3.UP, -angle), pivot) * Transform3D(Basis.IDENTITY, -pivot)
		card.transform = spread * Transform3D(Basis(Vector3.BACK, flip * PI), Vector3(0, y, 0))


## The deck and a little round it, and taller than it: flat, it is a sliver from across the room.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.1, 0.06, 0.12)
	return s


func centre_height() -> float:
	return BLOCK_H


## Flat in the palm, tipped up toward the eye so a fan faces it, its near end in the hand.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0.04, 0.03, 0.0))


func flies() -> Dictionary:
	return {"bounce": 0.15, "roll": 8.0, "drag": 0.12}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.card_sweep(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -20.0, -4.0), 1.4)


func _foley_contact() -> AudioStream:
	return Foley.card_sweep(0)
