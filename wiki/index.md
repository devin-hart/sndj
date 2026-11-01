---
title: sndj LLM Wiki Index
category: meta
updated: 2026-11-01
---

# `sndj` LLM Wiki — Master Index

Welcome to the persistent LLM knowledge base for **sndj** (Super Nintendo / Super Famicom LSDJ-inspired music tracker). Read this index first when answering questions or planning code modifications.

---

## 1. Meta & Operations
- **[`SCHEMA.md`](SCHEMA.md)** — Wiki architecture, conventions, and rules for `Ingest`, `Query`, and `Lint` operations.
- **[`log.md`](log.md)** — Chronological append-only log of wiki ingests, code syncs, and lint passes.

---

## 2. Architecture, Memory Maps & Hardware Invariants
- **[`overview.md`](overview.md)** — Project identity, sibling contract (`smsggdj` / `genmddj`), S-CPU vs. SPC700 division of labor, 2D screen map, control grammar, and build/test pipeline (`make`, `make test`, `make check`, `make shot-diff`).
- **[`memory-and-hardware.md`](memory-and-hardware.md)** — **MUST READ BEFORE EDITING `src/`**:
  - LoROM Bank Map (Banks 0–6, Bank 0 tight space limit below `$7FC0`, Bank 6 code/data spill via `jml` and `lda.l`)
  - Complete WRAM map (`$0000–$003F` frozen check block, `$0000–$00FF` Direct Page, `$0000–$03F9` **FULL** main enum, `$0400–$0BFF` `SHADOW_BG3`, `$0C00+` overflow enum, `$7E:2000–$7E:72FF` Song Block, `$7E:7400+` clipboard/purge/RLE staging)
  - 65816 Register Width discipline (`A=8, X/Y=16, D=$0000, DB=$80`, `plx`/`ply` 16-bit stack traps)
  - Scratch Variable Ownership (`tmp0..tmp2` vs. `es0..es3` vs. `ui_cnt` vs. `str_buf`)
  - ARAM 64 KB layout (`$0000–$FFFF`), SRAM 32 KB layout (`$70:0000–$70:7FFF`), and a summary of the 6 most edit-relevant Hard Invariants (all 13 live in `CLAUDE.md` §20).
- **[`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md)** — Deep dive into the SPC700 mailbox protocol, bulk upload loop-bit patching, ARAM residency & zero-copy directory aliases, the 6 instrument types (`SMP`, `KIT`, `WAV`, `NSE`, `SLICE`, `KARP`), the 25 row/table commands (`row_cmd_pre` vs. `row_cmd_post`), 16-bit interpolated pitch math, Echo/FIR erratum-safe reconfiguration, and external Sync/MIDI hardware protocols.
- **[`subsystems-graphics-and-ui.md`](subsystems-graphics-and-ui.md)** — Complete SNES PPU architecture, VRAM/CGRAM layout, Mode 0–7 technical breakdowns, and modernization avenues (BG1/BG2 waveform visualization, dynamic tile oscilloscopes, hardware sprites/OAM, HDMA gradients, and Mode 5 80-column high-res layout).

---

## 3. Complete File-by-File Functional Reference
Every file in the repository is cataloged with its exact responsibilities, ROM bank placement, key routines, WRAM/Song Block dependencies, and gotchas:

- **[`files-scpu-core.md`](files-scpu-core.md)** — S-CPU includes, boot, interrupt, and UI framework:
  - `src/snes.inc`, `src/ram.inc`, `src/song.inc`, `src/main.asm`, `src/init.asm`, `src/nmi.asm`, `src/input.asm`, `src/text.asm`, `src/palette.asm`, `src/splash.asm`, `src/screens.asm`
- **[`files-scpu-engine.md`](files-scpu-engine.md)** — S-CPU audio, sequencer, storage, sync, and SPC700 driver:
  - `src/apu/driver.asm`, `src/apu.asm`, `src/pool.asm`, `src/engine.asm`, `src/wave.asm`, `src/clone.asm`, `src/save.asm`, `src/sync.asm`, `src/midi.asm`
- **[`files-scpu-screens.md`](files-scpu-screens.md)** — All 15 tracker UI screens:
  - `src/phrase.asm`, `src/chainscr.asm`, `src/songscr.asm`, `src/instrscr.asm`, `src/filescr.asm`, `src/echoscr.asm`, `src/wavescr.asm`, `src/livescr.asm`, `src/kitscr.asm`, `src/optionscr.asm`, `src/groovescr.asm`, `src/projectscr.asm`, `src/firscr.asm`, `src/tablescr.asm`, `src/helpscr.asm`
- **[`files-toolchain-and-tests.md`](files-toolchain-and-tests.md)** — Build system, Python/JS build & test scripts, and all 41 Mesen 2 Lua check suites:
  - `Makefile`, `tools/commands.csv`, `tools/fixsum.py`, `tools/makefont.py`, `tools/makehelp.py`, `tools/makelogo.py`, `tools/maketables.py`, `tools/mesen_setup.py`, `tools/savetool.py`, `tools/shotdiff.py`, `tools/sndj_brr.py`, `tools/sndj_pool.py`, `tools/sndj_rle.py`, `tools/test_sf2.py`, `tools/test_sf2.js`, `tools/test_als.js`, `tools/test_spc.js`, `tools/check_runner.lua`, `tools/shot.lua`, and `tools/checks/*.lua` (41 files)
- **[`files-browser-ecosystem.md`](files-browser-ecosystem.md)** — Shared JS reference engine/DSP model, browser HTML tools, factory container, and root docs:
  - `user-tools/sndj.js`, `user-tools/patcher.html`, `user-tools/savetool.html`, `user-tools/als2sndj.html`, `user-tools/spcexport.html`, `factory/factory.sndjfact`, and all root `.md` / `help.txt` files.

---

## 4. Modification Playbooks, Cross-File Sync & Lint Log
- **[`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md)** — **MUST READ BEFORE MAKING CODE CHANGES**:
  - Step-by-step recipes for:
    1. Adding or modifying a UI screen
    2. Adding or modifying a tracker command (`A–Z`)
    3. Adding or modifying an instrument parameter or instrument type
    4. Modifying the sequencer engine or APU communication
    5. Spilling code from Bank 0 to Bank 6 when Bank 0 fills up
    6. Adding a new WRAM variable safely
  - **Cross-File Synchronization Matrix**: Exact list of files across `src/`, `tools/`, `user-tools/`, and `tools/checks/` that must change in lockstep when touching save format, pool geometry, BRR codec, factory markers, pitch math, or commands.
  - **Active Codebase Drift & Contradictions**: Known discrepancies between `src/` assembly, `user-tools/sndj.js`, and `CLAUDE.md` discovered during wiki synthesis.
