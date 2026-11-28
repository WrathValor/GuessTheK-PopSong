--| izna
-- Other (WAKEONE) · 5th gen girl group (from I-LAND 2) · active.
-- One entry per song; see Songs/init.luau for what each field means.
-- No songs yet: the cards go live as soon as an album has art (the card bot fills it in from
-- /cards group:izna album:<era>).

return {
	Group = "izna",
	GroupType = "Girl",
	Generation = "5th",
	Colour = "C8D4FF", -- card art + roll glow (pastel hex)
	PackArt = "rbxassetid://107379477046035", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Status = "Active",
	Songs = {},
	Albums = {
		{
			Id = "izna-n-a",
			Name = "N/a",
			Year = 2024,
			Colour = "C8D4FF",
			Songs = {}, -- (title track: IZNA)
			Members = { "MAI", "JEEMIN", "JIYOON", "KOKO", "SARANG", "JUNGEUN", "SAEBI" },
			Art = {
				["JEEMIN"] = "rbxassetid://126963591679629",
				["JIYOON"] = "rbxassetid://98341347722923",
				["JUNGEUN"] = "rbxassetid://135068253227891",
				["KOKO"] = "rbxassetid://110010373816021",
				["SAEBI"] = "rbxassetid://108394752471908",
				["MAI"] = "rbxassetid://108430095449651",
				["SARANG"] = "rbxassetid://125072866039224",
			},
		},
	},
}
