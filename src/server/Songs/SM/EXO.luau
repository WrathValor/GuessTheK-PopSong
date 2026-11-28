--| EXO
-- SM · 3rd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "EXO",
	GroupType = "Boy",
	Generation = "3rd",
	Colour = "CFD5E6", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFF8E7"), Color3.fromHex("E8D6AE")), -- official: Cosmic Latte
	Status = "Active",
	PackArt = "rbxassetid://111442422043957", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Monster",
			Year = 2016,
			MusicId = "rbxassetid://101024672072100",
			Volume = 0.8,
			PlaybackSpeed = 0.72,
			TimePosition = 0.5,
			ChorusPosition = 78.8,
		},
		{
			Name = "CALL ME BABY",
			Draft = true, -- audio didn't load in game (2026-11-01): re-upload / check permissions
			Year = 2015,
			MusicId = "rbxassetid://94231277616372",
			PlaybackSpeed = 0.80,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Tempo",
			Year = 2018,
			MusicId = "rbxassetid://70420913648757",
			Volume = 1.1,
			PlaybackSpeed = 0.97,
			TimePosition = 3,
			ChorusPosition = 72.8,
		},
		{
			Name = "Love Shot",
			Year = 2018,
			MusicId = "rbxassetid://94217715729788",
			Volume = 1.45,
			PlaybackSpeed = 0.82,
			TimePosition = 1,
			ChorusPosition = 36.9,
		},
		{
			Name = "Growl",
			Year = 2013,
			MusicId = "rbxassetid://97300645109098",
			Volume = 1.1,
			PlaybackSpeed = 0.71,
			TimePosition = 0,
			ChorusPosition = 33.4,
		},
		{
			Name = "The Eve",
			Year = 2017,
			MusicId = "rbxassetid://81366308556357",
			Volume = 1.3,
			TimePosition = 1,
			ChorusPosition = 45,
		},
		{
			Name = "Obsession",
			Year = 2019,
			MusicId = "rbxassetid://106632897050546",
			PlaybackSpeed = 0.55,
			TimePosition = 2,
			ChorusPosition = 101.5,
		},
		{
			Name = "Ko Ko Bop",
			Year = 2017,
			MusicId = "rbxassetid://102962035264134",
			Volume = 1.75,
			PlaybackSpeed = 0.67,
			TimePosition = 1,
			ChorusPosition = 106.1,
		},
		{
			Name = "Lotto",
			Year = 2016,
			MusicId = "rbxassetid://135222801004238",
			PlaybackSpeed = 0.98,
			TimePosition = 1,
			ChorusPosition = 46.2,
		},
		{
			Name = "Power",
			Year = 2017,
			MusicId = "rbxassetid://129111839213517",
			Volume = 0.8,
			PlaybackSpeed = 0.72,
			TimePosition = 0.5,
			ChorusPosition = 37.8,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Members are the era's line-up.
	-- Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "exo-exact",
			Name = "EX'ACT",
			Year = 2016,
			Colour = "BFE7D9",
			Cover = "rbxassetid://138913652123717",
			Songs = { "Monster" },
			Members = { "XIUMIN", "SUHO", "LAY", "BAEKHYUN", "CHEN", "CHANYEOL", "D.O.", "KAI", "SEHUN" },
			Art = {
				["XIUMIN"] = "rbxassetid://86678363408399",
				["SUHO"] = "rbxassetid://98059047262875",
				["LAY"] = "rbxassetid://100485150673711",
				["BAEKHYUN"] = "rbxassetid://110465946828201",
				["CHEN"] = "rbxassetid://77582509649093",
				["CHANYEOL"] = "rbxassetid://139501859869043",
				["D.O."] = "rbxassetid://135423570369678",
				["KAI"] = "rbxassetid://126083865464120",
				["SEHUN"] = "rbxassetid://140192872637740",
			},
		},
		{
			Id = "exo-obsession",
			Name = "Obsession",
			Year = 2019,
			Colour = "CFD5E6",
			Cover = "rbxassetid://92499028013907",
			Songs = {},
			Members = { "BAEKHYUN", "CHANYEOL", "CHEN", "KAI", "SEHUN", "SUHO" },
			Art = {
				["BAEKHYUN"] = "rbxassetid://86172412327755",
				["CHANYEOL"] = "rbxassetid://74187285247939",
				["CHEN"] = "rbxassetid://101095065189114",
				["KAI"] = "rbxassetid://139880018047592",
				["SEHUN"] = "rbxassetid://113392097055520",
				["SUHO"] = "rbxassetid://135773362420847",
			},
		},
	},
}
