--| BadgeChat
-- Posts a system line in chat when someone in the server earns a badge (Engine/Badges sends
-- BadgeRemote { Message = "Earned", UserId, Name, Badge, Blurb }). Your own badges read
-- "You earned …"; everyone else's read "<Name> earned …". Debut is only sent to the earner.
-- Uses TextChatService's RBXSystem channel, so nothing is drawn by this script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local BadgeRemote = Bridgenet.ReferenceBridge("BadgeRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local YELLOW = "#FFE07A" -- badge name
local PINK = "#FF9EC4" -- player name

local BadgeChat = {}

-- --------------------------------- Helpers -------------------------------- --

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function systemChannel(): TextChannel?
	local channels = TextChatService:WaitForChild("TextChannels", 10)
	return channels and channels:WaitForChild("RBXSystem", 10) :: TextChannel?
end

-- ---------------------------------- Start --------------------------------- --

function BadgeChat.Start()
	BadgeRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Earned" then
			return
		end
		local channel = systemChannel()
		if not channel then
			return
		end
		local badge = `<font color="{YELLOW}"><b>{escape(tostring(packet.Badge))}</b></font>`
		local who = if packet.UserId == LOCAL_PLAYER.UserId
			then "You"
			else `<font color="{PINK}"><b>{escape(tostring(packet.Name))}</b></font>`
		channel:DisplaySystemMessage(`🏅 {who} earned the {badge} badge!`)
	end)
end

return BadgeChat
