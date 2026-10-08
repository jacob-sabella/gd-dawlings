class_name Ergonomics
extends RefCounted

## One participant's body, senses and comfort, and the geometry that follows from them.
##
## THE THING THIS REPLACES. Until now the project had exactly one hardcoded human in it. The
## desk was at 0.74m because that is how high a desk is; the patchbay was at 1.23m because that
## is eye level; lettering stopped being drawn below 0.0054 radians of cap height because that
## is three pixels on a viewport someone is sitting a metre from. Every one of those numbers is
## true of a standing adult of average height with uncorrected-to-normal vision, and false of
## everybody else. None of them was marked as an assumption, which is what made them invisible.
##
## So: there is no average body, and this is the object that says so. Everything placed for a
## person is placed from here.
##
## WHY THIS IS AN ERGONOMICS WIN AND NOT ONLY AN ACCESSIBILITY ONE. A control room is a
## compromise with physics -- the desk is that big because faders are that big, it is that far
## away because your arms are that long, and the rack is across the room because it had to go
## somewhere. None of those constraints exist here. Space is free, things can move, and the
## only fixed quantity in the whole arrangement is the person. Building the room outward from
## the body is not an accommodation bolted onto a studio; it is the first arrangement that was
## ever actually available, and a physical studio would use it if it could.
##
## It is deliberately a plain RefCounted with public fields. It gets read every frame by
## placement code and it has to be cheap, and it gets written by a settings panel that does not
## want an API per field.

enum ColourVision {FULL, DEUTAN, PROTAN, TRITAN, MONO}

# --- the body -----------------------------------------------------------------------------

## Eye height from the floor, standing or seated. The single most load-bearing number here:
## every surface's height is derived from it, which is why there is no constant anywhere else
## in the project that means "eye level".
var eye_height := 1.62
## Seated changes more than the height. A seated person's comfortable reach is shorter, their
## usable downward gaze is wider, and they cannot step back from something -- so a surface that
## does not fit has to be moved rather than walked away from.
var seated := false
## Comfortable forward reach, shoulder to palm. NOT maximum reach: the distance you can work at
## for an hour. Full extension is roughly a third more and is not somewhere to put a fader.
var reach := 0.62
## Eye to shoulder. Used to put a touched surface at a height your arm actually reaches rather
## than one your eye likes, which are not the same place.
var shoulder_drop := 0.24
## +1 right-handed, -1 left. Decides which side single-handed controls and grab tabs go.
var handedness := 1
## How far either side of straight ahead you can look by turning your head alone, in degrees,
## before you would rather turn your body. This is what bounds how wide a surface may be, and
## it is the ergonomic replacement for "how much fits on the monitor".
var head_turn := 55.0
## Comfortable downward gaze from horizontal, in degrees. Where a work surface sits.
var gaze_down := 20.0
## How far up and down the eyes sweep comfortably without moving the head, in degrees. Smaller
## than the horizontal figure, and that asymmetry is real rather than a fudge: a neck yaws much
## further than it pitches, and eyes roll further sideways than up. Ignoring it is what put a
## 1.2m rack 35cm from the viewer's face the first time this ran -- the rack is narrow, width
## said "come closer", and nothing was asking about height.
var gaze_sweep := 30.0

# --- the senses ---------------------------------------------------------------------------

## Cap height in radians below which THIS PERSON cannot read lettering. The old global constant,
## which was 0.0054 -- about three pixels of capital at a normal viewing distance -- now a
## property of the reader. Someone who needs twice the angular size sets twice the number, and
## every placement and every visibility range in the project follows, because they all ask here.
var min_cap_angle := 0.0054
## Pulls everything closer rather than making the panels bigger. This is the move a screen
## cannot make and it is the better answer: scaling a font reflows a layout and eventually runs
## out of panel, whereas halving the distance doubles the angular size of EVERYTHING -- the
## lettering, the fader caps, the LED segments, the gaps between them -- which is what actually
## makes a surface readable rather than merely large-print.
var text_scale := 1.0
## Never let colour be the only thing carrying a meaning. Costs a little clutter for everyone
## and is the difference between usable and not for roughly one man in twelve.
var redundant_coding := false
var colour_vision: ColourVision = ColourVision.FULL

# --- comfort ------------------------------------------------------------------------------

## How much of a move to animate. 1.0 glides, 0.0 cuts. Smooth motion of something large and
## near is a common trigger for people who get motion sick in headsets, and the whole summon
## idea moves large things near you, so it has to be possible to turn off.
var motion_scale := 1.0
## Hold-to-act instead of click-to-act, in seconds. 0 disables. For anyone who can aim but
## cannot reliably click, or cannot hold a controller at all.
var dwell_seconds := 0.0
## One keyboard or button step of a continuous control, as a fraction of its range. The reason
## this exists is that a knob you can only operate by dragging is a knob some people cannot
## operate, and "drag precisely" is the single least accessible gesture in the project.
var step := 0.02

# --- derived geometry -----------------------------------------------------------------------

## How close something may be before the eyes cannot converge on it comfortably. Not a taste
## number: inside about 35cm sustained near work is uncomfortable for most adults and
## impossible for anyone with presbyopia, which is most people over about 45.
const NEAR_LIMIT := 0.35


static func standing() -> Ergonomics:
	return Ergonomics.new()


