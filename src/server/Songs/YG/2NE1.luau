--| 2NE1
-- YG · 2nd gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "2NE1",
	GroupType = "Girl",
	Generation = "2nd",
	Colour = "F3A6D8", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FF5CAD"), Color3.fromHex("FF1F8E")), -- official: Hot Pink
	Status = "Active",
	Songs = {
		{
			Name = "I Don't Care",
			Year = 2009,
			MusicId = "rbxassetid://77248102304853",
			Volume = 2,
			PlaybackSpeed = 0.63,
			TimePosition = 15,
			ChorusPosition = 65.2,
		},
		{
			Name = "Fire",
			Year = 2009,
			MusicId = "rbxassetid://77227937347541",
			Volume = 1.1,
			PlaybackSpeed = 0.63,
			TimePosition = 13,
			ChorusPosition = 58.9,
		},
		{
			Name = "I Am the Best",
			Year = 2011,
			MusicId = "rbxassetid://91753841127342",
			Volume = 2.3,
			PlaybackSpeed = 0.58,
			TimePosition = 9,
			ChorusPosition = 101.3,
		},
		{
			Name = "Lonely",
			Year = 2011,
			MusicId = "rbxassetid://112205226149518",
			Volume = 1.35,
			PlaybackSpeed = 0.65,
			TimePosition = 0,
			ChorusPosition = 39.1,
		},
		{
			Name = "Come Back Home",
			Draft = true, -- audio didn't load in game (2026-11-01): re-upload / check permissions
			Year = 2014,
			MusicId = "rbxassetid://139102251686812",
			PlaybackSpeed = 0.74,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Ugly",
			Draft = true, -- lesser-known song, held back for balance
			Year = 2011,
			MusicId = "rbxassetid://121993632610268",
			PlaybackSpeed = 0.75,
			TimePosition = 0,
			ChorusPosition = 57,
		},
		{
			Name = "Can't Nobody",
			Draft = true, -- lesser-known song, held back for balance
			Year = 2010,
			MusicId = "rbxassetid://107715212294117",
			PlaybackSpeed = 0.98,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Go Away",
			Year = 2010,
			MusicId = "rbxassetid://119454225535236",
			Volume = 1.1,
			PlaybackSpeed = 0.62,
			TimePosition = 1,
			ChorusPosition = 39.4,
		},
	},
}
