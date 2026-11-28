--| i-dle
-- CUBE · 4th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "i-dle",
	GroupType = "Girl",
	Generation = "4th",
	Colour = "F7A8C8", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("E4002B"), Color3.fromHex("5C068C")), -- official: Neon Red + Chic Violet
	Status = "Active",
	PackArt = "rbxassetid://90549545872400", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Queencard",
			Year = 2023,
			MusicId = "rbxassetid://134743727001743",
			Volume = 0.8,
			PlaybackSpeed = 0.61,
			TimePosition = 9,
			ChorusPosition = 44.4,
		},
		{
			Name = "Mono",
			Year = 2026,
			MusicId = "rbxassetid://120067012177777",
			Volume = 0.7,
			PlaybackSpeed = 0.7,
			TimePosition = 3,
			ChorusPosition = 29.7,
		},
		{
			Name = "Good Thing",
			Year = 2025,
			MusicId = "rbxassetid://95771603467120",
			PlaybackSpeed = 0.62,
			TimePosition = 0,
			ChorusPosition = 0,
            Draft = true;
		},
		{
			Name = "Super Lady",
			Year = 2024,
			MusicId = "rbxassetid://127051452304998",
			Volume = 0.85,
			PlaybackSpeed = 0.9,
			TimePosition = 4,
			ChorusPosition = 51.2,
		},
		{
			Name = "Oh my god",
			Year = 2020,
			MusicId = "rbxassetid://134738288629239",
			Volume = 1.1,
			PlaybackSpeed = 0.56,
			TimePosition = 1,
			ChorusPosition = 58.8,
		},
		{
			Name = "LATATA",
			Year = 2018,
			MusicId = "rbxassetid://128487692602031",
			PlaybackSpeed = 0.69,
			TimePosition = 0,
			ChorusPosition = 0,
            Draft = true;
		},
		{
			Name = "Fate",
			Year = 2024,
			MusicId = "rbxassetid://132297337117250",
			Volume = 0.8,
			PlaybackSpeed = 0.83,
			TimePosition = 4,
			ChorusPosition = 32.9,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "idle-i-feel",
			Name = "I feel",
			Year = 2023,
			Colour = "E8B3F5",
			Cover = "rbxassetid://111089863849587",
			Songs = { "Queencard" },
			Members = { "MIYEON", "MINNIE", "SOYEON", "YUQI", "SHUHUA" },
			Art = { -- assets/Photocards/i-dle/I feel/<member>
				MIYEON = "rbxassetid://116939856782934",
				MINNIE = "rbxassetid://88315984549616",
				SOYEON = "rbxassetid://76713106349370",
				YUQI = "rbxassetid://121533428963676",
				SHUHUA = "rbxassetid://101262745789936",
			},
		},
		{
			Id = "idle-2",
			Name = "2",
			Year = 2024,
			Colour = "F7A8C8",
			Cover = "rbxassetid://132770210515208",
			Songs = {},
			Members = { "MINNIE", "MIYEON", "SHUHUA", "SOYEON", "YUQI" },
			Art = {
				["MINNIE"] = "rbxassetid://121946287462858",
				["MIYEON"] = "rbxassetid://89909530158357",
				["SHUHUA"] = "rbxassetid://105075576170724",
				["SOYEON"] = "rbxassetid://95751395732307",
				["YUQI"] = "rbxassetid://83899747254717",
			},
		},
	},
}
