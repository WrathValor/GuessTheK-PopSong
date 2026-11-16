--| ReferralConstants
-- Invite friends (design boards "Invite friends", "Invite button on the HUD", "Referral
-- moments" and "Squad · referral banner + photocard"). A brand-new player who joins from
-- someone's invite (or their share link) gets FRIEND_GIFT straight away; once they finish
-- their first game (a duel, solo practice or the tutorial) the inviter gets INVITER_GIFT and
-- a step towards the MILESTONES, which are claimed on the Invite Friends screen. Each new
-- player counts once, for one inviter. Server: Engine/ReferralService. Client:
-- InterfaceController/Controllers/InviteController (+ InvitedController for the welcome card).

local ReferralConstants = {}

ReferralConstants.FRIEND_GIFT = 500 -- coins for the friend who joined, once
ReferralConstants.INVITER_GIFT = 300 -- coins for the inviter, per friend who plays a game

-- Claimed on the Invite Friends screen once that many friends have played. Key is what
-- PlayerData Referral.Claimed stores. Colour = the card, ArtBg = its art box (the board's).
-- A milestone gives every reward it lists: Title, Mic / Stage (ShopCatalog ids, Reward =
-- "Referral" there), Banner + Photocard (SeasonConstants ids).
ReferralConstants.MILESTONES = table.freeze({
	table.freeze({ Need = 1, Key = "1", Text = "Title: Plus One", Title = "Plus One", Colour = "FFE07A", ArtBg = "FFFFFF" }),
	table.freeze({ Need = 3, Key = "3", Text = "Friendship mic", Mic = "FriendshipMic", Colour = "9ED8F5", ArtBg = "E6F6FF" }),
	table.freeze({ Need = 5, Key = "5", Text = "Friendship platform", Stage = "FriendshipStage", Colour = "A7E9B8", ArtBg = "E8FFF0" }),
	table.freeze({ Need = 10, Key = "10", Text = "Squad banner + photocard", Banner = "Squad", Photocard = "Squad", Colour = "FF9EC4", ArtBg = "FFE8F2" }),
})
ReferralConstants.MAX = 10 -- the last milestone (the track on the screen is out of this)

-- the Invite Friends screen lists this many friends (newest first; no scrolling)
ReferralConstants.FRIENDS_SHOWN = 3

-- the line Roblox's invite pop-up sends with the invite
ReferralConstants.INVITE_MESSAGE = "Come guess K-pop songs with me!"

-- [[ Server ]]
-- each inviter's friends live in this DataStore (key = the inviter's UserId), so a friend in
-- another server, or while the inviter is offline, still counts
ReferralConstants.STORE = "Referrals_v1"
ReferralConstants.TOPIC = "Referral" -- MessagingService: "inviter X, check your friends"
ReferralConstants.MAX_RECORDS = 100 -- friends kept per inviter (oldest who never played go first)
ReferralConstants.SYNC_SECONDS = 120 -- online inviters re-read their friends this often
ReferralConstants.CHECK_SECONDS = 5 -- how often a referred player's first game is looked for

-- Studio only: a test player counts as referred by this UserId (0 = off), so the welcome
-- card and the first-game credit can be tried without a real invite
ReferralConstants.STUDIO_INVITER = 0

-- a milestone by its Need (nil if there's none)
function ReferralConstants.Milestone(need: number)
	for _, m in ReferralConstants.MILESTONES do
		if m.Need == need then
			return m
		end
	end
	return nil
end

-- the next milestone not yet reached with `played` friends (nil once all are)
function ReferralConstants.Next(played: number)
	for _, m in ReferralConstants.MILESTONES do
		if played < m.Need then
			return m
		end
	end
	return nil
end

return table.freeze(ReferralConstants)
