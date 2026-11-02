# Builds the store icon + thumbnails from the Blender renders (renders/) and Studio captures (bg/).
# python3 compose.py  ->  final/icon.png, final/thumb_panic.png, final/thumb_duel.png
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
P = lambda *a: os.path.join(HERE, *a)
INK = (30, 27, 46, 255); CREAM = (251, 247, 240, 255); YELLOW = (255, 224, 122, 255)
LILAC = (185, 166, 255, 255); PINK = (255, 158, 196, 255); BLUE = (158, 216, 245, 255)
MINT = (167, 233, 184, 255); RED = (255, 90, 78, 255)
TITLE = P("fonts", "LuckiestGuy-Regular.ttf"); BODY = P("fonts", "BuilderSans-ExtraBold.otf")

def font(path, size): return ImageFont.truetype(path, size)

def cover(im, w, h, fx=0.5, fy=0.5):
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x = round((im.width - w) * fx); y = round((im.height - h) * fy)
    return im.crop((x, y, x + w, y + h))

def outlined(canvas, xy, text, f, fill, stroke=14, shadow=12, anchor="la", rotate=0):
    """Thick ink outline + hard offset shadow, drawn on its own layer so it can be rotated."""
    l, t, r, b = f.getbbox(text, stroke_width=stroke)
    pad = stroke + shadow + 10
    layer = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    o = (pad - l, pad - t)
    d.text((o[0] + shadow, o[1] + shadow), text, font=f, fill=INK, stroke_width=stroke, stroke_fill=INK)
    d.text(o, text, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK)
    if rotate: layer = layer.rotate(rotate, resample=Image.BICUBIC, expand=True)
    x, y = xy
    if anchor[0] == "m": x -= layer.width // 2
    elif anchor[0] == "r": x -= layer.width
    if anchor[1] == "m": y -= layer.height // 2
    elif anchor[1] == "b": y -= layer.height
    canvas.alpha_composite(layer, (round(x), round(y)))
    return layer.size

