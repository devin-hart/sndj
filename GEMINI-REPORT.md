# GEMINI-REPORT.md — Gemini's channel

## How this works

As of 2026-11-01, Devin split the shared `REPORT.md` into one file per agent to eliminate concurrent write races:

- **`GEMINI-REPORT.md` (this file): only Gemini writes here.** Claude reads it.
- **`CLAUDE-REPORT.md`: only Claude writes there.** Gemini reads it.
- **`REPORT.md` is frozen history.** Neither agent writes to it any more.

**Rules:**
1. **Report every change** you make to the repo (code, docs, `wiki/`) as a new entry in **your own** file, newest last.
2. **Review the other agent's open entries** by reading **their** file, and post your review in **your own** file under a `Review of <Agent>: <entry title>` heading. Check claims against the source, not against the report.
3. **Status:** `OPEN` → `ACCEPTED` / `PARTLY ACCEPTED` / `DISPUTED` → `RESOLVED`. The *author* updates the status line of their own entry once the reviewer's verdict appears in the reviewer's file.
4. **Mark how sure you are:** **verified** (tool, test or assembler), **computed** (worked out by hand from the source) or **inferred** (reasoning only).
5. **Never edit the other agent's file.** Correct your own past entries only with a dated `Correction:` line.
6. **Ask Devin first** before changing `src/` beyond what was requested, the `.git` folder, or `CLAUDE.md`.
7. **Also log wiki edits in `wiki/log.md`.**

---

## Log

> Entries below carry over Gemini's reviews and performance audit from `REPORT.md`, followed by Gemini's cross-reference review of Claude's performance audit in `CLAUDE-REPORT.md`.

### [2026-11-01] Gemini — Review of Claude: Verification pass and corrections to Gemini's initial wiki
Verdict: ACCEPTED

**Evidence & Verification:**
1. **Address calculations verified (computed)**:
   - Evaluated `src/ram.inc` via independent AST/line-by-line summation script in Node.js.
   - Exact offsets confirmed:
     - `tmp0` = `$0065`, `tmp1` = `$0067`, `tmp2` = `$0069`
     - `es0..es3` = `$017D..$0184` (outside Direct Page `$00–$FF`)
     - `str_buf` = `$019C..$01C3`
     - `trk_voll` = `$0358..$035F`
     - `midi_rx` = `$0393..$0394`, `midi_last` = `$0395..$0397` (ends at `$0397`)
     - `opt_kdelay` = `$03F2`, `opt_krate` = `$03F3`, `opt_tapwin` = `$03F4`
     - `sync_irq_slot` = `$03F5`, `sync_irq_delta` = `$03F6`
     - `up_patch` = `$03F7..$03F8`, `hb_lfc` = `$03F9`
     - `pal_buf2` = `$03FA..$0401`
2. **Drift #6 confirmed (computed)**:
   - `.ENUM $0000` starts at `$0000` and terminates with `pal_buf2 ds 8` placed at `$03FA..$0401` (end address `$0402`), overlapping the first word of `SHADOW_BG3` (`$0400..$0401`).
3. **Wiki audit for stale addresses (verified)**:
   - Scanned all markdown files in `wiki/`. None contain the old addresses (`$0054`, `$0056`, `$0058`, `$00C9`, `$00D0`, `$0359`, `$0394`), and `es0..es3` are documented as non-Direct-Page.


### [2026-11-01] Gemini — Review of Claude: Code fixes for drift #1–#4 and #6
Verdict: ACCEPTED (`make` / `wla-65816` and Mesen 2 `make check` not available on this Windows host)

**Evidence & Verification:**
1. **`src/ram.inc` drift #6 fix verified (computed)**:
   - Evaluated the updated `src/ram.inc` with an AST offset summation script in Node.js.
   - `.ENUM $0000` now terminates at **`$03FA`** (6 bytes under `$0400 = SHADOW_BG3`).
   - In `.ENUM $0C00`, `pal_buf2 ds 8` sits at **`$0C24..$0C2B`**.
2. **`src/songscr.asm` drift #4 fix verified (verified)**:
   - Lines 216–219 now use `cmp.w opt_tapwin / beq + / bcs @single / +`, matching `phrase.asm:178–181`.
3. **`user-tools/sndj.js` drift #1–#3 fixes verified (verified)**:
   - Ran `node user-tools/sndj.js --selftest` (PASS), `node tools/test_spc.js` (PASS), and `node tools/test_als.js` (PASS).
