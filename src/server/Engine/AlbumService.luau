--| AlbumService
-- Opening K-POPPED! photocard packs (design boards "22 · Packs" to "25 · Pack summary").
-- Three kinds of pack (AlbumConstants):
--   Free    1 card from a gen you pick (Gen = "2nd" … "5th", or none for any). Paid for with a
--           banked free pack (Inventory.FreePacks: they refill on a clock, Albums.FreePacks, plus
--           one a day), or a roll ticket when none are banked.
--   Gen     PACK_SIZE cards, each from a random group of that gen. GEN_PACK_COST coins.
--   Group   PACK_SIZE cards from the group you pick. GROUP_PACK_COST coins. The only pack your
--           bias is BIAS_PULL_WEIGHT× as likely in. Only today's groups are on sale
--           (Albums.Rotation), plus your bias's group and your starred ones (Inventory.FavGroups).
--   Gen     also the MIXES: Gen = "Girl" | "Boy" | "All".
--   Premium PACK_SIZE cards from any group with a rarity floor (AlbumConstants.PREMIUM_PACKS):
--           PACK_SIZE - 1 from CardMin up, one from LastMin up; the GUARANTEE_RARITY pity
--           (Inventory.PremiumPity) makes the PREMIUM_GUARANTEE-th pack in a row end with one.
-- Each card is one of the group's albums (each equally likely), then a rarity, then a member
-- (Modules/Library/Albums.RollGroup). The card belongs to that album, which is the binder page
-- it goes on:
--   • a card you don't own   → it's yours (Inventory.Cards) at Normal
--   • a duplicate            → +1 copy of that exact card id: Gold at GOLD_COPIES, Rainbow at
--                              RAINBOW_COPIES. Copies past Rainbow are sold at once (Sell price).
-- A pack's cards come back worst to best, so the best one is always last. There's no pity for
-- new cards: every card is rolled at its odds, owned or not. Every change banks the binder
-- first (Engine/BinderService).
-- Collecting and duels are separate: nothing here touches songs.
--
-- Coins can be bought with Robux, so this is a paid random item: packs are off unless the
-- "RollsAllowed" attribute (checkPolicy below: PolicyService's ArePaidRandomItemsRestricted;
-- the name is from the song roll, which had the same rule) is true. The Packs page
-- shows the odds before opening.
--
-- The first one: a free group pack, once per account, after picking a bias (Rewards.Claimed
-- FIRST_ALBUM_KEY).
--
-- Numbered rarities (Fansign Benefit and up) get serial numbers, and a One of One is claimed for
-- the whole game before it's saved (Engine/SerialService): see that file. Pulls carry Serial.
--
-- Lucky Draw and rarer pulls, and Gold / Rainbow level-ups, are announced to the whole server:
-- AlbumRemote to everyone, { Message = "Pull", UserId, Name, Card, Member, Artist, Album,
-- Rarity, Serial?, Level?, More? } – the best card of the open; More = other announced cards
-- with it. Signed Polaroids and One of Ones go to every server too (Global = true there).
--
-- AlbumRemote request: { Action = "Open", Kind = "Free", Gen?, Count = 1 | "All" }
--                      { Action = "Open", Kind = "Gen", Gen, Count = 1 | 5 | 10 }
--                      { Action = "Open", Kind = "Group", Group, Count = 1 | 5 | 10 }
--                      { Action = "Open", Kind = "Premium", Pack = key, Count = 1 | 5 | 10 }
--                      { Action = "Open", Kind = "Free", Ticket = true } (Unopened: use a ticket)
--                      { Action = "Star", Group } → { Message = "Starred", Ok, Text?, Favourites }
--                      { Action = "First", Group = artist }
-- Reply:               { Message = "Opened", Ok, Text?, Kind, Group?, Gen?, How, Packs, Size, Short?,
--                        Pulls = { { Card, Album, Artist, Member, Rarity, New, Copies, Level, LevelUp, Sold, Serial? } },
--                        Sold (coins for copies past Rainbow), Complete? = { album ids whose page just filled },
--                        SetBonus? = coins paid for them (Engine/BinderService.ClaimSets) }
--   How = "Coins" | "Free" | "Ticket" | "First". Pulls run pack after pack, Size cards each.
--   Short = { Kind = "Coins" | "Tickets", Need, Name } when you can't pay (ShortOfferController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Analytics = require(script.Parent.Analytics)
local BinderService = require(script.Parent.BinderService)
local SerialService = require(script.Parent.SerialService)
local RewardsService = require(script.Parent.RewardsService)
local StreetScreens = require(script.Parent.StreetScreens)

