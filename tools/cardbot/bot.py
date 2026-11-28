"""K-POPPED! card bot: post photocards in Discord, get them on Roblox and in the game.

Slash commands (only the user ids in ALLOWED_USERS can use them):

  /cards group album photo1 [photo2 … photo10] [names] [year] [shift]
      group, album   autocomplete from the Songs files (type a new album name to add one)
      photoN         the photos, each named by member (Haruto.jpg, Jihoon.png, ...), or a .zip of
                     a folder of them (any number; a photo in a member-named subfolder,
                     Haruto/IMG_123.jpg, takes the folder's name)
      names          member names in photo order instead of file names: "Haruto, Jihoon"
      year           the year, when the album is new
      shift          move crops down (or up, negative) by that % of the photo: "Haruto 8, Yoshi -5"
  /albums group                    the group's albums and who's missing art
  /addmember group album name      add a member to an album that already exists
  /packart group photo [album]     a group's cover art (square): its pack sleeve and binder header;
                                   with album, that album's own cover (its binder page) instead

/cards crops each photo to 720x900 and posts a preview with Upload / Cancel. Upload sends them
to Roblox (group GROUP_ID) three at a time, waits for moderation, keeps the crops in
assets/Photocards/<Group>/<Album>/<MEMBER>/ and writes the approved ids into the album's Art in
the group's Songs file (src/server/Songs/...). Rojo syncs that straight into Studio.

A new album is added to the Songs file with the members you uploaded and no songs. A name that
isn't in an album that already exists is refused (it would make a new card id): rename the
file, use names, or /addmember first.

A soloist (GroupType = "Solo") gets several cards per era (Versions, cards.SOLO_VERSIONS for a
new album): photos named after them fill the versions with no art yet, in order; "IU 3.jpg"
picks (or replaces) one.

Set up: see README.md next to this file.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import io
import os
import re
import zipfile
from pathlib import Path, PurePosixPath

import discord
from discord import app_commands
from dotenv import load_dotenv

import cards

HERE = Path(__file__).resolve().parent
load_dotenv(HERE / ".env")

TOKEN = os.environ["DISCORD_TOKEN"]
API_KEY = os.environ["ROBLOX_API_KEY"]
GROUP_ID = os.environ.get("ROBLOX_GROUP_ID", "430052409")
ALLOWED = {int(x) for x in re.split(r"[,\s]+", os.environ.get("ALLOWED_USERS", "")) if x}
GUILD_ID = int(os.environ["GUILD_ID"]) if os.environ.get("GUILD_ID", "").strip() else None
REPO = Path(os.environ.get("REPO_ROOT") or HERE.parents[1]).resolve()

BATCH = 3  # uploads at a time
BATCH_WAIT = 45  # seconds before checking a batch (and between batches)
POLL_EVERY = 10
POLL_LIMIT = 300  # give up waiting on a batch after this many seconds
IMAGE_TYPES = (".png", ".jpg", ".jpeg", ".webp", ".bmp")
ZIP_LIMIT = 60  # photos read from one zip

client = discord.Client(intents=discord.Intents.default())  # (slash commands need no privileged intents)
tree = app_commands.CommandTree(client)
busy = asyncio.Lock()  # one batch at a time, so two never edit a Songs file together


# [[ Helpers ]]

def parse_shift(value: str | None) -> dict[str, float]:
    """"Haruto 8, I.N -5%" -> { "haruto": 0.08, "in": -0.05 }"""
    out = {}
    for part in (value or "").split(","):
        m = re.match(r"\s*(.+?)\s+(-?\d+(?:\.\d+)?)\s*%?\s*$", part)
        if m:
            out[cards.member_key(m.group(1))] = float(m.group(2)) / 100
    return out


def songs_file(group: str) -> Path:
    path = cards.find_group(REPO, group)
    if not path:
        raise ValueError(f"There's no Songs file with `Group = \"{group}\"`. Pick one from the list.")
    return path


def write(path: Path, text: str):
    path.write_text(text, encoding="utf-8", newline="")


def group_names() -> list[str]:
    names = []
    for path in (REPO / "src/server/Songs").rglob("*.luau"):
        m = re.search(r'^\s*Group\s*=\s*"([^"]+)"', path.read_text(encoding="utf-8"), re.M)
        if m:
            names.append(m.group(1))
    return sorted(names, key=str.lower)


async def allowed(interaction: discord.Interaction) -> bool:
    if interaction.user.id in ALLOWED:
        return True
    await interaction.response.send_message("You can't use this bot.", ephemeral=True)
    return False


async def group_autocomplete(_: discord.Interaction, current: str) -> list[app_commands.Choice[str]]:
    cur = current.lower()
    names = [n for n in group_names() if cur in n.lower()]
    return [app_commands.Choice(name=n, value=n) for n in names[:25]]


async def album_autocomplete(interaction: discord.Interaction, current: str) -> list[app_commands.Choice[str]]:
    group = getattr(interaction.namespace, "group", None)
    path = group and cards.find_group(REPO, group)
    if not path:
        return []
    cur = current.lower()
    albums = [a["name"] for a in cards._albums(path.read_text(encoding="utf-8")) if cur in a["name"].lower()]
    choices = [app_commands.Choice(name=a, value=a) for a in albums[:24]]
    if current and not any(a.lower() == cur for a in albums):
        choices.append(app_commands.Choice(name=f"{current} (new album)", value=current))
    return choices


class Confirm(discord.ui.View):
    def __init__(self, author: int):
        super().__init__(timeout=900)
        self.author = author
        self.choice: bool | None = None
        self.done = asyncio.Event()

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        return interaction.user.id == self.author

    async def _pick(self, interaction: discord.Interaction, ok: bool):
        self.choice = ok
        for child in self.children:
            child.disabled = True
        await interaction.response.edit_message(view=self)
        self.done.set()
        self.stop()

    @discord.ui.button(label="Upload", style=discord.ButtonStyle.success)
    async def upload(self, interaction: discord.Interaction, _):
        await self._pick(interaction, True)

    @discord.ui.button(label="Cancel", style=discord.ButtonStyle.secondary)
    async def cancel(self, interaction: discord.Interaction, _):
        await self._pick(interaction, False)

    async def on_timeout(self):
        self.done.set()


# [[ /cards ]]

@tree.command(name="cards", description="Crop photocards, upload them to Roblox and add them to an album")
@app_commands.describe(
    group="The group (from the Songs files)",
    album="The album (or type a new one)",
    photo1="A photo named by member (Haruto.jpg), or a .zip of a folder of them",
    names="Member names in photo order, instead of file names: Haruto, Jihoon",
    year="The album's year (new albums)",
    shift="Move crops down by % (negative = up): Haruto 8, Yoshi -5",
)
@app_commands.autocomplete(group=group_autocomplete, album=album_autocomplete)
async def cards_command(
    interaction: discord.Interaction,
    group: str,
    album: str,
    photo1: discord.Attachment,
    photo2: discord.Attachment | None = None,
    photo3: discord.Attachment | None = None,
    photo4: discord.Attachment | None = None,
    photo5: discord.Attachment | None = None,
    photo6: discord.Attachment | None = None,
    photo7: discord.Attachment | None = None,
    photo8: discord.Attachment | None = None,
    photo9: discord.Attachment | None = None,
    photo10: discord.Attachment | None = None,
    names: str | None = None,
    year: app_commands.Range[int, 2000, 2100] | None = None,
    shift: str | None = None,
):
    if not await allowed(interaction):
        return
    await interaction.response.defer(thinking=True)
    try:
        await run_cards(interaction, group, album, [p for p in (photo1, photo2, photo3, photo4, photo5, photo6, photo7, photo8, photo9, photo10) if p], names, year, shift)
    except ValueError as e:
        await interaction.followup.send(str(e))
    except Exception as e:
        await interaction.followup.send(f"Something broke: `{type(e).__name__}: {e}`")
        raise


def unzip(data: bytes) -> list[tuple[str, bytes]]:
    """The photos in a zip, in name order, each named "<folder>/<file>" (or just "<file>"):
    photo_name picks the folder when it's a member (Haruto/IMG_123.jpg), else the file name
    (an album folder like Ubermansch/G-Dragon 2.jpg). The zip's own top folder is ignored."""
    out = []
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        files = [i for i in z.infolist() if not i.is_dir() and i.filename.lower().endswith(IMAGE_TYPES)]
        files = [i for i in files if not any(p.startswith(("__MACOSX", ".")) for p in PurePosixPath(i.filename).parts)]
        tops = {PurePosixPath(i.filename).parts[0] for i in files if len(PurePosixPath(i.filename).parts) > 1}
        single_top = len(tops) == 1 and all(len(PurePosixPath(i.filename).parts) > 1 for i in files)
        for info in sorted(files, key=lambda i: i.filename.lower())[:ZIP_LIMIT]:
            parts = list(PurePosixPath(info.filename).parts)
            if single_top:
                parts = parts[1:]  # "TREASURE REBOOT/Haruto.jpg" -> "Haruto.jpg"
            name = "/".join(parts[-2:])  # "Haruto/IMG_1.jpg" (photo_name decides which part counts)
            out.append((name, z.read(info)))
    return out


