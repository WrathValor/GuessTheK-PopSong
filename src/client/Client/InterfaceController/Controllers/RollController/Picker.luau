--| RollController · Picker
-- "Pick a group" (Roll.Picker, built by SeasonController/Build.SeasonRewards; board "Seasons 12"):
-- a roll ticket rolls one song from a group you choose. Company tabs (All, then the companies
-- by size, Other last), 12 groups a page with how many of their songs you own, the picked
-- one ticked, and ROLL <GROUP> (uses 1 ticket). Only groups with a group pack
-- (Packs.MIN_GROUP_SONGS+) are listed.
--   local picker = Picker.new(roll.Picker, janitor, function(groupId) ... end)
--   picker:Open() / picker:Close()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)

local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local CREAM_PICK = C("FFF6D6")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local PER_PAGE = 12
local TABS = 8

local Picker = {}
Picker.__index = Picker

local function initials(name: string): string
	local words = {}
	for word in name:gsub("[^%w%s]", ""):gmatch("%S+") do
		table.insert(words, word)
	end
	if #words >= 2 then
		return string.upper(words[1]:sub(1, 1) .. words[2]:sub(1, 1))
	end
	return string.upper((words[1] or name):sub(1, 2))
end

local function owns(id: string): boolean
	local ok, has = pcall(PlayerData.Inventory.Songs.Has, id)
	return ok and has == true
end

local function tickets(): number
	return Currencies.Count(LOCAL_PLAYER, "Tickets")
end

-- the tabs: All, then each company with a group pack (most groups first), Other last
local function companyOf(pack): string
	local song = pack.Songs[1]
	return song and song.Company or "Other"
end