local AlbumRemote = Bridgenet.ReferenceBridge("AlbumRemote")

local AlbumService = {}

local busy: { [Player]: boolean } = {}
local rng = Random.new()

local function reply(player: Player, ok: boolean, text: string?, extra: { [string]: any }?)
	local packet = { Message = "Opened", Ok = ok, Text = text }
	for k, v in extra or {} do
		packet[k] = v
	end
	AlbumRemote:Fire(player, packet)
end

-- [[ Announcing ]]

-- tells the server about the best card of an open, if it's worth it (rarity.Announce, or a
-- Gold / Rainbow level-up). Engine/UniqueService will add the cross-server One of One banner.
local function announce(player: Player, pulls)
	local best, bestScore, count = nil, 0, 0
	for _, pull in pulls do
		local rarity = Albums.Rarity(pull.Rarity)
		local levelled = (pull.New or pull.LevelUp) and (pull.Level == "Gold" or pull.Level == "Rainbow")
		if (pull.New and rarity and rarity.Announce) or levelled then
			count += 1
			local score = Albums.RarityRank(pull.Rarity) * 10 + (Albums.LEVEL_RANK[pull.Level] or 0)
			if score > bestScore then
				best, bestScore = pull, score
			end
		end
	end
	if not best then
		return
	end
	local packet = {
		Message = "Pull",
		UserId = player.UserId,
		Name = player.DisplayName,
		Card = best.Card,
		Member = best.Member,
		Artist = best.Artist,
		Album = (Albums.Get(best.Album) or {}).Name,
		Rarity = best.Rarity,
		Serial = best.Serial,
		Level = if best.Level ~= "Normal" then best.Level else nil,
		More = if count > 1 then count - 1 else nil,
	}
	AlbumRemote:Fire(Bridgenet.AllPlayers(), packet)
	-- the gacha machine's ticker on the street (Engine/StreetScreens)
	local rarity = Albums.Rarity(best.Rarity)
	StreetScreens.Pull(player, `{best.Member} · {best.Artist}`, rarity and rarity.Name or best.Rarity, AlbumConstants.GLOBAL_RARITIES[best.Rarity] == true)
	-- a Signed Polaroid or a One of One is news in every server
	for _, pull in pulls do
		if pull.New and AlbumConstants.GLOBAL_RARITIES[pull.Rarity] then
			SerialService.Broadcast(if pull == best then packet else {
				Message = "Pull",
				UserId = player.UserId,
				Name = player.DisplayName,
				Card = pull.Card,
				Member = pull.Member,
				Artist = pull.Artist,
				Album = (Albums.Get(pull.Album) or {}).Name,
				Rarity = pull.Rarity,
				Serial = pull.Serial,
			})
		end
	end
end

-- [[ Free packs ]]

-- brings the free-pack bank up to date (refills, today's daily pack, a new player's first ones).
-- Call inside a Batch. Returns the free packs banked now.
local function settleFree(data, now: number): number
	local packs, at = data.Inventory.FreePacks.Get(), data.Inventory.FreePackAt.Get()
	local day = now // 86400
	if at == 0 then
		packs, at = AlbumConstants.FREE_PACK_START, now
		data.Inventory.FreePackDay.Set(day)
	end
	packs, at = Albums.FreePacks(packs, at, now)
	if data.Inventory.FreePackDay.Get() ~= day then
		data.Inventory.FreePackDay.Set(day)
		packs = math.min(packs + 1, AlbumConstants.FREE_PACK_CAP)
		if packs >= AlbumConstants.FREE_PACK_CAP then
			at = now
		end
	end
	if packs ~= data.Inventory.FreePacks.Get() then
		data.Inventory.FreePacks.Set(packs)
	end
	if at ~= data.Inventory.FreePackAt.Get() then
		data.Inventory.FreePackAt.Set(at)
	end
	return packs
end

-- [[ Opening ]]

local function validGen(gen: any): boolean
	if type(gen) ~= "string" then
		return false
	end
	if table.find(AlbumConstants.GENERATIONS, gen) then
		return true
	end
	for _, mix in AlbumConstants.MIXES do
		if mix.Key == gen then
			return true
		end
	end
	return false
