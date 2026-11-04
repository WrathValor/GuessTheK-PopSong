--| BTOB
-- CUBE · 3rd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "BTOB",
	GroupType = "Boy",
	Generation = "3rd",
	Colour = "9ED8F5", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("8DB8EB"), Color3.fromHex("4F7FCF")), -- official: Slow Blue
	Status = "Active",
	Songs = {
		{
			Name = "Missing You",
			Year = 2017,
			MusicId = "rbxassetid://111749396832242",
			PlaybackSpeed = 0.96,
			TimePosition = 75,
			ChorusPosition = 150.7,
		},
		{
			Name = "Beep Beep",
			Year = 2014,
			MusicId = "rbxassetid://89553597182565",
			PlaybackSpeed = 0.97,
			TimePosition = 1,
			ChorusPosition = 51.9,
		},
		{
			Name = "Movie",
			Year = 2017,
			MusicId = "rbxassetid://108990972836307",
			PlaybackSpeed = 0.53,
			TimePosition = 3,
			ChorusPosition = 37.7,
		},
		{
			Name = "Beautiful Pain",
			Year = 2018,
			MusicId = "rbxassetid://112855605095728",
			PlaybackSpeed = 0.52,
			TimePosition = 2,
			ChorusPosition = 37.9,
		},
		{
			Name = "The Song",
			Draft = true, -- lesser-known song, held back for balance
			Year = 2022,
			MusicId = "rbxassetid://79462026236843",
			PlaybackSpeed = 0.91,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Wind and Wish",
			Year = 2023,
			MusicId = "rbxassetid://134905893826005",
			PlaybackSpeed = 0.93,
			TimePosition = 8,
			ChorusPosition = 86,
		},
	},
}