def chip(canvas, xy, text, f, fill, pad=(28, 12), border=8, shadow=8, radius=20, rotate=0, anchor="la"):
    l, t, r, b = f.getbbox(text)
    w = r - l + pad[0] * 2 + border * 2; h = b - t + pad[1] * 2 + border * 2
    layer = Image.new("RGBA", (w + shadow + 4, h + shadow + 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((shadow, shadow, shadow + w - 1, shadow + h - 1), radius, fill=INK)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius, fill=INK)
    d.rounded_rectangle((border, border, w - 1 - border, h - 1 - border), max(2, radius - border), fill=fill)
    d.text((border + pad[0] - l, border + pad[1] - t), text, font=f, fill=INK)
    if rotate: layer = layer.rotate(rotate, resample=Image.BICUBIC, expand=True)
    x, y = xy
    if anchor[0] == "m": x -= layer.width // 2
    elif anchor[0] == "r": x -= layer.width
    canvas.alpha_composite(layer, (round(x), round(y)))

def card(im, border=8, radius=26, shadow=12):
    """Put a crop of the game UI on a photocard: ink border + hard shadow."""
    w, h = im.size
    out = Image.new("RGBA", (w + border * 2 + shadow, h + border * 2 + shadow), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((shadow, shadow, out.width - 1, out.height - 1), radius, fill=INK)
    d.rounded_rectangle((0, 0, w + border * 2 - 1, h + border * 2 - 1), radius, fill=INK)
    mask = Image.new("L", im.size, 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius - border, fill=255)
    out.paste(im, (border, border), mask)
    return out

def rim(im, colour=INK, width=10):
    """Ink outline round a transparent render, like a sticker."""
    a = im.split()[-1].filter(ImageFilter.MaxFilter(width * 2 + 1))
    base = Image.new("RGBA", im.size, colour); base.putalpha(a)
    base.alpha_composite(im)
    return base

def shadow_of(im, offset=(18, 18), colour=(30, 27, 46, 150)):
    a = im.split()[-1]
    s = Image.new("RGBA", im.size, colour); s.putalpha(a.point(lambda v: v * colour[3] // 255))
    out = Image.new("RGBA", (im.width + offset[0], im.height + offset[1]), (0, 0, 0, 0))
    out.alpha_composite(s, offset); out.alpha_composite(im)
    return out

def rays(w, h, cx, cy, colour, n=18, alpha=40):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    R = math.hypot(w, h)
    for i in range(n):
        a0 = (i / n) * 2 * math.pi; a1 = a0 + math.pi / n
        d.polygon([(cx, cy), (cx + R * math.cos(a0), cy + R * math.sin(a0)), (cx + R * math.cos(a1), cy + R * math.sin(a1))], fill=(*colour[:3], alpha))
    return layer

def dots(w, h, step=34, r=5, alpha=30):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    for y in range(0, h, step):
        for x in range(0, w, step):
            d.ellipse((x - r, y - r, x + r, y + r), fill=(30, 27, 46, alpha))
    return layer

def vignette(w, h, strength=170):
    m = Image.new("L", (w, h), 0); d = ImageDraw.Draw(m)
    for i in range(60):
        k = i / 60
        d.rectangle((k * w * 0.25, k * h * 0.25, w - k * w * 0.25, h - k * h * 0.25), fill=int(strength * (1 - k) ** 2))
    layer = Image.new("RGBA", (w, h), INK); layer.putalpha(m.filter(ImageFilter.GaussianBlur(60)))
    return layer

def trim(im):
    return im.crop(im.split()[-1].getbbox())

# ---------------------------------------------------------------- Thumbnail: panic
def thumb_panic():
    W, H = 1920, 1080
    round_ui = Image.open(P("bg", "bg_round.png")).convert("RGBA")
    bg = cover(Image.open(P("bg", "bg_street.png")).convert("RGBA"), W, H, 0.5, 0.35)
    bg = ImageEnhance.Brightness(bg.filter(ImageFilter.GaussianBlur(5))).enhance(0.75)
    c = bg
    c.alpha_composite(rays(W, H, 520, 560, PINK, 22, 34))
    c.alpha_composite(vignette(W, H))
    # the round screen's controls (play, tiers, answers) and scoreboard, from Studio
    controls = round_ui.crop((300, 528, 1292, 708))
    controls = controls.resize((round(controls.width * 1.12), round(controls.height * 1.12)), Image.LANCZOS)
    cc = card(controls, radius=24)
    c.alpha_composite(cc, (W - cc.width - 36, H - cc.height - 40))
    # title
    outlined(c, (1350, 70), "GUESS THE", font(TITLE, 112), YELLOW, 13, 12, "ma", rotate=3)
    outlined(c, (1350, 200), "K-POP SONG", font(TITLE, 176), CREAM, 16, 14, "ma", rotate=3)
    chip(c, (1350, 400), "CAN YOU GUESS IT IN 0.5s?", font(BODY, 46), PINK, rotate=3, anchor="ma")
    # the player
    me = trim(Image.open(P("renders", "panic.png")).convert("RGBA"))
    s = 1010 / me.height
    me = me.resize((round(me.width * s), round(me.height * s)), Image.LANCZOS)
    me = shadow_of(rim(me, INK, 9), (22, 22))
    c.alpha_composite(me, (-110, 50))
    return c.convert("RGB")

# ---------------------------------------------------------------- Thumbnail: duel
def thumb_duel():
    """renders/duel_stage.png: both avatars on the exported DuelStage in Blender, street backdrop behind."""
    W, H = 1920, 1080
    c = cover(Image.open(P("renders", "duel_stage.png")).convert("RGBA"), W, H)
    # darken the top so the title reads
    grad = Image.new("L", (1, H)); grad.putdata([int(max(0, 200 * (1 - y / 420))) for y in range(H)])
    top = Image.new("RGBA", (W, H), INK); top.putalpha(grad.resize((W, H)))
    c.alpha_composite(top)
    d = ImageDraw.Draw(c); cx, cy, R = W // 2, 560, 105
    d.ellipse((cx - R + 14, cy - R + 14, cx + R + 14, cy + R + 14), fill=INK)
    d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=INK)
    d.ellipse((cx - R + 12, cy - R + 12, cx + R - 12, cy + R - 12), fill=RED)
    outlined(c, (cx, cy + 6), "VS", font(TITLE, 112), YELLOW, 9, 0, "mm")
    outlined(c, (W // 2, 34), "GUESS THE K-POP SONG", font(TITLE, 128), CREAM, 15, 13, "ma", rotate=-2)
    chip(c, (W // 2, 210), "1v1 DUELS · WIN COINS · KEEP YOUR STREAK", font(BODY, 42), YELLOW, rotate=-2, anchor="ma")
    chip(c, (330, 880), "YOU", font(TITLE, 68), MINT, rotate=-5, anchor="ma")
    chip(c, (W - 330, 880), "RIVAL", font(TITLE, 68), PINK, rotate=5, anchor="ma")
    return c.convert("RGB")

# ---------------------------------------------------------------- Icon
def icon():
    S = 1024
    c = Image.new("RGBA", (S, S), LILAC)
    c.alpha_composite(rays(S, S, S // 2, 640, CREAM, 16, 60))
    c.alpha_composite(dots(S, S, 40, 6, 26))
    me = trim(Image.open(P("renders", "icon.png")).convert("RGBA"))
    s = 860 / me.width
    me = me.resize((round(me.width * s), round(me.height * s)), Image.LANCZOS)
    me = shadow_of(rim(me, INK, 10), (18, 18))
    c.alpha_composite(me, ((S - me.width) // 2 + 30, S - me.height + 40))
    # "?" sticker
    outlined(c, (190, 300), "?", font(TITLE, 330), YELLOW, 18, 16, "mm", rotate=12)
    # play button
    d = ImageDraw.Draw(c); cx, cy, R = 845, 830, 120
    d.ellipse((cx - R + 16, cy - R + 16, cx + R + 16, cy + R + 16), fill=INK)
    d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=INK)
    d.ellipse((cx - R + 14, cy - R + 14, cx + R - 14, cy + R - 14), fill=RED)
    d.polygon([(cx - 34, cy - 52), (cx - 34, cy + 52), (cx + 56, cy)], fill=CREAM)
    chip(c, (S // 2, 40), "K-POP", font(TITLE, 120), PINK, (40, 4), 12, 14, 30, rotate=-4, anchor="ma")
    return c.resize((512, 512), Image.LANCZOS).convert("RGB")

if __name__ == "__main__":
  os.makedirs(P("final"), exist_ok=True)
  icon().save(P("final", "icon.png"))
  thumb_panic().save(P("final", "thumb_panic.png"))
  thumb_duel().save(P("final", "thumb_duel.png"))
  print("ok")
