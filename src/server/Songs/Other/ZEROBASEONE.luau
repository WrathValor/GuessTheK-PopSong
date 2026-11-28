--| ZEROBASEONE
-- WakeOne · 5th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "ZEROBASEONE",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "A6C8FF", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("5C9BFF"), Color3.fromHex("2347D9")), -- official: Blue
	Status = "Active",
	PackArt = "rbxassetid://131008408598773", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "TOP 5",
			Year = 2026,
			MusicId = "rbxassetid://138702824651710",
			Volume = 1.1,
			PlaybackSpeed = 0.83,
			TimePosition = 0.5,
			ChorusPosition = 42,
		},
		{
			Name = "In Bloom",
			Year = 2023,
			MusicId = "rbxassetid://110736541263517",
			Volume = 1.3,
			PlaybackSpeed = 0.65,
			TimePosition = 0.5,
			ChorusPosition = 30,
		},
		{
			Name = "ICONIK",
			Year = 2025,
			MusicId = "rbxassetid://84585907457215",
			Volume = 1.1,
			PlaybackSpeed = 0.71,
			TimePosition = 0.5,
			ChorusPosition = 30,
		},
		{
			Name = "Doctor! Doctor!",
			Year = 2025,
			MusicId = "rbxassetid://131209585046528",
			PlaybackSpeed = 0.77,
			TimePosition = 1,
			ChorusPosition = 38.5,
		},
		{
			Name = "GOOD SO BAD",
			Year = 2024,
			MusicId = "rbxassetid://104741391199146",
			Volume = 0.75,
			PlaybackSpeed = 0.6,
			TimePosition = 1,
			ChorusPosition = 30,
		},
		{
			Name = "Insomnia",
			Year = 2024,
			MusicId = "rbxassetid://120216209799271",
			PlaybackSpeed = 0.75,
			TimePosition = 0.2,
			ChorusPosition = 42,
		},
		{
			Name = "SWEAT",
			Year = 2024,
			MusicId = "rbxassetid://85249612972776",
			PlaybackSpeed = 0.69,
			TimePosition = 0.2,
			ChorusPosition = 32,
		},
		{
			Name = "Feel the POP",
			Year = 2024,
			MusicId = "rbxassetid://122063514963235",
			Volume = 1.3,
			PlaybackSpeed = 0.54,
			TimePosition = 0.2,
			ChorusPosition = 25,
		},
		{
			Name = "YURA YURA",
			Year = 2024,
			MusicId = "rbxassetid://77661224560830",
			Volume = 1.3,
			PlaybackSpeed = 0.67,
			TimePosition = 0.3,
			ChorusPosition = 32,
		},
		{
			Name = "CRUSH",
			Year = 2023,
			MusicId = "rbxassetid://129438170213201",
			PlaybackSpeed = 0.72,
			TimePosition = 0.2,
			ChorusPosition = 22.5,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Members are the era's line-up.
	-- Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "zb1-youth-in-the-shade",
			Name = "Youth in the Shade",
			Year = 2023,
			Colour = "CDEFF2",
			Songs = { "In Bloom" },
			Members = { "SUNG HANBIN", "KIM JIWOONG", "ZHANG HAO", "SEOK MATTHEW", "KIM TAERAE", "RICKY", "KIM GYUVIN", "PARK GUNWOOK", "HAN YUJIN" },
			Art = {
				["HAN YUJIN"] = "rbxassetid://86496516462413",
				["KIM GYUVIN"] = "rbxassetid://114157675688095",
				["KIM JIWOONG"] = "rbxassetid://108181935576249",
				["KIM TAERAE"] = "rbxassetid://88272937164747",
				["PARK GUNWOOK"] = "rbxassetid://127269618257168",
				["RICKY"] = "rbxassetid://80159217090692",
				["SEOK MATTHEW"] = "rbxassetid://77794617386362",
				["SUNG HANBIN"] = "rbxassetid://137632659311630",
				["ZHANG HAO"] = "rbxassetid://96584645395729",
			},
		},
	},
}
