-- Builds the live rig's session: forty tracks, so banking is exercised (the OSC bank is 64
-- wide and the desk pages by its own width), with real audio on them, folders, colours, a few
-- stock Cockos plugins with real parameters, sends, markers and a loop. Run once by
-- tools/reaper_rig.sh, which then saves it; every later run opens the saved project.

local media = reaper.GetResourcePath() .. '/rig_media/'
local stems = { 'kick', 'snare', 'hat', 'bass', 'pad', 'lead', 'vox', 'gtr' }
local names = {
  'DRUMS', 'Kick In', 'Kick Out', 'Snare Top', 'Snare Bot', 'Hat', 'Tom 1', 'Tom 2', 'OH L', 'OH R',
  'BASS', 'Bass DI', 'Bass Amp', 'GTRS', 'Gtr L', 'Gtr R', 'Gtr Lead', 'Acoustic',
  'KEYS', 'Piano', 'Rhodes', 'Pad', 'Synth Lead', 'Arp',
  'VOX', 'Lead Vox', 'Vox Dbl', 'Harm 1', 'Harm 2', 'BV Low', 'BV High', 'Adlib',
  'FX', 'Riser', 'Impact', 'Reverse', 'Verb Rtn', 'Delay Rtn', 'Room Rtn', 'Print',
}
local folders = { [1] = true, [11] = true, [14] = true, [19] = true, [25] = true, [33] = true }
local stem_for = function(i)
  local n = names[i]
  if n:find('Kick') then return 'kick' end
  if n:find('Snare') or n:find('Tom') or n:find('Impact') then return 'snare' end
  if n:find('Hat') or n:find('OH') or n:find('Room') then return 'hat' end
  if n:find('Bass') then return 'bass' end
  if n:find('Pad') or n:find('Piano') or n:find('Rhodes') or n:find('Verb') or n:find('Riser') then return 'pad' end
  if n:find('Lead') or n:find('Arp') or n:find('Delay') then return 'lead' end
  if n:find('Vox') or n:find('Harm') or n:find('BV') or n:find('Adlib') then return 'vox' end
  return 'gtr'
end

reaper.Main_OnCommand(40859, 0) -- new project tab
reaper.SetCurrentBPM(0, 120, false)
local palette = { 0xE05A5A, 0xE0A04A, 0xD8D050, 0x6AC46A, 0x4AB0D8, 0x8A6AE0 }
local colour_i = 0
for i = 1, #names do
  reaper.InsertTrackAtIndex(i - 1, true)
  local tr = reaper.GetTrack(0, i - 1)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', names[i], true)
  if folders[i] then colour_i = colour_i + 1 end
  local c = palette[(colour_i - 1) % #palette + 1]
  reaper.SetTrackColor(tr, reaper.ColorToNative((c >> 16) & 255, (c >> 8) & 255, c & 255))
end
-- Folder structure: each folder parent opens, the track before the next parent closes.
for i = 1, #names do
  local tr = reaper.GetTrack(0, i - 1)
  if folders[i] then
    reaper.SetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH', 1)
  elseif folders[i + 1] or i == #names then
    reaper.SetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH', -1)
  end
end
-- Audio on every non-folder track, laid out in sections so the timeline has an arrangement.
local sections = { { 0, 16 }, { 16, 48 }, { 48, 64 }, { 64, 96 }, { 96, 112 } }
for i = 1, #names do
  if not folders[i] then
    local tr = reaper.GetTrack(0, i - 1)
    for s, sec in ipairs(sections) do
      if (i + s) % 3 ~= 0 or s == 2 or s == 4 then
        reaper.SetOnlyTrackSelected(tr)
        reaper.SetEditCurPos(sec[1], false, false)
        reaper.InsertMedia(media .. stem_for(i) .. '.wav', 0)
        local item = reaper.GetTrackMediaItem(tr, reaper.CountTrackMediaItems(tr) - 1)
        reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', sec[2] - sec[1])
        reaper.SetMediaItemInfo_Value(item, 'B_LOOPSRC', 1)
      end
    end
  end
end
-- Plugins: stock Cockos ones only, so the rig works on any install.
local fx = {
  ['Kick In'] = { 'ReaEQ', 'ReaComp' }, ['Snare Top'] = { 'ReaEQ', 'ReaGate' },
  ['Bass DI'] = { 'ReaComp' }, ['Lead Vox'] = { 'ReaEQ', 'ReaComp', 'ReaDelay' },
  ['Verb Rtn'] = { 'ReaVerbate' }, ['Delay Rtn'] = { 'ReaDelay' }, ['Gtr L'] = { 'ReaEQ' },
}
for i = 1, #names do
  local chain = fx[names[i]]
  if chain then
    local tr = reaper.GetTrack(0, i - 1)
    for _, name in ipairs(chain) do reaper.TrackFX_AddByName(tr, name, false, -1) end
  end
end
-- Sends to the returns.
local function idx(n) for i = 1, #names do if names[i] == n then return i - 1 end end end
reaper.CreateTrackSend(reaper.GetTrack(0, idx('Lead Vox')), reaper.GetTrack(0, idx('Verb Rtn')))
reaper.CreateTrackSend(reaper.GetTrack(0, idx('Lead Vox')), reaper.GetTrack(0, idx('Delay Rtn')))
reaper.CreateTrackSend(reaper.GetTrack(0, idx('Snare Top')), reaper.GetTrack(0, idx('Verb Rtn')))
-- Arrangement markers.
local labels = { 'INTRO', 'VERSE 1', 'CHORUS 1', 'VERSE 2', 'OUTRO' }
for s, sec in ipairs(sections) do reaper.AddProjectMarker(0, false, sec[1], 0, labels[s], s) end
reaper.GetSet_LoopTimeRange(true, true, 16, 32, false)
reaper.SetEditCurPos(0, true, false)
reaper.Main_SaveProjectEx(0, reaper.GetResourcePath() .. '/rig_session/rig.RPP', 0)
