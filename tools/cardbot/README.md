# K-POPPED! card bot

Post photocards in Discord → they're cropped, uploaded to Roblox (group 430052409), checked by
moderation, saved in `assets/Photocards/…` and written into the album's `Art` in the group's
Songs file. Runs on your PC, in this repo, so Rojo syncs the new art into Studio straight away.

## Use it

```
/cards group:TREASURE album:REBOOT photo1:… photo2:… …
```
`group` and `album` autocomplete from the Songs files (type a new album name to add one). Attach
up to 10 photos (`photo1`…`photo10`), each named by member (`Haruto.jpg`, `Jihoon.png`; any
capitalisation, `I.N` = `in`). The bot replies with a preview: **Upload** or **Cancel**.

**A whole folder:** Discord can't send folders, so zip it (right-click → Send to → Compressed
folder) and attach the .zip as `photo1`. Any number of photos (up to 60). Name the photos by
member, or put each in a folder named after the member (`Haruto/IMG_123.jpg`). Discord's upload
limit is 10 MB without Nitro, so a big set may need two zips (`photo1`, `photo2`).

Optional fields:

| field | what it does |
|---|---|
| `names` | member names in photo order, instead of file names: `Haruto, Jihoon, Yoshi` |
| `year` | the year, when the album is new |
| `shift` | moves crops down (or up, negative) by that % of the photo: `Haruto 8, Yoshi -5` |

- An album that isn't in the Songs file yet is added (members = the photos, no songs).
- In an album that's already there, a name that isn't a member is refused, because it would
  create a new card id. Fix the name, or `/addmember` first.
- Uploading again for a member replaces their art (the preview says so).
- `/albums` lists a group's albums and who's missing art.

The crop is the same every time: it trims the card edge, then takes a 4:5 box, centred across and
starting near the top. Look at the preview before you upload, especially for low necklines, bare
shoulders, watermarks or cartoon characters (those get cards rejected), and use `shift:` or a
tighter photo. Uploads go 3 at a time with a pause between, named "K-POPPED card art" (never
numbers). Several rejections close together can earn the account a warning, so slow down if
that happens.

## Set up (once)

1. **Python 3.10+** from python.org (tick "Add to PATH"). Then in this folder:
   ```
   py -m pip install -r requirements.txt
   ```
2. **Discord bot**: discord.com/developers/applications → New Application → **Bot**:
   - Reset Token → copy it into `.env` as `DISCORD_TOKEN`
   - OAuth2 → URL Generator → scopes `bot` **and** `applications.commands`; permissions:
     Send Messages, Attach Files, Read Message History → open the URL and add it to your server
     (if it's already in the server without `applications.commands`, open the new URL again)
3. **Roblox API key**, signed in as the **alt**: create.roblox.com → Open Cloud → API Keys →
   Create: Assets API with **Read** and **Write**, and the group 430052409 under its access.
   Copy it into `.env` as `ROBLOX_API_KEY`.
4. `copy .env.example .env`, then fill in the token, the key, your Discord user id
   (`ALLOWED_USERS`) and your server id (`GUILD_ID`, so the commands appear straight away).

## Run it

```
py tools\cardbot\bot.py
```
Leave the window open while you use it (Ctrl+C stops it). Run only one copy at a time: two
copies with the same token keep knocking each other off ("session has been invalidated"). Keep Studio open with Rojo connected
if you want the art in Studio straight away; otherwise it's in the files and syncs next time.

Check a group/album without Discord:
```
py tools\cardbot\cards.py "TREASURE" "REBOOT" Haruto Jihoon
```

Renaming an album or a member isn't done here: those need `AlbumConstants.RENAMED_ALBUMS` so
saved cards move with them.
