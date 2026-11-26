--| AlbumsController
-- K-POPPED! photocards (Interface.Frames.Albums, built by ./Build). Full-screen, over a dark
-- backdrop, from the design boards "2 · Pick your bias", "16–20 · Pull v2" and "22–25 · Packs":
--   Bias   pick a group, then a member (BiasRemote → Engine/BiasService)
--   Shop   the Packs page (AlbumRemote → Engine/AlbumService):
--            Free packs   1 card from a gen you pick; Open / Open all; the refill clock
--                         (Albums.FreePacks on Inventory.FreePacks / FreePackAt). With none
--                         banked, Open uses a roll ticket.
--            Mixes & gens 5 cards from any group in a gen, or girl / boy / every group
--            Favourites   your bias's group and up to 2 pinned groups, always on sale
--            Today        group packs: 5 cards from the group you pick (photo sleeve when it
--                         has PackArt), today's rotation (Albums.Rotation); pin one to keep it
--          The sidebar: premium packs (rarity floors, the Polaroid guarantee) and Unopened
--          (roll tickets). The main column and the sidebar scroll (design board "26 · Packs v3").
--          ×1 / ×5 / ×10 for paid packs and the odds sheet (a chance per rarity, plus your bias
--          boost), next to the
--          coins at the top right
--   Pull   the stage. Tap the sleeve to tear it open; the card backs fan out and shuffle (a free
--          pack skips straight to its card). Then one card at a time: tap to flip it, tap again
--          to drop it in the tray (hold to go fast). A pack's last card is its best one and says
--          so; a rare card teases on its back, then gets the ring, rays, sparkles and its
--          rarity's name. The summary at the end is the only place with buttons: Sell under each
--          card (BinderRemote), Sell all duplicates, Done, Open again. Skip jumps there.
-- Collecting and duels are separate: nothing here is about songs.
--
-- Interface:Open("Albums", opts):
--   opts.Page = "Bias" | "Shop" (default Shop; Bias when you have no bias yet)
--   opts.First = true   the free first pack: Bias first if needed, then a free group pack of your
--                       bias's group straight away; opts.OnDone runs when it closes
--   opts.Group = artist the group pack to show first

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local Upgrades = require(ReplicatedStorage.Modules.Library.Upgrades)
local CardDecor = require(ReplicatedStorage.Modules.UI.CardDecor)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Notify = require(ReplicatedStorage.Modules.UI.Notify)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local ShortOffer = require(script.Parent.ShortOfferController)
local Reveal = require(script.Reveal)

local AlbumRemote = Bridgenet.ReferenceBridge("AlbumRemote")
local BiasRemote = Bridgenet.ReferenceBridge("BiasRemote")
local BinderRemote = Bridgenet.ReferenceBridge("BinderRemote")

local fmt = ShopCatalog.Format
local C = Color3.fromHex
local player = Players.LocalPlayer

-- --------------------------------- Tables --------------------------------- --
local SELECTED = C("FFE07A")
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local PINK = C("FF9EC4")
local GOLD = C("F2C94C")
-- Lucky Draw: cool silver holo (One of One keeps the full rainbow, so they never look alike)
local HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("C9D3E3")),
	ColorSequenceKeypoint.new(0.3, C("EEF3FA")),
	ColorSequenceKeypoint.new(0.5, C("9ED8F5")),
	ColorSequenceKeypoint.new(0.7, C("F6F8FC")),
	ColorSequenceKeypoint.new(1, C("AEB9CC")),
})
local GLITTER = ColorSequence.new(C("FF9EC4"), C("B9A6FF"))
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FF5A4E")),
	ColorSequenceKeypoint.new(0.2, C("FFE07A")),
	ColorSequenceKeypoint.new(0.4, C("A7E9B8")),
	ColorSequenceKeypoint.new(0.6, C("9ED8F5")),
	ColorSequenceKeypoint.new(0.8, C("B9A6FF")),
	ColorSequenceKeypoint.new(1, C("FF9EC4")),
})

-- how each rarity looks (design board "5 · Rarity ladder")
local STYLE = {
	standard = { Colour = WHITE },
	selca = { Colour = C("FFD2E5") },
	store = { Colour = C("A7E9B8"), Stamp = "STORE" },
	luckydraw = { Colour = WHITE, Foil = HOLO, Shine = true, Stamp = "LUCKY DRAW" },
	fansign = { Colour = WHITE, Foil = GLITTER, Shine = true, Stamp = "♡ FANSIGN" },
	polaroid = { Colour = C("FBF7F0"), Signature = true },
	oneofone = { Colour = WHITE, Foil = RAINBOW, Shine = true },
}

-- gen pack sleeves (design board "22 · Packs")
local GEN_COLOURS = {
	["2nd"] = C("C9C3D9"),
	["3rd"] = C("FFC9A8"),
	["4th"] = C("C9B8F0"),
	["5th"] = C("A8E0F5"),
}

local HOLDER_AT = UDim2.fromOffset(640, 300)
local PACK_AT = UDim2.fromOffset(640, 320)
local HOLD_STEP = 0.22 -- seconds between cards while the stage is held down

-- "13.75%", "0.5%", "25%"
local function pct(p: number): string
	local s = string.format("%.2f", p * 100)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s .. "%"
end

local function hex(colour: string?, fallback: string): Color3
	local ok, c = pcall(Color3.fromHex, colour or fallback)
	return if ok then c else C(fallback)
end

local function cards(): { [string]: number }
	return PlayerData.Inventory.Cards.Get() or {}
end

local function bias(): string
	return PlayerData.Inventory.Bias.Get() or ""
end

