import os
os.chdir(os.path.expanduser('~/mnt/GuessTheK-PopSong/src'))
exec(open('/tmp/p.py').read())
H = 'client/Client/InterfaceController/Controllers/HUDController/init.luau'

patch(H, [
# tile targets
("""-- Frames opened by the HUD buttons. Missing controllers are skipped with a warning, so
-- buttons start working as soon as the matching controller is added.
-- (K-POPPED! layout, HUDController/BuildKPopped: Packs in the middle, the Binder beside it;
-- Profile is a small button top right)
local TILE_TARGETS = {
	Inventory = "Inventory",
	Binder = "Binder",
	Packs = "Albums",
	Shop = "Shop",
	Rewards = "Rewards",
}""",
"""-- Frames opened by the HUD buttons. Missing controllers are skipped with a warning, so
-- buttons start working as soon as the matching controller is added.
-- (v3 layout, HUDController/BuildV3: the left column in TopLeft, Profile + Gifts in Buttons)
local TILE_TARGETS = {
	Shop = "Shop",
	Binder = "Binder",
	Packs = "Albums",
	Quests = "Rewards",
	Daily = "DailyLogin",
}"""),
# boosts off the HUD
("""	-- active boost potions under the left cards (hover for what they do)
	Boosts.Start(hud, self._janitor, function()
		self:_open("Shop", "Boosts")
	end)
""", """	-- (the active boost potions are off the v3 HUD: BottomLeft is hidden, Boosts isn't started)
"""),
# XP header comment
("""-- [[ XP bar ]]
-- Menu.XPBar, under the tiles: "LEVEL 7 [620/1,000]", the fill tweening to the level's progress.""",
"""-- [[ XP bar ]]
-- Menu.XPBar, under Quick Play: "LEVEL 7 [620/1,000]", the fill tweening to the level's progress."""),
# currency
("""-- [[ Coins / wins ]]

function HUDController._bindCurrency(self: Self)
	local currency = self._hud.TopLeft
""", """-- [[ Coins ]]
-- Menu.Coins: the amount + coin on the dark band over Quick Play (tap: Shop › Coins)

function HUDController._bindCurrency(self: Self)
	local band = self._hud.Menu.Coins
"""),
("""	self._janitor:Add(PlayerData.Currencies.Won.Observe(function(coins: number)
		animateNumber("Coins", currency.Coins, currency.Coins.Amount, coins)
	end))

	self._janitor:Add(PlayerData.Statistics.Wins.Observe(function(wins: number)
		animateNumber("Wins", currency.Wins, currency.Wins.Amount, wins)
	end))

	self._janitor:Add(PlayerData.Player.Streak.Observe(function(streak: number)
		local was = currency.Wins.Streak.Visible
		currency.Wins.Streak.Visible = streak > 0
		currency.Wins.Streak.Value.Text = tostring(streak)
		if streak > 0 and (was or streak == 1) then
			Juice.Pop(currency.Wins.Streak, 0.25)
		end
	end))
end""", """	self._janitor:Add(PlayerData.Currencies.Won.Observe(function(coins: number)
		animateNumber("Coins", band, band.Amount, coins)
	end))
end"""),
# wallet: gone with the coins card
("""function HUDController._bindExtras(self: Self)
	local topLeft = self._hud.TopLeft
	local tab = topLeft.Coins:FindFirstChild("WalletTab")""",
"""function HUDController._bindExtras(self: Self)
	local topLeft = self._hud.TopLeft
	-- (the v3 HUD has no coins card, so no wallet: tickets show in Packs and the Shop)
	if not topLeft:FindFirstChild("Coins") then
		return
	end
	local tab = topLeft.Coins:FindFirstChild("WalletTab")"""),
# buttons
("""	for tile, target in TILE_TARGETS do
		self._janitor:Add(menu.Tiles[tile].Activated:Connect(function()
			self:_open(target)
		end))
	end


	self._janitor:Add(hud.TopLeft.Coins.Buy.Activated:Connect(function()
		self:_open("Shop", "Coins")
	end))""",
"""	for tile, target in TILE_TARGETS do
		self._janitor:Add(hud.TopLeft[tile].Activated:Connect(function()
			self:_open(target)
		end))
	end
	-- the Market isn't built yet: its tile says so
	self._janitor:Add(hud.TopLeft.Market.Activated:Connect(function()
		Sounds.Play("Click")
		Juice.Shake(hud.TopLeft.Market, 0.4)
		self:Toast("The Market is coming soon!")
	end))
	-- Gifts: the Shop, straight to "who's it for?"
	local gifts = hud.Buttons:FindFirstChild("Gifts")
	if gifts then
		self._janitor:Add(gifts.Activated:Connect(function()
			self:_open("Shop", "Gift")
		end))
	end
	self._janitor:Add(menu.Coins.Activated:Connect(function()
		self:_open("Shop", "Coins")
	end))"""),
# K-POPPED binder card → tiles
("""	local hud = self._hud
	local card = hud.TopLeft:FindFirstChild("Binder")
	local biasButton = hud.Buttons:FindFirstChild("Bias")
	local tiles = hud.Menu.Tiles
	local packs, binderTile = tiles:FindFirstChild("Packs"), tiles:FindFirstChild("Binder")""",
"""	local hud = self._hud
	-- (v3: the Binder card and bias are off the HUD; the Binder tile shows the coins waiting)
	local card = nil :: any
	local biasButton = hud.Buttons:FindFirstChild("Bias")
	local tiles = hud.TopLeft
	local packs, binderTile = tiles:FindFirstChild("Packs"), tiles:FindFirstChild("Binder")"""),
("""	-- the badges: free packs ready on Packs, cards owned on the Binder
	local function fillBadges()
		if packs and packs:FindFirstChild("Free") then
			local free = Albums.FreePacks(PlayerData.Inventory.FreePacks.Get() or 0, PlayerData.Inventory.FreePackAt.Get() or 0, os.time())
			packs.Free.Visible = free > 0
			packs.Free.Text = `{free} FREE`
		end
		if binderTile and binderTile:FindFirstChild("Count") then
			local n = 0
			for _, copies in cards() do
				if copies > 0 then
					n += 1
				end
			end
			binderTile.Count.Visible = n > 0
			binderTile.Count.Text = if n == 1 then "1 card" else `{ShopCatalog.Format(n)} cards`
		end
	end""",
"""	-- the badges: free packs ready on Packs (the red count), coins waiting on the Binder ("+412")
	local function fillBadges()
		if packs and packs:FindFirstChild("Count") then
			local free = Albums.FreePacks(PlayerData.Inventory.FreePacks.Get() or 0, PlayerData.Inventory.FreePackAt.Get() or 0, os.time())
			packs.Count.Visible = free > 0
			packs.Count.Text = if free > 9 then "9+" else tostring(free)
		end
		if binderTile and binderTile:FindFirstChild("Waiting") then
			local coins = waiting()
			binderTile.Waiting.Visible = coins >= 1
			binderTile.Waiting.Text = `+{ShopCatalog.Format(coins)}`
		end
	end"""),
# static
("""	hud.Menu.Tiles.Shop.Sale.Visible = HUDConstants.SHOP_SALE
	self:SetRewardsBadge(self._rewardsBadge or 0)""",
"""	hud.TopLeft.Shop.Sale.Visible = HUDConstants.SHOP_SALE
	self:SetRewardsBadge(self._rewardsBadge or 0)
	self:SetDailyBadge(self._dailyReady or false)"""),
# rewards badge
("""-- Number of unclaimed rewards on the Rewards tile; 0 hides the badge. `earned`: how many of
-- them are level rewards / quests (the Rewards nudge waits for one of those).""",
"""-- Number of unclaimed rewards on the Quests tile (the daily login has its own, SetDailyBadge);
-- 0 hides the badge. `earned`: how many of them are level rewards / quests (the Rewards nudge
-- waits for one of those)."""),
("""	local badge = self._hud.Menu.Tiles.Rewards.Badge
	badge.Visible = count > 0
	badge.Value.Text = if count > 9 then "9+" else tostring(count)
end""",
"""	local badge = self._hud.TopLeft.Quests.Count
	local n = math.max(0, count - (if self._dailyReady then 1 else 0))
	badge.Visible = n > 0
	badge.Text = if n > 9 then "9+" else tostring(n)
end

-- Today's login reward waiting: the red 1 on Daily Rewards (RewardsController keeps it right).
function HUDController.SetDailyBadge(self: Self, ready: boolean)
	self._dailyReady = ready
	if not self._hud then
		return
	end
	local badge = self._hud.TopLeft.Daily.Count
	badge.Visible = ready
	badge.Text = "1"
	self:SetRewardsBadge(self._rewardsBadge or 0)
end"""),
# pad binds
("""-- Controller shortcuts in the lobby (Modules/UI/PadBinds): Y Quick Play, RB Shop, D-pad
-- ← Binder, ↑ Packs, → Inventory, ↓ Rewards. A, B and X stay free: A jumps and X is the stage
-- prompt. Bound while the HUD is up.""",
"""-- Controller shortcuts in the lobby (Modules/UI/PadBinds): Y Quick Play, RB Shop, D-pad
-- ← Binder, ↑ Packs, → Daily Rewards, ↓ Quests. A, B and X stay free: A jumps and X is the stage
-- prompt. Bound while the HUD is up."""),
("""	local menu = self._hud.Menu
	local tiles = menu.Tiles
	local function open(name: string)""",
"""	local menu = self._hud.Menu
	local tiles = self._hud.TopLeft
	local function open(name: string)"""),
("""		{ Key = Enum.KeyCode.DPadRight, Chip = tiles.Inventory, Run = open("Inventory") },
		{ Key = Enum.KeyCode.DPadDown, Chip = tiles.Rewards, Run = open("Rewards") },""",
"""		{ Key = Enum.KeyCode.DPadRight, Chip = tiles.Daily, Run = open("DailyLogin") },
		{ Key = Enum.KeyCode.DPadDown, Chip = tiles.Quests, Run = open("Rewards") },"""),
])

