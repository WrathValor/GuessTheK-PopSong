--| SeasonController
-- The Season screen (Interface.Frames.Season, built by ./Build): the header's TRACK / RANKS /
-- REWARDS tabs and a days-left chip.
--   Track   – your tier (emblem, division pips, SP bar, "about N wins"), what your peak tier
--             pays at season end, duels / wins, then the Season Track: 5 milestones a page on a
--             road (claimed / ready / Stars to go / locked), Earn Stars and the next two big
--             rewards
--   Ranks   – the season board (top 3 cards with banners, rows 4–10) and your pinned row
--   Rewards – what each tier and each placement unlocks, your tier marked
-- Opened from the HUD's tier chip. Stars, claims and the season's duels / wins come from
-- Engine/SeasonService (mirrored as attributes); CLAIM asks it (SeasonRemote) to grant the
-- milestone, and a card upgrade opens the Index's upgrade picker straight away. SP / tiers are
-- still read from attributes until ranked duels set them.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- --------------------------------- Tables --------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local SeasonRemote = Bridgenet.ReferenceBridge("SeasonRemote")
local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local PINK = C("FF9EC4")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local PER_PAGE = 5
local SP_PER_WIN = 25 -- "about N wins" in the tier card (the base win in the doc)

-- milestone card art: which art frame + the colour of its tile
local ICONS = SeasonConstants.ICONS

-- coin milestones all use the shop's 1,000-coin pile art (two stacks + a coin)
local function coinPile(_amount: number): string
	return ShopCatalog.CoinBundles[2].Pile
end
-- paint a banner / photocard reward's art (only when it changes: photocards carry effects)
local function paintStyle(art: Instance, spec)
	local id = spec.Banner or spec.Photocard
	-- the kind is in the key: the S0 Comeback banner (20) and photocard (24) share an id and the
	-- same card slot. A banner card shows your photocard too, so a new photocard repaints it.
	local key = `{spec.Kind}|{id}|{LOCAL_PLAYER:GetAttribute("Photocard") or ""}`
	if art:GetAttribute("StyleShown") == key then
		return
	end
	art:SetAttribute("StyleShown", key)
	if spec.Kind == "Banner" then
		-- like the purchase reveal: the banner, with your photocard + name in front
		local box = art:FindFirstChild("Banner")
		SeasonArt.PaintBanner(box and box:FindFirstChild("Strip"), spec.Banner)
		local me = box and box:FindFirstChild("Me")
		if me then
			local avatar = me.Photo:FindFirstChild("Avatar")
			if avatar then
				avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
			end
			SeasonArt.PaintPhotocard(me, LOCAL_PLAYER:GetAttribute("Photocard") or SeasonConstants.DEFAULT_PHOTOCARD)
			box.PlayerName.Text = LOCAL_PLAYER.DisplayName
		end
	elseif spec.Kind == "Photocard" then
		local card = art:FindFirstChild("Card")
		local avatar = card and card.Photo:FindFirstChild("Avatar")
		if avatar then
			avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
		end
		SeasonArt.PaintPhotocard(card, spec.Photocard)
	end
end

local KIND = {
	Coins = { Art = "Coins", Tile = C("FFE07A"), Label = "coins" },
	Ticket = { Art = "Icon", Icon = "Ticket", Tile = C("DCD3FF"), Label = "roll ticket" },
	Upgrade = { Art = "Icon", Icon = "Upgrade", Tile = C("9ED8F5"), Label = "card upgrade" },
	Emote = { Art = "Icon", Icon = "Emote", Tile = C("A7E9B8"), Label = "emote" },
	Frame = { Art = "Icon", Icon = "Frame", Tile = C("DCD3FF"), Label = "profile frame" },
	Mic = { Art = "Icon", Icon = "Mic", Tile = C("FFD2E4"), Label = "mic skin" },
	Banner = { Art = "Banner", Icon = "Banner", Tile = C("FFF1A8"), Label = "profile banner" },
	Photocard = { Art = "Card", Icon = "Photocard", Tile = C("FFD2E4"), Label = "photocard" },
	Title = { Art = "TitleArt", Icon = "Title", Tile = C("CDEBFA"), Label = "title" },
}

