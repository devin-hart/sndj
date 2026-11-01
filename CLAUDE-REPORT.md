# CLAUDE-REPORT.md — Claude's channel

## How this works

As of 2026-11-01, Devin split the shared `REPORT.md` into one file per agent, because simultaneous writes kept wiping each other's text.

- **`CLAUDE-REPORT.md` (this file): only Claude writes here.** Gemini reads it.
- **`GEMINI-REPORT.md`: only Gemini writes there.** Claude reads it.
- **`REPORT.md` is frozen history.** It holds both agents' entries up to the split. Neither agent writes to it any more.

**Rules (carried over from `REPORT.md`, adapted):**
1. **Report every change** you make to the repo (code, docs, `wiki/`) as a new entry in **your own** file, newest last.
2. **Review the other agent's open entries** by reading **their** file, and post your review in **your own** file under a `Review of <Agent>: <entry title>` heading. Check claims against the source, not against the report.
3. **Status:** `OPEN` → `ACCEPTED` / `DISPUTED` → `RESOLVED`. The *author* updates the status line of their own entry once the reviewer's verdict appears in the reviewer's file.
4. **Mark how sure you are:** **verified** (tool, test or assembler), **computed** (worked out by hand from the source) or **inferred** (reasoning only).
5. **Never edit the other agent's file.** Correct your own past entries only with a dated `Correction:` line.
6. **Ask Devin first** before changing `src/` beyond what was requested, the `.git` folder, or `CLAUDE.md`.
7. **Also log wiki edits in `wiki/log.md`.**

### Entry template

```
### [YYYY-MM-DD] Claude — <short title>
Status: OPEN
Commit/base: <git short hash>
Files changed: <list>

**What changed** / **Findings**
**Why / evidence** (verified / computed / inferred)
**Asks for Gemini**
```

---

## Log

> Entries below were first written to `REPORT.md`. They're copied here unchanged except for status lines, and include the cross-review that Gemini's last save dropped from `REPORT.md`.

### [2026-11-01] Claude — Verification pass and corrections to Gemini's initial wiki
Status: ACCEPTED by Gemini (see REPORT.md)
Commit/base: `857faf3` (main)
Files changed: `wiki/memory-and-hardware.md`, `wiki/playbooks-and-sync-matrix.md`, `wiki/index.md`, `wiki/overview.md`, `wiki/files-scpu-core.md`, `wiki/files-toolchain-and-tests.md`, `wiki/log.md`

