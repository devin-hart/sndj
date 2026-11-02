-- cmdhelp.lua — verify G4 command help in the FRAME inspector
-- Checks classic (row 23) and hi-res (row 22 after V34), correct text for A-Z,
-- and that empty commands clear the line.

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

local function word(a) return emu.read(a, W) + emu.read(a + 1, W) * 256 end

local function get_char(x, y)
  local is_hr = (wram(0x0D66) & 0x80) ~= 0
  local g
  if is_hr then
    local off = y * 64 + (x >> 1) * 2
    if x % 2 == 0 then
      local w = word(0x0400 + off)
      g = ((w & 0x3FF) - 1) // 2
    else
      local w = word(0x0E00 + off)
      g = (w & 0x3FF) // 2
    end
  else
    local w = word(0x0400 + (y * 32 + x) * 2)
    g = w & 0x3FF
  end
  g = g % 96
  if g == 0 or g == 95 or g == -1 then return " " end
  return string.char(g + 32)
end

local function get_str(x, y, len)
  local s = ""
  for i = 0, len - 1 do
    s = s .. get_char(x + i, y)
  end
  return s
end

local SB_SONG    = 0x2000
local SB_CHAINS  = 0x3700
local SB_PHRASES = 0x4300

local plan = {
  -- 1. Boot onto classic SONG. Seed test phrases and navigate to FRAME
  {20, function()
    check(wram(0x000C) == 3, "SONG screen active (ui_mode " .. wram(0x000C) .. ")")

    -- Track 0 Row 0: Chain 0
    poke(SB_SONG + 0, 0)
    -- Chain 0 Step 0: Phrase 0
    poke(SB_CHAINS + 0, 0)
    poke(SB_CHAINS + 1, 0)

    -- Phrase 0 Rows:
    -- Row 0: Note C-4 (49), Instr 1, Cmd V (22), Val 0x34
    poke(SB_PHRASES + 0, 49)
    poke(SB_PHRASES + 1, 1)
    poke(SB_PHRASES + 2, 22)   -- V
    poke(SB_PHRASES + 3, 0x34)

    -- Row 1: Note D-4 (51), Instr 1, Cmd A (1), Val 0x12
    poke(SB_PHRASES + 4, 51)
    poke(SB_PHRASES + 5, 1)
    poke(SB_PHRASES + 6, 1)    -- A
    poke(SB_PHRASES + 7, 0x12)

    -- Row 2: Note E-4 (53), Instr 1, Cmd 0 (none), Val 0
    poke(SB_PHRASES + 8, 53)
    poke(SB_PHRASES + 9, 1)
    poke(SB_PHRASES + 10, 0)   -- none
    poke(SB_PHRASES + 11, 0)

    -- Row 3: Note F-4 (54), Instr 1, Cmd Z (26), Val 0x01
    poke(SB_PHRASES + 12, 54)
    poke(SB_PHRASES + 13, 1)
    poke(SB_PHRASES + 14, 26)  -- Z
    poke(SB_PHRASES + 15, 1)

    -- Navigate SONG -> CHAIN -> PHRASE -> FRAME
    pad = { a = true }
  end},
  {22, function() pad = { a = true, right = true } end},
  {24, function() pad = {} end},
  {28, function() pad = { a = true } end},
  {30, function() pad = { a = true, right = true } end},
  {32, function() pad = {} end},
  {36, function() pad = { x = true } end},
  {38, function() pad = {} end},

  -- 2. Hi-Res FRAME screen: cursor on Row 0 (Cmd V)
  {50, function()
    check(wram(0x000C) == 16, "on FRAME screen (ui_mode " .. wram(0x000C) .. ")")
    check((wram(0x0D66) & 0x80) ~= 0, "FRAME is in hi-res mode")

    local row22 = get_str(0, 22, 64)
    check(row22:find("V34", 1, true) ~= nil, "Hi-res row 22 contains V34: '" .. row22:sub(1, 30) .. "'")
    check(row22:find("VIB SPEED X DEPTH Y", 1, true) ~= nil, "Hi-res row 22 contains 'VIB SPEED X DEPTH Y'")

    -- Check that trailing columns (after the help text) are clean spaces
    local vpos = row22:find("VIB SPEED X DEPTH Y", 1, true)
    local tail = row22:sub(vpos + 19)
    check(tail == string.rep(" ", #tail), "Hi-res row 22 trailing columns are cleared")

    -- Navigate down to Row 1 (Cmd A)
    pad = { down = true }
  end},
  {52, function() pad = {} end},

  -- 3. Hi-Res FRAME screen: cursor on Row 1 (Cmd A)
  {60, function()
    local row22 = get_str(0, 22, 64)
    check(row22:find("CYCLE ROOT +X +Y", 1, true) ~= nil, "Hi-res row 22 contains 'CYCLE ROOT +X +Y'")

    -- Navigate down to Row 2 (Cmd 0: empty)
    pad = { down = true }
  end},
  {62, function() pad = {} end},

  -- 4. Hi-Res FRAME screen: cursor on Row 2 (Cmd 0: empty)
  {70, function()
    local row22 = get_str(0, 22, 64)
    local nocmd_pos = row22:find("%-%-%-")
    check(nocmd_pos ~= nil, "Hi-res row 22 shows '---' for empty command")
    local tail = row22:sub(nocmd_pos + 4)
    check(tail == string.rep(" ", #tail), "Hi-res row 22 cleared after '---' on empty command")

    -- Navigate down to Row 3 (Cmd Z)
    pad = { down = true }
  end},
  {72, function() pad = {} end},

  -- 5. Hi-Res FRAME screen: cursor on Row 3 (Cmd Z)
  {80, function()
    local row22 = get_str(0, 22, 64)
    check(row22:find("PMOD BY LEFT VOICE", 1, true) ~= nil, "Hi-res row 22 contains 'PMOD BY LEFT VOICE'")

    print(fails == 0 and "ALL PASS cmdhelp.lua" or ("FAILED cmdhelp.lua: " .. fails))
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
