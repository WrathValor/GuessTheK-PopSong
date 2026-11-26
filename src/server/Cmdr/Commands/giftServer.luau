local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local GiftInbox = require(ServerScriptService.Engine.GiftInbox)

local AMOUNTS = { Coins = true, Tickets = true }

-- the gift's name, as the inbox shows it (nil: no such item)
local function nameFor(kind: string, item: string): string?
	if AMOUNTS[kind] then
		local n = tonumber(item)
		return if n and n > 0 then `{ShopCatalog.Format(n)} {if kind == "Coins" then "Coins" else "Pack Tickets"}` else nil
	elseif kind == "Set" then
		local set = ShopCatalog.GetSet(item)
		return set and set.Name
	elseif kind == "Stage" or kind == "Mic" then
		local it = ShopCatalog.GetItem(kind, item)
		return it and it.Name
	elseif kind == "StyleSet" or kind == "Banner" or kind == "Photocard" then
		local spec = ShopCatalog.GetStyle(item)
		return spec and `{spec.Name} {if kind == "StyleSet" then "set" else string.lower(kind)}`
	elseif kind == "Pass" then
		local pass = ShopCatalog.GetPass(item)
		return pass and pass.Name
	end
	return nil
end

return function(context, to, kind, item, note)
	local userId = tonumber(to)
	if not userId then
		local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, to)
		if not ok or not id then
			return `No player called {to}`
		end
		userId = id
	end
	local name = nameFor(kind, item)
	if not name then
		return `Not a gift: {kind} {item}`
	end
	local executor = context.Executor
	local sent = GiftInbox.Send(userId, {
		From = if executor then executor.DisplayName else "K-POPPED!",
		FromId = if executor then executor.UserId else 0,
		Dev = true,
		Kind = kind,
		ItemId = if AMOUNTS[kind] then nil else item,
		Amount = if AMOUNTS[kind] then math.floor(tonumber(item) :: number) else nil,
		Name = name,
		Note = note,
	})
	return if sent then `Sent {name} to {to} ({userId})` else `Couldn't send to {to}: their inbox may be full`
end
