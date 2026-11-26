--| IVE
-- Starship · 4th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "IVE",
	GroupType = "Girl",
	Generation = "4th",
	Colour = "C6B3FF", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FF8FAB"), Color3.fromHex("E63946")), -- no official colour: rose to red
	Status = "Active",
	PackArt = "rbxassetid://118813739306486", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "CRUMBS",
			Year = 2026,
			MusicId = "rbxassetid://75949352055893",
			PlaybackSpeed = 0.8,
			TimePosition = 1,
			ChorusPosition = 62.8,
		},
		{
			Name = "Looks Can Kill",
			Year = 2026,
			MusicId = "rbxassetid://107856708478598",
			Volume = 3.75,
			PlaybackSpeed = 0.75,
			TimePosition = 1,
			ChorusPosition = 36.3,
		},
		{
			Name = "Rebel Heart",
			Year = 2025,
			MusicId = "rbxassetid://75579081452937",
			Volume = 0.8,
			PlaybackSpeed = 0.94,
			TimePosition = 1,
			ChorusPosition = 46.5,
		},
		{
			Name = "Mirror Mirror",
			Year = 2026,
			MusicId = "rbxassetid://94766253273433",
			Volume = 1.65,
			PlaybackSpeed = 0.85,
			TimePosition = 1,
			ChorusPosition = 36.5,
		},
		{
			Name = "SNAKESKIN",
			Year = 2026,
			MusicId = "rbxassetid://76677029754471",
			Volume = 0.8,
			PlaybackSpeed = 0.53,
			TimePosition = 0.7,
			ChorusPosition = 35.8,
		},
		{
			Name = "Girls Girls Girls",
			Year = 2026,
			MusicId = "rbxassetid://122576807244271",
			PlaybackSpeed = 0.82,
			TimePosition = 0,
			ChorusPosition = 36.5,
		},
		{
			Name = "Glow Motion",
			Draft = true, -- audio didn't load in game (2026-11-01): re-upload / check permissions
			Year = 2026,
			MusicId = "rbxassetid://134408227400703",
			PlaybackSpeed = 0.71,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "I AM",
			Year = 2023,
			MusicId = "rbxassetid://88586228510557",
			PlaybackSpeed = 0.86,
			TimePosition = 2,
			ChorusPosition = 46.9,
		},
		{
			Name = "Baddie",
			Draft = true, -- audio didn't load in game (2026-11-01): re-upload / check permissions
			Year = 2023,
			MusicId = "rbxassetid://84672455920399",
			PlaybackSpeed = 0.61,
			TimePosition = 1,
			ChorusPosition = 31.9,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "ive-looks-can-kill",
			Name = "Looks Can Kill",
			Year = 2026,
			Colour = "F5C2D6",
			Songs = { "Looks Can Kill" },
			Members = { "YUJIN", "GAEUL", "REI", "WONYOUNG", "LIZ", "LEESEO" },
			Art = {
				["YUJIN"] = "rbxassetid://77181092342345",
				["GAEUL"] = "rbxassetid://107459843155912",
				["REI"] = "rbxassetid://105641064949939",
				["WONYOUNG"] = "rbxassetid://86496879094237",
				["LIZ"] = "rbxassetid://115933396505834",
				["LEESEO"] = "rbxassetid://129955839047460",
			},
		},
	},
}
