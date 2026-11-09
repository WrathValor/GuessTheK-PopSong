--| ProfileController ("Profile")
-- Your profile (Interface.Frames.Profile, built by ./Build from the "Profile 1 · your card"
-- board), opened from the HUD's Profile tile:
--   • your photocard: avatar, name, equipped title (its tier), level badge, XP bar
--   • Change Title → the Inventory's Titles page
--   • six stat tiles from Statistics, each with a "#8 this week" tag while you're on that
--     board's kept top 100 (PlayerData Leaderboards)
--   • the showcase: 5 song card slots (Modules/Showcase)
--   • Edit (design board "Profile 3 · showcase"): the rest dims and each slot shows SLOT n.
--     Tap a slot → the Index picks its card (IndexController, Open("Index", { Slot, Showcase }))
--     and comes back here still editing; ✕ empties a slot; DONE (the Edit button) finishes.
--     Every change is saved through ProfileRemote (Engine/ProfileService checks it) and shows
--     straight away while the save comes back through PlayerData.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Levels = require(ReplicatedStorage.Modules.Levels)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Showcase = require(ReplicatedStorage.Modules.Showcase)
local SongCard = require(ReplicatedStorage.Modules.UI.SongCard)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ProfileRemote = Bridgenet.ReferenceBridge("ProfileRemote")

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PENDING_FOR = 5 -- seconds a just-saved pick shows before PlayerData must have it

