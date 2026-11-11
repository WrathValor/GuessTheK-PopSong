--| StreetScreens
-- Draws the screens around the street from the server's feed (Engine/StreetScreens publishes
-- it as JSON on Map.Landmarks.BigScreen's "Feed" attribute).
--   • Jumbotron (Map.Landmarks.BigScreen.SurfaceGui.Jumbotron): one white panel in the frames'
--     style (yellow title tag, heading, grey subtitle) whose content takes turns every
--     SLIDE_SECONDS: LIVE NOW · IN THE SHOP NOW · SERVER HIGHLIGHTS · TOP ON THIS SERVER.
--     IN THE SHOP NOW flips through the shop's 6-hour rotation a page at a time
--     (SHOP_PAGE_SECONDS each): stage sets → photocards → mics → stages, each card showing the
--     real thing (CosmeticView 3D models, the photocard skin with your avatar).
--     Slides with nothing to show are skipped.
--   • Walk-up machines scattered round the map (Blender models), each with a screen and a
--     prompt that opens its frame:
--       Fan Club   (Street.StreetProps, the red + blue vending machines under the FAN CLUB
--                  sign) red: join the group → claim its 3 rewards (same flow as the Join the
--                  Group board); blue: Roblox's favourite prompt (no reward: Roblox doesn't
--                  allow rewarding favourites). Each player sees their own state.
--       SongRoll   (Map.StreetMachines.SongRoll, by the PC Room) recent Gold / Rainbow pulls
--                  ticker on the lower screen; the window is a Display SurfaceGui  → Roll
--       Merch      (Map.StreetMachines.Merch) this week's featured UGC item     → UGC
--       PhotoBooth (Map.StreetMachines.PhotoBooth) YOUR card: photo, title, level, stats
--                  (each player sees their own)                                → Profile
-- All the UI is built in Studio; this only fills it in, switches slides and adds the prompts.

