--| GiftChat
-- Posts a system line in chat when someone in the server gifts something (Engine/GiftService
-- sends GiftRemote { Message = "Announce", From, To, Item } to everyone, the giver and the
-- recipient included): "🎁 <From> has gifted <To> VIP Pass!". The giver also gets "<name> says thanks!" when they're thanked
-- ({ Message = "Thanks", From }). Same RBXSystem channel as Client/BadgeChat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local GiftRemote = Bridgenet.ReferenceBridge("GiftRemote")

local PINK = "#FF9EC4" -- player names
local YELLOW = "#FFE07A" -- the gift

local GiftChat = {}

-- --------------------------------- Helpers -------------------------------- --

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function systemChannel(): TextChannel?
	local channels = TextChatService:WaitForChild("TextChannels", 10)
	return channels and channels:WaitForChild("RBXSystem", 10) :: TextChannel?
end

local function name(text: any): string
	return `<font color="{PINK}"><b>{escape(tostring(text))}</b></font>`
end

-- ---------------------------------- Start --------------------------------- --

function GiftChat.Start()
	GiftRemote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Message == "Announce" then
			local channel = systemChannel()
			if not channel then
				return
			end
			local item = `<font color="{YELLOW}"><b>{escape(tostring(packet.Item))}</b></font>`
			channel:DisplaySystemMessage(`🎁 {name(packet.From)} has gifted {name(packet.To)} {item}!`)
		elseif packet.Message == "Thanks" then
			local channel = systemChannel()
			if channel then
				channel:DisplaySystemMessage(`💗 {name(packet.From)} says thanks for the gift!`)
			end
		end
	end)
end

return GiftChat
