--| WINNER
-- YG · 3rd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means. (No songs yet: photocards only.)

return {
	Group = "WINNER",
	GroupType = "Boy",
	Generation = "3rd",
	Colour = "BFD0F2", -- card art + roll glow (pastel hex)
	Gradient = ColorSequence.new(Color3.fromHex("2E4FA8"), Color3.fromHex("1C2C6B")), -- official: Nebula Blue
	Status = "Active",
	PackArt = "rbxassetid://84100302396082", -- group art: pack sleeve + binder (assets/Photocards/Groups)
	Songs = {},
	-- K-POPPED! photocard albums (see Songs/init.luau)
	Albums = {
		{
			Id = "winner-fate-number-for",
			Name = "FATE NUMBER FOR",
			Year = 2019,
			Colour = "9ED8F5",
			Songs = {},
			Members = { "YOON", "JINU", "HOONY", "MINO" },
			Art = {
				["YOON"] = "rbxassetid://124569580194164",
				["JINU"] = "rbxassetid://72096607820196",
				["HOONY"] = "rbxassetid://113119554606097",
				["MINO"] = "rbxassetid://135825200893141",
			},
		},
	},
}
