--| Super Junior
-- SM · 2nd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "Super Junior",
	GroupType = "Boy",
	Generation = "2nd",
	Colour = "8FB8F0", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("3E7FE0"), Color3.fromHex("0F52BA")), -- official: Pearl Sapphire Blue
	Status = "Active",
	Songs = {
		{
			Name = "Sorry Sorry",
			Year = 2009,
			MusicId = "rbxassetid://89758592440816",
			AnimationId = "rbxassetid://8388954854",
			PlaybackSpeed = 0.9,
			TimePosition = 7,
			ChorusPosition = 108.3,
		},
		{
			Name = "U",
			Year = 2006,
			MusicId = "rbxassetid://107291480040753",
			TimePosition = 30,
			ChorusPosition = 138.2,
		},
		{
			Name = "Mamacita",
			Year = 2014,
			MusicId = "rbxassetid://87730731864558",
			PlaybackSpeed = 0.78,
			TimePosition = 1,
			ChorusPosition = 38.4,
		},
		{
			Name = "Mr. Simple",
			Year = 2011,
			MusicId = "rbxassetid://71808974855483",
			PlaybackSpeed = 0.63,
			TimePosition = 2,
			ChorusPosition = 43.1,
		},
		{
			Name = "Bonamana",
			Draft = true, -- audio didn't load in game (2026-11-04): re-upload / check permissions
			Year = 2010,
			MusicId = "rbxassetid://97031550641529",
			PlaybackSpeed = 0.55,
			TimePosition = 0,
			ChorusPosition = 0,
		},
	},
}
