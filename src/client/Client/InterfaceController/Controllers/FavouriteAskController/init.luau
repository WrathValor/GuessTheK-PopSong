--| FavouriteAskController
-- The second (and last) "favourite the game?" ask (design board "Fans 1 · second (last)
-- favourite ask"). The first is Client/FavoritePrompt, once after a player's first duel. This
-- one waits for a high: a win streak reaching STREAK, or a song's first Rainbow card
-- (RollConstants.RAINBOW_COPIES copies), and shows the next time you're back in the lobby
-- (no screen open, not on a stage). Only for players who were asked the first time
-- (Settings.FavoritePrompted), still haven't favourited, and haven't seen this before
-- (Settings.Hints "Favourite2", saved through SettingsService "HintSeen"). FAVOURITE opens
-- Roblox's own favourite pop-up; Not now just closes it. Either way it never shows again.
--   Interface:Open("FavouriteAsk", "Streak" | "Rainbow")

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local RollConstants = require(ReplicatedStorage.Constants.RollConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

local HINT = "Favourite2"
local STREAK = 3 -- wins in a row that count as a high
local DELAY = 1.5 -- seconds back in the lobby before it opens
local MOMENTS = {
	Streak = { Head = `{STREAK} WINS IN A ROW!`, Body = "It stays one tap away on your home page, so you can keep the streak going next time." },
	Rainbow = { Head = "FIRST RAINBOW CARD!", Body = "It stays one tap away on your home page, so you can keep collecting next time." },
}

-- --------------------------------- Helpers -------------------------------- --
local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

local function seen(): boolean
	local ok, v = pcall(PlayerData.Settings.Hints.Has, HINT)
	return not ok or v == true -- data not ready: treat as seen
end

-- asked the first time, not this one yet. (In Studio the first ask never saves, so it's taken
-- as done there: otherwise this one could never be tried.)
local function eligible(): boolean
	local firstDone = RunService:IsStudio() or get(PlayerData.Settings.FavoritePrompted, false) == true
	return firstDone and get(PlayerData.Settings.TutorialDone, false) == true and not seen()
end

local function rainbowSongs(map: any): { [string]: boolean }
	local out = {}
	for id, n in (if type(map) == "table" then map else {}) do
		if type(n) == "number" and n >= RollConstants.RAINBOW_COPIES then
			out[id] = true
		end
	end
	return out
end

-- ---------------------------------- Class --------------------------------- --
local FavouriteAsk = {}
FavouriteAsk.__index = FavouriteAsk

function FavouriteAsk.new()
	local self = setmetatable({}, FavouriteAsk)
	self.Name = "FavouriteAsk"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._pending = nil :: string? -- a moment waiting for the lobby
	self._done = false -- this session (the save catches up a moment later)
	return (self :: any) :: UITypes.Controller
end

function FavouriteAsk:Initialize(interface)
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "FavouriteAsk")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel

	j:Add(panel.Favourite.Activated:Connect(function()
		self:_answer("Favourite")
	end))
	j:Add(panel.NotNow.Activated:Connect(function()
		self:_answer("NotNow")
	end))

	-- the highs: the streak climbing to STREAK, a song reaching Rainbow (not what you already
	-- had when you joined)
	local lastStreak: number? = nil
	j:Add(PlayerData.Player.Streak.Observe(function(n: number)
		if lastStreak ~= nil and n >= STREAK and lastStreak < STREAK then
			self:_want("Streak")
		end
		lastStreak = n
	end))
	local known: { [string]: boolean }? = nil
	j:Add(PlayerData.Inventory.Copies.Observe(function()
		local now = rainbowSongs(get(PlayerData.Inventory.Copies, {}))
		if known then
			for id in now do
				if not known[id] then
					self:_want("Rainbow")
					break
				end
			end
		end
		known = now
	end))

	-- back in the lobby: show a waiting moment
	j:Add(interface.ModeChanged:Connect(function(mode)
		if mode == "Gameplay" then
			self:_try()
		end
	end))
end

function FavouriteAsk:_want(moment: string)
	if self._done or self._pending or not eligible() then
		return
	end
	self._pending = moment
	self:_try()
end

function FavouriteAsk:_try()
	if not self._pending or self._waiting then
		return
	end
	self._waiting = true
	task.delay(DELAY, function()
		self._waiting = false
		local moment = self._pending
		if not moment or self._done or not eligible() then
			return
		end
		if self._interface.Mode ~= "Gameplay" or self._interface.ActiveController ~= nil or LOCAL_PLAYER:GetAttribute("Stage") then
			return -- not now: the next time the lobby comes back
		end
		-- already a favourite? nothing to ask; never ask again
		local ok, favourited = pcall(AvatarEditorService.GetFavoriteAsync, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset)
		if ok and favourited then
			self:_finish()
			return
		end
		self._interface:Open(self.Name, moment)
	end)
end

function FavouriteAsk:_finish()
	self._done = true
	self._pending = nil
	SettingsRemote:Fire({ Action = "HintSeen", Id = HINT })
end

function FavouriteAsk:_answer(answer: string)
	if self._done then
		return
	end
	self:_finish()
	AnalyticsClient.Event("FavouriteAsk", 1, answer)
	if answer == "Favourite" then
		Sounds.Play("Success")
		self._interface:Close(self.Name)
		task.delay(0.35, function()
			pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	else
		self._interface:Close(self.Name)
	end
end

function FavouriteAsk:Activate(moment: string?)
	local spec = MOMENTS[moment or "Streak"] or MOMENTS.Streak
	local panel = self._frame.Panel
	panel.Header.Moment.Text = spec.Head
	panel.Body.Text = spec.Body
	self._frame.Visible = true
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	Juice.Pop(panel.Badge, 0.2)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function FavouriteAsk:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function FavouriteAsk:Destroy()
	self._janitor:Destroy()
end

return FavouriteAsk
