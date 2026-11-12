local ServerScriptService = game:GetService("ServerScriptService")
local GhostRecorder = require(ServerScriptService.Engine.GhostRecorder)
return function(_, userId)
	return `{userId}: {GhostRecorder.Purge(userId)} ghost recording(s) removed`
end
