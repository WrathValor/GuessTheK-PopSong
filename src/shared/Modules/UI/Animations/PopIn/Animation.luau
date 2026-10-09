local TweenService = game:GetService("TweenService")

export type PopInConfig = {
	TweenInfo: TweenInfo,
	StartScale: number,
}

local Animation = {}

Animation.Default = {
	TweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	StartScale = 0,
} :: PopInConfig

function Animation.TweenTo(uiScale: UIScale, config: PopInConfig): Tween
	return TweenService:Create(uiScale, config.TweenInfo, { Scale = 1 })
end

return Animation
