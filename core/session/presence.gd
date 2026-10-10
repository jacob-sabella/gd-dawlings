class_name Presence
extends Node3D

## Everyone else in the room: where they are, what they are pointing at, what they are holding.
##
## Two directions, one node. OUT: this participant's head and pointer, published to the session
## at PUBLISH_HZ, and every grab a local hand makes, claimed with the host. IN: an avatar for
## each other participant, a beam from them to whatever they are pointing at, their colour round
## anything they hold -- and that control refused to anyone else's hand until they let go.
##
## Lives beside the surfaces and never inside one. The console does not know anyone else is in
## the room, which is the presentation rule (docs/architecture.md); it learns that a fader is
## taken the same way it learns anything, by its affordance saying no.
##
## Pointers travel by CONTROL, not by position. Each participant has the gear where they put it,
## so a hit point in the sender's world is a patch of empty floor in mine. "Kick volume, 2cm up
## the travel" lands on my kick fader wherever my console is -- which is the one they mean.

const PUBLISH_HZ := 20.0
## How quickly an avatar catches up with the newest pose. Poses arrive at 20Hz and frames at 60
## or 90; drawn raw, a head steps three times a second's worth of jitter across a headset.
## What is left of easing a ghost after the poses heard are played back (PoseTrail): only enough
## to take the corners off them.
const FOLLOW_RATE := 40.0
## Each ghost's poses heard, by peer.
var _trails := {}
## When each one's newest pose was heard, to know a new one from the same one seen again.
var _heard_at := {}
## Closer than this to my own eye and an avatar is hidden: two desktop participants both spawn
## at the mix position, and the inside of somebody's head is not a view of the desk.
const PERSONAL_SPACE := 0.6
## Silent this long and an avatar is drawn as away rather than as a person standing very still.
const STALE_MSEC := 3000

## Whose eyes this participant sees through: the desktop camera, or the headset.
var head_node: Node3D
## Session space. Poses go out relative to it and come back through it, so two headsets that
## each started somewhere different agree where a person is. See core/xr/room_anchor.gd.
var frame: Node3D

var _avatars: Dictionary = {}
## You, as others see you, at your own eye, on a layer only mirrors draw. Null with no display.
var reflection: Avatar = null
var _publish_clock := 0.0
var _by_key: Dictionary = {}
var _scan_msec := -100000
var _claimed: Array[ControlAffordance] = []
var _claim_clock := 0.0
## {interactor: key it has claimed}, so a release names what the grab claimed even if the
## control has been renamed in between -- a track renamed mid-drag.
var _my_claims: Dictionary = {}
## The room's items (docs/items_loop.md), set by the studio. Carrying one is a hold like a
## fader's, but for as long as it is carried rather than while a button is down.
var items: ItemRoom = null
## {interactor: keys of the items it carries and has put on a head, as claimed}.
var _carry_claims: Dictionary = {}
## {item id: peer whose hand it has been put in here}, so the holds are acted on when they
## change, not every time they are read.
var _item_holders: Dictionary = {}
## {peer: Transform3D}: where the item in their hand is, relative to their head, as last heard.
var _carry_at: Dictionary = {}


## Listening only while in the tree. A studio taken out of the scene -- the suite builds dozens --
## must not go on answering for a session it is no longer part of.
func _enter_tree() -> void:
	Session.roster_changed.connect(_sync_avatars)
	Session.holds_changed.connect(_apply_holds)
	Session.hold_refused.connect(_on_hold_refused)
	Session.role_changed.connect(_on_role_changed)
	Session.item_carried.connect(_on_item_carried)
	Session.item_flown.connect(_on_item_flown)
	Session.item_used.connect(_on_item_used)
	Session.item_hit.connect(_on_item_hit)
	Session.note_played.connect(_on_note_played)


func _exit_tree() -> void:
	Session.item_carried.disconnect(_on_item_carried)
	Session.item_flown.disconnect(_on_item_flown)
	Session.item_used.disconnect(_on_item_used)
	Session.item_hit.disconnect(_on_item_hit)
	Session.note_played.disconnect(_on_note_played)
	Session.roster_changed.disconnect(_sync_avatars)
	Session.holds_changed.disconnect(_apply_holds)
	Session.hold_refused.disconnect(_on_hold_refused)
	Session.role_changed.disconnect(_on_role_changed)


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		_make_reflection()
	_sync_avatars()


func _make_reflection() -> void:
	reflection = Avatar.new()
	reflection.name = "Reflection"
	add_child(reflection)
	reflection.only_in_mirrors()


func _physics_process(delta: float) -> void:
	_hook_interactors()
	claim_carries()
	_publish_clock += delta
	if _publish_clock >= 1.0 / PUBLISH_HZ:
		_publish_clock = 0.0
		_publish()
	# Controls are rebuilt under a hold -- a bank moves, a rack page turns -- and a new fader
	# with the held name has to be told it is taken just as the old one was.
	if not Session.holds.is_empty():
		_claim_clock += delta
		if _claim_clock > 0.5:
			_claim_clock = 0.0
			_apply_holds()


func _process(delta: float) -> void:
	var eye := head_node.global_position if head_node != null else Vector3(0, 1e6, 0)
	if reflection != null and head_node != null:
		reflection.snap(head_node.global_transform)
		var mine := _my_pointing()
		reflection.point_at(mine["control"], mine["point"], mine["holding"])
		var carried := _my_carried()
		reflection.carry(carried.id if carried != null else &"")
		if carried != null and carried.carried_by != null:
			reflection.carry_at = _carry_local(carried)
		# What is on my head is the real thing, on my mirror ghost's head, seen only in mirrors.
		var wearing := _my_worn()
		reflection.wear_item(wearing != null)
		if wearing != null:
			wearing.worn_at = reflection.worn_pose
		# And what is in my pockets, on my mirror ghost's hips and back, seen only in mirrors.
		for item in _my_pocketed():
			if not item.pocket_at.is_valid():
				item.pocket_at = func(slot: int) -> Transform3D: return reflection.pocket_pose(slot, item)
	var weight := 1.0 - exp(-delta * FOLLOW_RATE)
	var now := PoseTrail.now()
	for id in _avatars:
		var avatar: Avatar = _avatars[id]
		var p = Session.participants.get(id)
		if p == null:
			continue
		# Nobody is drawn until they have been heard from: a participant with no pose yet --
		# or a headless host that will never send one -- would stand at the session origin.
		avatar.visible = p.heard_msec > 0
		if not avatar.visible:
			continue
		# Played back a moment behind, between the poses heard, rather than chased: see PoseTrail.
		var trail: PoseTrail = _trails.get(id)
		if trail == null:
			trail = PoseTrail.new()
			_trails[id] = trail
		if _heard_at.get(id, -1) != p.heard_msec:
			_heard_at[id] = p.heard_msec
			trail.push(now, p.head)
		var target := _from_session(trail.sample(now))
		if not avatar.placed:
			avatar.snap(target)
		avatar.follow(target, weight)
		avatar.set_close(avatar.head_position().distance_to(eye) < PERSONAL_SPACE)
		avatar.set_away(p.heard_msec > 0 and Time.get_ticks_msec() - p.heard_msec > STALE_MSEC)
		var held_key := _key_held_by(id)
		var key: String = held_key if not held_key.is_empty() else p.pointing_at
		var control := find_control(key)
		if control != null:
			avatar.point_at(control, control.global_transform * p.pointing_local, not held_key.is_empty())
		else:
			avatar.point_at(null, Vector3.ZERO, false)
		var theirs := _item_held_by(id)
		avatar.carry(theirs.id if theirs != null else &"", false)
		avatar.wear_item(_item_worn_by(id) != null)
		if _carry_at.has(id):
			avatar.carry_at = _carry_at[id]
		avatar.set_caption(_caption(p, held_key if theirs == null else theirs.network_key()))