local function buildTabs(): { string }
	local count = {}
	for _, pack in Packs.Groups() do
		local c = companyOf(pack)
		count[c] = (count[c] or 0) + 1
	end
	local list = {}
	for c in count do
		if c ~= "Other" then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		if count[a] ~= count[b] then
			return count[a] > count[b]
		end
		return a < b
	end)
	local out = { "All" }
	for i = 1, math.min(#list, TABS - 2) do
		table.insert(out, list[i])
	end
	table.insert(out, "Other") -- everything else (and any company past the tab row)
	return out
end

function Picker.new(frame: Frame, janitor, onRoll: (string) -> ())
	local self = setmetatable({}, Picker)
	self._frame = frame
	self._onRoll = onRoll
	self._tabs = buildTabs()
	self._tab = 1
	self._page = 1
	self._picked = nil :: string?
	frame.Visible = false
	local panel = frame.Panel
	ButtonScale.ApplyToDescendants(panel)

	janitor:Add(panel.Header.Close.Activated:Connect(function()
		self:Close()
	end))
	for i = 1, TABS do
		janitor:Add(panel.Tabs["Tab" .. i].Activated:Connect(function()
			if self._tabs[i] and self._tab ~= i then
				Sounds.Play("Click")
				self._tab, self._page = i, 1
				self:_fill()
			end
		end))
	end
	for i = 1, PER_PAGE do
		local tile = panel.Grid["Tile" .. i]
		janitor:Add(tile.Activated:Connect(function()
			local id = tile:GetAttribute("GroupId")
			if id then
				Sounds.Play("Click")
				self._picked = id
				Juice.Pop(tile, 0.08)
				self:_fill()
			end
		end))
	end
	for name, step in { Prev = -1, Next = 1 } do
		janitor:Add(panel[name].Activated:Connect(function()
			self._page += step
			self:_fill()
		end))
	end
	janitor:Add(panel.RollGroup.Activated:Connect(function()
		local id = self._picked
		if not id or tickets() < 1 then
			Juice.Shake(panel.RollGroup)
			Sounds.Play("Wrong")
			return
		end
		self:Close()
		self._onRoll(id)
	end))
	janitor:Add(LOCAL_PLAYER:GetAttributeChangedSignal(Currencies.Tickets.Attribute):Connect(function()
		if frame.Visible then
			self:_fill()
		end
	end))
	return self
end

function Picker:_list(): { any }
	local tab = self._tabs[self._tab]
	local main = {}
	for i = 2, #self._tabs - 1 do
		main[self._tabs[i]] = true
	end
	local out = {}
	for _, pack in Packs.Groups() do
		local c = companyOf(pack)
		if tab == "All" or c == tab or (tab == "Other" and not main[c]) then
			table.insert(out, pack)
		end
	end
	return out -- (Packs.Groups is A–Z)
end

function Picker:_fill()
	local panel = self._frame.Panel
	local n = tickets()
	panel.Header.Tickets.Amount.Text = if n == 1 then "1 ticket" else `{n} tickets`
	for i = 1, TABS do
		local t = panel.Tabs["Tab" .. i]
		local name = self._tabs[i]
		t.Visible = name ~= nil
		t.Text = name or ""
		local on = i == self._tab
		t.BackgroundColor3 = if on then INK else WHITE
		t.TextColor3 = if on then YELLOW else INK
	end

	local list = self:_list()
	local pages = math.max(1, math.ceil(#list / PER_PAGE))
	self._page = math.clamp(self._page, 1, pages)
	panel.Page.Text = `{self._page} / {pages}`
	panel.Prev.TextTransparency = if self._page > 1 then 0 else 0.6
	panel.Next.TextTransparency = if self._page < pages then 0 else 0.6
	local picked = nil
	for i = 1, PER_PAGE do
		local tile = panel.Grid["Tile" .. i]
		local pack = list[(self._page - 1) * PER_PAGE + i]
		tile.Visible = pack ~= nil
		panel.Grid["Tile" .. i .. "Shadow"].Visible = pack ~= nil
		tile:SetAttribute("GroupId", pack and pack.Id or nil)
		if pack then
			local have = 0
			for _, song in pack.Songs do
				have += if owns(song.Id) then 1 else 0
			end
			local total = #pack.Songs
			local on = pack.Id == self._picked
			tile.GroupName.Text = pack.Name
			tile.Owned.Text = `{have} / {total} owned`
			tile.Bar.Fill.Size = UDim2.fromScale(if total > 0 then have / total else 0, 1)
			tile.Bar.Fill.Visible = have > 0
			tile.Bar.Fill.BackgroundColor3 = if have == total then YELLOW else MINT
			tile.BackgroundColor3 = if on then CREAM_PICK else WHITE
			tile:FindFirstChildOfClass("UIStroke").Thickness = if on then 4 else 3
			tile.Check.Visible = on
			if tile:GetAttribute("Shown") ~= pack.Id then
				tile:SetAttribute("Shown", pack.Id)
				GroupArt.Paint(tile.Art, pack.Name)
				tile.Art.Initials.Text = initials(pack.Name)
			end
		end
	end
	for _, pack in Packs.Groups() do
		if pack.Id == self._picked then
			picked = pack
		end
	end

	-- the picked group: the odds line + ROLL <GROUP>
	local go = panel.RollGroup
	if picked then
		local missing = 0
		for _, song in picked.Songs do
			missing += if owns(song.Id) then 0 else 1
		end
		panel.Info.Text = if missing == 0
			then `You own every <b>{picked.Name}</b> song, so a roll adds a copy to one of them.`
			else `Every <b>{picked.Name}</b> song is equally likely. You're {missing} song{if missing == 1 then "" else "s"} from the set. Duplicates still level the card up.`
		go.Label.Text = `ROLL {string.upper(picked.Name)}`
	else
		panel.Info.Text = "Pick a group to roll one of its songs."
		go.Label.Text = "PICK A GROUP"
	end
	local can = picked ~= nil and n >= 1
	go.BackgroundColor3 = if can then MINT else GREY
	go.Active = can
end

function Picker:Open()
	self._frame.Visible = true
	self:_fill()
	FrameTransition.Open(self._frame)
end

function Picker:Close()
	FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
	end)
end

function Picker:IsOpen(): boolean
	return self._frame.Visible
end

return Picker
