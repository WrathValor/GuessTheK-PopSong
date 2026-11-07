--| IndexController
-- The Index (Interface.Frames.Index, built by ./Build from the "Song Index redesign"): your song
-- collection. It only fills up from the song roll (the shop's Songs tab); every song is one of:
--   • Missing – a quiet locked placeholder (lock tile + blank line): roll it to collect it
--   • Owned   – pulled from a roll (Inventory.Songs): a tile with the song's initials (one pastel
--               per group), name, "artist · gen", its card level and copies ("×2 owned",
--               Modules/Library/Cards). Normal is white, Gold a gold card, and only Rainbow
--               gets the pastel "Level" gradient.
-- Rail: All songs, then the companies by song count (Other last), each with a progress bar.
-- Content: heading + "22 of 82 collected" + the Collected bar, Gold / Rainbow stat cards, one
-- row (as in the redesign): chips that scroll sideways (the companies on All songs, a
-- company's groups otherwise) with a fade on the right, the All | Owned toggle and the A–Z
-- sort, then 12 cards a page and the pager in the footer.
-- On a set (a group, or a company with no group picked) the footer shows title reward progress:
-- own them all → all Gold → all Rainbow → done.
-- ♪ ROLL SONGS opens the shop's Songs tab. Nothing can be bought here.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local PAPER = C("F3EBDD")
local DASH = C("C9BFAE")
local GREEN = C("6FD08C")
local TRACK = C("EDE4D4")
local TRACK_ON = C("3A3550") -- a rail bar's track on the selected (dark) row
local MUTED = C("5C566B")
local CHIP_LINE = C("DCD3C4") -- an unpicked chip's outline
local THUMB_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PER_PAGE = Build.PER_PAGE
local SHOWS = { "All", "Owned" } -- the All | Owned toggle (button names in Content.Show)
local SORTS = { "A–Z", "Gen" }
local FILL_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ---------------------------------- Class --------------------------------- --
local Index = {}
Index.__index = Index

function Index.new()
	local self = setmetatable({}, Index)
	self.Name = "Index"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._row = 1
	self._page = 1
	self._group = nil :: string? -- a group picked inside a company row (nil = all its groups)
	self._show = 1
	self._sort = 1
	return (self :: any) :: UITypes.Controller
end

local function has(path, id: string): boolean
	local ok, yes = pcall(path.Has, id)
	return ok and yes == true
end

local function owned(song): boolean
	return has(PlayerData.Inventory.Songs, song.Id)
end

local function genNumber(song): number
	return tonumber(tostring(song.Generation or ""):match("%d+")) or 99
end

-- "Airplane pt.2" → "AP", "BOOMBAYAH" → "B"
local function initials(name: string): string
	local out = ""
	for word in string.gmatch(name, "[%w]+") do
		out ..= string.upper(string.sub(word, 1, 1))
		if #out == 2 then
			break
		end
	end
	return if out == "" then "♪" else out
end

-- rail rows: All songs, then one per company (most songs first, Other last)
function Index:_rows()
	local rows = { { Label = "All songs", Songs = Songs.All, Kind = "All" } }
	local byCompany, order = {}, {}
	for _, song in Songs.All do
		local company = song.Company or "Other"
		if not byCompany[company] then
			byCompany[company] = {}
			table.insert(order, company)
		end
		table.insert(byCompany[company], song)
	end
	table.sort(order, function(a, b)
		if (a == "Other") ~= (b == "Other") then
			return b == "Other"
		end
		if #byCompany[a] ~= #byCompany[b] then
			return #byCompany[a] > #byCompany[b]
		end
		return a < b
	end)
	for _, company in order do
		table.insert(rows, { Label = company, Songs = byCompany[company], Kind = "Company" })
	end
	return rows
end

-- the groups in a company row, A–Z
local function groupsOf(row): { string }
	local seen, out = {}, {}
	for _, song in row.Songs do
		if song.Artist and not seen[song.Artist] then
			seen[song.Artist] = true
			table.insert(out, song.Artist)
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

local function countIn(list): number
	local n = 0
	for _, song in list do
		if owned(song) then
			n += 1
		end
	end
	return n
end

-- [[ Drawing ]]

-- The chip row: on All songs it lists the companies (a tap opens that company), on a company
-- its groups (a tap narrows the cards to that group). First chip = "All …". The row scrolls
-- sideways; the fade on the right shows while there's more to scroll to.
function Index:_fillChips(rows, row)
	local frame = self._frame.Panel.Content.Groups
	local strip = frame.Chips
	local items, first = {}, "All groups"
	if row.Kind == "All" then
		first = "All companies"
		for i = 2, #rows do
			table.insert(items, { Text = rows[i].Label, Row = i })
		end
	else
		for _, group in groupsOf(row) do
			table.insert(items, { Text = group, Group = group })
		end
	end
	frame.Visible = #items > 1
	self._chipItems = {}
	for i = 1, Build.CHIPS do
		local chip = strip["Chip" .. i]
		local item = if i == 1 then { Text = first } else items[i - 1]
		self._chipItems[i] = item
		chip.Visible = item ~= nil
		if item then
			chip.Text = item.Text
			local on = (i == 1 and self._group == nil) or (item.Group ~= nil and item.Group == self._group)
			chip.BackgroundColor3 = if on then INK else WHITE
			chip.TextColor3 = if on then WHITE else INK
			chip:FindFirstChildOfClass("UIStroke").Color = if on then INK else CHIP_LINE
		end
	end
	self:_updateFade()
end

-- the right-hand fade: only while the chips run past the edge and you're not at the end
function Index:_updateFade()
	local frame = self._frame.Panel.Content.Groups
	local strip = frame.Chips
	local hidden = strip.AbsoluteCanvasSize.X - strip.AbsoluteWindowSize.X - strip.CanvasPosition.X
	frame.Fade.Visible = hidden > 2
end

-- All | Owned: the white thumb slides under the picked side
function Index:_fillShow(instant: boolean?)
	local seg = self._frame.Panel.Content.Show
	local picked = seg[SHOWS[self._show]]
	for _, name in SHOWS do
		seg[name].TextColor3 = if name == SHOWS[self._show] then INK else MUTED
	end
	local goal = { Position = UDim2.fromOffset(picked.Position.X.Offset, seg.Thumb.Position.Y.Offset), Size = UDim2.fromOffset(picked.Size.X.Offset, seg.Thumb.Size.Y.Offset) }
	local shadowGoal = { Position = UDim2.fromOffset(picked.Position.X.Offset, seg.ThumbShadow.Position.Y.Offset), Size = goal.Size }
	if instant then
		seg.Thumb.Position, seg.Thumb.Size = goal.Position, goal.Size
		seg.ThumbShadow.Position, seg.ThumbShadow.Size = shadowGoal.Position, shadowGoal.Size
	else
		TweenService:Create(seg.Thumb, THUMB_TWEEN, goal):Play()
		TweenService:Create(seg.ThumbShadow, THUMB_TWEEN, shadowGoal):Play()
	end
end

-- The set's title reward progress in the footer.
-- `pack` is the group / company pack in view (nil on All songs, or a set without a title).
function Index:_fillReward(pack, copies)
	local content = self._frame.Panel.Content
	local nextRow = content.NextStep
	local show = pack ~= nil and pack.Title ~= nil and #pack.Songs > 0
	nextRow.Visible = show
	content.Hint.Visible = not show
	if not show then
		return
	end
	local title, n = pack.Title, #pack.Songs
	local tiers = {}
	pcall(function()
		tiers = PlayerData.Inventory.TitleTiers.Get() or {}
	end)
	local tier = if has(PlayerData.Inventory.Titles, title) then Cards.LEVELS[tiers[title] or 1] else nil
	local function owns(id: string): boolean
		return has(PlayerData.Inventory.Songs, id)
	end
	local fill = nextRow.Bar.Fill
	local goal, step, progress, done
	if not tier then
		goal, done = "Normal", Cards.CountAtLeast(pack.Songs, copies, owns, "Normal")
		step = `Own all {n} {pack.Name} songs to unlock the title`
		progress = `{done} / {n}`
	elseif tier == "Normal" then
		goal, done = "Gold", Cards.CountAtLeast(pack.Songs, copies, owns, "Gold")
		step = `Get all {n} cards to <b>Gold</b> to upgrade it`
		progress = `{done} / {n} Gold`
	elseif tier == "Gold" then
		goal, done = "Rainbow", Cards.CountAtLeast(pack.Songs, copies, owns, "Rainbow")
		step = `Get all {n} cards to <b>Rainbow</b> for the top tier`
		progress = `{done} / {n} Rainbow`
	else
		goal, done = "Rainbow", n
		step = `Top tier: every {pack.Name} card is Rainbow`
		progress = "Done ✓"
	end
	TitleChip.Paint(nextRow.Chip, title, goal)
	nextRow.Text.Text = step
	self:_fitStep()
	nextRow.Progress.Text = progress
	fill.Size = UDim2.fromScale(math.clamp(done / n, 0, 1), 1)
	fill.Visible = done > 0
	TierShine.Apply(fill, fill.Rainbow, goal, GREEN) -- green to own them all, then gold / rainbow
end

-- Sizes the footer's step text so the bar and progress sit right after it, and stop
-- before the pager. Measured at the size it really renders on this screen (design size ×
-- canvas scale, in screen px) so phones' pixel rounding is counted; if it doesn't fit the
-- room left, the font steps down until it does. FitText skips this label (FitTextSkip).
local STEP_MIN_RATIO = 0.6

function Index:_fitStep()
	local row = self._frame.Panel.Content.NextStep
	local label = row.Text
	self._stepToken = (self._stepToken or 0) + 1
	local token = self._stepToken
	task.spawn(function()
		task.wait() -- let the chip's AutomaticSize catch up with its new title first
		if token ~= self._stepToken then
			return
		end
		-- screen px per design px (the row's height is a plain offset, so it gives the scale)
		local px = row.AbsoluteSize.Y / math.max(1, row.Size.Y.Offset)
		local layout = row:FindFirstChildOfClass("UIListLayout")
		local gap = (if layout then layout.Padding.Offset else 10) * px
		local others = 0
		for _, child in row:GetChildren() do
			if child:IsA("GuiObject") and child ~= label and child.Visible then
				others += child.AbsoluteSize.X + gap
			end
		end
		local room = math.max(40 * px, row.AbsoluteSize.X - others) -- screen px
		local base = label:GetAttribute("StepTextSize") or label.TextSize
		label:SetAttribute("StepTextSize", base)
		local params = Instance.new("GetTextBoundsParams")
		params.Text = label.Text
		params.Font = label.FontFace
		params.RichText = label.RichText
		params.Width = math.huge
		local size, width = base, 0
		while true do
			params.Size = math.max(1, math.floor(size * px + 0.5)) -- what this screen draws
			local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
			if token ~= self._stepToken then
				return
			end
			width = if ok then bounds.X + 2 else room
			if width <= room or size <= math.ceil(base * STEP_MIN_RATIO) then
				break
			end
			size -= 1
		end
		label.TextSize = size
		label.Size = UDim2.fromOffset(math.ceil(math.min(width, room) / px), label.Size.Y.Offset)
	end)
end

function Index:_fillCard(holder: Frame, song, level: string?, count: number, allSongs: boolean)
	holder.Visible = song ~= nil
	if not song then
		return
	end
	local mine = level ~= nil
	local face = holder.Face
	-- Gold cards shine, Rainbow cards scroll (Modules/UI/TierShine); Normal is plain white
	TierShine.Apply(face, face.Level, level, if mine then WHITE else PAPER)
	local line = face:FindFirstChildOfClass("UIStroke")
	line.Color = if mine then INK else DASH
	line.Thickness = if mine then 3 else 2
	holder.Shadow.Visible = mine
	for _, name in { "Art", "SongTitle", "Artist", "Tag" } do
		face[name].Visible = mine
	end
	face.Lock.Visible = not mine
	face.Skeleton.Visible = not mine
	face.Copies.Visible = mine and count > 1
	if not mine then
		return
	end
	GroupArt.Paint(face.Art, song) -- the group's gradient (Songs: Gradient), else its pastel
	face.Art.Initials.Text = initials(song.Name)
	face.SongTitle.Text = song.Name
	local gen = if song.Generation then `{song.Generation} gen` else nil
	face.Artist.Text = if allSongs then `{song.Artist} · {song.Company or "Other"}` elseif gen then `{song.Artist} · {gen}` else song.Artist
	face.Tag.Text = string.upper(level or "Normal")
	face.Copies.Text = `×{count} owned`
end

function Index:_refresh()
	if not self._frame or not self._frame.Visible then
		return
	end
	local panel = self._frame.Panel
	local content = panel.Content
	local rows = self:_rows()
	self._row = math.clamp(self._row, 1, #rows)
	local row = rows[self._row]

	-- rail
	for i = 1, Build.RAIL_ROWS do
		local b = panel.Rail:FindFirstChild("Row" .. i)
		local r = rows[i]
		b.Visible = r ~= nil
		if r then
			local on = i == self._row
			local have = countIn(r.Songs)
			b.Label.Text = r.Label
			b.Count.Text = `{have} / {#r.Songs}`
			b.BackgroundColor3 = if on then INK else WHITE
			b:FindFirstChildOfClass("UIStroke").Color = if on then INK else WHITE
			b.Label.TextColor3 = if on then YELLOW else INK
			b.Count.TextColor3 = if on then YELLOW else INK
			b.Bar.BackgroundColor3 = if on then TRACK_ON else TRACK
			b.Bar.Fill.BackgroundColor3 = if on then YELLOW else GREEN
			b.Bar.Fill.Size = UDim2.fromScale(if #r.Songs > 0 then have / #r.Songs else 0, 1)
			b.Bar.Fill.Visible = have > 0
		end
	end
	panel.Rail.PacksHeading.Visible = #rows > 1

	-- card level of every song (nil = missing)
	local copies = nil
	pcall(function()
		copies = PlayerData.Inventory.Copies.Get()
	end)
	local function levelOf(song): (string?, number)
		local mine = owned(song)
		local count = Cards.Copies(copies, mine, song.Id)
		return if mine then Cards.Level(count) else nil, count
	end

	-- this row's songs, narrowed to one group when one is picked
	if row.Kind ~= "Company" or (self._group and not table.find(groupsOf(row), self._group)) then
		self._group = nil
	end
	local songs = row.Songs
	if self._group then
		songs = {}
		for _, song in row.Songs do
			if song.Artist == self._group then
				table.insert(songs, song)
			end
		end
	end

	-- heading, Collected bar, Gold / Rainbow cards (Gold counts Gold or higher)
	local total, have, gold, rainbow = #songs, 0, 0, 0
	for _, song in songs do
		local level = levelOf(song)
		if level then
			have += 1
			gold += if level == "Gold" or level == "Rainbow" then 1 else 0
			rainbow += if level == "Rainbow" then 1 else 0
		end
	end
	content.TitleRow.Heading.Text = self._group or row.Label
	content.TitleRow.Sub.Text = `{have} of {total} collected`
	content.Collected.Fill.Size = UDim2.fromScale(if total > 0 then have / total else 0, 1)
	content.Collected.Fill.Visible = have > 0
	content.Tiers.Gold.Count.Text = `{gold} / {total}`
	content.Tiers.Rainbow.Count.Text = `{rainbow} / {total}`
	self:_fillChips(rows, row)
	-- the title for what's in view: the picked group's, else the company's
	local pack = nil
	if row.Kind == "Company" then
		pack = if self._group then Packs.Get(`Group:{self._group}`) else Packs.Get(`Company:{row.Label}`)
	end
	self:_fillReward(pack, copies)

	-- the cards: filtered, sorted, a page at a time
	local show = SHOWS[self._show]
	local list = {}
	for _, song in songs do
		local level = levelOf(song)
		if show == "All" or level then
			table.insert(list, song)
		end
	end
	local sort = SORTS[self._sort]
	table.sort(list, function(a, b)
		if sort == "Gen" then
			local ga, gb = genNumber(a), genNumber(b)
			if ga ~= gb then
				return ga < gb
			end
		end
		return a.Name:lower() < b.Name:lower()
	end)
	self:_fillShow()
	content.Sort.Label.Text = sort
	local pages = math.max(1, math.ceil(#list / PER_PAGE))
	self._page = math.clamp(self._page, 1, pages)
	content.Page.Text = `Page {self._page} of {pages}`
	content.Prev.TextTransparency = if self._page > 1 then 0 else 0.6
	content.Next.TextTransparency = if self._page < pages then 0 else 0.6
	content.Empty.Visible = #list == 0
	content.Empty.Text = if show == "All" then "No songs here yet" else "You don't own any of these yet"
	for i = 1, PER_PAGE do
		local song = list[(self._page - 1) * PER_PAGE + i]
		local level, count = if song then levelOf(song) else nil, 0
		self:_fillCard(content.Grid["Card" .. i], song, level, count, row.Kind == "All")
	end
end

-- The bars only move when the number changes: they grow from empty when the Index opens and
-- glide to the new value when you pick another row or group.
function Index:_animate(fromEmpty: boolean?)
	self._fillShown = self._fillShown or {}
	local fill = self._frame.Panel.Content.Collected.Fill
	local target = fill.Size
	local from = if fromEmpty then 0 else self._fillShown.Collected
	self._fillShown.Collected = target.X.Scale
	if from ~= nil and from ~= target.X.Scale then
		fill.Size = UDim2.fromScale(from, 1)
		TweenService:Create(fill, FILL_TWEEN, { Size = target }):Play()
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function Index:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Index")
	self._frame.Visible = false
	local panel = self._frame.Panel
	local content = panel.Content
	ButtonScale.ApplyToDescendants(panel)
	-- Footer next-step row (chip · step · bar · progress): stop it at the pager instead of
	-- running into it. The step text is sized to its own width (see _fitStep) so the bar
	-- follows right behind it, shrinking its font if it runs long (FitText leaves it alone).
	local nextRow = content.NextStep
	nextRow.Size = UDim2.new(1, -(38 + 8 + 104 + 8 + 38) - 12, 0, 36)
	local stepText = nextRow.Text
	stepText:SetAttribute("FitTextSkip", true)
	stepText.TextScaled = false
	stepText.TextWrapped = false
	stepText.AutomaticSize = Enum.AutomaticSize.None
	stepText.Size = UDim2.fromOffset(0, 20)
	local oldFlex = stepText:FindFirstChildOfClass("UIFlexItem")
	if oldFlex then
		oldFlex:Destroy()
	end
	-- re-measure when the screen changes size (the rendered font size changes with it)
	local canvasScale = self._frame.Parent:FindFirstChildOfClass("UIScale")
	if canvasScale then
		self._janitor:Add(canvasScale:GetPropertyChangedSignal("Scale"):Connect(function()
			if nextRow.Visible then
				self:_fitStep()
			end
		end))
	end
	local progress = nextRow.Progress
	progress.AutomaticSize = Enum.AutomaticSize.None
	progress.Size = UDim2.fromOffset(84, 20)
	local j = self._janitor
	-- the Rainbow stat dot scrolls too (cards + the next-step bar register as they're painted)
	TierShine.AddAll(content.Tiers, "UIGradient")

	local function redraw()
		self:_refresh()
		self:_animate()
	end
	local function pickRow(i: number)
		self._row = i
		self._page = 1
		self._group = nil
		content.Groups.Chips.CanvasPosition = Vector2.zero
		redraw()
	end

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(panel.Header.Roll.Activated:Connect(function()
		self._interface:Open("Roll")
	end))
	for i = 1, Build.RAIL_ROWS do
		j:Add(panel.Rail["Row" .. i].Activated:Connect(function()
			pickRow(i)
		end))
	end

	-- chips: a company (All songs) or a group (a company row); the strip scrolls sideways
	local groups = content.Groups
	j:Add(groups.Chips:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_updateFade()
	end))
	j:Add(groups.Chips:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		self:_updateFade()
	end))
	for i = 1, Build.CHIPS do
		j:Add(groups.Chips["Chip" .. i].Activated:Connect(function()
			local item = self._chipItems and self._chipItems[i]
			if not item then
				return
			end
			if item.Row then
				pickRow(item.Row)
			elseif item.Group ~= self._group then
				self._group = item.Group -- nil for "All groups"
				self._page = 1
				redraw()
			end
		end))
	end
	-- All | Owned
	for i, name in SHOWS do
		j:Add(content.Show[name].Activated:Connect(function()
			if self._show ~= i then
				self._show = i
				self._page = 1
				self:_refresh()
			end
		end))
	end
	j:Add(content.Sort.Activated:Connect(function()
		self._sort = self._sort % #SORTS + 1
		self:_refresh()
	end))
	for step, name in { [-1] = "Prev", [1] = "Next" } do
		j:Add(content[name].Activated:Connect(function()
			self._page += step
			self:_refresh()
		end))
	end

	j:Add(PlayerData.Inventory.Songs.Observe(function()
		self:_refresh()
	end))
	for _, path in { PlayerData.Inventory.Copies, PlayerData.Inventory.Titles, PlayerData.Inventory.TitleTiers } do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end
end

function Index:Activate()
	self._frame.Visible = true
	self:_refresh()
	self:_animate(true)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Index:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Index:Destroy()
	self._janitor:Destroy()
end

return Index
