#!/usr/bin/env python3
"""
Generate Flynn OS GRUB background — 1920×1080 TRON grid (PNG).
No external libs needed — pure Python struct + zlib.
Run:  python3 generate-bg.py  →  produces background.png
"""
import struct, zlib, math, random

W, H = 1920, 1080

# Colors
BG    = (6,   9,  26)   # #06091a
GRID  = (18,  40, 60)   # dim grid line
GLOW  = (22, 100, 150)  # brighter grid line
DOT   = (34, 170, 204)  # #22aacc accent dots
TRACE = (51, 221, 255)  # #33ddff energy trace

def lerp_color(c1, c2, t):
    return tuple(int(a + (b-a)*t) for a,b in zip(c1, c2))

# Build pixel buffer
pixels = bytearray(W * H * 3)

def px(x, y, r, g, b):
    i = (y * W + x) * 3
    pixels[i]   = max(0, min(255, r))
    pixels[i+1] = max(0, min(255, g))
    pixels[i+2] = max(0, min(255, b))

def blend_px(x, y, r, g, b, alpha=1.0):
    i = (y * W + x) * 3
    pixels[i]   = int(pixels[i]   * (1-alpha) + r * alpha)
    pixels[i+1] = int(pixels[i+1] * (1-alpha) + g * alpha)
    pixels[i+2] = int(pixels[i+2] * (1-alpha) + b * alpha)

# Fill background
for y in range(H):
    for x in range(W):
        # Subtle radial gradient — brighter center
        cx = (x - W/2) / (W/2)
        cy = (y - H/2) / (H/2)
        d = math.sqrt(cx*cx + cy*cy)
        t = max(0, 1 - d * 0.8)
        r = int(BG[0] + t * 8)
        g = int(BG[1] + t * 12)
        b = int(BG[2] + t * 20)
        px(x, y, r, g, b)

# TRON grid — horizontal lines
GRID_SPACING = 60
random.seed(42)

for y in range(0, H, GRID_SPACING):
    # Alternate dim / bright lines
    bright = (y // GRID_SPACING) % 3 == 0
    c = GLOW if bright else GRID
    alpha = 0.7 if bright else 0.4
    for x in range(W):
        blend_px(x, y, *c, alpha)

# TRON grid — vertical lines
for x in range(0, W, GRID_SPACING):
    bright = (x // GRID_SPACING) % 3 == 0
    c = GLOW if bright else GRID
    alpha = 0.7 if bright else 0.4
    for y in range(H):
        blend_px(x, y, *c, alpha)

# Intersection dots at grid crossings
for gy in range(0, H, GRID_SPACING):
    for gx in range(0, W, GRID_SPACING):
        bright = (gx // GRID_SPACING + gy // GRID_SPACING) % 5 == 0
        c = DOT if bright else GLOW
        a = 1.0 if bright else 0.5
        blend_px(gx, gy, *c, a)
        if bright:
            # Small glow cross
            for d in range(1, 4):
                da = max(0, a - d * 0.25)
                if gx+d < W:  blend_px(gx+d, gy, *c, da)
                if gx-d >= 0: blend_px(gx-d, gy, *c, da)
                if gy+d < H:  blend_px(gx, gy+d, *c, da)
                if gy-d >= 0: blend_px(gx, gy-d, *c, da)

# Energy traces — random horizontal lines that glow
trace_ys = random.sample(range(0, H, GRID_SPACING), min(8, H//GRID_SPACING))
for ty in trace_ys:
    # Random segment
    x1 = random.randrange(0, W//2)
    x2 = random.randrange(W//2, W)
    length = x2 - x1
    for x in range(x1, x2):
        t = (x - x1) / length
        # Fade in/out at edges
        edge = math.sin(t * math.pi)
        a = edge * 0.9
        # Thicker = 3 pixels
        for dy in range(-1, 2):
            ny = ty + dy
            if 0 <= ny < H:
                line_a = a * (0.4 if dy != 0 else 1.0)
                blend_px(x, ny, *TRACE, line_a)

# Encode as PNG
def make_png(w, h, pixels_rgb):
    def chunk(name, data):
        c = name + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)  # 8-bit RGB
    ihdr = chunk(b'IHDR', header)

    raw = bytearray()
    for y in range(h):
        raw += b'\x00'  # filter type None
        raw += pixels_rgb[y*w*3 : (y+1)*w*3]

    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    iend = chunk(b'IEND', b'')

    return b'\x89PNG\r\n\x1a\n' + ihdr + idat + iend

print("Generating 1920×1080 TRON background...")
png_data = make_png(W, H, pixels)
with open('background.png', 'wb') as f:
    f.write(png_data)
print(f"Done: background.png ({len(png_data)//1024} KB)")
