--| NMIXX
-- JYP · 4th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "NMIXX",
	GroupType = "Girl",
	Generation = "4th",
	Colour = "9FE3D6", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("7B6CFF"), Color3.fromHex("38D6C4")), -- no official colour: violet to teal (the 'mix')
	Status = "Active",
	PackArt = "rbxassetid://81826498922796", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "O.O",
			Year = 2022,
			MusicId = "rbxassetid://81996619275994",
			AnimationId = "rbxassetid://10788127821",
			PlaybackSpeed = 0.59,
			TimePosition = 1,
			ChorusPosition = 35.2,
		},
		{
			Name = "DICE",
			Year = 2022,
			MusicId = "rbxassetid://108751937501217",
			PlaybackSpeed = 0.56,
			TimePosition = 4,
			ChorusPosition = 33.3,
		},
		{
			Name = "Party O'Clock",
			Year = 2023,
			MusicId = "rbxassetid://131609960840269",
			Volume = 0.7,
			PlaybackSpeed = 0.57,
			TimePosition = 1,
			ChorusPosition = 39.9,
		},
		{
			Name = "DASH",
			Year = 2024,
			MusicId = "rbxassetid://136842587389485",
			Volume = 0.7,
			PlaybackSpeed = 0.56,
			TimePosition = 0.5,
			ChorusPosition = 30.4,
		},
		{
			Name = "Soñar (Breaker)",
			Year = 2024,
			MusicId = "rbxassetid://76408160294512",
			Volume = 0.85,
			PlaybackSpeed = 0.58,
			TimePosition = 7,
			ChorusPosition = 27.4,
		},
		{
			Name = "KNOW ABOUT ME",
			Year = 2025,
			MusicId = "rbxassetid://79916916919039",
			Volume = 0.7,
			PlaybackSpeed = 0.76,
			TimePosition = 5,
			ChorusPosition = 37,
		},
		{
			Name = "Blue Valentine",
			Year = 2025,
			MusicId = "rbxassetid://107038623777151",
			Volume = 1.45,
			PlaybackSpeed = 0.57,
			TimePosition = 0.5,
			ChorusPosition = 29.9,
		},
		{
			Name = "Young, Dumb, Stupid",
			Year = 2023,
			MusicId = "rbxassetid://77956701650883",
			Volume = 0.85,
			PlaybackSpeed = 0.6,
			TimePosition = 2,
			ChorusPosition = 34.6,
		},
		{
			Name = "See that?",
			Year = 2024,
			MusicId = "rbxassetid://101865042127223",
			Volume = 0.7,
			PlaybackSpeed = 0.68,
			TimePosition = 1,
			ChorusPosition = 37.1,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "nmixx-blue-valentine",
			Name = "Blue Valentine",
			Year = 2025,
			Colour = "A8D8FF",
			Songs = { "Blue Valentine" },
			Members = { "LILY", "HAEWON", "SULLYOON", "BAE", "JIWOO", "KYUJIN" },
			Art = {
				["LILY"] = "rbxassetid://116177611952053",
				["HAEWON"] = "rbxassetid://89227771648853",
				["SULLYOON"] = "rbxassetid://72802792053853",
				["BAE"] = "rbxassetid://98155259657583",
				["JIWOO"] = "rbxassetid://140717078741530",
				["KYUJIN"] = "rbxassetid://93119475940778",
			},
		},
	},
}
