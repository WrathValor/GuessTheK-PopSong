--| SongCard
-- Fills a song card built in Studio by ProfileController/Build.SongCard (holder → Shadow + Face
-- with a "Level" gradient, Art.Initials, SongTitle, Artist, Tag): the group's art (GroupArt),
-- the song's name and artist, and its tier finish (TierShine: Gold shines, Rainbow scrolls,
-- Normal is plain white). Used by the Profile showcase, its picker and the player card.
--   SongCard.Paint(holder, song, "Gold")   -- song nil hides the card

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local INK = C("1E1B2E")
local LILAC = C("B9A6FF")
local GOLD = C("F2C94C")

local SongCard = {}

-- "Airplane pt.2" → "AP", "BOOMBAYAH" → "B"
function SongCard.Initials(name: string): string
	local out = ""
	for word in string.gmatch(name, "[%w]+") do
		out ..= string.upper(string.sub(word, 1, 1))
		if #out == 2 then
			break
		end
	end
	return if out == "" then "♪" else out
end

function SongCard.Paint(holder: Frame, song: any?, level: string?)
	holder.Visible = song ~= nil
	if not song then
		return
	end
	local face = holder.Face
	TierShine.Apply(face, face:FindFirstChild("Level") :: UIGradient?, level, WHITE)
	GroupArt.Paint(face.Art, song)
	face.Art.Initials.Text = SongCard.Initials(song.Name)
	face.SongTitle.Text = song.Name
	face.Artist.Text = song.Artist or ""
	local tag = face.Tag
	local tier = level or "Normal"
	tag.Text = string.upper(tier)
	-- Normal: lilac · Gold: dark with gold text · Rainbow: the scrolling rainbow
	TierShine.Apply(tag, tag:FindFirstChild("Rainbow") :: UIGradient?, if tier == "Rainbow" then "Rainbow" else nil, if tier == "Gold" then INK else LILAC)
	tag.TextColor3 = if tier == "Gold" then GOLD else INK
end

return SongCard
