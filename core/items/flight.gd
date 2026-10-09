class_name Flight
extends RefCounted

## A thrown item's whole flight, worked out the moment it leaves the hand.
##
## Throws are launched, not streamed (docs/items_loop.md). Everyone is sent the same launch --
## where it left the hand, how fast and which way, how it spins -- once and reliably, and every
## machine flies it here, from that, against the same floor. The same numbers in give the same
## path out: no clock, no randomness, a fixed step. So a duck thrown across the room is in the
## same place on every screen without one position being sent while it flies.
##
## Something with wings (`wing`, see `fly`) glides instead of falling, until it touches
## anything: lift across its path that grows with the square of its speed, drag along it, and a
## bank that tips the lift sideways into a turn. Thrown at its gliding speed it crosses the room;
## thrown hard it climbs, runs out of speed and stalls; thrown at the floor it noses in. Once it
## has touched something it is paper on the floor, and falls and slides like anything else.
##
## It is all worked out up front rather than stepped as it goes. A flight is a few seconds, a
## few hundred steps of arithmetic, and having the end of it at the start is what lets the room
## say where it will land the moment it is thrown, and an item decide then whether it can stay
## there.
##
## The world it flies in is the walker's (Walker.walkable, Walker.fixed), in the item room's
## frame: the floor, the room's walls at its edges, and the venue's solids -- a riser, a booth
## wall, a palm trunk. Not the gear: an item that comes down on the desk is somewhere it cannot
## stay, and goes home from there (ItemRoom).

## Fine enough that a fast throw does not step through a booth wall in one go (9 m/s is 7.5cm a
## step, against walls that are thicker than that).
const STEP := 1.0 / 120.0
const GRAVITY := 9.8
## A throw that is still going after this long -- rolling round a curved wall -- is stopped where
## it is.
const LONGEST := 10.0
## Slower than this, on the floor, and it has stopped.
const SETTLE_SPEED := 0.05
## A bounce that leaves the floor slower than this does not leave it: the last, tiny hops are
## rolled out instead, rather than counted down to a thousand bounces a millimetre high.
const HOP_SPEED := 0.35
## How much of its speed along a wall or the floor a bounce keeps.
const SCUFF := 0.85

## Where it is at each step from launch, in the item room's frame.
var points := PackedVector3Array()
## How it is turned at each step.
var turns: Array[Quaternion] = []
## When it hit something, in seconds from launch, and how hard (the speed into the surface).
var hits := PackedFloat32Array()
var hit_speeds := PackedFloat32Array()
## Where it comes to rest, and which way it faces there.
var rest := Vector3.ZERO
var rest_yaw := 0.0


## How long it flies for.
func seconds() -> float:
	return maxf(0.0, (points.size() - 1) * STEP)


## Where it is `t` seconds after launch: between the two steps either side.
func at(t: float) -> Transform3D:
	if points.is_empty():
		return Transform3D(Basis(Vector3.UP, rest_yaw), rest)
	var f := clampf(t / STEP, 0.0, points.size() - 1.0)
	var i := mini(int(f), points.size() - 1)
	var j := mini(i + 1, points.size() - 1)
	var w := f - i
	return Transform3D(Basis(turns[i].slerp(turns[j], w)), points[i].lerp(points[j], w))


