#!/usr/bin/env python3
"""makepeaks.py — waveform overview of every pool sample for the hi-res
INSTR screen (src/instrhr.asm).

Decoding BRR on the 65816 at screen entry would take many frames, so the
build decodes each pool sample once (tools/sndj_brr.py) and stores 96
amplitude bins of 0-16 (half the display height) per entry.

Output: build/peaks.bin = 56 entries x 96 bytes (entries beyond the pool's
count are zero). Pool format: tools/sndj_pool.py header comment.

Limit: the table describes the pool this ROM was BUILT with. If a browser
tool later patches the pool in the ROM, the drawn shapes go stale (the
sound itself is unaffected).
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndj_brr  # noqa: E402

BINS = 96
MAX_ENTRIES = 56
HALF = 16


def main(pool_path, out_path):
    pool = open(pool_path, 'rb').read()
    assert pool[:8] == b'SNDJPOOL', 'not a pool image'
    count = pool[9]
    out = bytearray(MAX_ENTRIES * BINS)
    for e in range(min(count, MAX_ENTRIES)):
        rec = pool[16 + e * 16:32 + e * 16]
        off, blocks = struct.unpack('<HH', rec[8:12])
        data = pool[off * 9:(off + blocks) * 9]
        if blocks == 0 or len(data) < 9:
            continue
        pcm = sndj_brr.decode(data)
        if not pcm:
            continue
        peak = max(1, max(abs(v) for v in pcm))
        n = len(pcm)
        for b in range(BINS):
            lo = b * n // BINS
            hi = max(lo + 1, (b + 1) * n // BINS)
            a = max(abs(v) for v in pcm[lo:hi])
            out[e * BINS + b] = min(HALF, (a * HALF + peak - 1) // peak)
    open(out_path, 'wb').write(out)
    print(f"makepeaks: {min(count, MAX_ENTRIES)} samples x {BINS} bins -> {out_path}")


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/pool.bin',
         sys.argv[2] if len(sys.argv) > 2 else 'build/peaks.bin')
