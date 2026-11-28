--| MOMOLAND
-- Other · 3rd gen girl group · disbanded.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "MOMOLAND",
	GroupType = "Girl",
	Generation = "3rd",
	Colour = "FFD58A", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFC09A"), Color3.fromHex("FF8FA8")), -- no official colour: peach ('momo')
	Status = "Disbanded",
	PackArt = "rbxassetid://76908659997631", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "BBoom BBoom",
			Year = 2018,
			MusicId = "rbxassetid://83073055697009",
			AnimationId = "rbxassetid://12242220021",
			PlaybackSpeed = 0.82,
			TimePosition = 0.5,
			ChorusPosition = 68.5,
		},
		{
			Name = "Freeze!",
			Year = 2017,
			MusicId = "rbxassetid://91440054845433",
			Volume = 1.15,
			PlaybackSpeed = 0.97,
			TimePosition = 1,
			ChorusPosition = 66.2,
		},
		{
			Name = "BAAM",
			Year = 2018,
			MusicId = "rbxassetid://84320390375214",
			Volume = 0.85,
			PlaybackSpeed = 0.91,
			TimePosition = 1,
			ChorusPosition = 62.1,
		},
		{
			Name = "Thumbs Up",
			Year = 2019,
			MusicId = "rbxassetid://137911448859625",
			Volume = 0.85,
			PlaybackSpeed = 0.95,
			TimePosition = 1,
			ChorusPosition = 44.7,
		},
		{
			Name = "Wrap Me In Plastic",
			Year = 2021,
			MusicId = "rbxassetid://91536292071437",
			Volume = 1.4,
			PlaybackSpeed = 0.52,
			TimePosition = 1,
			ChorusPosition = 16.7,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "momoland-fun-to-the-world",
			Name = "Fun to the World",
			Year = 2018,
			Colour = "FFC4E1",
			Songs = { "BAAM", "BBoom BBoom" },
			Members = { "HYEBIN", "YEONWOO", "JANE", "TAEHA", "NAYUN", "DAISY", "JOOE", "AHIN", "NANCY" },
			Art = {
				["AHIN"] = "rbxassetid://90958220833433",
				["DAISY"] = "rbxassetid://111695119844338",
				["HYEBIN"] = "rbxassetid://98250327829779",
				["JANE"] = "rbxassetid://124618331783030",
				["JOOE"] = "rbxassetid://111017485253738",
				["NANCY"] = "rbxassetid://134564841327886",
				["NAYUN"] = "rbxassetid://127498382052237",
				["TAEHA"] = "rbxassetid://127194278916316",
				["YEONWOO"] = "rbxassetid://78787127663066",
			},
		},
	},
}
