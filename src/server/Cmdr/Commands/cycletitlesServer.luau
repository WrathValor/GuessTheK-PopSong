local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)

-- players currently cycling -> the title to put back when they stop
local running: { [Player]: string } = {}

-- fandom titles only: group packs that have a name in Packs.FANDOMS, A–Z by group
local function fandomTitles(data): { string }
	local list = {}
	for _, pack in Packs.Groups() do
		local fandom = Packs.FANDOMS[pack.Name]
		if fandom and data.Inventory.Titles.Has(fandom) then
			table.insert(list, fandom)
		end
	end
	return list
end

return function(_, players, seconds)
	local interval = math.max(seconds or 1, 0.2)
	return CmdrUtil.Each(players, function(player, data)
		if running[player] ~= nil then
			-- second run: stop and put the old title back
			local previous = running[player]
			running[player] = nil
			data.Inventory.Title.Set(previous)
			return "stopped cycling titles"
		end
		local titles = fandomTitles(data)
		if #titles == 0 then
			return "no fandom titles unlocked"
		end
		running[player] = data.Inventory.Title.Get()
		task.spawn(function()
			local i = 0
			while running[player] ~= nil and player.Parent do
				i = i % #titles + 1
				data.Inventory.Title.Set(titles[i])
				task.wait(interval)
			end
			running[player] = nil
		end)
		return `cycling {#titles} fandom titles every {interval}s (run again to stop)`
	end)
end
