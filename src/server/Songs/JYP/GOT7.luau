--| GOT7
-- JYP · 3rd gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
	Group = "GOT7",
	GroupType = "Boy",
	Generation = "3rd",
	Colour = "B8E6A3", -- GOT7's green fandom colour
	Gradient = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("00A86B")), -- official colours: green + white; shades approximated
	Status = "Active",
	Songs = {
		{
			Name = "A",
			Year = 2014,
			MusicId = "rbxassetid://133027140385567",
			Volume = 0.8,
			PlaybackSpeed = 0.5,
			TimePosition = 0.3,
			ChorusPosition = 28,
		},
		{
			Name = "Never Ever",
			Year = 2017,
			MusicId = "rbxassetid://112122793656037",
			Volume = 2.4,
			PlaybackSpeed = 0.8,
			TimePosition = 0.5,
			ChorusPosition = 55,
		},
		{
			Name = "If You Do",
			Year = 2015,
			MusicId = "rbxassetid://116459431746841",
			Volume = 0.75,
			PlaybackSpeed = 0.5,
			TimePosition = 0.2,
			ChorusPosition = 32,
		},
		{
			Name = "You Calling My Name",
			Year = 2019,
			MusicId = "rbxassetid://136992632950745",
			Volume = 1.5,
			PlaybackSpeed = 0.55,
			TimePosition = 0.5,
			ChorusPosition = 63.5,
		},
		{
			Name = "Stop stop it",
			Year = 2014,
			MusicId = "rbxassetid://123637513524628",
			PlaybackSpeed = 0.52,
			TimePosition = 0.3,
			ChorusPosition = 33,
		},
	},
}
