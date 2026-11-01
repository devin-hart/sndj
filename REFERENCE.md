# REFERENCE.md — Super Nintendo (SNES / SFC) Architecture, 65816, SPC700 & Audio Reference Manual

> **Purpose**: Technical reference guide for developing, optimizing, and debugging `sndj` on real Super Nintendo silicon and cycle-accurate emulators. Covers the 65816 S-CPU, SPC700 S-SMP, S-DSP, PPU/DMA subsystems, timing budgets, and silicon errata.

---

## Table of Contents
1. [S-CPU Architecture & 65816 Instruction Set](#1-s-cpu-architecture--65816-instruction-set)
2. [S-CPU Bus Timing, Memory Mapping & FastROM](#2-s-cpu-bus-timing-memory-mapping--fastrom)
3. [Direct Page, Stack & Addressing Modes](#3-direct-page-stack--addressing-modes)
4. [Hardware Multiplication, Division & Math Registers](#4-hardware-multiplication-division--math-registers)
5. [Interrupts, VBlank, H/V-Timer & Frame Timing](#5-interrupts-vblank-hv-timer--frame-timing)
6. [PPU Architecture, Tilemaps, Palettes & DMA](#6-ppu-architecture-tilemaps-palettes--dma)
7. [SPC700 (S-SMP) Architecture & Instruction Set](#7-spc700-s-smp-architecture--instruction-set)
8. [S-DSP Sound Architecture & Voice Model](#8-s-dsp-sound-architecture--voice-model)
9. [Bit Rate Reduction (BRR) Audio Format](#9-bit-rate-reduction-brr-audio-format)
10. [Echo Buffer, FIR Filter & S-DSP Internal Memory](#10-echo-buffer-fir-filter--s-dsp-internal-memory)
11. [S-CPU ⇄ SPC700 Mailbox Protocol & Silicon Errata](#11-s-cpu--spc700-mailbox-protocol--silicon-errata)
12. [Optimization Patterns, Traps & Anti-Patterns](#12-optimization-patterns-traps--anti-patterns)

---

## 1. S-CPU Architecture & 65816 Instruction Set

The Ricoh 5A22 is based on the WDC 65C816 16-bit microprocessor running at variable clock rates (3.58 MHz FastROM / 2.68 MHz SlowROM / 1.79 MHz internal/DMA).

### 1.1 CPU Registers & Modes
- **Accumulator (`A` / `C` / `B`)**:
  - In 8-bit mode (`M=1`): `A` is the lower 8 bits; `B` is the upper 8 bits (hidden accumulator accessed via `xba`).
  - In 16-bit mode (`M=0`): `C` is the combined 16-bit register (`A` refers to the full 16-bit word).
- **Index Registers (`X`, `Y`)**:
  - 8-bit mode (`X=1`) or 16-bit mode (`X=0`).
- **Stack Pointer (`S`)**: 16-bit register. Can point anywhere in Bank `$00` (typically initialized to `$1FFF` in WRAM).
- **Direct Page (`D`)**: 16-bit base address for zero-page/direct-page addressing. If `D != 0`, adds 1 cycle penalty. In `sndj`, **`D` is always `$0000`**.
- **Program Bank (`PB`)** and **Data Bank (`DB`)**: 8-bit bank registers for 24-bit addressing. In `sndj`, **`PB = $80`** and **`DB = $80`** after boot.

### 1.2 Processor Status Register (`P`)
```text
Bit:    7   6   5   4   3   2   1   0
Flag:   N   V   M   X   D   I   Z   C
```
- **`N` (Negative)**: Set if bit 7 (8-bit mode) or bit 15 (16-bit mode) of result is set.
- **`V` (Overflow)**: Signed arithmetic overflow.
- **`M` (Memory / Accumulator select)**: `1` = 8-bit Accumulator, `0` = 16-bit Accumulator.
- **`X` (Index register select)**: `1` = 8-bit `X`/`Y`, `0` = 16-bit `X`/`Y`.
- **`D` (Decimal mode)**: Binary-Coded Decimal arithmetic. **Always keep clear (`cld`)**; SNES interrupts do not clear `D`.
- **`I` (IRQ disable)**: `1` = maskable IRQs disabled, `0` = IRQs enabled.
- **`Z` (Zero)**: Set if result is zero.
- **`C` (Carry)**: Arithmetic carry/borrow (`borrow = NOT carry`).

### 1.3 Mode Switching (`rep` / `sep`)
- `rep #$xx` (Reset Processor Bits): Clears bits matching mask in `P` (turns flag to `0`).
  - `rep #$20` (`M=0`): Sets Accumulator to 16-bit.
  - `rep #$10` (`X=0`): Sets Index (`X`/`Y`) to 16-bit.
  - `rep #$30` (`M=0, X=0`): Sets Accumulator and Index to 16-bit.
- `sep #$xx` (Set Processor Bits): Sets bits matching mask in `P` (turns flag to `1`).
  - `sep #$20` (`M=1`): Sets Accumulator to 8-bit.
  - `sep #$10` (`X=1`): Sets Index (`X`/`Y`) to 8-bit.
  - `sep #$30` (`M=1, X=1`): Sets Accumulator and Index to 8-bit.

> [!IMPORTANT]
> **Register Width Invariant in `sndj`**:
> Standard state everywhere is: **`A` = 8-bit (`.ACCU 8`), `X`/`Y` = 16-bit (`.INDEX 16`), `DB = $80`, `D = $0000`**.
> Any subroutine that executes `rep #$20` **must** restore `sep #$20` before `rts`.

---

## 2. S-CPU Bus Timing, Memory Mapping & FastROM

### 2.1 Master Clock & Cycle Division
- **Master Clock**: 21.477272 MHz (NTSC) / 21.28137 MHz (PAL).
- Master clock divides into CPU clock cycles:
  - **Fast cycle**: 6 master clocks ≈ 3.58 MHz (FastROM banks `$80–$FF`).
  - **Slow cycle**: 8 master clocks ≈ 2.68 MHz (SlowROM banks `$00–$7D`, WRAM `$7E:0000–$7E:1FFF`, PPU/CPU registers).
  - **Extra Slow cycle**: 12 master clocks ≈ 1.79 MHz (Controller ports `$4016/$4017`, non-fast memory).
- **FastROM Enabling**: To enable 3.58 MHz execution in banks `$80–$FF`, bit 0 of `$420D` (`MEMSEL`) must be set to `1`.

### 2.2 LoROM Memory Mapping
In Mode 20 (LoROM), A15 is not connected to the cartridge ROM; each 64 KB bank maps 32 KB of ROM into `$8000–$FFFF`:
- **Banks `$00–$3F` and `$80–$BF`**:
  - `$0000–$1FFF`: 8 KB WRAM low mirror (accessible with fast/direct addressing).
  - `$2000–$20FF`: Reserved.
  - `$2100–$213F`: PPU registers (Slow cycle).
  - `$2140–$2143`: APU mailbox IO ports (Slow cycle).
  - `$2144–$217F`: Expansion IO.
  - `$2180–$2183`: WRAM access port (`WMDATA`, `WMADDL/M/H`).
  - `$4016–$4017`: Joypad Serial Ports (Extra Slow).
  - `$4200–$421F`: S-CPU control and math registers (Slow cycle).
  - `$4300–$437F`: DMA / HDMA channel registers (Slow cycle).
  - `$8000–$FFFF`: Cartridge ROM (32 KB per bank).
- **Banks `$70–$7D`**: Cartridge SRAM mapped at `$0000–$7FFF` (LoROM SRAM).
- **Banks `$7E–$7F`**: 128 KB WRAM (`$7E:0000–$7F:FFFF`).

---

## 3. Direct Page, Stack & Addressing Modes

### 3.1 65816 Addressing Modes & Cycle Counts
| Addressing Mode | Syntax | Example | Bytes | Base Cycles (8/16-bit A) |
|---|---|---|---|---|
| Immediate | `#const` | `lda #$10` | 2 (8-bit) / 3 (16-bit) | 2 / 3 |
| Direct Page | `dp` | `lda $65` | 2 | 3 / 4 (+1 if `DL != 0`) |
| Direct Page Indexed, X | `dp,x` | `lda $65,x` | 2 | 4 / 5 (+1 if `DL != 0`) |
| Absolute | `addr` | `lda.w $0400` | 3 | 4 / 5 |
| Absolute Indexed, X | `addr,x` | `lda.w $0400,x` | 3 | 4 / 5 (+1 if cross page in 8-bit mode) |
| Absolute Long | `long` | `lda.l $7E2000` | 4 | 5 / 6 |
| Absolute Long Indexed, X | `long,x` | `lda.l $7E2000,x` | 4 | 5 / 6 |
| Direct Indirect | `(dp)` | `lda ($40)` | 2 | 5 / 6 |
| Direct Indirect Long | `[dp]` | `lda [$40]` | 2 | 6 / 7 |
| Direct Indirect Long Indexed, Y | `[dp],y` | `lda [$40],y` | 2 | 6 / 7 |
| Stack Relative | `sr,s` | `lda 1,s` | 2 | 4 / 5 |
| Block Move | `srcbank, dstbank`| `mvn $7E, $7E` | 3 | 7 cycles per byte copied! |

### 3.2 Block Move Instructions (`mvn` / `mvp`)
Block move copies `C + 1` bytes from `[X] in srcbank` to `[Y] in dstbank`:
- `mvn srcbank, dstbank`: Moves forward (incrementing `X` and `Y`). Use when `dst <= src`.
- `mvp srcbank, dstbank`: Moves backward (decrementing `X` and `Y`). Use when `dst > src`.
- **Requirements**:
  - `A` / `C` = number of bytes minus 1 (16-bit mode).
  - `X` = 16-bit source address.
  - `Y` = 16-bit destination address.
  - Interrupts can occur between individual byte transfers; registers are updated after every byte.
- **Speed**: Exactly 7 S-CPU cycles (~2 µs) per byte transferred. Extremely fast for memory transfers between WRAM regions without setting up DMA channels.

---

## 4. Hardware Multiplication, Division & Math Registers

The 5A22 S-CPU includes dedicated unsigned multiplication and division hardware mapped to MMIO.

### 4.1 8-bit × 8-bit Unsigned Multiplier
- **Inputs**:
  - Write multiplicand A (8-bit) to `$4202` (`WRMPYA`).
  - Write multiplier B (8-bit) to `$4203` (`WRMPYB`).
- **Timing**: Result is ready **8 CPU cycles** after writing `$4203`.
- **Output**:
  - Read 16-bit product from `$4216` (`RDMPYL`) and `$4217` (`RDMPYH`).
  - In 16-bit mode (`rep #$20`), `lda $4216` reads the complete 16-bit result in 4 CPU cycles.

### 4.2 16-bit ÷ 8-bit Unsigned Divider
- **Inputs**:
  - Write dividend low byte to `$4204` (`WRDIVL`).
  - Write dividend high byte to `$4205` (`WRDIVH`).
  - Write divisor (8-bit) to `$4206` (`WRDIVB`).
- **Timing**: Division starts immediately upon writing `$4206` and completes in **16 CPU cycles**.
- **Outputs**:
  - 16-bit Quotient in `$4214` (`RDDIVL`) and `$4215` (`RDDIVH`).
  - 16-bit Remainder in `$4216` (`RDMPYL`) and `$4217` (`RDMPYH`).

> [!WARNING]
> **Math Unit Concurrency Trap (Invariant #9)**:
> Hardware math registers (`$4202–$4206` / `$4214–$4217`) are shared across the system. If an interrupt (NMI or IRQ) interrupts main code between writing `$4202/$4203` and reading `$4216`, or uses math registers itself, the calculation is silently corrupted.
> **Rule**: Never use hardware multiplication or division inside `NMI` or `IRQ` handlers without full context save/restore.

---

## 5. Interrupts, VBlank, H/V-Timer & Frame Timing

### 5.1 NTSC vs. PAL Timing Budget
| Metric | NTSC (60 Hz) | PAL (50 Hz) |
|---|---|---|
| Scanlines per frame | 262 (non-interlaced) | 312 (non-interlaced) |
| Dots per scanline | 341 dots = 1,364 master clocks | 341 dots = 1,364 master clocks |
| Master cycles / frame | 357,368 master cycles | 425,568 master cycles |
| Active display scanlines | Lines 1–224 (or 239) | Lines 1–224 (or 239) |
| VBlank duration | Scanlines 225–261 (37 scanlines) | Scanlines 225–311 (87 scanlines) |
| VBlank master cycles | ~50,468 master cycles | ~118,668 master cycles |
| S-CPU cycles / frame | ~45,000–59,000 CPU cycles | ~53,000–70,000 CPU cycles |
| Available VBlank DMA bytes | ~5.8 KB (NTSC) | ~14 KB (PAL) |

### 5.2 Auto-Joypad Read Timing
When bit 0 of `$4200` (`NMITIMEN`) is set, the S-CPU automatically polls controller ports starting at VBlank scanline 225:
- Takes 4,224 master clocks (~3 scanlines).
- Bit 0 of `$4212` (`HVBJOY`) is `1` while auto-joypad read is in progress.
- Reads land in `$4218–$421F` (`JOY1L/H` .. `JOY4L/H`).
- Reading controller registers `$4218–$421F` while `HVBJOY` bit 0 is set returns invalid bits.

### 5.3 Programmable H/V-Timer IRQs
Registers `$4207–$420A` allow triggering CPU IRQs at precise screen raster coordinates:
- `$4207` (`HTIMEL`) / `$4208` (`HTIMEH`): Target H-dot (`0..339`).
- `$4209` (`VTIMEL`) / `$420A` (`VTIMEH`): Target scanline (`0..261` NTSC / `0..311` PAL).
- Control in `$4200` (`NMITIMEN`):
  - Bits 5:4 = `00`: Timer IRQ disabled.
  - Bits 5:4 = `01`: H-Timer IRQ enabled (triggers on target H on every scanline).
  - Bits 5:4 = `10`: V-Timer IRQ enabled (triggers once per frame at target V, H=0).
  - Bits 5:4 = `11`: H/V-Timer IRQ enabled (triggers when both target V and target H match).
- Acknowledge IRQ by reading `$4211` (`TIMEUP`).

---

## 6. PPU Architecture, Tilemaps, Palettes & DMA

### 6.1 PPU Memory Access
VRAM and CGRAM can only be read or written by the S-CPU during **VBlank** (scanlines 225–261) or **Force-Blank** (`$2100` bit 7 = `1`).
Writing to `$2115–$2122` during active scanlines causes visual tearing and corrupts VRAM data.

### 6.2 BG Mode 1 Architecture
- **BG1**: 4bpp (16 colours/tile, 8 palettes = 128 colours).
- **BG2**: 4bpp (16 colours/tile, 8 palettes = 128 colours).
- **BG3**: 2bpp (4 colours/tile, 8 palettes = 32 colours; priority over BG1/BG2 enabled via `$2105` bit 3).
- **Tilemap Format (2 bytes per 8×8 tile)**:
  ```text
  Bit:   15   14   13   12   11   10    9    8    7    6    5    4    3    2    1    0
  Field:  V    H    P   [ Palette ] [       Tile Index (0..1023)                     ]
  ```
  - `V`: Vertical flip.
  - `H`: Horizontal flip.
  - `P`: Priority over lower layers.
  - `Palette`: 3 bits (`0..7`).

### 6.3 PPU Screen Modes Summary
| Mode | Layers | Color Depth | Palettes | Typical Use |
|---|---|---|---|---|
| **0** | 4 | 2bpp (all) | 8 palettes × 4 colors per layer | 4 independent scrolling layers |
| **1** | 3 | BG1/2: 4bpp, BG3: 2bpp | 8×16 (BG1/2), 8×4 (BG3) | **sndj current mode**; BG3 high-priority text overlay |
| **2** | 2 | 4bpp (both) | 8×16 | Column/row scrolling |
| **3** | 2 | BG1: 8bpp, BG2: 4bpp | 1×256 (BG1), 8×16 (BG2) | 256-color art with 16-color overlay |
| **4** | 2 | BG1: 8bpp, BG2: 2bpp | 1×256 (BG1), 8×4 (BG2) | 256-color art with 2bpp text overlay |
| **5** | 2 | BG1: 4bpp, BG2: 2bpp | 8×16, 8×4 | **512×224 high-res**: enables 64/80-column text UI |
| **6** | 1 | 4bpp | 8×16 | 512×224 high-res with column scroll |
| **7** | 1 | 8bpp | 1×256 | Affine rotation, scaling, perspective matrix |

### 6.4 DMA Transfer Engine
The S-CPU provides 8 independent DMA channels (`$4300–$437F`):
- **Transfer Modes (`$43x0` DMAPx)**:
  - `0`: 1 byte to 1 register (e.g. WRAM `$2180`).
  - `1`: 2 bytes to 2 registers (`$2118` then `$2119` for VRAM word write).
  - `2`: 2 bytes to 1 register alternate.
- **DMA Speed**: Fixed at 8 master clock cycles (≈ 372 ns) per byte transferred (~2.68 MB/sec at 21.477 MHz).
- **VBlank Transfer Limit**: During a 37-scanline NTSC VBlank, theoretical maximum DMA transfer is ~6.1 KB; practical safe budget is ~5.5 KB.

### 6.5 UI Modernization Avenues for sndj
- **BG1 / BG2 for Visual Backdrops & Scopes**: With Mode 1 BG3 priority active, BG1 and BG2 render behind the text UI. However, plain font glyphs render on transparent color 0 (`tools/makefont.py:10`), meaning any enabled BG1 will show through the background of every normal text cell (only inverted cursor/playhead cells are fully opaque). Any backdrop layer must be very low-contrast, confined via PPU windows (`$2123–$2129`) to margins without text, or paired with an opaque font background.
- **Dynamic Tile Oscilloscopes**: Updating 8–16 tiles in VRAM via a tiny 128–256 byte VBlank DMA provides 60 Hz waveform visualizers with 0 tilemap recomputation. **Data bottleneck caveat**: S-DSP audio registers (`VxOUTX`) and mixed audio are internal to the SPC700 and cannot be directly read by the S-CPU; streaming live oscilloscope waveform data requires extending the SPC700 mailbox telemetry driver first (`CLAUDE.md` §6.2 M-SCOPE).
- **Hardware Sprites (OBJ)**: OAM (544 bytes, 128 sprites, CGRAM colors 128–255) can drive smooth pixel-interpolated cursors, gliding playheads, or floating peak needles.
- **HDMA Raster Gradients**: HDMA channels can write to `COLDATA` (`$2132`) with color math enabled (`CGWSEL`/`CGADSUB`) or to `CGADD`/`CGDATA` per scanline automatically, creating CRT monitor glows with 0 CPU load.
- **Mode 5 (High-Res 512×224)**: High-resolution mode uses 16-dot wide characters (still 32 tilemap entries per row). Achieving 64 independent 8-px characters per row requires software blitting or character-pair tiles; high-res mode also experiences color blending on composite outputs.

---

## 7. SPC700 (S-SMP) Architecture & Instruction Set

The S-SMP sound CPU is an 8-bit Sony/Nintendo microprocessor running at 1.024 MHz (independent from S-CPU clock).

### 7.1 Architecture & Registers
- **Accumulator (`A`)**: 8-bit.
- **Index Registers (`X`, `Y`)**: 8-bit.
- **Word Register (`YA`)**: Combined 16-bit register (`Y` = high byte, `A` = low byte). Supports 16-bit addition (`addw YA, dp`), subtraction (`subw YA, dp`), comparison (`cmpw YA, dp`), multiplication (`mul YA`), and division (`div YA, X`).
- **Program Counter (`PC`)**: 16-bit (`$0000–$FFFF`).
- **Stack Pointer (`SP`)**: 8-bit. Always in Page 1 (`$0100–$01FF`).
- **Program Status Word (`PSW`)**:
  ```text
  Bit:    7   6   5   4   3   2   1   0
  Flag:   N   V   P   B   H   I   Z   C
  ```
  - `P` (Direct Page select): `0` = Page 0 (`$0000–$00FF`), `1` = Page 1 (`$0100–$01FF`). In `driver.asm`, `P = 0`.
  - `H`: Half-carry for BCD.

### 7.2 Key SPC700 MMIO Registers
| Address | Name | Description |
|---|---|---|
| `$F0` | `TEST` | Test register (keep `$00`). |
| `$F1` | `CONTROL` | Timer enable & IPL ROM control (bit 7: disable IPL ROM at `$FFC0–$FFFF`). |
| `$F2` | `DSPADDR` | S-DSP register address port (`0..127`). |
| `$F3` | `DSPDATA` | S-DSP register data read/write port. |
| `$F4–$F7` | `CPUIO0–3` | 4 bi-directional 8-bit mailbox ports linked to S-CPU `$2140–$2143`. |
| `$FA` | `T0TARGET` | Timer 0 scale (clocked at 8 kHz = 125 µs period). Range `1..256`. |
| `$FB` | `T1TARGET` | Timer 1 scale (clocked at 8 kHz = 125 µs period). |
| `$FC` | `T2TARGET` | Timer 2 scale (clocked at 64 kHz = 15.625 µs period). |
| `$FD` | `T0OUT` | Timer 0 4-bit output counter (reading clears counter). |
| `$FE` | `T1OUT` | Timer 1 4-bit output counter. |
| `$FF` | `T2OUT` | Timer 2 4-bit output counter. |

---

## 8. S-DSP Sound Architecture & Voice Model

The S-DSP generates 8 stereo voices at a fixed sample rate of **32,000 Hz**.

### 8.1 Voice Register Map (Registers `$x0–$x9` for Voice `x = 0..7`)
| Register | Name | Description |
|---|---|---|
| `$x0` | `VxVOLL` | Left Volume (signed 8-bit: `-$80` to `+$7F`). |
| `$x1` | `VxVOLR` | Right Volume (signed 8-bit: `-$80` to `+$7F`). |
| `$x2` | `VxPITCHL` | Pitch multiplier low 8 bits. |
| `$x3` | `VxPITCHH` | Pitch multiplier high 6 bits (bits 5:0). Rate = `pitch * 32000 / $1000`. |
| `$x4` | `VxSRCN` | Sample Directory index (`0..63`). |
| `$x5` | `VxADSR1` | Bit 7: `1`=ADSR enable, `0`=GAIN enable. Bits 6:4: Decay. Bits 3:0: Attack. |
| `$x6` | `VxADSR2` | Bits 7:5: Sustain Level (`0..7`). Bits 4:0: Sustain Rate. |
| `$x7` | `VxGAIN` | GAIN mode and value (Direct, Linear/Exponential decrease, Linear/Bent increase). |
| `$x8` | `VxENVX` | Current voice envelope height (`0..127`, read-only). |
| `$x9` | `VxOUTX` | Current voice output sample (`-$80` to `+$7F`, read-only). |

### 8.2 Global DSP Registers
| Register | Name | Description |
|---|---|---|
| `$0C` | `MVOLL` | Master volume Left (signed 8-bit). |
| `$1C` | `MVOLR` | Master volume Right (signed 8-bit). |
| `$2C` | `EVOLL` | Echo volume Left (signed 8-bit). |
| `$3C` | `EVOLR` | Echo volume Right (signed 8-bit). |
| `$4C` | `KON` | Key On voice mask (`bit x = 1` triggers voice `x`). Automatically cleared after latching. |
| `$5C` | `KOF` | Key Off voice mask (`bit x = 1` starts release phase for voice `x`). |
| `$6C` | `FLG` | Bit 7: Soft reset, Bit 6: Mute, Bit 5: Echo write disable (`ECEN`), Bits 4:0: Noise clock. |
| `$7C` | `ENDX` | Voice BRR loop/end flag (`bit x = 1` when voice reached end block). Any write clears it. |
| `$0D` | `EFB` | Echo feedback volume (signed 8-bit). |
| `$2D` | `PMON` | Pitch Modulation enable (bit `x` enables modulation of voice `x` by voice `x-1`). |
| `$3D` | `NON` | Noise generator enable (bit `x = 1` replaces sample with white noise LFSR). |
| `$4D` | `EON` | Echo enable (bit `x = 1` routes voice output into echo buffer). |
| `$5D` | `DIR` | Sample directory page base address in ARAM (`DIR * $100`). |
| `$6D` | `ESA` | Echo buffer base address in ARAM (`ESA * $100`). |
| `$7D` | `EDL` | Echo delay line length (`0..15`, delay = `EDL * 16 ms`, buffer size = `EDL * 2048 bytes`). |
| `$0F..$7F` (step 16) | `FIR0..7` | 8-tap finite impulse response filter coefficients (signed 8-bit). |

### 8.3 4-Tap Gaussian Interpolation
When pitch is not native (`$1000 = 4096`), the DSP interpolates between samples using a hardware 4-tap Gaussian FIR filter with a 512-entry fixed coefficient table:
```text
Sample = [ (Gauss[255-x]*S0) + (Gauss[511-x]*S1) + (Gauss[256+x]*S2) + (Gauss[x]*S3) ] >> 11
```
Because the Gaussian filter has an intrinsic low-pass rolloff, high frequencies are attenuated compared to linear interpolation. Bright samples often need treble pre-emphasis before BRR encoding.

---

## 9. Bit Rate Reduction (BRR) Audio Format

BRR compresses 16 linear 16-bit PCM samples into 9 bytes (a 9-byte BRR block), achieving a 32:9 compression ratio.

### 9.1 Block Layout
```text
Byte 0:  [ Shift (bits 7:4) ] [ Filter (bits 3:2) ] [ Loop (bit 1) ] [ End (bit 0) ]
Bytes 1–8: 16 signed 4-bit nibbles (sample data, high nibble first)
```
- **Shift (Range)**: Exponent `0..12` applied to nibbles.
- **Filter**: Prediction filter `0..3`:
  - Filter 0: $p_0 = 0$
  - Filter 1: $p_0 = s_{t-1} + (-s_{t-1} \gg 4)$
  - Filter 2: $p_0 = 2 s_{t-1} + (-3 s_{t-1} \gg 5) - s_{t-2} + (s_{t-2} \gg 4)$
  - Filter 3: $p_0 = 2 s_{t-1} + (-13 s_{t-1} \gg 6) - s_{t-2} + (3 s_{t-2} \gg 4)$
- **End bit (Bit 0)**: `1` marks the final block of the sample.
- **Loop bit (Bit 1)**: `1` causes playback to jump to the loop address specified in the sample directory entry when the End block completes; `0` silences the voice.

### 9.2 Critical BRR Encoder Rules
1. **The First Block Must Use Filter 0**: At note trigger, history samples $s_{t-1}$ and $s_{t-2}$ are undefined/cleared. The first block must have Filter = 0.
2. **Loop Point Alignment**: In looped samples, the loop target block must also use Filter 0 unless the history samples match the ending block's tail.
3. **Loop Point Multiple of 16**: Loop points must be an exact multiple of 16 PCM samples (matching a 9-byte block boundary).

---

## 10. Echo Buffer, FIR Filter & S-DSP Internal Memory

### 10.1 Echo Buffer Sizing & Placement
- Base address: `ESA * $0100`.
- Buffer length: If `EDL == 0`, buffer takes 4 bytes. If `EDL > 0`, buffer takes `EDL * 2,048` bytes:
  - `EDL = 1`: 2,048 B (16 ms)
  - `EDL = 2`: 4,096 B (32 ms)
  - `EDL = 4`: 8,192 B (64 ms)
  - `EDL = 8`: 16,384 B (128 ms)
  - `EDL = 15`: 30,720 B (240 ms)
- The echo buffer must be positioned at the top of ARAM (`$FFFF` down) to maximize contiguous sample heap space below it.

### 10.2 S-DSP Echo Buffer Shrink Hardware Bug (Silicon Erratum)
- The DSP internal echo ring pointer runs continuously in hardware even when `ECEN` (`FLG` bit 5) is disabled!
- **Bug**: If `EDL` is decreased (e.g. `EDL=4` → `EDL=1`), the internal write pointer may still be pointing to the old range (e.g. `+$1800` into the old buffer). When `ECEN` is re-enabled, the DSP will continue writing from that out-of-range pointer, wrapping around ARAM and **corrupting low ARAM (driver code, zero page, and sample directory)**!
- **Mandatory Defense (Invariant #4)**:
  1. Set `FLG = $60` (mute echo writes).
  2. Wait `cur_edl + 1` timer periods (flush old writes).
  3. Write new `ESA` and new `EDL`.
  4. Zero the new echo buffer memory.
  5. **If `new_edl < cur_edl`, wait 17 timer ticks (~270 ms)** for the internal offset pointer to cycle past `$7FFF` and safely wrap into the new boundary before re-enabling `FLG`.

---

## 11. S-CPU ⇄ SPC700 Mailbox Protocol & Silicon Errata

Communication occurs through four 8-bit bidirectional memory-mapped latches:
- S-CPU side: `$2140–$2143` (`APUIO0–3`)
- SPC700 side: `$F4–$F7` (`CPUIO0–3`)

### 11.1 Port Read Glitch Erratum (Invariant #13)
- **Silicon Defect**: When the S-CPU writes to an APU port while the SPC700 is simultaneously reading that port, the internal bus capacitors capture a metastable intermediate voltage, returning **mixed bits** (neither old nor new byte).
- **Emulators do not model this**: Code that runs perfectly in Mesen 2 or bsnes can glitch or hang on an FXPak Pro / real console.
- **Defenses**:
  1. **Double-Read Validation**:
     ```assembly
     @wait:
         mov a, rPORT0
         cmp a, rPORT0
         bne @wait
     ```
  2. **Strict Successor Check**: In streaming uploads, reject any byte that is not the exact expected successor (`bulk_ctr = bulk_ctr + 1`).
  3. **Non-Zero Handshake Markers**: Never use `$00` as a data handshake acknowledge byte; reserve `$00` exclusively for end-of-stream or resync.

### 11.2 Mailbox Command Flow
```text
S-CPU ($2140..$2143)                        SPC700 ($F4..$F7)
--------------------                        -----------------
1. Writes payload to APUIO1..3
2. Writes sequence/command to APUIO0  ──►   3. Double-reads CPUIO0 until stable
                                            4. Executes DSP write or command
5. Spins on APUIO0 waiting for echo   ◄──   6. Echoes command/sequence to CPUIO0
7. Advances to next write
```

---

## 12. Optimization Patterns, Traps & Anti-Patterns

### 12.1 S-CPU Optimization Patterns
1. **Dirty-Gating UI Redraws**:
   - Redrawing full screens (e.g. 16 rows × 8 tracks) takes ~40,000–50,000 CPU cycles.
   - Guard redraws with a dirty flag (`pad_event != 0`, cursor moved, or playhead row advanced). Idle frames consume **0 cycles**.
2. **`wai` Overrun Guard**:
   - Always test `frame_flag` *before* `wai`:
     ```assembly
     @wait:
         lda frame_flag
         bne @run
         wai
         bra @wait
     @run:
         stz frame_flag
     ```
   - Prevents a 1% frame overrun from sleeping an entire extra frame at 30 fps.
3. **Single-Calculation Hex/Tile Destination**:
   - `text_hex8` prints two adjacent glyphs. Compute the base destination once (`(y * 64) + (x * 2)`), store the high digit at `,x` and the low digit at `,x+2`. Saves 18 instructions (~44 cycles) per byte rendered.
4. **Hardware Multiplier in Hot FX Paths**:
   - Replace software addition loops (`clc / adc / dec / bne`) with `WRMPYA` / `WRMPYB` (`$4202/$4203`). Guarantees constant 8-cycle multiplication.
5. **DSP Register Shadow Cache**:
   - S-CPU mailbox handshakes take 35–180 cycles per write.
   - Shadow the 128 DSP registers in WRAM. If the new value equals the shadowed value, skip the mailbox write entirely.

### 12.2 Common Traps & Anti-Patterns
- **The 16-bit Index Pull Flag Trap**:
  - `plx` and `ply` update the `N` and `Z` flags based on the **16-bit pulled value**, clobbering any flags set by `A` before the pull.
  - *Fix*: Re-evaluate `cmp #$00` or `tax` after the stack pull before branching.
- **Back-to-Back KOF and KON (Invariant #3)**:
  - S-DSP samples `KON` and `KOF` every other sample (32 kHz). Writing `KOF` immediately followed by `KON` in the same tick can cause the hardware voice to drop or fail to trigger.
  - *Rule*: Never set both `koff_mask` and `kon_mask` for the same voice in the same tick. `KON` alone automatically re-triggers the voice from block 0.
- **Accidental Math in Markdown Text**:
  - In LLM documentation and artifacts, two unescaped dollar signs (`$0400 ... $0BFF`) trigger KaTeX math rendering, turning addresses into garbled italicized formulas.
  - *Fix*: Always escape hex dollar signs (`\$0400`) or wrap addresses in backticks (`` `$0400` ``).
