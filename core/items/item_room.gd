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
## In a session the room is the host's (`Session.room["items"]`, see `state` and `apply`): a hand
## here that puts something down does it at once and says so (`asked`), and the host's word
## then stands, or puts it back.
##
## A put-down is judged here, not by the hand, because only the room knows its floor. An item
## lies only where a person could reach to pick it up again (`Walker.reachable`): on the floor or
## on something you step up onto, never on the gear or in a wall. Anywhere else, it goes home.
##
## An instrument that stands still (`Item.fixed`, docs/spatial_loop.md part two, slice 38) is never
## laid, thrown, flown or pocketed here, and a room's word never moves it: its home is its station.

## The items there are, in the order they take the shelf's spots. The session in miniature
## (docs/spatial_loop.md part two, slice 34) is after the shelf's: its home is the side table by the seat,
## not the shelf. Then the hand drums (HandDrum, slice 40), fixed kinds that stand in their ring on
## the drum riser and never on the shelf: where a venue has no ring (the Rig Roulette room, AR) they
## are put away (`stand`), neither seen nor struck. Then the venue's instrument's bars
## (VenueInstrument.Bar, slice 42), `venue1` to `venue8`, fixed where the venue's set stands them and
## put away past the set's count or where the venue has none. Last is the drum pads' kit (KitItem,
## slice 41), fixed on the console's front rail wherever there is a console, AR too.
const KINDS: Array[StringName] = [&"duck", &"ball", &"plane", &"mic", &"headphones", &"glasses", &"tablet",
		&"chips", &"cards", &"dart1", &"dart2", &"dart3",
		&"cradle", &"yoyo", &"toy", &"rcplane", &"miniature",
		&"djembe", &"conga_hi", &"conga_lo", &"cajon",
		&"venue1", &"venue2", &"venue3", &"venue4", &"venue5", &"venue6", &"venue7", &"venue8", &"kit"]
## The kinds an AR room makes (`only`): the room is the player's own real one, with none of the
## shelf's things in it, but the desk's pads play there (docs/spatial_loop.md part two, slice 41).
const AR_KINDS: Array[StringName] = [&"kit"]
## How far in front of you a put-down can land; past this, it is put at your feet.
const PUT_REACH := 2.6
## Where it lands when the aim finds no floor in reach: this far in front of where you stand.
const AT_FEET := 0.45
## An aimed throw (`aim_point`) at a board no further than this; at nothing, this far along the aim.
const AIM_REACH := 8.0
const AIM_LENGTH := 2.5

## The kinds nobody shares: the shelf keeps one of each (`KINDS`, unchanged) as a dispenser that
## is never itself held, and a hand reaching for it is given a copy of its own instead
## (`take_personal`), bound to them (`Item.bound_to`, the same mechanism Tour marks a spill
## with) so nobody else's hand can take it. Put down, that copy is gone rather than sent to a
## shelf spot that would mean nothing shared between two people's copies (`retire`).
const PERSONAL_KINDS: Array[StringName] = [&"mic", &"headphones", &"glasses", &"tablet"]

## The kinds that exist only once somebody makes one while playing (docs/spatial_loop.md part two,
## slice 23): never on the shelf (not KINDS), minted by the host (`mint`) under the next free id in
## the shape `kind_of` reads, `cassette1`, `cassette2`. What a made item carries is not room state:
## its row ({id: [kind, maker, bytes]}, `made`) is sent once on a message of its own and to each
## guest as it joins, and the room names only its id (`made_ids`), so a put-down never resends a
## clip.
const MADE_KINDS: Array[StringName] = [&"cassette"]
## What a made item may carry, packed (var_to_bytes): at most this much one item, this much the
## whole room, and this many items. Past any of them a mint is refused, and says which.
const MADE_BYTES := 256 * 1024
const MADE_TOTAL := 4 * 1024 * 1024
const MADE_MOST := 64
## How near a free slot (`holders`) a made item has to be let go to go into it (m).
const SLOT_REACH := 0.08
## The holders that swallow what goes in them (`unmake`, on the host): the cassette rack's BIN.
const BINS: Array[StringName] = [&"bin"]
## What each holder takes, by kind, and what to call them when it refuses another: the rack and the
## platter cassettes. A holder not here (a bin) takes any made item.
const HOLDS := {&"rack": [&"cassette"], &"platter": [&"cassette"]}
const HOLDS_SAID := {&"cassette": "cassettes"}

