--| BESTie
-- Other (YNB) · 3rd gen girl group · disbanded.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "BESTie",
	GroupType = "Girl",
	Generation = "3rd",
	Colour = "FFD6E8", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("8FE3C6"), Color3.fromHex("8FB8FF")), -- no official colour: mint to sky
	Status = "Disbanded",
	PackArt = "rbxassetid://127542856592913", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Love Options",
			Year = 2013,
			MusicId = "rbxassetid://116329344199698",
			Volume = 0.85,
			PlaybackSpeed = 0.61,
			TimePosition = 5,
			ChorusPosition = 48.4,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "bestie-love-options",
			Name = "Love Options",
			Year = 2013,
			Colour = "FFD6E8",
			Songs = { "Love Options" },
			Members = { "HYEYEON", "UJI", "DAHYE", "HAERYUNG" },
		},
	},
}
