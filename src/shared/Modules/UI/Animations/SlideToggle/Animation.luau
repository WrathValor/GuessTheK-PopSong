local TweenService = game:GetService("TweenService")

export type SlideToggleConfig = {
	TweenInfo: TweenInfo,
}

local Animation = {}

Animation.Default = {
	TweenInfo = TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
} :: SlideToggleConfig

function Animation.TweenTo(frame: GuiObject, position: UDim2, config: SlideToggleConfig): Tween
	return TweenService:Create(frame, config.TweenInfo, { Position = position })
end

return Animation
