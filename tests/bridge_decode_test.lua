-- The bridge's request decoder, run outside Reaper: tools/verify.sh runs this when a Lua is
-- installed. The decoder is lifted out of reaper/reaper3d_bridge.lua by its text, because the
-- bridge itself talks to Reaper the moment it loads.
local here = arg[0]:match('(.*/)') or './'
local f = assert(io.open(here .. '../reaper/reaper3d_bridge.lua', 'r'))
local text = f:read('*a')
f:close()
local from = text:find('local function decode_args', 1, true)
local to = text:find('-- Reaper indexes tracks from 0', 1, true)
local chunk = text:sub(from, to - 1) .. '\nreturn decode_request'
local decode_request = assert(load(chunk))()

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
print(string.format('[bridge] %d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
