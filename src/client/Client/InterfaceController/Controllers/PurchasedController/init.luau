--| PurchasedController
-- The "YOU GOT!" reveal after any buy, so a player always sees what they got and where it went
-- (mock-up: UI canvas, "Purchase reveal"). It sits on top of whatever is open (not exclusive):
-- a scrim with turning light rays, a banner, one card per thing you got popping in one after
-- another (the real 3D model for stages / mics / sets, the coin pile for coins), a confetti
-- burst, "✓ Added to your Inventory", and EQUIP / Nice!.
--
-- What triggers it (no one has to call it):
--   ShopRemote reply  { Message = "Result", Ok = true, Action = "BuySet" | "BuyItem" | "BuyStyle", Id, Kind }
--                     – coin buys; the server has already equipped them
--   SeasonRemote reply { Message = "Result", Action = "Claim", Ok = true, Kind = "Banner" |
--                     "Photocard", N } – a Season Track banner / photocard (EQUIP NOW puts it on)
--   RewardsRemote reply { Message = "Result", Action = "RedeemCode", Ok = true, Code, Rewards }
--                     – a shop code: everything it gave (RewardsCatalog.CodeRewards)
--   RewardsRemote reply { Action = "ClaimLevel", All = true, Rewards, Titles, Levels } – level
--                     rewards' CLAIM ALL: the currencies added up, then each title
--   RewardsRemote reply { Action = "ClaimBonus", Scope, Rewards } – the daily / weekly quest bonus
--   PromptProductPurchaseFinished – the Debut Pack (waits for Rewards.Claimed "Debut"), coin
--                     bundles, roll ticket / card upgrade bundles (ShopCatalog.RollBundles) and
--                     (the mixed bundles, ShopCatalog.Bundles, show from Rewards.Bundles going up:
--                     up to 5 cards, stage + mic first)
--   PromptGamePassPurchaseFinished – passes (waits for GamePasses to have it)
-- A second buy while one is showing waits its turn.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local ProfileBuild = require(script.Parent.ProfileController.Build)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local Levels = require(ReplicatedStorage.Modules.Levels)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")
local SeasonRemote = Bridgenet.ReferenceBridge("SeasonRemote")
local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")

-- -------------------------------- Constants ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex
local RARITY_TAG = { Uncommon = "A7E9B8", Rare = "9ED8F5", Epic = "B9A6FF", Legendary = "FFE07A" }
local CONFETTI = { "FFE07A", "B9A6FF", "9ED8F5", "A7E9B8", "FF9EC4", "FF5A4E" }
local CARD_GAP = 0.22 -- seconds between the cards popping in
local GRANT_WAIT = 8 -- seconds to wait for a Robux grant to show up in the data
local RAY_SPEED = 8 -- degrees a second

-- --------------------------------- Helpers -------------------------------- --
local function owns(path, id: string): boolean
	local ok, has = pcall(path.Has, id)
	return ok and has == true
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	while true do
		local swapped, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = swapped
		if count == 0 then
			return s
		end
	end
end

-- resolves once check() is true (or after GRANT_WAIT seconds anyway: the buy went through)
local function waitFor(check: () -> boolean)
	return Promise.new(function(resolve)
		local deadline = os.clock() + GRANT_WAIT
		while os.clock() < deadline and not check() do
			task.wait(0.2)
		end
		resolve()
	end)
end

local function coinCard(amount: number, pile: string?)
	return { Name = `+{commas(amount)}`, Kind = "Coins", Colour = "FFE07A", Image = pile, Tag = "COINS", TagColour = "FFFFFF" }
end

-- the coin pile picture for an amount: the biggest coin bundle's pile that isn't bigger
local function pileFor(amount: number): string?
	local best, bestAmount = nil, -1
	for _, bundle in ShopCatalog.CoinBundles do
		if bundle.Amount <= amount and bundle.Amount > bestAmount then
			best, bestAmount = bundle.Pile, bundle.Amount
		end
	end
	return best or (ShopCatalog.CoinBundles[1] and ShopCatalog.CoinBundles[1].Pile)
end

-- roll tickets / card upgrades (or coins): "+5" over the currency's icon
local function currencyCard(id: string, amount: number)
	if id == "Coins" then
		return coinCard(amount, pileFor(amount))
	end
	local c = Currencies.Get(id)
	if not c then
		return nil
	end
	return {
		Name = `+{commas(amount)}`,
		Kind = if amount == 1 then c.Name else c.Plural,
		Colour = c.Colour:ToHex(),
		Image = c.Icon,
		Tag = string.upper(c.Plural),
		TagColour = "FFFFFF",
	}
