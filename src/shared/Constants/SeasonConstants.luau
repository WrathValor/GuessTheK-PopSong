--| SeasonConstants
-- Seasons, tiers, profile banners and the Season Track, from the "Seasons & Ranked" design doc.
-- The UI reads everything from here; SeasonService (not built yet) will own the real numbers.
-- Until then the client shows each player's season through attributes with these defaults:
--   SeasonSP (number), SeasonPeakSP (number), SeasonStars (number), Banner (banner Id)
-- Tier.Emblem / Banner.Art are image slots for the final art (empty = drawn from colours).

local Currencies = require(script.Parent.Currencies)

local C = Color3.fromHex

local function seq(...)
	local list = { ... }
	local keys = {}
	for i, hex in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), C(hex)))
	end
	return ColorSequence.new(keys)
end

local HOLO = seq("FFB3C7", "FFD8A8", "FFF1A8", "B8F0C8", "B5DDFF", "D8C4FF", "FFB3C7")

local SeasonConstants = {}

-- The master switch. false = seasons are off (they'll ship as an update once launch numbers
-- are in): no Stars or SP are given, the Season screen can't be opened, tier chips / the HUD
-- season card / the Results Season bar are hidden and the profile's sixth tile shows Solo
-- Best. Banners, photocards and card upgrades keep working. Flip to true (and put the season
-- in SCHEDULE) to launch them.
SeasonConstants.ENABLED = false

-- The season calendar, oldest first. A season is live from its Starts (os.time, UTC) until the
-- next one starts; its Ends is when SP stops moving and the countdown hits 0 (0 = open-ended,
-- shown as "Pre-season"). When a new Id goes live each player's season data rolls over the next
-- time they play (Engine/SeasonService): their peak SP is kept in Season.History, their
-- season-end title is granted, and Stars / milestones / SP start again from 0.
--   Badge: the short tag titles use ("S1 Rookie"). To schedule S1, add e.g.
--   { Id = "S1", Name = "DEBUT", Badge = "S1", Starts = 1767225600, Ends = 1772064000 }
--   (os.time{year=2026, month=1, day=1, hour=0} style UTC times).
SeasonConstants.SCHEDULE = table.freeze({
	table.freeze({ Id = "S0", Name = "PRE-DEBUT", Badge = "S0", Starts = 0, Ends = 0 }),
})

-- the season live at `now` (default os.time()): the last one in SCHEDULE that has started
function SeasonConstants.Current(now: number?)
	now = now or os.time()
	local live = SeasonConstants.SCHEDULE[1]
	for _, season in SeasonConstants.SCHEDULE do
		if season.Starts <= now then
			live = season
		end
	end
	return live
end

-- true while SP can move: the season has started and hasn't hit its Ends
function SeasonConstants.IsRated(now: number?): boolean
	now = now or os.time()
	local season = SeasonConstants.Current(now)
	return season.Ends <= 0 or now < season.Ends
end

function SeasonConstants.Find(id: string)
	for _, season in SeasonConstants.SCHEDULE do
		if season.Id == id then
			return season
		end
	end
	return nil
end

-- the season that's live (the UI's header and countdown). Servers read Current() so a season
-- that starts while a server is running still rolls over.
SeasonConstants.SEASON = SeasonConstants.Current()

