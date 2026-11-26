--| ShortOfferController
-- The "not enough" card (design board "Money 3"): when a buy fails because you're short, it
-- opens over the screen you're on with the smallest pack that covers the gap and its Robux
-- price; BUY goes straight to Roblox's prompt.
--   • coins: a shop set / item / banner / photocard, or a pack (ShopRemote / AlbumRemote replies
--     with Ok = false and Short = { Kind = "Coins", Need = price, Name }): how far off you are,
--     and the smallest coin bundle with Amount ≥ the gap (else the biggest). "See all packs"
--     goes to the shop's coin bundles.
--   • tickets: Short = { Kind = "Tickets" }: the POPULAR ticket bundle (nothing asks for it since
--     the song roll went, 25 Nov 2026).
-- Most buy buttons check your coins before asking the server: those call
-- ShortOfferController.Open(short) themselves (ShopController, AlbumsController).
-- Not an exclusive screen: it sits over the shop / packs screen (Frames.ShortOffer, ZIndex just
-- under the purchase reveal) and leaves it open underneath.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local Prices = require(ReplicatedStorage.Modules.Prices)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

local prices: { [number]: string } = {}
local current = nil -- the one instance (set in Initialize), for ShortOffer.Open

-- --------------------------------- Helpers -------------------------------- --
local function commas(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function forSale(list, filter): { any }
	local out = {}
	for _, b in list do
		if not b.Hidden and (b.ProductId or 0) > 0 and (not filter or filter(b)) then
			table.insert(out, b)
		end
	end
	table.sort(out, function(a, b)
		return a.Amount < b.Amount
	end)
	return out
end

-- the smallest coin bundle that covers the gap (else the biggest)
local function coinPack(gap: number)
	local list = forSale(ShopCatalog.CoinBundles)
	for _, b in list do
		if b.Amount >= gap then
			return b
		end
	end
	return list[#list]
end

-- the POPULAR ticket bundle (else the smallest)
local function ticketPack()
	local list = forSale(ShopCatalog.RollBundles, function(b)
		return b.Currency == "Tickets"
	end)
	for _, b in list do
		if b.Tag == "POPULAR" then
			return b
		end
	end
	return list[1]
end

local function price(productId: number): string
	if prices[productId] then
		return prices[productId]
	end
	local ok, info = Prices.Fetch(productId, Enum.InfoType.Product) -- (regional price)
	if ok and info and info.PriceInRobux then
		prices[productId] = tostring(info.PriceInRobux)
		return prices[productId]
	end
	return "…"
end

-- ---------------------------------- Class --------------------------------- --
local ShortOffer = {}
ShortOffer.__index = ShortOffer

function ShortOffer.new()
	local self = setmetatable({}, ShortOffer)
	self.Name = "ShortOffer"
	self.Exclusive = false
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._pack = nil :: any
	self._kind = "Coins"
	return (self :: any) :: UITypes.Controller
end

-- other screens call this when their own check says you're short (most buy buttons check
-- before asking the server): { Kind = "Coins", Need = price, Name } | { Kind = "Tickets" }
function ShortOffer.Open(short)
	if current and type(short) == "table" then
		current:Show(short)
	end
end

function ShortOffer:Initialize(interface)
	current = self
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "ShortOffer")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel

	j:Add(panel.Later.Activated:Connect(function()
		self:Hide()
	end))
	j:Add(panel.Offer.Buy.Activated:Connect(function()
		local pack = self._pack
		if pack then
			AnalyticsClient.Event("MoneyOffer", 1, self._kind, "Short")
			MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, pack.ProductId)
		end
	end))
	j:Add(panel.Alt.Activated:Connect(function()
		local kind = self._kind
		self:Hide()
		if kind == "Coins" then
			local shop = interface:GetController("Shop")
			if shop and (shop.State == "Active" or shop.State == "Activating") then
				(shop :: any):ScrollTo("Coins")
			else
				interface:Open("Shop", "Coins")
			end
		end
	end))
	-- bought: the reveal takes over
	j:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, bought)
		if bought and userId == LOCAL_PLAYER.UserId and self._pack and self._pack.ProductId == productId then
			self:Hide()
		end
	end))

	local function onShort(packet)
		if type(packet) == "table" and packet.Ok == false and type(packet.Short) == "table" then
			self:Show(packet.Short)
		end
	end
	j:Add(ShopRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Result" then
			onShort(packet)
		end
	end), "Disconnect")
