--| PlayerCardController ("PlayerCard")
-- The card you get by clicking (or tapping) another player in the lobby
-- (Interface.Frames.PlayerCard, built by ./Build from the "Profile 2 · clicking another
-- player" board): their photocard, name, title, level and best board rank, four stats, their
-- 5-card showcase, their streak, and Invite to Duel.
-- Everything comes from their player attributes (DataService: Level, Title, TitleTier, Streak;
-- Engine/ProfileService: Wins, Duels, BestStreak, Perfect, SongsOwned, Showcase), so it
-- updates while the card is open. Invite to Duel asks InviteService to "Challenge" them: it
-- puts you on a free stage first if you aren't waiting on one, then sends the invite (the
-- queue card then shows it as sent).
-- Two ways in, lobby only (not while you're on a stage or another screen is up): click / tap the
-- player, or the "View Profile" prompt (F) that shows when you walk up to them — a copy of
-- ReplicatedStorage.Assets.ViewProfilePrompt on each other player's HumanoidRootPart, made here
-- on this client and off while either of you is on a stage.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Showcase = require(ReplicatedStorage.Modules.Showcase)
local SongCard = require(ReplicatedStorage.Modules.UI.SongCard)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local InviteRemote = Bridgenet.ReferenceBridge("InviteRemote")

local C = Color3.fromHex
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local CLICK_TIME = 0.35 -- a press longer than this (or one that moved) was a camera drag
local CLICK_MOVE = 10
local REACH = 250 -- studs a click can reach
local PROMPT_NAME = "ViewProfile" -- the copy on each character

-- the boards their rank line can come from, best first when tied
local BOARDS = {
	{ Name = "MostWins", Label = "Most Wins" },
	{ Name = "TopStreaks", Label = "Top Streaks" },
	{ Name = "PerfectGames", Label = "Perfect Games" },
	{ Name = "MostAnswers", Label = "Most Answers" },
	{ Name = "TopFans", Label = "Top Fans" },
}

-- --------------------------------- Helpers -------------------------------- --
local function commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted, k = s, 0
	repeat
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

local function number(player: Player, attribute: string): number
	local v = player:GetAttribute(attribute)
	return if type(v) == "number" then v else 0
end

-- coin multiplier for a streak (DuelConstants.STREAK_MULTIPLIERS = { {wins, mult}, ... })
local function multiplierFor(streak: number): number
	for _, step in DuelConstants.STREAK_MULTIPLIERS do
		if streak >= step[1] then
			return step[2]
		end
	end
	return 1
end

-- their best place on any board's kept top 100: "#2 Most Wins"
local function bestRank(userId: number): string
	local best, label = nil, nil
	for _, board in BOARDS do
		local ok, entries = pcall(PlayerData.GetLeaderboard, board.Name)
		if ok and type(entries) == "table" then
			for _, e in entries do
				if e.UserId == userId and type(e.Score) == "number" and e.Score > 0 then
					if best == nil or e.Rank < best then
						best, label = e.Rank, board.Label
					end
					break
				end
			end
		end
	end
	return if best then `#{best} {label}` else ""
end

-- ---------------------------------- Class --------------------------------- --
local PlayerCard = {}
PlayerCard.__index = PlayerCard

function PlayerCard.new()
	local self = setmetatable({}, PlayerCard)
	self.Name = "PlayerCard"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._watch = Janitor.new() -- the shown player's attribute listeners
	self._player = nil :: Player?
	self._note = nil :: string? -- a short answer on the Invite button ("No free stages")
	return (self :: any) :: UITypes.Controller
end

-- [[ Drawing ]]

function PlayerCard:_paint()
	local player = self._player
	if not player then
		return
	end
	local panel = self._frame.Panel
	local top, body = panel.Top, panel.Body

	top.PlayerName.Text = player.DisplayName
	top.Photocard.Photo.Avatar.Image = `rbxthumb://type=AvatarBust&id={player.UserId}&w=150&h=150`
	TitleChip.Paint(top.Chips.Title, player:GetAttribute("Title") or HUDConstants.DEFAULT_TITLE, player:GetAttribute("TitleTier") or "Normal")
	top.Chips.Level.Text = `LV {number(player, "Level")}`
	top.Rank.Text = bestRank(player.UserId)
	top.Rank.Visible = top.Rank.Text ~= ""
	-- season: their banner behind the top strip + their tier chip
	local _, tierInfo, banner, photocard = SeasonArt.Of(player)
	SeasonArt.PaintBanner(top:FindFirstChild("Banner"), banner)
	SeasonArt.PaintPhotocard(top.Photocard, photocard)
	SeasonArt.PaintChip(top.Chips:FindFirstChild("Tier"), tierInfo)

	body.Stats.Wins.Value.Text = commas(number(player, "Wins"))
	body.Stats.BestStreak.Value.Text = commas(number(player, "BestStreak"))
	body.Stats.Perfect.Value.Text = commas(number(player, "Perfect"))
	body.Stats.Songs.Value.Text = commas(number(player, "SongsOwned"))

	local cards = Showcase.Decode(player:GetAttribute("Showcase"))
	for i = 1, Build.SHOWCASE do
		local c = cards[i]
		SongCard.Paint(body.Showcase["Card" .. i], c and Songs.GetById(c.Id), c and c.Level)
	end
	body.Showcase.Empty.Visible = Showcase.Count(cards) == 0

	local streak = number(player, "Streak")
	local mult = multiplierFor(streak)
	body.Streak.Text.Text = if streak > 0 then `On a {streak} win streak` else "No win streak right now"
	body.Streak.Mult.Visible = mult > 1
	body.Streak.Mult.Text = `×{mult}`

	-- Invite to Duel: not while they're on a stage, or you're mid-duel
	local busy = player:GetAttribute("InDuel") or player:GetAttribute("Stage") or player:GetAttribute("PartyStage")
	local mine = LOCAL_PLAYER:GetAttribute("InDuel") or LOCAL_PLAYER:GetAttribute("PartyStage")
	local invite = body.Invite
	invite.Text = if self._note then self._note elseif busy then "ON A STAGE" elseif mine then "FINISH YOUR DUEL FIRST" else "INVITE TO DUEL"
	invite.Active = not busy and not mine and self._note == nil
	invite.AutoButtonColor = false
	invite.BackgroundColor3 = if invite.Active then MINT else GREY
	body.InviteShadow.Visible = invite.Active
end

function PlayerCard:_flash(note: string)
	self._note = note
	self:_paint()
	Juice.Shake(self._frame.Panel.Body.Invite, 4)
	local token = {}
	self._noteToken = token
	task.delay(2.5, function()
		if self._noteToken == token then
			self._note = nil
			if self.State ~= "Inactive" then
				self:_paint()
			end
		end
	end)
end

-- [[ Clicking players in the world ]]

function PlayerCard:_playerAt(screen: Vector2): Player?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LOCAL_PLAYER.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * REACH, params)
	local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return if player ~= LOCAL_PLAYER then player else nil
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

