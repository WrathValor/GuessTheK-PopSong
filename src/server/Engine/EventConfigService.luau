--| EventConfigService
-- Which Roblox event the HUD event button points at (Constants/EventConstants). Reads the
-- experience config EventConstants.CONFIG_KEY (Creator Hub > Configs, a string: the event ID)
-- and puts it on ReplicatedStorage (attribute EventConstants.ATTRIBUTE) for the clients. A
-- published change reaches running servers within a few minutes, no restart.
-- ConfigService is server only. If Configs can't load, or has no key, DEFAULT_EVENT_ID is used;
-- an empty string hides the button. Staged (unpublished) values show in Studio playtests.
--   EventConfigService.Start()

local ConfigService = game:GetService("ConfigService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConstants = require(ReplicatedStorage.Constants.EventConstants)

local EventConfigService = {}

local function set(id: string)
	id = string.gsub(id, "%s", "")
	if ReplicatedStorage:GetAttribute(EventConstants.ATTRIBUTE) ~= id then
		ReplicatedStorage:SetAttribute(EventConstants.ATTRIBUTE, id)
	end
end

function EventConfigService.Start()
	set(EventConstants.DEFAULT_EVENT_ID)
	task.spawn(function()
		local ok, snapshot = pcall(ConfigService.GetConfigAsync, ConfigService)
		if not ok then
			warn("EventConfigService: Configs didn't load, using the default event:", snapshot)
			return
		end
		local function apply()
			local value = snapshot:GetValue(EventConstants.CONFIG_KEY)
			if type(value) == "string" then
				set(value)
			elseif type(value) == "number" then
				set(string.format("%d", value))
			end
		end
		apply()
		snapshot.UpdateAvailable:Connect(function()
			snapshot:Refresh()
			apply()
		end)
	end)
end

return EventConfigService
