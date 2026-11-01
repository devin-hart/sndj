-- statusbar.lua — verify G1 hi-res status bar on SONG and FRAME

local W = emu.memType.snesWorkRam
local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end

local frames, booted, pad = 0, false, {}
local fails = 0
local function check(c, m)
  print((c and "PASS " or "FAIL ") .. m)
  if not c then fails = fails + 1 end
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

-- Start with HI-RES OFF in SRAM
emu.write(0x000D, 0, emu.memType.snesSaveRam)

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

local function compute_fl_kb(bytes)
  local whole = bytes >> 10
  local frac = bytes & 0x03FF
  local dec = ((frac * 10) >> 10) & 0x0F
  local tens = whole // 10
  local unit = whole % 10
  local s_tens = tens > 0 and tostring(tens) or " "
  return string.format("%s%d.%dK", s_tens, unit, dec)
end

local plan = {
  -- 1. Boot onto classic SONG. Verify classic mode has no status bar on row 1
  {20, function()
    check(wram(0x000C) == 3, "SONG screen active (ui_mode " .. wram(0x000C) .. ")")
    check(wram(0x0D66) == 0, "SONG starts in classic mode (ui_hires == 0)")
    -- Seed chain 0 at track 0 row 0, and phrase 0 at step 0 so we can navigate to CHAIN/PHRASE/FRAME
    poke(0x2000, 0)
    poke(0x3700, 0)
  end},

  -- 2. Turn on HI-RES by poking opt_hires = 1 and re-entering SONG via OPTIONS
  {24, function() poke(0x0D8D, 1); pad = { a = true } end},
  {26, function() pad = { a = true, up = true } end},
  {28, function() pad = {} end},
  {34, function()
    check(wram(0x000C) == 10, "on OPTIONS screen (ui_mode " .. wram(0x000C) .. ")")
    pad = { a = true }
  end},
  {36, function() pad = { a = true, down = true } end},
  {38, function() pad = {} end},

  -- 3. Now on hi-res SONG (stopped)
  {45, function()
    check(wram(0x000C) == 3, "back on SONG screen (ui_mode " .. wram(0x000C) .. ")")
    check(wram(0x0D66) == 0x80, "SONG is in hi-res mode (ui_hires == 128)")
    local title = hr_str(0, 1, 4)
    check(title == "SONG", "SONG title: '" .. title .. "'")
    local name = hr_str(6, 1, 8)
    check(name == "SONG    ", "SONG status bar name: '" .. name .. "'")
    local bpm = hr_str(15, 1, 3)
    check(bpm == "150", "SONG status bar tempo: '" .. bpm .. "'")
    local play = hr_str(19, 1, 4)
    check(play == "STOP", "SONG status bar state stopped: '" .. play .. "'")
    local ram_lbl = hr_str(24, 1, 4)
    check(ram_lbl == "RAM ", "SONG status bar RAM label: '" .. ram_lbl .. "'")

    local res_cur = word(0x00D7)
    local used_str = compute_fl_kb(res_cur - 0x1200)
    local used_act = hr_str(28, 1, 5)
    check(used_act == used_str, "SONG ARAM used: '" .. used_act .. "' == '" .. used_str .. "'")

    local free_lbl = hr_str(33, 1, 6)
    check(free_lbl == " FREE ", "SONG status bar FREE label: '" .. free_lbl .. "'")

    local edl = emu.read(0x3600 + 17, W) & 0x0F
    local floor_page = (0x100 - edl * 8) & 0xFF
    if floor_page == 0 then floor_page = 0xFF end
    local floor_addr = floor_page * 256
    local free_bytes = (floor_addr > res_cur) and (floor_addr - res_cur) or 0
    local free_str = compute_fl_kb(free_bytes)
    local free_act = hr_str(39, 1, 5)
    check(free_act == free_str, "SONG ARAM free: '" .. free_act .. "' == '" .. free_str .. "'")
  end},

  -- 4. Start playback: verify STOP -> PLAY
  {48, function() pad = { start = true } end},
  {50, function() pad = {} end},
  {55, function()
    local play = hr_str(19, 1, 4)
    check(play == "PLAY", "SONG status bar state playing: '" .. play .. "'")
  end},

  -- 5. Stop playback before navigating
  {58, function() pad = { start = true } end},
  {60, function() pad = {} end},

  -- 6. Navigate to FRAME: SONG -> CHAIN (A+RIGHT) -> PHRASE (A+RIGHT) -> FRAME (X)
  {66, function() pad = { a = true } end},
  {69, function() pad = { a = true, right = true } end},
  {72, function() pad = {} end},
  {78, function()
    check(wram(0x000C) == 2, "on CHAIN screen (ui_mode " .. wram(0x000C) .. ")")
    pad = { a = true }
  end},
  {81, function() pad = { a = true, right = true } end},
  {84, function() pad = {} end},
  {90, function()
    check(wram(0x000C) == 1, "on PHRASE screen (ui_mode " .. wram(0x000C) .. ")")
    pad = { x = true }
  end},
  {92, function() pad = {} end},

  -- 7. Verify FRAME status bar
  {105, function()
    check(wram(0x000C) == 16, "on FRAME screen (ui_mode " .. wram(0x000C) .. ")")
    local fr_title = hr_str(0, 1, 5)
    check(fr_title == "FRAME", "FRAME title: '" .. fr_title .. "'")
    local fr_row = hr_str(7, 1, 4)
    check(fr_row == "ROW ", "FRAME row label intact: '" .. fr_row .. "'")

    local name = hr_str(21, 1, 8)
    check(name == "SONG    ", "FRAME status bar name: '" .. name .. "'")
    local bpm = hr_str(30, 1, 3)
    check(bpm == "150", "FRAME status bar tempo: '" .. bpm .. "'")
    local play = hr_str(34, 1, 4)
    check(play == "STOP", "FRAME status bar state stopped: '" .. play .. "'")
    local ram_lbl = hr_str(39, 1, 4)
    check(ram_lbl == "RAM ", "FRAME status bar RAM label: '" .. ram_lbl .. "'")

    local res_cur = word(0x00D7)
    local used_str = compute_fl_kb(res_cur - 0x1200)
    local used_act = hr_str(43, 1, 5)
    check(used_act == used_str, "FRAME ARAM used: '" .. used_act .. "' == '" .. used_str .. "'")

    local f_lbl = hr_str(48, 1, 3)
    check(f_lbl == " F ", "FRAME status bar F label: '" .. f_lbl .. "'")

    local edl = emu.read(0x3600 + 17, W) & 0x0F
    local floor_page = (0x100 - edl * 8) & 0xFF
    if floor_page == 0 then floor_page = 0xFF end
    local floor_addr = floor_page * 256
    local free_bytes = (floor_addr > res_cur) and (floor_addr - res_cur) or 0
    local free_str = compute_fl_kb(free_bytes)
    local free_act = hr_str(51, 1, 5)
    check(free_act == free_str, "FRAME ARAM free: '" .. free_act .. "' == '" .. free_str .. "'")

    -- Check 3-column margin before tick counter at column 59
    local margin = hr_str(56, 1, 3)
    check(margin == "   ", "FRAME 3-column margin before tick counter: '" .. margin .. "'")

    print(fails == 0 and "ALL PASS statusbar.lua" or ("FAILED statusbar.lua: " .. fails))
    emu.stop(fails)
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
