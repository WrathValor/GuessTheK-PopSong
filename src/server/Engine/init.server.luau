--| Require

for _, Service in script:GetChildren() do
    if Service:IsA("ModuleScript") then
        local Handler = require(Service)
        if type(Handler.Start) == "function" then
            Handler.Start()
        end
    end
end
