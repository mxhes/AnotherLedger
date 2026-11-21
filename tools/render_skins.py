"""Draws the skin textures of AnotherLedger (Theme.textures.skin*).

Writes into AnotherLedger/Media/Skins/ (uncompressed 32-bit TGA, bottom-left
origin, like the logo):

  Grain.tga    64 x 64  fine per-pixel noise, grey 120..255 (Background: Grain)
  Leather.tga  64 x 64  soft blotchy leather grain, grey 80..255 (Background: Leather)
  Stud.tga     16 x 16  a round bevelled stud, transparent around it (Border: Gilded)
  Dotted.tga    8 x 2   a dash: x 0..3 white, 4..7 transparent (Lines: Dotted)

All are grey-scale: the game tints them with the theme colors (vertex color
multiplies), so the lightest parts keep the color preset's own color.
(The ranges are wide on purpose: on the dark presets a narrow one did not
show in the client.) Backgrounds
tile seamlessly. Fixed seed: a run gives the same files again.
Run from the repo root: python tools/render_skins.py (Pillow only).
Optional: --preview DIR also writes enlarged PNG previews there.
"""
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SEED = 1609


def save_tga(img, path):
    img.convert("RGBA").save(path, compression=None, orientation=-1)


def grey_rgba(values, size):
    """A size x size RGBA image from a flat list of grey levels (opaque)."""
    img = Image.new("L", (size, size))
    img.putdata(values)
    return Image.merge("RGBA", (img, img, img, Image.new("L", (size, size), 255)))


def wrap_blur(img, radius):
    """Gaussian blur that wraps around the edges, so the tile stays seamless."""
    w, h = img.size
    big = Image.new(img.mode, (w * 3, h * 3))
    for dx in range(3):
        for dy in range(3):
            big.paste(img, (dx * w, dy * h))
    big = big.filter(ImageFilter.GaussianBlur(radius))
    return big.crop((w, h, 2 * w, 2 * h))


def stretch(img, lo, hi):
    """Maps the grey levels of an L image onto lo..hi."""
    data = list(img.getdata())
    a, b = min(data), max(data)
    span = max(1, b - a)
    img.putdata([lo + (v - a) * (hi - lo) // span for v in data])
    return img


def grain(rng):
    size = 64
    return grey_rgba([rng.randint(120, 255) for _ in range(size * size)], size)


def leather(rng):
    size = 64
    # Soft blotches (large blur) plus a little fine pore noise.
    blot = Image.new("L", (size, size))
    blot.putdata([rng.randint(0, 255) for _ in range(size * size)])
    blot = stretch(wrap_blur(blot, 3.0), 0, 255)
    pores = Image.new("L", (size, size))
    pores.putdata([rng.randint(0, 255) for _ in range(size * size)])
    pores = wrap_blur(pores, 0.6)
    mixed = Image.blend(blot, pores, 0.25)
    mixed = stretch(mixed, 80, 255)
    return grey_rgba(list(mixed.getdata()), size)


def stud():
    s, k = 16, 8  # drawn 8 times larger, then scaled down
    big = Image.new("RGBA", (s * k, s * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c, r = s * k / 2, s * k / 2 - k
    # Dark rim, the body, a light spot top left (light from the top left).
    d.ellipse((c - r, c - r, c + r, c + r), fill=(70, 70, 70, 255))
    r2 = r - k * 1.2
    d.ellipse((c - r2, c - r2, c + r2, c + r2), fill=(205, 205, 205, 255))
    r3 = r2 * 0.45
    hx, hy = c - r2 * 0.3, c - r2 * 0.3
    d.ellipse((hx - r3, hy - r3, hx + r3, hy + r3), fill=(255, 255, 255, 255))
    big = big.filter(ImageFilter.GaussianBlur(k * 0.35))
    return big.resize((s, s), Image.LANCZOS)


def dotted():
    img = Image.new("RGBA", (8, 2), (255, 255, 255, 0))
    for x in range(4):
        for y in range(2):
            img.putpixel((x, y), (255, 255, 255, 255))
    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "AnotherLedger", "Media", "Skins")
    os.makedirs(out, exist_ok=True)
    rng = random.Random(SEED)
    images = {
        "Grain": grain(rng),
        "Leather": leather(rng),
        "Stud": stud(),
        "Dotted": dotted(),
    }
    for name, img in images.items():
        save_tga(img, os.path.join(out, name + ".tga"))
    if "--preview" in sys.argv:
        where = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(where, exist_ok=True)
        for name, img in images.items():
            w, h = img.size
            scale = max(1, 256 // max(w, h))
            img.resize((w * scale, h * scale), Image.NEAREST).save(os.path.join(where, name + ".png"))


if __name__ == "__main__":
    main()