-- lobby only: no other screen up, not on a stage
function PlayerCard:_canOpen(): boolean
	local interface = self._interface
	if interface.Mode ~= "Gameplay" or interface.ActiveController ~= nil then
		return false
	end
	return not (LOCAL_PLAYER:GetAttribute("Stage") or LOCAL_PLAYER:GetAttribute("PartyStage"))
end

function PlayerCard:_tryOpenAt(screen: Vector2)
	if not self:_canOpen() then
		return
	end
	local player = self:_playerAt(screen)
	if player then
		self._interface:Open(self.Name, player)
	end
end

-- [[ The View Profile prompt ]]

local function onStage(player: Player): boolean
	return (player:GetAttribute("Stage") or player:GetAttribute("PartyStage") or player:GetAttribute("InDuel")) ~= nil
end

-- shown only in the lobby, for someone who isn't on a stage either
function PlayerCard:_updatePrompt(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChild(PROMPT_NAME)
	if prompt then
		prompt.Enabled = self._interface.Mode == "Gameplay" and not onStage(LOCAL_PLAYER) and not onStage(player)
	end
end

function PlayerCard:_updatePrompts()
	for _, player in Players:GetPlayers() do
		if player ~= LOCAL_PLAYER then
			self:_updatePrompt(player)
		end
	end
end

function PlayerCard:_addPrompt(player: Player, character: Model)
	local template = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("ViewProfilePrompt")
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not template or not root or root:FindFirstChild(PROMPT_NAME) then
		return
	end
	local prompt = template:Clone()
	prompt.Name = PROMPT_NAME
	prompt.ObjectText = player.DisplayName
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		if self:_canOpen() and player.Parent then
			self._interface:Open(self.Name, player)
		end
	end)
	self:_updatePrompt(player)
