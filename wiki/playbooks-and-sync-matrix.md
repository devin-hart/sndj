---
title: Modification Playbooks, Cross-File Sync Matrix & Active Drift Log
category: playbooks
updated: 2026-11-01
sources:
  - src/main.asm
  - src/ram.inc
  - src/song.inc
  - src/engine.asm
  - src/apu.asm
  - src/instrscr.asm
  - src/screens.asm
  - user-tools/sndj.js
---

# Modification Playbooks, Cross-File Sync Matrix & Active Drift Log

> [!IMPORTANT]
> Read this page whenever you are asked to add a feature, fix a bug, or modify data structures in `sndj`. It provides exact step-by-step recipes, the Cross-File Synchronization Matrix, and the Active Codebase Drift Log.

See also: [`memory-and-hardware.md`](memory-and-hardware.md), [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md), [`files-scpu-engine.md`](files-scpu-engine.md).

---

## 1. Step-by-Step Playbooks for Common Code Changes

### Playbook 1: Adding a New WRAM Variable
1. Open [`src/ram.inc`](../src/ram.inc).
2. **NEVER** insert or reorder variables in `.ENUM $0000` (`$0000–$03F9` is full, stopping just short of `$0400 = SHADOW_BG3`, and `$0000–$003F` + many higher offsets are hardcoded in `tools/checks/*.lua`).
3. Scroll to the bottom of **`.ENUM $0C00`** (currently after `pal_buf2`) and append your `db`, `dw`, or `ds N` variable before `.ENDE`.
4. Note that `$0C00+` (like `es0..es3` at `$017D`) is outside the Direct Page (`$0000–$00FF`), so it cannot be used with `[dp]` or `(dp),y` indirect addressing, and indexed accesses assemble as 16-bit absolute (`lda.w var,x`).
5. Since `init.asm` clears all 128 KB of WRAM to `$00` at boot, your variable starts at `$00`. If it needs a non-zero sentinel (like `$FF`) at boot or song load, initialize it in `init.asm` and/or `song_init` (`src/engine.asm`).

### Playbook 2: Spilling Code from Bank 0 to Bank 6 (When Bank 0 Fills Up)
All `.INCLUDE`d files in [`src/main.asm`](../src/main.asm) assemble into `.BANK 0 SLOT 0`, which ends at `.ORG $7FC0` (`$80:FFC0`, the internal ROM header). If `wlalink` reports an address/section collision near `$7FC0`:
1. Wrap a self-contained helper routine or table in `.BANK 6 SLOT 0` using a `FREE` section, then switch back to `.BANK 0 SLOT 0` (exactly like [`src/sync.asm`](../src/sync.asm) lines 131–240):
   ```asm
   .BANK 6 SLOT 0
   .SECTION "My Bank6 Spill" FREE
   my_far_helper:
       ; ... code here (DB is still $80, so low WRAM and MMIO work normally!
       ;     Any ROM table inside Bank 6 must be read with lda.l!) ...
       rtl
   .ENDS
   .BANK 0 SLOT 0
   ```
2. Call it from Bank 0 using **`jsl my_far_helper`** (and return with **`rtl`**), or if jumping from a Bank 0 stub, use **`jml`** (like `Vec_IRQ -> jml Sync_IRQ_Body`).

### Playbook 3: Adding or Modifying a Tracker Command (`A–Z`)
1. **Command ID (`src/engine.asm`)**:
   - Letters `A..Z` map to `1..26` (`CMDID_A = 1` .. `CMDID_Z = 26`). Currently **`O` (`CMDID_O = 15`) is the only unused letter** (`phrase.asm` and `tablescr.asm` already allow nudging `1..26`).
2. **Choose `row_cmd_pre` vs. `row_cmd_post` (`src/engine.asm`)**:
   - Put the dispatch in **`row_cmd_pre`** if the command alters whether/how `track_trigger_note` fires (`str_buf+27 = 1` suppresses normal trigger), modifies pitch/chord offsets read during trigger (`trk_fine,x`, `trk_chord,x`, `str_buf+28`), or sets global transport/DSP state.
   - Put the dispatch in **`row_cmd_post`** if the command modifies voice registers or track state that `track_trigger_note` / `apply_instrument` resets (`SRCN`, `trk_voll/r`, `trk_vib`, `trk_trm`, `trk_sl_rate`).
   - Check **`table_exec`** (`src/engine.asm`): `table_exec` calls both `row_cmd_pre` and `row_cmd_post`. If your command should be ignored inside a table (like `D`, `I`, `J`), add a filter at the top of `table_exec`.