end

-- titles: your name with the title chip under it, like the Inventory and the level reward cards
local function titleCard(title: string)
	return { Name = title, Kind = "Title", Colour = "CDEBFA", Title = title, Tag = "NEW", TagColour = "FF9EC4" }
end

local function itemCard(kind: string, id: string)
	local item = if kind == "Set" then ShopCatalog.GetSet(id) else ShopCatalog.GetItem(kind, id)
	if not item then
		return nil
	end
	return {
		Name = item.Name,
		Kind = `{kind} · {item.Rarity or "Common"}`,
		Colour = item.Bg or "FFF6D6",
		Model = { kind, id },
		Tag = "NEW",
		TagColour = RARITY_TAG[item.Rarity] or "B9A6FF",
	}
end

-- a banner or photocard you bought (Show draws it: see styleArt)
local function styleCard(kind: string, id: string)
	local spec = SeasonConstants.Banner(id) -- shop or Season Track, any banner / photocard
	if not spec or spec.Id ~= id then
		return nil
	end
	return {
		Name = spec.Name,
		Kind = if kind == "Banner" then "Profile banner" else "Photocard",
		Colour = spec.Fill:ToHex(),
		Style = { kind, id },
		Tag = if spec.Animated then "ANIMATED" else "NEW",
		TagColour = if spec.Animated then "FF9EC4" else "9ED8F5",
	}
end

-- a small photocard with your avatar (skin, photo background, stickers + its animation)
local function miniPhotocard(parent: Instance, id: string, pos: UDim2, w: number, rotation: number): Frame
	local h = math.floor(w * 334 / 280)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = pos
	card.Size = UDim2.fromOffset(w, h)
	card.Rotation = rotation
	card.BackgroundColor3 = C("FFFFFF")
	card.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card
	local line = Instance.new("UIStroke")
	line.Thickness = 2
	line.Color = C("1E1B2E")
	line.Parent = card
	card.Parent = parent
	local photo = ProfileBuild.Photo(card, UDim2.fromScale(12 / 280, 12 / 334), UDim2.fromScale(256 / 280, 228 / 334), 2)
	photo:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 5)
	SeasonArt.BuildCardSkin(card, photo, 8, true)
	photo.Avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
	SeasonArt.PaintPhotocard(card, id)
	return card
end

-- the card art for a banner (it across the top with the photocard you wear in front, like
-- your profile) or a photocard (the whole card, standing)
local function styleArt(art: Frame, kind: string, id: string)
	local holder = Instance.new("Frame")
	holder.Name = "Style"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 10
	holder.Parent = art
	if kind == "Banner" then
		-- like the profile: the banner band, your photocard tucked bottom-left, your name beside it
		art.BackgroundColor3 = C("FBF7F0")
		local banner = SeasonArt.BuildBanner(holder, "Banner", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 84), 0, false)
		SeasonArt.PaintBanner(banner, id)
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.Position = UDim2.fromOffset(0, 84)
		rule.Size = UDim2.new(1, 0, 0, 2)
		rule.BackgroundColor3 = C("1E1B2E")
		rule.BorderSizePixel = 0
		rule.ZIndex = 2
		rule.Parent = holder
		local worn = LOCAL_PLAYER:GetAttribute("Photocard") or SeasonConstants.DEFAULT_PHOTOCARD
		miniPhotocard(holder, worn, UDim2.new(0, 34, 0, 64), 50, -4)
		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.new(0, 66, 0, 116)
		name.Size = UDim2.new(1, -72, 0, 22)
		name.BackgroundColor3 = C("FFFFFF")
		name.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
		name.TextSize = 11
		name.TextColor3 = C("1E1B2E")
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = LOCAL_PLAYER.DisplayName
		name.ZIndex = 2
		local nc = Instance.new("UICorner")
		nc.CornerRadius = UDim.new(0, 7)
		nc.Parent = name
		local ns = Instance.new("UIStroke")
		ns.Thickness = 2
		ns.Color = C("1E1B2E")
		ns.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ns.Parent = name
		name.Parent = holder
	else
		miniPhotocard(holder, id, UDim2.new(0.5, 0, 0, 10), 108, -3)
	end
end

