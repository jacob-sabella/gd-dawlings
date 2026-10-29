class_name Sampler
extends Node3D

## Anything can be a sample (docs/spatial_loop.md part two, slice 26, idea #12): a small pad bank
## on a cabinet beside the cassette rack, with a microphone on a gooseneck bent over its pads. A
## station (Stations.ALL, `sampler`): gone to by name, and stood clear of everything else.
##
## Its REC key is a room row, `sampler`: the peer who pressed it, or 0 (`armed_by`). A press asks
## the host (the room's `sampler` [on]) and shows at once here; the host's room is the truth. One
## press catches one sound: the next use, by anyone, of an item within REACH of the mic, or of one
## in the hand of whoever pressed REC -- the duck squeezed, the cowbell struck, the shaker shaken,
## a yo-yo's or a deck's trick -- or the next bounce of a ball by the mic or thrown by them. Then
## REC goes off, so it is a sample a press, never a file a hit. Only the host catches (`heard`):
## every use reaches it with the Foley take its player's hand rang (Session.item_used's and
## item_hit's `take`), and a bounce is the host's own copy's (Item.rang: every copy flies a throw
## the same), so the sound it writes is Foley.take_of that kind and take, the very stream the
## player heard, at the pitch it was played (a second voice, a curse, a bell's chord tone: its
## `pitch`). It writes it as a WAV into the project's media (DAWBackend.media_path:
## `duck_squeeze_3.wav`, the use's kind and the next number free) and mints a sample cassette of it
## (`sample_data`: an audio clip of the file) into the cassette rack's first free slot. A sample
## cassette is a cassette: held to the ear it plays (slice 25, fetched by a guest), pressed onto a
## track it pastes as audio (slice 24).
##
## A rhythm squeezed or shaken while recording is already recorded, as hits (HitRecorder), and plays
## back as hits (slice 16); the sampler is for a sound, not a part.
##
## Its numbers are tools/blender/sampler.py's, which builds the model. Origin the middle of its foot,
## its front +Z.

const MODEL := "res://assets/models/sampler.glb"
## The room's row and the verb that asks for it (Session.ROOM_VERBS).
const VERB := &"sampler"
## How near the mic (m) somebody else's use has to be to be caught.
const REACH := 1.5
## The mic's grille, in its frame: the head of the gooseneck, bent forward over the pads.
const MIC_AT := Vector3(-0.16, 1.2532, 0.1394)
## The deck's top, the REC key's seat on it (x, z) and the screen's front (its lettering's plane).
const DECK_TOP := 0.92
const REC_AT := Vector2(0.13, 0.04)
const REC_RADIUS := 0.032
const SCREEN_Z := -0.13
const SCREEN_Y := 0.96
const SCREEN_WIDTH := 0.33
## The screen's two lines: what it is doing, large, and what that means, under it (`_show`).
const HEADLINE_Y := 0.974
const HEADLINE_SIZE := 160
const DETAIL_Y := 0.938
const DETAIL_SIZE := 110
## Where the REC key's legend lies, on the deck in front of the key (in the key's frame), and how
## wide it may be: read from where you stand, not only from over it.
const LEGEND_AT := Vector3(0, 0.0005, 0.076)
const LEGEND_WIDTH := 0.12
const LEGEND_SIZE := 170
## Half its footprint and how tall it stands: its walker solid (Stations' row says the same).
const FOOT := Vector2(0.2, 0.16)
const TOP := 1.33
## Where its plaque hangs: on the cabinet's front.
const PLAQUE_AT := Vector3(0, 0.55, 0.131)
const PLAQUE_WIDTH := 0.32
## The REC key's cap, unlit and lit. Lit is also said, in words on the screen and the key's card.
const REC_DARK := Color(0.32, 0.06, 0.05)
const REC_LIT := Color(1.0, 0.16, 0.1)
## What a sample cassette says it came from.
const TRACK_NAME := "SAMPLER"

## A hand here pressed REC: `on` for this player's next sound, or off. For the studio to do, or ask.
signal rec_pressed(on: bool)
## On the host: `made`, a sample cassette of `file_name`, caught from `from`'s use.
signal sampled(made: Item, file_name: String, from: int)
## Something for `peer` to be told: what was caught, or why it could not be kept.
signal told(peer: int, text: String)
## REC went off here because it caught something (the host's): for the room to be told.
signal armed_changed()

