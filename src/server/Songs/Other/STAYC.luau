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
	PackArt = "rbxassetid://72840963600302", -- group art: pack sleeve + binder (assets/Photocards/Groups)
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
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "stayc-staydom",
			Name = "STAYDOM",
			Year = 2021,
			Colour = "FFC2D1",
			Songs = { "ASAP" },
			Members = { "SUMIN", "SIEUN", "ISA", "SEEUN", "YOON", "J" },
			Art = {
				["ISA"] = "rbxassetid://71226112263423",
				["J"] = "rbxassetid://134742763312847",
				["SEEUN"] = "rbxassetid://124342538430991",
				["SIEUN"] = "rbxassetid://80152235342175",
				["SUMIN"] = "rbxassetid://71867881132639",
				["YOON"] = "rbxassetid://82844007250456",
			},
		},
	},
}
