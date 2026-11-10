--| Loading
-- The loading screen (design board "Loading A · photocard + equaliser"). Runs from
-- ReplicatedFirst, so it's up before anything else arrives, and replaces Roblox's default one.
-- Built in code: StarterGui hasn't replicated yet when this runs.
--
-- It stays up until, in order: the place has loaded (25%), the player's data has arrived (50%),
-- every Interface controller has started (LocalPlayer attribute "UIReady", 80%), and the
-- Interface's images have preloaded (80 → 100%). Then it fades out and sets the LocalPlayer
-- attribute "LoadingDone" (the tutorial's Welcome card waits for it). Skip shows after
-- SKIP_AFTER seconds in case something hangs.

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LOCAL_PLAYER = Players.LocalPlayer

--| Constants

local MIN_TIME = 1.5 -- never flash: stay up at least this long
local SKIP_AFTER = 8
local GIVE_UP = 45 -- stop waiting on any one step after this long
local TIP_TIME = 3.2

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local PINK = C("FF9EC4")
local LILAC = C("B9A6FF")
local MINT = C("A7E9B8")
local BLUE = C("9ED8F5")
local MUTED = C("5C566B")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local STEPS = {
	{ At = 0, Text = "Tuning the mics…" },
	{ At = 25, Text = "Loading the street…" },
	{ At = 50, Text = "Shuffling the songs…" },
	{ At = 80, Text = "Setting up your stage…" },
}
local TIPS = {
	"Guess from the shortest clip for <b>+10</b>. Every longer clip is worth less.",
	"Win streaks multiply the coins you win.",
	"Lose your streak? You can save it right after the game.",
	"Roll songs in the shop to fill your <b>Index</b>.",
	"Practise solo on any era or generation from the queue card.",
	"Invite a friend to a duel from the queue card.",
}

--| UI

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end

local function stroke(p: Instance, t: number)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local base = { BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a frame with a hard ink shadow behind it; both rotate together
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, rot: number, r: number, border: number, shadow: number)
	local s = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = pos + UDim2.fromOffset(shadow, shadow), Size = size, BackgroundColor3 = INK, Rotation = rot }, parent)
	corner(s, r)
	-- CanvasGroup so children rotate with it
	local f = new("CanvasGroup", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, BackgroundColor3 = colour, Rotation = rot }, parent)
	corner(f, r)
	stroke(f, border)
	return f, s
end

local gui = new("ScreenGui", { Name = "Loading", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
-- the map renders behind, blurred, as it streams in
local scrim = new("Frame", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0 }, gui)
local blur = new("BlurEffect", { Name = "LoadingBlur", Size = 18 }, Lighting)

local canvas = new("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, gui)
local scale = new("UIScale", {}, canvas)
local function fit()
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.ViewportSize
		scale.Scale = math.min(v.X / 1280, v.Y / 720)
	end
end
fit()
task.spawn(function()
	while not workspace.CurrentCamera do
		task.wait()
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
end)

-- logo: GUESS THE tag + K-POP SONG
local tag = card(canvas, "Tag", UDim2.fromOffset(640, 110), UDim2.fromOffset(190, 40), YELLOW, -2, 12, 4, 5)
text(tag, { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 24, Text = "GUESS THE" })
local title = text(canvas, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 180), Size = UDim2.fromOffset(700, 84), FontFace = HEAD, TextSize = 72, TextColor3 = CREAM, Text = "K-POP SONG", Rotation = -2 })
new("UIStroke", { Color = INK, Thickness = 4 }, title)
local titleShadow = title:Clone(); titleShadow.Name = "TitleShadow"; titleShadow.TextColor3 = INK; titleShadow.Position = title.Position + UDim2.fromOffset(6, 6); titleShadow.ZIndex = 0; titleShadow.Parent = canvas

-- photocard with the equaliser
local photo = card(canvas, "Photocard", UDim2.fromOffset(640, 403), UDim2.fromOffset(210, 270), CREAM, 3, 16, 4, 7)
local screen = new("Frame", { Name = "Screen", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -64), BackgroundColor3 = LILAC }, photo)
corner(screen, 10)
stroke(screen, 3)
local BAR_H = { 40, 72, 54, 96, 62, 84, 46 }
local BAR_C = { PINK, YELLOW, BLUE, CREAM, MINT, YELLOW, PINK }
local bars = {}
for i, h in BAR_H do
	local b = new("Frame", { Name = "Bar" .. i, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, (i - 4) * 22, 1, -22), Size = UDim2.fromOffset(14, h), BackgroundColor3 = BAR_C[i] }, screen)
	corner(b, 5)
	stroke(b, 3)
	bars[i] = b
end
text(photo, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.fromOffset(120, 20), FontFace = HEAD, TextSize = 15, Text = "NOW LOADING", TextXAlignment = Enum.TextXAlignment.Left })
local pctChip = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(46, 20), BackgroundColor3 = PINK }, photo)
corner(pctChip, 6)
stroke(pctChip, 2)
local pctLabel = text(pctChip, { Size = UDim2.fromScale(1, 1), TextSize = 12, Text = "0%" })

-- progress bar + step
local barShadow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(644, 578), Size = UDim2.fromOffset(460, 22), BackgroundColor3 = INK }, canvas)
corner(barShadow, 11)
local track = new("CanvasGroup", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 574), Size = UDim2.fromOffset(460, 22), BackgroundColor3 = CREAM }, canvas)
corner(track, 11)
stroke(track, 3)
local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = PINK, BorderSizePixel = 0 }, track)
new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, fill)
local stepLabel = text(canvas, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 606), Size = UDim2.fromOffset(460, 20), TextSize = 16, TextColor3 = CREAM, Text = STEPS[1].Text })

