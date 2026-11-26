"""Fetch K-POPPED! member photos from Wikimedia Commons (via Wikidata) and crop them to cards.

Output: assets/Photocards/Groups/<Group>/Art/<Album>/<MEMBER>.jpg  (800x1000, 4:5, face in upper half)
        assets/Photocards/Groups/<Group>/Art/<Album>/sources.json  (Commons page, license, author)

Commons photos are freely licensed; sources.json keeps the attribution CC-BY needs.

Your own images: drop them at assets/Photocards/Groups/<Group>/Art/<Album>/_raw/<MEMBER>.jpg|png|webp
(same name as the card) and run the script. A _raw image replaces the Commons one, is re-cropped
whenever you replace it, and a "crops" override fixes its framing like any other.

Usage:
    python tools/photocards/fetch_member_photos.py                 # every group, skip existing
    python tools/photocards/fetch_member_photos.py --groups BTS,TWICE --force

Overrides live in tools/photocards/overrides/*.json (one file per company so people can edit in
parallel). Shape:
    {
      "groups":  { "BEAST": "Q484614" },                 # group -> Wikidata item, when the label is ambiguous
      "members": { "BTS/RM": "Q20947082",                # member -> Wikidata item (uses its main image)
                   "BTS/Jin": "File:Jin at X 2018.jpg" },  # ...or an exact Commons file
      "crops":   { "BTS/RM": [0.5, 0.3, 0.25] }          # optional manual crop: centre x, face y, face height (fractions)
    }
"""

import argparse
import io
import json
import re
import sys
import time
import unicodedata
from pathlib import Path

import cv2
import numpy as np
import requests
from PIL import Image, ImageOps

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[2]
SONG_DIR = ROOT / "src" / "server" / "Songs"
OUT_DIR = ROOT / "assets" / "Photocards" / "Groups"
OVERRIDE_DIR = Path(__file__).resolve().parent / "overrides"

OUT_W, OUT_H = 800, 1000  # 4:5; the card window is 232x284
MIN_W, MIN_H = 600, 750
FACE_FRACTION = 0.30  # face height / crop height
FACE_Y = 0.30  # face centre, as a fraction of crop height (keeps it clear of the name strip)

session = requests.Session()
session.headers["User-Agent"] = "KpopPhotocardFetcher/1.0 (Roblox game art tool)"
CASCADE = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")


def get(url, **params):
    for attempt in range(4):
        r = session.get(url, params=params, timeout=60)
        if r.status_code in (429, 503):
            time.sleep(int(r.headers.get("Retry-After", 0) or 0) or 15 * (attempt + 1))
            continue
        r.raise_for_status()
        return r
    r.raise_for_status()


def safe_name(name):
    return re.sub(r'[<>:"/\\|?*]', "_", name).rstrip(" .") or "_"


def norm(name):
    name = unicodedata.normalize("NFKD", name)
    return re.sub(r"[^a-z0-9]", "", name.casefold())


# ---------------------------------------------------------------- catalog

def catalog():
    """[(company, group, album_name, [members])] for every album in the song modules."""
    out = []
    for path in sorted(SONG_DIR.rglob("*.luau")):
        if path.name == "init.luau":
            continue
        src = path.read_text(encoding="utf-8")
        group = re.search(r'\bGroup\s*=\s*"([^"]+)"', src)
        albums = src.split("Albums = {", 1)
        if not group or len(albums) < 2:
            continue
        for block in re.finditer(r'Name\s*=\s*"([^"]+)".*?Members\s*=\s*\{([^}]*)\}', albums[1], re.S):
            members = re.findall(r'"([^"]+)"', block.group(2))
            out.append((path.parent.name, group.group(1), block.group(1), members))
    return out


