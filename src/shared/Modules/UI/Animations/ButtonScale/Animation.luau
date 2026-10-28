local TweenService = game:GetService("TweenService")

export type ButtonScaleConfig = {
	HoverScale: number,
	PressScale: number,
	TweenInfo: TweenInfo, -- kept for older callers; the springy tweens below are used instead
	HoverTween: TweenInfo?,
	PressTween: TweenInfo?,
	ReleaseTween: TweenInfo?,
}

local Animation = {}

Animation.Default = {
	HoverScale = 1.07,
	PressScale = 0.9,
	TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- hover: a little springy overshoot
	HoverTween = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- press: quick squish
	PressTween = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- release / leave: bounces back past its size and settles
	ReleaseTween = TweenInfo.new(0.42, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, 0, false, 0),
} :: ButtonScaleConfig

-- `from` is the scale it's leaving, so a release out of a press gets the elastic bounce.
function Animation.TweenTo(uiScale: UIScale, scale: number, config: ButtonScaleConfig, from: number?): Tween
	local info = config.TweenInfo
	if scale == config.PressScale and config.PressTween then
		info = config.PressTween
	elseif from == config.PressScale and config.ReleaseTween then
		info = config.ReleaseTween
	elseif scale == config.HoverScale and config.HoverTween then
		info = config.HoverTween
	elseif config.HoverTween then
		info = config.HoverTween
	end
	return TweenService:Create(uiScale, info, { Scale = scale })
end

return Animation
