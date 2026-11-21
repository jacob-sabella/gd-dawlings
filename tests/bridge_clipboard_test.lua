-- The bridge's exact-target verbs, run outside Reaper against a small fake project, as
-- tests/bridge_decode_test.lua runs the decoder: the block is lifted out of
-- reaper/dawlings_bridge.lua by its text, because the bridge talks to Reaper the moment it loads.
-- The one argument names the part to run: round_trip or targets.
local here = arg[0]:match('(.*/)') or './'
local f = assert(io.open(here .. '../reaper/dawlings_bridge.lua', 'r'))
local text = f:read('*a')
f:close()
local from = text:find('-- --- exact targets and clipboards', 1, true)
local to = text:find('-- --- end of exact targets', from, true)

local failures, checks = 0, 0
local function check(label, ok)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print('FAIL  bridge clipboard: ' .. label)
  end
end

local tracks, blocks, open_blocks, serial
local function fresh(count)
  tracks, blocks, open_blocks, serial = {}, 0, 0, 0
  for n = 1, count do tracks[n] = {items = {}} end
end
local function add(track, pos, len, extra)
  serial = serial + 1
  local it = {track = tracks[track], D_POSITION = pos, D_LENGTH = len, C_LOCK = 0, selected = false,
    sound = 'sound' .. serial, take = {D_STARTOFFS = 0, D_PLAYRATE = 1}}
  for k, v in pairs(extra or {}) do it[k] = v end
  table.insert(tracks[track].items, it)
  return it