-- --------------------------------- Class ---------------------------------- --
local Purchased = {}
Purchased.__index = Purchased

function Purchased.new()
	local self = setmetatable({}, Purchased)
	self.Name = "Purchased"
	self.Exclusive = false
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._showJanitor = Janitor.new()
	self._queue = {}
	return (self :: any) :: UITypes.Controller
end

function Purchased:Initialize(interface)
	self._interface = interface
	local frame = interface:ResolveFrame("Interface", "Purchased")
	self._frame = frame
	frame.Visible = false
	self._template = frame.Items.CardTemplate
	self._template.Visible = false
	ButtonScale.ApplyToDescendants(frame)

	local j = self._janitor
	j:Add(frame.Nice.Activated:Connect(function()
		self:Hide()
	end))
	j:Add(frame.Scrim.Activated:Connect(function()
		self:Hide()
	end))
	j:Add(frame.Equip.Activated:Connect(function()
		local info = self._showing
		if info and info.Equip then
			info.Equip()
			Sounds.Play("Success")
		end
		self:Hide()
	end))

	-- coin buys (the server equips them itself)
	j:Add(ShopRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" or not packet.Ok then
			return
		end
		if packet.Action == "BuySet" and type(packet.Id) == "string" then
			local set = ShopCatalog.GetSet(packet.Id)
			self:Show({
				Banner = "NEW SET!",
				Sub = if set and set.Price then `−{commas(set.Price)} coins` else "",
				Cards = { itemCard("Set", packet.Id) },
				Where = "Equipped · added to your Inventory",
			})
		elseif packet.Action == "BuyStyle" and type(packet.Id) == "string" and type(packet.Kind) == "string" then
			local set = packet.Kind == "Set"
			local price = if type(packet.Price) == "number" then packet.Price else ShopCatalog.StylePrice(packet.Id, packet.Kind)
			self:Show({
				Banner = if set then "NEW SET!" elseif packet.Kind == "Banner" then "NEW BANNER!" else "NEW PHOTOCARD!",
				Sub = if price then `−{commas(price)} coins` else "",
				Cards = if set then { styleCard("Banner", packet.Id), styleCard("Photocard", packet.Id) } else { styleCard(packet.Kind, packet.Id) },
				Where = "Equipped · swap it any time in STYLE on your profile",
			})
		elseif packet.Action == "BuyItem" and type(packet.Id) == "string" and type(packet.Kind) == "string" then
			local item = ShopCatalog.GetItem(packet.Kind, packet.Id)
			self:Show({
				Banner = if packet.Kind == "Mic" then "NEW MIC!" else "NEW STAGE!",
				Sub = if item and item.Price then `−{commas(item.Price)} coins` else "",
				Cards = { itemCard(packet.Kind, packet.Id) },
				Where = "Equipped · added to your Inventory",
			})
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy

	-- Season Track: a banner / photocard milestone gets the same reveal (it isn't worn yet)
	j:Add(SeasonRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" or packet.Action ~= "Claim" or not packet.Ok then
			return
		end
		local spec = SeasonConstants.TRACK[packet.N]
		if not spec or (spec.Kind ~= "Banner" and spec.Kind ~= "Photocard") then
			return
		end
		local id = spec.Banner or spec.Photocard
		self:Show({
			Banner = if spec.Kind == "Banner" then "NEW BANNER!" else "NEW PHOTOCARD!",
			Sub = `Season Track · milestone {packet.N}`,
			Cards = { styleCard(spec.Kind, id) },
			Where = "Added to STYLE on your profile",
			EquipText = "EQUIP NOW",
			Equip = function()
				ShopRemote:Fire({ Action = "EquipStyle", [spec.Kind] = id })
			end,
		})
	end), "Disconnect")

	-- Rewards screen: CLAIM ALL on level rewards, and the daily / weekly quest bonus
	j:Add(RewardsRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" or not packet.Ok then
			return
		end
		local all = packet.Action == "ClaimLevel" and packet.All == true
		local bonus = packet.Action == "ClaimBonus"
		if not all and not bonus then
			return
		end
		local cards = {}
		local reward = if type(packet.Rewards) == "table" then packet.Rewards else {}
		for _, id in { "Coins", "Tickets", "Upgrades" } do
			local n = reward[id]
			if type(n) == "number" and n > 0 then
				table.insert(cards, currencyCard(id, n))
			end
		end
		-- the daily bonus's XP: a lilac card with the XP star
		if type(packet.XP) == "number" and packet.XP > 0 then
			table.insert(cards, { Name = `+{packet.XP}`, Kind = "XP", Colour = "DCD3FF", Image = SeasonConstants.ICONS.XP, Tag = "XP", TagColour = "FFFFFF" })
		end
		-- titles fill whatever card slots are left (Show shows up to 4); the rest follow on
		-- "NEW TITLES!" reveals, 4 at a time, queued after this one
		local titles = if type(packet.Titles) == "table" then packet.Titles else {}
		local overflow = {}
		for _, title in titles do
			if #cards < 4 then
				table.insert(cards, titleCard(title))
			else
				table.insert(overflow, titleCard(title))
			end
		end
		local sub = ""
		if all and type(packet.Levels) == "table" and packet.Levels[1] then
			local a, b = packet.Levels[1], packet.Levels[2] or packet.Levels[1]
			sub = if a == b then `Level {a}` else `Levels {a}–{b}`
		elseif bonus then
			sub = if packet.Scope == "Weekly" then "Every weekly quest done" else "Every daily quest done"
		end
		local pages = 1 + math.ceil(#overflow / 4)
		self:Show({
			Banner = if all then "LEVEL REWARDS!" elseif packet.Scope == "Weekly" then "WEEKLY BONUS!" else "DAILY BONUS!",
			Sub = if pages > 1 then `{sub} · 1 of {pages}` else sub,
			Cards = cards,
			Where = if #titles > 0 then "Added to your Inventory" else "Added to your wallet",
		})
		for i = 1, #overflow, 4 do
			self:Show({
				Banner = "NEW TITLES!",
				Sub = `{sub} · {math.ceil(i / 4) + 1} of {pages}`,
				Cards = table.move(overflow, i, math.min(i + 3, #overflow), 1, {}),
				Where = "Added to your Inventory",
			})
		end
	end), "Disconnect")

	-- shop codes: everything the code gave
	j:Add(RewardsRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" or packet.Action ~= "RedeemCode" or not packet.Ok then
			return
		end
		local cards = {}
		local wearable = {} -- stages / mics / banners / photocards EQUIP can put on
		for _, r in (if type(packet.Rewards) == "table" then packet.Rewards else {}) do
			if r.Kind == "Currency" then
				table.insert(cards, currencyCard(r.Key, r.Amount or 0))
			elseif r.Kind == "Item" then
				table.insert(cards, itemCard(r.Key, r.Id))
				table.insert(wearable, r)
			elseif r.Kind == "Style" then
				table.insert(cards, styleCard(r.Key, r.Id))
				table.insert(wearable, r)
			elseif r.Kind == "Title" then
				table.insert(cards, titleCard(r.Id))
			end
		end
		self:Show({
			Banner = "CODE REDEEMED!",
			Sub = if type(packet.Code) == "string" then packet.Code else "",
			Cards = cards,
			Where = if #wearable > 0 then "Added to your Inventory" else "Added to your account",
			EquipText = if #wearable > 0 then "EQUIP NOW" else nil,
			Equip = if #wearable > 0
				then function()
					for _, r in wearable do
						if r.Kind == "Item" then
							ShopRemote:Fire({ Action = "EquipItem", Kind = r.Key, Id = r.Id })
						else
							ShopRemote:Fire({ Action = "EquipStyle", [r.Key] = r.Id })
						end
					end
				end
				else nil,
		})
	end), "Disconnect")

	-- Robux: the Debut Pack, coin bundles, roll ticket + card upgrade bundles
	j:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if not purchased or userId ~= LOCAL_PLAYER.UserId then
			return
		end
		local pack = ShopCatalog.DebutPack
		if pack and pack.ProductId == productId then
			waitFor(function()
				return owns(PlayerData.Rewards.Claimed, pack.Id)
			end):andThen(function()
				self:Show({
					Banner = "YOU GOT!",
					Sub = "Debut Pack unlocked",
					Cards = {
						coinCard(pack.Coins, "rbxassetid://75882247530961"),
						pack.Stage and itemCard("Stage", pack.Stage),
						pack.Mic and itemCard("Mic", pack.Mic),
					},
					Where = "Added to your Inventory",
					EquipText = "EQUIP STAGE + MIC",
					Equip = function()
						if pack.Stage then
							ShopRemote:Fire({ Action = "EquipItem", Kind = "Stage", Id = pack.Stage })
						end
						if pack.Mic then
							ShopRemote:Fire({ Action = "EquipItem", Kind = "Mic", Id = pack.Mic })
						end
					end,
				})
			end)
			return
		end
		for _, bundle in ShopCatalog.CoinBundles do
			if bundle.ProductId == productId then
				task.delay(0.3, function()
					self:Show({
						Banner = "YOU GOT!",
						Sub = "Coins added",
						Cards = { coinCard(bundle.Amount, bundle.Pile) },
						Where = "Added to your coins",
					})
				end)
				return
			end
		end
		for _, bundle in ShopCatalog.RollBundles do
			if bundle.ProductId == productId then
				local c = Currencies.Get(bundle.Currency)
				local before = Currencies.Count(LOCAL_PLAYER, bundle.Currency)
				waitFor(function()
					return Currencies.Count(LOCAL_PLAYER, bundle.Currency) > before
				end):andThen(function()
					self:Show({
						Banner = "YOU GOT!",
						Sub = if c then `{c.Plural} added` else "",
						Cards = { currencyCard(bundle.Currency, bundle.Amount) },
						Where = if bundle.Currency == "Tickets" then "Use them on Roll · Pick a Group"
							else "Use them in the Index on any song you own",
					})
				end)
				return
			end
		end
	end))

	-- bundles (ShopCatalog.Bundles): shown the moment the grant lands, from the purchase
	-- counter (Rewards.Bundles). (Waiting on PromptProductPurchaseFinished and a currency going
	-- up was slow: the grant is often already in by then, so it sat out the whole GRANT_WAIT.)
	-- The baseline is read once the save has loaded. Scribe's Observe fires straight away with
	-- the empty default and then again while the first snapshot is replayed (before IsReady),
	-- so a baseline taken from either one turned every bundle already bought into a fresh
	-- "YOU GOT!" on every join.
	local bundleCounts: { [string]: number }? = nil -- nil until the save has loaded
	local function takeBaseline()
		local ok, all = pcall(PlayerData.Rewards.Bundles.Get)
		bundleCounts = if ok and type(all) == "table" then table.clone(all) else {}
	end
	if PlayerData.IsReady() then
		takeBaseline()
	else
		task.spawn(function()
			while not PlayerData.WaitForData(30) do end -- (WaitForData gives up after its timeout)
			if not bundleCounts then
				takeBaseline()
			end
		end)
	end
	j:Add(PlayerData.Rewards.Bundles.Observe(function(all)
		if type(all) ~= "table" or not PlayerData.IsReady() then
			return -- not loaded yet (the default, or the first snapshot being replayed)
		end
		local before = bundleCounts
		if not before then
			bundleCounts = table.clone(all)
			return
		end
		-- counts only go up, so the baseline never comes down: a re-sent snapshot (reset to
		-- the defaults, then replayed) mustn't make old purchases look new
		for id, n in all do
			local had = before[id] or 0
			if n > had then
				before[id] = n
				local bundle = ShopCatalog.GetBundle(id)
				if bundle then
					self:_showBundle(bundle)
				end
			end
		end
	end))

	-- Robux: passes
	j:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased or player ~= LOCAL_PLAYER then
			return
		end
		for _, pass in ShopCatalog.Passes do
			if pass.GamePassId == passId then
				waitFor(function()
					return owns(PlayerData.GamePasses, pass.Id)
				end):andThen(function()
					self:Show({
						Banner = "PASS UNLOCKED!",
						Sub = pass.Sub or "",
						Cards = {
							{
								Name = pass.Name,
								Kind = "Game pass · forever",
								Colour = pass.Bg or "FFE07A",
								Image = if pass.Icon == "Crown" then "rbxassetid://131353192492921" else nil,
								Big = if pass.Icon ~= "Crown" then pass.Icon else nil,
								Tag = "NEW",
								TagColour = "B9A6FF",
							},
						},
						Where = "Active on your account",
					})
				end)
				return
			end
		end
	end))
