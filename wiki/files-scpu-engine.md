---
title: File Reference — Audio, Sequencer, Pool, Save & Sync (S-CPU + SPC700)
category: files
updated: 2026-11-01
sources:
  - src/apu/driver.asm
  - src/apu.asm
  - src/pool.asm
  - src/engine.asm
  - src/wave.asm
  - src/clone.asm
  - src/save.asm
  - src/sync.asm
  - src/midi.asm
---

# File Reference: Audio, Sequencer, Pool, Save & Sync

This page catalogs the SPC700 driver (`src/apu/driver.asm`) and all S-CPU audio, sequencing, storage, and hardware I/O modules in `src/`.

See also: [`memory-and-hardware.md`](memory-and-hardware.md), [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md), [`files-scpu-core.md`](files-scpu-core.md), [`files-scpu-screens.md`](files-scpu-screens.md).

---

## 1. `src/apu/driver.asm` (308 lines — SPC700 Assembly)
- **Assembled By**: `wla-spc700` -> `build/driver.spc700.bin`, linked into Bank 6 of the main ROM (`driver_blob`) and uploaded to ARAM `$0200` at boot via the IPL ROM protocol.
- **Zero-Page Variables (`$0010–$001A`)**: `last_cmd`, `tick`, `dest_lo`, `dest_hi`, `cur_edl`, `cur_esa`, `wait_cnt`, `new_edl`, `new_esa`, `shrinking`, `bulk_ctr`.
- **Mailbox Commands (`rPORT0 & $7F`)**:
  - `CMD_NOP ($00)`: Acknowledge only.
  - `CMD_DSP_WRITE ($01)`: Writes `rPORT2` (value) to S-DSP register `rPORT1` via `$F2/$F3`, then echoes `last_cmd` on `rPORT0`.
  - `CMD_UPLOAD ($02)`: Latches `dest_lo = rPORT1`, `dest_hi = rPORT2`, echoes `last_cmd`, initializes `bulk_ctr = 1`. Loops reading `rPORT0` (double-read glitch guard): if `rPORT0 == 0`, exits bulk mode (`last_cmd = 0`, `rPORT0 = 0`); if `rPORT0 == bulk_ctr`, copies `rPORT1, rPORT2, rPORT3` into `[dest_lo]+0..2`, advances `dest` by 3, echoes `bulk_ctr`, and increments `bulk_ctr` (wrapping `255 -> 1`, skipping `0`).
  - `CMD_TICKRATE ($03)`: Writes `rPORT1` to `rT0TARGET` (`$FA`, Timer-0 8 kHz divider) and echoes `last_cmd`.
  - `CMD_ECHO_CFG ($04)`: Latches `new_edl = rPORT1 & $0F` and `new_esa = rPORT2`, **immediately echoes `last_cmd` on `rPORT0`** (so the S-CPU does not time out during the ~270 ms buffer drain!), and calls `echo_cfg`.
- **Telemetry Loop (`main`)**:
  - Polls `rT0OUT` (`$FD`). When non-zero, adds to `tick`, publishes `tick` on `rPORT3`, and reads live `VxENVX` (`$08 | (pair*32)` and `$28 | (pair*32)`, where `pair = tick & 3`) onto `rPORT1` and `rPORT2`.

---