## A hand here put `item` somewhere: `put_item` [id, x, z, yaw] or `home_item` [id], already
## done here. The studio sends it to the host as an ask.
signal asked(verb: StringName, args: Array)
## A hand here used `item`: for the session to tell everyone.
signal used(item: Item, down: bool)
## Something about where an item is changed: for a host to tell the room.
signal moved(item: Item)
## `item` rang a sound of its own on this copy (Item.rang: a ball's bounce): for the sampler.
signal rang(item: Item, kind: StringName, take: int, pitch: float)
## An instrument played by a hand here (InstrumentItem.played): for the session and the take. `at`
## is the song position it was played to, the one its note was pitched by; `zone`, where on a fixed
## one it was struck (&"" for none).
signal played(item: InstrumentItem, velocity: int, struck: bool, at: float, zone: StringName)
## A hand here was refused an item (Item.may_hold, a Tour "marked" spill): for the studio's toast.
signal refused(item: Item, why: String)
## `item` is a fresh personal copy, just spawned and bound (`take_personal`): for the studio to
## say whose it is (`Item.bound_name`), which needs `Session.name_of` and so stays out of this
## file, the same as `local_peer` above is asked through a callable rather than named here.
signal personal_taken(item: Item)
## `item` was just minted on this machine (`mint`): its row (`made[item.id]`) is for the session to
## send everyone, once.
signal minted(item: Item)
## Made item `id` is gone for good (`unmake`: the BIN): for the session to tell everyone.
signal unmade(id: StringName)
## Something for this player to be told (a full rack, a taken slot): the studio's toast.
signal told(text: String)
## A hand here pressed `item` (one that `pastes`: a cassette) onto `track` at `seconds` (docs/
## spatial_loop.md part two, slice 24): for the studio to paste it, or ask the host to.
signal paste_pressed(item: Item, track: int, seconds: float)

## {id: Item}.
var items: Dictionary = {}
## Says whether something lying at a floor spot (Vector2, this node's frame) could be picked up
## again and how high the floor is there: the walker's `reachable` and `ground_at`. Unset, the whole floor plan is floor.
var fits: Callable = Callable()
var ground_at: Callable = Callable()
## Whoever is local to this machine (`Session.local_peer_id`), studio.gd's, asked only when a
## throw is made -- so a registered target (the Tour case) can tell a host's own throw from a
## guest's. Unset, as in a test with no studio, a throw counts as the host's.
var local_peer: Callable = Callable()
## What a throw flies in: the walkable floor (Array of Rect2, walls at its edges) and the venue's
## solids (Walker.fixed), in this node's frame. The walker's, read when the throw is made.
var floor_rects: Callable = Callable()
var solids: Callable = Callable()
## The gear's footprints (the walker's `footprints`), for a put-down aimed through the gear at
## the floor behind it.
var gear: Callable = Callable()
## What a dart sticks in (Flight.fly's `boards`), in this node's frame: the venue's dartboard.
var boards: Array = []
## The baskets in the room (Venue.hoops), in its frame, for a round thing thrown at one: the
## shapes Flight.fly takes, and each its "node", the Hoop that swishes and clangs.
var hoops: Array = []
## Furniture a thrown item can register a hit against, without the ball-through-hoop or
## stick-in-board physics: {"node": Node3D, "radius": float}. Generic -- any prop that wants to
## know "something just hit me" registers here, the way a venue's hoops do; the Tour case is
## the first of these, but nothing here names it.
var targets: Array = []
var _spots: Array[Transform3D] = []
## Homes of their own, off the shelf's top, by kind: the mic's stand, the headphones' hook, the
## tablet's lower tier.
var _homes: Dictionary = {}
## Every made item's row, {id: [kind, maker, bytes]}: the session's (`Session.made`, set by the
## studio, the same Dictionary), or this room's own where there is no session.
var made: Dictionary = {}
## Furniture that holds made items in slots, {holder: [Transform3D per slot]} in this node's
## frame, filled by whatever builds it: the cassette rack (`rack`, 12) and its bin (`bin`, 1).
var holders: Dictionary = {}
## Where a made item with nowhere else to be lies, by kind and number ((kind, n) -> Transform3D,
## this node's frame): the cassette rack's tray. Unset, the room's origin.
var made_home: Callable = Callable()
## Whether this machine's word is the room's (Session.is_authority): a slot in the bin retires an
## item here, or waits for the host to. Unset, as with no session, it is.
var authority: Callable = Callable()
## How far along a hand's ray ((item, origin, direction) -> metres, global) what the carried item's
## own press is for lies, when it is not a control: a bandmate's ghost a made item is handed to
## (the studio's). Nearer than the control under the ray, the press is the item's (Interactor);
## unset, or INF, the control takes it.
var press_ahead: Callable = Callable()
## The kinds this room makes, if not every one: empty for all of KINDS, the spills and the made
## items; AR_KINDS in AR, whose room is the player's own (the studio's). A kind not here is never
## made, spawned or made real.
var only: Array[StringName] = []
## Why the last `mint` was refused, or "".
var mint_refusal := ""
## The number the next made item of each kind is after: ids are never given twice in a room, so a
## row heard late can never be taken for a newer one.
var _made_after: Dictionary = {}


