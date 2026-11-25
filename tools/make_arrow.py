"""Draws the arrow textures in Media/ (run from the repo root: python tools/make_arrow.py).
Needs Pillow. Every texture is white so the game can tint it with SetVertexColor.

  arrow.tga        the arrowhead, pointing up (the game rotates it with SetRotation)
  arrow_shade.tga  the right-hand facet of the arrowhead, a translucent shadow laid over it
                   and rotated with it, so the arrow reads as a folded, lit shape
  arrow_glow.tga   a soft round glow behind the arrow
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 128
SS = 4  # supersampling for smooth edges
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")
os.makedirs(OUT, exist_ok=True)

TIP, RIGHT, NOTCH, LEFT = (64, 10), (106, 112), (64, 90), (22, 112)


def scaled(points):
    return [(x * SS, y * SS) for x, y in points]


def save(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("wrote", name)


def arrow():
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    d.polygon(scaled([TIP, RIGHT, NOTCH, LEFT]), fill=(255, 255, 255, 255))
    save(img, "arrow.tga")


def shade():
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon(scaled([TIP, RIGHT, NOTCH]), fill=(0, 0, 0, 105))
    save(img, "arrow_shade.tga")


def glow():
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    c = SIZE * SS // 2
    r = int(SIZE * SS * 0.30)
    d.ellipse((c - r, c - r, c + r, c + r), fill=(255, 255, 255, 255))
    img = img.filter(ImageFilter.GaussianBlur(SIZE * SS * 0.09))
    save(img, "arrow_glow.tga")


if __name__ == "__main__":
    arrow()
    shade()
    glow()
