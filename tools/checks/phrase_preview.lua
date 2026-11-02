-- phrase_preview.lua — verify G2 phrase preview on hi-res SONG (x47..58)

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

local function hr_char(x, y)
  local off = y * 64 + (x >> 1) * 2
  local g
  if x % 2 == 0 then
    local w = word(0x0400 + off)
    g = ((w & 0x3FF) - 1) // 2
  else
    local w = word(0x0E00 + off)
    g = (w & 0x3FF) // 2
  end
  g = g % 96  -- un-invert inverted font roles (ACCENT / PLAY)
  if g == 0 or g == 95 or g == -1 then return " " end
  return string.char(g + 32)
end

local function hr_str(x, y, len)
  local s = ""
  for i = 0, len - 1 do
    s = s .. hr_char(x + i, y)
  end
  return s
end

local SB_SONG    = 0x2000
local SB_CHAINS  = 0x3700
local SB_PHRASES = 0x4300

local plan = {
  -- 1. Boot onto classic SONG. Turn on HI-RES by poking opt_hires = 1 and re-entering SONG via OPTIONS
  {20, function()
    check(wram(0x000C) == 3, "SONG screen active (ui_mode " .. wram(0x000C) .. ")")
    -- Seed test data:
    -- Track 0 Row 0 has Chain 0. Track 1 Row 0 has $FF (empty).
    poke(SB_SONG + 0, 0)          -- Chain 0
    poke(SB_SONG + 1, 0xFF)       -- Empty
    -- Chain 0 Step 0 has Phrase 0, Transpose +12 (0x0C, drawn in ATTR_PINK)
    poke(SB_CHAINS + 0, 0)        -- Phrase 0
    poke(SB_CHAINS + 1, 0x0C)     -- Transpose 0x0C (ATTR_PINK)

    -- Phrase 0 Row 0: Note = C-4 (index 49), Instr = 1, Cmd = 22 ('V'), Val = 0x34
    poke(SB_PHRASES + 0, 49)      -- Note = C-4
    poke(SB_PHRASES + 1, 1)       -- Instr = 0x01
    poke(SB_PHRASES + 2, 22)      -- Cmd = 'V'
    poke(SB_PHRASES + 3, 0x34)

    -- Phrase 0 Row 1: Note = 0 (---), Instr = 0xFF (--), Cmd = 0 (-)
    poke(SB_PHRASES + 4, 0)
    poke(SB_PHRASES + 5, 0xFF)
    poke(SB_PHRASES + 6, 0)
    poke(SB_PHRASES + 7, 0)

    -- Switch to OPTIONS
    poke(0x0D8D, 1)               -- opt_hires = 1
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

  -- 2. Now on hi-res SONG at (0, 0): Chain 0, Phrase 0
  {45, function()
    check(wram(0x000C) == 3, "back on SONG screen (ui_mode " .. wram(0x000C) .. ")")
    check(wram(0x0D66) == 0x80, "SONG is in hi-res mode (ui_hires == 128)")

    -- Check captions on row 3 and row 4
    local ch_cap = hr_str(38, 3, 5)
    check(ch_cap == "CHAIN", "CHAIN caption: '" .. ch_cap .. "'")
    local ch_id = hr_str(44, 3, 2)
    check(ch_id == "00", "CHAIN ID: '" .. ch_id .. "'")

    local ph_cap = hr_str(47, 3, 6)
    check(ph_cap == "PHRASE", "PHRASE caption: '" .. ph_cap .. "'")
    local ph_id = hr_str(54, 3, 2)
    check(ph_id == "00", "PHRASE ID: '" .. ph_id .. "'")

    local ch_ruler = hr_str(38, 4, 8)
    check(ch_ruler == "  PH TSP", "CHAIN ruler: '" .. ch_ruler .. "'")
    local ph_ruler = hr_str(47, 4, 12)
    check(ph_ruler == "  NOTE IN C ", "PHRASE ruler: '" .. ph_ruler .. "'")

    -- Check Row 0 (y = 5): C-4 01 V
    local r0 = hr_str(47, 5, 12)
    check(r0 == "00 C-4 01 V ", "Phrase Row 0: '" .. r0 .. "'")

    -- Check Row 1 (y = 6): --- -- -
    local r1 = hr_str(47, 6, 12)
    check(r1 == "01 --- -- - ", "Phrase Row 1: '" .. r1 .. "'")

    -- Check Row 15 (y = 20) label is 0F
    local r15_lbl = hr_str(47, 20, 2)
    check(r15_lbl == "0F", "Phrase Row 15 label: '" .. r15_lbl .. "'")

    -- Check chain-panel step digit palettes:
    -- Step 0 (previewed) has HILITE palette (2)
    local s0_pal = (word(0x0400 + 5 * 64 + (38 >> 1) * 2) >> 10) & 7
    check(s0_pal == 2, "Chain step 0 (previewed) has HILITE palette (2): " .. s0_pal)

    -- Step 1 (below non-zero transpose) has DIM palette (3)
    local s1_pal = (word(0x0400 + 6 * 64 + (38 >> 1) * 2) >> 10) & 7
    check(s1_pal == 3, "Chain step 1 (below non-zero transpose) has DIM palette (3): " .. s1_pal)

    -- Now move cursor right to Track 1 (which has chain $FF)
    pad = { right = true }
  end},
  {47, function() pad = {} end},

  -- 3. Now cursor on Track 1 Row 0: empty cell ($FF)
  {55, function()
    check(wram(0x001B) == 1, "cursor on track 1 (song_cx " .. wram(0x001B) .. ")")
    local ch_id = hr_str(44, 3, 2)
    check(ch_id == "--", "empty CHAIN ID: '" .. ch_id .. "'")
    local ph_id = hr_str(54, 3, 2)
    check(ph_id == "--", "empty PHRASE ID: '" .. ph_id .. "'")

    -- Check that all 16 rows (rows 5..20) are drawn blank
    local blank_ok = true
    for y = 5, 20 do
      local s = hr_str(47, y, 12)
      if s ~= "            " then
        blank_ok = false
        print("Row " .. y .. " not blank: '" .. s .. "'")
      end
    end
    check(blank_ok, "empty phrase draws blank on all 16 rows")

    -- Now move cursor back left to Track 0
    pad = { left = true }
  end},
  {57, function() pad = {} end},

  -- 4. Cursor back on Track 0: should restore Phrase 0 preview
  {65, function()
    check(wram(0x001B) == 0, "cursor back on track 0 (song_cx " .. wram(0x001B) .. ")")
    local ch_id = hr_str(44, 3, 2)
    check(ch_id == "00", "restored CHAIN ID: '" .. ch_id .. "'")
    local ph_id = hr_str(54, 3, 2)
    check(ph_id == "00", "restored PHRASE ID: '" .. ph_id .. "'")
    local r0 = hr_str(47, 5, 12)
    check(r0 == "00 C-4 01 V ", "restored Phrase Row 0: '" .. r0 .. "'")

    print(fails == 0 and "ALL PASS phrase_preview.lua" or ("FAILED phrase_preview.lua: " .. fails))
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
