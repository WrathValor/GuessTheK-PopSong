-- Song roll tuning. The song roll went on 25 Nov 2026 (photocard packs replaced it; the old
-- Engine/RollService and its screens are in _to_delete/step4). What's still read: the song
-- card levels (GOLD_COPIES / RAINBOW_COPIES, Modules/Library/Cards) for songs people rolled
-- before, and FIRST_ROLL_KEY / PITY in old saves and tools.
return table.freeze({
	COST = 150, -- one roll
	TEN_COST = 1350, -- ×10: ten rolls for the price of nine
	DUPLICATE_REFUND = 38, -- coins back for every duplicate pulled (about a quarter of a roll)
	FIRST_ROLL_KEY = "FirstRoll", -- Rewards.Claimed key: the first free card (RollService "FirstRoll") is used
	PITY = 4, -- after this many duplicates in a row, the next roll is a song you don't own yet
	-- card levels, by copies pulled (a song bought in the shop counts as 1 copy)
	GOLD_COPIES = 3,
	RAINBOW_COPIES = 5,
})