def photo_name(name: str, members: list[str]) -> str:
    """A zipped photo's member name: its folder when the folder is a member (or the album is
    new and has no members yet), otherwise its file name."""
    if "/" not in name:
        return name
    folder, file = name.rsplit("/", 1)
    if not members or cards.match_member(members, folder):
        return folder
    return file


async def read_photos(attachments: list[discord.Attachment]) -> list[tuple[str, bytes]]:
    photos = []
    for a in attachments:
        lower = a.filename.lower()
        if lower.endswith(".zip"):
            try:
                photos += await asyncio.to_thread(unzip, await a.read())
            except zipfile.BadZipFile:
                raise ValueError(f"{a.filename} isn't a zip I can open.")
        elif lower.endswith(IMAGE_TYPES):
            photos.append((a.filename, await a.read()))
    return photos


async def run_cards(interaction: discord.Interaction, group: str, album_name: str, attachments: list[discord.Attachment], names: str | None, year: int | None, shift: str | None):
    photos = await read_photos(attachments)
    if not photos:
        raise ValueError("No photos in that (png, jpg, webp, or a .zip of them).")
    name_list = [n.strip() for n in (names or "").split(",") if n.strip()]
    if name_list and len(name_list) != len(photos):
        raise ValueError(f"`names` has {len(name_list)} names for {len(photos)} photos.")
    shifts = parse_shift(shift)
    path = songs_file(group)
    text = path.read_text(encoding="utf-8")
    group = cards.group_name(text)
    album = cards.find_album(text, album_name)

    # who's who
    picks: list[tuple[str, bytes]] = []
    unknown = []
    solo_new = album is None and cards.is_solo(text)
    known = album["members"] if album else ([group] if solo_new else [])
    photo_names = name_list or [photo_name(n, known) for n, _ in photos]
    versioned = album if album and album.get("versions", 1) > 1 else None
    if solo_new:
        # a soloist's new era: their versions, all empty yet
        versioned = {"name": album_name, "members": [group], "versions": cards.SOLO_VERSIONS, "slots": cards.version_slots([group], cards.SOLO_VERSIONS)}
    if versioned:
        block = text[album["start"]:album["end"]] if album else ""
        slots, err = cards.assign_photos(versioned, photo_names, block)
        if err:
            raise ValueError(err)
        for name, slot, (_, photo) in zip(photo_names, slots, photos):
            if slot:
                picks.append((slot, photo))
            else:
                unknown.append(name)
        if unknown:
            raise ValueError(f"Not {', '.join(versioned['members'])}: {', '.join(unknown)}. Name the photos after them (or \"{versioned['members'][0]} 2\" …).")
    for name, (_, photo) in zip([] if versioned else photo_names, photos):
        if album:
            member = cards.match_member(album["members"], name)
            if not member:
                unknown.append(name)
                continue
        else:
            member = re.sub(r"\.(png|jpe?g|webp|bmp)$", "", name, flags=re.I).replace("_", " ").strip().upper()
        if any(m == member for m, _ in picks):
            raise ValueError(f"Two photos are for {member}. Keep one (the zip or the folder may have a spare).")
        picks.append((member, photo))
    if unknown:
        raise ValueError(
            f"Not in {album['name']}: {', '.join(unknown)}.\nIts members: {', '.join(album['members'])}.\n"
            f"Rename the files, use `names`, or `/addmember` first."
        )

    # crop + preview
    crops = []
    for member, photo in picks:
        crops.append((member, await asyncio.to_thread(cards.crop_card, photo, shifts.get(cards.member_key(member), 0.0))))
    sheet = await asyncio.to_thread(cards.preview_sheet, crops)
    where = f"**{group} · {album['name'] if album else album_name}**" + ("" if album else " (new album)")
    replacing = [m for m, _ in crops if album and cards.has_art(text[album["start"]:album["end"]], m)]
    note = f"\nReplaces the art for: {', '.join(replacing)}" if replacing else ""
    view = Confirm(interaction.user.id)
    preview = await interaction.followup.send(
        f"{where}: {len(crops)} card{'s' if len(crops) != 1 else ''}. Check the crops (run it again with `shift` to move one).{note}",
        file=discord.File(io.BytesIO(sheet), "preview.png"),
        view=view,
        wait=True,
    )
    await view.done.wait()
    channel = interaction.channel
    if not view.choice:
        await channel.send("Cancelled. Nothing was uploaded.", reference=preview)
        return
    if busy.locked():
        await channel.send("Another batch is uploading. This one starts when it's done.", reference=preview)
    async with busy:
        await upload_batch(channel, preview, path, group, album_name, album, crops, year)


