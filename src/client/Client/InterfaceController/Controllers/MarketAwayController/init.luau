--| MarketAwayController ("MarketAway")
-- The "While you were away" pop-up (Interface.Frames.MarketAway, built by ./Build from design
-- board "67b · Market · Away pop-up + ended toast"). Once a session, a few seconds after joining
-- and only back in the lobby (no screen open, past the first-time tutorial), if any of your
-- Market listings sold before you joined (Inventory.Listings, W) and aren't collected yet, or
-- ran out unsold since you last looked (Inventory.MarketLog "Ended" after MarketSeen): up to 3
-- cards (+N more), the coins waiting, then SEE MY LISTINGS (the Market on My listings) or
-- COLLECT ALL (MarketRemote "CollectAll"; MarketController shows the coins). Showing it counts
-- as looking (MarketRemote "Seen"), so the ended ones leave the HUD badge.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local MarketConstants = require(ReplicatedStorage.Constants.MarketConstants)
local Photocard = require(ReplicatedStorage.Modules.UI.Photocard)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local MarketRemote = Bridgenet.ReferenceBridge("MarketRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local PINK = C("FF9EC4")
local SAND = C("F3EEE0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")

local DELAY = 8 -- seconds after joining before it can show (the server's join check settles first)
local POLL = 2
local GIVE_UP = 600 -- stop waiting for the lobby after this long

-- --------------------------------- Helpers -------------------------------- --
local function get(path, fallback)
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else fallback
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- what to show: { { C, R?, Sold, Coins? } } (sold first), and the coins waiting
local function gather(): ({ { [string]: any } }, number)
	local items, coins = {}, 0
	for _, json in get(PlayerData.Inventory.Listings, {}) do
		local l = MarketConstants.Decode(json)
		if l and l.S == "Sold" then
			local pay = MarketConstants.Payout(l.P or 0)
			coins += pay
			if l.W and Albums.Card(l.C) then
				table.insert(items, { C = l.C, R = l.R, Sold = true, Coins = pay, T = l.T or 0 })
			end
		end
	end
	table.sort(items, function(a, b)
		return a.T > b.T
	end)
	local seen = get(PlayerData.Inventory.MarketSeen, 0)
	local log = get(PlayerData.Inventory.MarketLog, {})
	for i = #log, 1, -1 do
		local e = MarketConstants.Decode(log[i])
		if e and e.K == "Ended" and (e.T or 0) > seen and Albums.Card(e.C) then
			table.insert(items, { C = e.C, Sold = false })
		end
	end
	return items, coins
end

-- ---------------------------------- Class --------------------------------- --
local MarketAway = {}
MarketAway.__index = MarketAway

function MarketAway.new()
	local self = setmetatable({}, MarketAway)
	self.Name = "MarketAway"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._coins = 0
	return (self :: any) :: UITypes.Controller
end

function MarketAway:Initialize(interface)
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "MarketAway")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel

	j:Add(panel.SeeListings.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Close(self.Name)
		task.delay(0.25, function()
			if self._interface.Mode == "Gameplay" then
				self._interface:Open("Market", "Listings")
			end
		end)
	end))
	j:Add(panel.CollectAll.Activated:Connect(function()
		if self._coins > 0 then
			Sounds.Play("Click")
			MarketRemote:Fire({ Action = "CollectAll" })
		end
		self._interface:Close(self.Name)
	end))

	-- once, when the lobby's free
	j:Add(task.spawn(function()
		local started = os.clock()
		task.wait(DELAY)
		while os.clock() - started < GIVE_UP do
			local ready = get(PlayerData.Settings.Onboard, "") == "Done"
				and self._interface.Mode == "Gameplay"
				and self._interface.ActiveController == nil
				and not LOCAL_PLAYER:GetAttribute("Stage")
			if ready then
				local items = gather()
				if #items > 0 then
					self._interface:Open(self.Name)
				end
				return
			end
			task.wait(POLL)
		end
	end), true)
end

function MarketAway:_paint()
	local panel = self._frame.Panel
	local items, coins = gather()
	self._coins = coins
	for i = 1, Build.SLOTS do
		local slot = panel.Cards[`Slot{i}`]
		local it = items[i]
		slot.Visible = it ~= nil
		if it then
			local card = Albums.Card(it.C) :: any
			Photocard.Paint(slot.Card, it.C, 1, if (it.R or 0) > 0 then it.R else nil)
			slot.Name.Text = card.Member.Name
			slot.Tag.Text = if it.Sold then `SOLD · +{commas(it.Coins)}` else "ENDED · in binder"
			slot.Tag.BackgroundColor3 = if it.Sold then PINK else SAND
		end
	end
	local more = #items - Build.SLOTS
	panel.More.Visible = more > 0
	panel.More.Text = `+{more} more in My listings`
	panel.Collect.Inner.Amount.Text = if coins > 0 then `{commas(coins)} to collect` else "Nothing to collect"
	panel.Collect.BackgroundColor3 = if coins > 0 then C("FFE07A") else SAND
	panel.CollectAll.Text = if coins > 0 then "COLLECT ALL" else "OK"
	panel.CollectAll.BackgroundColor3 = if coins > 0 then MINT else WHITE
end

function MarketAway:Activate()
	self:_paint()
	self._frame.Visible = true
	MarketRemote:Fire({ Action = "Seen" })
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	Juice.Pop(self._frame.Panel.Collect, 0.15)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function MarketAway:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function MarketAway:Destroy()
	self._janitor:Destroy()
end

return MarketAway
