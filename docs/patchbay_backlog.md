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
2. Wall caps at 12 ports a column and 150 cables, silently past that; no paging, scrolling, filter.
3. Routing bay rows shrink to 26 mm and then the panel grows without bound; 64+ tracks is a
   tower no one can reach. Needs paging/zoom or a filter by name.
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
