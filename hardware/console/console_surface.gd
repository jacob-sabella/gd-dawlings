class_name ConsoleSurface
extends Surface

## The mixing desk: a strip per Reaper track, on a tilted panel, in a chassis.
##
## Rebuilt when the track count changes and at no other time. The panel geometry is sized from
## the strip count rather than being a fixed model, because a 6-track project and a 48-track one
## are different pieces of furniture -- and in ROOM mode a 48-track desk is 2.6m wide, which is
## a fact about the room that the person placing it needs to see honestly rather than scaled to
## fit.

## Degrees off vertical. 60 is a desk you lean over rather than a panel you face: it keeps the
## faders within reach of a standing hand and the legends readable from above.
## Whether a summoned desk bends around you or runs straight across. It runs straight.
##
## The bend was built to solve a real problem -- a desk wide enough for a session is wider than
## a person can face -- and it does solve it, but it turns out not to be the part that does the
## work. What fixed the desk was PAGING: twelve strips you can face, with the bank buttons
## moving the window. Twelve strips do not need bending; they already fit. The curve was then
## doing nothing except equalising distances that were already nearly equal, and charging a
## fanned gap between every pair of panels for it.
##
## Everything else the wrap brought stays, because none of it was really about the curve: the
## radius search that decides how wide a tier may be, the row splitting above that, the desk at
## elbow height, and `_page_arc` sizing the page from a head-turn. Those are measurements of a
## person. The bend was a shape.
##
## Left as a constant rather than deleted. In a headset, where turning your head is free and a
## flat desk really does run away from you at the ends, the arithmetic behind it is still right
## and this is the switch.
const CURVED := false


const PANEL_TILT := 60.0
const PANEL_MARGIN := 0.03

var _panel: Node3D
var strips: Array[ChannelStrip] = []
var master: MasterSection
var bank: BankSelector

## A bank change asked for while a hand is on a control, held until the hand lets go.
##
## THE ONE RULE BANKING MUST NOT BREAK: a strip may never change which track it means while
## someone is holding its fader. Applying immediately would rebuild the desk out from under a
## grab -- the fader is freed mid-drag, the hand is left holding nothing, and the last value
## written went to a track that is no longer there. Worse, nothing about it looks like an error.
var _pending_bank := -1

## Which return's sends the faders are showing, or 0 for levels. This participant's view of the
## desk, not the mix's -- the engineer can be riding reverb sends while the person beside them
## watches levels on their own copy -- so it lives here and is never replicated.
var send_dest := 0


func _ready() -> void:
	surface_kind = &"console"
	# Compensates the panel's own sixty-degree lay-back, less fifteen, so that on a monitor you
	# are looking slightly DOWN at the desk rather than straight into its face.
	screen_pitch_degrees = 45.0
	if surface_id == &"":
		surface_id = &"console"
	super()
	DAW.bank_changed.connect(_on_bank_changed)


func _process(delta: float) -> void:
	super(delta)
	if _pending_bank >= 0 and not _anything_held():
		var wanted := _pending_bank
		_pending_bank = -1
		_go_to_track(wanted)


func _on_bank_changed() -> void:
	mark_dirty()


## Asked for by the bank buttons. Deferred rather than refused: refusing would mean a press
## that did nothing, and the hand on the fader is usually the other hand.
func _request_bank(offset: int) -> void:
	if _anything_held():
		_pending_bank = offset
		return
	_go_to_track(offset)


## Show the page beginning at project track `offset`, fetching a different protocol bank first
## if that track is not one the DAW has sent us.
##
## Two layers that are easy to conflate and must not be: the protocol bank is how many tracks
## the DAW agreed to stream, the page is how many of those a person can face at once. Paging
## inside the cached bank costs nothing and happens instantly; walking off its end is a request
## to the DAW and may take a round trip.
func _go_to_track(offset: int) -> void:
	var wanted := maxi(0, offset)
	var cached := DAW.state.tracks.size()
	var local := wanted - DAW.state.bank_offset
	if local < 0 or local >= cached:
		view_offset = 0
		DAW.set_track_bank(wanted)
		return
	view_offset = local
	mark_dirty()


