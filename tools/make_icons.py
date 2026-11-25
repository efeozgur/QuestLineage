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


# --- service icons for the "Where?" quick bar (svc_*.tga) ----------------------------------------

def poly(d, pts, fill=W):
    d.polygon([(s(x), s(y)) for x, y in pts], fill=fill)


def svc(name, draw):
    img, d = canvas()
    draw(d)
    save(img, "svc_%s.tga" % name)


def repair(d):  # hammer over an anvil
    poly(d, [(8, 40), (56, 40), (50, 48), (40, 48), (44, 56), (20, 56), (24, 48), (14, 48)])
    d.line((s(20), s(32), s(44), s(8)), fill=W, width=s(6))
    d.rounded_rectangle((s(36), s(4), s(56), s(16)), radius=s(2), fill=W)


def inn(d):  # a bed
    d.rounded_rectangle((s(6), s(30), s(58), s(44)), radius=s(3), fill=W)
    d.rounded_rectangle((s(8), s(20), s(24), s(30)), radius=s(4), fill=W)
    d.rectangle((s(6), s(16), s(11), s(54)), fill=W)
    d.rectangle((s(53), s(36), s(58), s(54)), fill=W)


def flight(d):  # two wings
    poly(d, [(32, 34), (4, 18), (10, 30), (6, 34), (14, 40), (12, 46), (28, 44)])
    poly(d, [(32, 34), (60, 18), (54, 30), (58, 34), (50, 40), (52, 46), (36, 44)])
    d.ellipse((s(27), s(30), s(37), s(46)), fill=W)


def book(d):  # an open book (professions)
    poly(d, [(31, 14), (6, 10), (6, 50), (31, 54)])
    poly(d, [(33, 14), (58, 10), (58, 50), (33, 54)])


def food(d):  # a mug
    d.rounded_rectangle((s(10), s(14), s(42), s(56)), radius=s(5), fill=W)
    d.rounded_rectangle((s(38), s(22), s(56), s(46)), radius=s(9), outline=W, width=s(5))
    d.rectangle((s(16), s(20), s(36), s(26)), fill=(255, 255, 255, 110))


def mail(d):  # an envelope
    d.rounded_rectangle((s(6), s(14), s(58), s(50)), radius=s(4), fill=W)
    d.line((s(8), s(17), s(32), s(36), s(56), s(17)), fill=(0, 0, 0, 0), width=s(5))


def more(d):  # three dots
    for x in (14, 32, 50):
        d.ellipse((s(x - 6), s(26), s(x + 6), s(38)), fill=W)


def bank(d):  # a coin
    d.ellipse((s(8), s(8), s(56), s(56)), fill=W)
    d.ellipse((s(18), s(18), s(46), s(46)), outline=(0, 0, 0, 0), width=s(4))


def auction(d):  # a gavel
    d.line((s(14), s(50), s(38), s(26)), fill=W, width=s(6))
    poly(d, [(30, 10), (48, 28), (40, 36), (22, 18)])
    d.rounded_rectangle((s(8), s(52), s(36), s(58)), radius=s(2), fill=W)


def stable(d):  # a horseshoe
    d.arc((s(10), s(8), s(54), s(52)), 140, 400, fill=W, width=s(9))


def reagent(d):  # a flask
    poly(d, [(26, 8), (38, 8), (38, 24), (54, 52), (50, 58), (14, 58), (10, 52), (26, 24)])


def trade(d):  # a crate
    d.rectangle((s(8), s(16), s(56), s(54)), fill=W)
    d.line((s(8), s(16), s(56), s(54)), fill=(0, 0, 0, 0), width=s(4))
    d.line((s(56), s(16), s(8), s(54)), fill=(0, 0, 0, 0), width=s(4))


def weapon(d):  # a sword
    poly(d, [(32, 4), (38, 12), (36, 40), (28, 40), (26, 12)])
    d.rectangle((s(18), s(40), s(46), s(45)), fill=W)
    d.rectangle((s(29), s(45), s(35), s(56)), fill=W)
    d.ellipse((s(27), s(55), s(37), s(61)), fill=W)


def armor(d):  # a breastplate
    poly(d, [(12, 10), (24, 6), (32, 12), (40, 6), (52, 10), (54, 30), (46, 56), (18, 56), (10, 30)])


def ammo(d):  # an arrow
    d.line((s(10), s(54), s(48), s(16)), fill=W, width=s(5))
    poly(d, [(56, 8), (40, 14), (50, 24)])
    poly(d, [(10, 54), (8, 42), (14, 46)])
    poly(d, [(10, 54), (22, 56), (18, 50)])


def general(d):  # a bag
    d.rounded_rectangle((s(10), s(22), s(54), s(58)), radius=s(10), fill=W)
    d.arc((s(20), s(8), s(44), s(32)), 180, 360, fill=W, width=s(5))


def spirit(d):  # an ankh
    d.ellipse((s(20), s(4), s(44), s(30)), outline=W, width=s(6))
    d.rectangle((s(29), s(28), s(35), s(60)), fill=W)
    d.rectangle((s(16), s(32), s(48), s(38)), fill=W)


def weaponmaster(d):  # crossed swords
    for flip in (False, True):
        a = (14, 50, 46, 14) if not flip else (50, 50, 18, 14)
        d.line((s(a[0]), s(a[1]), s(a[2]), s(a[3])), fill=W, width=s(5))
    d.rectangle((s(12), s(44), s(24), s(48)), fill=W)
    d.rectangle((s(40), s(44), s(52), s(48)), fill=W)


def riding(d):  # a saddle-ish horse head
    poly(d, [(20, 58), (22, 34), (16, 26), (24, 10), (34, 6), (50, 18), (54, 28), (46, 30), (40, 24), (38, 40), (44, 58)])


SERVICES = {
    "repair": repair, "inn": inn, "flight": flight, "book": book, "food": food, "mail": mail,
    "more": more, "bank": bank, "auction": auction, "stable": stable, "reagent": reagent,
    "trade": trade, "weapon": weapon, "armor": armor, "ammo": ammo, "general": general,
    "spirit": spirit, "weaponmaster": weaponmaster, "riding": riding,
}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    quests()
    chains()
    shield()
    search()
    disc()
    ring()
    for name, draw in SERVICES.items():
        svc(name, draw)
