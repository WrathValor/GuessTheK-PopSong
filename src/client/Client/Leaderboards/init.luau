--| Leaderboards
-- The two signs at Map.Landmarks.Leaderboards (design board "Leaderboards v2 · one big board
-- with tabs + Join the Group"): Board1 the big leaderboard (32×20 studs, 1280 × 800) and Board2
-- Join the Group (16×20, 640 × 800). The signs are SurfaceGui instances in StarterGui
-- ("Leaderboard_Main" / "Leaderboard_JoinTheGroup", built once by ./Build); this script points
-- each at its part (its "Board" attribute) and fills it in. They live in PlayerGui so the
-- buttons work and each player sees their own tab, row and Join state.
-- The big board has a tab per PlayerData board (Weekly Wins, Weekly Answers, Top Streaks,
-- Perfect Games, Top Fans). It flips to the next one every FLIP seconds until you tap a tab,
-- and starts again once you've left it alone for IDLE seconds; the sign and its frame part
-- (tinted on this client only) take the open board's colours. The pinned YOU row is your
-- place in the board's kept top 100 (Scribe keeps 100 per board), "100+" below that, "—"
-- with nothing on it yet. Data comes from Scribe (PlayerData Leaderboards).
-- Join button: Join the group (Roblox prompt) → Claim rewards → Claimed ✓ (RewardsService
-- checks everything again).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local Levels = require(ReplicatedStorage.Modules.Levels)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local MINE = C("FFF1B8") -- your own row

local KEPT = 100 -- entries Scribe keeps per board (PlayerData Leaderboards Limit)
local FLIP = 10 -- seconds between boards while nobody's tapped a tab
local IDLE = 30 -- seconds after your last tap before it flips again
local TAB_OFF = C("FFFFFF")
local LIST_TINT = 0.12 -- the list panel: the board's colour, a shade darker (not cream)

local Leaderboards = {}

-- How each board looks and shows its numbers, in tab order (Build.TABS). Face / Frame are
-- the sign's and the frame part's colours, Sub the header line (a weekly board counts down to
-- its reset), Unit follows the podium values, Format turns a score into text, Local is your
-- own value for when you're past the top 100 on a lifetime board.
local function own(path): () -> number?
	return function()
		return path.Get()
	end
end
local BOARDS = {
	WeeklyWins = { Face = C("A7E9B8"), Frame = C("9ED8F5"), SubColour = YELLOW, Sub = "MOST WINS THIS WEEK", Weekly = true, Unit = "wins" },
	WeeklyAnswers = { Face = C("9ED8F5"), Frame = C("A7E9B8"), SubColour = C("9ED8F5"), Sub = "MOST CORRECT THIS WEEK", Weekly = true, Unit = "right" },
	TopStreaks = { Face = C("B9A6FF"), Frame = YELLOW, SubColour = C("FF9EC4"), Sub = "BEST WIN STREAK · ALL TIME", Unit = "streak", Local = own(PlayerData.Statistics.HighestStreak) },
	PerfectGames = { Face = YELLOW, Frame = C("FF9EC4"), SubColour = YELLOW, Sub = "7–0 WINS · ALL TIME", Unit = "perfect", Local = own(PlayerData.Statistics.PerfectGames) },
	TopFans = {
		Face = C("FF9EC4"), -- full-strength pastels, like Join's pink (pale ones wash out under the bloom)
		Frame = C("B9A6FF"),
		SubColour = C("FF9EC4"),
		Sub = "HIGHEST LEVEL · ALL TIME",
		Format = function(xp: number): string
			return `Lv {Levels.FromXP(xp)}`
		end,
		Local = own(PlayerData.Player.XP),
	},
}
local ORDER = { "WeeklyWins", "WeeklyAnswers", "TopStreaks", "PerfectGames", "TopFans" }

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- weekly boards reset Monday 00:00 UTC (PlayerData PeriodReset)
local WEEK, MONDAY0 = 7 * 86400, 4 * 86400 -- 1970-01-05 was a Monday
local function resetText(): string
	local now = os.time()
	local left = (math.floor((now - MONDAY0) / WEEK) + 1) * WEEK + MONDAY0 - now
	local d, h = math.floor(left / 86400), math.floor(left % 86400 / 3600)
	return if d > 0 then `RESETS MONDAY · {d}D {h}H` else `RESETS IN {h}H {math.floor(left % 3600 / 60)}M`
end

-- ------------------------------ The big board ------------------------------ --

local function bindMain(gui: SurfaceGui, framePart: BasePart?)
	local sign = gui.Sign
	local podium, list, you = sign.Podium, sign.List, sign.You
	you.PlayerName.Text = LOCAL_PLAYER.DisplayName
	local current = ORDER[1]
	local lastTap = -math.huge

	local function format(spec, score: number): string
		return if spec.Format then spec.Format(score) else tostring(score)
	end

	local function fillYou(spec, all: { any })
		local mine = nil
		for _, e in all do
			if e.UserId == LOCAL_PLAYER.UserId and type(e.Score) == "number" and e.Score > 0 then
				mine = e
				break
			end
		end
		if mine then
			you.Rank.Text = `#{mine.Rank}`
			you.Value.Text = format(spec, mine.Score)
			return
		end
		local ok, value = pcall(function()
			return if spec.Local then spec.Local() else nil
		end)
		value = if ok and type(value) == "number" then value else nil
		-- not on the kept list: past the top 100 (when it's full), else not on the board yet
		you.Rank.Text = if #all >= KEPT and (value == nil or value > 0) then `{KEPT}+` else "—"
		you.Value.Text = if value then format(spec, value) else ""
	end

	local function fill()
		local spec = BOARDS[current]
		local ok, entries = pcall(PlayerData.GetLeaderboard, current)
		entries = if ok and type(entries) == "table" then entries else {}
		fillYou(spec, entries)
		-- nobody shows with a score of 0 (a fresh week, or a streak that never started)
		local shown = {}
		for _, e in entries do
			if type(e.Score) ~= "number" or e.Score > 0 then
				table.insert(shown, e)
			end
		end
		for place = 1, 10 do
			local e = shown[place]
			local mine = e ~= nil and e.UserId == LOCAL_PLAYER.UserId
			local value = if e then (if type(e.Score) == "number" then format(spec, e.Score) else tostring(e.Score)) else ""
			if place <= 3 then
				local face = podium["Place" .. place].Card.Face
				face.PlayerName.Text = if e then e.Name else "—"
				face.Value.Text = if e then (if spec.Unit then `{value} {spec.Unit}` else value) else ""
				face.Photo.Avatar.Image = if e then headshot(e.UserId) else ""
				face.BackgroundColor3 = if mine then MINE else WHITE
			else
				local r = list["Row" .. place]
				r.PlayerName.Text = if e then e.Name else "—"
				r.Value.Text = value
				r.BackgroundColor3 = if mine then MINE else WHITE
			end
		end
	end

	-- the open board's colours, its header line and which tab is up
	local function paint()
		local spec = BOARDS[current]
		sign.BackgroundColor3 = spec.Face
		sign.List.BackgroundColor3 = spec.Face:Lerp(INK, LIST_TINT)
		if framePart then
			framePart.Color = spec.Frame -- this client only
		end
		sign.Header.Sub.TextColor3 = spec.SubColour
		sign.Header.Sub.Text = if spec.Weekly then `{spec.Sub} · {resetText()}` else spec.Sub
		for _, name in ORDER do
			local tab = sign.Tabs[name]
			local on = name == current
			tab.BackgroundColor3 = if on then BOARDS[name].Frame else TAB_OFF
			tab.Position = UDim2.fromOffset(tab.Position.X.Offset, if on then 13 else 16)
			sign.Tabs[name .. "Shadow"].Visible = on
		end
	end

	local function show(name: string)
		current = name
		paint()
		fill()
	end

	for _, name in ORDER do
		sign.Tabs[name].Activated:Connect(function()
			lastTap = os.clock()
			if name ~= current then
				show(name)
			end
		end)
	end
	show(current)
	pcall(function()
		PlayerData.OnLeaderboard:Connect(function(boardName)
			if boardName == current then
				fill()
			end
		end)
	end)
	-- flip through the boards (unless you're reading one), keep the countdown and the
	-- replicated cache fresh (it can land before OnLeaderboard is hooked)
	task.spawn(function()
		local sinceFlip = 0
		while gui.Parent do
			task.wait(1)
			sinceFlip += 1
			if sinceFlip >= FLIP then
				sinceFlip = 0
				if os.clock() - lastTap >= IDLE then
					show(ORDER[(table.find(ORDER, current) or 0) % #ORDER + 1])
				else
					paint()
					fill()
				end
			end
		end
	end)
end

-- ------------------------------ Join the Group ----------------------------- --

local JOIN_STATES = {
	Join = { Note = "Join Wrath's UGC to unlock all three", Label = "JOIN THE GROUP", Bg = MINT, Text = INK, Shadow = true },
	Claim = { Note = "You're in! Your rewards are waiting", Label = "CLAIM REWARDS", Bg = YELLOW, Text = INK, Shadow = true },
	Claimed = { Note = "Thanks for joining Wrath's UGC", Label = "CLAIMED ✓", Bg = GREY, Text = C("6B647A"), Shadow = false },
}

local function bindJoin(gui: SurfaceGui)
	local face = gui.Sign
	-- the real group stage with your avatar on it, like the shop cards; the drawn shapes in
	-- the art only show until the model has loaded
	CosmeticView.Show(face.Stage.Art, "Stage", RewardsCatalog.GROUP.Stage)

	local note, button, shadow = face.Note, face.Button, face.ButtonShadow
	local inGroup = false
	local busy = false
	local function claimed(): boolean
		local ok, v = pcall(PlayerData.Rewards.Claimed.Has, RewardsCatalog.GROUP.ClaimedKey)
		return ok and v == true
	end
	local function state(): string
		return if claimed() then "Claimed" elseif inGroup then "Claim" else "Join"
	end
	local function paint()
		local s = JOIN_STATES[state()]
		note.Text = s.Note
		button.Text = if busy then "…" else s.Label
		button.BackgroundColor3 = s.Bg
		button.TextColor3 = s.Text
		shadow.Visible = s.Shadow
		button.Active = state() ~= "Claimed"
	end

	button.Activated:Connect(function()
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
				local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, RewardsCatalog.GROUP.GroupId)
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
		local ok, member = pcall(LOCAL_PLAYER.IsInGroup, LOCAL_PLAYER, RewardsCatalog.GROUP.GroupId)
		inGroup = ok and member == true
		paint()
	end)
	paint()
end

-- ---------------------------------- Start ---------------------------------- --

-- Points a sign at its part (its "Board" attribute). Returns the part, or nil when the map
-- has no such part yet, and the sign stays off.
local function attach(gui: SurfaceGui, folder: Instance): BasePart?
	local part = folder:WaitForChild(gui:GetAttribute("Board") or "", 10)
	if not part or not part:IsA("BasePart") then
		gui.Enabled = false
		return nil
	end
	-- the placeholder text on the part itself goes (the sign is drawn here)
	for _, g in part:GetChildren() do
		if g:IsA("SurfaceGui") then
			g.Enabled = false
		end
	end
	gui.Adornee = part
	gui.Enabled = true
	return part
end

function Leaderboards.Start()
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		local folder = map and map:WaitForChild("Landmarks", 30)
		folder = folder and folder:WaitForChild("Leaderboards", 30)
		if not folder then
			warn("[Leaderboards] Map.Landmarks.Leaderboards not found")
			return
		end
		local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
		local main = playerGui:WaitForChild("Leaderboard_Main", 10)
		if main and attach(main, folder) then
			local frame = folder:FindFirstChild(main:GetAttribute("Frame") or "")
			bindMain(main, if frame and frame:IsA("BasePart") then frame else nil)
		end
		local join = playerGui:WaitForChild("Leaderboard_JoinTheGroup", 10)
		if join and attach(join, folder) then
			bindJoin(join)
		end
	end)
end

return Leaderboards
