---
title: Super Nintendo Graphics, PPU Architecture & UI Modernization Guide
category: architecture
updated: 2026-11-01
sources:
  - src/snes.inc
  - src/init.asm
  - src/nmi.asm
  - src/text.asm
  - src/palette.asm
  - PALETTE.md
  - HARDWARE.md
---

# Super Nintendo Graphics, PPU Architecture & UI Modernization Guide

This document is the reference for understanding the Super Nintendo (S-PPU) graphics hardware and designing future UI enhancements for `sndj` (oscilloscopes, peak meters, custom backgrounds, multi-layer views, windows, sprites, and smooth scrolling).

---

## 1. Current `sndj` Video Pipeline Architecture

`sndj` runs in **BG Mode 1** with **BG3 priority enabled** (`BGMODE = $09`), allocating all visual presentation to a single 2bpp text layer.

### 1.1 VRAM Allocation Map
VRAM is 64 KB (organized as 32K 16-bit words):

| VRAM Word Address | Byte Span | S-PPU Assignment | In `sndj` |
|---|---|---|---|
| `$0000–$03FF` | `$0000–$07FF` (2 KB) | `BG3SC` (BG3 Tilemap Base) | `VRAM_BG3_MAP`: 32×32 character tilemap. DMA'd every NMI from `SHADOW_BG3` in WRAM (`$7E:0400–$7E:0BFF`). |
| `$0400–$0FFF` | `$0800–$1FFF` (6 KB) | Free / `BG1SC` (`$0400`) | Allocated symbol `VRAM_BG1_MAP` (`$0400`). Currently unused. |
| `$1000–$1FFF` | `$2000–$3FFF` (8 KB) | `BG34NBA` (BG3 Character Base) | `VRAM_BG3_CHR`: 2bpp font glyphs + logo data (`192 tiles × 8 words = $0600 words`). |
| `$2000–$7FFF` | `$4000–$FFFF` (48 KB) | `BG12NBA` (BG1/2 Character Base) | `VRAM_BG1_CHR` (`$2000`): Reserved for 4bpp dynamic graphics. Currently unused. |

### 1.2 PPU Layer Configuration (`src/init.asm`)
```assembly
    lda #$09
    sta BGMODE         ; Mode 1 (BG1 4bpp, BG2 4bpp, BG3 2bpp), Bit 3=1: BG3 Priority over BG1/BG2
    lda #(VRAM_BG3_MAP >> 8)
    sta BG3SC          ; Base = $0000, Size = 32x32 tiles (no mirroring)
    lda #(VRAM_BG3_CHR >> 12)
    sta BG34NBA        ; BG3 CHR Base = $1000 ($2000 in bytes)
    lda #$04
    sta TM             ; Main screen enable: BG3 ONLY enabled (BG1, BG2, BG4, OBJ disabled)
```

### 1.3 Palette Architecture (`PALETTE.md`)
- CGRAM holds 256 15-bit BGR colors (`0BBBBBGGGGGRRRRR`).
- `sndj` strictly implements a **two-color scheme** (background color 0, text color 1).
- Inverted glyphs (offset `+96` in the 2bpp font) render cursors, playheads, and row selections using the inverted tile indices rather than extra palette entries.
- Palette colors:
  - CGRAM `$00..$03`: Palette 0 (default text: color 0 = background, color 1 = text).
  - CGRAM `$10..$13`: Color 16–19 (`ATTR_PLAY` palette).

---

## 2. PPU Background Modes Reference

The SNES PPU supports 8 screen modes (`BGMODE $2105`, bits 2:0):

