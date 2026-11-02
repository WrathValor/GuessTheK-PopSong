# 30s trailer, 1920x1080 @ 30fps. Stills from Blender (../thumbnails/renders) + the real game UI
# (ui/, keyed from Studio) animated in code. One mp4 per scene; mix.py adds the SFX and joins them.
#   python3 trailer.py frame <scene> <t>   -> frames/<scene>_<t>.png (preview a moment)
#   python3 trailer.py scene <scene>       -> scenes/<scene>.mp4
import math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
TH = os.path.join(HERE, "..", "thumbnails")
W, H, FPS = 1920, 1080, 30
INK = (30, 27, 46, 255); CREAM = (251, 247, 240, 255); YELLOW = (255, 224, 122, 255)
LILAC = (185, 166, 255, 255); PINK = (255, 158, 196, 255); BLUE = (158, 216, 245, 255)
MINT = (167, 233, 184, 255); RED = (255, 90, 78, 255)
TITLE = os.path.join(TH, "fonts", "LuckiestGuy-Regular.ttf"); BODY = os.path.join(TH, "fonts", "BuilderSans-ExtraBold.otf")
_fonts = {}
def font(p, s):
    if (p, s) not in _fonts: _fonts[(p, s)] = ImageFont.truetype(p, s)
    return _fonts[(p, s)]

# ------------------------------------------------------------------ easing
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def seg(t, a, b): return clamp((t - a) / (b - a)) if b > a else float(t >= a)
def out_cubic(x): return 1 - (1 - x) ** 3
def in_cubic(x): return x ** 3
def out_back(x, s=2.2): x -= 1; return 1 + (s + 1) * x ** 3 + s * x ** 2
def lerp(a, b, x): return a + (b - a) * x

# ------------------------------------------------------------------ assets
_cache = {}
def img(path, mode="RGBA"):
    k = (path, mode)
    if k not in _cache: _cache[k] = Image.open(path).convert(mode)
    return _cache[k]
def render(name): return img(os.path.join(TH, "renders", name), "RGB")
def ui(name): return img(os.path.join(HERE, "ui", name + ".png"))

def fit_cover(im, w=W, h=H):
    s = max(w / im.width, h / im.height)
    im = im.resize((math.ceil(im.width * s), math.ceil(im.height * s)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))

def kb(base, z, cx=0.5, cy=0.5, dx=0, dy=0):
    """Zoom z (>=1) around (cx, cy) of a W x H base, plus a pixel offset (shake)."""
    cw, ch = W / z, H / z
    x0 = clamp(cx * W - cw / 2 - dx / z, 0, W - cw); y0 = clamp(cy * H - ch / 2 - dy / z, 0, H - ch)
    return base.resize((W, H), Image.BICUBIC, box=(x0, y0, x0 + cw, y0 + ch))

def shake(t, t0, amp=26, dur=0.35, seed=0):
    if t < t0 or t > t0 + dur: return 0, 0
    k = 1 - (t - t0) / dur; r = random.Random(int(t * 1000) + seed)
    return r.uniform(-1, 1) * amp * k, r.uniform(-1, 1) * amp * k

def grade(im, sat=1.3, con=1.12, bright=1.0):
    return ImageEnhance.Brightness(ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(sat)).enhance(con)).enhance(bright)

def dim_blur(im, r=10, b=0.45): return ImageEnhance.Brightness(im.filter(ImageFilter.GaussianBlur(r))).enhance(b)

def paste(c, layer, cx, cy, scale=1.0, rot=0.0, alpha=1.0):
    if scale <= 0.01 or alpha <= 0.01: return
    l = layer
    if abs(scale - 1) > 1e-3: l = l.resize((max(1, round(l.width * scale)), max(1, round(l.height * scale))), Image.BICUBIC)
    if abs(rot) > 0.05: l = l.rotate(rot, resample=Image.BICUBIC, expand=True)
    if alpha < 0.999:
        a = l.split()[-1].point(lambda v: int(v * alpha)); l = l.copy(); l.putalpha(a)
    c.alpha_composite(l, (round(cx - l.width / 2), round(cy - l.height / 2)))