## Holders and the slots items lie in.
var slotting := ItemSlots.new(self)
## Made items: minting, applying and forgetting their rows.
var made_items := ItemMade.new(self)
## Throws, flights, hoops and targets.
var flight := ItemFlight.new(self)
## Putting items down, wearing, pocketing and where they may lie.
var placing := ItemPlacing.new(self)
## The room's items as a row for the session, and back.
var replica := ItemReplica.new(self)

## A new item of `kind` (a name from `KINDS`), unplaced.
static func make(kind: StringName) -> Item:
	match kind:
		&"duck":
			return DuckItem.new()
		&"ball":
			return BallItem.new()
		&"plane":
			return PlaneItem.new()
		&"mic":
			return MicItem.new()
		&"headphones":
			return HeadphonesItem.new()
		&"glasses":
			return SignalGlassesItem.new()
		&"tablet":
			return TabletItem.new()
		&"chips":
			return ChipsItem.new()
		&"cradle":
			return CradleItem.new()
		&"yoyo":
			return YoyoItem.new()
		&"toy":
			return ToyItem.new()
		&"rcplane":
			return RcPlaneItem.new()
		&"cards":
			return CardsItem.new()
		&"dart1":
			return DartItem.new(0)
		&"dart2":
			return DartItem.new(1)
		&"dart3":
			return DartItem.new(2)
		&"cowbell":
			return CowbellItem.new()
		&"woodblock":
			return WoodblockItem.new()
		&"pad":
			return PadItem.new()
		&"triangle":
			return TriangleItem.new()
		&"claves":
			return ClavesItem.new()
		&"hihat":
			return HihatItem.new()
		&"bongo":
			return BongoItem.new()
		&"cassette":
			return CassetteItem.new()
		&"miniature":
			return MiniatureItem.new()
		&"testdrum":
			return TestDrumItem.new()
		&"djembe", &"conga_hi", &"conga_lo", &"cajon":
			return HandDrum.new(kind)
		&"kit":
			return KitItem.new()
	if VenueInstrument.is_bar(kind):
		return VenueInstrument.Bar.new(int(String(kind).substr(5)) - 1)
	return null


## The kind a spilled instance's own id names, its voice number stripped off: "cowbell2" ->
## "cowbell", "cowbell" -> "cowbell". An id the shelf itself holds is its own kind, digits and
## all -- the darts are "dart1".."dart3", and `make` answers to
## exactly those -- so KINDS is checked first rather than trusting that no shelf id ends in a
## number.
static func kind_of(id: StringName) -> StringName:
	if id in KINDS:
		return id
	return StringName(String(id).rstrip("0123456789"))


