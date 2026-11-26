--| ProfileController ("Profile")
-- Your profile, full screen (Interface.Frames.Profile, built by ./Build BuildFullScreen from
-- design board "34 · Profile · full screen with a card showcase"), opened from the HUD's
-- Profile button:
--   • your player card: avatar, name, equipped title + your bias, level badge, XP bar
--   • tabs: Showcase (below), Stats (every stat, with a rank tag while you're on that board's
--     kept top 100) and Titles (the titles you own; Equip through ShopRemote, like the
--     Inventory). TITLE opens the Titles tab; STYLE → banners
--   • the SHOWCASE: 5 photocards everyone sees (Profile.Cards, Modules/UI/Photocard)
--   • Edit: each slot shows SLOT n. Tap a slot → the Picker
--     (your cards, best first) fills it; ✕ empties it; DONE (the Edit button) finishes. Every
--     change is saved through ProfileRemote (Engine/ProfileService checks it) and shows
--     straight away while the save comes back through PlayerData.
--   • someone else's profile: Open("Profile", { Player = player }) (PlayerCardController opens
--     it when you click / tap a player in the lobby). The same screen, read-only, from their
--     attributes (DataService, BiasService, Engine/ProfileService): their card, title, bias and
--     level; CHALLENGE TO A DUEL (InviteRemote "Challenge", like the old player card), ADD
--     FRIEND and GIFT in place of XP / TITLE / STYLE; what you have in common in place of EDIT;
--     VS YOU (your record against them, Statistics.Rivals) in place of BINDER; no Titles tab.
--   • five stat tiles and your SETS: albums with every member owned (✓), ALL-KILL when every
--     member is Gold (Albums.AllKill)

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Levels = require(ReplicatedStorage.Modules.Levels)
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local Upgrades = require(ReplicatedStorage.Modules.Library.Upgrades)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local Photocard = require(ReplicatedStorage.Modules.UI.Photocard)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ProfileRemote = Bridgenet.ReferenceBridge("ProfileRemote")
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")
local InviteRemote = Bridgenet.ReferenceBridge("InviteRemote")
local GREY = Color3.fromHex("E3DCCD")
local RED = Color3.fromHex("FF5A4E")
-- their attributes that redraw their profile while it's open
local WATCH = { "Level", "Title", "TitleTier", "Bias", "Streak", "Wins", "Duels", "BestStreak", "Perfect", "Correct", "SoloBest", "CardShowcase", "CardsOwned", "Sets", "SetsDone", "AllKills", "InDuel", "Stage", "PartyStage" }

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")

local TABS = { "Showcase", "Stats", "Titles" }
-- stat tile → the board its rank tag comes from
local RANKS = {
	Wins = "MostWins",
	BestStreak = "TopStreaks",
	Perfect = "PerfectGames",
	Correct = "MostAnswers",
}

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PENDING_FOR = 5 -- seconds a just-saved pick shows before PlayerData must have it
local SLOTS = AlbumConstants.SHOWCASE_SLOTS
local PICKER_LIMIT = 120 -- cards in the picker (best first)
local RARITY_COLOURS = {
	standard = "FFFFFF",
	selca = "FFD2E5",
	store = "A7E9B8",
	luckydraw = "B9A6FF",
	fansign = "FF9EC4",
	polaroid = "FBF7F0",
	oneofone = "FFE07A",
}

-- --------------------------------- Helpers -------------------------------- --
local function commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted, k = s, 0
	repeat
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

local function cards(): { [string]: number }
	local v = get(PlayerData.Inventory.Cards, nil)
	return if type(v) == "table" then v else {}
end

local function bias(): string
	return get(PlayerData.Inventory.Bias, "")
end

local function serialOf(cardId: string): number?
	local field = PlayerData.Inventory.Serials[cardId]
	return Albums.Serials(field and field.Get())[1]
end

-- when the player first rolled a card (os.time), for the Polaroid date stamp
local function dateOf(cardId: string): number?
	local field = PlayerData.Inventory.CardDates[cardId]
	local at = field and field.Get()
	return if at and at > 0 then at else nil
end

local function rateText(n: number): string
	return if n % 1 == 0 then commas(n) else string.format("%.1f", n)
end

-- (best first) rarity, then level, then name
local function strength(cardId: string, copies: number): number
	local info = Albums.Card(cardId)
	if not info then
		return -1
	end
	return Albums.RarityRank(info.Rarity.Key) * 10 + (Albums.LEVEL_RANK[Albums.Level(copies) or "Normal"] or 0)
end

-- every album you can collect, with whether it's complete / ALL-KILL
local function setsOf(owned: { [string]: number }): { { Album: any, AllKill: boolean } }
	local out = {}
	for _, artist in Albums.PullArtists() do
		for _, album in Albums.PullAlbums(artist) do
			if Albums.Complete(owned, album) then
				table.insert(out, { Album = album, AllKill = Albums.AllKill(owned, album) })
			end
		end
	end
	table.sort(out, function(a, b)
		if a.AllKill ~= b.AllKill then
			return a.AllKill
		end
		return a.Album.Artist:lower() < b.Album.Artist:lower()
	end)
	return out
end

-- your place on a board, while you're on its kept list with a score
local function rankOn(board: string, userId: number?): number?
	local ok, entries = pcall(PlayerData.GetLeaderboard, board)
	if not ok or type(entries) ~= "table" then
		return nil
	end
	for _, e in entries do
		if e.UserId == (userId or LOCAL_PLAYER.UserId) and type(e.Score) == "number" and e.Score > 0 then
			return e.Rank
		end
	end
	return nil
end

