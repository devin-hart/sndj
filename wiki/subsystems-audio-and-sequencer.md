---
title: Audio, Sequencer, Instrument Types & Sync Subsystems
category: subsystems
updated: 2026-11-01
sources:
  - src/apu/driver.asm
  - src/apu.asm
  - src/pool.asm
  - src/engine.asm
  - src/wave.asm
  - src/sync.asm
  - src/midi.asm
  - user-tools/sndj.js
---

# Audio, Sequencer, Instrument Types & Sync Subsystems

This page synthesizes how the S-CPU sequencer (`src/engine.asm`), APU bridge (`src/apu.asm`), sample pool residency manager (`src/pool.asm`), SPC700 driver (`src/apu/driver.asm`), and JS reference model (`user-tools/sndj.js`) work together.

See also: [`memory-and-hardware.md`](memory-and-hardware.md), [`files-scpu-engine.md`](files-scpu-engine.md), [`playbooks-and-sync-matrix.md`](playbooks-and-sync-matrix.md).

---

## 1. The 6 Instrument Types & Their 16-Byte Record (`SB_INSTR`)

Up to 64 instruments live at `SB_INSTR` (`$7E:2400–$7E:27FF`, 16 bytes each). Several bytes are reinterpreted depending on `rec[0]` (`TYPE`):

| Byte | `0: SMP` (Sample) | `1: KIT` (Drum Kit) | `2: WAV` (Wavetable) | `3: NSE` (Noise) | `4: SLICE` (Sliced Sample) | `5: KARP` (Karplus-Strong) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`+0`** | `0` (`TYPE_SMP`) | `1` (`TYPE_KIT`) | `2` (`TYPE_WAV`) | `3` (`TYPE_NSE`) | `4` (`TYPE_SLICE`) | `5` (`TYPE_KARP`) |
| **`+1`** | Pool sample `0..63` | Kit id `0..15` | Wave bank `0..7` | Noise clock (`0`=note-driven, `1..32`=pinned rate `0..31`) | Pool sample blob `0..63` | Exciter wave bank `0..7` |
| **`+2`** | `ADSR1` (`ATK` bits 0–3, `DEC` bits 4–6; bit 7 forced `1` on DSP) | *(Unused — kit uses fixed `$FF/$E0` ADSR)* | `ADSR1` | `ADSR1` | Low nibble = `ATK` (`0..15`), High nibble = `FADE` (`0..15`, sustain rate `sr = FADE*2` or `31` if `F`) | Low nibble = `DAMP` (`0..15` -> loop gain `g = 127 - d*8`), High nibble = `BURST` (`0..15` -> exciter `sr = 16+b`) |
| **`+3`** | `ADSR2` (`SUS RATE` bits 0–4, `SUS LVL` bits 5–7) | *(Unused)* | `ADSR2` | `ADSR2` | *(Unused — `SLICE` synthesizes `ADSR1=$80\|(DEC=7)<<4\|ATK`, `ADSR2=$E0\|sr`)* | `SUSTAIN` (`0..127` -> written to `DSP_EFB` on trigger) |
| **`+4`** | `VOL L` (`0..127`) | Master `VOL L` (`0..127`, scales kit slot `vol`) | `VOL L` (`0..127`) | `VOL L` (`0..127`) | `VOL L` (`0..127`) | `VOL L` (`0..127`) |
| **`+5`** | `VOL R` (`0..127`) | Master `VOL R` (`0..127`, scales kit slot `vol`) | `VOL R` (`0..127`) | `VOL R` (`0..127`) | `VOL R` (`0..127`) | `VOL R` (`0..127`) |
| **`+6`** | `FINE` (signed 1/256 semitone) | `FINE` | `FINE` | *(Unused)* | *(Unused)* | `FINE` |
| **`+7`** | Bit 0: `ECHO` (`EON`)<br>Bits 1–2: `LOOP` (`0`=pool, `1`=force ON, `2`=force OFF) | Bit 0: `ECHO` (`EON`) | Bit 0: `ECHO` (`EON`) | Bit 0: `ECHO` (`EON`) | Bit 0: `ECHO` (`EON`)<br>Bits 4–7: `SLICES - 1` (`1..15` -> `2..16` slices) | *(Forced `EON = 1` on trigger)* |
| **`+8`** | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) |
| **`+9`** | `TUNE` (signed semitones) | *(Per-slot tune in `SB_KITS`)* | `TUNE` (signed semitones) | *(Unused)* | `TUNE` (signed semitones for all slices) | `TUNE` (signed semitones) |
| **`+10..11`** | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) | Reserved (`0`) |
| **`+12`** | `TBL` (`0..31`, or `>=32`/`$FF` = off) | `TBL` | `TBL` | `TBL` | `TBL` | `TBL` |
| **`+13`** | `TBS` (`0`=note-sync, `1..15`=ticks/row) | `TBS` | `TBS` | `TBS` | `TBS` | `TBS` |
| **`+14`** | `VIB` (`speed` hi, `depth` lo) | `VIB` | `VIB` | `VIB` | `VIB` | `VIB` |
| **`+15`** | `TRM` (`speed` hi, `depth` lo) | `TRM` | `TRM` | `TRM` | `TRM` | `TRM` |

