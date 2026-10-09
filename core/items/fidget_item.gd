class_name FidgetItem
extends Item

## Something to turn over in your hand while somebody else plays: a stack of chips, a deck of
## cards (docs/items_loop.md). It does nothing for the session; it is what your hands do.
##
## Each press of the hand's button starts its next trick, in turn (`tricks`, `trick_name`), and
## the trick plays out by itself over a moment (`trick_seconds`, `pose`). A press while one is
## still playing finishes that one at once and starts the next, so a quick run of clicks never
## queues up and everybody's copy -- played by the same presses, relayed (Item.work) -- ends
## each trick the same way: the trick count is the whole of its state.

## How many tricks have been started since it was last picked up: which comes next, and the
## seed for anything a trick deals (CardsItem's faces).
var tricks_done := 0
## The trick playing, or -1, and how far into it.
var playing := -1
var _t := 0.0
## How far the last pose was, for `cue`; and whether this pose is a trick cut short, which makes
## no sound.
var _was := 0.0
var _cut := false


## Override: how many tricks it has, played in turn.
func tricks() -> int:
	return 1


## Override: trick `k`'s name, as the hint offers it: "riffle".
func trick_name(_k: int) -> String:
	return ""


## Override: how long trick `k` takes.
func trick_seconds(_k: int) -> float:
	return 0.5


## Override: trick `k` begins. What it will leave behind is decided here.
func begin(_k: int) -> void:
	pass


## Override: trick `k`, `p` of the way through (0 to 1): every part where it is now.
func pose(_k: int, _p: float) -> void:
	pass


## Override: trick `k` is over (`pose` has been given 1): what it moved is now where it rests.
func end(_k: int) -> void:
	pass


## Override: everything back in its resting place, as it is on the shelf.
func rest() -> void:
	pass


## Which trick a press now starts.
func next_trick() -> int:
	return tricks_done % tricks()


func hint() -> String:
	if state == State.HELD and not is_held_elsewhere():
		return "click to %s" % trick_name(next_trick())
	return _hint("click to pick up, then click to play with it")


func use(down: bool) -> void:
	if not down:
		return
	finish()
	playing = next_trick()
	tricks_done += 1
	_t = 0.0
	begin(playing)
	_was = -1.0
	_pose(playing, 0.0)
	set_process(true)


## The trick playing, done at once.
func finish() -> void:
	if playing < 0:
		return
	var k := playing
	playing = -1
	_cut = true
	_pose(k, 1.0)
	_cut = false
	end(k)


func on_put_down() -> void:
	finish()
	tricks_done = 0
	rest()


func _ready() -> void:
	super()
	set_process(false)


func _process(delta: float) -> void:
	if playing < 0:
		set_process(false)
		return
	_t += delta
	var p := _t / trick_seconds(playing)
	if p >= 1.0:
		# Played out: its last sounds are still to come.
		var k := playing
		playing = -1
		_pose(k, 1.0)
		end(k)
		set_process(false)
		return
	_pose(playing, p)


func _pose(k: int, p: float) -> void:
	pose(k, p)
	_was = p


## Whether the trick has just come to `at` (0 to 1) of the way through: the moment for a sound.
## Never in a trick cut short by the next press.
func cue(p: float, at: float) -> bool:
	return not _cut and _was < at and p >= at


## 0 before `a`, 1 after `b`, eased between.
static func span(p: float, a: float, b: float) -> float:
	return smoothstep(a, b, p)
