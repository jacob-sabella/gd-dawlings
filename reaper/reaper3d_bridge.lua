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
function handlers.GetProjectStructure()
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
      for p = 0, math.min(reaper.TrackFX_GetNumParams(tr, f), 32) - 1 do
        local _, p_name = reaper.TrackFX_GetParamName(tr, f, p, '')
        params[#params + 1] = {
          index = p,
          name = p_name,
          value = reaper.TrackFX_GetParamNormalized(tr, f, p),
        }
      end
      fx[#fx + 1] = {
        index = f,
        name = fx_name,
        enabled = reaper.TrackFX_GetEnabled(tr, f),
        params = params,
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
      sends[#sends + 1] = {
        index = s,
        dest_track = dest_index,
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
  return {tracks = tracks, tempo = reaper.Master_GetTempo()}
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

function handlers.Ping()
  return {ok = true, version = reaper.GetAppVersion()}
end

local function handle_file(filename)
  local id = filename:match('^request_(%d+)%.json$')
  if not id then return end

  local path = bridge_dir .. filename
  local f = io.open(path, 'r')
  if not f then return end
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

  local out = io.open(bridge_dir .. 'response_' .. tostring(req_id or id) .. '.json', 'w')
  if out then
    out:write(encode(result))
    out:close()
  end
end

local function tick()
  local i = 0
  while true do
    local filename = reaper.EnumerateFiles(bridge_dir, i)
    if not filename then break end
    -- Collected and handled without advancing the index when a file is consumed, because
    -- EnumerateFiles re-indexes after a deletion and skipping forward would miss every second
    -- request in a burst.
    if filename:match('^request_%d+%.json$') then
      handle_file(filename)
    else
      i = i + 1
    end
  end
  reaper.defer(tick)
end

ensure_dir()
reaper.ShowConsoleMsg('reaper-3d bridge running: ' .. bridge_dir .. '\n')
tick()
