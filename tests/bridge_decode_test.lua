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

-- The stage table's rope (docs/spatial_loop.md slice 20): CreateSidechain sends into channels 3/4,
-- gives a track with no ReaComp one and sets every ReaComp's detector to the auxiliary input, by
-- the parameter's own words; removing the last key into it sets them back to the main input, and
-- a ReaComp that was there before is kept.
local fxs, sends, nchan = {kick = {}, bass = {}}, {}, {}
local function of(tr, cat)
  local out = {}
  for _, s in ipairs(sends) do
    if (cat == 0 and s.src == tr) or (cat == -1 and s.dst == tr) then out[#out + 1] = s end
  end
  return out
end
reaper = {
  GetTrack = function(_, n) return ({[1] = 'kick', [5] = 'bass'})[n] end,
  GetMediaTrackInfo_Value = function(tr) return nchan[tr] or 2 end,
  SetMediaTrackInfo_Value = function(tr, _, v) nchan[tr] = v end,
  CreateTrackSend = function(src, dst) sends[#sends + 1] = {src = src, dst = dst, chan = 0}; return #of(src, 0) - 1 end,
  SetTrackSendInfo_Value = function(tr, cat, i, _, v) of(tr, cat)[i + 1].chan = v end,
  GetTrackSendInfo_Value = function(tr, cat, i, key)
    local s = of(tr, cat)[i + 1]
    return key == 'I_DSTCHAN' and s.chan or s.dst
  end,
  GetTrackNumSends = function(tr, cat) return #of(tr, cat) end,
  RemoveTrackSend = function(tr, cat, i)
    local s = of(tr, cat)[i + 1]
    for k, v in ipairs(sends) do if v == s then table.remove(sends, k); return true end end
    return false
  end,
  TrackFX_GetCount = function(tr) return #fxs[tr] end,
  TrackFX_GetFXName = function(tr, fx) return true, fxs[tr][fx + 1].name end,
  TrackFX_AddByName = function(tr, name)
    fxs[tr][#fxs[tr] + 1] = {name = 'VST: ' .. name .. ' (Cockos)', detector = 0}
    return #fxs[tr] - 1
  end,
  TrackFX_GetNumParams = function() return 3 end,
  TrackFX_GetParamName = function(_, _, p) return true, ({'Thresh', 'Ratio', 'Detector input'})[p + 1] end,
  TrackFX_FormatParamValueNormalized = function(_, _, _, v)
    return true, v >= 0.25 and 'Auxiliary Input L+R' or 'Main Input L+R'
  end,
  TrackFX_SetParamNormalized = function(tr, fx, p, v) if p == 2 then fxs[tr][fx + 1].detector = v end end,
  UpdateArrange = function() end,
  Undo_BeginBlock = function() end,
  Undo_EndBlock = function() end,
}
local routing = assert(load('local handlers, track_from_osc = ...\n'
  .. lift('-- The ReaComps in a track', '-- args: track, fx, to track, to fx') .. '\nreturn handlers'))(
  {}, function(n) return reaper.GetTrack(0, (n or 1) - 1) end)
local tied = routing.CreateSidechain({2, 6})
check('a sidechain into a track with no compressor gives it a ReaComp listening to its aux input',
  tied.ok and tied.compressor_added == true and #fxs.bass == 1 and fxs.bass[1].detector >= 0.25
  and sends[1].chan == 2 and nchan.bass == 4)
routing.RemoveTrackSend({2, 0})
check('cut, the ReaComp stays and listens to its own input again', #sends == 0 and #fxs.bass == 1
  and fxs.bass[1].detector == 0)
local again = routing.CreateSidechain({2, 6})
check('tied again, the ReaComp there is the one that listens, and none is added',
  again.ok and again.compressor_added == false and #fxs.bass == 1 and fxs.bass[1].detector >= 0.25)
routing.CreateTrackSend({2, 6})
routing.RemoveTrackSend({2, 1})
check('an ordinary send removed leaves the key listened to', fxs.bass[1].detector >= 0.25 and #sends == 1)

-- Automation by gesture (docs/spatial_loop.md part two slice 22): HoldLane switches an envelope off
-- while a write bead is out over its control and back at the let-go, as it was; the poll still reads
-- a held lane; a pass written by SetEnvelope while held stays off, and plays at the let-go.
local envs = {kick = {ACTIVE = '1', VISIBLE = '1', points = 3}}
reaper = {
  GetTrack = function(_, n) return n == 1 and 'kick' or nil end,
  GetMasterTrack = function() return 'master' end,
  GetSetEnvelopeInfo_String = function(env, key, v, set)
    if set then env[key] = v end
    return true, env[key]
  end,
  CountEnvelopePoints = function(env) return env.points or 0 end,
  DeleteEnvelopePointEx = function(env) env.points = math.max((env.points or 0) - 1, 0) end,
  InsertEnvelopePoint = function(env) env.points = (env.points or 0) + 1 end,
  Envelope_SortPoints = function() end,
  GetMediaTrackInfo_Value = function() return 1 end,
  SetMediaTrackInfo_Value = function() end,
  TrackList_AdjustWindows = function() end,
  UpdateArrange = function() end,
  Undo_BeginBlock = function() end,
  Undo_EndBlock = function() end,
}
local hold_handlers, is_held = assert(load('local handlers, track_from_osc, envelope_of, set_active, env_write = ...\n'
  .. lift('local function is_active', 'local function set_active')
  .. lift('-- Lanes a write bead holds', 'local function env_points')
  .. lift('-- args: track (0 the master), target, then flat', "-- args: track (0 the master), target, on")
  .. lift("-- args: track (0 the master), target, on", "-- args: track, mode (Reaper's I_AUTOMODE")
  .. '\nreturn handlers, is_held'))(
  {}, function(n) return reaper.GetTrack(0, (n or 1) - 1) end,
  function(tr, target) return target == 'volume' and envs[tr] or nil end,
  function(env, on) env.ACTIVE = on and '1' or '0'; env.VISIBLE = on and '1' or '0' end,
  function(_, _, _, v) return v end)
local _, hfn, h = decode_request('{"args":[2,"volume",1],"fn":"HoldLane","id":12}')
check('HoldLane decodes with its track, target and on', hfn == 'HoldLane' and h[1] == 2 and h[2] == 'volume' and h[3] == 1)
local held = hold_handlers.HoldLane(h)
check('held, the envelope stops playing and stays in view', held.ok and held.held and envs.kick.ACTIVE == '0'
  and envs.kick.VISIBLE == '1')
check('and the poll still reads it', is_held(envs.kick))
hold_handlers.SetEnvelope({2, 'volume', 1.0, -6.0, 1, 2.0, -3.0, 1})
check('a pass written while held is kept from playing', envs.kick.ACTIVE == '0' and envs.kick.points == 2)
hold_handlers.HoldLane({2, 'volume', false})
check('let go, it plays again', envs.kick.ACTIVE == '1' and not is_held(envs.kick))
envs.kick.ACTIVE = '0'
hold_handlers.HoldLane({2, 'volume', true})
hold_handlers.HoldLane({2, 'volume', 0})
check('a lane that was not playing is left not playing', envs.kick.ACTIVE == '0')
check('a lane with no envelope holds nothing, and no track is refused', hold_handlers.HoldLane({2, 'pan', 1}).held == false
  and hold_handlers.HoldLane({9, 'volume', 1}).ok == false)
-- A cassette onto a track (docs/spatial_loop.md part two, slice 24): PasteItem decodes as any call,
-- and makes a MIDI item with its notes and controls at the start asked, or an audio item of its
-- file with its offset, fades, shapes, gain and loop, inside one Undo block called "Paste item".
local _, pfn, p = decode_request([[{"args":[4,96.0,8.0,"Kick Verse 1",0,"",0,0.5,1.0,1,4,-3.0,0,0,0,1,96.25,96.75,36,100,9,1,96.5,1,64,0],"fn":"PasteItem","id":12}]])
check('PasteItem decodes with its track, start, length and name', pfn == 'PasteItem' and p[1] == 4 and p[2] == 96.0
  and p[3] == 8.0 and p[4] == 'Kick Verse 1' and p[6] == '' and p[16] == 1 and p[22] == 1)
local made, values, notes, ccs2, opened, closed = {}, {}, {}, {}, 0, {}
reaper = {
  Undo_BeginBlock = function() opened = opened + 1 end,
  Undo_EndBlock = function(name) closed[#closed + 1] = name end,
  CreateNewMIDIItemInProj = function(_, t0, t1) made[#made + 1] = {'midi', t0, t1}; return 'item' end,
  AddMediaItemToTrack = function() made[#made + 1] = {'audio'}; return 'item' end,
  AddTakeToMediaItem = function() return 'take' end,
  GetActiveTake = function() return 'take' end,
  PCM_Source_CreateFromFile = function(path) return 'src:' .. path end,
  SetMediaItemTake_Source = function(_, src) values.source = src end,
  SetMediaItemTakeInfo_Value = function(_, key, v) values[key] = v end,
  SetMediaItemInfo_Value = function(_, key, v) values[key] = v end,
  GetSetMediaItemTakeInfo_String = function(_, key, v) values[key] = v end,
  MIDI_GetPPQPosFromProjTime = function(_, t) return t * 960 end,
  MIDI_InsertNote = function(_, sel, muted, on, off, chan, pitch, vel) notes[#notes + 1] = {on, off, chan, pitch, vel}; return true end,
  MIDI_InsertCC = function(_, sel, muted, ppq, msg, chan, a, b) ccs2[#ccs2 + 1] = {ppq, msg, chan, a, b}; return true end,
  MIDI_Sort = function() end,
  UpdateItemInProject = function() end,
  file_exists = function(path) return path == '/takes/kick.wav' end,
  EnumProjects = function() return 0, '' end,
  Main_OnCommand = function() end,
  CountSelectedMediaItems = function() return 0 end,
}
local REAPER_SHAPE_T = {[0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 5}
local paste = assert(load('local handlers, track_from_osc, edited, copy_file, unselect_all, REAPER_SHAPE = ...\n'
  .. lift('function handlers.PasteItem', '-- args: track (1-based, as OSC), fx (1-based), param (1-based).')
  .. '\nreturn handlers.PasteItem'))(
  {}, function(n) return n == 4 and 'track' or nil end,
  function(label) reaper.Undo_EndBlock(label); return {ok = true} end, function() return true end, function() end,
  REAPER_SHAPE_T)
local midi = paste(p)
check('a MIDI cassette is a MIDI item from its start for its length', midi.ok and #made == 1 and made[1][1] == 'midi'
  and made[1][2] == 96.0 and made[1][3] == 104.0)
check('with its name, its fades, their shapes and its gain', values.P_NAME == 'Kick Verse 1' and values.D_FADEINLEN == 0.5
  and values.D_FADEOUTLEN == 1.0 and values.C_FADEINSHAPE == 1 and values.C_FADEOUTSHAPE == 5
  and math.abs(values.D_VOL - 10 ^ (-3 / 20)) < 1e-9 and values.B_LOOPSRC == 0 and values.B_MUTE == 0)
check('its note at its project time, on its channel', midi.notes == 1 and #notes == 1 and notes[1][1] == 96.25 * 960
  and notes[1][2] == 96.75 * 960 and notes[1][3] == 9 and notes[1][4] == 36 and notes[1][5] == 100)
check('its mod wheel as 0xB0', midi.controls == 1 and ccs2[1][2] == 0xB0 and ccs2[1][4] == 1 and ccs2[1][5] == 64)
check('in one Undo block, called Paste item', opened == 1 and #closed == 1 and closed[1] == 'Paste item')
made, values, opened, closed = {}, {}, 0, {}
local audio = paste({4, 30.0, 6.0, 'Kick take', 1, '/takes/kick.wav', 1.5, 0, 0, 0, 0, 0, 0.5, 4.5, 0, 0, 0})
check('an audio cassette is its file at the start asked, from its offset, looped, muted', audio.ok and made[1][1] == 'audio'
  and values.source == 'src:/takes/kick.wav' and values.D_STARTOFFS == 1.5 and values.D_POSITION == 30.0
  and values.D_LENGTH == 6.0 and values.B_LOOPSRC == 1 and values.B_MUTE == 1 and opened == 1)
made = {}
check('a file this machine does not have is refused, and nothing made', paste({4, 30.0, 6.0, 'x', 0, '/takes/gone.wav'}).ok == false
  and #made == 0)
check('no such track is refused', paste({9, 30.0, 6.0, 'x', 0, ''}).ok == false)
check('nor an empty item', paste({4, 30.0, 0, 'x', 0, ''}).ok == false)

-- Sections rearranged (docs/spatial_loop.md part two, slice 29): ArrangeSections decodes as any
-- call; an item across a moving edge is split there and each part goes with its section; markers
-- and regions move by their numbers; an envelope plays each section as it did; the tempo map is set
-- inside the same Undo block, and the master's "Tempo map" envelope is left to it; a bracket that
-- keeps a section's harmony renames the marker where it lands, or is a new one; a locked item in
-- the way refuses the lot, with nothing changed.
local _, afn, a2 = decode_request([[{"args":[2,10.0,20.0,0.0,0.0,10.0,10.0,1,0.0,120.0,0,0,2,0.0,"B [C major]",20.0,"[A minor]"],"fn":"ArrangeSections","id":13}]])
check('ArrangeSections decodes with its pieces, its tempo map and its brackets', afn == 'ArrangeSections' and a2[1] == 2
  and a2[2] == 10.0 and a2[4] == 0.0 and a2[8] == 1 and a2[10] == 120.0 and a2[12] == 0 and a2[13] == 2
  and a2[15] == 'B [C major]' and a2[16] == 20.0)
local items, marks, envs, set_marks, added_marks, blocks2, ended2, tempo_set = {}, {}, {}, {}, {}, 0, {}, nil
local function new_item(pos, len, lock) items[#items + 1] = {D_POSITION = pos, D_LENGTH = len, C_LOCK = lock or 0}; return items[#items] end
local env = {name = 'Volume', points = {{0, 1.0, 0}, {20, 0.0, 1}}}
local tempo_env = {name = 'Tempo map', points = {{0, 120.0, 1}, {15, 90.0, 1}}}
local function env_value(t)
  local pts = env.points
  if t <= pts[1][1] then return pts[1][2] end
  for i = #pts, 1, -1 do
    if pts[i][1] <= t then
      local nxt = pts[i + 1]
      if not nxt or pts[i][3] == 1 then return pts[i][2] end
      return pts[i][2] + (nxt[2] - pts[i][2]) * (t - pts[i][1]) / (nxt[1] - pts[i][1])
    end
  end
end
reaper = {
  Undo_BeginBlock = function() blocks2 = blocks2 + 1 end,
  Undo_EndBlock = function(name) ended2[#ended2 + 1] = name end,
  CountTracks = function() return 1 end,
  GetTrack = function() return 'track' end,
  GetMasterTrack = function() return 'master' end,
  CountTrackMediaItems = function() return #items end,
  GetTrackMediaItem = function(_, i) return items[i + 1] end,
  GetMediaItemInfo_Value = function(it, key) return it[key] end,
  SetMediaItemPosition = function(it, pos) it.D_POSITION = pos; return true end,
  SplitMediaItem = function(it, at)
    local right = new_item(at, it.D_POSITION + it.D_LENGTH - at)
    it.D_LENGTH = at - it.D_POSITION
    return right
  end,
  CountProjectMarkers = function()
    local regions = 0
    for _, mk in ipairs(marks) do if mk.region then regions = regions + 1 end end
    return #marks, #marks - regions, regions
  end,
  EnumProjectMarkers3 = function(_, m)
    local mk = marks[m + 1]
    return 1, mk.region, mk.pos, mk.stop, mk.name, mk.number, 0
  end,
  SetProjectMarker4 = function(_, number, region, pos, stop, name)
    set_marks[#set_marks + 1] = {number = number, region = region, pos = pos, stop = stop, name = name}
    return true
  end,
  AddProjectMarker2 = function(_, region, pos, stop, name)
    added_marks[#added_marks + 1] = {region = region, pos = pos, name = name}
    return #marks + #added_marks
  end,
  CountTrackEnvelopes = function() return 1 end,
  GetTrackEnvelope = function(tr) return tr == 'master' and tempo_env or env end,
  GetEnvelopeName = function(e) return true, e.name end,
  CountEnvelopePoints = function(e) return #e.points end,
  GetEnvelopePoint = function(e, p) local pt = e.points[p + 1]; return true, pt[1], pt[2], pt[3], 0, false end,
  Envelope_Evaluate = function(_, t) return 1, env_value(t) end,
  DeleteEnvelopePointRange = function(e) e.points = {} end,
  InsertEnvelopePoint = function(e, t, v, shape) e.points[#e.points + 1] = {t, v, shape} end,
  Envelope_SortPoints = function(e) table.sort(e.points, function(x, y) return x[1] < y[1] end) end,
  UpdateArrange = function() end,
  UpdateTimeline = function() end,
}
local arrange = assert(load('local handlers = ...\n'
  .. lift('-- Sections rearranged (docs/spatial_loop.md part two, slice 29), planned', '-- args: where (from 1), name. A new track there')
  .. '\nreturn handlers.ArrangeSections'))({SetTempoMap = function(args) reaper.Undo_BeginBlock(); tempo_set = args; reaper.Undo_EndBlock('Tempo map'); return {ok = true} end})
local crossing = new_item(5, 10)
local early = new_item(2, 2)
local after = new_item(25, 5)
marks = {{region = true, pos = 0, stop = 10, name = 'A', number = 1}, {region = true, pos = 10, stop = 20, name = 'B', number = 2},
  {region = false, pos = 12, stop = 0, name = 'Hook [A minor]', number = 3}, {region = false, pos = 10, stop = 0, name = 'B', number = 4}}
local done = arrange(a2)
check('BA: done, as one Undo block called Arrange sections', done.ok and blocks2 == 1 and #ended2 == 1 and ended2[1] == 'Arrange sections')
check('an item across the edge is cut there, each part with its section', crossing.D_POSITION == 15 and crossing.D_LENGTH == 5
  and #items == 4 and items[4].D_POSITION == 0 and items[4].D_LENGTH == 5)
check('an item inside a section goes with it, and one past them stays', early.D_POSITION == 12 and after.D_POSITION == 25)
local by_number = {}
for _, m in ipairs(set_marks) do by_number[m.number] = m end
check('the regions and the marker in them move by their numbers', by_number[1] and by_number[1].pos == 10 and by_number[1].stop == 20
  and by_number[2] and by_number[2].pos == 0 and by_number[2].stop == 10 and by_number[3] and by_number[3].pos == 2
  and not by_number[3].region)
local sounds = true
for k = 0, 19 do
  local t = 0.0 + k * 0.49
  local was = 1.0 - t / 20
  local now_at = t < 10 and t + 10 or t - 10
  local _, now = reaper.Envelope_Evaluate(env, now_at)
  if math.abs(was - now) > 0.001 then sounds = false end
end
check('the envelope plays each section as it did, where it now is', sounds and #env.points == 5)
check('and the tempo map is set inside the same block', tempo_set and #tempo_set == 3 and tempo_set[2] == 120.0)
check('the master\'s Tempo map envelope is left to it, not put back as it was', #tempo_env.points == 2
  and tempo_env.points[2][1] == 15 and tempo_env.points[2][2] == 90.0 and done.envelopes == 1)
check('a bracket renames the marker where it lands, by its number', by_number[4] and by_number[4].pos == 0
  and by_number[4].name == 'B [C major]' and not by_number[4].region)
check('and one where no marker is is a new marker', #added_marks == 1 and added_marks[1].pos == 20.0
  and added_marks[1].name == '[A minor]' and not added_marks[1].region)
items, set_marks, added_marks, blocks2, tempo_set = {}, {}, {}, 0, nil
local locked = new_item(12, 2, 1)
local refused = arrange({2, 10.0, 20.0, 0.0, 0.0, 10.0, 10.0, 0, 0})
check('a locked item in the way refuses the lot, with nothing changed', refused.ok == false and blocks2 == 0
  and locked.D_POSITION == 12 and #set_marks == 0)

print(string.format('[bridge] %d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
