--| StreakReminders
-- The daily login's "don't lose your streak" experience notification (Roblox's notification
-- feed, opted-in players 13+, at most one a day from the game). One reminder per player, 4 hours
-- before the 00:00 UTC reset, on a day they haven't claimed yet with a streak of 2+:
--   • "Daily Streak"  "Your {days}-day streak resets in 4 hours. Claim today's reward to keep it!"
--   • "Big Day!"      on a day 7: "Your day 7 reward is waiting: {coins} coins + a 2× Coins
--                     potion. Claim it before it resets!"
-- (the strings live in the Creator Hub: the live game → Engagement → Notifications)
-- The Join button brings them in; the daily login pops up on join as usual.
-- Each player's next reminder sits in a MemoryStore sorted map (key: user id, sort key: when
-- it's due), rewritten whenever they join, claim or leave, so claiming moves it to tomorrow
-- and nobody is reminded about a day they've already claimed. Every server checks the map
-- once a minute and sends what's due; a "Sent" mark claimed through UpdateAsync makes sure
-- only one server sends each one.
-- Sending goes through Roblox's official "Open Cloud" package (Creator Store, by Roblox) at
-- ServerStorage.OpenCloud (not ServerScriptService: Rojo owns that and would remove it);
-- without it (or outside the live game) nothing is sent.
--   StreakReminders.Schedule(player, data)   -- RewardsService after a daily claim
--   StreakReminders.Send(player, kind)      -- the notifyme command: one now, for testing
--   StreakReminders.Start()

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Analytics = require(script.Parent.Analytics)

-- the notification strings (Creator Hub asset ids, live game only)
local MESSAGES = {
	Streak = "e4a0631b-06fa-aa4e-a2be-8b4c9ded682c", -- "Daily Streak"
	BigDay = "c8e0cfbe-3477-cc42-809d-07d0b1f6073c", -- "Big Day!"
}
local ENABLED = ShopCatalog.LIVE -- (the strings belong to the live game)

local REMIND_AT = 20 * 3600 -- seconds into the UTC day: 4 hours before the reset
local MIN_STREAK = 2 -- a streak this long or longer is worth a reminder
local POLL = 60 -- seconds between checks of the map
local BATCH = 50 -- reminders read per check
local TTL = 3 * 86400 -- a reminder that's never sent drops out of the map after this
local LAUNCH_DATA = "DailyLogin"

local StreakReminders = {}

local map = nil
local function store()
	if not map then
		local ok, m = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, "StreakReminders")
		map = if ok then m else nil
	end
	return map
end

local userNotification = nil
local function sender()
	if userNotification == nil then
		-- (ServerStorage: Rojo leaves unknown things there alone; it owns ServerScriptService)
		local package = ServerStorage:FindFirstChild("OpenCloud") or ServerScriptService:FindFirstChild("OpenCloud")
		local module = package and package:FindFirstChild("V2") and package.V2:FindFirstChild("UserNotification")
		local ok, api = pcall(function()
			return require(module :: any)
		end)
		userNotification = if ok and api then api else false
		if not userNotification then
			warn("[StreakReminders] the Open Cloud package isn't in ServerStorage.OpenCloud; reminders are off")
		end
	end
	return userNotification or nil
end

-- [[ Pure parts (tests/StreakReminders.spec) ]]

