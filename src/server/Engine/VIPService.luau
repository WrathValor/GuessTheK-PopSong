--| VIPService
-- The VIP Pass's daily perks (ShopCatalog.Passes "VIP"; its looks live on the client: NameTags,
-- VIPChat, the ★ VIP chips). Each UTC day (os.time() // 86400) a VIP gets:
--   • one free roll ticket, paid on join, the moment the pass is bought, or at midnight if
--     they're still playing (Rewards.VIPTicketDay). The reveal:
--       RewardsRemote, server → client: { Message = "VIPDaily", Rewards = { { Key = "Tickets",
--         Kind = "Currency", Amount = 1 } } }  (PurchasedController shows it once you're free)
--   • one free Save Streak (Rewards.VIPSaveDay): the "VIPSaveFree" player attribute says it's
--     still there today, and the Save Streak popup offers it in place of the Robux price.
--       VIPRemote, client → server: { Request = "SaveStreak" }
--       VIPRemote, server → client: { Message = "SaveStreak", Ok = bool }
--     Same as the Save Streak product: the lost streak comes back (PlayerData Products.SaveStreak).
-- Neither helps anyone win a duel.
-- The map leaderboards (client/Client/Leaderboards) show ★ VIP on VIP rows. Boards list players
-- who aren't in the server, so ownership is checked with Roblox (UserOwnsGamePassAsync, cached
-- per player for CHECK_EVERY) for everyone in a board's top 10, and the VIPs' UserIds go on
-- ReplicatedStorage (attribute BOARD_ATTRIBUTE, a comma-separated list). Players in the server
-- count from their own data (a pass given in-game counts too).
--   VIPService.Start()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Analytics = require(script.Parent.Analytics)

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")
local VIPRemote = Bridgenet.ReferenceBridge("VIPRemote")

local DAILY_TICKETS = 1
local SAVE_ATTRIBUTE = "VIPSaveFree"
local BOARD_ATTRIBUTE = "VIPOnBoards"
-- the map leaderboards (PlayerData Leaderboards) and how many rows each sign shows
local BOARDS = { "MostWins", "MostAnswers", "TopStreaks", "PerfectGames", "TopFans" }
local BOARD_ROWS = 10
local CHECK_EVERY = 30 * 60 -- seconds before a player's pass is asked about again
local VIP_PASS = (ShopCatalog.GetPass("VIP") or {}).GamePassId or 0

local VIPService = {}

local busy: { [Player]: boolean } = {}
local owners: { [number]: { VIP: boolean, At: number } } = {} -- board players, by UserId
local scanning = false

local function today(): number
	return os.time() // 86400
end

local function isVIP(data): boolean
	return data.GamePasses.Has("VIP") == true
end

-- the free Save Streak's attribute, for the popup
local function paintSave(player: Player, data)
	local free = isVIP(data) and data.Rewards.VIPSaveDay.Get() < today()
	player:SetAttribute(SAVE_ATTRIBUTE, if free then true else nil)
end

-- today's free ticket, if it's due
local function payTicket(player: Player, data)
	if busy[player] or not isVIP(data) or data.Rewards.VIPTicketDay.Get() >= today() then
		return
	end
	busy[player] = true
	PlayerData.Batch(player, function()
		data.Rewards.VIPTicketDay.Set(today())
		Currencies.Data(data, "Tickets").Increment(DAILY_TICKETS)
	end)
	Analytics.Economy(player, "Source", "Tickets", DAILY_TICKETS, Currencies.Data(data, "Tickets").Get(), AnalyticsEvents.Transactions.VIPDaily, "VIPDaily")
	RewardsRemote:Fire(player, {
		Message = "VIPDaily",
		Rewards = { { Key = "Tickets", Kind = "Currency", Amount = DAILY_TICKETS } },
	})
	busy[player] = nil
end

local function refresh(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	payTicket(player, data)
	paintSave(player, data)
end

local function freeSave(player: Player)
	local data = PlayerData.Get(player)
	local ok = false
	if data and isVIP(data) and data.Rewards.VIPSaveDay.Get() < today() and data.Player.LostStreak.Get() > 0 then
		PlayerData.Batch(player, function()
			local lost = data.Player.LostStreak.Get()
			if lost > data.Player.Streak.Get() then
				data.Player.Streak.Set(lost)
			end
			data.Player.LostStreak.Set(0)
			data.Rewards.VIPSaveDay.Set(today())
		end)
		ok = true
	end
	if data then
		paintSave(player, data)
	end
	VIPRemote:Fire(player, { Message = "SaveStreak", Ok = ok })
end

-- does this board player own VIP? (their data if they're here, else Roblox, cached)
local function ownsVIP(userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player:GetAttribute("VIP") == true
	end
	local known = owners[userId]
	if known and os.clock() - known.At < CHECK_EVERY then
		return known.VIP
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, userId, VIP_PASS)
	if not ok then
		return if known then known.VIP else false
	end
	owners[userId] = { VIP = owns == true, At = os.clock() }
	return owns == true
end

-- the VIPs in every board's top rows, onto ReplicatedStorage for the signs
local function scanBoards()
	if scanning or VIP_PASS <= 0 then
		return
	end
	scanning = true
	local vips, seen = {}, {}
	for _, name in BOARDS do
		local ok, entries = pcall(PlayerData.GetLeaderboard, name, BOARD_ROWS)
		for _, entry in (if ok and type(entries) == "table" then entries else {}) do
			local id = tonumber(entry.UserId)
			if id and id > 0 and not seen[id] then
				seen[id] = true
				if ownsVIP(id) then
					table.insert(vips, tostring(id))
				end
			end
		end
	end
	ReplicatedStorage:SetAttribute(BOARD_ATTRIBUTE, table.concat(vips, ","))
	scanning = false
end

function VIPService.Start()
	local function onJoin(player: Player)
		local data = PlayerData.WaitForData(player)
		if not data then
			return
		end
		refresh(player)
		-- bought the pass mid-session: today's perks straight away
		data.GamePasses.Observe(function()
			task.defer(refresh, player)
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)

	VIPRemote:Connect(function(player: Player, packet)
		if type(packet) == "table" and packet.Request == "SaveStreak" then
			freeSave(player)
		end
	end)

	-- the leaderboards: on every board update, when a player's VIP changes, and every few minutes
	ReplicatedStorage:SetAttribute(BOARD_ATTRIBUTE, "")
	PlayerData.OnLeaderboard:Connect(function()
		task.defer(scanBoards)
	end)
	task.spawn(function()
		while true do
			scanBoards()
			task.wait(300)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("VIP"):Connect(function()
			task.defer(scanBoards)
		end)
	end)

	-- a new UTC day while people are still playing
	task.spawn(function()
		local day = today()
		while true do
			task.wait(30)
			if today() ~= day then
				day = today()
				for _, player in Players:GetPlayers() do
					task.spawn(refresh, player)
				end
			end
		end
	end)
end

return VIPService