-- a title reward is shown like the Inventory's titles: your name with the chip under it (on a
-- pastel blue tile like the other rewards), Gold shining / Rainbow scrolling (Build's titleArt)
local function paintTitle(art: Instance?, spec)
	if not art or not spec.Title then
		return
	end
	art.Player.Text = LOCAL_PLAYER.DisplayName
	local chip = art.Chip
	chip.Text = spec.Title
	TierShine.Apply(chip, chip.Rainbow, Cards.LEVELS[spec.TitleTier or 1], YELLOW)
end

-- ---------------------------------- Class --------------------------------- --
local SeasonController = {}
SeasonController.__index = SeasonController

function SeasonController.new()
	local self = setmetatable({}, SeasonController)
	self.Name = "Season"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Track"
	self._page = nil :: number?
	return (self :: any) :: UITypes.Controller
end

-- [[ Season state (attributes until SeasonService exists) ]]

local function state()
	local sp = LOCAL_PLAYER:GetAttribute("SeasonSP") or 0
	return {
		SP = sp,
		Peak = math.max(sp, LOCAL_PLAYER:GetAttribute("SeasonPeakSP") or 0),
		Stars = LOCAL_PLAYER:GetAttribute("SeasonStars") or 0,
		Claimed = LOCAL_PLAYER:GetAttribute("SeasonClaimed") or 0,
		Duels = LOCAL_PLAYER:GetAttribute("SeasonDuels") or 0,
		Wins = LOCAL_PLAYER:GetAttribute("SeasonWins") or 0,
		Banner = LOCAL_PLAYER:GetAttribute("Banner") or SeasonConstants.DEFAULT_BANNER,
	}
end

local function daysLeft(): string
	local ends = SeasonConstants.Current().Ends
	if ends <= 0 then
		return "Pre-season"
	end
	local days = math.max(0, math.ceil((ends - os.time()) / 86400))
	return if days == 1 then "1 day left" else `{days} days left`
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- -------------------------------- Lifecycle ------------------------------- --

function SeasonController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Season")
	self._frame.Visible = false
	local panel = self._frame.Panel
	FitPanel.Watch(self._frame, self._janitor)
	ButtonScale.ApplyToDescendants(panel)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, tab in panel.Header.Tabs:GetChildren() do
		if tab:IsA("GuiButton") then
			j:Add(tab.Activated:Connect(function()
				Sounds.Play("Click")
				self:_show(tab.Name)
			end))
		end
	end

	local track = panel.Pages.Track.Right
	j:Add(track.Milestones.Prev.Activated:Connect(function()
		self._page = math.max(1, (self._page or 1) - 1)
		self:_fillTrack()
	end))
	j:Add(track.Milestones.Next.Activated:Connect(function()
		self._page = math.min(math.ceil(#SeasonConstants.TRACK / PER_PAGE), (self._page or 1) + 1)
		self:_fillTrack()
	end))
	for i = 1, PER_PAGE do
		local face = track.Milestones["Card" .. i].Face
		j:Add(face.Claim.Activated:Connect(function()
			self:_claim(face:GetAttribute("Milestone"))
		end))
	end

	-- the Ranks board
	j:Add(SeasonRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Result" and packet.Action == "Board" and packet.Ok then
			self._boards = self._boards or {}
			self._boards[packet.Board.Kind or "SP"] = packet.Board
			if self._frame.Visible then
				self:_fillRanks()
			end
		end
	end), "Disconnect")

	-- Season Rating / Season Wins
	local ranksLeft = panel.Pages.Ranks.Left
	for kind, button in { SP = ranksLeft.Rating, Wins = ranksLeft.Wins } do
		j:Add(button.Activated:Connect(function()
			if self._boardKind == kind then
				return
			end
			Sounds.Play("Click")
			self._boardKind = kind
			self:_fillRanks()
			self:_requestBoard()
		end))
	end

	-- the server's answer to CLAIM
	j:Add(SeasonRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" or packet.Action ~= "Claim" then
			return
		end
		if not packet.Ok then
			Sounds.Play("Wrong")
			return
		end
		Sounds.Play("Success")
		local n = packet.N
		local holder = track.Milestones:FindFirstChild("Card" .. ((n - 1) % PER_PAGE + 1))
		if holder then
			Juice.Pop(holder.Face, 0.2)
		end
		-- an upgrade isn't forced on you: it waits under your coins on the HUD (HUDController)
	end), "Disconnect") -- BridgeNet2 connections have no Destroy

	for _, name in { "SeasonSP", "SeasonPeakSP", "SeasonStars", "SeasonClaimed", "SeasonDuels", "SeasonWins", "Banner", "Photocard" } do
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal(name):Connect(function()
			if self.State == "Active" or self.State == "Activating" then
				self:_fill()
			end
		end))
	end
