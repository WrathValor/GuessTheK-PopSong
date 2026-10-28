--| Settings UI builder
-- Builds Interface.Frames.Settings from the "Settings" design board: blue header, an Audio
-- section (Music, Sound effects, Song clips: icon, name, slider, percent chip, mute button),
-- a Social section (Duel invites on/off switch) and "Reset to default". Run once in Studio
-- (an existing frame is kept as ServerStorage.Settings_Legacy); SettingsMenuController finds
-- everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local BLUE = C("9ED8F5")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local PAPER = C("F3EBDD")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}

Build.ICONS = {
	Close = "rbxassetid://118345756178429",
	SpeakerOn = "rbxassetid://85108312239996",
	SpeakerOff = "rbxassetid://112845031037998",
	Atlas = "rbxassetid://87950570350196", -- gtks_atlas0 (i_users at 800,100)
}

-- Key = the Settings field it saves to
Build.ROWS = {
-- Icon = cell in gtks_atlas0 (i_note, i_star, i_play)
	{ Name = "Music", Key = "MusicVolume", Sub = "Lobby playlist", Icon = Vector2.new(100, 100), Colour = "B9A6FF" },
	{ Name = "SoundEffects", Key = "SfxVolume", Title = "Sound effects", Sub = "Buttons, spins, results", Icon = Vector2.new(300, 100), Colour = "A7E9B8" },
	{ Name = "SongClips", Key = "ClipVolume", Title = "Song clips", Sub = "Snippets + song reveal", Icon = Vector2.new(0, 0), Colour = "FFE07A" },
}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number | UDim)
	new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, p)
end

local function stroke(p: Instance, t: number, colour: Color3?)
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- face + hard shadow (<name>Shadow behind it)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function iconBox(parent: Instance, colour: Color3): Frame
	local box = new("Frame", { Name = "IconBox", Position = UDim2.fromOffset(14, 13), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = colour }, parent)
	corner(box, 12)
	stroke(box, 3)
	return box
end

local ROW_W, ROW_H = 632, 72

