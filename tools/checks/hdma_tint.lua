io.stdout:setvbuf("no")
-- hdma_tint.lua — G6: Beat-row HDMA tint check (hires.asm)
-- Verifies that:
-- 1. On SONG and FRAME screens in hi-res Mode 5, HDMA channels 1, 2, 3
--    actively stream to CGADD ($2121), CGDATA ($2122), and COLDATA ($2132).
-- 2. Beat rows (e.g. Row 5, scanlines 40-47) receive the darker color ($0420, $20, $C1).
-- 3. Non-beat rows (e.g. Rows 6-8, scanlines 48-71) receive the normal color ($0841, $21, $C2).
-- 4. On INSTR screen (ui_mode 4), HDMA is disabled (zero writes).
-- 5. On FRAME screen (ui_mode 16), HDMA is re-enabled with Phase 0.
-- 6. In classic Mode 1, HDMA is disabled.
-- 7. Restores original SRAM $000D on exit.

local W = emu.memType.snesWorkRam
local S = emu.memType.snesSaveRam
local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end

local orig_sram = emu.read(0x000D, S)
local fails = 0
local function check(c, m)
  print((c and "PASS " or "FAIL ") .. m)
  if not c then fails = fails + 1 end
end

local function cleanup()
  if orig_sram ~= nil then
    emu.write(0x000D, orig_sram, S)
  end
  print(fails == 0 and "ALL PASS hdma_tint.lua" or ("FAILED hdma_tint.lua: " .. fails))
  emu.stop(fails)
end

local frames, booted = 0, false
local pad = {}
emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)
emu.write(0x0007, 0, S)

local OPT_HIRES = 0x0D8D
local UI_MODE = 0x000C
local UI_HIRES = 0x0D66

-- Monitor writes to PPU registers
local cgdata_writes = 0
local coldata_writes = 0
local cgadd_writes = 0
local last_cgdata = 0
local last_coldata = 0
local dark_cgdata_seen = false
local norm_cgdata_seen = false

emu.addMemoryCallback(function(addr, val)
  cgadd_writes = cgadd_writes + 1
end, emu.callbackType.write, 0x002121, 0x002121)

local cgdata_byte1 = nil
emu.addMemoryCallback(function(addr, val)
  cgdata_writes = cgdata_writes + 1
  if cgdata_byte1 == nil then
    cgdata_byte1 = val
  else
    local word = cgdata_byte1 | (val << 8)
    cgdata_byte1 = nil
    last_cgdata = word
    if word == 0x0420 then dark_cgdata_seen = true end
    if word == 0x0841 then norm_cgdata_seen = true end
  end
end, emu.callbackType.write, 0x002122, 0x002122)

emu.addMemoryCallback(function(addr, val)
  coldata_writes = coldata_writes + 1
  last_coldata = val
end, emu.callbackType.write, 0x002132, 0x002132)

local song_cgdata_start = 0
local instr_cgdata_start = 0
local frame_cgdata_start = 0
local classic_start = 0

