--| Require

-- Disable the Roblox menu's Reset Character action while keeping normal death respawns.
local StarterGui = game:GetService("StarterGui")
task.spawn(function()
	while true do
		local ok = pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false)
		if ok then
			break
		end
		task.wait(1)
	end
end)

-- Start Scribe before controller initialization so slow startup cannot delay its handshake.
require(game:GetService("ReplicatedStorage").Modules.PlayerData)

for _, Controller in script:GetChildren() do
    if Controller:IsA("ModuleScript") then
        local Handler = require(Controller)
        if type(Handler.Start) == "function" then
            Handler.Start(Handler)
        end
    end
end
