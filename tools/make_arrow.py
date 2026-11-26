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
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")
os.makedirs(OUT, exist_ok=True)

TIP, RIGHT, NOTCH, LEFT = (64, 4), (99, 116), (64, 95), (29, 116)
SS = 8  # finer supersampling: the corners are rounded by blurring and cutting the mask
ROUND = 3.2  # corner radius in output pixels


def scaled(points):
    return [(x * SS, y * SS) for x, y in points]


def save(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("wrote", name)


def rounded_mask():
    """The slim arrowhead with softly rounded corners, as an 'L' mask at supersampled size."""
    m = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    ImageDraw.Draw(m).polygon(scaled([TIP, RIGHT, NOTCH, LEFT]), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(ROUND * SS))
    m = m.point(lambda v: 255 if v >= 128 else 0)  # cut: convex corners come out round
    return m.filter(ImageFilter.GaussianBlur(SS * 0.4))  # a touch of edge softness


def arrow():
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (255, 255, 255, 0))
    img.putalpha(rounded_mask())
    save(img, "arrow.tga")


def shade():
    """The right-hand facet as a translucent shadow, cut to the rounded outline."""
    facet = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    ImageDraw.Draw(facet).polygon(scaled([TIP, RIGHT, NOTCH]), fill=255)
    facet = facet.filter(ImageFilter.GaussianBlur(SS * 0.5))
    alpha = Image.new("L", facet.size, 0)
    alpha.paste(facet, mask=rounded_mask())  # facet where the arrow is
    alpha = alpha.point(lambda v: int(v * 0.42))
    img = Image.new("RGBA", facet.size, (0, 0, 0, 0))
    img.putalpha(alpha)
    save(img, "arrow_shade.tga")


def glow():
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    c = SIZE * SS // 2
    r = int(SIZE * SS * 0.26)
    d.ellipse((c - r, c - r, c + r, c + r), fill=(255, 255, 255, 255))
    img = img.filter(ImageFilter.GaussianBlur(SIZE * SS * 0.09))
    save(img, "arrow_glow.tga")


if __name__ == "__main__":
    arrow()
    shade()
    glow()