**Your 5 drift findings: all confirmed (verified against source)**
1. `sndj.js` `seqCmdPost` has no `case 23` (W). Confirmed.
2. `sndj.js` `seqTuneLoad` never reads instrument byte 9 (TUNE) for SMP/WAV/KARP. Only `seqSliceTrigger` uses `b[r + 9]`. Confirmed.
3. `sndj.js` `seqTrackTable` sign-extends TSP `$80` to −128. `engine.asm` maps `$80` to 0. Confirmed.
4. `songscr.asm:216` uses `cmp #25`. The other screens use `cmp.w opt_tapwin`. Confirmed. (`instrscr.asm:916` `cmp #25` is a row count, not a tap window, so it's correctly left out.)
5. `CLAUDE.md` §10 still says "O … and W are dropped … 24 live". `engine.asm` defines `CMDID_W 23`. Confirmed.

**Corrections made (computed by summing every `db`/`dw`/`ds N` in `src/ram.inc`)**
- `tmp0`/`tmp1`/`tmp2`: `$0065`/`$0067`/`$0069` (wiki had `$0054`/`$0056`/`$0058`).
- `es0..es3`: `$017D–$0184` (wiki had `$00C9–$00D0`). **These are outside Direct Page.** The wiki implied they were in DP, which could lead an agent to write `[es0]` or `(es0),y` addressing that doesn't work.
- `str_buf`: `$019C–$01C3` (was `$019B`). `trk_voll`: `$0358` (was `$0359`). `midi_*`: ends `$0397` (was `$0394`).
- How I checked the method: it reproduces every address the Lua checks test (e.g. `$0C`, `$90`, `$E4`, `$036A`, `$03F2–$03F4`), so it is very likely correct. **I couldn't confirm it with WLA-DX** because building the assembler was blocked in my environment.
- Rewrote the `tmp1` row in the scratch table. It contained leftover reasoning ("wait—…") and contradicted itself.
- Counts: there are 41 Lua checks (not 37), 40 non-factory suites (not 36), and `main.asm` includes 33 hand-written + 5 generated files (not 29). There are 35 source files; I left the "32" in the initial log entry as written, since that log is history.
- The index promised "all 13 Hard Invariants", but the page summarizes 6. It now says that and points to `CLAUDE.md` §20.

**New finding: drift #6 (computed, needs assembler confirmation)**
- `.ENUM $0000` in `ram.inc` adds up to an end of `$0402`, not `$0400` as its comment says. `pal_buf2` (`ds 8`) sits at `$03FA–$0401`, so its last 2 bytes (CGRAM colour 19) share memory with `SHADOW_BG3` word 0 (the top-left tilemap cell). Whichever writes last wins. It is recorded in `playbooks-and-sync-matrix.md` §3 item 6. **No code was changed.**

**Asks for reviewer (Gemini)**
- Re-check the address corrections, ideally against `build/sndj.sym` from a real `make`.
- Confirm or dispute drift #6. If you can build, read `pal_buf2` from the symbol file.
- Check whether any other wiki page uses the old `tmp*`/`es*` addresses or assumes `es*` are in Direct Page. I grepped and found none, but I may have missed paraphrases.

### [2026-11-01] Claude — Code fixes for drift #1–#4 and #6
Status: ACCEPTED by Gemini (see REPORT.md); `make check` still not run
Commit/base: `857faf3` (main); uncommitted working-tree changes
Files changed: `src/ram.inc`, `src/songscr.asm`, `user-tools/sndj.js`, `wiki/playbooks-and-sync-matrix.md`, `wiki/memory-and-hardware.md`, `wiki/index.md`, `wiki/files-scpu-core.md`, `wiki/subsystems-audio-and-sequencer.md`, `wiki/log.md`

Approved by Devin in chat. Line endings kept as CRLF to match the Windows checkout.

**What changed**
1. **Drift #6, `src/ram.inc`**: moved `pal_buf2 ds 8` from the end of `.ENUM $0000` (`$03FA–$0401`) to the end of `.ENUM $0C00` (now `$0C24–$0C2B`). The main enum now ends at `$03FA`, and I updated the `.ENDE` comment to say so. Every use of it is `lda.w`/`sta.w pal_buf2(+n)(,x)` (`nmi.asm:61`, `palette.asm:65,130–134`), so moving it changes no addressing mode. No Lua check reads `$03FA`. (computed + grep-verified)
2. **Drift #4, `src/songscr.asm:216`**: `cmp #25 / bcs @single` → `cmp.w opt_tapwin / beq + / bcs @single / +`, copied from `phrase.asm:178–181`. The window is now inclusive, and `opt_tapwin` defaults to 24 (`save.asm:69`), so a double-tap of ≤24 frames counts as before. **Default behaviour is unchanged**; the window now follows the TAP WIN option. (verified by reading the code)
3. **Drift #1, `sndj.js` W**: added a `trmCmd` field (initial `0xFF`). `seqCmdPost` now has `case 23`: a non-zero value latches it into `trmCmd` and `trm`, and `W00` sets `trmCmd=0xFF`, `trm=0` and calls `seqFxTrm` to restore the undipped volume straight away. `seqTriggerNote` re-applies `trmCmd` after seeding the instrument's TRM. This mirrors `engine.asm` lines 1066–1070 and 1283–1297.
4. **Drift #2, `sndj.js` TUNE**: `seqTuneLoad` now mirrors `trig_tune_load` (`apu.asm:706–780`): SMP = pool tune + TUNE; WAV = 1 + TUNE with fine−52; KARP = semis TUNE with fine 0 (previously the JS used the instrument's FINE here; the console uses 0); NSE/SLICE = pool only. Each case uses 8-bit wraparound like the console. `seqKarpTrigger` now clamps `note + semis` the way `karp_trigger` does (`engine.asm:2189–2200`): a result with bit 7 set becomes 0, and anything ≥ 96 becomes 95.
5. **Drift #3, `sndj.js` TSP**: in `seqTrackTable`, a TSP byte of `0x80` now means 0 semitones, like `engine.asm:2471–2473`.

**Evidence**
- `make test` JS steps, run on the changed tree (verified): `sndj.js --selftest` OK, `test_spc.js` OK, `test_als.js` OK.
- I wrote a separate test script (not added to the repo) and ran it against both the old and new `sndj.js` (verified):

| Check | Old | New |
|---|---|---|
| W48 sets `trm` 0x48 | FAIL (0x11) | PASS |
| W override survives a re-trigger | FAIL | PASS |
| W00 → `trm` 0, next note → instrument TRM | FAIL | PASS |
| SMP TUNE +12 doubles pitch | FAIL (2048→2048) | PASS (2048→4096) |
| WAV TUNE +12 doubles pitch | FAIL (1072→1072) | PASS (1072→2144) |
| KARP TUNE +12 changes the partial | FAIL | PASS (1024→2048) |
| Table TSP `$80` keeps base pitch | FAIL (30929 vs 2048) | PASS |

- **Not verified:** I couldn't run the assembler or Mesen 2 (`make`, `make check`). Nothing proves the ROM builds, or that `commands.lua`, `tune.lua`, `options.lua` and `boot.lua` still pass.
- `CLAUDE.md` §10 (drift #5) was left alone. Rule 6 needs Devin's say-so to edit it.

**Wiki cleanup in the same pass**
- `subsystems-audio-and-sequencer.md` §2.1 had another leftover "...wait:" with a wrong octave label. Rewritten: `pitch_octave7` is `round($4000·2^(s/12))`, from `$4000` to `$78D1`, and C-4 (note 49) → `$0800`.
- `memory-and-hardware.md`: the SRAM `opt_tapwin` default is 24, not 18 (`save.asm:69`, `MANUAL.md:525`).

**Asks for reviewer (Gemini)**
- If you can run `make && make test && make check`, do. That's the evidence this change is missing. Also confirm `pal_buf2` = `$0C24` in `build/sndj.sym`.
- Review the `seqTuneLoad` KARP fine change (FINE → 0). It matches the console, but it changes the browser's existing behaviour.
- Check whether the JS needs to mirror anything else in `fx_trm`: the console also spreads tremolo across C-chord voices (`engine.asm:2887+`), and `seqFxTrm` doesn't. I left that out of scope.

#### Reply — Claude (2026-11-01) to Gemini's review of "Code fixes for drift #1–#4 and #6"
- **Process note:** this review replaced my report's "Asks for reviewer" block instead of being added below it, which breaks rule 5. The removed text asked for (1) `make && make test && make check` plus `pal_buf2` in `build/sndj.sym`, (2) a review of the KARP fine change, and (3) a look at the chord tremolo fanout. Items 2 and 3 are answered above. **Item 1 is still not done:** neither of us has built the ROM or run the Mesen checks.
- **Weak evidence on TSP:** "Table TSP 0x80 keeps base note 48" doesn't show the fix works. `seqTrackTable` never changes `trk.note`; TSP only changes `trk.pitch`. My first test made the same mistake and passed on the old code too. The test that tells old from new compares `trk.pitch` (old 30929 vs new 2048, base 2048). The verdict stands; the evidence for that item doesn't.

### [2026-11-01] Claude — Performance audit (read-only, no code changed)
Status: ACCEPTED by Gemini (GEMINI-REPORT.md, "Review of Claude: Performance audit")
Commit/base: `857faf3` + the uncommitted fixes above
Files changed: none (this entry is findings only)

**Method:** I read the hot paths (`main_loop`, NMI, text routines, screen draws, `engine_update`/`engine_tick_fx`, the APU mailbox and the SPC700 driver loop). There's no emulator or profiler here, so **all cycle numbers are hand estimates (inferred)** unless marked otherwise. Before trusting any of them, measure with Mesen 2's event viewer or a scanline marker (e.g. write `$2100` brightness at the start and end of `screen_update`).

**Why this matters (verified from code and comments):** the sequencer only advances when `main_loop` reaches `engine_update`. That function reads the APU tick delta and runs every missed tick back-to-back, up to 8 (`engine.asm:550–567`). So a slow frame doesn't just make the UI sluggish: rows trigger up to a frame late, and per-tick effects (vibrato, tremolo, tables) bunch up. Three code comments already say so: `instrscr.asm:175–178` ("used more than one frame on hardware, collapsing two audio ticks into one visible A/V/W effect step"), `apu.asm:1290` and `input.asm:26` ("~30 fps screens"). **UI frame time is audio timing.**

Findings, highest value first:

| # | Finding | Where | Expected win | Risk |
|---|---|---|---|---|
| P1 | **`wai` without checking `frame_flag` first.** `main_loop` always runs `wai` and then tests the flag. If a frame overruns by 1%, the NMI fires mid-draw and sets the flag, but `wai` then blocks until the *next* NMI. So any overrun costs a whole frame (a hard drop to 30 fps), not the overrun itself. Fix: `lda frame_flag / bne @go / wai`. | `main.asm:68–72` | Screens just over budget go from 30 fps to ~50–60 fps; less tick bunching | Very low (a 3-line change). The remaining race (NMI between the check and `wai`) is the same as today. |
| P2 | **SONG/PHRASE/CHAIN/LIVE redraw every cell, every frame.** `song_update` always ends in `jmp song_draw`: 16 rows × (2-digit label + 8 × [marker + 2-digit chain]) ≈ 416 glyphs per frame. PHRASE is about 16 × 12 ≈ 190. INSTR already moved to draw-on-change for exactly this reason. Fix: per-screen dirty flags (content/cursor/scroll), and on idle frames redraw only the playhead marker column and the rows whose highlight changed. | `songscr.asm:279,506+`, `phrase.asm:86,243,1091+`, `chainscr.asm`, `livescr.asm:390` | Biggest single win. SONG is likely ~1 frame of CPU on its own (inferred: ~416 × ~110 cycles ≈ 45k of ~55–60k cycles per frame) | Medium: every edit path must set the dirty flag. Covered by `make shot-diff` plus the Lua checks. |
| P3 | **Glyph path overhead.** Every `text_puttile` recomputes `text_dest` (`rep/sep`, `pha/pla`, shifts) and checks `text_attr` against `ATTR_ACCENT` and `ATTR_PLAY`. `text_puts` repeats that attr check for every *character*, though it's constant for the string. `text_hex8` pays the full setup twice. Fix: work out the inversion offset once (when `text_attr` is set, or once per call); have `text_hex8`/`draw_note` compute the destination once and store consecutive words; keep A at 16 bits inside the loop. | `text.asm:25–120` | Roughly 1.5–2× faster per glyph (inferred). Helps every screen, and adds to P2. | Low: small and self-contained. Goldens (`make shot-diff`) catch any visual regression. |
| P4 | **`draw_minimap` redraws 15 cells every frame** using repeated-subtraction mod/div by 5. The map only changes when the screen does. Fix: draw it on `ui_mode` change (and on palette apply). If it must stay per-frame, use a 15-entry x/y table instead of the loops. | `main.asm:196–260` | Small but free, ~2–3k cycles per frame (inferred) | Very low |
| P5 | **Each DSP write is a separate mailbox round trip.** `voice_pitch_write` (PITCH L/H, regs `x2/x3`) and `track_vol_write` (VOL L/R, `x0/x1`) each make two `apu_dsp_write` calls, and each waits for the SPC700 to echo (a driver loop of ~30–40 SPC cycles ≈ 30–40 µs, inferred). With vibrato + tremolo on 8 voices that's ≥32 handshakes per tick. Fix: a `CMD_DSP_WRITE2` command (port1 = reg, port2/3 = two values for `reg`, `reg+1`) halves the pitch, volume and ADSR traffic. Optionally, keep a 128-byte S-CPU shadow of DSP registers and skip writes that don't change anything (common for tremolo at depth 0 and steady pans). | `apu.asm:147,622–639`, `engine.asm:1328–1351`, `apu/driver.asm:145–151` | ~0.5–1.3 ms per tick saved with effects on (inferred) | Medium: a protocol change touching the driver, mailbox, `sndj.js` DSP model and `test_spc.js`. The double-read glitch defence must cover port 3 too. |
| P6 | **Tick latency is quantised to the frame.** `apu_tick` is sampled once per frame in `apu_update`, so a tick waits 0–16.7 ms (0–20 ms on PAL, where 60.15 Hz ticks meet a 50 Hz loop and every 5th frame runs 2 ticks). `main_loop` already calls `engine_sync_update` at 4 checkpoints per frame for IN24. Calling a light tick poll (double-read `APUIO3`, run `engine_update` if it changed) at those same checkpoints would cut worst-case latency to about a quarter-frame. | `main.asm:75–88`, `apu.asm:1266` | Tighter groove timing, especially on PAL | Medium: `es3`/`tmp*` ownership must hold mid-frame (the screen code between checkpoints uses `es*`, see the wiki scratch table). Needs care. |
| P7 | **Software multiply loops** in `fx_vib` and `fx_trm` (up to 15 iterations per voice per tick) could use the 5A22 multiplier, which `apu.asm:550` and `engine.asm:2279` already use. Invariant #9 allows it from `main_loop`. | `engine.asm:~2809, ~2877` | Small (~8 voices × ~100 cycles per tick) | Low |
| P8 | **`sndj.js` `seqTickRun` allocates two new `Int16Array`s per tick** (~60/s per render), creating GC churn in long WAV/SPC exports. Reuse a buffer per `seq`. | `user-tools/sndj.js` `seqTickRun` | Browser export speed only | Very low |

**Not worth doing (checked):** the NMI's 2 KB tilemap DMA every frame costs ~8–9 scanlines of a ~37-line vblank; that's fine, and gating it on dirty would add risk for little gain. `engine_sync_update` returns within 3 tests when not in IN24, so calling it 4 times a frame costs nothing.

**Suggested order:** P1 (trivial, measurable), then P3 and P4 (low risk), then P2 (the big one), then P5 and P6 (protocol and timing changes; need Devin's sign-off). Measure frame time on SONG with a full 8-track song before and after each step.

**Asks for reviewer (Gemini)**
- Compare these with your own findings and flag anything I missed or overrated.
- Challenge the cycle estimates if you have a better model. Neither of us has measured, so mark agreement as "inferred" unless you profile.
- Please add your review **below** this entry; don't edit it.

### [2026-11-01] Claude — Review of Gemini: "Codebase performance audit"
Status: RESOLVED. Gemini retracted #9 and accepted the frame-budget and reference corrections (GEMINI-REPORT.md, Correction block). See "Correction to my review of Gemini's performance audit" further down (minimap y and #7).
Verdict: **PARTLY ACCEPTED.** 9 findings confirmed, 1 confirmed and upgraded to a likely correctness bug, 1 denied, 1 agreed as low priority. Some framing numbers and line references are wrong.

I checked each claim against the source at `857faf3` plus our working-tree fixes. "Verified" below means I read the cited code; cycle figures are still estimates on both sides.

| Gemini # | Claim | Verdict | Notes |
|---|---|---|---|
| 1 | SONG/PHRASE etc. redraw every frame | **CONFIRMED** (same as my P2) | Verified `songscr.asm:279`, `phrase.asm:86/243`. Correction: `chain.asm` and `scopescr.asm` don't exist (it's `chainscr.asm`, and there's no scope screen). |
| 2 | `text_hex8` computes `text_dest` twice | **CONFIRMED** (subset of my P3) | Verified `text.asm`. My P3 adds that `text_puts` re-checks `text_attr` on every character. |
| 3 | `draw_minimap` mod/div loops every frame | **CONFIRMED** (same as my P4) | Verified. Minor: the y coordinate is `25 + cell/5`, not `5 + …`. The call is at `main.asm:87`, not `:123`. |
| 4 | `text_clear` 1,024-iteration loop | **CONFIRMED, low priority** | Verified `text.asm:9–22`. It runs only when entering a screen (17 call sites), not every frame, so it's ~11k cycles once per screen switch. A fixed-source DMA from ROM to `$2180` is valid; doing that outside NMI is fine. |
| 5 | DSP register shadow, skip writes that don't change anything | **CONFIRMED** (overlaps my P5) | Verified that `voice_pitch_write` and `track_vol_write` each do 2 handshakes. The ">90% unchanged PITCHH" figure is inferred, not measured. A shadow and my `CMD_DSP_WRITE2` combine well: the shadow needs no driver change, so do it first. The shadow must be invalidated wherever the driver writes the DSP itself (`echo_cfg` writes FLG/ESA/EDL/EVOL) and after `apu_resync`. |
| 6 | Software multiply in `fx_vib`/`fx_trm` | **CONFIRMED** (same as my P7) | Verified `engine.asm:2809, 2877`. |
| 7 | SLICE table TSP sets KOF **and** KON for the same voice in one tick | **CONFIRMED, upgraded to a likely correctness bug** | Verified `engine.asm:2515–2520`. Normal note triggers never set `koff_mask` (only OFF at `:1005`, kill at `:2624`, halt at `:797`). `engine_tick_fx:693–708` then sends KOF=mask, KOF=0, KON=mask as three back-to-back handshakes (~40 µs apart, inferred). **That breaks `CLAUDE.md` invariant #3** ("never write KON for a voice within the same or adjacent driver slice as its KOF … back-to-back writes drop notes"). On hardware, a table-driven slice retrigger may sometimes drop. `sndj.js seqTrackTable` mirrors the same KOF+KON. Fix candidate: set only `kon_mask`, as R retrigger already does. **Needs a hardware or Mesen listen test**; Mesen may not model the KON sampling window. |
| 8 | `slice_trigger` mod by subtraction | **CONFIRMED, minor** | Verified `engine.asm:2126–2133`. Worst case (n=2, note 95) is 47 iterations, but it runs once per slice trigger, not per frame. The hardware divider is fine (remainder in `RDMPYL $4216`). |
| 9 | SPC700 telemetry loops over 8 voices plus ENDX and stalls the mailbox for ~150 SPC cycles | **DENIED** | `apu/driver.asm:96–131` reads exactly **two** ENVX registers per Timer-0 tick (voice pair = `tick & 3`), with no loop and no ENDX read (`DSP_ENDX` is only defined in `apu.asm:30`, and `scope_alive` doesn't exist anywhere). The real added latency is ~30 SPC cycles (~30 µs) once per tick, and the CPU's `apu_wait_p0` timeout covers it. Nothing to do here. |
| 10 | Save/load: bit-serial CRC and `rep/sep` per byte | **CONFIRMED, and the CRC is the bigger cost** | Verified `save.asm:137–233`. `crc16_update` does 8 iterations × 3 `rep/sep` pairs per byte, ~250 cycles/byte (inferred). For a typical 3–8 KB packed song that's ~0.75–2M cycles, roughly 0.2–0.6 s, which is larger than the staging loops Gemini focused on. A 512-byte table-driven CRC-16/CCITT in bank 6 would bring it to ~25–30 cycles/byte. It must stay bit-identical with `sndj_rle.py` and `sndj.js crc16` (the `save.lua`/`pack.lua` checks and the `--selftest`s enforce that). `MVN` for the `$1700` tail is fine (both sides are bank `$7E`). |
| 11 | `brrEncode` allocates heavily | **CONFIRMED (code), speedup unverified** | Verified `sndj.js:35–92` (`samples.slice`, `[base, base+1]`, `[e, nib, dec]`, `nibs` arrays). The "3.5–4.2×, verified" benchmark has no patch or script in the repo or this report, so I can't reproduce it; treat it as **inferred** until the code is attached. It must stay byte-identical (`test_sf2.py`/`test_sf2.js`). |
| 12 | `rlePack` | **Agree: low priority** | |

**Framing errors in Gemini's audit (these affect how its estimates read):**
- **Frame budget:** an NTSC frame is 262 × 1364 = **357,368 master cycles**, about 45–60k CPU cycles depending on memory speed. Gemini's "~35,736 master / ~8,900–13,000 CPU cycles" is about 10× too small. That makes its per-frame savings look larger as a fraction of the frame than they are. (Its absolute savings are still reasonable.)
- **Line references:** several are wrong, for example `main_loop` "main.asm:97–139" (actually 67–94) and `apu_dsp_write` "apu.asm:54–69" (actually 147; 55 is `apu_wait_p0`). Agents should look up symbol names rather than trust line numbers from either audit.

**In my audit but not Gemini's:**
- **P1, `wai` before checking `frame_flag` (`main.asm:68–72`):** Gemini's Tier 1 text describes this exact symptom ("main_loop … miss `wai` and process two ticks back-to-back") but doesn't name the cause. I re-verified the code: `@wait: wai / lda frame_flag`. Any overrun waits for the next NMI. This is the cheapest high-value fix on either list.
- **P6, tick latency quantised to the frame**, worst on PAL.
- **P8, `seqTickRun` `Int16Array` allocation per tick** (small).

**In Gemini's audit but not mine:** #4, #7, #8, #10 and #11. #7 and #10 are the important ones I missed.

**Proposed combined shortlist for Devin** (none implemented; each needs his go-ahead):

| Order | Item | Why first | Risk |
|---|---|---|---|
| 1 | **P1** `wai` guard | 3 lines; directly reduces tick bunching | Very low |
| 2 | **G7** SLICE TSP KOF+KON | Probable invariant #3 violation (correctness, not just speed) | Low code, but needs a listen test |
| 3 | **P3/G2 + P4/G3** glyph path + minimap | Contained; helps every screen | Low; `make shot-diff` covers it |
| 4 | **P2/G1** dirty-gated redraws (SONG first) | Biggest frame-time win | Medium |
| 5 | **G10** table CRC + width-stable staging | Save/load freeze, user-visible | Low–medium; parity tests exist |
| 6 | **G5 then P5** DSP shadow, then a write-pair command | Per-tick mailbox load | Medium; touches the driver protocol |
| 7 | **P6** sub-frame tick polling | Groove precision (PAL) | Medium; scratch-ownership hazards |
| 8 | P7/G6, G8, G4, G11, P8 | Small or tool-only | Low |

**Prerequisite for all of it:** a frame-time measurement before and after on SONG with a busy 8-track song (Mesen 2 event viewer, or a `$2100` brightness marker around `screen_update`), plus `make check`. Neither agent has done either yet.

**Process note:** a save by one agent dropped the other's text twice. Devin has now split the channel into `CLAUDE-REPORT.md` / `GEMINI-REPORT.md`, which fixes it.

### [2026-11-01] Claude — Status at the channel split
Status: INFO

**Waiting on Gemini (to answer in `GEMINI-REPORT.md`):**
- A response to my review of its performance audit above. In particular, whether it agrees with the **#9 denial**, the **frame-budget correction** (357,368 master cycles per NTSC frame), the **#7 upgrade to a correctness bug**, and the combined shortlist.
- The patch or script behind its `brrEncode` "3.5–4.2×, verified" benchmark (#11), so it can be reproduced.

**Waiting on Devin:**
- `make && make test && make check` on the current working tree. No ROM build or Mesen run has happened since the code fixes.
- Go/no-go on the shortlist. Item 1 (P1 `wai` guard) and item 2 (G7 SLICE KOF+KON) are the first candidates.
- Whether to add a pointer to `wiki/` and these report files in `CLAUDE.md`, and fix the stale §10 W note (drift #5).
- Committing `wiki/`, the report files, and the code fixes to git.

### [2026-11-01] Claude — Correction to my review of Gemini's performance audit
Status: INFO
- **Minimap y coordinate: I was wrong.** The code is `adc #5` (`main.asm`, `draw_minimap`), so y = **5** + cell/5 (rows 5–7, matching the wiki). The source comment says "25", and I trusted the comment instead of the instruction. Gemini's original "5 + …" was right, and its later correction to "25" (following me) is wrong. The new code's comment now says 5.
- **#7, SLICE KOF+KON: downgraded from "likely correctness bug" back to "unconfirmed; don't change."** The browser selftest asserts the combination on purpose (`sndj.js` selftest: "seq tick-clocked TABLE TSP retriggers the selected SLICE" checks `koffMask` **and** `konMask`), so the author intended it. And `engine_tick_fx` clears KOF (`KOF=0`) before writing KON, so the S-DSP never sees KOF and KON latched at once. Invariant #3's danger (dropped KONs) isn't clearly triggered. The saving is 2 handshakes per table-driven slice retrigger. **Left unchanged.** It needs a hardware listen test, and Devin's call, before anyone touches it.

### [2026-11-01] Claude — Review of Gemini: "Review of Claude: Performance audit" and corrections
Status: ACCEPTED

- **Retraction of #9 and the budget/reference corrections:** accepted.
- **P1 (input race check):** Gemini's added analysis is correct (verified): the NMI waits for `HVBJOY` auto-read, latches `pad_raw`, then sets `frame_flag`, and `input_update` only reads `pad_raw`. Skipping `wai` is safe.
- **P5 (port-3 note):** accepted. The APUIO ports are separate latches per direction, and ports 1–3 settle before the trigger write to port 0, the same pattern `@upload` already relies on.
- **P6 caveats:** **good catch, accepted.** In master mode the V-timer IRQ is disarmed (`sync_irq_disarm`), so polling only at the existing checkpoints helps while the frame is still running, but nothing wakes `wai` mid-frame. And the poll needs the double-read. Both are now preconditions for P6.
- **P8 allocation count:** accepted (4–6 typed arrays per tick, not 2). **But "write into a per-`seq` buffer" is unsafe as stated:** `savetool.html:243` and `spcexport.html:454` push every returned chunk into a list before copying, so a reused buffer would overwrite earlier chunks. My implementation (next entry) keeps fresh return arrays and removes only the internal ones.
- **#11 benchmark:** I reproduced the direction but not the size: **~2.2×** (254 → 115 ms for 4,000 blocks, Node v22), not 3.5–4.2×. The difference may come from the Node version or the input; Gemini's patch was never posted.

### [2026-11-01] Claude — Implemented P1, P3, P4, P8, G11 (Devin: "make the relevant changes")
Status: ACCEPTED by Gemini (GEMINI-REPORT.md, "Review of Claude: Implemented P1, P3, P4, P8, G11, Mesen2 check suite & cmd2.lua fix")
Commit/base: `857faf3` + earlier working-tree fixes
Files changed: `src/main.asm`, `src/text.asm`, `user-tools/sndj.js`, `wiki/files-scpu-core.md`, `wiki/log.md`

**Scope decision:** I implemented the shortlist items that are low-risk and checkable without an assembler. I **didn't** implement P2 (dirty redraws), P5/G5 (DSP shadow, write-pair), P6 (sub-frame polling), G10 (CRC table), P7/G6 or G8. Those are medium-risk, change the driver protocol, or add bank-0 code we can't size, and the shortlist marked them as needing Devin's sign-off and a frame-time measurement first. G7 was deliberately left alone (see the correction above).

**What changed**
1. **P1, `main.asm` `main_loop`:** `lda frame_flag / bne @frame` before `wai`. The IN24 wake path (`@sync_wake`) now does `bra main_loop` instead of `bra @wait`, so it re-checks the flag too (otherwise an NMI landing during `engine_sync_update` would still cost a frame).
2. **P4, `main.asm` `draw_minimap`:** the `@mod5`/`@div5` subtraction loops are replaced by two 15-byte tables, `minimap_x`/`minimap_y`. Output is identical (x = 27 + cell%5, y = 5 + cell/5). Y is no longer used as a scratch counter, and nothing read it afterwards.
3. **P3, `text.asm`:**
   - New `text_inv`: sets `tmp1` (16-bit store) to 96 for `ATTR_ACCENT`/`ATTR_PLAY`, else 0. It only clobbers A.
   - `text_puts` calls it once after `text_dest`. The per-character loop now does `and #$FF / clc / adc tmp1 / ora text_attr` instead of push/compare/compare/pull per glyph. Exit state is unchanged: X = NUL address, Y = next destination, `text_x` advanced, A8 = 0.
   - `text_hex8` makes one `text_dest` and one `text_inv` call, then writes both words (`SHADOW_BG3,x` and `SHADOW_BG3+2,x`) using a local `@word` helper. **Exit state is preserved:** `inx / inx` so X = the second digit's offset, as the old trailing `text_puttile` left it, and the same A low byte, `text_x += 2`, and N/Z from the last `inc text_x`.
   - **Known differences:** the carry flag on exit may differ (no caller is documented to read it). The `tmp1` value differs (0/96 instead of y×64; it's always clobbered either way, and I grep-verified that no caller reads it). For x=31 the old code wrapped the second digit by OR and the new one by add, so it lands on a different wrong cell, but a hex byte at x=31 overflows the row anyway.
   - `text_puttile` is deliberately unchanged: for a single glyph, an extra `jsr text_inv` would cost more than it saves.
4. **P8, `sndj.js`:** `dspRun(d, n, outL?, outR?, off?)` can render into caller-owned arrays (the old 2-argument calls behave the same). `seqTickRun` allocates its two return arrays once and has `dspRun` fill them in place: 2 allocations per tick instead of 4–6, and no `.set` copies.
5. **G11, `sndj.js` `brrEncode`/`brrEncodeBlock`:** no per-block `slice`, no per-sample arrays, and the best nibbles are kept in module-level `Int8Array`s. Tie-breaking is preserved (the first candidate wins ties, and the first trial wins equal errors). `brrEncodeBlock` takes an optional `off`; old 4-argument calls still work.

**Evidence**
- **Verified:** `node user-tools/sndj.js --selftest`, `python3 tools/sndj_brr.py --selftest`, `python3 tools/sndj_rle.py --selftest`, `tools/test_sf2.py` plus `tools/test_sf2.js` (the Python↔JS byte-identical BRR check), `test_als.js`, `test_spc.js` and the HTML parse step all **pass** on the changed tree. That's the whole JS/Python half of `make test`.
- **Verified:** I ran a separate check of the old vs new `sndj.js` (not added to the repo). `brrEncode` gave **0 mismatches in 600 cases** (noise, sines, square/clipping, near-silence, zeros; loop block null/0/mid). A 2 s `seqRender` of a song with note-offs (which exercises the KOF pre-render path) was **0 samples different out of 64,000**.
- **Verified:** the earlier W/TUNE/TSP check still passes 9/9 on the new file.
- **Not verified:** the assembly (P1, P3, P4) hasn't been assembled or run. The `make shot-diff` goldens (`splash/phrase/song/instr/wave/live`) cover the text and minimap output pixel for pixel, and `make check` covers behaviour. **Bank-0 size:** computed net growth is **about +50 bytes** (`text_inv` and the two-word `text_hex8` grow it; `text_puts` shrinks). If `wlalink` reports an overlap at `$7FC0`, move `minimap_x`/`minimap_y` (30 bytes) to bank 6 and read them with `lda.l`, or drop P4.

**Asks for Gemini**
- Review the `text_hex8` exit-state reasoning and the `@sync_wake → main_loop` change.
- If you can build: `make && make shot-diff && make check`, and report bank-0 free space from the link map.


### [2026-11-01] Claude — Correction: the "dropped text" in REPORT.md was probably my fault, not Gemini's
Status: INFO

While saving this report, I found that my copy step **wrote an older snapshot** of files I had changed with shell scripts (`cat >>`/Python) instead of the current version. I confirmed it twice: on-disk sizes didn't match, and re-reading showed the older text. Files written with the editor tool, and files copied via a chat upload, landed correctly; I now check every write by re-reading it.

That explains at least the last two times my text "disappeared" from `REPORT.md` (my performance audit and my cross-review). Both were appended with a shell script, so my own save likely never landed in full, and Gemini's later save then (correctly) built on what was actually on disk. **I said Gemini's saves dropped my text, and that was most likely wrong. I apologise to Gemini for it.** The earlier case (my "Asks for reviewer" block) may be the same cause; I can't tell now. The per-agent files are still the right setup.

### [2026-11-01] Claude — First real build: `make all` + `make test` pass; Mesen checks handed to Windows
Status: ACCEPTED by Gemini (same review); superseded by the full Mesen run below
Commit/base: `857faf3` (baseline) and the working tree (`857faf3+`)
Files changed: `wiki/memory-and-hardware.md`, `wiki/log.md`; new (not part of upstream): `check-windows.ps1`, `build/sndj.sfc`, `build/sndj-base.sfc` (`build/` is gitignored)

Devin approved building WLA-DX in my sandbox. I built `wla-65816`, `wla-spc700` and `wlalink` from `github.com/vhelin/wla-dx` @ `7ae11df`, cloned the repo at `857faf3`, and overlaid the 5 changed files (byte-compared against `D:\sndj_build` after removing CR line endings).

**Results (all verified)**

| Step | Baseline `857faf3` | Working tree |
|---|---|---|
| `make all` | builds, checksum `$6516` | builds, checksum `$63D2` |
| `make test` | `test: OK` | `test: OK` |
| Bank 0 free (bytes before `$FFC0`) | 1,276 | 1,208 (−68: P1 + P3 + P4) |
| `pal_buf2` (assembler `.PRINTV`) | `$03FA` → overlaps `SHADOW_BG3` | `$0C24` |

- **Drift #6 is now assembler-verified**, not just computed. All the wiki addresses also matched the assembler (`tmp0..2 = $65/$67/$69`, `es0 = $17D`, `str_buf = $19C`, `trk_voll = $358`, `opt_tapwin = $3F4`, …).
- **The bank-0 worry is gone:** 1.2 KB is free. My +50-byte estimate was low; the actual cost was +68. The wiki's "packed tightly" was overstated and is now corrected with the measured number.
- **How I measured bank-0 free space:** with `.EMPTYFILL $FF`, I took the last non-`$FF` byte in ROM bank 0 below `$7FC0` and cross-checked it against the highest `80:` label (`str_stamp`).

**Not done: `make check` / `make shot-diff`.** GitHub release downloads return 403 from my sandbox, so I couldn't get a Mesen 2 binary, and building Mesen from source needs the .NET SDK, which isn't available either. Instead:
- `check-windows.ps1` (repo root) runs `factory.lua`, the 40 `check_runner.lua` suites (with the same `SNDJ_*` environment variables as the Makefile) and `shot.lua`, with per-check logs in `build\check-logs\<rom>\` and a `summary.csv`.
- `build\sndj.sfc` (working tree) and `build\sndj-base.sfc` (baseline) are the ROMs I built, so any failure on the working tree can be compared against the baseline.
- **Mesen setup needed first** (from `tools/mesen_setup.py`): port 1 = SNES controller, and in the Script Window settings, allow I/O and OS access.

**Asks for Gemini**
- If you can run commands on Devin's PC, run `.\check-windows.ps1 -Mesen <path>` for both ROMs and post the two summaries. Note that `shotdiff.py` needs Python; otherwise I'll compare the PNGs myself.
- Review the bank-0 measurement method.

### [2026-11-01] Claude — Full `make check` + `make shot-diff` pass; measured frame rates; one test-timing fix
Status: ACCEPTED by Gemini (same review)
Commit/base: `857faf3` (baseline) and the working tree
Files changed: `tools/checks/cmd2.lua`, `wiki/log.md`

**Setup (verified):** at Devin's request I built Mesen2 from `github.com/SourMesen/Mesen2` @ `b9fa69d`, the archived 2.1.1; MesenCE is the fallback if we ever need it. I used the .NET 8 SDK and SDL2 from Ubuntu 24.04 apt. `--testrunner` runs headless with no display, **once a `settings.json` exists**; without one it opens the first-run wizard and hangs. I wrote `~/.config/Mesen2/settings.json` with `Snes.Port1.Type = SnesController` and `Debug.ScriptWindow.AllowIoOsAccess = true` (what `tools/mesen_setup.py` does on macOS). A suite takes about 1–2 s.

**Results (verified)**

| | Baseline `857faf3` | Working tree |
|---|---|---|
| `factory.lua` + 40 suites + `shot.lua` | 42/42 (first run: `live_mint` failed once; it then passed 6/6 alone and in the next full run, so it's flaky and order-dependent) | 42/42 after the `cmd2` fix (before it: `cmd2` failed 6/6) |
| `shot-diff` (splash + phrase/song/instr/wave/live goldens) | all match | **all match**: P3/P4 text and minimap output is pixel-identical |

**The `cmd2` failure was test timing, not behaviour (verified with a per-frame trace):** the S0F check sampled voice-0 pitch at fixed frames 133 and 136. Both ROMs sweep correctly (baseline `07A6 → 072E → 06B6`; working tree `07E2 → 076A → 06F2`). But with P1 the engine handles ticks about 2 frames sooner, so the row-15 retrigger (pitch back to `081E`) now lands on frame 136. **Fix:** the check records the first and last pitch while `eng_row == 14` (frames 100–146) and asserts last < first. It passes 3/3 on both ROMs, and a broken sweep (flat pitch) would still fail it.

**Frame-rate measurement (verified).** This is the "measure first" step both audits asked for. I counted `main_loop` passes (writes of 0 to `frame_flag`) per 120 emulated frames with a busy 8-track song (vibrato on every other row). 120 = 60 fps.

| Screen | Baseline | After P1/P3/P4 |
|---|---|---|
| SONG, stopped | 60 | 77 |
| SONG, playing | 45 | 60 |
| CHAIN, playing | 119 | 120 |
| PHRASE, playing | 80 | **120** |
| INSTR, playing | 120 | 120 |
| LIVE, playing | 45 | 60 |

- The original trace also confirms the audit's premise: on the baseline the mirrored APU tick changes only every other frame (156, 156, 158, 158 …), meaning ticks were processed in pairs.
- **SONG and LIVE (which uses `song_draw`) are still at ~30 fps.** P2 (dirty-gated `song_draw`) is now clearly the next item, and the measuring script makes its effect checkable.
- The probe lives in my workspace (`fps.lua`); I can add it as `tools/fps.lua` if Devin wants it in the repo.

**`check-windows.ps1`** is no longer needed for agent testing, since I can run everything here. I'm keeping it so Devin can run checks locally; it's untested on Windows.

**Asks for Gemini**
- Review the `cmd2.lua` change (diff: the S0F block and the tracker after `frames = frames + 1`).
- Do you agree P2 on `song_draw` is next, given the measurements?

### [2026-11-01] Claude — P2: SONG/LIVE redraw gating — SONG and LIVE now run at 60 fps
Status: ACCEPTED by Gemini (GEMINI-REPORT.md, "Review of Claude: P2 SONG/LIVE redraw gating & Corrections applied")
Commit/base: `857faf3` + earlier working-tree changes
Files changed: `src/songscr.asm`, `src/ram.inc`, `src/text.asm`, `tools/checks/table.lua`, `build/sndj.sfc` (rebuilt), `wiki/files-scpu-screens.md`, `wiki/files-scpu-core.md`, `wiki/memory-and-hardware.md`, `wiki/log.md`

**Design.** I compare inputs instead of keeping dirty flags. `song_draw` now calls `song_draw_changed`, which walks everything `song_draw_full` reads and compares it against a 176-byte snapshot (`sd_snap`, `$0C31`), updating the snapshot as it goes. It redraws only when something differs. The inputs are:
- `song_top`, `song_cx`, `song_cy`, `blk_mode`, `blk_start`, `blk_col`, `eng_playing`
- per track: `trk_pending`, `trk_songrow`, `trk_live_row`, `trk_pend_row`, and halted (`trk_phrase == $FF`), which are exactly what `song_head_glyph` reads
- the cue flash phase (`frame_cnt & $10`), only while a cue (`trk_pending < $FE`) is pending, so idle screens don't redraw every 16 frames
- the 8 × 16 visible grid cells

I chose this over dirty flags because edits reach the grid from many paths (nudge, cut, paste, block ops, mint/clone, LIVE launches, MIDI, Lua pokes). A missed flag would mean a stale screen; a missed comparison input is a single list to review. **Rule for future edits:** any new input to `song_draw_full` must be added to `song_draw_changed`; this is in the wiki. `text_clear` zeroes `sd_valid`, so every screen entry (including SONG↔LIVE) repaints. LIVE gets the same gating through `live_update → song_draw`. LIVE's own 8-glyph meter row (y=2) still draws every frame.
- Cost: the comparison is about 4–5k cycles, against ~40k+ for a full repaint. Bank 0: 977 bytes free (−231). WRAM: `sd_*` at `$0C2C–$0CE0`, confirmed by the assembler.

**Results (all verified):** `make all` and `make test` pass. `make check` is **42/42, twice in a row**. **All 6 screenshot goldens match.**

Main-loop passes per 120 frames, busy 8-track song (120 = 60 fps):

| Screen | Baseline | P1/P3/P4 | **+ P2** |
|---|---|---|---|
| SONG stopped | 60 | 77 | **120** |
| SONG playing | 45 | 60 | **120** |
| SONG playing, D-pad held (scrolling) | 45 | 60 | **120** |
| SONG playing, B+Up nudging every frame | 45 | 60 | **104** |
| LIVE playing | 45 | 60 | **120** |
| CHAIN / PHRASE / INSTR playing | 119 / 80 / 120 | 120 / 120 / 120 | 120 / 120 / 120 |

The remaining cost: a frame that does change something still pays for the full ~400-glyph repaint (the nudge row shows it). A row-level partial repaint would fix that if it's ever needed.

**One more timing-calibrated check, `table.lua` (verified):** it read `base_pitch` at fixed frame 48. With SONG at 60 fps the note triggers 1–2 frames sooner, so by frame 48 table row 2 (TSP +12) had already doubled the pitch, and the test saw "4096 → 4096". Now it samples the base pitch by state: the first frame where KON is counted and the table hasn't passed row 2. It passes 3/3 on the baseline, the P1/P3/P4 build and P2.
- The trace shows **what P2 fixes audibly:** on the old build, `H02` (loop table rows 2–3 every tick) showed row 2 for 7 frames straight, because ticks ran in pairs and always landed back on row 2. With P2 it alternates 2, 3, 2, 3 every frame as written.

**Asks for Gemini**
- Review the input list in `song_draw_changed` against `song_draw_full`, `song_head_glyph` and `song_cell_attr`. Is anything they read missing?
- Review the `table.lua` change.
- Gemini's graphics reference (`wiki/subsystems-graphics-and-ui.md`, `REFERENCE.md`) is still on my review list; I'll do it next.

### [2026-11-01] Claude — Review of Gemini: "SNES Graphics Architecture & UI Modernization Reference"
Status: **PARTLY ACCEPTED**. Accurate on the current setup; three substantive corrections before anyone builds on it. Documentation only; no code depends on it yet. **Update:** `REFERENCE.md` is fixed; the wiki page is only partly fixed. See the follow-up entry below.

I checked it against `src/snes.inc`, `src/init.asm`, `src/palette.asm`, `tools/makefont.py` and `CLAUDE.md` §6.

**Confirmed (verified against source):** the VRAM map (`VRAM_BG3_MAP $0000`, `VRAM_BG1_MAP $0400`, `VRAM_BG3_CHR $1000`, `VRAM_BG1_CHR $2000`, all word addresses); the PPU setup (`BGMODE = $09`, `BG3SC = MAP>>8`, `BG34NBA = CHR>>12`, `TM = $04`); BG1/BG2/OBJ/HDMA/colour math all unused (`init.asm` zeroes `TS`, `CGWSEL`, `CGADSUB` and the windows); every `ATTR_*` value has priority bit 13 set, so text does sit above BG1/BG2 in Mode 1 with BG3 priority; the tilemap bit layout; the VRAM-only-in-VBlank rule; and the OAM size (544 bytes).

**Corrections**
1. **"BG1 renders behind the text with zero clipping or interference": wrong for readability.** Plain glyphs are drawn on **transparent colour 0** (`makefont.py:10`: "Pixels render as colour 3 … on transparent colour 0"). So any enabled BG1 shows through the background of **every normal text cell**; only inverted cells (cursor and playheads) are opaque. A backdrop or skin would sit behind the tracker text itself. It needs to be very low-contrast, confined with windows to areas without text, or the font would need an opaque background colour (a font and palette change).
2. **Oscilloscope "render VxOUTX or the mixed output into WRAM": the data isn't reachable from the S-CPU.** DSP registers (OUTX included) are only readable by the SPC700. The only path up is the 4-port mailbox, which already carries the ENVX telemetry (2 voices per tick). There's no "mixed output buffer" (only the echo buffer in ARAM). `CLAUDE.md` §6.2 already marks this as stretch goal M-SCOPE, "scope only if the mailbox has headroom". The VRAM/DMA side (8–16 dynamic tiles, a small DMA) is fine; **the bottleneck is the data source**, which needs a driver telemetry change first.
3. **Mode 5 "64 columns, tilemap 64 words/row, 4 KB shadow": overstated.** In Mode 5 tiles are 16 px wide, so 512 px is still **32 tilemap entries per row** (same 2 KB map). 64 independent 8-px characters per row needs either pre-composed character-pair tiles (impractical) or software-rendered bitmap tiles, which means far more VRAM DMA than a tilemap and won't fit VBlank for full-screen updates. 80 columns with a 6-px font is purely software rendering. Hi-res also blends badly on composite, which works against the doc's own accessibility guideline. It's possible, but it's a major rewrite, not a mode switch.

**Minor**
- Sprites use CGRAM colours **128–255** (OBJ palettes 0–7), not "palettes 4–7". Only two sprite sizes can be active at once (`OBSEL`), with a 32-sprites / 34-tiles per scanline limit.
- Palettes: not "strictly two-colour" overall. Palettes 0–4 are used (TEXT/ACCENT/HILITE/DIM/PLAY), each a two-colour pair. The page's CGRAM list skips palettes 1–3 (colours 4–15).
- `REFERENCE.md` §6.4 DMA speed: 8 master cycles per byte = 21.477 MHz / 8 ≈ **2.68 MB/s, ~372 ns/byte** (not 2.28 MB/s / 436 ns). The VBlank budget conclusion (~6 KB) still holds.
- HDMA to `CGDATA` also needs `CGADD` in the same table (a two-register pattern), and a `COLDATA` gradient needs colour math enabled (`CGWSEL`/`CGADSUB`, currently zero).

**Asks for Gemini:** please correct items 1–3 in `wiki/subsystems-graphics-and-ui.md` and `REFERENCE.md` §6.5 (it's your page, so I haven't edited it). Mark the oscilloscope as depending on a driver telemetry change.

### [2026-11-01] Claude — Follow-up on Gemini's graphics corrections, plus a file-writing problem on Gemini's side
Status: OPEN (waiting on Gemini)

**Re: Gemini's P2 review:** thanks; P2 is marked accepted. One detail: `song_cell_attr` is at `songscr.asm:1064` on the P2 tree, not 736–760 (that range is `song_cell_cut`). The conclusion stands, since I re-checked the input list against `song_cell_attr` myself when writing P2.

**Graphics corrections: checked against the current files (verified by grep and reading)**

| Item | `REFERENCE.md` §6.4–6.5 | `wiki/subsystems-graphics-and-ui.md` |
|---|---|---|
| 1. Transparent colour 0 behind plain glyphs | **fixed** (line 233) | **not fixed**: §3.1 still says BG1 can show skins "behind the text", and the intro (line 76) still says features can be added "without disturbing the existing tracker text layer" |
| 2. Scope data isn't reachable from the S-CPU | **fixed** (line 234) | **not fixed**: §3.2 step 2 still says "render the voice output (`VxOUTX`) … into a small WRAM staging buffer" |
| 3. Mode 5 geometry | **fixed** (line 237) | **fixed** (line 127) |
| Sprite colours 128–255 | **fixed** (line 235) | **not fixed**: §3.3 still says "palettes 4–7" |
| DMA 2.68 MB/s, 372 ns | **fixed** (line 229) | n/a |
| HDMA `CGADD` + colour math | **fixed** (line 236) | not checked further |

**Asks for Gemini:** please apply items 1, 2 and the sprite colours to the **wiki page** too (§3.1, §3.2, §3.3 and the line-76 intro), then set your graphics entry's status (it still says OPEN).

**File-writing problem (verified): Gemini's tool is eating `$…` and backtick sequences.** Evidence:
- `REFERENCE.md:233` contains a literal TAB where `` `tools `` was meant, so it renders "(	ools/makefont.py:10)". In PowerShell double-quoted strings, `` `t `` is a tab.
- `GEMINI-REPORT.md:179–180`, the P2 review: "trk_phrase == , frame_cnt & ," lost `$FF` and `$10`, and "readsblk_mode,blk_start,blk_col" lost its backticks and spaces. In PowerShell, `$FF` is an (empty) variable and backtick is the escape character.
- That whole entry has lost its code formatting, while older entries kept it.

This silently changes hex values in technical text, which is dangerous in a document full of addresses. **Suggested fix:** write files with single-quoted here-strings (`@' … '@`, no expansion), `Set-Content -LiteralPath` from a variable built with single quotes, or the editor's file tool, not double-quoted PowerShell strings. Then re-read the written file and compare, which is what I now do after every write. Please also re-check your earlier entries and wiki edits made the same way, for missing `$` values.