-- stat tile → the board its rank tag comes from
local RANKS = {
	Wins = { Board = "WeeklyWins", Text = "this week" },
	BestStreak = { Board = "TopStreaks", Text = "all time" },
	Perfect = { Board = "PerfectGames", Text = "all time" },
	Correct = { Board = "WeeklyAnswers", Text = "this week" },
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

local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

local function owns(id: string): boolean
	local ok, yes = pcall(PlayerData.Inventory.Songs.Has, id)
	return ok and yes == true
end

local function copiesMap(): { [string]: number }
	local ok, map = pcall(PlayerData.Inventory.Copies.Get)
	return if ok and type(map) == "table" then map else {}
end

local function pins(): { string }
	local out = {}
	for _, key in Showcase.KEYS do
		table.insert(out, get(PlayerData.Profile.Showcase[key], ""))
	end
	return out
end

-- your place on a board, while you're on its kept list with a score
local function rankOn(board: string): number?
	local ok, entries = pcall(PlayerData.GetLeaderboard, board)
	if not ok or type(entries) ~= "table" then
		return nil
	end
	for _, e in entries do
		if e.UserId == LOCAL_PLAYER.UserId and type(e.Score) == "number" and e.Score > 0 then
			return e.Rank
		end
	end
	return nil
end

-- ---------------------------------- Class --------------------------------- --
local Profile = {}
Profile.__index = Profile

function Profile.new()
	local self = setmetatable({}, Profile)
	self.Name = "Profile"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._pending = nil :: { Ids: { string }, Until: number }? -- a showcase change just saved
	self._editing = false
	return (self :: any) :: UITypes.Controller
end

-- [[ Drawing ]]

function Profile:_paintCard()
	local left = self._frame.Panel.Content.Left
	local face = left.Photocard.Face
	face.PlayerName.Text = LOCAL_PLAYER.DisplayName
	face.Photo.Avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=420&h=420`
	TitleChip.Paint(face.Title, LOCAL_PLAYER:GetAttribute("Title") or HUDConstants.DEFAULT_TITLE, LOCAL_PLAYER:GetAttribute("TitleTier") or "Normal")

	local level, into, need = Levels.FromXP(get(PlayerData.Player.XP, 0))
	local maxed = level >= Levels.MAX_LEVEL
	face.LevelBadge.Level.Text = tostring(level)
	left.XP.Level.Text = `Level {level}`
	left.XP.Amount.Text = if maxed then "MAX" else `{commas(into)} / {commas(need)} XP`
	TweenService:Create(left.XP.Track.Fill, FILL_TWEEN, {
		Size = UDim2.fromScale(if maxed then 1 else math.clamp(into / math.max(need, 1), 0, 1), 1),
	}):Play()
end

function Profile:_paintStats()
	local stats = PlayerData.Statistics
	local tiles = self._frame.Panel.Content.Right.Stats
	local wins, duels = get(stats.Wins, 0), get(stats.Duels, 0)
	local owned, total = 0, 0
	for _, song in Songs.GetAllSongs() do
		total += 1
		owned += if owns(song.Id) then 1 else 0
	end
	local values = {
		Wins = { commas(wins), if duels > 0 then `{math.floor(wins / duels * 100 + 0.5)}% win rate` else "no duels yet" },
		BestStreak = { commas(get(stats.HighestStreak, 0)), `now on {get(PlayerData.Player.Streak, 0)}` },
		Perfect = { commas(get(stats.PerfectGames, 0)), "7–0 wins" },
		Correct = { commas(get(stats.CorrectAnswers, 0)), "duels + solo" },
		Songs = { commas(owned), `of {total} in the Index` },
		SoloBest = { commas(get(stats.SoloBest, 0)), "points in 7 rounds" },
	}
	for name, v in values do
		local tile = tiles[name]
		tile.Value.Text = v[1]
		tile.Sub.Text = v[2]
		local spec = RANKS[name]
		local rank = spec and rankOn(spec.Board)
		tile.Rank.Visible = rank ~= nil
		if rank then
			tile.Rank.Text = `#{rank} {spec.Text}`
		end
	end
end

-- the showcase as saved, or the pick you just made while its save is on the way
function Profile:_pins(): { string }
	local pending = self._pending
	if pending and os.clock() < pending.Until then
		local saved = pins()
		local same = true
		for i = 1, Showcase.SLOTS do
			if (saved[i] or "") ~= (pending.Ids[i] or "") then
				same = false
			end
		end
		if not same then
			return pending.Ids
		end
	end
	self._pending = nil
	return pins()
end

function Profile:_cards()
	return Showcase.Resolve(self:_pins(), owns, copiesMap())
end

function Profile:_paintShowcase()
	local content = self._frame.Panel.Content
	local right = content.Right
	local showcase = right.Showcase
	local cards = self:_cards()
	local editing = self._editing
	for i = 1, Build.SHOWCASE do
		local c = cards[i]
		local holder = showcase["Card" .. i]
		SongCard.Paint(holder, c and Songs.GetById(c.Id), c and c.Level)
		-- editing: every slot shows (an empty one as its Add tile) and can be tapped
		holder.Visible = c ~= nil or editing
		holder.Face.Visible = c ~= nil
		holder.Shadow.Visible = c ~= nil
		holder.Add.Visible = editing and c == nil
		holder.Slot.Visible = editing
		holder.Hit.Visible = editing
		holder.Unpin.Visible = editing and c ~= nil
	end
	showcase.Empty.Visible = not editing and Showcase.Count(cards) == 0
	content.DimLeft.Visible = editing
	content.DimStats.Visible = editing
	right.ShowcaseSub.Text = if editing then "tap a card to swap it" else "5 cards everyone sees"
	local edit = right.Edit
	edit.Label.Text = if editing then "DONE" else "EDIT"
	edit.Icon.Visible = not editing
	edit.Label.Position = UDim2.fromOffset(if editing then 0 else 42, 0)
	edit.Label.Size = UDim2.new(1, if editing then 0 else -50, 1, 0)
	edit.Label.TextXAlignment = if editing then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	edit.BackgroundColor3 = if editing then MINT else WHITE
end

-- saves a new showcase (5 ids by slot, "" = empty) and shows it right away
function Profile:_save(ids: { string })
	ProfileRemote:Fire({ Action = "SetShowcase", Songs = ids })
	self._pending = { Ids = ids, Until = os.clock() + PENDING_FOR }
	self:_paintShowcase()
end

function Profile:_refresh()
	self:_paintCard()
	self:_paintStats()
	self:_paintShowcase()
end

-- -------------------------------- Lifecycle ------------------------------- --

function Profile:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Profile")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor
	local right = panel.Content.Right

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(panel.Content.Left.ChangeTitle.Activated:Connect(function()
		self._interface:Open("Inventory", "Titles")
	end))
	-- Edit / Done
	j:Add(right.Edit.Activated:Connect(function()
		self._editing = not self._editing
		self:_paintShowcase()
		if self._editing then
			local showcase = right.Showcase
			Juice.Stagger({ showcase.Card1, showcase.Card2, showcase.Card3, showcase.Card4, showcase.Card5 }, 0.04)
		end
	end))
	for i = 1, Build.SHOWCASE do
		local holder = right.Showcase["Card" .. i]
		-- a slot: pick its card in the Index
		j:Add(holder.Hit.Activated:Connect(function()
			Juice.Pop(holder, 0.1)
			self._interface:Open("Index", { Slot = i, Showcase = Showcase.Ids(self:_cards()) })
		end))
		-- ✕: empty the slot (the others stay where they are)
		j:Add(holder.Unpin.Activated:Connect(function()
			local ids = Showcase.Ids(self:_cards())
			ids[i] = ""
			self:_save(ids)
		end))
	end

	-- redraw while open when anything shown changes
	local function changed()
		if self.State ~= "Inactive" then
			self:_refresh()
		end
	end
	local stats = PlayerData.Statistics
	for _, path in {
		PlayerData.Player.XP, PlayerData.Player.Streak, stats.Wins, stats.Duels, stats.HighestStreak,
		stats.PerfectGames, stats.CorrectAnswers, stats.SoloBest, PlayerData.Inventory.Songs, PlayerData.Inventory.Copies,
	} do
		j:Add(path.Observe(changed))
	end
	for _, key in Showcase.KEYS do
		j:Add(PlayerData.Profile.Showcase[key].Observe(function()
			if self.State ~= "Inactive" then
				self:_paintShowcase()
			end
		end))
	end
	j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("Title"):Connect(changed))
	j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("TitleTier"):Connect(changed))
end

function Profile:Activate(opts: any?)
	-- back from the Index: the slot it just filled shows now, and you're still editing
	local fromIndex = type(opts) == "table" and type(opts.Showcase) == "table"
	if fromIndex then
		self._pending = { Ids = opts.Showcase, Until = os.clock() + PENDING_FOR }
	end
	self._editing = fromIndex and opts.Editing == true
	self._frame.Visible = true
	self:_refresh()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local right = self._frame.Panel.Content.Right
	local list = {}
	for _, spec in Build.STATS do
		table.insert(list, right.Stats[spec.Name])
	end
	for i = 1, Build.SHOWCASE do
		table.insert(list, right.Showcase["Card" .. i])
	end
	Juice.Stagger(list, 0.04)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Profile:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Profile:Destroy()
	self._janitor:Destroy()
end

return Profile
