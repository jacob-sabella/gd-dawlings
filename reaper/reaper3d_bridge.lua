-- reaper-3d bridge: the structural half of the link.
--
-- WHAT THIS IS FOR. reaper-3d talks to Reaper over OSC for everything that moves -- faders,
-- pan, mute, solo, meters, transport, FX parameters. OSC covers none of the things that are
-- STRUCTURAL: it has no message that says how many tracks exist, what plugin is in slot 2, what
-- colour a track is, or "create a send from track 6 to track 12". Those only exist in ReaScript.
-- So this script runs inside Reaper and answers questions that OSC cannot.
--
-- WHY FILES. ReaScript's Lua has no sockets. A file dropbox polled on a deferred timer is the
-- pattern the author's existing mcp_bridge.lua already uses daily on this machine, so this
-- follows it rather than inventing something. Latency is a deferred tick, around 30ms, which is
-- fine for structure and useless for meters -- which is exactly why meters go over OSC instead.
--
-- INSTALL
--   1. Copy this file to <Reaper resource path>/Scripts/reaper3d_bridge.lua
--      (Options > Show REAPER resource path in explorer/finder)
--   2. Actions > Show action list > ReaScript: Load... > pick this file
--   3. Run it once. It stays running and re-arms itself; the console in Reaper says so.
--      To have it start with Reaper, add a dofile() line to Scripts/__startup.lua.
--
-- PROTOCOL. reaper-3d writes request_<id>.json into the data directory below; this reads it,
-- deletes it, and writes response_<id>.json beside it. One call per file, no ordering guarantee
-- between ids. See core/reaper/script_bridge.gd for the client half.

local bridge_dir = reaper.GetResourcePath() .. '/Scripts/reaper3d_bridge_data/'

local function ensure_dir()
  reaper.RecursiveCreateDirectory(bridge_dir, 0)
end