## The peer a personal copy's own id names ("tablet7" -> 7), `take_personal`'s id read backward.
## Good enough to stand in for syncing `Item.bound_to` across the wire: a personal copy's id
## always names exactly who it is for, so there is nothing else to carry.
static func peer_of(id: StringName) -> int:
	return int(String(id).trim_prefix(String(kind_of(id))))


## What an item of `kind` looks like, and nothing else: no grip, no springs. For a ghost to
## carry, so a mirror or another person sees what is in your hand. `kind` here is an item's own
## id, which for a spilled instrument's second voice ("cowbell2") is not one `make` answers to
## directly -- `kind_of` is what makes the carried look-alike right.
static func look_of(kind: StringName) -> Node3D:
	var item := make(kind_of(kind))
	if item == null:
		return null
	var look := item.body
	item.remove_child(look)
	item.free()
	look.scale = Vector3.ONE
	return look


## Whether `id` is a made item's (MADE_KINDS): one somebody made while playing.
static func is_made(id: StringName) -> bool:
	return not (id in KINDS) and kind_of(id) in MADE_KINDS


## Why a made item of `size` bytes would not fit in a room whose rows are `rows`, or "" if it
## would: MADE_BYTES an item, MADE_TOTAL a room, MADE_MOST items.
static func made_refusal(rows: Dictionary, size: int) -> String:
	if rows.size() >= MADE_MOST:
		return "The room has %d made things already: drop one in the BIN on the cassette rack first." % MADE_MOST
	if size > MADE_BYTES:
		return "That clip is too much to carry (%d KiB; a cassette holds %d KiB)." % [ceili(size / 1024.0), MADE_BYTES / 1024]
	var total := size
	for id in rows:
		var row: Array = rows[id]
		if row.size() == 3 and row[2] is PackedByteArray:
			total += (row[2] as PackedByteArray).size()
	if total > MADE_TOTAL:
		return "The room's made things are full (%d MiB): drop one in the BIN on the cassette rack first." % (MADE_TOTAL / 1024 / 1024)
	return ""


## What a made item of `kind` made `from` something here carries: a cassette of a clip
## ("clip:<track>:<item index>", CassetteItem.data_of the song as it is now). Empty
## where there is nothing there to make one of. The host packs it from its own state: a guest asks
## with `from`, never with the data.
static func made_data(kind: StringName, from: String) -> Dictionary:
	match kind:
		&"cassette":
			var part := from.split(":")
			if part.size() == 3 and part[0] == "clip" and part[1].is_valid_int() and part[2].is_valid_int():
				return CassetteItem.data_of(DAW.state, int(part[1]), int(part[2]))
	return {}


## Whether `holder` swallows what goes into it (BINS).
static func is_bin(holder: StringName) -> bool:
	return holder in BINS


## `item`, pressed onto `track` at `seconds` by a hand here: said (`paste_pressed`), for the studio.
## Nothing in the room moves: the cassette stays in the hand.
func paste(item: Item, track: int, seconds: float) -> void:
	if item != null and is_instance_valid(item) and item.pastes():
		paste_pressed.emit(item, track, seconds)


## The room an item is in, if any.
static func of(item: Item) -> ItemRoom:
	return item.get_parent() as ItemRoom if item != null and is_instance_valid(item) else null


func _ready() -> void:
	for kind in KINDS:
		if items.has(kind) or not makes(kind):
			continue
		var item := make(kind)
		item.name = "Item_" + String(kind)
		items[kind] = item
		add_child(item)
		_adopt(item)
	_rehome()


## Whether this room makes `kind` (`only`).
func makes(kind: StringName) -> bool:
	return only.is_empty() or kind in only


## The signal wiring every item here gets, whether it was here from `_ready` or fell out of the
## case later (`spawn`): lifted out so both call one thing.
func _adopt(item: Item) -> void:
	item.used.connect(func(down: bool) -> void: used.emit(item, down))
	item.rang.connect(func(kind: StringName, take: int, pitch: float) -> void: rang.emit(item, kind, take, pitch))
	item.state_changed.connect(func(_s: Item.State) -> void: moved.emit(item))
	item.landed.connect(func() -> void: moved.emit(item))
	item.worn_changed.connect(func() -> void: moved.emit(item))
	if item is InstrumentItem:
		(item as InstrumentItem).played.connect(func(velocity: int, struck: bool, at: float, zone: StringName) -> void:
			played.emit(item, velocity, struck, at, zone))


