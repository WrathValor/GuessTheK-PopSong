--| InvitePicker
-- Duel invites on the queue card (the "Invites" boards on the design canvas). Invite flips
-- the card over to "Who do you want to duel?": everyone else in the server in a 2 × 3 grid,
-- friends first, each with INVITE / SENT · Ns / In a duel / Invites off, paging, Back and
-- "Invite a Roblox friend" (the Roblox invite prompt). Sending flips back to the front,
-- which shows "Invite sent!" with their headshot and a countdown, and Invite turns into
-- Cancel. Answers show as a toast by the card. The server side is Engine/InviteService.
-- Build(queueFrame) runs once in Studio (a runtime fallback builds it if it's missing);
-- new() wires it up from QueueController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)

local InviteRemote = Bridgenet.ReferenceBridge("InviteRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local FRIEND_ROW = C("FFF6FA")
local GREY = C("EDE4D4")
local GREY_TEXT = C("6B647A")
local MUTED = C("5C566B")
local BLUE = C("9ED8F5")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local PINK = C("FF9EC4")
local DECLINED = C("6B2430")
local AVATARS = { C("FFD2CE"), C("DCD3FF"), C("C8EFD6"), C("CDEBFA"), C("FFE9A8"), C("FFD9EA") }

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local W, H = 710, 470
local PER_PAGE = 6
local ROW_W, ROW_H, GAP = 328, 64, 10
local LIST_Y = 84
local TOAST_TIME = 3

local InvitePicker = {}
InvitePicker.__index = InvitePicker

-- ------------------------------------------------------------------ Build -- --

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

local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, shadow: number?): TextButton
	if shadow then
		local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + shadow, y + shadow), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
		corner(s, 12)
	end
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		AutoButtonColor = false,
		FontFace = BODY,
		TextSize = 15,
		TextColor3 = INK,
		Text = "",
		ZIndex = 2,
	}, parent)
	corner(b, 12)
	stroke(b, 3)
	return b
end

