#!/usr/bin/env python3
"""Writes tests/data/placement.litematic: a hand-made build with every placement case of plan v2 (#85).

    python3 tests/data/make_plan_litematic.py

Region 'Placement', size 12 x 4 x 10. y0 is a sandstone floor. See the CELLS table for what each cell tests.
"""
import gzip, math, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import make_litematic as m

OUT = Path(__file__).with_name("placement.litematic")
M = "minecraft:"
SX, SY, SZ = 12, 4, 10

def stairs(f, h): return (M + "sandstone_stairs", dict(facing=f, half=h, shape="straight", waterlogged="false"))
def slab(t): return (M + "sandstone_slab", dict(type=t, waterlogged="false"))
STONE = (M + "stone", {})
COBBLE = (M + "cobblestone", {})

cells = {}
for x in range(SX):
    for z in range(SZ):
        cells[(x, 0, z)] = (M + "sandstone", {})
# arch: a bottom stair over air, standing cell (2,2,2) is a block that must come after it   -> F
cells.update({(2, 1, 2): COBBLE, (4, 1, 2): COBBLE, (2, 2, 2): COBBLE, (4, 2, 2): COBBLE, (3, 2, 2): stairs("east", "bottom")})
# top-half stair / slab with a block under                                                    -> T, T
cells.update({(6, 1, 2): STONE, (6, 2, 2): stairs("south", "top"), (8, 1, 2): STONE, (8, 2, 2): slab("top")})
# bottom slab over air next to a block                                                        -> F
cells.update({(10, 2, 3): COBBLE, (10, 2, 2): slab("bottom")})
# double slab                                                                                -> 2
cells[(1, 1, 5)] = slab("double")
# wall torch hanging west on a stone wall                                                     -> F, wall first
cells.update({(0, 1, 5): STONE, (0, 2, 5): STONE, (1, 2, 5): (M + "wall_torch", dict(facing="east"))})
# a row of sideways logs on the floor (the last one has nothing to click: U), a sideways hay pair in the air
for x in (3, 4, 5, 6): cells[(x, 1, 6)] = (M + "oak_log", dict(axis="x"))
cells.update({(9, 2, 6): (M + "hay_block", dict(axis="z")), (9, 2, 7): (M + "hay_block", dict(axis="z"))})
# defaults: upright log, chest, gate, bottom stair on the floor, top stair over air
cells.update({(11, 1, 0): (M + "oak_log", dict(axis="y")), (11, 1, 9): (M + "chest", dict(facing="north", type="single", waterlogged="false")),
              (0, 1, 9): (M + "oak_fence_gate", dict(facing="east", open="false", in_wall="false", powered="false")),
              (1, 1, 8): stairs("west", "bottom"), (2, 2, 8): stairs("north", "top")})
# U: top stair on the ground, and a top stair over a block that is walled in on every side
cells[(11, 0, 5)] = stairs("north", "top")
cells.update({(4, 1, 8): STONE, (6, 1, 8): STONE, (5, 1, 7): STONE, (5, 1, 9): STONE, (5, 1, 8): STONE, (5, 2, 8): stairs("south", "top")})

def main():
    pal = [(M + "air", {})]
    idx = {(M + "air", ()): 0}
    for (n, p) in cells.values():
        k = (n, tuple(sorted(p.items())))
        if k not in idx:
            idx[k] = len(pal); pal.append((n, p))
    bits = max(2, math.ceil(math.log2(len(pal))))
    v = 0
    for y in range(SY):
        for z in range(SZ):
            for x in range(SX):
                c = cells.get((x, y, z))
                i = idx[(c[0], tuple(sorted(c[1].items())))] if c else 0
                v |= i << (bits * (x + z * SX + y * SX * SZ))
    n = math.ceil(SX * SY * SZ * bits / 64)
    import struct
    ls = [(v >> (64 * i)) & (2**64 - 1) for i in range(n)]
    region = m.compound([
        m.named(10, "Position", m.xyz(0, 0, 0)), m.named(10, "Size", m.xyz(SX, SY, SZ)),
        m.named(9, "BlockStatePalette", m.lst(10, [m.block(a, **b) for a, b in pal])),
        m.named(12, "BlockStates", m.i32(len(ls)) + b"".join(struct.pack(">Q", l) for l in ls)),
    ])
    root = m.compound([
        m.named(3, "Version", m.i32(6)), m.named(3, "MinecraftDataVersion", m.i32(3955)),
        m.named(10, "Metadata", m.compound([m.named(8, "Name", m.s("Placement Test")), m.named(8, "Author", m.s("tests")),
                                           m.named(10, "EnclosingSize", m.xyz(SX, SY, SZ))])),
        m.named(10, "Regions", m.compound([m.named(10, "Placement", region)])),
    ])
    OUT.write_bytes(gzip.compress(bytes([10]) + m.s("") + root, 9, mtime=0))
    print("palette", len(pal), "bits", bits, "cells", len(cells), "bytes", OUT.stat().st_size)

if __name__ == "__main__":
    main()