static func seated_default() -> Ergonomics:
	var e := Ergonomics.new()
	e.seated = true
	e.eye_height = 1.21
	e.reach = 0.56
	# Wider, because a seated person looks down at a desk more steeply and cannot lean back as
	# far to compensate.
	e.gaze_down = 26.0
	return e


func shoulder_height() -> float:
	return eye_height - shoulder_drop


## Where a surface you TOUCH sits: comfortably short of full extension.
func working_distance() -> float:
	return maxf(reach * 0.82, NEAR_LIMIT)


## The farthest this person can read lettering of the given cap height.
##
## The whole of what `text_scale` does. A reader who has turned it up is not asking for bigger
## fonts; they are asking for everything to be closer, and this is the function that delivers
## it, because every placement is clamped by it.
func legible_to(cap_height: float) -> float:
	if cap_height <= 0.0 or min_cap_angle <= 0.0:
		return INF
	return cap_height / (min_cap_angle * maxf(text_scale, 0.01))


## The CLOSEST something this size may be and still be taken in without moving.
##
## The ergonomic replacement for fitting a panel to a monitor. A screen fit asks what the camera
## can see; this asks what the neck and eyes sweep, which is the constraint that actually tires
## someone out over a four-hour session. Both axes, against different angles, because a neck
## yaws much further than it pitches.
func fits_in_sweep(size: Vector3) -> float:
	var across := (size.x * 0.5) / tan(deg_to_rad(clampf(head_turn, 5.0, 85.0)))
	var up := (size.y * 0.5) / tan(deg_to_rad(clampf(gaze_sweep, 5.0, 85.0)))
	return maxf(across, up)


## Where a surface goes for this body, in head space: -Z forward, Y up, origin at the eye.
##
## Three constraints of three different kinds, which is the part worth getting right:
##   * fitting inside the sweep is a LOWER bound -- any closer and it overflows your vision,
##   * reading the smallest thing on it is an UPPER bound,
##   * and reach is a PREFERENCE, which is what the other two clamp.
##
## Treating reach as a third hard constraint is what went wrong first: it is not true that a
## surface must be within arm's length, only that you would like it to be. A 1.2m rack cannot
## be both inside your reach and inside your field of view, and the resolution is that you lean
## in to touch the top of it -- exactly as you would at a real rack -- rather than that it is
## shoved into your face where neither is possible.
##
## When the two bounds genuinely cross, `too_big_to_place` says so rather than this quietly
## returning a compromise nobody can use. A surface that cannot be both read and swept is not a
## placement problem, it is a layout problem -- the answer is to bank it, arc it, or split it,
## and all three of those are decisions for the surface rather than for the person's body.
func place(bearing_degrees: float, bounds: AABB, touched: bool, smallest_cap: float) -> Transform3D:
	var distance := _distance_for(bounds, touched, smallest_cap)
	var drop := drop_for(bounds, distance, touched)
	# The centre of the content on the line of sight, not the surface's origin -- a console's
	# origin is the front edge of the desk, and centring that puts half the desk out of view.
	var ahead := Vector3(0, -sin(drop), -cos(drop)) * distance
	# Facing the eye: pitched back by the same angle the gaze drops, so the panel is square to
	# the look rather than square to the floor.
	var facing := Basis(Vector3.RIGHT, drop)
	# Negated, because positive about +Y swings to the LEFT in Godot's handedness and every
	# other bearing in this project -- and every bearing anyone says out loud -- counts positive
	# to the right. The two conventions disagreeing silently is the kind of thing that only
	# shows up as gear mirrored across the viewer, which looks deliberate.
	var swung := Basis(Vector3.UP, -deg_to_rad(bearing_degrees))
	var basis := swung * facing
	return Transform3D(basis, swung * ahead - basis * bounds.get_center())


## How far below the horizon the centre of a surface this size should sit, in radians.
##
## A work surface belongs below the horizon -- that is where hands are and where a desk is, and
## looking slightly down all day is what necks are shaped for. But the drop is applied to the
## CENTRE, and on a tall surface that is not the same as putting the surface somewhere
## comfortable: the FX rack at a 20-degree drop put its own bottom row 50 degrees below the
## horizon, outside any cone a person can look through without moving, and the render simply
## ran off the bottom of the frame.
##
## So the drop yields to the surface. A small panel gets the full comfortable drop; a tall one
## straightens up until its far edge is back inside the sweep, which for something as tall as
## the sweep itself means dead ahead. Clamped at zero rather than going negative, because a
## surface tall enough to want lifting ABOVE the horizon is one that should have been split.
func drop_for(bounds: AABB, distance: float, touched: bool) -> float:
	var wanted := deg_to_rad(gaze_down if touched else gaze_down * 0.4)
	if distance <= 0.0:
		return wanted
	var half_angle := atan(bounds.size.y * 0.5 / distance)
	var room := deg_to_rad(clampf(gaze_sweep, 5.0, 85.0)) - half_angle
	return clampf(wanted, 0.0, maxf(room, 0.0))


## True when no distance satisfies both the sweep and the reading constraint.
func too_big_to_place(bounds: AABB, smallest_cap: float) -> bool:
	return fits_in_sweep(bounds.size) > legible_to(smallest_cap)


func _distance_for(bounds: AABB, touched: bool, smallest_cap: float) -> float:
	var nearest := maxf(fits_in_sweep(bounds.size), NEAR_LIMIT)
	var preferred := working_distance() if touched else nearest
	return clampf(preferred, nearest, maxf(legible_to(smallest_cap), nearest))
