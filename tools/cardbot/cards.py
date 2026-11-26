"""K-POPPED! card tools: the parts of the card bot that don't need Discord.

  crop_card(image_bytes, shift)      -> PNG bytes, 720x900 (4:5), ready to upload
  find_group(repo, name)             -> the group's Songs file (src/server/Songs/**/<group>.luau)
  find_album(text, album)            -> (album id, name, members) or None
  add_album(text, group, name, ...)  -> the Songs file text with a new album added
  match_member(members, name)        -> the album's member name for a filename / typed name
  set_art(text, album_id, member, id)-> the Songs file text with Art[member] set
  upload_image(api_key, group_id, png) / poll_operation(api_key, op_id)   (Open Cloud)
  card_path(repo, group, album, member) -> where the crop is kept (assets/Photocards/…)

Card ids are album:member:rarity, and the member part comes from the album's Members names
(Modules/Library/Albums.MemberKey), so this never renames a member or an album that's already
there: it only fills in Art and adds new albums.

Run it on its own to check a group and album without Discord:
    python tools/cardbot/cards.py "TREASURE" "REBOOT"
"""

from __future__ import annotations

import io
import json
import re
import sys
import time
from pathlib import Path

import requests
from PIL import Image, ImageFilter, ImageOps

CARD_W, CARD_H = 720, 900
INSET = 0.025  # trims the rounded corners / edge of a scanned photocard
TOP = 0.02  # how far down the crop starts (cards keep the head and crown in frame)
OPEN_CLOUD = "https://apis.roblox.com/assets/v1"
DISPLAY_NAME = "K-POPPED card art"  # never put numbers in asset names (moderation)
DESCRIPTION = "K-POPPED! photocard art"


# [[ Images ]]

def crop_card(data: bytes, shift: float = 0.0) -> bytes:
    """A photo (or a photocard scan) -> a 720x900 PNG.

    Trims INSET off every edge, takes the biggest 4:5 box (centred across, starting TOP down;
    `shift` moves it down by that fraction of the photo's height, negative moves it up), scales
    it with Lanczos and sharpens gently when the source was small. No AI upscaling: that got
    cards rejected."""
    im = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    w, h = im.size
    ix, iy = int(w * INSET), int(h * INSET)
    left, top, right, bottom = ix, iy, w - ix, h - iy
    aw, ah = right - left, bottom - top
    if aw * 5 / 4 <= ah:  # tall: full width, pick the height
        cw, ch = aw, int(aw * 5 / 4)
    else:  # wide: full height, pick the width (centred)
        ch, cw = ah, int(ah * 4 / 5)
    x = left + (aw - cw) // 2
    y = top + int(h * (TOP + shift))
    y = max(top, min(y, bottom - ch))
    card = im.crop((x, y, x + cw, y + ch)).resize((CARD_W, CARD_H), Image.LANCZOS)
    if cw < CARD_W:
        card = card.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    out = io.BytesIO()
    card.save(out, "PNG", optimize=True)
    return out.getvalue()


