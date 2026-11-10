--| ATEEZ
-- KQ · 4th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "ATEEZ",
	GroupType = "Boy",
	Generation = "4th",
	Colour = "FFC58A", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("F4C152"), Color3.fromHex("D9541E")), -- no official colour: gold to sunset orange
	Status = "Active",
	Songs = {
		{
			Name = "Guerrilla",
			Year = 2022,
			MusicId = "rbxassetid://127942082857385",
			PlaybackSpeed = 0.57,
			TimePosition = 18,
			ChorusPosition = 44.9,
		},
		{
			Name = "BOUNCY",
			Year = 2023,
			MusicId = "rbxassetid://123556233354026",
			Volume = 2,
			PlaybackSpeed = 0.59,
			TimePosition = 3,
			ChorusPosition = 45.1,
		},
		{
			Name = "BAD",
			Year = 2026,
			MusicId = "rbxassetid://105857837418182",
			PlaybackSpeed = 0.56,
			TimePosition = 0,
			ChorusPosition = 68.4,
		},
		{
			Name = "HALAZIA",
			Draft = true, -- audio didn't load in game (2026-11-04): re-upload / check permissions
			Year = 2022,
			MusicId = "rbxassetid://112208378848858",
			PlaybackSpeed = 0.61,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Crazy Form",
			Year = 2023,
			MusicId = "rbxassetid://114014936063500",
			PlaybackSpeed = 0.6,
			TimePosition = 1,
			ChorusPosition = 35.6,
		},
		{
			Name = "WORK",
			Year = 2024,
			MusicId = "rbxassetid://137338683178063",
			PlaybackSpeed = 0.75,
			TimePosition = 1,
			ChorusPosition = 41,
		},
		{
			Name = "Ice on my Teeth",
			Year = 2024,
			MusicId = "rbxassetid://95414215333438",
			PlaybackSpeed = 0.56,
			TimePosition = 1,
			ChorusPosition = 43,
		},
	},
}
