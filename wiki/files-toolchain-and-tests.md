---
title: File Reference — Build Toolchain, CLI Utilities & 41 Lua Checks
category: files
updated: 2026-11-01
sources:
  - Makefile
  - tools/commands.csv
  - tools/fixsum.py
  - tools/makefont.py
  - tools/makehelp.py
  - tools/makelogo.py
  - tools/maketables.py
  - tools/mesen_setup.py
  - tools/savetool.py
  - tools/shotdiff.py
  - tools/sndj_brr.py
  - tools/sndj_pool.py
  - tools/sndj_rle.py
  - tools/test_sf2.py
  - tools/test_sf2.js
  - tools/test_als.js
  - tools/test_spc.js
  - tools/check_runner.lua
  - tools/shot.lua
---

# File Reference: Build Toolchain, CLI Utilities & 41 Lua Checks

This page documents every script in `tools/` and all 41 headless emulator verification scripts in `tools/checks/*.lua`.

See also: [`overview.md`](overview.md), [`files-browser-ecosystem.md`](files-browser-ecosystem.md), [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

---

## 1. Build Generators & Host CLI Tools (`tools/`)

### `tools/commands.csv` (26 lines)
- **Role**: Single source of truth for the tracker command set (`letter,name,short` for `A` through `Z`). Consumed by `tools/makehelp.py` and `tools/maketables.py`.

### `tools/fixsum.py` (34 lines)
- **Usage**: `python3 tools/fixsum.py build/sndj.sfc`
- **Role**: Computes the 16-bit SNES LoROM checksum and complement at `$7FDC–$7FDF` (`~sum & 0xFFFF` at `$7FDC`, `sum & 0xFFFF` at `$7FDE`). Mirrored by `SNDJ.fixChecksum` in `user-tools/sndj.js`.

### `tools/makefont.py` (167 lines)
- **Usage**: `python3 tools/makefont.py build/font.bin`
- **Role**: Generates the 3,072-byte 2bpp 8×8 font (`build/font.bin`, included after `SNFONT` in Bank 6). Contains 96 normal tiles (64 uppercase ASCII `32..95` rendered from inline 5×7 bitmaps + 10 special glyphs at indices `64..73`: `GLYPH_BLOCK`, `GLYPH_BLOCK34`, `GLYPH_BLOCK12`, `GLYPH_BLOCK14`, `GLYPH_ARROW_R/L/U/D`, `GLYPH_NOTE`, `cursor_ul`, padded to 96) followed by 96 inverted tiles (`invert_tile`: plane 0 = `$FF`, plane 1 = `~b1`, mapping ink pixels to CGRAM color 1 = bg and background pixels to color 3 = ink).

### `tools/makehelp.py` (111 lines)
- **Usage**: `python3 tools/makehelp.py help.txt build/help.inc`
- **Role**: Compiles `help.txt` + `tools/commands.csv` (`@COMMANDS1`, `@COMMANDS2`, `@VERSION`) into `HELP_PAGES`, `help_pgtab`, and `help_data` (`build/help.inc`, included in Bank 6 and rendered by `src/helpscr.asm`). Enforces `WIDTH = 30` chars and `ROWS = 20` lines per page.

### `tools/makelogo.py` (122 lines)
- **Usage**: `python3 tools/makelogo.py build/logo.bin build/logo.inc`
- **Role**: Pure-Python PNG reader that downscales `art/sndj-logo.png` into a 22×10 tile (220 tiles = 3,520 bytes) 2bpp wordmark (`build/logo.bin`, Bank 6) and emits `LOGO_TW`, `LOGO_TH`, `LOGO_NTILES` (`build/logo.inc`).

### `tools/maketables.py` (297 lines)
- **Usage**: `python3 tools/maketables.py build`
- **Role**: Generates 5 build artifacts (reading `factory/factory.sndjfact` if present, or falling back to built-in defaults):
  1. `build/schemes.bin` (128 B, `SNPAL0`): 8 palette schemes × 16 B (`+0` bg BGR15 LE, `+2` ink BGR15 LE).
  2. `build/kits.bin` (1,024 B, `SNKIT0`): 16 kits × 16 slots × 4 B (`sample, tune, vol, flags`).
  3. `build/defaults.bin` (24 B, `SNDEF3`): 8 boot instruments (`types[8]`, `samples[8]`, `extras[8]`).
  4. `build/tables.inc` (Bank 6): `pitch_octave7` (12 `.DW` words for `C-7..B-7`), `note_semi2` (96 bytes), `note_shift` (96 bytes), and `default_waves` (8 × 32 4-bit wavetable frames).
  5. `build/karptab.inc` (Bank 6): `karp_tab` (`2 EDLs × 96 notes × 4 bytes`: `pitch_lo, pitch_hi, i0, fr`) for Karplus-Strong `KARP` synthesis.

### `tools/sndj_brr.py` (239 lines)
- **Usage**: `python3 tools/sndj_brr.py --selftest` or `encode in.wav out.brr [--loop N]`
- **Role**: Reference S-DSP 4-bit BRR encoder and bit-exact hardware decoder. Brute-forces optimal shift (`0..12`) and IIR prediction filter (`0..3`, forcing filter `0` on block 0 and `loop_block`) per 16-sample block while carrying hardware-clamped `p1, p2` state across blocks. Mirrored byte-for-byte in `user-tools/sndj.js`.

### `tools/sndj_pool.py` (549 lines)
- **Usage**: `python3 tools/sndj_pool.py build/pool.bin`
- **Role**: Builds the 163,834-byte (`RESERVED = 0x27FFA`) `SNDJPOOL` v2 image (`build/pool.bin`, included after `SNPOOL` across ROM Banks 1–5).
  - Extracts `pool` from `factory/factory.sndjfact` if present, or copies `samples/pool.bin`, or synthesizes the 48-slot copyright-clean fallback (18 melodic/drum sounds + 30 1-block `'--------'` free slots).
  - Also contains the Python SF2 parser/resampler (`sf2_samples`, `resample`, `prep_oneshot`) and **bank-boundary padding (`bank_pad`)** so no sample ever straddles a 32 KB LoROM bank boundary (`BANK0_SPAN = 0x7FFA`, `BANK_SPAN = 0x8000`).

### `tools/sndj_rle.py` (138 lines)
- **Usage**: `python3 tools/sndj_rle.py --selftest`
- **Role**: Python mirror of `src/save.asm`: `to_image` / `from_image` (column-planar transposition of `$5300`-byte Song Block), `pack` / `unpack` (byte-stream RLE), and `crc16` (CRC-16/CCITT `$1021`, seed `$FFFF`).

### `tools/savetool.py` (146 lines)
- **Usage**: `python3 tools/savetool.py list|new|extract|insert|erase <save.srm> [args]`
- **Role**: Command-line manager for 32 KB `SNDJ1` v2 `.srm` files and standalone `.sndj` song containers.

### `tools/mesen_setup.py` (41 lines), `tools/check_runner.lua` (28 lines), `tools/shot.lua` (30 lines), `tools/shotdiff.py` (93 lines)
- **Role**:
  - `mesen_setup.py`: Enables `AllowIoOsAccess` and `SnesController` in Mesen 2's `settings.json`.
  - `check_runner.lua`: Wrapper that pins SRAM `$0007` (`opt_pal`) to `0` and zeroes pool `tuneSemis`/`tuneFine` (`$8006 + 16 + i*16 + 14..15`) in ROM before executing the Lua check script named in `SNDJ_CHECK`.
  - `shot.lua` & `shotdiff.py`: Captures headless screenshots after `magic_boot == $5D` and pixel-compares them against `tools/goldens/*.png` (with scanline band masking).

### `tools/test_sf2.py`, `tools/test_sf2.js`, `tools/test_als.js`, `tools/test_spc.js`
- **Role**: Host-side cross-language parity tests executed by `make test`:
  - `test_sf2.py` + `test_sf2.js`: Generates a synthetic `.sf2` and proves Python (`sndj_pool.py` + `sndj_brr.py`) and JS (`sndj.js`) emit identical BRR bytes and tuning metadata.
  - `test_als.js`: Tests `user-tools/als2sndj.html` MML/MIDI/`.sndj` conversion and round-trip idempotence.
  - `test_spc.js`: Tests `user-tools/spcexport.html` `.spc` capture and runs the emitted SPC700 replayer machine code inside a 17-opcode JS micro-emulator to prove event-for-event DSP write accuracy.

---

## 2. All 41 Emulator-in-the-Loop Lua Check Scripts (`tools/checks/*.lua`)

Run via `make check`. Every script boots `build/sndj.sfc` in Mesen 2 `--testrunner`, drives scripted pad inputs or hardware pin transitions, and asserts on WRAM, S-DSP registers, ARAM, SRAM, or CGRAM:

| Check Script | What It Verifies |
| :--- | :--- |
| **`factory.lua`** | *(Run directly without `check_runner.lua`)* Untouched ROM smoke test: 48 pool slots, 16 authored sounds, all boot-referenced samples resident in `pool_map` (`$97+`), max EDL 15 headroom, and real pool `tuneSemis`/`tuneFine` reaching DSP `$02–$03`. |
| **`boot.lua`** | **M1 Gate**: `magic_boot == $5D`, `frame_cnt` advancing, splash tiles in `SHADOW_BG3`, `Start` entering `SONG` (`ui_mode == 3`), and DAS auto-repeat stepping `song_cy`. |
| **`mailbox.lua`** | **M2 Gate**: APU ready (`apu_status == 0`), `apu_tick` advancing, `DSP_FLG == $20`, heartbeat reaching `DSP $1D`, and watchdog timeout (overwriting ARAM `$0200+` with `SLEEP $EF` sets `apu_status == 1` and renders inverted `"APU?"` without hanging the S-CPU). |
| **`voice.lua`** | **M3 Gate**: ARAM directory (`$1000`), sample upload (`$1209+`), DSP init, and PHRASE note insert/nudge auditioning `C-4` (`$0800`) to `E-4` (`$0A14`) with live `ENVX`. |
| **`phrase.lua`** | **M4 Gate**: PHRASE editing, semitone/octave nudge, 1D/2D block copy/cut/paste (`$7400+`), single-column NOTE cut preserving INSTR/CMD/VAL, groove playback, and `shot-phrase.png` golden. |
| **`model.lua`** | **M5 Gate**: Multi-track SONG + CHAIN (`+12` transpose) + PHRASE construction and playback (`V0 = $0800`, `V1 = $1000`), plus `shot-song.png` golden. |
| **`instr.lua`** | **M6 Gate**: INSTR screen (`ui_mode == 4`), ADSR edits, coarse `TUNE` (`+12` octave step), `C47` 3-voice chord fanout on `V0..V2`, and `shot-instr.png` golden. |
| **`commands.lua`** | **M7 Gate**: Commands `P`, `K`, `D` (including `D06` boundary suppression), `B` (wave bank), `L` (including WAV legato slide octave accuracy), `TRM` chord fanout, `G`, `H`, `A`, `V`, `W` (tremolo override), `R`, and `T`. |
| **`cmd2.lua`** | Commands batch 2: `F40` fine tune, `M20` master vol, `N05` noise clock, `Z01` pitch mod (`PMON`), `Q35`/`Q00` GAIN override & ADSR restore, same-row `U11` surround phase invert, same-row `S0F` sweep, `C47` chord fanout. |
| **`cmd3.lua`** | Conditional phrase commands `I55` (play-count bitmask skipping odd passes) and `J22` (accumulating `+2` semitone transpose per pass). |
| **`save.lua`** | **M8 Gate**: Full WRAM Song Block (`$7E:2000–$72FF`) save to SRAM, independent Lua planar+RLE decode verification, WRAM wipe + reload byte-for-byte check, and persistence across `emu.reset()`. |
| **`pack.lua`** | `SNDJ1` v2 dense variable-length heap compaction and CRC-16 verification across multiple saves, larger slot overwrites, and `CLEAR`. |
| **`namesave.lua`** | Name-keyed `SAVE` and inline character renaming on `(EMPTY)` (`SH_NAME`) vs saved SRAM slots (`SRAM $0018+`). |
| **`files.lua`** | `FILES` menu with 2-step `SURE?` confirmation: `PURGE PH`, `PURGE CH`, `SAVE`, `CLEAR`, `LOAD` on `(EMPTY)` (`NEW SONG` + `echo_auto_edl`), and `CANC`. |
| **`echo.lua`** | **M9 Gate**: `ECHO` screen, safe `EDL` reconfiguration (`0 -> 4`, verifying ARAM directory `$1000+` and sample bytes `$1200+` are uncorrupted), FIR preset recall, `EON` mask, and `Y03`/`E00` commands. |
| **`fir.lua`** | `FIR` screen tap nudging (`SH_FIRTAPS` -> `DSP $0F..$7F`, setting `SH_FIR = $FF` custom) and `Y+Up/Down` preset recall. |
| **`wave.lua`** | **M10 Gate**: Boot wave compilation to ARAM `$1100+` (directory `56..63`), concert-tuned `WAV` pitch (`C-4 = $0430`), `B02` wave sequencing, `NSE` noise clock modes, live `WAVE` screen bar editing, and `shot-wave.png` golden. |
| **`pool.lua`** | **M11 Gate**: `SNDJPOOL` v2 header, silent stub at `$1200`, resident sample mapping in `pool_map`, and `KIT` slot trigger/volume scaling. |
| **`sync.lua`** | **M12 Gate**: External clock injection on `$804017` (Port 2 Data1) and `$804201` (IOBit) across `SYNC: IN`, `SYNC: IN24` (6 clocks/row), and `SYNC: PULSE` (2 PPQN output). |
| **`live.lua`** | **M13 Gate**: `Select` toggle to `LIVE`, `A+B` launch and quantized phrase-boundary chain switching (`trk_pending`), `X+D-pad` mute/solo, and `shot-live.png` golden. |
| **`livecue.lua`** | `LIVE` cue/stop lifecycle: boot `$FF` pending init, halted-track bar-boundary launch (`eng_barflag`), `A+B` queued stop (`$FE`), and plain `B` safety on occupied cells. |
| **`live_mint.lua`** | `LIVE` double-tap `B` minting/cloning chains without starting playback. |
| **`midi.lua`** | **M14 Gate**: Bit-banged 2-wire `SYNC: MIDI` frames over `$804017`/`$804201`: Note On/Off, velocity scaling, Pitch Bend, Program Change, CC 7, MIDI Panic, and mode exit cleanup. |
| **`slice.lua`** | `SLICE` instrument (`type 4`): ARAM alias generation, modulo slice selection, synthesized `ATK+FADE` ADSR, `TUNE` pitch shift, `CHAIN TSP` slice rotation, and `TABLE TSP` per-tick slice sequencing. |
| **`karp.lua`** | `KARP` instrument (`type 5`): plucking A-5 and C-6 at `EDL 1`, verifying exciter SRCN, partial pitch, burst ADSR, `EFB == SUSTAIN`, 2-tap interpolating FIR weights, and auto-clamping `SH_EDL` to `1` when selecting `KARP` on `INSTR`. |
| **`loop.lua`** | Per-instrument `SMP` `LOOP` override (`POOL` / `ON` / `OFF` in `rec[7]` bits 1–2) generating zero-copy ARAM directory aliases with loop pointers aimed at start vs `$1200` silent stub. |
| **`table.lua`** | Per-tick and note-sync (`TBS=0`) `TABLE` automation: `V` volume, `TSP` transpose (including explicit `00` `$80` reset), `M30` command, `H02` table loop, and `TBL --` disable. |
| **`tune.lua`** | Sub-semitone `FINE` (`rec[6]`, including negative borrow) and coarse semitone `TUNE` (`rec[9]`) across `SMP`, `WAV`, and `KARP`. |
| **`vibtrm.lua`** | Instrument-level `VIB` (`rec[14]`) and `TRM` (`rec[15]`), `V00` single-note vibrato suppression, and `X20` accent retargeting `TRM` base volume. |
| **`mint.lua`** | Double-tap `B` minting and cloning across `SONG` (`SLIM` vs `DEEP` chain clone), `CHAIN` (phrase clone), and `INSTR` (`TBL` field table mint/clone). |
| **`block2d.lua`** | 2D rectangular block selection, copy, and paste on `SONG` and `CHAIN`, plus `TABLE` `TSP` `B`-tap `$80` (`00`) insert and `B+Up` `+12` octave nudge. |
| **`chordtap.lua`** | `B`-tap auditioning of `C47` 3-voice chords in `PHRASE` (and inert `B`-tap on non-`C` commands). |
| **`arp_screen.lua`** | Regression check verifying `INSTR` screen idle frame optimization so `A47` arpeggio never drops ticks while viewing `INSTR`. |
| **`nav.lua`** | Complete `A + D-pad` screen navigation graph and `Y + Up/Down` phrase-walking within a chain. |
| **`chan.lua`** | `L/R` and `Y + Left/Right` track switching on `CHAIN`. |
| **`entry.lua`** | Mid-song playback entry scanning upward (`@scan_up`) to enter covering chains at the proper offset row while halting empty tracks. |
| **`transport.lua`** | Global `Start` vs contextual `A+B` transport, contiguous chain-block looping, and `walk_guard` empty-chain hang protection. |
| **`groove.lua`** | `GROOVE` screen editing and playback speed verification. |
| **`project.lua`** | `PROJECT` screen `TSP` song transpose and `MODE` (`SONG`/`LIVE`) toggle. |
| **`options.lua`** | `OPTIONS` `KEY DELAY`, `KEY RATE`, and `TAP WIN` editing and SRAM `$000A–$000C` persistence. |
| **`palette.lua`** | `OPTIONS` palette scheme cycling, 2-colour `pal_buf` CGRAM drain, and SRAM `$0007` persistence across reset. |
