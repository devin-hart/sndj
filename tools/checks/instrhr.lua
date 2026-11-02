-- instrhr.lua — hi-res INSTR panel (instrhr.asm): with HI-RES on, INSTR
-- gets the waveform + envelope graphics (tilemap entries, a drawn bitmap
-- in $7F:0000, uploaded to VRAM by the NMI) and redraws them when the
-- instrument changes; with it off INSTR stays classic. FR_HIRES=0 runs the
-- classic half. Fixture shared with frame.lua; FR_OUT writes screenshots.
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
  {20, function() fill(); poke(OPT_HIRES, HIRES)
    local I = 0x2400
    poke(I + 2*16 + 2, 0x08 | 0x50); poke(I + 2*16 + 3, (3 << 5) | 0x14)   -- instr 2: A8 D5 SL3 SR20
    poke(I + 3*16, 2); poke(I + 3*16 + 1, 1)                              -- instr 3: WAV bank 1
    for i = 0, 31 do poke(0x3100 + 32 + i, math.floor(7.5 + 7.5 * math.sin(i / 32 * 2 * math.pi))) end
  end},
  {24, function() pad = { a = true } end}, {27, function() pad = { a = true, right = true } end}, {30, function() pad = {} end},
  {34, function() pad = { a = true } end}, {37, function() pad = { a = true, right = true } end}, {40, function() pad = {} end},
  {44, function() pad = { a = true } end}, {47, function() pad = { a = true, right = true } end}, {50, function() pad = {} end},
  {85, function()
    check(wram(0x0C) == 4, "A+right x3 reaches INSTR")
    check(HIRES == 0 or wram(0x0D66) == 0x80, "INSTR is hi-res when OPTIONS HI-RES is on")
    check(HIRES == 1 or wram(0x0D66) == 0, "INSTR stays classic when it is off")
    if HIRES == 1 then
      local w = wram(0x0400 + 9 * 64 + 17 * 2) + wram(0x0400 + 9 * 64 + 17 * 2 + 1) * 256
      check(w == (0x3800 | 400), string.format("waveform tile entry at row 9 col 34 ($%04X)", w))
      local nz, same = 0, true
      for i = 0, 2687 do
        local b = emu.read(0x10000 + i, W)
        if b ~= 0 then nz = nz + 1 end
        if emu.read(0x4C80 * 2 + i, emu.memType.snesVideoRam) ~= b then same = false end
      end
      check(nz > 200, "waveform/envelope bitmap drawn (" .. nz .. " non-zero bytes)")
      check(same, "the NMI uploaded the whole bitmap to VRAM")
    end
    shot("instr1") end},
  -- B+right on the cursor field (INSTR number) moves to instrument 2:
  -- a different sample and ADSR must redraw and re-upload
  {87, function() pad = { y = true } end}, {89, function() pad = { y = true, down = true } end}, {91, function() pad = {} end},
  {125, function()
    if HIRES == 1 then
      local same = true
      for i = 0, 2687 do
        if emu.read(0x4C80 * 2 + i, emu.memType.snesVideoRam) ~= emu.read(0x10000 + i, W) then same = false end
      end
      check(same, "instrument change re-uploaded the panel")
      local w = 0
      for i = 1536, 2687 do if emu.read(0x10000 + i, W) ~= 0 then w = w + 1 end end
      check(w > 20, "envelope drawn for A8 D5 SL3 SR20 (" .. w .. " bytes)")
    end
    shot("instr2") end},
  {127, function() pad = { y = true } end}, {129, function() pad = { y = true, down = true } end}, {131, function() pad = {} end},
  {165, function()
    if HIRES == 1 then
      check(wram(0x0DE0 + 1 + 1) == 2, "WAV instrument keyed as type 2")
    end
    shot("instr3")
    print(fails == 0 and "ALL PASS instrhr.lua" or ("FAILED instrhr.lua: " .. fails)); emu.stop(fails) end},
}
emu.addEventCallback(function()
  if not booted then if wram(1) == 0x5D then booted = true end; return end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end
  for _, s in ipairs(plan) do if s[1] == frames then s[2]() end end
end, emu.eventType.endFrame)