end

function PlayerCard:_bindPrompts()
	local j = self._janitor
	local function watch(player: Player)
		if player == LOCAL_PLAYER then
			return
		end
		j:Add(player.CharacterAdded:Connect(function(character)
			self:_addPrompt(player, character)
		end))
		if player.Character then
			task.spawn(self._addPrompt, self, player, player.Character)
		end
		for _, attribute in { "Stage", "PartyStage", "InDuel" } do
			j:Add(player:GetAttributeChangedSignal(attribute):Connect(function()
				self:_updatePrompt(player)
			end))
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	j:Add(Players.PlayerAdded:Connect(watch))
	for _, attribute in { "Stage", "PartyStage", "InDuel" } do
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal(attribute):Connect(function()
			self:_updatePrompts()
		end))
	end
	j:Add(self._interface.ModeChanged:Connect(function()
		self:_updatePrompts()
	end))
end

function PlayerCard:_bindClicks()
	local j = self._janitor
	local down: { At: number, Pos: Vector2 }? = nil
	j:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			down = { At = os.clock(), Pos = Vector2.new(input.Position.X, input.Position.Y) }
		end
	end))
	j:Add(UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not down then
			return
		end
		local press = down
		down = nil
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if not processed and os.clock() - press.At <= CLICK_TIME and (pos - press.Pos).Magnitude <= CLICK_MOVE then
			self:_tryOpenAt(pos)
		end
	end))
	-- phones / tablets: a tap (not a camera swipe)
	j:Add(UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if not processed then
			self:_tryOpenAt(position)
		end
	end))
end

-- -------------------------------- Lifecycle ------------------------------- --

function PlayerCard:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "PlayerCard")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor

	local function close()
		self._interface:Close(self.Name)
	end
	j:Add(panel.Top.Close.Activated:Connect(close))
	j:Add(self._frame.Away.Activated:Connect(close))
	j:Add(panel.Body.Invite.Activated:Connect(function()
		local player = self._player
		if not player or not panel.Body.Invite.Active then
			return
		end
		InviteRemote:Fire({ Action = "Challenge", Target = player.UserId })
		self._note = "SENDING…"
		self:_paint()
	end))
	j:Add(InviteRemote:Connect(function(packet)
		if type(packet) ~= "table" or self.State == "Inactive" then
			return
		end
		if packet.Message == "Sent" then
			self._note = nil
			close() -- you're on a stage now: the queue card shows the invite
		elseif packet.Message == "Result" then
			if packet.Result == "NoStage" then
				self:_flash("NO FREE STAGES")
			elseif packet.Result == "Failed" then
				self:_flash("CAN'T DUEL RIGHT NOW")
			end
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy
	j:Add(Players.PlayerRemoving:Connect(function(player: Player)
		if player == self._player and self.State ~= "Inactive" then
			close()
		end
	end))
	self:_bindClicks()
	self:_bindPrompts()
end

function PlayerCard:Activate(player: Player?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return Promise.reject("PlayerCard needs a player")
	end
	self._player = player
	self._note = nil
	self._watch:Cleanup()
	for _, attribute in { "Level", "Title", "TitleTier", "Streak", "Wins", "BestStreak", "Perfect", "SongsOwned", "Showcase", "InDuel", "Stage", "PartyStage", "Banner", "Photocard", "SeasonSP" } do
		self._watch:Add(player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_paint()
		end))
	end
	self._frame.Visible = true
	self:_paint()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local cards = self._frame.Panel.Body.Showcase
	Juice.Stagger({ cards.Card1, cards.Card2, cards.Card3, cards.Card4, cards.Card5 }, 0.04)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function PlayerCard:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self._watch:Cleanup()
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self._player = nil
		self.State = "Inactive"
	end)
end

function PlayerCard:Destroy()
	self._watch:Destroy()
	self._janitor:Destroy()
end

return PlayerCard
