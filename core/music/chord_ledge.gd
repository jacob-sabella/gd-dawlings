class_name ChordLedge
extends Node3D

## The ledge for chord bricks (docs/spatial_loop.md part two, slice 31): a rail along the bricks
## table's near long edge (Venue.ledge_spot, its band of the table), with sixteen numbered felt
## slots, ItemRoom holder ChordBrick.LEDGE. Bricks stand in it in a row, and the slots' order is
## the progression (ChordBrick.ledge_row): taken from the ledge and pressed into a track or a
## section block, a brick writes the whole row.
##
## A brick let go near the ledge goes into the first free slot after the bricks there
## (ItemRoom.next_in_order), unless it is let go on a free slot itself (ItemRoom.SLOT_EXACT), which
## is how a row is put in another order. At a desk: a click on the rail with a brick in the hand
## stands it there, on the free slot under the click or else at the row's end. The wheel's MAKE
## BRICKS puts the strip's bricks at the end of the row. The BIN at the rail's right end retires a
## brick dropped or clicked into it (holder ChordBrick.BIN), and CLEAR at its left end bins the whole
## row. Behind the rail is a tray, where a brick with nowhere else to be lies (`tray_spot`).
##
## Every number here is tools/blender/chord_brick.py's, which builds the model. Origin the middle of
## its band on the table top, +X along the table, its front +Z toward the player at the near edge.

const STATION := &"ledge"
const MODEL := "res://assets/models/chord_ledge.glb"
const SLOTS := 16
const STEP := 0.07
const RAIL_HALF := 0.565
const RAIL_TOP := 0.018
const RAIL_FRONT := 0.095
const SLOT_Z := 0.048
## The lip along the rail's front (z from RAIL_FRONT to this, its top this high): the slots'
## numbers stand on its face, this big, toward the player, where the station's seat reads them.
const LIP_FRONT := 0.106
const LIP_TOP := 0.024
const NUMBER_SIZE := 80
## Behind the rail: the tray's middle along Z and its top.
const TRAY_Z := -0.075
const TRAY_TOP := 0.008
## The bin at the right end (x from, x to, z from, z to, its top) and CLEAR at the left.
const BIN := [0.585, 0.665, 0.0, 0.1, 0.05]
const CLEAR_AT := Vector3(-0.625, 0.0, 0.05)
const CLEAR_SIZE := Vector3(0.08, 0.02, 0.09)
## The plaque hangs on the table's near edge, under its top: this far out from the band's middle
## (the band's half depth, the 2 cm of table beyond it and half the plate), and its top this far below the top.
const PLAQUE_Z := 0.18
const PLAQUE_DROP := 0.02
const PLAQUE_WIDTH := 0.62
## The rail's, the BIN's and CLEAR's colliders are laid face up: each box's own face (x, y) is its
## top, where a click from above lands, and its z is its height. The same box either way to the
## pointer; but a control's size to aim at is read off its face, and stood the other way the
## rail's face was its 12 mm edge.
const FLAT := Basis(Vector3.RIGHT, -PI * 0.5)

## The room whose bricks it holds: what its rail, its bin and CLEAR stand and bin them in.
var items: ItemRoom = null
var rail: Rail
var bin: Bin
var clear_key: ClearKey


func _init() -> void:
	name = "ChordLedge"


func _ready() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	rail = Rail.new()
	rail.ledge = self
	rail.name = "Rail"
	add_child(rail)
	bin = Bin.new()
	bin.ledge = self
	bin.name = "BinOpening"
	add_child(bin)
	clear_key = ClearKey.new()
	clear_key.ledge = self
	clear_key.name = "Clear"
	clear_key.position = CLEAR_AT
	add_child(clear_key)
	# The slots' numbers, on the lip's face in front of each: upright toward the player, so they
	# read from the station's seat as the brick's own faces do, not lying flat behind the lip.
	for n in SLOTS:
		var number := _letter(str(n + 1), NUMBER_SIZE, Vector3(slot_x(n), LIP_TOP * 0.5, LIP_FRONT + 0.0006), false)
		number.name = "Number%d" % (n + 1)
		# Burnt into the pale wood: dark, where the BIN's and CLEAR's are pale on dark.
		number.modulate = ChordBrick.INK
		add_child(number)
	var bin_word := _letter("BIN", 70, Vector3((BIN[0] + BIN[1]) * 0.5, 0.03, float(BIN[3]) + 0.0025), false)
	bin_word.name = "BinLetters"
	add_child(bin_word)
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	plaque.position = Vector3(0, -PLAQUE_DROP - float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5, PLAQUE_Z)
	add_child(plaque)


