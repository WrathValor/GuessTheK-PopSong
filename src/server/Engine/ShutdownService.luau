--| ShutdownService
-- Server restarts: keeps them from deciding matches, and tells players one is coming.
-- Roblox moves players to a fresh server on its own when servers restart (Server Manager →
-- Restart servers after an update, or Roblox maintenance): it teleports them out, and each one
-- leaving would otherwise forfeit their match (the first out loses their streak, the other
-- gets a free win).
--   • From the scheduled restart time (game.ServerRestartScheduled: developer update or
--     maintenance, announced up to a few hours ahead) Duels.Halted is set: leaving then
--     cancels a match with no result, no streak or stake change. Matches before that time
--     play out as normal. BindToClose sets it too, as a fallback for unannounced restarts.
--   • NO_NEW_DUELS seconds before it, Duels.NoNewDuels stops new duels and ghost games from
--     starting (Quick Play and stepping on next to someone show a "restarting soon" toast;
--     solo practice still starts), so nobody gets cut off halfway through a game.
--   • The restart is published as JSON on ReplicatedStorage's "Restart" attribute for the
--     client (Controllers/RestartController: the lobby banner, the in-duel pill and the
--     hand-over card): { At = unix time, Kind = "Update" | "Maintenance", Title?, Message? }.
--     Title / Message come from the restart's attributes, which you can type in the Creator
--     Hub's Confirm Server Restart dialog as JSON, e.g.
--         { "title": "NEW EVENT!", "message": "The Christmas event is here!" }
--     Both are optional and run through the text filter; maintenance restarts never have them.
--   • RestartRemote { Action = "Hop" }: the banner's HOP OVER NOW. Teleports that player to
--     another server of this place (Roblox's matchmaking skips servers that are restarting,
--     so it's an updated one).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Duels = require(script.Parent.DuelService.Duels)
local Analytics = require(script.Parent.Analytics)

local RestartRemote = Bridgenet.ReferenceBridge("RestartRemote")

local EARLY = 5 -- seconds before the scheduled time to halt (players can start moving right at it)
local NO_NEW_DUELS = 180 -- seconds before it that no new duels start (a duel runs ~2–3 min)
local MAX_TITLE, MAX_MESSAGE = 24, 80 -- characters (the banner's room)
local HOP_EVERY = 10 -- seconds between one player's Hop requests

local ShutdownService = {}
ShutdownService.Closing = false

local token = 0 -- bumped by every new schedule, so a Simulate() replaces the last one
local lastHop: { [Player]: number } = {}

local function halt()
	ShutdownService.Closing = true
	Duels.Halted = true
end

-- a text the developer typed into the restart's attributes, filtered for everyone (TextService
-- needs a user to filter "from": any player here will do). nil if missing, empty or blocked.
local function clean(value: any, max: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = string.sub(string.gsub(value, "^%s+", ""), 1, max)
	text = string.gsub(text, "%s+$", "")
	if text == "" then
		return nil
	end
	if RunService:IsStudio() then
		return text -- (the filter doesn't run in Studio)
	end
	local from = Players:GetPlayers()[1]
	if not from then
		return nil
	end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, from.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok or result == "" or string.find(result, "^#+$") then
		return nil
	end
	return result
end

local function attr(attributes: any, key: string): any
	if type(attributes) ~= "table" then
		return nil
	end
	-- (any capitalisation: "message", "Message")
	for k, v in attributes do
		if type(k) == "string" and string.lower(k) == key then
			return v
		end
	end
	return nil
end

-- Publishes the restart and arms the timers. `at` is the unix time it happens.
local function schedule(at: number, kind: string, attributes: any, halts: boolean)
	token += 1
	local mine = token
	local info = { At = at, Kind = kind }
	if kind == "Update" then
		info.Title = clean(attr(attributes, "title"), MAX_TITLE)
		info.Message = clean(attr(attributes, "message"), MAX_MESSAGE)
	end
	ReplicatedStorage:SetAttribute("Restart", HttpService:JSONEncode(info))
	task.delay(math.max(0, at - os.time() - NO_NEW_DUELS), function()
		if token == mine then
			Duels.NoNewDuels = true
		end
	end)
	if halts then
		task.delay(math.max(0, at - os.time() - EARLY), function()
			if token == mine then
				halt()
			end
		end)
	end
end

local function scheduled(restartTime: DateTime, source: Enum.CloseReason?, attributes: any)
	local at = if typeof(restartTime) == "DateTime" then restartTime.UnixTimestamp else os.time()
	local kind = if source == Enum.CloseReason.RobloxMaintenance then "Maintenance" else "Update"
	schedule(at, kind, attributes, true)
end

-- Cmdr `restartsim`: shows the whole restart flow in a test server without closing it (and
-- without halting matches). seconds <= 0 clears it.
function ShutdownService.Simulate(seconds: number, kind: string?, title: string?, message: string?)
	if seconds <= 0 then
		token += 1
		Duels.NoNewDuels = false
		ReplicatedStorage:SetAttribute("Restart", nil)
		return
	end
	schedule(os.time() + math.floor(seconds), kind or "Update", { title = title, message = message }, false)
end

local function hop(player: Player)
	if not ReplicatedStorage:GetAttribute("Restart") then
		return
	end
	local now = os.clock()
	if lastHop[player] and now - lastHop[player] < HOP_EVERY then
		return
	end
	lastHop[player] = now
	if player:GetAttribute("Stage") or player:GetAttribute("PartyStage") then
		return -- (on a stage: finish there first; the banner hides in duels anyway)
	end
	Analytics.Event(player, "RestartHop", 1)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		warn("[ShutdownService] Hop failed:", err)
		RestartRemote:Fire(player, { Message = "HopFailed" })
	end
end

function ShutdownService.Start()
	-- (pcall: an engine without the event just falls back to BindToClose)
	pcall(function()
		game.ServerRestartScheduled:Connect(scheduled)
	end)
	game:BindToClose(halt)
	RestartRemote:Connect(function(player: Player, packet: any)
		if type(packet) == "table" and packet.Action == "Hop" then
			hop(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHop[player] = nil
	end)
	-- (a teleport can also fail after TeleportAsync returns: tell the banner so HOP works again)
	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		if lastHop[player] and os.clock() - lastHop[player] < HOP_EVERY * 3 then
			RestartRemote:Fire(player, { Message = "HopFailed" })
		end
	end)
end

return ShutdownService
