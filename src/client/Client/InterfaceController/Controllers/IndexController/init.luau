--| IndexController
-- The Index (Interface.Frames.Index, built by ./Build from the "Index · discovered + owned"
-- board): every song in the game, in three states:
--   • Missing    – "???" card; guess it correctly in a duel to discover it
--   • Discovered – guessed correctly at least once (Inventory.Index): white card, DISCOVERED tag
--   • Owned      – bought in the shop (Inventory.Songs): holographic card, ★, OWNED tag; these
--                  are the songs that count for duel packs. Owning a song also reveals it.
-- Header: Discovered x/y and Owned x/y bars. Rail: All songs · My Pack · one row per company.
-- Songs discovered this session get a NEW badge. Nothing can be bought here (that's the shop).

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local PAPER = C("F3EBDD")
local DASH = C("A39A8C")
local GREY = C("EDE4D4")
local LINE = C("CFC5B3")

local PER_PAGE = Build.PER_PAGE
local SHOWS = { "All", "Discovered", "Owned", "Missing" }
local SORTS = { "A–Z", "Gen" }

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
	self._show = 1
	self._sort = 1
	self._new = {} :: { [string]: boolean } -- collected this session
	self._known = nil :: { [string]: boolean }?
	return (self :: any) :: UITypes.Controller
end

local function has(path, id: string): boolean
	local ok, yes = pcall(path.Has, id)
	return ok and yes == true
end

local function genNumber(song): number
	return tonumber(tostring(song.Generation or ""):match("%d+")) or 99
end

-- rail rows: { Label, Songs = {...}, Kind }
function Index:_rows()
	local rows = {
		{ Label = "All songs", Songs = Songs.All, Kind = "All" },
		{ Label = "My Pack", Songs = {}, Kind = "Pack" },
	}
	for _, song in Songs.All do
		if has(PlayerData.Inventory.Songs, song.Id) then
			table.insert(rows[2].Songs, song)
		end
	end
	local byCompany, order = {}, {}
	for _, song in Songs.All do
		local company = song.Company or "Other"
		if not byCompany[company] then
			byCompany[company] = {}
			table.insert(order, company)
		end
		table.insert(byCompany[company], song)
	end
	table.sort(order)
	for _, company in order do
		table.insert(rows, { Label = company, Songs = byCompany[company], Kind = "Company" })
	end
	return rows
end

local function owned(song): boolean
	return has(PlayerData.Inventory.Songs, song.Id)
end

-- revealed: guessed correctly, or bought
local function discovered(song): boolean
	return has(PlayerData.Inventory.Index, song.Id) or owned(song)
end

local function countIn(list, test): number
	local n = 0
	for _, song in list do
		if test(song) then
			n += 1
		end
	end
	return n
end

function Index:_refresh()
	if not self._frame or not self._frame.Visible then
		return
	end
	local panel = self._frame.Panel
	local rows = self:_rows()
	self._row = math.clamp(self._row, 1, #rows)

	-- rail
	for i = 1, Build.RAIL_ROWS do
		local b = panel.Rail:FindFirstChild("Row" .. i)
		local row = rows[i]
		b.Visible = row ~= nil
		if row then
			local on = i == self._row
			b.Label.Text = row.Label
			b.Count.Text = if row.Kind == "Pack" then `{#row.Songs} owned` else `{countIn(row.Songs, discovered)} · {countIn(row.Songs, owned)}`
			b.BackgroundColor3 = if on then INK else WHITE
			b:FindFirstChildOfClass("UIStroke").Color = if on then INK else WHITE
			b.Label.TextColor3 = if on then YELLOW else INK
			b.Count.TextColor3 = if on then YELLOW else INK
		end
	end
	panel.Rail.PacksHeading.Visible = #rows > 2

	-- list for this row, filtered + sorted
	local row = rows[self._row]
	local show = SHOWS[self._show]
	local list = {}
	for _, song in row.Songs do
		local seen, mine = discovered(song), owned(song)
		if show == "All" or (show == "Discovered" and seen and not mine) or (show == "Owned" and mine) or (show == "Missing" and not seen) then
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
		return a.Name < b.Name
	end)

	local content = panel.Content
	local total = #row.Songs
	content.Heading.Text = row.Label
	for name, test in { Discovered = discovered, Owned = owned } do
		local n = countIn(row.Songs, test)
		local bar = content[name]
		bar.Count.Text = `{n} / {total}`
		bar.Bar.Fill.Size = UDim2.fromScale(if total > 0 then n / total else 0, 1)
		bar.Bar.Fill.Visible = n > 0
	end
	content.Show.Text = `Show: {show}`
	content.Sort.Text = `Sort: {sort}`
	local pages = math.max(1, math.ceil(#list / PER_PAGE))
	self._page = math.clamp(self._page, 1, pages)
	content.Page.Text = `{self._page} / {pages}`
	content.Prev.Visible = pages > 1
	content.Next.Visible = pages > 1
	content.Page.Visible = pages > 1
	content.Empty.Visible = #list == 0
	content.Empty.Text = if row.Kind == "Pack" and #row.Songs == 0 then "Buy songs in the shop to fill My Pack" else "No songs here"

	for i = 1, PER_PAGE do
		local holder = content.Grid["Card" .. i]
		local song = list[(self._page - 1) * PER_PAGE + i]
		holder.Visible = song ~= nil
		if song then
			local mine = owned(song)
			local seen = mine or discovered(song)
			local face = holder.Face
			face.BackgroundColor3 = if seen then WHITE else PAPER
			face.Holo.Enabled = mine
			face:FindFirstChildOfClass("UIStroke").Color = if seen then INK else DASH
			holder.Shadow.Visible = seen
			face.Badge.BackgroundColor3 = if mine then YELLOW elseif seen then MINT else GREY
			face.Badge:FindFirstChildOfClass("UIStroke").Color = if seen then INK else LINE
			face.Badge.Mark.Text = if mine then "★" elseif seen then "♪" else "?"
			face.Badge.Mark.TextColor3 = if seen then INK else DASH
			face.SongTitle.Text = if seen then song.Name else "???"
			face.Artist.Text = if seen then song.Artist else "Not discovered yet"
			face.Gen.Text = if seen and song.Generation then `{string.upper(song.Generation)} GEN` else ""
			face.Tag.Visible = seen
			face.Tag.Text = if mine then "OWNED" else "DISCOVERED"
			face.Tag.BackgroundColor3 = if mine then INK else MINT
			face.Tag.TextColor3 = if mine then YELLOW else INK
			holder.New.Visible = seen and self._new[song.Id] == true
		end
	end
end

-- The progress fill only moves when the number changes: it grows from empty when the Index
-- opens, glides to the new value when you pick another rail entry, and stays put on page,
-- filter and sort changes. (No card cascade: 18 cards per page is too busy.)
function Index:_animate(fromEmpty: boolean?)
	self._fillShown = self._fillShown or {}
	for _, name in { "Discovered", "Owned" } do
		local fill = self._frame.Panel.Content[name].Bar.Fill
		local target = fill.Size
		local from = if fromEmpty then 0 else self._fillShown[name]
		self._fillShown[name] = target.X.Scale
		if from ~= nil and from ~= target.X.Scale then
			fill.Size = UDim2.fromScale(from, 1)
			game:GetService("TweenService"):Create(fill, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = target }):Play()
		end
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function Index:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Index")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for i = 1, Build.RAIL_ROWS do
		j:Add(panel.Rail["Row" .. i].Activated:Connect(function()
			self._row = i
			self._page = 1
			self:_refresh()
			self:_animate()
		end))
	end
	local content = panel.Content
	j:Add(content.Show.Activated:Connect(function()
		self._show = self._show % #SHOWS + 1
		self._page = 1
		self:_refresh()
		self:_animate()
	end))
	j:Add(content.Sort.Activated:Connect(function()
		self._sort = self._sort % #SORTS + 1
		self:_refresh()
		self:_animate()
	end))
	j:Add(content.Prev.Activated:Connect(function()
		self._page -= 1
		self:_refresh()
		self:_animate()
	end))
	j:Add(content.Next.Activated:Connect(function()
		self._page += 1
		self:_refresh()
		self:_animate()
	end))

	-- NEW badges: anything that joins the Index after the first load
	j:Add(PlayerData.Inventory.Index.Observe(function(set)
		local now = {}
		if type(set) == "table" then
			for k, v in set do
				local id = if type(k) == "string" then k else v
				if type(id) == "string" then
					now[id] = true
				end
			end
		end
		if self._known then
			for id in now do
				if not self._known[id] then
					self._new[id] = true
				end
			end
		end
		self._known = now
		self:_refresh()
	end))
	j:Add(PlayerData.Inventory.Songs.Observe(function()
		self:_refresh()
	end))
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
		self._new = {} -- NEW badges clear once you've seen them
	end)
end

function Index:Destroy()
	self._janitor:Destroy()
end

return Index