local function volumeRow(parent: Instance, y: number, spec)
	local row = card(parent, spec.Name, UDim2.fromOffset(0, y), UDim2.fromOffset(ROW_W, ROW_H), WHITE, 14, 4, 3)
	local box = iconBox(row, C(spec.Colour))
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Image = Build.ICONS.Atlas,
		ImageRectOffset = spec.Icon,
		ImageRectSize = Vector2.new(96, 96),
	}, box)
	text(row, "Title", { Position = UDim2.fromOffset(74, 16), Size = UDim2.fromOffset(150, 20), TextSize = 16, Text = spec.Title or spec.Name })
	text(row, "Sub", { Position = UDim2.fromOffset(74, 37), Size = UDim2.fromOffset(150, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = spec.Sub })

	-- slider: track 16 high, fill, knob; Hit is the drag area (taller than the track)
	local sx, sw = 236, 236
	local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(sx, ROW_H / 2 - 8), Size = UDim2.fromOffset(sw, 16), BackgroundColor3 = PAPER }, row)
	corner(track, 8)
	stroke(track, 3)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.7, 1), BackgroundColor3 = C(spec.Colour), BorderSizePixel = 0 }, track)
	corner(fill, 5)
	local knob = new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = WHITE, ZIndex = 3 }, track)
	corner(knob, UDim.new(0.5, 0))
	stroke(knob, 3)
	new("TextButton", { Name = "Hit", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -12, 0.5, 0), Size = UDim2.new(1, 24, 0, 40), BackgroundTransparency = 1, Text = "", ZIndex = 4 }, track)

	local pct = text(row, "Percent", {
		Position = UDim2.fromOffset(sx + sw + 18, ROW_H / 2 - 15),
		Size = UDim2.fromOffset(56, 30),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		FontFace = HEAD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = "70%",
	})
	corner(pct, 9)
	stroke(pct, 2)

	local muteShadow = new("Frame", { Name = "MuteShadow", Position = UDim2.fromOffset(ROW_W - 14 - 42 + 2, ROW_H / 2 - 21 + 2), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, row)
	corner(muteShadow, 11)
	local mute = new("ImageButton", {
		Name = "Mute",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ROW_W - 14 - 21, ROW_H / 2),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = WHITE,
		Image = "",
		AutoButtonColor = false,
	}, row)
	corner(mute, 11)
	stroke(mute, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, Image = Build.ICONS.SpeakerOn }, mute)
	return row
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Settings")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Settings_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Settings_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "Settings", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, root)
	scrim.Active = true

	local W, H = 680, 590
	local panel = card(root, "Panel", UDim2.fromOffset(300, 65), UDim2.fromOffset(W, H), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true

	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = BLUE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(300, 64), FontFace = HEAD, TextSize = 26, Text = "SETTINGS" })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(W - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = Build.ICONS.Close }, close)

	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(22, 67 + 16), Size = UDim2.fromOffset(W - 44 - 4, H - 67 - 32), BackgroundTransparency = 1 }, panel)
	text(content, "AudioHeading", { Size = UDim2.fromOffset(200, 22), FontFace = HEAD, TextSize = 16, Text = "Audio" })
	local y = 30
	for _, spec in Build.ROWS do
		volumeRow(content, y, spec)
		y += ROW_H + 12
	end

	y += 4
	text(content, "SocialHeading", { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(200, 22), FontFace = HEAD, TextSize = 16, Text = "Social" })
	y += 30
	local invites = card(content, "Invites", UDim2.fromOffset(0, y), UDim2.fromOffset(ROW_W, ROW_H), WHITE, 14, 4, 3)
	local box = iconBox(invites, BLUE)
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Image = Build.ICONS.Atlas,
		ImageRectOffset = Vector2.new(800, 100),
		ImageRectSize = Vector2.new(96, 96),
	}, box)
	text(invites, "Title", { Position = UDim2.fromOffset(74, 16), Size = UDim2.fromOffset(380, 20), TextSize = 16, Text = "Duel invites" })
	text(invites, "Sub", { Position = UDim2.fromOffset(74, 37), Size = UDim2.fromOffset(400, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Let other players invite you to a duel. Off = invites are blocked." })
	text(invites, "State", { Position = UDim2.fromOffset(ROW_W - 14 - 64 - 46, ROW_H / 2 - 10), Size = UDim2.fromOffset(38, 20), FontFace = HEAD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Text = "On" })
	local tShadow = new("Frame", { Name = "ToggleShadow", Position = UDim2.fromOffset(ROW_W - 14 - 64 + 2, ROW_H / 2 - 17 + 2), Size = UDim2.fromOffset(64, 34), BackgroundColor3 = INK }, invites)
	corner(tShadow, UDim.new(0.5, 0))
	local toggle = new("TextButton", {
		Name = "Toggle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ROW_W - 14 - 32, ROW_H / 2),
		Size = UDim2.fromOffset(64, 34),
		BackgroundColor3 = C("A7E9B8"),
		Text = "",
		AutoButtonColor = false,
	}, invites)
	corner(toggle, UDim.new(0.5, 0))
	stroke(toggle, 3)
	local knob = new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -15, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = WHITE }, toggle)
	corner(knob, UDim.new(0.5, 0))
	stroke(knob, 3)

	-- footer
	local rw, rh = 150, 38
	local rs = new("Frame", { Name = "ResetShadow", Position = UDim2.new(1, -rw + 3 - 3, 1, -rh + 3 - 3), Size = UDim2.fromOffset(rw, rh), BackgroundColor3 = INK }, content)
	corner(rs, 11)
	local reset = new("TextButton", {
		Name = "Reset",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -rw / 2 - 3, 1, -rh / 2 - 3),
		Size = UDim2.fromOffset(rw, rh),
		BackgroundColor3 = YELLOW,
		FontFace = BODY,
		TextSize = 14,
		TextColor3 = INK,
		Text = "Reset to default",
		AutoButtonColor = false,
	}, content)
	corner(reset, 11)
	stroke(reset, 3)

	root.Parent = frames
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(root)
	return root
end

return Build