3. **Update Documentation & Metadata**:
   - Update [`tools/commands.csv`](../tools/commands.csv) (keep line length `<= 30` chars when formatted as `"L NAME  SHORT"` so `tools/makehelp.py` passes its width check!).
   - Update **`user-tools/sndj.js`** (`seqCmdPre` or `seqCmdPost`) so browser preview, WAV export, and `.spc` export match the console!
   - Update `MANUAL.md` and `README.md`.
   - Add an emulator assertion in `tools/checks/commands.lua` or `tools/checks/cmd2.lua`.

### Playbook 4: Adding or Modifying an Instrument Field (`SB_INSTR`)
1. **Byte Allocation (`src/song.inc`, `SAVEFORMAT.md`)**:
   - Each instrument in `SB_INSTR` (`$7E:2400 + id*16`) is 16 bytes. Bytes `8`, `10`, and `11` are currently reserved (`$00`).
2. **UI Descriptor Tables (`src/instrscr.asm`)**:
   - Update `IF_COUNT` and the parallel tables:
     - `if_fields`: `byte_offset, bit_shift, post_shift_mask, max_val` (4 bytes per field)
     - `if_vis`: 6-bit type visibility bitmask (`bit 0=SMP, 1=KIT, 2=WAV, 3=NSE, 4=SLICE, 5=KARP`)
     - `if_labels`: `.DW str_if_...`
     - `if_grp`: group index (`0..4`) controlling blank separator lines on screen
   - **Watch out for `tools/checks/*.lua`**: Checks like `instr.lua`, `loop.lua`, `mint.lua`, `slice.lua`, and `karp.lua` navigate `INSTR` by pressing `Down` N times or writing row index `if_cur` (`$91`, e.g., `field 19 = TUNE`, `field 24 = TBL`). Inserting a new field *before* `TBL` will shift field indices in those Lua checks! Appending at the end or reusing a hidden slot preserves existing indices.
3. **Engine & JS Sync**:
   - Read the field in `apply_instrument` / `trig_tune_load` (`src/apu.asm`) or `track_trigger_note` (`src/engine.asm`).
   - Mirror the behavior in `user-tools/sndj.js` (`seqApplyInstrument` / `seqTriggerNote`).

### Playbook 5: Adding or Modifying a Screen
1. **`src/screens.asm`**:
   - Define `SCREEN_FOO`, add dispatch in `screen_update`, wire `A + D-pad` transitions in `nav_update`, and add `cmp #SCREEN_FOO` cases in `screen_reopen` (`screens.asm`) and `help_reopen` (`helpscr.asm`).
2. **`src/main.asm`**:
   - `.INCLUDE "fooscr.asm"` and update `minimap_chars`, `minimap_impl`, and `minimap_pos`.
3. **Screen Implementation Rules**:
   - Never touch PPU registers directly; draw only via `PUTS`, `SETATTR`, `text_puts`, `text_puttile`, `text_hex8`, `text_dec3` into `SHADOW_BG3`.
   - Use `ui_cnt` (not `tmp0` or `tmp1`) for draw loops that call `text_*`.
   - If the screen is heavy (like `instrscr.asm`), skip redrawing on idle frames when no buttons or edits occurred so NMI / sequencer timing is never starved.

---

## 2. Cross-File Synchronization Matrix

Whenever you touch one of the domains below, you **must** update all listed files in the same change:

