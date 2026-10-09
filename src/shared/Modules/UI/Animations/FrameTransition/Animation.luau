export type FrameTransitionConfig = {
	OpenTween: TweenInfo,
	CloseTween: TweenInfo,
	FadeInTween: TweenInfo,
}

local Animation: FrameTransitionConfig = {
	OpenTween = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	CloseTween = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	FadeInTween = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

return Animation
