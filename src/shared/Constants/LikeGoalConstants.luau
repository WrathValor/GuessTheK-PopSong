--| LikeGoalConstants
-- The like goal on the back of the Join the Group sign (design board "Fans 4"). The game's like
-- count comes from our Cloudflare Worker (tools/likes-worker), which asks Roblox for it: game
-- servers can't call roblox.com themselves. Engine/LikeGoalService reads it every REFRESH
-- seconds and puts it on ReplicatedStorage (attribute "Likes"); Client/Leaderboards draws the sign.
-- GOALS go up in order. The sign counts toward the first one not hit yet. When one is hit, every
-- player gets its Reward straight into their account (a "LIKE GOAL HIT!" reveal), on every
-- server, and anyone who joins later gets every goal hit so far on their first visit after it.
-- A goal once hit stays hit even if likes drop (LikeGoalService keeps it in a DataStore). The
-- reward is for everyone who plays, not only people who liked: Roblox doesn't allow paying a
-- player for their own like.
--   URL = "" turns the count off (the sign then shows Likes from the setlikes command, Studio).

local LikeGoalConstants = {}

LikeGoalConstants.URL = "https://kpop-likes.mujtabah987.workers.dev/" -- the Worker (tools/likes-worker)
LikeGoalConstants.REFRESH = 120 -- seconds between reads
LikeGoalConstants.ATTRIBUTE = "Likes" -- on ReplicatedStorage; -1 until the first read
LikeGoalConstants.REACHED = "LikeGoalsReached" -- on ReplicatedStorage: how many GOALS are hit
LikeGoalConstants.STORE = "LikeGoal_v1" -- DataStore, key "Reached": the most GOALS ever hit

-- Likes = the goal; Id = its claim key (Rewards.Claimed "LikeGoal:<Id>": never change one once
-- live); Text = on the sign; Icon = the sign's reward picture (optional: else the first
-- currency's icon). Reward = any mix of (the same keys as a shop code, plus Set):
--   Coins / Tickets / Upgrades = how many
--   Set = a ShopCatalog set id (its stage + mic come with it)
--   Stage / Mic = a ShopCatalog stage / mic id
--   Banner / Photocard = a SeasonConstants banner / photocard id
--   Title = a title, TitleTier = 1 Normal / 2 Gold / 3 Rainbow (default 1)
-- e.g. Reward = table.freeze({ Coins = 500, Set = "Neon", Title = "Day One Fan", TitleTier = 2 })
LikeGoalConstants.GOALS = table.freeze({
	table.freeze({ Likes = 25, Id = "LIKES25", Reward = table.freeze({ Coins = 250 }), Text = "250 coins" }),
	table.freeze({ Likes = 50, Id = "LIKES50", Reward = table.freeze({ Tickets = 1, Coins = 150 }), Text = "1 roll ticket + 150 coins" }),
	table.freeze({ Likes = 100, Id = "LIKES100", Reward = table.freeze({ Tickets = 5, Upgrades = 2 }), Text = "5 roll tickets + 2 upgrades" }),
	table.freeze({ Likes = 250, Id = "LIKES250", Reward = table.freeze({ Upgrades = 3, Coins = 500 }), Text = "3 upgrades + 500 coins" }),
	table.freeze({ Likes = 500, Id = "LIKES500", Reward = table.freeze({ Tickets = 5, Upgrades = 2, Coins = 500 }), Text = "5 roll tickets + 2 upgrades + 500 coins" }),
})

-- how many GOALS this many likes hits
function LikeGoalConstants.Hits(likes: number): number
	local n = 0
	for i, g in LikeGoalConstants.GOALS do
		if likes >= g.Likes then
			n = i
		end
	end
	return n
end

-- the goal the sign counts toward (nil once every goal is hit) and the last one hit (or nil),
-- given how many are hit (reached: hits can stay hit after likes drop)
function LikeGoalConstants.State(reached: number)
	local goals = LikeGoalConstants.GOALS
	return goals[reached + 1], goals[reached]
end

return LikeGoalConstants
