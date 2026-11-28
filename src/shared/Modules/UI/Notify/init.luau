--| Notify
-- The game's one notification stack (design board "57 · Notifications"): top centre under the
-- Roblox bar, at most MAX at once with the newest on top. Every screen's old toast routes here.
--   Notify.Show(kind, title, body?, opts?)  – kind "Success" | "Notify" | "Neutral" | "Error".
--                                             With a body: the full card (title, body, timer bar);
--                                             without: the one-line pill
--   Notify.Toast(text, opts?)               – a pill whose kind comes from Notify.Guess(text)
--   Notify.Guess(text)                      – a best guess at the kind from the words
--   Notify.OnGetCoins(fn)                   – what "Get coins" does (the HUD opens the Shop's
--                                             coins); a "Not enough coins" toast then becomes a
--                                             card with that button
-- opts: Kind (Toast only), Duration (s), OnTap (tapping the face; Notify kind shows it can be
-- tapped), Action + OnAction (one button on a card, e.g. "Get coins"), Silent (no cue).
-- The same text already showing just restarts its timer instead of stacking twice. A mouse
-- hovering pauses the timer (for up to HOLD_MAX s); tapping dismisses. Each kind plays its own
-- cue (Sounds Notify*), unless the caller just played one of CALLER_CUES itself (or opts.Silent).
-- The instances (Interface.Notify) come from Notify/Build, built in Studio.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Modules.Sounds)

local Notify = {}

local C = Color3.fromHex
local MAX = 3
local GAP = 8 -- px under the Roblox bar
local PILL_MAX = 520
local HOLD_MAX = 6 -- a hover pauses the timer for at most this long
local IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

export type Kind = "Success" | "Notify" | "Neutral" | "Error"
export type Opts = {
	Kind: Kind?,
	Duration: number?,
	OnTap: (() -> ())?,
	Action: string?,
	OnAction: (() -> ())?,
	Silent: boolean?,
}

local KINDS = {
	Success = { Top = "E8FBEE", Bottom = "C8F2D3", Disc = "A7E9B8", Timer = "3CB371", Icon = 72460635358978, Time = 2.6, Sound = "NotifySuccess" },
	Notify = { Top = "FFF0F6", Bottom = "FFD2E3", Disc = "FF9EC4", Timer = "FF5A4E", Icon = 139039486662323, Time = 4, Sound = "NotifyBell" },
	Neutral = { Top = "FBF7F0", Bottom = "FBF7F0", Disc = "E6E1F0", Timer = "9B93B0", Icon = 122114555556399, Time = 2.6, Sound = "NotifyNeutral" },
	Error = { Top = "FFF0EE", Bottom = "FFD2CE", Disc = "FF5A4E", Timer = "FF5A4E", Icon = 130889089561782, Time = 3, Sound = "NotifyError" },
}

-- cues a caller may already have played for the same moment: then the notification stays quiet
local CALLER_CUES = { "Wrong", "Success", "Correct", "Coins", "Win", "Lose" }

-- words that mark a message's kind, checked in this order (lower case, plain find)
local GUESS = {
	{ "Error", { "not enough", "can't", "cannot", "couldn't", "don't have", "no player", "isn't", "first", "not now", "no answer", "too many", "full", "failed" } },
	{ "Neutral", { "coming soon", "yet", "waiting", "left the server", "tap again", "unpinned", "asked " } },
	{ "Success", { "!", "+", "sold", "claimed", "sent", "pinned", "collected", "complete", "accepted", "unlocked", "bought" } },
}

type Entry = {
	Slot: Frame,
	Group: CanvasGroup,
	Fill: Frame?,
	Text: string,
	Duration: number,
	Left: number,
	Paused: boolean,
	Held: number, -- seconds paused so far (capped at HOLD_MAX)
	Gone: boolean,
}

local live: { Entry } = {} -- newest first
local getCoins: (() -> ())? = nil
local order = 0
local beat: RBXScriptConnection? = nil

-- [[ Placement ]]

local function root(): Frame?
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	return interface and interface:FindFirstChild("Notify") :: Frame?
end

-- under the Roblox bar, scaled with the screen like the 1280×720 canvas
local function place(notify: Frame)
	local stack = notify.Stack :: Frame
	local view = notify.AbsoluteSize
	local scale = math.clamp(math.min(view.X / 1280, view.Y / 720), 0.45, 1) -- (was a 0.7 floor: far too big on phones)
	local bar = GuiService.TopbarInset.Max.Y
	if bar <= 0 then
		bar = 58
	end
	-- (measured from the ScreenGui's own top: an IgnoreGuiInset gui reports AbsolutePosition
	-- 58px up some moments and 0 at others, which dropped the stack a whole bar too low)
	local gui = notify:FindFirstAncestorOfClass("ScreenGui")
	local top = notify.AbsolutePosition.Y - (if gui then gui.AbsolutePosition.Y else 0)
	stack.Position = UDim2.new(0.5, 0, 0, bar + GAP - top)
	local uiScale = stack:FindFirstChild("Scale") :: UIScale
	uiScale.Scale = scale
end

-- [[ Showing / hiding ]]

local function dismiss(entry: Entry, quick: boolean?)
	if entry.Gone then
		return
	end
	entry.Gone = true
	local i = table.find(live, entry)
	if i then
		table.remove(live, i)
	end
	local info = if quick then TweenInfo.new(0.12) else OUT
	TweenService:Create(entry.Group, info, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) }):Play()
	task.delay(info.Time, function()
		entry.Slot:Destroy()
	end)
end

