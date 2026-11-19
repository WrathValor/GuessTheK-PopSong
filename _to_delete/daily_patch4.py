import sys, re
ROOT = sys.argv[1]
def sub(p, old, new, count=1):
    p = ROOT + "/" + p
    s = open(p, encoding='utf-8', newline='').read()
    nl = "\r\n" if "\r\n" in s else "\n"
    old, new = old.replace("\n", nl), new.replace("\n", nl)
    assert s.count(old) == count, (p, s.count(old), old[:70])
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))

B = 'src/client/Client/InterfaceController/Controllers/DailyLoginController/Build.luau'
# a UIScale on the stamp and the Next row for the claim animation (DailyLoginController)
sub(B, '''	corner(stamp, UDim.new(0.5, 0))
	stroke(stamp, 4)''', '''	corner(stamp, UDim.new(0.5, 0))
	stroke(stamp, 4)
	new("UIScale", { Name = "Pop" }, stamp) -- the claim drops it in from bigger''')
sub(B, '''	local nextRow = new("Frame", { Name = "Next", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, by + 3), Size = UDim2.fromOffset(560, 56), BackgroundTransparency = 1, Visible = false }, root)''', '''	local nextRow = new("Frame", { Name = "Next", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, by + 3), Size = UDim2.fromOffset(560, 56), BackgroundTransparency = 1, Visible = false }, root)
	new("UIScale", { Name = "Pop" }, nextRow) -- eases in after a claim''')

C = 'src/client/Client/InterfaceController/Controllers/DailyLoginController/init.luau'
sub(C, '''-- the pop-up on join: this long after the loading screen / tutorial, with the lobby free''', '''-- the claim animation (DailyLogin:_claimed)
local FADE = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DROP = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- the pop-up on join: this long after the loading screen / tutorial, with the lobby free''')

old_start = '''-- the server paid: stamp today's card, then show the countdown
function DailyLogin:_claimed(packet)'''
p = ROOT + "/" + C
s = open(p, encoding='utf-8', newline='').read()
nl = "\r\n" if "\r\n" in s else "\n"
i = s.index(old_start.replace("\n", nl))
j = s.index("-- [[ The pop-up on join ]]", i)
new_fn = '''-- fade a button (and its stroke) in or out; Transparency 1 hides it, 0 restores it
local function fadeButton(button: GuiObject, shadow: GuiObject?, to: number)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	TweenService:Create(button, FADE, { BackgroundTransparency = to, TextTransparency = to }):Play()
	if stroke then
		TweenService:Create(stroke, FADE, { Transparency = to }):Play()
	end
	if shadow then
		TweenService:Create(shadow, FADE, { BackgroundTransparency = to }):Play()
	end
end

-- the server paid: CLAIM fades away, today's card settles back into the grid and turns to
-- "done" as the ✓ stamp drops onto it, the streak ticks up, then the countdown eases in.
-- (The data changes land meanwhile; _animating keeps _paint from snapping over the tweens.)
function DailyLogin:_claimed(packet)
	self._busy = false
	self._animating = true
	Sounds.Play("Coins")
	local f = self._frame
	local day = tonumber(packet.Day)
	local holder = day and f.Days:FindFirstChild("Day" .. day)

	fadeButton(f.Claim, f.ClaimShadow, 1)

	if holder then
		local face = holder.Face
		local base = holder:GetAttribute("BaseY") or holder.Position.Y.Offset
		TweenService:Create(holder, SETTLE, { Rotation = 0, Position = UDim2.fromOffset(holder.Position.X.Offset, base) }):Play()
		TweenService:Create(holder.Shadow, SETTLE, { Position = UDim2.fromOffset(1, 1), BackgroundTransparency = 0.5 }):Play()
		TweenService:Create(face, SETTLE, { BackgroundColor3 = Build.COLOURS.Done }):Play()
		for _, label in { face.DayLabel, face.Big, face.Sub } do
			TweenService:Create(label, SETTLE, { TextTransparency = 0.35 }):Play()
		end
		for _, icon in { face.Art.Icon1, face.Art.Icon2 } do
			TweenService:Create(icon, SETTLE, { ImageTransparency = 0.55 }):Play()
		end
		-- TODAY slips off as the stamp lands
		local today = holder.Today
		local todayStroke = today:FindFirstChildOfClass("UIStroke")
		TweenService:Create(today, FADE, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(holder.TodayShadow, FADE, { BackgroundTransparency = 1 }):Play()
		if todayStroke then
			TweenService:Create(todayStroke, FADE, { Transparency = 1 }):Play()
		end
		local stamp = holder.Stamp
		local pop = stamp:FindFirstChild("Pop") :: UIScale?
		stamp.Visible = true
		stamp.Rotation = -32
		if pop then
			pop.Scale = 1.7
		end
		task.delay(0.1, function()
			Sounds.Play("Success", { Volume = 0.35 })
			TweenService:Create(stamp, DROP, { Rotation = -12 }):Play()
			if pop then
				TweenService:Create(pop, DROP, { Scale = 1 }):Play()
			end
		end)
	end

	task.delay(0.45, function()
		if self.State == "Inactive" then
			self._animating = false
			return
		end
		-- the streak ticks up with a little pop
		local streak = tonumber(packet.Streak)
		if streak then
			f.Streak.Row.Days.Text = `{streak} DAY STREAK`
			Juice.Pop(f.Streak, 0.08)
		end
	end)

	task.delay(0.6, function()
		self._animating = false
		if self.State == "Inactive" then
			return
		end
		self:_paint() -- the same end state the tweens reached, plus the Next row
		local pop = f.Next:FindFirstChild("Pop") :: UIScale?
		if pop then
			pop.Scale = 0.85
			TweenService:Create(pop, DROP, { Scale = 1 }):Play()
		end
	end)
end

'''
s = s[:i] + new_fn.replace("\n", nl) + s[j:]
open(p, 'w', encoding='utf-8', newline='').write(s)

