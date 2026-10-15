# Patch bay loop

Two patch surfaces, both in hardware/patchbay/:

- **PatchbaySurface** (the routing bay, tracks to tracks): two fixed columns FROM / TO, one row per
  track, `MAX_SLOTS = 7` jacks a row, row height clamped 26-50 mm over a 0.9 m span, so rows run
  off the panel's body past ~35 tracks (the panel just grows downward). Cables are `PatchCable`
  per send, every send redrawn on a rebuild. Patching: drag row to row, drag plug to re-patch,
  pull off to unplug, scroll for level. Hover dims everything but one track's cables.
- **PatchWallSurface** (the machine's audio graph from PipeWire, stood on two legs at 0.55 scale in
  every venue, hung in the studio's side room): boxes of ports, one ribbon mesh for all cables,
  `MAX_ROWS = 12` ports a column (the rest counted at its foot), `CABLE_LIMIT = 150`.

## Ranked problems

1. ~~Back of the wall: panel, boxes and frame bars are one-sided quads, so from behind it is a
   see-through screen with jacks and cables floating.~~ Fixed (iteration 1, below).
2. ~~Wall capped at 12 ports a column, the rest unreachable.~~ Paged (iteration 2). Still open: a filter/search by name, and CABLE_LIMIT 150.
3. ~~Routing bay rows shrank to 26 mm and the panel grew without bound (64 tracks: a 2 m tower).~~ Paged (iteration 3). Still open: filter by name, an off-page send has no cable, only its plug.
4. Routing bay `MAX_SLOTS = 7`: a track with more sends than that shares a bore (`mini(i, 6)`).
5. Cable clutter at 100+ patches: no bundling, no level of detail.
6. Labels at small rows are tiny from the seat; no hover-for-full-name.
7. Nothing undoes a patch.

## Stress table

Not yet measured (4/16/64/256 sources, 1/32/128/512 patches); next iterations.

## Iteration 1: the wall's back

A solid case behind the frame (`Casing`: chassis box, trim rim and three cross ribs, a nameplate
"AUDIO DEVICES · PATCH WALL" on its back face). Checked from behind in grid and desert
(shots/pb_grid_back3.png, shots/pb_desert_back.png) against the baseline shot, where only jack
dots and cables were visible (shots/pb_grid_y-1.57.png). Front unchanged (pb_grid_front_after.png
against pb_grid_y1.57.png). Suite 0 failed (10598 checks; the total has moved by itself between runs).

## Iteration 2: the wall pages

Each column packs its ports into pages of at most 12 rows (`_pages`); a node with more ports than a
page is cut across pages (title "name (1-12)"). ◀ ▶ buttons and "PAGE n / m · N PORTS" at the foot
of a column with more than one page; pages wrap. Before, whole nodes that did not fit were skipped
and only counted ("+N more ports"), so 190 outputs left 178 of them unpatchable. Tests: 190 outputs
make 16 pages, each port on exactly one, a page draws only its own jacks, turning shows others,
pages wrap. Suite 10605, 0 failed. Not yet looked at in a screenshot (the machine's real graph
fits one page, so nothing changes on screen until a graph is large).

## Iteration 3: the routing bay pages

Past 24 rows the bay shows a page of 24 per column, each column paged on its own (FROM turned to
the sender, TO to the receiver), with `<` `>` buttons and "1-24 OF 64" at the foot. 13 tracks are
one page, drawn exactly as before. 64 tracks went from a 2.1 m tower of 26 mm rows running off the
stand (shots/pbay_64.png) to a 24-row panel that fits it (shots/pbay_64_after3.png). A send whose far
end is on another page keeps its plug on the visible end, with no cable; dragging that plug
re-patches or unplugs it as usual, hovering skips the missing row. Suite 10608, 0 failed.

## Iteration 4: stress table, and busy returns

`tools/patchbay_stress.tscn` (headless) builds the routing bay at three sizes with random sends:

| tracks | sends | pages | plugs drawn | cables drawn | nodes | build ms |
|---|---|---|---|---|---|---|
| 16 | 32 | 1 | 68 | 34 | 1297 | 69 |
| 64 | 128 | 3 | 95 | 15 | 1373 | 20 |
| 256 | 512 | 11 | 101 | 9 | 1289 | 16 |

The bay's cost is flat in the size of the session (it only ever builds a page a column), so
256 tracks and 512 patches cost what 16 do. Not yet measured as frame ms in the studio, nor
as a screenshot at 256. The cost of that flatness: sends whose far end is on another page show
a plug and no cable, so at 512 patches only ~9 cables are visible; an off-page indicator or a
"show this track's routing" view is the next thing to do.

Busy returns: a row was capped at 7 jacks, so an eighth cable shared a bore. Now up to 12, the
pitch closing from 28 mm to 22 mm past seven (13 tracks and the usual rigs are unchanged). Test: 11
senders into one return get 11 jacks, no two plugs closer than a plug diameter. Beyond 12 sends
into one track the last jack is still shared (open). Suite 10613, 0 failed.

## Iteration 5: the wall's lettering

Steered by the user: the wall (audio devices) is the patch bay that matters most; the routing bay was
a bonus. Port labels on the wall went from font 34 to 46, node titles 40 to 50, and unused ports'
colour from 0.55 to 0.72 grey, so the names read from the seat (shots/wall_close.png before,
shots/wall_close2.png after). Next on the wall: highlight a jack's cables on hover, a filter by name,
CABLE_LIMIT 150, the empty middle of the wall.

## Iteration 6: the wall's hover

Hovering a port on the wall keeps its own cables lit and dims the rest toward the panel (the ribbons
are redrawn on their own, not the whole wall). Resting look unchanged (shots/wall_close3.png).
Tests: hovering keeps every cable and leaving restores. The dimmed look itself has not been seen in
a shot (no hover in the shot tool). Suite 10615, 0 failed.

## Iteration 7: links on other pages are counted

The wall's footer now says "N to other pages" for links with one end off-page (they have no cable
to draw). CABLE_LIMIT 150 is no longer a loss: a page of 12 outputs against 12 inputs shows at most
144 cables, so the cap cannot bite (struck from the list). Test: two links whose output page is
not showing are counted. Suite 10616, 0 failed. Open: a filter by name; the empty middle of the wall.

## Iteration 8: the back in the other venues (checked, nothing kept)

Shot from behind in cabin, rooftop and the studio (shots/pb_back_*.png). Rooftop: the casing, rim,
three ribs and the nameplate read as finished hardware. Cabin: the same casing, only very dark (the
venue's own lighting; the nameplate is visible). The studio's wall is hung on the side room's back
wall facing in (`StudioVenue._hang_patch_wall`), so its back is against plaster and cannot be
walked behind: no back needed. No change made.
