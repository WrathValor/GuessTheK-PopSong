--| KiiiKiii
-- Starship · 5th gen girl group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "KiiiKiii",
	GroupType = "Girl",
	Generation = "5th",
	Colour = "A7E9B8", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("FFE45C"), Color3.fromHex("FF9ED2")), -- no official colour: lemon to candy pink
	Status = "Active",
	PackArt = "rbxassetid://123671668525488", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "DANCING ALONE",
			Year = 2025,
			MusicId = "rbxassetid://130965356697835",
			PlaybackSpeed = 0.86,
			TimePosition = 0.5,
			ChorusPosition = 39.5,
		},
		{
			Name = "Pop Off Pop Off",
			Draft = true, -- audio didn't load in game (2026-11-02): re-upload / check permissions
			Year = 2026,
			MusicId = "rbxassetid://70438565719431",
			PlaybackSpeed = 0.96,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "404 (New Era)",
			Year = 2026,
			MusicId = "rbxassetid://124902238595193",
			PlaybackSpeed = 0.88,
			TimePosition = 1,
			ChorusPosition = 54,
		},
		{
			Name = "Candy Pink Magic Hole Flip Phone",
			Draft = true, -- audio didn't load in game (2026-11-02): re-upload / check permissions
			Year = 2026,
			MusicId = "rbxassetid://124525322471609",
			PlaybackSpeed = 0.58,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "SWEET SOUR",
			Draft = true, -- audio didn't load in game (2026-11-02): re-upload / check permissions
			Year = 2026,
			MusicId = "rbxassetid://94118668481660",
			PlaybackSpeed = 0.94,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Hey Hi",
			Draft = true, -- audio didn't load in game (2026-11-02): re-upload / check permissions
			Year = 2026,
			MusicId = "rbxassetid://98000133465978",
			PlaybackSpeed = 0.74,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "I DO ME",
			Year = 2025,
			MusicId = "rbxassetid://132181318189291",
			PlaybackSpeed = 0.85,
			TimePosition = 3,
			ChorusPosition = 36.5,
		},
		{
			Name = "Delulu",
			Year = 2026,
			MusicId = "rbxassetid://76516477302437",
			Volume = 0.7,
			PlaybackSpeed = 0.92,
			TimePosition = 3,
			ChorusPosition = 40,
		},
		{
			Name = "UNDERDOGS",
			Draft = true, -- lesser-known song, held back for balance
			Year = 2026,
			MusicId = "rbxassetid://115744576429546",
			PlaybackSpeed = 0.78,
			TimePosition = 0,
			ChorusPosition = 0,
		},
		{
			Name = "Blue Hour",
			Year = 2026,
			MusicId = "rbxassetid://70916363704916",
			PlaybackSpeed = 0.66,
			TimePosition = 0.5,
			ChorusPosition = 19.1,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "kiiikiii-delulu-pack",
			Name = "Delulu Pack",
			Year = 2026,
			Colour = "FFE0F0",
			Songs = { "Delulu" },
			Members = { "JIYU", "LEESOL", "SUI", "HAUM", "KYA" },
			Art = {
				["JIYU"] = "rbxassetid://133704954739197",
				["LEESOL"] = "rbxassetid://110192295504696",
				["SUI"] = "rbxassetid://99111303270396",
				["HAUM"] = "rbxassetid://100668896082057",
				["KYA"] = "rbxassetid://86389215485684",
			},
		},
	},
}
