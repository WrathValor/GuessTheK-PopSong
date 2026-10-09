local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Animation = require(script.Animation)

export type SlideUpConfig = Animation.SlideUpConfig

local SlideUp = {}

-- Home (fully-open) position per frame, captured on first Open so Close knows where to return.
local homePositions: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any

local function getHomePosition(frame: GuiObject): UDim2
	local home = homePositions[frame]

	if not home then
		home = frame.Position
		homePositions[frame] = home
	end

	return home
end

-- Slides `frame` up from below the screen into its designed StarterGui position.
function SlideUp.Open(frame: GuiObject, config: SlideUpConfig?)
	local cfg = config or Animation.Default
	local home = getHomePosition(frame)

	frame.Position = home + UDim2.fromScale(0, cfg.Distance)

	return Promise.new(function(resolve)
		local tween = TweenService:Create(frame, cfg.OpenTween, { Position = home })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

-- Reverse of Open: slides `frame` back down off-screen.
function SlideUp.Close(frame: GuiObject, config: SlideUpConfig?)
	local cfg = config or Animation.Default
	local home = getHomePosition(frame)

	return Promise.new(function(resolve)
		local tween = TweenService:Create(frame, cfg.CloseTween, { Position = home + UDim2.fromScale(0, cfg.Distance) })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

return SlideUp
