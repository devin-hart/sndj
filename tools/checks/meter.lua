-- meter.lua — verify G3 per-voice level meters on hi-res SONG and FRAME

local W = emu.memType.snesWorkRam
local S = emu.memType.snesSaveRam
local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end

local frames, booted, pad = 0, false, {}
local fails = 0
local function check(c, m)
  print((c and "PASS " or "FAIL ") .. m)
  if not c then fails = fails + 1 end
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

-- Save original SRAM $000D and restore on exit
local orig_sram = emu.read(0x000D, S)
local function finish(code)
  if orig_sram ~= nil then
    emu.write(0x000D, orig_sram, S)
  end
  emu.stop(code)
end

-- Dynamically locate apu_update@done from build/sndj.sym
local apu_done_addr = 0x808C60
local sym_file = io.open("build/sndj.sym", "r")
if sym_file then
  for line in sym_file:lines() do
    local b, a = line:match("^(%x%x):(%x%x%x%x)%s+apu_update@done")
    if a then
      apu_done_addr = (tonumber(b, 16) << 16) | tonumber(a, 16)
      break
    end
  end
  sym_file:close()
end

local mock_envx = nil
emu.addMemoryCallback(function(addr)
  if mock_envx then
    for i = 0, 7 do
      poke(0x00F1 + i, mock_envx[i + 1] or 0)
    end
  end
end, emu.callbackType.exec, apu_done_addr, apu_done_addr)

local function word(a) return emu.read(a, W) + emu.read(a + 1, W) * 256 end

local function hr_glyph(x, y)
  local off = y * 64 + (x >> 1) * 2
  local g
  if x % 2 == 0 then
    local w = word(0x0400 + off)
    g = ((w & 0x3FF) - 1) // 2
  else
    local w = word(0x0E00 + off)
    g = (w & 0x3FF) // 2
  end
  return g
end

local GLYPH_BLOCK   = 64
local GLYPH_BLOCK34 = 65
local GLYPH_BLOCK12 = 66
local GLYPH_BLOCK14 = 67