## A copy of `kind` that is not one of KINDS -- a Tour spill, cowbell or cowbell2 -- given `id`
## (unique per copy) and a home of its own at `home` (where it lies when lost, not a shelf
## spot). Idempotent: asking for an id already here just returns it, so a guest that hears of
## the same spill twice (a republish) does not make a second one.
func spawn(kind: StringName, id: StringName, home: Transform3D) -> Item:
	if items.has(id):
		return items[id]
	if not makes(kind):
		return null
	var item := make(kind)
	if item == null:
		return null
	item.id = id
	item.home = home
	item.own_home = true
	item.name = "Item_" + String(id)
	items[id] = item
	add_child(item)
	_adopt(item)
	item.snap_home()
	return item


## `id` is gone from the room entirely -- a run ending, the case swallowing its spills again.
## Whoever's hand has it opens first: an item that stops existing is not something to still be
## holding.
func despawn(id: StringName) -> void:
	var item: Item = items.get(id)
	if item == null:
		return
	if item.carried_by != null:
		item.carried_by.lose_carrying()
	items.erase(id)
	remove_child(item)
	item.queue_free()


## Every spawned item's id, not one of KINDS, in the order it fell out of the case: a Dictionary
## keeps insertion order, and KINDS is always populated first (`_ready`). Not the made items
## (`made_ids`), which no case spilled and no run's end swallows.
func spawned_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in items:
		# A fixed instrument stood here (a test kind's) is no spill either: it stands, it was not tipped out.
		if not (id in KINDS) and not is_made(id) and not (items[id] as Item).fixed:
			out.append(id)
	return out


## Every made item here, in the order they were made.
func made_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in items:
		if is_made(id):
			out.append(id)
	return out


## On the host: a made item of `kind` carrying `data`, made by `maker` (a peer id), under the next free id (`cassette1`, ...), its row kept in `made` and said (`minted`), and spawned at its home. Null, and `mint_refusal` saying why, past MADE_MOST, MADE_TOTAL or MADE_BYTES, or for no data (`ItemMade.mint`).
func mint(kind: StringName, data: Dictionary, maker := 1) -> Item: return made_items.mint(kind, data, maker)


## Made item `id` real here, from its row in `made`: spawned at its home and given what it carries (`ItemMade._make_real`).
func _make_real(id: StringName) -> Item: return made_items._make_real(id)


## The made items the host's room names (`made_ids`), here: each one this machine has the row of and has not met made real, and each one here the room no longer names gone. Its row, if any, stays until the host says it is gone (`forget_made`): a row can arrive before the room names it (`ItemMade.apply_made`).
func apply_made(ids: Array) -> void: made_items.apply_made(ids)


## Made item `id` gone for good, on the host: out of the room and out of `made`, and said (`ItemMade.unmake`).
func unmake(id: StringName) -> void: made_items.unmake(id)


## The host said made item `id` is gone: here too, row and all (`ItemMade.forget_made`).
func forget_made(id: StringName) -> void: made_items.forget_made(id)


# --- slots (docs/spatial_loop.md part two, slice 23) -------------------------------------------

## Holder `holder`'s slots are `slots` now (this node's frame): what is in them is laid there again (`ItemSlots.set_holder`).
func set_holder(holder: StringName, slots: Array[Transform3D]) -> void: slotting.set_holder(holder, slots)


## Whatever is in `holder`'s slot `n`, or null. A bin's is never taken: it swallows (`ItemSlots.in_slot`).
func in_slot(holder: StringName, n: int) -> Item: return slotting.in_slot(holder, n)


## Why `item` may not go into `holder`'s slot `n`, or "" (`ItemSlots.slot_refusal`).
func slot_refusal(item: Item, holder: StringName, n: int) -> String:
	return slotting.slot_refusal(item, holder, n)




## The room's word: `item` into `holder`'s slot `n`, if it may go there. The bin, on the host, retires it. Whether it went (`ItemSlots.slot`).
func slot(item: Item, holder: StringName, n: int) -> bool: return slotting.slot(item, holder, n)


