--| DailySongChat
-- Posts a system line in chat when someone in the server shares their Daily Song result
-- (Engine/DailySongService sends DailySongRemote { Message = "Shared", UserId, Name, Number,
-- Marks, Solved }). The squares are coloured ■ in the game's palette (emoji squares came out
-- as tiny flat bars in chat), never the song, so nobody's day is spoiled. Your own share reads
-- "You …". Same RBXSystem channel and yellow highlight as Client/BadgeChat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local DailySongConstants = require(ReplicatedStorage.Constants.DailySongConstants)

local DailySongRemote = Bridgenet.ReferenceBridge("DailySongRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local YELLOW = "#FFE07A" -- "Daily Song #n" (as badge names)
local PINK = "#FF9EC4" -- player name
local SQUARE = { Wrong = "#FF5A4E", Skip = "#8E879C", Right = "#A7E9B8" }
local EMPTY = "#4A4460" -- tries not needed

local DailySongChat = {}

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function systemChannel(): TextChannel?
	local channels = TextChatService:WaitForChild("TextChannels", 10)
	return channels and channels:WaitForChild("RBXSystem", 10) :: TextChannel?
end

function DailySongChat.Start()
	DailySongRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Shared" or type(packet.Marks) ~= "table" then
			return
		end
		local channel = systemChannel()
		if not channel then
			return
		end
		local squares = {}
		for i = 1, DailySongConstants.TRIES do
			squares[i] = `<font color="{SQUARE[packet.Marks[i]] or EMPTY}" size="22">■</font>`
		end
		local who = if packet.UserId == LOCAL_PLAYER.UserId
			then "You"
			else `<font color="{PINK}"><b>{escape(tostring(packet.Name))}</b></font>`
		local daily = `<font color="{YELLOW}"><b>Daily Song #{tonumber(packet.Number) or 0}</b></font>`
		local outcome = if packet.Solved
			then `solved {daily} in <b>{#packet.Marks}/{DailySongConstants.TRIES}</b>`
			else `missed {daily}`
		channel:DisplaySystemMessage(`🎧 {who} {outcome}  {table.concat(squares, " ")}`)
	end)
end

return DailySongChat