## 2. `src/apu.asm` (1,309 lines — Bank 0)
- **Role**: S-CPU APU driver uploader, mailbox transport, S-DSP shadow writer, tempo divider, 16-bit interpolated pitch calculator, instrument register loader, and editor note/chord auditioner.
- **Key Routines**:
  - `apu_wait_p0`: Polls `APUIO0 == A` with bounded timeout (`apu_tmo = 4` outer × 65,536 inner). Clobbers `Y` and `tmp0`. Returns `C=1` on timeout.
  - `apu_upload_driver`: IPL `$AA/$BB` upload of `driver_blob` to ARAM `$0200`, waits for `$EE` ready byte on `APUIO0`.
  - `apu_send`: Sends command `A` with 16-bit payload `X` (`APUIO1/2`), toggles bit 7 of `apu_seq` into `APUIO0`, awaits echo. Clobbers `Y, tmp0, tmp1`.
  - `apu_dsp_write`: Sends `CMD_DSP_WRITE` for DSP reg `A`, value `Y` (low byte). Clobbers `X, Y, tmp0, tmp1, tmp2`.
  - `apu_upload_block` / `apu_resync`: Uploads `up_len` bytes (rounded up to multiple of 3) from 24-bit `[up_src]` to ARAM `up_dest`. If `Y == up_patch`, ORs `$02` (BRR LOOP bit) into the byte in flight. On timeout, calls `apu_resync` (`APUIO0 = 0`) and retries once. Resets `up_patch = $FFFF` on exit.
  - `apu_audio_init`: Boot DSP setup (`DIR=$10`, `MVOLL/R=$60`, `ESA=$FF`, `EDL=$00`, `FLG=$20`, voices 0–7 default).
  - `apu_echo_apply` / `apu_echo_apply_light`: Writes `EVOLL/R`, `EFB`, calls `eon_sync` and `apu_fir_apply`. Full `apu_echo_apply` also sends `CMD_ECHO_CFG` when `SH_EDL != edl_applied` and sets `apu_cool` (`24` frames when shrinking `EDL`, or `edl*2+4` when growing) to pause heartbeat checks while the SPC700 zeroes/drains the echo buffer.
  - `apu_fir_preset` / `apu_fir_apply`: Copies 8-tap curve `A` (`0..7`) from Bank 6 `fir_presets` to `SB_HEADER + SH_FIRTAPS` and writes DSP `$0F..$7F`.
  - `apu_set_tempo`: Computes Timer-0 divider `20000 / clamp(BPM, 80, 255)` via hardware `WRDIVL/B` and sends `CMD_TICKRATE`.
  - `note_pitch` / `note_pitch_calc_only` / `note_pitch_raw` / `voice_pitch_write`: Computes 14-bit DSP pitch into `last_pitch` with `trig_semis` + `trig_fine` using 5A22 hardware multiplier (`WRMPYA/B`) for sub-semitone interpolation.
  - `trig_tune_pool` / `trig_tune_load`: Loads coarse (`trig_semis`) and fine (`trig_fine`) tuning from `POOL_TABLE+14/15` and `SB_INSTR+6/9` across `SMP`, `KIT`, `WAV` (`+1` semi, `-52` fine intrinsic offset), `NSE`, `SLICE`, and `KARP`.
  - `apply_instrument`: Configures `trig_voice` (`0..7`) from `SB_INSTR + A*16` (sets `SRCN` from `slice_base`/`pool_map`/`56+bank`, updates `eng_non`/`DSP_NON`, `eng_eon`/`DSP_EON`, synthesizes ADSR for `KARP`/`SLICE`/`SMP`, writes `VOLL/R` and latches `trk_voll/r`).
  - `audition_note` / `audition_chord`: Immediate preview on voice 0 (or voices 0–2 for `C xy` chords) when stopped (`eng_playing == 0`).
  - `apu_update`: Latches `APUIO3 -> apu_tick`, demuxes `APUIO1/2 -> envx_mirror[pair*2 .. +1]`, decrements `apu_cool`, and sends a periodic heartbeat to `DSP_UNUSED ($1D)` every 64 frames.

---

## 3. `src/pool.asm` (608 lines — Bank 0)
- **Role**: Reads the `SNDJPOOL` v2 sample pool in ROM Banks 1–5 (`POOL_ROM = $818006`), manages demand-driven ARAM sample residency (`$1209..ceiling`), and builds the 56-slot ARAM sample directory (`res_dir` -> `ARAM_DIR = $1000`).
- **Key Routines**:
  - `pool_entry_src`: Given pool index `A` (`0..pool_count-1`), reads its 16-byte directory entry at `POOL_TABLE + A*16` (`+8` `off_blk`, `+10` `len_blk`, `+12` `loop_blk`), converts `off_blk * 9` into a 24-bit LoROM pointer `up_src` (`bank = $81 + (F >> 15)`, `addr = $8000 | (F & $7FFF)`), sets `up_len = len_blk * 9`, and stores `loop_blk` in `es2`.
  - `residency_build`:
    1. Computes ARAM ceiling page `res_ceil = $100 - (SH_EDL * 8)` (`$FF` when `SH_EDL == 0`).
    2. Uploads 9-byte `silent_brr` to `$1200` (directory slot 0).
    3. Scans all 64 instruments (`SB_INSTR`, marking type 0 `SMP` samples via `res_mark`) and all 16×16 kit slots (`SB_KITS` where `vol > 0`, marking slot samples via `res_mark`).
    4. Runs a second pass over `SB_INSTR` to build zero-copy ARAM directory aliases in `slice_base[64]` for type 4 `SLICE` instruments (`2..16` equal block-aligned divisions) and type 0 `SMP` instruments with non-zero `LOOP` override (`rec[7]` bits 1–2).
    5. Uploads the 224-byte `res_dir` table (`56 * 4` bytes) to `ARAM_DIR` (`$1000`).
    - Full and **compacting**: clears `res_addr[]` and re-uploads every referenced sample (~0.85 s for the factory song). Used at boot, song load/NEW, INSTR TYPE edits, ECHO entry when `res_frag` is set, and as the refresh fallback.
  - `residency_refresh` (2026-11-01): the edit-time variant for INSTR SAMPLE/SLICES/LOOP and KIT sample edits. Same directory/alias rebuild, but `res_mark` reuses any sample whose data is already in ARAM (`res_addr[s]`, 16-bit start; 0 = absent) and uploads only new ones. `res_cursor` stays at its high-water mark, so replaced data is left behind (`res_frag = 1`). If a new sample doesn't fit around it (`res_over`), it falls through to the full build. Measured: swap to a resident sample 51 → 0 frames; to an unloaded 9.6 KB sample 72 → 22 frames.
  - `res_dirent`: writes directory entry `res_slot` from `res_start` + the pool loop block (`es2`; one-shots loop into the silent stub).

