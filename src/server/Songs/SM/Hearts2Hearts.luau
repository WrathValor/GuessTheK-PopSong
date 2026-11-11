--| Hearts2Hearts
-- SM · 5th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "Hearts2Hearts",
	GroupType = "Girl",
	Generation = "5th",
	Colour = "FFC1CC", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("B8E2FF"), Color3.fromHex("6FB8F2")), -- official: Sky Blue
	Status = "Active",
	Songs = {
		{
			Name = "The Chase",
			Year = 2025,
			MusicId = "rbxassetid://94786208211157",
			Volume = 0.85,
			PlaybackSpeed = 0.9,
			TimePosition = 0,
			ChorusPosition = 84.6,
		},
		{
			Name = "FOCUS",
			Year = 2025,
			MusicId = "rbxassetid://88279643163218",
			Volume = 1.25,
			PlaybackSpeed = 0.93,
			TimePosition = 3,
			ChorusPosition = 60.3,
		},
		{
			Name = "RUDE!",
			Year = 2026,
			MusicId = "rbxassetid://77704329055200",
			Volume = 1.4,
			PlaybackSpeed = 0.96,
			TimePosition = 2,
			ChorusPosition = 57.9,
		},
		{
			Name = "Lemon Tang",
			Year = 2026,
			MusicId = "rbxassetid://131649899465356",
			Volume = 0.85,
			PlaybackSpeed = 0.67,
			TimePosition = 3,
			ChorusPosition = 28.4,
		},
		{
			Name = "Moonride",
			Year = 2026,
			MusicId = "rbxassetid://132144003687745",
			PlaybackSpeed = 0.57,
			TimePosition = 3,
			ChorusPosition = 57.3,
		},
		{
			Name = "Butterflies",
			Draft = true, -- lesser-known song, held back for balance
			Year = 2025,
			MusicId = "rbxassetid://105342725336576",
			PlaybackSpeed = 0.74,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "ICONIC HEART",
			Year = 2026,
			MusicId = "rbxassetid://113745657046669",
			PlaybackSpeed = 0.88,
			TimePosition = 0,
			ChorusPosition = 0,
			Draft = true, -- audio works, future upd
		},
	},
}
