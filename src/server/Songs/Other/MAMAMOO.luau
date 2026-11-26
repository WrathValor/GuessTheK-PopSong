--| MAMAMOO
-- Other · 3rd gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "MAMAMOO",
	GroupType = "Girl",
	Generation = "3rd",
	Colour = "A8E0C9", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("A8E0C9"), Color3.fromHex("3FA97A")), -- no official colour: green
	Status = "Active",
	PackArt = "rbxassetid://115392892039524", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Starry Night",
			Year = 2018,
			MusicId = "rbxassetid://9783870104",
			AnimationId = "rbxassetid://9949308748",
			PlaybackSpeed = 0.83,
			Draft = true, -- not in the game until its audio is checked
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "mamamoo-yellow-flower",
			Name = "Yellow Flower",
			Year = 2018,
			Colour = "FFE9A0",
			Songs = { "Starry Night" },
			Members = { "SOLAR", "MOONBYUL", "WHEEIN", "HWASA" },
			Art = {
				["HWASA"] = "rbxassetid://124527886465225",
				["MOONBYUL"] = "rbxassetid://102701972968416",
				["SOLAR"] = "rbxassetid://132698840923070",
				["WHEEIN"] = "rbxassetid://72290240740417",
			},
		},
	},
}