---

## 4. `src/engine.asm` (2,966 lines — Bank 0)
- **Role**: The 8-track sequencer, song block initializer (`song_init`/`song_renew`), transport controller, 25-command executor (`row_cmd_pre`, `row_cmd_post`, `table_exec`), type-specific triggers (`kit_trigger`, `slice_trigger`, `karp_trigger`), per-tick table stepper (`track_table`), and continuous LFO/slide/arp/delay/retrig/kill engine (`track_fx`).
- **Key Routines**:
  - `song_init` / `song_renew`: Initializes `[SB, SB_END)` (`$7E:2000–$7E:72FF`), seeds waves (`waves_seed`), groove 0 (`6, 6`), 8 boot instruments from Bank 6 `SNDEF3` (`factory_instr_type/smp/x7`) + instruments `8..63` as `SMP 0`, 16 kits from `SNKIT0` (`factory_kits`), and `SB_HEADER`. `song_renew` additionally calls `wave_sync_all`, `residency_build`, `echo_auto_edl`, and `apu_echo_apply`.
  - `engine_play` / `engine_play_from_cursor` / `engine_play_row` / `engine_play_phrase` / `engine_play_chain` / `engine_go` / `engine_stop` / `engine_toggle`: Transport entry points.
  - `engine_update` / `engine_sync_update` / `engine_tick` / `engine_tick_row` / `engine_tick_fx`: Sequencer tick loop.
  - `track_row` / `track_chain_step` / `track_load_chain_entry` / `track_load_songrow`: Per-track row advancement and chain/song walking (with upward covering-chain scan `@scan_up`, `walk_guard = 16`, and `hop_guard = 4`).
  - `row_cmd_pre` / `row_cmd_post` / `track_trigger_note` / `kit_trigger` / `slice_trigger` / `karp_trigger`: Row command and note trigger execution (see [`subsystems-audio-and-sequencer.md`](subsystems-audio-and-sequencer.md)).
  - `track_table` / `table_exec`: Per-tick (or per-note when `TBS=0`) 16-row table automation.
  - `track_fx` / `fx_slide` / `fx_arp` / `fx_vib` / `fx_trm`: Per-tick continuous modulators.

---

## 5. `src/wave.asm` (183 lines — Bank 0)
- **Role**: Manages the 8 drawn 32-sample wavetable banks (`SB_WAVES` at `$7E:3100–$31FF`).
- **Key Routines**:
  - `waves_seed`: Copies 256 bytes from Bank 6 `default_waves` (`tables.inc`) into `SB_WAVES`.
  - `wave_compile`: Compiles wave bank `A` (`0..7`) into an 18-byte (2-block) BRR in `str_buf+0..17` (Block 0 header `$B0` = range 11, filter 0; Block 1 header `$B3` = range 11, filter 0, `LOOP+END`; nibbles `(sample - 8) & $0F`) and uploads it to ARAM `$1100 + bank*18`.
  - `wave_sync_all`: Writes ARAM directory slots `56..63` (`$10E0..$10FF`) pointing to `$1100 + bank*18`, then calls `wave_compile` for banks `0..7` (must run *after* directory upload because 3-byte bulk padding of the 32-byte directory touches `$1100`).

---

## 6. `src/clone.asm` (436 lines — Bank 0)
- **Role**: Implements double-tap `B` minting and cloning for chains, phrases, and tables.
- **Key Routines**:
  - `find_free_chain` / `find_free_phrase` / `find_free_table`: Returns the lowest unused ID in `A` (`C=0`), or `C=1` if the pool is full. (`find_free_table` also calls `table_is_referenced` over all 64 instruments' byte 12 `TBL` fields so freshly minted all-zero tables aren't re-picked.)
  - `clone_phrase` / `clone_table`: Allocates a free destination ID and copies the 64-byte source phrase/table into it.
  - `clone_chain`: Allocates a free chain ID and copies the 32-byte source chain; if `opt_clone != 0` (`DEEP` mode), also clones every unique referenced phrase inside that chain (deduplicating repeated phrases within the same chain via `cl_e`/`cl_s`).

