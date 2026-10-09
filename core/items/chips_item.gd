class_name ChipsItem
extends FidgetItem

## A stack of clay poker chips, the thing a hand does at a card table without being asked
## (docs/items_loop.md). Three tricks, in turn: a riffle (cut into two piles side by side and
## pushed back together, one chip from each in turn), a flip (the top chip thumbed up into the
## air, turning over, and caught back on the stack), and a cut (the top third slid off and the
## rest stacked on it).
##
## The stack is chips in an order (`order`, bottom first), which every trick rearranges, so a
## riffle of a stack of two colours comes out striped and a few more come out mixed.

const MODEL := "res://assets/models/chip.glb"
const COUNT := 12
## tools/blender/table_games.py's chip.
const THICK := 0.0033
const RADIUS := 0.0195
## The two piles of a riffle, either side of the middle, touching.
const SIDE := RADIUS + 0.0012
## How high a flip goes above the stack.
const FLIP_HEIGHT := 0.12
const CUT := 4
const RED := Color(0.62, 0.07, 0.08)
const BLUE := Color(0.07, 0.17, 0.5)
const INSERT := Color(0.72, 0.7, 0.65)
const INLAY := Color(0.7, 0.68, 0.62)

## The chips, by index: COUNT / 2 red, then the rest blue.
var chips: Array[Node3D] = []
## Which chip is where in the stack, bottom first.
var order: Array[int] = []
## Where each chip was when the trick began, and where the trick leaves it, by chip.
var _from: Array[Vector3] = []
var _to: Array[Vector3] = []


func _init() -> void:
	id = &"chips"
	super()
	_shape.position.y = 0.03


func item_title() -> String:
	return "POKER CHIPS"


func tricks() -> int:
	return 3


func trick_name(k: int) -> String:
	return ["riffle them", "flip one", "cut the stack"][k]


func trick_seconds(k: int) -> float:
	return [0.95, 0.6, 0.75][k]


func _build_body() -> Node3D:
	var root := Node3D.new()
	var scene := load(MODEL) as PackedScene
	var insert := _paint(INSERT, 0.4)
	var inlay := _paint(INLAY, 0.6)
	for i in COUNT:
		var chip := Node3D.new()
		chip.name = "Chip%02d" % i
		var model := scene.instantiate() as Node3D
		chip.add_child(model)
		var clay := _paint(RED if i < COUNT / 2 else BLUE, 0.55)
		var swap := {"clay": clay, "insert": insert, "inlay": inlay}
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for s in mesh.mesh.get_surface_count():
				var m := mesh.mesh.surface_get_material(s)
				if m != null and swap.has(m.resource_name):
					mesh.set_surface_override_material(s, swap[m.resource_name])
		# Turned a little each, as a real stack's inserts never line up.
		chip.rotation.y = float(i) * 2.4
		root.add_child(chip)
		chips.append(chip)
	order.clear()
	for i in COUNT:
		order.append(i)
	_place()
	return root