end

local function open(player: Player, kind: string, packet, how: "Coins" | "Free" | "Ticket" | "First")
	local artist = if kind == "Group" then packet.Group else nil
	local gen = if (kind == "Gen" or kind == "Free") and validGen(packet.Gen) then packet.Gen else nil
	local premium = if kind == "Premium" then Albums.Premium(packet.Pack) else nil
	local extra: { [string]: any } = { Kind = kind, Group = artist, Gen = gen, Pack = premium and premium.Key, How = how }
	if kind == "Premium" and not premium then
		return reply(player, false, "That pack isn't out yet", extra)
	elseif kind == "Group" and (type(artist) ~= "string" or not Albums.Pullable(artist)) then
		return reply(player, false, "That group isn't out yet", extra)
	elseif kind == "Gen" and not gen then
		return reply(player, false, "Pick a generation", extra)
	elseif #Albums.ArtistsInGen(gen) == 0 then
		return reply(player, false, "Those packs aren't out yet", extra)
	end
	if player:GetAttribute("RollsAllowed") ~= true then
		return reply(player, false, "Packs aren't available for your account", extra)
	end
	local data = PlayerData.Get(player)
	if not data then
		return reply(player, false, "Your data hasn't loaded yet", extra)
	end
	local bias = data.Inventory.Bias.Get()
	local now = os.time()
	local size = if kind == "Free" then 1 else AlbumConstants.PACK_SIZE
	local packs = 1
	local price = 0
	if how == "First" then
		if data.Rewards.Claimed.Has(AlbumConstants.FIRST_ALBUM_KEY) then
			return reply(player, false, "Your free pack is already used", extra)
		end
		if bias == "" then
			return reply(player, false, "Pick your bias first", extra)
		end
	elseif kind == "Free" then
		local banked = 0
		PlayerData.Batch(player, function()
			banked = settleFree(data, now)
		end)
		if banked > 0 and packet.Ticket ~= true then
			how = "Free"
			packs = if packet.Count == "All" then math.min(banked, AlbumConstants.FREE_OPEN_MAX) else 1
		elseif Currencies.Data(data, "Tickets").Get() > 0 then
			how = "Ticket"
		else
			extra.How = "Free"
			return reply(player, false, "No free packs yet: the next one is on its way", extra)
		end
		extra.How = how
	else
		if kind == "Group" and not Albums.InRotation(artist, bias, now, data.Inventory.FavGroups.Get()) then
			return reply(player, false, "That group's pack has rotated out: check today's groups", extra)
		end
		packs = if table.find(AlbumConstants.PACK_COUNTS, packet.Count) then packet.Count else 1
		price = packs * (if premium then premium.Cost elseif kind == "Gen" then AlbumConstants.GEN_PACK_COST else AlbumConstants.GROUP_PACK_COST)
		if Currencies.Data(data, "Coins").Get() < price then
			extra.Short = { Kind = "Coins", Need = price, Name = if packs == 1 then "a pack" else `{packs} packs` }
			return reply(player, false, "Not enough coins", extra)
		end
	end

	-- work every card out first, then save them in one batch
	local cards = table.clone(data.Inventory.Cards.Get() or {})
	local before = table.clone(cards)
	local hit = {}
	local changed = {}
	local pulls, sold = {}, 0
	local premiumPity = data.Inventory.PremiumPity.Get()
	local guaranteeRank = Albums.RarityRank(AlbumConstants.GUARANTEE_RARITY)
	for _ = 1, packs do
		local pack = {}
		local guaranteed = premium ~= nil and premiumPity >= AlbumConstants.PREMIUM_GUARANTEE - 1
		local best = 0
		for slot = 1, size do
			local minKey = nil
			if premium then
				minKey = if slot < size then premium.CardMin elseif guaranteed then AlbumConstants.GUARANTEE_RARITY else premium.LastMin
			end
			local album, memberKey, rarityKey
			if kind == "Group" then
				album, memberKey, rarityKey = Albums.RollGroup(artist, bias, rng)
			else
				album, memberKey, rarityKey = Albums.RollGen(gen, rng, nil, nil, minKey)
			end
			assert(album and memberKey and rarityKey, "no album to pull from")
			-- One of One: only if nobody in any server owns this one yet
			if rarityKey == "oneofone" and not SerialService.Claim(Albums.CardId(album.Id, memberKey, rarityKey), player) then
				rarityKey = AlbumConstants.FALLBACK_RARITY
			end
			best = math.max(best, Albums.RarityRank(rarityKey))
			hit[album.Id] = true
			local id = Albums.CardId(album.Id, memberKey, rarityKey)
			local had = cards[id] or 0
			local after, extraSold = had, 0
			if had >= AlbumConstants.RAINBOW_COPIES then
				extraSold = Albums.SellPrice(id) or 0 -- maxed out: this copy is sold straight away
			else
				after = had + 1
				cards[id] = after
				changed[id] = true
			end
			sold += extraSold
			local new = had == 0
			local member = Albums.Member(album, memberKey)
			local level = Albums.Level(after)
			table.insert(pack, {
				Card = id,
				Album = album.Id,
				Artist = album.Artist,
				Member = member and member.Name or memberKey,
				Rarity = rarityKey,
				New = new,
				Copies = after,
				Level = level,
				LevelUp = not new and level ~= Albums.Level(had),
				Sold = if extraSold > 0 then extraSold else nil,
				Order = #pack,
			})
		end
		-- worst to best: the best card is always last
		table.sort(pack, function(a, b)
			local ra, rb = Albums.RarityRank(a.Rarity), Albums.RarityRank(b.Rarity)
			if ra ~= rb then
				return ra < rb
			end
			return a.Order < b.Order
		end)
		for _, pull in pack do
			pull.Order = nil
			table.insert(pulls, pull)
		end
		if premium then
			premiumPity = if best >= guaranteeRank then 0 else premiumPity + 1
		end
	end

	-- serial numbers for the numbered copies kept (Engine/SerialService; a copy sold straight
	-- away past Rainbow gets none). One that can't be minted now waits in SerialsPending.
	local serials, pending = {}, {}
	for _, pull in pulls do
		if pull.Sold or not Albums.Numbered(pull.Card) then
			continue
		end
		local serial = if pull.Rarity == "oneofone" then 1 else SerialService.Mint(pull.Card)
		pull.Serial = serial
		if serial then
			serials[pull.Card] = Albums.AddSerial(serials[pull.Card] or data.Inventory.Serials[pull.Card].Get(), serial)
		else
			pending[pull.Card] = (pending[pull.Card] or 0) + 1
		end
	end
	if next(serials) or next(pending) then
		-- (minting yields: if coins were spent elsewhere meanwhile, don't take more than there is)
		price = math.min(price, Currencies.Data(data, "Coins").Get() + sold)
	end

	PlayerData.Batch(player, function()
		BinderService.Bank(data)
		Currencies.Data(data, "Coins").Increment(sold - price)
		if how == "Ticket" then
			Currencies.Data(data, "Tickets").Increment(-1)
		elseif how == "Free" then
			local banked = settleFree(data, now)
			local left = math.max(0, banked - packs)
			data.Inventory.FreePacks.Set(left)
			if banked >= AlbumConstants.FREE_PACK_CAP and left < AlbumConstants.FREE_PACK_CAP then
				data.Inventory.FreePackAt.Set(now) -- the clock starts again from now
			end
		elseif how == "First" then
			data.Rewards.Claimed.Add(AlbumConstants.FIRST_ALBUM_KEY)
		end
		for id in changed do
			data.Inventory.Cards[id].Set(cards[id])
			-- the day you first rolled it
			if (cards[id] or 0) > 0 and (data.Inventory.CardDates[id].Get() or 0) == 0 then
				data.Inventory.CardDates[id].Set(now)
			end
		end
		for id, value in serials do
			data.Inventory.Serials[id].Set(value)
		end
		for id, count in pending do
			data.Inventory.SerialsPending[id].Set((data.Inventory.SerialsPending[id].Get() or 0) + count)
		end
		if premium then
			data.Inventory.PremiumPity.Set(premiumPity)
		end
	end)

	announce(player, pulls)

	-- numbered copies: who rolled them (for their history; previous owners come with trading)
	task.spawn(function()
		for _, pull in pulls do
			if pull.Serial and not pull.Sold then
				SerialService.Record(pull.Card, pull.Serial, player)
			end
		end
	end)

	local balance = Currencies.Data(data, "Coins").Get()
	local sku = `{kind}{packs}`
	if price > 0 then
		Analytics.Economy(player, "Sink", "Coins", price, balance - sold, AnalyticsEvents.Transactions.Album, sku)
	elseif how == "Ticket" then
		Analytics.Economy(player, "Sink", "Tickets", 1, Currencies.Data(data, "Tickets").Get(), AnalyticsEvents.Transactions.Album, "Ticket")
	end
	if sold > 0 then
		Analytics.Economy(player, "Source", "Coins", sold, balance, AnalyticsEvents.Transactions.CardSell, "PastRainbow")
	end
	for _, pull in pulls do
		Analytics.Event(player, "AlbumOpened", 1, pull.Album, pull.Rarity, if how == "Coins" then sku else how)
	end

	local complete = {}
	for id in hit do
		local album = Albums.Get(id)
		if album and not Albums.Complete(before, album) and Albums.Complete(cards, album) then
			table.insert(complete, id)
		end
	end
	local fresh = 0
	for _, pull in pulls do
		if pull.New then
			fresh += 1
		end
	end
	RewardsService.RecordNewCards(player, fresh) -- the "new photocards" quests

	extra.Packs = packs
	extra.Size = size
	extra.Pulls = pulls
	extra.Sold = sold
	extra.Complete = if #complete > 0 then complete else nil
	if #complete > 0 then
		-- every member of these albums owned now: their one-time set bonus (Engine/BinderService)
		extra.SetBonus = BinderService.ClaimSets(player, data, complete)
	end
	reply(player, true, nil, extra)
end

-- [[ Starring groups ]]

-- star / unstar a group: starred groups' packs are always on sale (FAVOURITES_MAX of them)
local function star(player: Player, artist: any)
	local function answer(ok: boolean, text: string?, favourites: { string }?)
		AlbumRemote:Fire(player, { Message = "Starred", Ok = ok, Text = text, Favourites = favourites })
	end
	local data = PlayerData.Get(player)
	if not data or type(artist) ~= "string" or not Albums.Pullable(artist) then
		return answer(false, "That group isn't out yet")
	end
	local list = Albums.Favourites(data.Inventory.FavGroups.Get())
	local at = table.find(list, artist)
	if at then
		table.remove(list, at)
	elseif #list >= AlbumConstants.FAVOURITES_MAX then
		return answer(false, `You can star {AlbumConstants.FAVOURITES_MAX} groups: unstar one first`, list)
	else
		table.insert(list, artist)
	end
	PlayerData.Batch(player, function()
		data.Inventory.FavGroups.Set(table.concat(list, "|"))
	end)
	answer(true, nil, list)
end

-- [[ Lifecycle ]]

-- paid random items: packs are off unless PolicyService says they're allowed here (checked on
-- join; if the check fails they stay off). The "RollsAllowed" attribute tells the client.
local function checkPolicy(player: Player)
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	local yes = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
	if player.Parent then
		player:SetAttribute("RollsAllowed", yes)
	end