## The width past which a flat desk stops being a desk and starts being a wall.
##
## Below it a console is a thing you stand at; above it the far end is further away than the
## near end by more than the near end is away at all, so the lettering goes glancing and the
## reach goes impossible. 1.6m is about two arm-spans of panel, which is where a real desk
## stops too -- beyond that, real control rooms angle the wings in.
## Arc per tier, for a desk of `rows` tiers -- budgeted from the WORST tier, which is the
## bottom one: the gaze drop tips the whole circle and a tilted circle swings its low ends
## outward. Quantised down to whole strips so a tier ends on a strip boundary.
func _span_for(erg: Ergonomics, pitch: float, rows: int) -> float:
	return floor(erg.wrap_span_at(_wrap, -float(rows - 1) * pitch * 0.5, 0.0)
			/ ChannelStrip.WIDTH) * ChannelStrip.WIDTH


## How far the carcass reaches below the armrest. Not to the floor exactly -- a desk summoned
## for a seated body sits lower, and a skirt sized for standing would then be through it.
const SKIRT_HEIGHT := 0.46


## Vertical space between two rows of a wrapped desk. A seam, not a gap: wide enough that the
## row below is a different row and not a longer strip, narrow enough that a glance crosses it.
const ROW_GAP := 0.012

## The smallest lettering anywhere on the desk, and therefore how far the desk may be pushed
## before it stops being readable.
##
## Declared rather than measured, because the radius has to be chosen BEFORE a single label
## exists -- the radius decides the layout and the layout builds the labels. It can be declared
## safely because every label on this desk is built at the same pixel size and the smallest
## font any of them asks for is 40 -- the master's L/R, and the floor `Lettering.fit` is given
## for a strip's name and level, so a session with long track names cannot quietly go under it.
## There is a test that fails if that stops being true.
const SMALLEST_FONT := 40
const SMALLEST_CAP := SMALLEST_FONT * 0.00018

## Arc length of one row, and how many rows. Zero and one when the desk is flat.
var _row_span := 0.0
var _rows := 1
## Half the unrolled width, kept because _seat is given x measured from the desk's centre.
var _half_width := 0.0

var _wrap := 0.0

## Show every track at once, in as many tiers as that takes, instead of one page at a time.
##
## Off by default and it should stay that way. A summoned desk showing forty-eight tracks needs
## three tiers of faders stacked up your field of view, and that is a pit you stand in rather
## than a desk you work at -- correct by every number in ergonomics.gd and horrible to be in.
## The default is one tier you can take in at a glance, paged. This is the escape hatch for the
## moment you genuinely want to see the whole mix at once.
var expanded := false:
	set(value):
		if expanded == value:
			return
		expanded = value
		mark_dirty()

## Which page of the cached bank the single-tier desk is showing. Not the protocol's bank
## offset, which is a different thing at a different layer: that is how many tracks the DAW
## agreed to stream, this is how many of them a person can face at once. See page_size.
var view_offset := 0


## How many channel strips fit in ONE tier at arm's length -- the bank width a BODY asks for,
## as opposed to the one the protocol happens to offer.
##
## Reaper streams 64. Nothing about 64 came from a person; it is a round number in a protocol.
## The number that came from a person is this one: the arc a neck sweeps at reach, less what
## the master section and the bank buttons take out of it, divided by a strip. It lands near
## fourteen, which is roughly the width of every small-format desk ever built, and that is not
## a coincidence -- those were sized by the same measurement.
func page_size() -> int:
	return maxi(4, int(floor(_page_arc() / ChannelStrip.WIDTH)))


## Arc left for channel strips in one tier at arm's length, once the master section, the bank
## module and the panel margins have taken theirs.
func _page_arc() -> float:
	var erg := Ergonomics.current
	var radius := maxf(erg.working_distance(), Ergonomics.NEAR_LIMIT)
	# The narrower of what a neck can face and what the window can show. A page sized to the
	# neck alone is correct ergonomics and still runs off the sides of a monitor, which is the
	# same mistake the patchbay made and for the same reason: 55 degrees of yaw against 27 of
	# lens. In a headset `seated_fov` is the visor's own field and this term goes slack.
	var facing := minf(erg.wrap_span_at(radius, 0.0, 0.0),
			erg.frame_span(radius, erg.view_aspect) * Ergonomics.FRAME_MARGIN)
	var arc: float = floor(facing / ChannelStrip.WIDTH) * ChannelStrip.WIDTH
	return arc - PANEL_MARGIN * 2.0 - MasterSection.GAP - MasterSection.WIDTH \
			- BankSelector.WIDTH - MasterSection.GAP