---

## 7. `src/save.asm` (976 lines — Bank 0)
- **Role**: `SNDJ1` v2 SRAM manager (`$70:0000–$70:7FFF`), column-planar staging (`$7E:8000`), RLE codec, CRC-16/CCITT, and dense heap compaction.
- **Key Routines**:
  - `sram_check`: Verifies `"SNDJ1"` magic and version `2` at `$70:0000..$0005`. If unformatted, writes magic/version, zeroes option bytes `$70:0006..$000F`, seeds `opt_kdelay=14, opt_krate=3, opt_tapwin=18`, and marks all 16 directory entries (`$70:0010..$010F`) `$FF` empty.
  - `stage_out` / `stage_in`: Transposes `SB` (`$7E:2000–$72FF`) to/from the column-planar `IMAGE` buffer (`$7E:8000–$D2FF`) so empty phrase/chain columns compress into long runs.
  - `rle_pack` / `rle_unpack` / `crc16_update`: Packs `IMAGE` into SRAM at `[sv_dst]` up to `sv_limit` bytes (`C=1` on overflow) while computing CRC-16/CCITT (`sv_crc`); unpacks SRAM `[sv_src]` into `IMAGE`.
  - `save_song` / `save_slot` / `slot_clear` / `heap_close` / `load_slot`: Writes new packed song at `heap_free` (the end of the dense heap), updates the directory entry (`$A5` status written last for power-cut safety), and slides any songs above an overwritten/cleared hole downward via `heap_close`.

---

## 8. `src/sync.asm` (269 lines — Bank 0 + Bank 6 Spill)
- **Role**: Controller Port 2 external sync (`opt_sync`: `0=OFF`, `1=OUT`, `2=PULSE`, `3=IN`, `4=MIDI`, `5=IN24`).
- **Bank Placement**:
  - **Bank 0**: `sync_boot`, `sync_read`, `sync_play_start`, `sync_stop`, `sync_irq_arm`, `sync_irq_disarm`, `sync_pulse_tick`.
  - **Bank 6 (`.SECTION "Sync IRQ Capture" FREE`)**: `Sync_IRQ_Body`, `sync_irq_next`, `sync_irq_poll`, `sync_in_capture`, `sync_vtime_ntsc` (`16, 82, 148, 214`), `sync_vtime_pal` (`16, 94, 172, 250`).
- **Behavior**:
  - In `SYNC_IN` and `SYNC_IN24`, `sync_irq_arm` enables the 4x-per-frame V-timer IRQ (`NMITIMEN = $A1`). Each IRQ checks `HVBJOY & 1 == 0`, reads Port 2 Data1 (`JOYSER1` `$4017` bit 0), and on any edge (`!= sync_last`), increments `sync_gctr` and `sync_act`.
  - In `SYNC_PULSE`, `sync_pulse_tick` drives Port 2 IOBit (`WRIO` `$4201` bit 7) low for 4 ticks every 12 APU ticks (2 PPQN = 1 pulse per 2 tracker rows).

---

## 9. `src/midi.asm` (482 lines — Bank 0)
- **Role**: Controller Port 2 external MIDI takeover mode (`opt_sync == SYNC_MIDI` when `eng_playing == 0`).
- **Protocol & Mapping**:
  - Every frame in `main_loop`, `midi_service` polls up to 8 3-byte frames from the external bridge (`WRIO` `$4201` bit 7 = push-pull CLK output with 24-loop settle delay `mp_settle`; `JOYSER1` `$4017` bit 0 = MSB-first DAT input; leading bit `1` = 24-bit event `status, d1, d2` follows, `0` = queue empty).
  - Maps channels `0..7` (MIDI 1–8) to voices `0..7`:
    - `0x8n` / `0x9n vel=0`: Note Off (`DSP_KOF`).
    - `0x9n`: Note On (`note = d1 - 11` clamped `1..96`; scales instrument `VOL L/R` by velocity `d2` via 5A22 multiplier `WRMPYA/B`; triggers `SMP`, `KIT`, `WAV`, `NSE`, `SLICE`, or `KARP`).
    - `0xBn`: Control Change (`CC 7` volume, `CC 10` pan, `CC 91` echo send `EON`, `CC 74` FIR preset `0..7`, `CC 120/123` all-notes-off).
    - `0xCn`: Program Change (selects instrument `d1 & 63` for channel `n`).
    - `0xEn`: Pitch Bend (14-bit value -> `±2` semitones in `midi_bsemi,x` / `midi_bfine,x`, live-updating sounding voice pitch).
