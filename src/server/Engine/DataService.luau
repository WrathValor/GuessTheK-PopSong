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
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)

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

    -- old saves are fixed up once, on load, by Scribe (Modules/DataMigrations)

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
    -- the shop), its gold platform (ShopCatalog.VIP_STAGE) and the VIP Gold banner + photocard,
    -- given while the pass is owned
    data.GamePasses.Observe(function()
        local vip = data.GamePasses.Has("VIP")
        Player:SetAttribute("VIP", if vip then true else nil)
        -- 2× Coins pass: the HUD's boost tag says a coin potion makes it 3×
        Player:SetAttribute("DoubleCoins", if data.GamePasses.Has("DoubleCoins") then true else nil)
        if vip then
            task.defer(function()
                if not data.Inventory.Stages.Has(ShopCatalog.VIP_STAGE) then
                    data.Inventory.Stages.Add(ShopCatalog.VIP_STAGE)
                end
                -- and the VIP Gold banner + photocard (SeasonConstants, Tag "VIP")
                if not data.Inventory.Banners.Has("VIPGold") then
                    data.Inventory.Banners.Add("VIPGold")
                end
                if not data.Inventory.Photocards.Has("VIPGold") then
                    data.Inventory.Photocards.Add("VIPGold")
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
    -- fandom titles: a card of every member of a group unlocks its title, and the cards' levels
    -- level it up (Engine/Collection). Checked on join too, and whenever the cards change.
    data.Inventory.Cards.Observe(function()
        task.defer(Collection.Check, data)
    end)
    -- the equipped title + its tier ("Normal" / "Gold" / "Rainbow"), for name tags and the HUD.
    -- A worn group badge (Modules/Library/Ladders, "Badge:C:aespa") shows as "MY" (fandom name; the chip's look says the rung) with
    -- TitleTier "Rung:Gold" and TitleIcon "Cards" / "Songs" (Modules/UI/TitleChip paints it)
    local function showTitle()
        local title = data.Inventory.Title.Get()
        local ladder, artist = Ladders.FromTitle(title)
        if ladder and artist and not Ladders.Eligible(artist) then
            title = "" -- (a group that lost its ladders: show the default)
        elseif ladder and artist then
            local key = if ladder == "Legend" then Ladders.LegendKey(artist) else Ladders.Key(ladder, artist)
            local rung = (data.Inventory.Ladders.Get() or {})[key] or 0
            local name = Ladders.RungName(ladder, rung)
            if name then
                Player:SetAttribute("TitleIcon", if ladder == "Legend" then "" else ladder) -- (first: the chips repaint on Title / TitleTier)
                Player:SetAttribute("Title", Ladders.Label(ladder, artist, rung))
                Player:SetAttribute("TitleTier", `Rung:{name}`)
                return
            end
            title = "" -- (not earned: show the default)
        end
        local tiers = data.Inventory.TitleTiers.Get() or {}
        Player:SetAttribute("TitleIcon", nil)
        Player:SetAttribute("Title", if title ~= "" then title else HUDConstants.DEFAULT_TITLE)
        Player:SetAttribute("TitleTier", Cards.LEVELS[tiers[title] or 1] or "Normal")
    end
    data.Inventory.Title.Observe(showTitle)
    data.Inventory.TitleTiers.Observe(showTitle)
    data.Inventory.Ladders.Observe(showTitle) -- (a worn badge's rung goes up)
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