local Players = game:GetService("Players")
local C = Color3.fromHex
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local GroupService = game:GetService("GroupService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Constants.StreetScreens)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local Levels = require(ReplicatedStorage.Modules.Levels)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local InterfaceController = require(script.Parent.InterfaceController)

local LOCAL_PLAYER = Players.LocalPlayer
local PROMPT_DISTANCE = 9
local RARITY = { Common = C("FFFFFF"), Uncommon = C("A7E9B8"), Rare = C("9ED8F5"), Epic = C("B9A6FF"), Legendary = C("FFE07A") }

-- each slide: its title tag, heading and grey subtitle (the frames' recipe: one white panel)
local SLIDES = {
	{ Frame = "SlideLive", Tag = "LIVE NOW" },
	{ Frame = "SlideShop", Tag = "IN THE SHOP NOW" },
	{ Frame = "SlideHighlights", Tag = "SERVER HIGHLIGHTS", Heading = "Big moments on this server", Sub = "Comebacks, big pulls and win streaks, as they happen" },
	{ Frame = "SlideTop", Tag = "TOP ON THIS SERVER", Heading = "Most wins on this server", Sub = "Win duels to get your card up here" },
}
-- IN THE SHOP NOW pages: what's in this rotation, which art frame on the card shows it
-- (Art / ArtCard / ArtMic / ArtStage – each keeps its own 3D view, so flipping is free)
local SHOP_PAGES = {
	{ Kind = "Set", Art = "Art", Heading = "Stage sets in rotation", List = function(t)
		return ShopCatalog.Rotation(t)
	end },
	{ Kind = "Photocard", Art = "ArtCard", Heading = "Photocards in rotation", List = function(t)
		return ShopCatalog.StyleRotation(t)
	end },
	{ Kind = "Mic", Art = "ArtMic", Heading = "Mics in rotation", List = function(t)
		return ShopCatalog.ItemRotation("Mic", t)
	end },
	{ Kind = "Stage", Art = "ArtStage", Heading = "Stages in rotation", List = function(t)
		return ShopCatalog.ItemRotation("Stage", t)
	end },
}
local CHIP = { COMEBACK = { "ENCORE", C("FF9EC4") }, ["RAINBOW PULL"] = { "RAINBOW", C("FFE07A") }, STREAK = { "STREAK", C("A7E9B8") } }
local LABEL = { COMEBACK = "COMEBACK", ["RAINBOW PULL"] = "ROLL", STREAK = "STREAK" }

local StreetScreens = {}

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

local function ago(at: number): string
	local s = math.max(0, os.time() - (at or os.time()))
	if s < 60 then
		return "just now"
	elseif s < 3600 then
		return `{math.floor(s / 60)} min ago`
	end
	return `{math.floor(s / 3600)} h ago`
end

-- [[ Jumbotron ]]

local Jumbo = {}
Jumbo.__index = Jumbo

function Jumbo.new(content: Frame)
	local self = setmetatable({}, Jumbo)
	self.Content = content
	self.Tag = content:WaitForChild("Tag"):WaitForChild("Label")
	self.Heading = content:WaitForChild("Heading")
	self.Subtitle = content:WaitForChild("Subtitle")
	self.Feed = {}
	self.Index = 0
	self.Page = 1
	return self
end

function Jumbo:_has(i: number): boolean
	local f = self.Feed
	if i == 1 then
		return f.Live ~= nil
	elseif i == 2 then
		return #ShopCatalog.Rotation(ShopCatalog.ShopTime()) > 0
	elseif i == 3 then
		return f.Highlights ~= nil and #f.Highlights > 0
	end
	return f.Top ~= nil and #f.Top > 0
end

-- the heading + subtitle for slide i (some depend on the feed)
function Jumbo:_titles(i: number): (string, string)
	if i == 1 then
		local live = self.Feed.Live
		if not live then
			return "", ""
		end
		return `Live on {live.Stage}`, `Round {live.Round} of {live.Rounds} · the closest game on the server · walk over to watch`
	elseif i == 2 then
		local t = ShopCatalog.ShopTime()
		local _, windowEnd = ShopCatalog.RotationWindow(t)
		return SHOP_PAGES[self.Page].Heading,
			`Restocks in {ShopCatalog.Countdown(windowEnd - t)} · open the Shop to grab one`
	end
	return SLIDES[i].Heading, SLIDES[i].Sub
end

function Jumbo:_fillLive()
	local live = self.Feed.Live
	if not live then
		return
	end
	local s = self.Content.SlideLive
	s.LeftName.Text = live.A.Name
	s.RightName.Text = live.B.Name
	s.LeftCard.Face.Avatar.Image = headshot(live.A.UserId)
	s.RightCard.Face.Avatar.Image = headshot(live.B.UserId)
	s.LeftSub.Text = live.Stage
	s.RightSub.Text = live.Stage
	s.ScoreRow.LeftScore.Text = tostring(live.A.Score)
	s.ScoreRow.RightScore.Text = tostring(live.B.Score)
	local encore = (live.Mult or 1) > 1
	s.Round.Text = if encore then `ENCORE ×{live.Mult}` else `ROUND {live.Round}`
	s.Round.BackgroundColor3 = if encore then C("FF9EC4") else C("FFE07A")
end

-- the shop page on screen (self.Page): the four things in this 6-hour rotation
function Jumbo:_fillShop()
	local page = SHOP_PAGES[self.Page]
	local s = self.Content.SlideShop
	local list = page.List(ShopCatalog.ShopTime())
	for i = 1, 4 do
		local box = s:FindFirstChild("Card" .. i)
		local item = list[i]
		box.Visible = item ~= nil
		if not item then
			continue
		end
		local face = box.Card.Face
		for _, p in SHOP_PAGES do
			face[p.Art].Visible = p == page
		end
		local art = face[page.Art]
		local price, rarity, chip
		if page.Kind == "Photocard" then
			price = ShopCatalog.StylePrice(item.Id, "Photocard")
			rarity = if item.Animated then "ANIMATED" else "PHOTOCARD"
			chip = if item.Animated then C("FF9EC4") else C("FFFFFF")
			art.BackgroundColor3 = item.Fill
			local card = art.Photocard
			if card:GetAttribute("PhotocardId") ~= item.Id then
				SeasonArt.PaintPhotocard(card, item.Id)
			end
			card.Photo.Avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
		else
			price = item.Price
			rarity = string.upper(item.Rarity or "")
			chip = RARITY[item.Rarity] or C("FFFFFF")
			-- the drawn stand-in in the item's colours (shows until / unless the model loads)
			art.BackgroundColor3 = C(item.Bg or "EFEAFF")
			local scene = art:FindFirstChild("Scene")
			if scene then
				scene.Stage.Visible = page.Kind ~= "Mic"
				scene.Platform.Visible = page.Kind ~= "Mic"
				scene.Stand.Visible = page.Kind ~= "Stage"
				scene.Mic.Visible = page.Kind ~= "Stage"
				scene.Stage.BackgroundColor3 = C(item.Stage or "FF5A4E")
				scene.Platform.BackgroundColor3 = C(item.Platform or "FFE07A")
				scene.Mic.BackgroundColor3 = C(item.Mic or "FFE07A")
			end
			CosmeticView.Show(art, page.Kind, item.Id) -- the real model (+ your avatar on pads)
		end
		face.Title.Text = (string.gsub(item.Name, " Set$", "")) -- "Cherry Blossom" fits, "… Set" doesn't
		face.Artist.Text = `{ShopCatalog.Format(price or 0)} coins`
		box.Rarity.Text = rarity
		box.Rarity.BackgroundColor3 = chip
	end
end

-- flip the shop slide to page n (1 = sets … 4 = stages)
function Jumbo:SetPage(n: number)
	if self.Page == n then
		return
	end
	self.Page = n
	self:_fillShop()
	if self.Index == 2 then
		self.Heading.Text, self.Subtitle.Text = self:_titles(2)
	end
end

function Jumbo:_fillHighlights()
	local s = self.Content.SlideHighlights
	local list = self.Feed.Highlights or {}
	for i = 1, 3 do
		local box = s:FindFirstChild("Row" .. i)
		local h = list[i]
		box.Visible = h ~= nil
		if h then
			local face = box.Row.Face
			face.Label.Text = `{LABEL[h.Kind] or h.Kind} · {string.upper(ago(h.At))}`
			face.Text.Text = h.Text
			local chip = CHIP[h.Kind]
			box.Chip.Text = if chip then chip[1] else h.Kind
			box.Chip.BackgroundColor3 = if chip then chip[2] else C("FFFFFF")
		end
	end
end

function Jumbo:_fillTop()
	local s = self.Content.SlideTop
	local list = self.Feed.Top or {}
	for i = 1, 3 do
		local col = s:FindFirstChild("P" .. i)
		local p = list[i]
		col.Visible = p ~= nil
		if p then
			col.PlayerName.Text = p.Name
			col.Wins.Text = `{p.Wins} win{if p.Wins == 1 then "" else "s"}`
			col.Card.Face.Avatar.Image = headshot(p.UserId)
		end
	end
end

function Jumbo:Refresh()
	self:_fillLive()
	self:_fillShop()
	self:_fillHighlights()
	self:_fillTop()
	if self.Index > 0 then
		self.Heading.Text, self.Subtitle.Text = self:_titles(self.Index)
	end
end

function Jumbo:Show(i: number)
	self.Index = i
	if i == 2 then
		self.Page = 1 -- always opens on stage sets
		self:_fillShop() -- the rotation turns over on its own clock, not the feed's
	end
	for n, slide in SLIDES do
		self.Content[slide.Frame].Visible = n == i
	end
	self.Tag.Text = SLIDES[i].Tag
	self.Heading.Text, self.Subtitle.Text = self:_titles(i)
end

-- the next slide that has something to show (or stay put if none do)
function Jumbo:Next()
	for step = 1, #SLIDES do
		local i = (self.Index + step - 1) % #SLIDES + 1
		if self:_has(i) then
			self:Show(i)
			return
		end
	end
end

function Jumbo:SetFeed(feed)
	self.Feed = feed
	self:Refresh()
	-- the slide on screen ran out of things to show (e.g. the live duel ended): move on
	if self.Index == 0 or not self:_has(self.Index) then
		self:Next()
	end
end

-- [[ Walk-up machines ]]

local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

local function commas(n: number): string
	return ShopCatalog.Format(n)
end

-- a "press E" prompt on `part` that runs `onTrigger`
local function promptDo(part: BasePart, action: string, object: string, onTrigger: () -> ()): ProximityPrompt
	local p = part:FindFirstChild("StreetPrompt") or Instance.new("ProximityPrompt")
	p.Name = "StreetPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.MaxActivationDistance = PROMPT_DISTANCE
	p.RequiresLineOfSight = false
	p.HoldDuration = 0
	p.Parent = part
	p.Triggered:Connect(onTrigger)
	return p
end

-- a "press E" prompt on `part` that opens the interface frame `frame` (with `...`)
local function prompt(part: BasePart, action: string, object: string, frame: string, ...)
	local args = table.pack(...)
	promptDo(part, action, object, function()
		InterfaceController:Open(frame, table.unpack(args, 1, args.n))
	end)
end

-- [[ Fan Club: the red + blue vending machines ]]

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")
local GROUP = RewardsCatalog.GROUP

-- red: the Cta + prompt for each step (the same three steps as the Join the Group board)
local JOIN = {
	Join = { Cta = "PRESS E · JOIN", Bg = "A7E9B8", Action = "Join the group" },
	Claim = { Cta = "PRESS E · CLAIM", Bg = "FFE07A", Action = "Claim rewards" },
	Claimed = { Cta = "CLAIMED · THANK YOU", Bg = "FFFFFF", Action = nil },
}

local function fanGroup(front: BasePart)
	local gui = front:WaitForChild("FanGroup") :: SurfaceGui
	local panel = gui:WaitForChild("Panel")
	-- the real Group Exclusive stage with your avatar on it (like the Join the Group board);
	-- a 3D view only draws from PlayerGui, so the panel moves there, still on the machine
	gui.Adornee = front
	gui.ResetOnSpawn = false
	gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
	CosmeticView.Show(panel.Art, "Stage", GROUP.Stage) -- the drawn reward tiles until it loads
	local inGroup, busy = false, false
	local p: ProximityPrompt
	local function claimed(): boolean
		local ok, v = pcall(PlayerData.Rewards.Claimed.Has, GROUP.ClaimedKey)
		return ok and v == true
	end
	local function state(): string
		return if claimed() then "Claimed" elseif inGroup then "Claim" else "Join"
	end
	local function paint()
		local s = JOIN[state()]
		panel.Cta.Text = if busy then "…" else s.Cta
		panel.Cta.BackgroundColor3 = C(s.Bg)
		p.ActionText = s.Action or ""
		p.Enabled = s.Action ~= nil
	end
	p = promptDo(front, "Join the group", "Fan Club", function()
		if busy then
			return
		end
		local now = state()
		if now == "Claim" then
			RewardsRemote:Fire({ Action = "ClaimGroup" })
		elseif now == "Join" then
			busy = true
			paint()
			task.spawn(function()
				local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, GROUP.GroupId)
				AnalyticsClient.Event("GroupJoinPrompt", 1, if not ok then "Error"
					elseif status == Enum.GroupMembershipStatus.Joined then "Joined"
					elseif status == Enum.GroupMembershipStatus.AlreadyMember then "AlreadyMember"
					elseif status == Enum.GroupMembershipStatus.JoinRequestPending then "Pending"
					else "Cancelled")
				busy = false
				if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
					inGroup = true
					RewardsRemote:Fire({ Action = "ClaimGroup" }) -- straight to the reward
				end
				paint()
			end)
		end
	end)
	pcall(function()
		PlayerData.Rewards.Claimed.Observe(paint)
	end)
	task.spawn(function()
		local ok, member = pcall(LOCAL_PLAYER.IsInGroup, LOCAL_PLAYER, GROUP.GroupId)
		inGroup = ok and member == true
		paint()
	end)
	paint()
end

-- blue: Roblox's favourite prompt (no reward), the star breathing on the screen
local function fanFavourite(front: BasePart)
	local panel = front:WaitForChild("FanFavourite"):WaitForChild("Panel")
	local favourited = false
	local p: ProximityPrompt
	local function paint()
		panel.Cta.Text = if favourited then "FAVOURITED · THANK YOU" else "PRESS E · FAVOURITE"
		panel.Cta.BackgroundColor3 = if favourited then C("FFFFFF") else C("9ED8F5")
		p.Enabled = not favourited
	end
	local function check()
		local ok, fav = pcall(AvatarEditorService.GetFavoriteAsync, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset)
		favourited = ok and fav == true
		paint()
	end
	p = promptDo(front, "Favourite", "Fan Club", function()
		pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	AvatarEditorService.PromptSetFavoriteCompleted:Connect(function()
		task.wait(0.5)
		check()
	end)
	task.spawn(check)
	paint()
	local pulse = panel.Art.Star:FindFirstChild("Pulse")
	if pulse then
		TweenService:Create(pulse, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 }):Play()
	end
end

local function fanClub(props: Instance)
	for _, front in props:GetChildren() do
		if front.Name ~= "VendingFront" then
			continue
		end
		if front:FindFirstChild("FanGroup") then
			task.spawn(fanGroup, front)
		elseif front:FindFirstChild("FanFavourite") then
			task.spawn(fanFavourite, front)
		end
	end
end

local function songRoll(machine: Model)
	local line = machine:WaitForChild("Screen"):WaitForChild("Screen"):WaitForChild("Panel"):WaitForChild("Ticker"):WaitForChild("Line")
	prompt(machine:WaitForChild("Base"), "Roll a song", "Song Roll", "Roll")
	local i = 0
	task.spawn(function()
		while true do
			local pulls = StreetScreens.Feed and StreetScreens.Feed.Pulls or {}
			if #pulls > 0 then
				i = i % #pulls + 1
				line.Text = `★ {pulls[i]}`
			else
				line.Text = "Pull a Gold or Rainbow card to get up here!"
			end
			task.wait(3)
		end
	end)
end

local function merch(machine: Model, feed)
	local panel = machine:WaitForChild("Screen"):WaitForChild("Screen"):WaitForChild("Panel")
	local item = feed and feed.Merch
	if not item then
		panel.ItemName.Text = "New merch soon"
		panel.Artist.Text = ""
		panel.Price.Text = "UGC shop"
		panel.More.Text = ""
		panel.Thumb.Image = ""
		return
	end
	panel.ItemName.Text = item.Name
	panel.Artist.Text = item.Artist or ""
	panel.Price.Text = `{commas(item.Price or 0)} Robux`
	panel.More.Text = if (item.Count or 0) > 1 then `+ {item.Count - 1} more in the UGC shop` else "In the UGC shop"
	panel.Thumb.Image = `rbxthumb://type=Asset&id={item.Id}&w=150&h=150`
end

local function booth(machine: Model)
	local panel = machine:WaitForChild("Screen"):WaitForChild("Screen"):WaitForChild("Panel")
	prompt(machine:WaitForChild("Body"), "Check your card", "Photo Booth", "Profile")
	local card = panel.Card
	card.Photo.Image = `rbxthumb://type=AvatarHeadShot&id={LOCAL_PLAYER.UserId}&w=150&h=150`
	card.PlayerName.Text = LOCAL_PLAYER.DisplayName
	local function paint()
		local stats = PlayerData.Statistics
		local level = Levels.FromXP(get(PlayerData.Player.XP, 0))
		panel.Chips.Title.Text = LOCAL_PLAYER:GetAttribute("Title") or HUDConstants.DEFAULT_TITLE
		panel.Chips.Level.Text = `Lv {level}`
		local wins = get(stats.Wins, 0)
		panel.Chips.Wins.Text = `{commas(wins)} win{if wins == 1 then "" else "s"}`
		panel.Stats.Text = `Solo best {get(stats.SoloBest2, 0)} · best streak {get(stats.HighestStreak, 0)}`
	end
	paint()
	for _, path in { PlayerData.Player.XP, PlayerData.Statistics.Wins, PlayerData.Statistics.SoloBest2, PlayerData.Statistics.HighestStreak } do
		pcall(function()
			path.Observe(paint)
		end)
	end
	LOCAL_PLAYER:GetAttributeChangedSignal("Title"):Connect(paint)
end

-- [[ Start ]]

function StreetScreens.Start()
	task.spawn(function()
		local map = workspace:WaitForChild("Map")
		local screen = map:WaitForChild("Landmarks"):WaitForChild("BigScreen")
		local gui = screen:WaitForChild("SurfaceGui") :: SurfaceGui
		local content = gui:WaitForChild("Jumbotron"):WaitForChild("Content")
		-- Roblox doesn't draw ViewportFrames (the shop cards' 3D models) or CanvasGroups (the
		-- photocard effects) in a SurfaceGui that lives in Workspace: move it into PlayerGui,
		-- still drawn on the screen part through Adornee
		gui.Adornee = screen
		gui.ResetOnSpawn = false
		gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
		local jumbo = Jumbo.new(content)
		StreetScreens.Jumbo = jumbo

		local function read()
			local raw = screen:GetAttribute("Feed")
			if type(raw) ~= "string" then
				return
			end
			local ok, feed = pcall(HttpService.JSONDecode, HttpService, raw)
			if ok and type(feed) == "table" then
				jumbo:SetFeed(feed)
				StreetScreens.Feed = feed
				if StreetScreens.OnFeed then
					StreetScreens.OnFeed(feed)
				end
			end
		end
		screen:GetAttributeChangedSignal("Feed"):Connect(read)
		read()

		-- the walk-up machines (each one optional: a missing machine just isn't wired)
		task.spawn(function()
			local props = map:FindFirstChild("Street") and map.Street:FindFirstChild("StreetProps")
			if props then
				fanClub(props)
			end
		end)
		task.spawn(function()
			local machines = map:WaitForChild("StreetMachines", 10)
			if not machines then
				return
			end
			local g = machines:FindFirstChild("SongRoll")
			if g then
				task.spawn(songRoll, g)
			end
			local b = machines:FindFirstChild("PhotoBooth")
			if b then
				task.spawn(booth, b)
			end
			local m = machines:FindFirstChild("Merch")
			if m then
				prompt(m:WaitForChild("Counter"), "Browse merch", "Merch Pop-up", "UGC")
				merch(m, StreetScreens.Feed)
				local previous = StreetScreens.OnFeed
				StreetScreens.OnFeed = function(feed)
					if previous then
						previous(feed)
					end
					merch(m, feed)
				end
			end
		end)

		local since = 0
		while true do
			task.wait(1)
			since += 1
			-- the countdown + "x min ago" tick along between feed updates
			if jumbo.Index == 2 or jumbo.Index == 3 then
				jumbo:Refresh()
			end
			-- the shop slide stays up for all its pages, flipping every SHOP_PAGE_SECONDS
			local length = Constants.SLIDE_SECONDS
			if jumbo.Index == 2 then
				length = Constants.SHOP_PAGE_SECONDS * #SHOP_PAGES
				jumbo:SetPage(math.min(since // Constants.SHOP_PAGE_SECONDS + 1, #SHOP_PAGES))
			end
			if since >= length then
				since = 0
				jumbo:Next()
			end
		end
	end)
end

return StreetScreens
