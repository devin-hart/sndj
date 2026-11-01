-- fps.lua — main-loop iterations per 120 emulated frames, per screen
-- (120 = a steady 60 fps). Not a pass/fail check: run it directly with
--   Mesen --testrunner build\sndj.sfc tools\fps.lua
-- and compare the RESULT lines before/after a change. Fills a busy
-- 8-track song, then measures SONG stopped/playing, CHAIN, PHRASE,
-- INSTR and LIVE while playing. (Written by Claude.)
-- Counts writes of 0 to frame_flag ($0000): one per main_loop pass.
local W = emu.memType.snesWorkRam
local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local frames, booted, pad = 0, false, {}
local iters = 0
emu.addMemoryCallback(function(addr, value) if value == 0 then iters = iters + 1 end end,
  emu.callbackType.write, 0x0000, 0x0000, emu.cpuType.snes, W)
emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)
local function busy_song()
  for t = 0, 7 do
    for r = 0, 15 do poke(0x2000 + t * 128 + r, t * 4 + (r % 4)) end   -- grid
  end
  for c = 0, 31 do
    for s = 0, 15 do poke(0x3700 + c * 32 + s * 2, (c * 3 + s) % 64); poke(0x3700 + c * 32 + s * 2 + 1, 0) end
  end
  for p = 0, 63 do
    for r = 0, 15 do
      local o = 0x4300 + p * 64 + r * 4
      poke(o, 25 + ((p + r) % 48)); poke(o + 1, p % 4)
      poke(o + 2, (r % 2 == 0) and 22 or 0); poke(o + 3, 0x34)          -- V34 vibrato
    end
  end
end
local plan = {
  {17, function() pad = {} end},
  {30, function() busy_song() end},
  {60, function() iters = 0 end}, {180, function() print(string.format("RESULT song_stopped %d", iters)) end},
  {181, function() pad = { start = true } end}, {184, function() pad = {}; end},
  {200, function() iters = 0 end}, {320, function() print(string.format("RESULT song_playing %d play=%d", iters, wram(0x16))) end},
  {321, function() pad = { a = true } end}, {326, function() pad = { a = true, right = true } end}, {330, function() pad = {} end},
  {340, function() iters = 0 end}, {460, function() print(string.format("RESULT mode%d_playing %d", wram(0x0C), iters)) end},
  {461, function() pad = { a = true } end}, {466, function() pad = { a = true, right = true } end}, {470, function() pad = {} end},
  {480, function() iters = 0 end}, {600, function() print(string.format("RESULT mode%d_playing %d", wram(0x0C), iters)) end},
  {601, function() pad = { a = true } end}, {606, function() pad = { a = true, right = true } end}, {610, function() pad = {} end},
  {620, function() iters = 0 end}, {740, function() print(string.format("RESULT mode%d_playing %d", wram(0x0C), iters)) end},
  {741, function() pad = { select = true } end}, {744, function() pad = {} end},
  {760, function() iters = 0 end}, {880, function() print(string.format("RESULT mode%d_playing %d", wram(0x0C), iters)); emu.stop(0) end},
}
emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  for _, s in ipairs(plan) do if s[1] == frames then s[2]() end end
end, emu.eventType.endFrame)
