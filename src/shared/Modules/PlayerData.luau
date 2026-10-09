--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports

local Scribe = require(ReplicatedStorage.Packages.scribe)

--| Template

return Scribe({
    Template = {
        Player = {
			XP = Scribe.Int(0, { Min = 0 }),
            Streak = Scribe.Int(0, { Min = 0 }),
		},

        Currencies = {
            Won = Scribe.Int(0, { Min = 0 }),
        };

        Inventory = {
            Title = Scribe.String(""),

        };

        GamePasses = Scribe.SetOf(Scribe.String("", { MaxLength = 32 }));

        Statistics = {
            PlayTime = Scribe.Int(0, { Min = 0 });
            HighestStreak = Scribe.Int(0, { Min = 0 });
        }
    };
    ProfileStoreIndex = "PlayerData", -- required: your DataStore name
	ProfileKeyPrefix = "PLAYER_",
    Mode = "Mock",
})