static func _paint(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m


## Each chip where `order` says, in one straight stack.
func _place() -> void:
	for slot in order.size():
		var chip := chips[order[slot]]
		chip.position = Vector3(0, slot * THICK, 0)
		chip.rotation.x = 0.0
		chip.rotation.z = 0.0


func rest() -> void:
	_place()


func begin(k: int) -> void:
	_from.resize(COUNT)
	_to.resize(COUNT)
	for i in COUNT:
		_from[i] = chips[i].position
	var was := order.duplicate()
	match k:
		0:
			# Bottom half and top half, one from each in turn, the bottom's first.
			var half := COUNT / 2
			order.clear()
			for j in half:
				order.append(was[j])
				order.append(was[half + j])
		2:
			order = was.slice(COUNT - CUT) + was.slice(0, COUNT - CUT)
	for slot in COUNT:
		_to[order[slot]] = Vector3(0, slot * THICK, 0)


func pose(k: int, p: float) -> void:
	match k:
		0:
			_riffle(p)
		1:
			_flip(p)
		2:
			_cut_stack(p)


func end(_k: int) -> void:
	_place()


## Split (to 0.35): the top half lifts across onto the right, the bottom half slides left, side by
## side. Then each pile's chips spread apart so the other's fit between them, and the piles push
## together, tipped toward each other as thumbs tip them.
func _riffle(p: float) -> void:
	var half := COUNT / 2
	var split := span(p, 0.0, 0.35)
	var spread := span(p, 0.3, 0.6)
	var close := span(p, 0.5, 0.95)
	if cue(p, 0.55):
		Foley.play(self, Foley.chip_riffle(tricks_done), -4.0)
	for i in COUNT:
		var start := _from[i]
		var k := int(roundf(start.y / THICK))
		var top := k >= half
		var j := k - half if top else k
		var side := SIDE if top else -SIDE
		# Split: across first, then down, so the top half clears the bottom.
		var x := side * span(split, 0.0, 0.6)
		var y := start.y
		if top:
			y = lerpf(start.y, j * THICK, span(split, 0.4, 1.0)) + sin(split * PI) * 0.006
		# Riffled: one from each in turn, the bottom pile's first.
		var slot := 2 * j + (1 if top else 0)
		y = lerpf(y, slot * THICK, spread)
		x = lerpf(x, 0.0, close)
		var chip := chips[i]
		chip.position = Vector3(x, y, 0)
		chip.rotation.z = -signf(side) * 0.22 * sin(close * PI)


## The top chip up off the thumb and over, two turns and a half, and back down onto the stack.
func _flip(p: float) -> void:
	var top := chips[order[COUNT - 1]]
	var base := (COUNT - 1) * THICK
	if cue(p, 0.0):
		Foley.play(self, Foley.chip_clack(tricks_done), -14.0, 1.3)
	if cue(p, 0.97):
		Foley.play(self, Foley.chip_clack(tricks_done + 1), -6.0)
	var air := clampf(p / 0.97, 0.0, 1.0)
	top.position = Vector3(0, base + 4.0 * FLIP_HEIGHT * air * (1.0 - air), 0)
	top.rotation.x = air * TAU * 2.5 if p < 1.0 else 0.0


## The top CUT chips slid off to the right and down onto the shelf of the hand, the rest lifted
## across onto them, and the stack slid back to the middle.
func _cut_stack(p: float) -> void:
	var off := span(p, 0.0, 0.4)
	var over := span(p, 0.4, 0.8)
	var back := span(p, 0.8, 1.0)
	if cue(p, 0.4) or cue(p, 0.8):
		Foley.play(self, Foley.chip_clack(tricks_done + (1 if p >= 0.8 else 0)), -8.0)
	var aside := RADIUS * 2.0 + 0.003
	for i in COUNT:
		var start := _from[i]
		var end_y := _to[i].y
		var cut := start.y >= (COUNT - CUT) * THICK - 0.0001
		# The cut goes across and then down; the rest up, clear of it, and then across.
		var moving := off if cut else over
		var x := aside * span(moving, 0.0 if cut else 0.5, 0.5 if cut else 1.0)
		var y := lerpf(start.y, end_y, span(moving, 0.5 if cut else 0.0, 1.0 if cut else 0.5))
		chips[i].position = Vector3(lerpf(x, 0.0, back), y + sin(moving * PI) * 0.006, 0)


## A box a little bigger than the stack: small things on a shelf across the room are hard to
## point at.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.085, 0.06, 0.085)
	return s


func centre_height() -> float:
	return COUNT * THICK * 0.5


## On the fingers above the glove, upright, tipped toward the eye so the top and the stripes
## both show: a stack is small, and in the palm the glove is all there is to see.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0.035, 0.035, 0.06))


func flies() -> Dictionary:
	return {"bounce": 0.25, "roll": 6.0, "drag": 0.05}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.chip_clack(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0))


func _foley_contact() -> AudioStream:
	return Foley.chip_clack(0)
