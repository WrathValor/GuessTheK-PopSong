--| LOONA
-- Other · 4th gen girl group · disbanded.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "LOONA",
	GroupType = "Girl",
	Generation = "4th",
	Colour = "C9B8F0", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("C9B8F0"), Color3.fromHex("F2C94C")), -- no official colour: moon lilac to gold
	Status = "Disbanded",
	PackArt = "rbxassetid://97739848155415", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "So What",
			Year = 2020,
			MusicId = "rbxassetid://9963687119",
			AnimationId = "rbxassetid://9905346962",
			PlaybackSpeed = 0.83,
			Draft = true, -- not in the game until its audio is checked
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "loona-12-00",
			Name = "[12:00]",
			Year = 2020,
			Colour = "C9B8F0",
			Songs = { "So What" },
			Members = { "HEEJIN", "HYUNJIN", "YEOJIN", "VIVI", "KIM LIP", "JINSOUL", "CHOERRY", "YVES", "CHUU", "GO WON", "OLIVIA HYE" },
			Art = {
				["CHUU"] = "rbxassetid://89443591821182",
				["CHOERRY"] = "rbxassetid://89393885390295",
				["GO WON"] = "rbxassetid://137190613426025",
				["HEEJIN"] = "rbxassetid://109009999460733",
				["HYUNJIN"] = "rbxassetid://76748599941593",
				["JINSOUL"] = "rbxassetid://75570778172666",
				["KIM LIP"] = "rbxassetid://123731581323124",
				["OLIVIA HYE"] = "rbxassetid://133329813514631",
				["VIVI"] = "rbxassetid://101372086439505",
				["YEOJIN"] = "rbxassetid://139777523326945",
				["YVES"] = "rbxassetid://113627375065922",
			},
		},
	},
}
