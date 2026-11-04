"""Generate UZI RUSH's tiny, nearest-filtered PSX textures + the item icon sheet.

    python tools/gen_textures.py

(spark/glow/puff/ring/impact/noise/metal/concrete/brick/skyline/clouds/card_frame are carried over
from Sky Slugger and live in assets/textures already.)
"""
import math
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from font5x7 import draw_text, text_width  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
rng = random.Random(1999)


def clamp(v):
    return max(0, min(255, int(v)))


def new(w, h, color=(0, 0, 0, 255)):
    if len(color) == 3:
        color = (*color, 255)
    return Image.new("RGBA", (w, h), color)


def noise_fill(img, base, amp):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            n = rng.uniform(-amp, amp)
            px[x, y] = (clamp(base[0] + n), clamp(base[1] + n), clamp(base[2] + n), 255)


def shade(c, f):
    return (clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f), 255)


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))


def rect(img, x0, y0, x1, y1, color):
    px = img.load()
    for y in range(max(0, y0), min(img.size[1], y1)):
        for x in range(max(0, x0), min(img.size[0], x1)):
            px[x, y] = color if len(color) == 4 else (*color, 255)


def floor():
    img = new(64, 64)
    noise_fill(img, (62, 58, 78), 7)
    px = img.load()
    for i in range(64):
        for t in (0, 1):
            px[i, t] = shade((62, 58, 78), 0.55)
            px[t, i] = shade((62, 58, 78), 0.55)
            px[i, 63 - t] = shade((62, 58, 78), 1.25)
            px[63 - t, i] = shade((62, 58, 78), 1.25)
    for (x, y) in ((4, 4), (59, 4), (4, 59), (59, 59)):
        rect(img, x, y, x + 2, y + 2, (30, 28, 40))
    # scuffs and burns
    for _ in range(30):
        x, y = rng.randrange(64), rng.randrange(64)
        px[x, y] = shade(px[x, y], 0.65)
    save(img, "floor")


def stage_top():
    img = new(64, 64)
    noise_fill(img, (28, 32, 52), 5)
    px = img.load()
    for i in range(64):
        if i % 16 == 0:
            for j in range(64):
                px[i, j] = (40, 190, 210, 255)
                px[j, i] = (40, 190, 210, 255)
    save(img, "stage_top")


def wall():
    img = new(64, 64)
    noise_fill(img, (52, 44, 74), 6)
    px = img.load()
    for i in range(64):
        px[i, 0] = px[i, 32] = shade((52, 44, 74), 0.5)
        px[0, i] = px[32, i] = shade((52, 44, 74), 0.5)
        px[i, 1] = px[i, 33] = shade((52, 44, 74), 1.3)
    for (x, y) in ((3, 3), (28, 3), (3, 28), (28, 28), (35, 35), (60, 35), (35, 60), (60, 60), (35, 3), (60, 3), (3, 35), (28, 35)):
        rect(img, x, y, x + 2, y + 2, (96, 88, 128))
    for _ in range(14):  # streaks
        x = rng.randrange(64)
        for y in range(rng.randrange(64), 64):
            px[x, y] = shade(px[x, y], 0.8)
    save(img, "wall")