local plan = {
  -- 1. Boot onto classic SONG. Turn on HI-RES via opt_hires = 1 and re-entering SONG via OPTIONS
  {20, function()
    check(wram(0x000C) == 3, "SONG screen active (ui_mode " .. wram(0x000C) .. ")")
    -- Seed chain 0 at track 0 row 0 so we can navigate to FRAME later
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x0D8D, 1)          -- opt_hires = 1
    pad = { a = true }
  end},
  {22, function() pad = { a = true, up = true } end},
  {24, function() pad = {} end},
  {30, function()
    check(wram(0x000C) == 10, "on OPTIONS screen (ui_mode " .. wram(0x000C) .. ")")
    pad = { a = true }
  end},
  {32, function() pad = { a = true, down = true } end},
  {34, function() pad = {} end},

  -- 2. On hi-res SONG screen (stopped): all meters should be 0 (blank/space)
  {45, function()
    check(wram(0x000C) == 3, "back on SONG screen (ui_mode " .. wram(0x000C) .. ")")
    check(wram(0x0D66) == 0x80, "SONG is in hi-res mode (ui_hires == 128)")

    local all_zero = true
    for t = 0, 7 do
      local x = 5 + t * 4
      local g = hr_glyph(x, 4)
      if g ~= 0 and g ~= 95 and g ~= -1 then
        all_zero = false
        print("Track " .. t .. " meter not zero when stopped: glyph " .. g)
      end
    end
    check(all_zero, "SONG: all 8 meters are zero when stopped")

    -- Set mock playing and mock envx levels
    poke(0x0016, 1)          -- eng_playing = 1
    mock_envx = { 16, 48, 80, 112, 0, 127, 32, 1 }
  end},

  -- 3. Check SONG meters during playback
  {48, function()
    local g0 = hr_glyph(5 + 0 * 4, 4)
    check(g0 == GLYPH_BLOCK14, "SONG track 0 meter (16): " .. g0 .. " == " .. GLYPH_BLOCK14)
    local g1 = hr_glyph(5 + 1 * 4, 4)
    check(g1 == GLYPH_BLOCK12, "SONG track 1 meter (48): " .. g1 .. " == " .. GLYPH_BLOCK12)
    local g2 = hr_glyph(5 + 2 * 4, 4)
    check(g2 == GLYPH_BLOCK34, "SONG track 2 meter (80): " .. g2 .. " == " .. GLYPH_BLOCK34)
    local g3 = hr_glyph(5 + 3 * 4, 4)
    check(g3 == GLYPH_BLOCK, "SONG track 3 meter (112): " .. g3 .. " == " .. GLYPH_BLOCK)
    local g4 = hr_glyph(5 + 4 * 4, 4)
    check(g4 == 0 or g4 == 95 or g4 == -1, "SONG track 4 meter (0): empty (glyph " .. g4 .. ")")
    local g5 = hr_glyph(5 + 5 * 4, 4)
    check(g5 == GLYPH_BLOCK, "SONG track 5 meter (127): " .. g5 .. " == " .. GLYPH_BLOCK)

    -- Stop playback: verify meters drop back to zero
    poke(0x0016, 0)          -- eng_playing = 0
    mock_envx = nil
  end},

  -- 4. Verify meters drop to zero after stop
  {51, function()
    local all_zero = true
    for t = 0, 7 do
      local x = 5 + t * 4
      local g = hr_glyph(x, 4)
      if g ~= 0 and g ~= 95 and g ~= -1 then
        all_zero = false
        print("Track " .. t .. " meter not zero after stop: glyph " .. g)
      end
    end
    check(all_zero, "SONG: all 8 meters return to zero when stopped")

    -- Navigate to FRAME: SONG -> CHAIN (A+RIGHT) -> PHRASE (A+RIGHT) -> FRAME (X)
    pad = { a = true }
  end},
  {53, function() pad = { a = true, right = true } end},
  {55, function() pad = {} end},
  {60, function()
    check(wram(0x000C) == 2, "on CHAIN screen (ui_mode " .. wram(0x000C) .. ")")
    pad = { a = true }
  end},
  {62, function() pad = { a = true, right = true } end},
  {64, function() pad = {} end},
  {70, function()
    check(wram(0x000C) == 1, "on PHRASE screen (ui_mode " .. wram(0x000C) .. ")")
    pad = { x = true }
  end},
  {72, function() pad = {} end},

  -- 5. On FRAME screen: test level meters
  {85, function()
    check(wram(0x000C) == 16, "on FRAME screen (ui_mode " .. wram(0x000C) .. ")")

    -- Stopped: all meters at x = 7 + t * 7, y = 4 should be zero
    local all_zero = true
    for t = 0, 7 do
      local x = 7 + t * 7
      local g = hr_glyph(x, 4)
      if g ~= 0 and g ~= 95 and g ~= -1 then
        all_zero = false
        print("FRAME Track " .. t .. " meter not zero when stopped: glyph " .. g)
      end
    end
    check(all_zero, "FRAME: all 8 meters are zero when stopped")

    -- Set mock playing and mock envx
    poke(0x0016, 1)
    mock_envx = { 100, 70, 0, 0, 0, 0, 40, 20 }
  end},

  -- 6. Verify FRAME meters during playback
  {88, function()
    local g0 = hr_glyph(7 + 0 * 7, 4)
    check(g0 == GLYPH_BLOCK, "FRAME track 0 meter (100): " .. g0 .. " == " .. GLYPH_BLOCK)
    local g1 = hr_glyph(7 + 1 * 7, 4)
    check(g1 == GLYPH_BLOCK34, "FRAME track 1 meter (70): " .. g1 .. " == " .. GLYPH_BLOCK34)
    local g6 = hr_glyph(7 + 6 * 7, 4)
    check(g6 == GLYPH_BLOCK12, "FRAME track 6 meter (40): " .. g6 .. " == " .. GLYPH_BLOCK12)
    local g7 = hr_glyph(7 + 7 * 7, 4)
    check(g7 == GLYPH_BLOCK14, "FRAME track 7 meter (20): " .. g7 .. " == " .. GLYPH_BLOCK14)

    -- Stop playback
    poke(0x0016, 0)
    mock_envx = nil
  end},

  -- 7. Verify FRAME meters return to zero
  {91, function()
    local all_zero = true
    for t = 0, 7 do
      local x = 7 + t * 7
      local g = hr_glyph(x, 4)
      if g ~= 0 and g ~= 95 and g ~= -1 then
        all_zero = false
        print("FRAME Track " .. t .. " meter not zero after stop: glyph " .. g)
      end
    end
    check(all_zero, "FRAME: all 8 meters return to zero when stopped")

    print(fails == 0 and "ALL PASS meter.lua" or ("FAILED meter.lua: " .. fails))
    finish(fails)
  end},
}

emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end
  for _, s in ipairs(plan) do
    if s[1] == frames then s[2]() end
  end
end, emu.eventType.endFrame)
