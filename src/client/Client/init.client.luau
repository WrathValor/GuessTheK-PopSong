--| Require

-- Start Scribe before controller initialization so slow startup cannot delay its handshake.
require(game:GetService("ReplicatedStorage").Modules.PlayerData)

for _, Controller in script:GetChildren() do
    if Controller:IsA("ModuleScript") then
        local Handler = require(Controller)
        print(Handler)
        if type(Handler.Start) == "function" then
            Handler.Start(Handler)
        end
    end
end
