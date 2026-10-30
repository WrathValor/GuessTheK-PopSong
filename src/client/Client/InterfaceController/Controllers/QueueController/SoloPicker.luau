--| SoloPicker
-- The back of the queue card (the "Solo D · queue flip + photocards" board). Play Solo flips
-- the card over to "Pick your theme": All / Era / Gen / My Pack tabs, a row of photocards
-- (the picked one lifts and goes holo, themes without Themes.MIN_SONGS songs are SEALED), a
-- "Mix in my duel pack" switch, Back and Start. Start counts down START_DELAY seconds (the
-- picks can still change, tap Start again or Back to cancel), then sends
-- { Request = "Solo", Theme, Mix } on QueueRemote; the server saves both
-- (Settings.SoloTheme / SoloPool) for next time.
-- Build(queueFrame) runs once in Studio; new() wires it up from QueueController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local PAPER = C("F3EBDD")
local LINE = C("E6DCCB")
local MUTED = C("5C566B")
local SUB = C("4A4460")
local LILAC = C("B9A6FF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local GREY = C("CFC5B3")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.2, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.4, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.6, C("B8F0C8")),
	ColorSequenceKeypoint.new(0.8, C("B5DDFF")),
	ColorSequenceKeypoint.new(1, C("D4C2FF")),
})

local W, H = 710, 470 -- the back of the card
local DECK_W, DECK_H = 666, 250
local CARD_W, CARD_H = 124, 190 -- picked: SEL_W x SEL_H, lifted
local SEL_W, SEL_H = 140, 210
local CARD_GAP = 22
local MAX_CARDS = 4
local TILT = { -4, -2, 0, 3 }
local TAB_W = { All = 52, Era = 56, Gen = 56, Pack = 86 }
local TAB_LABEL = { All = "All", Era = "Era", Gen = "Gen", Pack = "My Pack" }
local START_DELAY = 3 -- seconds between pressing Start and the game starting

local SoloPicker = {}
SoloPicker.__index = SoloPicker

-- ------------------------------------------------------------------ Build -- --

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number | UDim)
	new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, p)
end

local function stroke(p: Instance, t: number, colour: Color3?)
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a tick made of two bars (glyphs like ✓ don't render in every font)
local function tick(parent: Instance)
	local holder = new("Frame", { Name = "Mark", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(14, 12), BackgroundTransparency = 1 }, parent)
	local a = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(4, 7), Size = UDim2.fromOffset(7, 3), Rotation = 45, BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(a, 2)
	local b = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(9, 5), Size = UDim2.fromOffset(11, 3), Rotation = -50, BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(b, 2)
end

local function buildCard(deck: Instance, i: number)
	local shadow = new("Frame", { Name = "Card" .. i .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = INK, BorderSizePixel = 0 }, deck)
	corner(shadow, 13)
	local card = new("TextButton", {
		Name = "Card" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
	}, deck)
	corner(card, 13)
	stroke(card, 3)
	new("UIGradient", { Name = "Holo", Color = HOLO, Rotation = 20, Enabled = false }, card)

	local count = text(card, "Count", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = "21 songs",
		ZIndex = 3,
	})
	corner(count, 7)
	stroke(count, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, count)

	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 32), Size = UDim2.new(1, -16, 1, -88), BackgroundColor3 = LILAC, ZIndex = 3 }, card)
	corner(art, 8)
	stroke(art, 2)
	local numeral = text(art, "Numeral", {
		Size = UDim2.fromScale(1, 1),
		FontFace = HEAD,
		TextSize = 40,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = "IV",
		ZIndex = 4,
	})
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, numeral)

	text(card, "Title", { Position = UDim2.new(0, 8, 1, -52), Size = UDim2.new(1, -16, 0, 18), FontFace = HEAD, TextSize = 15, Text = "Gen 4", ZIndex = 3 })
	text(card, "Groups", {
		Position = UDim2.new(0, 8, 1, -32),
		Size = UDim2.new(1, -16, 0, 26),
		FontFace = BODY_BOLD,
		TextSize = 11,
		TextColor3 = SUB,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "ITZY, LE SSERAFIM, aespa",
		ZIndex = 3,
	})

	local sealed = text(card, "Sealed", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(84, 24),
		Rotation = -8,
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		FontFace = HEAD,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "SEALED",
		Visible = false,
		ZIndex = 6,
	})
	corner(sealed, 9)
	stroke(sealed, 3)

	local picked = new("Frame", { Name = "Picked", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(28, 28), Rotation = 8, BackgroundColor3 = YELLOW, Visible = false, ZIndex = 6 }, card)
	corner(picked, UDim.new(0.5, 0))
	stroke(picked, 3)
	tick(picked)
	for _, d in picked:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 7
		end
	end