| Mode | Layers | Color Depths (bpp) | Palette Colors | Capabilities / Trade-offs |
|---|---|---|---|---|
| **Mode 0** | 4 layers | BG1–4: 2bpp (4 colors each) | 32 colors / layer (4 colors × 8 palettes) | 4 independent scrolling layers. Good for dense layered text/HUDs. |
| **Mode 1** | 3 layers | BG1: 4bpp (16 cols)<br>BG2: 4bpp (16 cols)<br>BG3: 2bpp (4 cols) | BG1/2: 128 cols (16×8)<br>BG3: 32 cols (4×8) | **`sndj`'s current mode.** BG3 has optional high priority over all layers. BG1/2 are available for 16-color graphics. |
| **Mode 2** | 2 layers | BG1: 4bpp (16 cols)<br>BG2: 4bpp (16 cols) | 128 colors each | Column-by-column vertical/horizontal offset per tile (Column Scroll). |
| **Mode 3** | 2 layers | BG1: 8bpp (256 cols)<br>BG2: 4bpp (16 cols) | BG1: 256 colors<br>BG2: 128 colors | Full 256-color backdrop/artwork on BG1; 4bpp overlay on BG2. |
| **Mode 4** | 2 layers | BG1: 8bpp (256 cols)<br>BG2: 2bpp (4 cols) | BG1: 256 colors<br>BG2: 32 colors | 256-color background with 2bpp text overlay layer. |
| **Mode 5** | 2 layers | BG1: 4bpp (16 cols)<br>BG2: 2bpp (4 cols) | 128 / 32 colors | **High-resolution 512×224 / 512×448 mode.** 16-dot wide characters. True 64-column or 80-column text possible. |
| **Mode 6** | 1 layer | BG1: 4bpp (16 cols) | 128 colors | High-resolution 512×224 with Column Scroll. |
| **Mode 7** | 1 layer | BG1: 8bpp (256 cols) | 256 colors | Affine transformations (rotation, scaling, perspective projection). |

---

## 3. UI Modernization Opportunities for `sndj`

Because `sndj` currently leaves **BG1, BG2, Sprites (OBJ), HDMA, and Color Math completely unused**, additional graphical features can be layered into the UI. However, because plain font glyphs render on transparent color 0 (`tools/makefont.py:10`), any active background layer will show through normal text cells unless window-masked (`$2123–$2129`), restricted to empty borders/margins, or rendered with an opaque font background.

### 3.1 Enabling BG1 / BG2 for Visual Backdrops and Waveform Scopes
- In Mode 1, `BG3` priority bit (`$2105` bit 3 = `1`) guarantees that all text in `SHADOW_BG3` with Priority Bit 13 (`ATTR_TEXT`, `ATTR_HILITE`, `ATTR_ACCENT`) renders **in front of BG1 and BG2**.
- Enabling BG1 (`lda #$05 / sta TM`):
  - BG1 is 4bpp (16 colors per tile).
  - Can display animated audio waveforms, spectrum visualizers, or custom tracker skins (caution: plain font glyphs have transparent backgrounds, so BG1 shows through text cells unless masked with PPU windows or restricted to non-text borders).
  - Can be scrolled independently in hardware using `BG1HOFS` (`$210D`) and `BG1VOFS` (`$210E`) with **zero CPU redraw overhead**.
  > [!WARNING]
  > **Transparent Background Caveat**: Plain font glyphs render on transparent color 0 (`tools/makefont.py:10`). Therefore, any enabled BG1 backdrop shows through the background of normal text cells (only inverted cells are fully opaque). To prevent unreadable UI contrast, BG1 artwork must be very low-contrast, confined via PPU windows (`$2123–$2129`) to margins without text, or paired with an opaque font background.

### 3.2 Real-Time Oscilloscope / Waveform Rendering via Dynamic Tiles
- **VRAM Budget**: A dynamic 4-tile or 8-tile oscilloscope band requires only 8–16 2bpp tiles (128–256 bytes) or 4bpp tiles (256–512 bytes).
- **Execution Strategy**:
  1. Allocate 8 consecutive dynamic tile IDs in VRAM.
  2. In `main_loop`, unpack waveform samples received via SPC mailbox telemetry (or S-CPU software synthesis) and render dot/column vectors into a small WRAM dynamic tile staging buffer.
  3. During NMI, execute a tiny 128-byte DMA to the dynamic tile VRAM address.
  4. The oscilloscope immediately animates smoothly at 60 Hz without redrawing the tilemap!
  > [!IMPORTANT]
  > **Data Source Prerequisite**: S-DSP registers (`VxOUTX`) and internal audio buffers are internal to the S-DSP/SPC700 and cannot be directly accessed by the S-CPU. Live waveform visualization requires extending the SPC700 driver telemetry over the mailbox ports first (`CLAUDE.md` §6.2 M-SCOPE).

