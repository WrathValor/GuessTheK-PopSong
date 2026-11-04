local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local function names(list)
	local out = {}
	for _, item in list do
		table.insert(out, item.Id)
	end
	return table.concat(out, ", ")
end
return function()
	local _, ends = ShopCatalog.RotationWindow()
	return table.concat({
		`Featured: {ShopCatalog.Featured().Id}`,
		`Sets: {names(ShopCatalog.Rotation())} (changes in {ShopCatalog.Countdown(ends - os.time())})`,
		`Stages: {names(ShopCatalog.ItemRotation("Stage"))}`,
		`Mics: {names(ShopCatalog.ItemRotation("Mic"))}`,
	}, "\n")
end
