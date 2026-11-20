local ServerScriptService = game:GetService("ServerScriptService")
local ShutdownService = require(ServerScriptService.Engine.ShutdownService)
return function(_context, seconds, kind, title, message)
	ShutdownService.Simulate(seconds, if kind == "Maintenance" then "Maintenance" else "Update", title, message)
	return if seconds <= 0 then "restart notice cleared" else `restart notice: {seconds} s`
end