end

local function onPlayerAdded(player: Player)
	task.spawn(checkPolicy, player)
	local data = PlayerData.WaitForData(player)
	if not data or not player.Parent then
		return
	end
	PlayerData.Batch(player, function()
		settleFree(data, os.time())
	end)
	BinderService.ClaimSets(player, data) -- (albums completed before set bonuses existed)
end

function AlbumService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
	-- keep everyone's free packs ticking over (and the daily one at midnight UTC) while they play
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.Get(player)
				if data and not busy[player] then
					PlayerData.Batch(player, function()
						settleFree(data, os.time())
					end)
				end
			end
		end
	end)
	AlbumRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local kind, how
		if packet.Action == "Star" then
			local ok, err = pcall(star, player, packet.Group)
			if not ok then
				warn(`[AlbumService] star failed for {player.Name}: {err}`)
			end
			return
		elseif packet.Action == "First" then
			kind, how = "Group", "First"
		elseif packet.Action == "Open" and (packet.Kind == "Free" or packet.Kind == "Gen" or packet.Kind == "Group" or packet.Kind == "Premium") then
			kind, how = packet.Kind, if packet.Kind == "Free" then "Free" else "Coins"
		else
			return
		end
		busy[player] = true
		local ok, err = pcall(open, player, kind, packet, how)
		busy[player] = nil
		if not ok then
			warn(`[AlbumService] open failed for {player.Name}: {err}`)
			reply(player, false, "Something went wrong, try again", { Kind = kind, Group = packet.Group, How = how })
		end
	end)
end

return AlbumService
