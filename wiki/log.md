---
title: sndj LLM Wiki Chronological Log
category: meta
updated: 2026-11-01
---

# `sndj` Wiki Log

Append-only chronological record of ingests, syntheses, and lint passes.
Format: `## [YYYY-MM-DD] <ingest|query|lint> | <Title>`

---

## [2026-11-01] ingest | Initial Full-Repository Synthesis (v0.15)
- Ingested all 32 assembly source and include files (`src/*.asm`, `src/*.inc`, `src/apu/driver.asm`), `Makefile`, 16 Python/JS/Lua build and test scripts in `tools/`, 37 emulator-in-the-loop Lua check suites in `tools/checks/*.lua`, 5 browser tools in `user-tools/` (`sndj.js`, `patcher.html`, `savetool.html`, `als2sndj.html`, `spcexport.html`), `factory/factory.sndjfact`, and all 12 root documentation files (`CLAUDE.md`, `README.md`, `MANUAL.md`, `SAVEFORMAT.md`, `HARDWARE.md`, `PALETTE.md`, `ALS.md`, `LINK-SYNC-WIRING.md`, `HARDWARE-TEST-CHECKLIST.md`, `RELEASING.md`, `THIRD_PARTY.md`, `help.txt`).
- Created [`SCHEMA.md`](SCHEMA.md), [`index.md`](index.md), [`overview.md`](overview.md), [`memory-and-hardware.md`](memory-and-hardware.md), [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md), [`files-scpu-core.md`](files-scpu-core.md), [`files-scpu-engine.md`](files-scpu-engine.md), [`files-scpu-screens.md`](files-scpu-screens.md), [`files-toolchain-and-tests.md`](files-toolchain-and-tests.md), [`files-browser-ecosystem.md`](files-browser-ecosystem.md), and [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

## [2026-11-01] lint | Initial Cross-Layer Parity & Contradiction Check
- Flagged 5 concrete drift/contradiction items in [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md):
  1. `user-tools/sndj.js` `seqCmdPost` does not yet implement command `W` (tremolo override, `CMDID_W = 23`), whereas `src/engine.asm` and `tools/checks/commands.lua` implement and test it.
  2. `user-tools/sndj.js` `seqPitchCalc` applies instrument coarse `TUNE` (`rec[9]`) only to `SLICE`, whereas `src/apu.asm` (`trig_tune_load`) and `tools/checks/tune.lua` apply `rec[9]` across `SMP`, `WAV`, `SLICE`, and `KARP`.
  3. `user-tools/sndj.js` `seqTrackTable` checks `tsp !== 0` with signed byte cast without stripping the `$80` explicit-zero sentinel (`TSP 00` reset) implemented in `src/engine.asm` and `src/tablescr.asm`.
  4. `src/songscr.asm` line 216 hardcodes `#25` for the double-tap B frame window instead of reading `opt_tapwin` (unlike `phrase.asm`, `chainscr.asm`, `instrscr.asm`, and `livescr.asm`).
  5. `CLAUDE.md` §10 still notes "`W` is dropped / 24 live commands" in prose from 2026-07-09, whereas `README.md`, `MANUAL.md`, `tools/commands.csv`, and `src/engine.asm` ship 25 live commands (`W` = tremolo override; only `O` is unused).

## [2026-11-01] lint | Claude verification pass against src @ 857faf3
- Verified all 5 drift items from the initial lint against source: all confirmed.
- Corrected scratch addresses in [`memory-and-hardware.md`](memory-and-hardware.md): `tmp0..2` = `$0065/$0067/$0069` (was `$0054/$0056/$0058`), `es0..es3` = `$017D–$0184` (was `$00C9–$00D0`; **not** Direct Page), `str_buf` = `$019C` (was `$019B`), `trk_voll` = `$0358` (was `$0359`), `midi_*` ends `$0397`.
- Rewrote the self-contradictory `tmp1` row (removed stray reasoning text).
- Fixed counts: 41 Lua checks (was 37), 40 non-factory suites (was 36), 33 hand-written + 5 generated includes in `main.asm` (was 29). Source file total is 35 (initial log said 32; left as historical).
- Index now states 6 invariants are summarized; `CLAUDE.md` §20 holds all 13.
- **New finding — drift #6**: `.ENUM $0000` computes to end at `$0402`; `pal_buf2` overlaps `SHADOW_BG3` by 2 bytes. Recorded in [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md). Not fixed in code.

## [2026-11-01] ingest | Code fixes for drift #1–#4 and #6 (Claude)
- `src/ram.inc`: `pal_buf2` moved from `$03FA` (main enum) to `$0C24` (overflow enum). Main enum now ends at `$03FA`.
- `src/songscr.asm`: double-tap window now reads `opt_tapwin` (same as `phrase.asm`). Default is 24, so behaviour at default is unchanged.
- `user-tools/sndj.js`: `W` command, `TUNE` for SMP/WAV/KARP, and table `TSP $80`, all matching the console.
- Wiki: drift items marked resolved; memory map, SRAM tap-window default (24, not 18), and the `pitch_octave7` paragraph in [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md) corrected (it contained leftover reasoning and a wrong octave).
- Details and evidence: `REPORT.md`.

## [2026-11-01] ingest | Performance changes P1, P3, P4 (Claude)
- `src/main.asm`: `main_loop` checks `frame_flag` before `wai`; the IN24 wake path re-enters at `main_loop`. `draw_minimap` uses `minimap_x`/`minimap_y` tables.
- `src/text.asm`: new `text_inv`; `text_puts` hoists the inverted-glyph test out of its per-character loop; `text_hex8` makes one `text_dest` call for both digits.
- `user-tools/sndj.js`: `dspRun` can render into caller-owned arrays; `seqTickRun` uses that; `brrEncode` no longer allocates per block or per sample (byte-identical output).
- Updated [`files-scpu-core.md`](files-scpu-core.md). Details and evidence: `CLAUDE-REPORT.md`.

## [2026-11-01] ingest | SNES Graphics Architecture & UI Modernization Reference (Gemini)
- Created [`subsystems-graphics-and-ui.md`](subsystems-graphics-and-ui.md): comprehensive reference on SNES PPU Modes 0–7, VRAM/CGRAM layout, Mode 1 background priority rules, dynamic tile blitting for oscilloscopes/visualizers, hardware sprites/OAM, HDMA raster effects, and Mode 5 80-column / fine tracker possibilities.
- Updated [`index.md`](index.md) to index the new graphics subsystem document.
- Expanded section 6 of root [`REFERENCE.md`](../REFERENCE.md) with PPU mode tables and UI modernization notes.

## [2026-11-01] lint | First real build (Claude, WLA-DX built from source)
- `make all` and `make test` pass at `857faf3` and on the working tree. The assembler (`.PRINTV`) confirmed every `ram.inc` address in [`memory-and-hardware.md`](memory-and-hardware.md), and confirmed drift #6 (`pal_buf2` was at `$03FA`; now `$0C24`).
- Bank 0 free space measured: 1,208 bytes (was 1,276). [`memory-and-hardware.md`](memory-and-hardware.md) no longer says it is "packed tightly".
- `make check` / `make shot-diff` not yet run (Mesen 2 isn't available in the build sandbox). See `check-windows.ps1` and `CLAUDE-REPORT.md`.


## [2026-11-01] lint | First `make check` + `make shot-diff` run (Claude, Mesen2 2.1.1 built from source, headless)
- All 41 Lua suites, `factory.lua` and the 6 screenshot goldens pass on both `857faf3` and the working tree, after one test-timing fix in `tools/checks/cmd2.lua` (S0F sweep window; see `CLAUDE-REPORT.md`).
- Measured main-loop rate per screen with a busy 8-track song (iterations per 120 frames): SONG playing 45→60, PHRASE 80→120, LIVE 45→60, SONG stopped 60→77; CHAIN/INSTR already 120. SONG and LIVE still run at about 30 fps, so redraw cost (P2) is the next target.

## [2026-11-01] ingest | P2: SONG/LIVE redraw gating (Claude)
- `src/songscr.asm`: `song_draw` → `song_draw_changed` (snapshot compare) → `song_draw_full` only on change. `src/ram.inc`: `sd_*` vars at `$0C2C–$0CE0`. `src/text.asm`: `text_clear` invalidates the snapshot.
- `tools/checks/table.lua`: the base pitch is now sampled at the trigger (by state) instead of at fixed frame 48 (another timing-calibrated check, like `cmd2`).
- Updated [`files-scpu-screens.md`](files-scpu-screens.md), [`files-scpu-core.md`](files-scpu-core.md) and [`memory-and-hardware.md`](memory-and-hardware.md) (bank 0 now 977 bytes free).

## [2026-11-01] ingest | residency_refresh: sample swaps upload only the new sample (Claude)
- `src/pool.asm`: `residency_refresh` + `res_dirent`; `residency_build` now clears `res_addr` and is the compacting path. `src/instrscr.asm` (SAMPLE/SLICES/LOOP) and `src/kitscr.asm` call the refresh; `src/echoscr.asm` compacts on entry when `res_frag` is set. `src/ram.inc`: `res_addr` etc. at `$0CE1–$0D65`.
- Updated [`files-scpu-engine.md`](files-scpu-engine.md) and [`memory-and-hardware.md`](memory-and-hardware.md) (bank 0 now 837 bytes free).

## [2026-11-01] update | Clarified PPU font transparency, oscilloscope telemetry, and OBJ palettes (Gemini)
- `wiki/subsystems-graphics-and-ui.md`: Updated §3 intro, §3.1, §3.2, and §3.3 to document that plain font glyphs render on transparent color 0 (`tools/makefont.py:10`) showing background layers through normal text cells unless window-masked; clarified that dynamic oscilloscopes require SPC700 mailbox telemetry (cannot read S-DSP `VxOUTX` directly); clarified that hardware sprites use CGRAM colors 128–255 (OBJ palettes 0–7) distinct from BG palettes 0–7.

## [2026-11-01] ingest | UI rewrite branch: hi-res renderer, FRAME editor, HI-RES option (Claude)
- Branch `ui-rewrite` (from tag `v0.15-perf`). New bank-7 code: `src/hires.asm` (Mode 5 two-layer 64-column text, hi-res SONG) and `src/framescr.asm` (FRAME editor, `SCREEN_FRAME` = 16). New tool `tools/makehrfont.py`; new check `tools/checks/frame.lua`.
- OPTIONS field 7 `HI-RES` (SRAM `$000D`, default off). Off: every screen is classic Mode 1; FRAME uses a 3-track side-scrolling view.
- `src/ram.inc`: overflow block now ends `$0DA6` (`ui_hires`, `ui_xoff`, `hr_*`, `opt_hires`, `fr_*`); `SHADOW_HRB` = `$0E00–$14FF`. Bank 0: 608 bytes free; bank 7: 10.7 KB free.
- The wiki pages are not yet updated for this branch; they describe `perf-and-fixes`.
