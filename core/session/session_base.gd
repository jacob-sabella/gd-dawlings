class_name SessionBase
extends Node

## The vocabulary of the session autoload: its ports, channels, limits, verb tables, notes enum and every signal it
## raises. Split out of `core/session/session.gd` without change of behaviour; `Session` extends this, so
## `Session.DEFAULT_PORT`, `Session.note_played` and the rest are reached as they always were.

const Role := {SOLO = 0, HOST = 1, GUEST = 2}
const DEFAULT_PORT := 7332
## Where a hosting session says so to the LAN, once a second. One above the game port so a
## firewall rule written for one is easy to widen to the other.
const DISCOVERY_PORT := 7333
## The mix's audio, on a socket of its own. See core/session/mix_feed.gd for why not ENet.
const AUDIO_PORT_OFFSET := 2
const BEACON_SECONDS := 1.0
const GOODBYE_SECONDS := 0.3
## How long a connection may sit unintroduced before the host hangs up on it. Long enough for a
## guest on a slow wifi hop to build its scene and say hello; short enough that a port scan does
## not leave a row of ghosts holding slots.
const ADMIT_SECONDS := 6.0
## How long a guest by code waits for a punched path before asking for the relay, and then for
## the relay. Six seconds: ENet's own connect gives up later than a person will wait.
const LINK_SECONDS := 6.0
## How long the host sends toward a guest noray announced, ten times a second.
const PUNCH_SECONDS := 3.0
## The mix, carried over the session's ENet for a guest by code (MixFeed.carried). Its own
## channel, so it never waits behind a reliable message on another.
const MIX_CHANNEL := 9
## How long a guest's mix socket waits to hear the mix over a punch, then over the relay, before
## the next way. Shorter than the session's: a mix that is not heard in three seconds is not coming.
const MIX_LINK_SECONDS := 3.0
## Handed out in join order, and the host's is the first. Chosen against every venue rather
## than for one: each has to read as a light on a dark studio AND on the chalk room's pale
## walls, and no two may be confusable by someone with the commonest colour-vision deficits --
## which is why there is a blue and an orange before there is a red and a green.
const PALETTE: Array[Color] = [
	Color(1.00, 0.58, 0.20),  # amber
	Color(0.30, 0.78, 1.00),  # sky
	Color(0.95, 0.38, 0.72),  # magenta
	Color(0.45, 0.90, 0.52),  # mint
	Color(0.72, 0.56, 1.00),  # violet
	Color(1.00, 0.88, 0.34),  # yellow
	Color(0.35, 0.95, 0.88),  # teal
	Color(1.00, 0.45, 0.42),  # coral
]
## A peer was admitted to the session.
signal participant_joined(peer_id: int)
## Joining by a code, or hosting online, moved on: found, punched, relayed, or failed. See `online`.
signal link_changed()
## A peer left or was dropped.
signal participant_left(peer_id: int)
## This process became host, guest or solo.
signal role_changed()
## Names, colours or mediums changed. Fires on everyone, from the host's word on the matter.
signal roster_changed()
## Who is holding which control changed. See `holds`.
signal holds_changed()
## A grab this participant made was turned down by the host: somebody else got there first.
signal hold_refused(control_key: String, holder: int)
## Something a person in the room should be told in words -- someone came in, the host went
## away. Owned by whoever draws the session's UI; nothing here waits on it being read.
signal notice(text: String)
## Host: a guest's recording was placed. {peer, track, start, seconds, path, name}.
signal audio_take_placed(info: Dictionary)
## Guest: the host's word on the room arrived; see `room`.
signal room_changed()
## A made item's row arrived (`made`, ItemRoom.mint), or was taken away (`gone`): a guest's word
## from the host, for the room to make it real or let it go.
signal made_changed(id: StringName, gone: bool)
## Host: someone asked to change the room. One of ROOM_VERBS, already checked for shape; the
## studio decides, and says what the room now is with `publish_room`.
signal room_asked(verb: StringName, args: Array, from: int)
## Guest: the host's word on the tour run under way arrived; see `tour`.
signal tour_changed()
## Host: someone asked to act on the run under way. One of TOUR_VERBS, already checked for
## shape; `Tour` decides, and says what the run now is with `publish_tour`.
signal tour_asked(verb: StringName, args: Array, from: int)
## Guest: the host's word on the last Rig Roulette roll arrived; see `roll`.
signal roll_changed()
## Guest: the host's word on what the next Rig Roulette roll is set to arrived; see `roll_setup`.
signal roll_setup_changed()
## Something in the room being pushed right now, by `from`: where it is this moment. Unconfirmed
## and unsaved -- the ask when it is let go is what counts -- and only for drawing it moving.
signal room_motion(piece: StringName, x: float, z: float, heading: float, from: int)
## Something in `from`'s hand, where it is this moment: relative to their head, so it lands in
## their ghost's glove wherever everyone has the ghost. Unreliable, like a head.
signal item_carried(item: StringName, local: Transform3D, from: int)
## Where something somebody is flying is (the radio plane, RcPlaneItem), in the session's frame,
## and how it is flying (its Mode).
signal item_flown(item: StringName, pose: Transform3D, mode: int, from: int)
## Something in `from`'s hand, used: a duck squeezed (`down`) or let go of. Reliable, because a
## squeak is an event, and a lost one is a silence nobody can account for. `take`: which of Foley's
## takes their hand rang (Item.use_take), so everyone hears the sound its player heard and the
## host's sampler catches exactly that (Sampler); -1 for not known.
signal item_used(item: StringName, down: bool, from: int, take: int)
## A key or the pedal on `from`'s keys, as they play it (`send_note`): for anyone patched into
## their keys to play here (TheirKeys), or into their monitor (TheirMonitor). `song`: the song
## position they were hearing as they played it, or -1 with their transport stopped. `source`:
## what of theirs played it (GuestMidi.instruments' names, `&""` for plain keys), so a note can
## be heard from the instrument that played it. Reliable and ordered, because a lost note-off is
## a note that never stops.
signal note_played(kind: int, pitch: int, velocity: int, from: int, song: float, source: StringName)
## An instrument in `from`'s hand shaken into a hit (InstrumentItem), `velocity` 1 to 127: for
## everyone else to hear from their hand. A click on percussion is a use (`item_used`), not this;
## a click on a pitched item is this too. `song`: the song position they played it
## to (the hit's one stamp, InstrumentItem.played's `at`), or -1 when not known, so a pitched item
## rings here the note it rang there, whenever it arrives. `snap`: whether its player snaps their
## hand percussion (GuestMidi.snap_hits), so whoever takes the hit down snaps it by their choice,
## not their own (HitRecorder.hit). `take`: which of Foley's takes their hand rang
## (InstrumentItem.sound_take), so everyone hears the sound its player heard; -1 for not known.
## A strike on an instrument that stands still (Item.fixed, docs/spatial_loop.md part two, slice 38)
## is this too, held by nobody: `zone` is where on it they struck it (InstrumentItem.zone_at, &""
## for an item with none), and it is heard from where the instrument stands.
signal item_hit(item: StringName, velocity: int, from: int, song: float, snap: bool, take: int, zone: StringName)
## An event down a jack into this player's instrument (docs/spatial_loop.md slice 6): `source`'s
## (an item's id, `keys:P`, `chord:P`) `kind` (Jack.Kind: NOTE_ON, NOTE_OFF, TRIGGER, CC,
## CHORD), sent by `from`
## at song position `song` (-1 for not known), passed on by the host to this player alone (Jacks).
signal jack_played(source: StringName, kind: int, pitch: int, velocity: int, from: int, song: float)
## A control on `from`'s keys, as they move it (`send_control`): `kind` the pitch wheel
## (DawKitClip.PITCH_BEND) or controller 1 (the mod wheel) or 11 (expression), `value` already
## kept in bounds by the host (`control_value`). For whoever plays their keys here (TheirKeys,
## TheirMonitor), to the one voice they have for that player. Unreliable: a lost one is
## sent again soon, and the wheel goes back to rest at the player's last note-off on every end
## (GuestMidi.control).
signal control_played(kind: int, value: int, from: int, song: float, source: StringName)
## The host's track spectra have arrived (`spectra`), on a guest.
signal spectra_heard()
## What a `note_played` is.
enum Note { OFF, ON, PEDAL_UP, PEDAL_DOWN }
## The kinds of device a guest may offer the host: their audio input (`audio`), and their keys and
## MIDI (`midi`). Nothing a guest has is used until the host allows it, one kind at a time.
const SHARE_KINDS: Array[StringName] = [&"audio", &"midi"]
## The channel a guest's live audio travels on: unreliable and ordered, its own, so a dropped
## packet is a click and never a stall, and never queues a note behind it.
const LIVE_CHANNEL := 10
## The most a live packet may carry, bytes: a tenth of a second of mono 16-bit at 48 kHz.
const LIVE_PACKET_MAX := 9600
## `peer` now plays into `track` (0 when they join or have none).
signal play_track_changed(peer: int, track: int)
## A guest's device offers, grants or refusals changed (`share_offers`, `shares`, `my_shares`).
signal shares_changed()
## Host: a guest's live audio, mono 16-bit at 48 kHz, as it arrived (`_live_up`), once the host has
## allowed that guest's audio input.
signal live_audio_heard(from: int, pcm: PackedByteArray)
## The ENet channel a guest's recording travels on: its own, so a take in flight never queues a
## fader move or a hold behind it.
const AUDIO_TAKE_CHANNEL := 3
## Things being pushed about the room: unreliable and ordered, on a channel of their own so a
## rack being wheeled is never queued behind anyone's head.
const MOTION_CHANNEL := 4
## Notes as they are played: their own channel, so a key is never queued behind a room update.
const KEYS_CHANNEL := 5
## Pitch bend and the two controllers beside it, as they move: a channel of their own,
## unreliable and ordered, so a lost control never holds a note back behind its resend (the
## head-of-line delay a reliable channel has) and the notes stay reliable on KEYS_CHANNEL.
const CONTROLS_CHANNEL := 6
## The host's track spectra (Spectra, the EQ wall's), five times a second: unreliable and ordered,
## a lost one overtaken by the next, on a channel of their own so they never wait behind a key.
const SPECTRA_CHANNEL := 7
## How often a knob's turn may be streamed, a second: the studio holds a turn to this.
const KNOBS_PER_SECOND := 30.0
## The controls a player's keys carry (`send_control`): the pitch wheel, the mod wheel (1) and
## expression (11). The host passes these and refuses any other. A take carries the same
## (MidiTake.CONTROL_KINDS), and so does a jack (Jack.Kind.CC).
const CONTROL_KINDS := MidiTake.CONTROL_KINDS
## The longest a note's source may be (`send_note`): an instrument's name. Anything longer that
## a guest sends is taken as plain keys.
const NOTE_SOURCE_MAX := 24
## What a guest may ask of the room. Not the venue: whose room it is decides what it looks like.
const ROOM_VERBS := {&"tv": [TYPE_STRING, TYPE_BOOL, TYPE_FLOAT], &"open_tablet": [TYPE_INT, TYPE_INT, TYPE_STRING, TYPE_FLOAT, TYPE_FLOAT],
		&"close_tablet": [TYPE_STRING_NAME], &"move_tablet": [TYPE_STRING_NAME, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT],
		&"move_piece": [TYPE_STRING_NAME, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT],
		&"place_surface": [TYPE_STRING_NAME, TYPE_TRANSFORM3D],
		&"put_item": [TYPE_STRING_NAME, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT], &"home_item": [TYPE_STRING_NAME],
		&"throw_item": [TYPE_STRING_NAME, TYPE_VECTOR3, TYPE_VECTOR3, TYPE_VECTOR3],
		&"wear_item": [TYPE_STRING_NAME, TYPE_BOOL], &"pocket_item": [TYPE_STRING_NAME, TYPE_INT], &"patch": [TYPE_INT, TYPE_STRING_NAME],
		&"on_air": [TYPE_BOOL], &"take_personal": [TYPE_STRING_NAME], &"board_source": [TYPE_STRING_NAME],
		&"open_track_rack": [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT], &"close_track_rack": [TYPE_STRING_NAME],
		# An instrument's output jack into a sink (Jack), or unplugged (an empty sink).
		&"plug": [TYPE_STRING_NAME, TYPE_STRING_NAME],
		# The fifths wheel's SET: the bar it writes at and the brackets' inside (FifthsWheel).
		&"harmony": [TYPE_INT, TYPE_STRING],
		# A stage table's rope tied or cut, and whether it added the compressor it keys: the room's
		# `ropes` row (StageTable.ropes; docs/spatial_loop.md slice 20).
		&"rope": [TYPE_STRING, TYPE_BOOL, TYPE_BOOL],
		# Made while playing (docs/spatial_loop.md part two, slice 23): a made item of a kind, of
		# something the host has ("clip:<track>:<item>"), never its data, which the host packs; an item
		# into a holder's slot (ItemRoom.holders: the cassette rack, its bin); and an
		# item handed to a bandmate, into their hand.
		&"make": [TYPE_STRING_NAME, TYPE_STRING],
		&"slot_item": [TYPE_STRING_NAME, TYPE_STRING_NAME, TYPE_INT],
		&"give": [TYPE_STRING_NAME, TYPE_INT],
		# A cassette in the asker's hand pasted onto a track at a song time (slice 24): named by
		# its id, never its clip, which the host pastes from its own row (DAW.paste_item).
		&"paste": [TYPE_STRING_NAME, TYPE_INT, TYPE_FLOAT],
		# The sampler's REC pressed on (for the asker's next sound) or off (slice 26): the room's
		# `sampler` row, the peer it is armed for or 0 (Sampler.armed_by).
		&"sampler": [TYPE_BOOL],
		# The weather's switch (slice 44): LISTEN or OFF, the room's `weather` row (Weather.listening).
		&"weather": [TYPE_BOOL],
		# A scratch on the DJ platter, for the sampler (slice 27): the cassette in its slot by id,
		# and the scratch's path (Varispeed.path), which the host renders from its own render.
		&"scratch": [TYPE_STRING_NAME, TYPE_PACKED_FLOAT32_ARRAY],
		# The looper's pad slapped (slice 45): armed for the asker from a bar (-1 to start the
		# transport) for so many bars, or 0 bars to clear their own row; the room's `looper` row
		# [peer, from_bar, bars] (Looper.answer). And a guest's finished layer, its notes [on, off,
		# pitch, velocity, channel] in song seconds, for the host to write as their track (Looper.write_layer).
		&"looper": [TYPE_INT, TYPE_INT],
		&"looper_layer": [TYPE_FLOAT, TYPE_FLOAT, TYPE_ARRAY],
		# The modular room's rack (RackPatch.answer): its patch, edited. The room's `rack` row.
		&"rack": [TYPE_STRING_NAME, TYPE_ARRAY],
		# An edit of the room's layout (LayoutEdit): move, rotate, add, remove or reset a piece. Host only, but a
		# guest's `move` of a piece on wheels is the push it makes by hand anywhere (docs/layouts.md 7).
		&"layout": [TYPE_STRING_NAME, TYPE_ARRAY],
		# Look to solo (LookSolo, docs/spatial_loop.md part three, G): the track looked at, held or
		# let go. The host solos it alone for the room and puts every solo back at the let-go.
		&"look_solo": [TYPE_INT, TYPE_BOOL]}
## The most a hit's zone may be (characters): a word, "bass" or "slap", or a pad's drum.
const ZONE_MOST := 16
## What a guest may ask of a run under way. Starting a run (breaking the case) and ending one
## are host-only and never asked: only the host can break the case, and only the host calls a
## run off. `draft_pick` is the one thing a guest originates.
const TOUR_VERBS := {&"draft_pick": [TYPE_INT]}
const PARCEL_BYTES := 1100