# --- out ----------------------------------------------------------------------------------

func _publish() -> void:
	# A headless process is a host in a rack: there is nobody at it, and its "head" is a camera
	# no one is looking through, parked at the mix position with a cursor stuck in a corner.
	# Published, it stood an avatar in the middle of everybody's desk pointing at the timeline.
	if head_node == null or DisplayServer.get_name() == "headless":
		return
	var key := ""
	var local := Vector3.ZERO
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor == null or not interactor.is_inside_tree():
			continue
		var control: ControlAffordance = interactor.held if interactor.held != null else interactor.hovered
		if control == null or not is_instance_valid(control) or control.personal():
			continue
		key = control.network_key()
		local = control.to_local(interactor.hover_point) if interactor.hovered == control \
				else Vector3.ZERO
		break
	Session.publish_presence(_to_session(head_node.global_transform), key, local)
	var carried := _my_carried()
	if carried != null and carried.carried_by != null:
		Session.send_carry(carried.id, _carry_local(carried))
	# The radio plane, flown from here: in my hand or my pocket, wherever it has got to.
	var flier := items.items.get(&"rcplane") as RcPlaneItem if items != null else null
	if flier != null and flier.carried_by != null and flier.away():
		Session.send_flier(flier.id, _to_session(flier.plane_pose()), flier.mode)


## Where the item in my hand is, relative to my head: what everyone else puts in my ghost's glove.
func _carry_local(item: Item) -> Transform3D:
	var hand := item.carried_by.carry_pose() * item.held_pose()
	return head_node.global_transform.affine_inverse() * hand if head_node != null else hand


## What my own hand is on, for the ghost the mirrors show: {control, point, holding}.
func _my_pointing() -> Dictionary:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor == null or not interactor.is_inside_tree():
			continue
		var control: ControlAffordance = interactor.held if interactor.held != null else interactor.hovered
		if control == null or not is_instance_valid(control):
			continue
		return {"control": control, "point": interactor.hover_point, "holding": interactor.held == control}
	return {"control": null, "point": Vector3.ZERO, "holding": false}


## What my own hand is carrying, or null: for the ghost the mirrors show, and for everyone else.
func _my_worn() -> Item:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and is_instance_valid(interactor.worn):
			return interactor.worn
	return null


func _my_pocketed() -> Array[Item]:
	var out: Array[Item] = []
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and interactor.pockets != null:
			for item in interactor.pockets.items():
				if not out.has(item):
					out.append(item)
	return out


func _my_carried() -> Item:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and is_instance_valid(interactor.carrying):
			return interactor.carrying
	return null


## Every hand here that has picked something up has it claimed with the host, and every hand
## that has let it go has let go of the claim -- however it came to be let go: put down, sent
## home, taken by the venue changing. Read off the hands rather than told by them, so no way
## of emptying a hand can leave a claim behind.
func claim_carries() -> void:
	# What every hand here has, all told: a thing moved from one hand to the other (out of a
	# pocket the other put it in) is let go of by neither.
	var everyone: Dictionary = {}
	var hands: Array[Interactor] = []
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor == null:
			continue
		hands.append(interactor)
		for key in _carried_by(interactor):
			everyone[key] = true
	for interactor in hands:
		# What is in the hand, what it has put on its person's head and in their pockets: all
		# still this hand's. Moving a thing from one to another changes nothing the host needs
		# to hear.
		var now := _carried_by(interactor)
		var was: Array = _carry_claims.get(interactor, [])
		if now == was:
			continue
		for key in was:
			if not now.has(key) and not everyone.has(key):
				Session.release_hold(key)
		for key in now:
			if not was.has(key):
				if is_instance_valid(interactor.carrying) and interactor.carrying.taken \
						and interactor.carrying.network_key() == key:
					Session.take_hold(key)
				else:
					Session.claim_hold(key)
		if now.is_empty():
			_carry_claims.erase(interactor)
		else:
			_carry_claims[interactor] = now
	for interactor in _carry_claims.keys():
		if not is_instance_valid(interactor):
			for key in _carry_claims[interactor]:
				Session.release_hold(key)
			_carry_claims.erase(interactor)


## The network keys of what `interactor` has: in it, on its person's head, in their pockets.
func _carried_by(interactor: Interactor) -> Array:
	var now: Array = []
	if is_instance_valid(interactor.carrying):
		now.append(interactor.carrying.network_key())
	if is_instance_valid(interactor.worn):
		now.append(interactor.worn.network_key())
	if interactor.pockets != null:
		for item in interactor.pockets.items():
			if item.carried_by == interactor:
				now.append(item.network_key())
	return now


func _hook_interactors() -> void:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor == null or interactor.grabbed.is_connected(_on_grabbed):
			continue
		interactor.grabbed.connect(_on_grabbed.bind(interactor))
		interactor.released.connect(_on_released.bind(interactor))


func _on_grabbed(control: ControlAffordance, interactor: Interactor) -> void:
	# An item's grab is a pick-up, over at once; carrying it is the hold (claim_carries).
	if control.personal() or control is Item:
		return
	var key := control.network_key()
	_my_claims[interactor] = key
	Session.claim_hold(key)


func _on_released(_control: ControlAffordance, interactor: Interactor) -> void:
	var key: String = _my_claims.get(interactor, "")
	_my_claims.erase(interactor)
	Session.release_hold(key)


## Somebody else's hand was there first. Ours opens, and whatever we did in the moment before
## the host's answer came back is overwritten by theirs as the mix replicates.
func _on_hold_refused(key: String, holder: int) -> void:
	for interactor in _my_claims.keys():
		if _my_claims[interactor] == key and is_instance_valid(interactor):
			_my_claims.erase(interactor)
			interactor.let_go()
	# Something picked up that somebody else had already: it leaves this hand for theirs.
	for interactor in _carry_claims.keys():
		if (_carry_claims[interactor] as Array).has(key) and is_instance_valid(interactor):
			_forget_carry(interactor, key)
			var hand := interactor as Interactor
			var item := hand.carrying
			if item != null and item.network_key() == key:
				hand.lose_carrying()
				_item_holders.erase(item.id)
	_apply_items()
	Session.notice.emit("%s already has %s." % [Session.name_of(holder), key.to_lower()])


## `key` is no longer this hand's to let go of: somebody else has it.
func _forget_carry(interactor: Object, key: String) -> void:
	var keys: Array = _carry_claims.get(interactor, [])
	keys.erase(key)
	if keys.is_empty():
		_carry_claims.erase(interactor)


# --- in -----------------------------------------------------------------------------------

func _sync_avatars() -> void:
	if reflection != null:
		var me = Session.local_participant()
		reflection.dress(Session.local_name, me.colour if me != null else Session.PALETTE[0],
				0, Session.role != Session.Role.GUEST, Session.local_look)
	for id in _avatars.keys():
		if not Session.participants.has(id) or id == Session.local_peer_id:
			_avatars[id].queue_free()
			_avatars.erase(id)
	for id in Session.participants:
		if id == Session.local_peer_id:
			continue
		var p = Session.participants[id]
		if not _avatars.has(id):
			var avatar := Avatar.new()
			avatar.name = "Avatar%d" % id
			add_child(avatar)
			avatar.wear_keys_pack(id)
			_avatars[id] = avatar
		_avatars[id].dress(p.display_name, p.colour, p.medium, id == 1, p.look)


