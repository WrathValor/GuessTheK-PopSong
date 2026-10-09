local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Animation = require(script.Animation)

export type PopOutConfig = Animation.PopOutConfig

local PopOut = {}

-- Reverse of PopIn: scales an instance out. Returns a Promise resolving once the tween
-- completes, so callers can chain the actual :Destroy() after the animation finishes.
function PopOut.Play(instance: GuiObject, config: PopOutConfig?)
	local cfg = config or Animation.Default
	local uiScale = instance:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	uiScale.Parent = instance

	return Promise.new(function(resolve)
		local tween = Animation.TweenTo(uiScale, cfg)
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

return PopOut