## Fly something from `origin` at `velocity`, spinning at `spin` (rad/s about each axis), from
## `turn`, in a room with `floor` (walkable rects) and `solids` (Walker.fixed footprints).
## `bounce` is how much of its speed into a surface it gets back; `roll` how fast it slows
## sliding along the floor (m/s²); `drag`, the air's, per second.
## `wing`, for a glider: {"trim": the speed it glides at (m/s), "glide": how far it goes forward
## for each metre it sinks, "stall": the speed below which its wings stop holding it up,
## "most": the most lift it can make, in g (a paper wing flexes and spills the rest), "bank":
## how far it leans of itself (rad, + to the right), "flutter": faster than this, the paper
## flutters and slows hard ("flap" how hard), "settle": how long out of the hand before its wing
## holds it up}.
static func fly(origin: Vector3, velocity: Vector3, spin: Vector3, turn: Quaternion,
		floor: Array, solids: Array, bounce := 0.35, roll := 3.0, drag := 0.08,
		wing := {}) -> Flight:
	var f := Flight.new()
	var p := origin
	var v := velocity
	var w := spin
	var q := turn.normalized()
	var grounded := false
	var gliding := not wing.is_empty() and velocity.length() > 0.01
	var bank := 0.0
	if gliding:
		# A throw with a twist about the way it is going leans it over further.
		bank = clampf(float(wing.get("bank", 0.0)) + spin.dot(velocity.normalized()) * 0.05, -0.9, 0.9)
		q = _wings(velocity.normalized(), bank)
	var steps := int(LONGEST / STEP)
	f.points.append(p)
	f.turns.append(q)
	for n in steps:
		var dt := STEP
		if gliding:
			v += _glide(v, bank, wing, n * dt) * dt
		else:
			if not grounded:
				v.y -= GRAVITY * dt
			v -= v * drag * dt
		var next := p + v * dt
		var hit := 0.0

		# The room's edge is a wall. Each way is tried on its own, so a throw into a corner
		# comes back off both walls and one along a wall slides along it.
		if not floor.is_empty() and not _on_floor(floor, Vector2(next.x, next.z)):
			if not _on_floor(floor, Vector2(next.x, p.z)):
				hit = maxf(hit, absf(v.x))
				v.x = -v.x * bounce
				v.z *= SCUFF
				next.x = p.x
			if not _on_floor(floor, Vector2(next.x, next.z)):
				hit = maxf(hit, absf(v.z))
				v.z = -v.z * bounce
				v.x *= SCUFF
				next.z = p.z

		# Into the side of a solid, or down onto its top.
		var ground := 0.0
		for s: Dictionary in solids:
			var top: float = s.get("top", Walker.SOLID_HEIGHT)
			var inside := Walker._gap(s, Vector2(next.x, next.z)) <= 0.0
			if not inside:
				continue
			if p.y >= top - 0.001:
				ground = maxf(ground, top)
				continue
			if next.y >= top:
				continue
			# From the side: back off it, the way it came in, in the solid's own frame.
			var turned := Basis(Vector3.UP, s["a"])
			var half: Vector2 = s["h"]
			var c: Vector2 = s["c"]
			var was := turned.inverse() * Vector3(p.x - c.x, 0.0, p.y - c.y)
			var local_v := turned.inverse() * v
			if absf(was.x) >= half.x:
				hit = maxf(hit, absf(local_v.x))
				local_v.x = -local_v.x * bounce
				local_v.z *= SCUFF
			else:
				hit = maxf(hit, absf(local_v.z))
				local_v.z = -local_v.z * bounce
				local_v.x *= SCUFF
			v = turned * local_v
			next = Vector3(p.x, next.y, p.z)

		# The floor, or whatever it is standing on.
		if next.y <= ground:
			next.y = ground
			if v.y < 0.0:
				hit = maxf(hit, -v.y)
				v.y = -v.y * bounce
				v.x *= SCUFF
				v.z *= SCUFF
				# A spin is mostly scrubbed off by the floor.
				w *= 0.6
				if v.y < HOP_SPEED:
					v.y = 0.0
					grounded = true
		elif grounded and next.y > ground + 0.001:
			# Rolled off the edge of a riser.
			grounded = false

		if grounded:
			var flat := Vector2(v.x, v.z)
			var slowed := maxf(0.0, flat.length() - roll * dt)
			flat = flat.normalized() * slowed if flat.length() > 0.0001 else Vector2.ZERO
			v = Vector3(flat.x, 0.0, flat.y)
			w = w.lerp(Vector3.ZERO, minf(1.0, 6.0 * dt))

		if gliding and (hit > 0.0 or next.y <= ground + 0.001):
			# Touched something: from here it is paper, not a wing. Its nose catches and it
			# tips over the way it was going.
			gliding = false
			w = Basis(q).x * -minf(v.length(), 4.0)
		if hit > 0.3:
			f.hits.append((n + 1) * dt)
			f.hit_speeds.append(hit)
		if gliding:
			if v.length() > 0.01:
				q = _wings(v.normalized(), bank)
		elif w.length() > 0.0001:
			q = (Quaternion(w.normalized(), w.length() * dt) * q).normalized()
		p = next
		f.points.append(p)
		f.turns.append(q)
		if grounded and v.length() < SETTLE_SPEED:
			break
	f.rest = p
	var forward := Basis(q) * Vector3.FORWARD
	f.rest_yaw = atan2(-forward.x, -forward.z) if Vector2(forward.x, forward.z).length() > 0.01 else 0.0
	return f


## How a wing speeds up, `v` going and leaning `bank`: gravity, drag along its path, and lift
## across it -- tipped by the bank, so a leaning wing turns. Lift is set so that at its trim
## speed it holds its weight exactly; slower than its stall speed it falls away fast.
static func _glide(v: Vector3, bank: float, wing: Dictionary, since: float) -> Vector3:
	var speed := v.length()
	var a := Vector3.DOWN * GRAVITY
	if speed < 0.01:
		return a
	var along := v / speed
	var trim: float = wing.get("trim", 4.0)
	var lift := GRAVITY * (speed * speed) / (trim * trim)
	var stall: float = wing.get("stall", trim * 0.6)
	if speed < stall:
		var under := speed / stall
		lift *= under * under
	lift = minf(lift, GRAVITY * float(wing.get("most", 1.8)))
	# Out of the hand it is still a thrown thing: the wing takes a moment to settle into the air
	# and start holding it up. So a throw at the floor goes into it, rather than pulling out of
	# the dive the instant it is let go.
	var settle: float = wing.get("settle", 0.0)
	if since < settle:
		lift *= since / settle
	# Drag is lift at trim over the glide ratio, so at trim it sinks one metre in `glide`.
	var drag := GRAVITY * (speed * speed) / (trim * trim) / float(wing.get("glide", 5.0))
	# Faster than it is built for, paper flutters and the air takes the speed off it.
	var flutter: float = wing.get("flutter", INF)
	if speed > flutter:
		drag += GRAVITY * (speed - flutter) * (speed - flutter) * float(wing.get("flap", 0.5))
	a += _lift_way(along, bank) * lift - along * drag
	return a


## Square off its path and leaning over by `bank`: which way its wings push.
static func _lift_way(along: Vector3, bank: float) -> Vector3:
	var up := Vector3.UP - along * along.dot(Vector3.UP)
	if up.length() < 0.001:
		up = Vector3.BACK - along * along.dot(Vector3.BACK)
	return up.normalized().rotated(along, bank)


## Nose along its path, wings level but for `bank`.
static func _wings(along: Vector3, bank: float) -> Quaternion:
	return Basis.looking_at(along, _lift_way(along, bank)).get_rotation_quaternion()


static func _on_floor(floor: Array, at: Vector2) -> bool:
	for r: Rect2 in floor:
		if r.has_point(at):
			return true
	return false
