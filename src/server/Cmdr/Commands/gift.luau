--| gift
-- Sends a gift to anyone's Gifts inbox (Engine/GiftInbox), from you, tagged DEVELOPER. They
-- can be offline or in another server: it waits for them to claim.
--   gift Roblox Coins 5000 "Thanks for testing!"
--   gift 1234567 Set Candy
--   kind: Coins | Tickets (item = amount), Set | Stage | Mic | StyleSet | Banner | Photocard | Pass (item = id)

return {
	Name = "gift",
	Aliases = {},
	Description = "Sends a gift to anyone's Gifts inbox (online, offline, any server), from you.",
	Group = "Testing",
	Args = {
		{ Type = "string", Name = "to", Description = "Username or UserId" },
		{ Type = "string", Name = "kind", Description = "Coins, Tickets, Set, Stage, Mic, StyleSet, Banner, Photocard or Pass" },
		{ Type = "string", Name = "item", Description = "Amount (Coins, Tickets) or the item's id" },
		{ Type = "string", Name = "note", Description = "A note on the gift", Optional = true },
	},
}