func _on_role_changed() -> void:
	_my_claims.clear()
	_carry_claims.clear()
	_carry_at.clear()
	_apply_holds()
	_sync_avatars()


## Every control another participant holds is refused to this participant's hands, and every
## control that was and no longer is, is given back.
func _apply_holds() -> void:
	var now_claimed: Array[ControlAffordance] = []
	for key in Session.holds:
		var holder: int = Session.holds[key]
		if holder == Session.local_peer_id:
			continue
		var control := find_control(key)
		if control == null:
			continue
		control.claimed_by = Session.participants.get(holder)
		now_claimed.append(control)
	for control in _claimed:
		if is_instance_valid(control) and not control in now_claimed:
			control.claimed_by = null
	_claimed = now_claimed
	_apply_items()


## An item somebody else holds is in their ghost's glove, wearing their colour. One they have
## let go of is where the room says: the host's word on where they put it arrives just before
## the hold is let go (they ask, then let go), and has put it there already. Only a hold that
## ends without a word -- they left the session -- leaves it to whoever owns the room: a host
## sends it home, a guest waits to be told.
func _apply_items() -> void:
	if items == null:
		return
	for id in items.items:
		var item: Item = items.items[id]
		var holder := Session.holder_of(item.network_key())
		var mine := holder == Session.local_peer_id or holder == 0
		if not mine and _item_holders.get(id, 0) != holder:
			if item.carried_by != null:
				# My hand has it too: the host says theirs was first. Ours opens.
				_forget_carry(item.carried_by, item.network_key())
				item.carried_by.lose_carrying()
				Session.notice.emit("%s took the %s." % [Session.name_of(holder), item.item_title().to_lower()])
			_item_holders[id] = holder
			item.follow(_palm_of.bind(holder, item))
			var p = Session.participants.get(holder)
			item.set_rim(p.colour if p != null else Color.WHITE)
		elif mine and _item_holders.has(id):
			_item_holders.erase(id)
			item.set_rim(Color(0, 0, 0, 0))
			if item.is_held_elsewhere() and Session.is_authority():
				item.go_home()


## Where the item in `peer`'s hand is: their ghost's palm, or where it is now if they have no
## ghost here to hold it.
## The ghost of `peer`, or null: nobody's for this machine's own.
func avatar_of(peer: int) -> Avatar:
	return _avatars.get(peer)


## Everyone else's ghosts.
func avatars() -> Array:
	return _avatars.values()


func _palm_of(peer: int, item: Item) -> Transform3D:
	var avatar: Avatar = _avatars.get(peer)
	if avatar == null or not is_instance_valid(avatar) or not avatar.visible:
		return item.global_transform
	if item.pocket >= 0:
		return avatar.pocket_pose(item.pocket, item)
	return avatar.worn_pose() if item.on_head else avatar.carried_pose()


## The item in `peer`'s hand, or null. Not one on their head.
func _item_held_by(peer: int) -> Item:
	if items == null:
		return null
	for id in _item_holders:
		var item: Item = items.items.get(id)
		if _item_holders[id] == peer and item != null and not item.on_head and item.pocket < 0:
			return item
	return null


## The item on `peer`'s head, or null.
func _item_worn_by(peer: int) -> Item:
	if items == null:
		return null
	for id in _item_holders:
		var item: Item = items.items.get(id)
		if _item_holders[id] == peer and item != null and item.on_head:
			return item
	return null


func _on_item_carried(id: StringName, local: Transform3D, from: int) -> void:
	_carry_at[from] = local


## Somebody's radio plane, where they are flying it: ours, there.
func _on_item_flown(id: StringName, pose: Transform3D, mode: int, from: int) -> void:
	if items == null or _item_holders.get(id, 0) != from:
		return
	var flier := items.items.get(id) as RcPlaneItem
	if flier != null:
		flier.hear(_from_session(pose), mode)


## Somebody else squeezed what is in their hand: ours squeaks, in their glove, where it is.
func _on_item_used(id: StringName, down: bool, from: int) -> void:
	if items == null or _item_holders.get(id, 0) != from:
		return
	var item: Item = items.items.get(id)
	if item != null:
		item.use(down)


## Somebody's keys: if the keytar is in their hands, it plays them, out of the keytar.
func _on_note_played(kind: int, pitch: int, velocity: int, from: int, _song: float) -> void:
	if items == null or _item_holders.get(&"keytar", 0) != from:
		return
	var keytar := items.items.get(&"keytar") as KeytarItem
	if keytar != null:
		keytar.heard(kind, pitch, velocity)


## Somebody else shook the instrument in their hand: ours plays the hit, in their glove.
func _on_item_hit(id: StringName, velocity: int, from: int) -> void:
	if items == null or _item_holders.get(id, 0) != from:
		return
	var item := items.items.get(id) as InstrumentItem
	if item != null:
		item.heard(velocity)


## The control `peer_id` has their hand on -- not an item they carry, which is in the other glove.
func _key_held_by(peer_id: int) -> String:
	for key in Session.holds:
		if Session.holds[key] == peer_id and not _is_item_key(key):
			return key
	return ""


func _is_item_key(key: String) -> bool:
	if items == null:
		return false
	for id in items.items:
		if (items.items[id] as Item).network_key() == key:
			return true
	return false


## The control on THIS desk that goes by `key`. Cached, and the cache is distrusted on every
## read, because the strip that was "KICK" a moment ago is "SNARE" after a bank change.
func find_control(key: String) -> ControlAffordance:
	if key.is_empty():
		return null
	# Untyped until checked: the cache can hold a control freed since it was filled, and a
	# typed variable refuses even to hold one long enough to ask.
	var cached = _by_key.get(key)
	if cached != null and is_instance_valid(cached) and cached.is_inside_tree() \
			and cached.network_key() == key:
		return cached as ControlAffordance
	# Rescanned at most four times a second. A key nobody here has -- a rack page this
	# participant has not opened -- would otherwise rescan the whole room every frame.
	var now := Time.get_ticks_msec()
	if now - _scan_msec < 250:
		return null
	_scan_msec = now
	_by_key.clear()
	for node in get_tree().get_nodes_in_group(ControlAffordance.GROUP):
		var control := node as ControlAffordance
		if control == null or not control.is_visible_in_tree():
			continue
		var k := control.network_key()
		if not _by_key.has(k):
			_by_key[k] = control
	var found: ControlAffordance = _by_key.get(key)
	return found


func _caption(p, held_key: String) -> String:
	var role := "HOST" if p.peer_id == 1 else "GUEST"
	var medium: String = ["SCREEN", "AR", "VR"][clampi(p.medium, 0, 2)]
	if not held_key.is_empty():
		return "HOLDING  %s" % held_key
	return "%s  ·  %s" % [role, medium]


func _to_session(world: Transform3D) -> Transform3D:
	if frame == null:
		return world
	return frame.global_transform.affine_inverse() * world


func _from_session(session: Transform3D) -> Transform3D:
	if frame == null:
		return session
	return frame.global_transform * session