### 3.3 Hardware Sprites (OBJ) for Floating Cursors & Meters
- **OAM (Object Attribute Memory)**: 544 bytes (`128 sprites × 4 bytes` + 32 bytes high table).
- Sprites can be 8×8, 16×16, 32×32, or 64×64 pixels with 4bpp graphics using CGRAM colors 128–255 (OBJ palettes 0–7, each with 16 colors where color 0 is transparent; distinct from BG palettes 0–7 which reside at colors 0–127).
- **UI Applications**:
  - Smooth pixel-positioned edit cursor (smoothly sliding between cells instead of jumping 8 pixels).
  - Floating VU meter needles or clip indicators.
  - Playhead indicators that glide across track columns.

### 3.4 HDMA (Horizontal DMA) Effects
HDMA transfers table-driven register values to PPU registers on every scanline automatically without S-CPU intervention:
- **Gradient Backgrounds**: HDMA writes to `COLDATA` (`$2132`) or `CGDATA` (`$2122`) to produce CRT monitor glows, scanline shading, or smooth vertical color gradients with **0 CPU cycles**.
- **Wavy / Ripple Screen Effects**: HDMA writes to `BG1HOFS` per scanline to create raster wobble on splash or game screens.
- **Brightness Shading (Window Dimming)**: HDMA writes to `INIDISP` (`$2100`) to darken inactive sections of the screen (e.g. dimming the background when an overlay menu pops up).

### 3.5 Hardware Window Masking & Transparency (Color Math)
- The SNES PPU contains hardware windowing units:
  - `W12SEL` (`$2123`) / `W34SEL` (`$2124`): Window mask enable for BG layers.
  - `WH0`–`WH3` (`$2126–$2129`): Left and right horizontal boundaries for Window 1 and Window 2.
- **Color Math (`CGADSUB $2131`)**:
  - Hardware addition or subtraction between Main Screen and Sub Screen layers.
  - Enables true translucent popup dialog boxes (dimming or tinting the tracker beneath menus).

---

## 4. Mode 5 High-Resolution Mode (80-Column / Fine Tracker UI)

If a future major overhaul of `sndj` requires more screen columns (e.g. 8 simultaneous 4-column tracks like Protracker, showing Note, Instrument, Volume, and Command side-by-side):

- **Resolution**: 512×224 (interlaced: 512×448).
- **Tile Format**: 16-dot wide characters (two 8-dot slices).
- **Display Capacity**:
  - Standard 8×8 font in Mode 1 yields 32 columns × 28 rows.
  - Mode 5 yields **64 columns × 28 rows** (or 80 columns with custom 6-pixel fonts).
- **VRAM Bandwidth**:
  - In Mode 5, characters are 16 dots wide, so a 512-dot line still uses 32 tilemap entries per row (same 2 KB map). Achieving 64 independent 8-pixel characters per row requires pre-composed character pairs or software tile blitting.
  - High-resolution rendering requires fast-path font blitting.

---

## 5. Summary Guidelines for UI Updates in `sndj`

1. **Protect VBlank**: All VRAM, CGRAM, and OAM updates must complete within VBlank (~37 scanlines in NTSC, ~5.5 KB DMA max).
2. **Keep Direct Page at `$0000`**: Do not relocate `D` to PPU registers; `sndj` relies on Direct Page scratch variables.
3. **Respect Bank 0 Space Limits**: UI rendering logic should remain compact, spilling large lookup tables or font assets into Bank 6 (`$86:8000`).
4. **Preserve Two-Color Accessibility**: If adding color layers (BG1/BG2), maintain strong luminance contrast so the tracker remains completely usable over RF and composite connections.
