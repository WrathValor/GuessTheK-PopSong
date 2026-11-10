--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Levels = require(ReplicatedStorage.Modules.Levels)
local Collection = require(script.Parent.Collection)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)

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

    -- the pre-season's banners, photocards and title were called S1 before they became S0:
    -- move anything saved under the old names
    PlayerData.Batch(Player, function()
        for _, kind in { "Comeback", "Glow", "Star", "Icon", "Legend" } do
            local old, new = "S1" .. kind, "S0" .. kind
            for _, list in { data.Inventory.Banners, data.Inventory.Photocards } do
                if list.Has(old) then
                    list.Remove(old)
                    if not list.Has(new) then
                        list.Add(new)
                    end
                end
            end
            for _, worn in { data.Inventory.Banner, data.Inventory.Photocard } do
                if worn.Get() == old then
                    worn.Set(new)
                end
            end
        end
        if data.Inventory.Titles.Has("S1 Comeback") then
            data.Inventory.Titles.Remove("S1 Comeback")
            if not data.Inventory.Titles.Has("S0 Comeback") then
                data.Inventory.Titles.Add("S0 Comeback")
            end
            local tier = data.Inventory.TitleTiers["S1 Comeback"].Get() or 0
            if tier > (data.Inventory.TitleTiers["S0 Comeback"].Get() or 0) then
                data.Inventory.TitleTiers["S0 Comeback"].Set(tier)
            end
            if data.Inventory.Title.Get() == "S1 Comeback" then
                data.Inventory.Title.Set("S0 Comeback")
            end
        end
    end)

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
    -- VIP Pass (ShopCatalog.Passes): the "VIP" attribute (the gold name tag, early restocks in
    -- the shop) and its gold platform (ShopCatalog.VIP_STAGE), given while the pass is owned
    data.GamePasses.Observe(function()
        local vip = data.GamePasses.Has("VIP")
        Player:SetAttribute("VIP", if vip then true else nil)
        if vip then
            task.defer(function()
                if not data.Inventory.Stages.Has(ShopCatalog.VIP_STAGE) then
                    data.Inventory.Stages.Add(ShopCatalog.VIP_STAGE)
                end
            end)
        end
    end)
    -- level titles: unlock every title the player's level has reached (also catches anyone
    -- who levelled up before titles existed)
    data.Player.XP.Observe(function(xp: number)
        local level = Levels.FromXP(xp)
        Player:SetAttribute("Level", level) -- (the walk-on chips show it)
        for _, title in Levels.TitlesUpTo(level) do
            if title ~= HUDConstants.DEFAULT_TITLE and not data.Inventory.Titles.Has(title) then
                data.Inventory.Titles.Add(title)
            end
            -- animated level titles (Levels.TITLE_TIERS: Legend is Rainbow)
            local rank = Cards.RANK[Levels.TITLE_TIERS[title] or ""]
            if rank and (data.Inventory.TitleTiers[title].Get() or 0) < rank then
                data.Inventory.TitleTiers[title].Set(rank)
            end
        end
    end)
    -- song sets: own every song of a group / company and its title unlocks (Engine/Collection).
    -- Checked on join too, so songs given any other way (or sets that shrank) still count.
    data.Inventory.Songs.Observe(function()
        task.defer(Collection.Check, data)
    end)
    data.Inventory.Copies.Observe(function()
        task.defer(Collection.Check, data) -- copies level sets up (Gold / Rainbow titles)
    end)
    -- the equipped title + its tier ("Normal" / "Gold" / "Rainbow"), for name tags and the HUD
    local function showTitle()
        local title = data.Inventory.Title.Get()
        local tiers = data.Inventory.TitleTiers.Get() or {}
        Player:SetAttribute("Title", if title ~= "" then title else HUDConstants.DEFAULT_TITLE)
        Player:SetAttribute("TitleTier", Cards.LEVELS[tiers[title] or 1] or "Normal")
    end
    data.Inventory.Title.Observe(showTitle)
    data.Inventory.TitleTiers.Observe(showTitle)
    -- profile style: the banner + photocard worn (everyone's inspect card / PreDuel reads
    -- them) and the owned lists as comma lists (the STYLE picker reads those)
    data.Inventory.Banner.Observe(function(id: string)
        Player:SetAttribute("Banner", if id ~= "" then id else SeasonConstants.DEFAULT_BANNER)
    end)
    data.Inventory.Photocard.Observe(function(id: string)
        Player:SetAttribute("Photocard", if id ~= "" then id else SeasonConstants.DEFAULT_PHOTOCARD)
    end)
    data.Inventory.Banners.Observe(function()
        Player:SetAttribute("Banners", table.concat(data.Inventory.Banners.Get() or {}, ","))
    end)
    data.Inventory.Photocards.Observe(function()
        Player:SetAttribute("Photocards", table.concat(data.Inventory.Photocards.Get() or {}, ","))
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