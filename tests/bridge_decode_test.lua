-- The bridge's request decoder, run outside Reaper: tools/verify.sh runs this when a Lua is
-- installed. The decoder is lifted out of reaper/dawlings_bridge.lua by its text, because the
-- bridge itself talks to Reaper the moment it loads.
local here = arg[0]:match('(.*/)') or './'
local f = assert(io.open(here .. '../reaper/dawlings_bridge.lua', 'r'))
local text = f:read('*a')
f:close()
local from = text:find('local function decode_args', 1, true)
local to = text:find('-- Reaper indexes tracks from 0', 1, true)
local chunk = text:sub(from, to - 1) .. '\nreturn decode_request, decode_batch, run_batch'
local decode_request, decode_batch, run_batch = assert(load(chunk))()

local failures, checks = 0, 0
local function check(label, ok)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print('FAIL  bridge: ' .. label)
  end
end

local id, fn, a = decode_request([[{"args":[3,1.5e-1,"C:\\Takes\\a, \"b\"]1.wav","Zo\u00eb",true,false,null,-2],"fn":"InsertAudioTake","id":7}]])
check('the id and the function', id == 7 and fn == 'InsertAudioTake')
check('numbers, in any form JSON writes them', a[1] == 3 and a[2] == 0.15 and a[8] == -2)
check('a path with a comma, quotes, a bracket and backslashes', a[3] == 'C:\\Takes\\a, "b"]1.wav')
check('a name outside ASCII', a[4] == 'Zoë')
check('true and false as themselves', a[5] == true and a[6] == false)
check('a null keeps its place', a[7] == nil and a[8] == -2)
local _, _, none = decode_request('{"args":[],"fn":"GetTimeline","id":1}')
check('no arguments', #none == 0)

-- A Batch: one gesture's edits, decoded call by call, and run inside one Undo block however many
-- blocks the handlers open of their own. The request is what ReaperBackend.batch_request writes.
local _, bfn, b = decode_request([[{"args":["Kick: place","SetItemGain",3,2,0,-3.5,"RenameItem",3,2,0,"a, \"b\"","AddMarker",0,"SetTrackValue",2,1,null],"fn":"Batch","id":9}]])
local label, calls = decode_batch(b)
check('a batch is a batch, with its name', bfn == 'Batch' and label == 'Kick: place')
check('its calls, by count', #calls >= 3 and calls[1].fn == 'SetItemGain' and calls[2].fn == 'RenameItem'
  and calls[3].fn == 'AddMarker')
check('each with its own arguments', calls[1].args[3] == -3.5 and calls[2].args[3] == 'a, "b"' and #calls[3].args == 0)
local depth, blocks, ended, ran = 0, 0, {}, {}
reaper = {
  Undo_BeginBlock = function() depth = depth + 1; blocks = blocks + 1 end,
  Undo_EndBlock = function(name, flags) depth = depth - 1; ended[#ended + 1] = name end,
}
local fake = {}
for _, name in ipairs({'SetItemGain', 'RenameItem', 'AddMarker'}) do
  fake[name] = function(args)
    reaper.Undo_BeginBlock()
    ran[#ran + 1] = name
    reaper.Undo_EndBlock('dawlings: ' .. name, -1)
    if name == 'RenameItem' then error('no such item') end
    return {ok = true}
  end
end
local result = run_batch(fake, label, {calls[1], calls[2], calls[3], {fn = 'Batch', args = {}}})
check('every call ran, in order', #ran == 3 and ran[1] == 'SetItemGain' and ran[3] == 'AddMarker')
check('inside one Undo block, named for the gesture', blocks == 1 and depth == 0 and #ended == 1
  and ended[1] == 'dawlings: Kick: place')
check('a call that fails says so and the rest still run', result.ok and result.results[2].ok == false
  and result.results[3].ok == true)
check('a batch inside a batch is refused', result.results[4].ok == false)
check('and the blocks are Reaper\'s own again afterwards', (function()
  reaper.Undo_BeginBlock(); reaper.Undo_EndBlock('after', -1); return blocks == 2 end)())
local _, empty = decode_batch({'nothing'})
check('a batch of nothing is no calls', #empty == 0)

-- A take's controls (docs/spatial_loop.md slice 14): InsertMidiTake writes each with
-- MIDI_InsertCC, the wheel as 0xE0 with its fourteen bits split low then high, 1 and 11 as 0xB0;
-- and the timeline reads them back the same way. Both are lifted out by their text, as above.
local function lift(first, last)
  local a = text:find(first, 1, true)
  local b = text:find(last, a, true)
  return text:sub(a, b - 1)
end
local inserted, ccs = {}, {}
reaper = {
  Undo_BeginBlock = function() end,
  CreateNewMIDIItemInProj = function() return 'item' end,
  GetActiveTake = function() return 'take' end,
  GetSetMediaItemTakeInfo_String = function() end,
  MIDI_GetPPQPosFromProjTime = function(_, t) return t * 960 end,
  MIDI_GetProjTimeFromPPQPos = function(_, ppq) return ppq / 960 end,
  MIDI_InsertNote = function() inserted[#inserted + 1] = 'note'; return true end,
  MIDI_InsertCC = function(_, sel, muted, ppq, msg, chan, a, b)
    ccs[#ccs + 1] = {ppq, msg, chan, a, b}
    return true
  end,
  MIDI_Sort = function() end,
  UpdateItemInProject = function() end,
  TakeIsMIDI = function() return true end,
  GetMediaItemInfo_Value = function() return 10 end,
  MIDI_CountEvts = function() return true, 0, 3, 0 end,
  MIDI_GetCC = function(_, n)
    local rows = {{true, false, false, 10.5 * 960, 0xE0, 0, 0, 0}, {true, false, false, 11 * 960, 0xB0, 2, 1, 64},
      {true, false, true, 11 * 960, 0xE0, 0, 0, 64}}
    return table.unpack(rows[n + 1])
  end,
}
local insert = assert(load('local handlers, track_from_osc, edited = ...\n'
  .. lift('function handlers.InsertMidiTake', '-- A copy of a file') .. '\nreturn handlers.InsertMidiTake'))(
  {}, function() return 'track' end, function() return {ok = true} end)
local took = insert({3, 10.0, 12.0, 'Grace take 1', 1, 10.25, 10.75, 60, 100, 0,
  3, 10.5, 128, -8192, 0, 10.6, 128, 8191, 0, 11.0, 1, 64, 2})
check('a take with controls places its note and every control', took.ok and took.notes == 1 and took.controls == 3
  and #ccs == 3)
check('the wheel at its bottom is 0xE0 with both halves 0', ccs[1][2] == 0xE0 and ccs[1][4] == 0 and ccs[1][5] == 0
  and ccs[1][1] == 10.5 * 960)
check('at its top both halves 127', ccs[2][2] == 0xE0 and ccs[2][4] == 127 and ccs[2][5] == 127)
check('the mod wheel is 0xB0, its number and its value, on its channel', ccs[3][2] == 0xB0 and ccs[3][4] == 1
  and ccs[3][5] == 64 and ccs[3][3] == 2)
ccs = {}
local old = insert({3, 10.0, 12.0, 'old', 1, 10.25, 10.75, 60, 100, 0})
check('a request from before controls still places its notes', old.ok and old.notes == 1 and old.controls == 0 and #ccs == 0)
local read = assert(load(lift('local CONTROLS_PER_ITEM', '-- --- automation') .. '\nreturn item_controls'))()
local back = read('item', 'take')
check('the timeline reads a take\'s controls back from its start, the wheel centred on 0, a muted one left out',
  back and #back == 8 and back[1] == 0.5 and back[2] == 128 and back[3] == -8192 and back[5] == 1.0 and back[6] == 1
  and back[7] == 64 and back[8] == 2)

-- The stage table's ring (docs/spatial_loop.md slice 18): SetTrackWidth decodes as any call, puts a
-- track whose pan mode ignores D_WIDTH in stereo pan (5) first, inside its one Undo block, and says
-- so; and a width is read back only in the pan modes that have one.
local _, wfn, w = decode_request('{"args":[3,0.6],"fn":"SetTrackWidth","id":11}')
check('SetTrackWidth decodes with its track and width', wfn == 'SetTrackWidth' and w[1] == 3 and w[2] == 0.6)
local values, blocks_opened, blocks_closed = {I_PANMODE = 3, D_WIDTH = 1}, 0, {}
reaper = {
  GetTrack = function(_, n) return n == 2 and 'track' or nil end,
  GetMediaTrackInfo_Value = function(_, key) return values[key] end,
  SetMediaTrackInfo_Value = function(_, key, v) values[key] = v end,
  Undo_BeginBlock = function() blocks_opened = blocks_opened + 1 end,
  Undo_EndBlock = function(name) blocks_closed[#blocks_closed + 1] = name end,
}
local widen = assert(load('local handlers, track_from_osc, STEREO_PAN = ...\n'
  .. lift('function handlers.SetTrackWidth', '-- --- editing') .. '\nreturn handlers.SetTrackWidth'))(
  {}, function(n) return reaper.GetTrack(0, (n or 1) - 1) end, 5)
local set = widen(w)
check('a track in stereo balance is put in stereo pan, then given its width, and the answer says so',
  set.ok and set.mode_set == true and values.I_PANMODE == 5 and values.D_WIDTH == 0.6)
check('in one Undo block of its own', blocks_opened == 1 and #blocks_closed == 1)
local again = widen({3, 1.7})
check('already in stereo pan it is not set again, and the width is held to 0..1',
  again.ok and again.mode_set == false and values.D_WIDTH == 1)
check('no such track is refused', widen({9, 0.5}).ok == false)
local read_width = assert(load('local STEREO_PAN = 5\n'
  .. lift('local function track_width', '--- The whole project shape') .. '\nreturn track_width'))()
values = {I_PANMODE = 6, D_WIDTH = 0.25}
check('a width is read in dual pan', read_width('track') == 0.25)
values = {I_PANMODE = 3, D_WIDTH = 0.25}
check('and is full in a pan mode that ignores it', read_width('track') == 1)
print(string.format('[bridge] %d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