E = 'client/Client/InterfaceController/Controllers/HUDController/Effects.luau'
patch(E, [
("""	local tiles = hud.Menu.Tiles

	rainbow(tiles.Shop, janitor)""", """	local tiles = hud.TopLeft -- (v3: the tiles are the left column)

	rainbow(tiles.Shop, janitor)"""),
("""	local badge = tiles.Rewards:FindFirstChild("Badge")""", """	local badge = tiles.Quests:FindFirstChild("Count")"""),
])

N = 'client/Client/InterfaceController/Controllers/HUDController/Nudges.luau'
s = open(N).read()
assert s.count('return hud.Menu.Tiles.Packs') == 2 and s.count('return hud.Menu.Tiles.Rewards') == 1
s = s.replace('return hud.Menu.Tiles.Packs', 'return hud.TopLeft.Packs').replace('return hud.Menu.Tiles.Rewards', 'return hud.TopLeft.Quests')
assert s.count('Side = "Above",\n\t\tOpens = "Albums",') == 2
s = s.replace('Side = "Above",\n\t\tOpens = "Albums",', 'Side = "Right", -- (v3: the tile is on the left edge)\n\t\tOpens = "Albums",')
s = s.replace('Side = "Right", -- (above it would cover Quick Play)', 'Side = "Right",')
s = s.replace('Collect coins, tickets and more in <b>Rewards</b>.', 'Collect coins, tickets and more in <b>Quests</b>.')
open(N, 'w').write(s)