-- (owned card count, all cards) over every album you can collect
local function cardCount(owned: { [string]: number }): (number, number)
	local have, total = 0, 0
	for _, artist in Albums.PullArtists() do
		for _, album in Albums.PullAlbums(artist) do
			for _, member in album.Members do
				for _, rarity in AlbumConstants.RARITIES do
					total += 1
					if (owned[Albums.CardId(album.Id, member.Key, rarity.Key)] or 0) > 0 then
						have += 1
					end
				end
			end
		end
	end
	return have, total
end

-- "Group:memberKey" -> the member's name
local function biasName(value: string?): string?
	local group, key = Albums.BiasParts(value or "")
	if group and key then
		for _, album in Albums.ForArtist(group) do
			for _, member in album.Members do
				if member.Key == key then
					return member.Name
				end
			end
		end
	end
	return nil
end

local function num(player: Player, attribute: string): number
	local v = player:GetAttribute(attribute)
	return if type(v) == "number" then v else 0
end

-- your record against them: (wins, losses, last five "WLWWL") or nil
local function rivalRecord(userId: number): (number?, number?, string?)
	local map = get(PlayerData.Statistics.Rivals, nil)
	local s = type(map) == "table" and map[tostring(userId)]
	if type(s) ~= "string" then
		return nil
	end
	local w, l, last = s:match("^(%d+)%.(%d+)%.([WL]*)%.")
	if not w then
		return nil
	end
	return tonumber(w), tonumber(l), last
end

-- "id*copies|..." -> ids by slot, copies by id
local function decodeShowcase(value: any): ({ string }, { [string]: number })
	local ids, copies = {}, {}
	local parts = string.split(if type(value) == "string" then value else "", "|")
	for i = 1, SLOTS do
		local id, n = string.match(parts[i] or "", "^(.+)%*(%d+)$")
		ids[i] = id or ""
		if id then
			copies[id] = tonumber(n) or 1
		end
	end
	return ids, copies
end

-- their completed albums from the Sets attribute ("<albumId>!" = ALL-KILL)
local function setsFrom(value: any): { { Album: any, AllKill: boolean } }
	local out = {}
	for _, part in string.split(if type(value) == "string" then value else "", ",") do
		local id = part:gsub("!$", "")
		local album = id ~= "" and Albums.Get(id)
		if album then
			table.insert(out, { Album = album, AllKill = part:sub(-1) == "!" })
		end
	end
	return out
end

local function groupArt(album): string
	return album.PackArt or ""
end

-- ---------------------------------- Class --------------------------------- --
local Profile = {}
Profile.__index = Profile

function Profile.new()
	local self = setmetatable({}, Profile)
	self.Name = "Profile"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._pending = nil :: { Ids: { string }, Until: number }? -- a showcase change just saved
	self._editing = false
	self._pickSlot = nil :: number? -- the slot the Picker is filling
	self._tiles = {} -- the Picker's tiles, kept for reuse
	self._setChips = {}
	self._tab = "Showcase"
	self._titleRows = {}
	self._viewing = nil :: Player? -- someone else's profile (nil = yours)
	self._watch = Janitor.new() -- their attribute listeners
	self._note = nil :: string? -- the Duel button's note while an invite is on its way
	return (self :: any) :: UITypes.Controller
end

-- [[ Drawing ]]

function Profile:_paintCard()
	local f = self._frame
	local left = f.Left
	local face = left.Photocard.Face
	local who = self._viewing or LOCAL_PLAYER
	face.PlayerName.Text = who.DisplayName
	face.Photo.Avatar.Image = `rbxthumb://type=AvatarBust&id={who.UserId}&w=420&h=420`
	TitleChip.Paint(face.Chips.Title, who:GetAttribute("Title") or HUDConstants.DEFAULT_TITLE, who:GetAttribute("TitleTier") or "Normal", who:GetAttribute("TitleIcon"))
	-- their bias, as a chip beside the title
	local name = biasName(if self._viewing then self._viewing:GetAttribute("Bias") else bias())
	face.Chips.Bias.Visible = name ~= nil
	face.Chips.Bias.Text = `♥ {name or ""}`

	local viewing = self._viewing ~= nil
	f.Title.Text = if viewing then who.DisplayName else "Profile"
	f.Sub.Text = if viewing then "In your server · tapped in the lobby" else "What other players see when they tap you"
	left.XP.Visible = not viewing
	for _, piece in { "ChangeTitle", "ChangeTitleShadow", "StyleButton", "StyleButtonShadow" } do
		left[piece].Visible = not viewing
	end
	left.Actions.Visible = viewing
	if self._viewing then
		face.LevelBadge.Level.Text = tostring(num(self._viewing, "Level"))
		self:_paintActions()
		return
	end

	local level, into, need = Levels.FromXP(get(PlayerData.Player.XP, 0))
	local maxed = level >= Levels.MAX_LEVEL
	face.LevelBadge.Level.Text = tostring(level)
	left.XP.Level.Text = `Level {level}`
	left.XP.Amount.Text = if maxed then "MAX" else `{commas(into)} / {commas(need)} XP`
	TweenService:Create(left.XP.Track.Fill, FILL_TWEEN, {
		Size = UDim2.fromScale(if maxed then 1 else math.clamp(into / math.max(need, 1), 0, 1), 1),
	}):Play()
end

-- VS YOU: your record against them
local function vsYou(userId: number): { string }
	local w, l, last = rivalRecord(userId)
	if not w then
		return { "0 – 0", "you haven't played yet" }
	end
	local lead = if w > l then "you lead" elseif l > w then "they lead" else "level"
	local lastResult = if last and #last > 0 then (if last:sub(-1) == "W" then " · last: won" else " · last: lost") else ""
	return { `{w} – {l}`, lead .. lastResult }
