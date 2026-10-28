export type FrameTransitionConfig = {
	OpenTween: TweenInfo,
	CloseTween: TweenInfo,
	FadeInTween: TweenInfo,
	RiseTween: TweenInfo,
	ScrimTween: TweenInfo,
	OpenFrom: number, -- scale the panel starts at when opening
	CloseTo: number, -- scale it shrinks to when closing
	Rise: number, -- px the panel rises while opening / drops while closing
}

local Animation: FrameTransitionConfig = {
	OpenTween = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	CloseTween = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	FadeInTween = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	RiseTween = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	ScrimTween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	OpenFrom = 0.82,
	CloseTo = 0.9,
	Rise = 28,
}

return Animation