def with_shadow(l, off=10, a=150):
    s = Image.new("RGBA", (l.width + off, l.height + off), (0, 0, 0, 0))
    sh = Image.new("RGBA", l.size, (10, 6, 20, 255)); sh.putalpha(l.split()[-1].point(lambda v: v * a // 255))
    s.alpha_composite(sh, (off, off)); s.alpha_composite(l); return s

def text_layer(text, size, fill, stroke=None, shadow=None, face=TITLE):
    f = font(face, size); stroke = stroke if stroke is not None else max(4, size // 11); shadow = shadow if shadow is not None else max(4, size // 13)
    l, t, r, b = f.getbbox(text, stroke_width=stroke); pad = stroke + shadow + 6
    im = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    o = (pad - l, pad - t)
    if shadow: d.text((o[0] + shadow, o[1] + shadow), text, font=f, fill=INK, stroke_width=stroke, stroke_fill=INK)
    d.text(o, text, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK)
    return im

def chip_layer(text, size, fill, face=TITLE, pad=(30, 10), border=8, shadow=8, radius=22):
    f = font(face, size); l, t, r, b = f.getbbox(text)
    w = r - l + pad[0] * 2 + border * 2; h = b - t + pad[1] * 2 + border * 2
    im = Image.new("RGBA", (w + shadow, h + shadow), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((shadow, shadow, w + shadow - 1, h + shadow - 1), radius, fill=INK)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius, fill=INK)
    d.rounded_rectangle((border, border, w - 1 - border, h - 1 - border), radius - border, fill=fill)
    d.text((border + pad[0] - l, border + pad[1] - t), text, font=f, fill=INK)
    return im

_TXT = {}
def T(key, fn):
    if key not in _TXT: _TXT[key] = fn()
    return _TXT[key]

# little sprites
def note_sprite(col, s=90):
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im); k = s / 90
    for dx in (0, 4 * k):
        pass
    d.line((60 * k, 12 * k, 60 * k, 66 * k), fill=INK, width=round(14 * k)); d.line((60 * k, 14 * k, 84 * k, 30 * k), fill=INK, width=round(14 * k))
    d.ellipse((22 * k, 52 * k, 66 * k, 84 * k), fill=INK)
    d.line((60 * k, 14 * k, 60 * k, 66 * k), fill=col, width=round(6 * k)); d.line((61 * k, 16 * k, 80 * k, 29 * k), fill=col, width=round(6 * k))
    d.ellipse((27 * k, 57 * k, 61 * k, 79 * k), fill=col)
    return im
def coin_sprite(s=80):
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse((2, 2, s - 3, s - 3), fill=INK); d.ellipse((7, 7, s - 8, s - 8), fill=(255, 205, 60, 255))
    d.ellipse((16, 16, s - 17, s - 17), outline=(214, 150, 20, 255), width=5)
    d.ellipse((s * 0.28, s * 0.22, s * 0.42, s * 0.36), fill=(255, 240, 180, 255))
    return im
PAL = [PINK, LILAC, BLUE, YELLOW, MINT]
NOTES = [note_sprite(c) for c in PAL]; COIN = coin_sprite()

def particles(c, t, sprites, n, seed, origin, speed=(500, 1100), grav=900, spin=200, size=(0.6, 1.3), t0=0.0, life=2.0, spread=(0, 360)):
    r = random.Random(seed); tt = t - t0
    if tt < 0: return
    for i in range(n):
        a = math.radians(r.uniform(*spread)); v = r.uniform(*speed); sc = r.uniform(*size); sp = r.choice(sprites); w0 = r.uniform(-spin, spin); delay = r.uniform(0, 0.25)
        u = tt - delay
        if u < 0 or u > life: continue
        x = origin[0] + math.cos(a) * v * u; y = origin[1] - math.sin(a) * v * u + 0.5 * grav * u * u
        paste(c, sp, x, y, sc * min(1, u * 6), w0 * u, clamp((life - u) / 0.4))

def rain(c, t, sprite, n, seed, t0=0.0, speed=(700, 1100)):
    r = random.Random(seed)
    for i in range(n):
        x = r.uniform(-40, W + 40); delay = r.uniform(0, 1.6); v = r.uniform(*speed); sc = r.uniform(0.6, 1.4); sp = r.uniform(-300, 300)
        u = t - t0 - delay
        if u < 0: continue
        y = -80 + v * u
        if y > H + 100: continue
        paste(c, sprite, x + math.sin(u * 3 + i) * 30, y, sc, sp * u)

def flash(c, t, t0, dur=0.18, col=(255, 255, 255)):
    k = 1 - seg(t, t0, t0 + dur)
    if t >= t0 and k > 0:
        ov = Image.new("RGBA", c.size, (*col, int(230 * k))); c.alpha_composite(ov)

def vignette_layer():
    m = Image.new("L", (W, H), 0); d = ImageDraw.Draw(m)
    d.ellipse((-W * 0.15, -H * 0.25, W * 1.15, H * 1.25), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(200)).point(lambda v: 255 - v)
    l = Image.new("RGBA", (W, H), (8, 5, 18, 255)); l.putalpha(m.point(lambda v: int(v * 0.6))); return l
VIG = None

def letterbox_bars(c, k):  # cinematic bars sliding away
    h = round(110 * k)
    if h > 0:
        d = ImageDraw.Draw(c); d.rectangle((0, 0, W, h), fill=(5, 4, 10, 255)); d.rectangle((0, H - h, W, H), fill=(5, 4, 10, 255))

# ------------------------------------------------------------------ scenes
# each scene: (name, duration, draw(t) -> RGBA W x H). t is seconds within the scene.
def bg_from(name, sat=1.3):
    return T("bg:" + name, lambda: grade(fit_cover(render(name)), sat).convert("RGBA"))

def s_hook(t):  # 0.0 - 2.4  black, ticks, "YOU HAVE" / "0.1 SECONDS"
    c = Image.new("RGBA", (W, H), (8, 6, 16, 255))
    # pulsing clock ring
    k = seg(t, 0.0, 1.2); d = ImageDraw.Draw(c)
    R = 220 + 10 * math.sin(t * 20)
    d.ellipse((W / 2 - R, H / 2 - R, W / 2 + R, H / 2 + R), outline=(60, 50, 90, 255), width=10)
    d.arc((W / 2 - R, H / 2 - R, W / 2 + R, H / 2 + R), -90, -90 + 360 * (1 - k), fill=RED, width=14)
    a = T("youhave", lambda: text_layer("YOU HAVE", 120, CREAM))
    b = T("seconds", lambda: text_layer("0.1 SECONDS", 230, RED))
    if t >= 0.25: paste(c, a, W / 2, H / 2 - 150 - 30 * (1 - out_cubic(seg(t, 0.25, 0.5))), 1.0, -3, seg(t, 0.25, 0.4))
    if t >= 1.25:
        dx, dy = shake(t, 1.25, 30)
        paste(c, b, W / 2 + dx, H / 2 + 80 + dy, lerp(2.4, 1.0, out_cubic(seg(t, 1.25, 1.42))), -3)
        flash(c, t, 1.25, 0.15, (255, 80, 70))
    return c

def s_panic(t):  # 2.4 - 5.0  smash cut: the buzzer slam
    base = bg_from("shot1.png", 1.35)
    z = lerp(1.18, 1.0, out_cubic(seg(t, 0, 0.35))) + 0.05 * seg(t, 0.35, 2.6)
    dx, dy = shake(t, 0.05, 34, 0.45)
    c = kb(base, z, 0.45, 0.55, dx, dy).convert("RGBA")
    particles(c, t, NOTES, 18, 4, (800, 900), (900, 1700), 1300, 260, (0.7, 1.3), 0.02, 1.8, (15, 70))
    particles(c, t, NOTES, 10, 5, (800, 900), (900, 1500), 1300, 260, (0.7, 1.3), 0.02, 1.8, (115, 165))
    flash(c, t, 0.0, 0.2)
    g = T("guessit", lambda: chip_layer("GUESS IT!", 84, YELLOW, pad=(36, 6), border=10, shadow=12, radius=26))
    if t > 0.7: paste(c, g, 380, 210, out_back(seg(t, 0.7, 0.95)), 7)
    return c

def s_title(t):  # 5.0 - 8.0  logo slam over the meltdown
    base = T("meltbg", lambda: dim_blur(bg_from("shot3.png"), 6, 0.55))
    c = kb(base, 1.04 + 0.04 * t / 3, 0.5, 0.45).convert("RGBA")
    words = [("GUESS THE", 150, YELLOW, 0.1, 330), ("K-POP", 300, PINK, 0.5, 560), ("SONG", 260, CREAM, 0.9, 800)]
    for w, s, col, t0, y in words:
        if t < t0: continue
        dx, dy = shake(t, t0, 18, 0.25, s)
        L = T("w" + w, lambda w=w, s=s, col=col: text_layer(w, s, col))
        paste(c, L, W / 2 + dx, y + dy, lerp(2.2, 1.0, out_cubic(seg(t, t0, t0 + 0.16))), -3)
    particles(c, t, NOTES, 30, 9, (W / 2, 560), (500, 1300), 700, 200, (0.7, 1.4), 0.5, 2.6)
    flash(c, t, 0.5, 0.15)
    return c

def s_tiers(t):  # 8.0 - 11.5  less you hear = more points
    base = T("roundbg", lambda: dim_blur(bg_from("shot2.png"), 14, 0.35))
    c = base.copy()
    TS = 1.9
    tiers = T("tiers", lambda: with_shadow(ui("tiers").resize((round(ui("tiers").width * TS), round(ui("tiers").height * TS)), Image.LANCZOS), 14))
    ty = 560 + 400 * (1 - out_back(seg(t, 0.0, 0.45)))
    paste(c, tiers, W / 2, ty)
    centres = [149, 291, 434, 576, 718]  # 0.5s .. 15s, px from the strip's left edge (unscaled)
    x0 = W / 2 - tiers.width / 2
    if t > 0.6:
        k = seg(t, 0.6, 1.9); idx = 4 - min(4, int(k * 5)) if t < 1.9 else 0
        cx = x0 + centres[idx] * TS
        ring = T("ring", lambda: (lambda im: (ImageDraw.Draw(im).rounded_rectangle((6, 6, 284, 140), 26, outline=(255, 255, 255, 255), width=10), im)[1])(Image.new("RGBA", (290, 146), (0, 0, 0, 0))))
        paste(c, ring, cx, ty - 6, 1.0 + 0.05 * math.sin(t * 18))
    a = T("less", lambda: text_layer("THE LESS YOU HEAR", 120, CREAM))
    b = T("more", lambda: text_layer("THE MORE YOU SCORE", 120, YELLOW))
    paste(c, a, W / 2, 250, out_back(seg(t, 0.2, 0.45)), -2)
    if t > 2.0: paste(c, b, W / 2, 830, out_back(seg(t, 2.0, 2.25)), -2)
    pts = T("p10", lambda: text_layer("+10", 160, MINT))
    if t > 2.0:
        u = seg(t, 2.0, 3.5); paste(c, pts, W / 2 - tiers.width / 2 + 149 * TS, 420 - 120 * out_cubic(u), out_back(seg(t, 2.0, 2.2)), 8, 1 - seg(t, 3.1, 3.5))
    return c

def s_answers(t):  # 11.5 - 14.5  four answers drop in, Magnetic is right
    base = T("roundbg", lambda: dim_blur(bg_from("shot2.png"), 14, 0.35))
    c = base.copy()
    q = T("which", lambda: text_layer("WHICH SONG IS IT?", 130, CREAM))
    paste(c, q, W / 2, 200, out_back(seg(t, 0.0, 0.25)), -2)
    pos = [(560, 470), (1360, 470), (560, 760), (1360, 760)]
    for i in range(4):
        t0 = 0.15 + i * 0.18
        if t < t0: continue
        L = T("ans%d" % i, lambda i=i: with_shadow(ui("ans%d" % (i + 1)).resize((round(238 * 2.9), round(ui("ans%d" % (i + 1)).height * 2.9)), Image.LANCZOS), 14))
        x, y = pos[i]; up = out_back(seg(t, t0, t0 + 0.3))
        sc = 1.0
        if i == 2 and t > 1.6: sc = 1 + 0.12 * out_back(seg(t, 1.6, 1.8)) - 0.05 * seg(t, 1.8, 2.3)
        dim = 1.0 if (i == 2 or t < 1.6) else 0.45
        paste(c, L, x, y + 40 + (1 - up) * 500, sc, [-3, 2, 3, -2][i], dim)
    if t > 1.6:
        tick = T("correct", lambda: chip_layer("CORRECT!", 70, MINT, pad=(30, 4), border=9, shadow=10))
        paste(c, tick, 560, 965, out_back(seg(t, 1.6, 1.85)), -6)
        pts = T("p10b", lambda: text_layer("+10", 170, MINT))
        u = seg(t, 1.7, 3.0); paste(c, pts, 900, 720 - 160 * out_cubic(u), out_back(seg(t, 1.7, 1.9)), 8, 1 - seg(t, 2.7, 3.0))
        particles(c, t, [COIN] + NOTES[:2], 14, 12, (560, 700), (700, 1200), 1500, 300, (0.5, 0.9), 1.6, 1.4, (60, 120))
    return c

def s_duel(t):  # 14.5 - 19.0  rival found -> face-off
    if t < 1.3:
        base = T("duelbg", lambda: dim_blur(bg_from("shot2.png"), 14, 0.4))
        c = base.copy()
        rf = T("rf", lambda: with_shadow(ui("rival_found").resize((244 * 3, 55 * 3), Image.LANCZOS), 12))
        pl = T("pl", lambda: with_shadow(ui("players").resize((458 * 3, 80 * 3), Image.LANCZOS), 14))
        paste(c, rf, W / 2, 340, out_back(seg(t, 0.0, 0.3)), -2)
        paste(c, pl, W / 2, 650, out_back(seg(t, 0.25, 0.55)), 0)
        return c
    u = t - 1.3
    base = T("faceoff", lambda: grade(fit_cover(img(os.path.join(TH, "final", "thumb_faceoff_clean.png"), "RGB")), 1.0).convert("RGBA"))
    dx, dy = shake(u, 0.0, 30, 0.4)
    c = kb(base, 1.06 - 0.06 * out_cubic(seg(u, 0, 3.2)), 0.5, 0.55, dx, dy).convert("RGBA")
    flash(c, u, 0.0, 0.2, (210, 220, 255)); flash(c, u, 1.4, 0.12, (210, 220, 255))
    sb = T("sb", lambda: with_shadow(ui("score").resize((round(685 * 1.75), round(89 * 1.75)), Image.LANCZOS), 12))
    paste(c, sb, W / 2, 100 - 220 * (1 - out_cubic(seg(u, 0.3, 0.6))), 1, -2)
    d = T("duels", lambda: text_layer("1V1 DUELS", 190, YELLOW))
    paste(c, d, W / 2, 900, lerp(2.0, 1.0, out_cubic(seg(u, 0.6, 0.78))) if u > 0.6 else 0, -3)
    return c

def s_stakes(t):  # 19.0 - 22.0  stake roll -> win coins
    base = T("stakebg", lambda: dim_blur(bg_from("shot4.png"), 14, 0.35))
    c = base.copy()
    st = T("stake", lambda: with_shadow(ui("stake").resize((round(706 * 1.9), round(198 * 1.9)), Image.LANCZOS), 14))
    paste(c, st, W / 2, 560, out_back(seg(t, 0.0, 0.35)), -2)
    if t > 0.9:
        w = T("wincoins", lambda: text_layer("BET COINS. WIN BIG.", 130, YELLOW))
        paste(c, w, W / 2, 230, out_back(seg(t, 0.9, 1.15)), -2)
    if t > 1.5: particles(c, t, [COIN], 20, 21, (W / 2, 520), (1100, 1700), 1600, 300, (0.6, 1.0), 1.5, 1.5, (25, 155))
    return c

def s_win(t):  # 22.0 - 25.5  victory + coins + YOU WIN card
    base = bg_from("shot4.png", 1.35)
    c = kb(base, 1.08 - 0.06 * out_cubic(seg(t, 0, 3.5)), 0.4, 0.45).convert("RGBA")
    rain(c, t, COIN, 70, 31, 0.1)
    card = T("youwin", lambda: with_shadow(ui("youwin").resize((round(310 * 1.55), round(560 * 1.55)), Image.LANCZOS), 14))
    paste(c, card, 1500 + 700 * (1 - out_cubic(seg(t, 0.4, 0.8))), 540, 1, 4)
    k = T("streak", lambda: chip_layer("KEEP YOUR STREAK!", 70, RED, pad=(30, 6), border=9, shadow=10))
    if t > 1.4: paste(c, k, 560, 950, out_back(seg(t, 1.4, 1.65)), -4)
    flash(c, t, 0.0, 0.15, (255, 230, 150))
    return c

def s_collect(t):  # 25.5 - 28.0  the index + song count
    base = T("colbg", lambda: dim_blur(bg_from("shot3.png"), 14, 0.38))
    c = base.copy()
    cards = T("idx", lambda: with_shadow(ui("index_cards").resize((round(797 * 1.5), round(440 * 1.5)), Image.LANCZOS), 14))
    paste(c, cards, W / 2, 745 + 30 * (1 - out_cubic(seg(t, 0, 0.5))), lerp(0.85, 1.0, out_cubic(seg(t, 0, 0.5))) + 0.02 * t, -2, seg(t, 0, 0.2))
    a = T("songs", lambda: text_layer("190+ SONGS", 170, PINK))
    b = T("gens", lambda: chip_layer("GEN 2  >  GEN 5", 72, YELLOW, pad=(34, 6), border=10, shadow=12))
    if t > 0.25: paste(c, a, W / 2, 150, lerp(2.0, 1.0, out_cubic(seg(t, 0.25, 0.42))), -3)
    if t > 0.75: paste(c, b, W / 2, 305, out_back(seg(t, 0.75, 1.0)), 2)
    return c

def s_end(t):  # 28.0 - 31.0  end card
    base = T("endbg", lambda: dim_blur(bg_from("shot2.png"), 18, 0.32))
    c = base.copy()
    ic = T("icon", lambda: with_shadow(img(os.path.join(TH, "final", "icon.png")).resize((360, 360), Image.LANCZOS), 14))
    m = T("iconmask", lambda: None)
    paste(c, ic, W / 2 - 560, H / 2 - 20, out_back(seg(t, 0.0, 0.35)), -6)
    for w, s, col, t0, y in (("GUESS THE", 110, YELLOW, 0.1, 360), ("K-POP SONG", 200, PINK, 0.25, 530)):
        if t > t0: paste(c, T("e" + w, lambda w=w, s=s, col=col: text_layer(w, s, col)), W / 2 + 190, y, lerp(1.8, 1.0, out_cubic(seg(t, t0, t0 + 0.15))), -2)
    p = T("play", lambda: chip_layer("PLAY NOW ON ROBLOX", 76, MINT, pad=(40, 10), border=10, shadow=12, radius=28))
    if t > 0.7: paste(c, p, W / 2 + 190, 760, out_back(seg(t, 0.7, 0.95)) * (1 + 0.03 * math.sin(t * 7)), -2)
    particles(c, t, NOTES, 24, 41, (W / 2 + 190, 530), (400, 1000), 500, 150, (0.6, 1.2), 0.25, 3.0)
    return c

SCENES = [("hook", 2.4, s_hook), ("panic", 2.6, s_panic), ("title", 3.0, s_title), ("tiers", 3.5, s_tiers),
          ("answers", 3.0, s_answers), ("duel", 4.5, s_duel), ("stakes", 3.0, s_stakes), ("win", 3.5, s_win),
          ("collect", 2.5, s_collect), ("end", 3.0, s_end)]

def draw(name, t):
    global VIG
    if VIG is None: VIG = vignette_layer()
    fn = dict((n, f) for n, _, f in SCENES)[name]
    c = fn(t)
    c.alpha_composite(VIG)
    return c.convert("RGB")

def start_of(name):
    s = 0.0
    for n, d, _ in SCENES:
        if n == name: return s
        s += d

def render_scene(name):
    dur = dict((n, d) for n, d, _ in SCENES)[name]; n = round(dur * FPS)
    tmp = os.path.join(HERE, "scenes", name + ".tmp.mp4"); out = os.path.join(HERE, "scenes", name + ".mp4")
    p = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                          "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS), tmp], stdin=subprocess.PIPE)
    for i in range(n):
        p.stdin.write(draw(name, i / FPS).tobytes())
    p.stdin.close(); p.wait()
    if p.returncode == 0: os.replace(tmp, out)
    print(name, n, "frames", p.returncode)

if __name__ == "__main__":
    if sys.argv[1] == "frame":
        name, t = sys.argv[2], float(sys.argv[3])
        draw(name, t).save(os.path.join(HERE, "frames", f"{name}_{t:.2f}.jpg"), quality=90); print("ok")
    elif sys.argv[1] == "scene":
        render_scene(sys.argv[2])
    elif sys.argv[1] == "list":
        for n, d, _ in SCENES: print(n, start_of(n), d)
