--| PurchasedController
-- The "YOU GOT!" reveal after any buy, so a player always sees what they got and where it went
-- (mock-up: UI canvas, "Purchase reveal"). It sits on top of whatever is open (not exclusive):
-- a scrim with turning light rays, a banner, one card per thing you got popping in one after
-- another (the real 3D model for stages / mics / sets, the coin pile for coins), a confetti
-- burst, "✓ Added to your Inventory", and EQUIP / Nice!.
--
-- What triggers it (no one has to call it):
--   ShopRemote reply  { Message = "Result", Ok = true, Action = "BuySet" | "BuyItem", Id, Kind }
--                     – coin buys; the server has already equipped them
--   PromptProductPurchaseFinished – the Debut Pack (waits for Rewards.Claimed "Debut") and coin bundles
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
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

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

	-- Robux: the Debut Pack + coin bundles
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

-- info = { Banner, Sub, Cards = { card? }, Where, EquipText?, Equip? }
-- card = { Name, Kind, Colour, Tag, TagColour, Model = { kind, id }? | Image? | Big? }
function Purchased:Show(info)
	-- drop missing cards (an id the catalog doesn't know), keep the order
	local cards = {}
	for i = 1, 4 do
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
		inner.Rotation = ({ -3, 1, 3, -1 })[i]
		local face = inner.Face
		local art = face.Art
		art.BackgroundColor3 = C(card.Colour)
		face.ItemName.Text = card.Name
		face.ItemKind.Text = card.Kind
		face.Tag.Text = card.Tag or "NEW"
		face.Tag.BackgroundColor3 = C(card.TagColour or "B9A6FF")
		art.Pic.Image = card.Image or ""
		art.Pic.Visible = card.Image ~= nil
		art.Big.Text = card.Big or ""
		art.Big.Visible = card.Big ~= nil
		c.Parent = frame.Items
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

function Purchased:Hide()
	if not self._showing then
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
	self:Hide()
	return Promise.resolve()
end

function Purchased:Destroy()
	self._showJanitor:Destroy()
	self._janitor:Destroy()
end

return Purchased
