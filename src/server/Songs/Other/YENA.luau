--| YENA
-- Other (Yuehua) · 4th gen soloist · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "YENA",
	GroupType = "Solo",
	Generation = "4th",
	Colour = "FFE07A", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFE46B"), Color3.fromHex("FFC21A")), -- official: Yen-low
	Status = "Active",
	PackArt = "rbxassetid://89914865490729", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Catch Catch",
			Year = 2026,
			MusicId = "rbxassetid://97778832287551",
			Volume = 0.85,
			PlaybackSpeed = 0.98,
			TimePosition = 0.5,
			ChorusPosition = 62.2,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "yena-love-catcher",
			Name = "LOVE CATCHER",
			Year = 2026,
			Colour = "FFD08A",
			Songs = { "Catch Catch" },
			Members = { "YENA" },
			Art = {
				["YENA"] = "rbxassetid://89450797877706",
			},
		},
	},
}
