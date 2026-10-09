class_name ItemRoom
extends Node3D

## Every item in the room, and the rules for where one may be.
##
## Lives in the studio's set, the frame the floor plan and the walker's floor are measured in,
## so an item's place is a place on that floor. The venue says where the shelf is
## (`Venue.item_spots`); this keeps each item's home on it, sends everything at home to the new
## shelf when the venue changes, and sends anything left lying where the new room has no floor
## home too. Items in a hand are left in it.
##
## A put-down is judged here, not by the hand, because only the room knows its floor. An item
## lies only where a person could stand to pick it up again (`Walker.fits`): on the floor or on
## something you step up onto, never on the gear or in a wall. Anywhere else, it goes home.

## The items there are, in the order they take the shelf's spots.
const KINDS: Array[StringName] = [&"duck"]
## How far in front of you a put-down can land; past this, it is put at your feet.
const PUT_REACH := 2.6
## Where it lands when the aim finds no floor in reach: this far in front of where you stand.
const AT_FEET := 0.45

## {id: Item}.
var items: Dictionary = {}
## Says whether a person fits at a floor spot (Vector2, this node's frame) and how high the
## floor is there: the walker's `fits` and `ground_at`. Unset, the whole floor plan is floor.
var fits: Callable = Callable()
var ground_at: Callable = Callable()
var _spots: Array[Transform3D] = []


static func make(kind: StringName) -> Item:
	match kind:
		&"duck":
			return DuckItem.new()
	return null


## What an item of `kind` looks like, and nothing else: no grip, no springs. For a ghost to
## carry, so a mirror or another person sees what is in your hand.
static func look_of(kind: StringName) -> Node3D:
	var item := make(kind)
	if item == null:
		return null
	var look := item.body
	item.remove_child(look)
	item.free()
	look.scale = Vector3.ONE
	return look


## The room an item is in, if any.
static func of(item: Item) -> ItemRoom:
	return item.get_parent() as ItemRoom if item != null and is_instance_valid(item) else null


func _ready() -> void:
	for kind in KINDS:
		if items.has(kind):
			continue
		var item := make(kind)
		item.name = "Item_" + String(kind)
		items[kind] = item
		add_child(item)
	_rehome()


## The shelf's spots, from the venue: one per item, in KINDS order, in this node's frame. Items
## at home go to their new spot; loose ones stay where they lie if they still can.
func set_spots(spots: Array[Transform3D]) -> void:
	_spots = spots
	_rehome()


func _rehome() -> void:
	for i in KINDS.size():
		var item: Item = items.get(KINDS[i])
		if item == null:
			continue
		item.home = _spots[i] if i < _spots.size() else Transform3D.IDENTITY
		match item.state:
			# A shelf that has moved under it: straight there, not floated across the map.
			Item.State.HOME:
				item.snap_home()
			Item.State.LOOSE:
				var at := Vector2(item.resting.origin.x, item.resting.origin.z)
				if not _can_lie(at):
					item.snap_home()


## Put `item` down along `aim` (world space): where the aim meets the floor within reach, or at
## the aimer's feet when it does not. Home if neither is somewhere it can lie.
func put_down(item: Item, aim: Transform3D) -> void:
	var local := global_transform.affine_inverse() * aim
	var origin := local.origin
	var toward := -local.basis.z.normalized()
	var spot := Vector2.INF
	if toward.y < -0.02:
		var along := -origin.y / toward.y
		if along > 0.0 and along < PUT_REACH:
			var hit := origin + toward * along
			spot = Vector2(hit.x, hit.z)
	if spot == Vector2.INF:
		var ahead := Vector2(toward.x, toward.z)
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector2(0, -1)
		spot = Vector2(origin.x, origin.z) + ahead * AT_FEET
	if not _can_lie(spot):
		item.go_home()
		return
	var y: float = ground_at.call(spot) if ground_at.is_valid() else 0.0
	# Facing the way you were looking, as if you had set it down in front of you.
	var yaw := atan2(-toward.x, -toward.z)
	item.lay_down(Vector3(spot.x, y, spot.y), yaw)


func _can_lie(at: Vector2) -> bool:
	if fits.is_valid():
		return fits.call(at)
	return true