async def upload_batch(channel, ref, path: Path, group: str, album_name: str, album: dict | None, crops, year: int | None):
    # (plain channel messages, not interaction follow-ups: those stop working after 15 minutes)
    text = path.read_text(encoding="utf-8")
    if not album:
        if cards.is_solo(text):  # a soloist's era: one person, several versions
            text, album_id = cards.add_album(text, album_name, year or dt.date.today().year, [group], cards.SOLO_VERSIONS)
        else:
            text, album_id = cards.add_album(text, album_name, year or dt.date.today().year, [m for m, _ in crops])
        write(path, text)
        album = cards.find_album(text, album_id)
    album_id, album_title = album["id"], album["name"]

    # keep the crops in the repo
    for member, png in crops:
        out = cards.card_path(REPO, group, album_title, member)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(png)

    status = await channel.send(f"Uploading {len(crops)} to Roblox, {BATCH} at a time…", reference=ref)
    approved, rejected, failed = [], [], []
    for start in range(0, len(crops), BATCH):
        batch = crops[start:start + BATCH]
        ops = []
        for member, png in batch:
            try:
                ops.append((member, await asyncio.to_thread(cards.upload_image, API_KEY, GROUP_ID, png)))
            except Exception as e:
                failed.append((member, str(e)))
        await asyncio.sleep(BATCH_WAIT)
        waited = BATCH_WAIT
        pending = list(ops)
        while pending and waited <= POLL_LIMIT:
            still = []
            for member, op in pending:
                try:
                    state, asset = await asyncio.to_thread(cards.poll_operation, API_KEY, op)
                except Exception as e:
                    failed.append((member, str(e)))
                    continue
                if state == "Approved" and asset:
                    approved.append((member, asset))
                    write(path, cards.set_art(path.read_text(encoding="utf-8"), album_id, member, asset))
                elif state == "Rejected":
                    rejected.append(member)
                else:
                    still.append((member, op))
            pending = still
            if pending:
                await asyncio.sleep(POLL_EVERY)
                waited += POLL_EVERY
        for member, op in pending:
            failed.append((member, f"still in review (operation {op})"))
        done = start + len(batch)
        await status.edit(content=f"Uploading… {done}/{len(crops)} · ✅ {len(approved)} · ❌ {len(rejected)}" + (f" · ⚠️ {len(failed)}" if failed else ""))
        if done < len(crops):
            await asyncio.sleep(10)

    lines = [f"**{group} · {album_title}** (`{album_id}`) done."]
    if approved:
        lines.append("✅ " + ", ".join(f"{m} `{a}`" for m, a in approved) + f"\nArt written to `{path.relative_to(REPO).as_posix()}`.")
    if rejected:
        lines.append("❌ Rejected by moderation: " + ", ".join(rejected) + ". Try another photo or a tighter crop (`shift`).")
    if failed:
        lines.append("⚠️ Didn't finish: " + "; ".join(f"{m}: {e}" for m, e in failed))
        if any("HTTP 500" in e for _, e in failed):
            lines.append("(HTTP 500 is Roblox's side: try again later.)")
    if len(rejected) >= 2:
        lines.append("Several rejections in one go: give it a while before the next batch.")
    await status.reply("\n".join(lines))


