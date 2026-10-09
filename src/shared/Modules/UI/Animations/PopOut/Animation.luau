local TweenService = game:GetService("TweenService")

export type PopOutConfig = {
	TweenInfo: TweenInfo,
	EndScale: number,
}

local Animation = {}

Animation.Default = {
	TweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	EndScale = 0,
} :: PopOutConfig

function Animation.TweenTo(uiScale: UIScale, config: PopOutConfig): Tween
	return TweenService:Create(uiScale, config.TweenInfo, { Scale = config.EndScale })
end

return Animation