def preview_sheet(cards: list[tuple[str, bytes]]) -> bytes:
    """Small previews side by side (5 a row), for the Discord check."""
    from PIL import ImageDraw

    tw, th, label = 180, 225, 26
    cols = min(5, len(cards)) or 1
    rows = (len(cards) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + label)), (30, 27, 46))
    draw = ImageDraw.Draw(sheet)
    for i, (name, png) in enumerate(cards):
        im = Image.open(io.BytesIO(png)).resize((tw, th))
        x, y = (i % cols) * tw, (i // cols) * (th + label)
        sheet.paste(im, (x, y))
        draw.text((x + 6, y + th + 6), name[:22], fill=(251, 247, 240))
    out = io.BytesIO()
    sheet.save(out, "PNG")
    return out.getvalue()


# [[ Names ]]

ACCENTS = str.maketrans({"É": "e", "é": "e", "È": "e", "è": "e", "Á": "a", "á": "a", "Í": "i", "í": "i", "Ó": "o", "ó": "o", "Ú": "u", "ú": "u"})


def member_key(name: str) -> str:
    """Albums.MemberKey: "Jung Kook" -> "jungkook", "ROSÉ" -> "rose", "I.N" -> "in"."""
    return re.sub(r"[^0-9a-z]", "", name.translate(ACCENTS).lower())


def match_member(members: list[str], name: str) -> str | None:
    """The album's member name for a typed or file name ("Haruto", "haruto_2.jpg" -> "HARUTO")."""
    stem = re.sub(r"\.(png|jpe?g|webp|gif|bmp)$", "", name, flags=re.I)
    key = member_key(stem)
    for m in members:
        if member_key(m) == key:
            return m
    # "haruto2", "haruto_hq": a member key at the start of the name (longest wins)
    hits = [m for m in members if member_key(m) and key.startswith(member_key(m))]
    return max(hits, key=lambda m: len(member_key(m))) if hits else None


def slug(s: str) -> str:
    return re.sub(r"-+", "-", re.sub(r"[^0-9a-z]+", "-", s.translate(ACCENTS).lower())).strip("-")


# [[ Songs files ]]

def find_group(repo: Path, name: str) -> Path | None:
    """The Songs file whose Group = "<name>" (case-insensitive)."""
    want = name.strip().lower()
    for path in sorted((repo / "src/server/Songs").rglob("*.luau")):
        text = path.read_text(encoding="utf-8")
        m = re.search(r'^\s*Group\s*=\s*"([^"]+)"', text, re.M)
        if m and m.group(1).lower() == want:
            return path
    return None


def group_name(text: str) -> str:
    return re.search(r'^\s*Group\s*=\s*"([^"]+)"', text, re.M).group(1)


def _block_end(text: str, start: int) -> int:
    """Index just past the } that closes the { at `start` (strings skipped)."""
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i = text.index('"', i + 1)
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces")


def _albums(text: str) -> list[dict]:
    """Every album in a Songs file: { id, name, members, start, end, indent }."""
    m = re.search(r"^(\s*)Albums\s*=\s*\{", text, re.M)
    if not m:
        return []
    outer_end = _block_end(text, m.end() - 1)
    out = []
    for idm in re.finditer(r'^(\s*)Id\s*=\s*"([^"]+)"', text[m.end():outer_end], re.M):
        pos = m.end() + idm.start()
        start = text.rindex("{", 0, pos)
        end = _block_end(text, start)
        block = text[start:end]
        name = re.search(r'^\s*Name\s*=\s*"([^"]*)"', block, re.M)
        members = re.search(r"^\s*Members\s*=\s*\{([^}]*)\}", block, re.M)
        out.append({
            "id": idm.group(2),
            "name": name.group(1) if name else idm.group(2),
            "members": re.findall(r'"([^"]+)"', members.group(1)) if members else [],
            "start": start,
            "end": end,
            "indent": idm.group(1),
        })
    return out


def find_album(text: str, album: str) -> dict | None:
    """An album by its Name or Id (case-insensitive)."""
    want = album.strip().lower()
    for a in _albums(text):
        if a["name"].lower() == want or a["id"].lower() == want:
            return a
    want = slug(album)
    for a in _albums(text):
        if slug(a["name"]) == want:
            return a
    return None


def add_album(text: str, name: str, year: int, members: list[str]) -> tuple[str, str]:
    """Adds a new album (empty Songs, Art to come) at the end of Albums. Returns (text, id)."""
    group = group_name(text)
    album_id = f"{member_key(group)}-{slug(name)}"
    if any(a["id"] == album_id for a in _albums(text)):
        raise ValueError(f"{album_id} already exists")
    colour = re.search(r'^\s*Colour\s*=\s*"([0-9A-Fa-f]{6})"', text, re.M)
    colour = colour.group(1) if colour else "B9A6FF"
    m = re.search(r"^(\s*)Albums\s*=\s*\{", text, re.M)
    if m:
        unit = m.group(1)  # one indent step (the Albums key sits one level in)
        outer_end = _block_end(text, m.end() - 1)
        close = outer_end - 1  # the } that closes Albums
        line_start = text.rindex("\n", 0, close) + 1
        i1, i2 = unit * 2, unit * 3
    else:
        # no Albums yet: add the table before the file's final }
        unit = re.search(r"^(\s+)Group\s*=", text, re.M).group(1)
        close = text.rindex("}")
        line_start = text.rindex("\n", 0, close) + 1
        i1, i2 = unit * 2, unit * 3
    member_list = ", ".join(f'"{m}"' for m in members)
    entry = (
        f"{i1}{{\n"
        f'{i2}Id = "{album_id}",\n'
        f'{i2}Name = "{name}",\n'
        f"{i2}Year = {year},\n"
        f'{i2}Colour = "{colour}",\n'
        f"{i2}Songs = {{}},\n"
        f"{i2}Members = {{ {member_list} }},\n"
        f"{i1}}},\n"
    )
    if m:
        text = text[:line_start] + entry + text[line_start:]
    else:
        text = text[:line_start] + f"{unit}Albums = {{\n{entry}{unit}}},\n" + text[line_start:]
    return text, album_id


def add_members(text: str, album_id: str, names: list[str]) -> str:
    """Adds members to an album's Members list (new ones only)."""
    a = next(a for a in _albums(text) if a["id"] == album_id)
    new = [n for n in names if not match_member(a["members"], n)]
    if not new:
        return text
    block = text[a["start"]:a["end"]]
    members = a["members"] + new
    block = re.sub(r"^(\s*Members\s*=\s*)\{[^}]*\}", lambda m: m.group(1) + "{ " + ", ".join(f'"{x}"' for x in members) + " }", block, count=1, flags=re.M)
    return text[:a["start"]] + block + text[a["end"]:]


def _art_key(member: str) -> str:
    """A regex for an Art entry's key: ["HARUTO"] or, for a plain name, the bare HARUTO form
    some files use (YUNAH = "...")."""
    alts = [r'\["' + re.escape(member) + r'"\]']
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", member):
        alts.append(re.escape(member) + r"(?![A-Za-z0-9_])")
    return "(?:" + "|".join(alts) + ")"


def has_art(block: str, member: str) -> bool:
    """Whether an album block's Art has an rbxassetid for this member."""
    return re.search(r"^[ \t]*" + _art_key(member) + r'[ \t]*=[ \t]*"rbxassetid://\d+"', block, re.M) is not None


def set_art(text: str, album_id: str, member: str, asset_id: str) -> str:
    """Sets Art[member] = "rbxassetid://<asset_id>" in one album, adding Art if it's missing."""
    a = next(a for a in _albums(text) if a["id"] == album_id)
    block = text[a["start"]:a["end"]]
    i2 = a["indent"]
    unit = i2[: len(i2) // 3] if len(i2) >= 3 else "\t"
    i3 = i2 + unit
    line = f'{i3}["{member}"] = "rbxassetid://{asset_id}",'
    art = re.search(r"^\s*Art\s*=\s*\{", block, re.M)
    if art:
        art_end = _block_end(block, art.end() - 1)
        body = block[art.end():art_end - 1]
        key = re.compile(r"^[ \t]*" + _art_key(member) + r'[ \t]*=[ \t]*"[^"]*",?[^\n]*$', re.M)
        if key.search(body):
            body = key.sub(line, body, count=1)
        else:
            body = body.rstrip(" \t")
            if not body.endswith("\n"):
                body += "\n"
            body += line + "\n" + i2
        block = block[:art.end()] + body + block[art_end - 1:]
    else:
        members = re.search(r"^\s*Members\s*=\s*\{[^}]*\},?[^\n]*\n", block, re.M)
        insert = members.end() if members else block.rindex("\n", 0, len(block) - 1) + 1
        block = block[:insert] + f"{i2}Art = {{\n{line}\n{i2}}},\n" + block[insert:]
    return text[:a["start"]] + block + text[a["end"]:]


def card_path(repo: Path, group: str, album: str, member: str) -> Path:
    """assets/Photocards/<Group>/<Album>/<MEMBER>/<MEMBER>.png, reusing a folder that's already
    there under another capitalisation ("STRAY KIDS" -> "Stray Kids")."""
    root = repo / "assets/Photocards"

    def pick(parent: Path, want: str) -> Path:
        if parent.exists():
            for p in parent.iterdir():
                if p.is_dir() and p.name.lower() == want.lower():
                    return p
        return parent / want

    safe = lambda s: re.sub(r'[<>:"/\\|?*]', "", s).strip() or "_"
    g = pick(root, safe(group))
    a = pick(g, safe(album))
    m = pick(a, safe(member))
    return m / f"{safe(member).upper()}.png"


# [[ Open Cloud ]]

def upload_image(api_key: str, group_id: str, png: bytes) -> str:
    """Starts an image upload for the group. Returns the operation id."""
    request = {
        "assetType": "Image",
        "displayName": DISPLAY_NAME,
        "description": DESCRIPTION,
        "creationContext": {"creator": {"groupId": str(group_id)}},
    }
    r = requests.post(
        f"{OPEN_CLOUD}/assets",
        headers={"x-api-key": api_key},
        files={"request": (None, json.dumps(request), "application/json"), "fileContent": ("card.png", png, "image/png")},
        timeout=60,
    )
    if r.status_code >= 300:
        raise RuntimeError(f"upload failed: HTTP {r.status_code} {r.text[:200]}")
    body = r.json()
    return body.get("operationId") or body["path"].split("/")[-1]


def poll_operation(api_key: str, op_id: str) -> tuple[str, str | None]:
    """("Approved" | "Rejected" | "Reviewing" | "Pending", asset id or None)."""
    r = requests.get(f"{OPEN_CLOUD}/operations/{op_id}", headers={"x-api-key": api_key}, timeout=30)
    if r.status_code >= 300:
        raise RuntimeError(f"poll failed: HTTP {r.status_code} {r.text[:200]}")
    body = r.json()
    if not body.get("done"):
        return "Pending", None
    resp = body.get("response") or {}
    state = (resp.get("moderationResult") or {}).get("moderationState", "Reviewing")
    return state, resp.get("assetId")


# [[ Check from the command line ]]

if __name__ == "__main__":
    repo = Path(__file__).resolve().parents[2]
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    path = find_group(repo, sys.argv[1])
    if not path:
        print(f"no Songs file with Group = {sys.argv[1]!r}")
        sys.exit(1)
    text = path.read_text(encoding="utf-8")
    album = find_album(text, sys.argv[2])
    print(path.relative_to(repo))
    if album:
        print(f"album {album['id']} ({album['name']}): members {album['members']}")
        for name in sys.argv[3:]:
            print(f"  {name} -> {match_member(album['members'], name)}")
    else:
        print(f"no album {sys.argv[2]!r} yet: the bot would add it")
