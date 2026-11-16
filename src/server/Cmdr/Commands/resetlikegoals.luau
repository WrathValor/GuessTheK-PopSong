--| resetlikegoals
-- Forgets which like goal rewards a player has had (Rewards.Claimed "LikeGoal:…"), so the
-- goals already hit pay them again on their next join (or the next setlikes).

return {
	Name = "resetlikegoals",
	Aliases = {},
	Description = "Pays the like goal rewards again (forgets they were had).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
