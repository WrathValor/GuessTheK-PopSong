--| aespa
-- SM · 4th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "aespa",
	GroupType = "Girl",
	Generation = "4th",
	Colour = "B8C4FF", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("0D0D14")), ColorSequenceKeypoint.new(0.5, Color3.fromHex("2D5BFF")), ColorSequenceKeypoint.new(1, Color3.fromHex("E62AB8")) }), -- black, blue + fuchsia
	Status = "Active",
	Songs = {
		{
			Name = "Next Level",
			Year = 2021,
			MusicId = "rbxassetid://126664177695353",
			Volume = 0.8,
			AnimationId = "rbxassetid://12002119615",
			PlaybackSpeed = 1,
			TimePosition = 5,
			ChorusPosition = 45.7,
		},
		{
			Name = "Supernova",
			Year = 2024,
			MusicId = "rbxassetid://97559273807135",
			Volume = 0.8,
			AnimationId = "rbxassetid://18613098825",
			PlaybackSpeed = 0.87,
			TimePosition = 6,
			ChorusPosition = 35.4,
		},
		{
			Name = "Black Mamba",
			Year = 2020,
			MusicId = "rbxassetid://106204230899514",
			Volume = 1.15,
			PlaybackSpeed = 0.57,
			TimePosition = 1,
			ChorusPosition = 25.9,
		},
		{
			Name = "LEMONADE",
			Year = 2026,
			MusicId = "rbxassetid://128795809970022",
			Volume = 1.25,
			PlaybackSpeed = 0.93,
			TimePosition = 0.5,
			ChorusPosition = 156.7,
		},
		{
			Name = "Armageddon",
			Year = 2024,
			MusicId = "rbxassetid://72937957486124",
			PlaybackSpeed = 0.96,
			TimePosition = 8,
			ChorusPosition = 103.8,
		},
		{
			Name = "KISS N TELL",
			Year = 2026,
			MusicId = "rbxassetid://122946646995569",
			PlaybackSpeed = 0.65,
			TimePosition = 8,
			ChorusPosition = 90.6,
		},
		{
			Name = "Whiplash",
			Year = 2024,
			MusicId = "rbxassetid://93994956505609",
			Volume = 0.7,
			TimePosition = 1,
			ChorusPosition = 124.2,
		},
		{
			Name = "Savage",
			Year = 2021,
			MusicId = "rbxassetid://110877559177545",
			PlaybackSpeed = 0.80,
			TimePosition = 0,
			ChorusPosition = 0,
			Draft = true, -- audio works
		},
	},
}
