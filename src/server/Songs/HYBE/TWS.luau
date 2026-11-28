--| TWS
-- HYBE (PLEDIS) · 5th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.
-- No songs yet: the cards go live as soon as an album has art (the card bot fills it in from
-- /cards group:TWS album:<era>).

return {
	Group = "TWS",
	GroupType = "Boy",
	Generation = "5th",
	Colour = "BFE3FF", -- card art + roll glow (pastel hex)
	PackArt = "rbxassetid://128415608900734", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Status = "Active",
	Songs = {},
	Albums = {
		{
			Id = "tws-sparkling-blue",
			Name = "Sparkling Blue",
			Year = 2024,
			Colour = "BFE3FF",
			Songs = {}, -- (title track: plot twist)
			Members = { "SHINYU", "DOHOON", "YOUNGJAE", "HANJIN", "JIHOON", "KYUNGMIN" },
			Art = {
				["DOHOON"] = "rbxassetid://72122025835300",
				["HANJIN"] = "rbxassetid://137515797177362",
				["JIHOON"] = "rbxassetid://131732494721596",
				["KYUNGMIN"] = "rbxassetid://84784304072368",
				["SHINYU"] = "rbxassetid://102756409839766",
				["YOUNGJAE"] = "rbxassetid://118695081880665",
			},
		},
	},
}
