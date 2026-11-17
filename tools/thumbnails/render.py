#!/usr/bin/env python3
"""
Guess the K-Pop Song — thumbnail compositor.

Takes a background image (AI-generated scene with characters, or a Studio
screenshot) and lays the Photocard UI on top as crisp vector HTML, so song
names are always correct and never warped/watermarked.

Usage:
    python3 render.py spec.json out.png

Spec (all keys optional except "background"):
{
  "background": "bg.png",           # any size; cover-fit to the canvas
  "size": [1920, 1080],             # 1920x1080 game thumbnail, 512x512 / 1024x1024 icon
  "answers": {
    "layout": "row" | "column",     # row = 4 cards along the bottom, column = stacked right
    "x": 230, "y": 850,             # top-left of the group (canvas px)
    "scale": 1.0,
    "tilt": true,                   # column only: slight alternating rotation
    "items": [ {"title": "Butter", "artist": "BTS", "correct": true}, ... ]
  },
  "tiers": {
    "x": 250, "y": 760, "scale": 1.0,
    "active": 0,
    "items": [["0.1s","+10"],["0.5s","+7"],["2s","+5"],["8s","+2"],["15s","+1"]]
  },
  "vs": {"x": 960, "y": 470, "scale": 1.0},   # optional VS badge (centre point)
  "text": [ {"text": "GUESS THE SONG!", "x": 960, "y": 90, "size": 110,
             "color": "#FFE07A", "rotate": -3} ]   # optional headline sticker text
}
"""
import base64, json, mimetypes, os, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
FONTS = HERE / "fonts"

INK = "#1E1B2E"
CREAM = "#FAF6E9"
NUMBOX = "#F3EEE0"
MINT = "#8EE3A3"
YELLOW = "#FFDB6E"
TIER = "#EFE7D4"
TIER_EDGE = "#CFC3A6"
RED = "#FF5A4E"
GREY = "#7E7878"


def data_uri(path: Path) -> str:
    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


CHECK_SVG = (
    '<svg viewBox="0 0 48 48" width="100%" height="100%">'
    f'<circle cx="24" cy="24" r="23" fill="{INK}"/>'
    '<path d="M13 25 L21 33 L36 16" fill="none" stroke="#fff" stroke-width="6" '
    'stroke-linecap="round" stroke-linejoin="round"/></svg>'
)


def answer_card(i, item, w, h, tiny_title):
    correct = item.get("correct", False)
    bg = MINT if correct else CREAM
    title = esc(item["title"])
    artist = esc(item.get("artist", ""))
    # long titles shrink so the card never overflows
    tsize = 0.30 * h if len(item["title"]) <= 12 else (0.26 * h if len(item["title"]) <= 16 else 0.21 * h)
    if tiny_title:
        tsize = min(tsize, 0.24 * h)
    check = f'<div class="chk" style="width:{0.34*h}px;height:{0.34*h}px">{CHECK_SVG}</div>' if correct else ""
    return f"""
    <div class="card" style="width:{w}px;height:{h}px;background:{bg};border-radius:{0.2*h}px">
      <div class="num" style="width:{0.56*h}px;height:{0.56*h}px;border-radius:{0.14*h}px;
           font-size:{0.30*h}px;margin-left:{0.16*h}px">{i+1}</div>
      <div class="txt" style="margin-left:{0.16*h}px">
        <div class="t fit" style="font-size:{tsize}px">{title}</div>
        <div class="a fit" style="font-size:{0.17*h}px;margin-top:{0.05*h}px">{artist}</div>
      </div>
      {check}
    </div>"""


