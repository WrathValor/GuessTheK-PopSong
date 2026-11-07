--| PickChips
-- Round reveal (duel, solo and Party Stage FFA): who picked what. Each answer button gets a row of small avatar
-- chips on its top edge, one per player who picked it (headshot, initials until it loads,
-- their colour behind (a profile's Colour, else the setlist colour); yours has a red ring). Built at run time on Controls.Answers —
-- nothing to build in Studio. See the "Party 9 · FFA reveal" board.

local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex
local INK = C("1E1B2E")
local RED = C("E0382C")
-- setlist colours (as FFABoard's place badges)
local AV = { C("DCD3FF"), C("FFD2CE"), C("C8EFD6"), C("CDEBFA"), C("FFE9A8"), C("F4D6FF") }
local SIZE = 30
local OVERLAP = 9
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local PickChips = {}

local thumbs: { [number]: string } = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function initialsOf(name: string): string
	local letters = name:gsub("[^%w]", "")
	return string.upper(letters:sub(1, 2))
end

local function chip(parent: Instance, profile, slot: number, order: number)
	local me = LOCAL_PLAYER ~= nil and profile.UserId == LOCAL_PLAYER.UserId
	local f = new("Frame", {
		Name = "Chip" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = profile.Colour or AV[slot] or AV[1],
		ZIndex = 5 + order,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	new("UIStroke", { Color = if me then RED else INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local label = new("TextLabel", {
		Name = "Initials",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = HEAD,
		TextSize = 10,
		TextColor3 = INK,
		Text = if me then "ME" else initialsOf(profile.Name or "?"),
		ZIndex = f.ZIndex,
	}, f)
	local img = new("ImageLabel", {
		Name = "Avatar",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = f.ZIndex,
	}, f)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
	local id = profile.UserId
	local function set(image: string)
		if img.Parent and image ~= "" then
			img.Image = image
			label.Visible = false
		end
	end
	if thumbs[id] then
		set(thumbs[id])
	else
		task.spawn(function()
			local ok, image = pcall(Players.GetUserThumbnailAsync, Players, id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			if ok and image then
				thumbs[id] = image
				set(image)
			end
		end)
	end
end

-- answers = Controls.Answers, options = the round's Options (index → song), picks = the
-- RoundEnd packet's Picks (userId string → { Picked = song? }), order = profiles in setlist order
-- (each { UserId, Name, Colour? }; a repeated UserId — solo's you vs you — is shown once)
function PickChips.Show(answers: Instance, options, picks, order)
	PickChips.Clear(answers)
	if not options or not picks then
		return
	end
	local byId = {}
	for i, opt in options do
		byId[opt.Id] = i
	end
	local rows = {}
	local seen = {}
	for slot, profile in order do
		if seen[profile.UserId] then
			continue
		end
		seen[profile.UserId] = true
		local pick = picks[tostring(profile.UserId)]
		local i = pick and pick.Picked and byId[pick.Picked.Id]
		local button = i and answers:FindFirstChild("Answer" .. i)
		if button then
			local row = rows[i]
			if not row then
				row = new("Frame", {
					Name = "PickChips",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0, 0),
					Size = UDim2.fromOffset(SIZE * 6, SIZE),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, button)
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, -OVERLAP),
				}, row)
				rows[i] = row
			end
			chip(row, profile, slot, slot)
		end
	end
end

function PickChips.Clear(answers: Instance)
	for _, button in answers:GetChildren() do
		local row = button:FindFirstChild("PickChips")
		if row then
			row:Destroy()
		end
	end
end

return PickChips
