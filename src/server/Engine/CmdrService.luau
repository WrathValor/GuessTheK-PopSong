--| CmdrService
-- Cmdr admin console (F2) with the testing commands in ServerScriptService.Cmdr:
-- Types/ (shopStage, shopMic, shopSet, shopPass, song, pack, duelPack, soloTheme) and
-- Commands/ (one module + its <Name>Server module each). Cmdr's built-in commands are on too.
-- Who can run them: anyone in Studio; live, members of the owning group (game.CreatorId)
-- at MIN_RANK or above (or the owner, for a user-owned place). Checked on the server for
-- every command (BeforeRun), so the client-side F2 gate is only cosmetic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Cmdr = require(ReplicatedStorage.Packages.cmdr)

local CmdrService = {}

CmdrService.MIN_RANK = 254 -- group rank needed live (255 = owner)

local allowedCache: { [Player]: boolean } = {}

function CmdrService.IsAllowed(player: Player?): boolean
	if not player then
		return true -- the server itself (auto-exec etc.)
	end
	if RunService:IsStudio() then
		return true
	end
	local cached = allowedCache[player]
	if cached ~= nil then
		return cached
	end
	local allowed = false
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		allowed = ok and rank >= CmdrService.MIN_RANK
	else
		allowed = player.UserId == game.CreatorId
	end
	allowedCache[player] = allowed
	return allowed
end

function CmdrService.Start()
	local folder = ServerScriptService:WaitForChild("Cmdr")
	Cmdr.Registry:RegisterDefaultCommands()
	Cmdr.Registry:RegisterTypesIn(folder:WaitForChild("Types"))
	Cmdr.Registry:RegisterCommandsIn(folder:WaitForChild("Commands"))
	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		if not CmdrService.IsAllowed(context.Executor) then
			return "You don't have permission to use commands."
		end
		return nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		allowedCache[player] = nil
	end)
end

return CmdrService
