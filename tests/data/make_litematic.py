#!/usr/bin/env python3
"""Writes tests/data/mini.litematic: a tiny hand-made Litematica file for the litematic scenario.

    python3 tests/data/make_litematic.py            # (re)write the file, print the expected numbers

Region 'Mini': Size (-6, 8, 5) (negative x on purpose), Position (10, 0, 0).
26 palette entries -> 5 bits per entry, so entries straddle longs. Built cells sit at x 0..4, y 1..4, z 0..4:
column x=5 is empty (edge), layer y=0 and layers y=5..7 are all air. Stdlib only.
"""
import gzip, math, struct, sys, zlib
from pathlib import Path

OUT = Path(__file__).with_name("mini.litematic")

def s(t): b = t.encode(); return struct.pack(">H", len(b)) + b
def named(tag, name, payload): return bytes([tag]) + s(name) + payload
def i32(v): return struct.pack(">i", v)
def compound(items): return b"".join(items) + b"\0"
def lst(tag, payloads): return bytes([tag]) + i32(len(payloads)) + b"".join(payloads)
def xyz(x, y, z): return compound([named(3, "x", i32(x)), named(3, "y", i32(y)), named(3, "z", i32(z))])

def block(name, **props):
    items = [named(8, "Name", s(name))]
    if props:
        items.append(named(10, "Properties", compound([named(8, k, s(str(v))) for k, v in props.items()])))
    return compound(items)

M = "minecraft:"
PALETTE = [
    (M + "air", {}),
    (M + "stone", {}),
    (M + "cobblestone", {}),
    (M + "sandstone", {}),
    (M + "cut_sandstone", {}),
    (M + "red_terracotta", {}),
    (M + "yellow_wool", {}),
    (M + "oak_planks", {}),
    (M + "oak_fence", dict(east="true", north="false", south="false", west="true", waterlogged="false")),
    (M + "oak_fence_gate", dict(facing="north", open="false", in_wall="false", powered="false")),
    (M + "sandstone_stairs", dict(facing="north", half="bottom", shape="straight", waterlogged="false")),
    (M + "sandstone_stairs", dict(facing="east", half="bottom", shape="straight", waterlogged="false")),
    (M + "sandstone_stairs", dict(facing="south", half="top", shape="straight", waterlogged="false")),
    (M + "sandstone_stairs", dict(facing="west", half="top", shape="inner_left", waterlogged="false")),
    (M + "sandstone_slab", dict(type="bottom", waterlogged="false")),
    (M + "sandstone_slab", dict(type="top", waterlogged="false")),
    (M + "sandstone_slab", dict(type="double", waterlogged="false")),
    (M + "oak_log", dict(axis="y")),
    (M + "oak_log", dict(axis="x")),
    (M + "hay_block", dict(axis="z")),
    (M + "grass_path", {}),
    (M + "chest", dict(facing="east", type="single", waterlogged="false")),
    (M + "wall_torch", dict(facing="south")),
    ("create:andesite_casing", {}),
    (M + "fancy_unknown_block", {}),
    (M + "jungle_leaves", dict(distance="1", persistent="true", waterlogged="false")),
]
SX, SY, SZ = 6, 8, 5
BITS = max(2, math.ceil(math.log2(len(PALETTE))))

def grid():
    g = {}
    for y in range(SY):
        for z in range(SZ):
            for x in range(SX):
                idx = 0
                if 1 <= y <= 4 and x <= 4:
                    n = x + z * SX + y * SX * SZ
                    idx = 0 if n % 5 == 0 else (n * 7 + 3) % (len(PALETTE) - 1) + 1
                g[(x, y, z)] = idx
    g[(0, 1, 0)] = 1; g[(4, 4, 4)] = 3; g[(0, 4, 4)] = 10; g[(4, 1, 0)] = 12
    # every palette entry appears at least once: park the missing ones on the y=2 layer, x 0..4
    missing = [i for i in range(1, len(PALETTE)) if i not in g.values()]
    for k, i in enumerate(missing):
        g[(k % 5, 2, k // 5)] = i
    return g

def longs(g):
    v = 0
    for y in range(SY):
        for z in range(SZ):
            for x in range(SX):
                v |= g[(x, y, z)] << (BITS * (x + z * SX + y * SX * SZ))
    n = math.ceil(SX * SY * SZ * BITS / 64)
    return [(v >> (64 * i)) & (2**64 - 1) for i in range(n)]

def build():
    g = grid()
    ls = longs(g)
    region = compound([
        named(10, "Position", xyz(10, 0, 0)),
        named(10, "Size", xyz(-SX, SY, SZ)),
        named(9, "BlockStatePalette", lst(10, [block(n, **p) for n, p in PALETTE])),
        named(12, "BlockStates", i32(len(ls)) + b"".join(struct.pack(">Q", l) for l in ls)),
    ])
    root = compound([
        named(3, "Version", i32(6)),
        named(3, "MinecraftDataVersion", i32(3955)),
        named(10, "Metadata", compound([
            named(8, "Name", s("Mini Test")), named(8, "Author", s("tests")),
            named(10, "EnclosingSize", xyz(SX, SY, SZ)),
        ])),
        named(10, "Regions", compound([named(10, "Mini", region)])),
    ])
    return bytes([10]) + s("") + root, g

WORDS = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf"]

def text():
    """The text the three inflate test streams carry; litematic scenario rebuilds it in Lua."""
    return "".join("line %d: %s %s\n" % (i, WORDS[i * i % 7], WORDS[(i * 3) % 7]) for i in range(1, 401))

def gz(data, level=9, strategy=zlib.Z_DEFAULT_STRATEGY):
    c = zlib.compressobj(level, zlib.DEFLATED, -15, 8, strategy)
    body = c.compress(data) + c.flush()
    head = b"\x1f\x8b\x08\x00\0\0\0\0\x02\xff"
    return head + body + struct.pack("<II", zlib.crc32(data), len(data) & 0xFFFFFFFF)

def main():
    t = text().encode()
    here = OUT.parent
    (here / "inflate_dynamic.gz").write_bytes(gz(t, 9))
    (here / "inflate_fixed.gz").write_bytes(gz(t[:300], 9, zlib.Z_FIXED))
    (here / "inflate_stored.gz").write_bytes(gz(t[:300], 0))
    raw, g = build()
    OUT.write_bytes(gzip.compress(raw, 9, mtime=0))
    cnt = {}
    for i in g.values():
        if i: cnt[PALETTE[i][0]] = cnt.get(PALETTE[i][0], 0) + 1
    print("bits", BITS, "palette", len(PALETTE), "bytes", OUT.stat().st_size)
    print("total", sum(cnt.values()), "types", len(cnt))
    for k, v in sorted(cnt.items(), key=lambda kv: (-kv[1], kv[0])): print(" ", k, v)
    st = {}
    for i in g.values():
        n, p = PALETTE[i]
        if n.endswith("stairs") or n.endswith("slab") or n.endswith("log"):
            key = ",".join(f"{k}={p[k]}" for k in ("facing", "half", "type", "axis") if k in p)
            st[(n, key)] = st.get((n, key), 0) + 1
    for k, v in sorted(st.items()): print(" state", k, v)
    for c in [(0, 1, 0), (4, 4, 4), (0, 4, 4), (4, 1, 0), (5, 2, 2), (3, 6, 1), (1, 1, 1)]:
        print(" get", c, g[c] + 1, PALETTE[g[c]][0])

if __name__ == "__main__":
    main()