### How `SLICE` (Type 4) Works Without Extra ARAM
- When `residency_build` (`src/pool.asm`) runs, it first uploads all referenced pool samples once into ARAM (`$1209+`), setting the final BRR block's `LOOP+END` bits (`$03`).
- In a second pass over `SB_INSTR`, for each `SLICE` instrument with `n = (rec[7] >> 4) + 1` (`2..16` slices), it divides the sample's `total_blocks` by `n` (`sl_step = (blocks / n) * 9` bytes) and allocates `n` consecutive 4-byte ARAM directory entries (`res_dir`, recording the base slot in `slice_base[instr_id]`).
- Each directory entry points `start` to `sample_aram_addr + k * sl_step` and `loop` to `$1200` (`silent_brr`). Even though only the last slice has a physical `END` block, `apply_instrument` synthesizes a hardware ADSR envelope from `ATK` and `FADE` (`rec[2]`) that decays to silence, or bleeds into subsequent slices when `FADE = 0`.
- At trigger time (`slice_trigger` in `src/engine.asm`), `(phrase_note - 1 + chain_tsp + pass_tsp) mod n` selects directory entry `slice_base[id] + slice_idx` and triggers it at native C-4 pitch (`note 49`) plus `rec[9]` (`TUNE`). In tables, the `TSP` column rotates and retriggers slices per tick!

### How `KARP` (Type 5) Turns the Echo Buffer into a Plucked String
- In S-DSP, an echo buffer of `EDL` (`1` or `2`, i.e., `512` or `1024` samples at 32 kHz) with high feedback (`EFB`) is a waveguide delay line whose harmonic modes sit at $f_k = \frac{k \cdot 32000}{512 \cdot \text{EDL} + d}$.
- `tools/maketables.py` precomputes `karp_tab` (in Bank 6 `build/karptab.inc`) for `EDL = 1` and `EDL = 2` across all 96 notes (`C-0..B-7`):
  - Picks the lowest harmonic integer $k \ge 1$ where the fractional delay $d = \frac{k \cdot 32000}{f} - 512 \cdot \text{EDL}$ falls inside $[0, 7)$ samples.
  - Encodes `pitch_lo, pitch_hi` (to pitch the 32-sample exciter wave at $k \times f$ so energy lands cleanly on mode $k$), integer tap index `i0` (`0..6`), and fractional tap weight `fr` (`0..255`).
- At trigger time (`karp_trigger` in `src/engine.asm`), the S-CPU:
  1. Scales the 2-tap linear interpolator `(256 - fr, fr)` by the instrument's `DAMP` gain `g = 127 - damp*8` via the 5A22 hardware multiplier (`WRMPYA/B`), placing the two adjacent non-zero taps at `FIR[i0]` and `FIR[i0+1]` (all other taps `0`) and shipping them to DSP `$0F..$7F`.
  2. Writes `SUSTAIN` (`rec[3]`) to `DSP_EFB` (`$0D`), forces `EON` (`$4D`) on for the voice, sets `SRCN` to `56 + exciter_bank`, configures a fast burst decay ADSR (`$FF`, `$00 | (16 + burst)`), and keys on the exciter wave!

---

## 2. Pitch Calculation & Tuning Hierarchy (`src/apu.asm`)

S-DSP pitch is a 14-bit value where `$1000` (4096) = 1:1 playback (32 kHz sample rate = 2000 Hz for a 16-sample BRR block, or 1000 Hz for a 32-sample 2-block `WAV`).
1. **Base Octave-7 Table (`pitch_octave7` in `tables.inc`)**: 12 16-bit words for `C-7..B-7`, `round($4000 × 2^(s/12))` (`$4000` up to `$78D1`), generated by `tools/maketables.py`. The engine right-shifts by `7 − octave`, so `C-4` (note `49`, octave 4) is `$4000 >> 3 = $0800`.
2. **Coarse & Fine Sum (`trig_tune_load` + `note_pitch_raw`)**:
   - Before computing pitch, `trig_tune_load` combines:
     - Pool entry default tuning (`POOL_TABLE + sample*16 + 14` coarse semitones, `+15` fine `1/256` semitones)
     - Instrument `FINE` (`rec[6]`, signed `1/256` semitone) + track `F` command `trk_fine,x`
     - Instrument `TUNE` (`rec[9]`, signed whole semitones)
     - For `WAV` (type 2): adds a fixed intrinsic offset (`+1` semitone, `-52` fine = `+204/256` semitones) because a 32-sample cycle at `$0800` plays at `500 Hz` (`1000 * 0.5`), which is `-196` cents below `C-4 = 261.6256 Hz` (`523.25 Hz` one octave up), so `+1` semi `-52/256` brings `C-4` to true concert `261.6 Hz` (`$0430`)!
   - If the signed sum of `trig_fine` is negative (`< 0`), `note_pitch_raw` borrows `-1` semitone from `np_note` and treats `np_fine` as an unsigned `0..255` fraction above the lower semitone.
   - It then computes `base = pitch(np_note)` and `next = pitch(np_note + 1)`, multiplies `(next - base) * np_fine` using hardware `WRMPYA/B`, and adds `(product >> 8)` to `base`.

