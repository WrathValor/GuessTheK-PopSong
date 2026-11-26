--| BinderController
-- The K-POPPED! binder (Interface.Frames.Binder, built by ./Build), from design board "27 · Binder ·
-- full screen (one group a page)". Full screen over a dark backdrop:
--   Header   your totals (cards owned of every card in the game, groups, coins an hour), the
--            Binder / Songs tabs, coins, COLLECT (what the binder has earned, ticking up;
--            BinderRemote → Engine/BinderService) and close
--   Binder   the group list (search, All / Girls / Boys / Most done) and one group a page: the
--            album's header (owned of its cards, coins an hour, OPEN PACK, a tab per album), then
--            a row per member with a slot per rarity. An owned card shows its copies (×n), level,
--            stamp and serial; a missing one is "?"; the One of One slot says who owns it
--            (BinderRemote "Owners") or "Unclaimed".
--   Pins     only pinned cards earn binder coins (Inventory.Pins, Albums.PinSlots of them; design
--            boards "32 · Binder · pin 3 cards to earn", "33 · Card detail · PIN"). My pins sits
--            over the group list; pinned cards wear a yellow pin. Each album shows its one-time
--            set bonus (own every member).
--   Detail   tap a card (design board "29 · Card detail"): your serials, copies to the next
--            level, what it earns when pinned, Sell, PIN / UNPIN (with every slot used, PIN
--            opens the swap sheet: pick a pin to swap out), and the member's other rarities to
--            flip between. Grade and Trade are shown but say "coming soon".
--   All      every card you own, best first / by group / duplicates only
--   Songs    how well you know each song (design board "46 · Binder · Songs tab"; ./Songs): the
--            same group list (each group's % mastered), one group's songs or All songs, and the
--            Music panel (lobby music) in My pins' place
-- Under the tabs, the group column's switch: By group / All cards (Binder), By group / All songs
-- (Songs). Tapping a group always opens it By group, on the tab you're on.
-- A card counts once per id: an album has members × rarities cards (AlbumConstants.RARITIES).
-- Only groups and albums with card art are shown (Albums.PullArtists / PullAlbums): the same
-- ones packs can pull, so the binder never lists a page nobody can fill.
--
-- Interface:Open("Binder", opts):
--   opts.Group = artist   the group page to show (default: your bias's group, else your fullest)
--   opts.Album = album id the album on that page
--   opts.Tab = "All"      start on All cards
--   opts.Tab = "Songs"    start on the Songs tab (opts.Group: that group's songs)

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local CardDecor = require(ReplicatedStorage.Modules.UI.CardDecor)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local SongsTab = require(script.Songs)
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)

local BinderRemote = Bridgenet.ReferenceBridge("BinderRemote")

local fmt = ShopCatalog.Format
local C = Color3.fromHex
local player = Players.LocalPlayer

-- --------------------------------- Tables --------------------------------- --
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local GOLD = C("F2C94C")
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

-- how each rarity looks (the same ladder as the packs screen, design board "5 · Rarity ladder")
local STYLE = {
	standard = { Colour = WHITE },
	selca = { Colour = C("FFD2E5") },
	store = { Colour = MINT, Stamp = "STORE" },
	luckydraw = { Colour = WHITE, Foil = HOLO, Shine = true, Stamp = "LUCKY DRAW" },
	fansign = { Colour = WHITE, Foil = GLITTER, Shine = true, Stamp = "♡ FANSIGN" },
	polaroid = { Colour = CREAM, Signature = true },
	oneofone = { Colour = WHITE, Foil = RAINBOW, Shine = true },
}

local RARITIES = AlbumConstants.RARITIES
local ALL_LIMIT = 240 -- tiles on All cards (best first); more would be a lot of instances
local TILE_BATCH = 24 -- new All cards tiles made per frame
local OWNERS_RETRY = 30 -- seconds before asking for an album's One of One owners again

-- --------------------------------- Helpers -------------------------------- --
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

-- "38", "6.5"
local function rateText(n: number): string
	if n % 1 == 0 then
		return fmt(n)
	end
	return string.format("%.1f", n)
end

local function escape(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function serialOf(cardId: string): number?
	local field = PlayerData.Inventory.Serials[cardId]
	return Albums.Serials(field and field.Get())[1]
end

-- when the player first rolled a card (os.time), for the Polaroid date stamp
local function dateOf(cardId: string): number?
	local field = PlayerData.Inventory.CardDates[cardId]
	local at = field and field.Get()
	return if at and at > 0 then at else nil
end

-- (owned card ids, all card ids) of one album
local function albumCount(album, owned: { [string]: number }): (number, number)
	local have = 0
	for _, member in album.Members do
		for _, rarity in RARITIES do
			if (owned[Albums.CardId(album.Id, member.Key, rarity.Key)] or 0) > 0 then
				have += 1
			end
		end
	end
	return have, #album.Members * #RARITIES
end

local function groupCount(artist: string, owned: { [string]: number }): (number, number)
	local have, total = 0, 0
	for _, album in Albums.PullAlbums(artist) do
		local h, t = albumCount(album, owned)
		have += h
		total += t
	end
	return have, total
end

-- the pinned card ids, in slot order (Inventory.Pins)
local function pins(): { string }
	return Albums.Pins(PlayerData.Inventory.Pins.Get())
end

local function pinValue(): string
	return PlayerData.Inventory.Pins.Get() or ""
end

-- ×2 with the 2× Coins pass (Albums.Boost)
local function boost(): number
	return Albums.Boost(PlayerData.GamePasses)
end

-- a group's photo for its icons (its PackArt), "" if none
local function groupArt(artist: string): string
	for _, album in Albums.PullAlbums(artist) do
		if album.PackArt and album.PackArt ~= "" then
			return album.PackArt
		end
	end
	return ""
end

local function groupColour(artist: string): Color3
	local albums = Albums.PullAlbums(artist)
	return hex(albums[#albums] and albums[#albums].Colour, "B9A6FF")
end

local function dressIcon(icon: ImageLabel, artist: string)
	local art = groupArt(artist)
	icon.Image = art
	icon.BackgroundColor3 = groupColour(artist)
	icon.Initial.Visible = art == ""
	icon.Initial.Text = string.upper(string.sub(artist, 1, 1))
end

-- dresses a binder slot's small card (Build's slotCard)
local function fillSlot(card: Frame, cardId: string, copies: number, pinned: boolean?)
	local info = Albums.Card(cardId)
	if not info then
		card.Visible = false
		return
	end
	local style = STYLE[info.Rarity.Key] or STYLE.standard
	local face = card.Face
	face.BackgroundColor3 = style.Colour
	face.Foil.Enabled = style.Foil ~= nil
	if style.Foil then
		face.Foil.Color = style.Foil
	end
	local photo = face.Photo
	photo.BackgroundColor3 = hex(info.Album.Colour, "FFD2E5")
	photo.Art.Image = info.Member.Art or ""
	photo.Silhouette.Visible = (info.Member.Art or "") == ""
	photo.Shine.Visible = style.Shine == true
	photo.Stamp.Visible = style.Stamp ~= nil
	photo.Stamp.Text = style.Stamp or ""
	photo.Stamp.BackgroundColor3 = if info.Rarity.Key == "store" then MINT else CREAM
	local serial = Albums.SerialText(cardId, serialOf(cardId))
	photo.Serial.Visible = serial ~= nil
	photo.Serial.Text = serial or ""
	face.Member.Text = string.upper(info.Member.Name)
	local level = Albums.Level(copies) or "Normal"
	face.Level.Visible = level ~= "Normal"
	face.Level.Text = string.upper(level)
	face.Level.BackgroundColor3 = if level == "Gold" then GOLD else WHITE
	face.Level.Rainbow.Enabled = level == "Rainbow"
	card.Copies.Visible = copies > 1
	card.Copies.Text = `×{copies}`
	card.Pin.Visible = pinned == true
	CardDecor.Paint(card, face, cardId, copies, { Serial = serialOf(cardId), Date = dateOf(cardId) })
	card.Visible = true
end

-- dresses a full card face (Build's cardFace) for a card id
local function fillFace(face: Instance, cardId: string, copies: number)
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
	photo.Stamp.BackgroundColor3 = if rarity.Key == "store" then MINT else CREAM
	photo.Signature.Visible = style.Signature == true
	photo.Signature.Text = member.Name
	local serial = Albums.SerialText(cardId, serialOf(cardId))
	photo.Serial.Visible = serial ~= nil
	photo.Serial.Text = serial or ""
	card.Member.Text = member.Name
	card.Album.Text = `{album.Artist} · {album.Name}`
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
	CardDecor.Paint(face, card, cardId, copies, { Serial = serialOf(cardId), Date = dateOf(cardId) })
	return info
end

-- a pill / tab on or off
local function setPill(b: GuiButton, on: boolean, onColour: Color3?, onText: Color3?)
	b.BackgroundColor3 = if on then (onColour or CREAM) else CREAM
	b.BackgroundTransparency = if on then 0 else 0.9
	b.TextColor3 = if on then (onText or INK) else CREAM
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = if on then INK else CREAM
		s.Transparency = if on then 0 else 0.75
	end
end

-- ---------------------------------- Class --------------------------------- --
local BinderController = {}
BinderController.__index = BinderController

function BinderController.new()
	local self = setmetatable({}, BinderController)
	self.Name = "Binder"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Binder" -- "Binder" | "Songs"
	self._mode = "Group" -- the group column's switch: "Group" (one group) | "All" (All cards / All songs)
	self._songSort = "Stars" -- All songs: "Stars" | "Near" | "Name"
	self._songRows = { Group = {}, All = {} } -- pooled song rows (./Songs)
	self._songShown = {}
	self.DressIcon = dressIcon -- (for ./Songs)
	self._filter = "All" -- "All" | "Girl" | "Boy" | "Done"
	self._search = ""
	self._sort = "Best" -- All cards: "Best" | "Group" | "Dupes"
	self._group = nil -- the artist on the page
	self._album = 1 -- which of their albums
	self._shownAlbum = nil -- the album id the member rows were built for
	self._rows = {} -- member key → row (the page's member rows)
	-- built once and reused (making UI is the slow part: every new label also goes through FitText)
	self._groupRows = {} -- artist → group row
	self._rowPool = {} -- member rows, in order
	self._tiles = {} -- All cards tiles, in order
	self._stats = nil -- artist → { owned, total }, until the cards change
	self._allDirty = true -- All cards needs refilling
	self._allSort = nil -- the sort it was last filled with
	self._allToken = 0
	self._owners = {} -- album id → { [member key] = name }
	self._asked = {} -- album id → os.clock() of the last Owners request
	self._preview = nil -- the card id being previewed
	self._confirm = false -- the preview's next Sell confirms selling your bias's last copy
	self._selling = false
	self._collecting = false
	self._pinning = false -- a Pin / Unpin request is out
	self._token = 0
	return (self :: any) :: UITypes.Controller
end

function BinderController:_toast(message: string?)
	local toast = self._frame:FindFirstChild("Toast")
	if not toast or not message or message == "" then
		return
	end
	toast.Text = message
	toast.Visible = true
	Juice.SlideIn(toast, -24)
	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(2.2, function()
		if self._toastToken == token then
			toast.Visible = false
		end
	end)
end

-- [[ Header ]]

-- owned / total cards per group, cached until Inventory.Cards changes
function BinderController:_groupStats(): { [string]: { number } }
	if not self._stats then
		local owned = cards()
		local stats = {}
		for _, artist in Albums.PullArtists() do
			local have, total = groupCount(artist, owned)
			stats[artist] = { have, total }
		end
		self._stats = stats
	end
	return self._stats
end

-- stars earned / most stars per group (the Songs tab's list), cached until Mastery changes
function BinderController:_songStats(): { [string]: { number } }
	if self._songStatsCache then
		return self._songStatsCache
	end
	local map = PlayerData.Inventory.Mastery.Get() or {}
	local out = {}
	for _, artist in SongsTab.Artists() do
		local share = SongsTab.Percent(artist, map)
		local most = #SongsTab.Of(artist) * 3
		out[artist] = { math.floor(share * most + 0.5), most }
	end
	self._songStatsCache = out
	return out
end

function BinderController:_waiting(): number
	local owned = cards()
	local rate = Albums.Rate(owned, bias(), pinValue(), boost())
	local coins = Albums.Waiting(PlayerData.Rewards.BinderBank.Get() or 0, PlayerData.Rewards.BinderAt.Get() or os.time(), rate, os.time())
	return coins
end

function BinderController:_fillHeader()
	local f = self._frame
	local owned = cards()
	local have, total = 0, 0
	local artists = Albums.PullArtists()
	local stats = self:_groupStats()
	for _, artist in artists do
		have += stats[artist][1]
		total += stats[artist][2]
	end
	local rate = Albums.Rate(owned, bias(), pinValue(), boost())
	local pinned = math.min(#pins(), Albums.PinSlots())
	f.Sub.Text = `{fmt(have)} of {fmt(total)} cards · {#artists} groups · {pinned} pinned, earning {rateText(rate)} coins an hour`
	self:_fillPins()
	f.Coins.Amount.Text = fmt(PlayerData.Currencies.Won.Get() or 0)
	self:_fillCollect()
	for _, name in { "Binder", "Songs" } do
		setPill(f.Tabs[name], self._tab == name)
		f.Tabs[name].BackgroundTransparency = if self._tab == name then 0 else 1
	end
	local mode = f.Binder.Groups.Mode
	mode.All.Text = if self._tab == "Songs" then "All songs" else "All cards"
	for _, name in { "Group", "All" } do
		local on = self._mode == name
		local b = mode[name]
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then INK else CREAM
		b:FindFirstChildOfClass("UIStroke").Transparency = if on then 0 else 1
	end
end

function BinderController:_fillCollect()
	local coins = self:_waiting()
	local b = self._frame.Collect
	b.Row.Amount.Text = fmt(coins)
	b.BackgroundColor3 = if coins >= 1 then YELLOW else C("E9E2CF")
end

function BinderController:_collect()
	if self._collecting then
		return
	end
	if self:_waiting() < 1 then
		Sounds.Play("Wrong")
		Juice.Shake(self._frame.Collect)
		self:_toast("Nothing to collect yet. Your pinned cards earn coins every minute")
		return
	end
	self._collecting = true
	Sounds.Play("Click")
	BinderRemote:Fire({ Action = "Collect" })
end

-- [[ My pins ]]

function BinderController:_fillPins()
	local panel = self._frame.Binder.Groups.Pins
	local owned = cards()
	local b = bias()
	local list = pins()
	local slots = Albums.PinSlots()
	local used = 0
	for i = 1, AlbumConstants.PIN_SLOTS_MAX do
		local slot = panel.Slots:FindFirstChild("Slot" .. i)
		if not slot then
			continue
		end
		local id = list[i]
		local copies = id and owned[id] or 0
		local holder = slot.Holder
		local locked = i > slots
		if not locked and id and copies > 0 then
			used += 1
			fillSlot(holder.Card, id, copies, true)
			holder.Empty.Visible = false
			slot.Earn.Text = `+{rateText(Albums.EarnPerHour(id, copies, b) * boost())}/hr`
			slot.Tap:SetAttribute("Card", id)
		else
			holder.Card.Visible = false
			holder.Empty.Visible = true
			holder.Empty.Mark.Visible = not locked
			holder.Empty.Lock.Visible = locked
			slot.Earn.Text = if locked then "Locked" else ""
			slot.Tap:SetAttribute("Card", nil)
		end
	end
	panel.Title.Text = `MY PINS · {used}/{slots}`
	panel.Rate.Amount.Text = `{rateText(Albums.Rate(owned, b, pinValue(), boost()))} an hour`
end

-- [[ The group list ]]

function BinderController:_artists(): { string }
	local search = string.lower(self._search)
	local songsTab = self._tab == "Songs"
	local out, stats = {}, if songsTab then self:_songStats() else self:_groupStats()
	for _, artist in if songsTab then SongsTab.Artists() else Albums.PullArtists() do
		if self._filter == "Girl" or self._filter == "Boy" then
			if (if songsTab then SongsTab.GroupType(artist) else Albums.GroupType(artist)) ~= self._filter then
				continue
			end
		end
		if search ~= "" and not string.find(string.lower(artist), search, 1, true) then
			continue
		end
		table.insert(out, artist)
	end
	table.sort(out, function(a, b)
		local sa, sb = stats[a], stats[b]
		if self._filter == "Done" then
			local pa, pb = sa[1] / math.max(sa[2], 1), sb[1] / math.max(sb[2], 1)
			if pa ~= pb then
				return pa > pb
			end
		end
		if sa[1] ~= sb[1] then
			return sa[1] > sb[1]
		end
		return a:lower() < b:lower()
	end)
	return out, stats
end

function BinderController:_fillList()
	local side = self._frame.Binder.Groups
	local scroll = side.List
	for _, b in side.Filters:GetChildren() do
		if b:IsA("TextButton") then
			setPill(b, b.Name == self._filter)
		end
	end
	local artists, stats = self:_artists()
	local shown = {}
	local biasArtist = Albums.BiasParts(bias())
	for i, artist in artists do
		shown[artist] = true
		local row = self._groupRows[artist]
		if not row then
			-- first time this group is listed: make its row (kept for good)
			row = scroll.Template:Clone()
			row.Name = "Group"
			row:SetAttribute("Artist", artist)
			dressIcon(row.Button.Icon, artist)
			ButtonScale.Apply(row.Button)
			row.Button.Activated:Connect(function()
				if self:_shownGroup() ~= artist or self._mode ~= "Group" then
					Sounds.Play("Click")
					self:_pickGroup(artist)
				end
			end)
			row.Parent = scroll
			self._groupRows[artist] = row
		end
		row.LayoutOrder = i
		local on = artist == self:_shownGroup() and self._mode == "Group"
		local b = row.Button
		local albumCountN = #Albums.PullAlbums(artist)
		local label = escape(artist)
		if on and albumCountN > 1 and self._tab == "Binder" then
			label ..= ` · {albumCountN} albums`
		end
		if artist == biasArtist then
			label ..= ` <font color="#FF5A4E">♥</font>`
		end
		b.Label.Text = label
		b.Count.Text = if self._tab == "Songs"
			then `{math.floor(stats[artist][1] / math.max(stats[artist][2], 1) * 100 + 0.5)}%`
			else `{stats[artist][1]}/{stats[artist][2]}`
		b.Bar.Fill.Size = UDim2.fromScale(stats[artist][1] / math.max(stats[artist][2], 1), 1)
		row.Shadow.Visible = on
		b.BackgroundColor3 = if on then YELLOW else CREAM
		b.BackgroundTransparency = if on then 0 else 0.95
		local s = b:FindFirstChildOfClass("UIStroke")
		s.Color = if on then INK else CREAM
		s.Transparency = if on then 0 else 0.9
		s.Thickness = if on then 3 else 2
		b.Label.TextColor3 = if on then INK else CREAM
		b.Count.TextColor3 = if on then INK else CREAM
		b.Bar.BackgroundColor3 = if on then INK else CREAM
		b.Bar.BackgroundTransparency = if on then 0.85 else 0.88
		b.Bar.Fill.BackgroundColor3 = if on then INK else MINT
		row.Visible = true
	end
	for artist, row in self._groupRows do
		if not shown[artist] then
			row.Visible = false
		end
	end
	scroll.Empty.Visible = #artists == 0
end

function BinderController:_pickGroup(artist: string, albumId: string?)
	self._album = 1
	local albums = Albums.PullAlbums(artist)
	for i, album in albums do
		if album.Id == albumId then
			self._album = i
		end
	end
	if self._tab == "Songs" then
		self._songGroup = artist
	else
		self._group = artist
	end
	self._mode = "Group"
	self:_show()
end

-- the group shown on the tab you're on
function BinderController:_shownGroup(): string?
	return if self._tab == "Songs" then self._songGroup else self._group
end

-- the group to open on: your bias's group, else the one you have most of, else the first
function BinderController:_defaultGroup(): string?
	local biasArtist = Albums.BiasParts(bias())
	if biasArtist and #Albums.PullAlbums(biasArtist) > 0 then
		return biasArtist
	end
	local owned = cards()
	local best, bestHave = nil, -1
	for _, artist in Albums.PullArtists() do
		local have = groupCount(artist, owned)
		if have > bestHave then
			best, bestHave = artist, have
		end
	end
	return best
end

-- [[ The page ]]

function BinderController:_fillPage()
	local p = self._frame.Binder.Page
	local artist = self._group
	local albums = artist and Albums.PullAlbums(artist) or {}
	local album = albums[self._album] or albums[1]
	if not album then
		return
	end
	local owned = cards()
	local b = bias()

	-- the header band
	local head = p.Head
	local colour = hex(album.Colour, "FF9EC4")
	local tint = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colour),
		ColorSequenceKeypoint.new(0.6, colour:Lerp(WHITE, 0.55)),
		ColorSequenceKeypoint.new(1, CREAM),
	})
	head.Tint.Color = tint
	head.Square.Tint.Color = tint
	dressIcon(head.Icon, artist)
	local bits = { string.upper(artist) }
	if album.Year then
		table.insert(bits, tostring(album.Year))
	end
	local gen = Albums.Generation(artist)
	if gen and gen ~= "" then
		table.insert(bits, `{string.upper(gen)} GEN`)
	end
	if #albums > 1 then
		table.insert(bits, `ALBUM {table.find(albums, album)} OF {#albums}`)
	end
	head.Meta.Text = table.concat(bits, " · ")
	head.AlbumName.Text = string.upper(album.Name)
	local have, total = albumCount(album, owned)
	head.Progress.Count.Text = `{have} / {total} cards`
	-- the album's one-time set bonus (every member owned, any rarity: Engine/BinderService)
	head.Progress.Rate.Amount.Text = if Albums.Complete(owned, album) then "Set complete" else `+{fmt(Albums.SetBonus(album))} set bonus`
	head.Progress.Bar.Fill.Size = UDim2.fromScale(have / math.max(total, 1), 1)
	-- the group's cards ladder (Modules/Library/Ladders): its rung and what the next one needs
	local badge = head:FindFirstChild("Badge")
	if badge then
		badge.Visible = Ladders.Eligible(artist) -- (no ladders without enough songs)
	end
	if badge and badge.Visible then
		local rung, nextRung = Ladders.CardsRung(owned, artist)
		local saved = (PlayerData.Inventory.Ladders.Get() or {})[Ladders.Key("Cards", artist)] or 0
		rung = math.max(rung, saved)
		badge.Rung.Text = SongsTab.RungText(rung)
		local nextName = Ladders.RUNGS[rung + 1]
		badge.Next.Visible = nextRung ~= nil and nextName ~= nil
		if nextRung and nextName then
			local unit = if rung == 0 then "" else " members"
			badge.Next.Text = `{nextRung.Text} · {nextRung.Have}/{nextRung.Need}{unit}`
			badge.Next.BackgroundColor3 = Ladders.COLOURS[nextName]
		end
	end

	-- the album tabs
	local tabs = head.Albums
	for _, child in tabs:GetChildren() do
		if child:GetAttribute("Album") then
			child:Destroy()
		end
	end
	for i, a in albums do
		local tab = tabs.Template:Clone()
		tab.Name = "Album"
		tab:SetAttribute("Album", a.Id)
		tab.LayoutOrder = i
		local on = a == album
		local h, t = albumCount(a, owned)
		tab.BackgroundColor3 = if on then INK else CREAM
		tab.BackgroundTransparency = if on then 0 else 0.25
		tab.Label.Text = string.upper(a.Name)
		tab.Label.TextColor3 = if on then CREAM else INK
		tab.Year.Text = if a.Year then tostring(a.Year) else ""
		tab.Year.Visible = a.Year ~= nil
		tab.Year.TextColor3 = if on then CREAM else INK
		tab.Count.Text = `{h}/{t}`
		tab.Count.BackgroundTransparency = if h > 0 then 0 else 1
		tab.Count.TextTransparency = if h > 0 then 0 else 0.4
		tab.Count.TextColor3 = if h > 0 or not on then INK else CREAM
		tab.Activated:Connect(function()
			if self._album ~= i then
				Sounds.Play("Click")
				self._album = i
				self:_fillPage()
			end
		end)
		tab.Visible = true
		tab.Parent = tabs
	end

	-- the member rows: reused from a pool (a slot reads its card id from its "Card" attribute)
	local rows = p.Rows
	if self._shownAlbum ~= album.Id then
		self._shownAlbum = album.Id
		self._rows = {}
		for i, member in album.Members do
			local row = self._rowPool[i]
			if not row then
				row = rows.Template:Clone()
				row.Name = "Member"
				row.LayoutOrder = i
				for k = 1, #RARITIES do
					local slot = row:FindFirstChild("Slot" .. k)
					if slot then
						ButtonScale.Apply(slot)
						slot.Activated:Connect(function()
							local id = slot:GetAttribute("Card")
							if type(id) == "string" and (cards()[id] or 0) > 0 then
								Sounds.Play("Click")
								self:_showPreview(id)
							end
						end)
					end
				end
				row.Parent = rows
				self._rowPool[i] = row
			end
			for k, rarity in RARITIES do
				local slot = row:FindFirstChild("Slot" .. k)
				if slot then
					slot:SetAttribute("Card", Albums.CardId(album.Id, member.Key, rarity.Key))
				end
			end
			row.Visible = true
			self._rows[member.Key] = row
		end
		for i = #album.Members + 1, #self._rowPool do
			self._rowPool[i].Visible = false
		end
		rows.CanvasPosition = Vector2.zero
	end
	local biasArtist, biasMember = Albums.BiasParts(b)
	local owners = self._owners[album.Id]
	local pinnedSet = {}
	for _, id in pins() do
		pinnedSet[id] = true
	end
	for _, member in album.Members do
		local row = self._rows[member.Key]
		if not row then
			continue
		end
		local isBias = biasArtist == artist and biasMember == member.Key
		row.Member.Text = escape(string.upper(member.Name)) .. (if isBias then ` <font color="#FF5A4E" size="14">♥</font>` else "")
		row.Bias.Visible = isBias
		row.Bias.Text = `BIAS · {AlbumConstants.BIAS_PULL_WEIGHT}× PULLS`
		local mine = 0
		for k, rarity in RARITIES do
			local slot = row:FindFirstChild("Slot" .. k)
			if not slot then
				continue
			end
			local id = Albums.CardId(album.Id, member.Key, rarity.Key)
			local copies = owned[id] or 0
			local unique = slot:FindFirstChild("Unique")
			if copies > 0 then
				mine += 1
				fillSlot(slot.Card, id, copies, pinnedSet[id])
				slot.Empty.Visible = false
				if unique then
					unique.Visible = false
				end
			else
				slot.Card.Visible = false
				slot.Empty.Visible = unique == nil
				if unique then
					unique.Visible = true
					local name = owners and owners[member.Key]
					unique.Inner.Label.Text = if not owners then "…" elseif name then `Owned by\n<b>{escape(name)}</b>` else "Unclaimed"
				end
			end
		end
		row.Count.Text = `{mine} / {#RARITIES} cards`
	end
	self:_askOwners(album.Id)
end

function BinderController:_askOwners(albumId: string)
	local at = self._asked[albumId]
	if at and os.clock() - at < OWNERS_RETRY then
		return
	end
	self._asked[albumId] = os.clock()
	BinderRemote:Fire({ Action = "Owners", Album = albumId })
end

-- [[ All cards ]]

function BinderController:_fillAll()
	local all = self._frame.All
	local grid = all.Page.Grid
	for _, b in all.Page.Sorts:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == self._sort
			b.BackgroundColor3 = if on then INK else CREAM
			b.TextColor3 = if on then CREAM else INK
		end
	end
	-- nothing changed since the last fill: the grid is still right
	if not self._allDirty and self._allSort == self._sort then
		return
	end
	self._allDirty = false
	self._allSort = self._sort
	self._allToken += 1
	local token = self._allToken

	local owned = cards()
	local entries, total, dupes = {}, 0, 0
	for id, copies in owned do
		local info = copies > 0 and Albums.Card(id)
		if not info then
			continue
		end
		total += 1
		if copies > 1 then
			dupes += 1
		end
		if self._sort == "Dupes" and copies < 2 then
			continue
		end
		table.insert(entries, { Id = id, Copies = copies, Info = info, Rank = Albums.RarityRank(info.Rarity.Key) })
	end
	table.sort(entries, function(a, b)
		if self._sort == "Group" then
			if a.Info.Album.Artist ~= b.Info.Album.Artist then
				return a.Info.Album.Artist:lower() < b.Info.Album.Artist:lower()
			end
			if a.Info.Album.Id ~= b.Info.Album.Id then
				return a.Info.Album.Name < b.Info.Album.Name
			end
			if a.Info.Member.Name ~= b.Info.Member.Name then
				return a.Info.Member.Name < b.Info.Member.Name
			end
			return a.Rank > b.Rank
		elseif self._sort == "Dupes" and a.Copies ~= b.Copies then
			return a.Copies > b.Copies
		end
		if a.Rank ~= b.Rank then
			return a.Rank > b.Rank
		end
		if a.Copies ~= b.Copies then
			return a.Copies > b.Copies
		end
		return a.Id < b.Id
	end)
	local shown = math.min(#entries, ALL_LIMIT)
	local summary = `{fmt(total)} cards · {fmt(dupes)} with duplicates`
	if #entries > shown then
		summary ..= ` · showing the top {ALL_LIMIT}`
	end
	all.Page.Summary.Text = summary
	all.Page.Empty.Visible = shown == 0
	all.Page.Empty.Text = if total == 0 then "No cards yet. Open a pack to start your binder!" else "No duplicates right now"

	local function place(i: number)
		local e = entries[i]
		local tile = self._tiles[i]
		if not tile then
			tile = grid.Template:Clone()
			tile.Name = "Tile"
			tile.LayoutOrder = i
			tile.Activated:Connect(function()
				local id = tile:GetAttribute("Card")
				if type(id) == "string" then
					Sounds.Play("Click")
					self:_showPreview(id)
				end
			end)
			tile.Parent = grid
			self._tiles[i] = tile
		end
		tile:SetAttribute("Card", e.Id)
		fillFace(tile.Face, e.Id, e.Copies)
		tile.Copies.Visible = e.Copies > 1
		tile.Copies.Text = `×{e.Copies}`
		tile.Visible = true
	end
	for i = shown + 1, #self._tiles do
		self._tiles[i].Visible = false
	end
	-- tiles that already exist refill at once; new ones are made a batch a frame
	local ready = math.min(shown, #self._tiles)
	for i = 1, ready do
		place(i)
	end
	if shown > ready then
		task.spawn(function()
			for i = ready + 1, shown do
				if self._allToken ~= token then
					return
				end
				place(i)
				if (i - ready) % TILE_BATCH == 0 then
					task.wait()
				end
			end
		end)
	end
end

-- [[ Tabs ]]

-- Binder | Songs, then the group column's By group | All switch. The group column (the
-- Binder holder's Groups) stays; the page beside it is the group's page, All cards, one
-- group's songs or All songs.
function BinderController:_showTab(tab: string, mode: string?)
	self._tab = tab
	self._mode = mode or self._mode
	self:_show()
	local f = self._frame
	if tab == "Binder" and self._mode == "All" then
		f.All.Page.Grid.CanvasPosition = Vector2.zero
	elseif tab == "Songs" and self._mode == "All" then
		f.Songs.AllSongs.List.CanvasPosition = Vector2.zero
	end
end

function BinderController:_show()
	local f = self._frame
	local songs, group = self._tab == "Songs", self._mode == "Group"
	f.Binder.Page.Visible = not songs and group
	f.Binder.PageShadow.Visible = not songs and group
	f.All.Visible = not songs and not group
	f.Songs.Visible = songs
	f.Songs.Group.Visible = songs and group
	f.Songs.GroupShadow.Visible = songs and group
	f.Songs.AllSongs.Visible = songs and not group
	f.Songs.AllShadow.Visible = songs and not group
	local side = f.Binder.Groups
	side.Pins.Visible, side.PinsShadow.Visible = not songs, not songs
	side.Music.Visible, side.MusicShadow.Visible = songs, songs
	self:_fillHeader()
	self:_fillList()
	if songs then
		SongsTab.FillPanel(self)
		if group then
			self._songGroup = self._songGroup or self:_defaultSongGroup()
			SongsTab.FillGroup(self, self._songGroup)
		else
			SongsTab.FillAll(self)
		end
	elseif group then
		self:_fillPage()
	else
		self:_fillAll()
	end
end

-- the Songs tab opens on: the Binder's group if it has songs, else your best-known group
function BinderController:_defaultSongGroup(): string?
	if self._group and #SongsTab.Of(self._group) > 0 then
		return self._group
	end
	local stats, best, bestHave = self:_songStats(), nil, -1
	for _, artist in SongsTab.Artists() do
		if stats[artist][1] > bestHave then
			best, bestHave = artist, stats[artist][1]
		end
	end
	return best
end

-- everything on screen, after the cards changed
function BinderController:_refresh()
	if self.State ~= "Active" and self.State ~= "Activating" then
		return
	end
	self:_show()
	if self._preview then
		self:_fillPreview()
	end
end

-- [[ Card detail ]]

local RARITY_CHIP = {
	standard = WHITE,
	selca = C("FFD2E5"),
	store = MINT,
	polaroid = CREAM,
}

function BinderController:_showPreview(cardId: string)
	self._preview = cardId
	self._confirm = false
	self._frame.Detail.Window.Panel.Swap.Visible = false
	self:_fillPreview()
	local d = self._frame.Detail
	if not d.Visible then
		d.Visible = true
		Juice.Pop(d.Window.Panel, 0.04)
	end
end

function BinderController:_hidePreview()
	self._preview = nil
	self._confirm = false
	self._pinning = false
	self._frame.Detail.Window.Panel.Swap.Visible = false
	self._frame.Detail.Visible = false
end

function BinderController:_fillPreview()
	local id = self._preview
	local d = self._frame.Detail
	local owned = cards()
	local copies = id and owned[id] or 0
	local info = id and Albums.Card(id)
	if not info or copies < 1 then
		self:_hidePreview()
		return
	end
	local rarity, album, member = info.Rarity, info.Album, info.Member
	local panel = d.Window.Panel
	local b = bias()
	local isBias = Albums.IsBias(album, member.Key, b)
	fillFace(panel.Face, id, copies)
	panel.Copies.Visible = copies > 1
	panel.Copies.Text = `×{copies}`

	local col = panel.Info
	local style = STYLE[rarity.Key] or STYLE.standard
	col.Chips.Rarity.Text = string.upper(rarity.Name)
	col.Chips.Rarity.BackgroundColor3 = RARITY_CHIP[rarity.Key] or WHITE
	col.Chips.Rarity.Foil.Enabled = style.Foil ~= nil
	if style.Foil then
		col.Chips.Rarity.Foil.Color = style.Foil
	end
	local numbered = rarity.Serial == true
	col.Chips.Numbered.Visible = numbered
	col.Chips.Numbered.Text = if rarity.Key == "oneofone" then "1 OF 1" else "NUMBERED"
	col.Member.Text = escape(string.upper(member.Name)) .. (if isBias then ` <font color="#FF5A4E" size="22">♥</font>` else "")
	col.Album.Text = string.upper(`{album.Artist} · {album.Name}`) .. (if album.Year then ` · {album.Year}` else "")

	-- serials: your best number first and dark, the rest cream
	local serials = Albums.Serials(PlayerData.Inventory.Serials[id].Get())
	local pending = PlayerData.Inventory.SerialsPending[id].Get() or 0
	local value = col.Serials.Value
	for _, chip in value:GetChildren() do
		if chip:GetAttribute("Serial") then
			chip:Destroy()
		end
	end
	col.Serials.Visible = numbered
	local function addChip(order: number, label: string, best: boolean)
		local chip = value.Template:Clone()
		chip.Name = "Serial"
		chip:SetAttribute("Serial", true)
		chip.LayoutOrder = order
		chip.Text = label
		chip.BackgroundColor3 = if best then INK else CREAM
		chip.TextColor3 = if best then YELLOW else INK
		chip.Visible = true
		chip.Parent = value
	end
	if rarity.Key == "oneofone" then
		addChip(1, "1 OF 1", true)
	else
		for i, n in serials do
			if i > 5 then
				addChip(6, `+{#serials - 5}`, false)
				break
			end
			addChip(i, `#{n}`, i == 1)
		end
		if pending > 0 then
			addChip(7, if pending == 1 then "numbering…" else `{pending} numbering…`, false)
		end
	end

	-- copies and level
	local level = Albums.Level(copies) or "Normal"
	local goldAt, rainbowAt = AlbumConstants.GOLD_COPIES, AlbumConstants.RAINBOW_COPIES
	local target = if copies < goldAt then goldAt else rainbowAt
	col.Copies.Value.Amount.Text = if copies >= rainbowAt then `{copies} · max` else `{copies} of {target}`
	col.Copies.Value.Level.Text = string.upper(level)
	col.Copies.Value.Level.Visible = level ~= "Normal"
	col.Copies.Value.Level.BackgroundColor3 = if level == "Gold" then GOLD else WHITE
	col.Copies.Value.Level.Rainbow.Enabled = level == "Rainbow"
	local levels = col.Levels
	levels.Bar.Fill.Size = UDim2.fromScale(math.clamp(copies / rainbowAt, 0, 1), 1)
	levels.Gold.Text = `Gold · {goldAt}`
	levels.Rainbow.Text = if copies < rainbowAt then `Rainbow · {rainbowAt} ({rainbowAt - copies} more)` else `Rainbow · {rainbowAt}`

	-- earnings: the rarity's rate × level (× bias)
	local earn = Albums.EarnPerHour(id, copies, b)
	col.Earns.Value.Amount.Text = `{rateText(earn)} an hour`
	col.Earns.Title.Text = if table.find(pins(), id) then "Earning (pinned)" else "Earns when pinned"
	local why = {}
	if level ~= "Normal" then
		table.insert(why, `{level} {AlbumConstants.LEVEL_EARN[level]}`)
	end
	if isBias then
		table.insert(why, `bias {AlbumConstants.BIAS_EARN}`)
	end
	col.Earns.Value.Why.Visible = #why > 0
	col.Earns.Value.Why.Text = `({rateText(rarity.Earn)} × {table.concat(why, " × ")})`

	-- rolled: the day you first rolled it; a numbered copy asks the server for its history
	local at = PlayerData.Inventory.CardDates[id].Get() or 0
	col.Rolled.Value.Date.Text = if at > 0 then os.date("%d %b %Y", at) else "before dates were kept"
	col.Owners.Visible = numbered
	if numbered then
		col.Owners.Text = "Looking up its owners…"
		BinderRemote:Fire({ Action = "History", Card = id })
	end

	-- selling
	local price = Albums.SellPrice(id)
	local sell = col.Actions.Sell
	sell.Visible = price ~= nil
	col.Actions.SellShadow.Visible = price ~= nil
	if price then
		sell.Row.Label.Text = if self._confirm then "SURE? SELL" else "SELL 1"
		sell.Row.Amount.Text = fmt(price)
		sell.BackgroundColor3 = if self._confirm then C("FFD2D0") else WHITE
	end
	local sellNote
	if not price then
		sellNote = `A {rarity.Name} can't be sold. It's the only one in the game.`
	elseif not numbered then
		sellNote = if copies > 1 then `Selling gives up 1 of your {copies} copies.` else "Selling gives up your only copy."
	elseif pending > 0 then
		sellNote = "Selling gives up a copy that's still waiting for its number first."
	elseif #serials > 1 then
		sellNote = `Selling gives up #{serials[#serials]}, your highest number. You keep #{serials[1]}.`
	elseif #serials == 1 then
		sellNote = `Selling gives up #{serials[1]}.`
	end
	if price and isBias and copies == 1 then
		sellNote = (sellNote or "") .. " It's your last copy of your bias's card."
	end
	col.SellNote.Visible = sellNote ~= nil
	col.SellNote.Text = sellNote or ""
	local pinX = if price then 260 else 102
	col.Actions.Pin.Position = UDim2.fromOffset(pinX, 26)
	col.Actions.PinShadow.Position = UDim2.fromOffset(pinX + 4, 30)
	self:_fillPinButton(id)

	-- the member's cards in this album, one per rarity
	local strip = panel.Strip
	strip.Title.Text = `{string.upper(member.Name)}'S {#RARITIES} CARDS · TAP ONE`
	local owners = self._owners[album.Id]
	for i, r in RARITIES do
		local item = strip.Items:FindFirstChild("Item" .. i)
		if not item then
			continue
		end
		local holder = item.Holder
		local cid = Albums.CardId(album.Id, member.Key, r.Key)
		local n = owned[cid] or 0
		holder.Ring.Visible = cid == id
		local unique = holder:FindFirstChild("Unique")
		if n > 0 then
			fillSlot(holder.Card, cid, n, table.find(pins(), cid) ~= nil)
			holder.Empty.Visible = false
			if unique then
				unique.Visible = false
			end
		else
			holder.Card.Visible = false
			holder.Empty.Visible = unique == nil
			if unique then
				unique.Visible = true
				local name = owners and owners[member.Key]
				unique.Inner.Label.Text = if not owners then "…" elseif name then `Owned by\n<b>{escape(name)}</b>` else "Unclaimed"
			end
		end
		item:SetAttribute("Card", cid)
	end
	self:_askOwners(album.Id)
end

function BinderController:_sell()
	local id = self._preview
	if not id or self._selling then
		return
	end
	self._selling = true
	Sounds.Play("Click")
	BinderRemote:Fire({ Action = "Sell", Card = id, Where = "Binder", Confirm = self._confirm or nil })
end

-- the detail's PIN button: UNPIN for a pinned card, PIN with a free slot, PIN · n/n FULL
-- (opens the swap sheet) when every unlocked slot is used
function BinderController:_fillPinButton(id: string)
	local b = self._frame.Detail.Window.Panel.Info.Actions.Pin
	local list = pins()
	local slots = Albums.PinSlots()
	local used = 0
	for i, pinId in list do
		if i <= slots and (cards()[pinId] or 0) > 0 then
			used += 1
		end
	end
	if table.find(list, id) then
		b.Text = "UNPIN"
		b.BackgroundColor3 = CREAM
	elseif used < slots then
		b.Text = "PIN"
		b.BackgroundColor3 = YELLOW
	else
		b.Text = `PIN · {slots}/{slots} FULL`
		b.BackgroundColor3 = YELLOW
	end
end

function BinderController:_pinTapped()
	local id = self._preview
	if not id or self._pinning then
		return
	end
	Sounds.Play("Click")
	if table.find(pins(), id) then
		self._pinning = true
		BinderRemote:Fire({ Action = "Unpin", Card = id })
		return
	end
	local sheet = self._frame.Detail.Window.Panel.Swap
	if sheet.Visible then
		sheet.Visible = false
		return
	end
	self._pinning = true
	BinderRemote:Fire({ Action = "Pin", Card = id })
end

-- the swap sheet: your pins, each with what it earns; the weakest is marked with the gain
function BinderController:_showSwap()
	local id = self._preview
	local info = id and Albums.Card(id)
	if not info then
		return
	end
	local sheet = self._frame.Detail.Window.Panel.Swap
	local owned = cards()
	local b = bias()
	local mine = Albums.EarnPerHour(id, owned[id] or 1, b)
	sheet.Gain.Text = `{info.Member.Name} earns +{rateText(mine)}/hr`
	local list = pins()
	local slots = Albums.PinSlots()
	local weakest, weakestRate = nil, math.huge
	for i = 1, slots do
		local pinId = list[i]
		if pinId then
			local r = Albums.EarnPerHour(pinId, owned[pinId] or 0, b)
			if r < weakestRate then
				weakest, weakestRate = i, r
			end
		end
	end
	for i = 1, AlbumConstants.PIN_SLOTS_MAX do
		local item = sheet.Items:FindFirstChild("Item" .. i)
		if not item then
			continue
		end
		local holder = item.Slot.Holder
		local pinId = list[i]
		local pinInfo = pinId and Albums.Card(pinId)
		if i <= slots and pinInfo then
			local copies = owned[pinId] or 0
			local r = Albums.EarnPerHour(pinId, copies, b)
			fillSlot(holder.Card, pinId, math.max(copies, 1), false)
			holder.Empty.Visible = false
			item.Member.Text = string.upper(pinInfo.Member.Name)
			item.Rate.Text = `{rateText(r)}/hr`
			item.Swap.Visible = true
			local best = i == weakest and mine > r
			item.Swap.Text = if best then `Swap · +{rateText(mine - r)}` else "Swap"
			item.Swap.BackgroundColor3 = if best then YELLOW else CREAM
			item.Swap:SetAttribute("Card", pinId)
		else
			holder.Card.Visible = false
			holder.Empty.Visible = true
			holder.Empty.Mark.Visible = false
			holder.Empty.Lock.Visible = true
			item.Member.Text = "Locked"
			item.Rate.Text = ""
			item.Swap.Visible = false
		end
	end
	sheet.Visible = true
	Juice.Pop(sheet, 0.05)
end

function BinderController:_soon(what: string, gui: GuiObject?)
	Sounds.Play("Wrong")
	if gui then
		Juice.Shake(gui)
	end
	self:_toast(`{what} is coming soon`)
end

-- [[ Replies ]]

-- a numbered card's history: who rolled your best copy and who has owned it
function BinderController:_fillHistory(packet)
	local panel = self._frame.Detail.Window.Panel
	if packet.Card ~= self._preview or type(packet.Records) ~= "table" then
		return
	end
	local serial = Albums.Serials(PlayerData.Inventory.Serials[packet.Card].Get())[1]
	local record = serial and packet.Records[tostring(serial)]
	local label = panel.Info.Owners
	if type(record) ~= "table" then
		label.Text = "Rolled by you · no other owners yet"
		return
	end
	local me = Players.LocalPlayer.UserId
	local function who(o)
		return if type(o) ~= "table" then "someone" elseif o.UserId == me then "you" else tostring(o.Name or "someone")
	end
	local rolled = record.Rolled
	local text = `#{serial} rolled by {who(rolled)}`
	if type(rolled) == "table" and type(rolled.At) == "number" then
		text ..= ` on {os.date("%d %b %Y", rolled.At)}`
	end
	local owners = if type(record.Owners) == "table" then record.Owners else {}
	if #owners > 1 then
		local names = {}
		for _, o in owners do
			table.insert(names, who(o))
		end
		text ..= ` · owners: {table.concat(names, " → ")}`
	else
		text ..= " · no other owners yet"
	end
	label.Text = text
end

function BinderController:_onBinder(packet)
	if packet.Action == "History" then
		self:_fillHistory(packet)
		return
	end
	if packet.Action == "Owners" then
		if type(packet.Album) == "string" and type(packet.Owners) == "table" then
			self._owners[packet.Album] = packet.Owners
			if self.State == "Active" and self._tab == "Binder" and self._shownAlbum == packet.Album then
				self:_fillPage()
			end
			if self._preview then
				self:_fillPreview()
			end
		end
		return
	end
	if packet.Action == "Pin" or packet.Action == "Unpin" then
		self._pinning = false
		if packet.Card ~= self._preview then
			return
		end
		if packet.Full then
			self:_showSwap()
			return
		end
		if not packet.Ok then
			Sounds.Play("Wrong")
			self:_toast(packet.Text)
			return
		end
		self._frame.Detail.Window.Panel.Swap.Visible = false
		if packet.Action == "Pin" then
			Sounds.Play("Success")
			local info = Albums.Card(packet.Card)
			local earn = Albums.EarnPerHour(packet.Card, cards()[packet.Card] or 0, bias())
			self:_toast(`Pinned {info and info.Member.Name or "it"}: +{rateText(earn)} coins an hour`)
		else
			self:_toast("Unpinned")
		end
		-- (the screen refreshes when Inventory.Pins changes)
		return
	end
	if packet.Action == "SetBonus" then
		if self.State == "Active" and type(packet.Albums) == "table" then
			local album = Albums.Get(packet.Albums[1])
			Sounds.Play("Coins")
			self:_toast(`{album and album.Name or "Album"} complete! +{fmt(packet.Coins or 0)} coins`)
		end
		return
	end
	if packet.Action == "Collect" then
		if not self._collecting then
			return
		end
		self._collecting = false
		if packet.Ok then
			Sounds.Play("Coins")
			self:_toast(`+{fmt(packet.Coins or 0)} coins collected`)
			Juice.Pop(self._frame.Collect)
		else
			Sounds.Play("Wrong")
			self:_toast(packet.Text)
		end
		self:_fillHeader()
		return
	end
	if packet.Action == "Sell" then
		if not self._selling or packet.Card ~= self._preview then
			return
		end
		self._selling = false
		if packet.Confirm then
			-- the last copy of your bias's card: ask once more
			self._confirm = true
			self:_fillPreview()
			Juice.Shake(self._frame.Detail.Window.Panel.Info.Actions.Sell)
			self:_toast("That's your last copy of your bias's card. Tap again to sell it")
			return
		end
		if not packet.Ok then
			Sounds.Play("Wrong")
			self:_toast(packet.Text)
			return
		end
		Sounds.Play("Coins", { Volume = 0.4 })
		self:_toast(`Sold for {fmt(packet.Coins or 0)} coins`)
		self._confirm = false
		if (packet.Copies or 0) < 1 then
			self:_hidePreview()
		end
		-- (the rest refreshes when Inventory.Cards changes)
	end
end

-- [[ Lifecycle ]]

function BinderController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Binder")
	self._frame.Visible = false
	local f = self._frame
	local j = self._janitor

	-- every built button but the templates (their clones are hooked as they're made)
	for _, b in f:GetDescendants() do
		if b:IsA("GuiButton") and not b:FindFirstAncestor("Template") and b.Name ~= "Template" and b.Name ~= "Scrim" then
			ButtonScale.Apply(b)
		end
	end

	j:Add(f.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(f.Collect.Activated:Connect(function()
		self:_collect()
	end))
	for _, name in { "Binder", "Songs" } do
		j:Add(f.Tabs[name].Activated:Connect(function()
			if self._tab ~= name then
				Sounds.Play("Click")
				self:_hidePreview()
				self:_showTab(name)
			end
		end))
	end
	for _, name in { "Group", "All" } do
		j:Add(f.Binder.Groups.Mode[name].Activated:Connect(function()
			if self._mode ~= name then
				Sounds.Play("Click")
				self:_hidePreview()
				self:_showTab(self._tab, name)
			end
		end))
	end

	-- the group list
	local side = f.Binder.Groups
	for _, b in side.Filters:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				Sounds.Play("Click")
				self._filter = b.Name
				self:_fillList()
				side.List.CanvasPosition = Vector2.zero
			end))
		end
	end
	j:Add(side.Search.Box:GetPropertyChangedSignal("Text"):Connect(function()
		self._search = side.Search.Box.Text
		if self.State == "Active" then
			self:_fillList()
		end
	end))
	j:Add(f.Binder.Page.Head.OpenPack.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Open("Albums", { Group = self._group })
	end))

	-- All cards
	for _, b in f.All.Page.Sorts:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				if self._sort ~= b.Name then
					Sounds.Play("Click")
					self._sort = b.Name
					self:_fillAll()
					f.All.Page.Grid.CanvasPosition = Vector2.zero
				end
			end))
		end
	end

	-- the Songs tab
	for _, b in f.Songs.AllSongs.Sorts:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				if self._songSort ~= b.Name then
					Sounds.Play("Click")
					self._songSort = b.Name
					SongsTab.FillAll(self)
					f.Songs.AllSongs.List.CanvasPosition = Vector2.zero
				end
			end))
		end
	end
	j:Add(f.Songs.Group.Head.Practise.Activated:Connect(function()
		if self._songGroup then
			SongsTab.Practise(self, self._songGroup)
		end
	end))
	j:Add(f.Binder.Groups.Music.Lobby.Stop.Activated:Connect(function()
		Sounds.Play("Click")
		SongsTab.StopMusic()
	end))
	j:Add(player:GetAttributeChangedSignal("BgMusic"):Connect(function()
		if self.State == "Active" and self._tab == "Songs" then
			SongsTab.RefreshMusic(self)
		end
	end))
	for _, field in { PlayerData.Inventory.Mastery, PlayerData.Inventory.Ladders } do
		j:Add(field.Observe(function()
			self._songStatsCache = nil
			if self._tab == "Songs" then
				self:_refresh()
			end
		end))
	end

	-- the card detail
	local d = f.Detail
	local info = d.Window.Panel.Info
	j:Add(info.Actions.Sell.Activated:Connect(function()
		self:_sell()
	end))
	j:Add(info.Actions.Pin.Activated:Connect(function()
		self:_pinTapped()
	end))
	for _, item in d.Window.Panel.Swap.Items:GetChildren() do
		if item:IsA("Frame") then
			j:Add(item.Swap.Activated:Connect(function()
				local replace = item.Swap:GetAttribute("Card")
				if type(replace) == "string" and self._preview and not self._pinning then
					Sounds.Play("Click")
					self._pinning = true
					BinderRemote:Fire({ Action = "Pin", Card = self._preview, Replace = replace })
				end
			end))
		end
	end
	-- My pins: tap a pinned card to see it
	for _, slot in f.Binder.Groups.Pins.Slots:GetChildren() do
		if slot:IsA("Frame") then
			ButtonScale.Apply(slot.Tap)
			j:Add(slot.Tap.Activated:Connect(function()
				local id = slot.Tap:GetAttribute("Card")
				if type(id) == "string" and (cards()[id] or 0) > 0 then
					Sounds.Play("Click")
					self:_showPreview(id)
				end
			end))
		end
	end
	j:Add(info.Grade.Value.ButtonWrap.Button.Activated:Connect(function()
		self:_soon("Grading", info.Grade.Value.ButtonWrap.Button)
	end))
	for _, b in { d.Window.Panel.Close, d.Scrim } do
		j:Add(b.Activated:Connect(function()
			Sounds.Play("Click")
			self:_hidePreview()
		end))
	end
	for _, item in d.Window.Panel.Strip.Items:GetChildren() do
		if item:IsA("GuiButton") then
			j:Add(item.Activated:Connect(function()
				local cid = item:GetAttribute("Card")
				if type(cid) ~= "string" or cid == self._preview then
					return
				end
				if (cards()[cid] or 0) > 0 then
					Sounds.Play("Click")
					self:_showPreview(cid)
				else
					Sounds.Play("Wrong")
					Juice.Shake(item)
					self:_toast("You don't have this one yet")
				end
			end))
		end
	end

	-- live data
	j:Add(BinderRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Binder" then
			self:_onBinder(packet)
		end
	end), "Disconnect")
	for _, field in { PlayerData.Inventory.Cards, PlayerData.Inventory.Bias, PlayerData.Inventory.Pins } do
		j:Add(field.Observe(function()
			self._stats = nil
			self._allDirty = true
			self:_refresh()
		end))
	end
	j:Add(PlayerData.Currencies.Won.Observe(function()
		if self.State == "Active" then
			f.Coins.Amount.Text = fmt(PlayerData.Currencies.Won.Get() or 0)
		end
	end))

	-- Studio only: the LocalPlayer's "BinderTest" attribute (any text opens it; "All" opens All cards)
	if RunService:IsStudio() then
		j:Add(player:GetAttributeChangedSignal("BinderTest"):Connect(function()
			local v = player:GetAttribute("BinderTest")
			if type(v) == "string" and v ~= "" then
				self._interface:Open(self.Name, { Tab = if v == "All" or v == "Songs" then v else nil })
			end
		end))
	end
end

function BinderController:Activate(opts: any?)
	opts = if type(opts) == "table" then opts else {}
	self:_hidePreview()
	self._selling, self._collecting = false, false
	if opts.Tab == "Songs" and type(opts.Group) == "string" and #SongsTab.Of(opts.Group) > 0 then
		self._songGroup = opts.Group
	end
	local group = if type(opts.Group) == "string" and #Albums.PullAlbums(opts.Group) > 0 then opts.Group else (self._group or self:_defaultGroup())
	if group then
		self._group = group
		self._album = 1
		for i, album in Albums.PullAlbums(group) do
			if album.Id == opts.Album then
				self._album = i
			end
		end
	end
	self._shownAlbum = nil -- rebuild the rows (cards may have changed while closed)
	self._frame.Visible = true
	self.State = if self.State == "Active" then "Active" else "Activating"
	if opts.Tab == "Songs" then
		self:_showTab("Songs", "Group")
	elseif opts.Tab == "All" then
		self:_showTab("Binder", "All")
	else
		self:_showTab("Binder", "Group")
	end
	self._frame.Binder.Groups.List.CanvasPosition = Vector2.zero

	-- the COLLECT amount ticks up while it's open
	self._token += 1
	local token = self._token
	task.spawn(function()
		while self._token == token do
			task.wait(1)
			if self._token == token and (self.State == "Active" or self.State == "Activating") then
				self:_fillCollect()
			end
		end
	end)

	if self.State == "Active" then
		return Promise.resolve()
	end
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

-- controller B: the preview first
function BinderController:PadBack(): boolean
	if self._preview then
		self:_hidePreview()
		return true
	end
	return false
end

function BinderController:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self._token += 1
	self:_hidePreview()
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function BinderController:Destroy()
	self._token += 1
	self._janitor:Destroy()
end

return BinderController