local function buildRow(list: Instance, i: number)
	local col, line = (i - 1) % 2, (i - 1) // 2
	local row = new("Frame", {
		Name = "Row" .. i,
		Position = UDim2.fromOffset(col * (ROW_W + GAP), line * (ROW_H + GAP)),
		Size = UDim2.fromOffset(ROW_W, ROW_H),
		BackgroundColor3 = CREAM,
	}, list)
	corner(row, 12)
	stroke(row, 2)
	local avatar = new("ImageLabel", { Name = "Avatar", Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = AVATARS[(i - 1) % #AVATARS + 1], Image = "" }, row)
	corner(avatar, 20)
	stroke(avatar, 2)
	text(row, "PlayerName", { Position = UDim2.fromOffset(60, 12), Size = UDim2.fromOffset(150, 20), TextSize = 15, Text = "Player" })
	local chip = text(row, "Friend", {
		Position = UDim2.fromOffset(60, 14),
		Size = UDim2.fromOffset(46, 16),
		BackgroundTransparency = 0,
		BackgroundColor3 = PINK,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = "FRIEND",
		Visible = false,
	})
	corner(chip, 6)
	stroke(chip, 2)
	text(row, "Sub", { Position = UDim2.fromOffset(60, 33), Size = UDim2.fromOffset(150, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Lv 1 · on the street" })
	local shadow = new("Frame", { Name = "ButtonShadow", Position = UDim2.fromOffset(ROW_W - 10 - 96 + 3, 14 + 3), Size = UDim2.fromOffset(96, 36), BackgroundColor3 = INK }, row)
	corner(shadow, 9)
	local b = new("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(ROW_W - 10 - 48, 32),
		Size = UDim2.fromOffset(96, 36),
		BackgroundColor3 = MINT,
		AutoButtonColor = false,
		FontFace = HEAD,
		TextSize = 13,
		TextColor3 = INK,
		Text = "INVITE",
		ZIndex = 2,
	}, row)
	corner(b, 9)
	stroke(b, 2)
end

function InvitePicker.Build(queueFrame: Instance)
	for _, n in { "Invite", "InviteShadow", "InviteToasts" } do
		local old = queueFrame:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local cx, cy = 640, 360
	local shadow = new("Frame", { Name = "InviteShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 6, cy + 6), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, Visible = false }, queueFrame)
	corner(shadow, 16)
	local back = new("Frame", { Name = "Invite", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(W, H), BackgroundColor3 = WHITE, Visible = false }, queueFrame)
	corner(back, 16)
	stroke(back, 3)
	new("UIScale", { Name = "Flip" }, back)
	new("UIScale", { Name = "Flip" }, shadow)

	local tagShadow = new("Frame", { Name = "TagShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2 + 4, 2), Size = UDim2.fromOffset(170, 31), Rotation = -2, BackgroundColor3 = INK, ZIndex = 2 }, back)
	corner(tagShadow, 10)
	local tag = text(back, "Tag", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W / 2, -2),
		Size = UDim2.fromOffset(170, 31),
		Rotation = -2,
		BackgroundTransparency = 0,
		BackgroundColor3 = BLUE,
		FontFace = HEAD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "INVITE A RIVAL",
		ZIndex = 3,
	})
	corner(tag, 10)
	stroke(tag, 3)

	text(back, "Heading", { Position = UDim2.fromOffset(22, 30), Size = UDim2.fromOffset(330, 26), FontFace = HEAD, TextSize = 21, Text = "Who do you want to duel?" })
	text(back, "Sub", { Position = UDim2.fromOffset(22, 56), Size = UDim2.fromOffset(400, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Players in this server · friends first" })

	local list = new("Frame", { Name = "List", Position = UDim2.fromOffset(22, LIST_Y), Size = UDim2.fromOffset(ROW_W * 2 + GAP, ROW_H * 3 + GAP * 2), BackgroundTransparency = 1 }, back)
	for i = 1, PER_PAGE do
		buildRow(list, i)
	end
	text(back, "Empty", {
		Position = UDim2.fromOffset(22, LIST_Y),
		Size = UDim2.fromOffset(ROW_W * 2 + GAP, ROW_H * 3 + GAP * 2),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextSize = 16,
		TextColor3 = MUTED,
		Text = "Nobody else is in this server yet.\nInvite a Roblox friend to join you!",
		Visible = false,
	})

	-- pager
	local py = LIST_Y + ROW_H * 3 + GAP * 2 + 16
	local prev = new("TextButton", { Name = "Prev", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2 - 60, py + 15), Size = UDim2.fromOffset(36, 30), BackgroundColor3 = WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 18, TextColor3 = INK, Text = "‹" }, back)
	corner(prev, 8)
	stroke(prev, 2)
	text(back, "Page", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2, py + 15), Size = UDim2.fromOffset(70, 20), FontFace = HEAD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
	local nxt = new("TextButton", { Name = "Next", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2 + 60, py + 15), Size = UDim2.fromOffset(36, 30), BackgroundColor3 = YELLOW, AutoButtonColor = false, FontFace = BODY, TextSize = 18, TextColor3 = INK, Text = "›" }, back)
	corner(nxt, 8)
	stroke(nxt, 2)

	-- Back + Invite a Roblox friend, same spot as the solo picker's Back + Start
	local by = 386
	local backBtn = button(back, "Back", 22, by, 130, 56, WHITE, 3)
	backBtn.Text = "Back"
	local fx, fw = 22 + 130 + 12, W - 44 - 130 - 12
	local friend = button(back, "Friend", fx, by, fw, 56, BLUE, 4)
	text(friend, "Title", { Position = UDim2.fromOffset(0, 9), Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Text = "INVITE A ROBLOX FRIEND", ZIndex = 3 })
	text(friend, "Sub", { Position = UDim2.fromOffset(0, 31), Size = UDim2.new(1, 0, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Text = "Bring a friend into the game", ZIndex = 3 })

	-- answer toasts: just above the queue card (the card sits at the bottom of the screen)
	new("Frame", { Name = "InviteToasts", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(640, 278), Size = UDim2.fromOffset(300, 120), BackgroundTransparency = 1 }, queueFrame)

	-- the Invite button's cancel face (its INVITE title is an image)
	local invite = queueFrame:FindFirstChild("Panel") and queueFrame.Panel:FindFirstChild("InvitePlayers")
	if invite then
		local old = invite:FindFirstChild("CancelTitle")
		if old then
			old:Destroy()
		end
		text(invite, "CancelTitle", { Position = UDim2.fromOffset(0, 9), Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "CANCEL", Visible = false, ZIndex = 3 })
	end
	return back
end

-- -------------------------------------------------------------- Behaviour -- --

local function tween(inst: Instance, info: TweenInfo, props)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function headshot(userId: number, label: ImageLabel)
	label.Image = ""
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and label:GetAttribute("UserId") == userId then
			label.Image = img
		end
	end)
	label:SetAttribute("UserId", userId)
end

local friendCache: { [number]: boolean } = {}
local function isFriend(userId: number): boolean
	if friendCache[userId] == nil then
		local ok, yes = pcall(LOCAL_PLAYER.IsFriendsWith, LOCAL_PLAYER, userId)
		friendCache[userId] = ok and yes == true
	end
	return friendCache[userId]
end

-- what the row's button shows for each Status from the server
local STATES = {
	Open = { "INVITE", MINT, INK, true },
	Sent = { "SENT", YELLOW, INK, false },
	InDuel = { "In a duel", GREY, GREY_TEXT, false },
	Off = { "Invites off", GREY, GREY_TEXT, false },
	Cooldown = { "Not now", GREY, GREY_TEXT, false },
}
local SUBS = {
	Open = "on the street",
	Sent = "invited",
	InDuel = "in a duel",
	Off = "invites off",
	Cooldown = "said not now",
}

function InvitePicker.new(queueFrame: Instance, janitor, solo)
	local self = setmetatable({}, InvitePicker)
	self._queue = queueFrame
	self._front = queueFrame:FindFirstChild("Panel")
	self._frontShadow = queueFrame:FindFirstChild("PanelShadow")
	self._solo = solo
	self.IsOpen = false
	self._players = {}
	self._page = 1
	self._sent = nil -- { Target, Name, Expires } while an invite is out

	if not queueFrame:FindFirstChild("Invite") then
		InvitePicker.Build(queueFrame) -- not built in Studio yet
		ButtonScale.ApplyToDescendants(queueFrame.Invite)
	end
	self._back = queueFrame.Invite
	self._backShadow = queueFrame.InviteShadow
	self._toasts = queueFrame:FindFirstChild("InviteToasts")
	local back = self._back

	for i = 1, PER_PAGE do
		local row = back.List["Row" .. i]
		janitor:Add(row.Button.Activated:Connect(function()
			local p = self._players[(self._page - 1) * PER_PAGE + i]
			if p and p.Status == "Open" and not self._sent then
				Sounds.Play("Click")
				InviteRemote:Fire({ Action = "Send", Target = p.UserId })
			end
		end))
	end
	janitor:Add(back.Prev.Activated:Connect(function()
		if self._page > 1 then
			self._page -= 1
			self:Render()
		end
	end))
	janitor:Add(back.Next.Activated:Connect(function()
		if self._page < self:_pages() then
			self._page += 1
			self:Render()
		end
	end))
	janitor:Add(back.Back.Activated:Connect(function()
		self:Close()
	end))
	janitor:Add(back.Friend.Activated:Connect(function()
		pcall(SocialService.PromptGameInvite, SocialService, LOCAL_PLAYER)
	end))

	janitor:Add(InviteRemote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Message == "List" then
			self:_setList(packet.Players or {})
		elseif packet.Message == "Sent" then
			self._sent = { Target = packet.Target, Name = packet.Name, Expires = packet.Expires }
			for _, p in self._players do
				if p.UserId == packet.Target then
					p.Status = "Sent"
				end
			end
			self:Close()
			self:RenderFront()
		elseif packet.Message == "Result" then
			self:_onResult(packet.Result, packet.Name)
		end
	end))

	-- the list refreshes while it's open (people come and go, duels end)
	local loop = task.spawn(function()
		while true do
			task.wait(1)
			if self.IsOpen then
				self._tick = (self._tick or 0) + 1
				if self._tick % 4 == 0 then
					InviteRemote:Fire({ Action = "List" })
				end
				self:Render()
			end
			if self._sent then
				self:RenderFront()
			end
		end
	end)
	janitor:Add(function()
		pcall(task.cancel, loop)
	end, true)
	return self
end

function InvitePicker:_pages(): number
	return math.max(1, math.ceil(#self._players / PER_PAGE))
end

function InvitePicker:_setList(list)
	for _, p in list do
		p.Friend = isFriend(p.UserId)
	end
	-- friends first, then whoever you can invite, then by level
	local rank = { Open = 0, Sent = 0, Cooldown = 1, InDuel = 2, Off = 3 }
	table.sort(list, function(a, b)
		if a.Friend ~= b.Friend then
			return a.Friend
		end
		if rank[a.Status] ~= rank[b.Status] then
			return (rank[a.Status] or 9) < (rank[b.Status] or 9)
		end
		return (a.Level or 0) > (b.Level or 0)
	end)
	self._players = list
	self._page = math.min(self._page, self:_pages())
	self:Render()
end

function InvitePicker:Render()
	local back = self._back
	local start = (self._page - 1) * PER_PAGE
	local now = workspace:GetServerTimeNow()
	for i = 1, PER_PAGE do
		local row = back.List["Row" .. i]
		local p = self._players[start + i]
		row.Visible = p ~= nil
		if p then
			local status = p.Status
			if self._sent and self._sent.Target == p.UserId then
				status = "Sent"
			elseif self._sent and status == "Open" then
				status = "Open" -- still shows INVITE, but sending waits for the first answer
			end
			local s = STATES[status] or STATES.Off
			row.BackgroundColor3 = if p.Friend then FRIEND_ROW else CREAM
			row.PlayerName.Text = p.Name
			row.Friend.Visible = p.Friend
			local nameW = math.min(row.PlayerName.TextBounds.X, if p.Friend then 96 else 150)
			row.PlayerName.Size = UDim2.fromOffset(if p.Friend then 96 else 150, 20)
			row.Friend.Position = UDim2.fromOffset(60 + nameW + 6, 14)
			local sub = SUBS[status] or ""
			if status == "Open" and (p.Streak or 0) > 0 then
				sub = `{p.Streak} win streak`
			end
			if status == "Sent" and self._sent then
				sub = `invited {math.max(0, math.floor(15 - (self._sent.Expires - now)))}s ago`
			end
			row.Sub.Text = `Lv {p.Level or 1} · {sub}`
			local label = s[1]
			if status == "Sent" and self._sent then
				label = `SENT · {math.max(0, math.ceil(self._sent.Expires - now))}s`
			end
			row.Button.Text = label
			row.Button.BackgroundColor3 = s[2]
			row.Button.TextColor3 = s[3]
			row.Button.FontFace = if s[4] then HEAD else BODY
			row.Button.Active = s[4] and not self._sent
			row.ButtonShadow.Visible = s[4]
			if row.Avatar:GetAttribute("UserId") ~= p.UserId then
				headshot(p.UserId, row.Avatar)
			end
		end
	end
	back.Empty.Visible = #self._players == 0
	local pages = self:_pages()
	back.Page.Text = `{self._page} / {pages}`
	back.Page.Visible = pages > 1
	back.Prev.Visible = pages > 1
	back.Next.Visible = pages > 1
	back.Prev.BackgroundColor3 = if self._page > 1 then YELLOW else WHITE
	back.Next.BackgroundColor3 = if self._page < pages then YELLOW else WHITE
end

-- the front of the card while an invite is out: "Invite sent!", their headshot + countdown,
-- and Invite becomes Cancel
function InvitePicker:RenderFront()
	local panel = self._front
	if not panel then
		return
	end
	local invite = panel:FindFirstChild("InvitePlayers")
	local participants = panel:FindFirstChild("Participants")
	local opponent = participants and participants:FindFirstChild("Opponent")
	local sent = self._sent
	if invite then
		local title = invite:FindFirstChild("Title")
		local cancel = invite:FindFirstChild("CancelTitle")
		if title then
			title.Visible = sent == nil
		end
		if cancel then
			cancel.Visible = sent ~= nil
		end
		invite.BackgroundColor3 = if sent then WHITE else BLUE
		if invite:FindFirstChild("Sub") then
			invite.Sub.Text = if sent then "Cancel invite" else "Ask a friend to duel"
		end
	end
	if not sent then
		return
	end
	local left = math.max(0, math.ceil(sent.Expires - workspace:GetServerTimeNow()))
	panel.Title.Text = "Invite sent!"
	panel.Subtitle.Text = `Waiting for {sent.Name} to answer… {left}s`
	if opponent and opponent:FindFirstChild("Thumbnail") then
		if opponent.Thumbnail:GetAttribute("UserId") ~= sent.Target then
			headshot(sent.Target, opponent.Thumbnail)
		end
		opponent.Thumbnail.Visible = true
		opponent.Unknown.Visible = false
	end
	if participants and participants:FindFirstChild("OpponentName") then
		participants.OpponentName.Text = sent.Name
	end
end

-- back to "Waiting for a rival…" after an invite that didn't work out
function InvitePicker:_clearFront()
	local panel = self._front
	local participants = panel and panel:FindFirstChild("Participants")
	local opponent = participants and participants:FindFirstChild("Opponent")
	self:RenderFront()
	if not panel then
		return
	end
	panel.Title.Text = "Waiting for a rival…"
	panel.Subtitle.Text = "Nobody's joined the other spot yet"
	if opponent then
		opponent.Thumbnail.Visible = false
		opponent.Thumbnail:SetAttribute("UserId", nil)
		opponent.Unknown.Visible = true
	end
	if participants and participants:FindFirstChild("OpponentName") then
		participants.OpponentName.Text = "Open spot"
	end
end

function InvitePicker:_onResult(result: string, name: string?)
	local had = self._sent
	self._sent = nil
	name = name or "They"
	if result == "Accepted" then
		self:Toast(`{name} accepted! Get ready…`, INK)
		self:RenderFront() -- the server's Opponent packet fills in the rest
		return
	elseif result == "Declined" then
		self:Toast(`{name} said not now`, DECLINED)
	elseif result == "Expired" then
		self:Toast(`No answer from {name}`, MUTED)
	elseif result == "Failed" then
		self:Toast(if name ~= "They" then `{name} can't duel right now` else "Couldn't send that invite", MUTED)
	end
	-- "Cancelled": you cancelled, or left / your game started, so nothing to say
	if had then
		self:_clearFront()
	end
	if self.IsOpen then
		InviteRemote:Fire({ Action = "List" })
	end
end

function InvitePicker:Toast(message: string, colour: Color3)
	local holder = self._toasts
	if not holder then
		return
	end
	for _, old in holder:GetChildren() do
		old:Destroy()
	end
	local shadow = new("Frame", { Name = "Shadow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 4, 1, 4), Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = INK }, holder)
	corner(shadow, 12)
	local toast = text(holder, "Toast", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		TextColor3 = colour,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = message,
		ZIndex = 2,
	})
	corner(toast, 12)
	stroke(toast, 3)
	local scale = new("UIScale", { Scale = 0.6 }, toast)
	local scale2 = new("UIScale", { Scale = 0.6 }, shadow)
	local pop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(scale, pop, { Scale = 1 })
	tween(scale2, pop, { Scale = 1 })
	Sounds.Play("Notify")
	task.delay(TOAST_TIME, function()
		if toast.Parent then
			toast:Destroy()
			shadow:Destroy()
		end
	end)
end

-- Invite on the front: open the picker, or cancel the invite that's out
function InvitePicker:Pressed()
	if self._sent then
		InviteRemote:Fire({ Action = "Cancel" })
		self._sent = nil
		self:_clearFront()
		return
	end
	self:Open()
end

function InvitePicker:Open()
	if self.IsOpen or (self._solo and self._solo.IsOpen) then
		return
	end
	self.IsOpen = true
	self._page = 1
	self:Render()
	InviteRemote:Fire({ Action = "List" })
	local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local pop = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fronts = { self._front, self._frontShadow }
	for _, f in fronts do
		local s = f:FindFirstChild("Flip") or new("UIScale", { Name = "Flip" }, f)
		tween(s, quick, { Scale = 0.7 })
	end
	Sounds.Play("Open")
	task.delay(0.12, function()
		if not self.IsOpen then
			return
		end
		for _, f in fronts do
			f.Visible = false
		end
		for _, f in { self._back, self._backShadow } do
			f.Flip.Scale = 0.7
			f.Visible = true
			tween(f.Flip, pop, { Scale = 1 })
		end
	end)
end

function InvitePicker:Close(instant: boolean?)
	if not self.IsOpen and not instant then
		return
	end
	local wasOpen = self.IsOpen
	self.IsOpen = false
	local fronts = { self._front, self._frontShadow }
	local function showFront()
		for _, f in { self._back, self._backShadow } do
			f.Visible = false
		end
		if not wasOpen and instant then
			return -- the solo picker owns the flip right now
		end
		for _, f in fronts do
			f.Visible = true
			local s = f:FindFirstChild("Flip") or new("UIScale", { Name = "Flip" }, f)
			if instant then
				s.Scale = 1
			else
				s.Scale = 0.7
				tween(s, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			end
		end
	end
	if instant then
		showFront()
		return
	end
	for _, f in { self._back, self._backShadow } do
		tween(f.Flip, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.7 })
	end
	task.delay(0.12, function()
		if not self.IsOpen then
			showFront()
		end
	end)
end

-- a new stage / the game starting: no invite is out any more (the server cancels it too)
function InvitePicker:Reset()
	self._sent = nil
	self:Close(true)
	self:RenderFront()
	if self._toasts then
		for _, t in self._toasts:GetChildren() do
			t:Destroy()
		end
	end
end

return InvitePicker
