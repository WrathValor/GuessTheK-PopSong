--| AnalyticsClient
-- The client's side of analytics: sends the few events the client is allowed to log
-- (Client = true in Constants/AnalyticsEvents) to Engine/Analytics, which checks them.
--   AnalyticsClient.Event(name, value?, field1?, field2?, field3?)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Events = require(ReplicatedStorage.Constants.AnalyticsEvents)

local AnalyticsRemote = Bridgenet.ReferenceBridge("AnalyticsRemote")

local AnalyticsClient = {}

function AnalyticsClient.Event(name: string, value: number?, f1: string?, f2: string?, f3: string?)
	local def = Events.Custom[name]
	if not (def and def.Client) then
		warn("[AnalyticsClient] not a client event:", name)
		return
	end
	AnalyticsRemote:Fire({ Name = name, Value = value, Fields = { f1, f2, f3 } })
end

return AnalyticsClient
