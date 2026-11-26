--| RIIZE
-- SM · 5th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "RIIZE",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "FF9A5C", -- card art + roll glow
	Gradient = ColorSequence.new(Color3.fromHex("FFC38B"), Color3.fromHex("F47B4A")),
	Status = "Active",
	PackArt = "rbxassetid://77813666766093", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Get A Guitar",
			Year = 2023,
			MusicId = "rbxassetid://104253494530970",
			PlaybackSpeed = 0.76,
			TimePosition = 0.5,
			ChorusPosition = 15.3,
		},
		{
			Name = "Do your dance",
			Year = 2026,
			MusicId = "rbxassetid://76819558872357",
			PlaybackSpeed = 0.75,
			TimePosition = 0.5,
			ChorusPosition = 55,
		},
		{
			Name = "Fame",
			Year = 2025,
			MusicId = "rbxassetid://72892512153867",
			PlaybackSpeed = 0.51,
			TimePosition = 0.2,
			ChorusPosition = 25,
		},
		{
			Name = "Love 119",
			Year = 2024,
			MusicId = "rbxassetid://133830668417209",
			PlaybackSpeed = 0.66,
			TimePosition = 0.5,
			ChorusPosition = 47,
		},
		{
			Name = "Boom Boom Bass",
			Year = 2024,
			MusicId = "rbxassetid://91116873944411",
			Volume = 0.85,
			PlaybackSpeed = 0.83,
			TimePosition = 0.2,
			ChorusPosition = 14.6,
		},
		{
			Name = "Impossible",
			Year = 2024,
			MusicId = "rbxassetid://140386936182023",
			Volume = 0.75,
			PlaybackSpeed = 0.83,
			TimePosition = 0.2,
			ChorusPosition = 44.6,
		},
		{
			Name = "Talk Saxy",
			Year = 2023,
			MusicId = "rbxassetid://107659141611837",
			Volume = 0.75,
			PlaybackSpeed = 0.51,
			TimePosition = 0.3,
			ChorusPosition = 30,
		},
		{
			Name = "Odyssey",
			Year = 2025,
			MusicId = "rbxassetid://125838332501762",
			PlaybackSpeed = 0.58,
			TimePosition = 0.3,
			ChorusPosition = 29.5,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Members are the era's line-up.
	-- Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "riize-riizing",
			Name = "RIIZING",
			Year = 2024,
			Colour = "FFD9B8",
			Songs = { "Boom Boom Bass", "Impossible", "Love 119" },
			Members = { "Shotaro", "Eunseok", "Sungchan", "Wonbin", "Sohee", "Anton" },
			Art = {
				["Shotaro"] = "rbxassetid://106529260166344",
				["Sungchan"] = "rbxassetid://73526057171590",
				["Wonbin"] = "rbxassetid://110703210316555",
				["Sohee"] = "rbxassetid://83571974591153",
				["Anton"] = "rbxassetid://120741675941620",
				["Eunseok"] = "rbxassetid://123096375362102",
			},
		},
	},
}
