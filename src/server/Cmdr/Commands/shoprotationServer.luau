local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local function names(list)
	local out = {}
	for _, item in list do
		table.insert(out, item.Id)
	end
	return table.concat(out, ", ")
end
return function()
	local _, ends = ShopCatalog.RotationWindow()
	local _, packEnds = Packs.RotationWindow()
	return table.concat({
		`Featured: {ShopCatalog.Featured().Id}`,
		`Sets: {names(ShopCatalog.Rotation())} (changes in {ShopCatalog.Countdown(ends - os.time())})`,
		`Stages: {names(ShopCatalog.ItemRotation("Stage"))}`,
		`Mics: {names(ShopCatalog.ItemRotation("Mic"))}`,
		`Company packs: {names(Packs.Rotation("Company"))}`,
		`Group packs: {names(Packs.Rotation("Group"))} (packs change in {ShopCatalog.Countdown(packEnds - os.time())})`,
	}, "\n")
end
