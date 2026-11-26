import os
os.chdir(os.path.expanduser('~/mnt/GuessTheK-PopSong/src/client/Client/InterfaceController/Controllers'))
exec(open('/tmp/p.py').read())

# --- Albums: Build ---
patch('AlbumsController/Build.luau', [
("""local function closeButton(parent: Instance, cx: number, cy: number): TextButton""",
"""-- the pink Bias button (design board "55 · Bias button"): left of ×1 / ×5 / ×10, opens the
-- Bias page, where you see your bias and can change it
local function biasButton(cluster: Instance): TextButton
	local b = new("TextButton", {
		Name = "Bias",
		LayoutOrder = -3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 38),
		BackgroundColor3 = PINK,
		FontFace = BODY,
		TextSize = 15,
		TextColor3 = INK,
		Text = "Bias",
		AutoButtonColor = false,
	}, cluster)
	corner(b, 12)
	stroke(b, 3, INK)
	pad(b, 18)
	return b
end

local function closeButton(parent: Instance, cx: number, cy: number): TextButton"""),
("""	ghost(cluster, "Odds", "Rarities", 14, { LayoutOrder = -1, Size = UDim2.fromOffset(0, 38) })
""", """	ghost(cluster, "Odds", "Rarities", 14, { LayoutOrder = -1, Size = UDim2.fromOffset(0, 38) })
	biasButton(cluster)
"""),
("""function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Albums")""",
"""-- Adds just the Bias button to an Albums frame built before it existed (Edit mode, then save):
--   require(<this>).BiasButton(game.StarterGui.Interface.Frames)
function Build.BiasButton(frames: Instance)
	local cluster = frames.Albums.Shop.Controls
	local old = cluster:FindFirstChild("Bias")
	if old then
		old:Destroy()
	end
	cluster.Size = UDim2.fromOffset(480, 38)
	return biasButton(cluster)
end

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Albums")"""),
("""	local cluster = new("Frame", { Name = "Controls", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 60), Size = UDim2.fromOffset(400, 38), BackgroundTransparency = 1 }, page)""",
"""	local cluster = new("Frame", { Name = "Controls", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 60), Size = UDim2.fromOffset(480, 38), BackgroundTransparency = 1 }, page)"""),
])

# --- Albums: controller ---
patch('AlbumsController/init.luau', [
("""	j:Add(f.Bias.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))""",
"""	j:Add(f.Bias.Close.Activated:Connect(function()
		-- opened from the Packs page's Bias button: back to the packs, not out
		if self._biasFromShop then
			self._biasFromShop = false
			self:_showPage("Shop")
			self:_fillShop()
			return
		end
		self._interface:Close(self.Name)
	end))
	local biasButton = f.Shop.Controls:FindFirstChild("Bias")
	if biasButton then
		j:Add(biasButton.Activated:Connect(function()
			Sounds.Play("Click")
			self._biasFromShop = true
			self._group, self._pick = nil, nil
			self:_showPage("Bias")
			self:_fillBias()
		end))
	end"""),
("""	else
		self:_showPage("Shop")
		self:_fillShop()
	end
end

-- -------------------------------- Shop page ------------------------------- --""",
"""	else
		self._biasFromShop = false
		self:_showPage("Shop")
		self:_fillShop()
	end
end

-- -------------------------------- Shop page ------------------------------- --"""),
("""	self._group, self._pick = nil, nil
	if self._opts.Page == "Bias" or (self._opts.First and bias() == "") then""",
"""	self._group, self._pick = nil, nil
	self._biasFromShop = false
	if self._opts.Page == "Bias" or (self._opts.First and bias() == "") then"""),
])

# --- Binder: Build ---
patch('BinderController/Build.luau', [
("""	text(coins, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 17, TextColor3 = CREAM, Text = "5,068", LayoutOrder = 2 })
end""",
"""	text(coins, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 17, TextColor3 = CREAM, Text = "5,068", LayoutOrder = 2 })
	Build.BiasButton(root)
end

-- the pink Bias button (design board "55 · Bias button"): left of the coins, opens the Bias
-- page in Packs (BinderController keeps it 12 px left of the coins as they grow)
function Build.BiasButton(root: Instance): TextButton
	local old = root:FindFirstChild("Bias")
	if old then
		old:Destroy()
	end
	local b = new("TextButton", {
		Name = "Bias",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(870, 81),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 38),
		BackgroundColor3 = PINK,
		FontFace = BODY,
		TextSize = 15,
		TextColor3 = INK,
		Text = "Bias",
		AutoButtonColor = false,
	}, root)
	corner(b, 12)
	stroke(b, 3, INK)
	pad(b, 18)
	return b
end"""),
])

# --- Binder: controller ---
patch('BinderController/init.luau', [
("""	j:Add(f.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(f.Collect.Activated:Connect(function()
		self:_collect()
	end))""",
"""	j:Add(f.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(f.Collect.Activated:Connect(function()
		self:_collect()
	end))
	-- Bias: the Bias page in Packs; it sits 12 px left of the coins, which grow with the amount
	local biasButton = f:FindFirstChild("Bias")
	if biasButton then
		local function place()
			local scale = f.AbsoluteSize.X / 1280
			if scale > 0 then
				biasButton.Position = UDim2.fromOffset(f.Coins.Position.X.Offset - f.Coins.AbsoluteSize.X / scale - 12, f.Coins.Position.Y.Offset)
			end
		end
		place()
		j:Add(f.Coins:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
		j:Add(biasButton.Activated:Connect(function()
			self._interface:Open("Albums", { Page = "Bias" })
		end))
	end"""),
])
print('bias patched')
