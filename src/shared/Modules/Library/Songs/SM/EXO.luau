--| EXO
-- SM · 3rd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "EXO",
	GroupType = "Boy",
	Generation = "3rd",
	Colour = "CFD5E6", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFF8E7"), Color3.fromHex("E8D6AE")), -- official: Cosmic Latte
	Status = "Active",
	Songs = {
		{
			Name = "Monster",
			Year = 2016,
			MusicId = "rbxassetid://101024672072100",
			PlaybackSpeed = 0.75,
			TimePosition = 0,
			ChorusPosition = 78.8,
		},
		{
			Name = "CALL ME BABY",
			Draft = true, -- audio didn't load in game (2026-11-01): re-upload / check permissions
			Year = 2015,
			MusicId = "rbxassetid://94231277616372",
			PlaybackSpeed = 0.80,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Tempo",
			Year = 2018,
			MusicId = "rbxassetid://70420913648757",
			PlaybackSpeed = 0.97,
			TimePosition = 3,
			ChorusPosition = 72.8,
		},
		{
			Name = "Love Shot",
			Year = 2018,
			MusicId = "rbxassetid://94217715729788",
			PlaybackSpeed = 0.82,
			TimePosition = 1,
			ChorusPosition = 36.9,
		},
		{
			Name = "Growl",
			Year = 2013,
			MusicId = "rbxassetid://97300645109098",
			PlaybackSpeed = 0.71,
			TimePosition = 0,
			ChorusPosition = 33.4,
		},
		{
			Name = "The Eve",
			Year = 2017,
			MusicId = "rbxassetid://81366308556357",
			TimePosition = 1,
			ChorusPosition = 45,
		},
		{
			Name = "Obsession",
			Year = 2019,
			MusicId = "rbxassetid://106632897050546",
			Volume = 2,
			PlaybackSpeed = 0.55,
			TimePosition = 1,
			ChorusPosition = 101.5,
		},
		{
			Name = "Ko Ko Bop",
			Year = 2017,
			MusicId = "rbxassetid://102962035264134",
			PlaybackSpeed = 0.67,
			TimePosition = 1,
			ChorusPosition = 106.1,
		},
		{
			Name = "Lotto",
			Year = 2016,
			MusicId = "rbxassetid://135222801004238",
			PlaybackSpeed = 0.98,
			TimePosition = 1,
			ChorusPosition = 46.2,
		},
		{
			Name = "Power",
			Year = 2017,
			MusicId = "rbxassetid://129111839213517",
			PlaybackSpeed = 0.72,
			TimePosition = 0.5,
			ChorusPosition = 37.8,
		},
	},
}
