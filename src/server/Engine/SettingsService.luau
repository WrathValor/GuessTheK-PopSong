--| SettingsService
-- Saves the Settings screen's changes. The client copy of PlayerData is read-only, so the
-- screen asks here and everything is checked before it's written.
--
-- SettingsRemote requests: { Action = "SetVolume", Key = "MusicVolume" | "SfxVolume" | "ClipVolume", Value = 0–1 }
--                          { Action = "SetInvites", Value = bool }
--                          { Action = "Reset" }                 (volumes back to 1, invites on)
--                          { Action = "SeenNews", Id = newsId } (clears the News button dot)
--                          { Action = "FavoritePrompted" }       (the one-time favourite prompt was shown)
--                          { Action = "Blocked", Ids = { userId } } (the player's Roblox block list,
--                            sent by Client/SettingsController; kept in memory, never saved)
-- Invites (Engine/InviteService duels, Engine/PartyService parties) ask AcceptsInvitesFrom:
-- the target has invites on, and neither player has blocked the other on Roblox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local News = require(ReplicatedStorage.Constants.News)
local Analytics = require(script.Parent.Analytics)

local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

local VOLUMES = { MusicVolume = true, SfxVolume = true, ClipVolume = true }
local MAX_BLOCKED = 1000 -- ids kept per player's block list
local MIN_GAP = 0.1 -- requests closer together than this are dropped (slider spam)

local SettingsService = {}

local last: { [Player]: number } = {}
local blocked: { [Player]: { [number]: boolean } } = {} -- Roblox block lists, by player

-- analytics: a slider sends many values while dragging, so only log where it settles
local SETTLE = 2
local pendingLog: { [Player]: { [string]: thread } } = {}
local function logSetting(player: Player, key: string, value: string)
	pendingLog[player] = pendingLog[player] or {}
	local old = pendingLog[player][key]
	if old then
		pcall(task.cancel, old)
	end
	pendingLog[player][key] = task.delay(SETTLE, function()
		if pendingLog[player] then
			pendingLog[player][key] = nil
		end
		Analytics.Event(player, "SettingChanged", 1, key, value)
	end)
end

local function handle(player: Player, packet)
	-- (the block list comes in at join, often before the player's data has loaded)
	if packet.Action == "Blocked" then
		if type(packet.Ids) == "table" then
			local set, n = {}, 0
			for _, id in packet.Ids do
				if type(id) == "number" and id == math.floor(id) and n < MAX_BLOCKED then
					set[id] = true
					n += 1
				end
			end
			blocked[player] = set
		end
		return
	end
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local settings = data.Settings
	local action = packet.Action
	if action == "SetVolume" then
		local value = tonumber(packet.Value)
		if VOLUMES[packet.Key] and value and value == value then
			local v = math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
			settings[packet.Key].Set(v)
			logSetting(player, packet.Key, `{math.floor(v * 10 + 0.5) * 10}%`) -- 10% buckets
		end
	elseif action == "SetInvites" then
		if type(packet.Value) == "boolean" then
			settings.DuelInvites.Set(packet.Value)
			logSetting(player, "DuelInvites", if packet.Value then "On" else "Off")
		end
	elseif action == "Reset" then
		PlayerData.Batch(player, function()
			for key in VOLUMES do
				settings[key].Set(1)
			end
			settings.DuelInvites.Set(true)
		end)
		logSetting(player, "Reset", "Reset")
	elseif action == "TutorialDone" then
		-- skipped the tutorial (finishing it is marked by the duel's rewards)
		if settings.TutorialDone.Get() ~= true then
			settings.TutorialDone.Set(true)
			logSetting(player, "Tutorial", "Skipped")
		end
	elseif action == "FavoritePrompted" then
		if settings.FavoritePrompted.Get() ~= true then
			settings.FavoritePrompted.Set(true)
		end
	elseif action == "SeenNews" then
		local newest = News.Entries[1]
		if newest and packet.Id == newest.Id then
			settings.NewsSeen.Set(newest.Id)
		end
	end
end

-- Has `target` got invites on? (Settings → Duel invites; covers duel and party invites)
function SettingsService.AcceptsInvites(target: Player): boolean
	-- (Get throws while the data is still loading: no invites until it has)
	local ok, data = pcall(PlayerData.Get, target)
	return ok and data ~= nil and data.Settings.DuelInvites.Get() == true
end

-- Has either player blocked the other on Roblox?
function SettingsService.Blocks(a: Player, b: Player): boolean
	local ofA, ofB = blocked[a], blocked[b]
	return (ofA ~= nil and ofA[b.UserId] == true) or (ofB ~= nil and ofB[a.UserId] == true)
end

-- May `sender` send `target` an invite (or a join request)?
function SettingsService.AcceptsInvitesFrom(target: Player, sender: Player): boolean
	return SettingsService.AcceptsInvites(target) and not SettingsService.Blocks(target, sender)
end

function SettingsService.Start()
	SettingsRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		if packet.Action ~= "SetVolume" or now - (last[player] or 0) >= MIN_GAP then
			last[player] = now
			local ok, err = pcall(handle, player, packet)
			if not ok then
				warn("[SettingsService]", packet.Action, err)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
		pendingLog[player] = nil
		blocked[player] = nil
	end)
end

return SettingsService
