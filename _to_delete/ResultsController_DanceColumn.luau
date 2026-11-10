--| DanceColumn
-- The DANCE column on the results table: a Robux button (or "Owned") on each round whose song
-- has a dance in the group's UGC (Constants/UGCCatalog.SONGS).
--   DanceColumn.Build(panel)              – once, in Studio: shifts You/Rival left, adds the
--                                           column header + a Dance button per row (safe twice)
--   DanceColumn.Fill(panel, rounds)       – rounds: the End packet's Rounds (Name, Artist)
--   DanceColumn.Connect(panel, janitor)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGC = require(ReplicatedStorage.Modules.UGC)
local UGCCatalog = require(ReplicatedStorage.Constants.UGCCatalog)

local C = Color3.fromHex
local INK = C("1E1B2E")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local ROBUX = "rbxassetid://83637405007021"
local SHIFT = 74

local DanceColumn = {}

local function new(className: string, props, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function moveX(gui: GuiObject?, dx: number)
	if gui then
		gui.Position += UDim2.fromOffset(dx, 0)
	end
end

function DanceColumn.Build(panel: Instance)
	local tbl = panel.Table
	if tbl.Header:FindFirstChild("ColDance") then
		return
	end
	moveX(tbl.Header.ColYou, -SHIFT)
	moveX(tbl.Header.ColRival, -SHIFT)
	moveX(tbl.Total.You, -SHIFT)
	moveX(tbl.Total.Rival, -SHIFT)
	local col = tbl.Header.ColRival:Clone()
	col.Name = "ColDance"
	col.Text = "DANCE"
	col.Position = UDim2.fromOffset(552, 0)
	col.Size = UDim2.fromOffset(72, 20)
	col.Parent = tbl.Header
	for i = 1, 7 do
		local row = tbl.Rows:FindFirstChild("Round" .. i)
		if row then
			moveX(row.You, -SHIFT)
			moveX(row.Rival, -SHIFT)
			row.Title.Size = UDim2.fromOffset(350, row.Title.Size.Y.Offset)
			row.Artist.Size = UDim2.fromOffset(350, row.Artist.Size.Y.Offset)
			local b = new("TextButton", { Name = "Dance", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(588, 27), Size = UDim2.fromOffset(70, 30), BackgroundColor3 = MINT, Text = "", AutoButtonColor = false, Visible = false }, row)
			new("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
			new("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, b)
			new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1, Image = ROBUX, ScaleType = Enum.ScaleType.Fit }, b)
			new("TextLabel", { Name = "Label", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BackgroundTransparency = 1, FontFace = HEAD, TextSize = 12, TextColor3 = INK, Text = "40" }, b)
		end
	end
end

function DanceColumn.Fill(panel: Instance, rounds: { any })
	local tbl = panel.Table
	local any = false
	for i = 1, 7 do
		local row = tbl.Rows:FindFirstChild("Round" .. i)
		local b = row and row:FindFirstChild("Dance")
		if b then
			local round = rounds[i]
			local item = round and UGC.ForSong(`{round.Name} - {round.Artist}`)
			if item and item.Kind ~= "Dance" then
				item = nil
			end
			b.Visible = item ~= nil
			b:SetAttribute("AssetId", item and item.Id or nil)
			if item then
				any = true
				local owned = UGC.Owned(item.Id) == true
				b.Label.Text = if owned then "Owned" else tostring(item.Price)
				b.Icon.Visible = not owned
				if UGCCatalog.ROBUX_ICON ~= "" then
					b.Icon.Image = UGCCatalog.ROBUX_ICON
					b.Icon.ImageColor3 = INK
				end
				b.BackgroundColor3 = if owned then GREY else MINT
			end
		end
	end
	local col = tbl.Header:FindFirstChild("ColDance")
	if col then
		col.Visible = any
	end
end

function DanceColumn.Connect(panel: Instance, janitor)
	for i = 1, 7 do
		local row = panel.Table.Rows:FindFirstChild("Round" .. i)
		local b = row and row:FindFirstChild("Dance")
		if b then
			janitor:Add(b.Activated:Connect(function()
				local id = b:GetAttribute("AssetId")
				if id and UGC.Owned(id) ~= true then
					UGC.Buy(id, "Results")
				end
			end))
		end
	end
end

return DanceColumn