end
local function all_items()
  local out = {}
  for _, tr in ipairs(tracks) do
    for _, it in ipairs(tr.items) do out[#out + 1] = it end
  end
  return out
end
local function selected()
  local out = {}
  for _, it in ipairs(all_items()) do
    if it.selected then out[#out + 1] = it end
  end
  return out
end

reaper = {
  GetTrack = function(_, n) return tracks[n + 1] end,
  CountTrackMediaItems = function(tr) return #tr.items end,
  GetTrackMediaItem = function(tr, n) return tr.items[n + 1] end,
  GetMediaItem_Track = function(it) return it.track end,
  GetMediaItemInfo_Value = function(it, key) return it[key] end,
  SetMediaItemInfo_Value = function(it, key, v) it[key] = v end,
  GetActiveTake = function(it) return it.take end,
  GetMediaItemTakeInfo_Value = function(take, key) return take[key] end,
  SetMediaItemTakeInfo_Value = function(take, key, v) take[key] = v end,
  CountSelectedMediaItems = function() return #selected() end,
  GetSelectedMediaItem = function(_, n) return selected()[n + 1] end,
  SetMediaItemSelected = function(it, on) it.selected = on end,
  AddMediaItemToTrack = function(tr)
    local it = {track = tr, D_POSITION = 0, D_LENGTH = 0, C_LOCK = 0, selected = false,
      take = {D_STARTOFFS = 0, D_PLAYRATE = 1}}
    table.insert(tr.items, it)
    return it
  end,
  DeleteTrackMediaItem = function(tr, it)
    for n, other in ipairs(tr.items) do
      if other == it then table.remove(tr.items, n); return true end
    end
  end,
  GetItemStateChunk = function(it)
    return true, string.format('<ITEM\nIGUID {%s}\nGUID {%s}\nSOUND %s\nLEN %f\nLOCK %d\nOFFS %f\n>',
      it.sound, it.sound, it.sound, it.D_LENGTH, it.C_LOCK, it.take.D_STARTOFFS)
  end,
  SetItemStateChunk = function(it, chunk)
    it.chunk = chunk
    it.sound = chunk:match('SOUND (%S+)')
    it.D_LENGTH = tonumber(chunk:match('LEN (%S+)'))
    it.C_LOCK = tonumber(chunk:match('LOCK (%S+)'))
    it.take.D_STARTOFFS = tonumber(chunk:match('OFFS (%S+)'))
    return true
  end,
  Undo_BeginBlock = function() blocks = blocks + 1; open_blocks = open_blocks + 1 end,
  Undo_EndBlock = function() open_blocks = open_blocks - 1 end,
  UpdateArrange = function() end,
}

local function track_from_osc(n) return reaper.GetTrack(0, (n or 1) - 1) end
local function sorted_items(tr)
  local items = {}
  for _, it in ipairs(tr.items) do items[#items + 1] = it end
  table.sort(items, function(a, b) return a.D_POSITION < b.D_POSITION end)
  return items
end
local function item_at(args)
  local tr = track_from_osc(args[1])
  if not tr then return nil end
  return sorted_items(tr)[math.floor(args[2] or -1) + 1]
end
local function unselect_all()
  for _, it in ipairs(selected()) do it.selected = false end
end
local function edited()
  reaper.Undo_EndBlock('edited', 4)
  return {ok = true}
end
local handlers = {}
assert(load('local handlers, item_at, unselect_all, edited, track_from_osc = ...\n' .. text:sub(from, to - 1)))(
  handlers, item_at, unselect_all, edited, track_from_osc)

local function round_trip()
  fresh(4)
  add(1, 0, 4)
  add(2, 2, 4)
  local before = #all_items()
  local copied = handlers.CopyToClipboard({9, 2, 1, 0, 0, 4, 2, 0, 2, 4})
  check('a copy holds both', copied.ok and copied.copied == 2)
  check('and changes nothing, with no undo block', #all_items() == before and blocks == 0)
  local pasted = handlers.PasteClipboard({9, 2, 3, 10, 4, 12})
  check('a paste lands them where the host planned', pasted.ok and #tracks[3].items == 1 and #tracks[4].items == 1
    and tracks[3].items[1].D_POSITION == 10 and tracks[4].items[1].D_POSITION == 12)
  check('in one undo block', blocks == 1 and open_blocks == 0)
  check('as the clips they were, by their chunks', tracks[3].items[1].sound == 'sound1' and tracks[4].items[1].sound == 'sound2')
  check('with their GUIDs taken out', not tracks[3].items[1].chunk:find('GUID', 1, true))
  check('and only they are selected', #selected() == 2 and tracks[3].items[1].selected and tracks[4].items[1].selected)
  check('a slot of another player is its own', handlers.PasteClipboard({8, 2, 3, 10, 4, 12}).error == 'no clipboard')
  check('a count that is not the slot\'s is refused', handlers.PasteClipboard({9, 1, 3, 10}).ok == false)
  local items = #all_items()
  check('a missing track refuses it all', handlers.PasteClipboard({9, 2, 3, 20, 9, 20}).ok == false and #all_items() == items)
  handlers.ForgetClipboard({9})
  check('a forgotten slot says so', handlers.PasteClipboard({9, 2, 3, 10, 4, 12}).error == 'no clipboard')

  fresh(1)
  add(1, 0, 4)
  add(1, 4, 4)
  blocks = 0
  local dup = handlers.DuplicateItems({2, 1, 0, 0, 4, 0, 1, 1, 4, 4, 0})
  local at = sorted_items(tracks[1])
  check('a phrase of 0-4 and 4-8 repeats whole at 8-12 and 12-16', dup.ok and #at == 4 and at[3].D_POSITION == 8
    and at[4].D_POSITION == 12 and at[3].sound == 'sound1' and at[4].sound == 'sound2')
  check('the copies are the selection, in one block', #selected() == 2 and at[3].selected and at[4].selected and blocks == 1)
  check('an unlooped copy stays at its place in the file', at[3].take.D_STARTOFFS == 0)
  fresh(1)
  add(1, 0, 4)
  handlers.DuplicateItems({1, 1, 0, 0, 4, 1})
  check('a looped one goes on by the span', sorted_items(tracks[1])[2].take.D_STARTOFFS == 4)
end

local function targets()
  fresh(2)
  local a = add(1, 0, 4)
  local b = add(1, 8, 4)
  local c = add(2, 0, 4)
  -- Reaper's selection is somewhere else altogether.
  c.selected = true
  local gone = handlers.DeleteItems({1, 1, 1, 8, 4})
  check('a delete takes its target and not the selection', gone.ok and gone.deleted == 1 and #tracks[1].items == 1
    and tracks[1].items[1] == a and #tracks[2].items == 1)
  b = add(1, 8, 4)
  local moved = handlers.DeleteItems({2, 1, 0, 0, 4, 1, 1, 8.5, 4})
  check('one target not where it was refuses them all', moved.ok == false and #tracks[1].items == 2)
  check('with no undo block', open_blocks == 0)
  check('a copy of a moved one too', handlers.CopyToClipboard({1, 1, 1, 1, 9, 4}).ok == false)
  check('a duplicate of a moved one too', handlers.DuplicateItems({1, 1, 1, 9, 4, 0}).ok == false and #tracks[1].items == 2)
  check('half a millisecond off is the same item', handlers.CopyToClipboard({1, 1, 1, 1, 8.0004, 4}).ok == true)
  check('the same item named twice is refused', handlers.DeleteItems({2, 1, 0, 0, 4, 1, 0, 0, 4}).ok == false
    and #tracks[1].items == 2)
  b.C_LOCK = 1
  local kept = handlers.DeleteItems({1, 1, 1, 8, 4})
  check('a locked one stays and is counted', kept.ok and kept.deleted == 0 and kept.locked == 1 and #tracks[1].items == 2)
  check('and Reaper\'s selection was never touched by a delete', c.selected)
end

local part = arg[1] or 'all'
if part == 'round_trip' or part == 'all' then round_trip() end
if part == 'targets' or part == 'all' then targets() end
print(string.format('%d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
