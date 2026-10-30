local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Levels = require(ReplicatedStorage.Modules.Levels)
return function(_, player)
	return CmdrUtil.Each({ player }, function(_, data)
		local inv = data.Inventory
		local level = Levels.FromXP(data.Player.XP.Get())
		return table.concat({
			"",
			`coins {data.Currencies.Won.Get()} · XP {data.Player.XP.Get()} (level {level}) · streak {data.Player.Streak.Get()}`,
			`sets {inv.Sets.Count()} · stages {inv.Stages.Count()} · mics {inv.Mics.Count()} · wearing {inv.EquippedStage.Get()} / {inv.EquippedMic.Get()}`,
			`songs {inv.Songs.Count()} · packs {inv.Packs.Count()} · duel pack "{inv.DuelPack.Get()}" · discovered {inv.Index.Count()}`,
			`titles {inv.Titles.Count()} · title "{inv.Title.Get()}" · daily streak {data.Rewards.DailyStreak.Get()}`,
		}, "\n")
	end)
end