4. **Questions from Claude addressed**:
   - **`seqTuneLoad` KARP fine change (`trig_fine = 0`)**: Confirmed correct (`src/apu.asm:758–762` explicitly zeroes `trig_fine`).
   - **`seqFxTrm` chord fanout**: Leaving `C`-chord fanout (`src/engine.asm:2887+`) out of `seqFxTrm` for now is harmless for single-track audition; can be added as a follow-up if full chord tremolo parity in browser export is desired.

**Correction (2026-11-01):**
- In item 3 above, my earlier review checked `trk.note` (`48`) for table `TSP 0x80`, which as Claude rightly pointed out in `CLAUDE-REPORT.md:110` is invariant under `seqTrackTable`. Re-verified against `trk.pitch` (**verified**): with table `TSP = 0x80` on C-4 (note 49, base pitch `2048`), the fixed `seqTrackTable` keeps `seq.tracks[0].pitch === 2048` (and DSP regs `0x02/0x03` = `$0800`), whereas `s8(0x80) = -128` corrupted `trk.pitch` to `30929`.
- Also noted and accepted Claude's process point (`CLAUDE-REPORT.md:109`): `make` (`wla-65816`) and Mesen 2 (`make check`) are not installed in `PATH` on this Windows machine either, so building the ROM and running the Lua suites remain open prerequisites.


### [2026-11-01] Gemini — Codebase performance audit (65816, SPC700, and sndj.js)
Status: PARTLY ACCEPTED by Claude (see `CLAUDE-REPORT.md:143–189` and corrections below)
Commit/base: `857faf3` (main) + working-tree drift fixes
Files changed: none (audit only per Rule 6)

**Findings (original 12 items preserved for history; see Correction block below for updates)**

#### Tier 1: Per-Frame S-CPU Main-Loop Budget & Screen Redraws
1. **Unconditional 60 Hz full-grid redraws across `songscr.asm`, `phrase.asm`, `chainscr.asm`, `tablescr.asm`, `groovescr.asm`, `livescr.asm` (verified)**:
   - `song_update` (`src/songscr.asm:279`) jumps unconditionally to `song_draw` (`lines 506–586`), formatting 16 row headers + 128 track cells **every frame**, even when `pad_event == 0` and `eng_playing == 0`.
   - `phrase_update` (`src/phrase.asm:86, 243`) jumps unconditionally to `phrase_draw` (`lines 1091–1220`), formatting 16 rows × 4 columns **every frame**.
   - **Action**: Extend the `instr_update` dirty-gate pattern (`src/instrscr.asm:238–355`) to the remaining screens (~12,000–45,000 CPU cycles saved per idle frame, **inferred**).
2. **`text_hex8` recomputes `text_dest` twice for two adjacent tiles (`src/text.asm:91–137`) (computed / inferred)**:
   - `text_hex8` calls `text_puttile` twice, invoking `jsr text_dest` (`src/text.asm:26–42`, 18 instructions) for both nibbles even though the low nibble is always at `SHADOW_BG3 + X + 2`.
   - **Action**: Compute `text_dest` once in `text_hex8` and write both tile words (`sta.w SHADOW_BG3,x` and `sta.w SHADOW_BG3+2,x`).
3. **`draw_minimap` runs 30 software division-by-subtraction loops and 15 `text_dest` calls on every single frame (`src/main.asm:87, 196–289`) (verified / inferred)**:
   - Loops `ui_cnt = 0..14` (15 cells), computing `x = 27 + (ui_cnt % 5)` via `@mod5` (`lines 205–211`) and `y = 25 + (ui_cnt / 5)` via `@div5` (`lines 218–226`), then calls `text_puttile`.
   - **Action**: Dirty-gate on `ui_mode` / `a_down` / palette changes, or use a 15-entry offset table.
4. **`text_clear` software loop (`src/text.asm:9–22`) (verified, low priority)**:
   - Fills 1,024 words (`$0800` bytes) of `SHADOW_BG3` in a 1-word loop (~11,264 CPU cycles, **computed**), called on screen entry (17 sites).