# [[ /packart ]]

@tree.command(name="packart", description="Set a group's cover art (its pack sleeve and binder header)")
@app_commands.describe(group="The group (from the Songs files)", photo="An album cover or group photo (cropped to a square)",
                       album="Optional: this album's own cover (its binder page). Leave it out for the group's art")
@app_commands.autocomplete(group=group_autocomplete, album=album_autocomplete)
async def packart_command(interaction: discord.Interaction, group: str, photo: discord.Attachment, album: str | None = None):
    if not await allowed(interaction):
        return
    await interaction.response.defer(thinking=True)
    try:
        path = songs_file(group)
        group = cards.group_name(path.read_text(encoding="utf-8"))
        art = await asyncio.to_thread(cards.square_art, await photo.read())
        text = path.read_text(encoding="utf-8")
        target = cards.find_album(text, album) if album else None
        if album and not target:
            raise ValueError(f"{group} has no album called {album}. Pick one from the list.")
        if target:
            had = re.search(r'Cover\s*=\s*"rbxassetid', text[target["start"]:target["end"]]) is not None
        else:
            had = re.search(r'PackArt\s*=\s*"rbxassetid', text) is not None
        what = f"**{group} · {target['name']}** album cover" if target else f"**{group}** cover art"
        view = Confirm(interaction.user.id)
        preview = await interaction.followup.send(
            what + (" (replaces the current one)" if had else "") + ". Upload?",
            file=discord.File(io.BytesIO(art), "cover.jpg"), view=view, wait=True)
        await view.done.wait()
        if not view.choice:
            await interaction.channel.send("Cancelled. Nothing was uploaded.", reference=preview)
            return
        async with busy:
            out = cards.cover_path(REPO, group, target["name"]) if target else cards.pack_art_path(REPO, group)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(art)
            op = await asyncio.to_thread(cards.upload_image, API_KEY, GROUP_ID, art)
            waited, state, asset = 0, "Pending", None
            while waited <= POLL_LIMIT:
                await asyncio.sleep(POLL_EVERY)
                waited += POLL_EVERY
                state, asset = await asyncio.to_thread(cards.poll_operation, API_KEY, op)
                if state in ("Approved", "Rejected"):
                    break
            if state == "Approved" and asset and target:
                write(path, cards.set_album_cover(path.read_text(encoding="utf-8"), target["id"], asset))
                await interaction.channel.send(f"✅ {what} is in (`rbxassetid://{asset}`).", reference=preview)
            elif state == "Approved" and asset:
                write(path, cards.set_pack_art(path.read_text(encoding="utf-8"), asset))
                ids = REPO / "assets/Photocards/Groups/packart_ids.json"
                try:
                    import json
                    table = json.loads(ids.read_text(encoding="utf-8")) if ids.exists() else {}
                    table[group] = str(asset)
                    ids.write_text(json.dumps(table, ensure_ascii=False), encoding="utf-8")
                except Exception:
                    pass
                await interaction.channel.send(f"✅ **{group}** cover art is in (`rbxassetid://{asset}`).", reference=preview)
            elif state == "Rejected":
                await interaction.channel.send(f"❌ Moderation rejected **{group}**'s cover. Try another image.", reference=preview)
            else:
                await interaction.channel.send(f"⚠️ Still in review after {POLL_LIMIT}s (operation {op}). Run it again later.", reference=preview)
    except ValueError as e:
        await interaction.followup.send(str(e))
    except Exception as e:
        await interaction.followup.send(f"Something broke: `{type(e).__name__}: {e}`")
        raise


