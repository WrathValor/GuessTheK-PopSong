--| LiveEvents
-- In-game events (design boards "79a–d · Events"): limited-time missions that pay an event
-- currency, and a shop to spend it in. Engine/EventService runs them, EventsController is the
-- screen. Not the HUD's Roblox-event button (Constants/EventConstants), though the Winter
-- Special runs alongside the "First Snow in Seoul" Roblox event and that button opens it.
--
-- An event (EVENTS, oldest first) is live from Starts until Ends (os.time, UTC). One at a time.
--   Currency       its currency's name and look (saved as Events.Currency: Currencies.EventCurrency)
--   Leftover       coins paid for each unspent unit once the event is over (Engine/EventService)
--   Set            its card set's name: the albums with Event = this Id (Modules/Library/Albums
--                  "Event sets": the acts, Songs/init.luau), only in its pack, kept forever after
--   Pack           its pack: PACK_SIZE cards, the last one always from the Set at CardMin or rarer
--                  (Engine/AlbumService Kind = "Event"); bought in its shop, saved as Events.Packs
--                  (Currencies.EventPacks). Unopened ones turn into gen packs when the event is over.
--   Daily          missions that start again every UTC day
--   Missions       missions that last the whole event
--     Id (saved: never rename one), Text, Stat (EventService.Record's names: Wins, Duels,
--     Correct, Perfect, Packs, Lucky, NewCards, Collects, Pins, SetCards), Goal, Reward
--     ({ Currency = n, Packs = n }), Go (the screen its button opens), Hint (a line under it)
--   Shop           { Id (saved), Kind, Name, Hint, Price (in the currency), Limit? (for the whole
--                  event), DailyLimit?, Exclusive? (gone when the event ends), Art (its picture),
--                  Colour (the picture's box) } with, by Kind:
--                    Pack     → +1 of the event's Pack
--                    Set      → Set (a ShopCatalog.Sets id with Event = this event: its stage + mic)
--                    Title    → Title (a profile title)
--                    Premium  → Pack (an AlbumConstants.PREMIUM_PACKS key, to open from the Packs page)
--                    Luck     → Minutes of the Luck potion
--                    Coins    → Amount
-- Studio: STUDIO_LIVE makes STUDIO_EVENT live in playtests whatever the date, to test it.

local RunService = game:GetService("RunService")

local LiveEvents = {}

LiveEvents.STUDIO_LIVE = true
LiveEvents.STUDIO_EVENT = "winter26"

LiveEvents.EVENTS = table.freeze({
	table.freeze({
		Id = "winter26",
		Name = "Winter Special",
		Blurb = "Do missions for Snowflakes, spend them on Winter packs: Christmas Stage '26 cards are only in those.",
		Starts = 1796083200, -- 2026-12-01 00:00 UTC (with the "First Snow in Seoul" Roblox event)
		Ends = 1799280000, -- 2027-01-07 00:00 UTC
		Currency = table.freeze({ Name = "Snowflake", Plural = "Snowflakes", Colour = "9ED8F5", Icon = "rbxassetid://119208551988683" }),
		-- the screen's look: the banner's gradient, the list thumbnail
		Theme = table.freeze({ Banner = { "CFEFFF", "EAF7FF", "FFE4EF" }, Thumb = "CFEFFF" }),
		Leftover = 5,
		Set = "Christmas Stage '26",
		Pack = table.freeze({ Name = "Winter pack", Short = "WINTER", Icon = "rbxassetid://108740710970654", CardMin = "selca" }),
		Daily = table.freeze({
			table.freeze({ Id = "wins", Text = "Win 3 duels", Stat = "Wins", Goal = 3, Reward = { Currency = 40 }, Go = "Play" }),
			table.freeze({ Id = "packs", Text = "Open 5 packs", Stat = "Packs", Goal = 5, Reward = { Currency = 30 }, Go = "Packs" }),
			table.freeze({ Id = "correct", Text = "Guess 15 songs right", Stat = "Correct", Goal = 15, Reward = { Currency = 30 }, Go = "Play", Hint = "In any mode, solo too" }),
		}),
		Missions = table.freeze({
			table.freeze({ Id = "first", Text = "Open your first Winter pack", Stat = "SetCards", Goal = 1, Reward = { Currency = 100 }, Go = "Shop" }),
			table.freeze({ Id = "winter10", Text = "Pull 10 Christmas Stage cards", Stat = "SetCards", Goal = 10, Reward = { Packs = 2 }, Go = "Shop" }),
			table.freeze({ Id = "wins25", Text = "Win 25 duels", Stat = "Wins", Goal = 25, Reward = { Currency = 200 }, Go = "Play" }),
			table.freeze({ Id = "duels60", Text = "Play 60 duels", Stat = "Duels", Goal = 60, Reward = { Currency = 250 }, Go = "Play" }),
			table.freeze({ Id = "lucky5", Text = "Pull 5 Lucky Draw or rarer cards", Stat = "Lucky", Goal = 5, Reward = { Currency = 200 }, Go = "Packs", Hint = "Luck potions help" }),
			table.freeze({ Id = "collect20", Text = "Collect your binder coins 20 times", Stat = "Collects", Goal = 20, Reward = { Currency = 150 }, Go = "Binder" }),
			table.freeze({ Id = "winter30", Text = "Pull 30 Christmas Stage cards", Stat = "SetCards", Goal = 30, Reward = { Currency = 400 }, Go = "Shop" }),
		}),
		Shop = table.freeze({
			table.freeze({ Id = "WinterPack", Kind = "Pack", Name = "Winter pack", Hint = "5 cards · 1 Christmas Stage", Price = 150, DailyLimit = 10, Art = "rbxassetid://108740710970654", Colour = "E6F6FF" }),
			table.freeze({ Id = "FirstSnowSet", Kind = "Set", Set = "FirstSnow", Name = "First Snow set", Hint = "Stage + mic", Price = 1200, Limit = 1, Exclusive = true, Art = "rbxassetid://98755974723933", Colour = "DFF3FF" }),
			table.freeze({ Id = "SnowBias", Kind = "Title", Title = "Snow Bias", Name = "Snow Bias", Hint = "Profile title", Price = 400, Limit = 1, Exclusive = true, Colour = "FFF6D6" }),
			table.freeze({ Id = "Photobook", Kind = "Premium", Pack = "photobook", Name = "Photobook pack", Hint = "Premium pack", Price = 500, Limit = 3, Art = "rbxassetid://76102402433080", Colour = "FFF6D6" }),
			table.freeze({ Id = "Luck30", Kind = "Luck", Minutes = 30, Name = "30 min Luck", Hint = "+50% Luck potion", Price = 250, Limit = 5, Art = "rbxassetid://136253068957955", Colour = "E8FBEE" }),
			table.freeze({ Id = "Coins", Kind = "Coins", Amount = 2500, Name = "2,500 coins", Hint = "Coins", Price = 100, Art = "rbxassetid://75882247530961", Colour = "FFF6D6" }),
		}),
	}),
})

function LiveEvents.Get(id: string?)
	for _, event in LiveEvents.EVENTS do
		if event.Id == id then
			return event
		end
	end
	return nil
end

-- the event live at `now` (default os.time()), or nil. In Studio playtests STUDIO_LIVE makes
-- STUDIO_EVENT live whatever the date.
function LiveEvents.Current(now: number?)
	if LiveEvents.STUDIO_LIVE and RunService:IsStudio() then
		return LiveEvents.Get(LiveEvents.STUDIO_EVENT)
	end
	local t = now or os.time()
	for _, event in LiveEvents.EVENTS do
		if t >= event.Starts and t < event.Ends then
			return event
		end
	end
	return nil
end

-- the next event that hasn't started yet, or nil
function LiveEvents.Next(now: number?)
	local t = now or os.time()
	for _, event in LiveEvents.EVENTS do
		if event.Starts > t then
			return event
		end
	end
	return nil
end

function LiveEvents.Mission(event, id: string)
	for _, list in { event.Daily, event.Missions } do
		for _, m in list do
			if m.Id == id then
				return m, list == event.Daily
			end
		end
	end
	return nil, false
end

function LiveEvents.Item(event, id: string)
	for _, item in event.Shop do
		if item.Id == id then
			return item
		end
	end
	return nil
end

-- every stat any event counts (the saved counters' keys)
LiveEvents.STATS = table.freeze({ "Wins", "Duels", "Correct", "Perfect", "Packs", "Lucky", "NewCards", "Collects", "Pins", "SetCards" })

-- the UTC day number (missions' daily reset)
function LiveEvents.Day(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

return table.freeze(LiveEvents)
