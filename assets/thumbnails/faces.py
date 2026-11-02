# Cartoon thumbnail faces, painted as 1024x1024 decals (the square = the front of the head).
# Each face also paints a soft skin patch so the avatar's own face doesn't show through.
import os
from PIL import Image, ImageDraw, ImageFilter, ImageStat
HERE = os.path.dirname(os.path.abspath(__file__))
S = 1024; SS = 2  # supersample
INK = (22, 18, 30, 255); WHITE = (255, 255, 255, 255)

def skin_of(tex):
    im = Image.open(tex).convert("RGB").resize((64, 64))
    px = sorted(im.get_flattened_data() if hasattr(im,'get_flattened_data') else im.getdata(), key=lambda p: sum(p))
    return px[len(px) * 2 // 3] + (255,)

def canvas(skin, patch=True):
    im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    if patch:
        m = Image.new("L", im.size, 0)
        ImageDraw.Draw(m).ellipse((90 * SS, 150 * SS, 934 * SS, 940 * SS), fill=255)
        m = m.filter(ImageFilter.GaussianBlur(40 * SS))
        sk = Image.new("RGBA", im.size, skin); sk.putalpha(m)
        im.alpha_composite(sk)
    return im, ImageDraw.Draw(im)

def E(d, cx, cy, rx, ry, fill, outline=None, w=0):
    d.ellipse(((cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS), fill=fill, outline=outline, width=w * SS)

def poly(d, pts, fill, outline=None, w=0):
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)
    if outline: d.line([(x * SS, y * SS) for x, y in pts + [pts[0]]], fill=outline, width=w * SS, joint="curve")

def line(d, pts, w):
    d.line([(x * SS, y * SS) for x, y in pts], fill=INK, width=w * SS, joint="curve")
    for x, y in (pts[0], pts[-1]): E(d, x, y, w / 2, w / 2, INK)

def eye(d, cx, cy, r, px, py, pr):
    E(d, cx, cy, r + 14, r + 16, INK); E(d, cx, cy, r, r + 2, WHITE)
    E(d, cx + px, cy + py, pr, pr, INK)
    E(d, cx + px - pr * 0.35, cy + py - pr * 0.4, pr * 0.3, pr * 0.3, WHITE)

def mouth_open(d, cx, cy, rx, ry, teeth=True):
    E(d, cx, cy, rx + 14, ry + 14, INK)
    E(d, cx, cy, rx, ry, (90, 18, 30, 255))
    E(d, cx, cy + ry * 0.55, rx * 0.62, ry * 0.42, (235, 90, 110, 255))  # tongue
    if teeth:
        d.chord(((cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS), 200, 340, fill=WHITE)

def shock(skin):
    im, d = canvas(skin)
    eye(d, 330, 455, 138, 0, 8, 24); eye(d, 694, 455, 138, 0, 8, 24)
    line(d, [(205, 270), (320, 228), (440, 252)], 28); line(d, [(584, 252), (704, 228), (819, 270)], 28)
    mouth_open(d, 512, 760, 135, 150)
    return im

def scream(skin):
    im, d = canvas(skin)
    eye(d, 335, 480, 112, 26, 12, 34); eye(d, 689, 480, 112, -26, 12, 34)
    line(d, [(225, 335), (440, 405)], 34); line(d, [(584, 405), (799, 335)], 34)
    # wide shouting mouth
    pts = [(300, 640), (724, 640), (660, 900), (364, 900)]
    poly(d, pts, (90, 18, 30, 255), INK, 26)
    d.rectangle((322 * SS, 654 * SS, 702 * SS, 706 * SS), fill=WHITE)
    E(d, 512, 850, 130, 44, (235, 90, 110, 255))
    return im

def smug(skin):
    im, d = canvas(skin)
    # half-lidded eyes
    for cx, flip in ((345, 1), (679, -1)):
        E(d, cx, 490, 100, 78, INK); E(d, cx, 490, 86, 64, WHITE)
        E(d, cx + 18 * flip, 505, 30, 30, INK)
        d.rectangle(((cx - 112) * SS, 400 * SS, (cx + 112) * SS, 478 * SS), fill=skin)
        line(d, [(cx - 104, 478), (cx + 104, 478)], 24)
    line(d, [(230, 330), (440, 300)], 26); line(d, [(584, 270), (690, 235), (800, 280)], 26)
    # smirk
    line(d, [(400, 745), (520, 770), (640, 720), (680, 690)], 26)
    return im


def grin(skin):
    im, d = canvas(skin)
    # happy closed eyes ^ ^
    line(d, [(230, 500), (330, 400), (430, 500)], 34); line(d, [(594, 500), (694, 400), (794, 500)], 34)
    line(d, [(240, 300), (420, 270)], 26); line(d, [(604, 270), (784, 300)], 26)
    # big open grin
    d.chord((300 * SS, 520 * SS, 724 * SS, 900 * SS), 0, 180, fill=INK)
    d.chord((326 * SS, 546 * SS, 698 * SS, 874 * SS), 0, 180, fill=(90, 18, 30, 255))
    d.rectangle((330 * SS, 706 * SS, 694 * SS, 752 * SS), fill=WHITE)
    E(d, 512, 830, 110, 36, (235, 90, 110, 255))
    return im

def save(im, name):
    im.resize((S, S), Image.LANCZOS).save(os.path.join(HERE, "faces", name))

wv = skin_of(os.path.join(HERE, "WrathValor", "Wrathvaior1_diff.png"))
g2 = skin_of(os.path.join(HERE, "Girl2", "Misiajestfajna12341_diff.png"))
print("skins", wv, g2)
for nm, f in (("shock", shock), ("scream", scream), ("smug", smug), ("grin", grin)):
    save(f(wv), f"wv_{nm}.png"); save(f(g2), f"g2_{nm}.png")
print("ok")