## A hand here put `item` into `holder`'s slot `n`: done at once, and said; or refused, and told (`ItemSlots.slot_item`).
func slot_item(item: Item, holder: StringName, n: int) -> bool: return slotting.slot_item(item, holder, n)






## The slot nearest `at` (global) within `reach`, [holder, n], taken or not; [] for none (`ItemSlots.slot_near`).
func slot_near(at: Vector3, reach := SLOT_REACH) -> Array: return slotting.slot_near(at, reach)




## `id`'s kind, said in the same breath: not `kind_of(id)`, which is also true of the dispenser
## itself (`kind_of("tablet") == "tablet"`) -- this is false for the dispenser, true only for a
## copy actually spawned for somebody (`kind_of(id) in PERSONAL_KINDS and id != kind_of(id)`).
func is_personal_copy(id: StringName) -> bool:
	var kind := kind_of(id)
	return kind in PERSONAL_KINDS and id != kind


## `peer`'s own copy of a personal kind: the one already spawned for them if they have one
## (idempotent, same as `spawn`), or a fresh one at the dispenser's own spot. Modelled directly on
## `scenes/studio.gd`'s `_spill_instrument`/`_dress_spilled` (spawn, then bind) -- the same shape,
## triggered by a pick-up instead of a card falling out of the case.
func take_personal(kind: StringName, peer: int) -> Item:
	if not (kind in PERSONAL_KINDS) or peer <= 0:
		return null
	var id := StringName("%s%d" % [kind, peer])
	var home: Transform3D = items[kind].home if items.has(kind) else Transform3D.IDENTITY
	var item := spawn(kind, id, home)
	if item == null:
		return null
	item.bound_to = peer
	personal_taken.emit(item)
	return item


## A hand here reached for the shelf's own dispenser of a personal kind (`Item._on_grab_begin`'s
## redirect): their own copy, given to the hand at once, and the ask that tells the host so.
func take_for(hand: Interactor, kind: StringName) -> void:
	var peer := int(local_peer.call()) if local_peer.is_valid() else 1
	var item := take_personal(kind, peer)
	if item == null:
		return
	hand.pick_up(item)
	asked.emit(&"take_personal", [kind])


## `item` out of a hand or off the floor: the shelf, for most kinds (`Item.go_home`); gone for
## good, for a personal copy (`is_personal_copy`), since there is no shelf spot that would mean
## anything once two people can each have one of their own.
func retire(item: Item) -> void:
	if is_personal_copy(item.id):
		despawn(item.id)
	else:
		item.go_home()


