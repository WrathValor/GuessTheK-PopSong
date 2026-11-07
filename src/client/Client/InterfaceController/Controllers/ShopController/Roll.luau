--| Shop · Roll
-- The shop's Roll tab (built by ./RollPage): the song roll replaces buying packs. Left: your
-- collection (songs pulled, per generation), the odds and how copies level a card up. Right:
-- ROLL ×1 / ROLL ×10 and the guaranteed-new counter. A roll is asked of the server
-- (Engine/RollService on RollRemote), which picks the songs; the reply flips the photocards
-- over on RollReveal: one big card for ×1, a 5 × 2 grid for ×10, each marked NEW or with its
-- new level. When the roll unlocks or upgrades a set title (packet.Title), the Title panel
-- ("TITLE UNLOCKED · CARAT" / "TITLE UPGRADED · CARAT" in gold) takes the place of the info line,
-- and EQUIP takes the place of ROLL AGAIN. A ×1 roll plays the full reveal from the "Roll motion"
-- boards (./RollMotion drives the effects): the mystery card pops in, its equaliser comes
-- alive with rings and particles, it floats and builds up, turns over on the sound's hit, then
-- shows the song in its group's colours (Songs: Gradient / Colour, through Modules/UI/GroupArt), the tier's finish and the collection result (NEW SONG,
-- DUPLICATE with the refund counting up, or the NOW GOLD! / NOW RAINBOW! upgrade).
-- The song plays after the turn (×10: the best card's) from its TimePosition, or from its
-- chorus when the roll made the card Gold / Rainbow, and keeps going until ROLL AGAIN, Done
-- or the song ends. Through the Song clips volume, with the lobby music paused under it
-- (GameController/Snippet + Client/BackgroundMusic).
-- ROLL AGAIN shrinks the last card away while the next roll is asked for. Rolls are off (buttons greyed, reason shown) when the "RollsAllowed" attribute
-- isn't true: paid random items are restricted for that account.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local RollConstants = require(ReplicatedStorage.Constants.RollConstants)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)

local Build = require(script.Parent.RollPage)
local RollMotion = require(script.Parent.RollMotion)
local Snippet = require(script.Parent.Parent.GameController.Snippet)
local BackgroundMusic = require(script.Parent.Parent.Parent.Parent.BackgroundMusic)

local RollRemote = Bridgenet.ReferenceBridge("RollRemote")
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote") -- EQUIP on a title moment

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local GOLD = C("F2C94C")
local GREY = C("EDE4D4")
local LILAC = C("B9A6FF")
local BLUE = C("9ED8F5")
local PINK = C("FF9EC4")
local MYSTERY_ART = C("5C566B") -- the art before the group colour comes in
local DIM = 0.05 -- the reveal's backdrop
local RAINBOW = { C("FFB3C7"), C("FFF1A8"), C("B8F0C8"), C("B5DDFF"), C("D8C4FF") }
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, RAINBOW[1]),
	ColorSequenceKeypoint.new(0.25, RAINBOW[2]),
	ColorSequenceKeypoint.new(0.5, RAINBOW[3]),
	ColorSequenceKeypoint.new(0.75, RAINBOW[4]),
	ColorSequenceKeypoint.new(1, RAINBOW[5]),
})

