#!/usr/bin/env python3
"""
Guess the K-Pop Song — art-layer decorator.

Adds seasonal props on top of an existing character render, BEFORE the UI
layer: outlined Santa hats placed on heads, falling snow, snow drifts.
Coordinates are in the source image's own pixels.

Usage:
    python3 decorate.py deco.json out.png

{
  "background": "render.png",
  "hats": [ {"x": 380, "y": 120, "w": 230, "rot": 8, "flip": false} ],  # x,y = brim centre
  "snow": {"count": 260, "seed": 7, "drifts": true}
}
"""
import base64, json, mimetypes, random, sys
from pathlib import Path
from PIL import Image
from playwright.sync_api import sync_playwright

INK = "#1E1B2E"

HAT = f"""
<svg viewBox="-10 -10 240 230" width="100%" height="100%" style="overflow:visible">
  <defs>
    <linearGradient id="red" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF6B5E"/><stop offset=".55" stop-color="#E5303A"/><stop offset="1" stop-color="#A9172A"/>
    </linearGradient>
    <radialGradient id="fur" cx=".4" cy=".35" r=".8">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset=".7" stop-color="#F2EEF8"/><stop offset="1" stop-color="#C9C3DA"/>
    </radialGradient>
  </defs>
  <!-- cone flopping to the right -->
  <path d="M28,158 C30,96 70,30 140,18 C186,10 214,40 206,96 C196,88 186,72 170,70
           C150,68 150,96 160,150 Z"
        fill="url(#red)" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>
  <path d="M58,140 C62,96 92,52 140,38" fill="none" stroke="#FF9A8E" stroke-width="10" stroke-linecap="round" opacity=".75"/>
  <!-- pompom -->
  <circle cx="206" cy="104" r="22" fill="url(#fur)" stroke="{INK}" stroke-width="8"/>
  <!-- fur brim -->
  <path d="M8,150 C40,136 150,132 200,146 C212,150 214,186 202,190 C150,180 50,180 14,194 C0,190 -2,154 8,150 Z"
        fill="url(#fur)" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>
  <path d="M26,160 C70,150 140,149 186,158" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" opacity=".9"/>
</svg>"""


def data_uri(p):
    p = Path(p)
    return f"data:{mimetypes.guess_type(str(p))[0] or 'image/png'};base64," + base64.b64encode(p.read_bytes()).decode()


def build(spec, W, H):
    out = []
    for h in spec.get("hats", []):
        w = h["w"]; hh = w * 230 / 240
        # brim centre sits at (x,y); brim centre in svg units is (105,170)
        left = h["x"] - w * (115 / 240); top = h["y"] - hh * (180 / 230)
        sx = -1 if h.get("flip") else 1
        out.append(f'<div style="position:absolute;left:{left}px;top:{top}px;width:{w}px;height:{hh}px;'
                   f'transform-origin:{w*115/240}px {hh*180/230}px;transform:rotate({h.get("rot",0)}deg) scaleX({sx});'
                   f'filter:drop-shadow(0 6px 6px rgba(20,10,40,.45))">{HAT}</div>')
    s = spec.get("snow")
    if s:
        rnd = random.Random(s.get("seed", 7))
        flakes = []
        for _ in range(s.get("count", 240)):
            x, y = rnd.uniform(0, W), rnd.uniform(0, H)
            depth = rnd.random()
            r = 1.2 + depth ** 3 * 9
            blur = 0 if r < 5 else (r - 5) * 0.8
            op = 0.55 + 0.45 * depth
            flakes.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="#fff" opacity="{op:.2f}"'
                          + (f' filter="url(#b{int(blur)})"' if blur > 0.5 else "") + "/>")
        blurs = "".join(f'<filter id="b{i}" x="-2" y="-2" width="5" height="5"><feGaussianBlur stdDeviation="{i}"/></filter>' for i in range(1, 6))
        drifts = ""
        if s.get("drifts", True):
            drifts = f"""
            <path d="M0,{H} L0,{H*0.80} C{W*0.06},{H*0.74} {W*0.16},{H*0.78} {W*0.22},{H*0.84} C{W*0.26},{H*0.88} {W*0.24},{H} {W*0.24},{H} Z" fill="#F4F2FF" stroke="{INK}" stroke-width="5"/>
            <path d="M{W},{H} L{W},{H*0.78} C{W*0.94},{H*0.73} {W*0.84},{H*0.79} {W*0.79},{H*0.86} C{W*0.76},{H*0.9} {W*0.77},{H} {W*0.77},{H} Z" fill="#F4F2FF" stroke="{INK}" stroke-width="5"/>
            <path d="M{W*0.03},{H*0.82} C{W*0.08},{H*0.78} {W*0.14},{H*0.8} {W*0.18},{H*0.85}" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round"/>
            <path d="M{W*0.97},{H*0.80} C{W*0.92},{H*0.77} {W*0.86},{H*0.8} {W*0.82},{H*0.86}" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round"/>"""
        out.append(f'<svg style="position:absolute;left:0;top:0" width="{W}" height="{H}"><defs>{blurs}</defs>{drifts}{"".join(flakes)}</svg>')
    tint = spec.get("tint")
    if tint:
        out.insert(0, f'<div style="position:absolute;inset:0;background:{tint};mix-blend-mode:soft-light"></div>')
    return out


def main(spec_path, out):
    spec = json.loads(Path(spec_path).read_text())
    bg = spec["background"]
    W, H = Image.open(bg).size
    sc = spec.get("upscale", 2)
    body = "".join(build(spec, W, H))
    html = f"""<!doctype html><html><body style="margin:0;width:{W}px;height:{H}px;overflow:hidden;position:relative">
    <img src="{data_uri(bg)}" style="position:absolute;left:0;top:0;width:{W}px;height:{H}px">{body}</body></html>"""
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": W, "height": H}, device_scale_factor=sc)
        pg.set_content(html); pg.wait_for_timeout(200)
        pg.screenshot(path=out); b.close()
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
