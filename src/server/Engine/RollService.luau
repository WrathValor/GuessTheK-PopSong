--| RollService
-- The song roll (design boards "Song roll 1–3"). A roll costs coins and pulls one song from
-- every playable song in the game, each equally likely (Songs.All, so drafts never come up):
--   • a song you don't own → it's yours (Inventory.Songs) as a Normal card
--   • a duplicate          → +1 copy (Inventory.Copies: Gold at 3, Rainbow at 5) and
--                            RollConstants.DUPLICATE_REFUND coins back
-- After PITY duplicates in a row the next pull is a song you don't own yet (while any are left).
-- Coins can be bought with Robux, so this is a paid random item: rolls are off for anyone whose
-- PolicyService says those are restricted (checked on join; if the check fails, rolls stay
-- off). The "RollsAllowed" player attribute tells the client.
--
-- Roll tickets (Season Track rewards, Inventory.Tickets): a free single roll from one group you
-- pick (a Packs group, "Group:<artist>"), every song in it equally likely. No coins, no pity
-- (DupesInRow is the coin rolls' counter); duplicates still level the card + refund coins.
--
-- RollRemote request: { Action = "Roll", Count = 1 | 10 }
--                     { Action = "Roll", Count = 1, Group = "Group:<artist>" } – spends a ticket
-- Reply:              { Message = "Rolled", Ok, Text?, Pulls = { { Song, New, Copies, Level, LevelUp } },
--                       Refund, DupesInRow, Title? = { Title, Tier, New } }
--   Title: the set title the roll unlocked or upgraded (Engine/Collection), for the reveal's
--   "TITLE UNLOCKED / UPGRADED" panel; the best one if a roll did several.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local RollConstants = require(ReplicatedStorage.Constants.RollConstants)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Analytics = require(script.Parent.Analytics)
local RewardsService = require(script.Parent.RewardsService)
local Collection = require(script.Parent.Collection)
local StreetScreens = require(script.Parent.StreetScreens)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)

local RollRemote = Bridgenet.ReferenceBridge("RollRemote")

local RollService = {}

local allowed: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}
local rng = Random.new()

-- [[ Policy ]]

local function checkPolicy(player: Player)
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	local yes = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
	if player.Parent then
		allowed[player] = yes
		player:SetAttribute("RollsAllowed", yes)
	end
end

-- [[ Rolling ]]

local function reply(player: Player, ok: boolean, text: string?, extra: { [string]: any }?)
	local packet = { Message = "Rolled", Ok = ok, Text = text }
	for k, v in extra or {} do
		packet[k] = v
	end
	RollRemote:Fire(player, packet)
end

