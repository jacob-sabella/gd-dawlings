class_name RouletteDoor
extends Node3D

## The way into the Rig Roulette room from a venue, and the way back out of it: a frame in the
## venue's own carpentry round a felt-green portal, a sign over it and a big button on it. A DUMB
## DOOR: it only says it was used (`used`); whether the band may go, and where, is the studio's.
##
## Its origin is the floor in the middle of the opening and +Z is the way it faces, 7cm off its
## wall (`Venue.rig_roulette_door`), the same convention as the roulette panel's spot. Where there
## is no wall (an open venue) it stands as a gate: the frame to the floor, the portal behind it.

signal used()

const OPENING := Vector2(1.0, 2.2)
const POST := 0.1
const DEPTH := 0.13
const LINTEL := 0.12
## The footprint a person or a piece of furniture stays out of: half extents, along and across.
## Everything stands a hair off the floor, so no bottom face shares the venue's own floor-level plane.
const LIFT := 0.002
const HALF := Vector2(OPENING.x * 0.5 + POST, DEPTH * 0.5)

var leaving := false:
	set(value):
		leaving = value
		if _sign != null:
			_sign.text = _words()
var venue_name := "the band"

var _sign: Label3D
var _button: PanelButton


func _words() -> String:
	return "BACK TO THE BAND" if leaving else "RIG ROULETTE"


func _ready() -> void:
	var frame := Materials.furniture()
	var pane := StandardMaterial3D.new()
	pane.albedo_color = Color(0.05, 0.22, 0.15)
	pane.roughness = 0.9
	pane.emission_enabled = true
	pane.emission = Color(0.06, 0.4, 0.26)
	pane.emission_energy_multiplier = 0.9
	for sx in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(POST, OPENING.y - LIFT, DEPTH), Vector3(sx * (OPENING.x * 0.5 + POST * 0.5), (OPENING.y + LIFT) * 0.5, 0.0),
				frame, "Post%s" % ("L" if sx < 0 else "R"))
	ZoneKit.block(self, Vector3(OPENING.x + POST * 2.0, LINTEL, DEPTH), Vector3(0, OPENING.y + LINTEL * 0.5, 0.0), frame, "Lintel")
	ZoneKit.block(self, Vector3(OPENING.x - 0.002, OPENING.y - LIFT * 2.0, 0.02), Vector3(0, (OPENING.y + LIFT * 2.0) * 0.5, -0.02), pane, "Portal")
	# Brass inlaid in the lintel's face and the posts' fronts, a hair proud, so the frame reads in a dark corner.
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.56, 0.24)
	brass.metallic = 0.85
	brass.roughness = 0.32
	ZoneKit.block(self, Vector3(OPENING.x + POST * 2.0 - 0.04, 0.02, 0.01), Vector3(0, OPENING.y + 0.02, DEPTH * 0.5 + 0.005), brass,
			"LintelBrass")
	for sx in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.02, OPENING.y - 0.04, 0.01), Vector3(sx * (OPENING.x * 0.5 + POST * 0.5), OPENING.y * 0.5,
				DEPTH * 0.5 + 0.005), brass, "PostBrass%s" % ("L" if sx < 0 else "R"))
	var lamp := SpotLight3D.new()
	lamp.name = "DoorLight"
	lamp.light_color = Color(1.0, 0.84, 0.62)
	lamp.light_energy = 3.0
	lamp.spot_range = 4.0
	lamp.spot_angle = 55.0
	lamp.shadow_enabled = false
	lamp.transform = Transform3D(Basis.looking_at(Vector3(0, -0.6, -0.5).normalized(), Vector3.UP),
			Vector3(0, OPENING.y + LINTEL + 0.5, 0.9))
	add_child(lamp)

	_sign = Label3D.new()
	_sign.name = "Sign"
	_sign.font_size = 120
	_sign.pixel_size = 0.0011
	_sign.text = _words()
	_sign.position = Vector3(0, OPENING.y + LINTEL * 0.5 + 0.025, DEPTH * 0.5 + 0.003)
	_sign.modulate = Color(0.95, 0.82, 0.5)
	_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_sign)
	add_child(_sign)

	_button = PanelButton.new()
	_button.name = "DoorButton"
	_button.led_colour = Color(0.3, 0.85, 0.4)
	_button.position = Vector3(0, 1.25, 0.0)
	_button.scale = Vector3.ONE * 8.0
	_button.pressed.connect(_on_pressed)
	_button.describe_title = func() -> String: return "RIG ROULETTE  " + ("BACK" if leaving else "ENTER")
	_button.lit = true
	add_child(_button)


## A footprint of this door on the floor, for what has to keep clear of it.
func footprint() -> Dictionary:
	return {"c": Vector2(global_position.x, global_position.z), "h": HALF, "a": global_basis.get_euler().y, "top": OPENING.y + LINTEL}


func _on_pressed() -> void:
	# A door is not a latch: the light stays on, ready for the next time.
	_button.lit = true
	used.emit()
