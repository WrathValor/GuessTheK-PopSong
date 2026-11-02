# Story thumbnails: Blender renders (renders/shot1-3.png, icon3.png) + light grading + 1-2 words.
# python3 compose2.py -> final/thumb_panic.png, thumb_faceoff.png, thumb_meltdown.png, icon.png
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops
from compose import P, INK, CREAM, YELLOW, PINK, RED, MINT, TITLE, BODY, font, outlined, chip

def grade(im, sat=1.25, con=1.12, bright=1.0):
    im = ImageEnhance.Color(im).enhance(sat)
    im = ImageEnhance.Contrast(im).enhance(con)
    return ImageEnhance.Brightness(im).enhance(bright)

def bloom(im, radius=18, amount=0.45, threshold=200):
    hi = im.convert("L").point(lambda v: 255 if v > threshold else 0)
    glow = Image.composite(im, Image.new("RGB", im.size), hi).filter(ImageFilter.GaussianBlur(radius))
    return ImageChops.add(im, ImageEnhance.Brightness(glow).enhance(amount))

def vignette(im, strength=0.55):
    w, h = im.size
    m = Image.new("L", (w, h), 0); d = ImageDraw.Draw(m)
    d.ellipse((-w * 0.15, -h * 0.25, w * 1.15, h * 1.25), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) // 5))
    dark = ImageEnhance.Brightness(im).enhance(1 - strength)
    return Image.composite(im, dark, m)

def tint_split(im, left, right, alpha=60):
    w, h = im.size
    grad = Image.new("L", (w, 1)); grad.putdata([int(255 * x / (w - 1)) for x in range(w)]); grad = grad.resize((w, h))
    a = Image.new("RGB", (w, h), left); b = Image.new("RGB", (w, h), right)
    col = Image.composite(b, a, grad)
    return Image.blend(im, ImageChops.screen(im, col), alpha / 255)

def speedlines(size, cx, cy, n=48, inner=0.42, colour=(255, 255, 255), alpha=70, seed=3):
    import random; random.seed(seed)
    w, h = size; layer = Image.new("RGBA", size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    R = math.hypot(w, h)
    for i in range(n):
        a = random.uniform(0, 2 * math.pi); r0 = R * random.uniform(inner, inner + 0.12); wdt = random.uniform(0.004, 0.012)
        p = [(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
             (cx + math.cos(a - wdt) * R, cy + math.sin(a - wdt) * R),
             (cx + math.cos(a + wdt) * R, cy + math.sin(a + wdt) * R)]
        d.polygon(p, fill=(*colour, alpha))
    return layer.filter(ImageFilter.GaussianBlur(1.2))

def sticker_q(c, xy, size, colour=YELLOW, rot=0):
    outlined(c, xy, "?", font(TITLE, size), colour, max(8, size // 18), max(6, size // 20), "mm", rotate=rot)

def load(name):
    return Image.open(P("renders", name)).convert("RGB")

def panic():
    im = load("shot1.png")
    im = vignette(bloom(grade(im, 1.3, 1.15), 22, 0.5), 0.45).convert("RGBA")
    im.alpha_composite(speedlines(im.size, 830, 930, 60, 0.33, (255, 240, 250), 55))
    # the time, glowing
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    outlined(glow, (330, 120), "0.1s", font(TITLE, 300), RED, 0, 0, "ma", rotate=8)
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26)))
    outlined(im, (330, 120), "0.1s", font(TITLE, 300), RED, 18, 16, "ma", rotate=8)
    chip(im, (330, 470), "GUESS IT!", font(TITLE, 74), YELLOW, (34, 6), 10, 12, 26, rotate=8, anchor="ma")
    return im.convert("RGB")

def ui(name, scale, rot=0, shadow=True):
    """A piece of the real game UI (keyed from a Studio green-screen capture), scaled up."""
    p = Image.open(P("bg", f"ui_{name}.png")).convert("RGBA")
    p = p.resize((round(p.width * scale), round(p.height * scale)), Image.LANCZOS)
    if shadow:
        a = p.split()[-1]; pad = round(18 * scale / 2)
        s = Image.new("RGBA", (p.width + pad, p.height + pad), (0, 0, 0, 0))
        sh = Image.new("RGBA", p.size, (10, 6, 20, 150)); sh.putalpha(a.point(lambda v: v * 150 // 255))
        s.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6)), (pad, pad)); s.alpha_composite(p); p = s
    if rot: p = p.rotate(rot, resample=Image.BICUBIC, expand=True)
    return p

def place(c, p, cx, cy):
    c.alpha_composite(p, (round(cx - p.width / 2), round(cy - p.height / 2)))

def faceoff():
    im = load("shot2.png")
    im = tint_split(grade(im, 1.3, 1.12, 0.95), (255, 60, 150), (60, 140, 255), 55)
    im = vignette(bloom(im, 16, 0.22, 245), 0.5).convert("RGBA")
    W, H = im.size
    # flash where their foreheads meet
    fl = Image.new("RGB", im.size, (0, 0, 0)); d = ImageDraw.Draw(fl)
    for rr, v in ((260, 60), (150, 120), (70, 220)):
        d.ellipse((940 - rr, 300 - rr, 940 + rr, 300 + rr), fill=(v, v, min(255, v + 40)))
    im = ImageChops.add(im.convert("RGB"), fl.filter(ImageFilter.GaussianBlur(60))).convert("RGBA")
    # the in-game scoreboard: final round, one point apart
    place(im, ui("score", 1.75, -2), W / 2, 92)
    # the two answers they're fighting over, flying in from the bottom corners
    place(im, ui("ans3", 2.15, 9), 270, 930)
    place(im, ui("ans4", 2.15, -9), W - 270, 930)
    # timer + rival-answered sticker by the clash
    place(im, ui("timer", 2.3, -8), 1640, 330)
    place(im, ui("rival", 2.6, 6), 1610, 225)
    chip(im, (W / 2, 960), "FINAL ROUND", font(TITLE, 64), YELLOW, (34, 4), 10, 12, 26, rotate=-2, anchor="ma")
    return im.convert("RGB")

def meltdown():
    im = load("shot3.png")
    im = vignette(bloom(grade(im, 1.35, 1.15), 20, 0.4), 0.55).convert("RGBA")
    sticker_q(im, (300, 210), 260, YELLOW, 14)
    sticker_q(im, (1640, 300), 200, PINK, -16)
    outlined(im, (960, 905), "NAME THAT SONG!", font(TITLE, 128), YELLOW, 15, 13, "ma", rotate=-2)
    return im.convert("RGB")

def icon():
    im = load("icon3.png")
    im = vignette(bloom(grade(im, 1.4, 1.15), 18, 0.45), 0.5).convert("RGBA")
    sticker_q(im, (210, 210), 300, YELLOW, 14)
    return im.resize((512, 512), Image.LANCZOS).convert("RGB")

os.makedirs(P("final"), exist_ok=True)
panic().save(P("final", "thumb_panic.png"))
faceoff().save(P("final", "thumb_faceoff.png"))
meltdown().save(P("final", "thumb_meltdown.png"))
icon().save(P("final", "icon.png"))
print("ok")
