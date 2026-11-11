--| TVXQ
-- SM · 2nd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "TVXQ",
	GroupType = "Boy",
	Generation = "2nd",
	Colour = "F09A9A", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("E5383B"), Color3.fromHex("A4161A")), -- official: Pearl Red
	Status = "Active",
	Songs = {
		{
			Name = "Rising Sun",
			Year = 2005,
			MusicId = "rbxassetid://85406612596458",
			Volume = 0.75,
			PlaybackSpeed = 0.6,
			TimePosition = 40,
			ChorusPosition = 83,
		},
		{
			Name = "Mirotic",
			Year = 2008,
			MusicId = "rbxassetid://96354044057405",
			PlaybackSpeed = 0.66,
			TimePosition = 15,
			ChorusPosition = 42.4,
		},
		{
			Name = "Catch Me",
			Year = 2012,
			MusicId = "rbxassetid://120244959338829",
			Volume = 0.6,
			PlaybackSpeed = 0.63,
			TimePosition = 4,
			ChorusPosition = 50.6,
		},
		{
			Name = "The Chance of Love",
			Year = 2018,
			MusicId = "rbxassetid://74268330963157",
			Volume = 0.75,
			PlaybackSpeed = 0.71,
			TimePosition = 2,
			ChorusPosition = 37.6,
		},
	},
}
