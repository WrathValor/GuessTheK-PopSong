--| InviteController
-- The Invite Friends screen (design board "Invite friends"; built by ./Build) and the bits of
-- the referral flow that live outside it (Engine/ReferralService, Constants/ReferralConstants):
--   • HUD.Buttons.Invite (right side, under News + Settings) opens the screen; its red CLAIM
--     badge shows while a milestone is ready
--   • INVITE FRIENDS opens Roblox's invite pop-up, with LaunchData "ref:<your UserId>" so a
--     new player who joins from it counts for you
--   • the milestones: the track, "n / 10", and each card's CLAIM! / "n / need friends" /
--     Claimed (ReferralRemote Claim; the reward reveal is PurchasedController's)
--   • "Your friends": the newest FRIENDS_SHOWN, Played · +300 or Joined · needs 1 game
--   • Frames.FriendToast: "<friend> played!" + the coins, when the server pays for a friend
--     (now, or the next time you join if it happened while you were away)
--   Interface:Open("Invite")

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ReferralConstants = require(ReplicatedStorage.Constants.ReferralConstants)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ReferralRemote = Bridgenet.ReferenceBridge("ReferralRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local CREAM_YELLOW = C("FFF6D6")
local CREAM = C("FBF7F0")
local CLAIMED = C("CFC5B3")
local MUTED = C("5C566B")
local AVATAR_COLOURS = { C("FFD2CE"), C("9ED8F5"), C("B9A6FF"), C("A7E9B8"), C("FFE07A") }

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOAST_HOLD = 4 -- seconds each "played!" toast stays

-- --------------------------------- Helpers -------------------------------- --
local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

local function has(path, key: string): boolean
	local ok, yes = pcall(path.Has, key)
	return ok and yes == true
end

-- friends who've played (and been paid for): the milestone count
local function played(): number
	local list = get(PlayerData.Referral.Paid, {})
	return if type(list) == "table" then #list else 0
end

local function headshot(userId: number?): string
	if not userId or userId <= 0 then
		return ""
	end
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- a milestone that's reached and not claimed yet
local function anyReady(n: number): boolean
	for _, m in ReferralConstants.MILESTONES do
		if n >= m.Need and not has(PlayerData.Referral.Claimed, m.Key) then
			return true
		end
	end
	return false
end

-- ---------------------------------- Class --------------------------------- --
local Invite = {}
Invite.__index = Invite

function Invite.new()
	local self = setmetatable({}, Invite)
	self.Name = "Invite"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._friends = {} :: { any }
	self._claiming = {} :: { [number]: boolean }
	self._toasts = {} :: { any }
	self._toasting = false
	return (self :: any) :: UITypes.Controller
end

function Invite:Initialize(interface)
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "Invite")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel
	local right = panel.Content.Right

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(panel.Content.How.InviteButton.Activated:Connect(function()
		self:_prompt()
	end))
	for _, m in ReferralConstants.MILESTONES do
		local face = right.Milestones["M" .. m.Key].Face
		j:Add(face.Claim.Activated:Connect(function()
			self:_claim(m)
		end))
	end

	-- the HUD button (HUD.Buttons.Invite, right side under News + Settings: ./Build.HUDButton)
	local screenGui = interface.PlayerGui:WaitForChild("Interface")
	local hud = screenGui:WaitForChild("HUD")
	local hudButton = hud:FindFirstChild("Buttons") and hud.Buttons:FindFirstChild("Invite")
	self._hudButton = hudButton
	if hudButton then
		j:Add(hudButton.Activated:Connect(function()
			if self._interface.Mode == "Gameplay" then
				self._interface:Open(self.Name)
			end
		end))
	end

	-- the "played!" toast
	self._toast = screenGui.Frames:FindFirstChild("FriendToast")
	if self._toast then
		self._toast.Visible = false
	end

	j:Add(ReferralRemote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Message == "State" then
			self._friends = if type(packet.Friends) == "table" then packet.Friends else {}
			self:_paint()
		elseif packet.Message == "Paid" then
			for _, f in (if type(packet.Friends) == "table" then packet.Friends else {}) do
				table.insert(self._toasts, f)
			end
			self:_nextToast()
		elseif packet.Message == "Claimed" then
			local need = packet.Need
			if type(need) == "number" then
				self._claiming[need] = nil
			end
			if not packet.Ok and type(need) == "number" then
				local m = ReferralConstants.Milestone(need)
				local face = m and right.Milestones["M" .. m.Key].Face
				if face then
					Juice.Shake(face.Claim, 0.4)
				end
			end
			self:_paint()
		end
	end), "Disconnect")

	-- the badge + the cards follow the saved data
	local function refresh()
		self:_badge()
		if self._frame.Visible then
			self:_paint()
		end
	end
	for _, path in { PlayerData.Referral.Paid, PlayerData.Referral.Claimed } do
		local ok, conn = pcall(path.Observe, refresh)
		if ok and conn then
			j:Add(conn)
		end
	end
	refresh()
