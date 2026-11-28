--| BoostService
-- Boost potions (ShopCatalog.Boosts): 2× coins, +50% luck in packs (Engine/AlbumService), or the
-- retired 2× XP. Buying one adds time to that kind's
-- clock (PlayerData Products, data.Boosts.Coins / .XP in seconds, capped at
-- ShopCatalog.BOOST_MAX_SECONDS). The clock only runs while the player is in the game: every
-- TICK seconds the time they've been online comes off it.
-- The client sees each clock as a player attribute, "Boost<Kind>" = the server time it ends
-- (workspace:GetServerTimeNow(); 0 = not running), for the HUD timers and the shop.
-- DuelService Rewards doubles coins / XP while BoostService.Active(data, kind).
--   BoostService.Active(data, kind: "Coins" | "XP" | "Luck"): boolean
--   BoostService.Start()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server

local TICK = 5 -- seconds between clock saves
local KINDS = { "Coins", "XP", "Luck" }

local BoostService = {}

local lastTick: { [Player]: number } = {}

function BoostService.Active(data, kind: string): boolean
	local clock = data and data.Boosts and data.Boosts[kind]
	return clock ~= nil and clock.Get() > 0
end

-- the "Boost<Kind>" attributes: when each clock runs out, in server time
local function paint(player: Player, data)
	local now = workspace:GetServerTimeNow()
	for _, kind in KINDS do
		local left = data.Boosts[kind].Get()
		local ends = if left > 0 then now + left else 0
		local shown = player:GetAttribute("Boost" .. kind) or 0
		-- only when it moves (the client counts down on its own between ticks)
		if (ends == 0) ~= (shown == 0) or math.abs(ends - shown) > 2 then
			player:SetAttribute("Boost" .. kind, ends)
		end
	end
end

-- takes the time played since the last tick off every running clock
local function tick(player: Player)
	local data = PlayerData.Get(player)
	local now = os.clock()
	local elapsed = now - (lastTick[player] or now)
	lastTick[player] = now
	if not data then
		return
	end
	local spent = math.floor(elapsed + 0.5)
	if spent > 0 then
		PlayerData.Batch(player, function()
			for _, kind in KINDS do
				local clock = data.Boosts[kind]
				local left = clock.Get()
				if left > 0 then
					clock.Set(math.max(0, left - spent))
				end
			end
		end)
	end
	paint(player, data)
end

function BoostService.Start()
	local function onJoin(player: Player)
		local data = PlayerData.WaitForData(player)
		if not data or not player.Parent then
			return
		end
		lastTick[player] = os.clock()
		paint(player, data)
		-- a potion bought: the timer appears straight away
		for _, kind in KINDS do
			data.Boosts[kind].Observe(function()
				task.defer(paint, player, data)
			end)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- (the data is already unloading here, so the last few seconds since the tick are free)
		lastTick[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for player in lastTick do
				task.spawn(tick, player)
			end
		end
	end)
end

return BoostService