end

function SoloPicker.Build(queueFrame: Instance)
	for _, n in { "Solo", "SoloShadow" } do
		local old = queueFrame:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local cx, cy = 640, 360 -- centred on the screen
	local shadow = new("Frame", { Name = "SoloShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 6, cy + 6), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, Visible = false }, queueFrame)
	corner(shadow, 16)
	local back = new("Frame", { Name = "Solo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(W, H), BackgroundColor3 = WHITE, Visible = false }, queueFrame)
	corner(back, 16)
	stroke(back, 3)
	new("UIScale", { Name = "Flip" }, back)
	new("UIScale", { Name = "Flip" }, shadow)

	-- lilac tag on the top edge, like DUEL STAGE on the front
	local tagShadow = new("Frame", { Name = "TagShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2 + 4, -2 + 4), Size = UDim2.fromOffset(176, 31), Rotation = -2, BackgroundColor3 = INK, ZIndex = 2 }, back)
	corner(tagShadow, 10)
	local tag = text(back, "Tag", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W / 2, -2),
		Size = UDim2.fromOffset(176, 31),
		Rotation = -2,
		BackgroundTransparency = 0,
		BackgroundColor3 = LILAC,
		FontFace = HEAD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "SOLO PRACTICE",
		ZIndex = 3,
	})
	corner(tag, 10)
	stroke(tag, 3)

	text(back, "Heading", { Position = UDim2.fromOffset(22, 26), Size = UDim2.fromOffset(330, 26), FontFace = HEAD, TextSize = 21, Text = "Pick your theme" })
	text(back, "Sub", { Position = UDim2.fromOffset(22, 52), Size = UDim2.fromOffset(330, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "XP + Index only · all 4 answers come from it" })

	-- segmented tabs
	local tabsW = 3
	for _, t in Themes.TABS do
		tabsW += TAB_W[t] + 3
	end
	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(W - 22 - tabsW, 28), Size = UDim2.fromOffset(tabsW, 40), BackgroundColor3 = PAPER }, back)
	corner(tabs, 12)
	stroke(tabs, 3)
	local x = 3
	for _, t in Themes.TABS do
		local tw = TAB_W[t]
		local b = new("TextButton", {
			Name = t,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + tw / 2, 17),
			Size = UDim2.fromOffset(tw, 28),
			BackgroundColor3 = INK,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			FontFace = BODY,
			TextSize = 13,
			TextColor3 = INK,
			Text = TAB_LABEL[t],
		}, tabs)
		corner(b, 8)
		x += tw + 3
	end

	-- the photocards
	local deck = new("Frame", { Name = "Deck", Position = UDim2.fromOffset(22, 84), Size = UDim2.fromOffset(DECK_W, DECK_H), BackgroundColor3 = CREAM }, back)
	corner(deck, 14)
	stroke(deck, 2, LINE)
	for i = 1, MAX_CARDS do
		buildCard(deck, i)
	end

	-- "Mix in my duel pack"
	local mix = new("Frame", { Name = "Mix", Position = UDim2.fromOffset(22, 348), Size = UDim2.fromOffset(DECK_W, 26), BackgroundTransparency = 1 }, back)
	local toggle = new("TextButton", { Name = "Toggle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(20, 13), Size = UDim2.fromOffset(40, 22), BackgroundColor3 = MINT, AutoButtonColor = false, Text = "" }, mix)
	corner(toggle, UDim.new(0.5, 0))
	stroke(toggle, 2)
	local knob = new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE }, toggle)
	corner(knob, UDim.new(0.5, 0))
	stroke(knob, 2)
	text(mix, "Label", { Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -50, 1, 0), TextSize = 13, RichText = true, Text = 'Mix in my duel pack <font color="#5C566B">· My Pack, Gen 4 songs only</font>' })

	-- Back + Start
	local by = 386
	local backShadow = new("Frame", { Name = "BackShadow", Position = UDim2.fromOffset(22 + 3, by + 3), Size = UDim2.fromOffset(130, 56), BackgroundColor3 = INK }, back)
	corner(backShadow, 12)
	local backBtn = new("TextButton", { Name = "Back", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(22 + 65, by + 28), Size = UDim2.fromOffset(130, 56), BackgroundColor3 = WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 15, TextColor3 = INK, Text = "Back", ZIndex = 2 }, back)
	corner(backBtn, 12)
	stroke(backBtn, 3)

	local sx, sw = 22 + 130 + 12, DECK_W - 130 - 12
	local startShadow = new("Frame", { Name = "StartShadow", Position = UDim2.fromOffset(sx + 4, by + 4), Size = UDim2.fromOffset(sw, 56), BackgroundColor3 = INK }, back)
	corner(startShadow, 12)
	local start = new("TextButton", { Name = "Start", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx + sw / 2, by + 28), Size = UDim2.fromOffset(sw, 56), BackgroundColor3 = MINT, AutoButtonColor = false, Text = "", ZIndex = 2 }, back)
	corner(start, 12)
	stroke(start, 3)
	text(start, "Title", { Position = UDim2.fromOffset(0, 9), Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Text = "START · GEN 4", ZIndex = 3 })
	text(start, "Sub", { Position = UDim2.fromOffset(0, 31), Size = UDim2.new(1, 0, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Text = "21 songs · 7 rounds", ZIndex = 3 })

	-- front: a mini holo photocard on Play Solo showing the last theme
	local playSolo = queueFrame:FindFirstChild("Panel") and queueFrame.Panel:FindFirstChild("PlaySolo")
	if playSolo then
		local old = playSolo:FindFirstChild("MiniCard")
		if old then
			old:Destroy()
		end
		local mini = new("Frame", { Name = "MiniCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(26, 32), Rotation = 8, BackgroundColor3 = WHITE, ZIndex = 4 }, playSolo)
		corner(mini, 5)
		stroke(mini, 2)
		new("UIGradient", { Name = "Holo", Color = HOLO, Rotation = 20 }, mini)
		text(mini, "Numeral", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "IV", ZIndex = 5 })
	end
	return back
end

-- -------------------------------------------------------------- Behaviour -- --

local function hasSong(id: string): boolean
	local ok, has = pcall(PlayerData.Inventory.Songs.Has, id)
	return ok and has == true
end

-- the player's duel pack: id, display name, owned songs in it (nil when none is on)
local function duelPack()
	local ok, id = pcall(PlayerData.Inventory.DuelPack.Get)
	if not ok or id == "" or not Packs.Get(id) then
		return nil
	end
	local songs = Packs.SongsFor(id, hasSong)
	if #songs == 0 then
		return nil
	end
	return { Id = id, Name = Packs.DisplayName(id), Songs = songs }
end

local function setting(path, fallback)
	local ok, value = pcall(path.Get)
	return if ok and value ~= nil then value else fallback
end

-- what a theme card shows: count text, groups line, open?, songs
local function describe(theme, pack)
	if theme.Id == Themes.PACK then
		if not pack then
			return { Count = "No pack", Groups = "Put a duel pack on in Inventory", Open = false, Songs = 0 }
		end
		local n = #pack.Songs
		local open = n >= DuelConstants.ROUNDS
		return {
			Count = if open then `{n} songs` else `{n} / {DuelConstants.ROUNDS}`,
			Groups = `{pack.Name} · only its songs`,
			Open = open,
			Songs = n,
		}
	end
	local n = Themes.Count(theme.Id)
	local open = Themes.IsOpen(theme.Id)
	return {
		Count = if open then `{n} songs` else `{n} / {Themes.MIN_SONGS}`,
		Groups = if theme.Id == "All" then "Everything in the library" else Themes.TopGroups(theme.Id, 3),
		Open = open,
		Songs = n,
	}
end

local function tween(inst: Instance, info: TweenInfo, props)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

function SoloPicker.new(queueFrame: Instance, janitor)
	local self = setmetatable({}, SoloPicker)
	self._queue = queueFrame
	self._front = queueFrame:FindFirstChild("Panel")
	self._frontShadow = queueFrame:FindFirstChild("PanelShadow")
	self._back = queueFrame:FindFirstChild("Solo")
	self._backShadow = queueFrame:FindFirstChild("SoloShadow")
	self.IsOpen = false
	if not self._back then
		return self -- not built in Studio yet: Play Solo starts an "All songs" game
	end

	self._theme = setting(PlayerData.Settings.SoloTheme, Themes.DEFAULT)
	if not Themes.Get(self._theme) then
		self._theme = Themes.DEFAULT
	end
	self._mix = setting(PlayerData.Settings.SoloPool, "Mix") ~= "Off"
	self._tab = Themes.Get(self._theme).Tab

	local back = self._back
	for _, t in Themes.TABS do
		janitor:Add(back.Tabs[t].Activated:Connect(function()
			if self._tab ~= t then
				self._tab = t
				-- a tab with one theme (All, My Pack) picks it straight away
				local list = Themes.ForTab(t)
				if #list == 1 and describe(list[1], duelPack()).Open then
					self._theme = list[1].Id
				end
				self:Render()
			end
		end))
	end
	for i = 1, MAX_CARDS do
		janitor:Add(back.Deck["Card" .. i].Activated:Connect(function()
			local theme = self._cards and self._cards[i]
			if theme and describe(theme, duelPack()).Open and self._theme ~= theme.Id then
				self._theme = theme.Id
				Sounds.Play("Click")
				self:Render()
			end
		end))
	end
	janitor:Add(back.Mix.Toggle.Activated:Connect(function()
		self._mix = not self._mix
		self:Render()
	end))
	janitor:Add(back.Back.Activated:Connect(function()
		self:Close()
	end))
	janitor:Add(back.Start.Activated:Connect(function()
		if not self.IsOpen then
			return
		end
		if self._countdown then
			self:_cancelStart() -- second tap = cancel
		else
			self:_startCountdown()
		end
	end))
	janitor:Add(function()
		self:_cancelStart()
	end, true)

	-- keep the front's mini card in step with what's saved
	for _, path in { PlayerData.Settings.SoloTheme, PlayerData.Inventory.DuelPack } do
		local ok, conn = pcall(path.Observe, function()
			if not self.IsOpen then
				local saved = setting(PlayerData.Settings.SoloTheme, Themes.DEFAULT)
				if Themes.Get(saved) then
					self._theme = saved
					self._tab = Themes.Get(saved).Tab
				end
			end
			self:RenderFront()
		end)
		if ok and conn then
			janitor:Add(conn)
		end
	end
	self:RenderFront()
	return self
end

-- Start counts down so the pick can still change; whatever is picked at 0 is played.
function SoloPicker:_startCountdown()
	self._countdown = task.spawn(function()
		for i = START_DELAY, 1, -1 do
			self._secondsLeft = i
			Sounds.Play("Countdown")
			self:_renderStart()
			task.wait(1)
		end
		self._countdown = nil
		self._secondsLeft = nil
		if not self.IsOpen then
			return
		end
		QueueRemote:Fire({ Request = "Solo", Theme = self:_playable(), Mix = self._mix })
		self:Close(true)
	end)
end

function SoloPicker:_cancelStart()
	if self._countdown then
		pcall(task.cancel, self._countdown)
	end
	self._countdown = nil
	self._secondsLeft = nil
	self:_renderStart()
end

-- the Start button: "START · GEN 4" / "21 songs · 7 rounds", or the countdown
function SoloPicker:_renderStart()
	local back = self._back
	if not back then
		return
	end
	local playing = Themes.Get(self:_playable())
	local info = describe(playing, duelPack())
	if self._secondsLeft then
		back.Start.BackgroundColor3 = YELLOW
		back.Start.Title.Text = `{string.upper(playing.Name)} · STARTING IN {self._secondsLeft}`
		back.Start.Sub.Text = "Tap to cancel · you can still change your pick"
	else
		back.Start.BackgroundColor3 = MINT
		back.Start.Title.Text = "START · " .. string.upper(playing.Name)
		back.Start.Sub.Text = `{info.Songs} songs · {DuelConstants.ROUNDS} rounds`
	end
end

-- the theme Start would play: the pick, or All songs if it has closed since
function SoloPicker:_playable(): string
	local theme = Themes.Get(self._theme)
	if theme and describe(theme, duelPack()).Open then
		return theme.Id
	end
	return Themes.DEFAULT
end

-- Play Solo on the front: "All songs" / "Gen 4" + mini card numeral
function SoloPicker:RenderFront()
	local playSolo = self._front and self._front:FindFirstChild("PlaySolo")
	if not playSolo then
		return
	end
	local theme = Themes.Get(self:_playable())
	local sub = playSolo:FindFirstChild("Sub")
	if sub then
		sub.Text = if theme.Id == Themes.DEFAULT then "Practice · pick a theme" else `Practice · {theme.Name}`
	end
	local mini = playSolo:FindFirstChild("MiniCard")
	if mini then
		mini.Numeral.Text = theme.Numeral
	end
end

function SoloPicker:Render()
	local back = self._back
	if not back then
		return
	end
	local pack = duelPack()

	for _, t in Themes.TABS do
		local b = back.Tabs[t]
		local on = t == self._tab
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then YELLOW else INK
	end

	-- cards for this tab, centred, the picked one bigger and lifted
	local list = Themes.ForTab(self._tab)
	self._cards = list
	local widths, total = {}, 0
	for i, theme in list do
		widths[i] = if theme.Id == self._theme then SEL_W else CARD_W
		total += widths[i]
	end
	total += CARD_GAP * math.max(0, #list - 1)
	local x = (DECK_W - total) / 2
	for i = 1, MAX_CARDS do
		local card, shadow = back.Deck["Card" .. i], back.Deck["Card" .. i .. "Shadow"]
		local theme = list[i]
		card.Visible = theme ~= nil
		shadow.Visible = theme ~= nil
		if theme then
			local info = describe(theme, pack)
			local sel = theme.Id == self._theme
			local w, h = widths[i], if sel then SEL_H else CARD_H
			local cx, cy = x + w / 2, DECK_H / 2 - (if sel then 6 else 0)
			x += w + CARD_GAP
			local rot = if sel or #list == 1 then 0 else TILT[i] or 0
			local drop = if sel then 6 else 3
			card.Size = UDim2.fromOffset(w, h)
			card.Position = UDim2.fromOffset(cx, cy)
			card.Rotation = rot
			shadow.Size = UDim2.fromOffset(w, h)
			shadow.Position = UDim2.fromOffset(cx + drop, cy + drop)
			shadow.Rotation = rot

			local accent = C(theme.Colour)
			card.Holo.Enabled = sel
			card.BackgroundColor3 = if info.Open then WHITE else PAPER
			card.Art.BackgroundColor3 = if info.Open then accent else accent:Lerp(GREY, 0.75)
			card.Art.Numeral.Text = theme.Numeral
			card.Art.Numeral.TextSize = if sel then 46 else 40
			card.Title.Text = theme.Name
			card.Groups.Text = info.Groups
			card.Count.Text = info.Count
			card.Count.BackgroundColor3 = if sel then INK else WHITE
			card.Count.TextColor3 = if sel then YELLOW else INK
			card.Sealed.Visible = not info.Open
			card.Sealed.Text = if theme.Id == Themes.PACK and not pack then "NO PACK" else "SEALED"
			card.Picked.Visible = sel
			card.Active = info.Open
		end
	end

	-- the switch: only when a duel pack is on and the theme isn't the pack itself
	local playing = Themes.Get(self:_playable())
	local mix = back.Mix
	mix.Visible = pack ~= nil and playing.Id ~= Themes.PACK
	if pack then
		mix.Toggle.BackgroundColor3 = if self._mix then MINT else PAPER
		mix.Toggle.Knob.Position = if self._mix then UDim2.new(1, -10, 0.5, 0) else UDim2.new(0, 10, 0.5, 0)
		local fit = 0
		for _, song in pack.Songs do
			if Themes.Matches(playing.Id, song) then
				fit += 1
			end
		end
		local detail = if fit == 0
			then "none of its songs fit this theme"
			elseif playing.Id == Themes.DEFAULT then `{pack.Name}`
			else `{pack.Name}, {playing.Name} songs only`
		mix.Label.Text = `Mix in my duel pack <font color="#5C566B">· {detail}</font>`
	end

	self:_renderStart()
end

-- Flip to the back: the front shrinks away, the back pops in.
function SoloPicker:Open()
	if not self._back then
		warn("[SoloPicker] Queue.Solo isn't built: run SoloPicker.Build in Studio")
		return
	end
	if self.IsOpen then
		return
	end
	self.IsOpen = true
	self:Render()
	local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local pop = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fronts = { self._front, self._frontShadow }
	for _, f in fronts do
		local s = f:FindFirstChild("Flip") or new("UIScale", { Name = "Flip" }, f)
		tween(s, quick, { Scale = 0.7 })
	end
	Sounds.Play("Open")
	task.delay(0.12, function()
		if not self.IsOpen then
			return
		end
		for _, f in fronts do
			f.Visible = false
		end
		for _, f in { self._back, self._backShadow } do
			f.Flip.Scale = 0.7
			f.Visible = true
			tween(f.Flip, pop, { Scale = 1 })
		end
	end)
end

-- Flip back to the front (instant = no animation, e.g. when the game starts)
function SoloPicker:Close(instant: boolean?)
	if not self._back or (not self.IsOpen and not instant) then
		return
	end
	self.IsOpen = false
	self:_cancelStart()
	local fronts = { self._front, self._frontShadow }
	local function showFront()
		for _, f in { self._back, self._backShadow } do
			f.Visible = false
		end
		for _, f in fronts do
			f.Visible = true
			local s = f:FindFirstChild("Flip") or new("UIScale", { Name = "Flip" }, f)
			if instant then
				s.Scale = 1
			else
				s.Scale = 0.7
				tween(s, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			end
		end
		self:RenderFront()
	end
	if instant then
		showFront()
		return
	end
	for _, f in { self._back, self._backShadow } do
		tween(f.Flip, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.7 })
	end
	task.delay(0.12, function()
		if not self.IsOpen then
			showFront()
		end
	end)
end

return SoloPicker
