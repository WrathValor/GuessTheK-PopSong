--| FrameTransition
-- Opening/closing animation for full-screen frames (Frames.<Name>):
--   open  – the dark scrim fades in while the panel springs up from slightly small and a
--           little low (Back overshoot), so it lands with a bounce
--   close – the panel dips and shrinks a touch while the scrim fades out
-- The frame is re-anchored to its centre once (without moving) so it scales from the middle.

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

-- Anchor at the centre (keeping the same spot) and remember the resting position.
local function prepare(frame: GuiObject): UDim2
	if frame:GetAttribute("FT_Home") == nil then
		local a, pos, size = frame.AnchorPoint, frame.Position, frame.Size
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = pos
			+ UDim2.new(size.X.Scale * (0.5 - a.X), size.X.Offset * (0.5 - a.X), size.Y.Scale * (0.5 - a.Y), size.Y.Offset * (0.5 - a.Y))
		frame:SetAttribute("FT_Home", frame.Position)
	end
	return frame:GetAttribute("FT_Home")
end

-- The frame's scrim (if any) and the transparency it rests at.
local function scrimOf(frame: GuiObject): (GuiObject?, number)
	local scrim = frame:FindFirstChild("Scrim")
	if not (scrim and scrim:IsA("GuiObject")) then
		return nil, 1
	end
	if scrim:GetAttribute("FT_Rest") == nil then
		scrim:SetAttribute("FT_Rest", scrim.BackgroundTransparency)
	end
	return scrim, scrim:GetAttribute("FT_Rest")
end

function FrameTransition.Open(frame: GuiObject)
	return Promise.new(function(resolve)
		local home = prepare(frame)
		local uiScale = getOrCreateUIScale(frame)
		uiScale.Scale = Animation.OpenFrom
		frame.Position = home + UDim2.fromOffset(0, Animation.Rise)

		local scrim, rest = scrimOf(frame)
		if scrim then
			scrim.BackgroundTransparency = 1
			TweenService:Create(scrim, Animation.ScrimTween, { BackgroundTransparency = rest }):Play()
		end
		TweenService:Create(frame, Animation.RiseTween, { Position = home }):Play()
		local tween = TweenService:Create(uiScale, Animation.OpenTween, { Scale = 1 })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

function FrameTransition.Close(frame: GuiObject)
	return Promise.new(function(resolve)
		local home = prepare(frame)
		local uiScale = getOrCreateUIScale(frame)
		local scrim = scrimOf(frame)
		if scrim then
			TweenService:Create(scrim, Animation.CloseTween, { BackgroundTransparency = 1 }):Play()
		end
		TweenService:Create(frame, Animation.CloseTween, { Position = home + UDim2.fromOffset(0, Animation.Rise * 0.5) }):Play()
		local tween = TweenService:Create(uiScale, Animation.CloseTween, { Scale = Animation.CloseTo })
		tween.Completed:Once(function()
			frame.Position = home
			resolve()
		end)
		tween:Play()
	end)
end

function FrameTransition.FadeIn(frame: GuiObject)
	return Promise.new(function(resolve)
		local tween = TweenService:Create(frame, Animation.FadeInTween, { BackgroundTransparency = 1 })
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

return FrameTransition