end

function Profile:_paintStats()
	local stats = PlayerData.Statistics
	local tiles = self._frame.Panel.ShowcasePage.Stats
	tiles.Binder.Label.Text = if self._viewing then "VS YOU" else "BINDER"
	if self._viewing then
		local p = self._viewing
		local _, total = cardCount({})
		local wins, duels = num(p, "Wins"), num(p, "Duels")
		local rank = rankOn("TopStreaks", p.UserId)
		local values = {
			Wins = { commas(wins), if duels > 0 then `{math.floor(wins / duels * 100 + 0.5)}% win rate` else "no duels yet" },
			BestStreak = { commas(num(p, "BestStreak")), if rank then `#{rank} all time` else `now on {num(p, "Streak")}` },
			Cards = { `{commas(num(p, "CardsOwned"))}<font size="13"> / {commas(total)}</font>`, "different cards" },
			Binder = vsYou(p.UserId),
			Sets = { commas(num(p, "SetsDone")), if num(p, "AllKills") > 0 then `{num(p, "AllKills")} ALL-KILL` else "albums complete" },
		}
		for name, v in values do
			tiles[name].Value.Text = v[1]
			tiles[name].Sub.Text = v[2]
		end
		self:_paintSets(setsFrom(p:GetAttribute("Sets")))
		return
	end
	local owned = cards()
	local have, total = cardCount(owned)
	local wins, duels = get(stats.Wins, 0), get(stats.Duels, 0)
	local sets = setsOf(owned)
	local allKills = 0
	for _, s in sets do
		allKills += if s.AllKill then 1 else 0
	end
	local rate = Albums.Rate(owned, bias(), get(PlayerData.Inventory.Pins, ""), Albums.Boost(PlayerData.GamePasses, Upgrades.Levels(PlayerData)), Upgrades.Levels(PlayerData))
	local values = {
		Wins = { commas(wins), if duels > 0 then `{math.floor(wins / duels * 100 + 0.5)}% win rate` else "no duels yet" },
		BestStreak = { commas(get(stats.HighestStreak, 0)), `now on {get(PlayerData.Player.Streak, 0)}` },
		Cards = { `{commas(have)}<font size="13"> / {commas(total)}</font>`, "different cards" },
		Binder = { `{rateText(rate)}<font size="13"> /hr</font>`, "from your pins" },
		Sets = { commas(#sets), if allKills > 0 then `{allKills} ALL-KILL` else "albums complete" },
	}
	for name, v in values do
		local tile = tiles[name]
		tile.Value.Text = v[1]
		tile.Sub.Text = v[2]
	end
	self:_paintSets(sets)
end

function Profile:_paintSets(sets)
	local row = self._frame.Panel.ShowcasePage.Sets
	local shown = {}
	for i, s in sets do
		local album = s.Album
		local chip = self._setChips[album.Id]
		if not chip then
			chip = row.Template:Clone()
			chip.Name = "Set"
			chip.Parent = row
			self._setChips[album.Id] = chip
		end
		shown[album.Id] = true
		chip.LayoutOrder = i
		chip.Visible = true
		chip.Icon.Image = groupArt(album)
		local ok, colour = pcall(Color3.fromHex, album.Colour or "FF9EC4")
		chip.Icon.BackgroundColor3 = if ok then colour else C("FF9EC4")
		chip.Label.Text = `{album.Artist} · {album.Name}`
		chip.BackgroundColor3 = if s.AllKill then YELLOW else MINT
		chip.Badge.Visible = s.AllKill
		chip.Tick.Visible = not s.AllKill
	end
	for id, chip in self._setChips do
		if not shown[id] then
			chip.Visible = false
		end
	end
	row.Empty.Visible = #sets == 0
end

-- the showcase as saved, or the pick you just made while its save is on the way
function Profile:_ids(): { string }
	local saved = Albums.Showcase(get(PlayerData.Profile.Cards, ""))
	local pending = self._pending
	if pending and os.clock() < pending.Until then
		for i = 1, SLOTS do
			if saved[i] ~= (pending.Ids[i] or "") then
				return pending.Ids
			end
		end
	end
	self._pending = nil
	return saved
end

function Profile:_paintShowcase()
	local panel = self._frame.Panel.ShowcasePage
	local showcase = panel.Showcase
	local owned, ids
	if self._viewing then
		ids, owned = decodeShowcase(self._viewing:GetAttribute("CardShowcase"))
		self._editing = false
	else
		owned, ids = cards(), self:_ids()
	end
	local editing = self._editing
	local viewing = self._viewing ~= nil
	for i = 1, SLOTS do
		local holder = showcase["Card" .. i]
		local id = ids[i]
		local copies = owned[id] or 0
		local info = if id ~= "" and copies > 0 then Photocard.Paint(holder.Card, id, copies, if viewing then nil else serialOf(id), if viewing then nil else dateOf(id)) else nil
		if not info then
			holder.Card.Visible = false
		end
		holder.Rarity.Visible = info ~= nil
		if info then
			holder.Rarity.Text = info.Rarity.Name
			holder.Rarity.BackgroundColor3 = C(RARITY_COLOURS[info.Rarity.Key] or "FFFFFF")
		end
		holder.Add.Visible = info == nil and not viewing
		holder.Add.Plus.Visible = editing
		holder.AddLabel.Visible = info == nil and editing
		holder.Slot.Visible = editing
		holder.Hit.Visible = editing
		holder.Unpin.Visible = editing and info ~= nil
	end
	local count = 0
	for _, id in ids do
		count += if id ~= "" and (owned[id] or 0) > 0 then 1 else 0
	end
	panel.ShowcaseSub.Text = if viewing
		then (if count == 0 then "nothing on show yet" else `{count} of {SLOTS} · their best pulls`)
		elseif editing then "tap a slot to choose its card"
		else `{count} of {SLOTS} · your best pulls, for everyone to see`
	panel.Edit.Visible = not viewing
	panel.EditShadow.Visible = not viewing
	self:_paintCommon()
	local edit = panel.Edit
	edit.Label.Text = if editing then "DONE" else "EDIT"
	edit.Icon.Visible = not editing
	edit.Label.Position = UDim2.fromOffset(if editing then 0 else 40, 0)
	edit.Label.Size = UDim2.new(1, if editing then 0 else -48, 1, 0)
	edit.Label.TextXAlignment = if editing then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	edit.BackgroundColor3 = if editing then MINT else WHITE
end

-- someone else's profile: what you have in common (the same bias's group, else a group on both
-- your showcases)
function Profile:_paintCommon()
	local chip = self._frame.Panel.ShowcasePage.Common
	local p = self._viewing
	local group = nil
	if p then
		local theirs = Albums.BiasParts(p:GetAttribute("Bias") or "")
		local mine = Albums.BiasParts(bias())
		if theirs and theirs == mine then
			group = theirs
		else
			local ids = decodeShowcase(p:GetAttribute("CardShowcase"))
			local myGroups = {}
			for _, id in self:_ids() do
				local info = id ~= "" and Albums.Card(id)
				if info then
					myGroups[info.Album.Artist] = true
				end
			end
			for _, id in ids do
				local info = id ~= "" and Albums.Card(id)
				if info and myGroups[info.Album.Artist] then
					group = info.Album.Artist
					break
				end
			end
		end
	end
	chip.Visible = group ~= nil
	if group then
		-- the group's photo, else a member's photo
		local image = ""
		for _, album in Albums.PullAlbums(group) do
			image = groupArt(album)
			if image == "" then
				for _, member in album.Members do
					if (member.Art or "") ~= "" then
						image = member.Art
						break
					end
				end
			end
			if image ~= "" then
				break
			end
		end
		chip.Icon.Image = image
		chip.Label.Text = `You both stan {group}`
	end
end

-- their Duel button: not while they're on a stage, or you're mid-duel
function Profile:_paintActions()
	local p = self._viewing
	if not p then
		return
	end
	local actions = self._frame.Left.Actions
	local busy = p:GetAttribute("InDuel") or p:GetAttribute("Stage") or p:GetAttribute("PartyStage")
	local mine = LOCAL_PLAYER:GetAttribute("InDuel") or LOCAL_PLAYER:GetAttribute("PartyStage")
	local duel = actions.Duel
	duel.Text = if self._note then self._note elseif busy then "ON A STAGE" elseif mine then "FINISH YOUR DUEL FIRST" else "CHALLENGE TO A DUEL"
	duel.Active = not busy and not mine and self._note == nil
	duel.BackgroundColor3 = if duel.Active then RED else GREY
	actions.DuelShadow.Visible = duel.Active
end

function Profile:_flash(note: string)
	self._note = note
	self:_paintActions()
	Juice.Shake(self._frame.Left.Actions.Duel, 4)
	local token = {}
	self._noteToken = token
	task.delay(2.5, function()
		if self._noteToken == token then
			self._note = nil
			if self.State ~= "Inactive" then
				self:_paintActions()
			end
		end
	end)
end

-- saves a new showcase (5 ids by slot, "" = empty) and shows it right away
function Profile:_save(ids: { string })
	ProfileRemote:Fire({ Action = "SetCards", Cards = ids })
	self._pending = { Ids = ids, Until = os.clock() + PENDING_FOR }
	self:_paintShowcase()
end

-- [[ The picker ]]

function Profile:_openPicker(slot: number)
	self._pickSlot = slot
	local picker = self._frame.Picker
	local grid = picker.Sheet.Grid
	picker.Sheet.Title.Text = `Pick a card for slot {slot}`
	local owned = cards()
	local ids = self:_ids()
	local onShow = {}
	for i, id in ids do
		if id ~= "" then
			onShow[id] = i
		end
	end
	local list = {}
	for id, copies in owned do
		if copies > 0 and Albums.Card(id) then
			table.insert(list, { Id = id, Copies = copies, Strength = strength(id, copies) })
		end
	end
	table.sort(list, function(a, b)
		if a.Strength ~= b.Strength then
			return a.Strength > b.Strength
		end
		return a.Id < b.Id
	end)
	for i = 1, math.max(#list, #self._tiles) do
		local entry = list[i]
		local tile = self._tiles[i]
		if entry and i <= PICKER_LIMIT then
			if not tile then
				tile = grid.Template:Clone()
				tile.Name = `Pick{i}`
				tile.LayoutOrder = i
				tile.Parent = grid
				self._tiles[i] = tile
				local index = i
				tile.Activated:Connect(function()
					local pick = self._pickList and self._pickList[index]
					if pick then
						self:_pick(pick.Id)
					end
				end)
			end
			local info = Photocard.Paint(tile.Card, entry.Id, entry.Copies, serialOf(entry.Id), dateOf(entry.Id))
			tile.Rarity.Text = info and info.Rarity.Name or ""
			tile.Using.Visible = onShow[entry.Id] ~= nil
			tile.Using.Text = if onShow[entry.Id] == slot then "IN THIS SLOT" else "ON SHOW"
			tile.Visible = true
		elseif tile then
			tile.Visible = false
		end
	end
	self._pickList = list
	grid.Empty.Visible = #list == 0
	grid.CanvasPosition = Vector2.zero
	picker.Visible = true
end

function Profile:_closePicker()
	self._pickSlot = nil
	self._frame.Picker.Visible = false
end

-- puts a card in the slot being picked (moving it if it was already on show)
function Profile:_pick(cardId: string)
	local slot = self._pickSlot
	if not slot then
		return
	end
	Sounds.Play("Click")
	local ids = table.clone(self:_ids())
	for i, id in ids do
		if id == cardId then
			ids[i] = ""
		end
	end
	ids[slot] = cardId
	self:_closePicker()
	self:_save(ids)
	local holder = self._frame.Panel.ShowcasePage.Showcase["Card" .. slot]
	Juice.Pop(holder, 0.12)
end

-- [[ Tabs ]]

function Profile:_setTab(name: string)
	self._tab = name
	local f = self._frame
	for _, tab in TABS do
		local on = tab == name
		local b = f.Tabs[tab]
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then INK else CREAM
		b.Visible = not (tab == "Titles" and self._viewing ~= nil) -- (you can't wear their titles)
		f.Panel[tab .. "Page"].Visible = on
	end
	if name ~= "Showcase" then
		self._editing = false
		self:_closePicker()
		self:_paintShowcase()
	end
	if name == "Stats" then
		self:_paintAllStats()
	elseif name == "Titles" then
		self:_paintTitles()
	end
end

function Profile:_paintAllStats()
	local page = self._frame.Panel.StatsPage
	page.Grid.Binder.Label.Text = if self._viewing then "VS YOU" else "BINDER"
	if self._viewing then
		local p = self._viewing
		local _, total = cardCount({})
		local wins, duels = num(p, "Wins"), num(p, "Duels")
		local values = {
			Wins = { commas(wins), if duels > 0 then `{math.floor(wins / duels * 100 + 0.5)}% win rate` else "no duels yet" },
			Duels = { commas(duels), "1v1 duels" },
			BestStreak = { commas(num(p, "BestStreak")), `now on {num(p, "Streak")}` },
			Perfect = { commas(num(p, "Perfect")), "7–0 wins" },
			Correct = { commas(num(p, "Correct")), "duels + solo" },
			SoloBest = { commas(num(p, "SoloBest")), "points in 7 rounds" },
			Cards = { `{commas(num(p, "CardsOwned"))}<font size="18"> / {commas(total)}</font>`, "different cards" },
			Binder = vsYou(p.UserId),
			Sets = { commas(num(p, "SetsDone")), if num(p, "AllKills") > 0 then `{num(p, "AllKills")} ALL-KILL` else "albums complete" },
		}
		for name, v in values do
			local tile = page.Grid[name]
			tile.Value.Text = v[1]
			tile.Sub.Text = v[2]
			local board = RANKS[name]
			local rank = board and rankOn(board, p.UserId)
			tile.Rank.Visible = rank ~= nil
			if rank then
				tile.Rank.Text = `#{rank} all time`
			end
		end
		return
	end
	local stats = PlayerData.Statistics
	local owned = cards()
	local have, total = cardCount(owned)
	local wins, duels = get(stats.Wins, 0), get(stats.Duels, 0)
	local sets = setsOf(owned)
	local allKills = 0
	for _, s in sets do
		allKills += if s.AllKill then 1 else 0
	end
	local rate = Albums.Rate(owned, bias(), get(PlayerData.Inventory.Pins, ""), Albums.Boost(PlayerData.GamePasses, Upgrades.Levels(PlayerData)), Upgrades.Levels(PlayerData))
	local values = {
		Wins = { commas(wins), if duels > 0 then `{math.floor(wins / duels * 100 + 0.5)}% win rate` else "no duels yet" },
		Duels = { commas(duels), `{commas(get(stats.Losses, 0))} lost · {commas(get(stats.Draws, 0))} drawn` },
		BestStreak = { commas(get(stats.HighestStreak, 0)), `now on {get(PlayerData.Player.Streak, 0)}` },
		Perfect = { commas(get(stats.PerfectGames, 0)), "7–0 wins" },
		Correct = { commas(get(stats.CorrectAnswers, 0)), "duels + solo" },
		SoloBest = { commas(get(stats.SoloBest2, 0)), "points in 7 rounds" },
		Cards = { `{commas(have)}<font size="18"> / {commas(total)}</font>`, "different cards" },
		Binder = { `{rateText(rate)}<font size="18"> /hr</font>`, "from your pins" },
		Sets = { commas(#sets), if allKills > 0 then `{allKills} ALL-KILL` else "albums complete" },
	}
	for name, v in values do
		local tile = page.Grid[name]
		tile.Value.Text = v[1]
		tile.Sub.Text = v[2]
		local board = RANKS[name]
		local rank = board and rankOn(board)
		tile.Rank.Visible = rank ~= nil
		if rank then
			tile.Rank.Text = `#{rank} all time`
		end
	end
end

-- [[ Titles tab (design board "49 · Profile · Titles tab with group badges") ]]
-- WEAR · Titles | Badges · Wearing <chip>. Titles: a chip per title you own (the default first),
-- tap to wear, the worn one ringed in mint. Badges: a row per group with a rung on either ladder
-- (Modules/Library/Ladders): cards and songs chips in fixed columns ("not started" / "no songs
-- yet" when there's none), Legend in the songs column once it's paid. Fandom titles (BLINK…)
-- aren't listed: a group's badge carries its fandom name now.

local NOT_STARTED_BG, NOT_STARTED_TEXT = Color3.fromHex("F3EEE0"), Color3.fromHex("9A93A8")
local FANDOM_NAMES = {}
for _, name in Packs.FANDOMS do
	FANDOM_NAMES[name] = true
end

-- a chip that isn't a badge yet: cream, muted text, no icon
local function paintEmpty(chip: TextLabel, label: string)
	TitleChip.Paint(chip, label, "Normal")
	chip.BackgroundColor3 = NOT_STARTED_BG
	chip.TextColor3 = NOT_STARTED_TEXT
	local icon = chip:FindFirstChild("BadgeIcon")
	if icon then
		icon.Visible = false
	end
	local pad = chip:FindFirstChildOfClass("UIPadding")
	if pad and pad:GetAttribute("BaseLeft") then
		pad.PaddingLeft = UDim.new(0, pad:GetAttribute("BaseLeft"))
	end
end

-- a group's photo for its badge row (its PackArt), "" if none
local function groupArt(artist: string): string
	for _, album in Albums.PullAlbums(artist) do
		if album.PackArt and album.PackArt ~= "" then
			return album.PackArt
		end
	end
	return ""
end

-- the titles you own (not fandom titles), the default first, then A–Z
function Profile:_titleList(): { { Title: string, Tier: string, Equipped: boolean } }
	local current = get(PlayerData.Inventory.Title, "")
	local tiers = get(PlayerData.Inventory.TitleTiers, {})
	local list = { { Title = "", Tier = "Normal", Equipped = current == "" } }
	local owned = get(PlayerData.Inventory.Titles, {})
	if type(owned) == "table" then
		for key, value in owned do
			local title = if type(key) == "string" then key else value
			if type(title) == "string" and title ~= "" and not FANDOM_NAMES[title] then
				table.insert(list, { Title = title, Tier = Cards.LEVELS[tiers[title] or 1] or "Normal", Equipped = current == title })
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.Title == "") ~= (b.Title == "") then
			return a.Title == ""
		end
		return a.Title:lower() < b.Title:lower()
	end)
	return list
end

-- every group with a rung on either ladder: { Artist, Cards, Songs, Legend, Best }
function Profile:_badgeList()
	local saved = get(PlayerData.Inventory.Ladders, {})
	local list = {}
	for _, artist in Ladders.Groups() do
		local c = saved[Ladders.Key("Cards", artist)] or 0
		local sg = saved[Ladders.Key("Songs", artist)] or 0
		local legend = (saved[Ladders.LegendKey(artist)] or 0) > 0
		if c > 0 or sg > 0 then
			table.insert(list, { Artist = artist, Cards = c, Songs = sg, Legend = legend, Best = if legend then 99 else math.max(c, sg) * 10 + math.min(c, sg) })
		end
	end
	local sort = self._badgeSort or "Best"
	if sort == "Legend" then
		local only = {}
		for _, b in list do
			if b.Legend then
				table.insert(only, b)
			end
		end
		list = only
	end
	table.sort(list, function(a, b)
		if sort == "Best" and a.Best ~= b.Best then
			return a.Best > b.Best
		end
		return Ladders.Fandom(a.Artist):lower() < Ladders.Fandom(b.Artist):lower()
	end)
	return list
end

-- the next rung to aim for in a group, as a line: "Next cards: every member Store+ · 2/4"
local function nextLine(artist: string, cardsRung: number, songsRung: number): string
	local cards = get(PlayerData.Inventory.Cards, {})
	local mastery = get(PlayerData.Inventory.Mastery, {})
	local _, nextCards = Ladders.CardsRung(cards, artist)
	local _, nextSongs = Ladders.SongsRung(mastery, artist)
	if cardsRung >= Ladders.TOP and songsRung >= Ladders.TOP then
		return "Legend: Diamond cards and Diamond songs"
	end
	local pick = if cardsRung <= songsRung or not Ladders.HasSongs(artist) then nextCards else nextSongs
	local which = if pick == nextCards then "cards" else "songs"
	if not pick then
		pick, which = nextSongs or nextCards, if nextSongs then "songs" else "cards"
	end
	if not pick then
		return ""
	end
	return `Next {which}: {pick.Text} · {pick.Have}/{pick.Need}`
end

function Profile:_paintTitles()
	local page = self._frame.Panel.TitlesPage
	local mode = self._wearMode or "Titles"
	local titles = self:_titleList()
	local badges = self:_badgeList()
	local current = get(PlayerData.Inventory.Title, "")

	-- the switch + what you're wearing
	for name, count in { Titles = #titles, Badges = #self:_allBadgeCount() } do
		local b = page.Mode[name]
		local on = name == mode
		b.Text = `{name} · {count}`
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then Color3.fromHex("FBF7F0") else Color3.fromHex("1E1B2E")
	end
	TitleChip.Paint(page.Wearing.Chip, LOCAL_PLAYER:GetAttribute("Title") or HUDConstants.DEFAULT_TITLE, LOCAL_PLAYER:GetAttribute("TitleTier") or "Normal", LOCAL_PLAYER:GetAttribute("TitleIcon"))
	page.Titles.Visible = mode == "Titles"
	page.Badges.Visible = mode == "Badges"

	-- Titles
	local list = page.Titles
	self._titleRows = self._titleRows or {}
	for i = 1, math.max(#titles, #self._titleRows) do
		local t = titles[i]
		local row = self._titleRows[i]
		if t and not row then
			row = list.Template:Clone()
			row.Name = `Title{i}`
			row.LayoutOrder = i
			row.Parent = list
			self._titleRows[i] = row
			local index = i
			row.Activated:Connect(function()
				local pick = self._titles and self._titles[index]
				if pick and not pick.Equipped then
					Sounds.Play("Click")
					ShopRemote:Fire({ Action = "EquipTitle", Id = pick.Title })
				end
			end)
		end
		if t then
			TitleChip.Paint(row.Chip, if t.Title == "" then HUDConstants.DEFAULT_TITLE else t.Title, t.Tier)
			row.Ring.Visible = t.Equipped
			row.Visible = true
		elseif row then
			row.Visible = false
		end
	end
	self._titles = titles
	list.Empty.Visible = #titles == 0

	-- Badges
	local blist = page.Badges.List
	for _, b in page.Badges.Sorts:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == (self._badgeSort or "Best")
			b.BackgroundColor3 = if on then Color3.fromHex("1E1B2E") else Color3.fromHex("FFFFFF")
			b.TextColor3 = if on then Color3.fromHex("FBF7F0") else Color3.fromHex("1E1B2E")
		end
	end
	self._badgeRows = self._badgeRows or {}
	for i = 1, math.max(#badges, #self._badgeRows) do
		local g = badges[i]
		local row = self._badgeRows[i]
		if g and not row then
			row = blist.Template:Clone()
			row.Name = `Group{i}`
			row.Parent = blist
			self._badgeRows[i] = row
			for _, ladder in { "Cards", "Songs" } do
				row.Face[ladder].Activated:Connect(function()
					local id = row.Face[ladder]:GetAttribute("Wear")
					if id and id ~= get(PlayerData.Inventory.Title, "") then
						Sounds.Play("Click")
						ShopRemote:Fire({ Action = "EquipTitle", Id = id })
					end
				end)
			end
		end
		if g then
			row.LayoutOrder = i
			local face = row.Face
			local art = groupArt(g.Artist)
			face.Icon.Image = art
			face.Icon.Initial.Visible = art == ""
			face.Icon.Initial.Text = string.upper(string.sub(g.Artist, 1, 1))
			face.GroupName.Text = if Ladders.Fandom(g.Artist) ~= g.Artist then `{g.Artist} · {Ladders.Fandom(g.Artist)}` else g.Artist
			face.Sub.Text = nextLine(g.Artist, g.Cards, g.Songs)
			-- cards
			local cardsId = Ladders.TitleId("Cards", g.Artist)
			if g.Cards > 0 then
				TitleChip.Paint(face.Cards.Chip, string.upper(Ladders.RUNGS[g.Cards]), `Rung:{Ladders.RUNGS[g.Cards]}`, "Cards")
				face.Cards:SetAttribute("Wear", cardsId)
			else
				paintEmpty(face.Cards.Chip, "not started")
				face.Cards:SetAttribute("Wear", nil)
			end
			face.Cards.Ring.Visible = current == cardsId
			-- songs (or Legend)
			local songsId = Ladders.TitleId(if g.Legend then "Legend" else "Songs", g.Artist)
			if g.Legend then
				TitleChip.Paint(face.Songs.Chip, "LEGEND", "Rung:Legend")
				face.Songs:SetAttribute("Wear", songsId)
			elseif g.Songs > 0 then
				TitleChip.Paint(face.Songs.Chip, string.upper(Ladders.RUNGS[g.Songs]), `Rung:{Ladders.RUNGS[g.Songs]}`, "Songs")
				face.Songs:SetAttribute("Wear", songsId)
			else
				paintEmpty(face.Songs.Chip, if Ladders.HasSongs(g.Artist) then "not started" else "no songs yet")
				face.Songs:SetAttribute("Wear", nil)
			end
			face.Songs.Ring.Visible = current == songsId or (current == Ladders.TitleId("Songs", g.Artist))
			row.Visible = true
		elseif row then
			row.Visible = false
		end
	end
	blist.Empty.Visible = #badges == 0
end

-- every badge you hold (each ladder's rung + each Legend), for the switch's count
function Profile:_allBadgeCount(): { string }
	local out = {}
	for key, rung in get(PlayerData.Inventory.Ladders, {}) do
		local _, artist = Ladders.ParseKey(key)
		if type(rung) == "number" and rung > 0 and artist and Ladders.Eligible(artist) then
			table.insert(out, key)
		end
	end
	return out
end

function Profile:_refresh()
	self:_paintCard()
	self:_paintStats()
	self:_paintShowcase()
	if self._tab == "Stats" then
		self:_paintAllStats()
	elseif self._tab == "Titles" then
		self:_paintTitles()
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function Profile:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Profile")
	self._frame.Visible = false
	local f = self._frame
	ButtonScale.ApplyToDescendants(f.Left)
	ButtonScale.ApplyToDescendants(f.Panel)
	ButtonScale.Apply(f.Close)
	ButtonScale.Apply(f.Picker.Sheet.Close)
	local j = self._janitor
	local panel = f.Panel.ShowcasePage

	j:Add(f.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(f.Left.ChangeTitle.Activated:Connect(function()
		self:_setTab("Titles")
	end))
	for _, tab in TABS do
		j:Add(f.Tabs[tab].Activated:Connect(function()
			if self._tab ~= tab then
				Sounds.Play("Click")
				self:_setTab(tab)
			end
		end))
	end
	j:Add(f.Left.StyleButton.Activated:Connect(function()
		self._interface:Open("Banners")
	end))
	-- the Titles tab's Titles / Badges switch and the badge sorts (board 49)
	local titlesPage = f.Panel.TitlesPage
	for _, name in { "Titles", "Badges" } do
		j:Add(titlesPage.Mode[name].Activated:Connect(function()
			if self._wearMode ~= name then
				Sounds.Play("Click")
				self._wearMode = name
				self:_paintTitles()
			end
		end))
	end
	for _, b in titlesPage.Badges.Sorts:GetChildren() do
		if b:IsA("TextButton") then
			j:Add(b.Activated:Connect(function()
				if (self._badgeSort or "Best") ~= b.Name then
					Sounds.Play("Click")
					self._badgeSort = b.Name
					self:_paintTitles()
					titlesPage.Badges.List.CanvasPosition = Vector2.zero
				end
			end))
		end
	end
	-- Edit / Done
	j:Add(panel.Edit.Activated:Connect(function()
		self._editing = not self._editing
		self:_paintShowcase()
		if self._editing then
			local showcase = panel.Showcase
			Juice.Stagger({ showcase.Card1, showcase.Card2, showcase.Card3, showcase.Card4, showcase.Card5 }, 0.04)
		end
	end))
	for i = 1, SLOTS do
		local holder = panel.Showcase["Card" .. i]
		-- a slot: pick its card
		j:Add(holder.Hit.Activated:Connect(function()
			Sounds.Play("Click")
			Juice.Pop(holder, 0.1)
			self:_openPicker(i)
		end))
		-- ✕: empty the slot (the others stay where they are)
		j:Add(holder.Unpin.Activated:Connect(function()
			local ids = table.clone(self:_ids())
			ids[i] = ""
			self:_save(ids)
		end))
	end
	-- someone else's profile
	local actions = f.Left.Actions
	j:Add(actions.Duel.Activated:Connect(function()
		local p = self._viewing
		if not p or not actions.Duel.Active then
			return
		end
		InviteRemote:Fire({ Action = "Challenge", Target = p.UserId })
		self._note = "SENDING…"
		self:_paintActions()
	end))
	j:Add(InviteRemote:Connect(function(packet)
		if type(packet) ~= "table" or self.State == "Inactive" or not self._viewing then
			return
		end
		if packet.Message == "Sent" then
			self._note = nil
			self._interface:Close(self.Name) -- you're on a stage now: the queue card shows the invite
		elseif packet.Message == "Result" then
			if packet.Result == "NoStage" then
				self:_flash("NO FREE STAGES")
			elseif packet.Result == "Failed" then
				self:_flash("CAN'T DUEL RIGHT NOW")
			end
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy
	j:Add(actions.AddFriend.Activated:Connect(function()
		local p = self._viewing
		if p and p.Parent then
			pcall(StarterGui.SetCore, StarterGui, "PromptSendFriendRequest", p)
		end
	end))
	j:Add(actions.Gift.Activated:Connect(function()
		local p = self._viewing
		local shop = self._interface:GetController("Shop")
		if not p or not shop then
			return
		end
		self._interface:Close(self.Name)
		self._interface:Open("Shop")
		shop:StartGift(p.UserId)
	end))
	j:Add(Players.PlayerRemoving:Connect(function(player: Player)
		if player == self._viewing and self.State ~= "Inactive" then
			self._interface:Close(self.Name)
		end
	end))

	j:Add(f.Picker.Sheet.Close.Activated:Connect(function()
		self:_closePicker()
	end))
	j:Add(f.Picker.Dim.Activated:Connect(function()
		self:_closePicker()
	end))

	-- redraw while open when anything shown changes
	local function changed()
		if self.State ~= "Inactive" then
			self:_refresh()
		end
	end
	local stats = PlayerData.Statistics
	for _, path in {
		PlayerData.Player.XP, PlayerData.Player.Streak, stats.Wins, stats.Duels, stats.HighestStreak,
		PlayerData.Inventory.Cards, PlayerData.Inventory.Bias, PlayerData.Inventory.Pins, PlayerData.Profile.Cards,
		PlayerData.Inventory.Title, PlayerData.Inventory.Titles, PlayerData.Inventory.Ladders,
	} do
		j:Add(path.Observe(changed))
	end
	j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("Title"):Connect(changed))
	j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("TitleTier"):Connect(changed))
	-- Studio only: the LocalPlayer's "ProfileTest" attribute opens yours as others see it
	if RunService:IsStudio() then
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("ProfileTest"):Connect(function()
			if LOCAL_PLAYER:GetAttribute("ProfileTest") then
				self._interface:Open(self.Name, { Player = LOCAL_PLAYER, Preview = true })
			end
		end))
	end
	for _, attribute in { "InDuel", "PartyStage" } do
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal(attribute):Connect(function()
			if self._viewing and self.State ~= "Inactive" then
				self:_paintActions()
			end
		end))
	end
end

function Profile:Activate(opts: any?)
	self._editing = false
	self:_closePicker()
	-- someone else's: { Player = player }
	local who = type(opts) == "table" and opts.Player
	-- (Studio: { Player = you, Preview = true } shows yours the way others see it)
	local preview = type(opts) == "table" and opts.Preview == true and RunService:IsStudio()
	self._viewing = if typeof(who) == "Instance" and who:IsA("Player") and (who ~= LOCAL_PLAYER or preview) and who.Parent then who else nil
	self._note = nil
	self._watch:Cleanup()
	if self._viewing then
		for _, attribute in WATCH do
			self._watch:Add(self._viewing:GetAttributeChangedSignal(attribute):Connect(function()
				if self.State ~= "Inactive" then
					self:_refresh()
				end
			end))
		end
	end
	self._frame.Visible = true
	-- opts.Tab = "Stats" | "Titles" opens on that tab (Showcase by default)
	local tab = if type(opts) == "table" and table.find(TABS, opts.Tab) then opts.Tab else "Showcase"
	self:_setTab(tab)
	self:_refresh()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local panel = self._frame.Panel.ShowcasePage
	local list = {}
	for i = 1, SLOTS do
		table.insert(list, panel.Showcase["Card" .. i])
	end
	for _, spec in Build.FS_STATS do
		table.insert(list, panel.Stats[spec.Name])
	end
	Juice.Stagger(list, 0.04)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Profile:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self:_closePicker()
	self._watch:Cleanup()
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self._viewing = nil
		self.State = "Inactive"
	end)
end

function Profile:Destroy()
	self._watch:Destroy()
	self._janitor:Destroy()
end

return Profile