-- the reminder a player should get next, or nil: { Due, Day, Kind, Days, Coins }
-- streak / last = Rewards.DailyStreak / LastDailyClaim, now = os.time()
function StreakReminders.Next(streak: number, last: number, now: number)
	local today = Catalog.Day(now)
	local lastDay = if last > 0 then Catalog.Day(last) else -1000
	local day, days
	if lastDay == today then
		-- claimed today: remind tomorrow, about the streak as it stands now
		day, days = today + 1, streak
	elseif lastDay == today - 1 and now < today * 86400 + REMIND_AT then
		-- not claimed yet today, the streak's still alive, and it isn't reminder time yet
		day, days = today, streak
	else
		return nil -- the streak's gone (or today's reminder time has passed)
	end
	if days < MIN_STREAK then
		return nil
	end
	-- the step they'd claim that day: day 7 of a week gets the Big Day message
	local index = (days % #Catalog.DAILY) + 1
	local _, dayOfWeek = Catalog.DailyWeek(index)
	local reward = Catalog.DAILY[index]
	local big = dayOfWeek == Catalog.DAILY_DAYS
	return {
		Due = day * 86400 + REMIND_AT,
		Day = day,
		Kind = if big then "BigDay" else "Streak",
		Days = days,
		Coins = reward and reward.Coins or 0,
	}
end

-- the request body for the Open Cloud package
function StreakReminders.Payload(reminder)
	local parameters = if reminder.Kind == "BigDay"
		then { coins = { int64Value = reminder.Coins } }
		else { days = { int64Value = reminder.Days } }
	return {
		payload = {
			messageId = MESSAGES[reminder.Kind],
			type = "MOMENT",
			parameters = parameters,
			joinExperience = { launchData = LAUNCH_DATA },
			analyticsData = { category = reminder.Kind },
		},
	}
end

-- [[ Scheduling ]]

-- writes (or clears) a player's next reminder from their data
function StreakReminders.Schedule(player: Player, data)
	if not ENABLED or player.UserId <= 0 then
		return
	end
	local m = store()
	if not m then
		return
	end
	local key = tostring(player.UserId)
	local reminder = StreakReminders.Next(data.Rewards.DailyStreak.Get(), data.Rewards.LastDailyClaim.Get(), os.time())
	task.spawn(function()
		local ok, err = pcall(function()
			if reminder then
				m:SetAsync(key, reminder, TTL, reminder.Due)
			else
				m:RemoveAsync(key)
			end
		end)
		if not ok then
			warn("[StreakReminders] couldn't schedule", player.Name, err)
		end
	end)
end

-- [[ Sending ]]

local function send(userId: number, reminder): (boolean, string?)
	local api = sender()
	if not api then
		return false, "no Open Cloud package"
	end
	local ok, result = pcall(api.createUserNotification, userId, StreakReminders.Payload(reminder))
	if not ok then
		return false, tostring(result)
	end
	if result and result.statusCode == 200 then
		return true
	end
	local e = result and result.error
	return false, `{result and result.statusCode} {e and e.code} {e and e.message}`
end

-- the notifyme command: send this player one now (Roblox still applies its one-a-day limit)
function StreakReminders.Send(player: Player, kind: string?): (boolean, string?)
	local data = PlayerData.WaitForData(player)
	if not data then
		return false, "no data"
	end
	local streak = math.max(data.Rewards.DailyStreak.Get(), MIN_STREAK)
	local index = (streak % #Catalog.DAILY) + 1
	local reminder = { Kind = if kind == "BigDay" then "BigDay" else "Streak", Days = streak, Coins = (Catalog.DAILY[index].Coins or 500) }
	if reminder.Kind == "BigDay" and reminder.Coins <= 0 then
		reminder.Coins = 500
	end
	return send(player.UserId, reminder)
end

-- one pass over the due reminders: mark each Sent (only one server wins it), send, remove
local function poll()
	local m = store()
	if not m then
		return
	end
	local now = os.time()
	local ok, items = pcall(m.GetRangeAsync, m, Enum.SortDirection.Ascending, BATCH, nil, { sortKey = now })
	if not ok or not items then
		return
	end
	for _, item in items do
		local userId = tonumber(item.key)
		local reminder = item.value
		if not userId or type(reminder) ~= "table" then
			pcall(m.RemoveAsync, m, item.key)
			continue
		end
		-- too late for that day (the reset has passed): drop it
		if now >= (reminder.Day + 1) * 86400 then
			pcall(m.RemoveAsync, m, item.key)
			continue
		end
		-- someone playing right here gets the pop-up instead
		if Players:GetPlayerByUserId(userId) then
			continue
		end
		local won = false
		pcall(m.UpdateAsync, m, item.key, function(current, sortKey)
			if type(current) ~= "table" or current.Sent or current.Day ~= reminder.Day then
				return nil -- another server has it, or it was rescheduled
			end
			current.Sent = true
			won = true
			return current, sortKey
		end, TTL)
		if won then
			local sent, why = send(userId, reminder)
			Analytics.Event(nil, "StreakReminder", 1, reminder.Kind, if sent then "Sent" else "Failed")
			if not sent then
				warn(`[StreakReminders] {userId} {reminder.Kind}: {why}`)
			end
			pcall(m.RemoveAsync, m, item.key)
		end
	end
end

function StreakReminders.Start()
	if not ENABLED or RunService:IsStudio() then
		return -- (the strings are the live game's; Studio would send real notifications)
	end
	local function track(player: Player)
		local data = PlayerData.WaitForData(player)
		if data then
			StreakReminders.Schedule(player, data)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		task.spawn(track, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local data = PlayerData.GetData and PlayerData.GetData(player)
		if data then
			StreakReminders.Schedule(player, data)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(POLL + math.random() * 10) -- (servers spread their checks out)
			poll()
		end
	end)
end

return StreakReminders