def hazard():
    img = new(32, 32)
    px = img.load()
    for y in range(32):
        for x in range(32):
            on = ((x + y) // 8) % 2 == 0
            c = (236, 188, 28) if on else (24, 22, 28)
            n = rng.uniform(-8, 8)
            px[x, y] = (clamp(c[0] + n), clamp(c[1] + n), clamp(c[2] + n), 255)
    save(img, "hazard")


def crate():
    img = new(32, 32)
    noise_fill(img, (140, 100, 56), 12)
    px = img.load()
    for x in range(32):
        for y in range(32):
            if x % 8 == 0:
                px[x, y] = shade(px[x, y], 0.75)
    rect(img, 0, 0, 32, 3, (62, 66, 78))
    rect(img, 0, 29, 32, 32, (62, 66, 78))
    rect(img, 0, 0, 3, 32, (62, 66, 78))
    rect(img, 29, 0, 32, 32, (62, 66, 78))
    for i in range(3, 29):   # diagonal brace
        rect(img, i - 1, i - 1, i + 1, i + 1, (84, 58, 30))
    for (x, y) in ((1, 1), (29, 1), (1, 29), (29, 29)):
        rect(img, x, y, x + 1, y + 1, (200, 200, 210))
    save(img, "crate")


def barrier():
    img = new(32, 32)
    noise_fill(img, (150, 150, 156), 8)
    px = img.load()
    for x in range(32):
        for y in range(10, 22):
            if ((x + y) // 6) % 2 == 0:
                px[x, y] = (200, 40, 40, 255)
    save(img, "barrier")


def rust():
    img = new(32, 32)
    noise_fill(img, (178, 108, 62), 20)
    px = img.load()
    for _ in range(60):
        x, y = rng.randrange(32), rng.randrange(32)
        px[x, y] = (96, 52, 30, 255)
    for x in range(0, 32, 16):
        for y in range(32):
            px[x, y] = shade(px[x, y], 0.6)
    for y in range(0, 32, 16):
        for x in range(32):
            px[x, y] = shade(px[x, y], 0.6)
    save(img, "rust")


def plate():
    """Greyscale riveted armour plate, tinted per enemy in code."""
    img = new(32, 32)
    noise_fill(img, (176, 176, 184), 10)
    px = img.load()
    for i in range(32):
        px[i, 0] = px[0, i] = (110, 110, 120, 255)
        px[i, 31] = px[31, i] = (226, 226, 234, 255)
    for (x, y) in ((3, 3), (27, 3), (3, 27), (27, 27)):
        rect(img, x, y, x + 2, y + 2, (96, 96, 108))
    for x in range(8, 24):
        px[x, 16] = (120, 120, 130, 255)
    save(img, "plate")


def sign():
    """Small on purpose: at distance the nearest-filtered texture would alias big text to mush."""
    img = new(96, 32, (14, 6, 24, 255))
    px = img.load()
    for i in range(96):
        px[i, 0] = px[i, 31] = (255, 60, 190, 255)
        px[i, 1] = px[i, 30] = (150, 30, 110, 255)
    for i in range(32):
        px[0, i] = px[95, i] = (255, 60, 190, 255)
        px[1, i] = px[94, i] = (150, 30, 110, 255)
    t1 = "UZI RUSH"
    w1 = text_width(t1, 2, 0)
    draw_text(img, (96 - w1) // 2, 8, t1, (255, 240, 90), 2, shadow=(255, 40, 120), spacing=0)
    save(img, "sign")


def sky_neon():
    """Sky dome texture: rows 0..31 run from zenith to horizon (the sphere's equator is row 32),
    the lower half is the same glow darkened (it is hidden below the arena floor)."""
    img = new(128, 64)
    px = img.load()
    stops = [(0.0, (8, 3, 36)), (0.4, (52, 12, 88)), (0.68, (186, 36, 124)), (0.88, (255, 112, 64)), (1.0, (255, 206, 96))]
    for y in range(64):
        k = min(y, 63 - y) / 31.0 if y < 32 else 1.0
        k = min(1.0, y / 31.0) if y < 32 else 1.0
        for i in range(len(stops) - 1):
            if stops[i][0] <= k <= stops[i + 1][0]:
                t = (k - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                c = tuple(stops[i][1][j] + (stops[i + 1][1][j] - stops[i][1][j]) * t for j in range(3))
                break
        f = 1.0 if y < 32 else 0.55
        for x in range(128):
            px[x, y] = (clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f), 255)
    for _ in range(80):   # stars in the upper sky
        x, y = rng.randrange(128), rng.randrange(0, 20)
        b = rng.randint(150, 255)
        px[x, y] = (b, b, 255, 255)
    cx, cy, r = 32, 28, 11    # a striped retro sun sitting on the horizon
    for y in range(64):
        for x in range(128):
            d = math.hypot(x - cx, y - cy)
            if d < r and y < 32 and not (y > cy - 4 and (y - (cy - 4)) % 3 == 0):
                px[x, y] = (255, clamp(220 - (y - (cy - r)) * 6), clamp(110 - (y - (cy - r)) * 3), 255)
    save(img, "sky_neon")


def tracer():
    img = new(16, 4, (0, 0, 0, 0))
    px = img.load()
    for x in range(16):
        a = clamp(255 * (x / 15) ** 1.5)
        px[x, 1] = px[x, 2] = (255, 245, 170, a)
        px[x, 0] = px[x, 3] = (255, 160, 60, a // 3)
    save(img, "tracer")


def flash():
    img = new(16, 16, (0, 0, 0, 0))
    px = img.load()
    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            d = math.hypot(dx, dy)
            star = max(0.0, 1.0 - min(abs(dx), abs(dy)) / 2.2) * max(0.0, 1.0 - d / 8.0)
            core = max(0.0, 1.0 - d / 4.0)
            v = min(1.0, star * 1.2 + core)
            if v > 0.1:
                px[x, y] = (255, clamp(210 + 45 * core), clamp(90 + 160 * core), clamp(255 * v))
    save(img, "flash")


def eyeblink():
    pass


# ------------------------------------------------------------------ item icons
# 8x8 bitmaps ('#' = bright, 'o' = mid accent, '.' = clear), tinted by rarity in code.
ICONS = {
    "bullet": ["..oo....", ".oooo...", ".####...", ".####...", ".####...", "oooooo..", "oooooo..", "........"],
    "fast": ["...##...", "..##....", ".###....", "#######.", "..###...", ".##.....", "##......", "........"],
    "sight": ["..####..", ".#....#.", "#..##..#", "#.####.#", "#..##..#", ".#....#.", "..####..", "........"],
    "boots": ["........", "..###...", "..###...", "..###...", ".######.", "oooooooo", "........", "........"],
    "heart": [".##..##.", "########", "########", "########", ".######.", "..####..", "...##...", "........"],
    "wing": ["......##", "....####", "..######", "#######.", "#####...", "###.....", "#.......", "........"],
    "coin": ["..####..", ".#oooo#.", "#oo##oo#", "#oo##oo#", "#oo##oo#", ".#oooo#.", "..####..", "........"],
    "magnet": ["#......#", "#......#", "#......#", "#......#", "##....##", ".##..##.", "..####..", "........"],
    "pierce": ["#.......", ".#......", "..#.....", "########", "..#.....", ".#......", "#.......", "........"],
    "fire": ["...#....", "..##....", "..###...", ".#####..", ".##o##..", "..ooo...", "...o....", "........"],
    "ricochet": ["#####...", "....#...", "....#...", "..###...", ".#.#....", "#..#....", "...#####", "........"],
    "bolt": ["...###..", "..###...", ".###....", "#######.", "..###...", ".##.....", "##......", "........"],
    "boom": ["#..#..#.", ".#.#.#..", "..###...", "#######.", "..###...", ".#.#.#..", "#..#..#.", "........"],
    "fang": ["########", "#######.", ".#####..", ".#o#o#..", "..#.#...", "..#.#...", "...#....", "........"],
    "grenade": ["...##...", "..####..", ".######.", "########", "########", "########", ".######.", "..####.."],
    "multi": ["##.##.##", "##.##.##", "##.##.##", "##.##.##", "oo.oo.oo", "oo.oo.oo", "........", "........"],
    "skull": [".######.", "########", "#.####.#", "########", ".######.", "..#..#..", "..####..", "........"],
    "shield": ["########", "########", "########", "#######.", ".######.", "..####..", "...##...", "........"],
    "clock": ["..####..", ".#.##.#.", "#..##..#", "#..###.#", "#......#", ".#....#.", "..####..", "........"],
    "nova": ["#..#..#.", ".#.#.#..", "..###...", "#######.", "..###...", ".#.#.#..", "#..#..#.", "........"],
    "star": ["...##...", "...##...", "########", ".######.", "..####..", ".##..##.", ".#....#.", "........"],
    "glass": ["#.#.#.#.", ".#####..", "#.###.#.", ".#####..", "#.###.#.", ".#####..", "#.#.#.#.", "........"],
    "gear": ["..#..#..", ".######.", "########", "###..###", "###..###", "########", ".######.", "..#..#.."],
    "devil": ["#......#", "##....##", "########", "#.####.#", "########", ".######.", "..#..#..", "........"],
    "drop": ["...##...", "..####..", ".######.", "########", "########", ".######.", "..####..", "........"],
    "ghost": [".######.", "########", "#.####.#", "########", "########", "########", "#.#..#.#", "........"],
    "dash": ["#....#..", ".#..##..", "..###...", "#######.", "..###...", ".#..##..", "#....#..", "........"],
    "eye": ["........", ".######.", "########", "###oo###", "###oo###", "########", ".######.", "........"],
    "chain": ["##.##.##", "#.#..#.#", "##.##.##", "........", "##.##.##", "#.#..#.#", "##.##.##", "........"],
    "life": ["...##...", "...##...", "########", "########", "...##...", "...##...", "...##...", "........"],
    "turret": ["..####..", "..####..", "########", "########", "..####..", ".######.", "########", "........"],
    "slow": ["########", ".######.", "..####..", "...##...", "...##...", "..####..", ".######.", "########"],
}


def items_sheet():
    names = list(ICONS.keys())
    cols = 8
    rows = (len(names) + cols - 1) // cols
    img = new(cols * 8, rows * 8, (0, 0, 0, 0))
    px = img.load()
    for i, n in enumerate(names):
        ox, oy = (i % cols) * 8, (i // cols) * 8
        for y, row in enumerate(ICONS[n]):
            assert len(row) == 8, (n, y, row)
            for x, ch in enumerate(row):
                if ch == "#":
                    px[ox + x, oy + y] = (255, 255, 255, 255)
                elif ch == "o":
                    px[ox + x, oy + y] = (255, 170, 90, 255)
    save(img, "items")
    with open(os.path.join(ROOT, "scripts", "icon_names.txt"), "w") as f:
        f.write("\n".join(names))
    print("icons:", len(names), "->", ", ".join(f"{i}:{n}" for i, n in enumerate(names)))


def main():
    os.makedirs(OUT, exist_ok=True)
    floor(); stage_top(); wall(); hazard(); crate(); barrier(); rust(); plate(); sign(); sky_neon()
    tracer(); flash(); items_sheet()
    print("textures ok")


main()
