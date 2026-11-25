"""Draws the navigation rail's icons in Media/ (run from the repo root: python tools/make_icons.py).
Needs Pillow. White on transparent, 64x64; the game tints them (muted, or the accent when active).

  nav_quests.tga   a list: three bullets and lines
  nav_chains.tga   two linked chain rings
  nav_class.tga    a shield
  nav_search.tga   a magnifying glass
"""
import os
from PIL import Image, ImageDraw

SIZE, SS = 64, 4
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")
W = (255, 255, 255, 255)


def canvas():
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (255, 255, 255, 0))
    return img, ImageDraw.Draw(img)


def s(v):
    return int(v * SS)


def save(img, name):
    img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name))
    print("wrote", name)


def quests():
    img, d = canvas()
    for i, y in enumerate((18, 32, 46)):
        d.ellipse((s(10), s(y - 4), s(18), s(y + 4)), fill=W)
        d.rounded_rectangle((s(24), s(y - 3), s(54), s(y + 3)), radius=s(3), fill=W)
    save(img, "nav_quests.tga")


def chains():
    img, d = canvas()
    # two rounded links, one rising left to right, overlapping in the middle
    d.rounded_rectangle((s(6), s(26), s(36), s(46)), radius=s(10), outline=W, width=s(5))
    d.rounded_rectangle((s(28), s(18), s(58), s(38)), radius=s(10), outline=W, width=s(5))
    save(img, "nav_chains.tga")


def shield():
    img, d = canvas()
    outline = [(32, 6), (54, 14), (52, 36), (44, 49), (32, 58), (20, 49), (12, 36), (10, 14)]
    d.polygon([(s(x), s(y)) for x, y in outline], fill=W)
    # a cut-out band so it reads as a crest
    inner = [(32, 14), (46, 19), (45, 34), (32, 49), (32, 14)]
    d.polygon([(s(x), s(y)) for x, y in inner], fill=(255, 255, 255, 110))
    save(img, "nav_class.tga")


def search():
    img, d = canvas()
    d.ellipse((s(8), s(8), s(40), s(40)), outline=W, width=s(6))
    d.line((s(36), s(36), s(55), s(55)), fill=W, width=s(8))
    d.ellipse((s(51), s(51), s(59), s(59)), fill=W)
    save(img, "nav_search.tga")


def disc():
    """A filled circle: route stop badges, the player's dot, the flowing lights."""
    img, d = canvas()
    d.ellipse((s(2), s(2), s(62), s(62)), fill=W)
    save(img, "disc.tga")


def ring():
    """A circle outline round a stop badge."""
    img, d = canvas()
    d.ellipse((s(3), s(3), s(61), s(61)), outline=W, width=s(5))
    save(img, "ring.tga")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    quests()
    chains()
    shield()
    search()
    disc()
    ring()
