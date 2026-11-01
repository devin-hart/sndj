---
title: File Reference — S-CPU Core, Boot, NMI & UI Infrastructure
category: files
updated: 2026-11-01
sources:
  - src/snes.inc
  - src/ram.inc
  - src/song.inc
  - src/main.asm
  - src/init.asm
  - src/nmi.asm
  - src/input.asm
  - src/text.asm
  - src/palette.asm
  - src/splash.asm
  - src/screens.asm
---

# File Reference: S-CPU Core, Boot, NMI & UI Infrastructure

This page documents the include files (`src/*.inc`) and core infrastructure files in `src/`.

See also: [`memory-and-hardware.md`](memory-and-hardware.md), [`files-scpu-engine.md`](files-scpu-engine.md), [`files-scpu-screens.md`](files-scpu-screens.md).

---

## 1. Include Files (`src/*.inc`)

### `src/snes.inc` (144 lines)
- **Role**: S-CPU hardware MMIO register definitions (`fullsnes` naming), joypad button bitmasks (`PAD_B = $8000` down to `PAD_R = $0010`), VRAM word addresses (`VRAM_BG3_MAP = $0000`, `VRAM_BG1_MAP = $0400`, `VRAM_BG3_CHR = $1000`, `VRAM_BG1_CHR = $2000`), BG3 tilemap attribute high words (`ATTR_TEXT = $2000`, `ATTR_ACCENT = $2400`, `ATTR_HILITE = $2800`, `ATTR_DIM = $2C00`, `ATTR_PLAY = $3000`), and extra 8×8 font glyph indices (`GLYPH_BLOCK = 64` .. `GLYPH_NOTE = 72`).

