---
title: File Reference — Browser Ecosystem (sndj.js, HTML Tools, Factory & Docs)
category: files
updated: 2026-11-01
sources:
  - user-tools/sndj.js
  - user-tools/patcher.html
  - user-tools/savetool.html
  - user-tools/als2sndj.html
  - user-tools/spcexport.html
  - user-tools/README.md
  - factory/README.md
  - MANUAL.md
  - PALETTE.md
  - ALS.md
  - LINK-SYNC-WIRING.md
  - HARDWARE-TEST-CHECKLIST.md
  - RELEASING.md
  - THIRD_PARTY.md
  - help.txt
---

# File Reference: Browser Ecosystem, Factory Container & Root Docs

All tools in `user-tools/` are offline-capable, zero-dependency static HTML/JS files that work directly from `file://` in a browser and can also be imported in Node.js for automated testing (`make test`).

See also: [`overview.md`](overview.md), [`files-toolchain-and-tests.md`](files-toolchain-and-tests.md), [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

---

## 1. `user-tools/sndj.js` (93.5 KB — The Shared Core Library)
Exported as `window.SNDJ` in browsers and `module.exports` in Node.js (`node user-tools/sndj.js --selftest`).
- **Constants & Format Geometry**:
  - `BLOCK_SZ = 0x5300`, `PHRASES_OFF = 0x2300`, `CHAINS_OFF = 0x1700`, `SRM_SIZE = 0x8000`, `SRM_SLOTS = 16`, `SRM_HEAP = 0x0110`, `SRM_HEAP_SZ = 0x7EF0`.
  - `POOL_RESERVED = 0x27FFA`, `POOL_BANK0_SPAN = 0x7FFA`, `POOL_BANK_SPAN = 0x8000`, `POOL_MAX_ENTRIES = 56`.
  - `SEQ_SB` (section offsets) and `SEQ_SH` (song header offsets).
- **Subsystems Implemented in `sndj.js`**:
  1. **Bit-Exact S-DSP BRR Codec**: `brrEncode(samples, loopBlock)`, `brrDecode(bytes)` (mirrors `tools/sndj_brr.py`).
  2. **SF2 & WAV Importer**: `sf2Parse`, `sf2Melodic`, `sf2Oneshot`, `sf2Resample` (uses `pyRound` round-half-to-even to match Python `round()`), `wavInfo`, `wavBuild`.
  3. **`SNDJPOOL` v2 Builder & Parser**: `poolParse`, `poolBuild` (inserts 9-byte `$FF` bank-boundary padding via `poolBankPad`), `aramBudget`.
  4. **Planar Image, RLE Codec & `SNDJ1` Save Containers**: `toImage`, `fromImage`, `rlePack`, `rleUnpack`, `crc16`, `srmNew`, `srmParse`, `srmExtract`, `srmInsert`, `srmErase`, `srmLayout`, `sndjFileBuild`, `sndjFileParse`.
  5. **ROM Marker & Checksum Utilities**: `findMarker(rom, marker)` (returns offset immediately after the ASCII marker), `fixChecksum(rom)`, `pitchForNote(note)`, `karpEntry(m, edl)`.
  6. **Sample-Accurate S-DSP Emulator (`dspNew`, `dspWrite`, `dspRun`)**: Clean-room JS port of the SNES S-DSP (4-tap Gaussian interpolation `GAUSS`, BRR block decoding, hardware ADSR/GAIN counter envelopes, LFSR noise, `PMON` pitch modulation, stereo volume/phase, and echo buffer + 8-tap FIR feedback loop).
  7. **Reference Sequencer (`seqAramBuild`, `seqNew`, `seqTick`, `seqTickRun`, `seqRender`)**: Mirrors `src/pool.asm`, `src/wave.asm`, `src/apu.asm`, and `src/engine.asm` at ~100x real-time so browser tools can play songs, render WAVs, and capture `.spc` files without an emulator.

---

## 2. Browser HTML Tools (`user-tools/*.html`)

### `user-tools/patcher.html` (71 KB)
- **Role**: Six-tabbed ROM customization workshop and `factory/factory.sndjfact` authoring environment.
- **ROM Binary Markers Patched In-Place**:
  - `SNPOOL` (Bank 1 `$8000`): Up to 163,834 B (`0x27FFA`) `SNDJPOOL` v2 sample pool.
  - `SNPAL0` (Bank 6): 128 B (8 schemes × 16 B).
  - `SNKIT0` (Bank 6): 1,024 B (16 kits × 16 slots × 4 B).
  - `SNDEF3` (Bank 6): 24 B (`types[8]`, `samples[8]`, `extras[8]`).
  - `SNFIR0` (Bank 6): 64 B (8 FIR presets × 8 signed tap bytes).
  - Recomputes SNES checksum via `SNDJ.fixChecksum` on ROM export.
- **Tabs**:
  1. **POOL**: Drag-and-drop `.sf2` or `.wav` import, bit-exact S-DSP Gaussian audition, C-5 reference tone, `tuneSemis`/`tuneFine` sliders, slot reordering (which automatically updates sample indices in `SNKIT0` and `SNDEF3`), and live ROM / ARAM budget bars.
  2. **BOOT**: Configures the 8 boot instruments (`I0..I7`) stored in `SNDEF3`.
  3. **KITS**: Edits all 16 factory drum kits (`SNKIT0`) with browser audition.
  4. **SLICES**: Transient slice previewer and equal-division BRR slicer/baker.
  5. **FIR**: Interactive 8-tap FIR filter designer with live dB frequency-response plot, sum overflow warning (`> 127`), echo room audition, and interactive `KARP` Karplus-Strong string pluck audition.
  6. **PALETTES**: 15-bit BGR color picker for the 8 two-color UI schemes (`SNPAL0`).

### `user-tools/savetool.html` (15.2 KB)
- **Role**: Browser manager for 32 KB `.srm` / `.sav` battery saves and standalone `.sndj` song files.
- **Features**: Lists all 16 SRAM slots (song name, phrase/chain count, packed byte size, CRC-16 validity), extracts/inserts `.sndj` files, renames songs, deletes slots with heap compaction, renders a read-only tracker view (`SONG`/`CHAIN`/`PHRASE`), and plays any slot live in-browser via WebAudio (`SNDJ.seqNew` + `SNDJ.dspRun`).

### `user-tools/als2sndj.html` (33.7 KB)
- **Role**: Bidirectional converter between Ableton Live Sets (`.als` gzipped XML), Standard MIDI Files (`.mid`), MML text, and `.sndj` song files. Tested in Node by `tools/test_als.js` via `window.ALS2SNDJ` / `module.exports`.
- **Features**: Maps up to 8 tracks (`V1..V8`), deduplicates 16-row phrases and 16-step chains, maps velocity to `X` command (`00..7F`), writes `OFF` (`97`) at note ends, imports master tempo (`80..255` BPM), and includes a built-in `SONG`/`CHAIN`/`PHRASE` viewer.

### `user-tools/spcexport.html` (23.6 KB)
- **Role**: Offline 32 kHz stereo `.wav` renderer and standalone `.spc` file exporter (`SNES-SPC700 Sound File Data v0.30`). Tested in Node by `tools/test_spc.js` via `window.SPCX` / `module.exports`.
- **How `.spc` Export Works**:
  - `spcCapture(block, pool)` runs the JS reference sequencer (`SNDJ.seqNew`/`seqTick`), logs all S-DSP register writes and tick delays into a compact opcode stream (`< $80` = write `reg, val`; `$FE` = wait 1 tick; `$FD nn` = wait `nn` ticks; `$FC tt` = Timer-0 target; `$FB` = KOF delay; `$FF` = loop), detects the first structural loop point (`stateKey`), and places the stream into free ARAM between `seq.sampleEnd` and `esaStart` (`ESA << 8`).
  - `buildReplayer` assembles a ~100-byte standalone SPC700 player at ARAM `$0200` using a built-in table-driven mini-assembler (`spcAsm`).

---

## 3. Factory Container & Root Documentation Files

- **`factory/factory.sndjfact` (39,884 bytes)** & **`factory/README.md`**:
  - Binary `SNDJFACT` v4 container holding the copyright-cleared factory sample pool (`plen` bytes), kits (`1,024` B), boot instrument defaults (`24` B), FIR presets (`64` B), and palette schemes (`128` B). Read at build time by `tools/sndj_pool.py` and `tools/maketables.py`; imported/exported in the browser by `user-tools/patcher.html`.
- **`CLAUDE.md`**: Master architectural plan, sibling contract, milestone definitions (`M1–M16`, `M-KARP`), and hard invariants (§20).
- **`MANUAL.md`**: Complete musician's reference manual.
- **`SAVEFORMAT.md`**: Byte-level specification of the `$5300`-byte WRAM Song Block, 16-byte instrument record, `SNDJ1` v2 SRAM directory/heap, column-planar staging image, and RLE/CRC-16 algorithms.
- **`HARDWARE.md`**: Real-silicon bring-up notes (APU mailbox port read glitch during write, SRAM `$FF` power-on state, Mesen 2 vs. hardware `ENVX` differences, verified Mega Drive `genmddj OUT` -> SNES `sndj IN` wiring).
- **`LINK-SYNC-WIRING.md`**: Pin-by-pin wiring guides for Controller Port 2 (`Data1` pin 4, `Data2` pin 5, `IOBit` pin 6, `GND` pin 7) for XIAO ESP32-C3 Ableton Link (`IN24`) and Mega Drive (`genmddj`) row sync.
- **`HARDWARE-TEST-CHECKLIST.md`**: Real-hardware validation checklist (FXPak Pro, NTSC/PAL timing, echo reconfiguration, SRAM power-cut safety, sync/MIDI).
- **`PALETTE.md`**: Explains the 2-colour BG3 2bpp architecture, normal vs. inverted glyph sets, and the 8 factory schemes.
- **`ALS.md`**: Specification for `user-tools/als2sndj.html` and the MML grammar.
- **`RELEASING.md`**, **`THIRD_PARTY.md`**, **`CHANGELOG.md`**, **`help.txt`**: Release runbook, clean-room/license provenance, version history, and source text for the 7-page in-ROM `HELP` screen.
