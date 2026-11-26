--| FrameTransition
-- Opening/closing animation for full-screen frames (Frames.<Name>):
--   open  – the dark scrim fades in while the panel springs up from slightly small and a
--           little low (Back overshoot), so it lands with a bounce
--   close – the panel dips and shrinks a touch while the scrim fades out
-- The frame is re-anchored to its centre once (without moving) so it scales from the middle.
-- Big screens (more than HEAVY descendants, like the Binder, Shop, Market) don't scale: a
-- UIScale change re-lays out every label under it each frame (all the text is TextScaled,
-- Modules/UI/FitText), which dropped frames while they opened and closed. They slide up with
-- the same bounce (Animation.HeavyRise) while the scrim fades, which costs nothing. A frame's
-- "FT_Scale" attribute (true / false) overrides the count.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Promise = require(ReplicatedStorage.Packages.promise)
local Animation = require(script.Animation)

local FrameTransition = {}

local HEAVY = 800 -- descendants: past this a frame slides instead of scaling

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

-- does this frame scale when it opens? (counted once)
local function scales(frame: GuiObject): boolean
	local forced = frame:GetAttribute("FT_Scale")
	if type(forced) == "boolean" then
		return forced
	end
	local heavy = frame:GetAttribute("FT_Heavy")
	if heavy == nil then
		heavy = #frame:GetDescendants() > HEAVY
		frame:SetAttribute("FT_Heavy", heavy)
	end
	return not heavy
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
		local scrim, rest = scrimOf(frame)
		if scrim then
			scrim.BackgroundTransparency = 1
			TweenService:Create(scrim, Animation.ScrimTween, { BackgroundTransparency = rest }):Play()
		end
		if not scales(frame) then
			local s = frame:FindFirstChildOfClass("UIScale")
			if s then
				s.Scale = 1
			end
			frame.Position = home + UDim2.fromOffset(0, Animation.HeavyRise)
			local slide = TweenService:Create(frame, Animation.OpenTween, { Position = home })
			slide.Completed:Once(resolve)
			slide:Play()
			return
		end
		local uiScale = getOrCreateUIScale(frame)
		uiScale.Scale = Animation.OpenFrom
		frame.Position = home + UDim2.fromOffset(0, Animation.Rise)
		TweenService:Create(frame, Animation.RiseTween, { Position = home }):Play()
		local tween = TweenService:Create(uiScale, Animation.OpenTween, { Scale = 1 })
		tween.Completed:Once(resolve)
		tween:Play()
	end)
end

function FrameTransition.Close(frame: GuiObject)
	return Promise.new(function(resolve)
		local home = prepare(frame)
		local scrim = scrimOf(frame)
		if scrim then
			TweenService:Create(scrim, Animation.CloseTween, { BackgroundTransparency = 1 }):Play()
		end
		if not scales(frame) then
			local slide = TweenService:Create(frame, Animation.CloseTween, { Position = home + UDim2.fromOffset(0, Animation.HeavyRise * 0.6) })
			slide.Completed:Once(function()
				frame.Position = home
				resolve()
			end)
			slide:Play()
			return
		end
		local uiScale = getOrCreateUIScale(frame)
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
