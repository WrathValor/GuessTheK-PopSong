--| BLACKPINK
-- YG · 3rd gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "BLACKPINK",
	GroupType = "Girl",
	Generation = "3rd",
	Colour = "FF9EC4", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFA3C4"), Color3.fromHex("2B1A22")), -- black + pink (logo and merch, not announced)
	Status = "Active",
	Songs = {
		{
			Name = "DDU-DU DDU-DU",
			Year = 2018,
			MusicId = "rbxassetid://98317914774714",
			AnimationId = "rbxassetid://12242141185",
			PlaybackSpeed = 0.55,
			TimePosition = 5,
			ChorusPosition = 73.4,
		},
		{
			Name = "Kill This Love",
			Year = 2019,
			MusicId = "rbxassetid://105736261833014",
			AnimationId = "rbxassetid://115299858690334",
			PlaybackSpeed = 0.55,
			TimePosition = 5,
			ChorusPosition = 39.4,
		},
		{
			Name = "How You Like That",
			Year = 2020,
			MusicId = "rbxassetid://127437780441396",
			AnimationId = "rbxassetid://10006646356",
			PlaybackSpeed = 0.55,
			TimePosition = 8,
			ChorusPosition = 54.9,
		},
		{
			Name = "Pink Venom",
			Year = 2022,
			MusicId = "rbxassetid://131998902160253",
			AnimationId = "rbxassetid://11275732879",
			PlaybackSpeed = 0.55,
			TimePosition = 5,
			ChorusPosition = 35,
		},
		{
			Name = "Lovesick Girls",
			Year = 2020,
			MusicId = "rbxassetid://128979978324039",
			PlaybackSpeed = 0.62,
			TimePosition = 5,
			ChorusPosition = 32.2,
		},
		{
			Name = "BOOMBAYAH",
			Year = 2016,
			MusicId = "rbxassetid://85928502225571",
			PlaybackSpeed = 0.71,
			TimePosition = 7,
			ChorusPosition = 60.5,
		},
		{
			Name = "GO",
			Year = 2026,
			MusicId = "rbxassetid://114333019744005",
			PlaybackSpeed = 0.93,
			TimePosition = 5,
			ChorusPosition = 41,
		},
		{
			Name = "As If It's Your Last",
			Year = 2017,
			MusicId = "rbxassetid://86169131194185",
			PlaybackSpeed = 0.56,
			TimePosition = 0.9,
			ChorusPosition = 36.5,
		},
		{
			Name = "WHISTLE",
			Year = 2016,
			MusicId = "rbxassetid://137428850740476",
			PlaybackSpeed = 0.55,
			TimePosition = 1,
			ChorusPosition = 42.8,
		},
		{
			Name = "Shut Down",
			Draft = true, -- audio didn't load in game (2026-11-04): re-upload / check permissions
			Year = 2022,
			MusicId = "rbxassetid://115932798932008",
			PlaybackSpeed = 0.61,
			TimePosition = 0,
			ChorusPosition = 0,
		},
	},
}
