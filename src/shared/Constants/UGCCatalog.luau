--| UGCCatalog
-- The group's own avatar items (Wrath's UGC), sold for Robux in the shop's UGC tab and next
-- to the answer on the reveal / results screens. Engine/UGCService reads the group's catalog
-- live (new uploads show up by themselves); this file only says what to leave out, how to
-- name things, and which dance goes with which song in the library.

local UGCCatalog = {}

UGCCatalog.CREATOR = "Wrath's UGC"
UGCCatalog.REFRESH = 15 * 60 -- seconds between catalog re-reads on a server
-- the white Robux icon on the buy buttons (tinted ink); "" = the shop's normal Robux icon
-- (file: assets/icons/RobuxWhite.png)
UGCCatalog.ROBUX_ICON = ""

-- items whose name matches any of these are never shown
UGCCatalog.SKIP = {
	"^%[Chat Bubble%]",
}

-- items never shown, by asset id (still on sale on the catalog, just not in the game)
UGCCatalog.EXCLUDE = {
	[79243170815626] = true, -- Butter - BTS
	[138822432974124] = true, -- Dynamite - BTS
	[105740895954804] = true, -- Bite Me - ENHYPEN
	[91671983703577] = true, -- Standing Next to You - Jungkook
	[103541567542838] = true, -- Hands Up - MEOVV
}

-- catalog AssetType -> what the shop calls it (anything not listed, e.g. bundles, is skipped)
UGCCatalog.KINDS = {
	EmoteAnimation = "Dance",
	HatAccessory = "Accessory",
	HairAccessory = "Accessory",
	FaceAccessory = "Accessory",
	NeckAccessory = "Accessory",
	ShoulderAccessory = "Accessory",
	FrontAccessory = "Accessory",
	BackAccessory = "Accessory",
	WaistAccessory = "Accessory",
}

-- the line under an accessory's name
UGCCatalog.ACCESSORY_SUB = {
	HatAccessory = "Hat",
	HairAccessory = "Hair",
	FaceAccessory = "Face accessory",
	NeckAccessory = "Neck accessory",
	ShoulderAccessory = "Shoulder accessory",
	FrontAccessory = "Front accessory",
	BackAccessory = "Back accessory",
	WaistAccessory = "Waist accessory",
}

-- dance asset id -> song Id in the library ("Name - Artist"). These get the "IN THE GAME" tag
-- and the "Get this dance" card on the reveal + results screens.
UGCCatalog.SONGS = {
	[74608002247637] = "RUN - BTS",
	[131309975440930] = "Fire - BTS",
	[124662611316273] = "VERY NICE - SEVENTEEN",
	[108533808262143] = "Super - SEVENTEEN",
	[105262036282209] = "Genie - Girls' Generation",
	[101177872120363] = "Thunderous - Stray Kids",
	[127694523669311] = "Lucifer - SHINee",
	[98229315027870] = "The Eve - EXO",
	[118262479862500] = "Love Shot - EXO",
	[101737650767160] = "CAKE - ITZY",
	[112805551961499] = "Peek-A-Boo - Red Velvet",
	[139487980529542] = "BBoom BBoom - MOMOLAND",
	[130106622284389] = "BAAM - MOMOLAND",
	[98183412102598] = "Drunk-Dazed - ENHYPEN",
	[86684971253412] = "Sorry Sorry - Super Junior",
}

-- names that don't read "Song - Artist" on the catalog: { Name, Artist }
UGCCatalog.NAMES = {
	[102919723780830] = { "Into the New World", "Girls' Generation" },
	[81392668372105] = { "S-Class (dance break)", "Stray Kids" },
	[123320288677455] = { "S-Class", "Stray Kids" },
	[86313871315918] = { "Maniac", "Stray Kids" },
	[78028049443516] = { "God's Menu", "Stray Kids" },
	[139523601697262] = { "MONEY", "LISA" },
	[78830527615307] = { "Wife", "i-dle" },
}

return UGCCatalog
