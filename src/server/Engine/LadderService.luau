--| LadderService
-- Pays group badge rungs (Modules/Library/Ladders, design board 48). Whenever a player's
-- photocards (Inventory.Cards) or song stars (Inventory.Mastery) change, and once on join, every
-- group's Cards and Songs rungs are worked out again; a rung higher than the one saved in
-- Inventory.Ladders pays its coins (and those of any rungs skipped on the way) and is saved, so it
-- is never paid twice and never lost. Diamond on both ladders pays Legend once ("L:<artist>").
-- Each rung reached logs BadgeRung (Ladder, Group; value = the rung, 6 = Legend), so we can see
-- where players stall before tuning the requirements.
--
-- BinderRemote, server → client: { Message = "Binder", Action = "Badge", Ok = true, Coins,
--   Badges = { { Artist, Ladder = "Cards" | "Songs" | "Legend", Rung } } } (best first: the HUD
--   toasts the first one, "+n more")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)
local Mastery = require(ReplicatedStorage.Modules.Library.Mastery)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Analytics = require(script.Parent.Analytics)

local BinderRemote = Bridgenet.ReferenceBridge("BinderRemote")

local CHECK_DELAY = 0.5 -- seconds to gather a burst of changes (a 10-pack, a round's stars)
local JOIN_QUIET = 8 -- seconds after joining before a toast is sent (the client is still loading)

local LadderService = {}

local queued: { [Player]: boolean } = {}
local joinedAt: { [Player]: number } = {}

-- [[ Checking ]]

local function check(player: Player)
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data or not player.Parent then
		return
	end
	local cards = data.Inventory.Cards.Get() or {}
	local mastery = data.Inventory.Mastery.Get() or {}
	local saved = data.Inventory.Ladders.Get() or {}

	local reached = {} -- { { Key, Artist, Ladder, From, To } }
	for _, artist in Ladders.Groups() do
		local rungs = { Cards = (Ladders.CardsRung(cards, artist)), Songs = (Ladders.SongsRung(mastery, artist)) }
		for ladder, rung in rungs do
			local key = Ladders.Key(ladder, artist)
			local had = saved[key] or 0
			if rung > had then
				table.insert(reached, { Key = key, Artist = artist, Ladder = ladder, From = had, To = rung })
			end
		end
		local cardsTop = math.max(rungs.Cards, saved[Ladders.Key("Cards", artist)] or 0) >= Ladders.TOP
		local songsTop = math.max(rungs.Songs, saved[Ladders.Key("Songs", artist)] or 0) >= Ladders.TOP
		local legend = Ladders.LegendKey(artist)
		if cardsTop and songsTop and (saved[legend] or 0) < 1 then
			table.insert(reached, { Key = legend, Artist = artist, Ladder = "Legend", From = 0, To = 1 })
		end
	end
	if #reached == 0 then
		return
	end

	local coins = 0
	for _, r in reached do
		r.Coins = if r.Ladder == "Legend" then Ladders.COINS.Legend else Ladders.CoinsBetween(r.Ladder, r.From, r.To)
		coins += r.Coins
	end
	PlayerData.Batch(player, function()
		for _, r in reached do
			data.Inventory.Ladders[r.Key].Set(r.To)
		end
		if coins > 0 then
			Currencies.Data(data, "Coins").Increment(coins)
			data.Statistics.CoinsEarned.Increment(coins)
		end
	end)

	for _, r in reached do
		Analytics.Event(player, "BadgeRung", if r.Ladder == "Legend" then Ladders.TOP + 1 else r.To, r.Ladder, r.Artist)
	end
	if coins > 0 then
		Analytics.Economy(player, "Source", "Coins", coins, Currencies.Data(data, "Coins").Get(), AnalyticsEvents.Transactions.Binder, "Badge")
	end

	-- best first: Legend, then the highest rung
	table.sort(reached, function(a, b)
		local ra = if a.Ladder == "Legend" then Ladders.TOP + 1 else a.To
		local rb = if b.Ladder == "Legend" then Ladders.TOP + 1 else b.To
		if ra ~= rb then
			return ra > rb
		end
		return a.Artist:lower() < b.Artist:lower()
	end)
	local badges = {}
	for _, r in reached do
		table.insert(badges, { Artist = r.Artist, Ladder = r.Ladder, Rung = r.To })
	end
	local packet = { Message = "Binder", Action = "Badge", Ok = true, Coins = coins, Badges = badges }
	local wait = JOIN_QUIET - (os.clock() - (joinedAt[player] or 0))
	if wait > 0 then
		task.delay(wait, function()
			if player.Parent then
				BinderRemote:Fire(player, packet)
			end
		end)
	else
		BinderRemote:Fire(player, packet)
	end
end

local function queue(player: Player)
	if queued[player] then
		return
	end
	queued[player] = true
	task.delay(CHECK_DELAY, function()
		queued[player] = nil
		local ok, err = pcall(check, player)
		if not ok then
			warn(`[LadderService] check failed for {player.Name}: {err}`)
		end
	end)
end

-- [[ Public ]]

-- the rung saved for a ladder key ("C:aespa"); 0 if none
function LadderService.Saved(data, key: string): number
	return (data.Inventory.Ladders.Get() or {})[key] or 0
end

-- [[ Lifecycle ]]

local function onPlayerAdded(player: Player)
	joinedAt[player] = os.clock()
	local data = PlayerData.WaitForData(player)
	if not data or not player.Parent then
		return
	end
	data.Inventory.Cards.Observe(function()
		queue(player)
	end)
	data.Inventory.Mastery.Observe(function()
		queue(player)
	end)
	queue(player)
	-- Studio only: the player's "LadderTest" attribute, "<artist>|<stars>|<count>?", gives that
	-- many of the group's songs (all if no count) that many stars, to test the Songs tab
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("LadderTest"):Connect(function()
			local value = player:GetAttribute("LadderTest")
			local artist, stars, count = string.match(tostring(value), "^(.-)|(%d)|?(%d*)$")
			stars = tonumber(stars)
			if not artist or not stars then
				return
			end
			local entry = ({ [0] = "1,0,0,0", [1] = "2,1,0,5", [2] = "3,2,0,3", [3] = "6,5,3,1" })[stars]
			local ids = Mastery.GroupSongs(artist)
			PlayerData.Batch(player, function()
				for i, id in ids do
					if count == "" or i <= tonumber(count) then
						data.Inventory.Mastery[id].Set(entry)
					end
				end
			end)
		end)
	end
end

function LadderService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		queued[player] = nil
		joinedAt[player] = nil
	end)
end

return LadderService
