--| G-DRAGON
-- Other (Galaxy Corporation; YG until 2023) · 2nd gen soloist (BIGBANG's leader) · active.
-- One entry per song; see Songs/init.luau for what each field means.
-- No songs yet: his photocards are live as soon as an album has art (the card bot adds albums,
-- with Versions = 5, from /cards group:G-DRAGON album:<era>).

return {
	Group = "G-DRAGON",
	GroupType = "Solo",
	Generation = "2nd",
	Colour = "E6E1F2", -- card art + roll glow (pastel hex)
	PackArt = "rbxassetid://113053408629942", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Status = "Active",
	Songs = {},
	Albums = {
		{
			Id = "gdragon-ubermensch",
			Name = "Übermensch",
			Year = 2025,
			Colour = "E6E1F2",
			Songs = {},
			Members = { "G-DRAGON" },
			Art = {
				["G-DRAGON"] = "rbxassetid://115274107144628",
				["G-DRAGON 3"] = "rbxassetid://107747464209384",
				["G-DRAGON 4"] = "rbxassetid://118455544029997",
				["G-DRAGON 5"] = "rbxassetid://134346644331682",
				["G-DRAGON 2"] = "rbxassetid://128700323366711",
			},
			Versions = 5,
		},
	},
}
