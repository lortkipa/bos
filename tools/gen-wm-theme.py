#!/usr/bin/env python3
"""Generate the bOS xfwm4 window decoration theme.

Writes PNG pieces + themerc into rootfs/usr/share/themes/bOS/xfwm4/. Pure stdlib
(no Pillow) so it runs anywhere; output is committed, re-run after tweaking colours:

    python3 tools/gen-wm-theme.py
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "rootfs/usr/share/themes/bOS/xfwm4")

TITLE_H = 36          # titlebar height in px
RADIUS = 10           # top corner radius
BTN_W = 22            # width of one button cell
DOT = 13              # traffic-light diameter
SS = 4                # supersampling factor for anti-aliasing

STATES = {
    # state: (titlebar fill, top highlight, outer border, separator under the title)
    "active":   ((0xF4, 0xF4, 0xF6), (0xFF, 0xFF, 0xFF), (0xC4, 0xC4, 0xCA), (0xDE, 0xDE, 0xE2)),
    "inactive": ((0xFA, 0xFA, 0xFB), (0xFF, 0xFF, 0xFF), (0xD2, 0xD2, 0xD6), (0xE8, 0xE8, 0xEB)),
}

# macOS-style traffic lights: (fill, ring)
LIGHTS = {
    "close":    ((0xFF, 0x5F, 0x57), (0xE2, 0x46, 0x3F)),
    "hide":     ((0xFE, 0xBC, 0x2E), (0xE1, 0xA1, 0x16)),
    "maximize": ((0x28, 0xC8, 0x40), (0x1A, 0xAB, 0x29)),
}
GREY = ((0xDC, 0xDC, 0xE0), (0xC8, 0xC8, 0xCD))
GLYPH = {"close": (0x8E, 0x1A, 0x10), "hide": (0x99, 0x5A, 0x00), "maximize": (0x0B, 0x65, 0x13)}


def write_png(path, w, h, px):
    """px: list of rows, each a list of (r, g, b, a) tuples."""
    raw = b"".join(b"\x00" + bytes(c for p in row for c in p) for row in px)
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def blend(dst, src, a):
    """Alpha-composite src (rgb) with coverage a over dst (rgba)."""
    if a <= 0:
        return dst
    da = dst[3] / 255.0
    oa = a + da * (1 - a)
    if oa == 0:
        return (0, 0, 0, 0)
    rgb = tuple(round((s * a + d * da * (1 - a)) / oa) for s, d in zip(src, dst[:3]))
    return rgb + (round(oa * 255),)


def coverage(w, h, inside):
    """Return a w*h grid of [0,1] coverage for predicate inside(x, y) (pixel units)."""
    grid = []
    for y in range(h):
        row = []
        for x in range(w):
            n = 0
            for sy in range(SS):
                for sx in range(SS):
                    if inside(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS):
                        n += 1
            row.append(n / (SS * SS))
        grid.append(row)
    return grid


def titlebar_column(state, h=TITLE_H):
    fill, hi, border, sep = STATES[state]
    col = []
    for y in range(h):
        if y == 0:
            c = border
        elif y == 1:
            c = hi
        elif y == h - 1:
            c = sep
        else:
            c = fill
        col.append(c + (255,))
    return col


def corner(state, mirror=False):
    """Rounded top corner piece, RADIUS wide, TITLE_H tall."""
    fill, hi, border, sep = STATES[state]
    w, h = RADIUS, TITLE_H
    r = RADIUS
    cx, cy = r, r  # circle centre (for the left corner)

    def in_outer(x, y):
        if y >= r or x >= r:
            return True
        return math.hypot(x - cx, y - cy) <= r

    def in_inner(x, y):
        if y >= r and x >= 1:
            return True
        if y < r and x >= r and y >= 1:
            return True
        return math.hypot(x - cx, y - cy) <= r - 1

    outer = coverage(w, h, in_outer)
    inner = coverage(w, h, in_inner)
    col = titlebar_column(state)
    px = []
    for y in range(h):
        row = []
        for x in range(w):
            p = blend((0, 0, 0, 0), border, outer[y][x])
            # Inside the curve the 1px highlight follows the arc instead of row 1.
            on_arc = y < r and math.hypot(x + 0.5 - cx, y + 0.5 - cy) > r - 2
            body = hi if on_arc and y >= 1 else col[y][:3]
            p = blend(p, body, inner[y][x])
            row.append(p)
        px.append(row[::-1] if mirror else row)
    return w, h, px


def button(state, kind, mode):
    """A button cell: titlebar background + traffic light (or nothing for unused buttons)."""
    w, h = BTN_W, TITLE_H
    col = titlebar_column(state)
    px = [[col[y] for _ in range(w)] for y in range(h)]
    if kind not in LIGHTS:
        return w, h, px

    fill, ring = LIGHTS[kind] if state == "active" or mode in ("prelight", "pressed") else GREY
    if mode == "pressed":
        fill = tuple(max(0, int(c * 0.82)) for c in fill)
        ring = tuple(max(0, int(c * 0.82)) for c in ring)
    cx, cy, r = w / 2, h / 2, DOT / 2
    ring_cov = coverage(w, h, lambda x, y: math.hypot(x - cx, y - cy) <= r)
    fill_cov = coverage(w, h, lambda x, y: math.hypot(x - cx, y - cy) <= r - 0.9)

    glyph_cov = None
    if mode in ("prelight", "pressed"):
        g = 3.0  # glyph half-size
        t = 0.75  # half stroke width
        def on_glyph(x, y):
            dx, dy = x - cx, y - cy
            if kind == "close":
                return (abs(dx) <= g and abs(dy) <= g and
                        (abs(dx - dy) / math.sqrt(2) <= t or abs(dx + dy) / math.sqrt(2) <= t))
            if kind == "hide":
                return abs(dx) <= g + 0.5 and abs(dy) <= t
            if kind == "maximize":
                return (abs(dx) <= g + 0.5 and abs(dy) <= t) or (abs(dy) <= g + 0.5 and abs(dx) <= t)
            return False
        glyph_cov = coverage(w, h, on_glyph)

    for y in range(h):
        for x in range(w):
            p = blend(px[y][x], ring, ring_cov[y][x])
            p = blend(p, fill, fill_cov[y][x])
            if glyph_cov:
                p = blend(p, GLYPH[kind], glyph_cov[y][x] * 0.9)
            px[y][x] = p
    return w, h, px


def solid(w, h, rgb):
    return w, h, [[rgb + (255,)] * w for _ in range(h)]


def main():
    os.makedirs(OUT, exist_ok=True)
    for state in STATES:
        border = STATES[state][2]
        col = titlebar_column(state)
        for i in range(1, 6):
            write_png(f"{OUT}/title-{i}-{state}.png", 1, TITLE_H, [[c] for c in col])
        write_png(f"{OUT}/top-left-{state}.png", *corner(state))
        write_png(f"{OUT}/top-right-{state}.png", *corner(state, mirror=True))
        for piece in ("left", "right"):
            write_png(f"{OUT}/{piece}-{state}.png", *solid(1, 1, border))
        for piece in ("bottom", "bottom-left", "bottom-right"):
            write_png(f"{OUT}/{piece}-{state}.png", *solid(1, 1, border))

        for kind in ("close", "hide", "maximize", "menu", "shade", "stick"):
            write_png(f"{OUT}/{kind}-{state}.png", *button(state, kind, "normal"))
            if state == "active":
                write_png(f"{OUT}/{kind}-prelight.png", *button(state, kind, "prelight"))
                write_png(f"{OUT}/{kind}-pressed.png", *button(state, kind, "pressed"))
            for toggled in ("maximize", "shade", "stick"):
                if kind == toggled:
                    write_png(f"{OUT}/{kind}-toggled-{state}.png", *button(state, kind, "normal"))
                    if state == "active":
                        write_png(f"{OUT}/{kind}-toggled-prelight.png", *button(state, kind, "prelight"))
                        write_png(f"{OUT}/{kind}-toggled-pressed.png", *button(state, kind, "pressed"))

    with open(f"{OUT}/themerc", "w") as f:
        f.write(
            "# bOS window decorations - generated by tools/gen-wm-theme.py\n"
            "button_offset=8\n"
            "button_spacing=0\n"
            "full_width_title=true\n"
            "title_alignment=center\n"
            "title_vertical_offset_active=1\n"
            "title_vertical_offset_inactive=1\n"
            "title_shadow_active=false\n"
            "title_shadow_inactive=false\n"
            "active_text_color=#2C2C30\n"
            "inactive_text_color=#A4A4AA\n"
            "show_app_icon=false\n"
            "shadow_delta_height=8\n"
            "shadow_delta_width=4\n"
            "shadow_delta_x=0\n"
            "shadow_delta_y=-6\n"
            "shadow_opacity=35\n"
        )
    print(f"wrote theme to {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
