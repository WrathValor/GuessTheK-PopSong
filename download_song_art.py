"""Download Deezer album artwork for the live song catalog."""

import json
import re
import sys
import time
from urllib.error import HTTPError
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
SONG_DIR = ROOT / "src" / "server" / "Songs"
OUT_DIR = ROOT / "assets" / "song_art"
ARTIST_ALIASES = {"i-dle": "(G)I-DLE", "TXT": "TOMORROW X TOGETHER", "BEAST": "HIGHLIGHT"}
FORCE_REFRESH = {("HOT SAUCE", "BABYMONSTER"), ("Bad Girl", "BEAST"), ("BREATH", "BEAST"),
                 ("On Rainy Days", "BEAST"), ("Shadow", "BEAST"), ("Shock", "BEAST")}


def catalog():
    entries = []
    for path in SONG_DIR.rglob("*.luau"):
        if path.name == "init.luau":
            continue
        source = path.read_text(encoding="utf-8")
        artist_match = re.search(r'\bGroup\s*=\s*"([^"]+)"', source)
        if not artist_match:
            continue
        artist = artist_match.group(1)
        for match in re.finditer(r'\{(?:(?!\n\s*\},).)*\n\s*\},', source, re.S):
            block = match.group(0)
            name = re.search(r'\bName\s*=\s*"([^"]+)"', block)
            if name and not re.search(r'\bDraft\s*=\s*true', block):
                entries.append((name.group(1), artist))
    return sorted(set(entries), key=lambda item: (item[1].casefold(), item[0].casefold()))


def fetch(url):
    request = Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36"})
    with urlopen(request, timeout=20) as response:
        return response.read()


def safe_name(value):
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip(" .")
    return value or "untitled"


def main():
    sys.stdout.reconfigure(errors="replace")
    songs = catalog()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    names = {}
    for title, artist in songs:
        names.setdefault(title.casefold(), []).append(artist)
    downloaded, missing, errors = [], [], []
    for index, (title, artist) in enumerate(songs, 1):
        filename = safe_name(title)
        if len(names[title.casefold()]) > 1:
            filename += " - " + safe_name(artist)
        target = OUT_DIR / (filename + ".jpg")
        if target.exists() and target.stat().st_size > 0 and (title, artist) not in FORCE_REFRESH:
            downloaded.append((title, artist, str(target.relative_to(ROOT)), "already present"))
            continue
        search_artist = ARTIST_ALIASES.get(artist, artist)
        query = quote(f"{search_artist} {title}")
        try:
            payload = json.loads(fetch(f"https://api.deezer.com/search?q={query}&limit=25"))
            results = payload.get("data", [])
            normalize = lambda value: re.sub(r"[^a-z0-9]", "", value.casefold())
            chosen = next((r for r in results if normalize(r.get("artist", {}).get("name", "")) == normalize(search_artist)
                           and normalize(r.get("title", "")) == normalize(title)), None)
            if not chosen:
                chosen = next((r for r in results if normalize(r.get("artist", {}).get("name", "")) == normalize(search_artist)), None)
            if not chosen:
                if (title, artist) == ("HOT SAUCE", "BABYMONSTER") and target.exists() and target.stat().st_size > 0:
                    downloaded.append((title, artist, str(target.relative_to(ROOT)), "Apple iTunes Search API fallback"))
                    print(f"[{index}/{len(songs)}] kept Apple fallback {target.name}", flush=True)
                    continue
                missing.append((title, artist))
                print(f"[{index}/{len(songs)}] NO MATCH: {title} — {artist}", flush=True)
                continue
            image_url = chosen.get("album", {}).get("cover_xl") or chosen.get("album", {}).get("cover_big")
            image = fetch(image_url)
            target.write_bytes(image)
            downloaded.append((title, artist, str(target.relative_to(ROOT)), chosen.get("album", {}).get("title", "")))
            print(f"[{index}/{len(songs)}] saved {target.name}", flush=True)
        except Exception as exc:
            errors.append((title, artist, str(exc)))
            print(f"[{index}/{len(songs)}] ERROR: {title} — {artist}: {exc}", flush=True)
        time.sleep(1.0)
    (OUT_DIR / "manifest.json").write_text(json.dumps({
        "source": "Deezer Search API album cover URLs; Apple iTunes Search API fallback for HOT SAUCE (BABYMONSTER)",
        "catalog_song_count": len(songs),
        "downloaded": downloaded,
        "missing": missing,
        "errors": errors,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Complete: {len(downloaded)} present/downloaded, {len(missing)} unmatched, {len(errors)} errors.")


if __name__ == "__main__":
    main()
