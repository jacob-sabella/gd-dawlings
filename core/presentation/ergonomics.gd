class_name Ergonomics
extends RefCounted

## The person this session is being presented to.
##
## A global, and deliberately so. Lettering sizes itself from it, the signal palette is drawn
## from it, dwell timing is read from it and the focus rig places surfaces with it -- four
## subsystems that have no business knowing about each other and every business agreeing about
## who is reading. Threading one object down four unrelated call chains to express that would
## be ceremony.
##
## It lived on Lettering first, which was the wrong home the moment anything but lettering
## needed it.
static var current: Ergonomics = Ergonomics.new()

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
## in the project that means "eye level". Set from a person's height with `set_height`.
##
## The room is NOT derived from it -- the desk, the stands and the walls are the sizes they
## are -- so a shorter person sees a bigger room, which is the honest effect. The default was
## 1.62 (someone 1.73 tall), and from there the room read a size small: the desk at a glance
## rather than in front of you. 1.56 (1.67 tall) still did; 1.47 is someone 1.58 tall, chosen
## from pictures of the four candidates side by side.
var eye_height := DEFAULT_HEIGHT - EYE_BELOW_CROWN
## How tall the body is, which the eye is worked out from. See set_height.
var height := DEFAULT_HEIGHT
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

## The vertical field of view of the seated screen view, in degrees.
##
## Not a fact about a body, which is why it sits oddly here -- but it IS the binding constraint
## on a monitor, and the constraints have to be comparable to be combined. A neck turns 55
## degrees each way; a 54-degree lens shows 27. Size a surface to the neck and present it
## through the lens and the ends are simply off-screen, which is how the patchbay came to run
## 75 percent past each edge of the frame while passing every ergonomics check in the suite.
##
## Set by the studio per medium: its own SEATED_FOV on a monitor, and something near a
## headset's own field in VR and AR, where the "frame" is the visor rather than a window. One
## number either way, so a surface can size itself to what will actually be shown without
## knowing which medium it is in -- and without a patchbay sized to a 54-degree crop being
## needlessly stacked into four units inside a headset that would have shown it in one.
var seated_fov := 54.0


## Width over height of the window gear is being presented through. Set by the studio from the
## viewport, because the frame budget is wider than it is tall and nothing else knows by how
## much. Defaulted to the narrowest common shape, so an unset rig errs toward standing back.
var view_aspect := 4.0 / 3.0


## Half the width of what the seated lens actually shows at `radius`, doubled -- the span of
## frame, as against the span of neck that `wrap_span_at` gives. `aspect` is width over height;
## the caller reads it off the viewport, because a surface cannot know the shape of a window.
func frame_span(radius: float, aspect: float) -> float:
	return 2.0 * radius * tan(deg_to_rad(clampf(seated_fov, 10.0, 150.0) * 0.5)) \
			* maxf(aspect, 0.2)


## And the height of it, which is the same number without the aspect.
func frame_rise(radius: float) -> float:
	return 2.0 * radius * tan(deg_to_rad(clampf(seated_fov, 10.0, 150.0) * 0.5))

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
## The size of one notch of a continuous control, as a fraction of its range. 0 is continuous.
##
## A knob you can only operate by dragging is a knob some people cannot operate, and "drag
## precisely, and hold while you do" is the single least accessible gesture in the project.
## Turning this on changes two things at once, and both are needed: a drag lands on notches
## instead of anywhere, and a TAP on the trough or the dial moves one notch instead of jumping
## to where it was tapped. The second is the one that matters -- it removes the drag entirely.
##
## Off by default, because quantising a mix engineer's fader without being asked is taking
## resolution away from someone who had a use for it.
var step := 0.0
## How far apart a pinch's thumb and fingertip may be, against what is right for a hand of their
## size (HandPose: in under 18 mm, out over 30 mm on the reference hand). Up for fingers that do
## not close all the way, or that tremble while held; down for someone whose hand at rest has its
## fingertips near the thumb. 1 is the measured default.
var finger_scale := 1.0

