--| PullChat
-- Posts a system line in chat when someone in the server pulls a good photocard (the song roll's
-- Gold / Rainbow song card lines went with it, 25 Nov 2026). Your own read "You …". Same
-- RBXSystem channel as Client/BadgeChat, so nothing is drawn by this script.
--
-- Engine/AlbumService announces (AlbumRemote { Message = "Pull", UserId,
-- Name, Member, Artist, Rarity, Serial?, Level?, More?, Global? }), Lucky Draw and up:
--   ✨ Mina pulled a FANSIGN BENEFIT #12: Jisoo · BLACKPINK!
--   💎 Mina pulled a ONE OF ONE: Jisoo · BLACKPINK! Nobody else will ever have it.
-- A Signed Polaroid or One of One from another server (Global) reads "… in another server".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local AlbumRemote = Bridgenet.ReferenceBridge("AlbumRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local GOLD = "#F2C94C"
local PINK = "#FF9EC4" -- player name
local SONG = "#FFE07A" -- song name
local RAINBOW = { "#FFB3C7", "#FFF1A8", "#B8F0C8", "#B5DDFF", "#D8C4FF" }
-- photocard rarities, in their Rarities-sheet colours
local RARITY_COLOUR = { luckydraw = "#DDE6F0", fansign = "#FF9EC4", polaroid = "#F2C94C" }
local RARITY_NAME = {
	luckydraw = "LUCKY DRAW",
	fansign = "FANSIGN BENEFIT",
	polaroid = "SIGNED POLAROID",
	oneofone = "ONE OF ONE",
}

local PullChat = {}

-- --------------------------------- Helpers -------------------------------- --

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function systemChannel(): TextChannel?
	local channels = TextChatService:WaitForChild("TextChannels", 10)
	return channels and channels:WaitForChild("RBXSystem", 10) :: TextChannel?
end

-- a word in the rainbow's colours, a letter each
local function rainbow(word: string): string
	local out = {}
	for i, letter in string.split(word, "") do
		table.insert(out, if letter == " " then " " else `<font color="{RAINBOW[(i - 1) % #RAINBOW + 1]}">{letter}</font>`)
	end
	return `<b>{table.concat(out)}</b>`
end

local function cardLine(packet): string?
	local name = RARITY_NAME[packet.Rarity]
	if not name then
		return nil
	end
	local who = if packet.UserId == LOCAL_PLAYER.UserId
		then "You"
		else `<font color="{PINK}"><b>{escape(tostring(packet.Name))}</b></font>`
	local card = `<font color="{SONG}"><b>{escape(tostring(packet.Member))}</b></font>`
	if packet.Artist then
		card ..= ` · {escape(tostring(packet.Artist))}`
	end
	if packet.Rarity == "oneofone" then
		local where = if packet.Global then " in another server" else ""
		return `💎 {who} pulled a {rainbow(name)}{where}: {card}! Nobody else will ever have it.`
	end
	local rarity = `<font color="{RARITY_COLOUR[packet.Rarity] or GOLD}"><b>{name}</b></font>`
	local serial = tonumber(packet.Serial)
	if serial then
		rarity ..= ` <b>#{serial}</b>`
	end
	local where = if packet.Global then " in another server" else ""
	local line = `✨ {who} pulled a {rarity}{where}: {card}!`
	local more = tonumber(packet.More)
	if more and more > 0 then
		line ..= ` (+{more} more)`
	end
	return line
end

-- ---------------------------------- Start --------------------------------- --

function PullChat.Start()
	AlbumRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Pull" then
			return
		end
		local line = cardLine(packet)
		local channel = line and systemChannel()
		if channel then
			channel:DisplaySystemMessage(line)
		end
	end)
end

return PullChat
