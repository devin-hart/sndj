---
title: Project Overview, Sibling Contract & Build Pipeline
category: architecture
updated: 2026-11-01
sources:
  - README.md
  - CLAUDE.md
  - Makefile
  - MANUAL.md
---

# `sndj` Overview & System Architecture

**sndj** (current version `0.15`) is an LSDJ-inspired music tracker for the **Super Nintendo / Super Famicom (SNES/SFC)**, written in **65816** (S-CPU) and **SPC700** (APU) assembly.

It is the third sibling in the tracker family alongside:
- **`smsggdj`** (Sega Master System / Game Gear — Z80 + SN76489 PSG)
- **`genmddj`** (Sega Mega Drive / Genesis — 68000 + Z80, YM2612 + SN76489)

See also: [`memory-and-hardware.md`](memory-and-hardware.md), [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md), [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

---

## 1. Core Architectural Pillars

### 1.1 S-CPU Owns Everything; SPC700 is a Pure Chip Servant
Following the `genmddj` model:
- **65816 (S-CPU, FastROM 3.58 MHz)**: Owns the entire song block in WRAM (`$7E:2000–$7E:72FF`), all 15 UI screens, joypad input, the 8-track sequencer, per-tick LFOs/tables, SRAM packing/journaling, and external sync/MIDI.
- **SPC700 (APU, 1.024 MHz / 24.576 MHz crystal)**: Holds **zero song state**. Its 308-line resident driver (`src/apu/driver.asm` at ARAM `$0200`) does four things:
  1. Generates the region-free master musical tick via **SPC700 Timer 0** (`8000 Hz / divider`) and publishes the tick counter on `APUIO3` (`$2143`) along with pairs of live voice `ENVX` values on `APUIO1/2`.
  2. Accepts single S-DSP register writes (`CMD_DSP_WRITE = $01`) via the 4-byte mailbox (`$2140–$2143`) with a flip-bit sequence echo handshake and double-read hardware glitch protection.
  3. Accepts 3-byte-per-round bulk ARAM uploads (`CMD_UPLOAD = $02`) for resident BRR samples, compiled single-cycle wavetables, and the 64-entry ARAM sample directory (`$1000`).
  4. Executes the erratum-safe echo buffer reconfiguration sequence (`CMD_ECHO_CFG = $04`) whenever `EDL` or `ESA` changes.

### 1.2 Region-Free Musical Timebase
Because the SNES APU has its own **24.576 MHz crystal** on both NTSC and PAL consoles, pitch and tempo are 100% region-independent.
- `NMI` (VBlank, 60 Hz NTSC / 50 Hz PAL) handles **only** DMAing the 2 KB BG3 tilemap shadow (`SHADOW_BG3 = $0400–$0BFF`) to VRAM, draining CGRAM palettes (`pal_buf`/`pal_buf2`) when dirty, reading controller 1 (`JOY1L`), and setting `frame_flag = 1`.
- The sequencer runs in `main_loop` (never inside NMI) whenever `apu_tick` advances (or when external `SYNC_IN` / `SYNC_IN24` clocks arrive).

### 1.3 Homogeneous 8-Voice S-DSP Architecture
Unlike `smsggdj` and `genmddj`, all 8 tracks (`V1`–`V8`) map 1:1 to identical S-DSP voices (`0`–`7`). Every track can play any of the **6 instrument types**:
- `0 = SMP` (Melodic BRR sample from the ROM pool)
- `1 = KIT` (16-slot drum kit, note selects slot `0..15`)
- `2 = WAV` (Drawn 32-sample single-cycle wavetable in `SB_WAVES`, compiled live to a 2-block looped BRR in ARAM `$1100+`)
- `3 = NSE` (S-DSP hardware noise generator via `NON` and global `FLG` noise clock `0..31`)
- `4 = SLICE` (Zero-copy ARAM directory aliases slicing a pool sample into `2..16` equal block-aligned divisions)
- `5 = KARP` (Karplus-Strong plucked string synthesis using the S-DSP hardware echo feedback loop + 2-tap interpolating FIR filter)

---

## 2. Control Grammar & 2D Screen Map

### 2.1 Held-Modifier Control Grammar (⚖ Settled)
The button already held when the second button arrives selects the action (zero simultaneous-press timing windows):

| Input | Action |
| :--- | :--- |
| **D-pad** | Move cursor |
| **B (tap)** | Insert default/last value into empty cell; audition occupied note/chord/kit/instrument |
| **B (hold) + D-pad** | Coarse (`Up/Down`) or fine (`Left/Right`) value nudge |
| **B (double-tap)** | Paste active clipboard (within `opt_tapwin` frames), or **Mint** (on empty cell) / **Clone** (on occupied cell) a chain, phrase, or table |
| **B (hold) + A** | Cut cell (or active block selection) to insert buffer / clipboard (`WAVE` screen: stamp preset wave) |
| **B (hold) + Y** | Copy cell (or active block selection) to insert buffer / clipboard |
| **Y (hold) + B** | Begin/confirm 2D rectangular block selection (`SONG`, `CHAIN`, `PHRASE`) |
| **Y (hold) + Left/Right** | Previous / next channel (`0..7`), or wave bank on `WAVE` |
| **Y (hold) + Up/Down** | Page up/down (`±16` rows on `SONG`), prev/next phrase/chain/instrument/kit/table, or recall FIR preset (`0..7`) on `FIR` |
| **A (hold) + D-pad** | Navigate the 2D screen map |
| **A (hold) + B** | Contextual play/stop (`SONG`: play from cursor row; `CHAIN`/`PHRASE`: solo-loop current chain/phrase; `LIVE`: queue/stop clip; `FILES`: open action menu) |
| **A (hold lone 2.5s)** | Global hotkey to toggle `HELP` screen from anywhere |
| **Start** | Play / stop song from cursor row (or exit splash screen at boot) |
| **Select** | Toggle `LIVE` performance launcher from any screen and return to previous screen |
| **L / R** | Channel `-` / `+` (`0..7`) |
| **X (hold) + Up/Down** | Toggle track mute (`SONG` / `LIVE`) |
| **X (hold) + Left/Right** | Toggle track solo (`SONG` / `LIVE`) |

### 2.2 The 3×5 Screen Map
Displayed in the top-right chrome (`x=27..31, y=5..7`) and navigated via **A + D-pad**:

```text
[O][P][ ][W][H]      OPTIONS (10)  PROJECT (12)   -          WAVE (7)   HELP (15)
[S][C][P][I][T]      SONG (3)/LIVE CHAIN (2)     PHRASE (1)  INSTR (4)  TABLE (14)
[F][G][K][E][F]      FILES (5)     GROOVE (11)   KIT (9)     ECHO (6)   FIR (13)
```
*(Numbers in parentheses are `ui_mode` / `SCREEN_*` constants in [`src/screens.asm`](../src/screens.asm). `SPLASH` is `0`, `LIVE` is `8` which highlights `S` on the minimap.)*

---

## 3. Build, Test & Verification Pipeline (`Makefile`)

All development follows a deterministic headless verification loop:

1. **`make`** (`all`):
   - Generates `build/buildid.inc` (git short hash + `+` if dirty)
   - Runs `tools/makefont.py` -> `build/font.bin` (3,072 B)
   - Runs `tools/makelogo.py` -> `build/logo.bin` + `build/logo.inc`
   - Runs `tools/makehelp.py` -> `build/help.inc` (from `help.txt` + `tools/commands.csv`)
   - Runs `tools/maketables.py` -> `build/schemes.bin`, `build/kits.bin`, `build/defaults.bin`, `build/tables.inc`, `build/karptab.inc` (reading `factory/factory.sndjfact` if present)
   - Runs `tools/sndj_pool.py` -> `build/pool.bin` (163,834 B, reading `factory/factory.sndjfact` or synthesizing the 48-slot fallback)
   - Assembles `src/apu/driver.asm` with `wla-spc700` + `wlalink` -> `build/driver.spc700.bin`
   - Assembles `src/main.asm` (single translation unit `.INCLUDE`ing 33 hand-written S-CPU `.asm`/`.inc` files plus 5 generated `build/*.inc` files) with `wla-65816` + `wlalink` -> `build/sndj.sfc`
   - Patches SNES header checksum (`$7FDC–$7FDF`) via `tools/fixsum.py` and copies to `build/sndj-<VERSION>-<STAMP>.sfc`.
2. **`make test`** (Host-side unit tests, no emulator required):
   - Verifies `makefont.py` and `maketables.py`
   - Runs `python3 tools/sndj_brr.py --selftest` (BRR encode/decode round-trip)
   - Runs `python3 tools/sndj_rle.py --selftest` (column-planar image + RLE pack/unpack + CRC-16)
   - Runs `node user-tools/sndj.js --selftest` (JS mirror of BRR, RLE, pool, S-DSP, reference sequencer)
   - Runs `tools/test_sf2.py` + `tools/test_sf2.js` (proves byte-identical SF2 resample + BRR output between Python and JS)
   - Runs `node tools/test_als.js` (MML/MIDI/`.als` converter round-trip)
   - Runs `node tools/test_spc.js` (`.spc` capture + micro-emulated SPC700 replayer verification)
   - Parses `<script>` blocks of all 4 HTML tools (`patcher.html`, `savetool.html`, `als2sndj.html`, `spcexport.html`).
3. **`make check`** (Emulator-in-the-loop ground truth via Mesen 2 `--testrunner`):
   - Configures Mesen via `tools/mesen_setup.py`
   - Runs `tools/checks/factory.lua` directly against the untouched ROM
   - Runs the 40 remaining Lua suites in `tools/checks/*.lua` via `tools/check_runner.lua` (which neutralizes SRAM palette to `0` and zeroes pool sample `tuneSemis`/`tuneFine` so pitch assertions test pure engine math).
4. **`make shot` / `make shot-diff`**:
   - Captures headless PNG screenshots via `tools/shot.lua` and compares pixel-by-pixel against `tools/goldens/{splash,phrase,song,instr,wave,live}.png` via `tools/shotdiff.py` (masking the build-stamp scanlines `112..120` on splash and header scanlines `8..16` on screen shots).
