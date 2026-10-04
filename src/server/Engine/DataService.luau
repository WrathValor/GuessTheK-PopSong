--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local PlayerData = require(ReplicatedStorage.Assets.Modules.PlayerData).Server

--| DataService

local DataService = {};

--| Functions

-- [[ Private ]]

local function onPlayerAdded(Player: Player)
    local data, reason = PlayerData.WaitForData(Player)
    if not data then
        warn("Failed to load data for player " .. Player.Name .. ": " .. reason)
        Player:Kick("Failed to load your data. Please try again later.")
        return
    end
end

-- [[ Public ]]

function DataService:Start()
    for _, Player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, Player)
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
end

--| Return
return DataService