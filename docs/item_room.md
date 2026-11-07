# Items and the item room

An item is a thing a person picks up and carries round the studio: a toy, an instrument, a mic, headphones, a
tablet, a cassette made from a clip. `ItemRoom` holds every item in the room and the rules for where one may be.
Behaviour briefs and history are in `docs/items_loop.md`; the spatial ideas behind them in `docs/spatial_loop.md`.

## Files

| Class | File | What |
|---|---|---|
| `Item` | `core/items/item.gd` | the base: model, hint, title, pick up / put down, use, bound_to (who may hold it), `fixed` (an instrument that stands still) |
| `InstrumentItem` | `instrument_item.gd` | an item played by shaking or striking; `CowbellItem`, `WoodblockItem`, `PadItem`, `TriangleItem`, `ClavesItem`, `HihatItem`, `BongoItem`, `HandDrum`, `KitItem` are its kinds |
| other items | `*_item.gd` | one class a kind: `DuckItem`, `BallItem`, `PlaneItem`, `RcPlaneItem`, `MicItem`, `HeadphonesItem`, `TabletItem`, `SignalGlassesItem`, `ChipsItem`, `CardsItem`, `DartItem`, `CradleItem`, `YoyoItem`, `ToyItem`, `CassetteItem`, `MiniatureItem` |
| `ItemRoom` | `item_room.gd` (703 lines) | `KINDS`, `PERSONAL_KINDS`, `MADE_KINDS`, `make(kind)`, the rules for where an item may lie, the host's row |
| helpers of `ItemRoom` | `ItemSlots`, `ItemMade`, `ItemFlight` (with `Flight`), `ItemPlacing`, `ItemReplica` | the slots of a holder (shelf, rack, hook); made items; throws and flights; wearing, pocketing and putting down; the room's row and a guest's application of it |
| `ItemHost` | `item_host.gd` | the studio's side: where each item lives (`_item_homes`), building the room's items, minting cassettes, giving an item to a peer |
| holders and extras | `CassetteRack`, `Pockets`, `Hoop`, `HitRecorder`, `TabletFace` | the cassette rack, the pockets, the basketball hoop, taking hand percussion down as MIDI, what a tablet shows |
| The shelf | `VenueShelf` (`core/venues/`) | `Venue.item_spots()`: where on the prop shelf each item lives |

## How it fits

- The studio builds an `ItemRoom` in `ItemHost._build_items()` and hands it the walker's reach, floor and solids; the
  room judges every put-down (an item lies only where a person could reach to pick it up again, never on gear or in
  a wall; anywhere else it goes home to its shelf spot).
- In a session the room is the host's: the studio's room row carries `items` (`ItemReplica.state`), a guest's hand
  puts something down at once and asks (`put_item`, `home_item`, `throw_item`, `wear_item`, `pocket_item`, `give`,
  `make`, ...: the `ROOM_VERBS` in `SessionBase`), and the host's word stands or puts it back. What an item does in a
  hand (carried, used, hit) goes on `Session.item_carried`, `item_used`, `item_hit` (`docs/session.md`).
- Made items (cassettes) are minted by the host, their data sent once on a message of their own and the room row
  names only the id.
- An item is not a piece of the layout: its shelf is placed by the layout, the item is not (`docs/layouts.md`).

## How to add an item kind

1. Write `core/items/<kind>_item.gd` extending `Item` (or `InstrumentItem` for something struck or shaken): set `id`
   in `_init`, override `item_title`, `hint`, `_build_body`, and the use/hit hooks.
2. Add the kind to `ItemRoom.KINDS` (a shelf item; order is the order of the shelf's spots) and an arm to
   `ItemRoom.make`. A personal one (everyone gets their own copy) also goes in `PERSONAL_KINDS`; one made while playing
   in `MADE_KINDS`.
3. If it makes a sound, add the voice to `Foley` / `ItemVoices` and give the use a `take` so every player hears the
   sound its player heard.
4. Give the shelf a spot: `Venue.item_spots()` yields one per kind, and tests check each venue has them.
5. Run the item tests (`DAWLINGS_TESTS=` with the `_test_*item*` and `_test_a_duck_*` groups), the venue spot
   test, and `tools/session_probe.sh` for the guest side (`tools/probe/session_probe_items.gd`).

## Tests

`tests/run_tests.gd` groups named for items (`_test_a_duck_is_picked_up_squeezed_and_put_down`, ...);
`tools/probe/session_probe_items.gd` for the wire. Known failures on this branch are listed in
`docs/refactor_loop.md` ("Known failures").