## Tossed out of the case, on the host: lobbed at `to` with a little sideways scatter and a
## tumble drawn from `seed`, so the same run spills the same way. A guest never calls this --
## it flies its own copy from the launch `state` carries (`launched_with`, replayed in `apply`),
## the way any thrown item reaches it.
func spill(item: Item, from: Vector3, to: Vector3, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := lob(from, to, 3.0)
	var side := Vector3(-v.z, 0.0, v.x).normalized() if Vector2(v.x, v.z).length() > 0.001 else Vector3.RIGHT
	v += side * rng.randf_range(-0.3, 0.3)
	var spin := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
	fly(item, from, v, spin, 1)


## The venue is `which`: its toy is that venue's (ToyItem.set_venue).
func set_venue(which: StringName) -> void:
	ToyItem.shown = which
	var toy := items.get(&"toy") as ToyItem
	if toy != null:
		toy.set_venue(which)


## The shelf's spots, from the venue: one per item, in KINDS order, in this node's frame. Items
## at home go to their new spot; loose ones stay where they lie if they still can.
func set_spots(spots: Array[Transform3D], homes: Dictionary = {}) -> void:
	_spots = spots
	_homes = homes
	_rehome()


func _rehome() -> void:
	# The shelf's spots go to the kinds with no home of their own, in KINDS order.
	var shelf := 0
	for i in KINDS.size():
		var item: Item = items.get(KINDS[i])
		# A fixed kind stands at its station or nowhere: never on the shelf.
		if item != null and item.fixed:
			stand(KINDS[i], _homes.get(KINDS[i]))
			continue
		if item != null:
			item.own_home = _homes.has(KINDS[i])
		if _homes.has(KINDS[i]):
			if item != null:
				item.home = _homes[KINDS[i]]
		else:
			if item != null:
				item.home = _spots[shelf] if shelf < _spots.size() else Transform3D.IDENTITY
			shelf += 1
		if item == null:
			continue
		match item.state:
			# A shelf that has moved under it: straight there, not floated across the map.
			Item.State.HOME:
				item.snap_home()
			Item.State.LOOSE:
				var at := Vector2(item.resting.origin.x, item.resting.origin.z)
				if item.slot_in == &"" and not placing._can_lie(at):
					item.snap_home()


## Fixed instrument `id` stood at `home` (Transform3D, this node's frame), its station, or put away
## where there is none (null): hidden, out of the physics so no ray or socket finds it, and not
## processed, so Strike passes it by (it reads only what is seen). The studio stands the hand drums
## through `set_spots`; the session probe stands one itself.
func stand(id: StringName, home: Variant) -> void:
	var item: Item = items.get(id)
	if item == null or not item.fixed:
		return
	var away := not (home is Transform3D)
	item.visible = not away
	item.process_mode = Node.PROCESS_MODE_DISABLED if away else Node.PROCESS_MODE_INHERIT
	if away:
		return
	item.own_home = true
	item.home = home
	item.snap_home()


## The instrument whose jack `source` is (InstrumentItem.jack_source): the item of that id, or for a
## venue's set (VenueInstrument.SOURCE) its first bar that stands here; null for none.
func source_item(source: StringName) -> Item:
	var item: Item = items.get(source)
	if item != null or source != VenueInstrument.SOURCE:
		return item
	for n in VenueInstrument.MOST:
		var bar: Item = items.get(VenueInstrument.bar_id(n))
		if bar != null and stands(bar.id):
			return bar
	return null


## Whether fixed instrument `id` stands here now (`stand`): false where it is put away.
func stands(id: StringName) -> bool:
	var item: Item = items.get(id)
	return item != null and item.fixed and item.visible


## Every item that is not at home, as the room has it: {id: [x, y, z, yaw]} for one lying on the floor (and "stuck" and the quaternion it is turned by after, for one stuck in a board), {id: []} for one in a hand, {id: [true]} for one on a head, {id: ["pocket", n]} for one in a pocket, {id: ["slot", holder, n]} for one in a slot (`holders`). One left out is on the shelf, or, made, at its home (`made_home`). What a made item carries is never here (`ItemReplica.state`).
func state() -> Dictionary: return replica.state()


## Make the items what the host's room says (`state`). Not one a hand here has, nor one this guest has put somewhere and not heard back about (`pending`, by id); nor one the room says is in a hand, which the holds put there (Presence). One the room has on the floor lands there; one it leaves out goes home -- unless it is a personal copy nobody here has met yet (spawned by another peer's pick-up, or already out there when this one joined), which is made real here too, the same way a Tour spill reaches a guest that was not there when it fell; or one nobody holds any more, which is retired rather than sent home (`ItemReplica.apply`).
func apply(room_items: Dictionary, pending: Dictionary = {}) -> void: replica.apply(room_items, pending)


## Lay `item` on the floor at `at` (this node's frame), turned to `yaw`, if it can lie there; home if it cannot. True if it lies there. The host's answer to a put-down, and a hand's own. A personal copy never lies anywhere: putting it down retires it (`retire`), same as sending it home, since there is no floor spot that would mean anything once two people can each have one (`ItemReplica.lay`).
func lay(item: Item, at: Vector2, yaw: float) -> bool: return replica.lay(item, at, yaw)


## Throw `item` from a hand here: from `origin` at `velocity` (world space), spinning at `spin` (rad/s, world axes). Flown at once, and said, for the host to fly too (`ItemFlight.throw`).
func throw(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3) -> void:
	flight.throw(item, origin, velocity, spin)


## Fly `item` from `origin` at `velocity`, spinning at `spin` -- all in this node's frame -- the same flight on every machine. `thrown_by` is whoever's throw this is (their peer id, 1 for the host): carried only for a registered target (the Tour case) to tell a host's own throw from a guest's; nothing else here reads it. Where it comes down, it stays if it can lie there; if not, it goes home when it has (`ItemFlight.fly`).
func fly(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3, thrown_by: int = 1) -> void:
	flight.fly(item, origin, velocity, spin, thrown_by)


## Something in flight hit a hoop's rim or board (Flight.RIM, Flight.BOARD) at `at` (world space): the nearest hoop sounds it. Whether there was one to (`ItemFlight.hoop_struck`).
func hoop_struck(on: int, speed: float, at: Vector3) -> bool: return flight.hoop_struck(on, speed, at)


## `item` has just dropped through hoop `index`, touching nothing on the way if `clean` (`ItemFlight.basket`).
func basket(item: Item, index: int, clean: bool) -> void: flight.basket(item, index, clean)


## Something in flight hit furniture registered in `targets` at `at` (world space), going at `speed`, thrown by `thrown_by` (its peer id, item.gd's `thrown_by`): the nearest one within its own radius takes it (`struck`, the same duck-typed call `hoop_struck` makes on a Hoop). Whether there was one close enough to (`ItemFlight.target_struck`).
func target_struck(speed: float, at: Vector3, thrown_by: int) -> bool:
	return flight.target_struck(speed, at, thrown_by)




## What `aim` (world space) is aimed at, for a thrown thing that is aimed (Item.aim_scatter): where it meets a board in front of it, or a throw's length along it. World space (`ItemFlight.aim_point`).
func aim_point(aim: Transform3D) -> Vector3: return flight.aim_point(aim)


## The velocity that takes a thing from `from` to `to` at about `speed`, falling as it goes:
## the time it takes is the distance over the speed, and it is thrown up by as much as it falls.
static func lob(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var gap := to - from
	var t := maxf(0.05, gap.length() / maxf(0.5, speed))
	# And half a step of gravity more: a flight falls by its speed at the end of each step.
	return gap / t + Vector3.UP * 0.5 * Flight.GRAVITY * (t + Flight.STEP)


## `at`, or the nearest point to it on the floor: a hand held out over a wall throws from this
## side of it.
static func _onto(floor: Array, at: Vector3) -> Vector3:
	if floor.is_empty():
		return at
	var flat := Vector2(at.x, at.z)
	var best := flat
	var best_d := INF
	for r: Rect2 in floor:
		var inner := r.grow(-0.02)
		var c := Vector2(clampf(flat.x, inner.position.x, inner.end.x), clampf(flat.y, inner.position.y, inner.end.y))
		var d := c.distance_to(flat)
		if d < best_d:
			best_d = d
			best = c
	return Vector3(best.x, at.y, best.y)


## Put `item` on a head here or take it off (`on`), and say so (`ItemPlacing.wear`).
func wear(item: Item, on: bool) -> void: placing.wear(item, on)


## Put `item` in pocket `slot` here, or out of it into the hand (-1), and say so (`ItemPlacing.pocket`).
func pocket(item: Item, slot: int) -> void: placing.pocket(item, slot)


## Send `item` home from a hand here, and say so. "Home" for a personal copy is nowhere at all (`retire`): it is gone, not sent to a shelf spot two people's copies would have to share (`ItemPlacing.send_home`).
func send_home(item: Item) -> void: placing.send_home(item)


## Put `item` down along `aim` (world space): where the aim meets the floor within reach, or at the aimer's feet when it does not. Home if neither is somewhere it can lie. A made item let go within SLOT_REACH of a slot, or aimed at a free one, goes into it instead (`slot_item`) (`ItemPlacing.put_down`).
func put_down(item: Item, aim: Transform3D) -> void: placing.put_down(item, aim)




## How high the floor is at `at` (this node's frame) (`ItemPlacing.ground`).
func ground(at: Vector2) -> float: return placing.ground(at)


## Whether something flying at `p` (this node's frame) has hit something: a wall, which is the edge of the floor, or anything standing on the floor -- the venue's solids, the gear -- below its top. For the radio plane (RcPlaneItem), which flies where it is steered (`ItemPlacing.blocked`).
func blocked(p: Vector3) -> bool: return placing.blocked(p)



