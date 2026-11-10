--| SeasonService
-- Server side of the season (Constants/SeasonConstants, design boards "Seasons 1–12"):
--   • Stars: duels played / won, daily quests claimed and solo games each give Stars
--     (SeasonConstants.STARS), up to DAILY_STARS of each a UTC day. Engine/DuelService/Rewards and
--     Engine/RewardsService call SeasonService.Award.
--   • the Season Track: every STARS_PER_MILESTONE Stars unlocks the next milestone; claiming
--     (in order) grants it: coins, roll tickets, card upgrades, the S0 banners / photocard.
--     Some milestones give a title on top (spec.Title / TitleTier). Mic milestones have no item
--     yet: they just count as claimed.
--   • card upgrades: +1 copy on a song you own (same as pulling it again: Gold at 3, Rainbow
--     at 5, Modules/Library/Cards). Roll tickets are spent by Engine/RollService.
--   • Season Points (SP): rated 1v1 duels move them (Rate, from DuelService/Rewards; tuning in
--     SeasonConstants.SP). Peak SP is kept for the season-end rewards. SP goes on the Ranks
--     board (./Board, an OrderedDataStore per season), with season wins on a second board.
--   • season rollover (SeasonConstants.SCHEDULE / Current): the first time a player is seen in a
--     new season their old peak SP goes into Season.History, their season-end title is granted
--     ("S1 Rookie", END_TITLE_TIER), and Stars / milestones / counts / SP start over
--     (tickets / upgrades keep).
-- Mirrored for the client as attributes: SeasonSP, SeasonPeakSP, SeasonStars, SeasonClaimed,
-- SeasonDuels, SeasonWins, Coins, Tickets, Upgrades.
--
-- SeasonRemote requests: { Action = "Claim", N = milestone }
--                        { Action = "UseUpgrade", Id = songId }
--                        { Action = "Board", Kind = "SP" | "Wins" }   (the Ranks tab)
-- Reply:                 { Message = "Result", Action, Ok, Text, N?, Kind?, Amount?, Id?, Copies?, Board? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Analytics = require(script.Parent.Analytics)
local Collection = require(script.Parent.Collection)
local Board = require(script.Board)

local SeasonRemote = Bridgenet.ReferenceBridge("SeasonRemote")

local SeasonService = {}

local DAY = 24 * 60 * 60
local DAILY_FIELD = { Duel = "DuelsToday", Quest = "QuestsToday", Solo = "SoloToday" }

local busy: { [Player]: boolean } = {}

-- [[ Helpers ]]

local function reply(player: Player, packet)
	packet.Message = "Result"
	SeasonRemote:Fire(player, packet)
end

-- the season-end title for a peak SP in `season` ("S1 Rookie"), and its title tier; nil for Trainee
local function endTitle(season, peak: number): (string?, number?)
	if not season or peak <= 0 then
		return nil, nil
	end
	local tier = SeasonConstants.TierOf(peak).Tier.Name
	local titleTier = SeasonConstants.END_TITLE_TIER[tier]
	if not titleTier then
		return nil, nil
	end
	return `{season.Badge or season.Id} {tier}`, titleTier
end

-- a new season id: keep last season's peak, give its end title, start the track and SP over
local function syncSeason(data)
	local id = SeasonConstants.Current().Id
	local old = data.Season.Id.Get()
	if old == id then
		return
	end
	if old ~= "" then
		local peak = data.Season.PeakSP.Get()
		if peak > 0 then
			data.Season.History[old].Set(peak)
		end
		local title, titleTier = endTitle(SeasonConstants.Find(old), peak)
		if title then
			if not data.Inventory.Titles.Has(title) then
				data.Inventory.Titles.Add(title)
			end
			data.Inventory.TitleTiers[title].Set(titleTier :: number)
		end
	end
	data.Season.Id.Set(id)
	for _, name in { "Stars", "Claimed", "Duels", "Wins", "DuelsToday", "QuestsToday", "SoloToday", "SP", "PeakSP" } do
		data.Season[name].Set(0)
	end
end

-- a new UTC day: the daily counts start over
local function syncDay(data)
	local today = math.floor(os.time() / DAY)
	if data.Season.Day.Get() ~= today then
		data.Season.Day.Set(today)
		data.Season.DuelsToday.Set(0)
		data.Season.QuestsToday.Set(0)
		data.Season.SoloToday.Set(0)
	end
end

-- [[ Stars ]]

-- source = "Duel" | "Quest" | "Solo"; won: a duel win (+Win Stars on top). Returns the Stars given.
function SeasonService.Award(player: Player, source: string, won: boolean?): number
	local data = PlayerData.Get(player)
	local field = DAILY_FIELD[source]
	if not data or not field or not SeasonConstants.ENABLED then
		return 0
	end
	local stars = 0
	PlayerData.Batch(player, function()
		syncSeason(data)
		syncDay(data)
		if source == "Duel" then
			data.Season.Duels.Increment(1)
			if won then
				data.Season.Wins.Increment(1)
				Board.Mark(player, "Wins", data.Season.Wins.Get())
			end
		end
		if data.Season[field].Get() >= SeasonConstants.DAILY_STARS[source] then
			return -- today's limit for this one
		end
		data.Season[field].Increment(1)
		stars = SeasonConstants.STARS[source] + (if source == "Duel" and won then SeasonConstants.STARS.Win else 0)
		data.Season.Stars.Increment(stars)
	end)
	return stars
end

-- [[ Season Points ]]

-- rated games between the same two players today (the SAME_RIVAL win-trading guard)
local pairGames: { [string]: number } = {}
local pairDay = 0

local function pairKey(a: Player, b: Player): string
	local x, y = a.UserId, b.UserId
	return if x < y then `{x}:{y}` else `{y}:{x}`
end

-- SP change for one side. outcome: "Win" | "Lose" | "Draw"
local function spDelta(mine: number, rival: number, outcome: string, scale: number): number
	local rules = SeasonConstants.SP
	if outcome == "Draw" then
		return 0
	end
	local gap = math.clamp(math.floor((rival - mine) / rules.GAP_STEP + 0.5), -rules.GAP_CAP, rules.GAP_CAP)
	if outcome == "Win" then
		return math.floor(math.max(rules.MIN_WIN, rules.WIN + gap) * scale + 0.5)
	end
	local tier = SeasonConstants.TierOf(mine).Tier
	local loss = math.max(rules.MIN_LOSS, rules.LOSS - gap) * (rules.LOSS_SCALE[tier.Name] or 1)
	local after = math.max(0, mine - math.floor(loss * scale + 0.5))
	if rules.TIER_FLOOR[tier.Name] then
		after = math.max(after, tier.Min)
	end
	return after - mine
end

local function setSP(player: Player, data, sp: number)
	sp = math.max(0, math.floor(sp))
	data.Season.SP.Set(sp)
	if sp > data.Season.PeakSP.Get() then
		data.Season.PeakSP.Set(sp)
	end
	Board.Mark(player, "SP", sp)
end

-- The SP a finished 1v1 duel moves, written to both players. Called by DuelService/Rewards before
-- it writes the rest (it needs both players' SP from before the duel). Nothing when SP isn't
-- moving (the season's Ends has passed), or the duel isn't 1v1.
-- result: { Winner?, Draw?, Leaver? }. Returns player → { Before, After, Delta, TierUp, TierDown, Gap }.
function SeasonService.Rate(result, players: { Player }): { [Player]: any }
	local out = {}
	if #players ~= 2 or not SeasonConstants.ENABLED or not SeasonConstants.IsRated() then
		return out
	end
	local a, b = players[1], players[2]
	local da, db = PlayerData.Get(a), PlayerData.Get(b)
	if not da or not db then
		return out
	end
	syncSeason(da)
	syncSeason(db)

	-- same rival again today: SP from it halves, then stops
	local today = math.floor(os.time() / DAY)
	if today ~= pairDay then
		pairDay, pairGames = today, {}
	end
	local key = pairKey(a, b)
	pairGames[key] = (pairGames[key] or 0) + 1
	local limits = SeasonConstants.SP.SAME_RIVAL
	local scale = if pairGames[key] > limits[2] then 0 elseif pairGames[key] > limits[1] then 0.5 else 1

	local before = { [a] = da.Season.SP.Get(), [b] = db.Season.SP.Get() }
	for _, p in players do
		local other = if p == a then b else a
		local outcome = if result.Leaver == p then "Lose"
			elseif result.Leaver == other then "Win"
			elseif result.Draw then "Draw"
			elseif result.Winner == p then "Win"
			else "Lose"
		local delta = spDelta(before[p], before[other], outcome, scale)
		local after = before[p] + delta
		local data = if p == a then da else db
		PlayerData.Batch(p, function()
			setSP(p, data, after)
		end)
		local from, to = SeasonConstants.TierOf(before[p]), SeasonConstants.TierOf(after)
		out[p] = {
			Before = before[p],
			After = after,
			Delta = delta,
			Gap = before[other] - before[p], -- "rival 168 SP above"
			TierUp = to.Index > from.Index,
			TierDown = to.Index < from.Index,
		}
	end
	return out
end

-- Cmdr / testing: set SP outright
function SeasonService.SetSP(player: Player, sp: number)
	local data = PlayerData.Get(player)
	if data then
		PlayerData.Batch(player, function()
			syncSeason(data)
			setSP(player, data, sp)
		end)
	end
end

-- Cmdr / testing: set season wins outright
function SeasonService.SetWins(player: Player, wins: number)
	local data = PlayerData.Get(player)
	if data then
		wins = math.max(0, math.floor(wins))
		PlayerData.Batch(player, function()
			syncSeason(data)
			data.Season.Wins.Set(wins)
		end)
		Board.Mark(player, "Wins", wins)
	end
end

-- [[ Track ]]

local GRANT = {}

function GRANT.Coins(data, spec)
	Currencies.Data(data, "Coins").Increment(spec.Amount or 0)
	data.Statistics.CoinsEarned.Increment(spec.Amount or 0)
end
function GRANT.Ticket(data, spec)
	Currencies.Data(data, "Tickets").Increment(spec.Amount or 1)
end
function GRANT.Upgrade(data, spec)
	Currencies.Data(data, "Upgrades").Increment(spec.Amount or 1)
end
function GRANT.Banner(data, spec)
	if spec.Banner and not data.Inventory.Banners.Has(spec.Banner) then
		data.Inventory.Banners.Add(spec.Banner)
	end
end
function GRANT.Photocard(data, spec)
	if spec.Photocard and not data.Inventory.Photocards.Has(spec.Photocard) then
		data.Inventory.Photocards.Add(spec.Photocard)
	end
end
-- a title at its tier: milestone 25 gives S0 Comeback, Rainbow
function GRANT.Title(data, spec)
	if spec.Title and not data.Inventory.Titles.Has(spec.Title) then
		data.Inventory.Titles.Add(spec.Title)
		if spec.TitleTier then
			data.Inventory.TitleTiers[spec.Title].Set(spec.TitleTier)
		end
	end
end

local function claim(player: Player, data, packet)
	syncSeason(data)
	local n = packet.N
	local claimed = data.Season.Claimed.Get()
	local spec = type(n) == "number" and SeasonConstants.TRACK[n]
	if not spec or n ~= claimed + 1 then
		return reply(player, { Action = "Claim", Ok = false, Text = "Claim the earlier ones first", N = n })
	end
	if data.Season.Stars.Get() < n * SeasonConstants.STARS_PER_MILESTONE then
		return reply(player, { Action = "Claim", Ok = false, Text = "Not enough Stars yet", N = n })
	end
	PlayerData.Batch(player, function()
		data.Season.Claimed.Set(n)
		local grant = GRANT[spec.Kind]
		if grant then
			grant(data, spec)
		end
	end)
	if spec.Kind == "Coins" then
		Analytics.Economy(player, "Source", "Coins", spec.Amount or 0, data.Currencies.Won.Get(), "SeasonTrack", `Milestone:{n}`)
	end
	Analytics.Event(player, "SeasonClaim", n, spec.Kind)
	reply(player, { Action = "Claim", Ok = true, Text = "Claimed!", N = n, Kind = spec.Kind, Amount = spec.Amount })
end

-- [[ Card upgrades ]]

local function useUpgrade(player: Player, data, packet)
	local id = packet.Id
	local out = { Action = "UseUpgrade", Ok = false, Id = id }
	if Currencies.Data(data, "Upgrades").Get() <= 0 then
		out.Text = "No card upgrades left"
		return reply(player, out)
	end
	if type(id) ~= "string" or not data.Inventory.Songs.Has(id) then
		out.Text = "You don't own that card"
		return reply(player, out)
	end
	local copies = data.Inventory.Copies.Get() or {}
	local have = Cards.Copies(copies, true, id)
	if Cards.Next(have) == nil then
		out.Text = "That card is already Rainbow"
		return reply(player, out)
	end
	PlayerData.Batch(player, function()
		Currencies.Data(data, "Upgrades").Increment(-1)
		data.Inventory.Copies[id].Set(have + 1)
	end)
	local song = Songs.GetById(id)
	if song then
		task.spawn(Collection.Check, data, { song }) -- a card levelling up can level its set's title
	end
	Analytics.Event(player, "CardUpgrade", have + 1, id)
	out.Ok, out.Text, out.Copies = true, "Upgraded!", have + 1
	reply(player, out)
end

local function board(player: Player, _data, packet)
	reply(player, { Action = "Board", Ok = true, Board = Board.Packet(player, packet.Kind) })
end

local ACTIONS = {
	Claim = claim,
	UseUpgrade = useUpgrade,
	Board = board,
}

-- [[ Lifecycle ]]

local function mirror(player: Player, data)
	local function set(attribute: string, path)
		path.Observe(function(value)
			player:SetAttribute(attribute, value)
		end)
	end
	set("SeasonStars", data.Season.Stars)
	set("SeasonClaimed", data.Season.Claimed)
	set("SeasonDuels", data.Season.Duels)
	set("SeasonWins", data.Season.Wins)
	set("SeasonSP", data.Season.SP)
	set("SeasonPeakSP", data.Season.PeakSP)
	-- every currency's count, to the attribute named in Constants/Currencies (Coins, Tickets, Upgrades)
	for _, currency in Currencies.All do
		set(currency.Attribute, Currencies.Data(data, currency.Id))
	end
end

function SeasonService.Start()
	SeasonRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local action = ACTIONS[packet.Action]
		local data = PlayerData.Get(player)
		if not action or not data then
			return
		end
		-- seasons off: no track claims or ranks (card upgrades still work for the Index)
		if not SeasonConstants.ENABLED and packet.Action ~= "UseUpgrade" then
			reply(player, { Action = packet.Action, Ok = false, Text = "Seasons are coming soon" })
			return
		end
		busy[player] = true
		local ok, err = pcall(action, player, data, packet)
		busy[player] = nil
		if not ok then
			warn("[SeasonService]", packet.Action, err)
			reply(player, { Action = packet.Action, Ok = false, Text = "Something went wrong" })
		end
	end)

	local function onJoin(player: Player)
		if not PlayerData.WaitForData(player) then
			return
		end
		local data = PlayerData.Get(player)
		if data then
			PlayerData.Batch(player, function()
				syncSeason(data)
			end)
			mirror(player, data)
			-- keeps the boards right after a missed write (nobody's put on them at 0)
			if data.Season.SP.Get() > 0 then
				Board.Mark(player, "SP", data.Season.SP.Get())
			end
			if data.Season.Wins.Get() > 0 then
				Board.Mark(player, "Wins", data.Season.Wins.Get())
			end
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		task.spawn(Board.Flush, player)
	end)
	Board.Start()
end

return SeasonService