end

-- Interface:Open("Season", "Ranks") lands on a tab
function SeasonController:Activate(tab: string?)
	self._frame.Visible = true
	self._page = nil
	self:_fill()
	self:_show(tab or self._tab)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function SeasonController:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function SeasonController:Destroy()
	self._janitor:Destroy()
end

-- [[ Tabs ]]

function SeasonController:_show(tab: string)
	local panel = self._frame.Panel
	if not panel.Pages:FindFirstChild(tab) then
		tab = "Track"
	end
	self._tab = tab
	for _, page in panel.Pages:GetChildren() do
		page.Visible = page.Name == tab
	end
	for _, button in panel.Header.Tabs:GetChildren() do
		if button:IsA("GuiButton") then
			button.BackgroundTransparency = if button.Name == tab then 0 else 0.55
		end
	end
	if tab == "Ranks" then
		self:_requestBoard()
	end
end

-- the Ranks board comes from the server (Engine/SeasonService/Board); asked for when the tab
-- opens, at most every BOARD_REFRESH seconds (the server only re-reads it that often anyway)
-- Two boards on the Ranks tab (Left.Rating / Left.Wins): "SP" (Season Rating) and "Wins".
function SeasonController:_requestBoard()
	local kind = self._boardKind or "SP"
	self._boardAsked = self._boardAsked or {}
	local now = os.clock()
	if self._boardAsked[kind] and now - self._boardAsked[kind] < SeasonConstants.BOARD_REFRESH then
		return
	end
	self._boardAsked[kind] = now
	SeasonRemote:Fire({ Action = "Board", Kind = kind })
end

-- [[ Fill ]]

function SeasonController:_fill()
	local header = self._frame.Panel.Header
	header.Title.Text = SeasonConstants.Current().Name
	header.Days.Text = daysLeft()
	self:_fillTrack()
	self:_fillRanks()
	self:_fillRewards()
end