---

## 3. Sequencer Tick Pipeline & Command Execution (`src/engine.asm`)

Each tick observed from `apu_tick` (or `sync_gctr` in `SYNC_IN24`) runs `engine_tick`:
1. **Groove Countdown (`eng_tickwait`)**:
   - Decrements `eng_tickwait`. If `> 0`, skips row advancement and jumps straight to `engine_tick_fx`.
   - When `eng_tickwait == 0`: toggles `eng_gpos` (`0 <-> 1`), loads the next step duration from `SB_GROOVES + eng_gpos` (`$7E:3000/3001`), and runs **`engine_tick_row`**.
2. **Row Advancement (`engine_tick_row` -> `track_row` for tracks `0..7`)**:
   - Steps `trk_prow,x`. At row 16 (`>= PHRASE_ROWS`), calls `track_chain_step` (which checks LIVE `trk_pending,x`, steps `trk_cpos,x`, or advances `trk_songrow,x`—looping back to the start of the contiguous chain block if the next song cell is `$FF`!).
   - Reads the 4-byte phrase row `(note, instr, cmd, val)` into `str_buf+28..31`.
   - Clears `str_buf+27` ("note consumed by pre-command" flag) and resets `trk_chord,x = 0`.
   - Calls **`row_cmd_pre`**, then **`track_trigger_note`** (if `str_buf+28 != 0` and `str_buf+27 == 0`), then **`row_cmd_post`**.
3. **Why Commands Are Split Between `row_cmd_pre` and `row_cmd_post`**:

| Phase | Commands Handled | Why This Phase Is Required |
| :--- | :--- | :--- |
| **`row_cmd_pre`** (Before `track_trigger_note`) | `A` (arp), `C` (chord), `D` (delay), `E` (echo send), `F` (fine tune), `G` (groove), `H` (hop), `I` (pass mask), `J` (pass tsp), `K` (kill), `L` (slide), `M` (master vol), `N` (noise), `Q` (GAIN override), `R` (retrig), `T` (tempo), `Y` (FIR preset), `Z` (pitch mod) | • `D` (`Dxy` > 0), `I` (when mask bit is 0), and `L` (when sliding from an active note) set `str_buf+27 = 1` to **suppress normal `track_trigger_note`**!<br>• `C` sets `trk_chord,x` and `F` sets `trk_fine,x` *before* `track_trigger_note` calculates pitch and fans out voices.<br>• `J` adds pass transpose to `str_buf+28` before trigger. |
| **`row_cmd_post`** (After `track_trigger_note`) | `B` (wave bank), `P` (pan), `S` (pitch sweep), `U` (surround phase invert), `V` (vibrato override), `W` (tremolo override), `X` (volume/accent) | `track_trigger_note` calls `apply_instrument` (which reloads `SRCN` and resets `trk_voll/r` from the instrument record) and reloads `trk_vib`/`trk_trm` and zeroes `trk_sl_rate`. Running `B`, `P`, `S`, `U`, `V`, `W`, `X` **after** `track_trigger_note` ensures same-row commands override the freshly triggered instrument! |

4. **Per-Tick Continuous Effects & Tables (`engine_tick_fx`)**:
   - For each track `0..7`: runs **`track_fx`** (processes `D` delayed trigger countdown, `K` kill countdown, `R` retrigger countdown, `L`/`S` pitch slide, `A` 3-tick arpeggio cycle, `V` triangle-LFO vibrato, `W`/instrument triangle-LFO tremolo) and **`track_table`** (steps 16-row `SB_TABLES` automation if `trk_tbl,x < 32`, applying `V` level, `TSP` transpose/slice-select, and calling `table_exec` -> `row_cmd_pre` + `row_cmd_post`).
   - Finally, ships batched **`koff_mask`** (`DSP_KOF = $5C`) and **`kon_mask`** (`DSP_KON = $4C`) once at the end of the tick.
   - **Chord Fanout Rule (`C xy`)**: When a track triggers with `trk_chord,x != 0`, `track_trigger_note` (and `fx_trm`) mirrors the note/volume onto `(track+1)&7` at `+x` semitones and `(track+2)&7` at `+y` semitones, setting `trk_instr_active` to `$FF` on those neighbour voices so they reload their own instrument when their own track next triggers.