R = 'client/Client/InterfaceController/Controllers/RewardsController/init.luau'
patch(R, [
("""	if hud and hud.SetRewardsBadge then
		-- (level rewards + quests: what the HUD's one-time Rewards nudge waits for)
		hud:SetRewardsBadge(count, self:_questsReady("Daily") + self:_questsReady("Weekly") + self:_levelsReady())
	end""",
"""	if hud and hud.SetRewardsBadge then
		-- the daily login has its own button on the HUD (Daily Rewards): tell it first, so
		-- the Quests count leaves it out
		if hud.SetDailyBadge then
			hud:SetDailyBadge((self:_daily()) == true)
		end
		-- (level rewards + quests: what the HUD's one-time Rewards nudge waits for)
		hud:SetRewardsBadge(count, self:_questsReady("Daily") + self:_questsReady("Weekly") + self:_levelsReady())
	end"""),
])

S = 'client/Client/InterfaceController/Controllers/ShopController/init.luau'
patch(S, [
("""	if section == "Featured" or section == "Sets" then
		section = nil
	elseif section == "Items" then""",
"""	-- "Gift": the HUD's Gifts button: the shop, then "who's it for?" (Shop.GiftPick)
	local giftPick = section == "Gift"
	if section == "Featured" or section == "Sets" or giftPick then
		section = nil
	elseif section == "Items" then"""),
("""	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Shop:Deactivate()""",
"""	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
		if giftPick and not gift then
			self:_showPicker(true)
		end
	end)
end

function Shop:Deactivate()"""),
])
print('patched')