-- tip card (bottom right)
local tip = card(canvas, "Tip", UDim2.fromOffset(1280 - 28 - 150, 720 - 26 - 42), UDim2.fromOffset(300, 84), WHITE, -1.5, 12, 3, 4)
local tipChip = new("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(34, 18), BackgroundColor3 = MINT }, tip)
corner(tipChip, 6)
stroke(tipChip, 2)
text(tipChip, { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 10, Text = "TIP" })
local tipCount = text(tip, { Position = UDim2.fromOffset(54, 10), Size = UDim2.fromOffset(60, 18), TextSize = 12, TextColor3 = MUTED, Text = "1 / " .. #TIPS, TextXAlignment = Enum.TextXAlignment.Left })
local tipText = text(tip, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 44), FontFace = BODY_BOLD, TextSize = 14, TextWrapped = true, RichText = true, Text = TIPS[1], TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })

-- skip: centred under the progress bar + step line, shows after SKIP_AFTER
local skipShadow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640 + 3, 638 + 3), Size = UDim2.fromOffset(84, 38), BackgroundColor3 = INK, Visible = false }, canvas)
corner(skipShadow, 10)
local skip = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 638), Size = UDim2.fromOffset(84, 38), BackgroundColor3 = WHITE, AutoButtonColor = true, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "Skip", Visible = false }, canvas)
corner(skip, 10)
stroke(skip, 3)

gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

--| Motion

local alive = true
for i, b in bars do
	task.spawn(function()
		local period = 0.6 + i * 0.09
		task.wait(i * 0.07)
		while alive do
			TweenService:Create(b, TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Size = UDim2.fromOffset(14, BAR_H[i] * 0.35) }):Play()
			task.wait(period / 2)
			if not alive then break end
			TweenService:Create(b, TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Size = UDim2.fromOffset(14, BAR_H[i]) }):Play()
			task.wait(period / 2)
		end
	end)
end
task.spawn(function()
	local i = 1
	while alive do
		task.wait(TIP_TIME)
		i = i % #TIPS + 1
		tipText.Text = TIPS[i]
		tipCount.Text = `{i} / {#TIPS}`
	end
end)

local shown = 0
local function setProgress(p: number)
	p = math.clamp(p, 0, 100)
	if p < shown then return end
	shown = p
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(p / 100, 1) }):Play()
	pctLabel.Text = `{math.floor(p)}%`
	for _, s in STEPS do
		if p >= s.At then
			stepLabel.Text = s.Text
		end
	end
end

--| Loading

local started = os.clock()
local skipped = false
task.delay(SKIP_AFTER, function()
	if alive then
		skip.Visible = true
		skipShadow.Visible = true
	end
end)
skip.Activated:Connect(function()
	skipped = true
end)

local function waitFor(check: () -> boolean)
	local deadline = os.clock() + GIVE_UP
	while not skipped and os.clock() < deadline and not check() do
		task.wait(0.1)
	end
end

setProgress(5)
waitFor(function() return game:IsLoaded() end)
-- once the map is in, let it show (blurred) behind the card
TweenService:Create(scrim, TweenInfo.new(0.6), { BackgroundTransparency = 0.38 }):Play()
setProgress(25)

local PlayerData
waitFor(function()
	if not PlayerData then
		local m = ReplicatedStorage:FindFirstChild("Modules")
		m = m and m:FindFirstChild("PlayerData")
		if not m then return false end
		local ok, mod = pcall(require, m)
		if not ok then return false end
		PlayerData = mod.Client
	end
	return (pcall(function() return PlayerData.Settings.TutorialDone.Get() end))
end)
setProgress(50)

waitFor(function() return LOCAL_PLAYER:GetAttribute("UIReady") == true end)
setProgress(80)

-- preload the Interface's images (counts toward the last 20%)
if not skipped then
	local pg = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	local root = pg and pg:FindFirstChild("Interface")
	local list = {}
	if root then
		for _, d in root:GetDescendants() do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" then
				table.insert(list, d)
			end
		end
	end
	local done, total = 0, math.max(1, #list)
	local preload = task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, list, function()
			done += 1
			setProgress(80 + 20 * done / total)
		end)
		done = total
	end)
	local deadline = os.clock() + 12
	while not skipped and done < total and os.clock() < deadline do
		task.wait(0.1)
	end
	pcall(task.cancel, preload)
end
setProgress(100)

local wait = MIN_TIME - (os.clock() - started)
if wait > 0 and not skipped then
	task.wait(wait)
end
task.wait(0.25)

--| Out

alive = false
local out = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
TweenService:Create(scrim, out, { BackgroundTransparency = 1 }):Play()
TweenService:Create(blur, out, { Size = 0 }):Play()
TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = scale.Scale * 0.85 }):Play()
for _, d in canvas:GetDescendants() do
	if d:IsA("CanvasGroup") then
		TweenService:Create(d, out, { GroupTransparency = 1 }):Play()
	elseif d:IsA("TextLabel") or d:IsA("TextButton") then
		TweenService:Create(d, out, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, out, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, out, { Transparency = 1 }):Play()
	end
end
task.wait(0.5)
LOCAL_PLAYER:SetAttribute("LoadingDone", true)
blur:Destroy()
gui:Destroy()
