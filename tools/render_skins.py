"""Draws the skin textures of AnotherLedger (Theme.textures.skin*).

Writes into AnotherLedger/Media/Skins/ (uncompressed 32-bit TGA, bottom-left
origin, like the logo):

  Dotted.tga     8 x 2    a dash: x 0..3 white, 4..7 transparent (Lines: Dotted)

Planned, not in the addon yet (written only with --backgrounds DIR):

  Grain.tga    512 x 512  fine cast grain: relief, pits and light flecks
  Leather.tga  512 x 512  pebble-grain leather: pebbles, creases, pores, wrinkles

Plan for them: a 256 UI unit tile (one unit holds two texels, a leather
pebble is about two units). They are height fields lit from the top left;
every noise wraps on the tile, so they tile seamlessly. Tinting multiplies
and only darkens, so the window is to paint a textured background LIFT times
brighter than the panel color; the textures average 1 / LIFT, so the panel
keeps its color on average and the relief gets highlights above it.

All are grey-scale: the game tints them with the theme colors (vertex color
multiplies). Fixed seed: a run gives the same files again (pure Python;
~6 s with --backgrounds).
Run from the repo root: python tools/render_skins.py (Pillow only).
Optional: --preview DIR also writes enlarged PNG previews there.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SEED = 1609
SIZE = 512  # backgrounds: twice the planned 256 unit tile (two texels per UI unit)
K = SIZE // 256  # the noise scales below are per 256 texels
LIFT = 2.2  # planned tint lift of a textured background


def save_tga(img, path):
    img.convert("RGBA").save(path, compression=None, orientation=-1)


# --- fields: flat lists of floats, row-major, SIZE x SIZE -------------------

def wrap_blur(field, radius):
    """Gaussian blur that wraps around the edges, so the tile stays seamless."""
    lo, hi = min(field), max(field)
    span = (hi - lo) or 1.0
    img = Image.new("L", (SIZE, SIZE))
    img.putdata([int((v - lo) / span * 255 + 0.5) for v in field])
    big = Image.new("L", (SIZE * 3, SIZE * 3))
    for dx in range(3):
        for dy in range(3):
            big.paste(img, (dx * SIZE, dy * SIZE))
    big = big.filter(ImageFilter.GaussianBlur(radius)).crop((SIZE, SIZE, 2 * SIZE, 2 * SIZE))
    return [lo + v / 255.0 * span for v in big.getdata()]


def smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(rng, period, sy=1.0):
    """Periodic value noise on a period x (period * sy) lattice over the tile."""
    px, py = max(1, int(period)), max(1, int(period * sy))
    lat = [[rng.random() for _ in range(px)] for _ in range(py)]
    out = []
    for y in range(SIZE):
        fy = y * py / SIZE
        iy = int(fy)
        ty = smooth(fy - iy)
        r0, r1 = lat[iy % py], lat[(iy + 1) % py]
        for x in range(SIZE):
            fx = x * px / SIZE
            ix = int(fx)
            tx = smooth(fx - ix)
            a = r0[ix % px] + (r0[(ix + 1) % px] - r0[ix % px]) * tx
            b = r1[ix % px] + (r1[(ix + 1) % px] - r1[ix % px]) * tx
            out.append(a + (b - a) * ty)
    return out


def fbm(rng, base, octaves, gain=0.5, sy=1.0):
    """Octaves of value noise, each twice as fine; 0..1."""
    total = [0.0] * (SIZE * SIZE)
    amp, period, norm = 1.0, base, 0.0
    for _ in range(octaves):
        for i, v in enumerate(value_noise(rng, period, sy)):
            total[i] += v * amp
        norm += amp
        amp *= gain
        period *= 2
    return [v / norm for v in total]


def cell_edges(rng, cells, warp, warp_amt):
    """Tileable cellular noise: per pixel the distance (px) to the nearest
    cell border (F2 - F1), the lookup warped by `warp` so cells are irregular."""
    cs = SIZE / cells
    pts = [[((cx + 0.5 + (rng.random() - 0.5) * 0.9) * cs, (cy + 0.5 + (rng.random() - 0.5) * 0.9) * cs)
            for cx in range(cells)] for cy in range(cells)]
    out = []
    for y in range(SIZE):
        for x in range(SIZE):
            i = y * SIZE + x
            qx = x + (warp[0][i] - 0.5) * warp_amt
            qy = y + (warp[1][i] - 0.5) * warp_amt
            cx, cy = int(qx // cs), int(qy // cs)
            d1 = d2 = 1e9
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    gx, gy = cx + ox, cy + oy
                    p = pts[gy % cells][gx % cells]
                    d = math.hypot(qx - p[0] - (gx - gx % cells) * cs, qy - p[1] - (gy - gy % cells) * cs)
                    if d < d1:
                        d1, d2 = d, d1
                    elif d < d2:
                        d2 = d
            out.append(d2 - d1)
    return out


def specks(rng, count, radius, lo=1.0, hi=1.0):
    """`count` single-pixel dots blurred to soft specks; 0..1."""
    f = [0.0] * (SIZE * SIZE)
    for _ in range(count):
        f[rng.randrange(SIZE) * SIZE + rng.randrange(SIZE)] = rng.uniform(lo, hi)
    f = wrap_blur(f, radius)
    top = max(f) or 1.0
    return [v / top for v in f]


def shade(height, strength):
    """Lambert shading of a height field (wraps), light from the top left."""
    lx, ly, lz = -1.0, -1.2, 1.0
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ln, ly / ln, lz / ln
    out = []
    for y in range(SIZE):
        up, dn, row = ((y - 1) % SIZE) * SIZE, ((y + 1) % SIZE) * SIZE, y * SIZE
        for x in range(SIZE):
            dx = (height[row + (x + 1) % SIZE] - height[row + (x - 1) % SIZE]) * strength
            dy = (height[dn + x] - height[up + x]) * strength
            nn = math.sqrt(dx * dx + dy * dy + 1.0)
            out.append(max(0.0, (-dx * lx - dy * ly + lz) / nn))
    return out


def tone_map(field, lo, hi):
    """Stretches `field` (0.5 / 99.5 percentiles) onto the grey levels lo..hi
    and bends it (gamma) so the mean is 255 / LIFT. An opaque RGBA image."""
    s = sorted(field)
    a, b = s[len(s) // 200], s[len(s) - len(s) // 200 - 1]
    span = (b - a) or 1.0
    f = [max(0.0, min(1.0, (v - a) / span)) for v in field]
    want = (255.0 / LIFT - lo) / (hi - lo)
    g_lo, g_hi = 0.2, 5.0
    for _ in range(30):
        g = (g_lo + g_hi) / 2
        if sum(v ** g for v in f) / len(f) > want:
            g_lo = g
        else:
            g_hi = g
    g = (g_lo + g_hi) / 2
    img = Image.new("L", (SIZE, SIZE))
    img.putdata([int(lo + (v ** g) * (hi - lo) + 0.5) for v in f])
    return Image.merge("RGBA", (img, img, img, Image.new("L", (SIZE, SIZE), 255)))


# --- the textures -----------------------------------------------------------

def grain(rng):
    """Fine cast grain (Forge): multi-scale relief with little pits, a soft
    cloudy tone and a few light flecks that catch the light."""
    fine = wrap_blur([rng.random() for _ in range(SIZE * SIZE)], 0.5)
    mid = fbm(rng, 128 * K, 1)
    low = fbm(rng, 16 * K, 4, gain=0.55)
    pits = specks(rng, 1200 * K * K, 0.5)
    height = [0.5 * f + 0.4 * m + 0.6 * l - 0.9 * p for f, m, l, p in zip(fine, mid, low, pits)]
    lit = shade(height, 3.0)
    flecks = specks(rng, 900 * K * K, 0.45, 0.5, 1.0)
    out = [(0.75 + 0.30 * (l - 0.5)) * (0.4 + 0.75 * s) + 0.35 * fl for l, s, fl in zip(low, lit, flecks)]
    return tone_map(out, 55, 215)


def leather(rng):
    """Pebble-grain leather: rounded pebbles split by creases with a
    little grime, finer pebbles between, pores, long shallow wrinkles, soft
    mottling and a faint sheen on the pebble tops."""
    warp = (fbm(rng, 4 * K, 3), fbm(rng, 4 * K, 3))
    big = cell_edges(rng, 64 * K, warp, 3.0)
    small = cell_edges(rng, 128 * K, warp, 1.5)

    def dome(e, w):  # rises from the crease, flat on top
        t = min(1.0, e / w)
        return math.sqrt(t * (2 - t))

    peb = [0.75 * dome(a, 1.8) + 0.25 * dome(b, 0.9) for a, b in zip(big, small)]
    wrinkles = [1.0 - min(1.0, abs(v - 0.5) * 14.0) for v in fbm(rng, 10 * K, 4, sy=2.0)]
    pores = specks(rng, 2400 * K * K, 0.45, 0.6, 1.0)
    height = [p - 0.35 * w - 0.5 * q for p, w, q in zip(peb, wrinkles, pores)]
    lit = shade(height, 1.5)
    mottle = fbm(rng, 6 * K, 4, gain=0.55)
    fine = fbm(rng, 128 * K, 1)
    out = []
    for i in range(SIZE * SIZE):
        albedo = 0.80 + 0.32 * (mottle[i] - 0.5) + 0.06 * (fine[i] - 0.5)
        grime = 0.80 + 0.20 * dome(big[i], 0.9)
        out.append(albedo * grime * (0.45 + 0.65 * lit[i]) + 0.10 * lit[i] ** 12 * peb[i])
    return tone_map(out, 40, 225)


def dotted():
    img = Image.new("RGBA", (8, 2), (255, 255, 255, 0))
    for x in range(4):
        for y in range(2):
            img.putpixel((x, y), (255, 255, 255, 255))
    return img


ROUND_CELL = 16  # one tile of the backdrop edge strip
ROUND_INNER = 14  # the part of a tile the game samples (texels 1..14)
ROUND_RADIUS = 7.0  # corner radius in texels (edgeSize 8 -> 4 UI units)
ROUND_LINE = 2.0  # line width in texels (about 1 UI unit)


def rounded():
    """Backdrop edge file of the Modern border (Border: Rounded).

    128 x 16: eight 16 x 16 tiles left, right, top, bottom, top-left,
    top-right, bottom-left, bottom-right; the game samples texels 1..14 of
    each. Top and bottom are drawn rotated (screen top = the tile's left
    column, screen bottom = its right column), so top looks like left and
    bottom like right. White, tinted with the border color in the game.
    """
    img = Image.new("RGBA", (8 * ROUND_CELL, ROUND_CELL), (255, 255, 255, 0))
    px = img.load()
    n, r, t = ROUND_INNER, ROUND_RADIUS, ROUND_LINE
    sub = 4  # supersampling per axis

    def coverage(x, y, flip_x, flip_y, corner):
        hits = 0
        for i in range(sub):
            for j in range(sub):
                u = x + (i + 0.5) / sub
                v = y + (j + 0.5) / sub
                if flip_x:
                    u = n - u
                if flip_y:
                    v = n - v
                if corner:
                    dx, dy = max(r - u, 0.0), max(r - v, 0.0)
                    d = math.hypot(dx, dy)
                    inside = d <= r and (dx > 0 or dy > 0 or True)
                    # distance from the outer edge, measured along the arc
                    edge = r - d if (dx > 0 and dy > 0) else min(u, v)
                    if inside and edge < t:
                        hits += 1
                elif u < t:
                    hits += 1
        return hits / (sub * sub)

    # tile index -> (flip_x, flip_y, corner)
    tiles = {
        0: (False, False, False),  # left: line at the left column
        1: (True, False, False),   # right: line at the right column
        2: (False, False, False),  # top (rotated): like left
        3: (True, False, False),   # bottom (rotated): like right
        4: (False, False, True),   # top-left
        5: (True, False, True),    # top-right
        6: (False, True, True),    # bottom-left
        7: (True, True, True),     # bottom-right
    }
    for tile, (fx, fy, corner) in tiles.items():
        inner = Image.new("L", (n, n), 0)
        ip = inner.load()
        for y in range(n):
            for x in range(n):
                ip[x, y] = int(coverage(x, y, fx, fy, corner) * 255 + 0.5)
        # The 14 x 14 tile at texel 1, its border texels repeated (filtering).
        padded = inner.resize((n, n))
        cell = Image.new("L", (ROUND_CELL, ROUND_CELL), 0)
        cell.paste(padded, (1, 1))
        for k in range(ROUND_CELL):
            cell.putpixel((0, k), cell.getpixel((1, min(max(k, 1), n))))
            cell.putpixel((ROUND_CELL - 1, k), cell.getpixel((n, min(max(k, 1), n))))
        for k in range(ROUND_CELL):
            cell.putpixel((k, 0), cell.getpixel((k, 1)))
            cell.putpixel((k, ROUND_CELL - 1), cell.getpixel((k, n)))
        cp = cell.load()
        for y in range(ROUND_CELL):
            for x in range(ROUND_CELL):
                px[tile * ROUND_CELL + x, y] = (255, 255, 255, cp[x, y])
    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "AnotherLedger", "Media", "Skins")
    os.makedirs(out, exist_ok=True)
    images = {"Dotted": dotted(), "Rounded": rounded()}
    for name, img in images.items():
        save_tga(img, os.path.join(out, name + ".tga"))
    if "--backgrounds" in sys.argv:
        where = sys.argv[sys.argv.index("--backgrounds") + 1]
        os.makedirs(where, exist_ok=True)
        planned = {"Grain": grain(random.Random(SEED)), "Leather": leather(random.Random(SEED))}
        for name, img in planned.items():
            save_tga(img, os.path.join(where, name + ".tga"))
        images.update(planned)
    if "--preview" in sys.argv:
        where = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(where, exist_ok=True)
        for name, img in images.items():
            w, h = img.size
            scale = max(1, 256 // max(w, h))
            img.resize((w * scale, h * scale), Image.NEAREST).save(os.path.join(where, name + ".png"))


if __name__ == "__main__":
    main()