local function tick(dt: number)
	for i = #live, 1, -1 do
		local entry = live[i]
		if entry and entry.Paused and entry.Held < HOLD_MAX then
			entry.Held += dt
		elseif entry then
			entry.Left -= dt
			if entry.Fill then
				entry.Fill.Size = UDim2.fromScale(math.max(entry.Left / entry.Duration, 0), 1)
			end
			if entry.Left <= 0 then
				dismiss(entry)
			end
		end
	end
	if #live == 0 and beat then
		beat:Disconnect()
		beat = nil
	end
end

-- a little hop for a message that's already up
local function bump(entry: Entry)
	entry.Left = entry.Duration
	entry.Held = 0
	local g = entry.Group
	g.Position = UDim2.fromOffset(0, -5)
	TweenService:Create(g, IN, { Position = UDim2.fromOffset(0, 0) }):Play()
end

local function width(text: string, face: GuiObject): number
	local label = face:FindFirstChild("Text") :: TextLabel
	local ok, size = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = label.FontFace
		params.Size = label.TextSize
		params.Width = 2000
		return TextService:GetTextBoundsAsync(params)
	end)
	local w = if ok then size.X else #text * 8
	return math.min(math.ceil(w) + 42 + 18, PILL_MAX)
end

local function paint(face: GuiObject, kind: Kind)
	local look = KINDS[kind]
	local tint = face:FindFirstChild("Tint") :: UIGradient
	tint.Color = ColorSequence.new(C(look.Top), C(look.Bottom))
	local disc = face:FindFirstChild("Disc") :: Frame
	disc.BackgroundColor3 = C(look.Disc)
	local icon = disc:FindFirstChild("Icon") :: ImageLabel
	icon.Image = "rbxassetid://" .. look.Icon
end

function Notify.Show(kind: Kind, title: string, body: string?, opts: Opts?): ()
	local notify = root()
	if not notify or not title or title == "" then
		return
	end
	opts = opts or {}
	kind = if KINDS[kind] then kind else "Neutral"
	local key = title .. "\n" .. (body or "")

	for _, entry in live do
		if entry.Text == key then
			bump(entry)
			return
		end
	end

	place(notify)
	local card = body ~= nil and body ~= ""
	local templates = notify:FindFirstChild("Templates") :: Frame
	local slot = (templates:FindFirstChild(if card then "Card" else "Pill") :: Frame):Clone()
	local group = slot:FindFirstChild("Group") :: CanvasGroup
	local face = group:FindFirstChild("Face") :: TextButton
	paint(face, kind)

	local look = KINDS[kind]
	local fill: Frame? = nil
	if card then
		local titleLabel = face:FindFirstChild("Title") :: TextLabel
		local bodyLabel = face:FindFirstChild("Body") :: TextLabel
		titleLabel.Text = title
		bodyLabel.Text = body :: string
		local bar = (face:FindFirstChild("Timer") :: Frame):FindFirstChild("Fill") :: Frame
		bar.BackgroundColor3 = C(look.Timer)
		fill = bar
	else
		local label = face:FindFirstChild("Text") :: TextLabel
		label.Text = title
		local w = width(title, face)
		slot.Size = UDim2.fromOffset(w + 10, slot.Size.Y.Offset) -- (the face + its outline and shadow: Notify/Build PAD)
	end

	local entry: Entry = {
		Slot = slot,
		Group = group,
		Fill = fill,
		Text = key,
		Duration = opts.Duration or look.Time,
		Left = opts.Duration or look.Time,
		Paused = false,
		Held = 0,
		Gone = false,
	}

	-- the one action (cards only), else hidden
	local action = face:FindFirstChild("Action") :: TextButton?
	if action then
		if opts.Action and card then
			action.Text = opts.Action
			action.Visible = true
			local title_ = face:FindFirstChild("Title") :: TextLabel
			local body_ = face:FindFirstChild("Body") :: TextLabel
			title_.Size = UDim2.new(1, -82 - 120, 0, 22)
			body_.Size = UDim2.new(1, -82 - 120, 0, 18)
			action.Activated:Connect(function()
				if opts.OnAction then
					task.spawn(opts.OnAction)
				end
				dismiss(entry)
			end)
		else
			action.Visible = false
		end
	end

	-- only a real mouse pauses it (touches fire hovers that never end)
	face.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			entry.Paused = true
		end
	end)
	face.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			entry.Paused = false
		end
	end)
	face.Activated:Connect(function()
		if opts.OnTap then
			task.spawn(opts.OnTap)
		end
		dismiss(entry)
	end)

	-- newest on top; the oldest goes when there are too many
	order += 1
	slot.LayoutOrder = -order
	table.insert(live, 1, entry)
	while #live > MAX do
		dismiss(live[#live], true)
	end

	if not opts.Silent and not Sounds.PlayedWithin(CALLER_CUES, 0.3) then
		Sounds.Play(look.Sound)
	end

	group.GroupTransparency = 1
	group.Position = UDim2.fromOffset(0, -14)
	slot.Parent = notify.Stack
	TweenService:Create(group, IN, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }):Play()

	if not beat then
		beat = RunService.Heartbeat:Connect(tick)
	end
end

function Notify.Guess(text: string): Kind
	local lower = string.lower(text)
	for _, rule in GUESS do
		for _, word in rule[2] do
			if string.find(lower, word, 1, true) then
				return rule[1] :: Kind
			end
		end
	end
	return "Neutral"
end

function Notify.Toast(text: string?, opts: Opts?): ()
	if not text or text == "" then
		return
	end
	local kind = (opts and opts.Kind) or Notify.Guess(text)
	if getCoins and string.lower(text) == "not enough coins" then
		return Notify.Show("Error", "Not enough coins", "Grab a coin pack to keep going", {
			Action = "Get coins",
			OnAction = getCoins,
		})
	end
	Notify.Show(kind, text, nil, opts)
end

function Notify.OnGetCoins(fn: () -> ())
	getCoins = fn
end

return Notify
