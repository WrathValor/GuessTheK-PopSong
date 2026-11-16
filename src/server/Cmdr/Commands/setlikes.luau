--| setlikes
-- Sets the like goal's count for this server, to test the sign and its codes. The next read
-- from the Worker puts the real count back.

return {
	Name = "setlikes",
	Aliases = {},
	Description = "Sets the like goal's count (this server, until the next real read).",
	Group = "Testing",
	Args = {
		{ Type = "integer", Name = "likes", Description = "Likes" },
	},
}
