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

-- Dynamically locate symbols from build/sndj.sym
local info = emu.getRomInfo and emu.getRomInfo() or nil
local sym_path = info and info.path:gsub("%.sfc$", ".sym") or "build/sndj.sym"
local rom_path = info and info.path or "build/sndj.sfc"

local apu_done_addr = 0x808C60
local hr_meters_addr = nil
local hr_sb_addr = nil

local sym_file = io.open(sym_path, "r") or io.open("build/sndj.sym", "r")
if sym_file then
  for line in sym_file:lines() do
    local b, a, name = line:match("^(%x%x):(%x%x%x%x)%s+([%w_@]+)")
    if a and name then
      local full_addr = (tonumber(b, 16) << 16) | tonumber(a, 16)
      if name == "apu_update@done" then apu_done_addr = full_addr
      elseif name == "hr_meters" then hr_meters_addr = full_addr
      elseif name == "hr_status_bar" then hr_sb_addr = full_addr
      end
    end
  end
  sym_file:close()
end

-- Find return address of jsr hr_meters inside hr_status_bar
local hr_meters_ret_addr = nil
if hr_sb_addr and hr_meters_addr then
  local rom_file = io.open(rom_path, "rb") or io.open("build/sndj.sfc", "rb")
  if rom_file then
    local off = 0x38000 + ((hr_sb_addr & 0xFFFF) - 0x8000)
    rom_file:seek("set", off)
    local bytes = rom_file:read(64)
    rom_file:close()
    local target = string.char(0x20, hr_meters_addr & 0xFF, (hr_meters_addr >> 8) & 0xFF)
    local idx = bytes:find(target, 1, true)
    if idx then
      hr_meters_ret_addr = hr_sb_addr + (idx - 1) + 3
    end
  end
end

local mock_envx = nil
if apu_done_addr then
  emu.addMemoryCallback(function(addr)
    if mock_envx then
      for i = 0, 7 do
        poke(0x00F1 + i, mock_envx[i + 1] or 0)
      end
    end
  end, emu.callbackType.exec, apu_done_addr, apu_done_addr)
end

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

local function snapshot_tilemaps()
  local snap = {}
  -- BG2 even layer (SHADOW_BG3): 0x0400 .. 0x0400 + 1791 (1792 bytes = 896 words)
  for a = 0x0400, 0x0400 + 1791, 2 do
    snap[a] = word(a)
  end
  -- BG1 odd layer (SHADOW_HRB): 0x0E00 .. 0x0E00 + 1791 (1792 bytes = 896 words)
  for a = 0x0E00, 0x0E00 + 1791, 2 do
    snap[a] = word(a)
  end
  return snap
end

local function get_meter_word_addrs(ui_mode)
  local addrs = {}
  local y = 4
  for t = 0, 7 do
    local x = (ui_mode == 3) and (5 + t * 4) or (7 + t * 7)
    local off = y * 64 + (x >> 1) * 2
    local base = (x % 2 == 0) and 0x0400 or 0x0E00
    addrs[base + off] = true
  end
  return addrs
end

-- Corruption detection hooks: runs immediately before and after hr_meters executes
local test_corruption = false
local snap_before_meters = nil
local checked_clean_count = 0

if hr_meters_addr and hr_meters_ret_addr then
  emu.addMemoryCallback(function()
    -- Poison registers/variables to detect 16-bit indexing bugs:
    -- tmp0+1 ($0066) = $FB, fr_r ($0D9A) = 5, fr_left ($0D92) = 2
    poke(0x0066, 0xFB)
    poke(0x0D9A, 0x05)
    poke(0x0D92, 0x02)

    if test_corruption then
      snap_before_meters = snapshot_tilemaps()
    end
  end, emu.callbackType.exec, hr_meters_addr, hr_meters_addr)

  emu.addMemoryCallback(function()
    if test_corruption and snap_before_meters then
      local snap_after = snapshot_tilemaps()
      local cur_mode = wram(0x000C)
      local allowed = get_meter_word_addrs(cur_mode)
      local corrupted = 0
      for a, old_w in pairs(snap_before_meters) do
        local new_w = snap_after[a]
        if old_w ~= new_w and not allowed[a] then
          corrupted = corrupted + 1
          print(string.format("CORRUPTION: tilemap at 0x%04X changed during hr_meters: 0x%04X -> 0x%04X", a, old_w, new_w))
        end
      end
      if corrupted > 0 then
        check(false, "hr_meters corrupted " .. corrupted .. " tilemap words outside 8 meter cells")
      else
        checked_clean_count = checked_clean_count + 1
      end
      snap_before_meters = nil
    end
  end, emu.callbackType.exec, hr_meters_ret_addr, hr_meters_ret_addr)
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

    -- Enable corruption detection across meter updates
    test_corruption = true

    -- Set mock playing and mock envx levels
    poke(0x0016, 1)          -- eng_playing = 1
    mock_envx = { 16, 48, 80, 112, 0, 127, 32, 1 }
  end},

  -- 3. Check SONG meters during playback
  {48, function()
    check(checked_clean_count > 0, "SONG hr_meters verified: zero tilemap words corrupted outside 8 meter cells")

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

    test_corruption = false

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

    test_corruption = true
    checked_clean_count = 0

    -- Set mock playing and mock envx
    poke(0x0016, 1)
    mock_envx = { 100, 70, 0, 0, 0, 0, 40, 20 }
  end},

  -- 6. Verify FRAME meters during playback
  {88, function()
    check(checked_clean_count > 0, "FRAME hr_meters verified: zero tilemap words corrupted outside 8 meter cells")

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

    test_corruption = false

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
