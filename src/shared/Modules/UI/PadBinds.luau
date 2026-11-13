--| PadBinds
-- Controller shortcuts for a screen. While a screen is up its buttons are bound above the
-- character controls (ContextActionService), and every bound button shows its controller icon:
-- a "PadIcon" made in Studio on that button (or on a holder near it), shown while a
-- controller is the last thing used. A PadIcon is a holder (or the ImageLabel itself) whose
-- "Glyph" ImageLabel shows one cell of the controller sheet: Kenney Input Prompts (CC0) redrawn
-- in ink, with the D-pad's pressed arm in red (assets/padicons/*_ink.png, 5×2 cells of 128px):
--   A B X Y LB / RB D-pad ← ↑ → ↓   (PlayStation: ✕ ○ □ △ L1 / R1 and its D-pad)
-- The D-pad is handed back to Roblox's menu navigation while a button is selected.
--   local unbind = PadBinds.Bind("HUD", {
--       { Key = Enum.KeyCode.ButtonY, Chip = menu.QuickPlay, Run = function() ... end },
--       { Key = Enum.KeyCode.ButtonB, Chip = panel.Leave, When = function() return panel.Leave.Visible end, Run = leave },
--   })
--   unbind()                                    -- on Deactivate
-- Several entries can share a key: the first whose When() is true (or has no When) runs; if
-- none can, the press passes through to whatever else wants it.
--   PadBinds.Paint(padIcon, Enum.KeyCode.ButtonA, true)   -- show one icon by hand
--   PadBinds.Label(key)                         -- "A" / "✕" on PlayStation, as text
--   PadBinds.UsingPad()                         -- a controller was the last thing used

-- -------------------------------- Services -------------------------------- --
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

-- --------------------------------- Tables --------------------------------- --
local SHEET = {
	Xbox = "rbxassetid://135713292515019",
	PlayStation = "rbxassetid://83377662820443",
}
-- Kenney's own light sheet, for icons over the dark street (the PadIcon has a PadLight attribute)
local SHEET_LIGHT = {
	Xbox = "rbxassetid://126142973967152",
	PlayStation = "rbxassetid://92107460421972",
}
local CELL_SIZE = 128
-- each key's cell on the sheet, left to right then the second row
local CELL = {
	ButtonA = 0, ButtonB = 1, ButtonX = 2, ButtonY = 3, ButtonL1 = 4,
	ButtonR1 = 5, DPadLeft = 6, DPadUp = 7, DPadRight = 8, DPadDown = 9,
}
local LABELS = {
	Xbox = { ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y", ButtonL1 = "LB", ButtonR1 = "RB" },
	PlayStation = { ButtonA = "✕", ButtonB = "○", ButtonX = "□", ButtonY = "△", ButtonL1 = "L1", ButtonR1 = "R1" },
}
local ARROWS = { DPadUp = "↑", DPadDown = "↓", DPadLeft = "←", DPadRight = "→" }

-- left to Roblox's menu navigation while a button is selected
local NAVIGATION = {
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadRight] = true,
	[Enum.KeyCode.DPadDown] = true,
}

export type Bind = {
	Key: Enum.KeyCode,
	Run: () -> (),
	Chip: Instance?, -- the button (or holder) whose "PadIcon" shows this key
	When: (() -> boolean)?, -- only while this is true; otherwise the press passes on
}

local PadBinds = {}

local active: { [string]: { Bind } } = {}

-- ---------------------------------- Looks --------------------------------- --

function PadBinds.UsingPad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- "Xbox" or "PlayStation": Roblox's own image for ButtonA names the pad it's drawing
local function kind(): string
	local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, Enum.KeyCode.ButtonA)
	local path = if ok and type(image) == "string" then string.lower(image) else ""
	local ps = string.find(path, "playstation", 1, true) or string.find(path, "ps4", 1, true) or string.find(path, "ps5", 1, true)
	return if ps then "PlayStation" else "Xbox"
end

function PadBinds.Label(key: Enum.KeyCode): string
	return LABELS[kind()][key.Name] or ARROWS[key.Name] or key.Name
end

-- A PadIcon with a PadInset attribute (px) makes room inside its button: the button's text
-- labels move right by that much while the icon shows, and back when it hides.
local function inset(icon: GuiObject, on: boolean)
	local px = icon:GetAttribute("PadInset")
	if type(px) ~= "number" or not icon.Parent then
		return
	end
	for _, label in icon.Parent:GetChildren() do
		if label:IsA("TextLabel") then
			if label:GetAttribute("PadBasePos") == nil then
				label:SetAttribute("PadBasePos", label.Position)
				label:SetAttribute("PadBaseSize", label.Size)
			end
			local pos, size = label:GetAttribute("PadBasePos"), label:GetAttribute("PadBaseSize")
			-- the left edge moves right by px and the right edge stays: the anchor decides how far
			-- the position has to move for that (all of px left-anchored, half of it centred)
			local shift = px * (1 - label.AnchorPoint.X)
			label.Position = if on then pos + UDim2.fromOffset(shift, 0) else pos
			label.Size = if on then size - UDim2.fromOffset(px, 0) else size
		end
	end
end

-- Shows `key` on a PadIcon (its cell of the pad's sheet), or hides it.
function PadBinds.Paint(icon: Instance?, key: Enum.KeyCode, show: boolean)
	if not icon or not icon:IsA("GuiObject") then
		return
	end
	local glyph = if icon:IsA("ImageLabel") then icon else icon:FindFirstChild("Glyph")
	local cell = CELL[key.Name]
	icon.Visible = show and cell ~= nil and glyph ~= nil
	inset(icon, icon.Visible)
	if not icon.Visible then
		return
	end
	glyph.Image = (if icon:GetAttribute("PadLight") then SHEET_LIGHT else SHEET)[kind()]
	glyph.ImageRectSize = Vector2.new(CELL_SIZE, CELL_SIZE)
	glyph.ImageRectOffset = Vector2.new((cell % 5) * CELL_SIZE, (cell // 5) * CELL_SIZE)
end

local function paint(binds: { Bind }, show: boolean)
	for _, bind in binds do
		if bind.Chip then
			PadBinds.Paint(bind.Chip:FindFirstChild("PadIcon"), bind.Key, show)
		end
	end
end

UserInputService.LastInputTypeChanged:Connect(function()
	local pad = PadBinds.UsingPad()
	for _, binds in active do
		paint(binds, pad)
	end
end)

-- ---------------------------------- Binding ------------------------------- --

function PadBinds.Bind(name: string, binds: { Bind }): () -> ()
	local action = "PadBinds_" .. name
	local keys: { Enum.KeyCode } = {}
	local byKey: { [Enum.KeyCode]: { Bind } } = {}
	for _, bind in binds do
		if not byKey[bind.Key] then
			byKey[bind.Key] = {}
			table.insert(keys, bind.Key)
		end
		table.insert(byKey[bind.Key], bind)
	end

	ContextActionService:BindActionAtPriority(action, function(_, state: Enum.UserInputState, input: InputObject)
		if NAVIGATION[input.KeyCode] and GuiService.SelectedObject then
			return Enum.ContextActionResult.Pass
		end
		for _, bind in byKey[input.KeyCode] or {} do
			if not bind.When or bind.When() then
				if state == Enum.UserInputState.Begin then
					bind.Run()
				end
				return Enum.ContextActionResult.Sink
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))

	active[name] = binds
	paint(binds, PadBinds.UsingPad())

	return function()
		ContextActionService:UnbindAction(action)
		if active[name] == binds then
			active[name] = nil
		end
		paint(binds, false)
	end
end

return PadBinds
