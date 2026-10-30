--| CmdrController
-- Opens the Cmdr console with F2 for players allowed to use it (Studio, or the owning
-- group's MIN_RANK+, matching Engine/CmdrService). The server checks every command again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local MIN_RANK = 254 -- keep in step with CmdrService.MIN_RANK

local CmdrController = {}

local function allowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank >= MIN_RANK
	end
	return player.UserId == game.CreatorId
end

function CmdrController.Start()
	task.spawn(function()
		local Cmdr = require(ReplicatedStorage:WaitForChild("CmdrClient"))
		Cmdr:SetActivationKeys({ Enum.KeyCode.F2 })
		Cmdr:SetEnabled(allowed(Players.LocalPlayer))
	end)
end

return CmdrController