local function roll(player: Player, count: number, groupId: string?)
	if busy[player] then
		return
	end
	if not allowed[player] then
		return reply(player, false, "Song rolls aren't available for your account")
	end
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data then
		return reply(player, false, "Your data hasn't loaded yet")
	end
	local all = Songs.All
	local group = nil
	if groupId then
		group = Packs.Get(groupId)
		if not group or group.Kind ~= "Group" then
			return reply(player, false, "That group can't be rolled")
		end
		if Currencies.Data(data, "Tickets").Get() < 1 then
			return reply(player, false, "No roll tickets left")
		end
		all, count = group.Songs, 1
	end
	if #all == 0 then
		return reply(player, false, "No songs to roll yet")
	end
	local price = if group then 0 elseif count == 10 then RollConstants.TEN_COST else RollConstants.COST
	if Currencies.Data(data, "Coins").Get() < price then
		return reply(player, false, "Not enough coins")
	end
	busy[player] = true

	-- work every pull out first, then save them in one batch
	local copies = table.clone(data.Inventory.Copies.Get() or {})
	local owned = {}
	for _, song in all do
		if data.Inventory.Songs.Has(song.Id) then
			owned[song.Id] = true
		end
	end
	local dupes = data.Inventory.DupesInRow.Get()
	local pulls, changed, refund = {}, {}, 0
	for _ = 1, count do
		local pool = all
		if dupes >= RollConstants.PITY and not group then
			local fresh = {}
			for _, song in all do
				if not owned[song.Id] then
					table.insert(fresh, song)
				end
			end
			if #fresh > 0 then
				pool = fresh
			end
		end
		local song = pool[rng:NextInteger(1, #pool)]
		local new = not owned[song.Id]
		local before = Cards.Copies(copies, owned[song.Id] == true, song.Id)
		local after = before + 1
		copies[song.Id] = after
		owned[song.Id] = true
		changed[song.Id] = true
		local level = Cards.Level(after)
		if new then
			dupes = if group then dupes else 0
		else
			dupes += if group then 0 else 1
			refund += RollConstants.DUPLICATE_REFUND
		end
		table.insert(pulls, {
			Song = Songs.Public(song),
			New = new,
			Copies = after,
			Level = level,
			LevelUp = not new and level ~= Cards.Level(before),
		})
	end

	PlayerData.Batch(player, function()
		Currencies.Data(data, "Coins").Increment(refund - price)
		if group then
			Currencies.Data(data, "Tickets").Increment(-1)
		end
		for id in changed do
			if not data.Inventory.Songs.Has(id) then
				data.Inventory.Songs.Add(id)
			end
			data.Inventory.Copies[id].Set(copies[id])
		end
		data.Inventory.DupesInRow.Set(dupes)
	end)
	busy[player] = nil

	-- the street screens: Gold / Rainbow pulls go on the gacha ticker (Rainbow on the jumbotron)
	for _, pull in pulls do
		if (pull.New or pull.LevelUp) and (pull.Level == "Gold" or pull.Level == "Rainbow") then
			StreetScreens.Pull(player, pull.Song.Name, pull.Level)
		end
	end

	-- titles: check the sets these songs are in now, so the reveal can show what changed
	local rolled = {}
	for id in changed do
		table.insert(rolled, Songs.GetById(id))
	end
	local title = nil
	for _, change in Collection.Check(data, rolled) do
		local better = not title
			or Cards.RANK[change.Tier] > Cards.RANK[title.Tier]
			or (change.Tier == title.Tier and change.New and not title.New)
		if better then
			title = change
		end
	end
	if title then
		-- what the set is ("SEVENTEEN", "HYBE"), for the reveal's line
		for _, pack in Packs.Groups() do
			if pack.Title == title.Title then
				title.Set, title.Size = pack.Name, #pack.Songs
			end
		end
		for _, pack in Packs.Companies() do
			if pack.Title == title.Title then
				title.Set, title.Size = pack.Name, #pack.Songs
			end
		end
	end

	local balance = data.Currencies.Won.Get()
	if group then
		Analytics.Event(player, "TicketRoll", 1, group.Name, if pulls[1].New then "New" else "Duplicate")
	else
		Analytics.Economy(player, "Sink", "Coins", price, balance - refund, "SongRoll", `Roll{count}`)
	end
	Analytics.Economy(player, "Source", "Coins", refund, balance, "RollRefund", "Duplicate")
	local fresh = 0
	for _, pull in pulls do
		Analytics.Event(player, "SongRolled", 1, if pull.New then "New" else "Duplicate", pull.Level, `x{count}`)
		fresh += if pull.New then 1 else 0
	end
	RewardsService.RecordNewSongs(player, fresh) -- the "new songs" daily quest
	reply(player, true, nil, { Pulls = pulls, Refund = refund, DupesInRow = dupes, Title = title, Group = group and group.Name or nil })
end

-- [[ Lifecycle ]]

function RollService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(checkPolicy, player)
	end
	Players.PlayerAdded:Connect(checkPolicy)
	Players.PlayerRemoving:Connect(function(player)
		allowed[player] = nil
		busy[player] = nil
	end)
	RollRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or packet.Action ~= "Roll" then
			return
		end
		local count = if packet.Count == 10 then 10 else 1
		local groupId = if type(packet.Group) == "string" then packet.Group else nil
		local ok, err = pcall(roll, player, count, groupId)
		if not ok then
			busy[player] = nil
			warn(`[RollService] roll failed for {player.Name}: {err}`)
			reply(player, false, "Something went wrong, try again")
		end
	end)
end

return RollService
