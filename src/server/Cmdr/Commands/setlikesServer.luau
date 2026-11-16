local ServerScriptService = game:GetService("ServerScriptService")
local LikeGoalService = require(ServerScriptService.Engine.LikeGoalService)
return function(_, likes)
	LikeGoalService.Set(likes)
	return `likes {likes}`
end