| Domain Modified | Files That Must Be Updated Together |
| :--- | :--- |
| **1. Song Working Block (`$5300` B) or `SNDJ1` Save Format** | 1. [`src/song.inc`](../src/song.inc) & [`src/save.asm`](../src/save.asm)<br>2. [`SAVEFORMAT.md`](../SAVEFORMAT.md) (Invariant #12)<br>3. [`tools/sndj_rle.py`](../tools/sndj_rle.py) (`BLOCK_SZ`, `to_image`, `from_image`, `pack`, `unpack`)<br>4. [`tools/savetool.py`](../tools/savetool.py)<br>5. [`user-tools/sndj.js`](../user-tools/sndj.js) (`BLOCK_SZ`, `SEQ_SB`, `SEQ_SH`, `toImage`, `fromImage`, `srm*`, `sndjFile*`)<br>6. [`user-tools/als2sndj.html`](../user-tools/als2sndj.html), [`user-tools/savetool.html`](../user-tools/savetool.html), [`user-tools/spcexport.html`](../user-tools/spcexport.html)<br>7. [`tools/checks/save.lua`](../tools/checks/save.lua) & [`tools/checks/pack.lua`](../tools/checks/pack.lua) |
| **2. Sample Pool (`SNDJPOOL` v2) or ARAM Residency** | 1. [`src/pool.asm`](../src/pool.asm), [`src/song.inc`](../src/song.inc), [`src/main.asm`](../src/main.asm) (`SNPOOL`, `POOL_ROM = $818006`)<br>2. [`tools/sndj_pool.py`](../tools/sndj_pool.py) (`RESERVED = 0x27FFA`, `MAX_ENTRIES = 56`, `bank_pad`)<br>3. [`user-tools/sndj.js`](../user-tools/sndj.js) (`poolParse`, `poolBuild`, `aramBudget`, `seqAramBuild`)<br>4. [`user-tools/patcher.html`](../user-tools/patcher.html)<br>5. [`tools/check_runner.lua`](../tools/check_runner.lua) & [`tools/checks/pool.lua`](../tools/checks/pool.lua) |
| **3. BRR Codec or SF2 Resampling** | 1. [`tools/sndj_brr.py`](../tools/sndj_brr.py) & [`tools/sndj_pool.py`](../tools/sndj_pool.py)<br>2. [`user-tools/sndj.js`](../user-tools/sndj.js) (`brrEncode`, `brrDecode`, `sf2Parse`, `sf2Resample`, `sf2Melodic`, `sf2Oneshot`)<br>3. Verify with `make test` (`tools/test_sf2.py` + `tools/test_sf2.js` enforce byte-for-byte identity). |
| **4. Factory Container (`SNDJFACT` v4) or ROM Asset Markers (`SNPOOL`, `SNPAL0`, `SNKIT0`, `SNDEF3`, `SNFIR0`, `SNFONT`)** | 1. [`src/main.asm`](../src/main.asm) (Bank 6 `.DB "SN..."` markers)<br>2. [`tools/maketables.py`](../tools/maketables.py) & [`tools/sndj_pool.py`](../tools/sndj_pool.py)<br>3. [`user-tools/patcher.html`](../user-tools/patcher.html) (`loadRom`, `exportRom`, `factoryImport`, `factoryExport`)<br>4. [`factory/factory.sndjfact`](../factory/factory.sndjfact) |
| **5. Pitch Math, Tuning (`FINE`/`TUNE`), or `KARP` Tables** | 1. [`tools/maketables.py`](../tools/maketables.py) (`pitch_octave7`, `karp_entry`)<br>2. [`src/apu.asm`](../src/apu.asm) (`note_pitch_raw`, `trig_tune_load`) & [`src/engine.asm`](../src/engine.asm) (`karp_trigger`)<br>3. [`user-tools/sndj.js`](../user-tools/sndj.js) (`pitchForNote`, `karpEntry`, `seqPitchCalc`, `seqKarpTrigger`)<br>4. [`tools/checks/tune.lua`](../tools/checks/tune.lua) & [`tools/checks/karp.lua`](../tools/checks/karp.lua) |
| **6. Tracker Commands (`A–Z`)** | 1. [`src/engine.asm`](../src/engine.asm) (`row_cmd_pre`, `row_cmd_post`, `table_exec`, `track_fx`)<br>2. [`tools/commands.csv`](../tools/commands.csv) (drives `build/help.inc` via `tools/makehelp.py`)<br>3. [`user-tools/sndj.js`](../user-tools/sndj.js) (`seqCmdPre`, `seqCmdPost`, `seqTrackFx`)<br>4. [`MANUAL.md`](../MANUAL.md) & [`README.md`](../README.md) |

---

## 3. Active Codebase Drift & Contradictions (Lint Findings)

As part of the Karpathy LLM Wiki pattern, the following minor discrepancies between layers were identified during the 2026-11-01 synthesis and should be kept in mind (or fixed when touching those modules):

1. ✅ **RESOLVED 2026-11-01 (Claude)** — **`user-tools/sndj.js` Missing Command `W` (Tremolo Override)**:
   - **Console (`src/engine.asm`)**: Implements `CMDID_W = 23` in `row_cmd_post` (`@cmd_w`: overrides `trk_trm_cmd,x` and `trk_trm,x`; `W00` suppresses tremolo for the note), verified by `tools/checks/commands.lua`.
   - **Browser (`user-tools/sndj.js`)**: `seqCmdPost` handles `V` (`cmd === 22`) but does not yet have a branch for `W` (`cmd === 23`).
2. ✅ **RESOLVED 2026-11-01 (Claude)** — **`user-tools/sndj.js` Coarse `TUNE` (`rec[9]`) Scope**:
   - **Console (`src/apu.asm` `trig_tune_load`)**: Applies `SB_INSTR + 9` (`TUNE`, signed semitones) to `SMP` (`type 0`), `WAV` (`type 2`), `SLICE` (`type 4`), and `KARP` (`type 5`), verified by `tools/checks/tune.lua`.
   - **Browser (`user-tools/sndj.js` `seqPitchCalc` / `seqTriggerNote`)**: Currently applies `rec[9]` only to `SLICE` (`type === 4`), not yet adding `rec[9]` in `seqPitchCalc` for `SMP`/`WAV` or `seqKarpTrigger` for `KARP`.
3. ✅ **RESOLVED 2026-11-01 (Claude)** — **`user-tools/sndj.js` Explicit `TSP 00` (`$80`) Sentinel in Tables**:
   - **Console (`src/engine.asm` `track_table` & `src/tablescr.asm`)**: Encodes an explicit zero-semitone reset in `TABLE` column 1 (`TSP`) as `$80` (since `$00` means `--` no change), clearing bit 7 when `== $80`.
   - **Browser (`user-tools/sndj.js` `seqTrackTable`)**: Checks `if (tsp !== 0)` and sign-extends `(tsp << 24) >> 24`, which treats `$80` as `-128` semitones instead of `0`!
4. ✅ **RESOLVED 2026-11-01 (Claude)** — **`src/songscr.asm` Double-Tap Window Hardcoded to `#25`**:
   - In [`src/songscr.asm`](../src/songscr.asm) line 216, the double-tap `B` check compares elapsed frames against `cmp #25` instead of `cmp opt_tapwin`, whereas `phrase.asm`, `chainscr.asm`, `instrscr.asm`, and `livescr.asm` all compare against `opt_tapwin`.
5. ⏳ **OPEN (needs Devin's OK to edit `CLAUDE.md`)** — **Historical Note in `CLAUDE.md` §10 vs. Current Code**:
   - `CLAUDE.md` §10 (written 2026-07-09) states "`W` is dropped... 24 live commands". Subsequent commits re-added `W` as **Tremolo Override** (`W xy`), bringing the live command count to **25** (matching `README.md`, `MANUAL.md`, `tools/commands.csv`, and `src/engine.asm`). Only `O` (`15`) remains unused.
6. ✅ **RESOLVED 2026-11-01 (Claude, pending `make check`)** — **`src/ram.inc` Main `.ENUM $0000` Overran `SHADOW_BG3` by 2 Bytes**: `pal_buf2` moved to `$0C24` in the `$0C00` block.
   - Summing every `db`/`dw`/`ds N` in `.ENUM $0000` places `pal_buf2` (`ds 8`) at `$03FA–$0401`. The `.ENDE` comment claims the block "ends exactly at `$0400`". This computation reproduces every Lua-tested address (`$0C`, `$90`, `$E4`, `$036A`, `$03F2–$03F4`, …), so it is very likely correct.
   - **Effect**: `pal_buf2` bytes 6–7 (CGRAM colour 19, the 4th `ATTR_PLAY` colour) alias `SHADOW_BG3` word 0 (tile at x=0, y=0). Whichever is written last wins: a top-left tile write corrupts colour 19, and a palette write corrupts the top-left tile.
   - **Confirm**: check `build/sndj.sym` (or the `wlalink -S` output) for `pal_buf2`. **Fix candidates**: move `pal_buf2` (or `hb_lfc` + `up_patch`) into `.ENUM $0C00`; no Lua check reads those addresses.