end

-- ---------------------------------- Show ---------------------------------- --

-- the "YOU GOT!" for a bundle: its stage + mic first, then the currencies (up to 5 cards)
function Purchased:_showBundle(bundle)
	local cards = {}
	for _, entry in ShopCatalog.BundleContents(bundle) do
		if entry.Kind == "Stage" or entry.Kind == "Mic" then
			table.insert(cards, itemCard(entry.Kind, entry.Id))
		else
			table.insert(cards, currencyCard(entry.Kind, entry.Amount))
		end
	end
	self:Show({
		Banner = "YOU GOT!",
		Sub = `{bundle.Name} bundle`,
		Cards = cards,
		Where = if bundle.Stage then "Added to your Inventory" else "Added to your wallet",
		EquipText = if bundle.Stage then "EQUIP STAGE + MIC" else nil,
		Equip = if bundle.Stage
			then function()
				ShopRemote:Fire({ Action = "EquipItem", Kind = "Stage", Id = bundle.Stage })
				if bundle.Mic then
					ShopRemote:Fire({ Action = "EquipItem", Kind = "Mic", Id = bundle.Mic })
				end
			end
			else nil,
	})
end

-- info = { Banner, Sub, Cards = { card? }, Where, EquipText?, Equip? }
-- card = { Name, Kind, Colour, Tag, TagColour, Model = { kind, id }? | Image? | Big? | Title? }
function Purchased:Show(info)
	-- drop missing cards (an id the catalog doesn't know), keep the order
	local cards = {}
	for i = 1, 5 do
		if info.Cards[i] then
			table.insert(cards, info.Cards[i])
		end
	end
	info.Cards = cards
	if #cards == 0 then
		return
	end
	if self._showing then
		table.insert(self._queue, info)
		return
	end
	self._showing = info
	self._shownAt = os.clock()
	self.State = "Active"

	local frame = self._frame
	local sj = self._showJanitor
	sj:Cleanup()

	frame.Banner.Text = info.Banner
	frame.Sub.Text = info.Sub or ""
	frame.Where.Label.Text = info.Where or "Added to your Inventory"

	-- buttons: EQUIP only when there's something to put on
	local canEquip = info.Equip ~= nil
	frame.Equip.Visible = canEquip
	frame.EquipShadow.Visible = canEquip
	if canEquip then
		frame.Equip.Label.Text = info.EquipText or "EQUIP NOW"
	end
	frame.Nice.Position = UDim2.fromOffset(if canEquip then 745 else 640, 587)
	frame.NiceShadow.Position = UDim2.fromOffset(if canEquip then 749 else 644, 591)

	-- the cards
	local made = {}
	for i, card in cards do
		local c = self._template:Clone()
		c.Name = "Card" .. i
		c.LayoutOrder = i
		c.Visible = true
		-- (the slot sits in the row's UIListLayout; Inner is what tilts and pops)
		local inner = c.Inner
		local TILTS = { -3, 1, 3, -1, 2 } -- (up to 5 cards: a bundle's stage + mic + 3 currencies)
		inner.Rotation = TILTS[(i - 1) % #TILTS + 1]
		local face = inner.Face
		local art = face.Art
		art.BackgroundColor3 = C(card.Colour)
		face.ItemName.Text = card.Name
		face.ItemKind.Text = card.Kind
		face.Tag.Text = card.Tag or "NEW"
		face.Tag.BackgroundColor3 = C(card.TagColour or "B9A6FF")
		art.Pic.Image = card.Image or ""
		art.Pic.Visible = card.Image ~= nil
		-- the coin pile art sits low in its square image: a touch bigger, nudged up onto the
		-- coins (like the shop's cards); everything else fills 82% of the art
		local coins = card.Kind == "Coins"
		art.Pic.AnchorPoint = Vector2.new(0.5, if coins then 0.56 else 0.5)
		art.Pic.Size = UDim2.fromScale(if coins then 1.12 else 0.82, if coins then 1.12 else 0.82)
		art.Big.Text = card.Big or ""
		art.Big.Visible = card.Big ~= nil
		local titleArt = art:FindFirstChild("TitleArt")
		if titleArt then
			titleArt.Visible = card.Title ~= nil
			if card.Title then
				titleArt.Player.Text = LOCAL_PLAYER.DisplayName
				local chip = titleArt.Chip
				chip.Text = card.Title
				-- Icon shines, Legend scrolls, the rest wear their colour (Levels.TITLE_COLOURS)
				TierShine.Apply(chip, chip.Rainbow, Levels.TITLE_TIERS[card.Title], Levels.TITLE_COLOURS[card.Title] or C("FFE07A"))
			end
		end
		c.Parent = frame.Items
		if card.Style then
			styleArt(art, card.Style[1], card.Style[2])
		end
		if card.Model then
			CosmeticView.Show(art, card.Model[1], card.Model[2])
			-- keep the card's own pastel, not the shop's night card
			local night = art:FindFirstChild("CardGradient")
			if night then
				night.Enabled = false
			end
			art.BackgroundColor3 = C(card.Colour)
		end
		sj:Add(c)
		table.insert(made, inner)
	end

	-- in: scrim fades up, banner pops, cards one after another, confetti, then the rest
	frame.Visible = true
	frame.Scrim.BackgroundTransparency = 1
	TweenService:Create(frame.Scrim, TweenInfo.new(0.25), { BackgroundTransparency = 0.25 }):Play()
	-- every card keeps its slot (so the row doesn't shuffle) but starts at zero size
	for _, inner in made do
		local s = inner:FindFirstChild("JuiceScale") or Instance.new("UIScale")
		s.Name = "JuiceScale"
		s.Scale = 0
		s.Parent = inner
	end
	frame.Where.Visible = false
	Juice.Stagger({ frame.Banner, frame.BannerShadow }, 0, 0.4)
	Juice.Pop(frame.Banner, 0.15)
	Sounds.Play("Perfect")
	for i, inner in made do
		sj:Add(task.delay(0.25 + (i - 1) * CARD_GAP, function()
			Juice.Stagger({ inner }, 0, 0)
			Sounds.Play(if cards[i].Kind == "Coins" then "Coins" else "SpinLand", { Pitch = 1 + i * 0.06 })
		end))
	end
	sj:Add(task.delay(0.25 + #made * CARD_GAP, function()
		frame.Where.Visible = true
		Juice.Stagger({ frame.Where }, 0, 0.6)
		self:_confetti()
	end))

	-- the rays turn while it's up
	local rays = frame.Rays
	sj:Add(RunService.RenderStepped:Connect(function(dt)
		rays.Rotation = (rays.Rotation + dt * RAY_SPEED) % 360
	end))
end

-- a quick burst of paper bits from behind the banner
function Purchased:_confetti()
	local layer = self._frame.Confetti
	for _ = 1, 36 do
		local bit = Instance.new("Frame")
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.Position = UDim2.fromOffset(640 + math.random(-60, 60), 110)
		bit.Size = UDim2.fromOffset(math.random(8, 13), math.random(12, 18))
		bit.Rotation = math.random(0, 360)
		bit.BackgroundColor3 = C(CONFETTI[math.random(#CONFETTI)])
		bit.BorderSizePixel = 0
		bit.ZIndex = layer.ZIndex
		local stroke = Instance.new("UIStroke")
		stroke.Color = C("1E1B2E")
		stroke.Thickness = 1.5
		stroke.Parent = bit
		bit.Parent = layer
		local angle = math.rad(math.random(200, 340)) -- mostly upwards and out
		local reach = math.random(180, 420)
		local peak = UDim2.fromOffset(640 + math.cos(angle) * reach, 110 + math.sin(angle) * reach * 0.6)
		local up = TweenService:Create(bit, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = peak, Rotation = bit.Rotation + math.random(-180, 180) })
		up.Completed:Once(function()
			local fall = TweenService:Create(bit, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = peak + UDim2.fromOffset(math.random(-40, 40), math.random(260, 420)),
				Rotation = bit.Rotation + math.random(-360, 360),
				BackgroundTransparency = 1,
			})
			TweenService:Create(stroke, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			fall.Completed:Once(function()
				bit:Destroy()
			end)
			fall:Play()
		end)
		up:Play()
	end
end

function Purchased:Hide(force: boolean?)
	if not self._showing then
		return
	end
	-- the tap that closed the last reveal (Nice + the scrim under it) must not also close the
	-- next one in the queue the moment it appears
	if not force and os.clock() - (self._shownAt or 0) < 0.4 then
		return
	end
	self._showing = nil
	self._showJanitor:Cleanup()
	self._frame.Confetti:ClearAllChildren()
	self._frame.Visible = false
	self.State = "Inactive"
	local nextUp = table.remove(self._queue, 1)
	if nextUp then
		task.defer(function()
			self:Show(nextUp)
		end)
	end
end

function Purchased:Activate(info)
	if info then
		self:Show(info)
	end
	return Promise.resolve()
end

function Purchased:Deactivate()
	self:Hide(true)
	return Promise.resolve()
end

function Purchased:Destroy()
	self._showJanitor:Destroy()
	self._janitor:Destroy()
end

return Purchased
