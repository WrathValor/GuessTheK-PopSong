local TweenService = game:GetService("TweenService")

export type ButtonScaleConfig = {
	HoverScale: number,
	PressScale: number,
	TweenInfo: TweenInfo,
}

local Animation = {}

Animation.Default = {
	HoverScale = 1.08,
	PressScale = 0.92,
	TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
} :: ButtonScaleConfig

function Animation.TweenTo(uiScale: UIScale, scale: number, config: ButtonScaleConfig): Tween
	return TweenService:Create(uiScale, config.TweenInfo, { Scale = scale })
end

return Animation
