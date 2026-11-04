-- Song roll tuning (Engine/RollService, the shop's Roll tab: ShopController/Roll). Coins can be bought with Robux, so a
-- roll counts as a paid random item: the roll screen shows the odds, and the roll is off for
-- players whose PolicyService says paid random items are restricted.
return table.freeze({
	COST = 150, -- one roll
	TEN_COST = 1350, -- ×10: ten rolls for the price of nine
	DUPLICATE_REFUND = 38, -- coins back for every duplicate pulled (about a quarter of a roll)
	PITY = 4, -- after this many duplicates in a row, the next roll is a song you don't own yet
	-- card levels, by copies pulled (a song bought in the shop counts as 1 copy)
	GOLD_COPIES = 3,
	RAINBOW_COPIES = 5,
})
