--| ScreenGuide · Guides
-- What each screen's first-open guide says, step by step (design boards "Roll guide 1–3"; the
-- rest reuse that look). Keyed by the controller's Name, or for a screen with pages by the key
-- its controller passes (PartyController: "PartyHost" / "PartyGuest" / "PartySettings" /
-- "PartySongs"). Each guide:
--   Hint      the Settings.Hints id it's saved under once seen (SettingsService HINTS, ≤ 16 chars)
--   When      optional (args, controller) -> bool: false skips it this time (the screen
--             opened for something else, like the Index's card upgrade reveal); it shows next time
--   Ready     optional (frame, controller) -> bool: wait for this before showing (a screen that
--             fills in after it opens); not ready within 5 s = try again next open
--   Steps     in order. Each step:
--     Target   (frame) -> GuiObject | { GuiObject }: what's lit (the screen's own frame is
--              passed in); a list is lit as one box round the visible ones
--     Side     where the bubble sits: "Left" | "Right" | "Below" | "Above" of the target
--     Title, Body          rich text
--     Ladder   true: the Normal › Gold › Rainbow cards with the copies each needs
--     Heading  optional small caps line above Points / Tiles
--     Points   up to 3 { Colour, Text }: a swatch and a line of rich text
--     Tiles    up to 3 { Colour, Name, Text }: little coloured cards in a row
--     Prepare  optional (frame) -> cleanup?: run before the step shows; the cleanup runs
--              when the step ends
-- Numbers come from the constants, so the text stays true if they're retuned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollConstants = require(ReplicatedStorage.Constants.RollConstants)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local DailySongConstants = require(ReplicatedStorage.Constants.DailySongConstants)
local PartyConstants = require(ReplicatedStorage.Constants.PartyConstants)

local C = Color3.fromHex
local MINT = C("A7E9B8")
local BLUE = C("9ED8F5")
local PINK = C("FF9EC4")
local YELLOW = C("FFE07A")
local LILAC = C("B9A6FF")
local PEACH = C("FFB38A")

local function rollPage(frame)
	return frame.Panel.Pages.Roll
end

local function dailyPlay(frame)
	return frame.Panel.Body.Play
end

local TRIES = #DailySongConstants.TIERS
local FFA_LOW = PartyConstants.FFA_MULTIPLIER[PartyConstants.MIN_SPOTS]
local FFA_HIGH = PartyConstants.FFA_MULTIPLIER[PartyConstants.MAX_SPOTS]

-- "0.1 s" / "15 s"
local function secs(n: number): string
	return `{n} s`
end

local function isHost(controller): boolean
	return controller._isHost ~= nil and controller:_isHost()
end