end

-- [[ Invite pop-up ]]

function Invite:_prompt()
	task.spawn(function()
		local okCan, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, LOCAL_PLAYER)
		if not okCan or not can then
			AnalyticsClient.Event("InvitePrompt", 1, "Unavailable")
			Juice.Shake(self._frame.Panel.Content.How.InviteButton, 0.4)
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = ReferralConstants.INVITE_MESSAGE
		options.LaunchData = `ref:{LOCAL_PLAYER.UserId}`
		local ok = pcall(SocialService.PromptGameInvite, SocialService, LOCAL_PLAYER, options)
		AnalyticsClient.Event("InvitePrompt", 1, if ok then "Opened" else "Unavailable")
	end)
end

-- [[ Claims ]]

function Invite:_claim(m)
	if self._claiming[m.Need] or has(PlayerData.Referral.Claimed, m.Key) then
		return
	end
	if played() < m.Need then
		local face = self._frame.Panel.Content.Right.Milestones["M" .. m.Key].Face
		Juice.Shake(face.Claim, 0.4)
		return
	end
	self._claiming[m.Need] = true
	Sounds.Play("Success")
	ReferralRemote:Fire({ Action = "Claim", Need = m.Need })
end

-- [[ Painting ]]

function Invite:_badge()
	local b = self._hudButton
	local badge = b and b:FindFirstChild("ClaimBadge")
	if not badge then
		return
	end
	local ready = anyReady(played())
	if ready and not badge.Visible then
		Juice.Pop(badge, 0.25)
	end
	badge.Visible = ready
	-- (the +300 sticker shares the corner: CLAIM takes its place)
	local sticker = b:FindFirstChild("Sticker")
	if sticker then
		sticker.Visible = not ready
	end
end

