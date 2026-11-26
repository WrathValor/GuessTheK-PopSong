--| A2O LITE
-- A2O Entertainment · 5th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "A2O LITE",
	GroupType = "Girl",
	Generation = "5th",
	Colour = "B6EAD7", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("B6EAD7"), Color3.fromHex("4FBF9A")), -- no official colour: mint
	Status = "Active",
	PackArt = "rbxassetid://139291080397160", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "NEON",
			Draft = true, -- held back until A2O LITE has enough songs for a group of their own
			Year = 2026,
			MusicId = "rbxassetid://102818501907757",
			PlaybackSpeed = 0.94,
			TimePosition = 0,
			ChorusPosition = 50.5,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "a2olite-neon",
			Name = "NEON",
			Year = 2026,
			Colour = "C2F5A8",
			Songs = { "NEON" },
			Members = { "YOUNG", "HIMEKI", "VORA", "XILI", "RADA", "MERCI", "AYUNE", "OA", "AIJING" },
		},
	},
}