## The room whose items it hears and whose rack its cassettes go into.
var items: ItemRoom = null
## Who REC is armed for, the room's `sampler` row; 0 is off.
var armed_by := 0:
	set(v):
		if v == armed_by:
			return
		armed_by = v
		_show()
## Whether this machine's word is the room's (Session.is_authority): only the host catches.
var authority: Callable = Callable()
## Where file `name` goes in this project's media: DAWBackend.media_path, or the suite's own.
var media_path: Callable = Callable()
## Who is local here (Session.local_peer_id), and what to call a peer (Session.name_of).
var local_peer: Callable = Callable()
var name_of: Callable = Callable()
var rec: Rec
var _screen: Label3D
var _detail: Label3D
var _cap: StandardMaterial3D
var _since_shown := 0.0
const SHOW_EVERY := 0.25


func _init() -> void:
	name = "Sampler"


func _ready() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	rec = Rec.new()
	rec.sampler = self
	rec.name = "Rec"
	rec.position = Vector3(REC_AT.x, DECK_TOP + 0.004, REC_AT.y)
	add_child(rec)
	_cap = rec.cap.material_override as StandardMaterial3D
	_screen = _line("Screen", HEADLINE_SIZE, HEADLINE_Y)
	_detail = _line("ScreenDetail", DETAIL_SIZE, DETAIL_Y)
	var plaque := Stations.plaque(&"sampler", PLAQUE_WIDTH)
	plaque.position = PLAQUE_AT
	add_child(plaque)
	_show()


## One of the screen's lines, at height `y`.
func _line(named: String, size: int, y: float) -> Label3D:
	var line := Label3D.new()
	line.name = named
	line.pixel_size = 0.0002
	line.font_size = size
	line.outline_size = 0
	line.modulate = Color(0.75, 0.95, 0.8)
	line.shaded = false
	line.double_sided = false
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.position = Vector3(0, y, SCREEN_Z + 0.0015)
	Lettering.range_to_legibility(line)
	add_child(line)
	return line


## The screen kept to what the room has: a sample cassette made or binned anywhere, a guest's
## room arriving, is on it within a quarter second.
func _process(delta: float) -> void:
	_since_shown += delta
	if _since_shown >= SHOW_EVERY:
		_show()


## The mic's grille, in global space: what REACH is measured from.
func mic_point() -> Vector3:
	return global_transform * MIC_AT


## The sampler as the walker's solid, at `spot` (its transform in the venue's frame).
static func solid(spot: Transform3D) -> Dictionary:
	return {"c": Vector2(spot.origin.x, spot.origin.z), "h": FOOT, "a": spot.basis.get_euler().y, "top": TOP}


func _me() -> int:
	return int(local_peer.call()) if local_peer.is_valid() else 1


func _is_authority() -> bool:
	return bool(authority.call()) if authority.is_valid() else true


func _name(peer: int) -> String:
	if peer == _me():
		return "your"
	return "%s's" % (str(name_of.call(peer)) if name_of.is_valid() else "someone")


## REC pressed by a hand here: on for this player's next sound, or off again when it is on for
## them (or for anyone: a press while it waits on somebody else's sound stops it too).
func press() -> void:
	rec_pressed.emit(armed_by == 0)


## Whether a use of `item` by `from` is one REC catches now: armed, and the item within REACH of
## the mic or in the hand of whoever armed it (a use is always its user's hand's; a bounce, its
## thrower's).
func catches(item: Item, from: int) -> bool:
	if armed_by == 0 or item == null or not is_instance_valid(item) or not is_inside_tree():
		return false
	return from == armed_by or item.middle().distance_to(mic_point()) <= REACH


## On the host: `item`, used by `from`, rang Foley's `kind` take `take` (Item.use_kind and
## use_take, InstrumentItem.sound_kind and sound_take, Item.rang), played `pitch` fast (Item.
## use_pitch, InstrumentItem.tune_at). Caught if REC `catches` it: that take, at that pitch
## (Foley.resampled), written as a WAV into the media (`write`), a sample cassette of it minted into
## the rack, and REC off. The cassette, or null for nothing caught (or nothing kept, and the presser
## told why).
func heard(item: Item, kind: StringName, take: int, from: int, pitch := 1.0) -> Item:
	if not _is_authority() or kind == &"" or take < 0 or items == null or not catches(item, from):
		return null
	return heard_stream(item, kind, Foley.resampled(Foley.take_of(kind, take), pitch), from)