function SeasonController:_fillTrack()
	local s = state()
	local page = self._frame.Panel.Pages.Track
	local info = SeasonConstants.TierOf(s.SP)

	-- tier card
	local tier = page.Left.Tier
	tier.BackgroundColor3 = if info.Tier.Holo then C("FFF1A8") else info.Tier.Colour
	SeasonArt.PaintEmblem(tier.Emblem, info)
	tier.TierName.Text = info.Label
	for i = 1, 3 do
		tier.Pips["Pip" .. i].BackgroundColor3 = if i <= info.Pips then YELLOW else CREAM
	end
	tier.SP.Text = `{comma(s.SP)} SP`
	if info.Next then
		local toGo = info.Next - s.SP
		tier.NextAt.Text = `{info.NextLabel} · {comma(info.Next)}`
		tier.ToGo.Text = `{comma(toGo)} SP to go · about {math.max(1, math.ceil(toGo / SP_PER_WIN))} wins`
	else
		tier.NextAt.Text = "Top tier"
		tier.ToGo.Text = "Hold your place in the Top 100"
	end
	tier.Bar.Fill.Size = UDim2.fromScale(info.Progress, 1)

	-- season-end rewards from the peak tier: the three best it has earned, then the next one
	local peak = SeasonConstants.TierOf(s.Peak)
	local earned = {}
	for i = 1, peak.Index do
		table.insert(earned, SeasonConstants.TIERS[i])
	end
	local rewards = page.Left.SeasonEnd.Rewards
	for i = 1, 3 do
		local slot = rewards["Slot" .. i]
		local t = earned[#earned - 3 + i]
		slot.Visible = t ~= nil
		if t then
			slot.Tile.BackgroundColor3 = if t.Holo then C("FFF1A8") else t.Colour
			slot.Tile.Text = ""
			slot.Tile.Icon.Image = ICONS[SeasonConstants.TIER_REWARD_ICONS[t.Name]] or ""
			slot.Label.Text = SeasonConstants.TIER_REWARDS[t.Name]
		end
	end
	local nextTier = SeasonConstants.TIERS[peak.Index + 1]
	page.Left.SeasonEnd.Next.Text = if nextTier
		then `Reach {nextTier.Name}: {string.lower(SeasonConstants.TIER_REWARDS[nextTier.Name])}`
		else "Every tier reward is yours"
	page.Left.Duels.Value.Text = comma(s.Duels)
	page.Left.Wins.Value.Text = comma(s.Wins)

	-- the track
	local right = page.Right
	local cost = SeasonConstants.STARS_PER_MILESTONE
	local total = #SeasonConstants.TRACK
	local reached = math.min(total, math.floor(s.Stars / cost))
	right.Stars.Value.Text = `{comma(s.Stars)} Stars`
	right.Count.Text = `{s.Claimed} / {total} milestones`
	right.TrackBar.Fill.Size = UDim2.fromScale(s.Claimed / total, 1)
	local maxPage = math.ceil(total / PER_PAGE)
	self._page = self._page or math.clamp(math.floor(s.Claimed / PER_PAGE) + 1, 1, maxPage)
	local first = (self._page - 1) * PER_PAGE
	for name, on in { Prev = self._page > 1, Next = self._page < maxPage } do
		right.Milestones[name].Visible = on
		local shadow = right.Milestones:FindFirstChild(name .. "Shadow")
		if shadow then
			shadow.Visible = on
		end
	end
	local here = nil
	for i = 1, PER_PAGE do
		local n = first + i
		local spec = SeasonConstants.TRACK[n]
		local holder = right.Milestones["Card" .. i]
		holder.Visible = spec ~= nil
		if spec then
			local face = holder.Face
			local kind = KIND[spec.Kind] or KIND.Coins
			local claimed = n <= s.Claimed
			local ready = not claimed and n <= reached and n == s.Claimed + 1
			face:SetAttribute("Milestone", n)
			face.Number.Text = tostring(n)
			face.Art.BackgroundColor3 = kind.Tile
			for _, art in face.Art:GetChildren() do
				if art:IsA("GuiObject") then
					art.Visible = art.Name == kind.Art
				end
			end
			face.Art.Icon.Image = if kind.Icon then ICONS[kind.Icon] else ""
			if spec.Kind == "Banner" or spec.Kind == "Photocard" then
				paintStyle(face.Art, spec)
			end
			if spec.Kind == "Coins" then
				face.Art.Coins.Image = coinPile(spec.Amount)
			elseif spec.Kind == "Title" then
				paintTitle(face.Art:FindFirstChild("TitleArt"), spec)
			end
			if spec.Kind == "Coins" then
				face.Amount.Text = comma(spec.Amount)
			elseif spec.Amount then
				face.Amount.Text = `×{spec.Amount}`
			else
				face.Amount.Text = spec.Name or ""
			end
			face.Kind.Text = kind.Label
			face.Kind.Visible = not ready
			face.Claim.Visible = ready
			local stateChip = face.State
			if claimed then
				stateChip.Text, stateChip.BackgroundColor3 = "✓ CLAIMED", MINT
			elseif ready then
				stateChip.Text, stateChip.BackgroundColor3 = "READY", YELLOW
			elseif n == s.Claimed + 1 or n <= reached + 1 then
				stateChip.Text, stateChip.BackgroundColor3 = `{comma(n * cost - s.Stars)} ★ TO GO`, WHITE
			else
				stateChip.Text, stateChip.BackgroundColor3 = if spec.Big then "BIG" else "LOCKED", if spec.Big then PINK else WHITE
			end
			holder.Shadow.Visible = ready
			holder.Position = UDim2.fromOffset(holder.Position.X.Offset, if ready then 4 else 12)
			for _, d in face:GetDescendants() do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					d.TextTransparency = if claimed then 0.35 else 0
				end
				if d:IsA("ImageLabel") then
					d.ImageTransparency = if claimed then 0.35 else 0
				end
			end
			if here == nil and not claimed then
				here = i
			end
		end
	end
	local road = right.Road
	local fillTo = if here then 0.1 + (here - 1) * 0.2 else 0.9
	road.Fill.Size = UDim2.new(math.max(0, fillTo - 0.1), 0, 0, 8)
	road.Fill.Visible = fillTo > 0.1
	road.Here.Visible = here ~= nil
	road.Here.Position = UDim2.new(fillTo, 0, 0.5, 0)
	for i = 1, PER_PAGE do
		local node = road["Node" .. i]
		node.BackgroundColor3 = if here and i < here or here == nil then PINK else WHITE
		node.Visible = i ~= here and SeasonConstants.TRACK[first + i] ~= nil
	end

	-- earn stars
	for i, spec in SeasonConstants.EARN do
		local tile = right.Earn:FindFirstChild("Tile" .. i)
		if tile then
			tile.BackgroundColor3 = spec.Colour
			tile.Value.Text = spec.Value
			tile.Icon.Image = ICONS[spec.Icon] or ""
			tile.Label.Text = spec.Label
			tile.Sub.Text = spec.Sub
		end
	end

	-- coming up: the next two big rewards
	local upcoming = {}
	for n = s.Claimed + 1, total do
		if SeasonConstants.TRACK[n].Big then
			table.insert(upcoming, n)
			if #upcoming == 2 then
				break
			end
		end
	end
	for i = 1, 2 do
		local tile = right.ComingUp["Big" .. i]
		local n = upcoming[i]
		tile.Visible = n ~= nil
		if n then
			local spec = SeasonConstants.TRACK[n]
			local what = spec.Name or ""
			if spec.Kind == "Photocard" then
				what ..= " photocard"
			elseif spec.Kind == "Title" then
				what ..= " title"
			end
			tile.Title.Text = `{n} · {what}`
			local away = n * cost - s.Stars
			tile.Sub.Text = if away <= 0 then "Ready to claim" else `{comma(away)} Stars away`
			-- a banner previews itself; anything else shows its icon on its card colour
			local banner = spec.Kind == "Banner"
			SeasonArt.PaintBanner(tile.Preview, if banner then spec.Banner else "Lilac")
			if not banner then
				tile.Preview.BackgroundColor3 = (KIND[spec.Kind] or KIND.Coins).Tile
				local tint = tile.Preview:FindFirstChild("Tint")
				if tint then
					tint.Enabled = false
				end
				for _, d in tile.Preview:GetChildren() do
					if d.Name == "Pattern" or d.Name == "Art" then
						d.Visible = false
					end
				end
			end
			local k = KIND[spec.Kind]
			local photocard = spec.Kind == "Photocard" and spec.Photocard ~= nil
			local card = tile:FindFirstChild("Card")
			if card then
				card.Visible = photocard
				if photocard then
					paintStyle(tile, spec)
				end
			end
			local title = spec.Kind == "Title"
			local titleArt = tile:FindFirstChild("TitleArt")
			if titleArt then
				titleArt.Visible = title
				if title then
					paintTitle(titleArt, spec)
				end
			end
			tile.Icon.Visible = not banner and not photocard and not title and k ~= nil and k.Icon ~= nil
			tile.Icon.Image = if k and k.Icon then ICONS[k.Icon] else ""
		end
	end
end

function SeasonController:_claim(n: number?)
	local s = state()
	if not n or n ~= s.Claimed + 1 or s.Stars < n * SeasonConstants.STARS_PER_MILESTONE then
		return
	end
	SeasonRemote:Fire({ Action = "Claim", N = n }) -- the reply pops the card (Initialize)
end

-- banners for board players who aren't in this server (their equipped one isn't known here)
local BOARD_BANNERS = { "S0Legend", "Lightsticks", "Sky", "Lilac" }

