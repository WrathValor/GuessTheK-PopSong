--| ShutdownService
-- Keeps server restarts from deciding matches. Roblox moves players to a fresh server on its
-- own when servers restart (Server Manager → Restart servers after an update, or Roblox
-- maintenance): it teleports them out, and each one leaving would otherwise forfeit their
-- match (the first out loses their streak, the other gets a free win).
-- So from the scheduled restart time (game.ServerRestartScheduled: developer update or
-- maintenance, announced up to ~30 min ahead) Duels.Halted is set: leaving then cancels a
-- match with no result, no streak or stake change. Matches before that time play out as
-- normal. BindToClose sets it too, as a fallback for restarts that aren't announced.

local Duels = require(script.Parent.DuelService.Duels)

local EARLY = 5 -- seconds before the scheduled time to halt (players can start moving right at it)

local ShutdownService = {}
ShutdownService.Closing = false

local function halt()
	ShutdownService.Closing = true
	Duels.Halted = true
end

local function scheduled(restartTime: DateTime)
	local wait = 0
	if typeof(restartTime) == "DateTime" then
		wait = math.max(0, restartTime.UnixTimestamp - os.time() - EARLY)
	end
	task.delay(wait, halt)
end

function ShutdownService.Start()
	-- (pcall: an engine without the event just falls back to BindToClose)
	pcall(function()
		game.ServerRestartScheduled:Connect(scheduled)
	end)
	game:BindToClose(halt)
end

return ShutdownService
