--| Prices
-- Live Robux prices for the game's developer products and passes, read from Roblox
-- (MarketplaceService) instead of being typed into the code. With managed / regional pricing
-- the price differs by player and changes over time, so the shop always shows what the
-- purchase prompt will ask for. Client only; cached for CACHE_SECONDS.
--   Prices.Get("Product" | "GamePass", id) -> (price: number?, forSale: boolean?)
--       nil, nil = still loading (fetches in the background, then fires Changed)
--       nil, false = not for sale (offsale pass / product)
--   Prices.Changed – Signal: a price arrived

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Signal = require(ReplicatedStorage.Packages.signal)

local CACHE_SECONDS = 10 * 60
local RETRY_SECONDS = 15

local Prices = {}
Prices.Changed = Signal.new()

type Entry = { Price: number?, ForSale: boolean?, At: number, Loading: boolean }
local cache: { [string]: Entry } = {}

local INFO_TYPE = {
	Product = Enum.InfoType.Product,
	GamePass = Enum.InfoType.GamePass,
}

-- GetProductInfoAsync is the current name (it returns the player's regional price);
-- older engines only have GetProductInfo
local function fetch(id: number, infoType: Enum.InfoType)
	local ok, info = pcall(function()
		return (MarketplaceService :: any):GetProductInfoAsync(id, infoType)
	end)
	if not ok then
		ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	end
	return ok, info
end

function Prices.Get(kind: string, id: number?): (number?, boolean?)
	local infoType = INFO_TYPE[kind]
	if not infoType or not id or id <= 0 then
		return nil, false
	end
	local key = `{kind}:{id}`
	local entry = cache[key]
	local fresh = entry and os.clock() - entry.At < (if entry.ForSale == nil then RETRY_SECONDS else CACHE_SECONDS)
	if not entry or (not fresh and not entry.Loading) then
		entry = entry or { At = 0, Loading = false }
		cache[key] = entry
		entry.Loading = true
		task.spawn(function()
			local ok, info = fetch(id, infoType)
			entry.Loading = false
			entry.At = os.clock()
			if ok and type(info) == "table" then
				entry.ForSale = info.IsForSale ~= false and type(info.PriceInRobux) == "number"
				entry.Price = if entry.ForSale then info.PriceInRobux else nil
			else
				warn(`[Prices] couldn't read {key}: {info}`)
			end
			Prices.Changed:Fire()
		end)
	end
	return entry.Price, entry.ForSale
end

return Prices
