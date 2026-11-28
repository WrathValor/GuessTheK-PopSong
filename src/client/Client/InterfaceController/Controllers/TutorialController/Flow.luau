--| TutorialController/Flow
-- The K-POPPED! onboarding (design boards 62–62e): cards first, then duels. It walks a player
-- through the real screens one step at a time, with a coach mark (Frames.Coach, ./Build) on the
-- part to use: the screen dims except that part, ringed in yellow, and a bubble says what to do.
-- Soft steps (pin a card, open a pack, collect) don't block anything and wait for the player to
-- do it; the others wait for the bubble's button.
--   Welcome   – Tutorial.Hello: LET'S GO, or Skip (returning players: "WELCOME BACK TO", no 4th tile)
--   Bias      – Albums { First = true }: pick a bias, then the free first pack (skipped once done)
--   Pin       – Binder on the bias's group: pin a card, then what pins earn
--   Upgrade   – Shop › Upgrades: the first Payout level on a 500-coin gift (once), then the tour
--   Practice  – (new players) a 3-round solo game (DuelService "Tutorial"); its "You're ready!"
--               card is skipped and the flow goes on
--   FreePacks – Albums: open the free packs (skipped with none banked)
--   Collect   – (new players) Binder › COLLECT what the pins earned
--   Done      – Tutorial.AllSet: the rewards (SettingsService "OnboardDone"), Quick Play / Lobby
-- Each step is saved as it starts (Settings.Onboard, SettingsService "Onboard"), so a player who
-- leaves part-way comes back to that step. Skip (the Hello card, or top right) ends it for good.
-- While it runs the player has the "Onboarding" attribute (ScreenGuide stays quiet).
--   Flow.new(tutorial, interface, frames)
--   flow:Start(resume: string?, returning: boolean?)
--   flow:Hello("Go") / flow:Skip()          -- the Hello card's buttons (TutorialController)
--   flow:Practising() -> bool / flow:Practised(packet?)   -- the practice game ended (or didn't start)
--   flow:Running() -> bool

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local Upgrades = require(ReplicatedStorage.Modules.Library.Upgrades)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Build = require(script.Parent.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ME = tostring(LOCAL_PLAYER.UserId)
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

local PAD = 8 -- design px of lit space around the part
local GAP = 22 -- design px between the bubble and the lit part
local EDGE = 200 -- design px the dim reaches past the canvas (phone notch strips)
local MARGIN = 16 -- the bubble keeps this far from the canvas edge
local W, H = 1280, 720
local BUBBLE = Build.COACH_BUBBLE
local ORDER = { "Welcome", "Bias", "Pin", "Upgrade", "Practice", "FreePacks", "Collect", "Done" }
local INDEX = {}
for i, step in ORDER do
	INDEX[step] = i
end
INDEX.FirstPack = INDEX.Bias -- (saved once the bias is picked; it resumes on the same screen)

-- ---------------------------------- Helpers ------------------------------- --
local function get(value: any, fallback: any): any
	local ok, v = pcall(value.Get)
	return if ok and v ~= nil then v else fallback
end

local function bias(): string
	return get(PlayerData.Inventory.Bias, "")
end

local function claimed(key: string): boolean
	local ok, v = pcall(PlayerData.Rewards.Claimed.Has, key)
	return ok and v == true
end

local function coins(): number
	return get(PlayerData.Currencies.Won, 0)
end

local function levels()
	return Upgrades.Levels(PlayerData)
end

local function pinCount(): number
	return #Albums.Pins(get(PlayerData.Inventory.Pins, ""))
end

local function rate(): number
	local lv = levels()
	return Albums.Rate(get(PlayerData.Inventory.Cards, {}), bias(), get(PlayerData.Inventory.Pins, ""), Albums.Boost(PlayerData.GamePasses, lv), lv)
end

local function rateText(): string
	local r = rate()
	if r % 1 ~= 0 then
		return string.format("%.1f", r)
	end
	local s = tostring(r)
	while true do
		local n
		s, n = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		if n == 0 then
			return s
		end
	end
end

-- free packs banked now, and seconds to the next (nil while full); as AlbumsController shows them
local function freePacks(): (number, number?)
	local at = get(PlayerData.Inventory.FreePackAt, 0)
	if at == 0 then
		return AlbumConstants.FREE_PACK_START, nil
	end
	local packs, _, wait = Albums.FreePacks(get(PlayerData.Inventory.FreePacks, 0), at, os.time(), levels())
	return packs, wait
end

local function clock(seconds: number): string
	local h, m = seconds // 3600, math.max(1, (seconds % 3600) // 60)
	return if h > 0 then `{h} h {m} min` else `{m} min`
end

local function send(step: string)
	SettingsRemote:Fire({ Action = "Onboard", Step = step })
end

-- ---------------------------------- Class --------------------------------- --
local Flow = {}
Flow.__index = Flow

function Flow.new(tutorial: any, interface: any, frames: Frame)
	local self = setmetatable({}, Flow)
	self._tutorial = tutorial
	self._interface = interface
	self._frames = frames
	self._coach = frames:WaitForChild("Coach")
	self._coach.Visible = false
	self._token = 0
	self._running = false
	self._target = nil :: GuiObject?
	self._spec = nil :: any
	self._pressed = false
	self._practice = nil :: string? -- "Waiting" | "Done" while the practice step runs
	self._packet = nil :: any
	self._hello = nil :: string?
	self._connections = {}
	ButtonScale.ApplyToDescendants(self._coach)

	local bubble = self._coach.Bubble
	table.insert(self._connections, bubble.Next.Activated:Connect(function()
		Sounds.Play("Click")
		self._pressed = true
	end))
	table.insert(self._connections, self._coach.Skip.Activated:Connect(function()
		Sounds.Play("Click")
		self:Skip()
	end))
	table.insert(self._connections, bubble.Skip.Activated:Connect(function()
		Sounds.Play("Click")
		self:Skip()
	end))
	-- the coach follows its part every frame (screens slide in, scroll and resize)
	table.insert(self._connections, RunService.RenderStepped:Connect(function()
		if self._coach.Visible then
			self:_place()
		end
	end))
	return self
end

function Flow:Running(): boolean
	return self._running
end

-- --------------------------------- The coach ------------------------------- --

-- a part's box in the Frames canvas's design px
function Flow:_box(g: GuiObject): (Vector2, Vector2)
	local frames = self._frames
	local s = frames.AbsoluteSize.X / W
	if s <= 0 then
		s = 1
	end
	return (g.AbsolutePosition - frames.AbsolutePosition) / s, g.AbsoluteSize / s
end

function Flow:_place()
	local coach, spec, target = self._coach, self._spec, self._target
	local dim, ring, bubble, shadow, arrow = coach.Dim, coach.Ring, coach.Bubble, coach.BubbleShadow, coach.Arrow
	local lit = target ~= nil and target.Parent ~= nil and target.Visible and target.AbsoluteSize.X > 0
	local hx, hy, hw, hh = 0, 0, 0, 0
	if lit then
		local p, z = self:_box(target :: GuiObject)
		hx, hy, hw, hh = p.X - PAD, p.Y - PAD, z.X + PAD * 2, z.Y + PAD * 2
	end

	-- the dim: four strips round the lit part (all of it with no part)
	dim.Visible = spec ~= nil and spec.Dim == true
	if not lit then
		hx, hy, hw, hh = W / 2, H + EDGE, 0, 0
	end
	dim.Top.Position = UDim2.fromOffset(-EDGE, -EDGE)
	dim.Top.Size = UDim2.fromOffset(W + EDGE * 2, math.max(0, hy + EDGE))
	dim.Bottom.Position = UDim2.fromOffset(-EDGE, hy + hh)
	dim.Bottom.Size = UDim2.fromOffset(W + EDGE * 2, math.max(0, H + EDGE - hy - hh))
	dim.Left.Position = UDim2.fromOffset(-EDGE, hy)
	dim.Left.Size = UDim2.fromOffset(math.max(0, hx + EDGE), hh)
	dim.Right.Position = UDim2.fromOffset(hx + hw, hy)
	dim.Right.Size = UDim2.fromOffset(math.max(0, W + EDGE - hx - hw), hh)

	ring.Visible = lit
	ring.Position = UDim2.fromOffset(hx, hy)
	ring.Size = UDim2.fromOffset(hw, hh)

	local showBubble = spec ~= nil and spec.Title ~= nil and not spec.Hidden
	bubble.Visible, shadow.Visible = showBubble, showBubble
	arrow.Visible = showBubble and lit
	-- Skip tutorial sits in the bubble; the corner button only shows when there's no bubble
	coach.Skip.Visible, coach.SkipShadow.Visible = not showBubble, not showBubble
	if not showBubble then
		return
	end
	local bw, bh = BUBBLE.X, bubble.Size.Y.Offset
	local x, y = (W - bw) / 2, (H - bh) / 2
	local side = nil
	if lit then
		local cx, cy = hx + hw / 2, hy + hh / 2
		local function clampX(v: number): number
			return math.clamp(v, MARGIN, W - MARGIN - bw)
		end
		local function clampY(v: number): number
			return math.clamp(v, MARGIN, H - MARGIN - bh)
		end
		local options = {
			Below = { clampX(cx - bw / 2), hy + hh + GAP, hy + hh + GAP + bh <= H - MARGIN },
			Above = { clampX(cx - bw / 2), hy - GAP - bh, hy - GAP - bh >= MARGIN },
			Right = { hx + hw + GAP, clampY(cy - bh / 2), hx + hw + GAP + bw <= W - MARGIN },
			Left = { hx - GAP - bw, clampY(cy - bh / 2), hx - GAP - bw >= MARGIN },
		}
		for _, name in { spec.Side or "Below", "Below", "Above", "Right", "Left" } do
			local o = options[name]
			if o and o[3] then
				x, y, side = o[1], o[2], name
				break
			end
		end
		-- the pointer, half under the bubble's edge, as near the part's middle as the corners allow
		if side == "Below" or side == "Above" then
			arrow.Position = UDim2.fromOffset(math.clamp(cx, x + 30, x + bw - 30), if side == "Below" then y else y + bh)
		elseif side then
			arrow.Position = UDim2.fromOffset(if side == "Right" then x else x + bw, math.clamp(cy, y + 30, y + bh - 30))
		end
		arrow.Visible = side ~= nil
	end
	-- (x, y is the top-left corner, whatever anchor the bubble was given)
	local a, sa = bubble.AnchorPoint, shadow.AnchorPoint
	bubble.Position = UDim2.fromOffset(x + bw * a.X, y + bh * a.Y)
	shadow.Position = UDim2.fromOffset(x + 2 + (bw + 8) * sa.X, y + 2 + (bh + 8) * sa.Y)
end

-- show the coach on a part (nil = no part: the bubble in the middle)
--   spec = { Title?, Body?, Button? (nil = no button: a soft step), Dim?, Side?, Tag? }
function Flow:_spot(target: GuiObject?, spec: any)
	local bubble = self._coach.Bubble
	self._target, self._spec = target, spec
	self._pressed = false
	if spec.Title then
		bubble.Title.Text = spec.Title
		bubble.Body.Text = spec.Body or ""
		bubble.Tag.Text = spec.Tag or self:_tag()
		bubble.Tag.Visible = bubble.Tag.Text ~= ""
		local hasButton = spec.Button ~= nil
		bubble.Next.Visible, bubble.NextShadow.Visible = hasButton, hasButton
		bubble.Next.Text = spec.Button or "NEXT"
		-- (a soft step has no button: the bubble ends under its text)
		local bh = if hasButton then BUBBLE.Y else BUBBLE.Y - 52
		bubble.Size = UDim2.fromOffset(BUBBLE.X, bh)
		self._coach.BubbleShadow.Size = UDim2.fromOffset(BUBBLE.X + 8, bh + 8)
		Sounds.Play("Notify", { Volume = 0.7 })
		Juice.Pop(bubble, 0.1)
	end
	self._coach.Skip.Visible, self._coach.SkipShadow.Visible = true, true
	self._coach.Visible = true
	self:_place()
end

-- only the Skip button (a screen that explains itself, like the bias pick)
function Flow:_skipOnly()
	self:_spot(nil, {})
end

function Flow:_hide()
	self._target, self._spec = nil, nil
	self._coach.Visible = false
end

function Flow:_tag(): string
	local i, n = self._stepNo or 0, self._steps or 0
	return if i > 0 and n > 0 then `STEP {i} OF {n}` else ""
end

-- ---------------------------------- Waiting -------------------------------- --

-- yields until check() is true (true), or the time runs out or the flow ended (false)
function Flow:_wait(check: () -> boolean, timeout: number?): boolean
	local token = self._token
	local deadline = os.clock() + (timeout or math.huge)
	while self._token == token and os.clock() < deadline do
		local ok, v = pcall(check)
		if ok and v then
			return true
		end
		task.wait(0.1)
	end
	return false
end

function Flow:_next(): boolean
	return self:_wait(function()
		return self._pressed
	end)
end

function Flow:_alive(token: number): boolean
	return self._token == token
end

-- a screen open and done opening
function Flow:_opened(name: string, timeout: number?): boolean
	local controller = self._interface:GetController(name)
	return self:_wait(function()
		return self._interface.ActiveController == controller and controller.State == "Active"
	end, timeout or 6)
end

function Flow:_open(name: string, ...: any): boolean
	self._interface:Open(name, ...)
	return self:_opened(name)
end

-- the Tutorial card (Hello / AllSet / nothing); Interface:Open does nothing while it's already open
function Flow:_card(view: string, opts: any?)
	local tutorial = self._tutorial
	if self._interface.ActiveController == tutorial then
		tutorial:_show(view, opts)
	else
		self._interface:Open("Tutorial", view, opts)
	end
end

-- ----------------------------------- Steps --------------------------------- --

function Flow:_welcome(): boolean
	self._hello = nil
	self:_hide()
	self:_card("Hello", { Returning = self._returning })
	send("Welcome")
	self:_wait(function()
		return self._hello ~= nil
	end)
	return self._hello == "Go"
end

function Flow:_bias()
	if bias() ~= "" and claimed(AlbumConstants.FIRST_ALBUM_KEY) then
		return
	end
	send("Bias")
	local closed = false
	self._interface:Open("Albums", { First = true, OnDone = function()
		closed = true
	end })
	self:_opened("Albums")
	self:_skipOnly()
	local picked = bias() ~= ""
	if picked then
		send("FirstPack")
	end
	self:_wait(function()
		if not picked and bias() ~= "" then
			picked = true
			send("FirstPack")
		end
		return closed
	end)
	self:_hide()
end

function Flow:_pin()
	send("Pin")
	local group = Albums.BiasParts(bias())
	if not self:_open("Binder", { Group = group }) then
		return
	end
	local binder = self._interface:GetController("Binder")
	local panel = binder._frame:FindFirstChild("Pins", true)
	local before = pinCount()
	if before == 0 then
		local spec = { Title = "Pin your best card", Body = "Tap a card in your binder, then <b>PIN</b>. Pinned cards earn coins every hour, even while you're away.", Side = "Right" }
		self:_spot(panel, spec)
		-- (the bubble steps aside while a card's detail is open)
		self:_wait(function()
			spec.Hidden = binder._frame.Detail.Visible
			return pinCount() > before or binder.State ~= "Active"
		end)
		spec.Hidden = false
		if binder.State ~= "Active" then
			return
		end
		task.wait(0.6) -- (the detail closing, the pin landing)
	end
	self:_spot(panel, {
		Title = if before == 0 then "Now it's earning!" else "Your pins",
		Body = `Your pins earn <b>{rateText()} coins an hour</b>. Rarer cards earn more, and your bias's cards earn extra.`,
		Button = "NEXT",
		Dim = true,
		Side = "Right",
	})
	self:_next()
end

function Flow:_upgrade()
	send("Upgrade")
	if not self:_open("Shop", "Upgrades") then
		return
	end
	local shop = self._interface:GetController("Shop")
	local page = shop._frame.Panel:FindFirstChild("Upgrades")
	if not page then
		return
	end
	local card = page:FindFirstChild("Payout")
	local cost = Upgrades.Cost("Payout", levels().Payout)
	if levels().Payout == 0 and cost and not claimed("OnboardGift") then
		self:_spot(card, {
			Title = "Upgrades last for good",
			Body = "<b>Payout</b> makes every pinned card earn more. Here's <b>500 coins</b> for your first level!",
			Button = "BUY PAYOUT LV 1",
			Dim = true,
		})
		if not self:_next() then
			return
		end
		self._spec.Button = nil
		self._coach.Bubble.Next.Visible, self._coach.Bubble.NextShadow.Visible = false, false
		SettingsRemote:Fire({ Action = "OnboardGift" })
		self:_wait(function()
			return coins() >= cost
		end, 8)
		if coins() >= cost then
			ShopRemote:Fire({ Action = "Upgrade", Id = "Payout" })
			self:_wait(function()
				return levels().Payout >= 1
			end, 8)
		end
	end
	local strip = page:FindFirstChild("Summary") or page
	self:_spot(strip, {
		Title = "Grow your binder",
		Body = "More pin slots, payout, luck and faster free packs. Spend coins here whenever you've saved some.",
		Button = "NEXT",
		Dim = true,
		Side = "Above",
	})
	self:_next()
end

function Flow:_practise()
	send("Practice")
	-- (on the Tutorial frame with no card: its scrim dims the lobby and the HUD stays away)
	self:_card("None")
	self:_spot(nil, {
		Title = "Now, the songs!",
		Body = "Guess K-pop songs from tiny clips and beat rivals for coins. Try a practice round first: 3 songs, just you.",
		Button = "PLAY PRACTICE",
	})
	if not self:_next() then
		return
	end
	self:_hide()
	self._interface:Close(self._tutorial.Name)
	self._practice, self._packet = "Waiting", nil
	QueueRemote:Fire({ Request = "Tutorial" })
	self:_wait(function()
		return self._practice ~= "Waiting"
	end, 900)
	self._practice = nil
	if LOCAL_PLAYER:GetAttribute("Stage") then
		QueueRemote:Fire("Leave")
	end
	task.wait(0.8)
end

function Flow:_freePacks()
	local packs = freePacks()
	if packs < 1 then
		return
	end
	send("FreePacks")
	if not self:_open("Albums") then
		return
	end
	local albums = self._interface:GetController("Albums")
	local free = albums._frame.Shop.Main:FindFirstChild("Free", true)
	local title, line = "Free packs!", ""
	local packet = self._packet
	if packet then
		local right, total = 0, 0
		for _, round in packet.Rounds or {} do
			total += 1
			local pick = round.Picks and round.Picks[ME]
			if pick and pick.Correct then
				right += 1
			end
		end
		total = math.max(total, DuelConstants.TUTORIAL_ROUNDS)
		local mine = packet.Rewards and packet.Rewards[ME]
		title = if right * 2 > total then `{right} of {total} right, nice!` else `{right} of {total} right, good start!`
		line = if mine and (mine.Coins or 0) > 0 then ` You won <b>+{mine.Coins} coins</b> too.` else ""
	end
	local spec = {
		Title = title,
		Body = `You've got <b>{packs} free pack{if packs == 1 then "" else "s"}</b>: open them for more cards.{line}`,
	}
	self:_spot(free, spec)
	-- opening: the coach steps aside for the pull, and the step ends once it's over
	local started = false
	self:_wait(function()
		if albums._pull ~= nil then
			started = true
		end
		spec.Hidden = started
		self._coach.Visible = not started
		return (started and albums._pull == nil) or albums.State ~= "Active"
	end)
	self:_hide()
end

function Flow:_collect()
	send("Collect")
	if not self:_open("Binder") then
		return
	end
	local binder = self._interface:GetController("Binder")
	local button = binder._frame.Collect
	if binder:_waiting() >= 1 then
		self:_spot(button, {
			Title = "Collect your coins",
			Body = "Your pins kept earning while you played. Tap <b>COLLECT</b> to bank them.",
			Side = "Left",
		})
		self:_wait(function()
			return binder:_waiting() < 1 or binder.State ~= "Active"
		end)
		task.wait(0.8)
	else
		self:_spot(button, {
			Title = "Your coins land here",
			Body = "Your pins earn every minute. Come back and tap <b>COLLECT</b> to bank them.",
			Button = "NEXT",
			Dim = true,
			Side = "Left",
		})
		self:_next()
	end
	self:_hide()
end

function Flow:_done()
	self:_hide()
	local pay = not claimed("Onboard")
	SettingsRemote:Fire({ Action = "OnboardDone" })
	local packs, wait = freePacks()
	self:_card("AllSet", {
		Paid = pay,
		Lines = {
			if packs > 0 then `<b>{packs} free pack{if packs == 1 then "" else "s"}</b> waiting in Packs`
				elseif wait then `Next free pack in <b>{clock(wait)}</b>`
				else "Free packs refill every few hours",
			`Your pins earn <b>{rateText()} coins an hour</b>`,
			"New <b>daily quests</b> every day in Rewards",
		},
	})
end

-- ----------------------------------- Run ----------------------------------- --

function Flow:Start(resume: string?, returning: boolean?)
	if self._running then
		return
	end
	self._running = true
	self._token += 1
	local token = self._token
	self._returning = returning == true
	LOCAL_PLAYER:SetAttribute("Onboarding", true)
	local from = (resume and INDEX[resume]) or 1
	local new = not self._returning
	-- the steps this player gets, numbered for the bubbles' "STEP n OF m" (a resumed run keeps
	-- its numbers and starts at the step it left on)
	local plan, numbers, counted = {}, {}, 0
	for i, step in ORDER do
		local wanted = true
		if step == "Practice" then
			wanted = new
		elseif step == "Collect" then
			wanted = new or from > INDEX.Practice
		end
		if wanted then
			if step ~= "Welcome" and step ~= "Done" then
				counted += 1
				numbers[step] = counted
			end
			if i >= from then
				table.insert(plan, step)
			end
		end
	end
	self._steps, self._stepNo = counted, 0

	task.spawn(function()
		for _, step in plan do
			if not self:_alive(token) then
				return
			end
			self._stepNo = numbers[step] or 0
			if step == "Welcome" then
				if not self:_welcome() then
					return -- skipped
				end
			elseif step == "Bias" then
				self:_bias()
			elseif step == "Pin" then
				self:_pin()
			elseif step == "Upgrade" then
				self:_upgrade()
			elseif step == "Practice" then
				self:_practise()
			elseif step == "FreePacks" then
				self:_freePacks()
			elseif step == "Collect" then
				self:_collect()
			elseif step == "Done" then
				if self:_alive(token) then
					self:_done()
					self:_finish()
				end
			end
		end
	end)
end

function Flow:_finish()
	self._token += 1
	self._running = false
	self._practice = nil
	self:_hide()
	LOCAL_PLAYER:SetAttribute("Onboarding", nil)
end

function Flow:Hello(choice: string)
	self._hello = choice
end

function Flow:Skip()
	if not self._running then
		return
	end
	self:_finish()
	SettingsRemote:Fire({ Action = "OnboardDone", Skipped = true })
	local active = self._interface.ActiveController
	if active == self._tutorial then
		self._interface:Close(self._tutorial.Name)
	end
end

function Flow:Practising(): boolean
	return self._running and self._practice == "Waiting"
end

-- the practice game ended (its End packet), or never started (no free stage: nil)
function Flow:Practised(packet: any?)
	self._packet = packet
	self._practice = "Done"
end

function Flow:Destroy()
	self:_finish()
	for _, c in self._connections do
		c:Disconnect()
	end
end

return Flow
