--| VIPChat
-- VIP Pass owners (the "VIP" player attribute) in chat: a gold "★ VIP" tag in front of their
-- name, and the name in gold too (design board "VIP 2 · VIP shows everywhere you are").
-- Uses TextChatService.OnIncomingMessage, so nothing is drawn by this script; only messages
-- from players are touched (system lines like BadgeChat's have no TextSource).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local GOLD = "#FFE07A"
local TAG = `<font color="{GOLD}"><b>★ VIP</b></font>`

local VIPChat = {}

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function VIPChat.Start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if player and player:GetAttribute("VIP") == true then
			props.PrefixText = `{TAG} <font color="{GOLD}">{escape(player.DisplayName)}:</font>`
		end
		return props
	end
end

return VIPChat
