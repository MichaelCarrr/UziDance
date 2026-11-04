"""Build the outlined 5x7 pixel font as a BMFont (.fnt + .png) that Godot imports."""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from font5x7 import GLYPHS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts")
CELL_W, CELL_H = 7, 9  # 5x7 glyph plus a 1px outline on every side
COLS = 16


def main():
    os.makedirs(OUT, exist_ok=True)
    keys = list(GLYPHS.keys())
    rows = (len(keys) + COLS - 1) // COLS
    aw, ah = COLS * CELL_W, rows * CELL_H
    img = Image.new("RGBA", (aw, ah), (0, 0, 0, 0))
    px = img.load()
    rects = {}
    for i, ch in enumerate(keys):
        gx, gy = (i % COLS) * CELL_W, (i // COLS) * CELL_H
        rects[ch] = (gx, gy)
        g = GLYPHS[ch]
        ink = [(x, y) for y in range(7) for x in range(5) if g[y][x] == "#"]
        for x, y in ink:  # outline first
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    px[gx + 1 + x + dx, gy + 1 + y + dy] = (0, 0, 0, 255)
        for x, y in ink:
            px[gx + 1 + x, gy + 1 + y] = (255, 255, 255, 255)
    img.save(os.path.join(OUT, "psx_font.png"))

    entries = []

    def add(code, ch):
        gx, gy = rects[ch]
        adv = 4 if ch == " " else 6
        entries.append(
            f"char id={code} x={gx} y={gy} width={CELL_W} height={CELL_H} "
            f"xoffset=0 yoffset=0 xadvance={adv} page=0 chnl=15"
        )

    for ch in keys:
        add(ord(ch), ch)
    for c in "abcdefghijklmnopqrstuvwyz":  # lowercase -> uppercase glyphs ('x' has its own)
        add(ord(c), c.upper())

    lines = [
        'info face="PSXFont" size=10 bold=0 italic=0 charset="" unicode=1 stretchH=100 '
        'smooth=0 aa=1 padding=0,0,0,0 spacing=0,0 outline=1',
        f"common lineHeight=11 base=8 scaleW={aw} scaleH={ah} pages=1 packed=0 "
        "alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0",
        'page id=0 file="psx_font.png"',
        f"chars count={len(entries)}",
    ] + entries
    with open(os.path.join(OUT, "psx_font.fnt"), "w", encoding="ascii") as f:
        f.write("\n".join(lines) + "\n")
    print("font:", len(entries), "glyphs,", aw, "x", ah)


if __name__ == "__main__":
    main()