# _paint puts back what the animation faded, and data changes wait for it to finish
sub(C, '''	f.Claim.Text = `CLAIM DAY {today}`
	f.Claim.Visible = canClaim
	f.ClaimShadow.Visible = canClaim''', '''	f.Claim.Text = `CLAIM DAY {today}`
	f.Claim.Visible = canClaim
	f.ClaimShadow.Visible = canClaim
	-- (the claim animation fades these; a later day shows them again)
	f.Claim.BackgroundTransparency, f.Claim.TextTransparency, f.ClaimShadow.BackgroundTransparency = 0, 0, 0
	local claimStroke = f.Claim:FindFirstChildOfClass("UIStroke")
	if claimStroke then
		claimStroke.Transparency = 0
	end''')
sub(C, '''	holder.Stamp.Visible = status == "Done"
	holder.Today.Visible = status == "Today"
	holder.TodayShadow.Visible = status == "Today"''', '''	holder.Stamp.Visible = status == "Done"
	holder.Stamp.Rotation = -12
	local pop = holder.Stamp:FindFirstChild("Pop")
	if pop then
		pop.Scale = 1
	end
	holder.Today.Visible = status == "Today"
	holder.TodayShadow.Visible = status == "Today"
	-- (the claim animation fades the TODAY sticker out)
	holder.Today.BackgroundTransparency, holder.Today.TextTransparency, holder.TodayShadow.BackgroundTransparency = 0, 0, 0
	local todayStroke = holder.Today:FindFirstChildOfClass("UIStroke")
	if todayStroke then
		todayStroke.Transparency = 0
	end''')
sub(C, '''			if self.State ~= "Inactive" and not self._busy then''', '''			if self.State ~= "Inactive" and not self._busy and not self._animating then''')
sub(C, '''	self._busy = false
	self._shownThisSession = false''', '''	self._busy = false
	self._animating = false
	self._shownThisSession = false''')
print("ok")
