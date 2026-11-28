--| Boosts
-- The active boost potions on the HUD (HUD.BottomLeft.Boosts, the bottom-left corner): one potion
-- per running clock (Coins / XP / Luck) with its time left under it. The server says when each clock
-- runs out as a player attribute ("BoostCoins" / "BoostXP", server time, 0 = off;
-- Engine/BoostService) and the timer counts down from that here. The clock pauses while
-- you're away, so the time shown is play time.
-- Hovering (or tapping, on touch) shows HUD.BottomLeft.BoostInfo above it, a small tag: the
-- boost and what it does (the time is on the pill). A click (or a second tap) opens the shop at the potions.
--   Boosts.Start(hud, janitor, openShop: () -> ())

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- --------------------------------- Imports -------------------------------- --
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local KINDS = { "Coins", "XP", "Luck" }
local EFFECT = {
	Coins = "Coins from matches doubled",
	XP = "XP from matches doubled",
	Luck = "Lucky Draw and rarer cards 50% likelier in packs",
}
local TOOLTIP_GAP = 8 -- px between the tooltip and the potion row
local TAP_HIDE = 3 -- seconds a tapped tooltip stays up

-- --------------------------------- Helpers -------------------------------- --
local function left(kind: string): number
	local ends = LOCAL_PLAYER:GetAttribute("Boost" .. kind)
	if type(ends) ~= "number" or ends <= 0 then
		return 0
	end
	return math.max(0, ends - workspace:GetServerTimeNow())
end

-- 1:52:08 / 24:13
local function clock(seconds: number): string
	seconds = math.ceil(seconds)
	local h, m, s = seconds // 3600, (seconds // 60) % 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- ---------------------------------- Module -------------------------------- --
local Boosts = {}

function Boosts.Start(hud, janitor, openShop: () -> ())
	local group = hud:FindFirstChild("BottomLeft") or hud.TopLeft -- (pinned by Interface.AutoScale)
	local row = group:FindFirstChild("Boosts")
	local info = group:FindFirstChild("BoostInfo")
	if not row or not info then
		return
	end
	info.Visible = false
	local shown: string? = nil -- the kind the tooltip is about
	local tapAt = 0

	local function paintInfo()
		if not shown then
			info.Visible = false
			return
		end
		local kind = ShopCatalog.BOOST_KINDS[shown]
		local card = info.Card
		-- a coin potion on top of the 2× Coins pass makes it 3× (ShopCatalog.CoinMultiplier)
		local stacked = shown == "Coins" and LOCAL_PLAYER:GetAttribute("DoubleCoins") == true
		card.Title.Text = if stacked then "3× Coins" else kind and kind.Name or shown
		card.Effect.Text = if stacked then "Stacks with your pass: 3× coins" else EFFECT[shown] or ""
		-- above the hovered potion, left edges lined up
		-- (the row's list layout places the buttons, so measure on screen and undo the HUD's scale)
		local button = row[shown]
		local scale = row.AbsoluteSize.X / math.max(row.Size.X.Offset, 1)
		local dx = (button.AbsolutePosition.X - row.AbsolutePosition.X) / scale
		info.Position = UDim2.fromOffset(row.Position.X.Offset + dx, row.Position.Y.Offset - info.Size.Y.Offset - TOOLTIP_GAP)
		info.Visible = true
	end

	local function show(kind: string?)
		shown = kind
		paintInfo()
	end

	for _, kind in KINDS do
		local button = row:FindFirstChild(kind)
		if button then
			button.Visible = false
			janitor:Add(button.MouseEnter:Connect(function()
				show(kind)
			end))
			janitor:Add(button.MouseLeave:Connect(function()
				if shown == kind then
					show(nil)
				end
			end))
			janitor:Add(button.Activated:Connect(function(input: InputObject?)
				local touch = input ~= nil and input.UserInputType == Enum.UserInputType.Touch
				if touch and (shown ~= kind or os.clock() - tapAt > TAP_HIDE) then
					-- first tap: what it is; a second tap opens the shop
					tapAt = os.clock()
					show(kind)
					return
				end
				show(nil)
				openShop()
			end))
		end
	end

	-- visible potions + timers, once a frame's worth of text a second
	local nextPaint = 0
	local was: { [string]: boolean } = {}
	janitor:Add(RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextPaint then
			return
		end
		nextPaint = now + 0.25
		for _, kind in KINDS do
			local button = row:FindFirstChild(kind)
			if button then
				local secs = left(kind)
				local on = secs > 0
				button.Visible = on
				if on then
					button.Timer.Text = clock(secs)
					if not was[kind] then
						Juice.Pop(button, 0.2) -- just drunk
					end
				elseif shown == kind then
					show(nil)
				end
				was[kind] = on
			end
		end
		if shown and UserInputService.TouchEnabled and not UserInputService.MouseEnabled and now - tapAt > TAP_HIDE then
			show(nil)
		end
	end))
end

return Boosts