end

function ShortOffer:Show(short)
	local panel = self._frame.Panel
	local tickets = short.Kind == "Tickets"
	local pack
	if tickets then
		pack = ticketPack()
		if not pack then
			return
		end
		panel.Header.Title.Text = "OUT OF ROLL TICKETS"
		panel.Line.Text = "Roll tickets roll a group for free. Get more, or roll with coins."
		panel.Offer.Item.Text = `{pack.Amount} roll tickets`
		panel.Offer.Sub.Text = if pack.Tag == "POPULAR" then "Most popular · roll any group" else "Roll any group"
		panel.Offer.IconBox.Icon.Image = Currencies.Tickets.Icon
		panel.Alt.Text = "Roll with coins"
	else
		local need = tonumber(short.Need) or 0
		local have = Currencies.Count(LOCAL_PLAYER, "Coins")
		local gap = math.max(1, need - have)
		pack = coinPack(gap)
		if not pack then
			return
		end
		local name = if type(short.Name) == "string" then short.Name else "that"
		panel.Header.Title.Text = "NOT ENOUGH COINS"
		panel.Line.Text = `You need {commas(gap)} more coins for {name}.`
		local prog = panel.Progress
		prog.Bar.Fill.Size = UDim2.fromScale(if need > 0 then math.clamp(have / need, 0, 1) else 0, 1)
		prog.Have.Text = `You have {commas(have)}`
		prog.Price.Text = `{name} · {commas(need)}`
		panel.Offer.Item.Text = `{commas(pack.Amount)} coins`
		panel.Offer.Sub.Text = if pack.Amount >= gap then `Covers it, with {commas(pack.Amount - gap)} left over` else "Our biggest pack"
		panel.Offer.IconBox.Icon.Image = pack.Pile or Currencies.Coins.Icon
		panel.Alt.Text = "See all packs"
	end
	self._kind = if tickets then "Tickets" else "Coins"
	self._pack = pack
	panel.Offer.Buy.Inner.Price.Text = "…"
	task.spawn(function()
		local p = price(pack.ProductId)
		if self._pack == pack then
			panel.Offer.Buy.Inner.Price.Text = p
		end
	end)

	-- the tickets version has no coins bar: the offer + buttons move up and the card shrinks
	local up = if tickets then Build.TICKETS_UP else 0
	panel.Progress.Visible = not tickets
	for _, n in { "Offer", "OfferShadow", "Later", "LaterShadow", "Alt", "AltShadow" } do
		local o = panel:FindFirstChild(n)
		if o then
			local base = o:GetAttribute("BaseY")
			if base == nil then
				base = o.Position.Y.Offset
				o:SetAttribute("BaseY", base)
			end
			o.Position = UDim2.new(o.Position.X.Scale, o.Position.X.Offset, 0, base - up)
		end
	end
	local h = Build.H - up
	panel.Size = UDim2.fromOffset(Build.W, h)
	panel.Position = UDim2.fromOffset(640 - Build.W / 2, 360 - h / 2)
	self._frame.PanelShadow.Size = panel.Size
	self._frame.PanelShadow.Position = panel.Position + UDim2.fromOffset(8, 8)

	if self.State == "Active" or self.State == "Activating" then
		Juice.Pop(panel.Offer, 0.15)
		return
	end
	self.State = "Activating"
	self._frame.Visible = true
	Juice.Pop(panel.Offer, 0.2)
	FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function ShortOffer:Hide()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return
	end
	self.State = "Deactivating"
	FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function ShortOffer:Activate(short)
	if type(short) == "table" then
		self:Show(short)
	end
	return Promise.resolve()
end

function ShortOffer:Deactivate()
	self:Hide()
	return Promise.resolve()
end

function ShortOffer:Destroy()
	self._janitor:Destroy()
end

return ShortOffer
