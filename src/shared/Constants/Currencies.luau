--| Currencies
-- Everything the game counts as a currency, in one place: its name, icon, colour, where it's
-- saved and how the client reads it. Require it anywhere (client or server) instead of copying
-- an icon id or a data path:
--   local Currencies = require(ReplicatedStorage.Constants.Currencies)
--   Currencies.Tickets.Icon                       -- "rbxassetid://..."
--   Currencies.Get("Upgrades").Name               -- "Card upgrade"
--   Currencies.Count(player, "Tickets")           -- client or server, from the player attribute
--   Currencies.Data(data, "Coins").Increment(50)  -- server, the Scribe path (PlayerData)
--   for _, c in Currencies.Wallet do ... end      -- the HUD wallet's rows, in order
-- Adding one: add an entry + its ORDER line, give it a Scribe Count() in PlayerData and a Path
-- here, mirror it to its Attribute on the server (Engine/DataService), and rebuild the HUD wallet
-- (SeasonController/Build.HUDExtras) if it goes in the wallet.

local C = Color3.fromHex

export type Currency = {
	Id: string,
	Name: string, -- one of it ("Roll ticket")
	Plural: string, -- more than one ("Roll tickets")
	Label: string, -- short caps label on cards ("COINS")
	Icon: string,
	Colour: Color3, -- its pastel (tiles, chips, wallet rows)
	Attribute: string, -- the player attribute the server mirrors the count to
	Path: { string }, -- where it's saved in PlayerData ({ "Currencies", "Won" })
	Wallet: boolean, -- listed in the HUD coins wallet
	Robux: boolean, -- can be bought with Robux (so rolls with it count as paid random items)
}

local Currencies = {}

Currencies.Coins = table.freeze({
	Id = "Coins",
	Name = "Coin",
	Plural = "Coins",
	Label = "COINS",
	Icon = "rbxassetid://105055420801588",
	Colour = C("FFE07A"),
	Attribute = "Coins",
	Path = table.freeze({ "Currencies", "Won" }),
	Wallet = false, -- it has its own card on the HUD
	Robux = true,
} :: Currency)

Currencies.Tickets = table.freeze({
	Id = "Tickets",
	Name = "Roll ticket",
	Plural = "Roll tickets",
	Label = "TICKETS",
	Icon = "rbxassetid://106180506046153",
	Colour = C("DCD3FF"),
	Attribute = "Tickets",
	Path = table.freeze({ "Inventory", "Tickets" }),
	Wallet = true, -- tap: Roll → Pick a Group
	Robux = true, -- sold in the shop's ticket bundles + Bundles
} :: Currency)

Currencies.Upgrades = table.freeze({
	Id = "Upgrades",
	Name = "Card upgrade",
	Plural = "Card upgrades",
	Label = "UPGRADES",
	Icon = "rbxassetid://106061333838255",
	Colour = C("9ED8F5"),
	Attribute = "Upgrades",
	Path = table.freeze({ "Inventory", "Upgrades" }),
	Wallet = true, -- tap: the Index's card picker
	Robux = false,
} :: Currency)

-- display order
local ORDER = { "Coins", "Tickets", "Upgrades" }

local all, wallet = {}, {}
for _, id in ORDER do
	table.insert(all, Currencies[id])
	if Currencies[id].Wallet then
		table.insert(wallet, Currencies[id])
	end
end
Currencies.All = table.freeze(all) :: { Currency }
Currencies.Wallet = table.freeze(wallet) :: { Currency }

function Currencies.Get(id: string): Currency?
	local c = Currencies[id]
	return if type(c) == "table" and c.Id == id then c else nil
end

-- the count, from the attribute the server mirrors (0 before it arrives)
function Currencies.Count(player: Player, id: string): number
	local c = Currencies.Get(id)
	return if c then (player:GetAttribute(c.Attribute) or 0) :: number else 0
end

-- server: the Scribe path for it in a player's data (Get / Set / Increment / Observe)
function Currencies.Data(data: any, id: string): any
	local c = Currencies.Get(id)
	assert(c, `Currencies: no currency "{id}"`)
	local node = data
	for _, key in c.Path do
		node = node[key]
	end
	return node
end

return table.freeze(Currencies)