local function tween(gui: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(gui, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- every member of a group, newest album first (so the art is their latest era)
local function groupMembers(artist: string): { { Key: string, Name: string, Art: string, Colour: string? } }
	local list, seen = {}, {}
	local albums = Albums.PullAlbums(artist) -- (members of albums with card art: the ones you can pick)
	for i = #albums, 1, -1 do
		for _, member in albums[i].Members do
			if not seen[member.Key] then
				seen[member.Key] = true
				table.insert(list, { Key = member.Key, Name = member.Name, Art = member.Art, Colour = albums[i].Colour })
			end
		end
	end
	return list
end

local function generation(artist: string): string
	return Albums.Generation(artist)
end

-- the bias picker's groups: only ones with card art (Albums.PullArtists)
local function sortedArtists(): { string }
	local artists = Albums.PullArtists()
	table.sort(artists, function(a, b)
		local ga, gb = generation(a), generation(b)
		if ga ~= gb then
			return ga < gb
		end
		return a:lower() < b:lower()
	end)
	return artists
end

-- a group's colour: its newest album's
local function groupColour(artist: string): Color3
	local albums = Albums.ForArtist(artist)
	return hex(albums[#albums] and albums[#albums].Colour, "B9A6FF")
end

-- binder slots filled (one per member per album) and how many there are
local function albumOwned(album, owned: { [string]: number }): number
	local have = 0
	for _, member in album.Members do
		if Albums.Best(owned, album, member.Key) then
			have += 1
		end
	end
	return have
end
local function groupOwned(artist: string, owned: { [string]: number }): (number, number)
	local have, total = 0, 0
	for _, album in Albums.ForArtist(artist) do
		total += #album.Members
		have += albumOwned(album, owned)
	end
	return have, total
end

local function setButtonRow(b: GuiButton, label: string, amount: string?, icon: string?)
	local row = b:FindFirstChild("Row")
	if not row then
		(b :: any).Text = label
		return
	end
	row.Label.Text = label
	row.Amount.Text = amount or ""
	row.Amount.Visible = amount ~= nil
	row.Icon.Visible = amount ~= nil
	if icon then
		row.Icon.Image = icon
	end
end

local function showWithShadow(page: Instance, name: string, visible: boolean)
	local b = page:FindFirstChild(name)
	if b then
		b.Visible = visible
	end
	local s = page:FindFirstChild(name .. "Shadow")
	if s then
		s.Visible = visible
	end
end

-- dresses a card face (Build's cardFace) for a pull or a card id
local function fillFace(face: Instance, cardId: string, copies: number, isNew: boolean?, serial: number?)
	local info = Albums.Card(cardId)
	if not info then
		return nil
	end
	local rarity, album, member = info.Rarity, info.Album, info.Member
	local style = STYLE[rarity.Key] or STYLE.standard
	local card = face.Card
	card.BackgroundColor3 = style.Colour
	card.Foil.Enabled = style.Foil ~= nil
	if style.Foil then
		card.Foil.Color = style.Foil
	end
	local photo = card.Photo
	photo.BackgroundColor3 = hex(album.Colour, "FFD2E5")
	photo.Art.Image = member.Art or ""
	photo.Silhouette.Visible = (member.Art or "") == ""
	photo.Shine.Visible = style.Shine == true
	photo.Stamp.Visible = style.Stamp ~= nil
	photo.Stamp.Text = style.Stamp or ""
	photo.Signature.Visible = style.Signature == true
	photo.Signature.Text = member.Name
	local serialText = Albums.SerialText(cardId, serial)
	photo.Serial.Visible = serialText ~= nil
	photo.Serial.Text = serialText or ""
	card.Member.Text = member.Name
	card.Album.Text = album.Name
	card.Rarity.Text = string.upper(rarity.Name)
	local isBias = Albums.IsBias(album, member.Key, bias())
	card.Bias.Visible = isBias
	local level = Albums.Level(copies) or "Normal"
	card.Level.Visible = level ~= "Normal"
	card.Level.Text = string.upper(level)
	card.Level.Position = if isBias then UDim2.new(1, -60, 1, -72) else UDim2.new(1, -14, 1, -72)
	face.Glow.Visible = level ~= "Normal"
	face.Glow.BackgroundColor3 = if level == "Gold" then GOLD else WHITE
	face.Glow.Rainbow.Enabled = level == "Rainbow"
	if level == "Rainbow" then
		face.Glow.Rainbow.Color = RAINBOW
	end
	CardDecor.Paint(face, card, cardId, copies, { Serial = serial, Date = os.time() }) -- just rolled
	face.New.Visible = isNew == true
	return info
end

-- ---------------------------------- Class --------------------------------- --
local AlbumsController = {}
AlbumsController.__index = AlbumsController

function AlbumsController.new()
	local self = setmetatable({}, AlbumsController)
	self.Name = "Albums"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._opts = {}
	self._shopGroup = nil -- the group pack picked on the Packs page (its odds sheet)
	self._count = 1 -- ×1 / ×5 / ×10 paid packs
	self._freeGen = "Any" -- the gen free packs come from
	self._group = nil -- the group the Bias page shows
	self._pick = nil -- the member picked on the Bias page
	self._biasFilter = "All" -- the Bias page's group filter: "All" | "Girl" | "Boy"
	self._biasSearch = ""
	self._biasRows = {} -- artist → the Bias page's group row
	self._waiting = false -- an open / bias request is out
	self._pull = nil -- the pull on stage (see _startPull)
	self._token = 0 -- bumps whenever an animation should stop
	return (self :: any) :: UITypes.Controller
end

function AlbumsController:_toast(message: string?)
	Notify.Toast(message)
end

function AlbumsController:_showPage(name: string)
	for _, page in { "Bias", "Shop", "Pull" } do
		self._frame[page].Visible = page == name
	end
	self._page = name
end

-- -------------------------------- Bias page ------------------------------- --

-- a group's photo for its row icon (its PackArt), "" if none
local function groupArt(artist: string): string
	for _, album in Albums.PullAlbums(artist) do
		if album.PackArt and album.PackArt ~= "" then
			return album.PackArt
		end
	end
	return ""
end

-- the bias page's group list, like the binder's: search, All / Girls / Boys, a row per group
-- (rows are made once per group and kept; the picked one is yellow with a shadow)
function AlbumsController:_fillBiasGroups(curGroup: string?)
	local side = self._frame.Bias.Groups
	local scroll = side.List
	for _, b in side.Filters:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == self._biasFilter
			b.BackgroundTransparency = if on then 0 else 0.9
			b.TextColor3 = if on then INK else CREAM
			local s = b:FindFirstChildOfClass("UIStroke")
			s.Color = if on then INK else CREAM
			s.Transparency = if on then 0 else 0.75
		end
	end
	local search = string.lower(self._biasSearch)
	local shown, n = {}, 0
	for _, artist in sortedArtists() do
		if (self._biasFilter == "Girl" or self._biasFilter == "Boy") and Albums.GroupType(artist) ~= self._biasFilter then
			continue
		end
		if search ~= "" and not string.find(string.lower(artist), search, 1, true) then
			continue
		end
		n += 1
		shown[artist] = true
		local row = self._biasRows[artist]
		if not row then
			row = scroll.Template:Clone()
			row.Name = "Group"
			row:SetAttribute("Artist", artist)
			local icon = row.Button.Icon
			local art = groupArt(artist)
			icon.Image = art
			icon.BackgroundColor3 = groupColour(artist)
			icon.Initial.Visible = art == ""
			icon.Initial.Text = string.upper(string.sub(artist, 1, 1))
			local count = #groupMembers(artist)
			row.Button.Members.Text = `{count} member{if count == 1 then "" else "s"}`
			row.Button.Gen.Text = `{generation(artist)} gen`
			ButtonScale.Apply(row.Button)
			row.Button.Activated:Connect(function()
				if self._group ~= artist then
					Sounds.Play("Click")
					local group, member = Albums.BiasParts(bias())
					self._group = artist
					self._pick = if artist == group then member else nil
					self:_fillBias()
				end
			end)
			row.Parent = scroll
			self._biasRows[artist] = row
		end
		row.LayoutOrder = n
		local on = artist == self._group
		local b = row.Button
		b.Label.Text = if artist == curGroup then `{artist} <font color="#FF5A4E">♥</font>` else artist
		row.Shadow.Visible = on
		b.BackgroundColor3 = if on then SELECTED else CREAM
		b.BackgroundTransparency = if on then 0 else 0.95
		local s = b:FindFirstChildOfClass("UIStroke")
		s.Color = if on then INK else CREAM
		s.Transparency = if on then 0 else 0.9
		s.Thickness = if on then 3 else 2
		for _, name in { "Label", "Members", "Gen" } do
			b[name].TextColor3 = if on then INK else CREAM
		end
		row.Visible = true
	end
	for artist, row in self._biasRows do
		if not shown[artist] then
			row.Visible = false
		end
	end
	scroll.Empty.Visible = n == 0
end

function AlbumsController:_fillBias()
	local page = self._frame.Bias
	local current = bias()
	local curGroup, curMember = Albums.BiasParts(current)
	local artists = sortedArtists()
	if curGroup and not Albums.Pullable(curGroup) then
		curGroup, curMember = nil, nil -- (a bias from before its group's art was pulled)
	end
	self._group = self._group or curGroup or artists[1]
	if self._pick == nil and self._group == curGroup then
		self._pick = curMember
	end

	self:_fillBiasGroups(curGroup)

	local members = page.Members
	for _, child in members:GetChildren() do
		if child:IsA("GuiButton") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
	local pickedName = nil
	page.MembersLabel.Text = `{self._group} · tap your bias`
	for i, member in groupMembers(self._group) do
		local b = members.Template:Clone()
		b.Name = member.Key
		b.LayoutOrder = i
		b.Visible = true
		b.Label.Text = member.Name
		b.Photo.BackgroundColor3 = hex(member.Colour, "9ED8F5")
		b.Photo.Art.Image = member.Art or ""
		b.Photo.Silhouette.Visible = (member.Art or "") == ""
		local on = member.Key == self._pick
		if on then
			pickedName = member.Name
		end
		b.Size = UDim2.fromOffset(98, if on then 178 else 160)
		b.BackgroundColor3 = if on then PINK else WHITE
		b.UIStroke.Thickness = if on then 5 else 3
		b.MyBias.Visible = on
		b.Parent = members
		b.Activated:Connect(function()
			Sounds.Play("Click")
			self._pick = member.Key
			self:_fillBias()
		end)
	end

	local perks = page.Perks
	perks.BiasName.Text = pickedName or "Tap a member"
	perks.Group.Text = `{self._group} · {Packs.FANDOMS[self._group] or self._group .. " Stan"}`
	perks.PerkWeight.Tag.Text = `{AlbumConstants.BIAS_PULL_WEIGHT}×`
	perks.PerkWeight.Line.Text = `as likely in {self._group} pulls`
	perks.PerkEarn.Tag.Text = `+{math.round((AlbumConstants.BIAS_EARN - 1) * 100)}%`
	perks.PerkEarn.Line.Text = `binder earnings on {pickedName or "their"} cards`
	perks.PerkTag.Line.Text = "Shows on your nametag and profile"

	local value = self._pick and Albums.BiasValue(self._group, self._pick)
	local nextChange = if current == "" then 0 else PlayerData.Inventory.BiasAt.Get() + AlbumConstants.BIAS_CHANGE_SECONDS
	local wait = nextChange - os.time()
	local locked = current ~= "" and value ~= current and wait > 0
	page.Note.Text = if locked
		then `You can change your bias again in {math.ceil(wait / 86400)} day{if wait > 86400 then "s" else ""}.`
		else "You can change your bias once a week."
	local ready = value ~= nil and not locked
	page.Confirm.Text = if value ~= nil and value == current then "KEEP MY BIAS" else "THIS IS MY BIAS"
	page.Confirm.BackgroundColor3 = if ready then PINK else C("E3DCCD")
	page.Confirm.TextTransparency = if ready then 0 else 0.4
	-- the first pick can't be closed away
	showWithShadow(page, "Close", not (self._opts.First and current == ""))
end

function AlbumsController:_confirmBias()
	if self._waiting or not self._pick then
		return
	end
	local value = Albums.BiasValue(self._group, self._pick)
	if value == bias() then
		return self:_afterBias()
	end
	self._waiting = true
	Sounds.Play("Click")
	BiasRemote:Fire({ Action = "Set", Group = self._group, Member = self._pick })
end

function AlbumsController:_afterBias()
	if self._opts.First then
		self:_startFirst()
	elseif self._opts.Page == "Bias" then
		self._interface:Close(self.Name)
	else
		self._biasFromShop = false
		self:_showPage("Shop")
		self:_fillShop()
	end
end

-- -------------------------------- Shop page ------------------------------- --

-- the free first pack: a group pack of your bias's group, straight onto the stage
function AlbumsController:_startFirst()
	local group = Albums.BiasParts(bias())
	self._shopGroup = group or self._shopGroup
	self:_showPage("Shop")
	self:_fillShop()
	if group and self:_free() then
		self:_open("First", 1, group)
	end
end

function AlbumsController:_free(): boolean
	return self._opts.First == true and not PlayerData.Rewards.Claimed.Has(AlbumConstants.FIRST_ALBUM_KEY)
end

function AlbumsController:_balance()
	local coins = fmt(PlayerData.Currencies.Won.Get())
	self._frame.Shop.Balance.Coins.Amount.Text = coins
	self._frame.Shop.Balance.Tickets.Amount.Text = tostring(Currencies.Count(player, "Tickets"))
	self._frame.Pull.Balance.Coins.Amount.Text = coins
end

-- free packs banked now, and seconds to the next (nil while full)
local function freePacks(): (number, number?)
	local at = PlayerData.Inventory.FreePackAt.Get() or 0
	if at == 0 then
		return AlbumConstants.FREE_PACK_START, nil -- (the server sets the clock up on join)
	end
	local packs, _, wait = Albums.FreePacks(PlayerData.Inventory.FreePacks.Get() or 0, at, os.time(), Upgrades.Levels(PlayerData))
	return packs, wait
end

local function clock(seconds: number): string
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if h > 0 then
		return `{h}h {m}m`
	end
	return if m > 0 then `{m}m` else `{seconds}s`
end

local function packPrice(kind: string, target: string?): number
	if kind == "Premium" then
		local pack = Albums.Premium(target)
		return pack and pack.Cost or 0
	end
	return if kind == "Gen" then AlbumConstants.GEN_PACK_COST else AlbumConstants.GROUP_PACK_COST
end

local MIX_NAMES = {}
for _, mix in AlbumConstants.MIXES do
	MIX_NAMES[mix.Key] = mix.Name
end
local GEN_KEYS = { "2nd", "3rd", "4th", "5th", "Girl", "Boy", "All" }

-- "4th gen pack", "Girl groups pack"
local function poolName(pool: string?): string
	if pool and MIX_NAMES[pool] then
		return MIX_NAMES[pool]
	end
	return if pool then `{pool} gen` else "Any gen"
end

-- the free-packs panel and its clock (runs every second while the page is open)
function AlbumsController:_fillFree()
	local free = self._frame.Shop.Main.Free
	local packs, wait = freePacks()
	local tickets = Currencies.Count(player, "Tickets")
	free.Count.Text = if packs == 1 then "1 free pack" else `{packs} free packs`
	free.Line.Text = if packs == 0 and tickets > 0
		then `Roll tickets open one too ({tickets} left). Pick a gen:`
		else "1 card each. Any rarity can turn up. Pick a gen:"
	for _, b in free.Gens:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == self._freeGen
			b.BackgroundColor3 = if on then C("1E1B2E") else CREAM
			b.TextColor3 = if on then CREAM else C("1E1B2E")
		end
	end
	local canOpen = packs > 0 or tickets > 0
	free.Open.BackgroundColor3 = if canOpen then C("A7E9B8") else C("E3DCCD")
	free.OpenAll.Visible = packs > 1
	free.OpenAll.Text = `Open all {math.min(packs, AlbumConstants.FREE_OPEN_MAX)}`
	-- one OPEN fills the row when there's nothing to open all of
	local wide = packs <= 1
	free.Open.Size = UDim2.fromOffset(if wide then 296 else 168, 46)
	free.Open.Position = UDim2.fromOffset(if wide then 668 else 604, 40)
	free.Open.Text = if packs == 0 and tickets > 0 then "OPEN WITH A TICKET" elseif wide then "OPEN FREE PACK" else "OPEN"
	free.OpenShadow.Size = free.Open.Size
	free.OpenShadow.Position = free.Open.Position + UDim2.fromOffset(4, 4)
	local lv = Upgrades.Levels(PlayerData)
	free.Cap.Text = `holds up to {Upgrades.StashCap(lv)}`
	if wait then
		free.Timer.Text = `Next free pack in {clock(wait)}`
		free.Track.Fill.Size = UDim2.fromScale(1 - wait / Upgrades.RefillSeconds(lv), 1)
	else
		free.Timer.Text = "Full! Open some to start the clock"
		free.Track.Fill.Size = UDim2.fromScale(1, 1)
	end
	-- the stack: one sleeve per pack (up to 3), centred in its spot
	local shown = math.clamp(packs, 1, 3)
	local left = (130 - (105 + (shown - 1) * 12)) / 2
	for k = 1, 3 do
		local sleeve = free.Stack["Sleeve" .. k]
		local i = k - (3 - shown) -- the top sleeve is always Sleeve3
		sleeve.Visible = i >= 1
		sleeve.Position = UDim2.fromOffset(left + (i - 1) * 12, (shown - i) * 8 + (3 - shown) * 4)
		sleeve.Sleeve.BackgroundTransparency = if packs == 0 then 0.5 else 0
	end
end

function AlbumsController:_fillShop()
	local page = self._frame.Shop
	local main = page.Main
	local biasArtist = Albums.BiasParts(bias())
	local favourites = Albums.Favourites(PlayerData.Inventory.FavGroups.Get())
	local allowed = player:GetAttribute("RollsAllowed") == true
	page.Blocked.Visible = not allowed
	local coins = PlayerData.Currencies.Won.Get()

	-- ×1 / ×5 / ×10
	for _, b in page.Controls.Counts:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == "X" .. self._count
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then C("1E1B2E") else CREAM
		end
	end
	local x = if self._count > 1 then ` ×{self._count}` else ""

	self:_fillFree()
	showWithShadow(main.Free, "Open", allowed)
	main.Free.OpenAll.Visible = allowed and main.Free.OpenAll.Visible

	-- mixes & gens
	for _, key in GEN_KEYS do
		local tile = main.GenPacks:FindFirstChild(key)
		if tile then
			local n = #Albums.ArtistsIn(key)
			tile.Visible = n > 0
			self:_dressSleeve(tile.Pack.Sleeve, nil, key)
			tile.Label.Text = if key == "All" then "Every group" elseif n == 1 then "1 group" else `{n} groups`
			tile.Price.Amount.Text = fmt(AlbumConstants.GEN_PACK_COST * self._count)
			tile.Buy.Text = "BUY" .. x
			showWithShadow(tile, "Buy", allowed)
		end
	end

	-- group packs: favourites (your bias's group, then pinned ones) and today's rotation
	local rotation, ends = Albums.Rotation(os.time())
	self._rotationEnds = ends
	local favList = {}
	if biasArtist and Albums.Pullable(biasArtist) then
		table.insert(favList, biasArtist)
	end
	for _, name in favourites do
		if not table.find(favList, name) then
			table.insert(favList, name)
		end
	end
	if self._oddsLink and (self._oddsLink:IsDescendantOf(main.Favs) or self._oddsLink:IsDescendantOf(main.Today)) then
		self:_hideOdds()
	end
	local function fillRow(row: Instance, names: { string })
		for _, child in row:GetChildren() do
			if child:IsA("GuiButton") and child.Name ~= "Template" then
				child:Destroy()
			end
		end
		for order, name in names do
			local tile = row.Template:Clone()
			tile.Name = name
			tile.LayoutOrder = order
			tile.Visible = true
			self:_dressSleeve(tile.Pack.Sleeve, name)
			tile.Label.Text = name
			tile.Bias.Visible = name == biasArtist
			local pinned = table.find(favourites, name) ~= nil
			tile.Pin.Visible = name ~= biasArtist
			tile.Pin.Text = if pinned then "PINNED" else "+ PIN"
			tile.Pin.BackgroundColor3 = if pinned then C("FFE07A") else C("1E1B2E")
			tile.Pin.TextColor3 = if pinned then C("1E1B2E") else CREAM
			tile.Pin.Size = UDim2.fromOffset(if pinned then 60 else 46, 22)
			tile.Price.Amount.Text = fmt(AlbumConstants.GROUP_PACK_COST * self._count)
			tile.Buy.Text = "BUY" .. x
			tile.Buy.BackgroundColor3 = if name == biasArtist then C("A7E9B8") else C("FFE07A")
			showWithShadow(tile, "Buy", allowed)
			tile.Parent = row
			ButtonScale.Apply(tile.Buy)
			tile.Activated:Connect(function()
				Sounds.Play("Click")
				self._shopGroup = name
			end)
			tile.Buy.Activated:Connect(function()
				self._shopGroup = name
				self:_open("Group", self._count, name)
			end)
			tile.Pin.Activated:Connect(function()
				if not pinned and #favourites >= AlbumConstants.FAVOURITES_MAX then
					Sounds.Play("Wrong")
					Juice.Shake(tile.Pin)
					self:_toast(`You can pin {AlbumConstants.FAVOURITES_MAX} groups: unpin one first`)
					return
				end
				Sounds.Play("Click")
				AlbumRemote:Fire({ Action = "Star", Group = name })
			end)
			self:_hookOdds(tile.Odds, "Group", name)
		end
	end
	fillRow(main.Favs, favList)
	main.Favs.Empty.Visible = #favourites < AlbumConstants.FAVOURITES_MAX
	local todayList = {}
	for _, name in rotation do
		if not table.find(favList, name) then
			table.insert(todayList, name)
		end
	end
	fillRow(main.Today, todayList)
	if not self._shopGroup or not (table.find(favList, self._shopGroup) or table.find(todayList, self._shopGroup)) then
		self._shopGroup = favList[1] or todayList[1]
	end

	-- premium packs
	local prem = page.Side.Premium
	for _, pack in AlbumConstants.PREMIUM_PACKS do
		local card = prem:FindFirstChild(pack.Key)
		if card then
			card.Title.Text = pack.Name
			local cardRarity = Albums.Rarity(pack.CardMin)
			local lastRarity = Albums.Rarity(pack.LastMin)
			card.Line.Text = if Albums.RarityRank(pack.CardMin) > 1
				then `Every card {cardRarity and cardRarity.Name or ""}+. Last is {lastRarity and lastRarity.Name or ""}+`
				else `Last card is {lastRarity and lastRarity.Name or ""} or better`
			local cost = pack.Cost * self._count
			if coins >= cost then
				setButtonRow(card.Buy, "", fmt(cost), Currencies.Coins.Icon)
			else
				setButtonRow(card.Buy, `Need {fmt(cost - coins)} more`, nil)
			end
			local robux = pack.ProductId ~= 0 and self._count == 1
			showWithShadow(card, "Robux", allowed and robux)
			card.Robux.Text = `R$ {pack.Robux or 0}`
			card.Buy.Size = UDim2.fromOffset(if robux then 170 else 268, 38)
			card.Buy.Position = UDim2.fromOffset(if robux then 96 else 146, 124)
			card.BuyShadow.Size = card.Buy.Size
			card.BuyShadow.Position = card.Buy.Position + UDim2.fromOffset(4, 4)
			showWithShadow(card, "Buy", allowed)
		end
	end
	local pity = PlayerData.Inventory.PremiumPity.Get() or 0
	local need = AlbumConstants.PREMIUM_GUARANTEE
	local guaranteed = Albums.Rarity(AlbumConstants.GUARANTEE_RARITY)
	prem.Guarantee.Text = `{guaranteed and guaranteed.Name or ""} guarantee`
	prem.GuaranteeCount.Text = `{pity} / {need}`
	prem.GuaranteeTrack.Fill.Size = UDim2.fromScale(math.clamp(pity / need, 0, 1), 1)
	prem.GuaranteeNote.Text = `Go {need - 1} premium packs without a {guaranteed and guaranteed.Name or ""} and the next one ends with one.`

	-- unopened
	local tickets = Currencies.Count(player, "Tickets")
	local unopened = page.Side.Unopened
	unopened.Tickets.Label.Text = `Pack tickets ×{tickets}`
	showWithShadow(unopened.Tickets, "Open", allowed and tickets > 0)
	-- gen packs bought with Robux: a whole gen pack each (the free pack's gen pick, else any)
	local genPacks = Currencies.Count(player, "GenPacks")
	local genRow = unopened:FindFirstChild("GenPacks")
	if genRow then
		genRow.Label.Text = `Gen packs ×{genPacks}`
		showWithShadow(genRow, "Open", allowed and genPacks > 0)
	end

	self:_fillRotation()
	self:_balance()
	if page.OddsSheet.Visible then
		self:_fillOdds()
	end
end

-- [[ The odds popover: hover (or tap) a pack's Odds link ]]

-- kind = "Free" | "Gen" | "Group"; target = gen ("Any" for free) or group
function AlbumsController:_showOdds(link: GuiObject, kind: string, target: string)
	local page = self._frame.Shop
	local pop = page.Popover
	local size = if kind == "Free" then 1 else AlbumConstants.PACK_SIZE
	local premium = if kind == "Premium" then Albums.Premium(target) else nil
	local luck = Upgrades.Luck(Upgrades.Levels(PlayerData)) -- (the odds shown are the ones you pull with)
	local each = Albums.LastOdds(1, nil, premium and premium.CardMin, nil, luck)
	local last = Albums.LastOdds(size, nil, premium and premium.CardMin, premium and premium.LastMin, luck)
	if kind == "Free" then
		pop.Title.Text = if target ~= "Any" then `Free pack · {target} gen` else "Free pack · any gen"
	elseif premium then
		pop.Title.Text = premium.Name
	elseif kind == "Gen" then
		local n = #Albums.ArtistsIn(target)
		pop.Title.Text = if target == "All" then `{poolName(target)} · every group` else `{poolName(target)} pack · {n} groups`
	else
		pop.Title.Text = `{target} pack`
	end
	pop.Header.Each.Text = if size > 1 then `CARDS 1-{size - 1}` else ""
	pop.Header.Last.Text = if size > 1 then "LAST" else "THE CARD"
	local rarities = Albums.RarityOdds(nil, nil, luck)
	for i = 1, 7 do
		local r = pop:FindFirstChild("Row" .. i)
		local entry = rarities[i]
		if r then
			r.Visible = entry ~= nil
			if entry then
				local key = entry.Rarity.Key
				local style = STYLE[key] or STYLE.standard
				r.Label.Text = entry.Rarity.Name
				r.Each.Text = if size > 1 then pct(each[key] or 0) else ""
				r.Last.Text = pct(last[key] or 0)
				r.Dot.BackgroundColor3 = style.Colour
				r.Dot.Foil.Enabled = style.Foil ~= nil
				if style.Foil then
					r.Dot.Foil.Color = style.Foil
				end
			end
		end
	end
	local note
	if premium then
		local pity = PlayerData.Inventory.PremiumPity.Get() or 0
		note = `{size} cards from any group, shown worst to best. {AlbumConstants.PREMIUM_GUARANTEE - 1 - pity} more premium packs without a Signed Polaroid and the next one ends with one.`
	elseif kind == "Free" then
		note = "1 card. Every group in the gen is equally likely, then each of its albums."
	elseif kind == "Gen" then
		note = `{size} cards, shown worst to best: the last is the best of the {size}. Every group in the gen is equally likely.`
	else
		note = `{size} cards, shown worst to best: the last is the best of the {size}. Each of the group's albums is equally likely.`
		local artist, key = Albums.BiasParts(bias())
		if artist == target and key then
			for _, m in groupMembers(target) do
				if m.Key == key then
					note ..= ` Bias boost: {m.Name} is {AlbumConstants.BIAS_PULL_WEIGHT}× as likely.`
				end
			end
		end
	end
	pop.Note.Text = note

	-- next to the link, kept on the page: above it in the lower half, below it up top
	local scale = page.AbsoluteSize.X / 1280
	if scale <= 0 then
		return
	end
	local at = (link.AbsolutePosition - page.AbsolutePosition) / scale
	local w, h = 330, 326
	local x = math.clamp(at.X + link.AbsoluteSize.X / scale - w, 16, 1280 - w - 16)
	local y = if at.Y > 360 then at.Y - h - 8 else at.Y + link.AbsoluteSize.Y / scale + 8
	pop.Position = UDim2.fromOffset(x, math.clamp(y, 16, 720 - h - 8))
	pop.Visible = true
	self._oddsLink = link
end

function AlbumsController:_hideOdds(link: GuiObject?)
	if link == nil or self._oddsLink == link then
		self._frame.Shop.Popover.Visible = false
		self._oddsLink = nil
	end
end

-- hover shows it, leaving hides it; a tap (touch, gamepad) toggles it
function AlbumsController:_hookOdds(link: GuiButton, kind: string, target: string | () -> string)
	local function resolve(): string
		return if type(target) == "function" then target() else target
	end
	link.MouseEnter:Connect(function()
		self:_showOdds(link, kind, resolve())
	end)
	link.MouseLeave:Connect(function()
		self:_hideOdds(link)
	end)
	link.Activated:Connect(function()
		if self._oddsLink == link and self._frame.Shop.Popover.Visible then
			self:_hideOdds(link)
		else
			Sounds.Play("Click")
			self:_showOdds(link, kind, resolve())
		end
	end)
end

-- "New groups in 5h 12m"; refills the page when the rotation turns over
function AlbumsController:_fillRotation()
	local ends = self._rotationEnds or 0
	local left = ends - os.time()
	if left <= 0 then
		self:_fillShop()
		return
	end
	self._frame.Shop.Main.TodayHead.NewGroups.Label.Text = `New groups in {clock(left)}`
end

-- a sleeve for a pack: a group's colour (and photo, when it has PackArt), a gen's or mix's, or
-- a premium pack's
function AlbumsController:_dressSleeve(sleeve: Instance, artist: string?, gen: string?, premiumKey: string?)
	local albums = artist and Albums.ForArtist(artist) or {}
	local art = albums[1] and albums[1].PackArt or ""
	local premium = Albums.Premium(premiumKey)
	sleeve.BackgroundColor3 = if premium then hex(premium.Colour, "FFE07A") elseif artist then groupColour(artist) else (GEN_COLOURS[gen or ""] or C("A7E9B8"))
	sleeve.Band.Label.Text = if premium then premium.Short
		elseif artist then artist
		elseif gen == "All" then "SHUFFLE"
		elseif gen and MIX_NAMES[gen] then string.upper(gen) .. "S"
		elseif gen then string.upper(gen) .. " GEN"
		else "FREE"
	sleeve.Photo.Image = art
	sleeve.Photo.Visible = art ~= ""
	sleeve.Stripes.Visible = art == ""
	sleeve.Band.Visible = art == "" -- group art speaks for itself; the name goes under the tile
end

-- what each rarity is (the Rarities sheet, rarest first)
local BLURBS = {
	oneofone = "The rarest card in the game: there's exactly one of each member's card, so if you pull it, nobody else ever can. Every server hears about it, and it can't be sold. If that member's One of One is already owned, you get a Signed Polaroid instead.",
	polaroid = "A real Polaroid with the member's signature across it. Numbered: every copy gets a serial (#1 is the first anyone pulled), and the whole server hears about it.",
	fansign = "The card you'd only get at a fansign event: glitter foil and a heart stamp. Numbered: every copy gets a serial, and the whole server hears about it.",
	luckydraw = "Silver holo foil with a shine and a Lucky Draw stamp, like the cards fans queue for at a record store. The whole server hears about it.",
	store = "A store-exclusive card with the shop's stamp in the corner. Earns and sells well.",
	selca = "A self-camera shot on pink. A step up from Standard.",
	standard = "The photocard that comes inside the album. Most of what you pull.",
}

-- "1 in 37 packs" / "in most packs": the chance a normal pack has at least one
local function perPack(odds: number): string
	local chance = 1 - (1 - odds) ^ AlbumConstants.PACK_SIZE
	if chance >= 0.5 then
		return `in {math.round(chance * 100)}% of packs`
	end
	return `1 in {math.round(1 / chance)} packs`
end

-- the Rarities sheet (a paid random item: shown before paying). Every rarity rarest first, what
-- it is, how often it turns up, what it sells for and earns; your bias boost underneath.
function AlbumsController:_fillOdds()
	local panel = self._frame.Shop.OddsSheet.Panel
	local list = panel.List
	for _, child in list:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
	local live = {}
	for _, entry in Albums.RarityOdds(nil, nil, Upgrades.Luck(Upgrades.Levels(PlayerData))) do
		live[entry.Rarity.Key] = entry.Odds
	end
	local order = 0
	for i = #AlbumConstants.RARITIES, 1, -1 do
		local rarity = AlbumConstants.RARITIES[i]
		order += 1
		local row = list.Template:Clone()
		row.Name = rarity.Key
		row.LayoutOrder = order
		row.Visible = true
		local style = STYLE[rarity.Key] or STYLE.standard
		row.Swatch.BackgroundColor3 = style.Colour
		row.Swatch.Foil.Enabled = style.Foil ~= nil
		if style.Foil then
			row.Swatch.Foil.Color = style.Foil
		end
		row.Swatch.Rank.Text = `#{order}`
		row.Body.Heading.Text = rarity.Name
		row.Body.Blurb.Text = BLURBS[rarity.Key] or ""
		local chips = row.Body.Chips
		local odds = live[rarity.Key]
		chips.Chip1.Text = if odds then `{pct(odds)} of cards · {perPack(odds)}` else "Coming in a later update"
		chips.Chip2.Visible = rarity.Sell ~= nil and not rarity.Unsellable
		chips.Chip2.Text = `Sells for {fmt(rarity.Sell or 0)}`
		chips.Chip3.Text = `Earns {rarity.Earn}/hr`
		chips.Chip4.Visible = rarity.Announce == true or rarity.Unsellable == true
		chips.Chip4.Text = if rarity.Key == "oneofone" then "1 of 1 · every server · can't be sold" elseif rarity.Serial then "Numbered · server shout-out" else "Server shout-out"
		row.Parent = list
	end
	list.CanvasPosition = Vector2.zero

	local artist, key = Albums.BiasParts(bias())
	local name = nil
	if artist and key then
		for _, m in groupMembers(artist) do
			if m.Key == key then
				name = m.Name
			end
		end
	end
	local weight = AlbumConstants.BIAS_PULL_WEIGHT
	panel.Boost.Tag.Text = `{weight}×`
	local levels = `Copies level a card up: {AlbumConstants.GOLD_COPIES} make it Gold ({AlbumConstants.LEVEL_EARN.Gold}× earnings), {AlbumConstants.RAINBOW_COPIES} make it Rainbow ({AlbumConstants.LEVEL_EARN.Rainbow}×).`
	panel.Boost.Line.Text = if name
		then `Bias boost: {name} is {weight}× as likely as the rest of {artist} in {artist} packs. {levels}`
		else `Bias boost: pick a bias and they're {weight}× as likely in their group's packs. {levels}`
end

-- kind = "Free" | "Gen" | "Group" | "First"; count = packs (Free: 1 or "All")
function AlbumsController:_open(kind: string, count: any, target: string?)
	if self._waiting then
		return
	end
	local page = self._frame.Shop
	if kind == "Gen" or kind == "Group" or kind == "Premium" then
		local cost = packPrice(kind, target) * count
		if PlayerData.Currencies.Won.Get() < cost then
			Sounds.Play("Wrong")
			local tile = if kind == "Gen" then page.Main.GenPacks:FindFirstChild(target or "")
				elseif kind == "Premium" then page.Side.Premium:FindFirstChild(target or "")
				else (page.Main.Favs:FindFirstChild(target or "") or page.Main.Today:FindFirstChild(target or ""))
			if tile and tile:FindFirstChild("Buy") then
				Juice.Shake(tile.Buy)
			end
			ShortOffer.Open({ Kind = "Coins", Need = cost, Name = if count == 1 then "a pack" else `{count} packs` })
			return
		end
	elseif kind == "Ticket" then
		if Currencies.Count(player, "Tickets") < 1 then
			Sounds.Play("Wrong")
			return
		end
	elseif kind == "Owned" then
		if Currencies.Count(player, "GenPacks") < 1 then
			Sounds.Play("Wrong")
			return
		end
	elseif kind == "Free" then
		local packs = freePacks()
		if packs < 1 and Currencies.Count(player, "Tickets") < 1 then
			Sounds.Play("Wrong")
			Juice.Shake(page.Main.Free.Open)
			self:_toast("No free packs yet: the next one is on its way")
			return
		end
	end
	self._waiting = true
	Sounds.Play("Click")
	self._last = { Kind = kind, Count = count, Target = target }
	if kind == "First" then
		AlbumRemote:Fire({ Action = "First", Group = target })
	elseif kind == "Free" then
		AlbumRemote:Fire({ Action = "Open", Kind = "Free", Gen = if target ~= "Any" then target else nil, Count = count })
	elseif kind == "Ticket" then
		AlbumRemote:Fire({ Action = "Open", Kind = "Free", Ticket = true, Count = 1 })
	elseif kind == "Owned" then
		local gen = target or self._freeGen
		AlbumRemote:Fire({ Action = "Open", Kind = "Gen", Gen = if gen and gen ~= "Any" then gen else nil, Owned = true, Count = 1 })
	elseif kind == "Gen" then
		AlbumRemote:Fire({ Action = "Open", Kind = "Gen", Gen = target, Count = count })
	elseif kind == "Premium" then
		AlbumRemote:Fire({ Action = "Open", Kind = "Premium", Pack = target, Count = count })
	else
		AlbumRemote:Fire({ Action = "Open", Kind = "Group", Group = target, Count = count })
	end
end

-- -------------------------------- The pull -------------------------------- --
-- self._pull = { Pulls, Index (card on show, 0 = none yet), Kind, Group, Gen, How, Packs, Size,
--               Count (cards), Sold = { [i] = true }, Phase = "Pack" | "Busy" | "Back" | "Face" |
--               "Summary", Complete }

local STAGE = { "Pack", "Strip", "Fan", "Holder", "Rarity", "Page", "Tray", "Rays", "Ring", "Sparkles", "Confetti", "Summary" }

function AlbumsController:_hideStage()
	local page = self._frame.Pull
	for _, n in STAGE do
		page[n].Visible = false
	end
	self:_spinRays(false)
	if self._reveal then
		self._reveal:Reset()
	end
end

function AlbumsController:_spinRays(on: boolean)
	local page = self._frame.Pull
	page.Rays.Visible = on
	page.Ring.Visible = on
	page.Sparkles.Visible = on
	if self._raysConn then
		self._raysConn:Disconnect()
		self._raysConn = nil
	end
	if on then
		local t = 0
		self._raysConn = RunService.RenderStepped:Connect(function(dt)
			t += dt
			page.Rays.Rotation = (page.Rays.Rotation + dt * 16) % 360
			for i, s in page.Sparkles:GetChildren() do
				if s:IsA("Frame") then
					s.Rotation = 45 + math.sin(t * 3 + i) * 20
				end
			end
		end)
	end
end

-- colours: the rarity's palette (Reveal.CONFETTI); nil keeps the bits' own colours
function AlbumsController:_confetti(colours: { Color3 }?)
	local box = self._frame.Pull.Confetti
	box.Visible = true
	for i, bit in box:GetChildren() do
		if bit:IsA("Frame") then
			if colours then
				bit:SetAttribute("Colour", bit:GetAttribute("Colour") or bit.BackgroundColor3)
				bit.BackgroundColor3 = colours[(i - 1) % #colours + 1]
			elseif bit:GetAttribute("Colour") then
				bit.BackgroundColor3 = bit:GetAttribute("Colour")
			end
			bit.Position = UDim2.fromOffset(0, 0)
			bit.Rotation = 0
			bit.BackgroundTransparency = 0
			bit.UIStroke.Transparency = 0
			local x, y, r = math.random(-420, 420), math.random(-300, -60), math.random(0, 360)
			tween(bit, 0.5, { Position = UDim2.fromOffset(x, y), Rotation = r }).Completed:Once(function()
				tween(bit, 1.3, { Position = UDim2.fromOffset(x * 1.1, y + 460), Rotation = r * 2, BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tween(bit.UIStroke, 1.3, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		end
	end
	task.delay(2, function()
		box.Visible = false
	end)
end

local function packName(p): string
	if p.How == "First" then
		return "Free pack"
	elseif p.Kind == "Free" then
		return if p.How == "Ticket" then "Ticket pack" else "Free pack"
	elseif p.Kind == "Premium" then
		local pack = Albums.Premium(p.Pack)
		return pack and pack.Name or "Premium pack"
	elseif p.Kind == "Gen" then
		return `{poolName(p.Gen)} pack`
	end
	return "Group pack"
end

-- the line under the title: where you are in the open (the title already names the pack)
function AlbumsController:_subLine()
	local p = self._pull
	local page = self._frame.Pull
	local cardsWord = if p.Count == 1 then "1 card" else `{p.Count} cards`
	if p.Phase == "Summary" then
		page.Sub.Text = `Done · {cardsWord}`
	elseif p.Index > 0 and p.Size > 1 then
		local pack = (p.Index - 1) // p.Size + 1
		local card = (p.Index - 1) % p.Size + 1
		page.Sub.Text = if p.Packs > 1 then `Pack {pack} of {p.Packs} · card {card} of {p.Size}` else `Card {card} of {p.Size}`
	elseif p.Index > 0 and p.Count > 1 then
		page.Sub.Text = `Card {p.Index} of {p.Count}`
	elseif p.Size > 1 then
		page.Sub.Text = if p.Packs > 1 then `{p.Packs} packs · {p.Size} cards each` else `{p.Size} cards · the best one is last`
	else
		page.Sub.Text = `{poolName(p.Gen)} · 1 card`
	end
end

-- 16 · the sealed sleeve, waiting for a tap
function AlbumsController:_startPull(packet)
	self._token += 1
	self._pull = {
		Pulls = packet.Pulls,
		Index = 0,
		Kind = packet.Kind,
		Group = packet.Group,
		Gen = packet.Gen,
		Pack = packet.Pack,
		How = packet.How,
		Packs = packet.Packs or 1,
		Size = packet.Size or 1,
		Count = #packet.Pulls,
		Sold = {},
		Phase = "Pack",
		Complete = packet.Complete,
		SetBonus = packet.SetBonus,
	}
	self:_showPage("Pull")
	self:_hideStage()
	local p = self._pull
	local page = self._frame.Pull
	page.Group.Text = (if packet.Group then `{packet.Group} pack` else packName(p)) .. (if p.Packs > 1 then ` ×{p.Packs}` else "")
	self:_subLine()
	self:_balance()
	page.Skip.Visible = true
	page.Hint.Visible = true
	for _, child in page.Tray:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "Template" then
			child:Destroy()
		end
	end

	-- a free pack is one card: no sleeve to tear, straight to the card
	if p.Size == 1 then
		self:_nextBack()
		return
	end

	page.Hint.Text = "Tap the sleeve to open it"
	local pack = page.Pack
	local sleeve = pack.Sleeve
	self:_dressSleeve(sleeve, packet.Group, packet.Gen, packet.Pack)
	sleeve.Sticker.Visible = true
	sleeve.Sticker.Count.Text = if p.Packs > 1 then `{p.Packs}\nPACKS` else `×{p.Size}`
	sleeve.Tear.Visible = true
	pack.Disc.Position = UDim2.new(0.5, 30, 0.5, 0)
	pack.Disc.Rotation = 0
	pack.Glow.BackgroundTransparency = 1
	pack.Rotation = -8
	pack.Scale.Scale = 1.2
	pack.Position = UDim2.fromOffset(640, -200)
	pack.Visible = true
	Sounds.Play("Click")
	tween(pack, 0.4, { Position = PACK_AT, Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	-- an idle bob while it waits
	local token = self._token
	task.spawn(function()
		task.wait(0.45)
		local t = 0
		while self._token == token and self._pull and self._pull.Phase == "Pack" do
			t += task.wait()
			pack.Rotation = math.sin(t * 2.2) * 2
		end
	end)
end

-- 17 · tear it open: the strip flies off, the backs fan out and shuffle into one stack
function AlbumsController:_openPack()
	local p = self._pull
	p.Phase = "Busy"
	self._token += 1
	local token = self._token
	local page = self._frame.Pull
	local pack = page.Pack
	page.Hint.Visible = false
	task.spawn(function()
		pack.Rotation = 0
		Sounds.Play("PackTear")
		pack.Sleeve.Tear.Visible = false
		local strip = page.Strip
		strip.Position = UDim2.fromOffset(640, 178)
		strip.Rotation = 0
		strip.BackgroundColor3 = pack.Sleeve.BackgroundColor3
		strip.Visible = true
		tween(strip, 0.45, { Position = UDim2.fromOffset(820, 40), Rotation = 24 })
		tween(pack.Scale, 0.12, { Scale = 1.28 })
		task.wait(0.14)
		if self._token ~= token then
			return
		end
		-- the cards come up out of the sleeve, then the sleeve drops away
		local fan = page.Fan
		fan.Visible = true
		local slots = {}
		for i = 1, 5 do
			local s = fan["Back" .. i]
			s.Position = UDim2.fromOffset(640, 330)
			s.Rotation = 0
			s.Scale.Scale = 0.5
			table.insert(slots, s)
		end
		tween(pack, 0.3, { Position = PACK_AT + UDim2.fromOffset(0, 380) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		strip.Visible = false
		for i, s in slots do
			local dx = (i - 3) * 80
			tween(s, 0.32, { Position = UDim2.fromOffset(640 + dx, 320 + math.abs(i - 3) * 14), Rotation = (i - 3) * 8 }, Enum.EasingStyle.Back)
			tween(s.Scale, 0.32, { Scale = 0.72 }, Enum.EasingStyle.Back)
		end
		task.wait(0.4)
		if self._token ~= token then
			return
		end
		pack.Visible = false
		-- shuffle: two quick swaps, then gather into the stack
		page.Hint.Text = "Shuffling…"
		page.Hint.Visible = true
		for round = 1, 2 do
			Sounds.Play("CardsFan", { Pitch = 1 + (round - 1) * 0.08 })
			for i, s in slots do
				local dx = (if (i + round) % 2 == 0 then -1 else 1) * (40 + i * 6)
				tween(s, 0.16, { Position = UDim2.fromOffset(640 + dx, 310), Rotation = dx / 8 })
			end
			task.wait(0.18)
		end
		for _, s in slots do
			tween(s, 0.18, { Position = UDim2.fromOffset(640, 300), Rotation = 0 })
			tween(s.Scale, 0.18, { Scale = 1 })
		end
		task.wait(0.2)
		if self._token ~= token then
			return
		end
		fan.Visible = false
		page.Hint.Visible = false
		self:_nextBack()
	end)
end

-- 18 · the next card, face down. From Lucky Draw up, the back hints at its rarity (Reveal);
-- a One of One plays its whole build-up and flips by itself, and nothing skips it.
function AlbumsController:_nextBack()
	local p = self._pull
	p.Index += 1
	self:_subLine()
	self:_spinRays(false)
	local page = self._frame.Pull
	self._reveal:Reset(page.Holder)
	page.Rarity.Visible = false
	-- a new pack (×5 / ×10): its own tray
	if p.Size > 1 and (p.Index - 1) % p.Size == 0 then
		for _, child in page.Tray:GetChildren() do
			if child:IsA("Frame") and child.Name ~= "Template" then
				child:Destroy()
			end
		end
	end
	local pull = p.Pulls[p.Index]
	local info = Albums.Card(pull.Card)
	local holder = page.Holder
	holder.Visible = true
	holder.Position = HOLDER_AT
	holder.Rotation = 0
	holder.Size = UDim2.fromOffset(260, 380)
	holder.Scale.Scale = 1
	holder.Back.Visible = true
	holder.Face.Visible = true
	fillFace(holder.Face, pull.Card, pull.Copies, pull.New, pull.Serial)
	holder.Face.New.Visible = false -- (it pokes out over the back; it pops in after the flip)
	CardDecor.ShowEdges(holder.Face, holder.Face.Card, false) -- (the stars, glow and ribbon too)
	-- (the binder page tag waits for the flip: it would give the group away)
	page.Page.Visible = false
	page.Hint.Visible = true
	page.Hint.Text = if p.Count > 1 then "Tap to flip · hold to go fast" else "Tap to flip"
	p.Last = p.Size > 1 and p.Index % p.Size == 0
	p.Phase = "Back"
	-- (duplicates get the reveal too)
	local key = if info and info.Rarity.Announce == true then info.Rarity.Key else nil
	p.Rare = key ~= nil
	p.RareKey = key
	page.Skip.Visible = true
	if key == "oneofone" then
		p.Locked = true
		page.Skip.Visible = false
		page.Hint.Visible = false
		local index = p.Index
		self._reveal:Hint(key, holder, function()
			if self._pull == p and p.Index == index and p.Phase == "Back" then
				self:_flip()
			end
		end)
	elseif key then
		self._reveal:Hint(key, holder)
	end
end

-- flip the card over, then the rare moment if it is one
function AlbumsController:_flip()
	local p = self._pull
	p.Phase = "Busy"
	self._token += 1
	local token = self._token
	local page = self._frame.Pull
	local holder = page.Holder
	local pull = p.Pulls[p.Index]
	local info = Albums.Card(pull.Card)
	-- the Polaroid's flash and the One of One's burst move the card themselves
	if p.RareKey and self._reveal:Flip(p.RareKey, holder, function()
		if self._token == token then
			self:_landFace(info, pull)
		end
	end) then
		return
	end
	task.spawn(function()
		holder.Rotation = 0
		-- clip both sides while the card is squashed, so the seal, dots and labels squeeze
		-- away with it instead of poking out past the edges
		holder.Back.ClipsDescendants = true
		holder.Face.Card.ClipsDescendants = true
		Sounds.Play("CardFlip")
		tween(holder, 0.13, { Size = UDim2.fromOffset(0, 380) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		if self._token ~= token then
			return
		end
		holder.Back.Visible = false
		tween(holder, 0.17, { Size = UDim2.fromOffset(260, 380) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out).Completed:Wait()
		if self._token ~= token then
			return
		end
		self:_landFace(info, pull)
	end)
end

function AlbumsController:_landFace(info, pull)
	local p = self._pull
	local page = self._frame.Pull
	page.Holder.Back.Visible = false
	page.Holder.Size = UDim2.fromOffset(260, 380)
	CardDecor.ShowEdges(page.Holder.Face, page.Holder.Face.Card, true)
	page.Holder.Back.ClipsDescendants = false
	page.Holder.Face.Card.ClipsDescendants = false
	-- the binder page this card belongs to (only now that it's face up)
	if info then
		local album = info.Album
		local have = albumOwned(album, cards())
		local tag = page.Page
		tag.Visible = true
		tag.Swatch.BackgroundColor3 = hex(album.Colour, "FF9EC4")
		tag.Album.Text = album.Name
		tag.Line.Text = `{album.Artist} · binder page`
		tag.Count.Text = `{have} / {#album.Members}`
		tag.Track.Fill.Size = UDim2.fromScale(have / math.max(#album.Members, 1), 1)
		Juice.Pop(tag, 0.15)
	end
	if p.Rare and info then
		-- the rarity's own reveal (Reveal): Lucky Draw's rays and coins, the Fansign's hearts
		-- and scribble, the Polaroid developing, the One of One's gold title and dust
		local key = info.Rarity.Key
		if key == "luckydraw" then
			self:_spinRays(true)
			page.Flash.BackgroundTransparency = 0.3
			tween(page.Flash, 0.45, { BackgroundTransparency = 1 })
		end
		local hold = self._reveal:Land(key, page.Holder, function(colours)
			self:_confetti(colours)
		end, function(text, foil, rotation)
			local rarity = page.Rarity
			rarity.Text = text
			rarity.Rotation = rotation
			rarity.Position = UDim2.fromOffset(640, 38) -- (up clear of the level stars)
			rarity.Foil.Enabled = foil ~= nil
			if foil then
				rarity.Foil.Color = foil
			end
			rarity.BackgroundColor3 = if foil then WHITE else CREAM
			rarity.Visible = true
			Juice.Pop(rarity, 0.35)
		end)
		Juice.Pop(page.Holder, 0.12)
		if p.Locked then
			-- (a One of One: taps wait until its reveal has played)
			local index = p.Index
			task.delay(hold, function()
				if self._pull == p and p.Index == index then
					p.Locked = false
					page.Skip.Visible = true
					page.Hint.Visible = true
				end
			end)
		end
	elseif pull.LevelUp then
		Juice.Pop(page.Holder, 0.08)
		Sounds.Play("Success")
	else
		Sounds.Play("CardPop")
	end
	-- a pack's last card is its best one, and says so
	if p.Last and not p.Rare then
		local rarity = page.Rarity
		rarity.Text = "LAST CARD · THE BEST ONE"
		rarity.Rotation = -2
		rarity.Position = UDim2.fromOffset(640, 38)
		rarity.Foil.Enabled = false
		rarity.BackgroundColor3 = C("A7E9B8")
		rarity.Visible = true
		Juice.Pop(rarity, 0.25)
	end
	page.Holder.Face.New.Visible = pull.New == true
	if pull.New then
		Juice.Pop(page.Holder.Face.New, 0.3)
	end
	page.Hint.Text = if p.Index >= p.Count then "Tap to finish" elseif p.Last then "Tap for the next pack · hold to go fast" else "Tap for the next card · hold to go fast"
	p.Phase = "Face"
end

-- the face-up card drops into the tray; then the next back, or the summary
function AlbumsController:_toTray()
	local p = self._pull
	local page = self._frame.Pull
	self._reveal:Reset(page.Holder)
	local pull = p.Pulls[p.Index]
	local tray = page.Tray
	tray.Visible = p.Count > 1
	if p.Count > 1 then
		local mini = tray.Template:Clone()
		mini.Name = "Card" .. p.Index
		mini.LayoutOrder = p.Index
		mini.Visible = true
		fillFace(mini.Face, pull.Card, pull.Copies, false, pull.Serial)
		mini.Parent = tray
		Juice.Pop(mini, 0.2)
		local left = if p.Size > 1 then (p.Size - (p.Index - 1) % p.Size - 1) else p.Count - p.Index
		tray.Left.Visible = left > 0
		tray.Left.Text = `+{left}`
	end
	if p.Index >= p.Count then
		self:_showSummary()
	else
		self:_nextBack()
	end
end

-- a tap (or a held step) on the stage
function AlbumsController:_advance()
	local p = self._pull
	if not p or p.Locked then
		return
	end
	if p.Phase == "Pack" then
		self:_openPack()
	elseif p.Phase == "Back" then
		self:_flip()
	elseif p.Phase == "Face" then
		Sounds.Play("CardSleeve")
		self:_toTray()
	end
end

-- 20 · the summary: the cards in an arc, Sell under each, Done / Pull again
-- Skip: straight to the summary, but never past a One of One still to come (its reveal
-- can't be skipped): jump to it instead, and Skip again after it to finish
function AlbumsController:_skip()
	local p = self._pull
	if not p or p.Locked then
		return
	end
	local from = if p.Phase == "Back" then p.Index else p.Index + 1
	for i = math.max(from, 1), p.Count do
		local pull = p.Pulls[i]
		if pull and pull.Rarity == "oneofone" and not (p.SeenOne and p.SeenOne[i]) then
			p.SeenOne = p.SeenOne or {}
			p.SeenOne[i] = true
			self._token += 1
			self._frame.Pull.Fan.Visible = false
			self._frame.Pull.Pack.Visible = false
			p.Index = i - 1
			self:_nextBack()
			return
		end
	end
	self:_showSummary()
end

function AlbumsController:_showSummary()
	local p = self._pull
	self._token += 1
	self._reveal:Reset(self._frame.Pull.Holder)
	p.Phase = "Summary"
	self:_subLine()
	local page = self._frame.Pull
	for _, n in { "Pack", "Strip", "Fan", "Holder", "Rarity", "Page", "Tray" } do
		page[n].Visible = false
	end
	self:_spinRays(false)
	page.Hint.Visible = false
	page.Skip.Visible = false
	local summary = page.Summary
	summary.Visible = true

	-- best card, chips
	local best, bestScore, fresh = nil, -1, 0
	for _, pull in p.Pulls do
		local score = Albums.RarityRank(pull.Rarity) * 10 + (Albums.LEVEL_RANK[pull.Level or "Normal"] or 0)
		if score > bestScore then
			best, bestScore = pull, score
		end
		fresh += if pull.New then 1 else 0
	end
	local bestInfo = best and Albums.Card(best.Card)
	summary.Best.Text = if bestInfo then `Best card: {bestInfo.Member.Name} · {bestInfo.Rarity.Name}` else "Pack opened"
	local chips = summary.Chips
	chips.Chip1.Text = if fresh == 1 then "1 new card" else `{fresh} new cards`
	local album = bestInfo and bestInfo.Album
	chips.Chip2.Visible = album ~= nil
	if album then
		chips.Chip2.Text = `{album.Name} {albumOwned(album, cards())} / {#album.Members}`
	end
	local lv = Upgrades.Levels(PlayerData)
	local rate = Albums.Rate(cards(), bias(), PlayerData.Inventory.Pins.Get(), Albums.Boost(PlayerData.GamePasses, lv), lv)
	-- (Albums.Rate is coins an hour)
	chips.Chip3.Text = `Pins earn: {if rate % 1 == 0 then fmt(rate) else string.format("%.1f", rate)} coins an hour`
	if #p.Pulls > 10 then
		chips.Chip1.Text ..= ` · {#p.Pulls} cards`
	end

	-- the cards
	local box = summary.Cards
	for _, child in box:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
	-- up to ten cards: all of them, or the best ten of a big open (the rest are in the binder)
	local show = {}
	for i in p.Pulls do
		table.insert(show, i)
	end
	if #show > 10 then
		table.sort(show, function(a, b)
			local ra, rb = Albums.RarityRank(p.Pulls[a].Rarity), Albums.RarityRank(p.Pulls[b].Rarity)
			if ra ~= rb then
				return ra > rb
			end
			if p.Pulls[a].New ~= p.Pulls[b].New then
				return p.Pulls[a].New == true
			end
			return a < b
		end)
		show = { table.unpack(show, 1, 10) }
		table.sort(show)
	end
	local more = #p.Pulls - #show
	local n = #show
	local scale = if n > 5 then 0.66 else 1
	local spacing = if n > 5 then 112 else 168
	for slotIndex, i in show do
		local pull = p.Pulls[i]
		local slot = box.Template:Clone()
		slot.Name = "Card" .. i
		slot.Visible = true
		slot.Scale.Scale = scale
		local off = slotIndex - (n + 1) / 2
		local w = 150 * scale
		slot.Position = UDim2.fromOffset(600 + off * spacing - w / 2, math.abs(off) * (if n > 5 then 6 else 14))
		slot.Rotation = off * (if n > 5 then 2.5 else 5)
		fillFace(slot.Card.Face, pull.Card, pull.Copies, pull.New, pull.Serial)
		local info = Albums.Card(pull.Card)
		local price = Albums.SellPrice(pull.Card)
		local isBias = info ~= nil and Albums.IsBias(info.Album, info.Member.Key, bias())
		local canSell = price ~= nil and not pull.Sold and not p.Sold[i]
		slot.Sell.Visible = canSell
		slot.Sell.Text = if canSell then `Sell {fmt(price :: number)}` else ""
		slot.Kept.Visible = not canSell
		slot.Kept.Text = if pull.Sold then `maxed · sold +{fmt(pull.Sold)}` elseif p.Sold[i] then "sold" elseif isBias then "your bias" else ""
		slot.Parent = box
		slot.Sell.Activated:Connect(function()
			self:_sellAt(i)
		end)
		task.delay(0.04 * slotIndex, function()
			Juice.Pop(slot.Card, 0.15)
		end)
	end
	self:_sellAllLine()
	if more > 0 then
		summary.SellAll.Text ..= ` · +{more} more in your binder`
	end

	-- buttons: Open again (same pack, same count) when it's a paid pack or there are free ones left
	local last = self._last
	local again = last ~= nil and p.How ~= "First"
	if again and p.Kind == "Free" then
		local packs = freePacks()
		again = packs > 0 or Currencies.Count(player, "Tickets") > 0
		if again then
			setButtonRow(summary.Again, if packs > 0 then `OPEN NEXT ({packs} LEFT)` else "OPEN WITH A TICKET", nil)
		end
	elseif again and p.How == "Owned" then
		local left = Currencies.Count(player, "GenPacks")
		again = left > 0
		if again then
			setButtonRow(summary.Again, `OPEN NEXT ({left} LEFT)`, nil)
		end
	elseif again then
		local x = if p.Packs > 1 then ` ×{p.Packs}` else ""
		setButtonRow(summary.Again, "OPEN AGAIN" .. x, fmt(packPrice(p.Kind, p.Pack) * p.Packs), Currencies.Coins.Icon)
	end
	showWithShadow(summary, "Again", again)
	summary.Done.Position = if again then UDim2.fromOffset(610, 628) else UDim2.fromOffset(720, 628)
	summary.DoneShadow.Position = summary.Done.Position + UDim2.fromOffset(4, 4)
	Sounds.Play("PullResults")
	local complete = p.Complete
	if type(complete) == "table" and #complete > 0 then
		local done = Albums.Get(complete[1])
		local bonus = tonumber(p.SetBonus) or 0
		self:_toast(`{done and done.Name or "Album"} complete!` .. (if bonus > 0 then ` +{fmt(bonus)} coins` else ""))
	end
end

-- duplicates that can still be sold (not new, not sold, sellable, not your bias's last copy)
function AlbumsController:_duplicates(): { number }
	local p = self._pull
	local out = {}
	if not p then
		return out
	end
	for i, pull in p.Pulls do
		if not pull.New and not pull.Sold and not p.Sold[i] and Albums.SellPrice(pull.Card) then
			table.insert(out, i)
		end
	end
	return out
end

function AlbumsController:_sellAllLine()
	local summary = self._frame.Pull.Summary
	local total = 0
	for _, i in self:_duplicates() do
		total += Albums.SellPrice(self._pull.Pulls[i].Card) or 0
	end
	summary.SellAll.Text = if total > 0 then `Sell all duplicates · +{fmt(total)}` else "Nothing new to sell"
	summary.SellAllButton.Visible = total > 0
end

function AlbumsController:_sellAt(i: number, confirm: boolean?)
	local p = self._pull
	if not p or p.Selling then
		return
	end
	local pull = p.Pulls[i]
	if not pull or p.Sold[i] then
		return
	end
	p.Selling = i
	Sounds.Play("Click")
	BinderRemote:Fire({ Action = "Sell", Card = pull.Card, Where = "Reveal", Confirm = confirm or p.ConfirmAt == i or nil })
end

function AlbumsController:_sellAll()
	local p = self._pull
	if not p or p.Selling then
		return
	end
	p.Queue = self:_duplicates()
	local first = table.remove(p.Queue, 1)
	if first then
		self:_sellAt(first)
	end
end

-- -------------------------------- Remotes --------------------------------- --

function AlbumsController:_onOpened(packet)
	self._waiting = false
	if packet.Ok then
		self:_startPull(packet)
		return
	end
	Sounds.Play("Wrong")
	if packet.Short then
		ShortOffer.Open(packet.Short)
	else
		self:_toast(packet.Text)
	end
end

function AlbumsController:_onBinder(packet)
	if packet.Action ~= "Sell" then
		return
	end
	local p = self._pull
	local i = p and p.Selling
	if p then
		p.Selling = nil
	end
	if not p or not i then
		return
	end
	local slot = self._frame.Pull.Summary.Cards:FindFirstChild("Card" .. i)
	if packet.Confirm then
		-- the last copy of your bias's card: ask once more
		p.ConfirmAt = i
		p.Queue = nil
		if slot then
			slot.Sell.Text = "Tap again to sell"
			Juice.Shake(slot.Sell)
		end
		self:_toast("That's your last copy of your bias's card")
		return
	end
	if not packet.Ok then
		Sounds.Play("Wrong")
		p.Queue = nil
		self:_toast(packet.Text)
		return
	end
	Sounds.Play("Coins", { Volume = 0.4 })
	p.Sold[i] = true
	p.ConfirmAt = nil
	if slot then
		slot.Sell.Visible = false
		slot.Kept.Visible = true
		slot.Kept.Text = `sold +{fmt(packet.Coins or 0)}`
		tween(slot.Card.Face.Card, 0.2, { BackgroundTransparency = 0.4 })
	end
	self:_balance()
	self:_sellAllLine()
	local nextI = p.Queue and table.remove(p.Queue, 1)
	if nextI then
		self:_sellAt(nextI)
	end
end

function AlbumsController:_onBias(packet)
	self._waiting = false
	if not packet.Ok then
		Sounds.Play("Wrong")
		self:_toast(packet.Text)
		self:_fillBias()
		return
	end
	Sounds.Play("Success")
	self:_afterBias()
end

-- -------------------------------- Lifecycle ------------------------------- --

function AlbumsController:_endPull()
	local p = self._pull
	self._pull = nil
	self._token += 1
	self:_hideStage()
	if p and p.How == "First" and self._opts.First then
		self._interface:Close(self.Name)
		return
	end
	self._frame.Shop.OddsSheet.Visible = false
	self:_showPage("Shop")
	self:_fillShop()
end

function AlbumsController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Albums")
	self._frame.Visible = false
	local f = self._frame
	self._reveal = Reveal.new(f.Pull) -- the rare reveals (Lucky Draw and up)
	local j = self._janitor
	-- (not the whole Pull page: its tap catcher covers the screen)
	for _, page in { f.Bias, f.Shop, f.Pull.Summary } do
		ButtonScale.ApplyToDescendants(page)
	end
	ButtonScale.Apply(f.Pull.Skip)

	-- bias
	j:Add(f.Bias.Close.Activated:Connect(function()
		-- opened from the Packs page's Bias button: back to the packs, not out
		if self._biasFromShop then
			self._biasFromShop = false
			self:_showPage("Shop")
			self:_fillShop()
			return
		end
		self._interface:Close(self.Name)
	end))
	local biasButton = f.Shop.Controls:FindFirstChild("Bias")
	if biasButton then
		j:Add(biasButton.Activated:Connect(function()
			Sounds.Play("Click")
			self._biasFromShop = true
			self._group, self._pick = nil, nil
			self:_showPage("Bias")
			self:_fillBias()
		end))
	end
	j:Add(f.Bias.Confirm.Activated:Connect(function()
		self:_confirmBias()
	end))
	for _, b in f.Bias.Groups.Filters:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				if self._biasFilter ~= b.Name then
					Sounds.Play("Click")
					self._biasFilter = b.Name
					self:_fillBias()
				end
			end))
		end
	end
	j:Add(f.Bias.Groups.Search.Box:GetPropertyChangedSignal("Text"):Connect(function()
		self._biasSearch = f.Bias.Groups.Search.Box.Text
		if self._frame.Visible and self._page == "Bias" then
			self:_fillBias()
		end
	end))

	-- the Packs page
	local shopPage = f.Shop
	j:Add(shopPage.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, b in shopPage.Controls.Counts:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				Sounds.Play("Click")
				self._count = tonumber(string.sub(b.Name, 2)) or 1
				self:_fillShop()
			end))
		end
	end
	local free = shopPage.Main.Free
	for _, b in free.Gens:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				Sounds.Play("Click")
				self._freeGen = b.Name
				self:_fillFree()
			end))
		end
	end
	j:Add(free.Open.Activated:Connect(function()
		self:_open("Free", 1, self._freeGen)
	end))
	j:Add(free.OpenAll.Activated:Connect(function()
		self:_open("Free", "All", self._freeGen)
	end))
	for _, key in GEN_KEYS do
		local tile = shopPage.Main.GenPacks:FindFirstChild(key)
		if tile then
			j:Add(tile.Buy.Activated:Connect(function()
				self:_open("Gen", self._count, key)
			end))
			self:_hookOdds(tile.Odds, "Gen", key)
		end
	end
	for _, pack in AlbumConstants.PREMIUM_PACKS do
		local card = shopPage.Side.Premium:FindFirstChild(pack.Key)
		if card then
			j:Add(card.Buy.Activated:Connect(function()
				self:_open("Premium", self._count, pack.Key)
			end))
			j:Add(card.Robux.Activated:Connect(function()
				if pack.ProductId ~= 0 then
					Sounds.Play("Click")
					MarketplaceService:PromptProductPurchase(player, pack.ProductId)
				end
			end))
			self:_hookOdds(card.Odds, "Premium", pack.Key)
		end
	end
	j:Add(shopPage.Side.Unopened.Tickets.Open.Activated:Connect(function()
		self:_open("Ticket", 1)
	end))
	local genRow = shopPage.Side.Unopened:FindFirstChild("GenPacks")
	if genRow then
		j:Add(genRow.Open.Activated:Connect(function()
			self:_open("Owned", 1)
		end))
	end
	for _, field in { PlayerData.Inventory.FavGroups, PlayerData.Inventory.PremiumPity } do
		j:Add(field.Observe(function()
			if self.State == "Active" and self._page == "Shop" then
				self:_fillShop()
			end
		end))
	end
	self:_hookOdds(free.Odds, "Free", function()
		return self._freeGen
	end)
	local sheet = shopPage.OddsSheet
	j:Add(shopPage.Controls.Odds.Activated:Connect(function()
		Sounds.Play("Click")
		sheet.Visible = true
		self:_fillOdds()
		Juice.Pop(sheet.Panel, 0.06)
	end))
	for _, b in { sheet.Dim, sheet.Panel.Close } do
		j:Add(b.Activated:Connect(function()
			Sounds.Play("Click")
			sheet.Visible = false
		end))
	end
	-- the free-pack clock
	local tick = 0
	j:Add(RunService.Heartbeat:Connect(function(dt)
		tick += dt
		if tick >= 1 then
			tick = 0
			if self.State == "Active" and self._page == "Shop" then
				self:_fillFree()
				self:_fillRotation()
			end
		end
	end))
	j:Add(PlayerData.Inventory.FreePacks.Observe(function()
		if self.State == "Active" and self._page == "Shop" then
			self:_fillShop()
		end
	end))

	-- the stage: tap to advance, hold to go fast, Skip to the summary
	local pull = f.Pull
	j:Add(pull.Tap.MouseButton1Down:Connect(function()
		self._holding = true
		local token = (self._holdToken or 0) + 1
		self._holdToken = token
		self:_advance()
		task.delay(0.45, function()
			while self._holding and self._holdToken == token and self._pull and self._pull.Phase ~= "Summary" and self._pull.Phase ~= "Pack" do
				self:_advance()
				task.wait(HOLD_STEP)
			end
		end)
	end))
	j:Add(pull.Tap.MouseButton1Up:Connect(function()
		self._holding = false
	end))
	j:Add(pull.Tap.MouseLeave:Connect(function()
		self._holding = false
	end))
	j:Add(pull.Skip.Activated:Connect(function()
		if self._pull and self._pull.Phase ~= "Summary" then
			Sounds.Play("Click")
			self:_skip()
		end
	end))
	local summary = pull.Summary
	j:Add(summary.Done.Activated:Connect(function()
		Sounds.Play("Click")
		self:_endPull()
	end))
	j:Add(summary.Again.Activated:Connect(function()
		local p = self._pull
		if not p then
			return
		end
		local last = self._last
		self:_endPull()
		if last then
			-- (Open all becomes one at a time once it's gone through the bank)
			self:_open(last.Kind, if last.Kind == "Free" then 1 else last.Count, last.Target)
		end
	end))
	j:Add(summary.SellAllButton.Activated:Connect(function()
		self:_sellAll()
	end))

	j:Add(AlbumRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Opened" then
			self:_onOpened(packet)
		elseif type(packet) == "table" and packet.Message == "Starred" and not packet.Ok then
			Sounds.Play("Wrong")
			self:_toast(packet.Text)
		end
	end), "Disconnect")
	j:Add(BinderRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Binder" then
			self:_onBinder(packet)
		end
	end), "Disconnect")
	j:Add(BiasRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Bias" then
			self:_onBias(packet)
		end
	end), "Disconnect")

	j:Add(PlayerData.Currencies.Won.Observe(function()
		if self.State == "Active" then
			self:_balance()
		end
	end))
	j:Add(player:GetAttributeChangedSignal(Currencies.Tickets.Attribute):Connect(function()
		if self.State == "Active" then
			self:_balance()
		end
	end))
	j:Add(player:GetAttributeChangedSignal(Currencies.GenPacks.Attribute):Connect(function()
		if self.State == "Active" and self._page == "Shop" and not self._pull then
			self:_fillShop()
		end
	end))

	-- Studio only: the LocalPlayer's "AlbumsTest" attribute ("Bias", "Shop" or "First") opens a page
	if RunService:IsStudio() then
		j:Add(player:GetAttributeChangedSignal("AlbumsTest"):Connect(function()
			local page = player:GetAttribute("AlbumsTest")
			if type(page) == "string" and page ~= "" then
				self._interface:Open(self.Name, if page == "First" then { First = true } else { Page = page })
			end
		end))
		-- "RevealTest" = "luckydraw" | "fansign" | "polaroid" | "oneofone": a pretend 5-card pack
		-- (shown here only, nothing is saved) whose 2nd and last cards are that rarity
		j:Add(player:GetAttributeChangedSignal("RevealTest"):Connect(function()
			local key = player:GetAttribute("RevealTest")
			local album = Albums.Get("aespa-armageddon") or Albums.All()[1]
			if type(key) ~= "string" or key == "" or not album then
				return
			end
			local pulls = {}
			for i = 1, 5 do
				local member = album.Members[(i - 1) % #album.Members + 1]
				local rarity = if i == 2 or i == 5 then key else "standard"
				table.insert(pulls, { Card = Albums.CardId(album.Id, member.Key, rarity), Album = album.Id, Artist = album.Artist, Member = member.Name, Rarity = rarity, New = i == 5, Copies = 1, Level = "Normal", Serial = if rarity ~= "standard" and rarity ~= "luckydraw" then 7 else nil })
			end
			self._interface:Open(self.Name, { Page = "Shop" })
			task.wait(0.6)
			self:_startPull({ Pulls = pulls, Kind = "Group", Group = album.Artist, How = "Coins", Packs = 1, Size = 5 })
		end))
	end
end

function AlbumsController:Activate(opts: any?)
	self._opts = if type(opts) == "table" then opts else {}
	self._waiting = false
	self._pull = nil
	self._token += 1
	self:_hideStage()
	self._frame.Shop.OddsSheet.Visible = false
	self._frame.Shop.Main.CanvasPosition = Vector2.zero
	self._frame.Shop.Side.CanvasPosition = Vector2.zero
	self._frame.Shop.Popover.Visible = false
	if type(self._opts.Group) == "string" and Albums.Pullable(self._opts.Group) then
		self._shopGroup = self._opts.Group
	end
	self._group, self._pick = nil, nil
	self._biasFromShop = false
	if self._opts.Page == "Bias" or (self._opts.First and bias() == "") then
		self:_showPage("Bias")
		self:_fillBias()
	else
		self:_showPage("Shop")
		self:_fillShop()
		if self._opts.First then
			self:_startFirst()
		end
	end
	self._frame.Visible = true
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

-- Behind the loading screen (Interface.Start): build and lay out the default page once,
-- off-screen, so the first real open is instant. Leaves the screen closed.
function AlbumsController:Prewarm()
	local f = self._frame
	if f.Visible or self.State ~= "Inactive" then
		return
	end
	local home = f.Position
	f.Position = home + UDim2.fromOffset(20000, 0)
	f.Visible = true
	self._opts = {}
	self:_showPage("Shop")
	self:_fillShop()
	for _ = 1, 2 do
		RunService.RenderStepped:Wait()
	end
	if self.State == "Inactive" then
		f.Visible = false
	end
	f.Position = home
end

-- controller B: the odds sheet, then the pull (to its summary, then back to the shop)
function AlbumsController:PadBack(): boolean
	if self._frame.Shop.OddsSheet.Visible then
		self._frame.Shop.OddsSheet.Visible = false
		return true
	end
	if self._pull then
		if self._pull.Phase ~= "Summary" then
			self:_skip()
		else
			self:_endPull()
		end
		return true
	end
	return false
end

function AlbumsController:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	local onDone = self._opts.OnDone
	self._pull = nil
	self._token += 1
	self:_spinRays(false)
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
		if type(onDone) == "function" then
			task.spawn(onDone)
		end
	end)
end

function AlbumsController:Destroy()
	self._janitor:Destroy()
end

return AlbumsController