## How wide these strips lay out, folder gaps and all.
func _unrolled_width(indices: Array) -> float:
	return indices.size() * ChannelStrip.WIDTH \
			+ _group_breaks(DAW.state, indices).size() * GROUP_GAP


## Bent around the viewer when it is wide enough to need it and presented at the body.
##
## Not when it is standing in the room: a curved desk you walk up to has its curve centred on
## nobody, which is worse than flat. The bend only means anything when the centre of curvature
## is an actual eye, and the only time this surface knows that is when it has been summoned.
func wrap_radius() -> float:
	return _wrap


func _rebuild() -> void:
	_clear_built()
	_wrap = 0.0
	_row_span = 0.0
	_rows = 1
	_half_width = 0.0
	strips.clear()
	master = null
	bank = null

	var indices := DAW.state.track_indices()
	if indices.is_empty():
		return

	# One tier's worth, when this desk has been summoned to a body and not asked to show
	# everything. Sliced HERE, before anything is measured, because the page is what the desk
	# is -- sizing a 48-track panel and then hiding two thirds of it would leave the carcass,
	# the wrap radius and the tier count all describing a desk that is not on screen.
	var paged := compact and not expanded
	var page := page_size()
	if paged and indices.size() > page:
		view_offset = clampi(view_offset, 0, maxi(0, indices.size() - 1))
		view_offset -= view_offset % page
		indices = indices.slice(view_offset, mini(view_offset + page, indices.size()))
		# Folder gaps are 13mm each and a page of thirteen strips can carry four of them, so
		# a page sized purely in strips overflows its own tier and the desk silently grows a
		# second row -- which is the one thing paging exists to avoid. Drop strips from the
		# end until what is left genuinely fits.
		while indices.size() > 4 and _unrolled_width(indices) > _page_arc():
			indices = indices.slice(0, indices.size() - 1)
		page = indices.size()
	else:
		view_offset = 0
		paged = false

	# The bank module is only built when there is more project than bank -- a session that fits
	# on the desk needs no bank controls, and two dead buttons invite the question of what they
	# are for. See hardware/console/bank_selector.gd.
	var banking := paged \
			or (DAW.can(DAWBackend.Capability.TRACK_BANKING) and DAW.state.has_more_banks())
	var bank_width := (BankSelector.WIDTH + MasterSection.GAP) if banking else 0.0

	# Folder breaks are measured BEFORE the panel is sized, because they make the desk wider.
	# Sizing the plate first and then inserting gaps is how strips end up hanging off the end.
	var breaks := _group_breaks(DAW.state, indices)
	var channels_width := indices.size() * ChannelStrip.WIDTH + breaks.size() * GROUP_GAP
	var width := bank_width + channels_width + MasterSection.GAP + MasterSection.WIDTH \
			+ PANEL_MARGIN * 2.0

	_half_width = width * 0.5

	if compact:
		var erg := Ergonomics.current
		var pitch := _row_pitch()
		_wrap = erg.wrap_radius_for(width, pitch, ChannelStrip.WIDTH, SMALLEST_CAP)
		# How many tiers this desk NEEDS, not how many the glance could hold. wrap_rows is a
		# budget; using all of it would make a fourteen-strip page reserve three tiers and then
		# size its arc for the lowest of three, pulling a desk that fits on one row inward for
		# clearance it never uses.
		var most := erg.wrap_rows(_wrap, pitch)
		_rows = 1
		while _rows < most and width > _span_for(erg, pitch, _rows) * float(_rows):
			_rows += 1
		_row_span = _span_for(erg, pitch, _rows)
		# Reported, not hidden. The desk is drawn either way -- a mixer that refuses to appear
		# is worse than one you have to turn your head for -- but a session this wide has
		# outgrown the body in front of it and the honest answer is a narrower bank.
		if _row_span * float(_rows) < width:
			push_warning(("console: %.2fm of desk into %.2fm of reachable arc (%d rows at "
					+ "%.2fm); the ends are outside the head-turn. Bank narrower.")
					% [width, _row_span * float(_rows), _rows, _wrap])

	_panel = Node3D.new()
	# A wrapped desk is tilted by the RIG, about the eye, where the tilt costs no translation
	# and keeps every strip equidistant. Tilting the panel here as well would rotate the arc
	# about its own chord and throw the ends out of reach again.
	_panel.rotation_degrees = Vector3(0 if _wrap > 0.0 else -PANEL_TILT, 0, 0)
	_adopt(_panel)

	# Skipped when wrapped. A single 5-metre box cannot follow an arc, and the strips carry
	# their own backing plates -- which is why the bend is possible at all.
	if _wrap <= 0.0:
		_build_slabs(width)


	var x := -width * 0.5 + PANEL_MARGIN
	if banking:
		bank = BankSelector.new()
		bank.name = "Bank"
		# When paged, the caption counts in PROJECT tracks, not in page tracks. "1-14 OF 90" is
		# the only reading that helps; "1-14 OF 14" would be true of the page and a lie about
		# the session, which is the exact failure the bank module was written to prevent.
		bank.bank_offset = DAW.state.bank_offset + (view_offset if paged else 0)
		bank.bank_size = page if paged else DAW.state.bank_size
		bank.project_count = DAW.state.project_track_count
		bank.shown_count = indices.size()
		bank.transform = _seat(x + BankSelector.WIDTH * 0.5, PANEL_MARGIN, 0.0)
		bank.bank_requested.connect(_request_bank)
		_panel.add_child(bank)
		x += bank_width

	# Built BEFORE the strips and parented to the panel, because a button claims its slot by
	# converting its own world transform into the bank's -- so the bank has to be in the tree,
	# and in its final place, before the first strip exists.
	var body_bank := MeshBank.parts(PanelButton.BODY_SIZE, PanelButton.body_material())
	body_bank.name = "ButtonBodies"
	_panel.add_child(body_bank)
	var lamp_bank := MeshBank.lamps(PanelButton.LAMP_SIZE)
	lamp_bank.name = "ButtonLamps"
	_panel.add_child(lamp_bank)
	var plate_bank := MeshBank.parts(ChannelStrip.PLATE_SIZE, Materials.chassis())
	plate_bank.name = "StripPlates"
	_panel.add_child(plate_bank)
	var slot_bank := MeshBank.parts(Fader.SLOT_SIZE, Materials.recess())
	slot_bank.name = "FaderSlots"
	_panel.add_child(slot_bank)
	# The two authored parts. Null when the asset will not resolve, in which case every knob
	# and cap falls back to building its own mesh and the desk still works -- same contract as
	# the patchbay's jacks.
	var knob_bank := MeshBank.of(
		Knob.MESH_PATH,
		Materials.knob_cap(),
		{"indicator": Materials.legend()},
	)
	if knob_bank != null:
		knob_bank.name = "PanKnobs"
		_panel.add_child(knob_bank)
	var cap_bank := MeshBank.of(
		Fader.MESH_PATH,
		Materials.fader_cap(),
		{"indicator": Materials.legend()},
	)
	if cap_bank != null:
		cap_bank.name = "FaderCaps"
		_panel.add_child(cap_bank)
	# Unshaded like the lamps, because a colour chip is a lit patch and not a painted one -- it
	# has to stay findable on a desk of 32 identical strips in a dim room.
	var chip_bank := MeshBank.lamps(ChannelStrip.CHIP_SIZE)
	chip_bank.name = "ColourChips"
	_panel.add_child(chip_bank)
	var socket_bank := MeshBank.meshed(SendSocket.face_mesh())
	socket_bank.name = "SendSockets"
	# A nut 12mm across, flush on the panel: its shadow is nothing to see, and drawn into every
	# lamp's shadow maps a desk of them cost more primitives than the rest of the desk.
	socket_bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel.add_child(socket_bank)

	x += ChannelStrip.WIDTH * 0.5
	for index in indices:
		if breaks.has(index):
			# A rule in the gap, not just the gap. On a desk tilted away from you a plain space
			# reads as a missing strip; a line reads as a division, which is what it is.
			_group_rule(x - ChannelStrip.WIDTH * 0.5 + GROUP_GAP * 0.5)
			x += GROUP_GAP
		var strip := ChannelStrip.create(index)
		strip.body_bank = body_bank
		strip.lamp_bank = lamp_bank
		strip.plate_bank = plate_bank
		strip.chip_bank = chip_bank
		strip.slot_bank = slot_bank
		strip.knob_bank = knob_bank
		strip.cap_bank = cap_bank
		strip.socket_bank = socket_bank
		strip.transform = _seat(x, PANEL_MARGIN, 0.0)
		_panel.add_child(strip)
		strips.append(strip)
		x += ChannelStrip.WIDTH

	# After every claim and before anything can light up. A MultiMesh has to know how many
	# instances it holds before it can hold any, so this is the moment the buffer is sized.
	body_bank.commit()
	lamp_bank.commit()
	plate_bank.commit()
	slot_bank.commit()
	chip_bank.commit()
	socket_bank.commit()
	if knob_bank != null:
		knob_bank.commit()
	if cap_bank != null:
		cap_bank.commit()

	if _wrap > 0.0:
		_build_shell(width)

	master = MasterSection.new()
	master.name = "Master"
	master.transform = _seat(x + MasterSection.GAP + MasterSection.WIDTH * 0.5, PANEL_MARGIN, 0.0)
	_panel.add_child(master)
	master.sends_pressed.connect(cycle_sends)
	# A return that has gone -- deleted, or banked away -- takes the flip with it.
	if send_dest > 0 and not send_destinations(DAW.state).has(send_dest):
		send_dest = 0
	_show_sends()


