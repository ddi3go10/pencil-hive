"""Procedural skeletons for levels 5-20 (levels 1-4 stay hand-made in make_skeletons.py).

Each level is a small scene (150 x 100 canvas) built from a few parts, plus a board whose size
shrinks as the levels go on. The forge (main.swift) then deals tiles for each skeleton and the
solver proves every result can be won. Re-running this script rewrites skeletons 05..20 only.
"""
import json, math, os, random

def poly(*pts): return {"type": "polygon", "points": [list(p) for p in pts]}
def ell(cx, cy, rx, ry): return {"type": "ellipse", "cx": cx, "cy": cy, "rx": rx, "ry": ry}
def rect(x, y, w, h, r=0): return {"type": "rect", "x": x, "y": y, "w": w, "h": h, "radius": r}
def star(cx, cy, ro, ri, n=5):
    pts = []
    for i in range(n * 2):
        a = -math.pi / 2 + i * math.pi / n
        r = ro if i % 2 == 0 else ri
        pts.append((round(cx + r * math.cos(a), 1), round(cy + r * math.sin(a), 1)))
    return poly(*pts)

class Scene:
    def __init__(self, name, paper, bg):
        self.name, self.paper, self.regions, self.line = name, paper, [], []
        self.add(bg, rect(0, 0, 150, 100))
    def add(self, color, shape):
        self.regions.append({"id": len(self.regions) + 1, "color": color, "shape": shape})
        return self
    def lines(self, *shapes):
        self.line.extend(shapes)
        return self
    def out(self):
        return {"name": self.name, "paper": self.paper, "regions": self.regions, "lineArt": self.line}

# ---- reusable parts -------------------------------------------------------------------------
def sun(s, x=120, y=22, c="lemon", r=13): return s.add(c, ell(x, y, r, r))
def hills(s, c="mint", y=72): return s.add(c, poly((0, y), (30, y - 12), (70, y - 6), (110, y - 16), (150, y - 8), (150, 100), (0, 100)))
def ground(s, c="mint", y=74): return s.add(c, rect(0, y, 150, 100 - y))
def cloud(s, x, y, c="sky"): return s.add(c, ell(x, y, 16, 7))
def house(s, x, body="amber", roof="coral"):
    s.add(body, rect(x, 56, 40, 28, 2)); s.add(roof, poly((x - 6, 58), (x + 20, 32), (x + 46, 58))); return s
def tree(s, x, leaf="mint", trunk="amber"):
    s.add(trunk, rect(x - 3, 62, 6, 20)); s.add(leaf, ell(x, 52, 14, 18)); return s
def mountain(s, x, w, h, c="violet", base=80): return s.add(c, poly((x - w, base), (x, base - h), (x + w, base)))
def flower(s, x, y, petal="rose", c2="lemon"):
    s.add(petal, ell(x, y, 9, 9)); s.add(c2, ell(x, y, 3.5, 3.5)); return s
def fish(s, x, y, c="coral"):
    s.add(c, ell(x, y, 17, 9)); s.add(c, poly((x + 14, y), (x + 28, y - 9), (x + 28, y + 9))); return s
def balloon(s, x, y, c):
    s.add(c, ell(x, y, 10, 13)); return s