def load_overrides():
    merged = {"groups": {}, "members": {}, "crops": {}}
    for path in sorted(OVERRIDE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for key in merged:
            merged[key].update(data.get(key, {}))
    return merged


# ---------------------------------------------------------------- wikidata

def sparql(query):
    return get("https://query.wikidata.org/sparql", format="json", query=query).json()["results"]["bindings"]


def find_group(name, overrides):
    if name in overrides["groups"]:
        return overrides["groups"][name]
    rows = sparql(f"""SELECT DISTINCT ?g WHERE {{
        ?g rdfs:label|skos:altLabel "{name}"@en.
        {{ ?g wdt:P527 ?m. ?m wdt:P106 ?job. }} UNION {{ ?m wdt:P463 ?g. ?m wdt:P106 ?job. }}
        ?g wdt:P495|wdt:P17|wdt:P740 ?c. }} LIMIT 5""")
    return rows[0]["g"]["value"].rsplit("/", 1)[1] if rows else None


def group_members(qid):
    """{qid: {"names": set(normalised names), "image": commons file name or None}}"""
    rows = sparql(f"""SELECT ?m ?name ?img WHERE {{
        {{ wd:{qid} wdt:P527 ?m. }} UNION {{ ?m wdt:P463 wd:{qid}. }}
        ?m rdfs:label|skos:altLabel ?name. FILTER(LANG(?name) IN ("en", "ko", "ja"))
        OPTIONAL {{ ?m wdt:P18 ?img. }} }}""")
    members = {}
    for row in rows:
        m = members.setdefault(row["m"]["value"].rsplit("/", 1)[1], {"names": set(), "image": None})
        m["names"].add(norm(row["name"]["value"]))
        if "img" in row:
            m["image"] = requests.utils.unquote(row["img"]["value"].rsplit("/", 1)[1])
    return members


def member_image(qid):
    rows = sparql(f"SELECT ?img WHERE {{ wd:{qid} wdt:P18 ?img. }}")
    return requests.utils.unquote(rows[0]["img"]["value"].rsplit("/", 1)[1]) if rows else None


def match(member, members):
    want = norm(member)
    hits = [q for q, m in members.items() if want in m["names"]]
    if not hits:  # stage names often sit inside a longer label ("Kim Jiwoong", "Jin (vocalist)")
        hits = [q for q, m in members.items() if any(want and (want == n or n.endswith(want) or n.startswith(want)) for n in m["names"])]
    return hits[0] if len(hits) == 1 else None


# ---------------------------------------------------------------- commons

def commons_file(title):
    title = title if title.startswith("File:") else "File:" + title
    pages = get("https://commons.wikimedia.org/w/api.php", action="query", format="json", titles=title,
                prop="imageinfo", iiprop="url|extmetadata|size", iiurlwidth=1280).json()["query"]["pages"]  # a standard thumb size: Commons rate-limits odd sizes
    page = next(iter(pages.values()))
    info = page["imageinfo"][0]
    meta = info.get("extmetadata", {})
    text = lambda k: re.sub(r"<[^>]+>", "", meta.get(k, {}).get("value", "")).strip()
    return {
        "title": page["title"],
        "page": info["descriptionurl"],
        "download": info.get("thumburl") or info["url"],
        "license": text("LicenseShortName"),
        "licenseUrl": text("LicenseUrl"),
        "author": text("Artist"),
        "date": text("DateTimeOriginal")[:10],
    }


# ---------------------------------------------------------------- crop

def crop_card(img, manual=None):
    """4:5 crop with the face in the upper half. Returns (image, flags)."""
    w, h = img.size
    flags = []
    if manual:
        cx, fy, fh = manual[0] * w, manual[1] * h, manual[2] * h
    else:
        grey = cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2GRAY)
        faces = CASCADE.detectMultiScale(grey, 1.1, 6, minSize=(max(24, w // 25), max(24, w // 25)))
        if len(faces):
            x, y, fw, fh = max(faces, key=lambda f: f[2] * f[3])
            cx, fy = x + fw / 2, y + fh / 2
            fh *= 1.25  # haar boxes stop at the brow; pad to the hairline
            if len(faces) > 1:
                flags.append(f"{len(faces)}faces")
        else:
            flags.append("noface")
            cx, fy, fh = w / 2, 0, h  # widest 4:5 window from the top; a person checks these by eye
    ch = min(fh / FACE_FRACTION, h, w * 5 / 4)
    cw = ch * 4 / 5
    top = min(max(fy - ch * FACE_Y, 0), h - ch)
    left = min(max(cx - cw / 2, 0), w - cw)
    card = img.crop((round(left), round(top), round(left + cw), round(top + ch)))
    if card.width < MIN_W:
        flags.append(f"lowres{card.width}x{card.height}")
    return card.resize((OUT_W, OUT_H), Image.LANCZOS), flags


RAW_EXTS = (".jpg", ".jpeg", ".png", ".webp")


def local_raw(folder, member):
    """An image you placed at <album>/_raw/<MEMBER>.<ext>, if any."""
    for ext in RAW_EXTS:
        path = folder / "_raw" / f"{safe_name(member)}{ext}"
        if path.exists():
            return path
    return None


def fit_card(img, manual=None):
    """For dropped-in images. A portrait image (a photocard scan, a teaser) is already framed, so
    keep all of its width and trim height to 4:5, mostly from the bottom. Face-cropping those
    zooms onto hands and props. Landscape or square images still go through crop_card."""
    w, h = img.size
    if manual or w / h > 0.85:
        return crop_card(img, manual)
    ch = w * 5 / 4
    top = (h - ch) * 0.3
    card = img.crop((0, round(top), w, round(top + ch)))
    flags = [f"lowres{card.width}x{card.height}"] if card.width < MIN_W else []
    return card.resize((OUT_W, OUT_H), Image.LANCZOS), flags


def download(url):
    time.sleep(1.5)  # stay polite on upload.wikimedia.org
    data = get(url).content
    return to_rgb(ImageOps.exif_transpose(Image.open(io.BytesIO(data))))


def to_rgb(img):
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[-1])
        return bg
    return img.convert("RGB")


# ---------------------------------------------------------------- main

def run(only, force):
    overrides = load_overrides()
    report = {"ok": 0, "skipped": 0, "missing": [], "flagged": []}
    for company, group, album, roster in catalog():
        if only and group not in only:
            continue
        folder = OUT_DIR / safe_name(group) / "Art" / safe_name(album)
        folder.mkdir(parents=True, exist_ok=True)
        sources_path = folder / "sources.json"
        sources = json.loads(sources_path.read_text(encoding="utf-8")) if sources_path.exists() else {}
        for member in roster:  # images you dropped in _raw/ win over Commons
            raw = local_raw(folder, member)
            out = folder / f"{safe_name(member)}.jpg"
            if raw and (force or not out.exists() or raw.stat().st_mtime > out.stat().st_mtime):
                with Image.open(raw) as src:
                    card, flags = fit_card(to_rgb(ImageOps.exif_transpose(src)), overrides["crops"].get(f"{group}/{member}"))
                card.save(out, quality=90)
                sources[member] = {"local": f"_raw/{raw.name}", "flags": flags}
                report["ok"] += 1
                print(f"   {member:<14} (local) {raw.name}  {' '.join(flags)}")
        todo = [m for m in roster if not local_raw(folder, m) and (force or not (folder / f"{safe_name(m)}.jpg").exists())]
        report["skipped"] += sum(1 for m in roster if not local_raw(folder, m)) - len(todo)
        if not todo:
            sources_path.write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding="utf-8")
            continue
        gq = find_group(group, overrides)
        members = group_members(gq) if gq else {}
        print(f"[{company}] {group} ({gq}) · {album} · {len(members)} wikidata members")
        for member in todo:
            key = f"{group}/{member}"
            try:
                ov = overrides["members"].get(key)
                if ov and ov.startswith("File:"):
                    qid, file = None, ov
                else:
                    qid = ov or match(member, members)
                    file = (members.get(qid, {}).get("image") or member_image(qid)) if qid else None
                if not file:
                    report["missing"].append(f"{key}: " + ("no Wikidata match" if not qid else f"{qid} has no image"))
                    continue
                meta = commons_file(file)
                card, flags = crop_card(download(meta["download"]), overrides["crops"].get(key))
                card.save(folder / f"{safe_name(member)}.jpg", quality=90)
                sources[member] = {"wikidata": qid, **{k: v for k, v in meta.items() if k != "download"}, "flags": flags}
                report["ok"] += 1
                if flags:
                    report["flagged"].append(f"{key}: {', '.join(flags)}")
                print(f"   {member:<14} {meta['title'][5:70]}  {' '.join(flags)}")
            except Exception as e:  # keep going; the report lists it
                report["missing"].append(f"{key}: {type(e).__name__}: {e}")
        sources_path.write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nsaved {report['ok']}, already there {report['skipped']}, missing {len(report['missing'])}")
    for line in report["missing"]:
        print("MISSING", line)
    for line in report["flagged"]:
        print("CHECK  ", line)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--groups", default="", help="comma list of group names (default: all)")
    parser.add_argument("--force", action="store_true", help="refetch photos that already exist")
    args = parser.parse_args()
    run({g.strip() for g in args.groups.split(",") if g.strip()}, args.force)
