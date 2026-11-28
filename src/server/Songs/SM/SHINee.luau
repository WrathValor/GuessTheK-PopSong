--| SHINee
-- SM · 2nd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "SHINee",
	GroupType = "Boy",
	Generation = "2nd",
	Colour = "9EE6D8", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("A8EBDD"), Color3.fromHex("5FCDB8")), -- official: Pearl Aqua Green
	Status = "Active",
	PackArt = "rbxassetid://138135554458945", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Lucifer",
			Year = 2010,
			MusicId = "rbxassetid://90031012640818",
			PlaybackSpeed = 0.89,
			TimePosition = 1,
			ChorusPosition = 65.2,
		},
		{
			Name = "View",
			Year = 2015,
			MusicId = "rbxassetid://118580107233781",
			Volume = 1.8,
			PlaybackSpeed = 0.87,
			TimePosition = 1,
			ChorusPosition = 133,
		},
		{
			Name = "Everybody",
			Year = 2013,
			MusicId = "rbxassetid://102418401220396",
			Volume = 0.85,
			PlaybackSpeed = 0.58,
			TimePosition = 14,
			ChorusPosition = 92,
		},
		{
			Name = "Hello",
			Year = 2010,
			MusicId = "rbxassetid://86901082067245",
			PlaybackSpeed = 0.8,
			TimePosition = 18,
			ChorusPosition = 122.8,
		},
		{
			Name = "1 of 1",
			Year = 2016,
			MusicId = "rbxassetid://115141097160366",
			PlaybackSpeed = 0.74,
			TimePosition = 1,
			ChorusPosition = 30.3,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "shinee-atmos",
			Name = "Atmos",
			Year = 2026,
			Colour = "9EE8E0",
			Cover = "rbxassetid://121222320246119",
			Songs = {},
			Members = { "ONEW", "KEY", "MINHO", "TAEMIN" },
			Art = {
				["ONEW"] = "rbxassetid://89190063905573",
				["KEY"] = "rbxassetid://124397661813025",
				["TAEMIN"] = "rbxassetid://124279650878149",
				["MINHO"] = "rbxassetid://136172171811776",
			},
		},
		{
			Id = "shinee-hard",
			Name = "HARD",
			Year = 2023,
			Colour = "9EE6D8",
			Cover = "rbxassetid://91045304258825",
			Songs = {},
			Members = { "KEY", "MINHO", "ONEW", "TAEMIN" },
			Art = {
				["KEY"] = "rbxassetid://113446864749437",
				["MINHO"] = "rbxassetid://88177508226512",
				["ONEW"] = "rbxassetid://92486822512036",
				["TAEMIN"] = "rbxassetid://126208944491279",
			},
		},
	},
}
