--| Analytics
-- Every analytics event goes through here (Roblox AnalyticsService → Creator Hub ▸ Analytics).
-- The list of events, their breakdown fields and Roblox's limits live in
-- Constants/AnalyticsEvents. This module:
--   • checks names + fields against that list (typos would waste one of the 100 names)
--   • rate-limits to Roblox's 120 + 20 × players requests a minute (drops past that)
--   • never yields or errors into gameplay code (everything is pcall'd)
--   • takes a few client events through AnalyticsRemote, checked and throttled per player
--   • prints each event in Studio when DEBUG is on
--   Analytics.Event(player, name, value?, field1?, field2?, field3?)
--   Analytics.Economy(player, "Source" | "Sink", "Coins" | "XP", amount, balance, transaction, sku)
--   Analytics.Onboarding(player, stepName)
--   Analytics.Funnel(player, "Duel" | "Solo", sessionId, stepName)

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Events = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)

local AnalyticsRemote = Bridgenet.ReferenceBridge("AnalyticsRemote")

local Analytics = {}

Analytics.DEBUG = RunService:IsStudio() -- print every event in the Output while testing

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}
local MAX_FIELD = 50 -- characters per field value
local CLIENT_PER_MINUTE = 40 -- per player

-- [[ Rate limit: a token bucket refilled to Roblox's per-minute budget ]]
local tokens, lastRefill = 120, os.clock()
local function take(): boolean
	local now = os.clock()
	local perMinute = 120 + 20 * #Players:GetPlayers()
	tokens = math.min(perMinute, tokens + (now - lastRefill) * perMinute / 60)
	lastRefill = now
	if tokens < 1 then
		return false
	end
	tokens -= 1
	return true
end

local function fields(...: any): { [string]: string }?
	local out, any = {}, false
	for i, v in { ... } do
		if v ~= nil and i <= 3 then
			out[FIELD_KEYS[i]] = string.sub(tostring(v), 1, MAX_FIELD)
			any = true
		end
	end
	return if any then out else nil
end

local function debugPrint(...)
	if Analytics.DEBUG then
		print("[Analytics]", ...)
	end
end

local function valid(player: Player?): boolean
	return player ~= nil and player.Parent == Players
end

function Analytics.Event(player: Player, name: string, value: number?, f1: any?, f2: any?, f3: any?)
	local def = Events.Custom[name]
	if not def then
		warn("[Analytics] unknown event", name, "(add it to Constants/AnalyticsEvents)")
		return
	end
	if not valid(player) or not take() then
		return
	end
	local custom = fields(f1, f2, f3)
	debugPrint(player.Name, name, value or 1, f1, f2, f3)
	pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, name, value or 1, custom)
end

-- flow "Source" (earned) or "Sink" (spent). amount > 0; balance = what they have after.
function Analytics.Economy(player: Player, flow: string, currency: string, amount: number, balance: number, transaction: string, sku: string?)
	if amount <= 0 or not valid(player) or not take() then
		return
	end
	local flowType = if flow == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
	debugPrint(player.Name, flow, currency, amount, "→", balance, transaction, sku)
	pcall(AnalyticsService.LogEconomyEvent, AnalyticsService, player, flowType, currency, amount, math.max(0, balance), transaction, sku or transaction)
end

-- Onboarding: each step once per player per server (Roblox ignores repeats anyway)
local onboarded: { [Player]: { [number]: boolean } } = {}
function Analytics.Onboarding(player: Player, stepName: string)
	local step = table.find(Events.Onboarding, stepName)
	if not step or not valid(player) then
		return
	end
	onboarded[player] = onboarded[player] or {}
	if onboarded[player][step] or not take() then
		return
	end
	onboarded[player][step] = true
	debugPrint(player.Name, "onboarding", step, stepName)
	pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, step, stepName)
end

-- A step of a recurring funnel. sessionId ties one run together (a duel id, a solo game id).
function Analytics.Funnel(player: Player, funnel: string, sessionId: string, stepName: string)
	local steps = Events.Funnels[funnel]
	local step = steps and table.find(steps, stepName)
	if not step or not valid(player) or not take() then
		return
	end
	debugPrint(player.Name, "funnel", funnel, sessionId, step, stepName)
	pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, player, funnel, sessionId, step, stepName)
end

-- [[ Client events ]]

local songByMusicId = {}
for _, song in Songs.GetAllSongs() do
	if song.MusicId then
		songByMusicId[song.MusicId] = song.Id
	end
end

local clientCount: { [Player]: { number } } = {}
local function clientAllowed(player: Player): boolean
	local now = os.clock()
	local list = clientCount[player] or {}
	clientCount[player] = list
	while list[1] and now - list[1] > 60 do
		table.remove(list, 1)
	end
	if #list >= CLIENT_PER_MINUTE then
		return false
	end
	table.insert(list, now)
	return true
end

local function onClient(player: Player, packet)
	if type(packet) ~= "table" or type(packet.Name) ~= "string" then
		return
	end
	local def = Events.Custom[packet.Name]
	if not def or not def.Client or not clientAllowed(player) then
		return
	end
	local values = {}
	for i, fieldName in def.Fields or {} do
		local v = packet.Fields and packet.Fields[i]
		if type(v) ~= "string" then
			v = nil
		end
		-- songs come as a MusicId; turn it into the song's name (and drop unknown ones)
		if v and fieldName == "Song" then
			v = songByMusicId[v]
		end
		-- group items come by name; only names in the group's catalog count
		if v and fieldName == "Item" then
			local ok, UGCService = pcall(require, script.Parent.UGCService)
			local known = false
			for _, item in if ok then UGCService.Items else {} do
				if item.Name == v then
					known = true
					break
				end
			end
			v = if known then v else nil
		end
		local allowed = def.Allowed and def.Allowed[fieldName]
		if v and allowed and not table.find(allowed, v) then
			v = nil
		end
		values[i] = v
	end
	local value = tonumber(packet.Value)
	if value and (value ~= value or value < 0 or value > 100000) then
		value = nil
	end
	if packet.Name == "ScreenOpened" and values[1] == "Shop" then
		Analytics.Onboarding(player, "OpenedShop")
	end
	if packet.Name == "SoloPickerOpened" then
		Analytics.Funnel(player, "Solo", Analytics.SoloSession(player, true), "PickerOpened")
	end
	Analytics.Event(player, packet.Name, value, values[1], values[2], values[3])
end

-- a solo run's funnel id: a new one each time the picker opens
local soloSessions: { [Player]: string } = {}
function Analytics.SoloSession(player: Player, new: boolean?): string
	if new or not soloSessions[player] then
		soloSessions[player] = `{player.UserId}-{os.time()}-{math.random(1000, 9999)}`
	end
	return soloSessions[player]
end

function Analytics.Start()
	AnalyticsRemote:Connect(onClient)
	Players.PlayerAdded:Connect(function(player)
		Analytics.Onboarding(player, "Joined")
	end)
	for _, player in Players:GetPlayers() do
		Analytics.Onboarding(player, "Joined")
	end
	Players.PlayerRemoving:Connect(function(player)
		onboarded[player] = nil
		clientCount[player] = nil
		soloSessions[player] = nil
	end)
end

return Analytics