function Invite:_paintMilestones(n: number)
	local right = self._frame.Panel.Content.Right
	right.MilestonesHead.Count.Text = `{math.min(n, ReferralConstants.MAX)} / {ReferralConstants.MAX}`
	TweenService:Create(right.Track.Fill, FILL_TWEEN, { Size = UDim2.fromScale(math.clamp(n / ReferralConstants.MAX, 0, 1), 1) }):Play()

	for _, m in ReferralConstants.MILESTONES do
		local holder = right.Milestones["M" .. m.Key]
		local face = holder.Face
		local claimed = has(PlayerData.Referral.Claimed, m.Key)
		local ready = n >= m.Need and not claimed
		local claim = face.Claim
		claim.Text = if claimed then "Claimed" elseif ready then "CLAIM!" else `{math.min(n, m.Need)} / {m.Need} friends`
		claim.BackgroundColor3 = if claimed then CLAIMED elseif ready then YELLOW else WHITE
		claim.TextColor3 = if ready then INK else MUTED
		face.ClaimShadow.Visible = ready
		-- a claimed card fades back a little (its colour washed towards cream; the face stays
		-- solid so the shadow behind it can't show through); one out of reach shows its art softer
		face.BackgroundColor3 = if claimed then C(m.Colour):Lerp(CREAM, 0.55) else C(m.Colour)
		face.Art.BackgroundTransparency = if n >= m.Need then 0 else 0.25

		-- the art: the real mic / platform, the Squad banner + photocard
		local art = face.Art
		if m.Mic then
			CosmeticView.Show(art, "Mic", m.Mic)
		elseif m.Stage then
			CosmeticView.Show(art, "Stage", m.Stage)
		elseif m.Banner and art:GetAttribute("Shown") ~= m.Banner then
			-- the shop's way (ShopController:_fillStyle): banner, your avatar in the photocard
			art:SetAttribute("Shown", m.Banner)
			SeasonArt.PaintBanner(art.Banner, m.Banner)
			local avatar = art.Card.Photo:FindFirstChild("Avatar")
			if avatar then
				avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
			end
			SeasonArt.PaintPhotocard(art.Card, m.Photocard)
			art.BackgroundColor3 = SeasonConstants.Banner(m.Banner).Fill
		end
	end
end

function Invite:_paintFriends()
	local list = self._frame.Panel.Content.Right.Friends
	local friends = self._friends
	local shown = math.min(#friends, ReferralConstants.FRIENDS_SHOWN)
	list.Empty.Visible = #friends == 0
	for i = 1, ReferralConstants.FRIENDS_SHOWN do
		local row = list["Row" .. i]
		local f = friends[i]
		row.Visible = f ~= nil
		if f then
			row.FriendName.Text = f.Name or "A friend"
			row.Avatar.Image = headshot(f.UserId)
			row.Avatar.BackgroundColor3 = AVATAR_COLOURS[((f.UserId or i) % #AVATAR_COLOURS) + 1]
			row.Status.Text = if f.Played then `Played · +{ReferralConstants.INVITER_GIFT}` else "Joined · needs 1 game"
			row.Status.BackgroundColor3 = if f.Played then MINT else CREAM_YELLOW
		end
	end
	list.More.Visible = #friends > shown
	list.More.Text = `and {#friends - shown} more`
end

function Invite:_paint()
	local n = played()
	local chip = self._frame.Panel.Header.Left.PlayedChip
	chip.Label.Text = if n == 1 then "1 friend played" else `{n} friends played`
	self:_paintMilestones(n)
	self:_paintFriends()
	self:_badge()
end

-- [[ "<friend> played!" toasts, one after another ]]

function Invite:_nextToast()
	local toast = self._toast
	if self._toasting or not toast then
		return
	end
	local f = table.remove(self._toasts, 1)
	if not f then
		return
	end
	self._toasting = true
	local face = toast.Face
	local n = played()
	local nextUp = ReferralConstants.Next(n)
	face.Title.Text = `{f.Name or "A friend"} played!`
	face.Sub.Text = `Friends: {math.min(n, ReferralConstants.MAX)} / {ReferralConstants.MAX}` .. (if nextUp then ` · next: {nextUp.Text}` else "")
	face.Avatar.Image = headshot(f.UserId)
	face.Amount.Text = `+{ReferralConstants.INVITER_GIFT}`
	toast.Visible = true
	Juice.SlideIn(toast, -40)
	Sounds.Play("Coins")
	task.delay(TOAST_HOLD, function()
		toast.Visible = false
		self._toasting = false
		self:_nextToast()
	end)
end

-- [[ Lifecycle ]]

function Invite:Activate()
	self._frame.Visible = true
	self:_paint()
	ReferralRemote:Fire({ Action = "State" })
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local cards = {}
	for _, m in ReferralConstants.MILESTONES do
		table.insert(cards, self._frame.Panel.Content.Right.Milestones["M" .. m.Key])
	end
	Juice.Stagger(cards, 0.05)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Invite:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Invite:Destroy()
	self._janitor:Destroy()
end

return Invite
