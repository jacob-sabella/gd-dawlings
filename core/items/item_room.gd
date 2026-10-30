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
## (docs/spatial_loop.md part two, slice 34) is after the shelf's: its home is the desk's left wing,
## not the shelf. Then the hand drums (HandDrum, slice 40), fixed kinds that stand in their ring on
## the drum riser and never on the shelf: where a venue has no ring (the Rig Roulette room, AR) they
## are put away (`stand`), neither seen nor struck. Then the venue's instrument's bars
## (VenueInstrument.Bar, slice 42), `venue1` to `venue8`, fixed where the venue's set stands them and
## put away past the set's count or where the venue has none. Last is the drum pads' kit (KitItem,
## slice 41), fixed on the console's front rail wherever there is a console, AR too.
const KINDS: Array[StringName] = [&"duck", &"ball", &"plane", &"mic", &"headphones", &"glasses", &"tablet", &"shaker",
		&"tambourine", &"keytar", &"chips", &"cards", &"dart1", &"dart2", &"dart3",
		&"cradle", &"yoyo", &"toy", &"rcplane", &"bell1", &"bell2", &"bell3", &"bell4", &"miniature",
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
const PERSONAL_KINDS: Array[StringName] = [&"mic", &"headphones", &"glasses", &"tablet", &"keytar"]

## The kinds that exist only once somebody makes one while playing (docs/spatial_loop.md part two,
## slice 23): never on the shelf (not KINDS), minted by the host (`mint`) under the next free id in
## the shape `kind_of` reads, `cassette1`, `cassette2`. What a made item carries is not room state:
## its row ({id: [kind, maker, bytes]}, `made`) is sent once on a message of its own and to each
## guest as it joins, and the room names only its id (`made_ids`), so a put-down never resends a
## clip. Chord bricks (slice 31) are made too, from the fifths wheel: `brick1`, `brick2`.
const MADE_KINDS: Array[StringName] = [&"cassette", &"brick"]
## What a made item may carry, packed (var_to_bytes): at most this much one item, this much the
## whole room, and this many items. Past any of them a mint is refused, and says which.
const MADE_BYTES := 256 * 1024
const MADE_TOTAL := 4 * 1024 * 1024
const MADE_MOST := 64
## How near a free slot (`holders`) a made item has to be let go to go into it (m).
const SLOT_REACH := 0.08
## The holders that swallow what goes in them (`unmake`, on the host): the cassette rack's BIN and
## the chord ledge's (slice 31).
const BINS: Array[StringName] = [&"bin", &"ledge_bin"]
## The holders that hold a row in order (slice 31: the chord ledge, whose slots' order is a
## progression): a made item let go near one goes into the first free slot after what is in it
## (`next_in_order`), unless it is let go within SLOT_EXACT of a free slot, which takes it, or it
## is a brick let go by, or aimed back at, the free slot it was taken from (ChordBrick.from_ledge),
## which it goes back into: taken out to be turned to another length, it keeps its place.
const IN_ORDER: Array[StringName] = [&"ledge"]
const SLOT_EXACT := 0.03
## What each holder takes, by kind, and what to call them when it refuses another: the rack and the
## platter and the grain cloud's bowl cassettes, the ledge chord bricks. A holder not here (a bin)
## takes any made item.
const HOLDS := {&"rack": [&"cassette"], &"platter": [&"cassette"], &"ledge": [&"brick"], &"bowl": [&"cassette"]}
const HOLDS_SAID := {&"cassette": "cassettes", &"brick": "chord bricks"}

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
## spatial_loop.md part two, slice 24): for the studio to paste it, or ask the host to. A chord
## brick's press on a section block (slice 31) names ChordBrick.SECTION and the section's start.
signal paste_pressed(item: Item, track: int, seconds: float)
## A chord brick's length was nudged here (ChordBrick.resized, slice 31): for the room's `bricks`
## row, the host's at once and a guest's asked.
signal resized(item: Item, bars: int)

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
		&"shaker":
			return ShakerItem.new()
		&"tambourine":
			return TambourineItem.new()
		&"keytar":
			return KeytarItem.new()
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
		&"bell1":
			return HandbellItem.new(1)
		&"bell2":
			return HandbellItem.new(2)
		&"bell3":
			return HandbellItem.new(3)
		&"bell4":
			return HandbellItem.new(4)
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
		&"brick":
			return ChordBrick.new()
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
## all -- the darts are "dart1".."dart3" and the handbells "bell1".."bell4", and `make` answers to
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
## ("clip:<track>:<item index>", CassetteItem.data_of the song as it is now), or a chord brick of a
## chord in a key ("chord:<key>:<chord>" or "ledge:<key>:<chord>", ChordBrick.data_from). Empty
## where there is nothing there to make one of. The host packs it from its own state: a guest asks
## with `from`, never with the data.
static func made_data(kind: StringName, from: String) -> Dictionary:
	match kind:
		&"cassette":
			var part := from.split(":")
			if part.size() == 3 and part[0] == "clip" and part[1].is_valid_int() and part[2].is_valid_int():
				return CassetteItem.data_of(DAW.state, int(part[1]), int(part[2]))
		&"brick":
			return ChordBrick.data_from(from)
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
	if item is ChordBrick:
		(item as ChordBrick).resized.connect(func(bars: int) -> void: resized.emit(item, bars))
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


## On the host: a made item of `kind` carrying `data`, made by `maker` (a peer id), under the next
## free id (`cassette1`, ...), its row kept in `made` and said (`minted`), and spawned at its home.
## Null, and `mint_refusal` saying why, past MADE_MOST, MADE_TOTAL or MADE_BYTES, or for no data.
func mint(kind: StringName, data: Dictionary, maker := 1) -> Item:
	mint_refusal = ""
	if not (kind in MADE_KINDS) or data.is_empty():
		mint_refusal = "There is nothing there to make a %s of." % kind
		return null
	var bytes := var_to_bytes(data)
	mint_refusal = made_refusal(made, bytes.size())
	if not mint_refusal.is_empty():
		return null
	var n := int(_made_after.get(kind, 0)) + 1
	while items.has(StringName("%s%d" % [kind, n])) or made.has(StringName("%s%d" % [kind, n])):
		n += 1
	_made_after[kind] = n
	var id := StringName("%s%d" % [kind, n])
	made[id] = [kind, maker, bytes]
	var item := _make_real(id)
	minted.emit(item)
	return item


## Made item `id` real here, from its row in `made`: spawned at its home and given what it carries.
## Idempotent, as `spawn` is. Null without a row, or with one that does not read.
func _make_real(id: StringName) -> Item:
	if items.has(id):
		return items[id]
	var row: Variant = made.get(id)
	if not (row is Array) or (row as Array).size() != 3 or not ((row as Array)[2] is PackedByteArray):
		return null
	var data: Variant = bytes_to_var((row as Array)[2])
	if not (data is Dictionary):
		return null
	var kind := kind_of(id)
	var n := int(String(id).trim_prefix(String(kind)))
	_made_after[kind] = maxi(int(_made_after.get(kind, 0)), n)
	var item := spawn(kind, id, made_home.call(kind, n) if made_home.is_valid() else Transform3D.IDENTITY)
	if item != null and item.has_method("read"):
		item.read(data)
	return item


## The made items the host's room names (`made_ids`), here: each one this machine has the row of
## and has not met made real, and each one here the room no longer names gone. Its row, if any,
## stays until the host says it is gone (`forget_made`): a row can arrive before the room names it.
func apply_made(ids: Array) -> void:
	for id in ids:
		_make_real(StringName(id))
	for id in made_ids():
		if not ids.has(id) and not ids.has(String(id)):
			despawn(id)


## Made item `id` gone for good, on the host: out of the room and out of `made`, and said.
func unmake(id: StringName) -> void:
	if not is_made(id):
		return
	despawn(id)
	made.erase(id)
	unmade.emit(id)


## The host said made item `id` is gone: here too, row and all.
func forget_made(id: StringName) -> void:
	despawn(id)
	made.erase(id)


# --- slots (docs/spatial_loop.md part two, slice 23) -------------------------------------------

## Holder `holder`'s slots are `slots` now (this node's frame): what is in them is laid there again.
func set_holder(holder: StringName, slots: Array[Transform3D]) -> void:
	holders[holder] = slots
	for id in items:
		var item: Item = items[id]
		if item.slot_in == holder and item.slot_n >= 0 and item.slot_n < slots.size():
			_lay_in_slot(item, holder, item.slot_n)


## Whatever is in `holder`'s slot `n`, or null. A bin's is never taken: it swallows.
func in_slot(holder: StringName, n: int) -> Item:
	if is_bin(holder):
		return null
	for id in items:
		var item: Item = items[id]
		if item.slot_in == holder and item.slot_n == n and item.state == Item.State.LOOSE:
			return item
	return null


## Why `item` may not go into `holder`'s slot `n`, or "".
func slot_refusal(item: Item, holder: StringName, n: int) -> String:
	var why := kind_refusal(item, holder)
	if not why.is_empty():
		return why
	var slots: Array = holders.get(holder, [])
	if n < 0 or n >= slots.size():
		return "There is no slot %d there." % (n + 1)
	var there := in_slot(holder, n)
	if there != null and there != item:
		return "That slot has %s in it." % there.item_title().to_lower()
	return ""


## Why `item` may not go into `holder` at all, whichever slot, or "": it was not made while
## playing, or it is not of a kind the holder takes (HOLDS).
func kind_refusal(item: Item, holder: StringName) -> String:
	if not is_made(item.id):
		return "Only things made while playing go on the %s." % holder
	var kind := kind_of(item.id)
	if HOLDS.has(holder) and not kind in HOLDS[holder]:
		return "Only %s go on the %s." % [" and ".join(PackedStringArray((HOLDS[holder] as Array).map(
				func(k): return HOLDS_SAID.get(k, String(k))))), holder]
	return ""


## The room's word: `item` into `holder`'s slot `n`, if it may go there. The bin, on the host,
## retires it. Whether it went.
func slot(item: Item, holder: StringName, n: int) -> bool:
	if not slot_refusal(item, holder, n).is_empty():
		return false
	if is_bin(holder) and (not authority.is_valid() or authority.call()):
		unmake(item.id)
		return true
	_lay_in_slot(item, holder, n)
	return true


## A hand here put `item` into `holder`'s slot `n`: done at once, and said; or refused, and told.
func slot_item(item: Item, holder: StringName, n: int) -> bool:
	var why := slot_refusal(item, holder, n)
	if not why.is_empty():
		told.emit(why)
		return false
	var id := item.id
	slot(item, holder, n)
	asked.emit(&"slot_item", [id, holder, n])
	return true


## `item` into `holder`'s slot `n` (`slot_item`), or, with no slot free there (-1), told so; it stays
## in the hand.
func _slot_or_tell(item: Item, holder: StringName, n: int) -> void:
	if n < 0:
		told.emit("The %s is full: bin one first." % holder)
		return
	slot_item(item, holder, n)


func _lay_in_slot(item: Item, holder: StringName, n: int) -> void:
	var slots: Array = holders.get(holder, [])
	if n < 0 or n >= slots.size():
		return
	item.stick_at(slots[n])
	item.slot_in = holder
	item.slot_n = n


## The first free slot of `holder` after everything in it (IN_ORDER: the end of the ledge's row),
## or, with its last slot taken, the first free one at all; -1 when it is full.
func next_in_order(holder: StringName) -> int:
	var slots: Array = holders.get(holder, [])
	var last := -1
	for n in slots.size():
		if in_slot(holder, n) != null:
			last = n
	for n in range(last + 1, slots.size()):
		if in_slot(holder, n) == null:
			return n
	for n in slots.size():
		if in_slot(holder, n) == null:
			return n
	return -1


## Where `item`, let go at or aimed at `holder`'s slot `n`, goes: that slot, but for a holder kept
## in order (IN_ORDER), where it is the first free slot after the row unless `at` (this node's
## frame, null when aimed) is within SLOT_EXACT of `n` and `n` is free, or `n` is the free slot it
## was taken from. -1 for nowhere.
func _slot_for(item: Item, holder: StringName, n: int, at: Variant) -> int:
	if not (holder in IN_ORDER):
		return n
	var slots: Array = holders.get(holder, [])
	if item is ChordBrick and n >= 0 and n == (item as ChordBrick).from_ledge and in_slot(holder, n) == null:
		return n
	if at is Vector3 and n >= 0 and n < slots.size() and in_slot(holder, n) == null \
			and ((slots[n] as Transform3D) * Vector3(0, ChordBrick.SIZE.y * 0.5, 0)).distance_to(at) <= SLOT_EXACT:
		return n
	var there := in_slot(holder, n) if n >= 0 else null
	if there == item:
		return n
	return next_in_order(holder)


## The slot nearest `at` (global) within `reach`, [holder, n], taken or not; [] for none.
func slot_near(at: Vector3, reach := SLOT_REACH) -> Array:
	var best: Array = []
	var nearest := reach
	var local := global_transform.affine_inverse() * at if is_inside_tree() else at
	for holder in holders:
		var slots: Array = holders[holder]
		for n in slots.size():
			var d := ((slots[n] as Transform3D) * Vector3(0, CassetteItem.SIZE.y * 0.5, 0)).distance_to(local)
			if d < nearest:
				nearest = d
				best = [holder, n]
	return best


## The free slot nearest the line `aim` (global) points along, within PUT_REACH, and within
## SLOT_REACH and a half of it: [holder, n], or [] for none.
func free_slot_along(item: Item, aim: Transform3D) -> Array:
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var local := inv * aim
	var origin := local.origin
	var toward := -local.basis.z.normalized()
	var best: Array = []
	var nearest := SLOT_REACH * 1.5
	for holder in holders:
		var slots: Array = holders[holder]
		for n in slots.size():
			var at := (slots[n] as Transform3D) * Vector3(0, CassetteItem.SIZE.y * 0.5, 0)
			var along := (at - origin).dot(toward)
			if along <= 0.0 or along > PUT_REACH:
				continue
			var off := (origin + toward * along).distance_to(at)
			# A holder kept in order takes it at the end of its row, wherever along it is aimed:
			# taken or not, the slot aimed at only says which holder. Still only what it holds.
			var fits := kind_refusal(item, holder).is_empty() if holder in IN_ORDER \
					else slot_refusal(item, holder, n).is_empty()
			if off < nearest and fits:
				nearest = off
				best = [holder, n]
	return best


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
				if item.slot_in == &"" and not _can_lie(at):
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


## Every item that is not at home, as the room has it: {id: [x, y, z, yaw]} for one lying on
## the floor (and "stuck" and the quaternion it is turned by after, for one stuck in a board),
## {id: []} for one in a hand, {id: [true]} for one on a head, {id: ["pocket", n]} for one in a
## pocket, {id: ["slot", holder, n]} for one in a slot (`holders`). One left out is on the
## shelf, or, made, at its home (`made_home`). What a made item carries is never here.
func state() -> Dictionary:
	var out := {}
	for id in items:
		var item: Item = items[id]
		match item.state:
			Item.State.LOOSE:
				# In a slot: which holder's, and which slot; where that is, the holder's.
				if item.slot_in != &"":
					out[id] = ["slot", String(item.slot_in), item.slot_n]
					continue
				var at := item.resting.origin
				var entry := [at.x, at.y, at.z, item.resting.basis.get_euler().y]
				# In the air: how it was thrown too, for a copy that has not flown it to fly.
				if item.is_flying() and item.launched_with.size() == 3:
					entry.append(item.throws)
					entry.append_array(item.launched_with)
				elif item.is_stuck():
					# Not lying flat -- stuck in a board: how it is turned, whole.
					var q := item.resting.basis.get_rotation_quaternion()
					entry.append_array(["stuck", q.x, q.y, q.z, q.w])
				out[id] = entry
			Item.State.HELD:
				if item.pocket >= 0:
					out[id] = ["pocket", item.pocket]
				else:
					out[id] = [true] if item.on_head else []
	return out


## Make the items what the host's room says (`state`). Not one a hand here has, nor one this
## guest has put somewhere and not heard back about (`pending`, by id); nor one the room says is
## in a hand, which the holds put there (Presence). One the room has on the floor lands there;
## one it leaves out goes home -- unless it is a personal copy nobody here has met yet (spawned
## by another peer's pick-up, or already out there when this one joined), which is made real
## here too, the same way a Tour spill reaches a guest that was not there when it fell; or one
## nobody holds any more, which is retired rather than sent home.
func apply(room_items: Dictionary, pending: Dictionary = {}) -> void:
	for id in room_items:
		if items.has(id) or not is_personal_copy(id):
			continue
		var kind := kind_of(id)
		var item := spawn(kind, id, items[kind].home if items.has(kind) else Transform3D.IDENTITY)
		if item != null:
			item.bound_to = peer_of(id)
			personal_taken.emit(item)
	var gone: Array[StringName] = []
	for id in items:
		var item: Item = items[id]
		# A fixed instrument never leaves its station, whatever a room says.
		if pending.has(id) or item.carried_by != null or item.fixed:
			continue
		var entry: Variant = room_items.get(id)
		if entry == null:
			if is_personal_copy(id):
				gone.append(id)
			elif item.state != Item.State.HOME:
				item.go_home()
			continue
		var spot := entry as Array
		# On somebody's head: that it is worn is the room's; whose it is, the holds'.
		if spot.size() == 1:
			item.set_pocket(-1)
			item.set_worn(bool(spot[0]))
			continue
		# In a slot: laid there, unless it already is.
		if spot.size() == 3 and spot[0] is String and spot[0] == "slot":
			var holder := StringName(str(spot[1]))
			if item.slot_in != holder or item.slot_n != int(spot[2]) or item.state != Item.State.LOOSE:
				_lay_in_slot(item, holder, int(spot[2]))
			continue
		# In somebody's pocket: which, the room's; whose, the holds'.
		if spot.size() == 2 and spot[0] is String and spot[0] == "pocket":
			item.set_worn(false)
			item.set_pocket(int(spot[1]))
			continue
		if spot.size() < 4:
			if spot.is_empty() and item.state == Item.State.HELD:
				item.set_worn(false)
				item.set_pocket(-1)
			continue
		var at := Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
		# A throw this copy has not flown: flown here from the same launch, to where the room
		# says it lands.
		if spot.size() == 8 and int(spot[4]) > item.throws:
			item.throws = int(spot[4]) - 1
			fly(item, spot[5], spot[6], spot[7])
			if not item.resting.origin.is_equal_approx(at):
				item.resting = Transform3D(Basis(Vector3.UP, float(spot[3])), at)
			continue
		if item.state == Item.State.LOOSE and item.resting.origin.is_equal_approx(at):
			continue
		if spot.size() == 9 and spot[4] is String:
			item.stick_at(Transform3D(Basis(Quaternion(float(spot[5]), float(spot[6]), float(spot[7]),
					float(spot[8])).normalized()), at))
			continue
		item.lay_down(at, float(spot[3]))
	for id in gone:
		despawn(id)


## Lay `item` on the floor at `at` (this node's frame), turned to `yaw`, if it can lie there;
## home if it cannot. True if it lies there. The host's answer to a put-down, and a hand's own.
## A personal copy never lies anywhere: putting it down retires it (`retire`), same as sending it
## home, since there is no floor spot that would mean anything once two people can each have one.
func lay(item: Item, at: Vector2, yaw: float) -> bool:
	# A fixed instrument lies nowhere but its station.
	if item.fixed:
		item.snap_home()
		return false
	if is_personal_copy(item.id):
		retire(item)
		return false
	if not _can_lie(at):
		retire(item)
		return false
	var y: float = ground_at.call(at) if ground_at.is_valid() else 0.0
	item.lay_down(Vector3(at.x, y, at.y), yaw)
	return true


## Throw `item` from a hand here: from `origin` at `velocity` (world space), spinning at `spin`
## (rad/s, world axes). Flown at once, and said, for the host to fly too.
func throw(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3) -> void:
	if item.fixed:
		return
	var into := global_transform.affine_inverse()
	var from := into * origin
	var v := into.basis * velocity
	var w := into.basis * spin
	fly(item, from, v, w, int(local_peer.call()) if local_peer.is_valid() else 1)
	asked.emit(&"throw_item", [item.id, from, v, w])


## Fly `item` from `origin` at `velocity`, spinning at `spin` -- all in this node's frame -- the
## same flight on every machine. `thrown_by` is whoever's throw this is (their peer id, 1 for
## the host): carried only for a registered target (the Tour case) to tell a host's own throw
## from a guest's; nothing else here reads it. Where it comes down, it stays if it can lie
## there; if not, it goes home when it has.
func fly(item: Item, origin: Vector3, velocity: Vector3, spin: Vector3, thrown_by: int = 1) -> void:
	if item.fixed:
		return
	var floor: Array = floor_rects.call() if floor_rects.is_valid() else []
	var start := _onto(floor, origin)
	var how := item.flies()
	# Facing the way it was thrown, not the way it sat in the hand: the hand is not the same on
	# every machine, and the throw has to be.
	var facing := Quaternion(Basis(Vector3.UP, atan2(-velocity.x, -velocity.z)))
	var f := Flight.fly(start, velocity, spin, facing, floor,
			solids.call() if solids.is_valid() else [], how.get("bounce", 0.35), how.get("roll", 3.0),
			how.get("drag", 0.08), how.get("wing", {}), boards, how.get("point", 0.0),
			hoops if how.has("radius") else [], how.get("radius", 0.0))
	item.thrown_by = thrown_by
	# A personal copy never stays where a throw lands, same as a put-down (`lay`): there is no
	# floor spot that would mean anything once two people can each have their own, so it always
	# goes home after -- which `retire` turns into "gone" rather than "back on the shelf".
	var stays := (f.stuck or _can_lie(Vector2(f.rest.x, f.rest.z))) and not is_personal_copy(item.id)
	item.launch(f, [origin, velocity, spin], stays)


## Something in flight hit a hoop's rim or board (Flight.RIM, Flight.BOARD) at `at` (world
## space): the nearest hoop sounds it. Whether there was one to.
func hoop_struck(on: int, speed: float, at: Vector3) -> bool:
	var hoop := _nearest_hoop(at)
	if hoop == null:
		return false
	hoop.struck(on == Flight.RIM, speed)
	return true


## `item` has just dropped through hoop `index`, touching nothing on the way if `clean`.
func basket(item: Item, index: int, clean: bool) -> void:
	if index < 0 or index >= hoops.size():
		return
	var hoop = hoops[index].get("node")
	if hoop is Hoop and is_instance_valid(hoop):
		(hoop as Hoop).sink(clean, item)


## Something in flight hit furniture registered in `targets` at `at` (world space), going at
## `speed`, thrown by `thrown_by` (its peer id, item.gd's `thrown_by`): the nearest one within
## its own radius takes it (`struck`, the same duck-typed call `hoop_struck` makes on a Hoop).
## Whether there was one close enough to.
func target_struck(speed: float, at: Vector3, thrown_by: int) -> bool:
	var best: Node = null
	var nearest := INF
	for t: Dictionary in targets:
		var node = t.get("node")
		if not is_instance_valid(node):
			continue
		var d := (node as Node3D).global_position.distance_to(at)
		if d < float(t.get("radius", 0.3)) and d < nearest:
			nearest = d
			best = node
	if best == null:
		return false
	best.struck(speed, thrown_by)
	return true


func _nearest_hoop(at: Vector3) -> Hoop:
	var best: Hoop = null
	var nearest := INF
	for h: Dictionary in hoops:
		var node = h.get("node")
		if not (node is Hoop) or not is_instance_valid(node):
			continue
		var d := (node as Hoop).global_position.distance_to(at)
		if d < nearest:
			nearest = d
			best = node
	return best


## What `aim` (world space) is aimed at, for a thrown thing that is aimed (Item.aim_scatter):
## where it meets a board in front of it, or a throw's length along it. World space.
func aim_point(aim: Transform3D) -> Vector3:
	var origin := aim.origin
	var toward := -aim.basis.z.normalized()
	for b: Dictionary in boards:
		var frame: Transform3D = global_transform * (b["at"] as Transform3D)
		var normal := frame.basis.z.normalized()
		var facing := toward.dot(normal)
		if facing > -0.05:
			continue
		var along := (frame.origin - origin).dot(normal) / facing
		if along <= 0.0 or along > AIM_REACH:
			continue
		var hit := origin + toward * along
		var local := frame.affine_inverse() * hit
		if Vector2(local.x, local.y).length() < float(b.get("radius", b.get("half", 0.0))) * 1.6:
			return hit
	return origin + toward * AIM_LENGTH


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


## Put `item` on a head here or take it off (`on`), and say so.
func wear(item: Item, on: bool) -> void:
	item.set_worn(on)
	asked.emit(&"wear_item", [item.id, on])


## Put `item` in pocket `slot` here, or out of it into the hand (-1), and say so.
func pocket(item: Item, slot: int) -> void:
	if item.fixed:
		return
	item.set_pocket(slot)
	asked.emit(&"pocket_item", [item.id, slot])


## Send `item` home from a hand here, and say so. "Home" for a personal copy is nowhere at all
## (`retire`): it is gone, not sent to a shelf spot two people's copies would have to share.
func send_home(item: Item) -> void:
	var id := item.id
	retire(item)
	asked.emit(&"home_item", [id])


## Put `item` down along `aim` (world space): where the aim meets the floor within reach, or at
## the aimer's feet when it does not. Home if neither is somewhere it can lie. A made item let go
## within SLOT_REACH of a slot, or aimed at a free one, goes into it instead (`slot_item`); near a
## holder kept in order (the chord ledge), at the end of its row (`_slot_for`).
func put_down(item: Item, aim: Transform3D) -> void:
	if item.fixed:
		return
	# A made item let go by a slot goes into it -- or, the slot taken, stays in the hand and says
	# so -- and one aimed at a free slot within reach goes there.
	if is_made(item.id) and not holders.is_empty():
		var middle := item.middle()
		var near := slot_near(middle)
		if not near.is_empty():
			var local: Vector3 = global_transform.affine_inverse() * middle if is_inside_tree() else middle
			_slot_or_tell(item, near[0], _slot_for(item, near[0], near[1], local))
			return
		var along := free_slot_along(item, aim)
		if not along.is_empty():
			_slot_or_tell(item, along[0], _slot_for(item, along[0], along[1], null))
			return
	var local := global_transform.affine_inverse() * aim
	var origin := local.origin
	var toward := -local.basis.z.normalized()
	var spot := Vector2.INF
	if toward.y < -0.02:
		var along := -origin.y / toward.y
		if along > 0.0 and along < PUT_REACH:
			var hit := origin + toward * along
			spot = Vector2(hit.x, hit.z)
			# Aimed at the floor through the gear: it was aimed at the gear.
			if _through_gear(origin, hit):
				item.go_home()
				asked.emit(&"home_item", [item.id])
				return
	if spot == Vector2.INF:
		var ahead := Vector2(toward.x, toward.z)
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector2(0, -1)
		spot = Vector2(origin.x, origin.z) + ahead * AT_FEET
	# Facing the way you were looking, as if you had set it down in front of you.
	var yaw := atan2(-toward.x, -toward.z)
	if lay(item, spot, yaw):
		asked.emit(&"put_item", [item.id, spot.x, spot.y, yaw])
	else:
		asked.emit(&"home_item", [item.id])


## Whether the line from `from` to `to` passes through any gear below its top: a hand reaching
## past a console puts the thing on the console, not on the floor behind it.
func _through_gear(from: Vector3, to: Vector3) -> bool:
	if not gear.is_valid():
		return false
	var prints: Array = gear.call()
	var n := maxi(1, int(from.distance_to(to) / 0.05))
	for i in n + 1:
		var p := from.lerp(to, float(i) / n)
		if p.y >= Walker.SOLID_HEIGHT:
			continue
		for f: Dictionary in prints:
			if Walker._gap(f, Vector2(p.x, p.z)) <= 0.0:
				return true
	return false


## How high the floor is at `at` (this node's frame).
func ground(at: Vector2) -> float:
	return ground_at.call(at) if ground_at.is_valid() else 0.0


## Whether something flying at `p` (this node's frame) has hit something: a wall, which is the
## edge of the floor, or anything standing on the floor -- the venue's solids, the gear -- below
## its top. For the radio plane (RcPlaneItem), which flies where it is steered.
func blocked(p: Vector3) -> bool:
	var at := Vector2(p.x, p.z)
	var floor: Array = floor_rects.call() if floor_rects.is_valid() else []
	if not floor.is_empty() and not Flight._on_floor(floor, at):
		return true
	var standing: Array = solids.call() if solids.is_valid() else []
	for f: Dictionary in standing:
		if p.y < float(f.get("top", Walker.SOLID_HEIGHT)) and Walker._gap(f, at) <= 0.0:
			return true
	if gear.is_valid() and p.y < Walker.SOLID_HEIGHT:
		for f: Dictionary in gear.call():
			if Walker._gap(f, at) <= 0.0:
				return true
	return false


func _can_lie(at: Vector2) -> bool:
	if fits.is_valid():
		return fits.call(at)
	return true