return {
	Roll = {
		Hint = "GuideRoll",
		-- not when Roll opened to play a card upgrade's reveal or straight into Pick a Group
		When = function(args)
			local opts = args[1]
			return not (type(opts) == "table" and (opts.Upgrade or opts.Picker))
		end,
		Steps = {
			{
				Target = function(frame)
					return rollPage(frame).Stage
				end,
				Side = "Left",
				Title = "Roll for songs!",
				Body = "Every roll pulls a random song card. New songs go in your <b>Index</b>.",
				Points = {
					{ Colour = MINT, Text = `Duplicates give <b>{RollConstants.DUPLICATE_REFUND} coins</b> back` },
					{ Colour = BLUE, Text = `{RollConstants.PITY} duplicates in a row? The next one is <b>new</b>` },
				},
			},
			{
				Target = function(frame)
					return rollPage(frame).Stage.Deck
				end,
				Side = "Left",
				Title = "Aim for Rainbow!",
				Body = "Pull the same song again and its card levels up.",
				Ladder = true,
				Heading = "WHY RAINBOW",
				Points = {
					{ Colour = PINK, Text = `<b>{DuelConstants.OWNED_WEIGHT.Rainbow}× as likely</b> to come up in your duels: a song you know is easy points` },
					{ Colour = BLUE, Text = "<b>Lobby music:</b> set any Rainbow card as your background song" },
					{ Colour = YELLOW, Text = "<b>Fandom title:</b> get a whole group to Rainbow for its Rainbow title" },
				},
			},
			{
				Target = function(frame)
					return frame.Panel.Header.Tickets
				end,
				Side = "Below",
				Title = "Roll tickets",
				Body = "A ticket rolls one song from <b>a group you pick</b>, so you can finish your bias's set. When you have one, <b>ROLL A GROUP</b> shows up under the roll buttons.",
				Heading = "WHERE TO GET THEM",
				Tiles = {
					{ Colour = YELLOW, Name = "Level up", Text = "Level rewards" },
					{ Colour = MINT, Name = "Quests", Text = "Daily + weekly quests" },
					{ Colour = PINK, Name = "Shop", Text = "Ticket bundles" },
				},
			},
		},
	},

	-- [[ Daily Song: the first time you play one ]]
	DailySong = {
		Hint = "GuideDaily",
		-- only on the play view (not on a day you've already finished)
		Ready = function(frame)
			return dailyPlay(frame).Visible
		end,
		Steps = {
			{
				Target = function(frame)
					return dailyPlay(frame).Mystery
				end,
				Side = "Right",
				Title = "One song for everyone",
				Body = "Everyone gets the <b>same mystery song</b> today, and a new one every day. Press play to hear the clip.",
				Points = {
					{ Colour = MINT, Text = `You get <b>{TRIES} tries</b>` },
					{ Colour = PINK, Text = "Solve it every day for your <b>Daily streak</b> (separate from your duel streak)" },
				},
			},
			{
				Target = function(frame)
					return dailyPlay(frame).Ladder
				end,
				Side = "Right",
				Title = "Every miss plays more",
				Body = `A wrong guess or a skip unlocks a longer clip, from {secs(DailySongConstants.TIERS[1])} up to {secs(DailySongConstants.TIERS[TRIES])}. The sooner you get it, the more coins: <b>{DailySongConstants.COINS[1]}</b> on the first try, down to <b>{DailySongConstants.COINS[TRIES]}</b> on the last.`,
			},
			{
				Target = function(frame)
					return dailyPlay(frame).Guesses.SearchBox
				end,
				Side = "Above",
				Title = "Type to guess",
				Body = "Start typing a song or a group, then pick it from the list and press <b>GUESS</b>. Not sure? <b>Skip</b> to hear more.",
				Points = {
					{ Colour = YELLOW, Text = "Solved? <b>Share</b> your squares in chat (no spoilers)" },
					{ Colour = BLUE, Text = "Solve it 5 days in a week for a <b>weekly quest</b>" },
				},
			},
		},
	},

	-- [[ Party Stages: the lobby card (host / guest), Stage settings and Pick songs ]]
	PartyHost = {
		Hint = "GuidePartyHost",
		When = function(_, controller)
			return isHost(controller)
		end,
		Steps = {
			{
				Target = function(frame)
					return frame.Lobby.Setlist
				end,
				Side = "Above",
				Title = "You're the host!",
				Body = "Whoever's <b>#1</b> on the setlist hosts: you pick how this stage plays. If you leave, #2 takes over.",
				Points = {
					{ Colour = LILAC, Text = "Tap a <b>player</b> to make them host or remove them" },
					{ Colour = MINT, Text = "Tap an <b>open spot</b> to invite someone" },
				},
			},
			{
				Target = function(frame)
					return frame.Lobby.Settings
				end,
				Side = "Right",
				Title = "Settings",
				Body = "Pick <b>1v1 or free-for-all</b>, which <b>songs</b> can come up, how many <b>spots</b> and who can join. The line under the button shows what's set now.",
			},
			{
				Target = function(frame)
					return frame.Lobby.Start
				end,
				Side = "Above",
				Title = "Start when they're ready",
				Body = `Everyone else presses <b>READY UP</b>. START runs a {PartyConstants.COUNTDOWN} s countdown, and anyone un-readying stops it.`,
			},
		},
	},
	PartyGuest = {
		Hint = "GuidePartyGuest",
		When = function(_, controller)
			return not isHost(controller)
		end,
		Steps = {
			{
				Target = function(frame)
					return frame.Lobby.Ready
				end,
				Side = "Above",
				Title = "Ready up!",
				Body = "The host (<b>#1</b> on the setlist) picks the settings and starts the match. Press <b>READY UP</b> so they know you're in.",
			},
		},
	},
	PartySettings = {
		Hint = "GuidePartySet",
		When = function(_, controller)
			return isHost(controller)
		end,
		Steps = {
			{
				Target = function(frame)
					return frame.Settings.Mode
				end,
				Side = "Below",
				Title = "How you play",
				Body = `<b>1v1 Duel</b>: exactly 2 players. <b>Free-for-all</b>: {PartyConstants.MIN_FFA_PLAYERS}–{PartyConstants.MAX_SPOTS} players, everyone on their own score.`,
				Points = {
					{ Colour = YELLOW, Text = `Free-for-all pays more the more players start: <b>×{FFA_LOW}</b> up to <b>×{FFA_HIGH}</b> coins` },
					{ Colour = MINT, Text = "Every change saves straight away: everyone sees it" },
				},
			},
			{
				Target = function(frame)
					return frame.Settings.SongsRow
				end,
				Side = "Below",
				Title = "Songs",
				Body = "Every song by default. Tap <b>Edit</b> to pick gens and groups, or take out single songs.",
				Points = {
					{ Colour = PEACH, Text = `A custom pick pays <b>×{PartyConstants.CUSTOM_POOL_MULTIPLIER}</b> coins` },
					{ Colour = PINK, Text = `Under <b>{PartyConstants.MIN_POOL_REWARDS} songs</b>: no coins or XP` },
				},
			},
			{
				Target = function(frame)
					return frame.Settings.OwnedRow
				end,
				Side = "Below",
				Title = "Owned songs count",
				Body = "<b>On</b>: songs players own come up more often, like in normal duels (it helps whoever owns more). <b>Off</b>: every song has the same chance.",
			},
			{
				Target = function(frame)
					return frame.Settings.SpotsRow
				end,
				Side = "Below",
				Title = "Spots",
				Body = `How many can join: <b>{PartyConstants.MIN_SPOTS}–{PartyConstants.MAX_SPOTS}</b> for free-for-all (never fewer than are already on the stage). A duel is always {PartyConstants.DUEL_SPOTS}.`,
			},
			{
				Target = function(frame)
					return frame.Settings.Every
				end,
				Side = "Above",
				Title = "Who gets in",
				Body = "Who can join your stage, and who can watch.",
				Points = {
					{ Colour = BLUE, Text = "<b>Friends only</b>: friends and players you invite. Anyone else can ask to join" },
					{ Colour = LILAC, Text = "<b>Spectators</b>: others can watch when the stage is full or playing" },
				},
			},
		},
	},
	PartySongs = {
		Hint = "GuidePartySongs",
		Steps = {
			{
				Target = function(frame)
					return frame.Songs.View
				end,
				Side = "Below",
				Title = "Two ways to pick",
				Body = "<b>Gens + groups</b> switches whole groups on or off. <b>Songs</b> lets you take single songs out of the groups that are on.",
			},
			{
				-- the gen tiles + the group chips showing (GensView itself runs on past them)
				Target = function(frame)
					local view = frame.Songs.GensView
					local parts = { view.Gen1, view.Gen2, view.Gen3, view.Gen4, view.AllOff }
					for _, chip in view.Chips:GetChildren() do
						if chip:IsA("GuiButton") then
							table.insert(parts, chip)
						end
					end
					return parts
				end,
				Side = "Below",
				Title = "Gens and groups",
				Body = "Tap a <b>gen</b> to see its groups, then tap a <b>group</b> to switch it on or off. <b>All on</b> / <b>All off</b> do the whole gen.",
			},
			{
				Target = function(frame)
					return frame.Songs.Save
				end,
				Side = "Above",
				Title = "Save your pick",
				Body = "Nothing changes until you press <b>SAVE</b>. Back throws your changes away.",
				Points = {
					{ Colour = MINT, Text = `At least <b>{PartyConstants.MIN_POOL} songs</b> to save, <b>{PartyConstants.MIN_POOL_REWARDS}+</b> to keep coins + XP` },
					{ Colour = PEACH, Text = `A custom pick pays <b>×{PartyConstants.CUSTOM_POOL_MULTIPLIER}</b> coins` },
				},
			},
		},
	},
}
