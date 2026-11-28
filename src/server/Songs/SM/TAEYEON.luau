--| TAEYEON
-- SM · 2nd gen soloist (Girls' Generation's leader) · active.
-- One entry per song; see Songs/init.luau for what each field means.
-- No songs yet: her photocards are live as soon as an album has art (the card bot fills the
-- versions from /cards group:TAEYEON album:<era>).

return {
	Group = "TAEYEON",
	GroupType = "Solo",
	Generation = "2nd",
	Colour = "C9E4F7", -- card art + roll glow (pastel hex)
	PackArt = "rbxassetid://95707009967453", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Status = "Active",
	Songs = {},
	Albums = {
		{
			Id = "taeyeon-invu",
			Name = "INVU",
			Year = 2022,
			Colour = "D9C7F2",
			Songs = {}, -- (title track: INVU)
			Members = { "TAEYEON" },
			Art = {
				["TAEYEON"] = "rbxassetid://72013508133942",
				["TAEYEON 2"] = "rbxassetid://87404103877759",
				["TAEYEON 3"] = "rbxassetid://70377836955890",
				["TAEYEON 5"] = "rbxassetid://139620540023409",
			},
			Versions = 5,
		},
	},
}
