--| News
-- The update log behind the What's New card (NewsController). Newest first: Updates[1] pops
-- up once on join (last, after any other join pop-up) until the player has seen it
-- (Settings.NewsSeen = its Id), and the HUD's News button opens the card again with ‹ › to
-- page back through older updates. A new update at the top lights the News button's red dot.
--
-- Each update:
--   Id        unique, never reused ("2026-11-11")                           required
--   Name      the big title on the art ("Ghost Rivals!")                    required
--   Version   "v1.1" (the tag on the art)                                   required
--   Date      "Nov 20th, 2026"                                              required
--   Art       { Icon, Back, Front, Top, Bottom }: the icon on the front photocard, the
--             back card's colour, the front card's colour and the panel's gradient (hex)
--   Featured  up to 4 { Icon, Colour, Title, Body }: the big rows on the right
--   Also      { { Tag = "NEW" | "SHOP" | "FIX" | "EVENT", Text } }: one-liners under them
--   Codes     { { Code, Reward, Expires } }: shown under the art. Expires = when the code
--             stops working (UTC, os.time with a date; leave it out for never): past it the
--             chip greys out and reads EXPIRED. Keep Reward in line with what the code
--             really gives (RewardsCatalog.CODES or the GitHub codes file).
-- Icon = a SeasonConstants.ICONS key ("Duel", "Party", …) or an rbxassetid. Drawn for this card:
--   rbxassetid://139628311844369 ghost (assets/ui/NewsGhost.png), rbxassetid://93616403173926 invite
--   (assets/ui/NewsInvite.png), rbxassetid://115794843985239 gift (the shop's gift tab),
--   rbxassetid://120664233001275 coin potion (assets/ui/PotionCoinsSmall.png)

local function utc(year: number, month: number, day: number, hour: number, min: number): number
	return os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = 0 })
end

return table.freeze({
	TAG_COLOURS = table.freeze({ NEW = "FFE07A", SHOP = "A7E9B8", FIX = "9ED8F5", EVENT = "FF9EC4" }),

	Updates = table.freeze({
		{
			Id = "2026-11-ghost-rivals",
			Name = "Ghosts + Gifts!",
			Version = "v1.1",
			Date = "Nov 20th, 2026",
			Art = { Icon = "rbxassetid://139628311844369", Back = "FFE07A", Front = "FAF6E9", Top = "B9A6FF", Bottom = "FF9EC4" },
			Featured = {
				{ Icon = "rbxassetid://139628311844369", Colour = "B9A6FF", Title = "Ghost Rivals", Body = "Nobody on the stage? A ghost of a real duel steps up within seconds." },
				{ Icon = "rbxassetid://115794843985239", Colour = "FF9EC4", Title = "Gifting", Body = "Tap a player's card, hit Gift and send them anything in the shop." },
				{ Icon = "rbxassetid://120664233001275", Colour = "FFE07A", Title = "Potions", Body = "2× Coins and 2× XP. They only tick down while you play." },
				{ Icon = "rbxassetid://93616403173926", Colour = "A7E9B8", Title = "Invite + earn", Body = "New button top right: 300 coins for every friend who plays." },
			},
			Also = {
				{ Tag = "NEW", Text = "Daily login: new prizes every day, potions on day 7" },
				{ Tag = "NEW", Text = "Waiting alone? We pair you with someone on another stage" },
				{ Tag = "NEW", Text = "Rivals can join you while you practise solo" },
				{ Tag = "NEW", Text = "Beat a ghost for 80% of the stake" },
				{ Tag = "SHOP", Text = "New shop layout with quick tabs down the side" },
				{ Tag = "SHOP", Text = "Coin potion + 2× Coins pass = 3× coins" },
				{ Tag = "SHOP", Text = "VIP perks now listed in the shop, like early restocks" },
				{ Tag = "FIX", Text = "Picking a practice theme isn't interrupted any more" },
				{ Tag = "FIX", Text = "Starter offer shows right after you skip the tutorial" },
			},
			-- (add these to the codes file too: News only shows them)
			Codes = {
				{ Code = "GIFTED", Reward = "300 coins · 1 ticket", Expires = utc(2026, 11, 27, 23, 59) },
				{ Code = "BOOSTED", Reward = "30 min 2× Coins + 2× XP", Expires = utc(2026, 11, 27, 23, 59) },
				{ Code = "5KVISITS", Reward = "500 coins · 1 ticket", Expires = utc(2026, 11, 27, 23, 59) },
			},
		},
		{
			Id = "2026-11-11",
			Name = "Release!",
			Version = "v1.0",
			Date = "Nov 11th, 2026",
			Art = { Icon = "Photocard", Back = "9ED8F5", Front = "FAF6E9", Top = "9ED8F5", Bottom = "A7E9B8" },
			Featured = {
				{ Icon = "Duel", Colour = "FF9EC4", Title = "1v1 song duels", Body = "Hear a tiny clip, name the song before your rival. 300+ songs, gen 2 to 5." },
				{ Icon = "Party", Colour = "B9A6FF", Title = "Party Stages", Body = "Host a private stage for up to 6 and pick which groups play." },
				{ Icon = "Photocard", Colour = "FFE07A", Title = "Collect the songs", Body = "Roll for songs: the ones you own come up more in your duels." },
				{ Icon = "Ranks", Colour = "A7E9B8", Title = "Badges + leaderboards", Body = "8 badges to earn and 5 leaderboards on the street." },
			},
			Also = {
				{ Tag = "NEW", Text = "Duel anyone in the server from the queue card" },
				{ Tag = "NEW", Text = "Practise solo on any era or generation" },
				{ Tag = "SHOP", Text = "Stage sets and items rotate every 6 hours" },
				{ Tag = "EVENT", Text = "Join the group for a free stage and coins" },
			},
			Codes = {
				{ Code = "KPOP", Reward = "500 coins · 2 tickets", Expires = utc(2026, 11, 26, 23, 59) },
				{ Code = "DEBUT", Reward = "250 coins · 1 upgrade", Expires = utc(2026, 11, 26, 23, 59) },
				{ Code = "DAYONE", Reward = "Day One title · 300 coins", Expires = utc(2026, 11, 26, 23, 59) },
			},
		},
	}),
})
