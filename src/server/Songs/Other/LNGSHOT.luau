--| LNGSHOT
-- Other · 5th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "LNGSHOT",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "A7B6D9", -- card art + roll glow
	Gradient = ColorSequence.new(Color3.fromHex("D4DDF2"), Color3.fromHex("879BCB")),
	Status = "Active",
	PackArt = "rbxassetid://130506765299803", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {
		{
			Name = "Moonwalkin'",
			Year = 2026,
			MusicId = "rbxassetid://130807626041031",
			Volume = 1.15,
			PlaybackSpeed = 0.6,
			TimePosition = 0.5,
			ChorusPosition = 46.7,
		},
		{
			Name = "Never Let Go",
			Year = 2026,
			MusicId = "rbxassetid://114331407256544",
			PlaybackSpeed = 0.5,
			TimePosition = 0.5,
			ChorusPosition = 40,
		},
		{
			Name = "FaceTime",
			Year = 2026,
			MusicId = "rbxassetid://70544013229480",
			Volume = 0.75,
			PlaybackSpeed = 0.77,
			TimePosition = 0.5,
			ChorusPosition = 38.3,
		},
		{
			Name = "Saucin'",
			Year = 2025,
			MusicId = "rbxassetid://100461750143433",
			PlaybackSpeed = 0.7,
			TimePosition = 0.5,
			ChorusPosition = 15,
		},
		{
			Name = "Backseat",
			Year = 2026,
			MusicId = "rbxassetid://108657424760288",
			Volume = 2.3,
			PlaybackSpeed = 0.74,
			TimePosition = 0.5,
			ChorusPosition = 40,
		},
		{
			Name = "Vanilla Days",
			Year = 2026,
			MusicId = "rbxassetid://127020165619854",
			Volume = 0.8,
			PlaybackSpeed = 0.69,
			TimePosition = 0.2,
			ChorusPosition = 33.9,
		},
		{
			Name = "Fire With Fire",
			Year = 2026,
			MusicId = "rbxassetid://77428149611809",
			Volume = 0.8,
			PlaybackSpeed = 0.6,
			TimePosition = 7,
			ChorusPosition = 41.2,
		},
	},
	-- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
	Albums = {
		{
			Id = "lngshot-shot-callers",
			Name = "SHOT CALLERS",
			Year = 2026,
			Colour = "C2C9D9",
			Songs = { "Moonwalkin'", "FaceTime", "Never Let Go", "Saucin'" },
			Members = { "OHYUL", "RYUL", "WOOJIN", "LOUIS" },
			Art = {
				["WOOJIN"] = "rbxassetid://105446936136324",
				["LOUIS"] = "rbxassetid://71072561468265",
				["OHYUL"] = "rbxassetid://136517701519161",
				["RYUL"] = "rbxassetid://96192563814023",
			},
		},
	},
}
