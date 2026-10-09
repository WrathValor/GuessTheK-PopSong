local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Promise = require(ReplicatedStorage.Packages.promise)
local Animation = require(script.Animation)

local FrameTransition = {}

local function getOrCreateUIScale(frame: GuiObject): UIScale
	local uiScale = frame:FindFirstChildOfClass("UIScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end

	return uiScale
end

function FrameTransition.Open(frame: GuiObject)
	return Promise.new(function(resolve)
		local uiScale = getOrCreateUIScale(frame)
		uiScale.Scale = 0

		local tween = TweenService:Create(uiScale, Animation.OpenTween, { Scale = 1 })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

function FrameTransition.FadeIn(frame: GuiObject)
	return Promise.new(function(resolve)
		local tween = TweenService:Create(frame, Animation.FadeInTween, { BackgroundTransparency = 1})
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

function FrameTransition.FadeOut(frame: GuiObject)
	return Promise.new(function(resolve)
		local tween = TweenService:Create(frame, Animation.FadeInTween, { BackgroundTransparency = 1 })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

function FrameTransition.Close(frame: GuiObject)
	return Promise.new(function(resolve)
		local uiScale = getOrCreateUIScale(frame)

		local tween = TweenService:Create(uiScale, Animation.CloseTween, { Scale = 0 })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

return FrameTransition
