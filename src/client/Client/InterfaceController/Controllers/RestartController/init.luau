--| RestartController ("Restart")
-- Tells players a server restart is coming (Engine/ShutdownService publishes it as JSON on
-- ReplicatedStorage's "Restart" attribute: At, Kind "Update" / "Maintenance", Title?, Message?).
-- Design boards "Server restart 1–3"; the UI is built in Studio by ./Build.
--   • Lobby: the banner under the top bar (HUD.TopCenter.Restart) counting down. Yellow +
--     rocket for an update (its title / line can come from the restart's attributes), blue +
--     wrench for Roblox maintenance. Tapping it shrinks it to the clock pill (RestartMini), and
--     tapping that opens it again. HOP OVER NOW asks the server to teleport you to a fresh,
--     updated server (hidden while you're on a stage). It lives in the HUD, so it slides away
--     with it when a menu opens or a duel starts.
--   • In a duel: the small pill under the scoreboard (Frames.Game.RestartPill). It takes that
--     spot over: whatever else sits there (the STAGE OPEN chip, the pack tag) stays hidden
--     while a restart is coming, and comes back if it's called off.
--   • The last HANDOVER seconds: the hand-over card (Frames.Restart) over everything, counting
--     down while Roblox moves everyone (Roblox does the teleport itself at restart time).
-- Sounds: Notify when a restart is announced, Open when the hand-over card comes up.
-- Not opened through Interface:Open: it drives its pieces itself from the attribute.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local RestartRemote = Bridgenet.ReferenceBridge("RestartRemote")

local HANDOVER = 12 -- seconds before the restart that the hand-over card takes over
local HOP_COOLDOWN = 8 -- seconds the HOP button says "HOPPING…" for
local SPIN_SPEED = 300 -- degrees a second, the hand-over ring's arc
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local WORDS = {
	Update = {
		Title = "UPDATE INCOMING!",
		Message = "New stuff is ready · this server restarts soon",
		Pill = "UPDATE IN",
		Heading = "Moving you to an updated server",
		Icon = Build.ROCKET,
		Colour = Build.UPDATE,
	},
	Maintenance = {
		Title = "QUICK MAINTENANCE",
		Message = "Roblox is tidying up · this server restarts soon",
		Pill = "RESTART IN",
		Heading = "Moving you to a fresh server",
		Icon = Build.WRENCH,
		Colour = Build.MAINTENANCE,
	},
}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function read(): any
	local raw = ReplicatedStorage:GetAttribute("Restart")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(info) ~= "table" or type(info.At) ~= "number" then
		return nil
	end
	return info
end

-- --------------------------------- Class ---------------------------------- --
local Restart = {}
Restart.__index = Restart

function Restart.new()
	local self = setmetatable({}, Restart)
	self.Name = "Restart"
	self.Exclusive = false
	self.State = "Inactive" :: UITypes.ControllerState
	self._janitor = Janitor.new()
	self._info = nil
	self._collapsed = false
	self._hopUntil = 0
	self._ticker = nil :: thread?
	self._spin = nil :: RBXScriptConnection?
	return (self :: any) :: UITypes.Controller
end

-- [[ Painting ]]

function Restart:_paintKind()
	local info = self._info
	local words = WORDS[info.Kind] or WORDS.Update
	local banner = self._banner
	banner.Face.BackgroundColor3 = words.Colour
	banner.Face.IconBox.Icon.Image = words.Icon
	banner.Face.Title.Text = if info.Kind == "Update" and info.Title then info.Title else words.Title
	banner.Face.Message.Text = if info.Kind == "Update" and info.Message then info.Message else words.Message
	self._mini.BackgroundColor3 = words.Colour
	self._pill.BackgroundColor3 = words.Colour
	self._card.Card.Heading.Text = words.Heading
end

-- shows / hides the lobby banner or its shrunk pill (pop on the way in)
function Restart:_showBanner(show: boolean)
	local full = show and not self._collapsed
	local mini = show and self._collapsed
	if full and not self._banner.Visible then
		local pop = self._banner:FindFirstChild("Pop") :: UIScale?
		if pop then
			pop.Scale = 0.6
			TweenService:Create(pop, POP, { Scale = 1 }):Play()
		end
	end
	self._banner.Visible = full
	self._mini.Visible = mini
	self._miniShadow.Visible = mini
end

function Restart:_showCard(show: boolean)
	local card = self._card
	if show and not card.Visible then
		card.Visible = true
		Sounds.Play("Open")
		local pop = card.Card:FindFirstChild("Pop") :: UIScale?
		if pop then
			pop.Scale = 0.7
			TweenService:Create(pop, POP, { Scale = 1 }):Play()
		end
		local spin = card.Card.Ring.Arc:FindFirstChildOfClass("UIStroke")
		local gradient = spin and spin:FindFirstChild("Spin") :: UIGradient?
		if gradient and not self._spin then
			self._spin = RunService.RenderStepped:Connect(function(dt)
				gradient.Rotation = (gradient.Rotation + SPIN_SPEED * dt) % 360
			end)
		end
	elseif not show and card.Visible then
		card.Visible = false
		if self._spin then
			self._spin:Disconnect()
			self._spin = nil
		end
	end
end

function Restart:_tick()
	local info = self._info
	if not info then
		return
	end
	local left = info.At - workspace:GetServerTimeNow()
	local words = WORDS[info.Kind] or WORDS.Update
	local time = clock(left)

	-- the last seconds: the hand-over card over everything
	if left <= HANDOVER then
		self:_showBanner(false)
		self._pill.Visible = false
		self._pillShadow.Visible = false
		self:_showCard(true)
		self._card.Card.Ring.Count.Text = tostring(math.max(0, math.ceil(left)))
		return
	end
	self:_showCard(false)

	-- lobby banner (it rides on the HUD, which hides it in menus and duels)
	self._banner.Face.Time.Label.Text = time
	self._mini.Label.Text = time
	local hopping = os.clock() < self._hopUntil
	self._banner.Hop.Text = if hopping then "HOPPING…" else "HOP OVER NOW"
	local onStage = LOCAL_PLAYER:GetAttribute("Stage") ~= nil or LOCAL_PLAYER:GetAttribute("PartyStage") ~= nil
	self._banner.Hop.Visible = not onStage
	self._banner.HopShadow.Visible = not onStage
	self:_showBanner(true)

	-- in a duel: the pill under the scoreboard, in place of anything else there
	self._pill.Label.Text = `{words.Pill} {time}`
	self._pill.Visible = true
	self._pillShadow.Visible = true
	self:_hideSlot(true)
end

-- The pieces that share the spot under the duel scoreboard. While a restart is coming they're
-- kept hidden (each one is hidden again the moment GameController shows it); `hide` false
-- lets them back (the ones that should be up then are shown again on their next update).
local SLOT = { "OpenChip", "OpenChipShadow", "PackTag" }

function Restart:_hideSlot(hide: boolean)
	if hide == (self._slotHidden == true) then
		return
	end
	self._slotHidden = hide
	if self._slotJanitor then
		self._slotJanitor:Destroy()
		self._slotJanitor = nil
	end
	if not hide then
		for name, was in self._slotWas or {} do
			local piece = self._game:FindFirstChild(name)
			if piece then
				piece.Visible = was
			end
		end
		self._slotWas = nil
		return
	end
	self._slotJanitor = Janitor.new()
	self._slotWas = {}
	for _, name in SLOT do
		local piece = self._game:FindFirstChild(name) :: GuiObject?
		if piece then
			self._slotWas[name] = piece.Visible
			piece.Visible = false
			self._slotJanitor:Add(piece:GetPropertyChangedSignal("Visible"):Connect(function()
				if piece.Visible then
					self._slotWas[name] = true
					piece.Visible = false
				end
			end))
		end
	end
end

function Restart:_refresh()
	local before = self._info
	self._info = read()
	if self._info and (not before or before.At ~= self._info.At or before.Kind ~= self._info.Kind) then
		self._collapsed = false -- a new restart: the full banner again
		Sounds.Play("Notify") -- (the same ping as a tip popping up)
	end
	if self._ticker then
		task.cancel(self._ticker)
		self._ticker = nil
	end
	if not self._info then
		self:_showBanner(false)
		self:_showCard(false)
		self._pill.Visible = false
		self._pillShadow.Visible = false
		self:_hideSlot(false)
		return
	end
	self:_paintKind()
	self:_tick()
	self._ticker = task.spawn(function()
		while true do
			task.wait(0.25)
			self:_tick()
		end
	end)
end

-- [[ Lifecycle ]]

function Restart:Initialize(interface)
	self._interface = interface
	local gui = interface.PlayerGui:WaitForChild("Interface")
	local hud = gui:WaitForChild("HUD")
	local top = hud:WaitForChild("TopCenter")
	self._banner = top:WaitForChild("Restart")
	self._mini = top:WaitForChild("RestartMini")
	self._miniShadow = top:WaitForChild("RestartMiniShadow")
	self._game = interface:ResolveFrame("Interface", "Game")
	self._pill = self._game:WaitForChild("RestartPill")
	self._pillShadow = self._game:WaitForChild("RestartPillShadow")
	self._card = interface:ResolveFrame("Interface", "Restart")
	self._frame = self._card
	self._banner.Visible = false
	self._card.Visible = false

	-- (HOP and the clock pill get the HUD's hover / press scale: HUDController applies it to the HUD)
	local j = self._janitor
	j:Add(self._banner.Face.Activated:Connect(function()
		self._collapsed = true
		self:_tick()
	end))
	j:Add(self._mini.Activated:Connect(function()
		self._collapsed = false
		self:_tick()
	end))
	j:Add(self._banner.Hop.Activated:Connect(function()
		if os.clock() < self._hopUntil then
			return
		end
		self._hopUntil = os.clock() + HOP_COOLDOWN
		Sounds.Play("Click")
		RestartRemote:Fire({ Action = "Hop" })
		self:_tick()
	end))
	j:Add(RestartRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "HopFailed" then
			self._hopUntil = 0
			local hudController = interface:GetController("HUD")
			if hudController and hudController.Toast then
				hudController:Toast("Couldn't hop right now, try again in a moment")
			end
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy
	j:Add(ReplicatedStorage:GetAttributeChangedSignal("Restart"):Connect(function()
		self:_refresh()
	end))
	self:_refresh()
end

function Restart:Activate()
	return Promise.resolve()
end

function Restart:Deactivate()
	return Promise.resolve()
end

function Restart:Destroy()
	if self._ticker then
		task.cancel(self._ticker)
	end
	if self._spin then
		self._spin:Disconnect()
	end
	if self._slotJanitor then
		self._slotJanitor:Destroy()
	end
	self._janitor:Destroy()
end

return Restart
