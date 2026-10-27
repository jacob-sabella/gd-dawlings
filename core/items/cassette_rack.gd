class_name CassetteRack
extends Node3D

## The cassette rack (docs/spatial_loop.md part two, slice 23): a visible clipboard beside the prop
## shelf, the clips the band has pulled out of the timeline standing face out on twelve ledges,
## three columns of four. A station (Stations.ALL, `cassette_rack`): it is gone to by name, and it
## stands clear of everything else the way the harp does.
##
## Its slots are ItemRoom holder RACK (12, top left first, along each row): a made item let go
## within ItemRoom.SLOT_REACH of a free one goes into it, Q aimed at it puts it there, and a click
## on the rack's face with a cassette in the hand shelves it in the free slot nearest the click. A
## full rack says so. Under the slots is the tray, where a cassette with nowhere else to be lies
## (its home, `tray_spot`); under the tray the BIN, holder BIN (one slot), which retires whatever
## is dropped in it: dropped by a hand, aimed at by Q, or clicked with a cassette in the hand.
##
## Every number here is tools/blender/cassette.py's, which builds the model. Origin the middle of
## its foot, its front +Z.

const MODEL := "res://assets/models/cassette_rack.glb"
const RACK := &"rack"
const BIN := &"bin"
const SLOTS := 12
const COLS: Array[float] = [-0.125, 0.0, 0.125]
const ROWS: Array[float] = [1.335, 1.235, 1.135, 1.035]
## How far in front of the back board a racked cassette stands (its middle, along Z).
const SLOT_Z := -0.065
const TRAY_Y := 0.90
const TRAY_Z := -0.08
const BIN_FLOOR := 0.46
const BIN_TOP := 0.72
const BIN_HALF := 0.18
const BIN_BACK := -0.085
const BIN_FRONT := 0.09
## Half its footprint and how tall it stands: its walker solid (Stations' row says the same).
const FOOT := Vector2(0.22, 0.1)
const TOP := 1.5
## Where its plaque hangs: on the cabinet front under the bin.
const PLAQUE_AT := Vector3(0, 0.25, 0.102)
const PLAQUE_WIDTH := 0.40

## The room whose cassettes it holds: what its face and its bin shelve into (ItemRoom.slot_item).
var items: ItemRoom = null
var face: Face
var bin: Bin


func _init() -> void:
	name = "CassetteRack"


func _ready() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	face = Face.new()
	face.rack = self
	face.name = "Face"
	add_child(face)
	bin = Bin.new()
	bin.rack = self
	bin.name = "BinOpening"
	add_child(bin)
	var lettering := Label3D.new()
	lettering.name = "BinLetters"
	lettering.text = "BIN"
	lettering.pixel_size = 0.0004
	lettering.font_size = 100
	lettering.modulate = Color(0.92, 0.88, 0.8)
	lettering.position = Vector3(0, (BIN_FLOOR + BIN_TOP) * 0.5, BIN_FRONT + 0.002)
	lettering.double_sided = false
	lettering.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Lettering.range_to_legibility(lettering)
	add_child(lettering)
	var tray := Label3D.new()
	tray.name = "RackLetters"
	tray.text = "CASSETTES"
	tray.pixel_size = 0.0003
	tray.font_size = 90
	tray.modulate = Color(0.92, 0.88, 0.8)
	# On the back board, over the top row.
	tray.position = Vector3(0, TOP - 0.06, SLOT_Z - 0.019)
	tray.double_sided = false
	tray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Lettering.range_to_legibility(tray)
	add_child(tray)
	var plaque := Stations.plaque(&"cassette_rack", PLAQUE_WIDTH)
	plaque.position = PLAQUE_AT
	add_child(plaque)


## Slot `n` (0 top left, along each row), in the rack's frame: standing on its ledge, its front
## (an item's -Z) out of the rack.
static func slot_pose(n: int) -> Transform3D:
	var col := n % COLS.size()
	var row := clampi(n / COLS.size(), 0, ROWS.size() - 1)
	return Transform3D(Basis(Vector3.UP, PI), Vector3(COLS[col], ROWS[row], SLOT_Z))


