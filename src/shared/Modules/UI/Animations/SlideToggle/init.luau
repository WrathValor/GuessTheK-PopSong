local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.promise)
local Animation = require(script.Animation)

export type SlideToggleConfig = Animation.SlideToggleConfig

local SlideToggle = {}

-- Tweens `frame`'s Position to `position`, resolving once the slide finishes. Generic - the
-- caller decides what "open"/"closed" mean (e.g. off the right edge of the screen vs docked).
function SlideToggle.To(frame: GuiObject, position: UDim2, config: SlideToggleConfig?)
	local cfg = config or Animation.Default

	return Promise.new(function(resolve)
		local tween = Animation.TweenTo(frame, position, cfg)
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

return SlideToggle