# [[ /albums, /addmember ]]

@tree.command(name="albums", description="A group's albums and which members are missing art")
@app_commands.autocomplete(group=group_autocomplete)
async def albums_command(interaction: discord.Interaction, group: str):
    if not await allowed(interaction):
        return
    try:
        path = songs_file(group)
    except ValueError as e:
        await interaction.response.send_message(str(e), ephemeral=True)
        return
    text = path.read_text(encoding="utf-8")
    out = [f"**{cards.group_name(text)}** (`{path.relative_to(REPO).as_posix()}`)"]
    albums = cards._albums(text)
    if not albums:
        out.append("No albums yet.")
    for a in albums:
        block = text[a["start"]:a["end"]]
        have = [m for m in a["slots"] if cards.has_art(block, m)]  # (a soloist's versions count one by one)
        missing = [m for m in a["slots"] if m not in have]
        out.append(f"• **{a['name']}** `{a['id']}`: {len(have)}/{len(a['slots'])} with art" + (f" (missing: {', '.join(missing)})" if missing else ""))
    await interaction.response.send_message("\n".join(out))


@tree.command(name="addmember", description="Add a member to an album that already exists")
@app_commands.autocomplete(group=group_autocomplete, album=album_autocomplete)
async def addmember_command(interaction: discord.Interaction, group: str, album: str, name: str):
    if not await allowed(interaction):
        return
    try:
        path = songs_file(group)
        text = path.read_text(encoding="utf-8")
        a = cards.find_album(text, album)
        if not a:
            raise ValueError(f"No album {album!r} in {cards.group_name(text)}.")
        name = name.strip().upper()
        if cards.match_member(a["members"], name):
            raise ValueError(f"{name} is already in {a['name']}.")
        write(path, cards.add_members(text, a["id"], [name]))
    except ValueError as e:
        await interaction.response.send_message(str(e), ephemeral=True)
        return
    await interaction.response.send_message(f"Added **{name}** to {a['name']}.")


# [[ Discord ]]

@client.event
async def on_ready():
    # GUILD_ID: the commands show up in that server straight away; without it they're global
    # and can take up to an hour to appear the first time
    if GUILD_ID:
        guild = discord.Object(id=GUILD_ID)
        tree.copy_global_to(guild=guild)
        synced = await tree.sync(guild=guild)
    else:
        synced = await tree.sync()
    print(f"[cardbot] logged in as {client.user} · {len(synced)} slash commands · repo {REPO} · group {GROUP_ID}")
    if not ALLOWED:
        print("[cardbot] ALLOWED_USERS is empty: nobody can use the bot. Put your Discord user id in .env")


if __name__ == "__main__":
    client.run(TOKEN)
