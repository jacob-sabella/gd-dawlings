class_name HandbellItem
extends InstrumentItem

## One of four handbells, rung in the song's chord (docs/spatial_loop.md slice 4; idea #32, a
## handbell choir). A bell's job is its number: bell 1 rings the chord's root, 2 its third, 3 its
## fifth and 4 its top (the seventh in a four-note chord, else the root an octave up), voiced at
## centre 72 (`Harmony.voiced`: in Am they ring A4 C5 E5 A5, in F F5 A5 C6 F6). So a band holding
## the four cannot clash, and one player can hold two and pocket the others.
##
## It is played the way the hand percussion is (InstrumentItem): swing it and stop, and it rings;
## on a desktop the mouse's wiggle swings it, and a click rings it. What it rings is a note of the
## song at the one song position the hit is played to (`note_at`), so the sound heard here, the
## note recorded (on InstrumentItem.MELODIC_CHANNEL, NOTE_SECONDS long) and the song position sent
## to the room all agree, across a bar line, on every machine. Its sound is Foley.handbell, rung
## at C5 and pitched to the note.
##
## The tab at the foot of its handle letters its number and the note it rings now, so which bell is
## which, and what it will ring, is read rather than told by colour; it changes at each chord
## change. Carried by a hand here under a chord shape, it rings the shape's chord tone, and its tab
## says so (InstrumentItem.harmony_at, docs/spatial_loop.md part two, slice 32). Its home is a seat
## on the bell stand beside the chord harp (Venue.bell_spot).

const MODEL := "res://assets/models/handbell.glb"
const STAND_MODEL := "res://assets/models/bell_stand.glb"
## tools/blender/handbell.py's: the mouth's radius, the bell's whole height, its tab's height.
const MOUTH := 0.05
const HEIGHT := 0.22
const TAB_Y := 0.13
## Where the tab's face is, in front of the loop (the model's +Z, turned to face -Z here).
const TAB_FACE := 0.012
## The stand: its top's size, its padded top (where a bell's mouth rests), the seats' spacing.
const STAND := Vector2(0.54, 0.24)
const STAND_TOP := 0.80
const PEG_SPACING := 0.125
## The voicing's centre (Harmony.voiced): C5.
const CENTRE := 72
## How many bells there are, and each one's job in the chord, by number.
const COUNT := 4
const JOBS := ["root", "third", "fifth", "top"]
## How long a ring is as a note in a take (s): longer than a drum's tick, as a bell is heard.
const RING_SECONDS := 0.8
## How often the tab's lettering is looked at again (s): a chord change shows within this.
const RELETTER := 0.1
const BRONZE := Color(0.78, 0.6, 0.3)
const LEATHER := Color(0.2, 0.12, 0.07)
const TAB := Color(0.12, 0.08, 0.05)
const INK := Color(0.96, 0.92, 0.8)

## Which bell this is, 1 to 4.
var number := 1
var _number_label: Label3D
var _note_label: Label3D
var _reletter_in := 0.0


func _init(n := 1) -> void:
	number = clampi(n, 1, COUNT)
	id = StringName("bell%d" % number)
	super()
	_shape.position.y = HEIGHT * 0.5
	_reletter()


func item_title() -> String:
	return "HANDBELL %d" % number


func hint() -> String:
	return _hint("click to pick up, then swing the mouse to ring it, or click to ring it")


## What it rings now, and why: "rings C5, the third of Am". With no key in the song, says so.
func readout() -> String:
	var h := harmony_at(InstrumentItem.now())
	var said := "rings %s, the %s of %s" % [h.note_name(note_at(InstrumentItem.now())), JOBS[number - 1], h.chord_name]
	if not h.named:
		said += " (NO KEY SET)"
	return "%s  ·  %s" % [super(), said]


## Its chord tone at `seconds`: the chord there voiced at CENTRE, this bell's number's place in it.
func note_at(seconds: float) -> int:
	var tones := Harmony.voiced(harmony_at(seconds), CENTRE, COUNT)
	return tones[number - 1] if tones.size() >= number else CENTRE


## Its chord tone's General MIDI meaning has no drum: `pitch()` is what it rings now.
func pitch() -> int:
	return note_at(InstrumentItem.now())


func channel() -> int:
	return MELODIC_CHANNEL


func note_seconds() -> float:
	return RING_SECONDS


func sound_kind(_struck: bool) -> StringName:
	return &"handbell"


