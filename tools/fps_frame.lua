-- fps_frame.lua — main-loop iterations per 120 frames on the FRAME editor
-- (hold RIGHT, hold DOWN across chain steps, B+UP nudge, idle; playing).
-- FR_HIRES=1 (default) or 0 picks the layout. Run directly with
--   Mesen --testrunner build\sndj.sfc tools\fps_frame.lua
-- (Written by Claude; derived from tools/checks/frame.lua.)
-- frame.lua: FRAME editor smoke test + screenshots (hi-res and classic)
local W = emu.memType.snesWorkRam
local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local out = os.getenv("FR_OUT") or "/tmp/fr_"
local HIRES = tonumber(os.getenv("FR_HIRES") or "1")
local OPT_HIRES, FR_TRK, FR_ROW, FR_STEP = 0x0D8D, 0x0D90, 0x0D8E, 0x0D8F
local frames, booted, pad = 0, false, {}
local fails = 0
local function check(c, m) print((c and "PASS " or "FAIL ") .. m); if not c then fails = fails + 1 end end
emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)
emu.write(0x0007, 0, emu.memType.snesSaveRam)
local function shot(name)
  local png = emu.takeScreenshot(); local f = io.open(out .. name .. ".png", "wb"); f:write(png); f:close()
end
local function ph(p, r) return 0x4300 + p * 64 + r * 4 end
local function fill()
  for t = 0, 7 do for r = 0, 127 do poke(0x2000 + t * 128 + r, 0xFF) end end
  local prog = {{49,53,56,25},{46,49,53,22},{42,46,49,18},{44,48,51,20}}
  for t = 0, 3 do
    poke(0x2000 + t * 128, t)                 -- song row 0: chain t
    for s = 0, 15 do poke(0x3700 + t * 32 + s * 2, 0xFF); poke(0x3700 + t * 32 + s * 2 + 1, 0) end
    poke(0x3700 + t * 32, 0x10 + t)           -- step 0
    poke(0x3700 + t * 32 + 2, 0x20 + t)       -- step 1
    for _, p in ipairs({0x10 + t, 0x20 + t}) do
      for r = 0, 15 do poke(ph(p, r), 0); poke(ph(p, r) + 1, 0xFF); poke(ph(p, r) + 2, 0); poke(ph(p, r) + 3, 0) end
      for b = 0, 3 do
        poke(ph(p, b * 4), prog[b + 1][t + 1]); poke(ph(p, b * 4) + 1, t == 3 and 5 or 1)
        if t == 3 then poke(ph(p, b * 4 + 2), prog[b + 1][t + 1] + 12); poke(ph(p, b * 4 + 2) + 1, 5) end
      end
    end
  end
  poke(ph(0x10, 0) + 2, 22); poke(ph(0x10, 0) + 3, 0x34)     -- V34 on track 1 row 0
  poke(ph(0x13, 14) + 2, 11); poke(ph(0x13, 14) + 3, 0x02)   -- K02 on track 4
  -- track 6 uses track 1's phrase at step 0 (a shared phrase)
  poke(0x2000 + 5 * 128, 4); for s = 0, 15 do poke(0x3700 + 4 * 32 + s * 2, 0xFF) end
  poke(0x3700 + 4 * 32, 0x10)
end
local iters = 0
emu.addMemoryCallback(function(addr, value) if value == 0 then iters = iters + 1 end end, emu.callbackType.write, 0x0000, 0x0000, emu.cpuType.snes, W)
local t0
local plan = {
  {20, function() fill(); poke(OPT_HIRES, HIRES) end},
  -- SONG -> CHAIN -> PHRASE (A held + right, twice)
  {24, function() pad = { a = true } end}, {27, function() pad = { a = true, right = true } end}, {30, function() pad = {} end},
  {34, function() pad = { a = true } end}, {37, function() pad = { a = true, right = true } end}, {40, function() pad = {} end},
  {44, function() print("ui_mode " .. wram(0x0C)); pad = { x = true } end}, {46, function() pad = {} end},
  {60, function() check(wram(0x0C) == 16, "X on PHRASE opens FRAME (ui_mode " .. wram(0x0C) .. ")"); shot("enter") end},
  {62, function() pad = { start = true } end}, {64, function() pad = {} end},
  {70, function() iters = 0; pad = { right = true } end},
  {190, function() print(string.format("RESULT frame_hold_right %d", iters)); pad = {} end},
  {200, function() iters = 0; pad = { down = true } end},
  {320, function() print(string.format("RESULT frame_hold_down %d step=%d", iters, wram(FR_STEP))); pad = {} end},
  {330, function() iters = 0; pad = { b = true } end}, {334, function() pad = { b = true, up = true } end},
  {450, function() print(string.format("RESULT frame_B_up_nudge %d", iters)); pad = {} end},
  {460, function() iters = 0 end},
  {580, function() print(string.format("RESULT frame_idle_playing %d", iters)); emu.stop(0) end},
}
emu.addEventCallback(function()
  if not booted then if wram(1) == 0x5D then booted = true end; return end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end
  for _, s in ipairs(plan) do if s[1] == frames then s[2]() end end
end, emu.eventType.endFrame)
