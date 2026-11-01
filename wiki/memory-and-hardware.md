---
title: Memory Maps, Register Conventions & Hardware Invariants
category: architecture
updated: 2026-11-01
sources:
  - src/main.asm
  - src/ram.inc
  - src/song.inc
  - src/snes.inc
  - SAVEFORMAT.md
  - HARDWARE.md
  - CLAUDE.md
---

# Memory Maps, Register Conventions & Hardware Invariants

> [!IMPORTANT]
> **Every LLM agent must check this page before modifying any `.asm` or `.inc` file in `src/`.** Most catastrophic bugs in `sndj` come from violating Bank 0 capacity, the `$0400` WRAM boundary, 16-bit index stack pulls (`plx`/`ply`), or scratch variable ownership (`tmp0..2` vs `es0..3`).

See also: [`overview.md`](overview.md), [`files-scpu-core.md`](files-scpu-core.md), [`files-scpu-engine.md`](files-scpu-engine.md), [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

---

## 1. LoROM Cartridge Map (1 MB = 32 × 32 KB Banks, FastROM `$80+`)

The cartridge uses **LoROM** with `.BASE $80` so code executes out of the **3.58 MHz FastROM mirror** (`$80:8000–$80:FFFF`). Data Bank register is fixed at **`DB = $80`** after reset.

| Bank (`.BANK`) | FastROM Address | Contents | Access Method from Code (`DB=$80`) |
| :--- | :--- | :--- | :--- |
| **Bank 0** | `$80:8000–$80:FFBF` | **All executable 65816 code** (`.INCLUDE`d in [`src/main.asm`](../src/main.asm)) except the `Sync_IRQ_Body` spill; internal ROM header & vectors at `.ORG $7FC0` (`$80:FFC0–$80:FFFF`). | Direct 16-bit absolute (`jsr`, `lda.w`) because `DB=$80` and `PB=$80`. |
| **Banks 1–5** | `$81:8000–$85:FFFF` | **`SNPOOL`** marker (`6` bytes at `$81:8000`) + `build/pool.bin` (`POOL_ROM = $818006`, `POOL_RESERVED = $27FFA` = 163,834 bytes across 5 banks). | **MUST use 24-bit long addressing** (`lda.l POOL_ROM+...,x` or `[up_src]`). |
| **Bank 6** | `$86:8000–$86:FFFF` | Marker-wrapped patchable assets & read-only data tables:<br>• `SNFONT` + `font.bin` (`font_data`)<br>• `SNPAL0` + `schemes.bin` (`pal_schemes`)<br>• `logo.bin` (`logo_data`)<br>• `SNKIT0` + `kits.bin` (`factory_kits`)<br>• `SNDEF3` + `defaults.bin` (`factory_instr_type/smp/x7`)<br>• `SNFIR0` + `fir_presets` (64 B)<br>• `tables.inc` (`note_shift`, `note_semi2`, `pitch_octave7`, `default_waves`)<br>• `karptab.inc` (`karp_tab`)<br>• `help.inc` (`help_pgtab`, `help_data`)<br>• `driver.spc700.bin` (`driver_blob`)<br>• **Code spill**: `Sync_IRQ_Body` section from [`src/sync.asm`](../src/sync.asm). | **MUST use 24-bit long addressing** (`lda.l`, `jml`, `jsl` / `rtl`) or DMA with bank `:label`. |
| **Banks 7–31** | `$87:8000–$9F:FFFF` | Currently unused (`$FF` fill). Available for future code/data expansion. | Long addressing (`lda.l`, `jsl`). |

> [!CAUTION]
> **Bank 0 Space Constraint & WLA-DX Cross-Bank Label Gotcha:**
> 1. **Bank 0 ends at `.ORG $7FC0` (`$80:FFC0`).** Measured 2026-11-01 from a real build: **837 bytes free** after `residency_refresh` (977 after P2; 1,208 after P1/P3/P4; 1,276 at `857faf3`). Re-measure with the last-label method in `CLAUDE-REPORT.md` after large additions. If adding code causes `wlalink` to fail with a section/org overlap at `$7FC0`, move cold subroutines or lookup tables into `.BANK 6 SLOT 0` (see [`src/sync.asm`](../src/sync.asm) lines 131–240 for the exact pattern).
> 2. **WLA-DX drops the bank byte (`$81`) on cross-bank label expressions in long-indexed operands** (`lda.l label+offset,x` assembles with bank `$00`!). That is why `POOL_ROM` is defined as a numeric literal `.DEFINE POOL_ROM $818006` in [`src/song.inc`](../src/song.inc) and `POOL_TABLE` as `(POOL_ROM + 16)` in [`src/pool.asm`](../src/pool.asm). Always verify cross-bank indexed reads!

---

## 2. S-CPU WRAM Map (128 KB at `$7E:0000–$7F:FFFF`)

Because `DB = $80`, the first 8 KB of WRAM (`$7E:0000–$7E:1FFF`) is mirrored at `$80:0000–$80:1FFF` and can be accessed with 8-bit Direct Page (`$00–$FF`) or 16-bit absolute addressing (`$0000–$1FFF`). Everything at **`$7E:2000` and above MUST be accessed via 24-bit long addressing (`lda.l $7E0000 + ...,x` or `[dp]`)**.

```text
$7E:0000 .. $7E:003F   FROZEN Check Block (NEVER reorder — tools/checks/*.lua read by hex addr!)
$7E:0040 .. $7E:00FF   Direct Page pointers & hot scalars (up_src, sv_src, sv_dst, tmp0..2, etc.)
$7E:0100 .. $7E:03FF   Main WRAM variables (FULL — DO NOT ADD VARS HERE! Ends at $03FA since pal_buf2 moved to $0C24; $03FA–$03FF are 6 spare bytes)
$7E:0400 .. $7E:0BFF   SHADOW_BG3 (2 KB = 32x32 word tilemap shadow, DMA'd to VRAM every NMI)
$7E:0C00 .. $7E:0CE0+  Overflow WRAM variables (.ENUM $0C00 — add ALL new variables here! pal_buf2 = $0C24–$0C2B, sd_* SONG-draw snapshot = $0C2C–$0CE0, res_addr/res_start/res_keep/res_over/res_frag = $0CE1–$0D65)
   ...                 (Free low WRAM; hardware stack grows down from S = $1FFF)
$7E:2000 .. $7E:72FF   Contiguous Song Block (SB .. SB_END, $5300 = 21,248 bytes — see §2.2)
$7E:7400 .. $7E:75FF   Editor 2D Block-Select Clipboard (SONG / CHAIN / PHRASE copy/cut/paste)
$7E:7600 .. $7E:765F   FILES Purge chain reachability mark table (96 bytes)
$7E:7700 .. $7E:77BF   FILES Purge phrase reachability mark table (192 bytes)
$7E:8000 .. $7E:D2FF   SAVE/LOAD column-planar RLE staging buffer (IMAGE, $5300 = 21,248 bytes)
```

### 2.1 Frozen Check Addresses (`$0000–$003F` in [`src/ram.inc`](../src/ram.inc))
The Lua test suite in `tools/checks/*.lua` asserts on these exact hex addresses:
- `$00`: `frame_flag` (set by NMI, cleared by `main_loop`)
- `$01`: `magic_boot` (`$5D` once boot initialization completes)
- `$02–$03`: `frame_cnt` (16-bit NMI frame counter)
- `$04–$05`: `pad_raw`, `$06–$07`: `pad_held`, `$08–$09`: `pad_pressed`, `$0A–$0B`: `pad_event`
- `$0C`: `ui_mode` (active `SCREEN_*` id `0..15`)
- `$0D`: `apu_status` (`0` = OK, `1` = timeout `"APU?"`)
- `$0E`: `cur_x`, `$0F`: `cur_y` (PHRASE row cursor `0..15`)
- `$10`: `apu_seq` (mailbox flip-bit sequence byte)
- `$11`: `apu_tick` (mirrored SPC700 Timer-0 tick counter from `APUIO3`)
- `$12`: `hb_val` (heartbeat value written to DSP `$1D`)
- `$13–$14`: `last_pitch` (last 14-bit DSP pitch computed)
- `$15`: `kon_count` (cumulative count of KON triggers)
- `$16`: `eng_playing` (`0` = stopped, `1` = playing)
- `$17`: `eng_row` (track 0 phrase row mirror `0..15`)
- `$18`: `ed_phrase` (`0..191`), `$19`: `ed_col` (`0..3`)
- `$1A`: `ed_chain` (`0..95`), `$1B`: `song_cx` (`0..7`), `$1C`: `song_cy` (`0..127`), `$1D`: `song_top` (`0..112`), `$1E`: `chain_cy` (`0..15`), `$1F`: `chain_cx` (`0..1`)
- `$20–$27`: `trk_chain[8]`, `$28–$2F`: `trk_phrase[8]`, `$30–$37`: `trk_prow[8]`, `$38–$3F`: `trk_songrow[8]`

> [!WARNING]
> **Other WRAM addresses hardcoded in `tools/checks/*.lua`**:
> Several Lua tests also inspect variables outside `$00–$3F` by hex offset:
> - `$90`: `ed_instr`, `$91`: `if_cur` (INSTR cursor)
> - `$97..$D6`: `pool_map[64]`
> - `$E4`: `clip_kind`, `$E5`: `clip_len`, `$0C23`: `clip_width`
> - `$E8..$EF`: `trk_pending[8]`, `$F0`: `trk_mute`
> - `$018F`: `ed_lastchain`, `$01CE`: `fl_menu`, `$01D1–$01D2`: `tick_ctr`, `$01D4`: `opt_pal`, `$01D6..$01F5`: `pal_buf`, `$01F6`: `opt_cur`
> - `$02DB`: `pj_cur`, `$02FF`: `trk_tbl[0]`, `$0307`: `trk_tbl_row[0]`, `$0322`: `opt_clone`
> - `$0358`: `trk_voll[0]`, `$036A`: `opt_sync`, `$036C`: `sync_wait`, `$036D`: `sync_gctr`, `$036E`: `sync_cnt`, `$036F–$0370`: `sync_act`, `$0371`: `sync_shadow`, `$0373..$0397`: `midi_*`
> - `$03F2–$03F4`: `opt_kdelay`, `opt_krate`, `opt_tapwin`
> - `$0C00..$0C0F`: `trk_live_row[8]`, `trk_pend_row[8]`
>
> **Rule**: Never delete or reorder existing variables in [`src/ram.inc`](../src/ram.inc)! Always append new variables to the end of the `.ENUM $0C00` block (after `pal_buf2`).

### 2.2 The Contiguous Song Block (`$7E:2000–$7E:72FF`, [`src/song.inc`](../src/song.inc))
Total size: **`$5300` (21,248) bytes**. Fixed-size sections sit at the front; growable pools (`SB_CHAINS`, `SB_PHRASES`) sit at the end.

| Symbol | Bank `$7E` Addr | Offset | Size | Structure |
| :--- | :--- | :--- | :--- | :--- |
| **`SB_SONG`** | `$7E:2000` | `+$0000` | `$0400` (1,024 B) | `8 tracks × 128 rows` (track-major: `track * 128 + row`; byte = chain id `0..95`, `$FF` = empty) |
| **`SB_INSTR`** | `$7E:2400` | `+$0400` | `$0400` (1,024 B) | `64 instruments × 16 bytes` (see [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md)) |
| **`SB_TABLES`** | `$7E:2800` | `+$0800` | `$0800` (2,048 B) | `32 tables × 64 bytes` (`16 rows × 4 bytes`: `V` `00..7F`, `TSP` signed semitones or `$80`=`00` reset, `CMD` `0..26`, `VAL` `00..FF`; `$00` = no change in all 4 cols) |
| **`SB_GROOVES`** | `$7E:3000` | `+$1000` | `$0100` (256 B) | `16 grooves × 16 bytes` (currently groove 0 steps `0` and `1` at `$7E:3000–$3001` form the active 2-step groove pair, values `1..15`) |
| **`SB_WAVES`** | `$7E:3100` | `+$1100` | `$0100` (256 B) | `8 wave banks × 32 bytes` (each byte `0..15` is a 4-bit sample height) |
| **`SB_KITS`** | `$7E:3200` | `+$1200` | `$0400` (1,024 B) | `16 kits × 16 slots × 4 bytes` (`+0` pool sample `0..63`, `+1` signed semitone tune, `+2` vol `0..127` where `0` = empty slot, `+3` flags) |
| **`SB_HEADER`** | `$7E:3600` | `+$1600` | `$0100` (256 B) | `+0` `SH_GROOVE`, `+1` `SH_TRANSPOSE` (signed), `+2` `SH_MAGIC` (`$D7`), `+3` `SH_EDL` (`0..15`), `+4` `SH_EFB` (signed), `+5` `SH_EVL` (signed), `+6` `SH_EVR` (signed), `+7` `SH_EON` (8-bit voice mask), `+8` `SH_FIR` (`0..7` preset or `$FF` custom), `+9..+16` `SH_NAME` (8 ASCII space-padded), `+17` `SH_MODE` (`0`=SONG, `1`=LIVE), `+18` `SH_BPM` (`80..255`, `0`->`150`), `+19..+26` `SH_FIRTAPS` (8 signed FIR tap bytes) |
| **`SB_CHAINS`** | `$7E:3700` | `+$1700` | `$0C00` (3,072 B) | `96 chains × 16 rows × 2 bytes` (`+0` phrase id `0..191` or `$FF` empty, `+1` signed transpose) |
| **`SB_PHRASES`** | `$7E:4300` | `+$2300` | `$3000` (12,288 B) | `192 phrases × 16 rows × 4 bytes` (`+0` note `0`=empty, `1..96`=`C-0..B-7`, `97`=`OFF`; `+1` instr `0..63` or `$FF`=none; `+2` cmd `0`=none, `1..26`=`A..Z`; `+3` val `00..FF`) |

---

## 3. 65816 Register Width & Scratch Ownership Rules

### 3.1 Register Width Convention (Invariant #8)
- **Default state everywhere**: **`A` = 8-bit (`M=1`, `.ACCU 8`), `X` and `Y` = 16-bit (`X=0`, `.INDEX 16`), Direct Page `D = $0000`, Data Bank `DB = $80`**.
- Any routine that widens `A` to 16-bit (`rep #$20` or `rep #$30`) **must** restore `sep #$20` (`.ACCU 8`) before returning (`rts`).
- **The 16-bit Index Stack Trap**: Because `X` and `Y` are always 16-bit:
  1. `phx` / `phy` push **2 bytes** and `plx` / `ply` pull **2 bytes**. Never push an 8-bit `A` with `pha` and pull it with `ply` (use `pla` then `tay` after zero-extending, or `rep #$20 / and #$00FF / tay / sep #$20`).
  2. `plx` and `ply` overwrite the CPU `N` and `Z` flags based on the 16-bit value pulled into `X`/`Y`! If you hold a return value in `A` across `plx`, you must explicitly `cmp #$00` after `plx` if you branch on `beq`/`bne`/`bmi`.

### 3.2 Scratch Variable Ownership Matrix
Violating scratch ownership causes silent register/loop corruption:

| Scratch Vars | Address | Who Clobbers It | Who May Use It Safely |
| :--- | :--- | :--- | :--- |
| **`tmp0`** | `$0065` (2B, Direct Page) | • `apu_wait_p0` (every APU command / DSP write!)<br>• `text_puts`, `text_dec3`, `fl_kb`<br>• `save.asm` (`rle_pack`, `heap_close`) | Leaf math or screen code **only between** `text_*` and `apu_*` calls. Never hold loop state in `tmp0` across `text_puts` or `apu_dsp_write`. |
| **`tmp1`** | `$0067` (2B, Direct Page) | • `apu_send` (every APU command / DSP write!)<br>• `text_dest` (**every** `text_puts`, `text_puttile`, `text_hex8` call!)<br>• `nudge_delta` (returns signed delta in `tmp1+1`) | Leaf address calculations only. `text_dest` runs in 16-bit A (`rep #$30`) and stores a 16-bit value to `tmp1`, so **both** `tmp1` and `tmp1+1` are clobbered by every `text_*` call that positions output. Never hold state in either byte across `text_*`; use `ui_cnt` for screen draw loops. |
| **`tmp2`** | `$0069` (2B, Direct Page) | • `apu_dsp_write` (clobbers `tmp2` and `Y`!)<br>• `nudge_delta` (reads coarse step from `tmp2`) | Screen helpers (`song_cell_addr`, `phrase_draw`, `chain_draw`) that do not call `apu_dsp_write`. |
| **`ui_cnt`** | `$0192` (1B) | Screen draw routines (`draw_minimap`, `song_draw`, `instr_draw`, etc.) | Dedicated loop counter for screen rendering across `text_*` calls. |
| **`es0..es3`** | `$017D–$0184` (4×2B, **outside Direct Page** — no `[dp]`/`(dp),y` addressing) | • `engine_update` (`es3` holds remaining tick catch-up count!)<br>• `pool_entry_src`, `residency_build`, `wave_compile`<br>• Screen editors during `screen_update` | Sequencer routines (`es0..es2` inside `engine_tick`; **never clobber `es3` inside `engine_tick`, `apu_*`, or `sync_*`**). Screen routines may freely use `es0..es3` during `screen_update` (since `screen_update` runs after `engine_update` in `main_loop`), except across `wave_compile` or `residency_build`. |
| **`str_buf`** | `$019C–$01C3` (40B) | • `karp_trigger` (`+0..+7`)<br>• `track_row` / `track_trigger_note` (`+26..+31`)<br>• `wave_compile` (`+0..+32`)<br>• Screens (`+24..+39` during `screen_update`) | Temporary formatting/staging within a single phase. Never store persistent state here. |
| **`sync_irq_slot`, `sync_irq_delta`** | `$03F5–$03F6` | `Sync_IRQ_Body` (4x/frame V-timer IRQ) | **IRQ-exclusive.** The V-timer IRQ must never touch `tmp0..2` or `es0..3`. |

---

## 4. ARAM Layout (64 KB on SPC700 / S-DSP)

```text
$0000 .. $00FF   Zero page & SPC700 variables ($0010..$001A in driver.asm)
$0100 .. $01FF   SPC700 hardware stack (initial SP = $EF)
$0200 .. $0FFF   Resident SPC700 driver code (driver.spc700.bin, ~600 bytes)
$1000 .. $10FF   S-DSP Sample Directory (DIR = $10; 64 entries × 4 bytes [start_lo, start_hi, loop_lo, loop_hi]):
                   • Slot 0 ($1000): 9-byte silent BRR stub at $1200
                   • Slots 1..55 ($1004..$10DF): Resident pool samples + SLICE/LOOP-override aliases
                   • Slots 56..63 ($10E0..$10FF): 8 compiled single-cycle WAV banks
$1100 .. $118F   8 compiled WAV banks (8 × 18 bytes = 2 BRR blocks each, filter 0, range 11, looped)
$1200 .. $1208   9-byte silent_brr stub ($03, 0,0,0,0,0,0,0,0)
$1209 .. (ESA<<8)-1  Resident BRR sample heap (res_cursor tracks free end)
(ESA<<8) .. $FFFF    Hardware Echo Buffer: size = EDL * 2048 bytes (0..30 KB; when EDL=0, ESA=$FF uses 4 bytes at $FF00..$FF03)
```

---

## 5. SRAM Layout (32 KB at `$70:0000–$70:7FFF`, `SNDJ1` v2)

```text
$70:0000 .. $70:0004   5B  Magic "SNDJ1"
$70:0005               1B  Format version ($02)
$70:0006               1B  Reserved ($00)
$70:0007               1B  Persistent option: opt_pal (0..7)
$70:0008               1B  Persistent option: opt_clone (0=SLIM, 1=DEEP)
$70:0009               1B  Persistent option: opt_sync (0=OFF, 1=OUT, 2=PULSE, 3=IN, 4=MIDI, 5=IN24)
$70:000A               1B  Persistent option: opt_kdelay (4..30, default 14)
$70:000B               1B  Persistent option: opt_krate (1..8, default 3)
$70:000C               1B  Persistent option: opt_tapwin (10..40, default 24)
$70:000D .. $70:000F   3B  Reserved ($00)
$70:0010 .. $70:010F  256B Directory: 16 slots × 16 bytes:
                             +0: status ($A5 = valid, $FF = empty; packed contiguously 0..used-1)
                             +1..+2: 16-bit LE heap offset ($0110+)
                             +3..+4: 16-bit LE packed byte size
                             +5..+6: 16-bit LE CRC-16/CCITT (poly $1021, seed $FFFF)
                             +7: reserved ($00)
                             +8..+15: 8-char ASCII song name (space-padded)
$70:0110 .. $70:7FFF  ~31.7 KB Dense variable-length heap of column-planar RLE-packed songs
```

---

## 6. Hard Invariants & Silicon Errata Defenses (`CLAUDE.md` §20 & `HARDWARE.md`)

> Summary of the 6 invariants most likely to bite during edits. `CLAUDE.md` §20 is authoritative and lists all 13.

1. **APU Mailbox Port Read Glitch (Hardware Erratum, Invariant #13)**:
   - On real SNES silicon, an SPC700 read of `$F4–$F7` (`$2140–$2143`) during an S-CPU write returns **mixed bits** (emulators do not model this).
   - **Defense**: `src/apu/driver.asm` double-reads `rPORT0` (`mov a, rPORT0 / cmp a, rPORT0 / bne ...`) in both the main loop and bulk upload loop, and bulk mode accepts **only** the exact expected successor counter (`bulk_ctr = 1..255`, `0` = end). On timeout, S-CPU `apu_upload_block` runs `apu_resync` (`APUIO0 = 0`) and retries once.
2. **Mailbox Waits Always Time Out (Invariant #1)**:
   - Never write an unbounded spin loop waiting on `APUIO0–3`. All waits go through `apu_wait_p0` (`apu_tmo = 4`), setting `apu_status = 1` (displaying inverted `APU?` at top-right) on timeout.
3. **Echo Buffer Reconfiguration & Shrinking Offset Drain (Invariant #4)**:
   - S-DSP writes to `[ESA<<8, ESA<<8 + EDL*2048)` whenever `FLG` bit 5 (`ECEN`) is clear—even when echo volume is 0. Furthermore, the S-DSP internal echo offset counter **free-runs even when `ECEN` is disabled**! If `EDL` is shrunk while an in-flight offset is past the new wrap boundary, re-enabling echo writes causes the DSP to write past the buffer and wrap into low ARAM (corrupting the driver and sample directory!).
   - **Defense**: `echo_cfg` in `src/apu/driver.asm` disables `ECEN` (`FLG=$60`), waits out the old delay (`cur_edl + 1` Timer-0 periods), writes new `ESA`/`EDL`, zeroes the new buffer, and **if `new_edl < cur_edl` (`shrinking == 1`), waits an additional 17 Timer-0 periods (~270 ms)** for the internal offset counter to wrap before clearing `FLG` to `$00`. Meanwhile, S-CPU sets `apu_cool` so `apu_update` skips heartbeat writes while the driver is busy inside `echo_cfg`.
4. **Fresh Battery SRAM Powers Up as `$FF` (`HARDWARE.md`)**:
   - Unformatted SRAM reads `$FF` everywhere. `sram_check` seeds all option bytes at format time, and `palette_boot` / `sync_boot` / `options_boot` explicitly range-check (`cmp #max / bcc`) rather than bit-masking (`$FF & 7` would select palette 7).
5. **VRAM / CGRAM Access Only in VBlank or Force-Blank (Invariant #6)**:
   - Screen and editor code **never** touches `$2115–$2122`. Text writes go to `SHADOW_BG3` (`$0400–$0BFF`), and palette writes go to `pal_buf`/`pal_buf2` with `pal_dirty = 1`.
6. **5A22 Hardware Multiplier/Divider Discipline (Invariant #9)**:
   - Hardware multiply (`WRMPYA/B` `$4202/$4203`, 8 cycles) and divide (`WRDIVL/H/B` `$4204–$4206`, 16 cycles via `jsr div_wait`) are used only in `main_loop` (never inside `Vec_NMI` or `Sync_IRQ_Body`).
