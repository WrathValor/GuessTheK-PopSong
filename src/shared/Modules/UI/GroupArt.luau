--| GroupArt
-- A group's colours on card art, from its song module (Songs/<Company>/<Group>.luau):
-- Gradient (its real colours, a ColorSequence) when it has one, else its pastel Colour.
-- Paint() puts them on a frame through a UIGradient named "Group" (made on first use; the
-- frame turns white so the gradient shows as it is) and makes the frame's text readable
-- (Glyph / Initials go cream on a dark gradient). Used by the roll reveal, Index cards and
-- the Inventory's group packs.
--   local target = GroupArt.Paint(card.Art, song)      -- song table (Id / Artist) or group name
--   GroupArt.Colours(song)                             -- { Color3 } for particles
--   GroupArt.Main(song)                                -- the pastel Colour (glows)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Songs = require(ReplicatedStorage.Modules.Library.Songs)

local C = Color3.fromHex
local WHITE = Color3.new(1, 1, 1)
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local FALLBACK = C("9ED8F5")
local TEXT_NAMES = { "Glyph", "Initials" }

local GroupArt = {}

local byGroup: { [string]: any } = {}

-- the library entry carrying the group's fields (Colour, Gradient)
local function entryOf(ref: any): any?
	if type(ref) == "table" then
		local full = ref.Id and Songs.GetById(ref.Id)
		if full then
			return full
		end
		ref = ref.Artist
	end
	if type(ref) ~= "string" then
		return nil
	end
	local hit = byGroup[ref]
	if hit == nil then
		hit = false
		for _, song in Songs.All do
			if song.Artist == ref then
				hit = song
				break
			end
		end
		byGroup[ref] = hit
	end
	return hit or nil
end

local function luminance(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

function GroupArt.Main(ref: any): Color3
	local e = entryOf(ref)
	return if e and e.Colour then C(e.Colour) else FALLBACK
end

function GroupArt.Gradient(ref: any): ColorSequence?
	local e = entryOf(ref)
	return e and e.Gradient
end

-- the gradient's colours plus the pastel, for particles
function GroupArt.Colours(ref: any): { Color3 }
	local out = { GroupArt.Main(ref) }
	local g = GroupArt.Gradient(ref)
	if g then
		for _, k in g.Keypoints do
			table.insert(out, k.Value)
		end
	end
	return out
end

-- dark enough that ink text would get lost
function GroupArt.IsDark(ref: any): boolean
	local g = GroupArt.Gradient(ref)
	if not g then
		return luminance(GroupArt.Main(ref)) < 0.45
	end
	local sum = 0
	for _, k in g.Keypoints do
		sum += luminance(k.Value)
	end
	return sum / #g.Keypoints < 0.45
end

-- Paints `frame` and returns the BackgroundColor3 it should end on (white under a gradient),
-- so a caller can tween to it from something else.
function GroupArt.Paint(frame: GuiObject, ref: any, rotation: number?): Color3
	local grad = frame:FindFirstChild("Group") :: UIGradient?
	local colours = GroupArt.Gradient(ref)
	if colours and not grad then
		local g = Instance.new("UIGradient")
		g.Name = "Group"
		g.Parent = frame
		grad = g
	end
	local target = if colours then WHITE else GroupArt.Main(ref)
	if grad then
		grad.Enabled = colours ~= nil
		if colours then
			grad.Color = colours
			grad.Rotation = rotation or 135
		end
	end
	frame.BackgroundColor3 = target
	local textColour = if GroupArt.IsDark(ref) then CREAM else INK
	for _, name in TEXT_NAMES do
		local label = frame:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.TextColor3 = textColour
		end
	end
	return target
end

return GroupArt
