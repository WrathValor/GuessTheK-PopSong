local ServerScriptService = game:GetService("ServerScriptService")
local StreakReminders = require(ServerScriptService.Engine.StreakReminders)
return function(context, kind)
	local ok, why = StreakReminders.Send(context.Executor, if kind == "BigDay" or kind == "DayTwo" then kind else "Streak")
	return if ok then "sent: check your Roblox notifications" else `not sent: {why}`
end
