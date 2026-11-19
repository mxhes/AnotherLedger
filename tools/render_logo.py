"""Draws the LootLedger logo (leather ledger book with the LL coin).

Writes LootLedger/Media/Logo.tga (64 x 64, the in-game icon) and docs/logo.png
(512 x 512). Run from the repo root: python tools/render_logo.py (Pillow only).
The shapes use a 64 x 64 grid drawn 16 times larger, then scaled down. Light
comes from the top left. The grain uses a fixed seed, so a run gives the same
images again.
"""
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 16  # supersampling
GRID = 64
W = GRID * S

COVER = (150, 80, 40)       # leather before grain and light
PAGE_LIGHT = (246, 235, 203)
PAGE_DARK = (205, 185, 138)
PAGE_LINE = (176, 156, 112)
STITCH = (215, 167, 106)
STITCH_SHADOW = (58, 28, 11)


def u(v):
    return round(v * S)


def box(x0, y0, x1, y1):
    return [u(x0), u(y0), u(x1) - 1, u(y1) - 1]


def circle(cx, cy, r):
    return box(cx - r, cy - r, cx + r, cy + r)


def solid(rgb):
    return Image.new("RGB", (W, W), rgb)


def mask(draw_fn):
    m = Image.new("L", (W, W), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def rrect(x0, y0, x1, y1, r):
    return mask(lambda d: d.rounded_rectangle(box(x0, y0, x1, y1), radius=u(r), fill=255))


def disc(cx, cy, r):
    return mask(lambda d: d.ellipse(circle(cx, cy, r), fill=255))


def shift(m, dx, dy):
    return ImageChops.offset(m, u(dx), u(dy))


def clip(m, *others):
    for o in others:
        m = ImageChops.multiply(m, o)
    return m


def fade(m, alpha):
    return m.point(lambda v: v * alpha // 255)


def grad(x0, y0, x1, y1, c0, c1, angle):
    """Linear gradient from c0 to c1 across the box; angle 0 runs top to
    bottom, 90 left to right, 45 top left to bottom right."""
    w, h = u(x1) - u(x0), u(y1) - u(y0)
    side = 2 * max(w, h)
    g = Image.linear_gradient("L").resize((side, side), Image.BICUBIC)
    g = g.rotate(angle, resample=Image.BICUBIC)
    g = g.crop(((side - w) // 2, (side - h) // 2, (side + w) // 2, (side + h) // 2))
    color = Image.composite(Image.new("RGB", (w, h), c1), Image.new("RGB", (w, h), c0), g)
    full = solid(c0)
    full.paste(color, (u(x0), u(y0)))
    return full


def gray(v):
    return (v, v, v)


def noise(cells, sigma):
    """Gray noise around 128, `cells` per side, smoothly scaled up."""
    return Image.effect_noise((cells, cells), sigma).resize((W, W), Image.BICUBIC)


def to_range(m, lo, hi):
    return m.point(lambda v: lo + v * (hi - lo) // 255)


def put(canvas, img, m):
    canvas.paste(img, (0, 0), m)


def letters(dx=0.0, dy=0.0):
    """The two L's on the coin as a mask."""
    def draw(d):
        for x in (28.8, 34.8):
            d.rectangle(box(x - 1.2 + dx, 25.3 + dy, x + 1.2 + dx, 36.7 + dy), fill=255)
            d.rectangle(box(x - 1.2 + dx, 34.3 + dy, x + 3.6 + dx, 36.7 + dy), fill=255)
    return mask(draw)


def stitches(d, x0, y0, x1, y1, color, width, dash=1.4, gap=0.9):
    """Dashed seam along a rectangle."""
    edges = [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))]
    for (ax, ay), (bx, by) in edges:
        length = abs(bx - ax) + abs(by - ay)
        sx, sy = (bx - ax) / length, (by - ay) / length
        t = gap / 2
        while t + dash <= length:
            p0 = (u(ax + sx * t), u(ay + sy * t))
            p1 = (u(ax + sx * (t + dash)), u(ay + sy * (t + dash)))
            d.line([p0, p1], fill=color, width=u(width))
            t += dash + gap


def draw():
    random.seed(7)
    canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    # Tile: beveled bronze edge around a dark inset.
    tile = rrect(0, 0, 64, 64, 9)
    inner = rrect(2, 2, 62, 62, 7)
    put(canvas, grad(0, 0, 64, 64, (200, 158, 86), (74, 52, 22), 45), tile)
    put(canvas, grad(2, 2, 62, 62, (44, 31, 21), (14, 9, 6), 0), inner)

    pages = rrect(15, 9, 52, 56, 3)
    cover = rrect(11, 7, 48, 55, 3)

    # The book's shadow on the tile.
    shadow = ImageChops.lighter(pages, cover)
    shadow = shift(shadow, 1.2, 1.8).filter(ImageFilter.GaussianBlur(u(1.5)))
    put(canvas, solid((0, 0, 0)), clip(fade(shadow, 180), inner))

    # Pages: cream block with thin page lines on the fore edge and the bottom.
    put(canvas, grad(15, 9, 52, 56, PAGE_LIGHT, PAGE_DARK, 45), pages)
    d = ImageDraw.Draw(canvas)
    x = 48.7
    while x < 51.6:
        d.line([(u(x), u(10.5)), (u(x), u(54.5))], fill=PAGE_LINE, width=max(1, u(0.22)))
        x += 0.75
    d.line([(u(16), u(55.6)), (u(50.5), u(55.6))], fill=PAGE_LINE, width=max(1, u(0.22)))
    # The cover's shadow on the pages.
    cover_shadow = shift(cover, 0.9, 0.6).filter(ImageFilter.GaussianBlur(u(0.8)))
    put(canvas, solid((60, 40, 20)), clip(fade(cover_shadow, 150), pages))

    # Leather: grain (blotches plus fine pores), light from the top left and
    # darker edges where the cover curves away.
    grain = ImageChops.add(noise(48, 70), noise(220, 60), scale=2.0)
    leather = ImageChops.multiply(solid(COVER), to_range(grain, 196, 255).convert("RGB"))
    leather = ImageChops.multiply(leather, grad(11, 7, 48, 55, gray(255), gray(170), 45))
    edge = cover.filter(ImageFilter.GaussianBlur(u(1.3)))
    leather = ImageChops.multiply(leather, to_range(edge, 120, 255).convert("RGB"))
    put(canvas, leather, cover)

    # Spine: darker and rounded, two raised bands, a groove at the hinge.
    spine = clip(mask(lambda m: m.rectangle(box(11, 7, 18, 55), fill=255)), cover)
    spine_color = ImageChops.multiply(leather, grad(11, 7, 18, 55, gray(150), gray(205), 90))
    put(canvas, spine_color, spine)
    d = ImageDraw.Draw(canvas)
    for y in (13.0, 48.0):
        d.rectangle(box(11.4, y, 17.8, y + 0.6), fill=(150, 88, 50))
        d.rectangle(box(11.4, y + 0.6, 17.8, y + 1.3), fill=(40, 19, 8))
    d.rectangle(box(17.8, 7.4, 18.4, 54.6), fill=(36, 17, 7))
    d.rectangle(box(18.4, 7.4, 18.8, 54.6), fill=(140, 80, 44))

    # Stitched seam around the front of the cover.
    stitches(d, 21.25, 10.25, 45.25, 52.25, STITCH_SHADOW, 0.55)
    stitches(d, 21, 10, 45, 52, STITCH, 0.5)

    # Brass corner caps on the front corners.
    caps = mask(lambda m: (m.polygon([(u(41), u(7)), (u(48), u(7)), (u(48), u(14))], fill=255),
                           m.polygon([(u(48), u(48)), (u(48), u(55)), (u(41), u(55))], fill=255)))
    caps = clip(caps, cover)
    put(canvas, grad(41, 7, 48, 55, (236, 196, 104), (120, 82, 26), 45), caps)
    caps_edge = ImageChops.subtract(caps, caps.filter(ImageFilter.MinFilter(7)))
    put(canvas, solid((92, 60, 18)), fade(caps_edge, 200))

    # Coin: its shadow, a beveled rim, the face and the stamped LL.
    coin_shadow = disc(34.2, 32.6, 11).filter(ImageFilter.GaussianBlur(u(1.0)))
    put(canvas, solid((20, 8, 2)), clip(fade(coin_shadow, 170), cover))
    put(canvas, grad(22, 20, 44, 42, (255, 240, 160), (128, 82, 0), 45), disc(33, 31, 11))
    put(canvas, grad(23, 21, 43, 41, (150, 100, 0), (255, 226, 110), 45), disc(33, 31, 9.7))
    face = disc(33, 31, 9)
    face_color = grad(24, 22, 42, 40, (255, 226, 80), (214, 156, 0), 45)
    face_color = ImageChops.multiply(face_color, to_range(noise(160, 40), 225, 255).convert("RGB"))
    put(canvas, face_color, face)
    # Stamped letters: a light lip on the lower right, dark inside.
    put(canvas, solid((255, 240, 150)), clip(letters(0.4, 0.4), face))
    put(canvas, grad(27, 25, 39, 37, (70, 44, 0), (110, 72, 0), 45), letters())
    # Shine on the upper left of the face.
    shine = mask(lambda m: m.ellipse(box(26, 23.5, 33, 28), fill=255))
    shine = shine.filter(ImageFilter.GaussianBlur(u(1.2)))
    put(canvas, solid((255, 255, 230)), clip(fade(shine, 110), face, ImageChops.invert(letters())))

    return canvas


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    big = draw()
    media = os.path.join(root, "LootLedger", "Media")
    os.makedirs(media, exist_ok=True)
    # Uncompressed 32-bit TGA, bottom-left origin (the classic layout).
    big.resize((64, 64), Image.LANCZOS).save(
        os.path.join(media, "Logo.tga"), compression=None, orientation=-1)
    big.resize((512, 512), Image.LANCZOS).save(os.path.join(root, "docs", "logo.png"))


if __name__ == "__main__":
    main()
