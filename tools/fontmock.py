#!/usr/bin/env python3
"""fontmock.py — Font design, binary builder, and visual comparison sheet
for Mode 1 256px EarthBound-style rendering (Options C, D, and Prose).

Generates:
  build/font5.bin               - 1bpp binary font for 5-px cells (4x7 in 5x8 box)
  build/font6.bin               - 1bpp binary font for 6-px cells (5x7 in 6x8 box)
  build/fontmock_comparison.png - Complete visual comparison sheet (Sharp, Blended, 4:3 TV)
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

# -----------------------------------------------------------------------------
# Color Palette (Mode 1 16-color UI palette)
# -----------------------------------------------------------------------------
COLOR_BG       = (12, 16, 22)     # #0C1016 Dark slate background
COLOR_TEXT     = (215, 220, 229)  # #D7DCE5 Normal text / values
COLOR_ACCENT   = (255, 196, 92)   # #FFC45C Cursor / Amber
COLOR_HILITE   = (255, 255, 255)  # #FFFFFF Bright white headings
COLOR_DIM      = (139, 149, 165)  # #8B95A5 Dim / rulers / labels
COLOR_GREEN    = (114, 224, 138)  # #72E08A Playing / Meters
COLOR_CYAN     = (111, 211, 255)  # #6FD3FF Track / Note IDs
COLOR_PINK     = (255, 122, 178)  # #FF7AB2 Commands
COLOR_BAND     = (20, 27, 36)     # #141B24 Lighter beat band
COLOR_CURSOR   = (255, 196, 92)   # Cursor inverted block

# -----------------------------------------------------------------------------
# Glyph Definitions (8 rows, each row defined by '#' for pixel, '.' for empty)
# -----------------------------------------------------------------------------
# Font 5: 4 pixels wide (cols 0..3), col 4 is blank spacing.
# Font 6: 5 pixels wide (cols 0..4), col 5 is blank spacing.

GLYPHS_5 = {}
GLYPHS_6 = {}

def def_glyph(char, rows5, rows6):
    assert len(rows5) == 8, f"rows5 len {len(rows5)} for {char}"
    assert len(rows6) == 8, f"rows6 len {len(rows6)} for {char}"
    for r in rows5: assert len(r) == 4, f"r5 len {len(r)} in {char}"
    for r in rows6: assert len(r) == 5, f"r6 len {len(r)} in {char}"
    GLYPHS_5[char] = rows5
    GLYPHS_6[char] = rows6

# Space
def_glyph(' ',
    ["...."]*8,
    ["....."]*8
)

# Digits 0-9
def_glyph('0',
    [".##.", "#..#", "#.##", "##.#", "#..#", "#..#", ".##.", "...."],
    [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###.", "....."]
)
def_glyph('1',
    [".##.", "..#.", "..#.", "..#.", "..#.", "..#.", ".###", "...."],
    ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###.", "....."]
)
def_glyph('2',
    ["###.", "..#.", "..#.", ".##.", "#...", "#...", "####", "...."],
    [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####", "....."]
)
def_glyph('3',
    ["###.", "..#.", "..#.", ".##.", "..#.", "..#.", "###.", "...."],
    ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###.", "....."]
)
def_glyph('4',
    ["#.#.", "#.#.", "#.#.", "####", "..#.", "..#.", "..#.", "...."],
    ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#.", "....."]
)
def_glyph('5',
    ["####", "#...", "###.", "..#.", "..#.", "#..#", "###.", "...."],
    ["#####", "#....", "####.", "....#", "....#", "#...#", ".###.", "....."]
)
def_glyph('6',
    [".##.", "#...", "###.", "#..#", "#..#", "#..#", ".##.", "...."],
    ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###.", "....."]
)
def_glyph('7',
    ["####", "..#.", "..#.", ".#..", ".#..", ".#..", ".#..", "...."],
    ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#...", "....."]
)
def_glyph('8',
    [".##.", "#..#", "#..#", ".##.", "#..#", "#..#", ".##.", "...."],
    [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###.", "....."]
)
def_glyph('9',
    [".##.", "#..#", "#..#", ".###", "..#.", "..#.", ".##.", "...."],
    [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##..", "....."]
)

# Uppercase A-Z
def_glyph('A',
    [".##.", "#..#", "#..#", "####", "#..#", "#..#", "#..#", "...."],
    [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#", "....."]
)
def_glyph('B',
    ["###.", "#..#", "#..#", "###.", "#..#", "#..#", "###.", "...."],
    ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####.", "....."]
)
def_glyph('C',
    [".###", "#...", "#...", "#...", "#...", "#...", ".###", "...."],
    [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.", "....."]
)
def_glyph('D',
    ["###.", "#..#", "#..#", "#..#", "#..#", "#..#", "###.", "...."],
    ["###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###..", "....."]
)
def_glyph('E',
    ["####", "#...", "#...", "###.", "#...", "#...", "####", "...."],
    ["#####", "#....", "#....", "####.", "#....", "#....", "#####", "....."]
)
def_glyph('F',
    ["####", "#...", "#...", "###.", "#...", "#...", "#...", "...."],
    ["#####", "#....", "#....", "####.", "#....", "#....", "#....", "....."]
)
def_glyph('G',
    [".###", "#...", "#...", "#.##", "#..#", "#..#", ".###", "...."],
    [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####", "....."]
)
def_glyph('H',
    ["#..#", "#..#", "#..#", "####", "#..#", "#..#", "#..#", "...."],
    ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#", "....."]
)
def_glyph('I',
    ["###.", ".#..", ".#..", ".#..", ".#..", ".#..", "###.", "...."],
    [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.", "....."]
)
def_glyph('J',
    ["..##", "...#", "...#", "...#", "...#", "#..#", ".##.", "...."],
    ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##..", "....."]
)
def_glyph('K',
    ["#..#", "#.#.", "##..", "##..", "#.#.", "#..#", "#..#", "...."],
    ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#", "....."]
)
def_glyph('L',
    ["#...", "#...", "#...", "#...", "#...", "#...", "####", "...."],
    ["#....", "#....", "#....", "#....", "#....", "#....", "#####", "....."]
)
def_glyph('M',
    ["#..#", "####", "#.##", "#..#", "#..#", "#..#", "#..#", "...."],
    ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#", "....."]
)
def_glyph('N',
    ["#..#", "##.#", "##.#", "#.##", "#.##", "#..#", "#..#", "...."],
    ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "....."]
)
def_glyph('O',
    [".##.", "#..#", "#..#", "#..#", "#..#", "#..#", ".##.", "...."],
    [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.", "....."]
)
def_glyph('P',
    ["###.", "#..#", "#..#", "###.", "#...", "#...", "#...", "...."],
    ["####.", "#...#", "#...#", "####.", "#....", "#....", "#....", "....."]
)
def_glyph('Q',
    [".##.", "#..#", "#..#", "#..#", "#.#.", "#..#", ".##.", "...."],
    [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#", "....."]
)
def_glyph('R',
    ["###.", "#..#", "#..#", "###.", "#.#.", "#..#", "#..#", "...."],
    ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#", "....."]
)
def_glyph('S',
    [".###", "#...", "#...", ".##.", "...#", "...#", "###.", "...."],
    [".####", "#....", "#....", ".###.", "....#", "....#", "####.", "....."]
)
def_glyph('T',
    ["####", ".#..", ".#..", ".#..", ".#..", ".#..", ".#..", "...."],
    ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "....."]
)
def_glyph('U',
    ["#..#", "#..#", "#..#", "#..#", "#..#", "#..#", ".##.", "...."],
    ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.", "....."]
)
def_glyph('V',
    ["#..#", "#..#", "#..#", "#..#", "#..#", ".##.", ".##.", "...."],
    ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#..", "....."]
)
def_glyph('W',
    ["#..#", "#..#", "#..#", "#..#", "####", "####", "#..#", "...."],
    ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#", "....."]
)
def_glyph('X',
    ["#..#", "#..#", ".##.", ".##.", ".##.", "#..#", "#..#", "...."],
    ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#", "....."]
)
def_glyph('Y',
    ["#..#", "#..#", "#..#", ".##.", "..#.", "..#.", "..#.", "...."],
    ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#..", "....."]
)
def_glyph('Z',
    ["####", "...#", "..#.", ".#..", ".#..", "#...", "####", "...."],
    ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####", "....."]
)

# Lowercase a-z (with descenders on row 7 for g, j, p, q, y)
def_glyph('a',
    ["....", "....", ".##.", "...#", ".###", "#..#", ".###", "...."],
    [".....", ".....", ".###.", "....#", ".####", "#...#", ".####", "....."]
)
def_glyph('b',
    ["#...", "#...", "###.", "#..#", "#..#", "#..#", "###.", "...."],
    ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####.", "....."]
)
def_glyph('c',
    ["....", "....", ".###", "#...", "#...", "#...", ".###", "...."],
    [".....", ".....", ".####", "#....", "#....", "#....", ".####", "....."]
)
def_glyph('d',
    ["...#", "...#", ".###", "#..#", "#..#", "#..#", ".###", "...."],
    ["....#", "....#", ".####", "#...#", "#...#", "#...#", ".####", "....."]
)
def_glyph('e',
    ["....", "....", ".##.", "#..#", "####", "#...", ".###", "...."],
    [".....", ".....", ".###.", "#...#", "#####", "#....", ".####", "....."]
)
def_glyph('f',
    [".##.", ".#..", "###.", ".#..", ".#..", ".#..", ".#..", "...."],
    ["..##.", ".#...", "####.", "..#..", "..#..", "..#..", "..#..", "....."]
)
def_glyph('g',
    ["....", "....", ".###", "#..#", "#..#", ".###", "...#", ".##."],
    [".....", ".....", ".####", "#...#", "#...#", ".####", "....#", ".###."]
)
def_glyph('h',
    ["#...", "#...", "###.", "#..#", "#..#", "#..#", "#..#", "...."],
    ["#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#", "....."]
)
def_glyph('i',
    [".#..", "....", "##..", ".#..", ".#..", ".#..", ".###", "...."],
    ["..#..", ".....", ".##..", "..#..", "..#..", "..#..", ".###.", "....."]
)
def_glyph('j',
    ["..#.", "....", ".##.", "..#.", "..#.", "..#.", "#.#.", ".##."],
    ["...#.", ".....", "..##.", "...#.", "...#.", "...#.", "#..#.", ".##.."]
)
def_glyph('k',
    ["#...", "#...", "#..#", "#.#.", "##..", "#.#.", "#..#", "...."],
    ["#....", "#....", "#...#", "#..#.", "###..", "#..#.", "#...#", "....."]
)
def_glyph('l',
    ["##..", ".#..", ".#..", ".#..", ".#..", ".#..", ".##.", "...."],
    [".##..", "..#..", "..#..", "..#..", "..#..", "..#..", "..##.", "....."]
)
def_glyph('m',
    ["....", "....", "####", "####", "#..#", "#..#", "#..#", "...."],
    [".....", ".....", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "....."]
)
def_glyph('n',
    ["....", "....", "###.", "#..#", "#..#", "#..#", "#..#", "...."],
    [".....", ".....", "####.", "#...#", "#...#", "#...#", "#...#", "....."]
)
def_glyph('o',
    ["....", "....", ".##.", "#..#", "#..#", "#..#", ".##.", "...."],
    [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###.", "....."]
)
def_glyph('p',
    ["....", "....", "###.", "#..#", "#..#", "###.", "#...", "#..."],
    [".....", ".....", "####.", "#...#", "#...#", "####.", "#....", "#...."]
)
def_glyph('q',
    ["....", "....", ".###", "#..#", "#..#", ".###", "...#", "...#"],
    [".....", ".....", ".####", "#...#", "#...#", ".####", "....#", "....#"]
)
def_glyph('r',
    ["....", "....", "#.##", "##..", "#...", "#...", "#...", "...."],
    [".....", ".....", "#.###", "##...", "#....", "#....", "#....", "....."]
)
def_glyph('s',
    ["....", "....", ".###", "#...", ".##.", "...#", "###.", "...."],
    [".....", ".....", ".####", "#....", ".###.", "....#", "####.", "....."]
)
def_glyph('t',
    [".#..", ".#..", "####", ".#..", ".#..", ".#.#", "..##", "...."],
    ["..#..", "..#..", "#####", "..#..", "..#..", "..#.#", "...##", "....."]
)
def_glyph('u',
    ["....", "....", "#..#", "#..#", "#..#", "#..#", ".###", "...."],
    [".....", ".....", "#...#", "#...#", "#...#", "#...#", ".####", "....."]
)
def_glyph('v',
    ["....", "....", "#..#", "#..#", "#..#", ".##.", "..#.", "...."],
    [".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#..", "....."]
)
def_glyph('w',
    ["....", "....", "#..#", "#..#", "####", "####", "#..#", "...."],
    [".....", ".....", "#...#", "#...#", "#.#.#", "##.##", "#...#", "....."]
)
def_glyph('x',
    ["....", "....", "#..#", ".##.", "..#.", ".##.", "#..#", "...."],
    [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "....."]
)
def_glyph('y',
    ["....", "....", "#..#", "#..#", "#..#", ".###", "...#", ".##."],
    [".....", ".....", "#...#", "#...#", "#...#", ".####", "....#", ".###."]
)
def_glyph('z',
    ["....", "....", "####", "...#", ".##.", "#...", "####", "...."],
    [".....", ".....", "#####", "....#", "..#..", ".#...", "#####", "....."]
)

# Punctuation & Symbols: - # . : / % + ! ? ' " , ; ( ) < > = [ ] _
def_glyph('-',
    ["....", "....", "....", "####", "....", "....", "....", "...."],
    [".....", ".....", ".....", "#####", ".....", ".....", ".....", "....."]
)
def_glyph('#',
    [".#.#", "####", ".#.#", ".#.#", "####", ".#.#", "....", "...."],
    [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#.", "....."]
)
def_glyph('.',
    ["....", "....", "....", "....", "....", ".##.", ".##.", "...."],
    [".....", ".....", ".....", ".....", ".....", ".##..", ".##..", "....."]
)
def_glyph(':',
    ["....", ".##.", ".##.", "....", ".##.", ".##.", "....", "...."],
    [".....", ".##..", ".##..", ".....", ".##..", ".##..", ".....", "....."]
)
def_glyph('/',
    ["...#", "..#.", "..#.", ".#..", ".#..", "#...", "#...", "...."],
    ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#....", "....."]
)
def_glyph('%',
    ["#..#", "..#.", ".#..", ".#..", "#...", "#..#", "....", "...."],
    ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##", "....."]
)
def_glyph('+',
    ["....", ".#..", ".#..", "####", ".#..", ".#..", "....", "...."],
    [".....", "..#..", "..#..", "#####", "..#..", "..#..", ".....", "....."]
)
def_glyph('!',
    [".#..", ".#..", ".#..", ".#..", "....", ".#..", "....", "...."],
    ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#..", "....."]
)
def_glyph('?',
    ["###.", "..#.", "..#.", ".##.", "....", ".#..", "....", "...."],
    [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#..", "....."]
)
def_glyph("'",
    [".#..", ".#..", "....", "....", "....", "....", "....", "...."],
    ["..#..", "..#..", ".....", ".....", ".....", ".....", ".....", "....."]
)
def_glyph('"',
    ["#.#.", "#.#.", "....", "....", "....", "....", "....", "...."],
    [".#.#.", ".#.#.", ".....", ".....", ".....", ".....", ".....", "....."]
)
def_glyph(',',
    ["....", "....", "....", "....", "....", ".##.", "..#.", ".#.."],
    [".....", ".....", ".....", ".....", ".....", "..#..", ".#...", "....."]
)
def_glyph(';',
    ["....", ".##.", ".##.", "....", ".##.", "..#.", ".#..", "...."],
    [".....", ".##..", ".##..", ".....", ".##..", "..#..", ".#...", "....."]
)
def_glyph('(',
    ["..#.", ".#..", ".#..", ".#..", ".#..", ".#..", "..#.", "...."],
    ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#.", "....."]
)
def_glyph(')',
    [".#..", "..#.", "..#.", "..#.", "..#.", "..#.", ".#..", "...."],
    [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#...", "....."]
)
def_glyph('>',
    ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#...", "...."],
    [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#...", "....."]
)
def_glyph('<',
    ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#", "...."],
    ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#.", "....."]
)
def_glyph('=',
    ["....", "####", "....", "####", "....", "....", "....", "...."],
    [".....", ".....", "#####", ".....", "#####", ".....", ".....", "....."]
)

# Extra UI Glyphs: meter blocks, arrows
# Meters: 1/4 (block_1), 2/4 (block_2), 3/4 (block_3), 4/4 (block_4)
def_glyph('\x80', # meter 1/4
    ["....", "....", "....", "....", "....", "####", "####", "...."],
    [".....", ".....", ".....", ".....", ".....", "#####", "#####", "....."]
)
def_glyph('\x81', # meter 2/4
    ["....", "....", "....", "####", "####", "####", "####", "...."],
    [".....", ".....", ".....", "#####", "#####", "#####", "#####", "....."]
)
def_glyph('\x82', # meter 3/4
    ["....", "####", "####", "####", "####", "####", "####", "...."],
    [".....", ".###.", "#####", "#####", "#####", "#####", "#####", "....."]
)
def_glyph('\x83', # meter 4/4 (full block)
    ["####", "####", "####", "####", "####", "####", "####", "...."],
    ["#####", "#####", "#####", "#####", "#####", "#####", "#####", "....."]
)

# Arrows: up, down, left, right
def_glyph('^',
    [".#..", "###.", "#.#.", ".#..", ".#..", ".#..", "....", "...."],
    ["..#..", ".###.", "#.###", "..#..", "..#..", "..#..", ".....", "....."]
)
def_glyph('v', # or arrow down \x84
    ["\x84", "....", ".#..", ".#..", ".#..", "#.#.", "###.", ".#.."],
    [".....", "..#..", "..#..", "..#..", "#.###", ".###.", "..#..", "....."]
)[0] if False else None

def_glyph('\x84', # arrow down
    [".#..", ".#..", ".#..", "#.#.", "###.", ".#..", "....", "...."],
    ["..#..", "..#..", "..#..", "#.###", ".###.", "..#..", ".....", "....."]
)
def_glyph('\x85', # arrow left
    ["..#.", ".##.", "####", ".##.", "..#.", "....", "....", "...."],
    ["...#.", "..##.", "#####", "..##.", "...#.", ".....", ".....", "....."]
)
def_glyph('\x86', # arrow right
    [".#..", ".##.", "####", ".##.", ".#..", "....", "....", "...."],
    [".#...", ".##..", "#####", ".##..", ".#...", ".....", ".....", "....."]
)

# -----------------------------------------------------------------------------
# Prose Font Width Table (Variable-width EarthBound style)
# -----------------------------------------------------------------------------
# Character widths in pixels (glyph natural width + 1 pixel inter-character spacing)
PROSE_WIDTHS = {}
for ch in GLYPHS_6:
    if ch == ' ':
        PROSE_WIDTHS[ch] = 3
        continue
    r6 = GLYPHS_6[ch]
    # Find min and max active column across rows
    min_c, max_c = 5, -1
    for r in r6:
        for c, bit in enumerate(r):
            if bit == '#':
                if c < min_c: min_c = c
                if c > max_c: max_c = c
    if max_c == -1:
        PROSE_WIDTHS[ch] = 3
    else:
        # Natural width + 1 px spacing
        natural_w = (max_c - min_c + 1)
        # Give proportional widths: e.g. 'i', 'l', '!' -> 2 or 3 px
        PROSE_WIDTHS[ch] = natural_w + 1

# Fine-tune prose widths for EarthBound feel
PROSE_WIDTHS = {
    ' ': 3,
    '!': 2, '"': 4, '#': 6, '$': 6, '%': 6, '&': 6, "'": 2, '(': 3, ')': 3,
    '*': 4, '+': 5, ',': 2, '-': 4, '.': 2, '/': 5,
    '0': 5, '1': 4, '2': 5, '3': 5, '4': 5, '5': 5, '6': 5, '7': 5, '8': 5, '9': 5,
    ':': 2, ';': 2, '<': 4, '=': 5, '>': 4, '?': 5, '@': 6,
    'A': 5, 'B': 5, 'C': 5, 'D': 5, 'E': 5, 'F': 5, 'G': 5, 'H': 5, 'I': 4,
    'J': 5, 'K': 5, 'L': 5, 'M': 6, 'N': 5, 'O': 5, 'P': 5, 'Q': 5, 'R': 5,
    'S': 5, 'T': 5, 'U': 5, 'V': 5, 'W': 6, 'X': 5, 'Y': 5, 'Z': 5,
    'a': 5, 'b': 5, 'c': 4, 'd': 5, 'e': 4, 'f': 4, 'g': 5, 'h': 5, 'i': 2,
    'j': 3, 'k': 5, 'l': 2, 'm': 6, 'n': 5, 'o': 5, 'p': 5, 'q': 5, 'r': 4,
    's': 4, 't': 4, 'u': 5, 'v': 5, 'w': 6, 'x': 5, 'y': 5, 'z': 5,
    '\x80': 5, '\x81': 5, '\x82': 5, '\x83': 5,
    '^': 5, '\x84': 5, '\x85': 5, '\x86': 5
}

# -----------------------------------------------------------------------------
# Binary Generator for font5.bin and font6.bin (1bpp, 8 rows per glyph, MSB left)
# -----------------------------------------------------------------------------
def build_font_bins(build_dir):
    os.makedirs(build_dir, exist_ok=True)
    f5_path = os.path.join(build_dir, "font5.bin")
    f6_path = os.path.join(build_dir, "font6.bin")
    
    # Standard ASCII 32..126 + extras 128..134
    chars_to_export = [chr(i) for i in range(32, 127)] + ['\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86']
    
    data5 = bytearray()
    data6 = bytearray()
    
    for ch in chars_to_export:
        r5 = GLYPHS_5.get(ch, ["...."]*8)
        r6 = GLYPHS_6.get(ch, ["....."]*8)
        
        # 1 bpp: MSB = leftmost pixel (bit 7)
        for row in r5:
            b = 0
            for i, p in enumerate(row):
                if p == '#':
                    b |= (0x80 >> i)
            data5.append(b)
            
        for row in r6:
            b = 0
            for i, p in enumerate(row):
                if p == '#':
                    b |= (0x80 >> i)
            data6.append(b)
            
    with open(f5_path, "wb") as f:
        f.write(data5)
    with open(f6_path, "wb") as f:
        f.write(data6)
        
    print(f"Exported {f5_path} ({len(data5)} bytes, {len(chars_to_export)} glyphs)")
    print(f"Exported {f6_path} ({len(data6)} bytes, {len(chars_to_export)} glyphs)")

# -----------------------------------------------------------------------------
# Screen Drawing Engine
# -----------------------------------------------------------------------------
def render_text_fixed(img, text, x0, y0, font_dict, cell_w, color, bg_color=None):
    draw = ImageDraw.Draw(img)
    cur_x = x0
    for ch in text:
        r = font_dict.get(ch, font_dict[' '])
        if bg_color and 0 <= cur_x < img.width and 0 <= y0 < img.height:
            draw.rectangle([cur_x, y0, min(img.width - 1, cur_x + cell_w - 1), min(img.height - 1, y0 + 7)], fill=bg_color)
        for y, row in enumerate(r):
            py = y0 + y
            if 0 <= py < img.height:
                for x, bit in enumerate(row):
                    px = cur_x + x
                    if bit == '#' and 0 <= px < img.width:
                        img.putpixel((px, py), color)
        cur_x += cell_w

def render_text_prose(img, text, x0, y0, font_dict, color, bg_color=None):
    draw = ImageDraw.Draw(img)
    cur_x = x0
    for ch in text:
        r = font_dict.get(ch, font_dict[' '])
        w = PROSE_WIDTHS.get(ch, 4)
        if bg_color and 0 <= cur_x < img.width and 0 <= y0 < img.height:
            draw.rectangle([cur_x, y0, min(img.width - 1, cur_x + w - 1), min(img.height - 1, y0 + 7)], fill=bg_color)
        for y, row in enumerate(r):
            py = y0 + y
            if 0 <= py < img.height:
                for x, bit in enumerate(row):
                    px = cur_x + x
                    if bit == '#' and 0 <= px < img.width:
                        img.putpixel((px, py), color)
        cur_x += w

# -----------------------------------------------------------------------------
# Screen Mockups: FRAME, HELP (Fixed), and HELP (Prose)
# -----------------------------------------------------------------------------
def draw_frame_screen(cell_w):
    # 256x224 canvas
    img = Image.new("RGB", (256, 224), COLOR_BG)
    font_dict = GLYPHS_5 if cell_w == 5 else GLYPHS_6
    
    # Beat row HDMA tinting (rows 5, 9, 13, 17)
    draw = ImageDraw.Draw(img)
    for r in [5, 9, 13, 17]:
        draw.rectangle([0, r * 8, 255, r * 8 + 7], fill=COLOR_BAND)
        
    # Row 1: Status bar
    # FRAME   ROW 00  SONG     T150 STOP RAM 22.3K  F 36.8K   00
    if cell_w == 5:
        # 51 cols
        render_text_fixed(img, "FRAME", 0*5, 1*8, font_dict, 5, COLOR_HILITE)
        render_text_fixed(img, "ROW 00", 6*5, 1*8, font_dict, 5, COLOR_TEXT)
        render_text_fixed(img, "SONG", 14*5, 1*8, font_dict, 5, COLOR_DIM)
        render_text_fixed(img, "T150", 19*5, 1*8, font_dict, 5, COLOR_TEXT)
        render_text_fixed(img, "STOP", 24*5, 1*8, font_dict, 5, COLOR_DIM)
        render_text_fixed(img, "RAM 22.3K", 29*5, 1*8, font_dict, 5, COLOR_TEXT)
        render_text_fixed(img, "F 36.8K", 39*5, 1*8, font_dict, 5, COLOR_TEXT)
        render_text_fixed(img, "00", 48*5, 1*8, font_dict, 5, COLOR_CYAN)
        
        # Row 3: Track headers (8 tracks side-by-side: cols 3..50 = 48 cols, 6 cols/track!)
        # T1..T8
        for t in range(8):
            tx = 3 + t * 6
            render_text_fixed(img, f"T{t+1} 01", tx*5, 3*8, font_dict, 5, COLOR_HILITE)
            
        # Rows 5..20: Grid rows 00..0F
        notes = ["C-4", "D-4", "E-4", "F-4", "G-4", "A-4", "B-4", "C-5"]
        for row in range(16):
            y = (5 + row) * 8
            render_text_fixed(img, f"{row:02X}", 0*5, y, font_dict, 5, COLOR_DIM)
            for t in range(8):
                tx = 3 + t * 6
                if t < 4:
                    note = notes[(row + t) % 8]
                    # Note in cyan, instr/cmd in text/pink
                    render_text_fixed(img, note, tx*5, y, font_dict, 5, COLOR_CYAN)
                    render_text_fixed(img, "01", (tx+3)*5, y, font_dict, 5, COLOR_TEXT)
                else:
                    render_text_fixed(img, "---", tx*5, y, font_dict, 5, COLOR_DIM)
                    render_text_fixed(img, "--", (tx+3)*5, y, font_dict, 5, COLOR_DIM)
                    
        # Row 21: Level meters (8 tracks)
        render_text_fixed(img, "VU", 0*5, 21*8, font_dict, 5, COLOR_DIM)
        meters = ['\x83', '\x82', '\x81', '\x80', ' ', ' ', ' ', ' ']
        for t in range(8):
            tx = 3 + t * 6
            render_text_fixed(img, meters[t]*3, tx*5, 21*8, font_dict, 5, COLOR_GREEN)
            
        # Row 22: Inspector
        render_text_fixed(img, "T1 P00 C-4 01 STRINGS  V34 VIB SPEED X DEPTH Y", 0*5, 22*8, font_dict, 5, COLOR_TEXT)
        
        # Row 24: Hint
        render_text_fixed(img, "X:RETURN  A+D:NAV  B+D:EDIT  L/R:TRK", 0*5, 24*8, font_dict, 5, COLOR_DIM)
        
    else:
        # 6-px cells (42 cols across 252 px)
        render_text_fixed(img, "FRAME", 0*6, 1*8, font_dict, 6, COLOR_HILITE)
        render_text_fixed(img, "R00", 6*6, 1*8, font_dict, 6, COLOR_TEXT)
        render_text_fixed(img, "SONG", 10*6, 1*8, font_dict, 6, COLOR_DIM)
        render_text_fixed(img, "T150", 15*6, 1*8, font_dict, 6, COLOR_TEXT)
        render_text_fixed(img, "STOP", 20*6, 1*8, font_dict, 6, COLOR_DIM)
        render_text_fixed(img, "22.3K", 25*6, 1*8, font_dict, 6, COLOR_TEXT)
        render_text_fixed(img, "F36.8K", 31*6, 1*8, font_dict, 6, COLOR_TEXT)
        render_text_fixed(img, "00", 38*6, 1*8, font_dict, 6, COLOR_CYAN)
        
        # 8 tracks in 5 cols each (cols 2..41 = 40 cols, 5 cols/track)
        for t in range(8):
            tx = 2 + t * 5
            render_text_fixed(img, f"T{t+1} 01", tx*6, 3*8, font_dict, 6, COLOR_HILITE)
            
        # Rows 5..20: Grid
        notes = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
        for row in range(16):
            y = (5 + row) * 8
            render_text_fixed(img, f"{row:02X}", 0*6, y, font_dict, 6, COLOR_DIM)
            for t in range(8):
                tx = 2 + t * 5
                if t < 4:
                    note = notes[(row + t) % 8]
                    render_text_fixed(img, note, tx*6, y, font_dict, 6, COLOR_CYAN)
                    render_text_fixed(img, "01", (tx+2)*6, y, font_dict, 6, COLOR_TEXT)
                else:
                    render_text_fixed(img, "-- --", tx*6, y, font_dict, 6, COLOR_DIM)
                    
        # Row 21: Level meters
        render_text_fixed(img, "M", 0*6, 21*8, font_dict, 6, COLOR_DIM)
        meters = ['\x83', '\x82', '\x81', '\x80', ' ', ' ', ' ', ' ']
        for t in range(8):
            tx = 2 + t * 5
            render_text_fixed(img, meters[t]*3, tx*6, 21*8, font_dict, 6, COLOR_GREEN)
            
        # Row 22: Inspector
        render_text_fixed(img, "T1 P00 C-4 01 STRINGS V34 VIB SPEED", 0*6, 22*8, font_dict, 6, COLOR_TEXT)
        
        # Row 24: Hint
        render_text_fixed(img, "X:RET A+D:NAV B+D:EDIT L/R:TRK", 0*6, 24*8, font_dict, 6, COLOR_DIM)
        
    return img

def draw_help_screen_fixed(cell_w):
    img = Image.new("RGB", (256, 224), COLOR_BG)
    font_dict = GLYPHS_5 if cell_w == 5 else GLYPHS_6
    
    # Title
    render_text_fixed(img, "HELP: NAVIGATION & BUTTONS", 0, 1*8, font_dict, cell_w, COLOR_HILITE)
    
    lines = [
        ("DPAD", "MOVE THE CURSOR"),
        ("HOLD A +DPAD", "GO TO SCREENS (SONG/CHAIN/PHRASE/INSTR)"),
        ("A + B", "PLAY THIS SCREEN"),
        ("START", "PLAY / STOP ALL TRACKS"),
        ("SELECT", "LIVE MODE / MUTE MATRIX"),
        ("HOLD A 3 SEC", "ENTER / EXIT HELP"),
        ("", ""),
        ("CELL EDITING:", ""),
        ("TAP B", "INSERT ON EMPTY CELL"),
        ("HOLD B + L/R", "EDIT VALUE (SMALL STEP)"),
        ("HOLD B + U/D", "EDIT VALUE (OCTAVE / BIG STEP)"),
        ("HOLD B TAP A", "CUT WITH COPY TO CLIPBOARD"),
        ("> TAP B,B", "PASTE CLIPBOARD VALUE"),
        ("", ""),
        ("CHANNELS:", ""),
        ("L / R", "PREV / NEXT TRACK IN VIEW"),
        ("X + DPAD", "MUTE / SOLO VOICE"),
    ]
    
    for idx, (btn, desc) in enumerate(lines):
        y = (3 + idx) * 8
        if btn and not desc:
            render_text_fixed(img, btn, 0, y, font_dict, cell_w, COLOR_HILITE)
        elif btn and desc:
            render_text_fixed(img, btn, 0, y, font_dict, cell_w, COLOR_ACCENT)
            render_text_fixed(img, desc, 14 * cell_w, y, font_dict, cell_w, COLOR_TEXT)
            
    return img

def draw_help_screen_prose():
    img = Image.new("RGB", (256, 224), COLOR_BG)
    
    # Title with accent bar
    render_text_prose(img, "HELP: Navigation & Controls (Prose Font)", 8, 1*8, GLYPHS_6, COLOR_HILITE)
    draw = ImageDraw.Draw(img)
    draw.line([8, 2*8 + 2, 248, 2*8 + 2], fill=COLOR_DIM)
    
    sections = [
        ("Basic Navigation", [
            ("D-Pad", "Move cursor across tracks and rows"),
            ("Hold A + D-Pad", "Navigate screens (Song, Chain, Phrase, Frame)"),
            ("Start", "Play / Stop global sequencer playback"),
            ("Select", "Toggle Live performance matrix"),
            ("Hold A (3s)", "Open or close this Help guide"),
        ]),
        ("Pattern Editing", [
            ("Tap B", "Insert default note or value on empty cell"),
            ("Hold B + Left/Right", "Nudge value by single steps"),
            ("Hold B + Up/Down", "Nudge pitch by octaves / coarse values"),
            ("Hold B + Tap A", "Cut cell and copy value to clipboard"),
            ("Double-tap B", "Paste clipboard value or clone pattern"),
        ]),
        ("Track Management", [
            ("L / R Shoulders", "Switch active track horizontally"),
            ("X + D-Pad", "Quick mute or solo current voice"),
        ])
    ]
    
    cur_y = 3 * 8
    for sec_title, items in sections:
        render_text_prose(img, sec_title, 8, cur_y, GLYPHS_6, COLOR_CYAN)
        cur_y += 9
        for key, val in items:
            render_text_prose(img, key, 16, cur_y, GLYPHS_6, COLOR_ACCENT)
            render_text_prose(img, "-", 100, cur_y, GLYPHS_6, COLOR_DIM)
            render_text_prose(img, val, 108, cur_y, GLYPHS_6, COLOR_TEXT)
            cur_y += 9
        cur_y += 3
        
    return img

# -----------------------------------------------------------------------------
# Display Simulation Filters: Sharp, Blended, 4:3 TV
# -----------------------------------------------------------------------------
def make_sharp(img, scale=2):
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)

def make_blended(img, scale=2):
    # Apply horizontal video blend (simulates Snes9x / NTSC horizontal low-pass)
    # Each pixel blends with adjacent horizontal pixels
    w, h = img.size
    blended = Image.new("RGB", (w, h))
    pixels_in = img.load()
    pixels_out = blended.load()
    
    for y in range(h):
        for x in range(w):
            r0, g0, b0 = pixels_in[max(0, x-1), y]
            r1, g1, b1 = pixels_in[x, y]
            r2, g2, b2 = pixels_in[min(w-1, x+1), y]
            # 25% left, 50% center, 25% right
            r = int(0.25 * r0 + 0.50 * r1 + 0.25 * r2)
            g = int(0.25 * g0 + 0.50 * g1 + 0.25 * g2)
            b = int(0.25 * b0 + 0.50 * b1 + 0.25 * b2)
            pixels_out[x, y] = (r, g, b)
            
    return blended.resize((w * scale, h * scale), Image.NEAREST)

def make_tv43(img, target_h=448):
    # SNES 256x224 displays on 4:3 CRT TV (aspect ratio 4:3 -> 597x448)
    target_w = int(target_h * 4 / 3)
    # First blend horizontally
    blended = make_blended(img, scale=1)
    # Resample to 4:3 aspect ratio
    tv = blended.resize((target_w, target_h), Image.BILINEAR)
    return tv

# -----------------------------------------------------------------------------
# Comparison Sheet Compositor
# -----------------------------------------------------------------------------
def build_comparison_sheet(build_dir):
    print("Rendering mock screens...")
    frame_c = draw_frame_screen(5)
    frame_d = draw_frame_screen(6)
    help_c  = draw_help_screen_fixed(5)
    help_d  = draw_help_screen_fixed(6)
    help_p  = draw_help_screen_prose()
    
    # All 5 screens:
    # 1. Option C (5-px cells) FRAME
    # 2. Option D (6-px cells) FRAME
    # 3. Option C (5-px cells) HELP (Fixed)
    # 4. Option D (6-px cells) HELP (Fixed)
    # 5. Variable-Width Prose HELP (EarthBound Style)
    screens = [
        ("C (5-px): FRAME Screen (51 Cols)", frame_c),
        ("D (6-px): FRAME Screen (42 Cols)", frame_d),
        ("C (5-px): HELP Fixed (51 Cols)", help_c),
        ("D (6-px): HELP Fixed (42 Cols)", help_d),
        ("Prose: HELP Variable-Width (EarthBound)", help_p),
    ]
    
    col_w = 512
    row_h = 448
    header_h = 44
    title_h = 70
    pad_x = 30
    pad_y = 24
    
    num_cols = len(screens)
    sheet_w = pad_x * 2 + num_cols * col_w + (num_cols - 1) * pad_x
    sheet_h = title_h + (header_h + row_h + pad_y) * 3 + pad_y
    
    sheet = Image.new("RGB", (sheet_w, sheet_h), (8, 10, 14))
    draw = ImageDraw.Draw(sheet)
    
    # Title
    render_text_fixed(sheet, "SNDJ UI REWRITE: FONT & RENDERER COMPARISON SHEET (EARTHBOUND 256px)",
                      pad_x, 16, GLYPHS_6, 6, COLOR_HILITE)
    render_text_prose(sheet, "Devin Choice: Text drawn at 256px Mode 1 from full low-res pixels. Sharp, Blended (Snes9x/NTSC), and 4:3 CRT TV views.",
                      pad_x, 34, GLYPHS_6, COLOR_DIM)
    draw.line([pad_x, 52, sheet_w - pad_x, 52], fill=COLOR_DIM)
                      
    view_types = [
        ("SHARP (1:1 Low-Res Pixels at 2x Integer Scale - Zero Blending, Maximum Clarity)", make_sharp),
        ("BLENDED (Horizontal Low-Pass Composite / Snes9x Smoothing Filter)", make_blended),
        ("4:3 TV VIEW (Aspect Ratio Corrected 4:3 CRT Display Simulation)", lambda im: make_tv43(im, 448))
    ]
    
    for r_idx, (view_label, filter_fn) in enumerate(view_types):
        y_top = title_h + r_idx * (header_h + row_h + pad_y)
        draw.text((pad_x, y_top), view_label, fill=COLOR_ACCENT)
        draw.line([pad_x, y_top + 18, sheet_w - pad_x, y_top + 18], fill=COLOR_DIM)
        
        y_img = y_top + 26
        for c_idx, (col_label, screen_img) in enumerate(screens):
            x_img = pad_x + c_idx * (col_w + pad_x)
            if r_idx == 0:
                # Add column label on first row
                draw.text((x_img, y_top - 18), col_label, fill=COLOR_CYAN)
                
            rendered_img = filter_fn(screen_img)
            if rendered_img.width > col_w:
                display_img = rendered_img.resize((col_w, row_h), Image.BILINEAR)
            else:
                display_img = rendered_img
                
            sheet.paste(display_img, (x_img, y_img))
            # Border
            draw.rectangle([x_img - 1, y_img - 1, x_img + col_w, y_img + row_h], outline=COLOR_DIM)
            
    out_path = os.path.join(build_dir, "fontmock_comparison.png")
    sheet.save(out_path)
    sheet.save(os.path.join(build_dir, "sheet.png"))
    print(f"Comparison sheet saved to {out_path} and build/sheet.png ({sheet.width}x{sheet.height})")

def main():
    build_dir = sys.argv[1] if len(sys.argv) > 1 else "build"
    build_font_bins(build_dir)
    build_comparison_sheet(build_dir)
    
    # Print Prose Width Table summary
    print("\nPROSE WIDTH TABLE (character: pixel advance):")
    chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz- #.:/%+!?',;"
    table_str = " ".join(f"'{c}':{PROSE_WIDTHS.get(c, 4)}" for c in chars[:40])
    print(" ", table_str)
    table_str2 = " ".join(f"'{c}':{PROSE_WIDTHS.get(c, 4)}" for c in chars[40:])
    print(" ", table_str2)

if __name__ == "__main__":
    main()