## On the host: `stream` (16-bit mono), a sound of `item` that is not a Foley take, Foley's word
## for what it is `kind` (the platter's scratch, Platter.render_scratch, slice 27), made by `from`:
## caught as `heard` catches a take, if REC `catches` it. The cassette, or null.
func heard_stream(item: Item, kind: StringName, stream: AudioStreamWAV, from: int) -> Item:
	if not _is_authority() or kind == &"" or items == null or not catches(item, from):
		return null
	if stream == null or stream.data.is_empty():
		return null
	var presser := armed_by
	armed_by = 0
	armed_changed.emit()
	var file_name := next_name(kind)
	var data := sample_data(file_name, kind, stream)
	var why := ItemRoom.made_refusal(items.made, var_to_bytes(data).size())
	if why.is_empty() and not write(stream, _path(file_name)):
		why = "The sampler could not write %s into the project's media." % file_name
	if not why.is_empty():
		told.emit(presser, why)
		return null
	var made := items.mint(CassetteItem.KIND, data, from)
	if made == null:
		DirAccess.remove_absolute(_path(file_name))
		told.emit(presser, items.mint_refusal)
		return null
	var n := _free_slot()
	if n >= 0:
		items.slot(made, CassetteRack.RACK, n)
	told.emit(presser, "Sampled %s: %s, a cassette on the rack%s. Hold it to your ear to hear it, or paste it onto a track."
			% [_what(item, kind), file_name, " (slot %d)" % (n + 1) if n >= 0 else "'s tray"])
	sampled.emit(made, file_name, from)
	_show()
	return made


## What a sound of each kind is, of the thing that made it, for the notice.
const SAID := {&"duck_squeeze": "squeeze", &"duck_release": "letting go", &"ball_bounce": "bounce",
		&"yoyo_trick": "trick", &"cards_trick": "trick", &"platter_scratch": "scratch"}


## "the rubber duck's squeeze", "the deck of cards' trick", "the tambourine", for the notice.
static func _what(item: Item, kind: StringName) -> String:
	var title := item.item_title().to_lower() if item != null else "something"
	if SAID.has(kind):
		return "the %s%s %s" % [title, "'" if title.ends_with("s") else "'s", SAID[kind]]
	return "the %s" % title


func _path(file_name: String) -> String:
	if media_path.is_valid():
		return str(media_path.call(file_name))
	if DAW.backend != null:
		return DAW.backend.media_path(file_name)
	return ProjectSettings.globalize_path(AudioTake.DIR.path_join(file_name))


## The next free name for a sample of `kind` (`duck_squeeze_3.wav`): numbered from 1, past any file
## of that name in the media and any made cassette's clip of it.
func next_name(kind: StringName) -> String:
	var taken := {}
	if items != null:
		for id in items.made:
			var row: Variant = items.made[id]
			if row is Array and (row as Array).size() == 3 and row[2] is PackedByteArray:
				var d: Variant = bytes_to_var(row[2])
				if d is Dictionary and d.get("clip") is Dictionary:
					taken[str((d["clip"] as Dictionary).get("source", ""))] = true
	var n := 1
	while true:
		var file_name := "%s_%d.wav" % [kind, n]
		if not taken.has(file_name) and not FileAccess.file_exists(_path(file_name)):
			return file_name
		n += 1
	return ""


## `stream` (16-bit mono, as Foley makes every sound) written whole to `path` as a WAV: its own
## samples after a RIFF header at its own rate, so the file is the stream to the byte. Whether it
## was written.
static func write(stream: AudioStreamWAV, path: String) -> bool:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(AudioTake.header(stream.data.size() / 2, stream.mix_rate))
	f.store_buffer(stream.data)
	f.close()
	return true


## What a sample cassette of `file_name`, Foley's `kind`, carries: an audio clip of the whole file
## from its start, named for it ("duck squeeze 3"), from the SAMPLER, and which sound it is.
static func sample_data(file_name: String, kind: StringName, stream: AudioStreamWAV) -> Dictionary:
	var seconds := float(stream.data.size() / 2) / float(stream.mix_rate)
	var clip := {"start": 0.0, "length": seconds, "name": file_name.get_basename().replace("_", " "),
			"source": file_name, "offset": 0.0}
	return {"clip": clip, "track": -1, "index": -1, "track_name": TRACK_NAME, "sample": String(kind)}


