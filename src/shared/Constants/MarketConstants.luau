--| MarketConstants
-- The Market (design boards "60 · Market · Browse", "60b · Sell a card", "60c · Card detail +
-- buy"): players buy and sell their photocards, any rarity (26 Nov 2026: Standard, Selca and
-- Store Benefit too), with each other, for coins only (never Robux). Engine/MarketService runs it; MarketController is the screen.
--   MarketConstants.Tradeable(cardId) → boolean
--   MarketConstants.Floor(cardId) → number       (the lowest price a card can be listed for)
--   MarketConstants.Payout(price) → number       (what the seller gets, after the fee)
--   MarketConstants.Cap(cardId) → number         (the highest price a card can be listed for)
--   MarketConstants.Decode(json) → listing?      (an Inventory.Listings entry)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Albums = require(ReplicatedStorage.Modules.Library.Albums)

local MarketConstants = {}

MarketConstants.MAP = "Market_v1" -- MemoryStore SortedMap: every listing, by price
MarketConstants.CLAIM_STORE = "MarketClaims_v1" -- DataStore: who got each listing (a buyer, or the seller back)
MarketConstants.SALES_STORE = "MarketSales_v1" -- DataStore: each card id's last SALES_KEPT sale prices

-- the rarities that can be listed, worst to best: every one
MarketConstants.RARITIES = { "standard", "selca", "store", "luckydraw", "fansign", "polaroid", "oneofone" }
MarketConstants.RARITY_COLOURS = { standard = "F3EEE0", selca = "FFD2E5", store = "A7E9B8", luckydraw = "FFFFFF", fansign = "FFFFFF", polaroid = "FBF7F0", oneofone = "FFFFFF" }
-- (Lucky Draw, Fansign and One of One are white under their Photocard foil: holo, glitter, rainbow)
MarketConstants.ONE_OF_ONE_FLOOR = 5000 -- (a One of One can't be sold to the game, so it has no Sell price)

MarketConstants.FEE = 0.10 -- taken from the price when a card sells (a coin sink)
MarketConstants.LIMIT = 10 -- listings at once
MarketConstants.LIMIT_VIP = 20
MarketConstants.HOURS = { 24, 48, 168 } -- how long a listing can stay up (the Sell form's chips)
MarketConstants.DEFAULT_HOURS = 48
MarketConstants.STEP = 50 -- the − / + on the price
MarketConstants.MAX_PRICE = 10000000
-- Guardrails (26 Nov 2026): so a junk card listed for millions can't move coins from one account
-- to another (an alt), each rarity has a price cap, and selling needs SELL_LEVEL (buying doesn't).
MarketConstants.CAPS = { standard = 1000, selca = 2500, store = 5000, luckydraw = 20000, fansign = 100000, polaroid = 500000, oneofone = 10000000 }
MarketConstants.SELL_LEVEL = 10
MarketConstants.PER_PAGE = 8 -- Browse tiles a page
MarketConstants.SALES_KEPT = 5
MarketConstants.REFRESH = 20 -- seconds between each server's reads of the whole map
MarketConstants.SORTS = { "Price", "Newest", "Rarest", "Serial" }

local tradeable = {}
for _, key in MarketConstants.RARITIES do
	tradeable[key] = true
end

function MarketConstants.Tradeable(cardId: string): boolean
	local card = Albums.Card(cardId)
	return card ~= nil and tradeable[card.Rarity.Key] == true
end

function MarketConstants.Floor(cardId: string): number
	local card = Albums.Card(cardId)
	if not card then
		return MarketConstants.MAX_PRICE
	end
	return card.Rarity.Sell or MarketConstants.ONE_OF_ONE_FLOOR
end

function MarketConstants.Cap(cardId: string): number
	local card = Albums.Card(cardId)
	return card and MarketConstants.CAPS[card.Rarity.Key] or MarketConstants.MAX_PRICE
end

function MarketConstants.Payout(price: number): number
	return price - math.floor(price * MarketConstants.FEE)
end

function MarketConstants.Decode(json: any): { [string]: any }?
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and type(t) == "table" and type(t.C) == "string" then t else nil
end

return MarketConstants
