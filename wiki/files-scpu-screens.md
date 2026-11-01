---
title: File Reference — All 15 Tracker UI Screens (src/*scr.asm & phrase.asm)
category: files
updated: 2026-11-01
sources:
  - src/phrase.asm
  - src/chainscr.asm
  - src/songscr.asm
  - src/instrscr.asm
  - src/filescr.asm
  - src/echoscr.asm
  - src/wavescr.asm
  - src/livescr.asm
  - src/kitscr.asm
  - src/optionscr.asm
  - src/groovescr.asm
  - src/projectscr.asm
  - src/firscr.asm
  - src/tablescr.asm
  - src/helpscr.asm
---

# File Reference: All 15 Tracker UI Screens

All 15 screen files are `.INCLUDE`d into **Bank 0** (`$80`) in [`src/main.asm`](../src/main.asm) and dispatched from `screen_update` in [`src/screens.asm`](../src/screens.asm).

See also: [`overview.md`](overview.md), [`memory-and-hardware.md`](memory-and-hardware.md), [`files-scpu-core.md`](files-scpu-core.md), [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

---

## 1. Composing Spine (`SONG`, `LIVE`, `CHAIN`, `PHRASE`, `INSTR`, `TABLE`)

### `src/songscr.asm` (1,002 lines) — `SCREEN_SONG` (`3`)
- **Role**: 8-track (`V1..V8`) × 16-row scrolling view (`song_top`) into the 128-row arrangement grid (`SB_SONG`, `$7E:2000–$23FF`).
- **Key Routines**: `song_init_screen` (redirects to `live_init` if `SH_MODE != 0`), `song_update`, `song_cursor_cell`, `song_cell_addr`, `song_cursor_move`, `song_snap_window`, `song_head_glyph` (shared with `livescr.asm`: returns `GLYPH_ARROW_R` steady/flashing or `'X'` stop marker), `song_draw`, `song_dtap`.
- **Features**:
  - `B` tap inserts `ed_lastchain`; `B + D-pad` nudges (`±1` L/R, `±16` U/D); `B + A` cuts; `B + Y` copies; `Y + Up/Down` pages `±16` rows.
  - Double-tap `B` (`song_dtap`): pastes rectangular song clipboard (`clip_kind == 3`), or mints a new chain (`find_free_chain`) on an empty cell, or clones (`clone_chain`, honoring `opt_clone` `SLIM`/`DEEP`) on a populated cell.
  - `Y + B` enters 2D multi-track block selection (`blk_mode`, `blk_start`, `blk_col`), copying/cutting into `$7E:7400`.
  - `X + Up/Down` toggles mute (`trk_mute`); `X + Left/Right` solos track.
- **Redraw gating (P2, 2026-11-01)**: `song_draw` first calls `song_draw_changed`, which compares everything the grid shows against a 176-byte snapshot (`sd_snap`): `song_top`, cursor, block state, `eng_playing`, per-track `trk_pending`/`trk_songrow`/`trk_live_row`/`trk_pend_row`/halted, the cue-flash phase (only while a cue is pending) and the 8 × 16 visible cells. It runs `song_draw_full` only on a difference. **No dirty flag is needed at edit sites**, and any new input to the drawing must be added to `song_draw_changed`. `text_clear` invalidates the snapshot. LIVE shares this through `live_update → song_draw`. Measured: SONG/LIVE went from ~22–30 fps to 60 fps with a busy song.

### `src/livescr.asm` (394 lines) — `SCREEN_LIVE` (`8`)
- **Role**: Quantized performance clip launcher sharing `SONG`'s grid and cursor (`song_cx`, `song_cy`, `song_top`).
- **Key Routines**: `live_init`, `live_update`, `live_queue_cursor`, `live_launch_row`, `live_pending_reset`, `engine_play_live`, `live_draw`.
- **Features**:
  - Reached via `Select` from any screen (stores return screen in `live_prev`) or when `SH_MODE == 1`.
  - `Start` launches all tracks from cursor row (`live_launch_row`); `A + B` queues/stops the single cell under the cursor (`live_queue_cursor`: writes chain id or `$FE` stop marker to `trk_pending,x`, firing at the next phrase boundary on playing tracks or next 16-row bar boundary `eng_barflag` on halted tracks).
  - Plain `B` tap inserts on an empty cell (inert on occupied cells so accidental taps don't overwrite live clips), and double-tap `B` mints/clones chains without starting transport (`live_mint.lua`).

### `src/chainscr.asm` (1,030 lines) — `SCREEN_CHAIN` (`2`)
- **Role**: 16-row × 2-column (`PHRASE`, `TSP`) editor for `ed_chain` (`0..95`, `SB_CHAINS` at `$7E:3700–$42FF`).
- **Key Routines**: `chain_init`, `chain_update`, `chain_cursor_phrase`, `chain_draw`, and the **shared global helper `nudge_delta`** (computes signed delta in `tmp1+1` from `pad_event` D-pad bits: `±1` for Left/Right, `±tmp2` for Up/Down).
- **Features**:
  - `B` tap inserts `ed_lastphrid` / `ed_lasttsp`; double-tap `B` pastes (`clip_kind == 2`), mints a free phrase (`find_free_phrase`), or clones the phrase under the cursor (`clone_phrase`).
  - `Y + Up/Down` switches `ed_chain` (`0..95`); `L/R` or `Y + Left/Right` switches to the chain on the adjacent track at `song_cy` (`chan_update`).
  - `Y + B` 2D rectangular block selection (`clip_kind = 2` at `$7E:7400`).

### `src/phrase.asm` (1,511 lines) — `SCREEN_PHRASE` (`1`)
- **Role**: 16-row × 4-column (`NOTE`, `IN`, `CMD`, `VAL`) editor for `ed_phrase` (`0..191`, `SB_PHRASES` at `$7E:4300–$72FF`).
- **Key Routines**: `phrase_init`, `phrase_update`, `phrase_cursor_instr`, `phrase_draw`, `draw_note`.
- **Features**:
  - `B` tap on empty cell inserts `ed_lastnote` (+ auto-stamps `ed_lastinstr`), `ed_lastinstr`, `ed_lastcmd`, or `ed_lastval` and auditions on voice 0 (`audition_note` or 3-voice `audition_chord` when `CMD == C`); `B` tap on occupied `NOTE`, `IN`, or `C`-command cell auditions it.
  - `B + D-pad` nudges (`NOTE`: `±1` semi L/R, `±12` octave U/D, wrapping to `97 = OFF` above `B-7` when nudging down from `C-0` or up from `B-7`; `IN`: `±1` / `±16`; `CMD`: `±1` / `±4` across `1..26` `A..Z`; `VAL`: `±1` / `±16`).
  - Context-aware `NOTE` column display (`draw_note`): if the row's resolved instrument is `KIT`, displays `hex_slot + 3-char sample name`; if `SLICE`, displays `S + hex_slice + 2-char sample name`; otherwise displays standard `C-4`..`B-7` / `OFF`.
  - `Y + Up/Down` walks to the previous/next populated phrase in `ed_chain` (`chain_cy` moves with it).
  - `Y + B` 2D rectangular block selection (`clip_kind = 1` at `$7E:7400`) and single-column `B + A` cut / `B + Y` copy.

### `src/instrscr.asm` (957 lines) — `SCREEN_INSTR` (`4`)
- **Role**: Type-switched parameter editor for `ed_instr` (`0..63`, `SB_INSTR` at `$7E:2400–$27FF`).
- **Key Routines**: `instr_init`, `instr_update`, `instr_draw`, `if_desc`, `if_get_x`, `if_set_x`, `if_field_vis`, `instr_table_dtap`.
- **Descriptor Table Architecture (`IF_COUNT = 26`)**:
  - `if_fields`: 26 × 4-byte descriptors `(byte_offset, bit_shift, mask, max_val)`.
  - `if_vis`: 26 bytes where bits `0..5` enable visibility for types `0=SMP, 1=KIT, 2=WAV, 3=NSE, 4=SLICE, 5=KARP`. Cursor movement (`Up/Down`) automatically skips invisible fields via `if_field_vis`.
  - Side effects on edit: invalidates `trk_instr_active[0..7] = $FF`; calls `residency_build` when `TYPE` (`0`), `SAMPLE` (`1`), `SLICES` (`7`), or `LOOP` (`18`) changes; auto-clamps `SH_EDL` to `1..2` and calls `apu_echo_apply` when switching `TYPE` to `KARP`.
  - Double-tap `B` on the `TBL` field (`field 24`) calls `instr_table_dtap` to mint a free table (when `--`) or clone the assigned table (`clone_table`).
  - **Critical Optimization**: `instr_draw` only runs when an edit or cursor/button event occurs (`@idle` returns immediately without redrawing), preventing VBlank overruns during fast arpeggios (`arp_screen.lua`).

### `src/tablescr.asm` (547 lines) — `SCREEN_TABLE` (`14`)
- **Role**: 16-row × 4-column (`V`, `TSP`, `CMD`, `VAL`) editor for `ed_table` (`0..31`, `SB_TABLES` at `$7E:2800–$2FFF`).
- **Key Routines**: `table_init`, `table_update`, `table_draw`, `tb_nudge`.
- **Special `TSP` Encoding**: In all 4 columns, byte `$00` means `--` (no change). In column 1 (`TSP`), byte `$80` encodes an explicit `00` (zero semitone transpose reset) so a table can return pitch to the base note after transposing! `B` tap on an empty `TSP` cell inserts `$80` (`00`), and nudging across zero writes `$80`.

---

## 2. Sound Design & Room Screens (`WAVE`, `KIT`, `ECHO`, `FIR`)

### `src/wavescr.asm` (393 lines) — `SCREEN_WAVE` (`7`)
- **Role**: 32-column × 16-level graphical bar-chart editor for `ed_wave` (`0..7`, `SB_WAVES` at `$7E:3100–$31FF`), rendered with quarter-block glyphs (`GLYPH_BLOCK..GLYPH_BLOCK14`).
- **Key Routines**: `wave_init`, `wave_update`, `wave_draw`, `wave_stamp`, `wave_edit`.
- **Features**: `B + Up/Down` edits sample `wv_x` (`0..31`); `B + Left/Right` paint-copies the current sample value into adjacent columns; `B + A` stamps the next factory preset shape (`wave_stamp`, cycling `wv_stamp` `0..7` from `default_waves`); `Y + Left/Right` or `A + Left/Right` switches wave banks. Calls `wave_compile` immediately on every change.

### `src/kitscr.asm` (426 lines) — `SCREEN_KIT` (`9`)
- **Role**: 16-slot × 3-column (`SMP`, `TUNE`, `VOL`) drum kit editor for `ed_kit` (`0..15`, `SB_KITS` at `$7E:3200–$35FF`).
- **Key Routines**: `kit_init`, `kit_update`, `kit_audition`, `kit_draw`.
- **Features**: `B` tap auditions the cursor slot on voice 0 (`kit_audition`); `B + D-pad` nudges (`SMP` edits trigger `residency_build` and auto-seed `VOL = $60` if the slot was previously empty `vol == 0`); `B + A` zeroes slot `VOL` (clearing the slot); `Y + Up/Down` switches `ed_kit` (`0..15`).

### `src/echoscr.asm` (572 lines) — `SCREEN_ECHO` (`6`)
- **Role**: S-DSP hardware echo editor (`DELAY`, `FEEDBACK`, `ECHO L`, `ECHO R`, `EON MASK`, `FIR` preset `0..7`) + live ARAM budget ledger (`RAM xx.xKB / FREE xx.xKB (xxxMS)`) + 8-tap FIR hex preview.
- **Key Routines**: `echo_init`, `echo_update`, `echo_draw`, and **global helper `echo_auto_edl`** (called by `song_renew` and `filescr.asm` when creating a new song: sets `SH_EDL = min(6, max_free_edl)`).
- **Safety Clamp**: `EDL` is dynamically clamped to `($10000 - res_cursor) >> 11` so the echo buffer can never collide with resident samples in ARAM.

### `src/firscr.asm` (263 lines) — `SCREEN_FIR` (`13`)
- **Role**: 8-tap signed hex editor (`T0..T7`) for `SB_HEADER + SH_FIRTAPS` (`$7E:3613–$361A`) with bipolar ASCII bar graph (`-` left of center, `+` right of center).
- **Key Routines**: `fir_init`, `fir_update`, `fir_draw`, `fs_nudge`.
- **Features**: `B + D-pad` nudges tap `fs_row` (`0..7`), sets `SH_FIR = $FF` (displayed as `PRESET --`), and calls `apu_fir_apply`; `B + A` zeroes the tap (`$7F` on `T0`); `Y + Up/Down` recalls ROM preset `0..7` (`apu_fir_preset`).

---

## 3. Project, Device, Storage & Reference Screens (`GROOVE`, `PROJECT`, `FILES`, `OPTIONS`, `HELP`)

### `src/groovescr.asm` (356 lines) — `SCREEN_GROOVE` (`11`)
- **Role**: Edits the 2-step groove (`STEP 0`, `STEP 1` at `SB_GROOVES+0/1`, clamped `1..15` ticks) and displays the resulting effective tempo (`BPM = 12 * SH_BPM / (step0 + step1)`).
- **Exported Global Helpers**:
  - **`text_dec3`**: Prints 16-bit value `X` (`0..999`) as 3 decimal digits (`"  5"`, `"150"`), using `tmp0`.
  - **`div_wait`**: 16-cycle wait (`nop` × 8) after writing `WRDIVB` (`$4206`).

### `src/projectscr.asm` (302 lines) — `SCREEN_PROJECT` (`12`)
- **Role**: Edits song-level header settings (`NAME` readout, `TMPO` `80..255` tick BPM calling `apu_set_tempo`, `TSP` signed song transpose, `MODE` `SONG`/`LIVE`).
- **Key Routines**: `project_init`, `project_update`, `project_draw`, `pj_nudge`.

### `src/filescr.asm` (1,162 lines) — `SCREEN_FILES` (`5`)
- **Role**: SRAM slot manager (`0..15` + `(EMPTY)` row), inline song/file renamer, and unused-chain/phrase garbage collector (`PURGE CH`, `PURGE PH`).
- **Key Routines**: `files_init`, `files_update`, `files_menu`, `files_draw`, `purge_scan`, `purge_chains`, `purge_phrases`, and **global helper `fl_kb`** (prints byte count `X` as `xx.xKB`, also used by `echoscr.asm`).
- **Features**:
  - Stops transport on entry (`engine_stop`).
  - `Left/Right` moves character cursor `fl_ncur` (`0..7`); `B + D-pad` renames either the SRAM directory entry (on a saved slot) or `SH_NAME` (on the `(EMPTY)` row) via `fl_char_cycle`.
  - `A + B` opens the popup action menu (`SAVE`, `LOAD`, `CLEAR`, `PURGE PH`, `PURGE CH`, `CANC`). Destructive/state-changing items require a 2-step `SURE?` confirmation (`fl_armed`). Loading on the `(EMPTY)` row calls `song_renew` (`NEW SONG`).

### `src/optionscr.asm` (505 lines) — `SCREEN_OPTIONS` (`10`)
- **Role**: Device-persistent settings (`PALETTE` `0..7`, `CLONE` `SLIM`/`DEEP`, `VIDEO` `NTSC 60HZ`/`PAL 50HZ` + `CLOCK APU XTAL`, `SYNC` `OFF`/`OUT`/`PULSE`/`IN`/`MIDI`/`IN24`, `KEY DELAY` `4..30`, `KEY RATE` `1..8`, `TAP WIN` `10..40`) + live `RX` counter/frame monitor for `SYNC` and `MIDI`.
- **Key Routines**: `options_init`, `options_update`, `options_draw`, `opt_timing_edit`, `options_boot`.

### `src/helpscr.asm` (373 lines) — `SCREEN_HELP` (`15`)
- **Role**: 7-page in-ROM manual renderer (`help_pgtab` / `help_data` in Bank 6), global 2.5-second lone-`A`-hold toggle (`help_hotkey`), and 3-second boot hint banner (`hint_tick`).
- **Key Routines**: `help_init`, `help_update`, `help_draw_page`, `help_hotkey`, `help_reopen`, `hint_tick`.
