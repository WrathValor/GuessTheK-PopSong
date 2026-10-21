local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(script.Animation)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

export type ButtonScaleConfig = Animation.ButtonScaleConfig

local ButtonScale = {}

local function getOrCreateUIScale(button: GuiObject): UIScale
	local uiScale = button:FindFirstChildOfClass("UIScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = button
	end

	return uiScale
end

function ButtonScale.Apply(button: GuiObject, config: ButtonScaleConfig?): () -> ()
	local cfg = config or Animation.Default
	local uiScale = getOrCreateUIScale(button)
	local hovered = false
	local pressed = false

	local function refresh()
		local scale = pressed and cfg.PressScale or (hovered and cfg.HoverScale or 1)

		Animation.TweenTo(uiScale, scale, cfg):Play()
	end

	local connections = {
		button.MouseEnter:Connect(function()
			hovered = true
			Sounds.Play("Hover")
			refresh()
		end),
		button.MouseLeave:Connect(function()
			hovered = false
			pressed = false
			refresh()
		end),
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not pressed then
					Sounds.Play("Click")
				end

				pressed = true
				refresh()
			end
		end),
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressed = false
				refresh()
			end
		end),
	}

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

function ButtonScale.ApplyToChildren(container: Instance, config: ButtonScaleConfig?): () -> ()
	local cleanups = {}

	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(cleanups, ButtonScale.Apply(child, config))
		end
	end

	return function()
		for _, cleanup in cleanups do
			cleanup()
		end
	end
end

-- Same as ApplyToChildren but recurses the whole descendant tree, only targeting real
-- GuiButtons (TextButton/ImageButton) so decorative nested Frames/ImageLabels are skipped.
function ButtonScale.ApplyToDescendants(container: Instance, config: ButtonScaleConfig?): () -> ()
	local cleanups = {}

	for _, descendant in container:GetDescendants() do
		if descendant:IsA("GuiButton") then
			table.insert(cleanups, ButtonScale.Apply(descendant, config))
		end
	end

	return function()
		for _, cleanup in cleanups do
			cleanup()
		end
	end
end

return ButtonScale