## Every track something sends to, in track order: what the SENDS key steps through.
static func send_destinations(state: MixState) -> Array:
	var out: Array = []
	for index in state.track_indices():
		var t := state.track(index)
		for slot in t.sends:
			if int(slot) < 1:
				continue
			var dest: int = (t.sends[slot] as MixState.SendState).resolve(state)
			if dest > 0 and state.tracks.has(dest) and not out.has(dest):
				out.append(dest)
	out.sort()
	return out


## Faders on to the next return's sends; past the last, back to levels.
##
## Refused while a hand is on anything, by the rule banking keeps: a fader that changed what it
## writes in the middle of a drag would put the rest of the drag on the wrong number.
func cycle_sends() -> void:
	# Faders and knobs only: the SENDS key is itself held while it is being pressed.
	for node in find_children("*", "ControlAffordance", true, false):
		if (node is Fader or node is Knob) and (node as ControlAffordance).is_held():
			return
	var dests := send_destinations(DAW.state)
	var at := dests.find(send_dest)
	send_dest = dests[at + 1] if at + 1 < dests.size() else 0
	if dests.is_empty():
		send_dest = 0
	_show_sends()


func _show_sends() -> void:
	for strip in strips:
		strip.show_sends_to(send_dest)
	if master != null:
		master.show_sends("" if send_dest <= 0
				else DAW.state.track(send_dest).display_name().to_upper())


