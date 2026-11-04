--| STAYC
-- Other · 4th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "STAYC",
	GroupType = "Girl",
	Generation = "4th",
	Colour = "FFB8D9", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFB8D9"), Color3.fromHex("FF5FA2")), -- no official colour: pink
	Status = "Active",
	Songs = {
		{
			Name = "ASAP",
			Year = 2021,
			MusicId = "rbxassetid://13958604539",
			AnimationId = "rbxassetid://8388901204",
			PlaybackSpeed = 0.75,
			Draft = true, -- not in the game until its audio is checked
		},
	},
}