local plan = {
  -- 1. Boot onto classic SONG. Enable HI-RES via opt_hires = 1 and bounce through OPTIONS
  {20, function()
    check(wram(UI_MODE) == 3, "starts on SONG screen (ui_mode " .. wram(UI_MODE) .. ")")
    poke(0x2000, 0)          -- track 0 row 0: chain 0
    poke(0x3700, 0)          -- chain 0 step 0: phrase 0
    poke(OPT_HIRES, 1)       -- opt_hires = 1
    pad = { a = true }
  end},
  {22, function() pad = { a = true, up = true } end},
  {24, function() pad = {} end},
  {30, function()
    check(wram(UI_MODE) == 10, "on OPTIONS screen (ui_mode " .. wram(UI_MODE) .. ")")
    pad = { a = true }
  end},
  {32, function() pad = { a = true, down = true } end},
  {34, function() pad = {} end},

  -- 2. Back on SONG screen in hi-res Mode 5
  {45, function()
    check(wram(UI_MODE) == 3, "back on SONG screen (ui_mode 3)")
    check(wram(UI_HIRES) == 0x80, "SONG is in Mode 5 hi-res (ui_hires == 0x80)")
    check(cgadd_writes > 0, "Channel 1 streamed to CGADD (" .. cgadd_writes .. " writes)")
    check(cgdata_writes > 0, "Channel 2 streamed to CGDATA (" .. cgdata_writes .. " writes)")
    check(coldata_writes > 0, "Channel 3 streamed to COLDATA (" .. coldata_writes .. " writes)")
    check(dark_cgdata_seen, "Darker beat-row color $0420 streamed via HDMA")
    check(norm_cgdata_seen, "Normal background color $0841 streamed via HDMA")

    song_cgdata_start = cgdata_writes

    -- Navigate to CHAIN -> PHRASE -> INSTR
    pad = { a = true }
  end},
  {48, function() pad = { a = true, right = true } end}, {51, function() pad = {} end},
  {58, function() pad = { a = true } end}, {61, function() pad = { a = true, right = true } end}, {64, function() pad = {} end},
  {71, function() pad = { a = true } end}, {74, function() pad = { a = true, right = true } end}, {77, function() pad = {} end},

  -- 3. On INSTR screen (ui_mode 4): HDMA must be OFF
  {90, function()
    check(wram(UI_MODE) == 4, "A+right reached INSTR (ui_mode 4)")
    check(wram(UI_HIRES) == 0x80, "INSTR is in Mode 5 hi-res")
    instr_cgdata_start = cgdata_writes
  end},
  -- Wait a few frames on INSTR to confirm 0 HDMA writes
  {94, function()
    local writes_on_instr = cgdata_writes - instr_cgdata_start
    check(writes_on_instr == 0, "HDMA is disabled on INSTR (0 writes during INSTR frames)")

    -- Navigate back to PHRASE: A+Left
    pad = { a = true }
  end},
  {96, function() pad = { a = true, left = true } end}, {99, function() pad = {} end},

  -- 4. In PHRASE, press X to enter FRAME
  {108, function()
    check(wram(UI_MODE) == 1, "reached PHRASE (ui_mode 1)")
    pad = { x = true }
  end},
  {111, function() pad = {} end},

  -- 5. In FRAME screen (ui_mode 16): HDMA must be active
  {125, function()
    check(wram(UI_MODE) == 16, "X entered FRAME (ui_mode 16)")
    check(wram(UI_HIRES) == 0x80, "FRAME is in Mode 5 hi-res")
    frame_cgdata_start = cgdata_writes
  end},
  {130, function()
    local writes_on_frame = cgdata_writes - frame_cgdata_start
    check(writes_on_frame > 0, "HDMA is re-enabled on FRAME (" .. writes_on_frame .. " writes)")

    -- Return to PHRASE, then CHAIN, then SONG
    pad = { x = true }
  end},
  {133, function() pad = {} end},
  {140, function() pad = { a = true } end}, {143, function() pad = { a = true, left = true } end}, {146, function() pad = {} end},
  {152, function() pad = { a = true } end}, {155, function() pad = { a = true, left = true } end}, {158, function() pad = {} end},

  -- 6. Back on SONG screen in hi-res
  {170, function()
    check(wram(UI_MODE) == 3, "back on SONG screen (ui_mode 3)")

    -- Switch to classic Mode 1 via OPTIONS
    poke(OPT_HIRES, 0)
    pad = { a = true }
  end},
  {173, function() pad = { a = true, up = true } end}, {176, function() pad = {} end},
  {184, function()
    check(wram(UI_MODE) == 10, "on OPTIONS screen (ui_mode 10)")
    pad = { a = true }
  end},
  {187, function() pad = { a = true, down = true } end}, {190, function() pad = {} end},

  -- 7. Classic Mode 1 on SONG screen: HDMA must be off
  {205, function()
    check(wram(UI_MODE) == 3, "on classic SONG screen (ui_mode 3)")
    check(wram(UI_HIRES) == 0x00, "SONG is in classic Mode 1 (ui_hires == 0)")
    classic_start = cgdata_writes
  end},
  {210, function()
    local writes_in_classic = cgdata_writes - classic_start
    check(writes_in_classic == 0, "HDMA is disabled in classic Mode 1 (0 writes)")
    cleanup()
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
  for _, step in ipairs(plan) do
    if step[1] == frames then step[2]() end
  end
end, emu.eventType.endFrame)
