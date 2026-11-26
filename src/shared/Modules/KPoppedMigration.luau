--| KPoppedMigration
-- The one-off K-POPPED! conversion: everyone's song collection turns into coins and tickets,
-- so nobody loses value and they start collecting photocards with a head start (design doc,
-- "Migration for existing players"; board "1 · Welcome to K-POPPED!").
--
-- NOT WIRED IN YET. This is a release gate: Scribe steps can never be edited once shipped, so
-- the numbers below get checked against real saves first (model a few options, test on copies
-- of real saves in Studio). At release it becomes the next DataMigrations step:
--     Migrations[4] = require(script.Parent.KPoppedMigration).Step
--
-- What it does, once per profile (also marked Rewards.Claimed KEY, so it can't run twice):
--   • every owned song → COINS_PER_SONG, plus COINS_PER_COPY for each copy past the first
--   • Gold songs → TICKETS_GOLD roll tickets, Rainbow → TICKETS_RAINBOW
--   • card upgrades held (Inventory.Upgrades, gone with the Index) → Currencies.UPGRADE_COINS
--     each, on top of the cap; Upgrades goes to 0
--   • coins from this are capped at COIN_CAP (nil = no cap)
--   • clears the song Showcase, Profile.BgMusic and Inventory.Packs (song packs); titles stay
--   • leaves Inventory.Songs and Inventory.Copies in the save, unused (support can read them)
--   • saves what it gave in Rewards.WelcomeCoins / WelcomeTickets for the welcome card
-- It works on the RAW save (DataMigrations explains what that looks like).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currencies = require(ReplicatedStorage.Constants.Currencies)

local KPoppedMigration = {}

KPoppedMigration.KEY = "KPopped"
KPoppedMigration.COINS_PER_SONG = 150 -- one song roll's price
KPoppedMigration.COINS_PER_COPY = 38 -- the song roll's duplicate refund
KPoppedMigration.TICKETS_GOLD = 1
KPoppedMigration.TICKETS_RAINBOW = 2
KPoppedMigration.GOLD_COPIES = 3 -- RollConstants' card levels, copied so a later change there can't change this step
KPoppedMigration.RAINBOW_COPIES = 5
KPoppedMigration.COIN_CAP = nil :: number?

-- what one save converts to: (coins, tickets). Pure, so tools can model it over real saves.
function KPoppedMigration.Value(songs: { string }, copies: { [string]: number }): (number, number)
	local M = KPoppedMigration
	local owned = {}
	for _, id in songs do
		owned[id] = math.max(owned[id] or 0, 1)
	end
	for id, n in copies do
		if type(n) == "number" and n > 0 then
			owned[id] = math.max(owned[id] or 0, n)
		end
	end
	local coins, tickets = 0, 0
	for _, n in owned do
		coins += M.COINS_PER_SONG + M.COINS_PER_COPY * (n - 1)
		if n >= M.RAINBOW_COPIES then
			tickets += M.TICKETS_RAINBOW
		elseif n >= M.GOLD_COPIES then
			tickets += M.TICKETS_GOLD
		end
	end
	if M.COIN_CAP then
		coins = math.min(coins, M.COIN_CAP)
	end
	return coins, tickets
end

function KPoppedMigration.Step(data)
	local claimed = data.Rewards.Claimed
	if table.find(claimed, KPoppedMigration.KEY) then
		return
	end
	local inv = data.Inventory
	local coins, tickets = KPoppedMigration.Value(inv.Songs, inv.Copies)
	coins += math.max(0, inv.Upgrades or 0) * Currencies.UPGRADE_COINS
	inv.Upgrades = 0
	data.Currencies.Won += coins
	inv.Tickets += tickets
	data.Rewards.WelcomeCoins = coins
	data.Rewards.WelcomeTickets = tickets
	data.Rewards.WelcomeSeen = false

	for slot in data.Profile.Showcase do
		data.Profile.Showcase[slot] = ""
	end
	data.Profile.BgMusic = ""
	table.clear(inv.Packs)

	table.insert(claimed, KPoppedMigration.KEY)
	table.sort(claimed)
end

return KPoppedMigration
