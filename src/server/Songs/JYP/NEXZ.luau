--| NEXZ
-- JYP · 5th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "NEXZ",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "C2B8FF", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("39D5FF"), Color3.fromHex("3B5BFF")), -- no official colour: electric blue
	Status = "Active",
	PackArt = "rbxassetid://127049197531461", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Ride the Vibe",
			Year = 2024,
			MusicId = "rbxassetid://77448335411927",
			Volume = 0.85,
			PlaybackSpeed = 0.86,
			TimePosition = 11,
			ChorusPosition = 68,
		},
		{
			Name = "Keep on Moving",
			Draft = true, -- audio didn't load in game (2026-11-04): re-upload / check permissions
			Year = 2024,
			MusicId = "rbxassetid://134570343203816",
			PlaybackSpeed = 0.71,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Nallina",
			Year = 2024,
			MusicId = "rbxassetid://138643648277703",
			PlaybackSpeed = 0.92,
			TimePosition = 1,
			ChorusPosition = 48.6,
		},
		{
			Name = "O-RLY?",
			Year = 2025,
			MusicId = "rbxassetid://82977541432664",
			Volume = 0.75,
			PlaybackSpeed = 0.85,
			TimePosition = 1,
			ChorusPosition = 40.8,
		},
		{
			Name = "Beat-Boxer",
			Year = 2025,
			MusicId = "rbxassetid://133541741717215",
			Volume = 0.8,
			PlaybackSpeed = 0.65,
			TimePosition = 1,
			ChorusPosition = 37.2,
		},
		{
			Name = "One Bite",
			Year = 2025,
			MusicId = "rbxassetid://75436489393574",
			Volume = 1.15,
			PlaybackSpeed = 0.75,
			TimePosition = 1,
			ChorusPosition = 42,
		},
		{
			Name = "Mmchk",
			Year = 2026,
			MusicId = "rbxassetid://135285626273386",
			Volume = 1.15,
			PlaybackSpeed = 0.59,
			TimePosition = 1,
			ChorusPosition = 24.2,
		},
		{
			Name = "Hellmate",
			Year = 2026,
			MusicId = "rbxassetid://84679256553387",
			PlaybackSpeed = 0.97,
			TimePosition = 0.5,
			ChorusPosition = 27,
		},
		{
			Name = "SAUCIN'",
			Year = 2026,
			MusicId = "rbxassetid://140375188104403",
			Volume = 0.7,
			PlaybackSpeed = 0.82,
			TimePosition = 0.5,
			ChorusPosition = 27,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "nexz-ride-the-vibe",
			Name = "Ride the Vibe",
			Year = 2024,
			Colour = "B9F0C2",
			Songs = { "Ride the Vibe", "Keep on Moving" },
			Members = { "TOMOYA", "YU", "HARU", "SO GEON", "SEITA", "HYUI", "YUKI" },
			Art = {
				["TOMOYA"] = "rbxassetid://80815875086734",
				["YU"] = "rbxassetid://98733592450979",
				["HARU"] = "rbxassetid://118998815380919",
				["SO GEON"] = "rbxassetid://106278212231735",
				["SEITA"] = "rbxassetid://109625561440180",
				["HYUI"] = "rbxassetid://89146810559663",
				["YUKI"] = "rbxassetid://135842639565317",
			},
		},
	},
}