## The twelve slots, in the frame `rack` (the rack's own transform in it) puts them.
static func slots_in(rack: Transform3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for n in SLOTS:
		out.append(rack * slot_pose(n))
	return out


## Where a cassette with nowhere else to be lies, numbered `n` (its id's number): flat on the
## tray, face up, three across and stacked, in the rack's frame.
static func tray_spot(n: int) -> Transform3D:
	var k := maxi(n - 1, 0)
	var col := k % COLS.size()
	var layer := (k / COLS.size()) % 4
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(COLS[col], TRAY_Y + CassetteItem.SIZE.z * 0.5 + layer * (CassetteItem.SIZE.z + 0.001), TRAY_Z))


## Inside the bin, lying on its floor: where a binned cassette is shown until the room drops it.
static func bin_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, BIN_FLOOR + 0.02, -0.03))


## The rack as the walker's solid, at `spot` (its transform in the venue's frame).
static func solid(spot: Transform3D) -> Dictionary:
	return {"c": Vector2(spot.origin.x, spot.origin.z), "h": FOOT, "a": spot.basis.get_euler().y, "top": TOP}


## The free rack slot nearest `at` (global), or -1 when every one is taken.
func free_slot_near(at: Vector3) -> int:
	if items == null:
		return -1
	var best := -1
	var nearest := INF
	for n in SLOTS:
		if items.in_slot(RACK, n) != null:
			continue
		var d := (global_transform * slot_pose(n)).origin.distance_to(at)
		if d < nearest:
			nearest = d
			best = n
	return best


## The made item in `hand`, or null.
static func made_in(hand: Node) -> Item:
	var carrying: Variant = hand.get("carrying") if hand != null else null
	if carrying is Item and is_instance_valid(carrying) and ItemRoom.is_made(carrying.id):
		return carrying
	return null


## The rack's face behind the slots: a click with a cassette in the hand shelves it in the free
## slot nearest the click. A racked cassette stands in front of it, so a click on one picks it up.
class Face extends ControlAffordance:
	var rack: CassetteRack

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.38, 0.42, 0.014)
		shape.shape = box
		shape.position = Vector3(0, 1.21, -0.081)
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "CASSETTE RACK"

	func _default_readout() -> String:
		var taken := 0
		if rack != null and rack.items != null:
			for n in SLOTS:
				taken += 1 if rack.items.in_slot(RACK, n) != null else 0
		return "%d of %d slots taken" % [taken, SLOTS] if taken < SLOTS else "full: bin one to make room"

	func hint() -> String:
		return "with a cassette in your hand, click to shelve it · pull a clip off the timeline for one"

	func _on_grab_begin(at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		var item := CassetteRack.made_in(hand)
		if item == null or rack == null or rack.items == null:
			return
		var n := rack.free_slot_near(at)
		if n < 0:
			rack.items.told.emit("The cassette rack is full: drop one in the BIN under it to make room.")
			return
		rack.items.slot_item(item, RACK, n)


## The BIN's opening: a click with a cassette in the hand drops it in, and it is gone.
class Bin extends ControlAffordance:
	var rack: CassetteRack

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(BIN_HALF * 2.0, BIN_TOP - BIN_FLOOR, BIN_FRONT - BIN_BACK)
		shape.shape = box
		shape.position = Vector3(0, (BIN_FLOOR + BIN_TOP) * 0.5, (BIN_FRONT + BIN_BACK) * 0.5)
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "BIN"

	func _default_readout() -> String:
		return "retires a cassette for good"

	func hint() -> String:
		return "with a cassette in your hand, click to bin it"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		var item := CassetteRack.made_in(hand)
		if item != null and rack != null and rack.items != null:
			rack.items.slot_item(item, BIN, 0)