func _letter(text: String, size: int, at: Vector3, flat := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00025
	l.modulate = Color(0.95, 0.9, 0.78)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = at
	if flat:
		# Lying on the rail, its top toward the far side, read from where the player stands.
		l.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	Lettering.range_to_legibility(l)
	l.outline_size = 0
	return l


## Slot `n`'s middle along the rail.
static func slot_x(n: int) -> float:
	return (n - (SLOTS - 1) * 0.5) * STEP


## Slot `n` (0 the left end, as the player sees it), in the ledge's frame: standing on the rail's
## felt, a lettered face (an item's -Z) toward the player.
static func slot_pose(n: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(slot_x(n), RAIL_TOP, SLOT_Z))


## The sixteen slots, in the frame `ledge` (the ledge's own transform in it) puts them.
static func slots_in(ledge: Transform3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for n in SLOTS:
		out.append(ledge * slot_pose(n))
	return out


## Inside the bin, on its floor: where a binned brick is shown until the room drops it.
static func bin_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3((BIN[0] + BIN[1]) * 0.5, 0.006, (float(BIN[2]) + float(BIN[3])) * 0.5))


## Where a brick with nowhere else to be lies, numbered `n` (its id's number): on the tray behind
## the rail, a row along it, stacked two high past that.
static func tray_spot(n: int) -> Transform3D:
	var k := maxi(n - 1, 0)
	var layer := (k / SLOTS) % 2
	return Transform3D(Basis(Vector3.UP, PI), Vector3(slot_x(k % SLOTS), TRAY_TOP + layer * (ChordBrick.SIZE.y + 0.006), TRAY_Z))


## The free slot nearest `at` (global) within half a slot of it, or -1.
func free_slot_at(at: Vector3) -> int:
	if items == null:
		return -1
	var p := to_local(at)
	var n := roundi(p.x / STEP + (SLOTS - 1) * 0.5)
	if n < 0 or n >= SLOTS or absf(p.x - slot_x(n)) > STEP * 0.5 or items.in_slot(ChordBrick.LEDGE, n) != null:
		return -1
	return n


## The chord brick in `hand`, or null.
static func brick_in(hand: Node) -> ChordBrick:
	var carrying: Variant = hand.get("carrying") if hand != null else null
	if carrying is ChordBrick and is_instance_valid(carrying):
		return carrying
	return null


## The rail: a click with a brick in the hand stands it on the free slot under the click, or at the
## end of the row. Its hover card says the row.
class Rail extends ControlAffordance:
	var ledge: ChordLedge

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(RAIL_HALF * 2.0, RAIL_FRONT, 0.012)
		shape.shape = box
		shape.basis = FLAT
		shape.position = Vector3(0, RAIL_TOP - 0.006, RAIL_FRONT * 0.5)
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "LEDGE"

	func _default_readout() -> String:
		var row := ChordBrick.ledge_row(ledge.items if ledge != null else null)
		if row.is_empty():
			return "empty: MAKE BRICKS on the wheel fills it"
		return "%s · %d brick%s, %d bars" % [ChordBrick.chords_text(row), row.size(), "" if row.size() == 1 else "s",
				ChordBrick.bars_in(row)]

	func hint() -> String:
		return "with a chord brick in your hand, click to stand it here · take one and click a lane, a strip or a section block: the whole row is written"

	func _on_grab_begin(at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		var brick := ChordLedge.brick_in(hand)
		if brick == null or ledge == null or ledge.items == null:
			return
		var n := ledge.free_slot_at(at)
		if n < 0:
			n = ledge.items.next_in_order(ChordBrick.LEDGE)
		if n < 0:
			ledge.items.told.emit("The ledge is full: drop a brick in its BIN, or press CLEAR.")
			return
		ledge.items.slot_item(brick, ChordBrick.LEDGE, n)


## The BIN's opening: a click with a brick in the hand drops it in, and it is gone.
class Bin extends ControlAffordance:
	var ledge: ChordLedge

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(BIN[1]) - float(BIN[0]), float(BIN[3]) - float(BIN[2]), float(BIN[4]))
		shape.shape = box
		shape.basis = FLAT
		shape.position = Vector3((BIN[0] + BIN[1]) * 0.5, float(BIN[4]) * 0.5, (BIN[2] + BIN[3]) * 0.5)
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "LEDGE  BIN"

	func _default_readout() -> String:
		return "retires a chord brick for good"

	func hint() -> String:
		return "with a chord brick in your hand, click to bin it"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		var brick := ChordLedge.brick_in(hand)
		if brick != null and ledge != null and ledge.items != null:
			ledge.items.slot_item(brick, ChordBrick.BIN, 0)


## CLEAR: every brick on the ledge into the bin, for a fresh row.
class ClearKey extends ControlAffordance:
	var ledge: ChordLedge

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(CLEAR_SIZE.x, CLEAR_SIZE.z, CLEAR_SIZE.y)
		shape.shape = box
		shape.basis = FLAT
		shape.position = Vector3(0, CLEAR_SIZE.y * 0.5, 0)
		add_child(shape)
		var cap := MeshInstance3D.new()
		cap.name = "ClearCap"
		var mesh := BoxMesh.new()
		mesh.size = CLEAR_SIZE - Vector3(0.006, 0.0, 0.006)
		cap.mesh = mesh
		cap.position = Vector3(0, CLEAR_SIZE.y * 0.5, 0)
		cap.material_override = FifthsWheel._paint(Color(0.16, 0.12, 0.08), 0.4, 0.5)
		add_child(cap)
		var l := Label3D.new()
		l.text = "CLEAR"
		l.font_size = 72
		l.pixel_size = 0.00025
		l.modulate = Color(0.95, 0.9, 0.78)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.double_sided = false
		l.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		l.position = Vector3(0, CLEAR_SIZE.y + 0.0008, 0)
		Lettering.range_to_legibility(l)
		l.outline_size = 0
		add_child(l)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "LEDGE  CLEAR"

	func _default_readout() -> String:
		var row := ChordBrick.ledge_row(ledge.items if ledge != null else null)
		return "bins the row: %s" % ChordBrick.chords_text(row) if not row.is_empty() else "the ledge is empty"

	func hint() -> String:
		return "press to bin every brick on the ledge"

	func _on_grab_begin(_at: Vector3) -> void:
		if ledge == null or ledge.items == null:
			return
		var row := ChordBrick.ledge_row(ledge.items)
		for brick in row:
			ledge.items.slot_item(brick, ChordBrick.BIN, 0)
		if not row.is_empty():
			ledge.items.told.emit("Cleared the ledge: %s." % ChordBrick.chords_text(row))
