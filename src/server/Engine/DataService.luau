--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Levels = require(ReplicatedStorage.Modules.Levels)

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

    -- sets bought before stages + mics were split: make sure each owned set's pieces are owned
    for _, set in ShopCatalog.Sets do
        if data.Inventory.Sets.Has(set.Id) then
            local stage, mic = ShopCatalog.SetPieces(set)
            if not data.Inventory.Stages.Has(stage.Id) then
                data.Inventory.Stages.Add(stage.Id)
            end
            if not data.Inventory.Mics.Has(mic.Id) then
                data.Inventory.Mics.Add(mic.Id)
            end
        end
    end

    -- public bits other players' clients need (name tags, stage looks): mirrored as attributes
    data.Inventory.EquippedStage.Observe(function(id: string)
        Player:SetAttribute("EquippedStage", id)
    end)
    data.Inventory.EquippedMic.Observe(function(id: string)
        Player:SetAttribute("EquippedMic", id)
    end)
    data.Player.Streak.Observe(function(streak: number)
        Player:SetAttribute("Streak", streak)
    end)
    -- level titles: unlock every title the player's level has reached (also catches anyone
    -- who levelled up before titles existed)
    data.Player.XP.Observe(function(xp: number)
        local level = Levels.FromXP(xp)
        for _, title in Levels.TitlesUpTo(level) do
            if title ~= HUDConstants.DEFAULT_TITLE and not data.Inventory.Titles.Has(title) then
                data.Inventory.Titles.Add(title)
            end
        end
    end)
    data.Inventory.Title.Observe(function(title: string)
        Player:SetAttribute("Title", if title ~= "" then title else HUDConstants.DEFAULT_TITLE)
    end)
end

-- [[ Public ]]

local PLAYTIME_TICK = 60 -- seconds between PlayTime saves

function DataService:Start()
    for _, Player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, Player)
    end
    Players.PlayerAdded:Connect(onPlayerAdded)

    -- Statistics.PlayTime: add a minute for everyone online, once a minute
    task.spawn(function()
        while true do
            task.wait(PLAYTIME_TICK)
            for _, player in Players:GetPlayers() do
                local data = PlayerData.Get(player)
                if data then
                    data.Statistics.PlayTime.Increment(PLAYTIME_TICK)
                end
            end
        end
    end)
end

--| Return
return DataService