## Gap inserted at a folder boundary. Narrow on purpose: this is a seam between sections of one
## desk, not a gap between two desks, and anything wider starts to read as the latter.
const GROUP_GAP := 0.013


## Which of `indices` begin a new folder group, as a Dictionary used as a set.
##
## Returned rather than recomputed per strip because `folder_level` is a running sum over every
## track before it -- asking per strip makes laying out a 90-track desk quadratic for an answer
## that does not change during the layout.
##
## The FIRST strip is never a break. It begins a group, but there is nothing before it to be
## divided from, and a rule hanging off the left edge of the panel is just a scratch.
## Takes the state rather than reaching for the DAW autoload, which is not only testable but
## correct: this is arithmetic over a project, and a static helper that reads a global can only
## ever describe the one project that happens to be open.
static func _group_breaks(state: MixState, indices: Array) -> Dictionary:
	var out := {}
	var level := 0
	var previous := 0
	for i in indices.size():
		var index: int = indices[i]
		var depth: int = state.track(index).folder_depth
		if i > 0 and (depth > 0 or level < previous):
			out[index] = true
		previous = level
		level = maxi(level + depth, 0)
	return out


func _group_rule(at_x: float) -> void:
	var rule := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.0014, ChannelStrip.HEIGHT * 0.92, 0.0012)
	rule.mesh = mesh
	rule.transform = _seat(at_x, PANEL_MARGIN + ChannelStrip.HEIGHT * 0.5, 0.0008)
	# Legend white is what a LABEL is. A folder divider is a seam in a surface, and forty-seven
	# of them at label brightness turned a desk into a picket fence -- the brightest thing on
	# the panel after the meters, carrying the least.
	rule.material_override = Materials.recess()
	_panel.add_child(rule)


## The tilted panel, not the desk. The carcass is twice the height of the controls and carries
## nothing; on a monitor it is two thirds of the screen spent on a black box.
func framing_root() -> Node3D:
	return _panel if _panel else self


