--| Stray Kids
-- JYP · 4th gen boy group · active.
-- One entry per song; see Songs/init.luau for what each field means.

return {
    Group = "Stray Kids",
    GroupType = "Boy",
    Generation = "4th",
    Colour = "FFA3A3", -- card art + roll glow (pastel hex)
    Gradient = ColorSequence.new(Color3.fromHex("FF4B3E"), Color3.fromHex("5A0F1E")), -- no official colour: red from their branding
    Status = "Active",
    PackArt = "rbxassetid://86078898835368", -- group art: pack sleeve + binder (assets/Photocards/Groups)
    Songs = {
        {
            Name = "Back Door",
            Year = 2020,
            MusicId = "rbxassetid://127111541973309",
            AnimationId = "rbxassetid://12241982264",
            PlaybackSpeed = 0.7,
            TimePosition = 1,
            ChorusPosition = 39.9,
        },
        {
            Name = "Thunderous",
            Year = 2021,
            MusicId = "rbxassetid://86119743398359",
            Volume = 1.1,
            AnimationId = "rbxassetid://8966029098",
            PlaybackSpeed = 0.7,
            TimePosition = 1,
            ChorusPosition = 41.8,
        },
        {
            Name = "Social Path",
            Year = 2023,
            MusicId = "rbxassetid://133940631608103",
            AnimationId = "rbxassetid://14902106745",
            PlaybackSpeed = 0.55,
            TimePosition = 1,
            ChorusPosition = 32.4,
        },
        {
            Name = "LALALALA",
            Year = 2023,
            MusicId = "rbxassetid://107345208006343",
            Volume = 0.75,
            AnimationId = "rbxassetid://16400592661",
            PlaybackSpeed = 0.55,
            TimePosition = 2,
            ChorusPosition = 74.6,
        },
        {
            Name = "Chk Chk Boom",
            Year = 2024,
            MusicId = "rbxassetid://120525189171033",
            AnimationId = "rbxassetid://119574014307882",
            PlaybackSpeed = 0.73,
            TimePosition = 1,
            ChorusPosition = 40.9,
        },
    },
    -- K-POPPED! photocard albums (see Songs/init.luau). Art ids are placeholders until the art batch.
    Albums = {
        {
            Id = "straykids-this-and-that",
            Name = "This and That",
            Year = 2026,
            Colour = "D6C2A8",
            Songs = {},
            Members = { "BANG CHAN", "LEE KNOW", "CHANGBIN", "HYUNJIN", "HAN", "FELIX", "SEUNGMIN", "I.N" },
            Art = {
                ["BANG CHAN"] = "rbxassetid://107703760156805",
                ["LEE KNOW"] = "rbxassetid://114139527861442",
                ["CHANGBIN"] = "rbxassetid://118051880268950",
                ["HYUNJIN"] = "rbxassetid://133778908178940",
                ["HAN"] = "rbxassetid://127854058458404",
                ["FELIX"] = "rbxassetid://114509146777358",
                ["SEUNGMIN"] = "rbxassetid://132250737376873",
                ["I.N"] = "rbxassetid://96286289055250",
            },
        },
    },
}
