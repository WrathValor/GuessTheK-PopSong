-- Static lobby HUD content that isn't driven by player data yet.
return table.freeze({
	-- Text under "NEW DROP". Set to nil to hide the card.
	NEW_DROP = "3 new songs this Friday" :: string?,
	-- Shows the SALE tag on the Shop tile.
	SHOP_SALE = false,
	-- Title shown on the profile when the player hasn't equipped one.
	DEFAULT_TITLE = "Fan",
})