function SeasonController:_fillRanks()
	local s = state()
	local page = self._frame.Panel.Pages.Ranks
	local info = SeasonConstants.TierOf(s.SP)
	local kind = self._boardKind or "SP"
	local wins = kind == "Wins"
	local board = self._boards and self._boards[kind]
	local entries = if board and board.Season == SeasonConstants.Current().Id then board.Entries else {}
	local function bannerFor(entry, i: number): string
		return entry.Banner or BOARD_BANNERS[math.min(i, #BOARD_BANNERS)]
	end
	-- a value as the board shows it: "1,041 SP" / "12 wins"
	local function value(n: number): string
		return if wins then `{comma(n)} {if n == 1 then "win" else "wins"}` else `{comma(n)} SP`
	end

	-- the two board buttons: the open one is ink
	for k, button in { SP = page.Left.Rating, Wins = page.Left.Wins } do
		local on = k == kind
		button.BackgroundColor3 = if on then INK else WHITE
		button.TextColor3 = if on then C("FBF7F0") else INK
	end
	page.Right.Heading.Text = if wins then "Season Wins · Top 100" else "Season Rating · Top 100"

	-- top 3: the billboard cards
	for i = 1, 3 do
		local t = page.Left["Top" .. i]
		local entry = entries[i]
		if entry then
			t.PlayerName.Text = if entry.UserId == LOCAL_PLAYER.UserId then `{entry.Name} (you)` else entry.Name
			t.SP.Text = if wins then value(entry.Value) else `{value(entry.Value)} · {SeasonConstants.TierOf(entry.Value).Label}`
			SeasonArt.PaintBanner(t.Banner, bannerFor(entry, i))
		else
			t.PlayerName.Text = "—"
			t.SP.Text = if board then "Open spot" else "Loading…"
			SeasonArt.PaintBanner(t.Banner, ({ "S0Legend", "Lightsticks", "Sky" })[i])
		end
	end
	-- #4–#10: the rows; an empty place shows as an open spot. The tier chip is SP's (a wins
	-- board doesn't know other players' SP), so it only shows on Season Rating.
	local rows = page.Right.Rows
	for i = 1, 7 do
		local row = rows["Row" .. i]
		local entry = entries[i + 3]
		row.Visible = true
		row.Rank.Text = `#{i + 3}`
		if entry then
			local mine = entry.UserId == LOCAL_PLAYER.UserId
			row.PlayerName.Text = if mine then `YOU · {entry.Name}` else entry.Name
			row.PlayerName.TextColor3 = INK
			row.SP.Text = comma(entry.Value)
			row.Tier.Visible = not wins
			if not wins then
				SeasonArt.PaintChip(row.Tier, SeasonConstants.TierOf(entry.Value))
			end
			SeasonArt.PaintBanner(row.Banner, bannerFor(entry, 4))
			row.Banner.BackgroundTransparency = 0
		else
			row.PlayerName.Text = "Open spot"
			row.PlayerName.TextColor3 = C("8A8398")
			row.SP.Text = "—"
			row.Tier.Visible = false
			SeasonArt.PaintBanner(row.Banner, "Lilac")
			row.Banner.BackgroundTransparency = 0.6
		end
	end
	rows.Empty.Visible = false
	local size = if board then board.Size else SeasonConstants.BOARD_SIZE
	page.Right.Cutoff.Text = if not board then "Loading the board…"
		elseif not SeasonConstants.IsRated() then "Season over · final standings"
		elseif board.Cutoff then `Top {size} cutoff: {value(board.Cutoff)}`
		elseif wins then `Top {size} · every duel win counts`
		else `Top {size} · every rated duel counts`
	-- your row, pinned
	local mineValue = if wins then s.Wins else s.SP
	local you = page.Right.You
	you.Rank.Text = if board and board.Rank then `#{board.Rank}` elseif mineValue > 0 then `{size}+` else "—"
	you.PlayerName.Text = `YOU · {LOCAL_PLAYER.DisplayName}`
	you.SP.Text = comma(mineValue)
	SeasonArt.PaintBanner(you.Banner, s.Banner)
	SeasonArt.PaintChip(you.Tier, info)
end

function SeasonController:_fillRewards()
	local s = state()
	local page = self._frame.Panel.Pages.Rewards
	local mine = SeasonConstants.TierOf(s.Peak).Tier.Name
	for i, tier in SeasonConstants.TIERS do
		local t = page.Tiers:FindFirstChild(tier.Name)
		if t then
			local nextTier = SeasonConstants.TIERS[i + 1]
			SeasonArt.PaintEmblem(t.Emblem, SeasonConstants.TierOf(tier.Min))
			t.Range.Text = if nextTier then `{comma(tier.Min)}–{comma(nextTier.Min - 1)} SP` else `{comma(tier.Min)}+ SP`
			t.Reward.Text = SeasonConstants.TIER_REWARDS[tier.Name]
			t.You.Visible = tier.Name == mine
			t.BackgroundColor3 = if tier.Name == mine then (if tier.Holo then C("FFF1A8") else tier.Colour) else WHITE
		end
	end
end

return SeasonController