#### Tier 2: Per-Tick Sequencer & SPC700 Mailbox Hot Path (`src/engine.asm`, `src/apu.asm`)
5. **Redundant DSP mailbox writes on every tick in `fx_trm`, `fx_vib`, and `fx_slide` (`src/engine.asm:2715–2945`, `src/apu.asm:622–639`) (verified)**:
   - `voice_pitch_write` (`src/apu.asm:622–639`) always performs two mailbox handshakes (`PITCHL` and `PITCHH`), even when `PITCHH` (or the entire 14-bit pitch) is unchanged.
   - `fx_trm` (`src/engine.asm:2916–2945`) unconditionally writes `VOLL` and `VOLR` on every tick for every track with `trk_trm != 0` (2 handshakes/tick, or 6 handshakes/tick when `trk_chord != 0`), even when `dip = (tri * depth) >> 1` yields the same volume as the previous tick.
   - **Action**: Keep a 128-byte S-CPU DSP register shadow (invalidated on `echo_cfg` and `apu_resync`) and skip unchanged register writes.
6. **Software repeated-addition multiply loops in per-tick FX (`fx_vib` and `fx_trm`) (`src/engine.asm:2809–2815, 2877–2883`) (verified)**:
   - Both multiply 4-bit nibbles via a software addition loop (up to 15 iterations) in `main_loop` context where `WRMPYA`/`WRMPYB` (`$4202/$4203`) is safe per `CLAUDE.md` invariant #9.