### `src/ram.inc` (310 lines)
- **Role**: Defines all low-WRAM variables (`$7E:0000–$7E:1FFF`, mirrored at `$80:0000–$80:1FFF`), `MAGIC_BOOT_OK = $5D`, `SYNC_*` constants (`0..5`), and `SHADOW_BG3 = $0400` (`$0400–$0BFF`, 2 KB).
- **Layout & Critical Rules**:
  - `.ENUM $0000` (`$0000–$03FF`):
    - `$0000–$003F` are **FROZEN** for `tools/checks/*.lua`.
    - `$0040–$00FF` hold Direct Page 24-bit pointers (`up_src`, `sv_src`, `sv_dst`) and hot scalars (`tmp0..2`, `text_x`, `text_y`). Note: **`text_y` MUST immediately follow `text_x`** (`text_dest` reads both as a 16-bit word at `text_x`).
    - **`opt_kdelay`, `opt_krate`, `opt_tapwin` (`$03F2–$03F4`) MUST stay consecutive** (`optionscr.asm` indexes them as `opt_kdelay,x`).
    - **The `$0000` `.ENUM` is FULL (ends at `$03FA`). `pal_buf2` was moved to the `$0C00` block because it used to overrun `SHADOW_BG3` by 2 bytes — see [drift #6](playbooks-and-sync-matrix.md).**
  - `.ENUM $0C00` (`$0C00+`): Overflow WRAM block above `SHADOW_BG3` (`$0400–$0BFF`) and below the stack (`$1FFF`). **Add all new WRAM variables here.**

### `src/song.inc` (80 lines)
- **Role**: Defines the contiguous WRAM Song Block at `SB = $2000` (`$7E:2000–$7E:72FF`, `SB_END = $7300`, size `$5300` = 21,248 bytes), pool counts (`PHRASE_COUNT = 192`, `CHAIN_COUNT = 96`, `SONG_ROWS = 128`, `TRACKS = 8`, `INSTR_COUNT = 64`, `TABLE_COUNT = 32`, `GROOVE_COUNT = 16`, `KIT_COUNT = 16`), section base offsets (`SB_SONG` through `SB_PHRASES`), `SB_HEADER` field offsets (`SH_GROOVE = 0` .. `SH_FIRTAPS = 19`), cell sentinels (`NOTE_EMPTY = 0`, `NOTE_OFF = 97`, `INSTR_NONE = $FF`, `CMD_NONE = 0`), and ROM sample pool constants (`POOL_RESERVED = $27FFA`, `POOL_BANKS = 5`, `POOL_ROM = $818006`).

---

## 2. Top-Level Translation Unit & Boot (`main.asm`, `init.asm`, `nmi.asm`)

### `src/main.asm` (418 lines)
- **Role**: Single translation unit assembled by `wla-65816`.
- **Key Contents**:
  - `.DEFINE VERSION "0.15"` (parsed by `Makefile` and rendered on the splash/HELP screens).
  - Configures 1 MB LoROM (`32` × `$8000` banks, `.BASE $80` FastROM).
  - `.INCLUDE`s all 28 `.asm` files into **Bank 0** (`.BANK 0 SLOT 0`).
  - `main_loop`: Checks `frame_flag` first and skips `wai` if the NMI already fired (an overrunning frame runs immediately instead of sleeping a whole extra frame); otherwise `wai`s, then checks `frame_flag`. On VBlank wake, runs in order: `input_update`, `apu_update`, `engine_update`, `engine_sync_update`, `midi_service`, `tick_track`, `engine_sync_update`, `screen_update`, `engine_sync_update`, `hint_tick`, `draw_status`, `draw_minimap`, `engine_sync_update`. On V-timer IRQ wake (`frame_flag == 0`), drains `engine_sync_update` and returns to `wai`.
  - `tick_track`: Folds 8-bit `apu_tick` deltas into 16-bit `tick_ctr`.
  - `draw_status` & `draw_minimap`: Draws right-column chrome (`x=27..31`: 4-digit hex `tick_ctr` or inverted `APU?` at `y=1`, `PLAY`/`WAIT`/`STOP` at `y=3`, and the 3×5 screen map at `y=5..7`). `draw_minimap` reads cell positions from the `minimap_x`/`minimap_y` tables (formerly mod/div-by-5 loops).
  - **Banks 1–5**: Embeds `"SNPOOL"` (`$81:8000`) + `build/pool.bin` split across 5 banks (`$7FFA` in Bank 1, `$8000` each in Banks 2–5).
  - **Bank 6**: Embeds `"SNFONT"` + `font.bin`, `"SNPAL0"` + `schemes.bin`, `logo.bin`, `"SNKIT0"` + `kits.bin`, `"SNDEF3"` + `defaults.bin`, `"SNFIR0"` + `fir_presets`, `tables.inc`, `karptab.inc`, `help.inc`, and `driver.spc700.bin`.
  - **Internal Header & Vectors (`.ORG $7FC0` in Bank 0)**: LoROM/FastROM (`$30`), 1 MB ROM, 32 KB SRAM, `Reset`, `Vec_NMI`, `Vec_IRQ`.

### `src/init.asm` (268 lines)
- **Role**: Hardware reset (`Reset`), WRAM/VRAM/OAM zeroing, subsystem initialization, and transition to `main_loop`.
- **Execution Sequence**:
  1. Enters 65816 native mode (`clc / xce`), sets `S = $1FFF`, `D = $0000`, `DB = $80`, enables `FastROM` (`MEMSEL = 1`), and jumps long (`jml @fast`) into Bank `$80`.
  2. Force-blanks PPU (`INIDISP = $8F`), disables NMI/HDMA/DMA, and clears all **128 KB of WRAM** (`$7E:0000–$7F:FFFF`) using two 64 KB fixed-source DMAs to `WMDATA` (`$2180`). *(Must run inline before any `jsr` because it wipes the stack!)*
  3. Calls `init_regs` (parks PPU registers, sets `WRIO = $FF` so Port 2 IOBit is idle high) and `init_video` (clears 64 KB VRAM, parks OAM at `$F0`, reads `STAT78` `$213F` bit 4 into `video_pal`, calls `palette_boot`, `sync_boot`, `options_boot`, DMAs `font_data` and `logo_data` from Bank 6 to `VRAM_BG3_CHR = $1000`, configures BG Mode 1 with BG3 priority).
  4. Displays splash (`splash_loading` `"LOADING AUDIO"`), enables NMI + auto-joypad (`NMITIMEN = $81`, `INIDISP = $0F`).
  5. Calls `apu_upload_driver` -> `apu_audio_init`, `song_init`, `live_pending_reset`, `sram_check`, `wave_sync_all`, `residency_build`, sets `hint_ctr = 180`, calls `apu_echo_apply`, seeds `trk_instr_active[0..7] = $FF` and editor defaults (`ed_lastnote = 49` C-4, `ed_lastcmd = 1`), calls `splash_ready` (`"PRESS START"`), writes `magic_boot = $5D`, and jumps to `main_loop`.

### `src/nmi.asm` (97 lines)
- **Role**: VBlank interrupt handler (`Vec_NMI`) and fast-mirror jump stub for the V-timer IRQ (`Vec_IRQ -> jml Sync_IRQ_Body`).
- **Execution Sequence**:
  - Hop to `$80` FastROM mirror (`jml @body`), save 16-bit `A, X, Y, DB, D`, set `D = $0000` and `DB = $80`, read `RDNMI` (`$4210`).
  - DMA 2 KB `SHADOW_BG3` (`$7E:0400–$0BFF`) to `VRAM_BG3_MAP` (`$0000`).
  - If `pal_dirty != 0`, write `pal_buf` (32 bytes -> CGRAM `0..15`) and `pal_buf2` (8 bytes -> CGRAM `16..19` for `ATTR_PLAY`), clear `pal_dirty`.
  - Wait for `HVBJOY & 1 == 0`, read 16-bit `JOY1L & $FFF0` into `pad_raw`, increment `frame_cnt`, set `frame_flag = 1`, restore registers, `rti`.

---

## 3. Input, Text, Palette, Splash & Screen Router

### `src/input.asm` (79 lines)
- **Role**: Per-frame controller edge detector and Delayed Auto-Repeat (DAS) generator (`input_update`).
- **Behavior**: Copies `pad_raw` -> `pad_held`, computes newly pressed buttons (`pad_pressed = pad_held & ~pad_prev`), and tracks held D-pad directions (`PAD_DPAD = $0F00`) using NMI frame deltas (`frame_cnt - das_last_fc`) against `opt_kdelay` (initial delay, default 14 frames) and `opt_krate` (repeat period, default 3 frames). Outputs `pad_event = pad_pressed | das_repeat_dpad`.

### `src/text.asm` (138 lines)
- **Role**: Writes tiles and strings to the WRAM BG3 tilemap shadow (`SHADOW_BG3 = $0400`).
- **Key Routines**:
  - `text_clear`: Fills all 1,024 words of `SHADOW_BG3` with `ATTR_TEXT | 0` (`$2000`, blank space tile), then zeroes `sd_valid` so the SONG/LIVE grid repaints after any screen entry.
  - `text_dest`: Computes `(text_y * 32 + text_x) * 2` into `X` (and `tmp1`).
  - `text_puts`: Renders NUL-terminated ASCII string at `DB:X` (`$80:X`) into `SHADOW_BG3` at `(text_x, text_y)` with `text_attr`, advancing `text_x`. Automatically adds `+96` to the glyph index when `text_attr` is `ATTR_ACCENT` (`$2400`) or `ATTR_PLAY` (`$3000`) to select the inverted tile bank.
  - `text_puttile`: Writes single tile index `A` at `(text_x, text_y)` with `text_attr` (adding `+96` if `ATTR_ACCENT` or `ATTR_PLAY`).
  - `text_hex8`: Prints byte `A` as two uppercase hex characters at `(text_x, text_y)`, advancing `text_x` by 2. Computes `text_dest` once and writes both words (exit `X` = second digit's offset, as before).
  - `text_inv`: Sets `tmp1` (16-bit) to `96` for `ATTR_ACCENT`/`ATTR_PLAY`, else `0`. Used once per call by `text_puts` and `text_hex8` instead of once per glyph.
- **Clobber Warning**: `text_dest` clobbers `X` and `tmp1`; `text_puts` clobbers `X, Y, tmp0, tmp1`; `text_puttile` and `text_hex8` clobber `X, Y, tmp1`.

### `src/palette.asm` (140 lines)
- **Role**: Manages the 8 2-colour palette schemes (`BLK`, `WHT`, `KIDD`, `AMBR`, `CYAN`, `PINK`, `NEON`, `MINT`) stored at `pal_schemes` (`SNPAL0` in Bank 6).
- **Key Routines**:
  - `palette_boot`: Reads `opt_pal` (`$70:0007`) and `opt_clone` (`$70:0008`) from SRAM if `SNDJ1` magic is valid (range-checking `< 8` and `< 2`), builds `pal_buf` + `pal_buf2`, and writes CGRAM directly under force-blank.
  - `palette_select`: Sets `opt_pal = A & 7`, calls `palette_apply`, and writes `opt_pal` to SRAM `$70:0007` if formatted.
  - `palette_apply`: Reads the 16-byte scheme (`bg` word at `+0`, `ink` word at `+2`) from Bank 6 `pal_schemes`, populates CGRAM slots `0..15` (`pal_buf`: color 0 = `bg`, color 1 = `bg`, color 2 = `bg`, color 3 = `ink` across palettes 0–3) and CGRAM slots `16..19` (`pal_buf2`: color 17 = `ink`, color 19 = `bg` for inverted `ATTR_PLAY`), and sets `pal_dirty = 1`.

### `src/splash.asm` (125 lines)
- **Role**: Boot splash screen (`ui_mode = 0`) and global text macros (`PUTS x, y, label`, `SETATTR attr`).
- **Key Routines**: `splash_init` (draws 22×10 tile wordmark starting at tile 192, subtitle `"SUPER FAMICOM MUSIC TRACKER"`, and centered `str_version` + `str_stamp` at `y=14`), `splash_loading` (`"LOADING AUDIO"` at `y=21`), `splash_ready` (`"PRESS START"`), and `splash_update` (blinks `"PRESS START"` using `frame_cnt & $20`; on `PAD_START`, transitions to `song_init_screen`).

### `src/screens.asm` (665 lines)
- **Role**: Central screen dispatcher (`screen_update`), `A + D-pad` 2D navigation map (`nav_update`), `Select` LIVE toggle (`screen_reopen`), and `L/R` or `Y + Left/Right` track switching (`chan_update`).
- **Screen ID Constants**:
  - `SCREEN_SPLASH = 0`, `SCREEN_PHRASE = 1`, `SCREEN_CHAIN = 2`, `SCREEN_SONG = 3`, `SCREEN_INSTR = 4`, `SCREEN_FILES = 5`, `SCREEN_ECHO = 6`, `SCREEN_WAVE = 7`, `SCREEN_LIVE = 8`, `SCREEN_KIT = 9`, `SCREEN_OPTIONS = 10`, `SCREEN_GROOVE = 11`, `SCREEN_PROJECT = 12`, `SCREEN_FIR = 13`, `SCREEN_TABLE = 14`, `SCREEN_HELP = 15`.
- **Context-Aware Descent (`nav_update`)**:
  - `SONG`/`LIVE` + `A+Right` -> peeks `SB_SONG[song_cx, song_cy]`; if not `$FF`, sets `ed_chain` to that cell before opening `CHAIN`.
  - `CHAIN` + `A+Right` -> peeks `SB_CHAINS[ed_chain, chain_cy]`; if not `$FF`, sets `ed_phrase` to that entry before opening `PHRASE`.
  - `PHRASE` + `A+Right` -> resolves instrument on cursor row (or scans upward in phrase, falling back to `ed_lastinstr`), sets `ed_instr`, opens `INSTR`.
  - `INSTR` + `A+Right` -> if instrument's `TBL` (`rec[12]`) `< 32`, sets `ed_table` to it before opening `TABLE`.
  - `WAVE` + `A+Left/Right` -> nudges `ed_wave` (`0..7`) in-place; `A+Down` returns to `INSTR`.
