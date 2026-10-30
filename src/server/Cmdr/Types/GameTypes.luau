--| GameTypes
-- Cmdr argument types for the testing commands (autocomplete on the client):
--   shopStage / shopMic / shopSet / shopPass – ShopCatalog ids ("all" for every one)
--   song / pack                              – CmdrKeys ("all" for every song / pack)
--   duelPack                                 – a pack key, "My", or "off"
--   soloTheme                                – Themes ids (All, 2010s, Gen4, Pack…)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(registry)
	local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
	local Util = registry.Cmdr.Util

	local function with(list: { string }, ...: string): { string }
		local out = table.clone(list)
		for _, extra in { ... } do
			table.insert(out, 1, extra)
		end
		return out
	end

	registry:RegisterType("shopStage", Util.MakeEnumType("Stage", with(CmdrKeys.StageIds(), "all")))
	registry:RegisterType("shopMic", Util.MakeEnumType("Mic", with(CmdrKeys.MicIds(), "all")))
	registry:RegisterType("shopSet", Util.MakeEnumType("Set", with(CmdrKeys.SetIds(), "all")))
	registry:RegisterType("shopPass", Util.MakeEnumType("Pass", CmdrKeys.PassIds()))
	registry:RegisterType("song", Util.MakeEnumType("Song", with(CmdrKeys.SongKeys(), "all")))
	registry:RegisterType("pack", Util.MakeEnumType("Pack", with(CmdrKeys.PackKeys(), "all")))
	registry:RegisterType("duelPack", Util.MakeEnumType("DuelPack", with(CmdrKeys.PackKeys(), "off", "My")))
	registry:RegisterType("soloTheme", Util.MakeEnumType("SoloTheme", CmdrKeys.ThemeIds()))
end
