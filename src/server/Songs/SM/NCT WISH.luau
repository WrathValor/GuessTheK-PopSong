--| NCT WISH
-- SM · 5th gen boy group (NCT's Korea–Japan unit) · active.
-- One entry per song; see Songs/init.luau for what each field means.
-- No songs yet: the cards go live as soon as an album has art (the card bot fills it in from
-- /cards group:NCT WISH album:<era>).

return {
	Group = "NCT WISH",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "C9F2D6", -- card art + roll glow (pastel hex)
	PackArt = "rbxassetid://70794969390188", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Status = "Active",
	Songs = {},
	Albums = {
		{
			Id = "nctwish-steady",
			Name = "Steady",
			Year = 2024,
			Colour = "C9F2D6",
			Songs = {}, -- (title track: Steady)
			Members = { "SION", "RIKU", "YUSHI", "JAEHEE", "RYO", "SAKUYA" },
			Art = {
				["JAEHEE"] = "rbxassetid://98950629146115",
				["RIKU"] = "rbxassetid://134289514369660",
				["RYO"] = "rbxassetid://89593464463154",
				["SAKUYA"] = "rbxassetid://116191679083908",
				["SION"] = "rbxassetid://122945557600639",
				["YUSHI"] = "rbxassetid://104413815143502",
			},
		},
	},
}