## From C5, where Foley.handbell rings, to `note`.
func sound_pitch(note: int) -> float:
	return pow(2.0, float(note - Foley.HANDBELL_NOTE) / 12.0)


func _process(delta: float) -> void:
	_reletter_in -= delta
	if _reletter_in <= 0.0:
		_reletter_in = RELETTER
		_reletter()


## The tab's lettering: its number, and the note it rings now.
func _reletter() -> void:
	if _note_label == null:
		return
	var at := InstrumentItem.now()
	var said := harmony_at(at).note_name(note_at(at))
	if _note_label.text != said:
		_note_label.text = said


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	# Its tab toward the item's front, -Z.
	model.rotation.y = PI
	root.add_child(model)
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = BRONZE
	bronze.metallic = 0.85
	bronze.roughness = 0.3
	var clapper := StandardMaterial3D.new()
	clapper.albedo_color = Color(0.25, 0.22, 0.2)
	clapper.roughness = 0.6
	var leather := StandardMaterial3D.new()
	leather.albedo_color = LEATHER
	leather.roughness = 0.75
	var tab := StandardMaterial3D.new()
	tab.albedo_color = TAB
	tab.roughness = 0.8
	var swap := {"bronze": bronze, "clapper": clapper, "leather": leather, "tab": tab}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	_number_label = _letter(str(number), 64, Vector3(0, TAB_Y + 0.006, -TAB_FACE))
	root.add_child(_number_label)
	_note_label = _letter("", 34, Vector3(0, TAB_Y - 0.01, -TAB_FACE))
	root.add_child(_note_label)
	return root


## Lettering on the tab's face, facing out of the item's front.
static func _letter(text: String, size: int, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = 6
	label.pixel_size = 0.0003
	label.modulate = INK
	label.outline_modulate = Color(0.04, 0.03, 0.02)
	label.position = at
	label.rotation.y = PI
	label.double_sided = false
	return label


## Round the bell and up its handle: a bell on a stand is a small thing to point at.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(MOUTH * 2.0 + 0.02, HEIGHT + 0.01, MOUTH * 2.0 + 0.02)
	return s


func centre_height() -> float:
	return 0.07


## Its jack is on its front, low by the mouth, under the tab: on the stand its ends all but touch
## the next bell's.
func jack_point() -> Vector3:
	return Vector3(0, 0.045, -MOUTH - 0.01 - JackSocket.REACH * 0.6)


func jack_out() -> Vector3:
	return Vector3.FORWARD


## Held by its loop, the bell hanging under the hand with its mouth tipped away, the tab turned
## back toward you so you can read what it rings.
func held_pose() -> Transform3D:
	var turn := Basis(Vector3.RIGHT, 0.55) * Basis(Vector3.UP, PI - 0.3)
	return Transform3D(turn, -(turn * Vector3(0, 0.165, 0)))


func flies() -> Dictionary:
	return {"bounce": 0.15, "roll": 4.0, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.handbell(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, -3.0),
			sound_pitch(note_at(InstrumentItem.now())))


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()


## The stand the four bells rest on (tools/blender/handbell.py's), its origin the middle of its
## feet, its front (+Z) toward whoever rings them. Only drawn: its solid is `stand_solid`.
static func stand() -> Node3D:
	var model := (load(STAND_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "BellStand"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.12)
	wood.roughness = 0.5
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.1, 0.16, 0.12)
	pad.roughness = 0.95
	var peg := StandardMaterial3D.new()
	peg.albedo_color = Color(0.14, 0.13, 0.12)
	peg.roughness = 0.9
	var swap := {"wood": wood, "pad": pad, "peg": peg}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	# Its plaque on its front, under the bells (Stations.plaque).
	var plaque := Stations.plaque(&"bells", STAND.x - 0.02)
	plaque.position = Vector3(0, STAND_TOP - 0.2, STAND.y * 0.5 + 0.006)
	model.add_child(plaque)
	return model


## The stand's walker solid, stood at `at` (the walker's {c, h, a, top}).
static func stand_solid(at: Transform3D) -> Dictionary:
	return {"c": Vector2(at.origin.x, at.origin.z), "h": STAND * 0.5, "a": at.basis.get_euler().y, "top": STAND_TOP}


## Bell `n`'s seat (1 to 4), in the stand's frame: lowest on the left as you face it, its mouth on
## the pad, its tab toward you.
static func seat(n: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3((float(clampi(n, 1, COUNT)) - 2.5) * PEG_SPACING, STAND_TOP, 0))
