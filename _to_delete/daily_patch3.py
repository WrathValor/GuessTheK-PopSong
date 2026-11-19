import sys
ROOT = sys.argv[1]
def sub(p, old, new, count=1):
    p = ROOT + "/" + p
    s = open(p, encoding='utf-8', newline='').read()
    nl = "\r\n" if "\r\n" in s else "\n"
    old, new = old.replace("\n", nl), new.replace("\n", nl)
    assert s.count(old) == count, (p, s.count(old), old[:70])
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))

B = 'src/client/Client/InterfaceController/Controllers/DailyLoginController/Build.luau'

# card(): Roblox draws a Border stroke OUTSIDE the frame, so the shadow has to start under the
# stroke and be as big as the stroked face, or the stroke swallows `drop` pixels of it.
sub(B, '''-- a face with a hard ink shadow behind it (both rotate together when `rotation` is given)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number, rotation: number?): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation or 0 }, parent)
	corner(shadow, radius)''', '''-- a face with a hard ink shadow behind it (both rotate together when `rotation` is given).
-- A Border stroke is drawn outside the frame, so the shadow covers the stroked face (`line`
-- bigger all round) and shows `drop` px past it, like the boards' CSS shadows.
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number, rotation: number?): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop - line, drop - line), Size = size + UDim2.fromOffset(2 * line, 2 * line), BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation or 0 }, parent)
	corner(shadow, radius + line)''')
sub(B, '''	local sh = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X + 3, centre.Y + 3), Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation, ZIndex = 4 }, parent)
	corner(sh, 9)''', '''	local sh = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X + 3, centre.Y + 3), Size = UDim2.fromOffset(size.X + 6, size.Y + 6), BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation, ZIndex = 4 }, parent)
	corner(sh, 12)''')
# the day card's shadow (DailyLoginController moves it: 5 px, 7 px for today)
sub(B, '''	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(shadow, 16)''', '''	-- (under the 4 px stroke: Position = drop - 4, Size = the face + 8)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, 8, 1, 8), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(shadow, 20)''')
# bigger art (the coin piles have room round them)
sub(B, '''	local one = if seven then 140 else 62''', '''	local one = if seven then 150 else 72''')
sub(B, '''	local two = if seven then 104 else 54''', '''	local two = if seven then 110 else 60''')
# a drawn tick instead of the ✓ glyph (it renders as a thin √)
sub(B, '''	text(stamp, "Tick", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 26, Text = "✓", ZIndex = 7 })''', '''	-- the tick: two rounded ink bars (the ✓ glyph draws as a thin √)
	local tick = new("Frame", { Name = "Tick", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, ZIndex = 7 }, stamp)
	for _, bar in { { "Short", 7.6, 16.2, 12, 45 }, { "Long", 15.6, 13.2, 19, -50 } } do
		local b = new("Frame", { Name = bar[1], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bar[2], bar[3]), Size = UDim2.fromOffset(bar[4], 4.5), Rotation = bar[5], BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 7 }, tick)
		corner(b, UDim.new(0.5, 0))
	end''')
# close + streak + claim shadows: under the stroke, as big as the stroked face
sub(B, '''	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(cx + 3, cy + 3), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(cs, 12)''', '''	local cs = new("Frame", { Name = "CloseShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 24 + 3, cy + 24 + 3), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(cs, 16)''')
sub(B, '''	local streakShadow = new("Frame", { Name = "StreakShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640 + 3, P.Y + 40 + 3), Size = UDim2.fromOffset(170, 32), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(streakShadow, 11)''', '''	-- (DailyLoginController sizes the chip to its words, and this to the chip + 6)
	local streakShadow = new("Frame", { Name = "StreakShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640 + 3, P.Y + 40), Size = UDim2.fromOffset(176, 38), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(streakShadow, 14)''')
sub(B, '''	local claimShadow = new("Frame", { Name = "ClaimShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640 + 5, by + 5), Size = UDim2.fromOffset(270, 62), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(claimShadow, 14)''', '''	local claimShadow = new("Frame", { Name = "ClaimShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640 + 5, by + 31 + 5), Size = UDim2.fromOffset(278, 70), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(claimShadow, 18)''')

C = 'src/client/Client/InterfaceController/Controllers/DailyLoginController/init.luau'
sub(C, '''	holder.Shadow.Position = UDim2.fromOffset(if status == "Today" then 7 else 5, if status == "Today" then 7 else 5)''', '''	-- 5 px of shadow past the stroke (7 for today); the stroke is 4 px outside the face
	local drop = (if status == "Today" then 7 else 5) - 4
	holder.Shadow.Position = UDim2.fromOffset(drop, drop)''')
sub(C, '''	f.StreakShadow.Size = UDim2.fromOffset(w, 32)''', '''	f.StreakShadow.Size = UDim2.fromOffset(w + 6, 38) -- under the 3 px stroke''')
print("ok")
