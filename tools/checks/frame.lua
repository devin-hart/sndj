-- frame.lua — FRAME editor (framescr.asm): X on PHRASE opens it, the
-- cursor walks across tracks and into the next chain step, a B tap edits
-- the cursor track's phrase, Y+UP pages back, X returns to PHRASE on the
-- cursor track's phrase. FR_HIRES=0 runs it in the classic 3-track view;
-- FR_OUT=<prefix> also writes screenshots.
--
-- Non-frozen addresses (from src/ram.inc): $0D8D opt_hires, $0D8E fr_row,
-- $0D8F fr_step, $0D90 fr_trk.
local W = emu.memType.snesWorkRam
local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local out = os.getenv("FR_OUT")
local HIRES = tonumber(os.getenv("FR_HIRES") or "1")
local OPT_HIRES, FR_TRK, FR_ROW, FR_STEP = 0x0D8D, 0x0D90, 0x0D8E, 0x0D8F
local frames, booted, pad = 0, false, {}
local fails = 0
local function check(c, m) print((c and "PASS " or "FAIL ") .. m); if not c then fails = fails + 1 end end
emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)
emu.write(0x0007, 0, emu.memType.snesSaveRam)
local function shot(name)
  if not out then return end
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
local t0
local plan = {
  {20, function() fill(); poke(OPT_HIRES, HIRES) end},
  -- SONG -> CHAIN -> PHRASE (A held + right, twice)
  {24, function() pad = { a = true } end}, {27, function() pad = { a = true, right = true } end}, {30, function() pad = {} end},
  {34, function() pad = { a = true } end}, {37, function() pad = { a = true, right = true } end}, {40, function() pad = {} end},
  {44, function() print("ui_mode " .. wram(0x0C)); pad = { x = true } end}, {46, function() pad = {} end},
  {60, function() check(wram(0x0C) == 16, "X on PHRASE opens FRAME (ui_mode " .. wram(0x0C) .. ")"); shot("enter") end},
  -- walk right 5 columns: track 1 col 0 -> track 2 col 1, back 1, down 2
  {62, function() pad = { right = true } end}, {64, function() pad = {} end},
  {66, function() pad = { right = true } end}, {68, function() pad = {} end},
  {70, function() pad = { right = true } end}, {72, function() pad = {} end},
  {74, function() pad = { right = true } end}, {76, function() pad = {} end},
  {78, function() pad = { right = true } end}, {80, function() pad = {} end},
  {82, function() pad = { down = true } end}, {84, function() pad = {} end},
  {86, function() pad = { down = true } end}, {88, function() pad = {} end},
  {90, function() check(wram(FR_TRK) == 1, "cursor walked to track 2 (" .. wram(FR_TRK) .. ")")
                  check(wram(0x0F) == 2 and wram(0x19) == 1, "row 02, instrument column") end},
  -- B tap: insert the last note into track 2's phrase (0x11) row 2
  {92, function() pad = { b = true } end}, {94, function() pad = {} end},
  {100, function() check(wram(ph(0x11, 2) + 1) ~= 0xFF, "B tap wrote track 2's phrase 11 row 02 (instr " .. wram(ph(0x11, 2) + 1) .. ")"); shot("edit") end},
  -- down 14 rows to cross into step 1
  {102, function() pad = { down = true } end},
  {162, function() pad = {} end},
  {166, function() check(wram(FR_STEP) == 1, "walked down into chain step 1 (step " .. wram(FR_STEP) .. ", row " .. wram(0x0F) .. ")"); shot("step1") end},
  {168, function() pad = { y = true } end}, {170, function() pad = { y = true, up = true } end}, {172, function() pad = {} end},
  {176, function() check(wram(FR_STEP) == 0, "Y+UP pages back a step") end},
  {178, function() pad = { up = true } end}, {180, function() pad = {} end},
  {182, function() pad = { start = true } end}, {184, function() pad = {} end},
  {230, function() shot("play") end},
  -- B held + Y + UP must not reach PHRASE's Y+UP/DOWN path (it paints
  -- the classic "PHRASE xx" header over FRAME's title line)
  {236, function() pad = { b = true } end}, {238, function() pad = { b = true, y = true } end},
  {240, function() pad = { b = true, y = true, up = true } end}, {242, function() pad = {} end},
  {244, function()
    local w = wram(0x0E00 + 64 + 6) + wram(0x0E00 + 64 + 7) * 256   -- x7 y1, odd layer
    if (wram(0x0D66) & 0x80) == 0 then w = (wram(0x0400 + 64 + 14) + wram(0x0400 + 64 + 15) * 256) * 2 end
    check(((w & 0x3FF) >> 1) == string.byte("R") - 32, "B+Y+UP leaves FRAME's title intact")
    pad = { x = true } end}, {246, function() pad = {} end},
  {257, function() check(wram(0x0C) == 1, "X returns to PHRASE"); check(wram(0x18) == 0x11, "PHRASE opens on the cursor track's phrase (" .. string.format("%02X", wram(0x18)) .. ")"); shot("back")
                   print(fails == 0 and "ALL PASS frame.lua" or ("FAILED frame.lua: " .. fails)); emu.stop(fails) end},
}
emu.addEventCallback(function()
  if not booted then if wram(1) == 0x5D then booted = true end; return end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end
  for _, s in ipairs(plan) do if s[1] == frames then s[2]() end end
end, emu.eventType.endFrame)
