--| CmdrUtil
-- Shared helpers for the testing commands' Server modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server

local CmdrUtil = {}

-- Runs fn(player, data) for each player whose data is loaded; returns a summary line.
-- fn may return a short note shown after the player's name.
function CmdrUtil.Each(players: { Player }, fn: (Player, any) -> string?): string
	local lines = {}
	for _, player in players do
		local ok, data = pcall(PlayerData.Get, player)
		if not ok or not data then
			table.insert(lines, `{player.Name}: data not loaded`)
			continue
		end
		local ran, note = pcall(fn, player, data)
		if not ran then
			table.insert(lines, `{player.Name}: error ({note})`)
		else
			table.insert(lines, if note then `{player.Name}: {note}` else player.Name)
		end
	end
	return table.concat(lines, "\n")
end

-- adds every id in `ids` to a SetOf, returns how many were new
function CmdrUtil.AddAll(set, ids: { string }): number
	local added = 0
	for _, id in ids do
		if not set.Has(id) then
			set.Add(id)
			added += 1
		end
	end
	return added
end

return CmdrUtil