## The cassette rack's first free slot, or -1.
func _free_slot() -> int:
	if items == null or not items.holders.has(CassetteRack.RACK):
		return -1
	for n in (items.holders[CassetteRack.RACK] as Array).size():
		if items.in_slot(CassetteRack.RACK, n) == null:
			return n
	return -1


## The newest sample cassette in the room, or null.
func latest() -> CassetteItem:
	if items == null:
		return null
	var ids := items.made_ids()
	ids.reverse()
	for id in ids:
		var c := items.items.get(id) as CassetteItem
		if c != null and c.data.has("sample"):
			return c
	return null


## The key lit while armed, and the screen saying so in words, two short lines large enough to
## read from where you stand: whose next sound it waits for and where, or what to do and what it
## last caught.
func screen_text() -> String:
	return "\n".join(screen_lines())


## The screen's headline and the line under it (`screen_text`).
func screen_lines() -> PackedStringArray:
	if armed_by != 0:
		return PackedStringArray(["REC · %s NEXT SOUND" % _name(armed_by).to_upper(),
				"by the mic, or in %s hand" % ("your" if armed_by == _me() else "their")])
	var last := latest()
	return PackedStringArray(["PRESS REC", "last: %s" % last.clip_name() if last != null else "then make a sound by the mic"])


func _show() -> void:
	_since_shown = 0.0
	if _cap != null:
		_cap.albedo_color = REC_LIT if armed_by != 0 else REC_DARK
		_cap.emission_enabled = armed_by != 0
		_cap.emission = REC_LIT
		_cap.emission_energy_multiplier = 1.4
	if _screen != null:
		var lines := screen_lines()
		if lines[0] != _screen.text:
			_screen.text = lines[0]
			Lettering.fit(_screen, SCREEN_WIDTH, HEADLINE_SIZE, 60)
		if lines[1] != _detail.text:
			_detail.text = lines[1]
			Lettering.fit(_detail, SCREEN_WIDTH, DETAIL_SIZE, 50)
	if rec != null:
		var said := "REC ON" if armed_by != 0 else "REC"
		if said != rec.legend.text:
			rec.legend.text = said
			Lettering.fit(rec.legend, LEGEND_WIDTH, LEGEND_SIZE, 80)


## The REC key: round, on the deck's right, lit while armed. A press is the sampler's (`press`).
class Rec extends ControlAffordance:
	var sampler: Sampler
	var cap: MeshInstance3D
	var legend: Label3D

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = REC_RADIUS + 0.008
		cylinder.height = 0.04
		shape.shape = cylinder
		shape.position = Vector3(0, 0.012, 0)
		add_child(shape)
		cap = MeshInstance3D.new()
		cap.name = "Cap"
		var mesh := CylinderMesh.new()
		mesh.top_radius = REC_RADIUS
		mesh.bottom_radius = REC_RADIUS
		mesh.height = 0.014
		cap.mesh = mesh
		cap.position = Vector3(0, 0.007, 0)
		var paint := StandardMaterial3D.new()
		paint.albedo_color = REC_DARK
		paint.roughness = 0.5
		cap.material_override = paint
		add_child(cap)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.text = "REC"
		legend.pixel_size = 0.0002
		legend.font_size = LEGEND_SIZE
		legend.outline_size = 0
		legend.modulate = Color(0.98, 0.95, 0.9)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Lying on the deck in front of the key, its top toward the back: read by whoever stands at
		# the front, from where they stand.
		legend.rotation.x = -PI * 0.5
		legend.position = LEGEND_AT
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "SAMPLER  REC"

	func _default_readout() -> String:
		if sampler == null or sampler.armed_by == 0:
			return "off"
		return "on: catching %s next sound" % sampler._name(sampler.armed_by)

	func hint() -> String:
		return "press, then squeeze, hit or shake something, do a yo-yo or card trick, or bounce the ball, within %.1f m of the mic or in your hand: one sample, a cassette on the rack · press again to stop" % REACH

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if sampler != null:
			sampler.press()
