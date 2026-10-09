local Animation = require(script.Animation)

export type PopInConfig = Animation.PopInConfig

local PopIn = {}

function PopIn.Play(instance: GuiObject, config: PopInConfig?)
	local cfg = config or Animation.Default
	local uiScale = instance:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	uiScale.Parent = instance
	uiScale.Scale = cfg.StartScale

	Animation.TweenTo(uiScale, cfg):Play()
end

function PopIn.WatchContainer(container: Instance, config: PopInConfig?): () -> ()
	local connection = container.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			PopIn.Play(child, config)
		end
	end)

	return function()
		connection:Disconnect()
	end
end

return PopIn
