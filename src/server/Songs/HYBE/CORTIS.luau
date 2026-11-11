--| CORTIS
-- HYBE · 5th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "CORTIS",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "FFD2A8", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("7BE495"), Color3.fromHex("22A35A")), -- no official colour: GREENGREEN era green
	Status = "Active",
	Songs = {
		{
			Name = "GO!",
			Year = 2025,
			MusicId = "rbxassetid://136203255761917",
			Volume = 1.8,
			PlaybackSpeed = 0.62,
			TimePosition = 0.5,
			ChorusPosition = 16.3,
		},
		{
			Name = "FaSHioN",
			Draft = true, -- audio didn't load in game (2026-11-04): re-upload / check permissions
			Year = 2025,
			MusicId = "rbxassetid://126392806007412",
			PlaybackSpeed = 0.53,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "REDRED",
			Year = 2026,
			MusicId = "rbxassetid://79549981431120",
			PlaybackSpeed = 0.62,
			TimePosition = 0.5,
			ChorusPosition = 0,
		},
		{
			Name = "MONEYMONEYMONEY",
			Year = 2026,
			MusicId = "rbxassetid://87937517395160",
			Volume = 1.2,
			PlaybackSpeed = 0.75,
			TimePosition = 0.5,
			ChorusPosition = 15,
		},
		{
			Name = "ACAI",
			Year = 2026,
			MusicId = "rbxassetid://117634531638486",
			PlaybackSpeed = 0.7,
			TimePosition = 1,
			ChorusPosition = 36,
		},
		{
			Name = "MOTION",
			Year = 2026,
			MusicId = "rbxassetid://89930901999335",
			Volume = 0.75,
			PlaybackSpeed = 0.9,
			TimePosition = 1,
			ChorusPosition = 61,
		},
		{
			Name = "TNT",
			Year = 2026,
			MusicId = "rbxassetid://131955769099787",
			Volume = 2,
			PlaybackSpeed = 0.93,
			TimePosition = 1,
			ChorusPosition = 33,
		},
		{
			Name = "JoyRide",
			Year = 2025,
			MusicId = "rbxassetid://115849693920627",
			Volume = 1.7,
			PlaybackSpeed = 0.69,
			TimePosition = 1,
			ChorusPosition = 43.5,
		},
		{
			Name = "What You Want",
			Year = 2025,
			MusicId = "rbxassetid://130370764274856",
			Volume = 1.25,
			PlaybackSpeed = 0.91,
			TimePosition = 0.5,
			ChorusPosition = 41,
		},
		{
			Name = "Mention Me",
			Year = 2026,
			MusicId = "rbxassetid://134615846672856",
			Volume = 1.25,
			PlaybackSpeed = 0.88,
			TimePosition = 1,
			ChorusPosition = 26,
		},
	},
}