def scenes():
    out = []
    # 5
    s = Scene("Windy Meadow", "#FFF6DC", "sky"); sun(s); hills(s, "mint", 74); flower(s, 32, 80, "rose"); flower(s, 70, 84, "coral"); flower(s, 108, 80, "violet")
    s.lines(poly((32, 89), (32, 96)), poly((70, 93), (70, 99)), poly((108, 89), (108, 96))); out.append(s)
    # 6
    s = Scene("Red Barn", "#FFF6DC", "sky"); sun(s, 28, 22, "lemon"); ground(s, "mint", 72); s.add("coral", rect(46, 46, 58, 34, 2)); s.add("amber", poly((40, 48), (75, 22), (110, 48))); s.add("lemon", rect(66, 58, 18, 22, 1))
    s.lines(poly((46, 46), (104, 80)), poly((104, 46), (46, 80))); out.append(s)
    # 7
    s = Scene("Paper Boat", "#EAF6FF", "sky"); s.add("indigo", rect(0, 64, 150, 36)); s.add("coral", poly((38, 62), (112, 62), (96, 82), (54, 82))); s.add("lemon", poly((74, 18), (74, 60), (102, 60))); s.add("rose", poly((70, 24), (70, 60), (46, 60))); sun(s, 124, 20, "amber", 11)
    s.lines(poly((74, 14), (74, 62)), poly((8, 74), (30, 72), (52, 74))); out.append(s)
    # 8
    s = Scene("Autumn Tree", "#FFF3E4", "lemon"); ground(s, "amber", 76); s.add("amber", rect(68, 52, 14, 28, 2)); s.add("coral", ell(75, 38, 30, 24)); s.add("rose", ell(50, 54, 14, 10)); s.add("mint", ell(112, 84, 18, 6)); s.add("violet", ell(30, 16, 14, 6))
    s.lines(poly((60, 30), (66, 36)), poly((86, 40), (94, 34))); out.append(s)
    # 9
    s = Scene("Snowy Peaks", "#F0F6FF", "sky"); mountain(s, 44, 40, 52, "indigo"); mountain(s, 100, 44, 62, "violet"); s.add("lemon", poly((88, 38), (100, 18), (112, 38))); s.add("mint", rect(0, 82, 150, 18)); sun(s, 18, 18, "amber", 9); cloud(s, 128, 16, "rose")
    s.lines(star(60, 14, 3, 1.4), poly((0, 92), (150, 92))); out.append(s)
    # 10
    s = Scene("Goldfish Pond", "#EAFBF5", "mint"); s.add("sky", ell(75, 52, 62, 38)); fish(s, 56, 48, "amber"); fish(s, 92, 66, "coral"); s.add("lemon", ell(112, 36, 8, 5)); s.add("rose", ell(24, 24, 9, 9)); s.add("violet", ell(130, 82, 12, 7))
    s.lines(ell(48, 46, 1.6, 1.6), ell(100, 64, 1.6, 1.6)); out.append(s)
    # 11
    s = Scene("Hot Air Balloons", "#FFF6DC", "sky"); cloud(s, 30, 78, "lemon"); cloud(s, 118, 84, "lemon")
    balloon(s, 42, 34, "coral"); balloon(s, 78, 26, "rose"); balloon(s, 112, 38, "violet"); s.add("amber", rect(72, 46, 12, 8, 1)); s.add("mint", ell(22, 14, 8, 8))
    s.lines(poly((42, 47), (42, 60)), poly((78, 39), (78, 46)), poly((112, 51), (112, 62))); out.append(s)
    # 12
    s = Scene("Seaside Castle", "#FFF6DC", "sky"); sun(s, 124, 18, "lemon", 11); s.add("sky", rect(0, 74, 150, 26)); s.add("amber", poly((0, 82), (150, 82), (150, 100), (0, 100)))
    s.add("rose", rect(50, 40, 50, 40, 2)); s.add("coral", rect(44, 30, 14, 20)); s.add("coral", rect(92, 30, 14, 20)); s.add("violet", rect(68, 56, 14, 24, 7)); s.add("mint", ell(22, 80, 14, 5))
    s.lines(poly((44, 30), (51, 20), (58, 30)), poly((92, 30), (99, 20), (106, 30))); out.append(s)
    # 13
    s = Scene("Night Owl", "#EEF2FF", "indigo"); s.add("lemon", ell(124, 22, 12, 12)); s.add("amber", rect(0, 82, 150, 18)); s.add("amber", ell(75, 56, 24, 28)); s.add("rose", ell(75, 62, 14, 16)); s.add("lemon", ell(64, 40, 7, 7)); s.add("lemon", ell(86, 40, 7, 7)); s.add("coral", poly((70, 46), (80, 46), (75, 54)))
    s.lines(ell(64, 40, 2, 2), ell(86, 40, 2, 2), star(30, 18, 4, 1.8), star(100, 10, 3, 1.4)); out.append(s)
    # 14
    s = Scene("Rainbow Valley", "#FFF6DC", "sky"); hills(s, "mint", 78)
    s.add("coral", ell(75, 80, 62, 54)); s.add("amber", ell(75, 80, 52, 44)); s.add("lemon", ell(75, 80, 42, 34)); s.add("sky", ell(75, 80, 32, 24)); s.add("mint", rect(0, 80, 150, 20)); cloud(s, 22, 70, "rose"); cloud(s, 130, 70, "rose")
    out.append(s)
    # 15
    s = Scene("Space Station", "#F4EEFF", "indigo"); s.add("sky", ell(30, 74, 24, 24)); s.add("rose", rect(52, 44, 46, 20, 4)); s.add("lemon", rect(24, 48, 24, 12)); s.add("lemon", rect(102, 48, 24, 12)); s.add("coral", ell(75, 40, 12, 12)); s.add("violet", ell(120, 82, 16, 10)); s.add("mint", ell(118, 18, 8, 8))
    s.lines(star(20, 20, 4, 1.8), star(90, 12, 3, 1.4), star(50, 90, 3, 1.4)); out.append(s)
    # 16
    s = Scene("Garden Party", "#FFF6DC", "sky"); sun(s, 22, 20, "lemon", 12); ground(s, "mint", 70); house(s, 86, "lemon", "coral"); tree(s, 30, "mint", "amber"); flower(s, 62, 88, "rose"); flower(s, 138, 88, "violet"); balloon(s, 126, 28, "rose")
    s.lines(rect(98, 62, 10, 22, 2), poly((126, 41), (126, 56))); out.append(s)
    # 17
    s = Scene("Deep Sea Treasure", "#E6F7FF", "sky"); s.add("indigo", rect(0, 28, 150, 72)); s.add("amber", poly((0, 86), (50, 80), (100, 88), (150, 82), (150, 100), (0, 100))); s.add("coral", rect(56, 62, 38, 22, 3)); s.add("lemon", rect(56, 56, 38, 10, 5)); fish(s, 30, 44, "rose"); fish(s, 110, 52, "mint"); s.add("violet", ell(22, 70, 8, 12)); s.add("lemon", ell(128, 74, 6, 6))
    s.lines(ell(26, 43, 1.6, 1.6), ell(106, 51, 1.6, 1.6), poly((75, 62), (75, 68))); out.append(s)
    # 18
    s = Scene("Dragon Castle", "#F4EEFF", "violet"); sun(s, 126, 18, "lemon", 10); mountain(s, 40, 44, 40, "indigo", 84); s.add("mint", rect(0, 84, 150, 16)); s.add("rose", rect(70, 40, 50, 44, 2)); s.add("coral", poly((64, 42), (95, 16), (126, 42))); s.add("amber", rect(88, 62, 14, 22, 7)); s.add("lemon", ell(40, 58, 14, 10)); s.add("sky", ell(20, 30, 10, 5))
    s.lines(poly((95, 16), (95, 6)), star(44, 14, 3, 1.4)); out.append(s)
    # 19
    s = Scene("Carnival Night", "#EEF2FF", "indigo"); ground(s, "violet", 80); s.add("coral", poly((20, 30), (60, 30), (60, 80), (20, 80))); s.add("lemon", poly((20, 30), (40, 12), (60, 30))); s.add("rose", ell(100, 52, 28, 28)); s.add("sky", ell(100, 52, 16, 16)); s.add("amber", rect(96, 78, 8, 6)); balloon(s, 130, 24, "mint"); balloon(s, 14, 16, "amber"); s.add("lemon", ell(75, 14, 6, 6))
    s.lines(star(76, 40, 3, 1.4), poly((100, 24), (100, 80)), poly((72, 52), (128, 52))); out.append(s)
    # 20
    s = Scene("Grand Finale", "#FFF6DC", "sky"); sun(s, 126, 16, "lemon", 11); s.add("violet", rect(0, 72, 150, 28)); s.add("indigo", poly((0, 72), (24, 40), (48, 72))); s.add("indigo", poly((102, 72), (126, 40), (150, 72))); s.add("coral", ell(75, 56, 30, 30)); s.add("amber", ell(75, 56, 20, 20)); s.add("lemon", ell(75, 56, 10, 10)); s.add("mint", ell(20, 86, 16, 8)); s.add("rose", ell(130, 86, 16, 8)); s.add("sky", ell(30, 20, 12, 6)); s.add("mint", star(75, 14, 8, 3.5))
    out.append(s)
    return out