## Where one module sits on the panel: straight along x when flat, bent onto the arc when not.
##
## Applied HERE, at the moment a module is positioned, and not as a pass over the finished
## panel. The MeshBanks read each instance's transform off the node as it enters the tree, so a
## bend applied afterwards would move the strips and leave every banked knob, cap and lamp
## standing in the flat positions they were claimed at -- a console of floating controls next
## to the console they belong to.
##
## The arc's centre is at local (0, 0, radius), which is where the eye goes. Each module is
## turned by -theta so it faces that centre rather than staying square to the room; without the
## turn the strips stay parallel and the far ones are seen edge-on, which is most of what makes
## a wide flat desk unreadable in the first place.
## `flat` leaves the lay-back off, for the parts of the desk that are horizontal rather than
## panelled -- the armrest, most of all. Seating the rail in the tilted frame stood a 70mm-deep
## bar on its end and put a curved wall across the bottom of the view.
func _seat(x: float, y: float, z: float, flat: bool = false) -> Transform3D:
	if _wrap <= 0.0:
		return Transform3D(Basis.IDENTITY, Vector3(x, y, z))
	# `x` arrives as one long ruler across a desk that no longer exists. Cut it into rows first,
	# then bend what is left. The row runs left to right and the rows run bottom to top, because
	# that is the order the strips are in and reading order is the only thing that makes a
	# wrapped desk findable: track 40 is where track 40 would be if you unrolled it.
	var along := x + _half_width
	var row := 0
	if _row_span > 0.0:
		row = clampi(int(floor(along / _row_span)), 0, _rows - 1)
		along -= float(row) * _row_span
	return _seat_in_row(along, row, y, z, flat)


## Place something a given distance along a given row.
##
## Split out of `_seat` because the end cheeks cannot be addressed through the unrolled ruler:
## the right-hand one belongs at the far end OF ROW ZERO, and an x that far along the ruler is
## by definition the start of row one. Everything that is laid out strip by strip still goes
## through `_seat`, which cuts the ruler and then calls this.
func _seat_in_row(along: float, row: int, y: float, z: float, flat: bool) -> Transform3D:
	var theta := (along - _row_span * 0.5) / _wrap if _wrap > 0.0 else 0.0
	var lift := float(row) * _row_pitch()
	# Tilted, exactly as the flat desk is tilted, and leaving this out is what made the first
	# wrapped console unbearable: upright strips at face height on a closed circle are not a
	# desk you lean over, they are a cell you stand in. The tilt is also what makes the rows
	# affordable -- a panel laid back sixty degrees is half as tall in your field of view, so
	# the tiers stack inside the same glance.
	var lay := Basis.IDENTITY if flat else Basis(Vector3.RIGHT, -deg_to_rad(PANEL_TILT))
	if not CURVED:
		# Straight, with the rows and the lay-back kept. The bend is the one part of this that
		# is optional: it buys uniformity -- every strip the same distance away, head-on -- and
		# costs a lot of arithmetic to get right. The rows and the tilt are not optional.
		return Transform3D(lay, Vector3(along - _row_span * 0.5, y + lift, z))
	return Transform3D(Basis(Vector3.UP, -theta) * lay, Vector3(
			sin(theta) * (_wrap - z), y + lift, _wrap - cos(theta) * (_wrap - z)))


## How much height one tier of a wrapped desk costs. The panel's own height, foreshortened by
## its lay-back, plus a seam.
func _row_pitch() -> float:
	return ChannelStrip.HEIGHT * cos(deg_to_rad(PANEL_TILT)) + ROW_GAP


