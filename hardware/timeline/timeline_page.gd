class_name TimelinePage
extends Node3D

## One page of the timeline's deck (see TimelineDeck): the controls for one kind of thing -- the
## selected item, the picked track, the tempo, writing the song out -- as tokens and rails,
## laid out left to right by the deck. A page only says what its controls are and what they do;
## where they go is the deck's.

## The TimelineSurface. Typed loosely so the files load in any order.
var surface: Node
## What the tab is called (its hover card), and the mark on it.
var tab_name := ""
var tab_glyph := &""
## Said where the controls would be while there is nothing for them to act on, or "".
var notice := ""

var _controls: Array[Node3D] = []


## The page's controls, in the order they are laid out.
func controls() -> Array[Node3D]:
	return _controls


## A gap before the next control: a group ends here.
const BREAK := &"break"
var _breaks: Array[int] = []


func breaks_before(control: Node3D) -> bool:
	return _controls.find(control) in _breaks


func _group() -> void:
	_breaks.append(_controls.size())


func _key(key_name: String, mark: StringName, colour: Color, title: String, act: Callable,
		what: Callable = Callable(), toggle := false) -> GlyphKey:
	var key := GlyphKey.new()
	key.name = key_name
	key.glyph = mark
	key.label = title
	key.led_colour = colour
	key.toggle = toggle
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	if what.is_valid():
		key.describe_value = func(_v: float) -> String: return what.call()
	add_child(key)
	_controls.append(key)
	return key


func _slider(slider_name: String, mark: StringName, colour: Color, title: Callable,
		text: Callable) -> GlyphRail:
	var s := GlyphRail.new()
	s.name = slider_name
	s.glyph = mark
	s.led_colour = colour
	s.describe_title = title
	s.describe_value = text
	add_child(s)
	_controls.append(s)
	return s


## Called by the deck when the page is shown, and by the page itself when what it shows changes.
func refresh() -> void:
	pass
