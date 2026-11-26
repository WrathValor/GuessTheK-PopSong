--| GiftsController ("Gifts")
-- The Gifts screen (design board "56 · Gifts inbox + send to anyone", built by ./Build):
--   • Inbox: every gift waiting in your Inventory.Gifts (Engine/GiftInbox), newest first: what it
--     is, who from (a DEVELOPER tag on the developer's), their note and when, CLAIM (the "GIFT
--     RECEIVED!" reveal is PurchasedController's) and CLAIM ALL
--   • Send a gift: search a username (GiftRemote "Find") or pick a friend, add a note, then SHOP
--     FOR <NAME> opens the shop in gift mode for them (ShopController:StartGift), in any server
--     or offline
--   • a toast when a gift lands while you're playing (GiftRemote "Inbox")
-- The HUD's Gifts tile opens it and shows the count (HUDController).
--   Interface:Open("Gifts")

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Notify = require(ReplicatedStorage.Modules.UI.Notify)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local GiftRemote = Bridgenet.ReferenceBridge("GiftRemote")

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local CREAM_YELLOW = C("FFF6D6")
local GIFT_ICON = "rbxassetid://119916041465663"
local EXPIRE_DAYS = 30 -- (Engine/GiftInbox.EXPIRE_DAYS)
local FRIENDS_SHOWN = 50

-- the item square's colour, by kind
local KIND_COLOURS = {
	Coins = "FFF0B8",
	Tickets = "FFE4EF",
	Pass = "D6F0FC",
	Set = "E5DCFF",
	Stage = "E5DCFF",
	Mic = "E5DCFF",
	StyleSet = "FFE4EF",
	Banner = "FFE4EF",
	Photocard = "FFE4EF",
}

-- --------------------------------- Helpers -------------------------------- --

local function decode(json: any): { [string]: any }?
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, gift = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and type(gift) == "table" then gift else nil
end

-- the waiting gifts, newest first
local function gifts(): { { [string]: any } }
	local ok, map = pcall(PlayerData.Inventory.Gifts.Get)
	local out = {}
	for id, json in (if ok and type(map) == "table" then map else {}) do
		local gift = decode(json)
		if gift then
			gift.Id = id
			table.insert(out, gift)
		end
	end
	table.sort(out, function(a, b)
		return (a.At or 0) > (b.At or 0)
	end)
	return out
end

local function ago(at: number): string
	local s = math.max(0, os.time() - at)
	if s < 3600 then
		local m = math.max(1, s // 60)
		return if m == 1 then "1 min ago" else `{m} min ago`
	elseif s < 86400 then
		local h = s // 3600
		return if h == 1 then "1 h ago" else `{h} h ago`
	end
	local d = s // 86400
	return if d == 1 then "yesterday" else `{d} days ago`
end

-- a gentle "no": the outline goes red for a moment with the smallest wobble (a wide box
-- swinging at full strength looked violent)
local function nope(gui: GuiObject)
	local s = gui:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = C("FF5A4E")
		local token = (gui:GetAttribute("NopeToken") or 0) + 1
		gui:SetAttribute("NopeToken", token)
		task.delay(0.7, function()
			if gui:GetAttribute("NopeToken") == token then
				s.Color = C("1E1B2E")
			end
		end)
	end
	Juice.Shake(gui, 0.12)
end

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- ---------------------------------- Class --------------------------------- --

local Gifts = {}
Gifts.__index = Gifts

function Gifts.new()
	local self = setmetatable({}, Gifts)
	self.Name = "Gifts"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Inbox"
	self._claiming = {} :: { [string]: boolean }
	self._found = nil :: { UserId: number, Name: string }?
	self._friends = nil :: { { UserId: number, Name: string, Online: boolean } }?
	self._picked = nil :: { UserId: number, Name: string }?
	return (self :: any) :: UITypes.Controller
end

function Gifts:_toast(message: string)
	Notify.Toast(message)
end

-- [[ Inbox ]]

function Gifts:_paintRow(row: Frame, gift)
	local kind = gift.Kind or ""
	local item = row.Item
	item.BackgroundColor3 = C(KIND_COLOURS[kind] or "FFE4EF")
	item.Big.Visible = false
	item.Icon.Visible = true
	if kind == "Coins" then
		item.Icon.Image = Currencies.Coins.Icon
	elseif kind == "Tickets" then
		item.Icon.Image = Currencies.Tickets.Icon
	elseif kind == "Pass" then
		local pass = ShopCatalog.GetPass(gift.ItemId or "")
		if pass and pass.Art then
			item.Icon.Image = pass.Art
		else
			item.Icon.Visible = false
			item.Big.Visible = true
			item.Big.Text = pass and pass.Icon or "★"
		end
	else
		item.Icon.Image = GIFT_ICON
	end
	row.Top.Item.Text = gift.Name or "A gift"
	row.Top.Dev.Visible = gift.Dev == true
	row.BackgroundColor3 = if gift.Dev then CREAM_YELLOW else WHITE
	row.From.Text = `From {gift.From or "a fan"}`
	local when = ago(gift.At or os.time())
	row.Note.Text = if type(gift.Note) == "string" and gift.Note ~= "" then `“{gift.Note}” · {when}` else when
	local busy = self._claiming[gift.Id] == true
	row.Claim.Text = if busy then "…" else "CLAIM"
	row.Claim.Active = not busy
end

function Gifts:_paintInbox()
	local page = self._frame.Panel.Inbox
	local scroll = page.List
	local template = scroll.Template
	local list = gifts()
	local rows = {}
	for _, child in scroll:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			rows[child.Name] = child
		end
	end
	for i, gift in list do
		local row = rows[gift.Id]
		rows[gift.Id] = nil
		if not row then
			row = template:Clone()
			row.Name = gift.Id
			row.Visible = true
			row.Parent = scroll
			ButtonScale.Apply(row.Claim)
			local id = gift.Id
			self._janitor:Add(row.Claim.Activated:Connect(function()
				if self._claiming[id] then
					return
				end
				self._claiming[id] = true
				Sounds.Play("Click")
				GiftRemote:Fire({ Action = "Claim", Id = id })
				self:_paintInbox()
			end))
		end
		row.LayoutOrder = i
		self:_paintRow(row, gift)
	end
	for _, gone in rows do
		gone:Destroy()
	end
	page.Empty.Visible = #list == 0
	page.ClaimAll.Visible = #list > 1
	page.ClaimAllShadow.Visible = #list > 1
	local header = self._frame.Panel.Header
	header.Sub.Text = if #list == 0 then `Nothing waiting · gifts last {EXPIRE_DAYS} days` else `{#list} waiting · gifts last {EXPIRE_DAYS} days`
	header.Tabs.Inbox.Text = if #list > 0 then `Inbox {#list}` else "Inbox"
end

-- [[ Send a gift ]]

function Gifts:_loadFriends()
	if self._friends then
		return
	end
	self._friends = {}
	task.spawn(function()
		local online = {}
		local ok, list = pcall(LOCAL_PLAYER.GetFriendsOnline, LOCAL_PLAYER, FRIENDS_SHOWN)
		if ok and type(list) == "table" then
			for _, f in list do
				online[f.VisitorId] = true
			end
		end
		local okPages, pages = pcall(Players.GetFriendsAsync, Players, LOCAL_PLAYER.UserId)
		local friends = {}
		if okPages and pages then
			for _, f in pages:GetCurrentPage() do
				table.insert(friends, { UserId = f.Id, Name = f.Username, Online = online[f.Id] == true })
			end
		end
		-- online first, then A–Z
		table.sort(friends, function(a, b)
			if a.Online ~= b.Online then
				return a.Online
			end
			return string.lower(a.Name) < string.lower(b.Name)
		end)
		self._friends = friends
		self._friendsLoaded = true
		if self.State ~= "Inactive" then
			self:_paintPeople()
		end
	end)
end

function Gifts:_paintPeople()
	local page = self._frame.Panel.Send
	local scroll = page.People
	for _, child in scroll:GetChildren() do
		if (child:IsA("TextLabel") or child:IsA("TextButton")) and not string.find(child.Name, "Template") and child.Name ~= "Loading" then
			child:Destroy()
		end
	end
	local order = 0
	local function head(label: string)
		order += 1
		local h = scroll.HeadTemplate:Clone()
		h.Name = "Head" .. order
		h.Text = label
		h.LayoutOrder = order
		h.Visible = true
		h.Parent = scroll
	end
	local function person(p: { UserId: number, Name: string }, line: string)
		order += 1
		local row = scroll.PersonTemplate:Clone()
		row.Name = "Person" .. order
		row.LayoutOrder = order
		row.Visible = true
		row.Avatar.Image = headshot(p.UserId)
		row.PersonName.Text = p.Name
		row.Line.Text = line
		local picked = self._picked ~= nil and self._picked.UserId == p.UserId
		row.BackgroundTransparency = if picked then 0 else 1
		row.UIStroke.Transparency = if picked then 0 else 1
		row.Parent = scroll
		self._janitor:Add(row.Activated:Connect(function()
			Sounds.Play("Click")
			self._picked = { UserId = p.UserId, Name = p.Name }
			self:_paintPeople()
			self:_paintShopFor()
		end))
	end
	if self._found then
		head("FOUND")
		person(self._found, if Players:GetPlayerByUserId(self._found.UserId) then "In this server" else "Gets it next time they play")
	end
	head("FRIENDS")
	local friends = self._friends or {}
	scroll.Loading.Visible = not self._friendsLoaded
	scroll.Loading.LayoutOrder = order + 1
	if self._friendsLoaded and #friends == 0 then
		scroll.Loading.Visible = true
		scroll.Loading.Text = "No friends to show. Search a username above."
	end
	for _, f in friends do
		person(f, if Players:GetPlayerByUserId(f.UserId) then "In this server" elseif f.Online then "Online" else "Offline")
	end
end

function Gifts:_paintShopFor()
	local b = self._frame.Panel.Send.ShopFor
	b.Text = if self._picked then `SHOP FOR {string.upper(self._picked.Name)}` else "PICK SOMEONE"
	-- (washed out until someone's picked: a lighter colour, not see-through, so its shadow
	-- doesn't show through)
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = if self._picked then C("FF9EC4") else C("F6D7E4")
	b.TextColor3 = if self._picked then C("1E1B2E") else C("8C8299")
end

function Gifts:_find()
	local box = self._frame.Panel.Send.Search.Box
	local name = string.gsub(box.Text, "[^%w_]", "")
	if #name < 3 then
		nope(self._frame.Panel.Send.Search)
		return
	end
	box.Text = name
	Sounds.Play("Click")
	GiftRemote:Fire({ Action = "Find", Name = name })
end

function Gifts:_shopFor()
	local picked = self._picked
	if not picked then
		nope(self._frame.Panel.Send.ShopFor)
		return
	end
	local shop = self._interface:GetController("Shop")
	if not shop or not shop.StartGift then
		return
	end
	local note = self._frame.Panel.Send.Note.Box.Text
	Sounds.Play("Click")
	self._interface:Open("Shop")
	shop:StartGift(picked.UserId, picked.Name, if note ~= "" then string.sub(note, 1, 80) else nil)
end

-- [[ Tabs ]]

function Gifts:_show(tab: string)
	self._tab = tab
	local panel = self._frame.Panel
	panel.Inbox.Visible = tab == "Inbox"
	panel.Send.Visible = tab == "Send"
	for _, b in panel.Header.Tabs:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundTransparency = if b.Name == tab then 0 else 1
		end
	end
	if tab == "Send" then
		self:_loadFriends()
		self:_paintPeople()
		self:_paintShopFor()
	else
		self:_paintInbox()
	end
end

-- [[ Lifecycle ]]

function Gifts:Initialize(interface)
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "Gifts")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(self._frame.Scrim.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, name in { "Inbox", "Send" } do
		j:Add(panel.Header.Tabs[name].Activated:Connect(function()
			if self._tab ~= name then
				Sounds.Play("Click")
				self:_show(name)
			end
		end))
	end
	j:Add(panel.Inbox.ClaimAll.Activated:Connect(function()
		local list = gifts()
		if #list == 0 then
			return
		end
		for _, gift in list do
			self._claiming[gift.Id] = true
		end
		Sounds.Play("Click")
		GiftRemote:Fire({ Action = "ClaimAll" })
		self:_paintInbox()
	end))
	j:Add(panel.Send.Find.Activated:Connect(function()
		self:_find()
	end))
	j:Add(panel.Send.Search.Box.FocusLost:Connect(function(enter)
		if enter then
			self:_find()
		end
	end))
	j:Add(panel.Send.ShopFor.Activated:Connect(function()
		self:_shopFor()
	end))

	-- the inbox follows your data (a new gift, a claim)
	j:Add(PlayerData.Inventory.Gifts.Observe(function()
		for id in self._claiming do
			local ok, json = pcall(function()
				return PlayerData.Inventory.Gifts.Get()[id]
			end)
			if not ok or json == nil then
				self._claiming[id] = nil
			end
		end
		if self.State ~= "Inactive" and self._tab == "Inbox" then
			self:_paintInbox()
		end
	end))

	j:Add(GiftRemote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Message == "Found" then
			if packet.UserId then
				self._found = { UserId = packet.UserId, Name = packet.Name }
				self._picked = self._found
			else
				self._found = nil
				if self.State ~= "Inactive" then
					self:_toast(`No player called {packet.Name}`)
					Sounds.Play("Wrong")
					nope(self._frame.Panel.Send.Search)
				end
			end
			if self.State ~= "Inactive" and self._tab == "Send" then
				self:_paintPeople()
				self:_paintShopFor()
			end
		elseif packet.Message == "Claimed" then
			if packet.Id then
				self._claiming[packet.Id] = nil
			end
			if packet.Text and self.State ~= "Inactive" then
				self:_toast(packet.Text)
			end
			if self.State ~= "Inactive" and self._tab == "Inbox" then
				self:_paintInbox()
			end
		elseif packet.Message == "Inbox" then
			-- a gift just landed: say so on the HUD (or here, if it's open)
			local text = `{packet.From or "Someone"} sent you {packet.Name or "a gift"}!`
			if self.State ~= "Inactive" then
				self:_toast(text)
			else
				local hud = self._interface:GetController("HUD")
				if hud and hud.Toast then
					Notify.Show("Notify", text, "Tap to open Gifts and claim it", {
						OnTap = function()
							hud:_open("Gifts")
						end,
					})
				end
			end
		end
	end), "Disconnect")
end

function Gifts:Activate(tab: string?)
	self._frame.Visible = true
	self:_show(if tab == "Send" then "Send" else "Inbox")
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Gifts:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Gifts:Destroy()
	self._janitor:Destroy()
	self._interface = nil
end

return Gifts