# ---- boards ---------------------------------------------------------------------------------
def hexagon(radius):
    return [(q, r) for q in range(-radius, radius + 1) for r in range(-radius, radius + 1) if abs(q + r) <= radius]

def dist(c): q, r = c; return max(abs(q), abs(r), abs(q + r))

def board(radius, keep, seed):
    rng = random.Random(seed)
    cells = hexagon(radius)
    ranked = sorted(cells, key=lambda c: (dist(c), rng.random()))
    kept = set(ranked[:keep])
    return radius, sorted([list(c) for c in cells if c not in kept])

# (pencilSize, boardRadius, cell count) per level 5..20: a gentle ramp, then tight boards.
CURVE = {
    5: (3, 2, 19), 6: (4, 2, 19), 7: (4, 2, 19), 8: (4, 3, 23), 9: (4, 3, 23), 10: (4, 3, 22), 11: (4, 3, 18), 12: (4, 3, 17),
    13: (4, 3, 16), 14: (4, 3, 16), 15: (4, 3, 15), 16: (4, 3, 15), 17: (4, 3, 14), 18: (4, 3, 14), 19: (4, 3, 13), 20: (4, 3, 13),
}

if __name__ == "__main__":
    os.makedirs("skeletons", exist_ok=True)
    for i, scene in enumerate(scenes()):
        lid = i + 5
        size, radius, keep = CURVE[lid]
        rad, removed = board(radius, keep, 1000 + lid)
        level = {"id": lid, "name": scene.name, "pencilSize": size, "boardRadius": rad, "removed": removed,
                 "artwork": scene.out(), "supply": []}
        level["artwork"]["name"] = scene.name
        json.dump(level, open(f"skeletons/level_{lid:02d}.json", "w"), indent=1)
        print(lid, scene.name, "regions", len(scene.regions), "cells", keep)