## The curved carcass: a continuous backing behind every tier, and an armrest along the near
## edge of the bottom one.
##
## The wrapped desk went out with none of this, and that single omission is most of why it
## looked wrong. A flat desk gets a backing plate, a body and an armrest; the bent one got
## forty-eight separate strips hanging in air with the room showing through the gaps between
## them, which reads as scaffolding rather than as a thing someone built.
##
## Drawn across the FULL row span rather than only behind the strips that exist, so every tier
## is the same length and the desk has an edge. A real console does the same with blank panels,
## and for the same reason: a ragged end reads as unfinished, not as economical.
##
## One box per slot rather than a swept mesh. They overlap by six percent, which closes the
## wedge-shaped gaps that butting flat boxes along a curve would otherwise leave, and it means
## the whole carcass is one MultiMesh and one draw call instead of a lathe.
func _build_shell(width: float) -> void:
	var per_row := int(round(_row_span / ChannelStrip.WIDTH))
	if per_row <= 0:
		return
	# Enough slots for the WHOLE desk, master section and bank module included, not just for
	# the channel strips. Sizing it to the strips left the master standing on nothing at the
	# end of the arc, which read as a separate panel that had drifted off the desk.
	var slots := maxi(per_row * _rows, int(ceil(width / ChannelStrip.WIDTH)))
	# Taller than the strip by one row gap, measured in the panel's own tilted plane, so the
	# tiers close into one stepped surface instead of showing daylight between them.
	var lay := ROW_GAP / maxf(cos(deg_to_rad(PANEL_TILT)), 0.1)
	# Eighteen percent wider than a strip, not six. These are flat boxes stood along a curve,
	# so the wedge between two of them opens up the further you get from the axis -- and the
	# top of a panel laid back sixty degrees is a long way from the axis. At six percent the
	# desk came out crenellated, a neat row of battlements along its back edge.
	var shell := MeshBank.parts(
			Vector3(ChannelStrip.WIDTH * 1.18, ChannelStrip.HEIGHT + PANEL_MARGIN + lay, 0.016),
			Materials.chassis())
	shell.name = "Carcass"
	_panel.add_child(shell)
	var rail := MeshBank.parts(
			Vector3(ChannelStrip.WIDTH * 1.18, 0.022, 0.07), Materials.brushed_metal())
	rail.name = "Armrest"
	_panel.add_child(rail)
	# The back rail, which is the armrest's opposite number and exists for the same reason: a
	# row of panels stood along a curve ends in a row of separate top edges, and from any seat
	# that is not dead centre they stagger. One continuous band across them closes the line.
	# Half again as wide as a strip, where the shell needs only eighteen percent. The rail sits
	# five centimetres behind the panel face and is nearly flat, so most of it lives at a bigger
	# radius than the strips do, and the wedge between neighbours opens up accordingly.
	var crown := MeshBank.parts(
			Vector3(ChannelStrip.WIDTH * 1.5, 0.016, 0.05), Materials.brushed_metal())
	crown.name = "BackRail"
	_panel.add_child(crown)
	# The carcass down to the floor. Without it the desk hangs in mid-air over its own shadow
	# and you can see the room underneath it, which is the difference between a console and a
	# control panel someone has bolted to nothing.
	var skirt := MeshBank.parts(
			Vector3(ChannelStrip.WIDTH * 1.18, SKIRT_HEIGHT, 0.17), Materials.furniture())
	skirt.name = "Carcass"
	# Set back behind the armrest rather than flush with it, so the desk has a toe recess and
	# the near edge keeps an overhang to cast a line along itself. Flush, it read as one slab
	# from the floor to the faders.
	skirt.add_to_group(&"presentation_chrome")
	_panel.add_child(skirt)

	for row in _rows:
		for slot in (slots if _rows == 1 else per_row):
			var x := float(row) * _row_span + (float(slot) + 0.5) * ChannelStrip.WIDTH \
					- _half_width
			# Offset INSIDE the tilted panel, by composing with the seat, rather than by
			# passing a taller y. _seat's y is a world-vertical lift applied before the
			# lay-back, so adding half a strip height there raises the backing straight up
			# instead of sliding it up the slope -- which put a 38cm slab in front of the tier
			# above and filled the screen with brown.
			var base := _seat(x, PANEL_MARGIN, 0.0)
			# Flush with the top of the strip, give or take a two-millimetre lip. Sized from
			# the old margin-both-ends formula the carcass stood seven centimetres proud of
			# every panel and the desk's back edge came out castellated.
			shell.claim(base * Transform3D(Basis.IDENTITY, Vector3(
					0, ChannelStrip.HEIGHT - (ChannelStrip.HEIGHT + PANEL_MARGIN + lay) * 0.5
							+ 0.002,
					-0.014)), Color.WHITE)
			# Above the panel, not across it. Set level with the top edge the rail lay over
			# every track name on the desk, which is a stylish way to build a mixer nobody
			# can use.
			crown.claim(base * Transform3D(Basis.IDENTITY,
					Vector3(0, ChannelStrip.HEIGHT + 0.006, -0.018)), Color.WHITE)
			if row == 0:
				rail.claim(_seat(x, -0.004, 0.052, true), Color.WHITE)
				skirt.claim(_seat(x, -SKIRT_HEIGHT * 0.5 - 0.03, -0.11, true), Color.WHITE)
	shell.commit()
	rail.commit()
	crown.commit()
	skirt.commit()
	_build_cheeks(width, lay)