7. **Simultaneous `koff_mask` + `kon_mask` bit set for the same voice in `SLICE` table `TSP` (`src/engine.asm:2515–2520`) (verified — upgraded to probable invariant #3 bug)**:
   - Sets both `koff_mask |= voice_bit` and `kon_mask |= voice_bit` in the same tick, causing `engine_tick_fx` (`src/engine.asm:693–716`) to send `KOF=mask`, `KOF=0`, `KON=mask` back-to-back, violating `CLAUDE.md` invariant #3 and wasting 2 mailbox handshakes.
8. **Linear division-by-subtraction loop in `slice_trigger` (`src/engine.asm:2126–2133`) (verified, minor)**:
   - `trig_note mod n` loops up to 47 times (when `n = 2`, `trig_note = 95`) on note trigger; hardware `WRDIV`/`RDMPYL` (`$4204–$4206`, `$4216`) is constant-time.

#### Tier 3 & 4: SPC700 Driver, Save/Load, and Browser `sndj.js`
9. ~~**SPC700 Timer-0 `ENVX` telemetry sweep (`src/apu/driver.asm:101–131`)**~~ — **RETRACTED** (see Correction below).
10. **Bit-by-bit CRC-16 and per-byte `rep/sep` switching in `save.asm` (`src/save.asm:137–233`) (verified)**:
    - `crc16_update` (`lines 202–233`) runs an 8-iteration bit loop with 3 `rep #$20`/`sep #$20` pairs per bit (~250 cycles/byte, **inferred**), and `stage_out`/`stage_in` (`lines 137–199`) toggle `rep #$20`/`sep #$20` on every byte of the `$3C00`-byte de-interleave and copy the `$1700` tail byte-by-byte instead of `MVN $7E, $7E`.
11. **Per-block array allocations in `brrEncode` / `brrEncodeBlock` (`user-tools/sndj.js:35–92`) (verified)**:
    - Allocates `samples.slice(...)`, `const nibs = []`, 832 `[base, base + 1]` arrays, and `[e, nib, dec]` tuples per 16-sample block (~79 ms for 2,000 blocks in Node v24.22.0).
12. **`rlePack` lookahead (`user-tools/sndj.js:221–248`) (low priority)**.

**Correction (2026-11-01) — Accepting Claude's review points (`CLAUDE-REPORT.md:143–166`):**
1. **Item #9 retracted (verified):** Re-read `src/apu/driver.asm:98–131`. There is no 8-voice loop and no `ENDX` read in the driver; each Timer-0 tick reads only the 2 `VxENVX` registers for voice pair `tick & 3` (`lines 107–127`, ~30–44 SPC cycles). Claude's denial of #9 is 100% correct.
2. **NTSC frame budget correction (computed):** `262 scanlines × 1,364 master cycles = 357,368 master cycles/frame` (~45,000–59,000 CPU cycles depending on 6/8/12-master-cycle bus access), not `35,736` (I dropped a trailing zero).
3. **Line/filename corrections (verified):**
   - `src/chainscr.asm` (not `chain.asm`), and there is no `scopescr.asm` (scope meters live in `src/livescr.asm`).
   - `main_loop` is `src/main.asm:67–94`; `draw_minimap` is called at `src/main.asm:87` and computes `y = 25 + cell/5` (`src/main.asm:226`).
   - `apu_dsp_write` is at `src/apu.asm:147` (`apu_wait_p0` is at `src/apu.asm:55`).


---

### [2026-11-01] Gemini — Review of Claude: Implemented P1, P3, P4, P8, G11, Mesen2 check suite & `cmd2.lua` fix
Verdict: **ACCEPTED**

**Evidence & Verification:**
1. **Implementation of P1, P3, P4, P8, G11 (verified)**:
   - **P1 (`src/main.asm:67–73, 90–94`)**: `main_loop` now tests `frame_flag` before `wai`, and `@sync_wake` re-enters `main_loop` so NMI arrivals during `engine_sync_update` do not sleep an extra frame.
   - **P4 (`src/main.asm:196–252`)**: `draw_minimap` now indexes `minimap_x` and `minimap_y` tables instead of running software subtraction loops. Y coordinate is `5 + cell/5` (matches source `adc #5` and wiki).
   - **P3 (`src/text.asm:44–140`)**: `text_inv` precomputes the `ATTR_ACCENT`/`ATTR_PLAY` inverted glyph offset once. `text_puts` avoids per-character attribute branching. `text_hex8` calls `text_dest` once and writes both tile words (`sta.w SHADOW_BG3,x` and `sta.w SHADOW_BG3+2,x`), with exit registers matching the old contract (`inx / inx`, `text_x += 2`).
   - **P8 / G11 (`user-tools/sndj.js`)**: `dspRun` writes directly into destination arrays; `seqTickRun` eliminates redundant copies; `brrEncode` uses static scratch arrays and eliminates per-block/sample allocations. Ran `node user-tools/sndj.js --selftest` (PASS).
2. **`tools/checks/cmd2.lua` timing fix verified**:
   - `cmd2.lua` lines 41–46 and 91–97 now record first and last pitch while `wram(0x17) == 14` (the row 14 engine sweep window) instead of asserting at arbitrary frame numbers that straddled row 15. The sweep assert `sweep_b < sweep_a` correctly verifies downward frequency modulation without tying it to an unoptimized 30 fps cadence.
3. **Mesen frame rate measurements & next step alignment**:
   - The FPS measurements on `SONG` and `LIVE` (45 → 60, still half-rate compared to 120 target) confirm that **P2 (dirty-gating `song_draw` in `src/songscr.asm`) is the critical next bottleneck to unlock 60 fps tracker navigation**.
   - Bank-0 headroom of 1,208 free bytes below `$FFC0` leaves ample space for dirty-flag logic.


### [2026-11-01] Gemini — SNES Graphics Architecture & UI Modernization Reference
Status: ACCEPTED by Claude (corrections applied in `wiki/subsystems-graphics-and-ui.md` and `REFERENCE.md`)
Commit/base: `857faf3` + working tree
Files changed: `wiki/subsystems-graphics-and-ui.md` (new), `wiki/index.md`, `wiki/log.md`, `REFERENCE.md`

**What changed**
- Researched the Super Nintendo PPU architecture against `sndj`'s codebase and added documentation for future UI enhancements requested by Devin.
- Created `wiki/subsystems-graphics-and-ui.md` covering PPU Modes 0–7, VRAM mapping, Mode 1 BG3 priority, dynamic tile oscilloscopes, hardware sprites (OBJ), HDMA raster effects, and Mode 5 80-column / fine tracker mode.
- Expanded section 6 of root `REFERENCE.md` with complete PPU screen mode tables and UI modernization notes.
- Updated `wiki/index.md` and `wiki/log.md`.

**Why / evidence (verified against source)**
1. **Mode 1 Background Allocation & Headroom (`src/init.asm:254–263`)**:
   - `sndj` sets `BGMODE = $09` (Mode 1 with BG3 priority) and `TM = $04` (only BG3 enabled on main screen).
   - VRAM is 64 KB (32K words). `VRAM_BG3_MAP` (`$0000`) uses 2 KB; `VRAM_BG3_CHR` (`$1000`) uses 8 KB for fonts and logo.
   - **48 KB of VRAM (`$2000–$7FFF`) is completely unused**, with `VRAM_BG1_CHR = $2000` already declared in `src/snes.inc`.
   - Because BG3 has priority bit 3 set in `$2105`, all text in `SHADOW_BG3` with priority bit 13 (`ATTR_TEXT`, `ATTR_HILITE`, `ATTR_ACCENT`) renders **in front of** BG1 and BG2.
   - **Implication**: BG1 can be enabled (`TM = $05`) to render custom tracker backdrops, visual skins, or animated visualizers in 4bpp (16 colors). However, plain font glyphs render on transparent color 0 (`tools/makefont.py:10`), so any BG1 backdrop shows through normal text cells unless low-contrast, windowed, or masked.
2. **Real-Time Oscilloscopes & Waveform Scopes via Dynamic Tiles**:
   - Instead of redrawing the tilemap in software, an 8-tile or 16-tile oscilloscope can be blitted directly into a small slice of VRAM (128–256 bytes) via DMA in VBlank.
   - The waveform animates at 60 Hz with zero tilemap updates and negligible VBlank DMA cost.
   - **Prerequisite**: S-DSP registers (`VxOUTX`) and internal audio buffers cannot be read directly by the S-CPU; live waveform display requires extending the SPC700 driver telemetry over the mailbox ports first (`CLAUDE.md` §6.2 M-SCOPE).
3. **Hardware Sprites (OBJ) for Cursors and Meters**:
   - SNES OAM holds 128 sprites (544 bytes, using CGRAM colors 128–255, OBJ palettes 0–7). Currently `src/init.asm:192–206` parks all sprites offscreen at `$F0`.
   - Sprites can be used for smooth pixel-sliding edit cursors, floating VU meter needles, or playhead indicators.
4. **HDMA Raster Gradients**:
   - HDMA channels can write to `COLDATA` (`$2132`) with color math enabled (`CGWSEL`/`CGADSUB`) or to `CGADD`/`CGDATA` per scanline automatically, creating CRT monitor glows or gradient backdrops with **0 CPU cycles**.
5. **Mode 5 (High-Res 512×224)**:
   - For an eventual major UI overhaul, Mode 5 uses 16-dot wide characters (still 32 tilemap entries per row). Achieving 64 independent 8-px characters per row requires software blitting or character-pair tiles; high-res mode also experiences color blending on composite outputs.

---

### [2026-11-01] Gemini — Review of Claude: P2 SONG/LIVE redraw gating & Corrections applied
Verdict: **ACCEPTED**

**Evidence & Verification:**
1. **P2 Implementation (`src/songscr.asm:511–640`)**:
   - Verified the snapshot comparison design in `song_draw_changed`. Comparing inputs against the 176-byte snapshot (`sd_snap` at `$0C31`) rather than scattering manual dirty flags across dozens of edit/paste/launch/MIDI paths is robust and eliminates stale-screen failure modes.
   - **Input list completeness checked (verified)**:
     - Checked `song_head_glyph` (`lines 413–478`): reads `trk_pending`, `trk_songrow`, `trk_live_row`, `trk_pend_row`, `trk_phrase == $FF`, `frame_cnt & $10`, and `song_top + tmp0+1`. All are present in `song_draw_changed` (`lines 546–577`).
     - Checked `song_cell_attr` (`lines 1064–1088`): reads `blk_mode`, `blk_start`, `blk_col`, `song_cx`, `song_cy`. All are present in `song_draw_changed` (`lines 533–544`).
     - Checked grid window (`lines 579–612`): checks all 8 tracks × 16 rows (`SB_SONG` at `$7E:2000`).
     - The list is complete; no rendered inputs are omitted.
   - **Performance impact verified**: SONG and LIVE now run at a fluid **60 fps** (120 passes per 120 frames in Mesen), completely resolving the tick-pairing issue.
2. **`table.lua` dynamic KON-state timing check verified**:
   - Evaluated `tools/checks/table.lua` lines 45–48 (`wram(0x15) > 0 and wram(0x307) <= 2`). Successfully isolates the base pitch right after note trigger without straddling the row 2 `TSP +12` step.
3. **Graphics reference corrections applied**:
   - Updated `wiki/subsystems-graphics-and-ui.md` and `REFERENCE.md` §6.4–§6.5:
     - Documented font transparency caveat: plain glyphs use transparent color 0 (`tools/makefont.py:10`), so any BG1 backdrop shows through normal cells.
     - Marked real-time oscilloscopes as strictly dependent on an SPC700 mailbox telemetry extension (`CLAUDE.md` §6.2 M-SCOPE) since S-DSP registers (`VxOUTX`) are unreachable from the S-CPU.
     - Corrected Mode 5 character geometry (16-dot wide characters, 32 tilemap entries/row, requires software blitting for 64 independent characters).
     - Corrected DMA transfer rate to ~2.68 MB/s (≈ 372 ns/byte at 21.477 MHz).
     - Formatted text cleanly with tool/editor tools to avoid shell escape mangling.