# --- derived geometry -----------------------------------------------------------------------

## How close something may be before the eyes cannot converge on it comfortably. Not a taste
## number: inside about 35cm sustained near work is uncomfortable for most adults and
## impossible for anyone with presbyopia, which is most people over about 45.
const NEAR_LIMIT := 0.35


## How tall the default person is, and how far below the top of the head the eyes are.
const DEFAULT_HEIGHT := 1.58
const EYE_BELOW_CROWN := 0.11
## Seated eye height over standing height: 1.21 for someone 1.73 tall, an ordinary chair.
const SEATED_EYE_RATIO := 1.21 / 1.73
const HEIGHT_RANGE := Vector2(1.0, 2.2)
## Where a person's height is remembered between launches.
const HEIGHT_PATH := "user://body.cfg"


## The eye of someone `height` metres tall, standing or seated.
static func eye_for(height: float, sitting: bool) -> float:
	var h := clampf(height, HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	return h * SEATED_EYE_RATIO if sitting else h - EYE_BELOW_CROWN


## Make this the body of someone `height` metres tall. Only the eye moves: reach and the angles
## are a matter of proportion, and proportion does not change much with height.
func set_height(to: float) -> void:
	height = clampf(to, HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	eye_height = eye_for(height, seated)


## The height remembered at `path`, or 0.0 when nobody has said.
static func load_height(path: String) -> float:
	var file := ConfigFile.new()
	if path.is_empty() or file.load(path) != OK:
		return 0.0
	return clampf(float(file.get_value("body", "height", 0.0)), 0.0, HEIGHT_RANGE.y)


static func save_height(height: float, path: String) -> void:
	if path.is_empty():
		return
	var file := ConfigFile.new()
	file.load(path)
	file.set_value("body", "height", clampf(height, HEIGHT_RANGE.x, HEIGHT_RANGE.y))
	file.save(path)


static func standing() -> Ergonomics:
	return Ergonomics.new()


static func seated_default() -> Ergonomics:
	var e := Ergonomics.new()
	e.seated = true
	e.set_height(DEFAULT_HEIGHT)
	e.reach = 0.56
	# Wider, because a seated person looks down at a desk more steeply and cannot lean back as
	# far to compensate.
	e.gaze_down = 26.0
	return e


## Where a working surface goes: elbow height, which is the only height a desk has ever been.
##
## Derived from the eye rather than declared, so a short person gets a low desk and a seated
## one gets a lower desk again, without anybody maintaining a table of them.
func desk_height() -> float:
	return eye_height - (0.46 if seated else 0.55)


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
## Mostly an ergonomic replacement for fitting a panel to a monitor: a screen fit asks what the
## camera can see, and this asks what the neck and eyes sweep, which is the constraint that
## actually tires someone out over a four-hour session. Both axes, against different angles,
## because a neck yaws much further than it pitches.
##
## And then the lens, because "mostly" was doing too much work. A neck yaws 55 degrees either
## way and a seated 54-degree lens shows 27 up and down; whenever the window is the tighter of
## the two, a surface placed at the distance the NECK wanted is simply cropped. The patchbay
## found this -- at 48 tracks it sat where the sweep asked and ran three-quarters of its width
## past each edge of the frame, having passed every ergonomics check in the suite on the way.
##
## Taking the max of the two is right in both directions. On a monitor the frame is tighter and
## pushes gear back until it is all visible. In a headset `seated_fov` is the visor's own wide
## field, that term goes slack, and the body is the binding constraint again -- which is what
## it should be when you can simply turn your head.
func fits_in_sweep(size: Vector3, aspect: float = 4.0 / 3.0) -> float:
	var across := (size.x * 0.5) / tan(deg_to_rad(clampf(head_turn, 5.0, 85.0)))
	var up := (size.y * 0.5) / tan(deg_to_rad(clampf(gaze_sweep, 5.0, 85.0)))
	var lens := tan(deg_to_rad(clampf(seated_fov, 10.0, 150.0) * 0.5))
	var framed_across := (size.x * 0.5) / maxf(lens * maxf(aspect, 0.2), 0.01)
	# The hypotenuse of half-height and half-depth, not half-height. `place` pitches a surface
	# back by the gaze drop, and a pitched box presents more vertical extent than its own
	# height: the top-near corner swings up as the top-far corner swings down. Bounding it by
	# the diagonal costs a little distance on a deep surface and is right for any drop angle,
	# which beats recomputing this against a drop that has not been chosen yet.
	var framed_up := Vector2(size.y * 0.5, size.z * 0.5).length() / maxf(lens, 0.01)
	# Divided by the margin rather than multiplied: this is a DISTANCE, and leaving a border
	# means standing further back, not nearer.
	var want := maxf(maxf(across, up), maxf(framed_across, framed_up) / FRAME_MARGIN)
	# Plus how much nearer than the centre the nearest corner can come, because this fits the
	# box's CENTRE to the cone and the corner that actually overflows is the near one. On the
	# FX rack, which is 30cm deep, that is the whole error -- the rack sat exactly where the
	# centre fit asked and put its near top corner 28 percent past the frame edge. Half the
	# depth was the first answer and holds for a box square to the look; pitched back by the
	# gaze drop, the near TOP corner comes closer still -- the drop turns some of the height
	# toward the eye -- which put a four-unit rack's corner a percent past the edge. The drop
	# is the one `drop_for` would choose here: the full `gaze_down` for something short, and
	# next to nothing for something as tall as the sweep, which a blanket allowance for the
	# full drop pushed back a fifth of a metre for no corner at all.
	var pitch := drop_for(AABB(Vector3.ZERO, size), want + size.z * 0.5, true)
	return want + size.z * 0.5 * cos(pitch) + size.y * 0.5 * sin(pitch)


## How much of the frame a surface may fill.
##
## Not all of it, for two reasons. Something sized to exactly the frustum touches all four
## edges, which reads as cropped whether or not it is. And the fit above is a BOUND rather
## than an exact solve -- it approximates a box pitched by an angle that has not been chosen
## yet, so it is right to within a few percent rather than to the pixel. The margin absorbs
## that; `_test_focused_gear_fits_the_frame_it_is_shown_in` is what proves it absorbs enough,
## and it rejected 0.88 on the tape deck by three percent.
const FRAME_MARGIN := 0.84


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


## Place a surface that is bent around the viewer.
##
## Its centre of curvature goes at the eye, so every part of it is `radius` away and the
## question "how far back does this have to be" stops having a width term in it. The gaze drop
## is then free: tilting about a pivot that is already at the eye costs no translation, so the
## whole arc swings down together and stays equidistant.
func place_wrapped(
		bearing_degrees: float, radius: float, touched: bool, centre_y: float) -> Transform3D:
	# An upright cylinder sat at desk height, NOT the whole arc swung down about the eye.
	#
	# Swinging it was the first version, and it is what you get by analogy with `place`: the
	# gaze drops twenty degrees, so drop the surface twenty degrees. For a flat panel that is
	# right. For a desk it is wrong twice over. It tips the circle, so its far ends swing out
	# past the head-turn and its low ends swing wider still; and it hangs the surface off the
	# eye at reading distance, which put the top edge of a mixing desk level with the eyebrows
	# and its near edge a hand's width from the chin. Measured rather than guessed: the box ran
	# from four degrees ABOVE the horizon to fifty-nine below, across sixty-three degrees of a
	# fifty-four degree lens.
	#
	# A desk does not hang off your face. It stands on the floor at elbow height and you look
	# down at it. So the arc stays upright -- centre of curvature still at the eye in plan,
	# which is the whole point, every strip equidistant and head-on -- and it is lowered.
	var basis := Basis(Vector3.UP, -deg_to_rad(bearing_degrees))
	var sits := (desk_height() - eye_height) if touched else -0.18
	return Transform3D(basis, Vector3(0, sits, 0) - basis * Vector3(0, centre_y, radius))

## How much ARC, at `radius`, one head-turn each way can bring to the front.
##
## The number that makes wrapping worth doing, and the number that shows why wrapping alone is
## not enough. At arm's length a neck sweeps about a metre of arc -- roughly seventeen channel
## strips -- so a 90-track desk bent round one circle at reading distance does not become
## readable, it becomes a tube with sixty strips behind your head. The fix for the rest is rows,
## not a bigger circle, and that is what wrap_rise is for.
func wrap_span(radius: float) -> float:
	return 2.0 * radius * deg_to_rad(clampf(head_turn, 5.0, 85.0))


## How much HEIGHT, at `radius`, a glance up and down can cover without moving the head.
func wrap_rise(radius: float) -> float:
	return 2.0 * radius * tan(deg_to_rad(clampf(gaze_sweep, 5.0, 85.0)))


## How many rows of `pitch` fit the vertical glance at `radius`. At least one, always: a single
## row that overflows is a layout to report, not a surface to refuse to draw.
func wrap_rows(radius: float, pitch: float) -> int:
	if pitch <= 0.0:
		return 1
	return maxi(1, int(floor(wrap_rise(radius) / pitch)))


## The smallest radius at which `width` of surface, cut into rows of `pitch` and quantised to
## whole `module` widths, fits inside both sweeps.
##
## The three constraints behave exactly as they do for a flat panel, and for the same reasons:
## reach is where you would LIKE it (the search starts there), the sweep is a lower bound (too
## near and it wraps past your shoulders), and legibility is a hard upper bound (past it the
## lettering is gone whatever else is true). What changes is that growing the radius now buys
## capacity twice over -- a longer arc per row AND room for another row -- so the search
## converges much faster than pushing a flat panel back, which only ever buys angle.
##
## Returns the legible limit when nothing fits. Reporting the overflow is the caller's job; a
## radius that quietly satisfies one constraint by breaking another is the failure this whole
## file exists to stop.
func wrap_radius_for(width: float, pitch: float, module: float, smallest_cap: float) -> float:
	var ceiling := maxf(legible_to(smallest_cap), NEAR_LIMIT)
	var radius := maxf(working_distance(), NEAR_LIMIT)
	while radius < ceiling:
		if wrap_capacity(radius, pitch, module) >= width:
			return radius
		radius += WRAP_SEARCH_STEP
	return ceiling


## The arc a head-turn reaches on a row sitting `rise` above (or below) the middle of the arc.
##
## Not the same as `wrap_span`, and the difference is the one the tilted desk walked into. The
## gaze drop tips the whole circle about the eye, and a tilted circle swings its LOW ends
## outward: on a three-tier desk the bottom row reads about seven degrees further round than
## the flat geometry says, which is how a layout that measured 53 degrees rendered at 65.
##
## Solved by bisection. The closed form exists and is longer than the loop.
func wrap_span_at(radius: float, rise: float, tilt: float) -> float:
	var drop := tilt
	var limit := deg_to_rad(clampf(head_turn, 5.0, 85.0))
	var lo := 0.0
	var hi := PI * 0.5
	for _i in 28:
		var mid := (lo + hi) * 0.5
		var swung := atan2(radius * sin(mid), rise * sin(drop) + radius * cos(mid) * cos(drop))
		if swung > limit:
			hi = mid
		else:
			lo = mid
	return 2.0 * radius * lo


## Total arc, over every row, available at `radius` -- rounded DOWN to whole modules per row so
## a row ends on a strip boundary rather than halfway through one.
##
## Every row gets the WORST row's span, not its own. Rows of different widths would hold
## different numbers of strips, and a desk whose tiers end in different places is a desk you
## cannot count along. One span, set by the bottom tier, is the cheaper answer.
func wrap_capacity(radius: float, pitch: float, module: float) -> float:
	var rows := wrap_rows(radius, pitch)
	# Zero tilt: the arc is upright, so no tier swings wider than any other. The argument is
	# kept because the geometry is general and the tilted case is still what place() does.
	var per_row := wrap_span_at(radius, -float(rows - 1) * pitch * 0.5, 0.0)
	if module > 0.0:
		per_row = floor(per_row / module) * module
	return per_row * float(rows)


const WRAP_SEARCH_STEP := 0.01


## True when no distance satisfies both the sweep and the reading constraint.
func too_big_to_place(bounds: AABB, smallest_cap: float) -> bool:
	return fits_in_sweep(bounds.size) > legible_to(smallest_cap)


func _distance_for(bounds: AABB, touched: bool, smallest_cap: float) -> float:
	var nearest := maxf(fits_in_sweep(bounds.size, view_aspect), NEAR_LIMIT)
	var preferred := working_distance() if touched else nearest
	return clampf(preferred, nearest, maxf(legible_to(smallest_cap), nearest))


## The nearest notch to a value, or the value itself when notches are off.
func quantise(value: float) -> float:
	if step <= 0.0:
		return value
	return clampf(round(value / step) * step, 0.0, 1.0)


## One notch along from where you are, in the given direction.
##
## Off the CURRENT value rather than off the nearest notch, so a control sitting between notches
## -- because Reaper set it, or because it was dragged before stepping was turned on -- still
## moves by exactly one notch on the first tap instead of snapping somewhere else first. The
## snap-then-move version loses a tap, and losing the first tap is how a stepped control gets
## the reputation of being unresponsive.
func nudge(value: float, direction: int) -> float:
	if step <= 0.0 or direction == 0:
		return value
	return clampf(value + signf(direction) * step, 0.0, 1.0)


## The colours this studio uses to MEAN something, chosen for the eyes reading them.
##
## Separate from decoration. A chassis can be any grey; a record light cannot be any red,
## because its whole job is to be told apart from the solo light next to it. Roughly one man in
## twelve and one woman in two hundred cannot do that with the default palette, and on a console
## the three buttons in question are identical rectangles in a vertical column -- there is no
## shape, position or label to fall back on. That is the definition of colour carrying meaning
## alone, and it is the single most common accessibility defect in audio software.
##
## The palette changes with the reader rather than being one "colourblind-safe" set for
## everyone, because the sets that work for deutans and for tritans are different sets, and a
## compromise between them is worse for both than either is alone.
const SIGNAL_ROLES: Array[StringName] = [&"record", &"solo", &"mute", &"ok", &"warn", &"over"]

const _SIGNALS := {
	ColourVision.FULL: {
		&"record": Color(0.95, 0.25, 0.22), &"solo": Color(0.98, 0.78, 0.20),
		&"mute": Color(0.35, 0.72, 0.98), &"ok": Color(0.30, 0.86, 0.42),
		&"warn": Color(0.95, 0.68, 0.18), &"over": Color(0.98, 0.22, 0.18),
	},
	# Red and green collapse together, so the axis that survives is blue-to-yellow. Record stays
	# warm because a red record light is a convention worth more than a marginal gain, and is
	# pulled bright and orange so it separates from solo by LIGHTNESS as well as hue.
	ColourVision.DEUTAN: {
		&"record": Color(1.00, 0.42, 0.10), &"solo": Color(0.98, 0.90, 0.35),
		&"mute": Color(0.30, 0.60, 1.00), &"ok": Color(0.40, 0.70, 1.00),
		&"warn": Color(0.95, 0.85, 0.30), &"over": Color(1.00, 0.40, 0.10),
	},
	ColourVision.PROTAN: {
		&"record": Color(1.00, 0.50, 0.12), &"solo": Color(0.97, 0.92, 0.42),
		&"mute": Color(0.28, 0.58, 1.00), &"ok": Color(0.42, 0.72, 1.00),
		&"warn": Color(0.95, 0.86, 0.34), &"over": Color(1.00, 0.46, 0.12),
	},
	# Blue and yellow collapse, so red-green is what is left.
	ColourVision.TRITAN: {
		&"record": Color(1.00, 0.24, 0.26), &"solo": Color(0.98, 0.52, 0.72),
		&"mute": Color(0.35, 0.85, 0.80), &"ok": Color(0.35, 0.88, 0.45),
		&"warn": Color(1.00, 0.55, 0.55), &"over": Color(0.95, 0.18, 0.20),
	},
	# Nothing to tell apart by hue at all, so the palette is a lightness ramp and everything
	# else has to be carried by the lettering and the notches.
	ColourVision.MONO: {
		&"record": Color(1.00, 0.98, 0.96), &"solo": Color(0.72, 0.72, 0.72),
		&"mute": Color(0.42, 0.44, 0.46), &"ok": Color(0.52, 0.54, 0.55),
		&"warn": Color(0.78, 0.78, 0.78), &"over": Color(1.00, 1.00, 1.00),
	},
}


## The colour to use for one of the meanings above.
func signal_colour(role: StringName) -> Color:
	var table: Dictionary = _SIGNALS.get(colour_vision, _SIGNALS[ColourVision.FULL])
	return table.get(role, _SIGNALS[ColourVision.FULL].get(role, Color.WHITE))


## What this colour looks like to the person reading it.
##
## Viénot-Brettel-Mollon for the two red-green deficiencies and the standard tritan
## approximation, applied in LINEAR light because that is where the cone response lives --
## running it on sRGB values is a common shortcut that makes everything look more
## distinguishable than it is, which defeats the point of simulating at all.
##
## Here to be TESTED against, not to be rendered through. The studio does not show anyone a
## simulation of their own eyesight; it picks a palette and then checks, in the suite, that the
## palette survives the eyes it was picked for.
func simulate(colour: Color) -> Color:
	if colour_vision == ColourVision.FULL:
		return colour
	var c := colour.srgb_to_linear()
	if colour_vision == ColourVision.MONO:
		var y := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		return Color(y, y, y).linear_to_srgb()
	var m: Array
	match colour_vision:
		ColourVision.PROTAN:
			m = [[0.1121, 0.8853, -0.0005], [0.1127, 0.8897, -0.0001], [0.0045, 0.0085, 1.0000]]
		ColourVision.DEUTAN:
			m = [[0.2920, 0.7054, -0.0003], [0.2934, 0.7089, 0.0000], [-0.0209, 0.4912, 0.5273]]
		_:
			m = [[1.0000, 0.1440, -0.1440], [0.0000, 0.8591, 0.1409], [0.0000, 0.2137, 0.7863]]
	return Color(
			m[0][0] * c.r + m[0][1] * c.g + m[0][2] * c.b,
			m[1][0] * c.r + m[1][1] * c.g + m[1][2] * c.b,
			m[2][0] * c.r + m[2][1] * c.g + m[2][2] * c.b).clamp().linear_to_srgb()


## How far apart two colours are to the person reading them, 0 to about 1.7.
##
## Lightness weighted heavily, because lightness is the one channel every reader keeps -- two
## signals that differ only in hue are one eye condition away from being the same signal.
func separation(a: Color, b: Color) -> float:
	var x := simulate(a)
	var y := simulate(b)
	var lightness := absf((0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b)
			- (0.2126 * y.r + 0.7152 * y.g + 0.0722 * y.b))
	return Vector3(x.r - y.r, x.g - y.g, x.b - y.b).length() * 0.5 + lightness