## The timber at each end of the desk.
##
## Not decoration, or not only. A console built out of nothing but repeated strips has no edge
## -- the last panel is the same panel as the first, so the desk stops wherever the geometry
## happened to run out, and from an angle it reads as a surface that continues off into the
## dark. A pair of cheeks in the one material nothing else in the room uses says where it ends.
##
## Sized from the carcass rather than declared: top edge level with the back rail, bottom edge
## at the foot of the plinth, so it is one board down the whole side of the thing regardless of
## how many tiers got built.
func _build_cheeks(width: float, lay: float) -> void:
	# In the panel's own plane, tilted with it, and built from the same numbers the shell is
	# built from. Stood upright beside the desk instead -- which is what a box placed in world
	# axes does -- a cheek is a slab that happens to be near a console, with a wedge of daylight
	# between it and the panel that widens as the panel lays back. It has to be a side board of
	# the thing, not a thing of its own.
	var thick := 0.026
	var tall := ChannelStrip.HEIGHT + PANEL_MARGIN + lay + float(_rows - 1) * _row_pitch()
	var cheek := MeshBank.parts(Vector3(thick, tall, 0.085), Materials.end_cheek())
	cheek.name = "EndCheeks"
	_panel.add_child(cheek)
	# `width`, not the slot count the shell rounds up to. The shell may overrun the desk by
	# most of a strip and nobody sees it, because it is behind the panels; a cheek that does
	# the same is a board floating off the end with a gap behind it.
	for ends in [-thick * 0.5, width + thick * 0.5]:
		var base := _seat_in_row(ends, 0, PANEL_MARGIN, 0.0, false)
		cheek.claim(base * Transform3D(Basis.IDENTITY, Vector3(
				0, ChannelStrip.HEIGHT - tall * 0.5 + 0.002, -0.014)), Color.WHITE)
	cheek.commit()


## The three full-width slabs: the panel backing, the desk body and the armrest.
##
## Built only for a flat desk. None of them can follow an arc -- a single 5-metre box bent
## round a viewer is just a box at a jaunty angle -- and a wrapped console has no use for them
## anyway: it is summoned, so it is not furniture, and the strips bring their own backing.
func _build_slabs(width: float) -> void:
	var panel_plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	# A few millimetres proud of everything it meets, on every side. Cut to the same size, its top
	# edge lay in exactly the plane of every strip plate's top edge and its ends in the plane of
	# the body's ends, and two faces in one plane are drawn in whichever order the depth buffer's
	# rounding picks that frame: a desk whose edges crawl as the camera moves.
	plate_mesh.size = Vector3(width + 0.004, ChannelStrip.HEIGHT + PANEL_MARGIN * 2.0 + 0.006, 0.018)
	panel_plate.mesh = plate_mesh
	panel_plate.position = Vector3(0, ChannelStrip.HEIGHT * 0.5 + 0.003, -0.014)
	panel_plate.material_override = Materials.chassis()
	_panel.add_child(panel_plate)

	# The desk body, which is doing more than decoration: in ROOM mode it is what tells a person
	# in passthrough that they must not walk through this spot.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(width, 0.62, 0.34)
	body.mesh = body_mesh
	body.position = Vector3(0, -0.31, -0.10)
	body.material_override = Materials.furniture()
	GearTrim.edges(body)
	_adopt(body)

	# Armrest along the near edge. Real desks have one, and more usefully it gives a hand in AR
	# something to rest against while reaching for a fader -- without it, a 100mm throw in mid-air
	# is done entirely by unsupported arm.
	var rest := MeshInstance3D.new()
	var rest_mesh := BoxMesh.new()
	# Overhanging the body a little at each end, for the same reason as the panel above.
	rest_mesh.size = Vector3(width + 0.010, 0.022, 0.07)
	rest.mesh = rest_mesh
	rest.position = Vector3(0, 0.005, 0.055)
	rest.material_override = Materials.brushed_metal()
	_adopt(rest)
