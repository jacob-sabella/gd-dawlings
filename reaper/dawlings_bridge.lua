-- dawlings bridge: the structural half of the link.
--
-- WHAT THIS IS FOR. dawlings talks to Reaper over OSC for everything that moves -- faders,
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
--   1. Copy this file to <Reaper resource path>/Scripts/dawlings_bridge.lua
--      (Options > Show REAPER resource path in explorer/finder)
--   2. Actions > Show action list > ReaScript: Load... > pick this file
--   3. Run it once. It stays running and re-arms itself; the console in Reaper says so.
--      To have it start with Reaper, add a dofile() line to Scripts/__startup.lua.
--
-- PROTOCOL. dawlings writes request_<id>.json into the data directory below; this reads it,
-- deletes it, and writes response_<id>.json beside it. One call per file, no ordering guarantee
-- between ids. See core/reaper/script_bridge.gd for the client half.

local bridge_dir = reaper.GetResourcePath() .. '/Scripts/dawlings_bridge_data/'

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
-- The args array of a request, read as JSON: numbers, strings with their escapes undone,
-- true and false. A real scanner rather than a split on commas, because a take's name or a
-- file's path may hold a comma, a quote or a backslash, and a Windows path always holds the
-- last. Positions are kept: a null is a hole at its own index, never a shift of the rest.
local function decode_args(text, from)
  local args, k, i, n = {}, 0, from, #text
  local escapes = {n = '\n', t = '\t', r = '\r', b = '\b', f = '\f'}
  while i <= n do
    local c = text:sub(i, i)
    if c == ']' then break
    elseif c == '"' then
      local out, j = {}, i + 1
      while j <= n do
        local d = text:sub(j, j)
        if d == '\\' then
          local e = text:sub(j + 1, j + 1)
          if e == 'u' then
            out[#out + 1] = utf8.char(tonumber(text:sub(j + 2, j + 5), 16) or 63)
            j = j + 6
          else
            out[#out + 1] = escapes[e] or e
            j = j + 2
          end
        elseif d == '"' then break
        else
          out[#out + 1] = d
          j = j + 1
        end
      end
      k = k + 1
      args[k] = table.concat(out)
      i = j + 1
    elseif c:match('[%-%d]') then
      local num = text:match('^[%-%d%.eE%+]+', i)
      k = k + 1
      args[k] = tonumber(num)
      i = i + #num
    elseif text:sub(i, i + 3) == 'true' then
      k = k + 1; args[k] = true; i = i + 4
    elseif text:sub(i, i + 4) == 'false' then
      k = k + 1; args[k] = false; i = i + 5
    elseif text:sub(i, i + 3) == 'null' then
      k = k + 1; i = i + 4
    else
      i = i + 1
    end
  end
  return args
end

local function decode_request(text)
  local id = tonumber(text:match('"id"%s*:%s*(%-?%d+)'))
  local fn = text:match('"fn"%s*:%s*"([^"]*)"')
  local _, open = text:find('"args"%s*:%s*%[')
  local args = open and decode_args(text, open + 1) or {}
  return id, fn, args
end

-- Reaper indexes tracks from 0 and OSC addresses them from 1. Everything crossing this boundary
-- goes through these two, because an off-by-one here moves the wrong fader -- which looks like a
-- working bridge until the moment it matters.
local function track_from_osc(n)
  return reaper.GetTrack(0, (n or 1) - 1)
end

local handlers = {}

--- The whole project shape in one call: what dawlings builds its racks and patchbay from.
--
-- args[1] == 1 asks for the LIGHT answer: every plugin's name and bypass, but none of its
-- parameter values. That exists because dawlings polls this on a slow clock for the three
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
      local wet = nil
      local wet_param = reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(tr, f, ':wet') or -1
      if wet_param >= 0 then wet = reaper.TrackFX_GetParamNormalized(tr, f, wet_param) end
      local _, preset = reaper.TrackFX_GetPreset(tr, f, '')
      local _, preset_count = reaper.TrackFX_GetPresetIndex(tr, f)
      fx[#fx + 1] = {
        index = f,
        name = fx_name,
        enabled = reaper.TrackFX_GetEnabled(tr, f),
        params = params,
        param_names = param_names,
        wet = wet,
        preset = preset or '',
        preset_count = preset_count or -1,
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
        -- Into channels 3/4 or above: a key for a plugin's detector, not part of the mix. The
        -- low ten bits are the first channel; the bits above say mono and the like.
        key = (math.floor(reaper.GetTrackSendInfo_Value(tr, 0, s, 'I_DSTCHAN')) & 1023) >= 2,
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
-- Tracks with nothing on them are omitted entirely, and dawlings clears every lane before
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

-- A MIDI take's notes for the arranger's mini piano roll: flat {on, off, pitch, velocity,
-- channel, ...} in seconds from the item's start. Capped, because this rides a poll that runs
-- every two seconds over the whole project; a sketch of the notes is what a block on a lane
-- can show, and the cap is far past what one fits.
local NOTES_PER_ITEM = 512
local function item_notes(it, take)
  if not take or not reaper.TakeIsMIDI(take) then return nil end
  local item_start = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
  local _, count = reaper.MIDI_CountEvts(take)
  local out = {}
  for n = 0, math.min(count, NOTES_PER_ITEM) - 1 do
    local ok, _, muted, ppq_on, ppq_off, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
    if ok and not muted then
      out[#out + 1] = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_on) - item_start
      out[#out + 1] = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_off) - item_start
      out[#out + 1] = pitch
      out[#out + 1] = vel
      out[#out + 1] = chan
    end
  end
  if #out == 0 then return nil end
  return out
end

-- --- automation --------------------------------------------------------------------------
--
-- A track's envelopes as dawlings names them: "volume" and "send:<destination track, from 1>" in
-- dB, "pan" -1 left to 1 right, "mute" 0/1, "fx:<fx>:<param>" (both from 1, as OSC numbers them)
-- normalised 0-1. Points cross as flat seconds, value, shape (0 hold, 1 linear) triples.

local ENVELOPE_CHUNKS = {volume = '<VOLENV2', pan = '<PANENV2', mute = '<MUTEENV'}
-- Track: Toggle track volume / pan / mute envelope visible, for the one track selected: how an
-- envelope Reaper does not have yet is made, as a person would make it.
local ENVELOPE_SHOW = {volume = 40406, pan = 40407, mute = 40867}

local function send_to(tr, dest)
  for s = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local d = reaper.GetTrackSendInfo_Value(tr, 0, s, 'P_DESTTRACK')
    if d and reaper.ValidatePtr(d, 'MediaTrack*') and reaper.GetMediaTrackInfo_Value(d, 'IP_TRACKNUMBER') == dest then
      return s
    end
  end
  return nil
end

-- The envelope for a target, made when `create` and Reaper has none; and the fx and parameter
-- (from 0) for an fx target.
local function envelope_of(tr, target, create)
  local chunk = ENVELOPE_CHUNKS[target]
  if chunk then
    local env = reaper.GetTrackEnvelopeByChunkName(tr, chunk)
    if not env and create then
      local selected = {}
      for i = 0, reaper.CountSelectedTracks(0) - 1 do selected[#selected + 1] = reaper.GetSelectedTrack(0, i) end
      reaper.SetOnlyTrackSelected(tr)
      reaper.Main_OnCommand(ENVELOPE_SHOW[target], 0)
      reaper.SetTrackSelected(tr, false)
      for _, t in ipairs(selected) do reaper.SetTrackSelected(t, true) end
      env = reaper.GetTrackEnvelopeByChunkName(tr, chunk)
    end
    return env
  end
  local dest = target:match('^send:(%d+)$')
  if dest then
    local s = send_to(tr, tonumber(dest))
    if not s then return nil end
    -- '<VOLENV' is the envelope's chunk name, and Reaper hands back its (inactive) envelope
    -- whether anyone has drawn on it or not.
    local env = reaper.GetTrackSendInfo_Value(tr, 0, s, 'P_ENV:<VOLENV')
    return env and reaper.ValidatePtr(env, 'TrackEnvelope*') and env or nil
  end
  local fx, param = target:match('^fx:(%d+):(%d+)$')
  if fx then
    fx, param = tonumber(fx) - 1, tonumber(param) - 1
    if fx < 0 or fx >= reaper.TrackFX_GetCount(tr) or param < 0 or param >= reaper.TrackFX_GetNumParams(tr, fx) then
      return nil
    end
    return reaper.GetFXEnvelope(tr, fx, param, create), fx, param
  end
  return nil
end

local function to_amplitude(env, raw)
  local mode = reaper.GetEnvelopeScalingMode(env)
  return mode ~= 0 and reaper.ScaleFromEnvelopeMode(mode, raw) or raw
end

local function from_amplitude(env, amp)
  local mode = reaper.GetEnvelopeScalingMode(env)
  return mode ~= 0 and reaper.ScaleToEnvelopeMode(mode, amp) or amp
end

-- An envelope's value in dawlings's unit, and back.
local function env_read(env, tr, target, raw, fx, param)
  if target == 'volume' or target:match('^send:') then
    local amp = to_amplitude(env, raw)
    return amp > 0 and 20 * math.log(amp, 10) or -150
  elseif target == 'pan' then
    return -raw
  elseif target == 'mute' then
    -- Reaper's mute envelope is "playing": 1 at the top is heard, 0 is muted.
    return raw < 0.5 and 1 or 0
  end
  local _, lo, hi = reaper.TrackFX_GetParamEx(tr, fx, param)
  return hi > lo and (raw - lo) / (hi - lo) or raw
end

local function env_write(env, tr, target, v, fx, param)
  if target == 'volume' or target:match('^send:') then
    return from_amplitude(env, v <= -150 and 0 or 10 ^ (v / 20))
  elseif target == 'pan' then
    return -v
  elseif target == 'mute' then
    return v >= 0.5 and 0 or 1
  end
  local _, lo, hi = reaper.TrackFX_GetParamEx(tr, fx, param)
  return lo + v * (hi - lo)
end

-- Whether an envelope plays: a track's own are there from the start, inactive and hidden, until
-- someone draws on them.
local function is_active(env)
  local _, active = reaper.GetSetEnvelopeInfo_String(env, 'ACTIVE', '', false)
  return active == '1'
end

local function set_active(env, on)
  local flag = on and '1' or '0'
  reaper.GetSetEnvelopeInfo_String(env, 'ACTIVE', flag, true)
  reaper.GetSetEnvelopeInfo_String(env, 'VISIBLE', flag, true)
end

local function env_points(env, tr, target, fx, param)
  local out = {}
  for p = 0, reaper.CountEnvelopePoints(env) - 1 do
    local ok, time, raw, shape = reaper.GetEnvelopePoint(env, p)
    if ok then
      out[#out + 1] = time
      out[#out + 1] = env_read(env, tr, target, raw, fx, param)
      -- Reaper's square is a hold; every other shape is drawn as a straight line.
      out[#out + 1] = shape == 1 and 0 or 1
    end
  end
  return out
end

-- Every envelope with points on a track, by target.
local function track_automation(tr)
  local lanes = {}
  local any = false
  for target, _ in pairs(ENVELOPE_CHUNKS) do
    local env = envelope_of(tr, target, false)
    if env and reaper.CountEnvelopePoints(env) > 0 and is_active(env) then
      lanes[target] = env_points(env, tr, target)
      any = true
    end
  end
  for s = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local env = reaper.GetTrackSendInfo_Value(tr, 0, s, 'P_ENV:<VOLENV')
    local d = reaper.GetTrackSendInfo_Value(tr, 0, s, 'P_DESTTRACK')
    if env and reaper.ValidatePtr(env, 'TrackEnvelope*') and reaper.CountEnvelopePoints(env) > 0
        and is_active(env) and d and reaper.ValidatePtr(d, 'MediaTrack*') then
      local target = 'send:' .. math.floor(reaper.GetMediaTrackInfo_Value(d, 'IP_TRACKNUMBER'))
      lanes[target] = env_points(env, tr, target)
      any = true
    end
  end
  -- A plugin's envelopes by asking each envelope whose it is, not each of a plugin's parameters
  -- whether it has one: some plugins have thousands.
  for e = 0, reaper.CountTrackEnvelopes(tr) - 1 do
    local env = reaper.GetTrackEnvelope(tr, e)
    local _, fx, param = reaper.Envelope_GetParentTrack(env)
    if fx and fx >= 0 and param and param >= 0 and reaper.CountEnvelopePoints(env) > 0 and is_active(env) then
      local target = ('fx:%d:%d'):format(fx + 1, param + 1)
      lanes[target] = env_points(env, tr, target, fx, param)
      any = true
    end
  end
  return any and lanes or nil
end

-- args: track (0 the master), target, then flat seconds/value/shape triples: the whole envelope, replaced, as one
-- undo point. No points empties it.
function handlers.SetEnvelope(args)
  -- Track 0 is the master.
  local tr = args[1] == 0 and reaper.GetMasterTrack(0) or track_from_osc(args[1])
  local target = tostring(args[2] or '')
  if not tr then return {ok = false, error = 'no such track'} end
  reaper.Undo_BeginBlock()
  local env, fx, param = envelope_of(tr, target, #args > 2)
  if env then
    -- Active while it has points; without, the control is the fader's again.
    -- Made active first: Reaper does not play an envelope switched on after its points are in.
    set_active(env, #args > 2)
    -- Then emptied one by one: a range leaves the point a new envelope starts with, at 0.
    for p = reaper.CountEnvelopePoints(env) - 1, 0, -1 do
      reaper.DeleteEnvelopePointEx(env, -1, p)
    end
    for i = 3, #args - 2, 3 do
      reaper.InsertEnvelopePoint(env, args[i], env_write(env, tr, target, args[i + 1], fx, param),
          (args[i + 2] or 1) < 0.5 and 1 or 0, 0, false, true)
    end
    reaper.Envelope_SortPoints(env)
    -- Trim/Read plays envelopes under faders that stay where they are; Read moves the faders,
    -- which is what the desk shows.
    if #args > 2 and reaper.GetMediaTrackInfo_Value(tr, 'I_AUTOMODE') == 0 then
      reaper.SetMediaTrackInfo_Value(tr, 'I_AUTOMODE', 1)
    end
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('Automation', -1)
  return {ok = env ~= nil}
end

-- args: track, mode (Reaper's I_AUTOMODE; dawlings's read is Reaper's Read, 1, so its faders move).
function handlers.SetAutomationMode(args)
  local tr = args[1] == 0 and reaper.GetMasterTrack(0) or track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local mode = math.floor(args[2] or 0)
  reaper.SetMediaTrackInfo_Value(tr, 'I_AUTOMODE', mode == 0 and 1 or mode)
  return {ok = true}
end

-- The count-in before recording: the project's metronome setting (projmetroen) &16, "Count-in
-- before recording", and its length in bars (projmetrocountin). Checked on the rig: with &16 set
-- and the metronome on (&1), a record runs the playhead from that many bars before the cursor,
-- reporting recording all the while, and records from the cursor; with the metronome off it
-- records at once, so a count-in is the click's. args: bars, 0 for none.
local COUNT_IN_BEFORE_RECORDING = 16
-- And &8, "Count-in before playback": the same bars of click before the song plays.
local COUNT_IN_BEFORE_PLAYBACK = 8

-- Pre-roll, the song under the count rather than the click alone: Reaper's own toggles, "Pre-roll:
-- Toggle pre-roll on record" and "on play", and its length in measures (prerollmeas). Each action
-- is checked by name before it is used, so a Reaper that numbers them otherwise is left alone.
local PREROLL_RECORD = 41819
local PREROLL_PLAY = 41818

local function preroll_action(id, word)
  local ok, name = pcall(reaper.kbd_getTextFromCmd, id, nil)
  name = ok and tostring(name or ''):lower() or ''
  return name:find('pre%-roll') ~= nil and name:find(word) ~= nil, name
end

local function preroll_on(id, word)
  return preroll_action(id, word) and reaper.GetToggleCommandState(id) == 1
end

local function set_preroll(id, word, on)
  if preroll_action(id, word) and (reaper.GetToggleCommandState(id) == 1) ~= on then
    reaper.Main_OnCommand(id, 0)
  end
end

local function count_in_bars()
  local _, en = reaper.get_config_var_string('projmetroen')
  local _, bars = reaper.get_config_var_string('projmetrocountin')
  if (math.floor(tonumber(en) or 0) & COUNT_IN_BEFORE_RECORDING) == 0 then
    if preroll_on(PREROLL_RECORD, 'record') then
      local _, meas = reaper.get_config_var_string('prerollmeas')
      return math.floor((tonumber(meas) or 0) + 0.5)
    end
    return 0
  end
  return math.floor((tonumber(bars) or 0) + 0.5)
end

local function record_inputs()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    out[#out + 1] = math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), 'I_RECINPUT'))
  end
  return out
end

local function count_in_play()
  local _, en = reaper.get_config_var_string('projmetroen')
  return (math.floor(tonumber(en) or 0) & COUNT_IN_BEFORE_PLAYBACK) ~= 0 or preroll_on(PREROLL_PLAY, 'play')
end

local function pre_roll()
  return preroll_on(PREROLL_RECORD, 'record')
end

-- args: bars (0 for none), whether playback counts in too, and whether the count is pre-roll (the
-- song under it). Pre-roll is Reaper's pre-roll in place of its count-in, never both.
function handlers.SetCountIn(args)
  local bars = math.max(0, math.floor(args[1] or 0))
  local play = args[2] == true
  local song = args[3] == true and bars > 0
  local _, en = reaper.get_config_var_string('projmetroen')
  local flags = math.floor(tonumber(en) or 0)
  set_preroll(PREROLL_RECORD, 'record', song)
  set_preroll(PREROLL_PLAY, 'play', song and play)
  if song then
    reaper.set_config_var_string('prerollmeas', tostring(bars), 0)
    reaper.set_config_var_string('projmetroen', tostring(flags & ~COUNT_IN_BEFORE_RECORDING & ~COUNT_IN_BEFORE_PLAYBACK), 0)
    local _, rec_name = preroll_action(PREROLL_RECORD, 'record')
    local _, play_name = preroll_action(PREROLL_PLAY, 'play')
    return {ok = pre_roll(), count_in = count_in_bars(), count_in_play = count_in_play(), pre_roll = pre_roll(),
      actions = {rec_name, play_name}}
  end
  if bars > 0 then
    flags = flags | COUNT_IN_BEFORE_RECORDING
    -- The third argument is required, and 0 is what works.
    reaper.set_config_var_string('projmetrocountin', tostring(bars), 0)
  else
    flags = flags & ~COUNT_IN_BEFORE_RECORDING
  end
  if bars > 0 and play then
    flags = flags | COUNT_IN_BEFORE_PLAYBACK
  else
    flags = flags & ~COUNT_IN_BEFORE_PLAYBACK
  end
  reaper.set_config_var_string('projmetroen', tostring(flags), 0)
  return {ok = true, count_in = count_in_bars(), count_in_play = count_in_play(), pre_roll = pre_roll()}
end

-- A track's record input: Reaper's I_RECINPUT (-1 none, a hardware input index, |1024 for the
-- stereo pair from there, 4096 and up MIDI). args: track (1-based, as OSC), code.
function handlers.SetTrackInput(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  reaper.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', math.floor(args[2] or 0))
  return {ok = true}
end

-- Punching in and out: Reaper's record mode, time selection auto-punch (40076) or normal (40252),
-- checked on the rig to be radio toggles of each other. Reaper's preference, not the project's.
-- args: 1 to punch, 0 not.
local PUNCH_MODE, NORMAL_MODE = 40076, 40252

function handlers.SetPunch(args)
  reaper.Main_OnCommand((args[1] or 0) ~= 0 and PUNCH_MODE or NORMAL_MODE, 0)
  return {ok = true, punch = reaper.GetToggleCommandState(PUNCH_MODE) == 1}
end

-- args: start, end (seconds), stems (0/1), tail (ms; Reaper renders that much after the end, for
-- effects to ring out). Reaper renders that stretch of the project, offline,
-- as 24-bit stereo WAVs in "<project> renders" beside the project file: "<project> - mix.wav",
-- and with stems "<project> - <track>.wav" for every track, replacing the last render's. Its
-- render settings are put back after, so the project's own are not changed by dawlings asking.
-- Answers the files written.
local RENDER_KEYS = {'RENDER_FILE', 'RENDER_PATTERN', 'RENDER_FORMAT'}
local RENDER_VALUES = {'RENDER_BOUNDSFLAG', 'RENDER_STARTPOS', 'RENDER_ENDPOS', 'RENDER_SETTINGS',
  'RENDER_SRATE', 'RENDER_CHANNELS', 'RENDER_ADDTOPROJ', 'RENDER_TAILFLAG', 'RENDER_TAILMS'}

function handlers.RenderProject(args)
  local from, to, stems, tail = args[1] or 0, args[2] or 0, (args[3] or 0) > 0.5, math.max(args[4] or 0, 0)
  if to - from <= 0.01 then return {ok = false, error = 'nothing to render'} end
  local _, file = reaper.EnumProjects(-1)
  local name = (reaper.GetProjectName(0, '') or ''):gsub('%.[Rr][Pp][Pp]$', '')
  if name == '' then name = 'Untitled' end
  local base = (file and file ~= '') and file:match('^(.*)[/\\]') or reaper.GetProjectPath('')
  local dir = base .. '/' .. name .. ' renders'
  reaper.RecursiveCreateDirectory(dir, 0)
  -- What a render writes there, by name: the mix, and a stem per track. EnumerateFiles would
  -- answer from a listing Reaper keeps for half a second, from before the render.
  local function exists(path)
    local f = io.open(path, 'rb')
    if f then f:close() end
    return f ~= nil
  end
  local expected = {dir .. '/' .. name .. ' - Master.wav'}
  for i = 0, reaper.CountTracks(0) - 1 do
    local _, tname = reaper.GetTrackName(reaper.GetTrack(0, i))
    expected[#expected + 1] = dir .. '/' .. name .. ' - ' .. tname .. '.wav'
  end
  local mix = dir .. '/' .. name .. ' - mix.wav'
  -- A render replaces the last one written there, so what is there after is this render's.
  os.remove(mix)
  for _, f in ipairs(expected) do os.remove(f) end

  local saved_s, saved_v = {}, {}
  for _, k in ipairs(RENDER_KEYS) do
    local _, v = reaper.GetSetProjectInfo_String(0, k, '', false)
    saved_s[k] = v
  end
  for _, k in ipairs(RENDER_VALUES) do saved_v[k] = reaper.GetSetProjectInfo(0, k, 0, false) end
  local selected = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    selected[#selected + 1] = {tr, reaper.IsTrackSelected(tr)}
    reaper.SetTrackSelected(tr, stems)
  end

  reaper.GetSetProjectInfo_String(0, 'RENDER_FILE', dir, true)
  -- $track is the track's name for a stem, and "Master" for the mix, renamed below.
  reaper.GetSetProjectInfo_String(0, 'RENDER_PATTERN', name .. ' - $track', true)
  -- WAV, 24-bit.
  reaper.GetSetProjectInfo_String(0, 'RENDER_FORMAT', 'ZXZhdxgAAQ==', true)
  reaper.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', 0, true)
  reaper.GetSetProjectInfo(0, 'RENDER_STARTPOS', from, true)
  reaper.GetSetProjectInfo(0, 'RENDER_ENDPOS', to, true)
  -- The master mix, and with stems the selected tracks too.
  reaper.GetSetProjectInfo(0, 'RENDER_SETTINGS', stems and 1 or 0, true)
  reaper.GetSetProjectInfo(0, 'RENDER_SRATE', 0, true)
  reaper.GetSetProjectInfo(0, 'RENDER_CHANNELS', 2, true)
  reaper.GetSetProjectInfo(0, 'RENDER_ADDTOPROJ', 0, true)
  -- The tail, for the custom time bounds (bit 1) the render uses.
  reaper.GetSetProjectInfo(0, 'RENDER_TAILFLAG', tail > 0 and 1 or 0, true)
  reaper.GetSetProjectInfo(0, 'RENDER_TAILMS', tail, true)
  local began = reaper.time_precise()
  -- File: Render project, using the most recent render settings, auto-close render dialog.
  reaper.Main_OnCommand(42230, 0)

  for k, v in pairs(saved_s) do reaper.GetSetProjectInfo_String(0, k, v, true) end
  for k, v in pairs(saved_v) do reaper.GetSetProjectInfo(0, k, v, true) end
  for _, row in ipairs(selected) do reaper.SetTrackSelected(row[1], row[2]) end

  -- What it wrote. The mix is named for itself.
  local files = {}
  for k, path in ipairs(expected) do
    if exists(path) then
      if k == 1 then
        os.rename(path, mix)
        path = mix
      end
      files[#files + 1] = path
    end
  end
  -- The mix first, then the stems in order of name.
  local first = files[1] == mix and table.remove(files, 1) or nil
  table.sort(files)
  if first then table.insert(files, 1, first) end
  return {ok = #files > 0, files = files, seconds = reaper.time_precise() - began}
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
      -- An audio item's file, by name only, and how far into it the item begins: what lets the
      -- desk draw a guest's take it recorded, split or moved in Reaper or not.
      local source, offset = '', 0
      if take and not reaper.TakeIsMIDI(take) then
        local src = reaper.GetMediaItemTake_Source(take)
        local path = src and reaper.GetMediaSourceFileName(src, '') or ''
        source = path:match('([^/\\]+)$') or ''
        offset = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      end
      items[#items + 1] = {
        start = reaper.GetMediaItemInfo_Value(it, 'D_POSITION'),
        length = reaper.GetMediaItemInfo_Value(it, 'D_LENGTH'),
        muted = reaper.GetMediaItemInfo_Value(it, 'B_MUTE') > 0.5,
        locked = (math.floor(reaper.GetMediaItemInfo_Value(it, 'C_LOCK')) & 1) == 1,
        selected = reaper.IsMediaItemSelected(it),
        name = name,
        notes = item_notes(it, take),
        source = source,
        offset = offset,
        fade_in = reaper.GetMediaItemInfo_Value(it, 'D_FADEINLEN'),
        fade_out = reaper.GetMediaItemInfo_Value(it, 'D_FADEOUTLEN'),
        gain = reaper.GetMediaItemInfo_Value(it, 'D_VOL'),
      }
    end
    -- Envelopes and the automation mode ride along, so a track with only those is reported too.
    local automation = track_automation(tr)
    local mode = math.floor(reaper.GetMediaTrackInfo_Value(tr, 'I_AUTOMODE'))
    if #items > 0 or automation or mode ~= 0 then
      tracks[#tracks + 1] = {index = i + 1, items = items, automation = automation or {}, automode = mode}
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

  -- The tempo's changes, as {quarter note, bpm, ramps} from the start of the song; empty for one
  -- tempo throughout. A marker's gradual flag ramps from it to the next, as dawlings's map does.
  -- Before Reaper's first marker the project's own tempo holds.
  local tempo = {}
  local tempo_count = reaper.CountTempoTimeSigMarkers(0)
  if tempo_count > 0 then
    for m = 0, tempo_count - 1 do
      local ok, timepos, _, _, bpm, _, _, linear = reaper.GetTempoTimeSigMarker(0, m)
      if ok then
        local qn = reaper.TimeMap2_timeToQN(0, timepos)
        if #tempo == 0 and qn > 0.000001 then
          local _, base = reaper.GetProjectTimeSignature2(0)
          tempo[1] = {0, base, false}
        end
        tempo[#tempo + 1] = {qn, bpm, linear}
      end
    end
  end

  -- The time signature and its changes, as {quarter note, numerator, denominator}: the song's own
  -- first (at the start of the song), then every marker that changes it.
  local timesig = {}
  local first_num, first_den = reaper.TimeMap_GetTimeSigAtTime(0, 0)
  timesig[1] = {0, first_num, first_den}
  for m = 0, tempo_count - 1 do
    local ok, timepos, _, _, _, num, den = reaper.GetTempoTimeSigMarker(0, m)
    if ok and num > 0 then
      local qn = reaper.TimeMap2_timeToQN(0, timepos)
      if qn > 0.000001 then
        timesig[#timesig + 1] = {qn, num, den}
      end
    end
  end

  return {
    timesig = timesig,
    tracks = tracks,
    master_automation = track_automation(reaper.GetMasterTrack(0)) or {},
    count_in = count_in_bars(),
    count_in_play = count_in_play(),
    pre_roll = pre_roll(),
    -- Every track's record input, in order, and how many hardware inputs there are to choose.
    inputs = record_inputs(),
    audio_inputs = reaper.GetNumAudioInputs(),
    punch = reaper.GetToggleCommandState(PUNCH_MODE) == 1,
    master_automode = math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetMasterTrack(0), 'I_AUTOMODE')),
    -- The project's name (its file's, without .rpp) and its file's name, not its folder: what a
    -- guest is shown. Both empty for a project never saved.
    project_name = (reaper.GetProjectName(0, '') or ''):gsub('%.[Rr][Pp][Pp]$', ''),
    project_file = (select(2, reaper.EnumProjects(-1)) or ''):match('[^/\\]*$') or '',
    markers = markers,
    tempo = tempo,
    length = reaper.GetProjectLength(0),
    -- Every track in the project, not just the ones with items on them and not just the ones
    -- in the OSC bank. It rides along here because it changes on roughly the same clock as the
    -- arrangement, and because nothing else dawlings can reach knows the number at all.
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

--- A sidechain: a send into the destination's channels 3/4, which is where Reaper's own
-- compressors and gates listen when their detector is set to the auxiliary input. The
-- destination is widened to four channels first, or there would be no 3/4 to send into.
function handlers.CreateSidechain(args)
  local src = track_from_osc(args[1])
  local dst = track_from_osc(args[2])
  if not src or not dst then return {ok = false, error = 'no such track'} end
  reaper.Undo_BeginBlock()
  if reaper.GetMediaTrackInfo_Value(dst, 'I_NCHAN') < 4 then
    reaper.SetMediaTrackInfo_Value(dst, 'I_NCHAN', 4)
  end
  local index = reaper.CreateTrackSend(src, dst)
  if index >= 0 then
    reaper.SetTrackSendInfo_Value(src, 0, index, 'I_DSTCHAN', 2)
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('dawlings: sidechain', -1)
  return {ok = index >= 0, send_index = index}
end

-- args: track, fx, to track, to fx (all 1-based, as OSC), copy. A slot past the end of the
-- destination's chain is its end, which is what Reaper does with it too.
function handlers.MoveFx(args)
  local src = track_from_osc(args[1])
  local dst = track_from_osc(args[3])
  if not src or not dst then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  if fx < 0 or fx >= reaper.TrackFX_GetCount(src) then return {ok = false, error = 'no such fx'} end
  local to = math.min(math.floor(args[4] or 1) - 1, reaper.TrackFX_GetCount(dst))
  reaper.Undo_BeginBlock()
  reaper.TrackFX_CopyToTrack(src, fx, dst, math.max(to, 0), not args[5])
  reaper.Undo_EndBlock(args[5] and 'dawlings: copy FX' or 'dawlings: move FX', -1)
  return {ok = true}
end

-- No args. Every plugin format REAPER's own FX browser can see on this machine -- VST, VST3, AU,
-- JS, CLAP, whatever is actually installed here, not a curated list: `EnumInstalledFX` walked
-- from 0 until it stops answering. `ident`, not `name`, is what a later AddFx should be given
-- back, since it is what tells a VST2 build of a plugin apart from its VST3 build when both
-- share the same display name. Capped well past any real plugin count as a safety net: a
-- ReaScript loop that never terminates hangs Reaper's own UI thread, not just this one request.
function handlers.ListInstalledFx()
  local out = {}
  local i = 0
  while i < 100000 do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    if name ~= '' and ident ~= '' then
      out[#out + 1] = {id = ident, label = name}
    end
    i = i + 1
  end
  return {ok = true, fx = out}
end

-- The plugins the desk may add: Reaper's own stock ones, as ReaperBackend.fx_choices offers them.
local STOCK_FX = {ReaEQ = true, ReaComp = true, ReaXcomp = true, ReaGate = true, ReaLimit = true,
  ReaDelay = true, ReaVerbate = true, ReaPitch = true}

-- args: track, plugin (a STOCK_FX name), slot to put it before (1-based, as OSC), or -1 for the
-- end. Answers with the slot it landed in.
function handlers.AddFx(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local name = tostring(args[2] or '')
  if not STOCK_FX[name] then return {ok = false, error = 'not a plugin the desk adds'} end
  local at = math.floor(tonumber(args[3]) or -1)
  local count = reaper.TrackFX_GetCount(tr)
  -- -1000 - n puts it at slot n; -1 always adds one at the end.
  local where = (at >= 1 and at <= count) and (-1000 - (at - 1)) or -1
  reaper.Undo_BeginBlock()
  local index = reaper.TrackFX_AddByName(tr, name, false, where)
  reaper.Undo_EndBlock('dawlings: add FX', -1)
  return {ok = index >= 0, fx = index + 1}
end

-- args: track, fx (1-based).
function handlers.RemoveFx(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  if fx < 0 or fx >= reaper.TrackFX_GetCount(tr) then return {ok = false, error = 'no such fx'} end
  reaper.Undo_BeginBlock()
  local ok = reaper.TrackFX_Delete(tr, fx)
  reaper.Undo_EndBlock('dawlings: remove FX', -1)
  return {ok = ok}
end

-- args: track, fx (1-based), wet 0..1. The plugin's own wet/dry, which every plugin in Reaper
-- has whether or not it has a mix knob of its own.
function handlers.SetFxWet(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  local p = reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(tr, fx, ':wet') or -1
  if p < 0 then return {ok = false, error = 'no wet control'} end
  reaper.TrackFX_SetParamNormalized(tr, fx, p, args[3] or 1)
  return {ok = true}
end

-- args: track, fx (1-based), direction (1 or -1). Answers with the preset it landed on.
function handlers.StepFxPreset(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  reaper.TrackFX_NavigatePresets(tr, fx, (args[3] or 1) < 0 and -1 or 1)
  local _, preset = reaper.TrackFX_GetPreset(tr, fx, '')
  return {ok = true, preset = preset or ''}
end

-- The parameters a plugin really has, by 1-based index. Not Reaper's own Bypass, Wet and Delta,
-- which it appends to every plugin and which the tablet has its own controls for, and not the
-- MIDI CC slots a VST3 with MIDI mapping reports: sixteen channels of 130 of them, which is
-- 2080 of Archetype Gojira X's 2222 "parameters".
local function real_params(tr, fx)
  local skip = {}
  if reaper.TrackFX_GetParamFromIdent then
    for _, ident in ipairs({':bypass', ':wet', ':delta'}) do
      local at = reaper.TrackFX_GetParamFromIdent(tr, fx, ident)
      if at >= 0 then skip[at] = true end
    end
  end
  local out = {}
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do
    if not skip[p] then
      local _, name = reaper.TrackFX_GetParamName(tr, fx, p, '')
      if not name:match('^MIDI CC %d+|%d+$') then
        out[#out + 1] = {index = p + 1, name = name}
      end
    end
  end
  return out
end

-- args: track, fx (1-based). The plugin's real parameters and their names.
function handlers.ListFxParams(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  if fx < 0 or fx >= reaper.TrackFX_GetCount(tr) then return {ok = false, error = 'no such fx'} end
  return {ok = true, params = real_params(tr, fx)}
end

-- args: track, fx, then 1-based parameter indices, flat: the request decoder reads one level. Each one's value, name and the
-- plugin's own words for it: what a tablet showing parameters past OSC's 32 reads its page by.
function handlers.GetFxParams(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  local total = reaper.TrackFX_GetNumParams(tr, fx)
  local out = {}
  for a = 3, #args do
    local p = math.floor(args[a] or 0) - 1
    if p >= 0 and p < total then
      local _, name = reaper.TrackFX_GetParamName(tr, fx, p, '')
      local _, text = reaper.TrackFX_GetFormattedParamValue(tr, fx, p, '')
      out[#out + 1] = {index = p + 1, name = name, value = reaper.TrackFX_GetParamNormalized(tr, fx, p), text = text}
    end
  end
  return {ok = true, params = out}
end

-- args: track, fx, parameter (all 1-based), value 0..1. For a parameter OSC does not carry.
function handlers.SetFxParam(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local ok = reaper.TrackFX_SetParamNormalized(tr, math.floor(args[2] or 1) - 1,
      math.floor(args[3] or 1) - 1, args[4] or 0)
  return {ok = ok}
end

-- args: track (1-based), plugin name as Reaper's browser lists it. Appends it to the chain and
-- answers with its 1-based slot, or ok = false when Reaper has no plugin by that name. Used by
-- tools/probe to load real third-party plugins into the rig; the desk does not add plugins yet.
function handlers.AddFx(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  reaper.Undo_BeginBlock()
  local fx = reaper.TrackFX_AddByName(tr, tostring(args[2] or ''), false, -1)
  reaper.Undo_EndBlock('dawlings: add FX', -1)
  if fx < 0 then return {ok = false, error = 'no such plugin'} end
  return {ok = true, fx = fx + 1, params = reaper.TrackFX_GetNumParams(tr, fx)}
end

-- args: track, fx (1-based), show. Opens the plugin's own window, floating, or closes it.
-- Answers with what the window's title says -- "<plugin> - Track <n>", how something outside
-- Reaper finds it -- and whether it was open already, so whoever opened it closes only what
-- they opened.
function handlers.ShowFx(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local fx = math.floor(args[2] or 1) - 1
  if fx < 0 or fx >= reaper.TrackFX_GetCount(tr) then return {ok = false, error = 'no such fx'} end
  local was_open = reaper.TrackFX_GetFloatingWindow(tr, fx) ~= nil
  reaper.TrackFX_Show(tr, fx, args[3] == false and 2 or 3)
  local _, name = reaper.TrackFX_GetFXName(tr, fx, '')
  local number = math.floor(reaper.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER'))
  return {
    ok = true,
    was_open = was_open,
    open = reaper.TrackFX_GetFloatingWindow(tr, fx) ~= nil,
    title = string.format('%s - Track %d', name, number),
  }
end

-- args: track, fx (1-based).
function handlers.DeleteFx(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  reaper.Undo_BeginBlock()
  local ok = reaper.TrackFX_Delete(tr, math.floor(args[2] or 1) - 1)
  reaper.Undo_EndBlock('dawlings: delete FX', -1)
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
    -- Sends as the desk numbers them: the first is [1], as /track/N/send/1 is on the wire.
    local sends = {}
    for s = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
      sends[#sends + 1] = {
        volume = reaper.GetTrackSendInfo_Value(tr, 0, s, 'D_VOL'),
        pan = reaper.GetTrackSendInfo_Value(tr, 0, s, 'D_PAN'),
      }
    end
    tracks[#tracks + 1] = {
      index = i + 1,
      sends = sends,
      volume = reaper.GetMediaTrackInfo_Value(tr, 'D_VOL'),
      pan = reaper.GetMediaTrackInfo_Value(tr, 'D_PAN'),
      mute = reaper.GetMediaTrackInfo_Value(tr, 'B_MUTE') > 0.5,
      solo = reaper.GetMediaTrackInfo_Value(tr, 'I_SOLO') > 0.5,
      arm = reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM') > 0.5,
      monitor = reaper.GetMediaTrackInfo_Value(tr, 'I_RECMON'),
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
    -- 40364, Options: Toggle metronome.
    metronome = reaper.GetToggleCommandState(40364) == 1,
    loop_start = loop_start, loop_end = loop_end,
    selection_start = sel_start, selection_end = sel_end,
    can_undo = reaper.Undo_CanUndo2(0) or '',
    can_redo = reaper.Undo_CanRedo2(0) or '',
    tracks = tracks,
  }
end

--- Set one of a track's numeric properties, the way a mouse in Reaper would. For checking that
-- a change made in REAPER reaches the desk, which the desk cannot test by writing it itself.
local SETTABLE = {D_VOL = true, D_PAN = true, B_MUTE = true, I_SOLO = true, I_RECARM = true, I_RECMON = true}
function handlers.SetTrackValue(args)
  local tr = track_from_osc(args[1])
  if not tr or not SETTABLE[args[2] or ''] then return {ok = false, error = 'no such track or key'} end
  reaper.SetMediaTrackInfo_Value(tr, args[2], args[3])
  return {ok = true}
end

-- Edit: Undo and Edit: Redo, served in line with the edits; see ReaperBackend.undo.
function handlers.Undo()
  reaper.Undo_DoUndo2(0)
  reaper.UpdateArrange()
  return {ok = true}
end

function handlers.Redo()
  reaper.Undo_DoRedo2(0)
  reaper.UpdateArrange()
  return {ok = true}
end

-- args: seconds, bpm, ramps (0 or 1), repeated: the whole tempo map, every marker of Reaper's
-- replaced, as one undo point. Positions come in seconds, worked out on dawlings's side along the
-- same map, because Reaper's own conversion would move with each marker as it is added.
function handlers.SetTempoMap(args)
  reaper.Undo_BeginBlock()
  for m = reaper.CountTempoTimeSigMarkers(0) - 1, 0, -1 do
    reaper.DeleteTempoTimeSigMarker(0, m)
  end
  for i = 1, #args - 2, 3 do
    reaper.SetTempoTimeSigMarker(0, -1, args[i], -1, -1, args[i + 1], 0, 0, (args[i + 2] or 0) > 0.5)
  end
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Tempo map', -1)
  return {ok = true}
end

-- The time signature's changes, as flat {quarter note, numerator, denominator}, the first at 0.
-- Reaper keeps a signature on a tempo marker: each marker's is cleared first, and one that only
-- held a signature (its tempo the one before it, not ramped into) goes; then each change is put
-- on the marker at its place, or a new one at the tempo there. A new marker inside a ramp breaks
-- the ramp in two. One undo point.
function handlers.SetTimeSignatures(args)
  reaper.Undo_BeginBlock()
  for m = reaper.CountTempoTimeSigMarkers(0) - 1, 0, -1 do
    local ok, timepos, _, _, bpm, num, _, linear = reaper.GetTempoTimeSigMarker(0, m)
    if ok and num > 0 then
      local before_ramps = false
      local before_bpm = nil
      if m > 0 then
        local _, _, _, _, pbpm, _, _, plinear = reaper.GetTempoTimeSigMarker(0, m - 1)
        before_ramps, before_bpm = plinear, pbpm
      end
      if m > 0 and not before_ramps and not linear and math.abs(before_bpm - bpm) < 0.0001 then
        reaper.DeleteTempoTimeSigMarker(0, m)
      else
        reaper.SetTempoTimeSigMarker(0, m, timepos, -1, -1, bpm, 0, 0, linear)
      end
    end
  end
  for i = 1, #args - 2, 3 do
    local time = reaper.TimeMap2_QNToTime(0, args[i])
    local num, den = math.floor(args[i + 1]), math.floor(args[i + 2])
    local found = -1
    for m = 0, reaper.CountTempoTimeSigMarkers(0) - 1 do
      local _, timepos = reaper.GetTempoTimeSigMarker(0, m)
      if math.abs(timepos - time) < 0.000001 then found = m end
    end
    if found >= 0 then
      local _, timepos, _, _, bpm, _, _, linear = reaper.GetTempoTimeSigMarker(0, found)
      reaper.SetTempoTimeSigMarker(0, found, timepos, -1, -1, bpm, num, den, linear)
    else
      reaper.SetTempoTimeSigMarker(0, -1, time, -1, -1, reaper.TimeMap_GetDividedBpmAtTime(time), num, den, false)
    end
  end
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Time signature', -1)
  return {ok = true}
end

-- args: where (from 1), name. A new track there, as Insert new track does: one undo point.
function handlers.InsertTrack(args)
  local at = math.max(1, math.min(math.floor(args[1] or 1), reaper.CountTracks(0) + 1))
  reaper.Undo_BeginBlock()
  reaper.InsertTrackAtIndex(at - 1, true)
  local tr = reaper.GetTrack(0, at - 1)
  if tr and (args[2] or '') ~= '' then
    reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', args[2], true)
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.Undo_EndBlock('Insert track', -1)
  return {ok = true}
end

-- args: track. Gone, with its items and the sends to it, as Remove tracks does.
function handlers.DeleteTrack(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  reaper.Undo_BeginBlock()
  reaper.DeleteTrack(tr)
  reaper.TrackList_AdjustWindows(false)
  reaper.Undo_EndBlock('Remove track', -1)
  return {ok = true}
end

-- args: track, name.
function handlers.RenameTrack(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  reaper.Undo_BeginBlock()
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', args[2] or '', true)
  reaper.Undo_EndBlock('Rename track', 1)
  return {ok = true}
end

-- args: track, red, green, blue (0-1). Reaper's custom colour, its flag set so it shows.
function handlers.SetTrackColour(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local function byte(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 0) * 255 + 0.5))) end
  reaper.Undo_BeginBlock()
  reaper.SetTrackColor(tr, reaper.ColorToNative(byte(args[2]), byte(args[3]), byte(args[4])))
  reaper.Undo_EndBlock('Set track color', 1)
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

function handlers.SelectAllItems()
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    for n = 0, reaper.CountTrackMediaItems(tr) - 1 do
      reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(tr, n), true)
    end
  end
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
  -- args[4], when another track: onto that one as well.
  local to = (args[4] or 0) > 0 and args[4] ~= args[1] and track_from_osc(args[4]) or nil
  reaper.Undo_BeginBlock()
  reaper.SetMediaItemInfo_Value(it, 'D_POSITION', math.max(0, args[3] or 0))
  if to then reaper.MoveMediaItemToTrack(it, to) end
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
    local locked = (math.floor(reaper.GetMediaItemInfo_Value(it, 'C_LOCK')) & 1) == 1
    if at > start and at < start + length and not locked then targets[#targets + 1] = it end
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

-- Every selected item deleted, one undo point, as Reaper's own Remove items.
function handlers.DeleteSelected()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return {ok = true, deleted = 0} end
  reaper.Undo_BeginBlock()
  local deleted = 0
  for n = count - 1, 0, -1 do
    local it = reaper.GetSelectedMediaItem(0, n)
    -- A locked item stays, as the desk's own delete leaves it.
    if (math.floor(reaper.GetMediaItemInfo_Value(it, 'C_LOCK')) & 1) == 0 then
      reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it)
      deleted = deleted + 1
    end
  end
  local result = edited('Remove items')
  result.deleted = deleted
  return result
end

-- Reaper's own Item: Duplicate items (41295): a copy straight after each selected item, the
-- copies selected. Its own undo point.
function handlers.DuplicateSelected()
  if reaper.CountSelectedMediaItems(0) == 0 then return {ok = true} end
  reaper.Main_OnCommand(41295, 0)
  reaper.UpdateArrange()
  return {ok = true}
end

-- args: seconds. Copies of the selected items, the earliest one's start put there, each on its own
-- track. Cloned through the item's state chunk with the GUIDs taken out, so Reaper numbers the
-- copies itself rather than holding two items that claim to be the same one.
function handlers.CopySelectedTo(args)
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return {ok = true} end
  local earliest = math.huge
  local picked = {}
  for n = 0, count - 1 do
    local it = reaper.GetSelectedMediaItem(0, n)
    picked[#picked + 1] = it
    earliest = math.min(earliest, reaper.GetMediaItemInfo_Value(it, 'D_POSITION'))
  end
  reaper.Undo_BeginBlock()
  for _, it in ipairs(picked) do
    local ok, chunk = reaper.GetItemStateChunk(it, '', false)
    if ok then
      chunk = chunk:gsub('\n%s*I?GUID %b{}', ''):gsub('\n%s*GUID %b{}', '')
      local tr = reaper.GetMediaItem_Track(it)
      local copy = reaper.AddMediaItemToTrack(tr)
      reaper.SetItemStateChunk(copy, chunk, false)
      reaper.SetMediaItemInfo_Value(copy, 'D_POSITION',
        math.max(0, args[1] or 0) + reaper.GetMediaItemInfo_Value(it, 'D_POSITION') - earliest)
      reaper.SetMediaItemSelected(copy, false)
    end
  end
  return edited('Copy items')
end

-- args: track, index, start, end. The item's edges moved with its contents left where they are
-- in the song: the take's start offset moves with the left edge, at the take's own rate.
function handlers.TrimItem(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  local start = math.max(0, args[3] or 0)
  local finish = args[4] or start
  if finish - start < 0.01 then return {ok = false, error = 'too short'} end
  reaper.Undo_BeginBlock()
  local moved = start - reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
  for t = 0, reaper.CountTakes(it) - 1 do
    local take = reaper.GetTake(it, t)
    if take then
      local rate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
      local offset = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offset + moved * rate)
    end
  end
  reaper.SetMediaItemInfo_Value(it, 'D_POSITION', start)
  reaper.SetMediaItemInfo_Value(it, 'D_LENGTH', finish - start)
  return edited('Trim item')
end

-- args: track, index, dB. The item's own volume, which Reaper keeps as a linear gain.
function handlers.SetItemGain(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  reaper.Undo_BeginBlock()
  reaper.SetMediaItemInfo_Value(it, 'D_VOL', 10 ^ ((args[3] or 0) / 20))
  return edited('Item volume')
end

-- args: track, index, 1 to mute, 0 to unmute.
function handlers.SetItemMuted(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  reaper.Undo_BeginBlock()
  reaper.SetMediaItemInfo_Value(it, 'B_MUTE', (args[3] or 0) > 0.5 and 1 or 0)
  return edited('Item mute')
end

-- args: track, index, 1 to lock, 0 to unlock. Reaper's own item lock (C_LOCK's first bit).
function handlers.SetItemLocked(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  reaper.Undo_BeginBlock()
  local flags = math.floor(reaper.GetMediaItemInfo_Value(it, 'C_LOCK'))
  flags = (args[3] or 0) > 0.5 and (flags | 1) or (flags & ~1)
  reaper.SetMediaItemInfo_Value(it, 'C_LOCK', flags)
  return edited('Item lock')
end

-- args: track, index, fade in, fade out, in seconds.
function handlers.SetItemFades(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  reaper.Undo_BeginBlock()
  reaper.SetMediaItemInfo_Value(it, 'D_FADEINLEN', math.max(0, args[3] or 0))
  reaper.SetMediaItemInfo_Value(it, 'D_FADEOUTLEN', math.max(0, args[4] or 0))
  return edited('Item fades')
end

-- Every note of every MIDI take of an item, through `change(take, ppq_on, ppq_off, pitch)`,
-- which answers the note's new on, off and pitch. Notes are rewritten unsorted, then sorted.
local function each_note(it, change)
  for t = 0, reaper.CountTakes(it) - 1 do
    local take = reaper.GetTake(it, t)
    if take and reaper.TakeIsMIDI(take) then
      local _, count = reaper.MIDI_CountEvts(take)
      for n = 0, count - 1 do
        local ok, sel, muted, ppq_on, ppq_off, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
        if ok then
          local on, off, p, v = change(take, ppq_on, ppq_off, pitch, vel)
          reaper.MIDI_SetNote(take, n, sel, muted, on, off, chan, p, v or vel, true)
        end
      end
      reaper.MIDI_Sort(take)
    end
  end
end

-- args: track, index, amount: added to every note's velocity, kept between 1 and 127.
function handlers.ShiftVelocity(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  local by = math.floor(args[3] or 0)
  reaper.Undo_BeginBlock()
  each_note(it, function(_, on, off, pitch, vel)
    return on, off, pitch, math.max(1, math.min(127, vel + by))
  end)
  return edited('Note velocity')
end

-- args: track, index, semitones.
function handlers.TransposeItem(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  local by = math.floor(args[3] or 0)
  reaper.Undo_BeginBlock()
  each_note(it, function(_, on, off, pitch)
    return on, off, math.max(0, math.min(127, pitch + by))
  end)
  return edited('Transpose notes')
end

-- args: track, index, grid in beats (quarter notes), strength 0-1. Against Reaper's own tempo
-- map; a note pulled before the item's start stops there, and keeps its length.
function handlers.QuantizeItem(args)
  local it = item_at(args)
  if not it then return {ok = false, error = 'no such item'} end
  local grid = math.max(1 / 32, args[3] or 1)
  local strength = math.max(0, math.min(1, args[4] or 1))
  local item_start = reaper.GetMediaItemInfo_Value(it, 'D_POSITION')
  reaper.Undo_BeginBlock()
  each_note(it, function(take, ppq_on, ppq_off, pitch)
    local on = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq_on)
    local qn = reaper.TimeMap_timeToQN(on)
    local target = reaper.TimeMap_QNToTime(math.floor(qn / grid + 0.5) * grid)
    local moved = math.max(on + (target - on) * strength, item_start)
    local new_on = reaper.MIDI_GetPPQPosFromProjTime(take, moved)
    return new_on, ppq_off + (new_on - ppq_on), pitch
  end)
  return edited('Quantize notes')
end

-- args: seconds, name. A marker, one undo point, as Insert marker does from Reaper's own menu --
-- but at the time given rather than at the edit cursor, which on a desk someone else is
-- driving is not where the person pressing MARK was listening.
function handlers.AddMarker(args)
  local at = math.max(0, args[1] or reaper.GetPlayPosition())
  reaper.Undo_BeginBlock()
  local index = reaper.AddProjectMarker2(0, false, at, 0, tostring(args[2] or ''), -1, 0)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Insert marker', -1)
  return {ok = index >= 0, index = index}
end

-- The marker (not region) at `at` seconds, to a millisecond: its enum index's number and colour.
local function marker_at(at)
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  for m = 0, marker_count + region_count - 1 do
    local ok, is_region, pos, _, _, number, colour = reaper.EnumProjectMarkers3(0, m)
    if ok ~= 0 and not is_region and math.abs(pos - (tonumber(at) or -1)) < 0.001 then
      return number, colour
    end
  end
  return nil
end

-- args: at, to (seconds), name. Renamed and moved in one undo point; an empty name is cleared.
function handlers.EditMarker(args)
  local number, colour = marker_at(args[1])
  if not number then return {ok = false, error = 'no marker there'} end
  local name = tostring(args[3] or '')
  reaper.Undo_BeginBlock()
  local ok = reaper.SetProjectMarker4(0, number, false, math.max(0, tonumber(args[2]) or 0), 0, name, colour,
    name == '' and 1 or 0)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Edit marker', -1)
  return {ok = ok}
end

-- args: at (seconds).
function handlers.RemoveMarker(args)
  local number = marker_at(args[1])
  if not number then return {ok = false, error = 'no marker there'} end
  reaper.Undo_BeginBlock()
  local ok = reaper.DeleteProjectMarker(0, number, false)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Remove marker', -1)
  return {ok = ok}
end

-- A guest's take, placed by song position. args, flat because the request decoder reads one
-- flat list: track (1-based, as OSC), start and end in project seconds, take name, note count,
-- then five numbers per note -- on and off in project seconds, pitch, velocity, channel.
-- Seconds rather than ticks on the wire, converted here with the take's own PPQ, so a project
-- with tempo changes places each note where the guest heard it rather than where a constant
-- tempo would have put it.
function handlers.InsertMidiTake(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local t0, t1 = args[2] or 0, args[3] or 0
  if t1 <= t0 then return {ok = false, error = 'empty take'} end
  local name = type(args[4]) == 'string' and args[4] or ''
  local count = math.floor(args[5] or 0)
  reaper.Undo_BeginBlock()
  local item = reaper.CreateNewMIDIItemInProj(tr, t0, t1, false)
  local take = item and reaper.GetActiveTake(item)
  if not take then
    reaper.Undo_EndBlock('Insert MIDI take', 4)
    return {ok = false, error = 'could not create a MIDI item'}
  end
  if name ~= '' then reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', name, true) end
  local placed = 0
  for n = 0, count - 1 do
    local at = 6 + n * 5
    local on, off = args[at], args[at + 1]
    local pitch, vel, chan = args[at + 2], args[at + 3], args[at + 4]
    if on and off and pitch and vel and chan then
      local ppq_on = reaper.MIDI_GetPPQPosFromProjTime(take, on)
      local ppq_off = reaper.MIDI_GetPPQPosFromProjTime(take, off)
      -- noSort: one sort at the end rather than one per note.
      if reaper.MIDI_InsertNote(take, false, false, ppq_on, math.max(ppq_off, ppq_on + 1),
          math.floor(chan), math.floor(pitch), math.floor(vel), true) then
        placed = placed + 1
      end
    end
  end
  reaper.MIDI_Sort(take)
  reaper.UpdateItemInProject(item)
  local result = edited('Insert MIDI take')
  result.notes = placed
  return result
end

-- A copy of a file, byte for byte, or false.
local function copy_file(from, to)
  local src = io.open(from, 'rb')
  if not src then return false end
  local data = src:read('*a')
  src:close()
  local dst = io.open(to, 'wb')
  if not dst then return false end
  dst:write(data)
  dst:close()
  return true
end

-- A guest's recorded take. args: track (1-based, as OSC), start in project seconds, the WAV's
-- absolute path on this machine, take name. A saved project gets its own copy of the file in
-- its media folder, the place Reaper puts its own recordings, so the project still opens once
-- the desk's copy is gone; an unsaved one, which has no folder yet, uses the file where it is.
function handlers.InsertAudioTake(args)
  local tr = track_from_osc(args[1])
  if not tr then return {ok = false, error = 'no such track'} end
  local path = type(args[3]) == 'string' and args[3] or ''
  if path == '' or not reaper.file_exists(path) then return {ok = false, error = 'no such file'} end
  local _, project_file = reaper.EnumProjects(-1)
  if project_file and project_file ~= '' then
    local folder = reaper.GetProjectPathEx(0)
    reaper.RecursiveCreateDirectory(folder, 0)
    local name = path:match('([^/\\]+)$')
    local kept = folder .. '/' .. name
    if copy_file(path, kept) then path = kept end
  end
  reaper.Undo_BeginBlock()
  local item = reaper.AddMediaItemToTrack(tr)
  local take = reaper.AddTakeToMediaItem(item)
  local source = reaper.PCM_Source_CreateFromFile(path)
  reaper.SetMediaItemTake_Source(take, source)
  local length = reaper.GetMediaSourceLength(source)
  reaper.SetMediaItemInfo_Value(item, 'D_POSITION', math.max(0, args[2] or 0))
  reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', length)
  local name = type(args[4]) == 'string' and args[4] or ''
  if name ~= '' then reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', name, true) end
  reaper.UpdateItemInProject(item)
  -- Build any missing peaks, so the item has a waveform in Reaper's own window at once.
  reaper.Main_OnCommand(40047, 0)
  local result = edited('Insert audio take')
  result.path = path
  result.length = length
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
reaper.ShowConsoleMsg('dawlings bridge running: ' .. bridge_dir .. '\n')
tick()
