#!/usr/bin/env python3
"""makehrfont.py — hi-res (Mode 5) text assets from the classic font.

Mode 5 draws every tilemap entry 16 hi-res pixels wide, as tile N on the
left and tile N+1 on the right. A 64-column text screen therefore uses two
layers, each holding every other column:

    BG2 (2bpp) = even columns: entry tile 2g+1 -> (glyph g, blank)
    BG1 (4bpp) = odd columns:  entry tile 2g   -> (blank, glyph g)

so both layers share one tile order: tile 0 blank, then glyph g at 2g+1
followed by a blank at 2g+2. No glyph pairs are composed at run time.

Outputs (into the build dir):
  hrfont2.bin  385 2bpp tiles (6160 bytes)
  hrfont4.bin  385 4bpp tiles (12320 bytes: the 2bpp rows + zero planes 2/3)
  hrpal.bin    128 CGRAM words for the hi-res colour palettes
"""
import os
import sys

# logical palettes (tilemap palette field), see snes.inc ATTR_*
COLOURS = [
    0xD7DCE5,  # 0 TEXT
    0xFFC45C,  # 1 ACCENT  (inverted glyphs: amber block, dark letter)
    0xFFFFFF,  # 2 HILITE
    0x8B95A5,  # 3 DIM
    0x72E08A,  # 4 PLAY    (inverted)
    0x72E08A,  # 5 GREEN
    0x6FD3FF,  # 6 CYAN
    0xFF7AB2,  # 7 PINK
]
BG = 0x0C1016

# BG1 (4bpp) palette q covers CGRAM 16q..; BG2 (2bpp) palette p covers 4p..
# BG1 palette 1 (CGRAM 17-19) overlaps BG2 palette 4 (CGRAM 16-19), so the
# odd-column layer swaps palettes 1 and 4 (hires.asm hr_put does the same).
BG1_PAL = {0: 0, 1: 4, 2: 2, 3: 3, 4: 1, 5: 5, 6: 6, 7: 7}


def bgr555(rgb):
    r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def main(build):
    font = open(os.path.join(build, 'font.bin'), 'rb').read()
    n = len(font) // 16
    blank2 = bytes(16)
    t2 = [blank2]
    for g in range(n):
        t2.append(font[g * 16:(g + 1) * 16])
        t2.append(blank2)
    t2 = t2[:2 * n + 1]
    open(os.path.join(build, 'hrfont2.bin'), 'wb').write(b''.join(t2))
    open(os.path.join(build, 'hrfont4.bin'), 'wb').write(
        b''.join(t + bytes(16) for t in t2))

    # font ink: normal glyphs draw colour 3 on 0 (transparent); inverted
    # glyphs draw colour 1 (the background) on a colour-3 field
    def pal(c):
        return [bgr555(BG), bgr555(BG), bgr555(c), bgr555(c)]
    cg = [bgr555(BG)] * 128
    for p, c in enumerate(COLOURS):
        cg[4 * p + 1:4 * p + 4] = pal(c)[1:]
    for p, q in BG1_PAL.items():
        want = pal(COLOURS[p])[1:]
        # BG1 palette 1 is BG2 palette 4's slots: identical by design
        assert q != 1 or cg[17:20] == want
        cg[16 * q + 1:16 * q + 4] = want
    cg[0] = bgr555(BG)
    open(os.path.join(build, 'hrpal.bin'), 'wb').write(
        b''.join(w.to_bytes(2, 'little') for w in cg))
    print(f"makehrfont: {len(t2)} tiles x2 layers, 128-colour palette -> {build}")


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build')
