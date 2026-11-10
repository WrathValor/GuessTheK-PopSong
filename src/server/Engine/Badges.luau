--| Badges
-- Awards the badges in Constants/BadgeCatalog from each player's saved stats, so nothing else
-- has to call in: when a stat changes (or on join, for players who already earned one) every
-- badge whose condition holds and that they don't have yet is given. Badges with Id = 0
-- aren't made yet and are skipped. Each badge is checked against Roblox at most once per player
-- per server (UserHasBadgeAsync), and a failed award is retried on the next change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local BadgeCatalog = require(ReplicatedStorage.Constants.BadgeCatalog)
local Levels = require(ReplicatedStorage.Modules.Levels)
local Analytics = require(script.Parent.Analytics)

local CHECK_DELAY = 1 -- seconds to gather a burst of stat changes into one check

-- each badge's condition, from the player's data
local EARNED: { [string]: (any) -> boolean } = {
	Welcome = function()
		return true
	end,
	FirstWin = function(data)
		return data.Statistics.Wins.Get() >= 1
	end,
	Streak5 = function(data)
		return data.Statistics.HighestStreak.Get() >= 5
	end,
	Streak10 = function(data)
		return data.Statistics.HighestStreak.Get() >= 10
	end,
	Perfect = function(data)
		return data.Statistics.PerfectGames.Get() >= 1
	end,
	Level10 = function(data)
		return Levels.FromXP(data.Player.XP.Get()) >= 10
	end,
	FirstCard = function(data)
		return #(data.Inventory.Songs.Get() or {}) >= 1
	end,
	Collector = function(data)
		return #(data.Inventory.Songs.Get() or {}) >= 50
	end,
}

local Badges = {}

local has: { [Player]: { [string]: boolean } } = {} -- badges known to be owned (or just given)
local pending: { [Player]: boolean } = {}

-- [[ Private ]]

local function check(player: Player)
	pending[player] = nil
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data or not player.Parent then
		return
	end
	local owned = has[player] or {}
	has[player] = owned
	for _, badge in BadgeCatalog do
		local earned = EARNED[badge.Key]
		if (badge.Id or 0) > 0 and not owned[badge.Key] and earned and earned(data) then
			local okHas, already = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badge.Id)
			if okHas and already then
				owned[badge.Key] = true
			elseif okHas then
				local okAward, awarded = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badge.Id)
				if okAward and awarded then
					owned[badge.Key] = true
					Analytics.Event(player, "BadgeEarned", 1, badge.Key)
				else
					warn(`[Badges] couldn't award {badge.Key} to {player.Name}:`, awarded)
				end
			end
		end
	end
end

-- a check soon (many stats change at once at the end of a duel)
local function queue(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(CHECK_DELAY, check, player)
end

local function onJoin(player: Player)
	if not PlayerData.WaitForData(player) then
		return
	end
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data then
		return
	end
	for _, stat in {
		data.Statistics.Wins,
		data.Statistics.HighestStreak,
		data.Statistics.PerfectGames,
		data.Player.XP,
		data.Inventory.Songs,
	} do
		stat.Observe(function()
			queue(player)
		end)
	end
	queue(player)
end

-- [[ Public ]]

function Badges.Start()
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		has[player], pending[player] = nil, nil
	end)
end

return Badges