## One other person, drawn: a big blue ghost.
##
## Tall, round and soft, with a pair of heavy-lidded eyes too big for the face -- a friendly
## thing to find leaning over the desk beside you, and impossible to mistake for the hardware.
## A ghost also settles the old problem of a screen participant having no body below the
## head: it never had legs, so nothing is cut off. It floats, it bobs, its hem drifts.
##
## Everyone is the same blue, because the blue is what makes it a ghost. Who it is lives in
## the glow round its edge, its name, its pointer and the rim on what it holds -- all in
## that person's colour.
##
## The origin is their eye. The ghost turns with their yaw only and leans a little with
## their pitch; the pupils do the rest of the looking, which reads better on a face this
## size than tipping the whole body over a fader.
class Avatar extends Node3D:
	const BLUE := Color(0.30, 0.55, 0.98)
	## The whole ghost, scaled about the eye. Modelled at 1.3m; at 0.72 the dome is a hand above a
	## standing person's head and the hem is at desk height, so the gear -- built to real sizes,
	## 55mm channel strips -- reads as gear and the ghost as a large person, not a building.
	const SIZE := 0.72
	## Dome apex above the eye line, and the hem below it, before SIZE.
	const TOP := 0.34
	const HEM := -0.96
	const BELLY := 0.37
	const SEGMENTS := 40
	const SCALLOPS := 6
	## Lid angles: rim height on the eye is sin(angle). Dopey is mostly open, never quite.
	const LID_AWAKE := 0.18
	const LID_SLEEPY := -0.55
	const LID_SHUT := -1.45
	## How far a hand will fly from its side to reach something, in metres.
	const REACH := 0.95

	const SKIN_SHADER := """
shader_type spatial;
// Not shadowed, only lit: a smooth body this size self-shadows into stripes (acne) that
// crawl as it sways and read as z-fighting. It has its own glow; it still casts a shadow.
render_mode shadows_disabled;
uniform vec4 body : source_color = vec4(0.42, 0.64, 0.95, 1.0);
uniform vec4 glow : source_color = vec4(1.0);
uniform float glow_amount = 1.0;
uniform float hem_from = 0.0;
uniform float hem_to = -0.96;
uniform float sway = 1.0;
void vertex() {
	// Nothing moves above the eyes; the hem drifts the most.
	float w = clamp((hem_from - VERTEX.y) / (hem_from - hem_to), 0.0, 1.0);
	w = w * w * w * sway;
	float a = atan(VERTEX.x, VERTEX.z);
	VERTEX.xz *= 1.0 + w * 0.06 * sin(TIME * 2.1 + a * 3.0);
	VERTEX.x += w * 0.035 * sin(TIME * 1.3);
	VERTEX.z += w * 0.025 * cos(TIME * 1.1);
}
void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = body.rgb;
	ROUGHNESS = 0.42;
	SPECULAR = 0.45;
	// A soft inner light, so a ghost in a dim corner is still a ghost, and their colour
	// round the silhouette, which is what you see of someone across the room.
	EMISSION = body.rgb * 0.10 + glow.rgb * edge * 0.55 * glow_amount;
}
"""

	var _ghost := Node3D.new()
	var _lean := Node3D.new()
	var _tag := Label3D.new()
	var _caption := Label3D.new()
	var _beam := MeshInstance3D.new()
	var _dot := MeshInstance3D.new()
	var _rim := HoverRim.new()
	var _skin := ShaderMaterial.new()
	## The lids are skin without the edge light: seen edge-on, a lit cap reads as glass.
	var _lid_skin := ShaderMaterial.new()
	var _eye_size := Vector3.ONE
	var _beam_material := StandardMaterial3D.new()
	var _lids: Array[Node3D] = []
	var _lid_rest := LID_AWAKE
	var _lid_tilt := 0.0
	var _hat := Node3D.new()
	var _propeller: Node3D = null
	var _hat_key := ""
	## The top of whatever is on their head, so the name floats over the hat, not through it.
	var _hat_top := TOP
	var _look: Dictionary = GhostLook.default_look()
	var _pupils: Array[Node3D] = []
	var _pupil_rest: Array[Vector3] = []
	var _hands: Array[Glove] = []
	var _pointing: ControlAffordance = null
	var _point := Vector3.ZERO
	## What the left glove carries (docs/items_loop.md): a look of the item, sat on its palm, in
	## a mirror; nothing of its own for somebody else's ghost, whose glove the real item rides.
	var _carried: Node3D = null
	## The SEND socket on this player's keys pack (`wear_keys_pack`); null on a reflection.
	var send: SendSocket = null
	## The MONITOR socket under it, while this player is ON AIR (`set_on_air`); null otherwise.
	var monitor_send: SendSocket = null
	var _keys_lamp: MeshInstance3D = null
	var _pack: Node3D = null
	var _air: Node3D = null
	var _carried_kind := &""
	## Where the carried item is, relative to the eye, as its holder last said; until they have,
	## held out in front of the chest.
	var carry_at := Transform3D.IDENTITY:
		set(v):
			carry_at = v
			_carry_heard = true
	var _carry_heard := false
	var _holding := false
	var _mirror_only := false
	var _colour := Color.WHITE
	var _close := false
	var _away := false
	var _pose := Transform3D.IDENTITY
	var _pitch := 0.0
	var _lid := LID_AWAKE
	var _blink_in := 2.0
	var _blink := 0.0
	var _phase := randf() * TAU
	var _clock := 0.0
	var placed := false

	func _init() -> void:
		var shader := Shader.new()
		shader.code = SKIN_SHADER
		_skin.shader = shader
		_skin.set_shader_parameter("hem_to", HEM)
		_lid_skin.shader = shader
		_lid_skin.set_shader_parameter("glow_amount", 0.0)
		_lid_skin.set_shader_parameter("sway", 0.0)

		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED

		add_child(_ghost)
		_ghost.add_child(_lean)
		_part(body_mesh(), _skin, _lean)
		_build_face()
		_lean.add_child(_hat)
		_build_hands()

		for label in [_tag, _caption]:
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.render_priority = 5
			label.outline_render_priority = 4
			label.outline_modulate = Color(0, 0, 0, 0.85)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.double_sided = true
			add_child(label)
		_tag.font_size = 64
		_tag.outline_size = 14
		_tag.pixel_size = 0.0011
		_caption.font_size = 36
		_caption.outline_size = 10
		_caption.pixel_size = 0.0011
		_caption.modulate = Color(0.82, 0.85, 0.9)

		var rod := CylinderMesh.new()
		rod.top_radius = 0.0022
		rod.bottom_radius = 0.0022
		rod.height = 1.0
		rod.radial_segments = 6
		rod.rings = 1
		_beam.mesh = rod
		_beam.material_override = _beam_material
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.top_level = true
		add_child(_beam)
		var bead := SphereMesh.new()
		bead.radius = 0.008
		bead.height = 0.016
		_dot.mesh = bead
		var dot_material := StandardMaterial3D.new()
		dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot_material.no_depth_test = true
		dot_material.render_priority = 9
		_dot.material_override = dot_material
		_dot.top_level = true
		add_child(_dot)
		_rim.name = "Rim"
		add_child(_rim)

	## How wide the ghost is at height y (eye line = 0): a dome on top, a belly that swells
	## below the face and draws in a little toward the hem.
	static func radius_at(y: float) -> float:
		if y >= 0.0:
			var t := clampf(y / TOP, 0.0, 1.0)
			return 0.30 * sqrt(maxf(0.0, 1.0 - t * t))
		var down := clampf(-y / -HEM, 0.0, 1.0)
		var swell := sin(down * PI * 0.8)
		return 0.30 + (BELLY - 0.30) * swell * 1.15 - 0.02 * down * down

	## The ghost's skin, turned on a lathe: one smooth surface from the dome to a scalloped
	## hem, tucked under into a shallow hollow so the hem has thickness from below.
	static func body_mesh() -> ArrayMesh:
		var rings: Array[float] = []
		var count := 28
		for i in count + 1:
			# Denser near the top, where the dome curves fastest.
			var t := float(i) / count
			rings.append(TOP - (TOP - HEM) * (t * t * 0.35 + t * 0.65))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		st.add_vertex(Vector3(0, TOP, 0))  # apex
		for y in rings.slice(1):
			var near_hem := clampf((y - (HEM + 0.25)) / -0.25, 0.0, 1.0)
			for s in SEGMENTS:
				var a := TAU * s / SEGMENTS
				var r := radius_at(y)
				var dip := near_hem * near_hem * 0.045 * (0.5 + 0.5 * cos(a * SCALLOPS))
				st.add_vertex(Vector3(sin(a) * r, y - dip, cos(a) * r))
		# Under the hem: curl in and up to a hollow.
		for ring in [[0.88, 0.035], [0.55, 0.09]]:
			for s in SEGMENTS:
				var a := TAU * s / SEGMENTS
				var r: float = radius_at(HEM) * ring[0]
				var dip: float = 0.045 * (0.5 + 0.5 * cos(a * SCALLOPS)) * ring[0]
				st.add_vertex(Vector3(sin(a) * r, HEM - dip + ring[1], cos(a) * r))
		var hollow := 1 + (rings.size() - 1 + 2) * SEGMENTS
		st.add_vertex(Vector3(0, HEM + 0.12, 0))

		for s in SEGMENTS:
			st.add_index(0)
			st.add_index(1 + (s + 1) % SEGMENTS)
			st.add_index(1 + s)
		var bands := rings.size() - 1 + 2
		for b in bands - 1:
			var top_row := 1 + b * SEGMENTS
			var low_row := top_row + SEGMENTS
			for s in SEGMENTS:
				var n := (s + 1) % SEGMENTS
				st.add_index(top_row + s)
				st.add_index(top_row + n)
				st.add_index(low_row + s)
				st.add_index(top_row + n)
				st.add_index(low_row + n)
				st.add_index(low_row + s)
		var last := 1 + (bands - 1) * SEGMENTS
		for s in SEGMENTS:
			st.add_index(last + s)
			st.add_index(last + (s + 1) % SEGMENTS)
			st.add_index(hollow)
		st.generate_normals()
		return st.commit()

	## Two big eyes set close together, high on the face, under lids that never quite open --
	## and pupils that do not quite agree on where to look.
	func _build_face() -> void:
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.97, 0.97, 0.95)
		white.roughness = 0.25
		white.emission_enabled = true
		white.emission = Color(0.12, 0.12, 0.12)
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.03, 0.03, 0.05)
		black.roughness = 0.15
		black.clearcoat_enabled = true
		var shine := StandardMaterial3D.new()
		shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shine.albedo_color = Color.WHITE

		var eye_y := 0.07
		var size := Vector3(0.155, 0.2, 0.09)
		_eye_size = size
		for side in [-1.0, 1.0]:
			var x: float = side * 0.085
			var z := -sqrt(maxf(0.0, pow(radius_at(eye_y), 2) - x * x)) + 0.035
			var socket := Node3D.new()
			socket.position = Vector3(x, eye_y, z)
			# Facing out of the dome a little, the way eyes on a round face do.
			socket.rotation = Vector3(-0.12, -side * 0.28, 0)
			_lean.add_child(socket)
			var ball := SphereMesh.new()
			ball.radius = 0.5
			ball.height = 1.0
			_part(ball, white, socket).scale = size

			var pupil := Node3D.new()
			# Dopey: a touch low, a touch apart.
			var rest := Vector3(side * 0.016, -0.02, 0)
			pupil.position = rest
			socket.add_child(pupil)
			_pupils.append(pupil)
			_pupil_rest.append(rest)
			var dot := SphereMesh.new()
			dot.radius = 0.5
			dot.height = 1.0
			_part(dot, black, pupil).scale = Vector3(0.062, 0.078, 0.024)
			var glint := SphereMesh.new()
			glint.radius = 0.5
			glint.height = 1.0
			_part(glint, shine, pupil).transform = Transform3D(
					Basis.from_scale(Vector3(0.02, 0.02, 0.008)), Vector3(0.014, 0.018, -0.01))

			# The lid: a cap of ghost over the top of the eye, swung down by _lid. Swung and
			# tilted INSIDE the eye's stretch, not after it: as a round cap a hair outside a
			# round ball it can turn any way and never cut it, and stretched with the ball it
			# stays outside it. Stretched first and turned after, the lid's long axis swung
			# round into the eye's short one and the white came through it, worst for Grumpy.
			var eye_space := Node3D.new()
			eye_space.scale = size
			socket.add_child(eye_space)
			var lid := Node3D.new()
			eye_space.add_child(lid)
			var cap := SphereMesh.new()
			cap.radius = 0.5
			cap.height = 0.5
			cap.is_hemisphere = true
			_part(cap, _lid_skin, lid).scale = Vector3.ONE * 1.04
			_lids.append(lid)

		# A small, contented mouth.
		var mouth := SphereMesh.new()
		mouth.radius = 0.5
		mouth.height = 1.0
		var my := -0.12
		var m := _part(mouth, black, _lean)
		m.scale = Vector3(0.11, 0.022, 0.03)
		m.position = Vector3(0, my, -radius_at(my) + 0.008)

	## No arms: two gloves that float at its sides, the way a cartoon's do. The right one goes
	## to whatever they are pointing at -- all the way, if it is in reach -- and grips what they
	## hold; the left one cheers it on.
	func _build_hands() -> void:
		for side in [-1.0, 1.0]:
			var glove := Glove.new(side)
			glove.size = 1.25
			glove.name = "RightHand" if side > 0 else "LeftHand"
			add_child(glove)
			_hands.append(glove)

	## Where a hand floats when it has nothing to do: beside the belly, a little forward,
	## fingers down and palm in, bobbing out of step with the body.
	func _rest(side: float) -> Transform3D:
		var at := _ghost.global_transform * Vector3(side * (radius_at(-0.4) + 0.14), -0.42, -0.1)
		var droop := 0.12 if _away else 0.0
		var speed := 3.6 if _holding else 2.3
		at.y += sin(_clock * speed + side * 1.3 + _phase) * 0.022 - droop
		var turn := Basis(Vector3.UP, _ghost.global_basis.orthonormalized().get_euler().y)
		var fingers := turn * Vector3(side * 0.25, -0.8, -0.5).normalized()
		var inward := turn * Vector3(-side, 0, 0)
		return Transform3D(_attitude(fingers, inward), at)

	## A glove's basis with its fingers along `fingers` and its palm turned toward `palm`.
	static func _attitude(fingers: Vector3, palm: Vector3) -> Basis:
		var z := -fingers.normalized()
		var y := -palm - z * (-palm).dot(z)
		if y.length() < 0.01:
			y = Vector3.UP - z * Vector3.UP.dot(z)
		y = y.normalized()
		return Basis(y.cross(z), y, z)

	func _aim_hands() -> void:
		var left: Glove = _hands[0]
		var right: Glove = _hands[1]
		if _carried_kind != &"":
			# Carrying: the left hand palm up under the item, the way you hold something out to
			# look at it.
			var turn := Basis(Vector3.UP, _ghost.global_basis.orthonormalized().get_euler().y)
			var at := carried_pose().origin - Vector3.UP * PALM_LIFT * left.size
			left.target = Transform3D(_attitude(turn * Vector3(0.3, 0.1, -1.0), Vector3.UP), at)
			left.pose = Glove.Pose.OPEN
		else:
			left.target = _rest(-1.0)
			left.pose = Glove.Pose.GRIP if _holding else Glove.Pose.OPEN
		var rest := _rest(1.0)
		if _pointing == null:
			right.target = rest
			right.pose = Glove.Pose.OPEN
			return
		var span := _point - rest.origin
		var dist := span.length()
		if dist < 0.01:
			right.target = rest
			return
		var toward := span / dist
		# Fingertip on the point, or palm on it when gripping; out of reach, as far as it goes.
		var attitude := _attitude(toward, Vector3.DOWN)
		var on := _point - attitude * (Vector3(0, 0, -0.05 * right.size) if _holding else right.tip_offset())
		var go := on - rest.origin
		if go.length() > REACH:
			go = go.normalized() * REACH
		right.target = Transform3D(attitude, rest.origin + go)
		right.pose = Glove.Pose.GRIP if _holding else Glove.Pose.POINT

	func _part(mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = material
		parent.add_child(m)
		return m

	func dress(display_name: String, colour: Color, _medium: int, _is_host: bool,
			look: Dictionary = {}) -> void:
		_colour = colour
		for glove in _hands:
			glove.set_colour(colour)
		_tag.text = display_name
		_tag.modulate = colour.lightened(0.25)
		wear(look if not look.is_empty() else _look)
		_skin.set_shader_parameter("glow", colour)
		(_dot.material_override as StandardMaterial3D).albedo_color = colour.lightened(0.3)
		_beam_material.albedo_color = Color(colour, 0.55)
		_rim.tint = colour
		if _keys_lamp != null:
			_keys_lamp.material_override = Materials.led(colour, true)
		if send != null:
			send.label = display_name.to_upper() + "'S KEYS"
		if monitor_send != null:
			monitor_send.label = display_name.to_upper() + "'S MONITOR"

	## Put on a look (GhostLook): body colour, eyes, hat, gloves. Their session colour still
	## glows round the edge and tints what they wear, so a look never hides who someone is.
	func wear(look: Dictionary) -> void:
		var tidy := GhostLook.clean(look)
		_look = tidy
		var body := GhostLook.body_colour(tidy).lerp(_colour, 0.12)
		_skin.set_shader_parameter("body", body)
		_lid_skin.set_shader_parameter("body", body.darkened(0.22))
		match GhostLook.EYES[tidy["eyes"]]:
			"Wide": _lid_rest = 1.0; _lid_tilt = 0.0
			"Sleepy": _lid_rest = -0.4; _lid_tilt = 0.0
			"Grumpy": _lid_rest = 0.05; _lid_tilt = -0.42
			_: _lid_rest = LID_AWAKE; _lid_tilt = 0.0
		for glove in _hands:
			glove.set_colour(_colour)
			match GhostLook.GLOVES[tidy["gloves"]]:
				"Black": glove.set_cloth(Color(0.07, 0.07, 0.08))
				"My colour": glove.set_cloth(_colour.lightened(0.2))
				"Gold": glove.set_cloth(Color(1.0, 0.78, 0.32), 0.85)
				_: glove.set_cloth(Glove.WHITE)
		var hat: String = GhostLook.HATS[tidy["hat"]]
		var key := "%s|%s" % [hat, _colour.to_html()]
		if key != _hat_key:
			_hat_key = key
			_put_on_hat(hat)

	## Hats are built in the ghost's own units (eye line 0, dome apex TOP) on the leaning part,
	## so they nod with the face. Each sits on the dome, never through it where it shows.
	func _put_on_hat(hat: String) -> void:
		for old in _hat.get_children():
			_hat.remove_child(old)
			old.queue_free()
		_propeller = null
		_hat.rotation = Vector3.ZERO
		_hat_top = {"Beanie": 0.45, "Top hat": 0.63, "Crown": 0.45, "Propeller": 0.43}.get(hat, TOP)
		var felt := StandardMaterial3D.new()
		felt.albedo_color = _colour.darkened(0.15)
		felt.roughness = 0.9
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.06, 0.06, 0.07)
		dark.roughness = 0.5
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(1.0, 0.8, 0.3)
		gold.metallic = 0.9
		gold.roughness = 0.25
		match hat:
			"Beanie":
				var dome := SphereMesh.new()
				dome.radius = 0.275
				dome.height = 0.275
				dome.is_hemisphere = true
				var cap := _part(dome, felt, _hat)
				cap.position.y = 0.16
				cap.scale = Vector3(1.0, 0.78, 1.0)
				var cuff := TorusMesh.new()
				cuff.inner_radius = 0.25
				cuff.outer_radius = 0.30
				_part(cuff, felt, _hat).position.y = 0.17
				var pom := SphereMesh.new()
				pom.radius = 0.055
				pom.height = 0.11
				var white := StandardMaterial3D.new()
				white.albedo_color = Color(0.95, 0.95, 0.92)
				white.roughness = 1.0
				_part(pom, white, _hat).position.y = 0.39
			"Headphones":
				# The band is a whole ring; its lower half is inside the body, out of sight.
				var band := TorusMesh.new()
				band.inner_radius = 0.345
				band.outer_radius = 0.385
				band.rings = 40
				var arc := _part(band, dark, _hat)
				arc.rotation.z = PI * 0.5
				arc.rotation.y = PI * 0.5
				arc.position = Vector3(0, 0.0, 0.02)
				for side in [-1.0, 1.0]:
					var can := CylinderMesh.new()
					can.top_radius = 0.085
					can.bottom_radius = 0.095
					can.height = 0.07
					var cup := _part(can, dark, _hat)
					cup.rotation.z = side * PI * 0.5
					cup.position = Vector3(side * 0.31, 0.0, 0.02)
					var ring := TorusMesh.new()
					ring.inner_radius = 0.055
					ring.outer_radius = 0.08
					var trim := _part(ring, felt, _hat)
					trim.rotation.z = PI * 0.5
					trim.position = Vector3(side * 0.348, 0.0, 0.02)
			"Top hat":
				_hat.rotation.z = -0.12
				var crown := CylinderMesh.new()
				crown.top_radius = 0.15
				crown.bottom_radius = 0.14
				crown.height = 0.3
				_part(crown, dark, _hat).position.y = 0.44
				var brim := CylinderMesh.new()
				brim.top_radius = 0.235
				brim.bottom_radius = 0.235
				brim.height = 0.016
				_part(brim, dark, _hat).position.y = 0.302
				var ribbon := CylinderMesh.new()
				ribbon.top_radius = 0.149
				ribbon.bottom_radius = 0.148
				ribbon.height = 0.045
				var band_part := _part(ribbon, felt, _hat)
				band_part.position.y = 0.333
			"Crown":
				_hat.rotation.z = 0.08
				var ring := CylinderMesh.new()
				ring.top_radius = 0.15
				ring.bottom_radius = 0.135
				ring.height = 0.085
				_part(ring, gold, _hat).position.y = 0.325
				for i in 5:
					var a := TAU * i / 5.0
					var spike := CylinderMesh.new()
					spike.top_radius = 0.0
					spike.bottom_radius = 0.032
					spike.height = 0.08
					_part(spike, gold, _hat).position = Vector3(sin(a) * 0.125, 0.405, cos(a) * 0.125)
					var jewel := SphereMesh.new()
					jewel.radius = 0.016
					jewel.height = 0.032
					var gem := StandardMaterial3D.new()
					gem.albedo_color = _colour
					gem.emission_enabled = true
					gem.emission = _colour * 0.4
					_part(jewel, gem, _hat).position = Vector3(sin(a) * 0.152, 0.327, cos(a) * 0.152)
			"Propeller":
				var dome := SphereMesh.new()
				dome.radius = 0.24
				dome.height = 0.24
				dome.is_hemisphere = true
				var cap := _part(dome, felt, _hat)
				cap.position.y = 0.215
				cap.scale = Vector3(1.0, 0.62, 1.0)
				var stem := CylinderMesh.new()
				stem.top_radius = 0.012
				stem.bottom_radius = 0.012
				stem.height = 0.07
				_part(stem, dark, _hat).position.y = 0.38
				_propeller = Node3D.new()
				_propeller.position.y = 0.415
				_hat.add_child(_propeller)
				var yellow := StandardMaterial3D.new()
				yellow.albedo_color = Color(1.0, 0.85, 0.2)
				for i in 2:
					var blade := BoxMesh.new()
					blade.size = Vector3(0.14, 0.008, 0.045)
					var b := _part(blade, yellow if i == 0 else felt, _propeller)
					b.position.x = 0.075 if i == 0 else -0.075
					b.rotation.x = 0.25 if i == 0 else -0.25
		if _mirror_only:
			only_in_mirrors()

	## Drawn by mirrors and nothing else, casting no shadow on the desk in front of you, and
	## without the name over its head -- you know who you are.
	func only_in_mirrors() -> void:
		_mirror_only = true
		for node in find_children("*", "VisualInstance3D", true, false):
			var drawn := node as VisualInstance3D
			drawn.layers = Mirror.SELF_ONLY
			if drawn is GeometryInstance3D:
				(drawn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tag.visible = false
		_caption.visible = false
		_beam.visible = false
		_dot.visible = false

	func set_caption(text: String) -> void:
		if _caption.text != text:
			_caption.text = text

	func snap(pose: Transform3D) -> void:
		placed = true
		_pose = pose
		_place()

	func follow(pose: Transform3D, weight: float) -> void:
		_pose = _pose.interpolate_with(pose, weight)
		_place()

	func head_position() -> Vector3:
		return _pose.origin

	func _process(delta: float) -> void:
		_clock += delta
		# Blinking: every few seconds, quick. A ghost that never blinks is a statue.
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink = 0.16
			_blink_in = randf_range(2.5, 6.0)
		_blink = maxf(0.0, _blink - delta)
		var want := minf(LID_SLEEPY, _lid_rest) if _away else _lid_rest
		_lid = lerpf(_lid, want, 1.0 - exp(-delta * 3.0))
		var angle := LID_SHUT if _blink > 0.0 else _lid
		for i in _lids.size():
			_lids[i].rotation.x = angle
			# Grumpy: the inner corners down. Blinks still shut them flat.
			_lids[i].rotation.z = 0.0 if _blink > 0.0 else _lid_tilt * (1.0 if i == 0 else -1.0)
		if _propeller != null:
			_propeller.rotation.y += delta * 14.0
		_place()
		_aim_hands()
		_seat_carried()

	## How far above the palm a carried thing sits, before the glove's size.
	const PALM_LIFT := 0.03

	## Take `kind` into the left glove, or put down whatever is there (&""). With `look`, a
	## look-alike of it sits there; without, the glove only holds itself ready for the real
	## one, which rides `carried_pose`.
	func carry(kind: StringName, look := true) -> void:
		if kind == _carried_kind:
			return
		var had := _carried_kind != &""
		_carried_kind = kind
		if _carried != null:
			_carried.queue_free()
			_carried = null
		if had:
			_hands[0].poke(0.3)
		if kind == &"":
			_carry_heard = false
			return
		_hands[0].poke(-0.4)
		if not look:
			return
		_carried = ItemRoom.look_of(kind)
		if _carried == null:
			return
		_carried.top_level = true
		add_child(_carried)
		for node in _carried.find_children("*", "VisualInstance3D", true, false):
			if _mirror_only:
				(node as VisualInstance3D).layers = Mirror.SELF_ONLY
			if _mirror_only and node is GeometryInstance3D:
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_seat_carried()

	## Where the carried item is, in the world: where its holder says, relative to this ghost's
	## eye, or held out in front of the chest until they have said. The glove goes under it.
	func carried_pose() -> Transform3D:
		var bob := Vector3.UP * sin(_clock * 2.3 + _phase) * 0.012
		if _carry_heard:
			var pose := _pose.orthonormalized() * carry_at
			return pose.translated(bob)
		var turn := Basis(Vector3.UP, _ghost.global_basis.orthonormalized().get_euler().y)
		var at := _ghost.global_transform * Vector3(-0.22, -0.3, -0.42)
		return Transform3D(turn, at + bob + Vector3.UP * PALM_LIFT * _hands[0].size)

	## How big a ghost's head is against a person's: the real headphones, worn, are drawn this
	## much bigger, so they sit on the dome where the hat of the same name does.
	const HEAD_FIT := 2.75

	## Where something worn on this ghost's head is, in the world: the middle between its ears,
	## nodding with its face, at the size of its head.
	func worn_pose() -> Transform3D:
		# From what the hat hangs on, not the hat: a top hat tips its node, and headphones do not.
		var lean := _hat.get_parent_node_3d()
		var unit := lean.global_basis.get_scale().x
		var at := lean.global_transform.orthonormalized() * Transform3D(Basis.IDENTITY, _hat.position)
		# Forward a little, as the hat's headphones are: the dome's widest is in front of its middle.
		return Transform3D(at.basis.scaled(Vector3.ONE * unit * HEAD_FIT), at * Vector3(0, 0, 0.02 * unit))

	## Where pocket `slot` (Pockets) is on this ghost, in the world, for `item` to ride there:
	## at the left hip, the right hip, or slung across the back. Against the body, its face out,
	## at its own size; swaying with the ghost.
	const POCKETS := [[-0.58, 0.95, 0.0], [-0.58, -0.95, 0.0], [-0.12, PI, 0.7]]

	func pocket_pose(slot: int, _item: Item = null) -> Transform3D:
		var spec: Array = POCKETS[clampi(slot, 0, POCKETS.size() - 1)]
		var y: float = spec[0]
		var turn: float = spec[1]
		var out := Vector3(sin(turn), 0, -cos(turn))
		var unit := _lean.global_basis.get_scale().x
		var frame := _lean.global_transform.orthonormalized()
		# Its skin there, and 6 cm out from it in the world.
		var at := _lean.global_transform * (out * (radius_at(y) + 0.06 / maxf(unit, 0.01)) + Vector3(0, y, 0))
		# Face out from the body, upright, and a thing across the back tipped along it.
		var z := frame.basis * -out
		var x := Vector3.UP.cross(z).normalized()
		var basis := Basis(x, z.cross(x), z) * Basis(Vector3.BACK, float(spec[2]))
		return Transform3D(basis, at)

	## The pack their keys send from, low on their belly: a SEND socket anyone can drag a plug
	## from their tablet into, to hear this player's keys (PersonalMix, TheirKeys). Built in the
	## ghost's own units, so it sways with it; the socket is at its real size, as every socket is.
	func wear_keys_pack(peer: int) -> void:
		if send != null:
			return
		var y := -0.42
		# A little to the ghost's left of its middle, clear of where its hands come to rest.
		var turn := 0.5
		var out := Vector3(sin(turn), 0, -cos(turn))
		var pack := Node3D.new()
		_pack = pack
		pack.name = "KeysPack"
		var z := out
		var x := Vector3.UP.cross(z).normalized()
		pack.transform = Transform3D(Basis(x, Vector3.UP, z), out * (radius_at(y) + 0.012) + Vector3(0, y, 0))
		_lean.add_child(pack)
		var body := BoxMesh.new()
		body.size = Vector3(0.085, 0.11, 0.03)
		var case := StandardMaterial3D.new()
		case.albedo_color = Color(0.08, 0.085, 0.095)
		case.roughness = 0.6
		_part(body, case, pack)
		var aerial := CylinderMesh.new()
		aerial.top_radius = 0.004
		aerial.bottom_radius = 0.005
		aerial.height = 0.07
		aerial.radial_segments = 8
		aerial.rings = 1
		_part(aerial, case, pack).position = Vector3(0.028, 0.09, 0)
		var lamp := BoxMesh.new()
		lamp.size = Vector3(0.012, 0.006, 0.002)
		_keys_lamp = _part(lamp, Materials.led(_colour, true), pack)
		_keys_lamp.position = Vector3(-0.025, 0.04, 0.0155)
		var word := Label3D.new()
		word.text = "KEYS"
		word.font_size = 40
		word.pixel_size = 0.0007
		word.position = Vector3(0.008, 0.038, 0.0155)
		word.modulate = Color(0.86, 0.87, 0.89)
		pack.add_child(word)
		send = SendSocket.new()
		send.source = PersonalMix.player_socket(peer)
		send.label = _tag.text.to_upper() + "'S KEYS" if _tag.text != "" else "KEYS"
		send.position = Vector3(0, -0.012, 0.015)
		send.scale = Vector3.ONE / SIZE
		pack.add_child(send)

	## ON AIR (TheirMonitor): a block under the keys pack with a lit ON AIR sign, so the room can
	## see who is performing, and a MONITOR socket to plug into them in time. Gone when they
	## come off air, plugs and all.
	func set_on_air(on: bool, peer: int) -> void:
		if on == (_air != null) or _pack == null:
			return
		if not on:
			_air.queue_free()
			_air = null
			monitor_send = null
			return
		_air = Node3D.new()
		_air.name = "OnAir"
		_air.position = Vector3(0, -0.11, 0)
		_pack.add_child(_air)
		var body := BoxMesh.new()
		body.size = Vector3(0.085, 0.1, 0.03)
		var case := StandardMaterial3D.new()
		case.albedo_color = Color(0.08, 0.085, 0.095)
		case.roughness = 0.6
		_part(body, case, _air)
		# The sign: a red lit panel across the top, as the light over a studio door.
		var sign := BoxMesh.new()
		sign.size = Vector3(0.072, 0.022, 0.004)
		_part(sign, Materials.led(Color(0.5, 0.05, 0.04), true), _air).position = Vector3(0, 0.032, 0.016)
		var word := Label3D.new()
		word.text = "ON AIR"
		word.font_size = 34
		word.pixel_size = 0.0007
		word.outline_size = 0
		word.position = Vector3(0, 0.032, 0.0185)
		word.modulate = Color(1.0, 1.0, 1.0)
		_air.add_child(word)
		var under := Label3D.new()
		under.text = "MONITOR"
		under.font_size = 30
		under.pixel_size = 0.0007
		under.position = Vector3(0, -0.038, 0.0155)
		under.modulate = Color(0.86, 0.87, 0.89)
		_air.add_child(under)
		monitor_send = SendSocket.new()
		monitor_send.source = PersonalMix.monitor_socket(peer)
		monitor_send.label = _tag.text.to_upper() + "'S MONITOR" if _tag.text != "" else "MONITOR"
		monitor_send.position = Vector3(0, -0.006, 0.015)
		monitor_send.scale = Vector3.ONE / SIZE
		_air.add_child(monitor_send)

	## Something real is on its head: its own hat comes off while it is, so they do not sit one
	## in the other.
	func wear_item(on: bool) -> void:
		_hat.visible = not on

	## The look-alike in a mirror sits where the item is.
	func _seat_carried() -> void:
		if _carried == null:
			return
		_carried.global_transform = carried_pose()
		_carried.visible = _hands[0].visible

	## Yaw from the pose; a slight lean for pitch; the eyes take the rest. And a slow bob,
	## so nobody is ever quite standing still.
	func _place() -> void:
		var basis := _pose.basis.orthonormalized()
		var forward := -basis.z
		_pitch = asin(clampf(forward.y, -1.0, 1.0))
		forward.y = 0.0
		var yaw := atan2(-forward.x, -forward.z) if forward.length() > 0.01 else 0.0
		var bob := sin(_clock * 1.6 + _phase) * 0.018 * SIZE
		_ghost.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SIZE),
				_pose.origin + Vector3(0, bob, 0))
		# Lean about the belly, not the eye, so the face dips toward the desk.
		var lean := clampf(_pitch, -0.6, 0.6) * 0.3
		_lean.transform = Transform3D(Basis(Vector3.RIGHT, lean), Vector3.ZERO)
		var look := clampf(_pitch, -0.8, 0.8) / 0.8
		var half := _eye_size * 0.5
		for i in _pupils.size():
			var at := _pupil_rest[i] + Vector3(0, look * 0.022, 0)
			# Sat on the surface of the eye wherever it has rolled to, not floating off it.
			var inside := 1.0 - pow(at.x / half.x, 2) - pow(at.y / half.y, 2)
			at.z = -half.z * sqrt(maxf(0.05, inside)) - 0.004
			_pupils[i].position = at
		_tag.global_position = _pose.origin + Vector3(0, _hat_top * SIZE + 0.16 + bob, 0)
		_caption.global_position = _pose.origin + Vector3(0, _hat_top * SIZE + 0.09 + bob, 0)

	func set_close(close: bool) -> void:
		if close == _close:
			return
		_close = close
		_ghost.visible = not close
		for glove in _hands:
			glove.visible = not close
		_tag.visible = not close
		_caption.visible = not close

	## Away: the glow fades and the lids droop. A ghost that has dozed off.
	func set_away(away: bool) -> void:
		if away == _away:
			return
		_away = away
		_skin.set_shader_parameter("glow_amount", 0.25 if away else 1.0)
		_tag.modulate = Color(0.6, 0.6, 0.62) if away else _colour.lightened(0.25)

	## Their right glove flies to what they mean on MY copy of it -- points at it, or grips it --
	## and a beam runs from its fingertip to the spot when it cannot reach. Every change is a
	## bounce: a new target, a grab (a squash, and the other hand jumps), a let-go (a boing).
	func point_at(control: ControlAffordance, at: Vector3, holding: bool) -> void:
		var right: Glove = _hands[1]
		var left: Glove = _hands[0]
		if control != _pointing and control != null:
			right.poke(0.35)
		elif control == null and _pointing != null:
			right.poke(0.2)
		if holding and not _holding:
			right.poke(-0.6)
			left.poke(0.35)
		elif _holding and not holding:
			right.poke(0.5)
			left.poke(0.25)
		_pointing = control
		_holding = holding and control != null
		_point = at
		if _mirror_only:
			return
		_rim.show_on(control, holding)
		var on := control != null
		_dot.visible = on
		if not on:
			_beam.visible = false
			return
		_dot.global_position = at
		var from := right.fingertip()
		var span := at - from
		var length := span.length()
		_beam.visible = not _close and length > 0.04
		if not _beam.visible:
			return
		var y := span / length
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		_beam.global_transform = Transform3D(Basis(x, y * length, z), from + span * 0.5)
		_beam_material.albedo_color = Color(_colour, 0.8 if holding else 0.45)