-- Minimal JSON encoder. Backslash is escaped FIRST; escaping it after introducing \" and \n
-- would double every escape this function just added, which corrupts any track name containing
-- a path or a quote and does so silently.
local function esc(s)
  return (s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'))
end

local function encode(v)
  local t = type(v)
  if v == nil then return 'null'
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then
    -- %.17g rather than tostring(): Lua's default drops precision on parameter values, and a
    -- normalised FX parameter that round-trips to a different number makes a knob drift every
    -- time the rack is rebuilt.
    if v ~= v or v == math.huge or v == -math.huge then return 'null' end
    return string.format('%.17g', v)
  elseif t == 'string' then return '"' .. esc(v) .. '"'
  elseif t == 'table' then
    local parts = {}
    if #v > 0 then
      for _, item in ipairs(v) do parts[#parts + 1] = encode(item) end
      return '[' .. table.concat(parts, ',') .. ']'
    end
    for k, item in pairs(v) do
      parts[#parts + 1] = '"' .. esc(tostring(k)) .. '":' .. encode(item)
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'null'
end

-- Scalar-only decoder, which is all the protocol needs: every request is
-- {"id":N,"fn":"Name","args":[...]} with numbers and strings in args. A general JSON parser here
-- would be a hundred lines guarding against input this script writes the other half of.
local function decode_request(text)
  local id = tonumber(text:match('"id"%s*:%s*(%-?%d+)'))
  local fn = text:match('"fn"%s*:%s*"([^"]*)"')
  local args = {}
  local args_body = text:match('"args"%s*:%s*%[(.-)%]')
  if args_body then
    for raw in args_body:gmatch('[^,]+') do
      -- Lua 5.4 makes the loop variable const, so the trim has to land in a new local.
      local token = raw:match('^%s*(.-)%s*$')
      local str = token:match('^"(.*)"$')
      if str then args[#args + 1] = str
      else args[#args + 1] = tonumber(token) end
    end
  end
  return id, fn, args
end

-- Reaper indexes tracks from 0 and OSC addresses them from 1. Everything crossing this boundary
-- goes through these two, because an off-by-one here moves the wrong fader -- which looks like a
-- working bridge until the moment it matters.
local function track_from_osc(n)
  return reaper.GetTrack(0, (n or 1) - 1)
end

local handlers = {}

--- The whole project shape in one call: what reaper-3d builds its racks and patchbay from.
--
-- args[1] == 1 asks for the LIGHT answer: every plugin's name and bypass, but none of its
-- parameter values. That exists because reaper-3d polls this on a slow clock for the three
-- things OSC genuinely cannot say -- track colour, folder depth, and a send's destination as an
-- INDEX -- all of which are one cheap property read each. The parameter sweep is the expensive
-- part of this handler by a wide margin (32 reads per plugin per track), and OSC already
-- streams those values continuously, so re-reading them here is duplicated work on the slowest
-- channel in the system. The full answer is still what a one-off read asks for.
function handlers.GetProjectStructure(args)
  local light = (args and args[1] == 1)
  local tracks = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local colour = reaper.GetTrackColor(tr)
    local r, g, b = reaper.ColorFromNative(colour)

    local fx = {}
    for f = 0, reaper.TrackFX_GetCount(tr) - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(tr, f, '')
      local params = {}
      -- Names ride even the light poll. OSC only names the parameters of the track selected
      -- in Reaper, so without these every other rack unit reads P1..P8 -- a faceplate you can
      -- turn and cannot read. Values stay out: OSC streams those and is their authority.
      local param_names = {}
      for p = 0, math.min(reaper.TrackFX_GetNumParams(tr, f), 32) - 1 do
        local _, p_name = reaper.TrackFX_GetParamName(tr, f, p, '')
        param_names[#param_names + 1] = p_name
      end
      if not light then
        for p = 0, math.min(reaper.TrackFX_GetNumParams(tr, f), 32) - 1 do
          local _, p_name = reaper.TrackFX_GetParamName(tr, f, p, '')
          params[#params + 1] = {
            index = p,
            name = p_name,
            value = reaper.TrackFX_GetParamNormalized(tr, f, p),
          }
        end
      end
      fx[#fx + 1] = {
        index = f,
        name = fx_name,
        enabled = reaper.TrackFX_GetEnabled(tr, f),
        params = params,
        param_names = param_names,
      }
    end

    local sends = {}
    for s = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
      local dest = reaper.GetTrackSendInfo_Value(tr, 0, s, 'P_DESTTRACK')
      local dest_index = -1
      if dest then
        -- Resolved to an INDEX, not a name. OSC can only identify a send's destination by
        -- name, which is ambiguous the moment a project has two tracks called "Verb" -- and
        -- duplicate track names are completely normal. The patchbay prefers this.
        dest_index = math.floor(reaper.GetMediaTrackInfo_Value(dest, 'IP_TRACKNUMBER'))
      end
      local dest_name = ''
      if dest then
        local _, dn = reaper.GetTrackName(dest)
        dest_name = dn
      end
      sends[#sends + 1] = {
        index = s,
        dest_track = dest_index,
        dest_name = dest_name,
        volume = reaper.GetTrackSendInfo_Value(tr, 0, s, 'D_VOL'),
        pan = reaper.GetTrackSendInfo_Value(tr, 0, s, 'D_PAN'),
      }
    end

    tracks[#tracks + 1] = {
      index = i + 1,
      name = name,
      colour = {r / 255.0, g / 255.0, b / 255.0},
      rec_arm = reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') > 0.5,
      folder_depth = reaper.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH'),
      fx = fx,
      sends = sends,
    }
  end
  return {tracks = tracks, tempo = reaper.Master_GetTempo(),
          track_count = reaper.CountTracks(0)}
end

--- The arrangement: where the blocks are. The other thing OSC says nothing whatsoever about.
--
-- Separate from GetProjectStructure rather than folded into it, because the two change on
-- completely different clocks. The structure -- track count, plugin chains, routing -- changes
-- when someone reaches for it; the arrangement changes on every drag of every item. Polling one
-- at the rate the other needs would mean either a stale patchbay or a thousand plugin
-- parameters re-read twice a second.
--
-- Tracks with nothing on them are omitted entirely, and reaper-3d clears every lane before
-- applying this. That is not an optimisation: the encoder below cannot tell an empty list from
-- an empty object, so an explicit empty `items` would arrive as `{}` and have to be guessed at.
-- A track's items in time order. Reaper keeps its own list in the order items were made or
-- last moved, which is close to time order and not the same thing -- and the desk numbers items
-- left to right, so every handler that takes or reports an item index goes through this.
local function sorted_items(tr)
  local items = {}
  for n = 0, reaper.CountTrackMediaItems(tr) - 1 do
    items[#items + 1] = reaper.GetTrackMediaItem(tr, n)
  end
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, 'D_POSITION') < reaper.GetMediaItemInfo_Value(b, 'D_POSITION')
  end)
  return items
end

function handlers.GetTimeline()
  local tracks = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local items = {}
    for _, it in ipairs(sorted_items(tr)) do
      local name = ''
      local take = reaper.GetActiveTake(it)
      if take then
        -- GetSetMediaItemTakeInfo_String rather than GetTakeName: the latter is missing on
        -- older Reaper builds, and a bridge that errors on one is worse than a nameless block.
        local ok, value = reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', false)
        if ok then name = value end
      end
      items[#items + 1] = {
        start = reaper.GetMediaItemInfo_Value(it, 'D_POSITION'),
        length = reaper.GetMediaItemInfo_Value(it, 'D_LENGTH'),
        muted = reaper.GetMediaItemInfo_Value(it, 'B_MUTE') > 0.5,
        selected = reaper.IsMediaItemSelected(it),
        name = name,
      }
    end
    if #items > 0 then
      tracks[#tracks + 1] = {index = i + 1, items = items}
    end
  end

  -- Markers only, not regions. A region is a span and the ruler draws points; a region drawn as
  -- its start marker would silently lose the half of it that matters.
  local markers = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  for m = 0, marker_count + region_count - 1 do
    local ok, is_region, pos, _, name = reaper.EnumProjectMarkers(m)
    if ok ~= 0 and not is_region then
      markers[#markers + 1] = {position = pos, name = name}
    end
  end

  return {
    tracks = tracks,
    markers = markers,
    length = reaper.GetProjectLength(0),
    -- Every track in the project, not just the ones with items on them and not just the ones
    -- in the OSC bank. It rides along here because it changes on roughly the same clock as the
    -- arrangement, and because nothing else reaper-3d can reach knows the number at all.
    track_count = reaper.CountTracks(0),
  }
end

--- Create a send. The one thing the patchbay exists to do and the one thing OSC cannot express.
function handlers.CreateTrackSend(args)
  local src = track_from_osc(args[1])
  local dst = track_from_osc(args[2])
  if not src or not dst then return {ok = false, error = 'no such track'} end
  local index = reaper.CreateTrackSend(src, dst)
  reaper.UpdateArrange()
  return {ok = index >= 0, send_index = index}
end

function handlers.RemoveTrackSend(args)
  local src = track_from_osc(args[1])
  if not src then return {ok = false, error = 'no such track'} end
  local ok = reaper.RemoveTrackSend(src, 0, math.floor(args[2] or 0))
  reaper.UpdateArrange()
  return {ok = ok}
end

--- What Reaper itself holds right now: the transport, the loop, the history, and every track's
-- mix settings and plugin states. OSC already streams most of this, which is exactly why it is
-- here: a test that checks the desk against the desk's own echo proves nothing, and this reads
-- the project directly, by a different road.
--
-- args[1], when given, caps how many parameters per plugin are reported (default 8).
function handlers.GetState(args)
  local cap = math.floor((args and args[1]) or 8)
  local state = reaper.GetPlayState()
  local playing = (state & 1) == 1
  local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  local sel_start, sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local tracks = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local fx = {}
    for f = 0, reaper.TrackFX_GetCount(tr) - 1 do
      local params = {}
      for p = 0, math.min(reaper.TrackFX_GetNumParams(tr, f), cap) - 1 do
        params[#params + 1] = reaper.TrackFX_GetParamNormalized(tr, f, p)
      end
      fx[#fx + 1] = {enabled = reaper.TrackFX_GetEnabled(tr, f), params = params}
    end
    local items = {}
    for _, it in ipairs(sorted_items(tr)) do
      items[#items + 1] = {
        start = reaper.GetMediaItemInfo_Value(it, 'D_POSITION'),
        length = reaper.GetMediaItemInfo_Value(it, 'D_LENGTH'),
        selected = reaper.IsMediaItemSelected(it),
      }
    end
    tracks[#tracks + 1] = {
      index = i + 1,
      volume = reaper.GetMediaTrackInfo_Value(tr, 'D_VOL'),
      pan = reaper.GetMediaTrackInfo_Value(tr, 'D_PAN'),
      mute = reaper.GetMediaTrackInfo_Value(tr, 'B_MUTE') > 0.5,
      solo = reaper.GetMediaTrackInfo_Value(tr, 'I_SOLO') > 0.5,
      arm = reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') > 0.5,
      fx = fx,
      items = items,
    }
  end
  return {
    ok = true,
    playing = playing,
    recording = (state & 4) == 4,
    position = playing and reaper.GetPlayPosition() or reaper.GetCursorPosition(),
    cursor = reaper.GetCursorPosition(),
    repeating = reaper.GetSetRepeat(-1) == 1,
    loop_start = loop_start, loop_end = loop_end,
    selection_start = sel_start, selection_end = sel_end,
    can_undo = reaper.Undo_CanUndo2(0) or '',
    can_redo = reaper.Undo_CanRedo2(0) or '',
    tracks = tracks,
  }
end

--- Set one of a track's numeric properties, the way a mouse in Reaper would. For checking that
-- a change made in REAPER reaches the desk, which the desk cannot test by writing it itself.
local SETTABLE = {D_VOL = true, D_PAN = true, B_MUTE = true, I_SOLO = true, I_RECARM = true}
function handlers.SetTrackValue(args)
  local tr = track_from_osc(args[1])
  if not tr or not SETTABLE[args[2] or ''] then return {ok = false, error = 'no such track or key'} end
  reaper.SetMediaTrackInfo_Value(tr, args[2], args[3])
  return {ok = true}
end

-- --- editing ----------------------------------------------------------------------------
--
-- Items are addressed as (track, index in lane): the same numbering GetTimeline reports, which
-- is Reaper's own, left to right. Every edit is one undo point named the way Reaper names its
-- own, so Edit: Undo from the desk or from Reaper's menu takes it back as one step.

local function item_at(args)
  local tr = track_from_osc(args[1])
  if not tr then return nil end
  return sorted_items(tr)[math.floor(args[2] or -1) + 1]
end

-- SelectAllMediaItems(0, false) would be the obvious call, and it writes its own "Unselect all
-- items" undo point -- so a click on the desk pushed the last real edit one undo further away.
local function unselect_all()
  for n = reaper.CountSelectedMediaItems(0) - 1, 0, -1 do
    reaper.SetMediaItemSelected(reaper.GetSelectedMediaItem(0, n), false)
  end
end

local function edited(label)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(label, 4)
  return {ok = true}
end

-- args: track, index, additive. Not additive replaces the selection, as a click does in Reaper.
function handlers.SelectItem(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  -- Not an undo point. Undo on the desk is for things that change the song; a selection
  -- step in the history means an undo that appears to do nothing.
  if not args[3] then unselect_all() end
  reaper.SetMediaItemSelected(it, not (args[3] and reaper.IsMediaItemSelected(it)))
  reaper.UpdateArrange()
  return {ok = true}
end

function handlers.ClearItemSelection()
  unselect_all()
  reaper.UpdateArrange()
  return {ok = true}
end

-- args: track, index, new start in seconds.
function handlers.MoveItem(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  reaper.Undo_BeginBlock()
  reaper.SetMediaItemInfo_Value(it, 'D_POSITION', math.max(0, args[3] or 0))
  return edited('Move media item')
end

-- args: seconds. Every selected item that spans that point is cut there, and both halves stay
-- selected -- what Reaper's own "S" does at the edit cursor.
function handlers.SplitSelected(args)
  local at = args[1] or reaper.GetCursorPosition()
  local targets = {}
  for n = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, n)
    local start = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
    local length = reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')
    if at > start and at < start + length then targets[#targets + 1] = it end
  end
  if #targets == 0 then return {ok = true, split = 0} end
  reaper.Undo_BeginBlock()
  for _, it in ipairs(targets) do
    local right = reaper.SplitMediaItem(it, at)
    if right then reaper.SetMediaItemSelected(right, true) end
  end
  local result = edited('Split items')
  result.split = #targets
  return result
end

-- args: track (1-based, as OSC), fx (1-based), param (1-based). The plugin's own words for one
-- parameter's value -- "-12.0 dB", "4.0:1" -- with the normalised value they describe, so the
-- caller can tell whether the words still belong to the knob it is looking at. Asked for one
-- knob at a time, by whoever is touching it: OSC can stream these for every track, and doing
-- so made a single surface refresh 115,000 messages long.
function handlers.GetParamText(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx, p = (args[2] or 1) - 1, (args[3] or 1) - 1
  local _, text = reaper.TrackFX_GetFormattedParamValue(tr, fx, p, '')
  return {ok = true, text = text, value = reaper.TrackFX_GetParamNormalized(tr, fx, p)}
end

function handlers.Ping()
  return {ok = true, version = reaper.GetAppVersion()}
end

local expected

local function handle_file(filename)
  local id = filename:match('^request_(%d+)%.json$')
  if not id then return false end

  local path = bridge_dir .. filename
  local f = io.open(path, 'r')
  if not f then return false end
  expected[id] = nil
  expected[tostring(tonumber(id) + 1)] = reaper.time_precise()
  local text = f:read('*a')
  f:close()
  -- Deleted BEFORE the handler runs. A handler that errors would otherwise leave the request on
  -- disk to be retried on the next tick, forever, at thirty times a second.
  os.remove(path)

  local req_id, fn, args = decode_request(text)
  local handler = handlers[fn or '']
  local result
  if not handler then
    result = {ok = false, error = 'unknown function: ' .. tostring(fn)}
  else
    local ok, value = pcall(handler, args)
    result = ok and value or {ok = false, error = tostring(value)}
  end

  -- Written aside and renamed into place, so the reader never sees half an answer. A response
  -- with forty tracks of state in it is big enough to be caught mid-write by a 60 Hz poll.
  local final = bridge_dir .. 'response_' .. tostring(req_id or id) .. '.json'
  local out = io.open(final .. '.tmp', 'w')
  if out then
    out:write(encode(result))
    out:close()
    os.remove(final)
    os.rename(final .. '.tmp', final)
  end
  return true
end

-- The id each client is expected to send next, and when that was last true.
--
-- EnumerateFiles answers from a listing Reaper caches for about half a second, with no call
-- that refreshes it -- so a bridge that only listed the directory made every request wait for
-- that cache to expire: 0.5 s a request, back to back, from a script that runs thirty times a
-- second. Clients number their requests in sequence, so once one has been heard from, its next
-- request has a name known in advance and can simply be opened. Listing is left for a client's
-- first request, and for anyone who does not count.
expected = {}

local function handle_expected()
  local progressed = true
  while progressed do
    progressed = false
    local now = reaper.time_precise()
    for next_id, seen in pairs(expected) do
      if now - seen > 30 then
        expected[next_id] = nil
      else
        local name = 'request_' .. next_id .. '.json'
        local f = io.open(bridge_dir .. name, 'r')
        if f then
          f:close()
          handle_file(name)
          progressed = true
          break
        end
      end
    end
  end
end

local function tick()
  handle_expected()
  local i = 0
  while true do
    local filename = reaper.EnumerateFiles(bridge_dir, i)
    if not filename then break end
    -- Collected and handled without advancing the index when a file is consumed, because
    -- EnumerateFiles re-indexes after a deletion and skipping forward would miss every second
    -- request in a burst. A name the cache still lists but that is already handled fails to
    -- open in handle_file and is stepped over.
    if filename:match('^request_%d+%.json$') and handle_file(filename) then
      -- consumed
    else
      i = i + 1
    end
  end
  reaper.defer(tick)
end

ensure_dir()
-- Answers left by a previous run are for clients that have long since given up on them.
do
  local stale, i = {}, 0
  while true do
    local name = reaper.EnumerateFiles(bridge_dir, i)
    if not name then break end
    if name:match('^response_') then stale[#stale + 1] = name end
    i = i + 1
  end
  for _, name in ipairs(stale) do os.remove(bridge_dir .. name) end
end
reaper.ShowConsoleMsg('reaper-3d bridge running: ' .. bridge_dir .. '\n')
tick()