-- Season Points for a rated duel (1v1 duels; solo, party and the tutorial aren't rated).
-- gap = (rival SP - your SP) / GAP_STEP, capped at ±GAP_CAP: beating someone above you pays
-- more, losing to them costs less. Draws move nothing. Leaving counts as a loss.
SeasonConstants.SP = table.freeze({
	WIN = 24,
	LOSS = 18,
	GAP_STEP = 25, -- SP of difference per point of gap
	GAP_CAP = 8,
	MIN_WIN = 12,
	MIN_LOSS = 6,
	-- softer losses low down, so new players don't stall
	LOSS_SCALE = table.freeze({ Trainee = 0.5, Rookie = 0.75 }),
	-- in these tiers a loss never drops you below the tier's floor (Rookie stays Rookie)
	TIER_FLOOR = table.freeze({ Rookie = true }),
	-- after this many rated games against the same rival in a UTC day, SP from them halves;
	-- after the second number it stops (stops win-trading with an alt)
	SAME_RIVAL = table.freeze({ 3, 5 }),
})

-- Season-end titles, by peak tier: "<Badge> <Tier>" ("S1 Rookie"), at this title tier
-- (1 Normal / 2 Gold / 3 Rainbow). Trainee gets none.
SeasonConstants.END_TITLE_TIER = table.freeze({ Rookie = 1, Idol = 1, Star = 2, Icon = 2, Legend = 3 })

-- the Ranks board: top BOARD_SIZE by SP (an OrderedDataStore per season), refreshed every
-- BOARD_REFRESH seconds; SP writes are batched every BOARD_FLUSH seconds
SeasonConstants.BOARD_SIZE = 100
SeasonConstants.BOARD_REFRESH = 60
SeasonConstants.BOARD_FLUSH = 30

-- tiers, lowest first. Divisions split each range into thirds (III → I); Legend has none.
-- Rank art is the lightstick set ("Rank icons · lightsticks" on the design canvas), exported
-- at 256 × 256 from assets/ui/season/ranks. Emblems[division] is that division's lightstick
-- (III plain head, II glowing, I white-hot core); Emblem is the fallback. Image ids.
SeasonConstants.TIERS = table.freeze({
	table.freeze({ Name = "Trainee", Min = 0, Colour = C("A7E9B8"), Shape = "Circle", Emblem = "rbxassetid://112120706076085",
		Emblems = table.freeze({ III = "rbxassetid://136747450219831", II = "rbxassetid://88084024799251", I = "rbxassetid://112120706076085" }) }),
	table.freeze({ Name = "Rookie", Min = 300, Colour = C("9ED8F5"), Shape = "Square", Emblem = "rbxassetid://120039675222415",
		Emblems = table.freeze({ III = "rbxassetid://104129519186544", II = "rbxassetid://73030909510942", I = "rbxassetid://120039675222415" }) }),
	table.freeze({ Name = "Idol", Min = 700, Colour = C("FF9EC4"), Shape = "Shield", Emblem = "rbxassetid://85747164593679",
		Emblems = table.freeze({ III = "rbxassetid://81639952590637", II = "rbxassetid://103107027545208", I = "rbxassetid://85747164593679" }) }),
	table.freeze({ Name = "Star", Min = 1200, Colour = C("FFE07A"), Shape = "Hexagon", Emblem = "rbxassetid://115388636872229",
		Emblems = table.freeze({ III = "rbxassetid://82228431044283", II = "rbxassetid://72585194065156", I = "rbxassetid://115388636872229" }) }),
	table.freeze({ Name = "Icon", Min = 1800, Colour = C("B9A6FF"), Shape = "Burst", Emblem = "rbxassetid://130567699607952",
		Emblems = table.freeze({ III = "rbxassetid://73987703153967", II = "rbxassetid://107074187994856", I = "rbxassetid://130567699607952" }) }),
	table.freeze({ Name = "Legend", Min = 2500, Colour = C("FFF1A8"), Shape = "Crest", Emblem = "rbxassetid://114088441720563", Holo = true,
		-- animated Legend ("Night aura"): back (dark disc, shadow, handle, halo outline), a white
		-- layer the rainbow tints (glow rings, gem, halo) and front (gem outline, core). No
		-- sparkles. Emblem above is the flat fallback.
		Layers = table.freeze({
			Back = "rbxassetid://119152091087356",
			Disc = "rbxassetid://123715646871766",
			Front = "rbxassetid://139149743515375",
		}) }),
})
SeasonConstants.HOLO = HOLO

local DIVISIONS = { "III", "II", "I" }

-- tier info for an SP total: { Tier, Index, Division ("II" / "" for Legend), Label ("IDOL II"),
-- Pips (1–3), Next (SP of the next division or tier, nil at Legend), Floor, Progress (0–1) }
function SeasonConstants.TierOf(sp: number)
	sp = math.max(0, math.floor(sp or 0))
	local tiers = SeasonConstants.TIERS
	local index = 1
	for i, tier in tiers do
		if sp >= tier.Min then
			index = i
		end
	end
	local tier = tiers[index]
	local nextTier = tiers[index + 1]
	if not nextTier then
		return { Tier = tier, Index = index, Division = "", Label = string.upper(tier.Name), Pips = 3, Next = nil, Floor = tier.Min, Progress = 1 }
	end
	-- division floors, rounded once so the division, Floor and Next always agree (a span that
	-- isn't a whole number, like Rookie's 133.3, used to leave you a division behind at Next)
	local span = (nextTier.Min - tier.Min) / 3
	local floors = { tier.Min, math.floor(tier.Min + span + 0.5), math.floor(tier.Min + span * 2 + 0.5) }
	local step = if sp >= floors[3] then 2 elseif sp >= floors[2] then 1 else 0
	local floor = floors[step + 1]
	local nextAt = if step == 2 then nextTier.Min else floors[step + 2]
	local division = DIVISIONS[step + 1]
	return {
		Tier = tier,
		Index = index,
		Division = division,
		Label = `{string.upper(tier.Name)} {division}`,
		Pips = step + 1,
		Next = nextAt,
		-- the top tier (Legend) has no divisions, so it's just its name
		NextLabel = if step < 2
			then `{string.upper(tier.Name)} {DIVISIONS[step + 2]}`
			elseif tiers[index + 2] then `{string.upper(nextTier.Name)} III`
			else string.upper(nextTier.Name),
		Floor = floor,
		Progress = math.clamp((sp - floor) / math.max(1, nextAt - floor), 0, 1),
	}
end

-- what each tier unlocks at season end (peak tier; rewards stack)
-- the season icon sheet ("Seasons 10 · icon sheet" on the design canvas), exported at 256 × 256
-- from assets/ui/season and uploaded to the group. Image ids (not the decal ids).
SeasonConstants.ICONS = table.freeze({
	Badge = "rbxassetid://128487293224919",
	Banner = "rbxassetid://132091212735945",
	Billboard = "rbxassetid://100914820560400",
	Chest = "rbxassetid://110262105237149",
	Claimed = "rbxassetid://86588932612484",
	Correct = "rbxassetid://133539132949623", -- 2×2 answer tiles, one ticked ("get answers right" quests)
	Daily = "rbxassetid://91324418708748",
	Days = "rbxassetid://135275368592087",
	Duel = "rbxassetid://70917590170018",
	Emote = "rbxassetid://94610372590510",
	Featured = "rbxassetid://113628318815145",
	Frame = "rbxassetid://117464164402806",
	Home = "rbxassetid://136270577691198",
	Locked = "rbxassetid://122553280798696",
	Mic = "rbxassetid://122340358340051",
	Party = "rbxassetid://117064451995096",
	Perfect = "rbxassetid://76004651066351",
	Photocard = "rbxassetid://117171878289579",
	Ranks = "rbxassetid://139389755108721",
	Ready = "rbxassetid://89875658592709",
	SP = "rbxassetid://87582809015562",
	Solo = "rbxassetid://135857118627165",
	Stage = "rbxassetid://108552357965335",
	Stars = "rbxassetid://92448810394913",
	Streak = "rbxassetid://74346417839400",
	Ticket = Currencies.Tickets.Icon,
	Title = "rbxassetid://96968976075090",
	Upgrade = Currencies.Upgrades.Icon,
	Weekly = "rbxassetid://130415816343201",
	Win = "rbxassetid://130009600461003",
	XP = "rbxassetid://140366784838207",
})

SeasonConstants.TIER_REWARDS = table.freeze({
	Trainee = "Season badge",
	Rookie = "Season title",
	Idol = "Tier frame",
	Star = "Tier mic skin",
	Icon = "Animated frame + podium effect",
	Legend = "Legend title + Encore effect",
})
-- the icon each tier reward shows on the Track's "at season end" row
SeasonConstants.TIER_REWARD_ICONS = table.freeze({
	Trainee = "Badge",
	Rookie = "Title",
	Idol = "Frame",
	Star = "Mic",
	Icon = "Frame",
	Legend = "Title",
})

-- profile banners. Fill = flat colour, Gradient = a ColorSequence over it, Holo = animated,
-- TextTone = the colour the name sits in. Art = the 1200 × 300 image (assets/ui/banners), drawn
-- over Fill; the left ~40% of every image is kept calm for the photocard + name.
SeasonConstants.BANNERS = table.freeze({
	table.freeze({ Id = "Sky", Name = "Sky", Fill = C("9ED8F5"), Tag = "FREE", Source = "Default · pick any", Art = "rbxassetid://122382880874699" }),
	table.freeze({ Id = "Lilac", Name = "Lilac", Fill = C("B9A6FF"), Tag = "FREE", Source = "Default · pick any", Art = "rbxassetid://94961475052491" }),
	table.freeze({ Id = "Mint", Name = "Mint", Fill = C("A7E9B8"), Tag = "FREE", Source = "Default · pick any", Art = "rbxassetid://116976406630180" }),
	table.freeze({ Id = "S0Comeback", Name = "S0 Comeback", Fill = C("FF9EC4"), Gradient = seq("B9A6FF", "B9A6FF", "FF9EC4", "FFB3C7", "FFE07A"), Tag = "SEASON", Source = "Season Track · banner at 20, photocard at 24", Art = "rbxassetid://99839980716620" }),
	table.freeze({ Id = "S0Glow", Name = "S0 Glow", Fill = C("A7E9B8"), Gradient = seq("A7E9B8", "A7E9B8", "9ED8F5", "B9A6FF"), Tag = "SEASON", Source = "Season Track · banner at 5, photocard at 10", Art = "rbxassetid://113884756239749" }),
	table.freeze({ Id = "Lightsticks", Name = "Lightsticks", Fill = C("2A2540"), Gradient = seq("2A2540", "2A2540", "3B3360", "FF9EC4"), Tag = "INDEX", Source = "Own 100 songs", Dark = true, Art = "rbxassetid://115176556670381" }),
	table.freeze({ Id = "CityNight", Name = "City Night", Fill = C("3B3360"), Gradient = seq("1E1B2E", "3B3360", "B9A6FF", "FF9EC4"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Dark = true, Art = "rbxassetid://112137843878365" }),
	table.freeze({ Id = "PopArt", Name = "Pop Art", Fill = C("2B2440"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Dark = true, Art = "rbxassetid://118747984932160" }),
	table.freeze({ Id = "Y2KDesktop", Name = "Y2K Desktop", Fill = C("1E1B2E"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Dark = true, Art = "rbxassetid://122816496156746" }),
	table.freeze({ Id = "RetroBloom", Name = "Retro Bloom", Fill = C("4B35A8"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Dark = true, Art = "rbxassetid://73054728430835" }),
	table.freeze({ Id = "ChromeDream", Name = "Chrome Dream", Fill = C("D9B6F5"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Animated = true, Art = "rbxassetid://93344764502642" }),
	table.freeze({ Id = "MascotParade", Name = "Mascot Parade", Fill = C("FFF7EC"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://70853903057368" }),
	table.freeze({ Id = "PastelGem", Name = "Pastel Gem", Fill = C("F2E6F7"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://111940127557534" }),
	table.freeze({ Id = "NeonSeoul", Name = "Neon Seoul", Fill = C("1A1440"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Animated = true, Dark = true, Art = "rbxassetid://87819930455604" }),
	table.freeze({ Id = "LightstickCrowd", Name = "Lightstick Crowd", Fill = C("2E1A52"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Dark = true, Art = "rbxassetid://114523337826923" }),
	table.freeze({ Id = "Mixtape", Name = "Mixtape", Fill = C("FFF1DC"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://122822921710453" }),
	table.freeze({ Id = "PhotocardSwap", Name = "Photocard Swap", Fill = C("FF9EC4"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://120767389505534" }),
	table.freeze({ Id = "CornerStore", Name = "Corner Store", Fill = C("E8FBEE"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://116515872897612" }),
	table.freeze({ Id = "FanLetter", Name = "Fan Letter", Fill = C("FFE4EF"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://72873022048809" }),
	table.freeze({ Id = "MusicShow", Name = "Music Show", Fill = C("FFF6D6"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://115167565916307" }),
	table.freeze({ Id = "PolaroidWall", Name = "Polaroid Wall", Fill = C("F3EBDD"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://103437456449948" }),
	table.freeze({ Id = "AlbumUnboxing", Name = "Album Unboxing", Fill = C("EFEAFF"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Art = "rbxassetid://100194046281956" }),
	table.freeze({ Id = "LoveSlogan", Name = "Love Slogan", Fill = C("FFC8E0"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Animated = true, Art = "rbxassetid://138383735117727" }),
	table.freeze({ Id = "CheerSlogan", Name = "Cheer Slogan", Fill = C("E4F4FF"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Animated = true, Art = "rbxassetid://127773709407230" }),
	table.freeze({ Id = "BiasDoodle", Name = "Bias Doodle", Fill = C("FFF6D6"), Tag = "SHOP", Source = "Shop · Banners + photocards", Shop = true, Animated = true, Art = "rbxassetid://135748026570803" }),
	table.freeze({ Id = "S0Star", Name = "S0 Star", Fill = C("FFE07A"), Gradient = seq("FFE07A", "FFD24A", "FFE07A", "FFF1A8"), Tag = "TIER", Source = "Reach Star in S0", Art = "rbxassetid://125201482845414" }),
	table.freeze({ Id = "S0Icon", Name = "S0 Icon", Fill = C("FF9EC4"), Gradient = seq("FF9EC4", "FFD2CE", "FF9EC4", "FFB3C7"), Tag = "ANIMATED", Source = "Reach Icon in S0", Animated = true, Art = "rbxassetid://121431333266715" }),
	table.freeze({ Id = "S0Legend", Name = "S0 Legend", Fill = C("FFFFFF"), Gradient = HOLO, Tag = "HOLO", Source = "Reach Legend in S0 · never returns", Animated = true, Art = "rbxassetid://106791514235927" }),
})
-- the picker shows this many a page (a 4 × 3 grid), with ‹ › in its header past that
-- photocards: one per banner (same Id, name, tag + source), three image layers on the Profile
-- photocard's shape (280 × 334, photo window 12,12 256 × 228): Face (card + name plate), Photo
-- (behind the avatar) and Deco (stickers over the window). assets/ui/photocards. A banner + its
-- photocard is a set. Fx = SeasonFx effects (see Modules/UI/SeasonFx).
SeasonConstants.PHOTOCARDS = table.freeze({
	table.freeze({ Id = "Sky", Face = "rbxassetid://119061865579712", Photo = "rbxassetid://72140529020333", Deco = "rbxassetid://88005047175412" }),
	table.freeze({ Id = "Lilac", Face = "rbxassetid://95545539731191", Photo = "rbxassetid://107977577126282", Deco = "rbxassetid://139004081582154" }),
	table.freeze({ Id = "Mint", Face = "rbxassetid://91076255485657", Photo = "rbxassetid://133730307605414", Deco = "rbxassetid://136447155936527" }),
	table.freeze({ Id = "S0Comeback", Face = "rbxassetid://108128726396382", Photo = "rbxassetid://95642261521279", Deco = "rbxassetid://138257925305753", Fx = { { Kind = "Confetti", Layer = "Photo", Area = { 0, 0, 1, 1 }, Count = 14 }, { Kind = "Sparkle", At = { { 0.093, 0.749, 0.109 } } } } }),
	table.freeze({ Id = "S0Glow", Face = "rbxassetid://101062805392559", Photo = "rbxassetid://103301335242084", Deco = "rbxassetid://114166866719722", Fx = { { Kind = "Glow", At = { { 0.893, 0.078, 0.2, "FFE07A" } } }, { Kind = "Glow", Layer = "Photo", At = { { 0.141, 0.211, 0.219, "FF9EC4" }, { 0.852, 0.342, 0.281, "FFE07A" }, { 0.188, 0.825, 0.188, "FFFFFF" }, { 0.82, 0.868, 0.219, "FF9EC4" } } }, { Kind = "Sparkle", At = { { 0.107, 0.749, 0.109 }, { 0.893, 0.766, 0.089 } } } } }),
	table.freeze({ Id = "Lightsticks", Face = "rbxassetid://106886286585631", Photo = "rbxassetid://97619553209723", Deco = "rbxassetid://135565533029606" }),
	table.freeze({ Id = "CityNight", Face = "rbxassetid://95397970892569", Photo = "rbxassetid://137477381840051", Deco = "rbxassetid://101404560387608" }),
	table.freeze({ Id = "PopArt", Face = "rbxassetid://115537992489445", Photo = "rbxassetid://87696933767713", Deco = "rbxassetid://123496984465777" }),
	table.freeze({ Id = "Y2KDesktop", Face = "rbxassetid://75026928743192", Photo = "rbxassetid://116660554636841", Deco = "rbxassetid://71874407787619" }),
	table.freeze({ Id = "RetroBloom", Face = "rbxassetid://134428048652424", Photo = "rbxassetid://71257568198134", Deco = "rbxassetid://127011137020037" }),
	table.freeze({ Id = "ChromeDream", Face = "rbxassetid://130524959042811", Photo = "rbxassetid://127506030703458", Deco = "rbxassetid://109472325261723", Fx = { { Kind = "Holo", Alpha = 0.82 }, { Kind = "Sparkle", Soft = true, At = { { 0.107, 0.09, 0.079 }, { 0.936, 0.898, 0.063 }, { 0.064, 0.898, 0.056 } } }, { Kind = "Sparkle", Soft = true, Layer = "Photo", At = { { 0.789, 0.167, 0.069 }, { 0.133, 0.693, 0.061 } } } } }),
	table.freeze({ Id = "MascotParade", Face = "rbxassetid://124942287849483", Photo = "rbxassetid://138169082010036", Deco = "rbxassetid://113371062836680" }),
	table.freeze({ Id = "PastelGem", Face = "rbxassetid://109912899213827", Photo = "rbxassetid://85477617547396", Deco = "rbxassetid://98745820887983" }),
	table.freeze({ Id = "NeonSeoul", Face = "rbxassetid://102648297286667", Photo = "rbxassetid://92203061872836", Deco = "rbxassetid://136325065136709", Fx = { { Kind = "Glow", Flicker = true, At = { { 0.88, 0.287, 0.22, "FF5FA8" }, { 0.15, 0.665, 0.17, "FF5FA8" }, { 0.236, 0.11, 0.15, "FFF6C8" } } } } }),
	table.freeze({ Id = "LightstickCrowd", Face = "rbxassetid://136116035577224", Photo = "rbxassetid://104734834990873", Deco = "rbxassetid://89495527811596" }),
	table.freeze({ Id = "Mixtape", Face = "rbxassetid://82779448828591", Photo = "rbxassetid://102374397453746", Deco = "rbxassetid://88515233303856" }),
	table.freeze({ Id = "PhotocardSwap", Face = "rbxassetid://77571232670242", Photo = "rbxassetid://84374909808052", Deco = "rbxassetid://124772323829969" }),
	table.freeze({ Id = "CornerStore", Face = "rbxassetid://92132879759933", Photo = "rbxassetid://138230961760920", Deco = "rbxassetid://92010979438240" }),
	table.freeze({ Id = "FanLetter", Face = "rbxassetid://103222037526668", Photo = "rbxassetid://96560544124840", Deco = "rbxassetid://85323740225454" }),
	table.freeze({ Id = "MusicShow", Face = "rbxassetid://122399138434551", Photo = "rbxassetid://139845995567728", Deco = "rbxassetid://88215341739393" }),
	table.freeze({ Id = "PolaroidWall", Face = "rbxassetid://139140021029218", Photo = "rbxassetid://92686898441583", Deco = "rbxassetid://112143533213378" }),
	table.freeze({ Id = "AlbumUnboxing", Face = "rbxassetid://115975829620834", Photo = "rbxassetid://86935404629192", Deco = "rbxassetid://104565841282029" }),
	table.freeze({ Id = "LoveSlogan", Face = "rbxassetid://96448553634463", Photo = "rbxassetid://132975007654476", Deco = "rbxassetid://125222029234802", Fx = { { Kind = "Masked", Mode = "Rainbow", Fill = "LoveTagFill", Line = "LoveTagLine", At = { 0.5, 0.075, 0.67 } }, { Kind = "Sway", Layer = "Photo", At = { { "SlogCloud", 0.205, 0.181, 0.263 }, { "SlogCloud", 0.839, 0.33, 0.205 } } }, { Kind = "Sway", At = { { "HeartRed", 0.911, 0.697, 0.161 } } }, { Kind = "Sparkle", At = { { 0.089, 0.712, 0.092 } } } } }),
	table.freeze({ Id = "CheerSlogan", Face = "rbxassetid://95188645492301", Photo = "rbxassetid://129770402001717", Deco = "rbxassetid://109761433262707", Fx = { { Kind = "Glow", Layer = "Photo", At = { { 0.498, 0.385, 1.073, "FF9EC4" } } }, { Kind = "Sway", Bounce = true, At = { { "HeartPink", 0.893, 0.097, 0.259 }, { "HeartRed", 0.08, 0.719, 0.161 } } }, { Kind = "Sparkle", At = { { 0.92, 0.712, 0.082 } } } } }),
	table.freeze({ Id = "BiasDoodle", Face = "rbxassetid://93542400721314", Photo = "rbxassetid://98639927579793", Deco = "rbxassetid://109271029648876", Fx = { { Kind = "Masked", Mode = "Pulse", Fill = "BiasTagFill", Line = "BiasTagLine", At = { 0.83, 0.112, 0.375 } }, { Kind = "Sway", Layer = "Photo", At = { { "DoodleStar", 0.146, 0.187, 0.205 }, { "DoodleSpiral", 0.859, 0.198, 0.283 } } }, { Kind = "Sway", At = { { "HeartRed", 0.08, 0.719, 0.161 } } }, { Kind = "Sparkle", At = { { 0.92, 0.712, 0.082 } } } } }),
	table.freeze({ Id = "S0Star", Face = "rbxassetid://104586905526639", Photo = "rbxassetid://116362065962637", Deco = "rbxassetid://133164242791332", Fx = { { Kind = "Masked", Mode = "Pulse", Fill = "StarCardFill", Line = "StarCardLine", At = { 0.886, 0.09, 0.229 } }, { Kind = "Sparkle", At = { { 0.907, 0.754, 0.089 } } } } }),
	table.freeze({ Id = "S0Icon", Face = "rbxassetid://125414317299661", Photo = "rbxassetid://87307637208247", Deco = "rbxassetid://114201224274124", Fx = { { Kind = "Spin", Image = "Vinyl", At = { { 0.879, 0.09, 0.189, 50 } } }, { Kind = "Spin", Image = "Vinyl", Layer = "Photo", At = { { 0.109, 0.825, 0.292, -35 } } }, { Kind = "Sparkle", At = { { 0.1, 0.754, 0.099 }, { 0.907, 0.766, 0.079 } } } } }),
	table.freeze({ Id = "S0Legend", Face = "rbxassetid://114220390054677", Photo = "rbxassetid://93930596805719", Deco = "rbxassetid://84244901864688", Fx = { { Kind = "Holo", Alpha = 0.8 }, { Kind = "Rays", Layer = "Photo", At = { 0.5, 0.43, 1.4 }, Speed = 10 }, { Kind = "Sparkle", At = { { 0.893, 0.084, 0.179 }, { 0.107, 0.09, 0.119 }, { 0.1, 0.754, 0.129 }, { 0.907, 0.76, 0.099 } } } } }),
})
-- banner animations (SeasonFx), by banner Id; positions are fractions of the banner art
SeasonConstants.BANNER_FX = table.freeze({
	S0Comeback = { { Kind = "Confetti", Area = { 0.45, 0, 1, 1 }, Count = 26 } },
	S0Glow = { { Kind = "Glow", At = { { 0.517, 0.667, 0.087, "FFFFFF" }, { 0.6, 0.3, 0.113, "FF9EC4" }, { 0.708, 0.633, 0.14, "FFE07A" }, { 0.817, 0.267, 0.1, "FFFFFF" }, { 0.9, 0.667, 0.127, "FF9EC4" }, { 0.967, 0.233, 0.08, "FFE07A" } } }, { Kind = "Sparkle", At = { { 0.658, 0.133, 0.032 }, { 0.775, 0.867, 0.028 }, { 0.942, 0.9, 0.028 } } } },
	ChromeDream = { { Kind = "Holo", Alpha = 0.82 }, { Kind = "Sparkle", Soft = true, At = { { 0.547, 0.156, 0.026 }, { 0.85, 0.898, 0.022 }, { 0.977, 0.156, 0.03 }, { 0.508, 0.898, 0.017 }, { 0.674, 0.117, 0.015 }, { 0.918, 0.547, 0.013 } } } },
	NeonSeoul = { { Kind = "Glow", Flicker = true, At = { { 0.62, 0.578, 0.186, "FF5FA8" }, { 0.776, 0.535, 0.225, "5FF2FF" }, { 0.938, 0.156, 0.146, "FFF6C8" }, { 0.903, 0.723, 0.107, "FF5FA8" } } } },
	S0Star = { { Kind = "Masked", Mode = "Pulse", Fill = "StarBigFill", Line = "StarBigLine", At = { 0.75, 0.5, 0.167 } }, { Kind = "Sparkle", At = { { 0.633, 0.8, 0.037 }, { 0.842, 0.133, 0.032 } } } },
	S0Icon = { { Kind = "Spin", Image = "Vinyl", At = { { 0.75, 0.5, 0.176, 40 }, { 0.9, 0.733, 0.103, -60 } } }, { Kind = "Sparkle", At = { { 0.65, 0.233, 0.037 }, { 0.842, 0.133, 0.03 }, { 0.983, 0.767, 0.028 } } } },
	S0Legend = { { Kind = "Rays", At = { 0.767, 0.5, 0.6 }, Speed = 10 }, { Kind = "Masked", Mode = "Rainbow", Fill = "LegendIconFill", Line = "LegendIconLine", At = { 0.767, 0.5, 0.167 } }, { Kind = "Sparkle", At = { { 0.583, 0.267, 0.051 }, { 0.917, 0.2, 0.06 }, { 0.95, 0.8, 0.042 }, { 0.633, 0.8, 0.032 }, { 0.867, 0.9, 0.028 } } } },
	LoveSlogan = { { Kind = "Shine" }, { Kind = "Masked", Mode = "Rainbow", Fill = "LoveWordFill", Line = "LoveWordLine", At = { 0.716, 0.479, 0.625 } }, { Kind = "Sway", At = { { "SlogCloud", 0.399, 0.25, 0.104 }, { "SlogCloud", 0.94, 0.108, 0.08 }, { "NoteWhite", 0.498, 0.192, 0.062 }, { "NoteYellow", 0.976, 0.45, 0.051 }, { "HeartRed", 0.417, 0.708, 0.05 }, { "HeartWhite", 0.637, 0.167, 0.036 } } }, { Kind = "Sparkle", At = { { 0.583, 0.854, 0.029 }, { 0.792, 0.125, 0.031 }, { 0.983, 0.833, 0.024 }, { 0.333, 0.125, 0.022 } } } },
	CheerSlogan = { { Kind = "Shine" }, { Kind = "Glow", At = { { 0.583, 0.5, 0.354, "FF9EC4" }, { 0.854, 0.542, 0.354, "FFFFFF" } } }, { Kind = "Hop", At = { { "HopH", 0.474, 0.492, 0.177 }, { "HopW", 0.55, 0.492, 0.177 }, { "HopA", 0.625, 0.492, 0.177 }, { "HopI", 0.677, 0.492, 0.177 }, { "HopT", 0.726, 0.492, 0.177 }, { "HopI", 0.775, 0.492, 0.177 }, { "HopN", 0.827, 0.492, 0.177 }, { "HopG", 0.895, 0.492, 0.177 }, { "HopBang", 0.947, 0.492, 0.177 } } }, { Kind = "Sway", Bounce = true, At = { { "HeartPink", 0.471, 0.192, 0.073 }, { "HeartRed", 0.969, 0.292, 0.06 }, { "HeartWhite", 0.729, 0.892, 0.04 } } }, { Kind = "Sparkle", At = { { 0.667, 0.125, 0.031 }, { 0.417, 0.792, 0.026 }, { 0.983, 0.808, 0.024 }, { 0.312, 0.25, 0.024 } } } },
	BiasDoodle = { { Kind = "Shine" }, { Kind = "Masked", Mode = "Pulse", Fill = "BiasWordFill", Line = "BiasWordLine", At = { 0.743, 0.508, 0.396 } }, { Kind = "Sway", At = { { "DoodleStar", 0.49, 0.292, 0.058 }, { "DoodleSpiral", 0.948, 0.267, 0.083 }, { "DoodleArrow", 0.479, 0.667, 0.083 }, { "HeartRed", 0.531, 0.817, 0.04 } } }, { Kind = "Sparkle", At = { { 0.917, 0.583, 0.029 }, { 0.562, 0.192, 0.026 }, { 0.417, 0.458, 0.022 } } } },
})
-- the images the effects use
SeasonConstants.FX_IMAGES = table.freeze({
	FlowerOrange = "rbxassetid://116919994382602",
	FlowerYellow = "rbxassetid://80583273140442",
	FlowerPink = "rbxassetid://138885098588904",
	Vinyl = "rbxassetid://76971127570840",
	Rays = "rbxassetid://140372449518848",
	Glow = "rbxassetid://118244830983530",
	Sparkle = "rbxassetid://91554616661236",
	SparkleSoft = "rbxassetid://132383516641236",
	LegendIconFill = "rbxassetid://91164921444574",
	LegendIconLine = "rbxassetid://120888042439632",
	StarBigFill = "rbxassetid://80728911154906",
	StarBigLine = "rbxassetid://115903617689972",
	StarCardFill = "rbxassetid://127370401040216",
	StarCardLine = "rbxassetid://100429386577374",
	BiasTagFill = "rbxassetid://89505069343530",
	BiasTagLine = "rbxassetid://130503479148399",
	BiasWordFill = "rbxassetid://103881004246674",
	BiasWordLine = "rbxassetid://91451722060801",
	DoodleArrow = "rbxassetid://117673121595221",
	DoodleSpiral = "rbxassetid://129256583377383",
	DoodleStar = "rbxassetid://122054567844574",
	HeartPink = "rbxassetid://113427922160561",
	HeartRed = "rbxassetid://106717555630410",
	HeartWhite = "rbxassetid://122810835481825",
	HopA = "rbxassetid://126050081831789",
	HopBang = "rbxassetid://115599718194348",
	HopG = "rbxassetid://99425356124219",
	HopH = "rbxassetid://96821545641790",
	HopI = "rbxassetid://72200880386825",
	HopN = "rbxassetid://135735417636814",
	HopT = "rbxassetid://88472141707703",
	HopW = "rbxassetid://86965582074478",
	LoveTagFill = "rbxassetid://103123535306727",
	LoveTagLine = "rbxassetid://71251395019221",
	LoveWordFill = "rbxassetid://115191505873074",
	LoveWordLine = "rbxassetid://112824961552017",
	NoteWhite = "rbxassetid://117272396847013",
	NoteYellow = "rbxassetid://126449178775219",
	SlogCloud = "rbxassetid://118892108890719",
})
SeasonConstants.BANNERS_PER_PAGE = 12
SeasonConstants.DEFAULT_PHOTOCARD = "Sky"
SeasonConstants.FREE_PHOTOCARDS = table.freeze({ Sky = true, Lilac = true, Mint = true })

-- a photocard by Id, with its banner's Name / Tag / Source (nil if there's no such card)
local photocardCache = {}
function SeasonConstants.Photocard(id: string?)
	if not id then
		return nil
	end
	if photocardCache[id] then
		return photocardCache[id]
	end
	for _, card in SeasonConstants.PHOTOCARDS do
		if card.Id == id then
			local banner = SeasonConstants.Banner(id)
			local merged = table.clone(card)
			merged.Name, merged.Tag, merged.Source = banner.Name, banner.Tag, banner.Source
			photocardCache[id] = table.freeze(merged)
			return photocardCache[id]
		end
	end
	return nil
end

SeasonConstants.DEFAULT_BANNER = "Sky"
SeasonConstants.FREE_BANNERS = table.freeze({ Sky = true, Lilac = true, Mint = true })
-- Studio only: own every banner + photocard so the STYLE picker shows them all while testing
-- (live servers always use the player's real list). Off: Studio shows only what you own too.
SeasonConstants.STUDIO_OWN_ALL = false

function SeasonConstants.Banner(id: string?)
	for _, banner in SeasonConstants.BANNERS do
		if banner.Id == id then
			return banner
		end
	end
	return SeasonConstants.BANNERS[1]
end

-- Season Track: 25 milestones, 100 Stars each. Kind picks the card art; Banner / Photocard
-- rewards name theirs (the card shows the real banner / photocard). Title gives a title at its
-- TitleTier (Cards.LEVELS index: 3 = Rainbow, like the S0 Comeback banner + photocard).
SeasonConstants.STARS_PER_MILESTONE = 100
SeasonConstants.TRACK = table.freeze({
	{ Kind = "Coins", Amount = 100 }, { Kind = "Coins", Amount = 150 }, { Kind = "Ticket", Amount = 1 },
	{ Kind = "Coins", Amount = 150 }, { Kind = "Banner", Name = "S0 Glow banner", Banner = "S0Glow" }, { Kind = "Coins", Amount = 200 },
	{ Kind = "Upgrade", Amount = 1 }, { Kind = "Coins", Amount = 200 }, { Kind = "Ticket", Amount = 1 },
	{ Kind = "Photocard", Name = "S0 Glow", Photocard = "S0Glow", Big = true }, { Kind = "Coins", Amount = 250 }, { Kind = "Ticket", Amount = 1 },
	{ Kind = "Upgrade", Amount = 1 }, { Kind = "Coins", Amount = 300 }, { Kind = "Mic", Name = "S0 Mic", Big = true },
	{ Kind = "Coins", Amount = 250 }, { Kind = "Ticket", Amount = 1 }, { Kind = "Upgrade", Amount = 1 },
	{ Kind = "Coins", Amount = 300 }, { Kind = "Banner", Name = "S0 Comeback banner", Banner = "S0Comeback", Big = true }, { Kind = "Ticket", Amount = 1 },
	{ Kind = "Upgrade", Amount = 2 }, { Kind = "Ticket", Amount = 2 }, { Kind = "Photocard", Name = "S0 Comeback", Photocard = "S0Comeback", Big = true },
	{ Kind = "Title", Name = "S0 Comeback", Title = "S0 Comeback", TitleTier = 3, Big = true },
})

-- how Stars are earned (the Track page's "Earn Stars" tiles)
SeasonConstants.EARN = table.freeze({
	{ Value = "+10", Label = "Duel played", Icon = "Duel", Sub = "15 a day count", Colour = C("FFFFFF") },
	{ Value = "+10", Label = "Duel won", Icon = "Win", Sub = "on top of played", Colour = C("A7E9B8") },
	{ Value = "+20", Label = "Daily quest", Icon = "Daily", Sub = "3 a day", Colour = C("FFE07A") },
	{ Value = "+5", Label = "Solo game", Icon = "Solo", Sub = "10 a day count", Colour = C("CDEBFA") },
})
SeasonConstants.SOLO_STARS = 5
-- season titles: their chip is holo foil with the season's badge in front (Modules/UI/TitleChip),
-- not a set title's Normal / Gold / Rainbow. Title → badge. (None yet: S0 Comeback is Rainbow.)
SeasonConstants.SEASON_TITLES = table.freeze({})
-- what Engine/SeasonService gives (keep in step with EARN above) and how many count a day (UTC)
SeasonConstants.STARS = table.freeze({ Duel = 10, Win = 10, Quest = 20, Solo = 5 })
SeasonConstants.DAILY_STARS = table.freeze({ Duel = 15, Quest = 3, Solo = 10 }) -- Win rides on Duel

return table.freeze(SeasonConstants)
