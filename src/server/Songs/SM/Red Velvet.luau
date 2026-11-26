--| Red Velvet
-- SM · 3rd gen girl group · hiatus.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "Red Velvet",
	GroupType = "Girl",
	Generation = "3rd",
	Colour = "F7A1A1", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFB8A3"), Color3.fromHex("F4846C")), -- official: Pastel Coral
	Status = "Active",
	PackArt = "rbxassetid://135031992743714", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Russian Roulette",
			Year = 2016,
			MusicId = "rbxassetid://110949694817973",
			Volume = 1.5,
			PlaybackSpeed = 0.96,
			TimePosition = 1,
			ChorusPosition = 56.7,
		},
		{
			Name = "Bad Boy",
			Year = 2018,
			MusicId = "rbxassetid://112748895364129",
			Volume = 1.65,
			PlaybackSpeed = 0.85,
			TimePosition = 0.5,
			ChorusPosition = 67,
		},
		{
			Name = "Surfin' Boy",
			Year = 2026,
			MusicId = "rbxassetid://123129279059156",
			Volume = 1.35,
			PlaybackSpeed = 0.66,
			TimePosition = 2,
			ChorusPosition = 26.1,
		},
		{
			Name = "Peek-A-Boo",
			Year = 2017,
			MusicId = "rbxassetid://123097361358829",
			Volume = 0.8,
			PlaybackSpeed = 0.88,
			TimePosition = 23,
			ChorusPosition = 121.5,
		},
		{
			Name = "Cosmic",
			Year = 2024,
			MusicId = "rbxassetid://107939615810942",
			PlaybackSpeed = 0.8,
			TimePosition = 5,
			ChorusPosition = 55.4,
		},
		{
			Name = "Red Flavor",
			Year = 2017,
			MusicId = "rbxassetid://76734468362792",
			TimePosition = 17,
			ChorusPosition = 174.3,
		},
		{
			Name = "Dumb Dumb",
			Year = 2015,
			MusicId = "rbxassetid://88405456466891",
			Volume = 0.8,
			PlaybackSpeed = 0.56,
			TimePosition = 0.5,
			ChorusPosition = 22.9,
		},
		{
			Name = "Day 1",
			Year = 2015,
			MusicId = "rbxassetid://114060228014035",
			PlaybackSpeed = 0.7,
			TimePosition = 9,
			ChorusPosition = 47.9,
		},
		{
			Name = "Psycho",
			Year = 2019,
			MusicId = "rbxassetid://70664304758367",
			AnimationId = "rbxassetid://81487273177125",
			TimePosition = 3,
			ChorusPosition = 125.3,
		},
		{
			Name = "Chill Kill",
			Year = 2023,
			MusicId = "rbxassetid://136165598574697",
			Volume = 1.15,
			PlaybackSpeed = 0.65,
			TimePosition = 1,
			ChorusPosition = 42,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Members are the era's line-up.
	-- Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "redvelvet-cosmic",
			Name = "Cosmic",
			Year = 2024,
			Colour = "F7C9C9",
			Songs = { "Cosmic", "Surfin' Boy" },
			Members = { "Irene", "Seulgi", "Wendy", "Joy", "Yeri" },
			Art = {
				["Irene"] = "rbxassetid://84981473444258",
				["Seulgi"] = "rbxassetid://105766637185303",
				["Wendy"] = "rbxassetid://110070585648694",
				["Joy"] = "rbxassetid://117941493974268",
				["Yeri"] = "rbxassetid://133386439792138",
			},
		},
	},
}
