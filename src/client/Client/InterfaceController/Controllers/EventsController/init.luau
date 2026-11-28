--| EventsController ("Events")
-- The Events screen (design boards "79a · Events · Winter Special missions", "79b · … shop",
-- built by ./Build): the live in-game event (Constants/LiveEvents, Engine/EventService).
--   • the list on the left: the live event, the next one ("soon"), and Fan Club (opens Quests)
--   • Missions: today's (reset at midnight UTC) and the whole event's, each with its progress,
--     reward and Claim / Go / Done. Go opens where you do it (a duel, Packs, the Binder, the shop tab)
--   • Shop: what the event currency buys; the pack card also opens the packs you have
--     (straight into the Packs page's reveal)
-- Everything repaints from your data (PlayerData.Events) as it changes.
-- The HUD's event button opens it while an event is live (HUDController._bindEvent).
--   Interface:Open("Events", "Shop"?)

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local LiveEvents = require(ReplicatedStorage.Constants.LiveEvents)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Notify = require(ReplicatedStorage.Modules.UI.Notify)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local EventRemote = Bridgenet.ReferenceBridge("EventRemote")
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local PAPER = C("EFE7D4")
local GREY_TEXT = C("8B8499")
local CLAIM_BG = C("F2FFF5")

-- --------------------------------- Helpers -------------------------------- --

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- "23d 4h", "6h 12m", "12m"
local function left(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
	if d > 0 then
		return `{d}d {h}h`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return `{math.max(1, m)}m`
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function day(t: number): string
	local d = os.date("!*t", t - 1) -- (the last day it's on: Ends is midnight)
	return `{d.day} {MONTHS[d.month]}`
end

-- reads a saved value, nil-safe (the mirror can be missing a key until it's first written)
local function read(fn: () -> any, default: any): any
	local ok, value = pcall(fn)
	if ok and value ~= nil then
		return value
	end
	return default
end

local function live()
	local id = ReplicatedStorage:GetAttribute("LiveEvent")
	return if type(id) == "string" and id ~= "" then LiveEvents.Get(id) else nil
end

-- saved progress, for the live event only (an old event's is settled on the server)
local function state(event)
	local ev = PlayerData.Events
	local mine = read(function()
		return ev.Id.Get()
	end, "") == event.Id
	local today = read(function()
		return ev.Day.Get()
	end, 0) == LiveEvents.Day(workspace:GetServerTimeNow())
	local function map(node, fresh: boolean)
		return if mine and fresh then read(function()
			return node.Get()
		end, {}) else {}
	end
	local function set(node, fresh: boolean)
		local out = {}
		for _, id in map(node, fresh) do
			out[id] = true
		end
		return out
	end
	return {
		Daily = map(ev.Daily, today),
		Total = map(ev.Total, true),
		DailyClaimed = set(ev.DailyClaimed, today),
		Claimed = set(ev.Claimed, true),
		Bought = map(ev.Bought, true),
		BoughtToday = map(ev.BoughtToday, today),
	}
end

-- ---------------------------------- Class --------------------------------- --

local Events = {}
Events.__index = Events

function Events.new()
	local self = setmetatable({}, Events)
	self.Name = "Events"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Missions"
	self._pending = {} :: { [string]: boolean } -- claims / buys sent, waiting on the server
	self._rows = {} :: { Instance }
	self._items = {} :: { [string]: Instance }
	return (self :: any) :: UITypes.Controller
end

function Events:_toast(message: string)
	local toast = self._frame.Toast
	toast.Text = message
	toast.Visible = true
	local token = (toast:GetAttribute("Token") or 0) + 1
	toast:SetAttribute("Token", token)
	task.delay(2.2, function()
		if toast:GetAttribute("Token") == token then
			toast.Visible = false
		end
	end)
end

function Events:_show(tab: string)
	self._tab = tab
	local panel = self._frame.Panel
	panel.Missions.Visible = tab == "Missions"
	panel.Shop.Visible = tab == "Shop"
	for _, name in { "Missions", "Shop" } do
		local b = panel.Tabs[name]
		local on = name == tab
		b.BackgroundColor3 = if on then INK else PAPER
		b.Label.TextColor3 = if on then CREAM else INK
	end
end

-- [[ Header, list + banner ]]

function Events:_paintTop(event)
	local f = self._frame
	local now = workspace:GetServerTimeNow()
	local balance = Currencies.Count(LOCAL_PLAYER, "EventCurrency")
	f.Header.Balance.Amount.Text = fmt(balance)
	f.Header.Balance.Icon.Image = event.Currency.Icon
	local banner = f.Panel.Banner
	banner.Title.Text = event.Name
	banner.Blurb.Text = event.Blurb
	banner.Chips.Ends.Label.Text = `Ends {day(event.Ends)} · {left(event.Ends - now)}`
	banner.Chips.Balance.Label.Text = `{fmt(balance)} {if balance == 1 then event.Currency.Name else event.Currency.Plural}`
	banner.Chips.Balance.Icon.Image = event.Currency.Icon
	local list = f.List
	list.Live.Title.Text = event.Name
	list.Live.Chip.Label.Text = `LIVE · {left(event.Ends - now)} left`
	list.Live.Thumb.Icon.Image = event.Currency.Icon
	local nextOne = LiveEvents.Next(os.time())
	if nextOne and nextOne.Id ~= event.Id then
		list.Soon.Title.Text = nextOne.Name
		list.Soon.Line.Text = `Starts {day(nextOne.Starts + 1)}`
	end
end

-- [[ Missions ]]

-- what a mission's Go opens
function Events:_go(where: string?)
	Sounds.Play("Click")
	if where == "Shop" then
		self:_show("Shop")
		self:_paint()
	elseif where == "Packs" then
		self._interface:Open("Albums", { Page = "Shop" })
	elseif where == "Binder" then
		self._interface:Open("Binder")
	elseif where == "Play" then
		self._interface:Close(self.Name)
		QueueRemote:Fire("QuickPlay")
	end
end

function Events:_paintMissions(event, st)
	local scroll = self._frame.Panel.Missions
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)
	local now = workspace:GetServerTimeNow()
	local nextDay = (LiveEvents.Day(now) + 1) * 86400
	local ready = 0
	local order = 0
	local function head(label: string)
		order += 1
		local h = scroll.HeadTemplate:Clone()
		h.Name = "Head"
		h.LayoutOrder = order
		h.Label.Text = label
		h.Visible = true
		h.Parent = scroll
		table.insert(self._rows, h)
	end
	local function row(m, daily: boolean)
		order += 1
		local counts = if daily then st.Daily else st.Total
		local claimed = if daily then st.DailyClaimed[m.Id] else st.Claimed[m.Id]
		local have = math.min(counts[m.Stat] or 0, m.Goal)
		local done = have >= m.Goal
		local r = scroll.RowTemplate:Clone()
		r.Name = "Row_" .. m.Id
		r.LayoutOrder = order
		r.Visible = true
		r.Text.Text = m.Text
		r.Hint.Text = m.Hint or ""
		r.Hint.Visible = m.Hint ~= nil
		r.Text.Position = UDim2.fromOffset(16, if m.Hint then 10 else 20)
		r.Bar.Fill.Size = UDim2.fromScale(have / m.Goal, 1)
		r.Bar.Fill.Visible = have > 0
		r.Count.Text = `{fmt(have)} / {fmt(m.Goal)}`
		-- the reward: currency, or packs
		if (m.Reward.Packs or 0) > 0 then
			r.Reward.Icon.Image = event.Pack.Icon
			r.Reward.Amount.Text = `×{m.Reward.Packs}`
		else
			r.Reward.Icon.Image = event.Currency.Icon
			r.Reward.Amount.Text = fmt(m.Reward.Currency or 0)
		end
		local action = r.Action
		local pending = self._pending["Claim:" .. m.Id]
		if claimed then
			action.BackgroundColor3 = PAPER
			action.Label.Text = "Done"
			action.Label.TextColor3 = GREY_TEXT
			r.ActionShadow.Visible = false
			r.BackgroundColor3 = WHITE
			for _, d in r:GetDescendants() do
				if d:IsA("TextLabel") and d.Parent ~= action then
					d.TextTransparency = 0.45
				elseif d:IsA("ImageLabel") then
					d.ImageTransparency = 0.45
				end
			end
		elseif done then
			ready += 1
			action.BackgroundColor3 = MINT
			action.Label.Text = if pending then "..." else "Claim"
			r.BackgroundColor3 = CLAIM_BG
		else
			action.BackgroundColor3 = WHITE
			action.Label.Text = "Go"
			action.Visible = m.Go ~= nil
			r.ActionShadow.Visible = m.Go ~= nil
		end
		ButtonScale.Apply(action)
		action.Activated:Connect(function()
			if claimed then
				return
			elseif done then
				if self._pending["Claim:" .. m.Id] then
					return
				end
				self._pending["Claim:" .. m.Id] = true
				Sounds.Play("Click")
				EventRemote:Fire({ Action = "Claim", Id = m.Id })
				action.Label.Text = "..."
			else
				self:_go(m.Go)
			end
		end)
		r.Parent = scroll
		table.insert(self._rows, r)
	end
	head(`DAILY · RESETS IN {left(nextDay - now)}`)
	for _, m in event.Daily do
		row(m, true)
	end
	head(`{string.upper(event.Name)} · ALL EVENT`)
	-- (ready ones first, then the rest in order, claimed last)
	local list = table.clone(event.Missions)
	local function rank(m): number
		if st.Claimed[m.Id] then
			return 2
		end
		return if (st.Total[m.Stat] or 0) >= m.Goal then 0 else 1
	end
	local index = {}
	for i, m in event.Missions do
		index[m] = i
	end
	table.sort(list, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return index[a] < index[b]
	end)
	for _, m in list do
		row(m, false)
	end
	local count = self._frame.Panel.Tabs.Missions.Count
	count.Text = tostring(ready)
	count.Visible = ready > 0
	return ready
end

-- [[ Shop ]]

local function owns(item): boolean
	if item.Kind == "Set" then
		return read(function()
			return PlayerData.Inventory.Sets.Has(item.Set)
		end, false)
	elseif item.Kind == "Title" then
		return read(function()
			return PlayerData.Inventory.Titles.Has(item.Title)
		end, false)
	end
	return false
end

function Events:_buy(event, item)
	if self._pending["Buy:" .. item.Id] then
		return
	end
	self._pending["Buy:" .. item.Id] = true
	Sounds.Play("Click")
	EventRemote:Fire({ Action = "Buy", Id = item.Id })
end

function Events:_paintShop(event, st)
	local scroll = self._frame.Panel.Shop
	local balance = Currencies.Count(LOCAL_PLAYER, "EventCurrency")
	local packs = Currencies.Count(LOCAL_PLAYER, "EventPacks")
	for i, item in event.Shop do
		local cell = self._items[item.Id]
		if not cell then
			cell = scroll.ItemTemplate:Clone()
			cell.Name = "Item_" .. item.Id
			cell.LayoutOrder = i
			cell.Visible = true
			cell.Parent = scroll
			self._items[item.Id] = cell
			local card = cell.Card
			ButtonScale.Apply(card.Buy)
			ButtonScale.Apply(card.Art.OpenPack)
			card.Buy.Activated:Connect(function()
				local ev = live()
				local it = ev and LiveEvents.Item(ev, item.Id)
				if not it then
					return
				end
				local s = state(ev)
				if owns(it) or (it.Limit and (s.Bought[it.Id] or 0) >= it.Limit) or (it.DailyLimit and (s.BoughtToday[it.Id] or 0) >= it.DailyLimit) then
					Sounds.Play("Wrong")
					Juice.Shake(card.Buy, 0.12)
					return
				end
				if Currencies.Count(LOCAL_PLAYER, "EventCurrency") < it.Price then
					Sounds.Play("Wrong")
					Juice.Shake(card.Buy, 0.12)
					self:_toast(`Not enough {ev.Currency.Plural}: do missions for more`)
					return
				end
				self:_buy(ev, it)
			end)
			card.Art.OpenPack.Activated:Connect(function()
				Sounds.Play("Click")
				self._interface:Open("Albums", { Page = "Shop", OpenEvent = true })
			end)
		end
		local card = cell.Card
		card.Tag.Visible = item.Exclusive == true
		card.Art.BackgroundColor3 = C(item.Colour or "DFF3FF")
		card.Art.Pic.Image = item.Art or ""
		card.Art.Pic.Visible = item.Art ~= nil
		card.Art.TitleChip.Visible = item.Kind == "Title"
		card.Art.TitleChip.Text = item.Title or ""
		card.Art.OpenPack.Visible = item.Kind == "Pack" and packs > 0
		card.Art.OpenPack.Label.Text = if packs > 1 then `Open ×{packs}` else "Open"
		card.Title.Text = item.Name
		card.Hint.Text = item.Hint or ""
		local bought, today = st.Bought[item.Id] or 0, st.BoughtToday[item.Id] or 0
		local have = owns(item)
		local soldOut = (item.Limit and bought >= item.Limit) or (item.DailyLimit and today >= item.DailyLimit)
		if have then
			card.Stock.Text = "You have it"
		elseif item.Limit == 1 then
			card.Stock.Text = "1 per player"
		elseif item.Limit then
			card.Stock.Text = `{math.max(0, item.Limit - bought)} left`
		elseif item.DailyLimit then
			card.Stock.Text = `{math.max(0, item.DailyLimit - today)} left today`
		else
			card.Stock.Text = "No limit"
		end
		local buy = card.Buy
		local off = have or soldOut
		buy.BackgroundColor3 = if off then PAPER else C("DFF3FF")
		buy.Icon.Visible = not off
		buy.Icon.Image = event.Currency.Icon
		buy.Price.Text = if have then "Owned" elseif soldOut then (if item.DailyLimit then "Back tomorrow" else "Sold out") elseif self._pending["Buy:" .. item.Id] then "..." else fmt(item.Price)
		buy.Price.TextColor3 = if off then GREY_TEXT elseif balance < item.Price then C("B5485A") else INK
		card.BuyShadow.Visible = not off
	end
	-- items no longer in the shop (another event)
	for id, cell in self._items do
		if not LiveEvents.Item(event, id) then
			cell:Destroy()
			self._items[id] = nil
		end
	end
	local note = scroll.Note.Box.Label
	note.Text = `Left-over {event.Currency.Plural} turn into coins when the event ends (1 = {event.Leftover} coins), so nothing is wasted. Unopened {event.Pack.Name}s become gen packs.`
end

function Events:_paint()
	if not self._frame then
		return
	end
	local event = live()
	if not event then
		return
	end
	local st = state(event)
	self:_paintTop(event)
	self:_paintMissions(event, st)
	self:_paintShop(event, st)
end

-- [[ Snow ]]

function Events:_startSnow()
	local snow = self._frame.Snow
	local flakes = {}
	for _, f in snow:GetChildren() do
		if f:IsA("Frame") then
			table.insert(flakes, { f, f.Position.X.Offset, f.Position.Y.Offset, f:GetAttribute("Speed") or 20, math.random() * 6 })
		end
	end
	local t = 0
	self._snow = RunService.RenderStepped:Connect(function(dt)
		t += dt
		for _, s in flakes do
			s[3] += s[4] * dt
			if s[3] > 740 then
				s[3] = -20
			end
			s[1].Position = UDim2.fromOffset(s[2] + math.sin(t * 0.6 + s[5]) * 10, s[3])
		end
	end)
end

function Events:_stopSnow()
	if self._snow then
		self._snow:Disconnect()
		self._snow = nil
	end
end

-- ------------------------------- Lifecycle -------------------------------- --

function Events:Initialize(interface)
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "Events")
	if not self._frame then
		warn("EventsController: build Interface.Frames.Events first (EventsController/Build)")
		return
	end
	self._frame.Visible = false
	local f = self._frame
	ButtonScale.Apply(f.Header.Close)
	j:Add(f.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, name in { "Missions", "Shop" } do
		local tab = f.Panel.Tabs[name]
		ButtonScale.Apply(tab)
		j:Add(tab.Activated:Connect(function()
			if self._tab ~= name then
				Sounds.Play("Click")
				self:_show(name)
			end
		end))
	end
	ButtonScale.Apply(f.List.FanClub)
	j:Add(f.List.FanClub.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Open("Rewards")
	end))
	j:Add(f.List.Soon.Activated:Connect(function()
		Sounds.Play("Wrong")
		self:_toast("Coming soon: keep an eye on this page")
	end))

	-- repaint whenever the event's save or the balances move (one repaint a frame at most)
	local queued = false
	local function changed()
		if queued or self.State == "Inactive" then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if self.State ~= "Inactive" then
				self:_paint()
			end
		end)
	end
	local ev = PlayerData.Events
	for _, key in { "Id", "Day", "Daily", "Total", "DailyClaimed", "Claimed", "Bought", "BoughtToday" } do
		local ok, conn = pcall(function()
			return ev[key].Observe(changed)
		end)
		if ok and conn then
			j:Add(conn)
		end
	end
	for _, key in { "EventCurrency", "EventPacks" } do
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal(Currencies[key].Attribute):Connect(changed))
	end
	j:Add(ReplicatedStorage:GetAttributeChangedSignal("LiveEvent"):Connect(function()
		if not live() and self.State ~= "Inactive" then
			self._interface:Close(self.Name)
		else
			changed()
		end
	end))

	j:Add(EventRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" then
			return
		end
		self._pending[`{packet.Action}:{packet.Id}`] = nil
		if self.State == "Inactive" then
			return
		end
		if packet.Ok then
			Sounds.Play(if packet.Action == "Claim" then "GiftClaim" else "MarketBuy")
			local event = live()
			if packet.Action == "Claim" and event then
				local r = packet.Reward or {}
				self:_toast(if (r.Packs or 0) > 0 then `+{r.Packs} {event.Pack.Name}{if r.Packs == 1 then "" else "s"}` else `+{fmt(r.Currency or 0)} {event.Currency.Plural}`)
			elseif packet.Action == "Buy" then
				local item = packet.Item
				self:_toast(if item and item.Kind == "Pack" then `Got a {item.Name}: tap Open on it` elseif item and item.Kind == "Premium" then `Got a {item.Name}: open it on the Packs page` else packet.Text)
			end
		else
			Sounds.Play("Wrong")
			self:_toast(packet.Text or "That didn't work")
		end
		self:_paint()
	end), "Disconnect")

	-- Studio only: the LocalPlayer's "EventsTest" attribute ("Missions" / "Shop") opens it
	if RunService:IsStudio() then
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("EventsTest"):Connect(function()
			local tab = LOCAL_PLAYER:GetAttribute("EventsTest")
			if type(tab) == "string" and tab ~= "" then
				self._interface:Open(self.Name, tab)
			end
		end))
	end

	-- the countdowns
	local ticker = task.spawn(function()
		while true do
			task.wait(30)
			if self.State == "Active" then
				self:_paint()
			end
		end
	end)
	j:Add(function()
		task.cancel(ticker)
	end, true)
end

function Events:Activate(tab: string?)
	if not live() then
		Notify.Toast("No event is on right now")
		task.defer(function()
			self._interface:Close(self.Name)
		end)
		return Promise.resolve()
	end
	self._frame.Visible = true
	self:_show(if tab == "Shop" then "Shop" else "Missions")
	self:_paint()
	self._frame.Panel.Missions.CanvasPosition = Vector2.zero
	self._frame.Panel.Shop.CanvasPosition = Vector2.zero
	self:_stopSnow()
	self:_startSnow()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Events:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
		self:_stopSnow()
	end)
end

function Events:Destroy()
	self:_stopSnow()
	self._janitor:Destroy()
	self._interface = nil
end

return Events
