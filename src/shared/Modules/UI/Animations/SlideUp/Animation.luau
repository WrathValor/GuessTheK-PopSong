export type SlideUpConfig = {
	OpenTween: TweenInfo,
	CloseTween: TweenInfo,
	Distance: number,
}

local Animation = {}

Animation.Default = {
	OpenTween = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	CloseTween = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
	Distance = 1,
} :: SlideUpConfig

return Animation
