--| BEAST
-- CUBE · 2nd gen boy group · disbanded.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "BEAST",
	GroupType = "Boy",
	Generation = "2nd",
	Colour = "C9C3D9", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("5A5A66"), Color3.fromHex("2E2E36")), -- official: Dark Grey
	Status = "Disbanded",
	PackArt = "rbxassetid://121319161015431", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Shock",
			Year = 2010,
			MusicId = "rbxassetid://82871602462313",
			PlaybackSpeed = 0.62,
			TimePosition = 9,
			ChorusPosition = 94.2,
		},
		{
			Name = "On Rainy Days",
			Year = 2011,
			MusicId = "rbxassetid://132259541018166",
			Volume = 1.25,
			PlaybackSpeed = 0.74,
			TimePosition = 11,
			ChorusPosition = 113.6,
		},
		{
			Name = "Shadow",
			Year = 2012,
			MusicId = "rbxassetid://80204307026458",
			Volume = 1.5,
			PlaybackSpeed = 0.61,
			TimePosition = 1,
			ChorusPosition = 41.8,
		},
		{
			Name = "12:30",
			Draft = true, -- lesser-known song, held back for balance
			Year = 2014,
			MusicId = "rbxassetid://95655246779003",
			PlaybackSpeed = 0.95,
			TimePosition = 11,
			ChorusPosition = 73.6,
		},
		{
			Name = "BREATH",
			Year = 2010,
			MusicId = "rbxassetid://91967502194602",
			Volume = 1.55,
			PlaybackSpeed = 0.89,
			TimePosition = 30,
			ChorusPosition = 151,
		},
		{
			Name = "Bad Girl",
			Year = 2009,
			MusicId = "rbxassetid://126434403453627",
			PlaybackSpeed = 0.92,
			TimePosition = 9,
			ChorusPosition = 69.4,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "beast-fiction-and-fact",
			Name = "Fiction and Fact",
			Year = 2011,
			Colour = "C9C3D9",
			Songs = { "On Rainy Days", "Shock", "BREATH", "Bad Girl", "Shadow" },
			Members = { "DOOJOON", "HYUNSEUNG", "JUNHYUNG", "YOSEOB", "GIKWANG", "DONGWOON" },
			Art = { -- assets/Photocards/BEAST/Fiction and Fact/<member>
				DOOJOON = "rbxassetid://110915418198297",
				HYUNSEUNG = "rbxassetid://113286495444041",
				JUNHYUNG = "rbxassetid://70905041907346",
				YOSEOB = "rbxassetid://71535701240618",
				GIKWANG = "rbxassetid://90878284697787",
				DONGWOON = "rbxassetid://138580838276417",
			},
		},
	},
}