def build_html(spec):
    W, H = spec.get("size", [1920, 1080])
    bg = Path(spec["background"])
    if not bg.is_absolute():
        bg = Path(spec.get("_base", ".")) / bg
    parts = []

    a = spec.get("answers")
    if a:
        s = a.get("scale", 1.0)
        items = a["items"]
        if a.get("layout", "row") == "row":
            w, h = 395 * s, 140 * s
            gap = 22 * s
            cards = "".join(
                f'<div style="position:absolute;left:{k*(w+gap)}px;top:0">{answer_card(k, it, w, h, True)}</div>'
                for k, it in enumerate(items))
        else:
            w, h = 495 * s, 140 * s
            gap = 18 * s
            tilts = [-3, -2.5, -2, -3]
            cards = "".join(
                f'<div style="position:absolute;left:{(k%2)*14*s}px;top:{k*(h+gap)}px;'
                f'transform:rotate({tilts[k%4] if a.get("tilt", True) else 0}deg)">'
                f'{answer_card(k, it, w, h, False)}</div>'
                for k, it in enumerate(items))
        parts.append(f'<div style="position:absolute;left:{a.get("x",0)}px;top:{a.get("y",0)}px">{cards}</div>')

    t = spec.get("tiers")
    if t:
        s = t.get("scale", 1.0)
        items = t.get("items", [["0.1s", "+10"], ["0.5s", "+7"], ["2s", "+5"], ["8s", "+2"], ["15s", "+1"]])
        act = t.get("active", 0)
        x = 0
        html = []
        play = 140 * s
        html.append(f'''<div class="play" style="left:0;top:{40*s}px;width:{play}px;height:{play}px;
            box-shadow:{8*s}px {8*s}px 0 {INK}">
            <svg viewBox="0 0 100 100" width="46%" height="46%" style="margin-left:8%">
            <path d="M22 12 L86 50 L22 88 Z" fill="{INK}" stroke="{INK}" stroke-width="10" stroke-linejoin="round"/></svg></div>''')
        x = play + 28 * s
        for k, (lab, pts) in enumerate(items):
            if k == act:
                w, h = 380 * s, 220 * s
                html.append(f'''<div class="tier on" style="left:{x}px;top:0;width:{w}px;height:{h}px;
                    border-radius:{0.17*h}px;border-width:{11*s}px;box-shadow:0 0 0 {7*s}px #FFF8E4, {14*s}px {14*s}px 0 {7*s}px {INK};
                    transform:rotate(3deg)">
                    <span class="lab fit" style="font-size:{78*s}px">{esc(lab)}</span>
                    <span class="pts" style="font-size:{30*s}px">{esc(pts)}</span></div>''')
                x += w + 34 * s
            else:
                w, h = 165 * s, 145 * s
                html.append(f'''<div class="tier" style="left:{x}px;top:{50*s}px;width:{w}px;height:{h}px;
                    border-radius:{0.17*h}px;border-width:{7*s}px">
                    <span class="lab fit" style="font-size:{40*s}px">{esc(lab)}</span>
                    <span class="pts" style="font-size:{19*s}px">{esc(pts)}</span></div>''')
                x += w + 18 * s
        parts.append(f'<div style="position:absolute;left:{t.get("x",0)}px;top:{t.get("y",0)}px">{"".join(html)}</div>')

    v = spec.get("vs")
    if v:
        s = v.get("scale", 1.0)
        parts.append(f'''<div style="position:absolute;left:{v["x"]}px;top:{v["y"]}px;transform:translate(-50%,-50%) scale({s})">
          <svg width="460" height="340" viewBox="0 0 460 340" style="overflow:visible">
            <g font-family="Dela" font-size="250" font-style="italic" stroke-linejoin="round" paint-order="stroke">
              <text x="20" y="265" fill="#fff" stroke="#fff" stroke-width="58">V</text>
              <text x="205" y="265" fill="#fff" stroke="#fff" stroke-width="58">S</text>
              <text x="20" y="265" fill="#E8323C" stroke="{INK}" stroke-width="26">V</text>
              <text x="205" y="265" fill="#2F7BEF" stroke="{INK}" stroke-width="26">S</text>
            </g>
            <polygon points="300,0 316,4 168,340 156,336" fill="{INK}" stroke="#fff" stroke-width="5"/>
          </svg></div>''')

    for tx in spec.get("text", []):
        size = tx.get("size", 100); o = max(4, size * 0.11); w = o + max(3, size * 0.06)
        import math
        ring = ",".join(f"{o*math.cos(a*math.pi/12):.1f}px {o*math.sin(a*math.pi/12):.1f}px 0 {INK}" for a in range(24))
        white = ",".join(f"{w*math.cos(a*math.pi/16):.1f}px {w*math.sin(a*math.pi/16):.1f}px 0 #fff" for a in range(32))
        drop = f"{w*0.6:.1f}px {w*1.3:.1f}px 0 {INK}"
        parts.append(f'''<div class="head" style="left:{tx["x"]}px;top:{tx["y"]}px;font-size:{size}px;
            color:{tx.get("color","#FFE07A")};transform:translate(-50%,-50%) rotate({tx.get("rotate",0)}deg);
            text-shadow:{ring},{white},{drop}">{esc(tx["text"])}</div>''')

    return f"""<!doctype html><html><head><style>
@font-face {{ font-family:Dela; src:url('{data_uri(FONTS/"DelaGothicOne-Regular.ttf")}'); }}
@font-face {{ font-family:Mont; src:url('{data_uri(FONTS/"Montserrat.ttf")}'); font-weight:100 900; }}
html,body {{ margin:0; width:{W}px; height:{H}px; overflow:hidden; }}
#bg {{ position:absolute; inset:0; width:{W}px; height:{H}px; object-fit:cover; }}
.card {{ position:relative; display:flex; align-items:center; box-sizing:border-box;
        border:7px solid {INK}; box-shadow:0 0 0 5px #fff, 9px 11px 0 5px {INK}; }}
.num {{ flex:none; display:flex; align-items:center; justify-content:center; box-sizing:border-box;
       background:{NUMBOX}; border:6px solid {INK}; font-family:Dela; color:{INK}; line-height:1; padding-bottom:2%; }}
.txt {{ flex:1; min-width:0; overflow:hidden; padding-right:14px; }}
.fit {{ overflow:hidden; }}
.t {{ font-family:Mont; font-weight:800; color:{INK}; white-space:nowrap; letter-spacing:-0.01em; line-height:1.05; }}
.a {{ font-family:Mont; font-weight:700; color:{GREY}; white-space:nowrap; }}
.chk {{ flex:none; margin-right:22px; }}
.play {{ position:absolute; border-radius:50%; background:{RED}; display:flex; align-items:center; justify-content:center; }}
.tier {{ position:absolute; box-sizing:border-box; background:{TIER}; border:solid {TIER_EDGE};
        display:flex; align-items:center; justify-content:space-between; padding:0 6%; }}
.tier.on {{ background:{YELLOW}; border-color:{INK}; padding:0 8%; }}
.tier .lab {{ font-family:Dela; color:#4A4558; display:inline-block; white-space:nowrap; }}
.tier.on .lab {{ color:{INK}; }}
.tier .pts {{ font-family:Mont; font-weight:800; color:#4A4558; align-self:center; }}
.tier.on .pts {{ color:{INK}; }}
.vs {{ position:absolute; font-family:Dela; font-size:230px; line-height:1; font-style:italic; display:flex; }}
.vs span {{ paint-order:stroke fill; -webkit-text-stroke:0; text-shadow:none; }}
.vs .v {{ color:#E8323C; -webkit-text-stroke:26px {INK}; paint-order:stroke fill; }}
.vs .s {{ color:#2F7BEF; -webkit-text-stroke:26px {INK}; paint-order:stroke fill; margin-left:-30px; }}
.vs .slash {{ position:absolute; left:47%; top:-12%; width:14px; height:125%; background:{INK}; transform:rotate(28deg); border-radius:8px; }}
.head {{ position:absolute; font-family:Dela; white-space:nowrap; paint-order:stroke fill; }}
</style></head><body>
<img id="bg" src="{data_uri(bg)}">
{''.join(parts)}
<script>
document.fonts.ready.then(()=>{{
  document.querySelectorAll('.fit').forEach(el=>{{
    let fs=parseFloat(getComputedStyle(el).fontSize), box=el.parentElement;
    const lim = el.classList.contains('lab') ? box.clientWidth*0.62 : box.clientWidth-14;
    const card = el.closest('.card');
    const floor = (el.classList.contains('t') && card) ? card.clientHeight*0.17 : 8;
    while(el.scrollWidth>lim && fs>floor){{ fs-=1; el.style.fontSize=fs+'px'; }}
    if(el.scrollWidth>lim && el.classList.contains('t')){{
      el.style.whiteSpace='normal'; el.style.lineHeight='1.0';
      fs = card.clientHeight*0.21; el.style.fontSize=fs+'px';
      while(el.scrollHeight>card.clientHeight*0.5 && fs>8){{ fs-=1; el.style.fontSize=fs+'px'; }}
    }}
  }});
  document.body.dataset.ready=1;
}});
</script>
</body></html>"""


def render(spec, out):
    W, H = spec.get("size", [1920, 1080])
    html = build_html(spec)
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": W, "height": H})
        pg.set_content(html)
        pg.wait_for_selector('body[data-ready]')
        pg.wait_for_timeout(100)
        pg.screenshot(path=out)
        b.close()


if __name__ == "__main__":
    spec_path = Path(sys.argv[1])
    spec = json.loads(spec_path.read_text())
    spec["_base"] = str(spec_path.parent)
    render(spec, sys.argv[2])
    print("wrote", sys.argv[2])
