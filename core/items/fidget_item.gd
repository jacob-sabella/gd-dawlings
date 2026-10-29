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
##
## A trick is a use with a take (Item.use_take): the count of tricks with this one, which says
## which trick it is and which of Foley's takes its sounds ring. Sent with the press
## (Session.item_used), so a copy that hears it plays that trick, not its own count's next. A kind
## whose tricks make sounds lists them (`trick_sounds`) and names the whole of one (`trick_kind`):
## the sampler (Sampler) catches a trick as that one sound, every sound it rings where it rings it
## (`trick_stream`).

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


## Override: the sounds trick `k` rings and when, for `_pose` to play at their moments and the
## sampler to keep whole: each [how far through it (0 to 1), Foley's kind (Foley.take_of), level
## (dB), how fast it is played].
func trick_sounds(_k: int) -> Array:
	return []


## Override: what Foley calls one whole trick of this kind (Foley.take_of: `yoyo_trick`), the
## use the sampler catches; &"" for one it has no sound for.
func trick_kind() -> StringName:
	return &""


## A press starts a trick: the trick's sound, its kind's `trick_kind`.
func use_kind(down: bool) -> StringName:
	return trick_kind() if down else &""


## Trick number `take` (1 for the first since it was picked up) of tricks `sounds` (each trick's
## `trick_sounds`), each `seconds` long, heard whole: every sound it rings, at its moment, played as
## the trick plays it, Foley's take `take` of each. Kept as `key`.
static func trick_stream(key: String, sounds: Array, seconds: Array, take: int) -> AudioStreamWAV:
	var k := posmod(take - 1, sounds.size())
	take = posmod(take, Foley.TAKES)
	var layers: Array = []
	for ring: Array in sounds[k]:
		layers.append([float(ring[0]) * float(seconds[k]), Foley.take_of(ring[1], take), ring[2], ring[3]])
	return Foley.layered("%s_%d_%d" % [key, k, take], layers)


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
	return posmod(tricks_done, tricks())


func hint() -> String:
	if state == State.HELD and not is_held_elsewhere():
		return "click to %s" % trick_name(next_trick())
	return _hint("click to pick up, then click to play with it")


## A press: the next trick, or the one somebody else's hand played (`heard_use`'s take, their
## count).
func use(down: bool) -> void:
	if not down:
		return
	finish()
	if _heard_take >= 1:
		tricks_done = _heard_take - 1
	playing = next_trick()
	tricks_done += 1
	use_take = tricks_done
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


## Pocketed mid-trick: the trick is over, and it goes in as it lies at rest.
func on_stowed() -> void:
	finish()
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
	for ring: Array in trick_sounds(k):
		if cue(p, float(ring[0])):
			Foley.play(self, Foley.take_of(ring[1], tricks_done), float(ring[2]), float(ring[3]))
	_was = p


## Whether the trick has just come to `at` (0 to 1) of the way through: the moment for a sound.
## Never in a trick cut short by the next press.
func cue(p: float, at: float) -> bool:
	return not _cut and _was < at and p >= at


## 0 before `a`, 1 after `b`, eased between.
static func span(p: float, a: float, b: float) -> float:
	return smoothstep(a, b, p)