local FLIP_SQUASH = 0.1 -- the first half of a flip, before the face shows
local FLIP = TweenInfo.new(FLIP_SQUASH, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- The CardReveal sound ("Rare_Pull1") drives the reveal: a build-up from 0.1 s, a short dip at
-- 0.8–1.0 s, then the hit at 1.1 s. Cards shake through the build-up, hold still in the dip,
-- and turn face up exactly on the hit.
local REVEAL_SHAKE = 0.8 -- seconds of shaking, from when the sound starts
local REVEAL_HIT = 1.1 -- seconds into the sound when the hit lands (the face shows here)
-- ×1 timeline (seconds from the reply): card in at 0.2, sound at 0.3, so the hit (the turn)
-- lands at 1.4; song details 1.4–1.75, the collection result at 1.9, buttons at 2.4
local ONE_SOUND = 0.3
local ONE_HIT = ONE_SOUND + REVEAL_HIT
-- the song: from just after the hit (on an upgrade, as the upgrade lands)
local CHORUS_DELAY = 0.2
local FLIP_BACK = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local REPLY_TIMEOUT = 8

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function get(path, fallback)
	local ok, value = pcall(path.Get)
	return if ok and value ~= nil then value else fallback
end

local function owns(id: string): boolean
	local ok, yes = pcall(PlayerData.Inventory.Songs.Has, id)
	return ok and yes == true
end

local Roll = {}
Roll.__index = Roll

-- pages = Panel.Pages (holds Roll), shop = the Shop frame (holds RollReveal); toast(text)
-- shows a shop toast. Both frames are built in Studio by ./RollPage.
function Roll.new(pages: Instance, shop: Instance, janitor, toast: (string) -> ())
	local self = setmetatable({}, Roll)
	self._page, self._reveal = pages.Roll, shop.RollReveal
	self._reveal.Visible = false
	self._fx = RollMotion.new(self._reveal)
	self._toast = toast
	self._rolling = false
	self._last = 1 -- count of the last roll (ROLL AGAIN repeats it)
	ButtonScale.ApplyToDescendants(self._page)
	ButtonScale.ApplyToDescendants(self._reveal)

	-- the page's buttons do nothing while the reveal is up (ROLL AGAIN rolls from there)
	janitor:Add(self._page.Stage.RollOne.Activated:Connect(function()
		if not self._reveal.Visible then
			self:_roll(1)
		end
	end))
	janitor:Add(self._page.Stage.RollTen.Activated:Connect(function()
		if not self._reveal.Visible then
			self:_roll(10)
		end
	end))
	janitor:Add(self._reveal.Done.Activated:Connect(function()
		self:_closeReveal()
	end))
	janitor:Add(self._reveal.Again.Activated:Connect(function()
		-- the last card shrinks away while the next roll is asked for (the reveal stays open)
		if self:_roll(self._last) then
			self:_exitCard()
		end
	end))
	-- EQUIP the title a roll just unlocked / upgraded
	janitor:Add(self._reveal.Equip.Activated:Connect(function()
		local info = self._title
		if not info or not self._reveal.Equip.Active then
			return
		end
		ShopRemote:Fire({ Action = "EquipTitle", Id = info.Title })
		self._reveal.Equip.Label.Text = "EQUIPPED ✓"
		self._reveal.Equip.BackgroundColor3 = GREY
		self._reveal.Equip.Active = false
		Juice.Pop(self._reveal.Equip, 0.1)
	end))
	janitor:Add(RollRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Rolled" then
			self:_onRolled(packet)
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy
	local function refresh()
		if self._page.Visible and not self._reveal.Visible then
			self:_fill()
		end
	end
	for _, path in { PlayerData.Inventory.Songs, PlayerData.Inventory.DupesInRow } do
		janitor:Add(path.Observe(refresh))
	end
	janitor:Add(Players.LocalPlayer:GetAttributeChangedSignal("RollsAllowed"):Connect(refresh))
	return self
end

function Roll:_allowed(): boolean
	return Players.LocalPlayer:GetAttribute("RollsAllowed") == true
end

-- the shop calls this whenever the Roll tab is showing (and on coin changes)
function Roll:Fill()
	if not self._reveal.Visible then
		self:_fill()
	end
end

-- closing the shop puts the reveal away
function Roll:Hide()
	self._reveal.Visible = false
	self:_stopChorus(0.3)
end

-- [[ The song ]]

-- Loads the song's audio now (so it's ready by the turn); _playChorus() then plays it.
function Roll:_loadChorus(song)
	self:_stopChorus(0.2)
	local entry = song and song.Id and Songs.GetById(song.Id)
	if not entry or type(entry.MusicId) ~= "string" or entry.MusicId == "" then
		return
	end
	self._chorus = Snippet.new(entry, "Song")
end

-- chorus = true (the roll made it Gold / Rainbow) plays from ChorusPosition, else from the
-- snippet's TimePosition. It plays on until _stopChorus() or the song ends.
function Roll:_playChorus(chorus: boolean?)
	local clip = self._chorus
	if not clip or clip._started then
		return
	end
	clip._started = true
	if not self._ducked then
		self._ducked = true
		BackgroundMusic.Duck()
	end
	clip:PlayFull(not chorus) -- once loaded (a clip that never loads stays silent)
	if clip.Sound then
		clip.Sound.Ended:Once(function()
			if self._chorus == clip then
				self:_stopChorus(0) -- the song ran out: the lobby music comes back
			end
		end)
	end
end

-- fades the chorus out (ROLL AGAIN, Done, closing the shop, the next roll) and the lobby music back in
function Roll:_stopChorus(fade: number)
	local clip = self._chorus
	self._chorus = nil
	if clip then
		clip:FadeAndDestroy(fade)
	end
	if self._ducked then
		self._ducked = false
		task.delay(fade, function()
			if not self._ducked then
				BackgroundMusic.Resume()
			end
		end)
	end
end

function Roll:_fill()
	local page = self._page
	local coins = get(PlayerData.Currencies.Won, 0)

	local all = Songs.All
	local total, owned = #all, 0
	local genTotal, genOwned = {}, {}
	for _, song in all do
		local gen = song.Generation or "?"
		genTotal[gen] = (genTotal[gen] or 0) + 1
		if owns(song.Id) then
			owned += 1
			genOwned[gen] = (genOwned[gen] or 0) + 1
		end
	end
	local left = page.Collection
	left.Total.Count.Text = `{owned}<font size="20" color="#5C566B"> / {total}</font>`
	left.Total.Bar.Fill.Size = UDim2.fromScale(if total > 0 then owned / total else 0, 1)
	left.Total.Bar.Fill.Visible = owned > 0
	for i, gen in Build.GENS do
		local g = left["Gen" .. i]
		local t, o = genTotal[gen] or 0, genOwned[gen] or 0
		g.Owned.Text = `{o} / {t}`
		g.Bar.Fill.Size = UDim2.fromScale(if t > 0 then o / t else 0, 1)
		g.Bar.Fill.Visible = o > 0
	end
	local fresh = total - owned
	left.Odds.Text.Text = if fresh <= 0
		then `You own all {total} songs, so every roll adds a copy to one of them.`
		else `Every roll is 1 of all {total} songs, each equally likely. You own {owned}, so a <b>{fresh} in {total}</b> chance ({math.floor(fresh / total * 100 + 0.5)}%) of a new song.`
	left.Levels.Text.Text = `A duplicate is a copy: {RollConstants.GOLD_COPIES} copies make a <b>Gold</b> card, {RollConstants.RAINBOW_COPIES} a <b>Rainbow</b> one. Higher cards come up more in your duels. Each duplicate gives {RollConstants.DUPLICATE_REFUND} coins back.`

	local stage = page.Stage
	local allowed = self:_allowed()
	for name, cost in { RollOne = RollConstants.COST, RollTen = RollConstants.TEN_COST } do
		local b = stage[name]
		b.Cost.Amount.Text = if name == "RollTen" then `{commas(cost)} · save 10%` else commas(cost)
		local can = allowed and coins >= cost and not self._rolling
		b.BackgroundColor3 = if not allowed then GREY elseif name == "RollOne" then MINT else YELLOW
		b.Label.TextTransparency = if can then 0 else 0.45
		b.Cost.Amount.TextColor3 = if coins >= cost then INK else C("C0392B")
	end
	local dupes = get(PlayerData.Inventory.DupesInRow, 0)
	stage.Pity.Text = if not allowed
		then "Song rolls aren't available for your account."
		elseif fresh <= 0 then "You own every song: rolls now level your cards up."
		elseif dupes >= RollConstants.PITY then "<b>Your next roll is a guaranteed new song!</b>"
		else `Guaranteed new song after {RollConstants.PITY} dupes in a row · <b>{dupes} / {RollConstants.PITY}</b>`
end

-- true when the roll was sent
function Roll:_roll(count: number): boolean
	if self._rolling then
		return false
	end
	local stage = self._page.Stage
	local b = if count == 10 then stage.RollTen else stage.RollOne
	local cost = if count == 10 then RollConstants.TEN_COST else RollConstants.COST
	if not self:_allowed() or get(PlayerData.Currencies.Won, 0) < cost then
		Juice.Shake(b)
		Sounds.Play("Wrong")
		if self:_allowed() then
			self._toast("Not enough coins · win duels or get more in Coins")
		end
		return false
	end
	self._rolling = true
	self._last = count
	Sounds.Play("Click")
	Juice.Shake(stage.Deck.Top)
	self:_fill()
	RollRemote:Fire({ Action = "Roll", Count = count })
	local token = {}
	self._token = token
	task.delay(REPLY_TIMEOUT, function()
		if self._token == token and self._rolling then
			self._rolling = false
			if self._reveal.Visible then
				self:_closeReveal()
			end
			self:_fill()
		end
	end)
	return true
end

-- [[ The reveal ]]

-- the card's finish + level chip for `level`
local function paintLevel(card: Frame, level: string)
	TierShine.Apply(card, card.Rainbow, level, WHITE) -- Gold shines, Rainbow scrolls
	card.Level.Text = string.upper(level)
	card.Level.BackgroundColor3 = if level == "Normal" then CREAM else INK
	card.Level.TextColor3 = if level == "Gold" then GOLD elseif level == "Rainbow" then YELLOW else INK
end

local function setCard(card: Frame, pull)
	local song = pull.Song or {}
	local level = pull.Level or "Normal"
	GroupArt.Paint(card.Art, song) -- the group's gradient (or its pastel)
	card.SongName.Text = song.Name or "?"
	card.Meta.Text = if song.Year then `{song.Artist or "?"} · {song.Year}` else song.Artist or "?"
	paintLevel(card, level)
	local badge = card:FindFirstChild("Badge")
	if badge then
		badge.Visible = pull.New or pull.LevelUp
		badge.Text = if pull.New then "NEW" else `{string.upper(level)}!`
		badge.BackgroundColor3 = if pull.New then MINT else YELLOW
	end
	card.Back.Visible = true
end

-- Rattle a face-down card: it wobbles side to side, a little harder each time, for `duration`
-- seconds, then settles back and calls `done`. `ticks` plays a tick sound on every other wobble.
local RATTLE_STEP = 0.055
local function rattle(card: Frame, duration: number, ticks: boolean, done: (() -> ())?)
	local base = card:GetAttribute("BaseRotation")
	if base == nil then
		base = card.Rotation
		card:SetAttribute("BaseRotation", base)
	end
	local home = card:GetAttribute("BasePosition")
	if home == nil then
		home = card.Position
		card:SetAttribute("BasePosition", home)
	end
	task.spawn(function()
		local start = os.clock()
		local i = 0
		while os.clock() - start < duration and card.Parent do
			i += 1
			local p = math.clamp((os.clock() - start) / duration, 0, 1)
			local side = if i % 2 == 0 then 1 else -1
			local tween = TweenService:Create(card, TweenInfo.new(RATTLE_STEP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Rotation = base + side * (2 + 7 * p), -- 2° growing to 9°
				Position = home + UDim2.fromOffset(side * (1 + 3 * p), -2 * p), -- jitters and lifts a touch
			})
			tween:Play()
			if ticks and i % 2 == 0 then
				Sounds.Play("SpinTick", { Pitch = 1 + p * 0.4 })
			end
			tween.Completed:Wait()
		end
		card.Rotation = base
		card.Position = home
		if done then
			done()
		end
	end)
end

-- flip a face-down card over: squash to nothing, swap to the face, spring back
local function flip(card: Frame, after: (() -> ())?)
	local size = card:GetAttribute("FullSize") or card.Size
	card:SetAttribute("FullSize", size)
	local squash = TweenService:Create(card, FLIP, { Size = UDim2.new(0, 0, size.Y.Scale, size.Y.Offset) })
	squash.Completed:Once(function()
		card.Back.Visible = false
		TweenService:Create(card, FLIP_BACK, { Size = size }):Play()
		if after then
			after()
		end
	end)
	squash:Play()
end

-- the text and buttons under the cards wait until the cards have turned over
function Roll:_showFooter(on: boolean)
	local reveal = self._reveal
	local title = on and self._title ~= nil -- a title moment replaces the info + ROLL AGAIN
	reveal.Info.Visible = on and not title
	reveal.Pips.Visible = on and not title and reveal.Card.Visible
	reveal.Refund.Visible = on and not title and (self._refund or 0) > 0
	reveal.Title.Visible = title
	reveal.TitleShadow.Visible = title
	for name, visible in { Again = on and not title, Equip = title, Done = on } do
		reveal[name].Visible = visible
		reveal[name .. "Shadow"].Visible = visible
	end
	if title then
		Juice.Pop(reveal.Title, 0.12)
		Sounds.Play("Success")
	end
	if on then
		Juice.Stagger({ if title then reveal.Equip else reveal.Again, reveal.Done }, 0.05)
	end
end

-- fill the Title panel + EQUIP for packet.Title ({ Title, Tier, New, Set, Size })
function Roll:_setTitle(info)
	self._title = info
	if not info then
		return
	end
	local panel, set = self._reveal.Title, info.Set or "this"
	panel.Kicker.Text = if info.New then "TITLE UNLOCKED" else "TITLE UPGRADED"
	TitleChip.Paint(panel.Chip, info.Title, info.Tier)
	panel.Why.Text = if info.New
		then `You own every {set} song{if info.Size then ` ({info.Size} / {info.Size})` else ""}.`
		elseif info.Tier == "Gold" then `Every {set} card is Gold. Next: all Rainbow for the rainbow title.`
		else `Every {set} card is Rainbow. That's the top tier!`
	local ok, current = pcall(PlayerData.Inventory.Title.Get)
	local worn = ok and current == info.Title
	local equip = self._reveal.Equip
	equip.Label.Text = if worn then "EQUIPPED ✓" else `EQUIP {info.Title}`
	equip.BackgroundColor3 = if worn then GREY else MINT
	equip.Active = not worn
end

function Roll:_setFooter(pulls, refund: number)
	self._refund = refund
	local reveal = self._reveal
	reveal.Refund.Visible = refund > 0
	local dupes = 0
	for _, pull in pulls do
		if not pull.New then
			dupes += 1
		end
	end
	reveal.Refund.Row.Amount.Text = `+{refund} back for {if dupes == 1 then "the duplicate" else `{dupes} duplicates`}`
	reveal.Again.Label.Text = if self._last == 10 then "ROLL ×10 AGAIN" else "ROLL AGAIN"
	local cost = if self._last == 10 then RollConstants.TEN_COST else RollConstants.COST
	reveal.Again.BackgroundColor3 = if self:_allowed() and get(PlayerData.Currencies.Won, 0) >= cost then MINT else GREY
end

local function tw(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- a new play: anything still scheduled for the last one stops. at(t, fn) runs fn t seconds
-- after the play started (not after the call), so it can be called from later steps too.
function Roll:_newPlay(): (number, (() -> ())) -> ()
	local token = {}
	self._play = token
	local reveal = self._reveal
	local start = os.clock()
	return function(t: number, fn: () -> ())
		task.delay(math.max(t - (os.clock() - start), 0), function()
			if self._play == token and reveal.Visible then
				fn()
			end
		end)
	end
end

-- open the reveal (the backdrop fades in) or keep it open after ROLL AGAIN
function Roll:_openReveal()
	local reveal = self._reveal
	self._fx:Reset()
	reveal.Dim.BackgroundColor3 = C("2A2340")
	if not reveal.Visible then
		reveal.Dim.BackgroundTransparency = 1
		reveal.Visible = true
		tw(reveal.Dim, 0.2, { BackgroundTransparency = DIM })
	end
end

-- ROLL AGAIN: the info + buttons go, the card shrinks away, the glow dims
function Roll:_exitCard()
	self._play = nil
	self:_stopChorus(0.25)
	local reveal, fx = self._reveal, self._fx
	fx:StopRings()
	fx:ClearParticles(0.15)
	fx:Glow("A", nil, 1, 0.2)
	fx:Glow("B", nil, 1, 0.2)
	self._title = nil
	self:_showFooter(false)
	reveal.Banner.Visible = false
	tw(reveal.Dim, 0.2, { BackgroundTransparency = 0 })
	for _, card in { reveal.Card, reveal.Grid } do
		if card.Visible then
			local scale = card:FindFirstChild("Motion") or card:FindFirstChildOfClass("UIScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name = "Motion"
				scale.Parent = card
			end
			tw(scale, 0.18, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
				if self._play == nil then
					card.Visible = false
				end
				scale.Scale = 1
			end)
		end
	end
end

-- the banner drops in: NEW SONG! (mint), DUPLICATE (white), NOW GOLD! (yellow), NOW RAINBOW! (rainbow)
local function dropBanner(banner: TextLabel)
	banner.Visible = true
	Juice.SlideIn(banner, -40)
end

-- the collection result under the card: info, copy pips (the new copy pops), the refund counting up
function Roll:_showInfo(newPip: number?)
	local reveal = self._reveal
	if self._title then
		return -- the title panel takes this space (at the buttons)
	end
	reveal.Info.Visible = true
	Juice.SlideIn(reveal.Info, 8)
	reveal.Pips.Visible = true
	if newPip and newPip <= 5 then
		local pip = reveal.Pips["Pip" .. newPip]
		pip.BackgroundColor3 = pip:GetAttribute("On") or YELLOW
		Juice.Pop(pip, 0.35)
	end
	local refund = self._refund or 0
	if refund > 0 then
		reveal.Refund.Visible = true
		Juice.Pop(reveal.Refund, 0.08)
		Juice.CountUp(reveal.Refund.Row.Amount, 0, refund, function(n)
			return `+{math.floor(n)} back for the duplicate`
		end, 0.45)
		Sounds.Play("Coins", { Volume = 0.3 })
	end
end

function Roll:_showOne(pull, refund: number)
	local reveal, fx = self._reveal, self._fx
	local at = self:_newPlay()
	reveal.Grid.Visible = false
	local card = reveal.Card
	local scale = card.Motion
	local base = card:GetAttribute("BaseRotation")
	if base == nil then
		base = card.Rotation
		card:SetAttribute("BaseRotation", base)
	end

	local song = pull.Song or {}
	local level = pull.Level or "Normal"
	local copies = pull.Copies or 1
	-- an upgrade shows the card at its old level first, then turns it Gold / Rainbow
	local upgrade = if pull.LevelUp and not pull.New then level else nil
	local shown = if upgrade then (Cards.Level(copies - 1) or "Normal") else level
	local group = { Main = GroupArt.Main(song), Colours = GroupArt.Colours(song) }
	self:_loadChorus(song) -- loads while the card builds up

	setCard(card, pull)
	paintLevel(card, shown)
	group.Art = card.Art.BackgroundColor3 -- what setCard painted (white under a gradient)
	card.Art.BackgroundColor3 = MYSTERY_ART -- tinted down until the turn
	for _, name in { "SongName", "Meta" } do
		local label = card[name]
		local home = label:GetAttribute("Home")
		if home == nil then
			home = label.Position
			label:SetAttribute("Home", home)
		end
		label.Position = home
		label.TextTransparency = 1
	end
	card.Level.Visible = false

	local banner = reveal.Banner
	banner.Text = if pull.New then "NEW SONG!" elseif upgrade then `NOW {string.upper(upgrade)}!` else "DUPLICATE"
	banner.BackgroundColor3 = if pull.New then MINT elseif upgrade == "Rainbow" then WHITE elseif upgrade then YELLOW else WHITE
	banner.Rainbow.Enabled = upgrade == "Rainbow"
	banner.Visible = false

	local pack = song.Artist and Packs.Get(`Group:{song.Artist}`)
	local nextLevel, need = Cards.Next(copies)
	if pull.New then
		local have = if pack then #Packs.SongsFor(pack.Id, owns) else 0
		reveal.Info.Text = if pack
			then `You have <b>{have} / {#pack.Songs}</b> from {song.Artist} {if have >= #pack.Songs then ` · <b>{pack.Title}</b> title unlocked!` else ""}`
			else "it comes up more in your duels"
	else
		reveal.Info.Text = if nextLevel
			then `{copies} copies · <b>{need - copies} more</b> to {string.upper(nextLevel)}`
			else `You reached the top tier · it comes up more in your duels`
	end
	-- pips: the new copy fills in with the result (a NEW song's only pip shows straight away)
	for i = 1, 5 do
		local pip = reveal.Pips["Pip" .. i]
		local colour = if i >= RollConstants.RAINBOW_COPIES then C("B5DDFF") elseif i >= RollConstants.GOLD_COPIES then GOLD else YELLOW
		pip:SetAttribute("On", colour)
		local on = i < copies or (pull.New and i <= copies)
		pip.BackgroundColor3 = if on then colour else CREAM
	end
	self:_setFooter({ pull }, refund)
	self:_showFooter(false)
	self:_openReveal()
	card.Visible = false

	-- 0.2 · the mystery card pops in (65% → 105% → 100%, a little turn)
	at(0.2, function()
		card.Visible = true
		card.Back.Visible = true
		scale.Scale = 0.65
		card.Rotation = base - 6
		tw(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
		tw(card, 0.15, { Rotation = base + 2 })
		task.delay(0.15, function()
			tw(scale, 0.1, { Scale = 1 })
			tw(card, 0.1, { Rotation = base })
		end)
		fx:Glow("A", LILAC, 0.6, 0.25, 560)
	end)
	at(ONE_SOUND, function()
		Sounds.Play("CardReveal")
	end)
	-- 0.45 · the visualiser: bars, the note pulses, a gloss, rings, the first particles
	at(0.45, function()
		fx:Bars(true)
		fx:Pulse(true)
		fx:Gloss(0.4)
		fx:PulseRings({ LILAC, BLUE }, 0.4)
		fx:Orbit(1, 12, { LILAC, BLUE, CREAM })
		fx:Glow("A", nil, 0.45, 0.4, 600)
	end)
	-- 0.85 · build-up: it floats, more particles, faster rings, a brighter glow
	at(0.85, function()
		fx:Float(true)
		fx:Orbit(13, 24, { BLUE, LILAC, CREAM })
		fx:PulseRings({ LILAC, BLUE }, 0.22)
		fx:Glow("A", nil, 0.25, 0.45, 680)
	end)
	at(1.0, function()
		fx:Gloss(0.3)
	end)
	-- 1.12 · it comes forward, the particles edge out (the sound's dip)
	at(1.12, function()
		fx:Float(false)
		tw(scale, 0.18, { Scale = 1.03 })
		fx:Spread(0.75, 0.18)
	end)
	-- 1.3 · the turn: face up exactly on the hit (1.4)
	at(ONE_HIT - FLIP_SQUASH, function()
		fx:StopRings()
		fx:Pulse(false)
		flip(card, function()
			if self._play == nil then
				return
			end
			self:_revealFace(at, pull, shown, upgrade, group)
		end)
	end)
end

-- from the hit (1.4): flash, the waveform bursts, the group's colour comes in, the details
-- arrive, then the collection result and the buttons
function Roll:_revealFace(at, pull, shown: string, upgrade: string?, group)
	local reveal, fx = self._reveal, self._fx
	local card = reveal.Card
	local scale = card.Motion
	local t0 = ONE_HIT

	local burst = if shown == "Rainbow" then RAINBOW elseif shown == "Gold" then { GOLD, group.Main, YELLOW } else table.clone(group.Colours)
	fx:Flash(if shown == "Rainbow" then 0 elseif shown == "Gold" then 0.1 else 0.25)
	fx:Ring(CREAM, 1, 2.6, 0.55, 6)
	fx:Burst(burst, 1.8)
	fx:Glow("A", nil, 1, 0.3)
	fx:Glow("B", group.Main, 0.3, 0.3, 700)
	if shown == "Rainbow" then
		fx:Shake(9)
	elseif shown == "Gold" then
		fx:Shake(4)
	end
	scale.Scale = 1
	tw(card.Art, 0.25, { BackgroundColor3 = group.Art })

	-- the details, one after another, then a small bounce
	local name, meta = card.SongName, card.Meta
	name.Position = name:GetAttribute("Home") + UDim2.fromOffset(0, 12)
	tw(name, 0.2, { Position = name:GetAttribute("Home"), TextTransparency = 0 })
	at(t0 + 0.12, function()
		tw(meta, 0.2, { TextTransparency = 0 })
		tw(scale, 0.1, { Scale = 1.04 }).Completed:Once(function()
			tw(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end)
	at(t0 + 0.28, function()
		card.Level.Visible = true
		Juice.Pop(card.Level, 0.3)
	end)

	local done = t0 + 1 -- 2.4: the buttons
	if not upgrade then
		at(t0 + CHORUS_DELAY, function()
			self:_playChorus()
		end)
	end
	if upgrade == "Gold" then
		-- pause, the gold light crosses, the frame turns gold, gold particles, NOW GOLD!
		at(t0 + 0.6, function()
			fx:Sweep(C("FFF6D6"), 0.4)
			fx:Glow("B", GOLD, 0.2, 0.25, 760)
		end)
		at(t0 + 0.8, function()
			paintLevel(card, "Gold")
			Juice.Pop(card.Level, 0.35)
			fx:Burst({ GOLD, YELLOW, group.Main }, 1.5)
			self:_playChorus(true) -- the chorus comes in with the upgrade
			fx:Flash(0.45, C("FFE58A"))
			tw(scale, 0.1, { Scale = 1.05 }).Completed:Once(function()
				tw(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
			Sounds.Play("Success")
		end)
		at(t0 + 0.85, function()
			dropBanner(reveal.Banner)
			self:_showInfo(pull.Copies)
		end)
		done = t0 + 1.25
	elseif upgrade == "Rainbow" then
		-- darker, the card lifts, prism light, rainbow particles, NOW RAINBOW!, a final impact
		at(t0 + 0.5, function()
			tw(reveal.Dim, 0.2, { BackgroundColor3 = C("120F1E") })
			tw(card, 0.3, { Position = fx._cardHome + UDim2.fromOffset(0, -12) }, Enum.EasingStyle.Sine)
			fx:Glow("B", nil, 0.5, 0.2)
		end)
		at(t0 + 0.65, function()
			fx:Sweep(RAINBOW_SEQ, 0.5)
		end)
		at(t0 + 0.9, function()
			paintLevel(card, "Rainbow")
			Juice.Pop(card.Level, 0.35)
			fx:Burst(RAINBOW, 1.9)
			self:_playChorus(true)
			fx:Glow("B", LILAC, 0.15, 0.3, 820)
			Sounds.Play("Success")
		end)
		at(t0 + 1.0, function()
			tw(card, 0.18, { Position = fx._cardHome }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.18, function()
				fx:Shake(11)
				fx:Flash(0.3)
				tw(reveal.Dim, 0.3, { BackgroundColor3 = C("2A2340") })
			end)
			dropBanner(reveal.Banner)
		end)
		at(t0 + 1.15, function()
			self:_showInfo(pull.Copies)
		end)
		done = t0 + 1.45
	else
		-- 1.9 · NEW SONG! / DUPLICATE
		at(t0 + 0.5, function()
			dropBanner(reveal.Banner)
			self:_showInfo(if pull.New then nil else pull.Copies)
		end)
	end
	-- the effects settle, the buttons come in; the card stays until you choose
	at(done, function()
		fx:StopRings()
		fx:ClearParticles(0.4)
		fx:Glow("B", nil, 0.7, 0.5, 620)
		self:_showFooter(true)
	end)
end

function Roll:_showTen(pulls, refund: number)
	local reveal, fx = self._reveal, self._fx
	local at = self:_newPlay()
	reveal.Card.Visible = false
	reveal.Pips.Visible = false
	local grid = reveal.Grid
	grid.Visible = true
	local new, ups = 0, 0
	for i = 1, Build.TEN do
		local card = grid["Card" .. i]
		local pull = pulls[i]
		card.Visible = pull ~= nil
		if pull then
			setCard(card, pull)
			if pull.New then
				new += 1
			elseif pull.LevelUp then
				ups += 1
			end
		end
	end
	-- the song of the best card (its chorus when that's an upgrade): an upgrade (highest tier first), else the first new song,
	-- else the highest card
	local best, bestScore = nil, -1
	for i, pull in pulls do
		local rank = Cards.RANK[pull.Level or "Normal"] or 1
		local score = (if pull.LevelUp and not pull.New then 300 elseif pull.New then 200 else 100) + rank * 10 - i * 0.01
		if score > bestScore then
			best, bestScore = pull, score
		end
	end
	self:_loadChorus(best and best.Song)
	local banner = reveal.Banner
	banner.Text = `{#pulls} SONGS · {new} NEW`
	banner.BackgroundColor3 = if new > 0 then MINT else YELLOW
	banner.Rainbow.Enabled = false
	banner.Visible = false
	reveal.Info.Text = if ups > 0 then `<b>{ups}</b> card{if ups == 1 then "" else "s"} levelled up` else "Every duplicate adds a copy to that card"
	self:_setFooter(pulls, refund)
	self:_showFooter(false)
	self:_openReveal()
	-- one sound for the lot: every card shakes through the build-up, then they all turn
	-- around together on the hit
	at(0.2, function()
		Sounds.Play("CardReveal")
		fx:Glow("A", LILAC, 0.5, 0.4, 900)
		fx:PulseRings({ LILAC, BLUE }, 0.3)
		for i = 1, #pulls do
			rattle(grid["Card" .. i], REVEAL_SHAKE, false)
		end
	end)
	at(0.2 + REVEAL_HIT - FLIP_SQUASH, function()
		fx:StopRings()
		for i = 1, #pulls do
			flip(grid["Card" .. i])
		end
	end)
	at(0.2 + REVEAL_HIT, function()
		fx:Flash(0.25)
		fx:Ring(CREAM, 1, 3.2, 0.6, 6)
		fx:Burst({ PINK, YELLOW, BLUE, LILAC, MINT, CREAM }, 2.3)
		task.delay(CHORUS_DELAY, function()
			if reveal.Visible then
				self:_playChorus(best ~= nil and best.LevelUp == true and not best.New)
			end
		end)
		fx:Glow("A", nil, 0.75, 0.4, 900)
		dropBanner(banner)
		Juice.Stagger({ grid.Card1, grid.Card2, grid.Card3, grid.Card4, grid.Card5, grid.Card6, grid.Card7, grid.Card8, grid.Card9, grid.Card10 }, 0.03, 0.9)
		self:_showFooter(true)
	end)
end

function Roll:_onRolled(packet)
	self._rolling = false
	self._token = nil
	if not packet.Ok then
		Sounds.Play("Wrong")
		if self._reveal.Visible then
			self:_closeReveal()
		end
		self:_fill()
		self._page.Stage.Pity.Text = `<b>{packet.Text or "Couldn't roll"}</b>`
		return
	end
	local pulls = packet.Pulls or {}
	self:_setTitle(packet.Title)
	if #pulls == 1 then
		self:_showOne(pulls[1], packet.Refund or 0)
	else
		self:_showTen(pulls, packet.Refund or 0)
	end
end

function Roll:_closeReveal()
	self._play = nil
	self:_stopChorus(0.4)
	self._reveal.Visible = false
	self._fx:Stop()
	self._title = nil
	self._reveal.Title.Visible = false
	self._reveal.TitleShadow.Visible = false
	self:_fill()
end

return Roll
