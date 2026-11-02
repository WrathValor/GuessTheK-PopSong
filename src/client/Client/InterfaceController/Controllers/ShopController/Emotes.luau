--| Shop · UGC
-- The UGC tab: the group's own avatar items (Modules/UGC, Engine/UGCService), sold for
-- Robux. Left: the selected item, big, on your own avatar. Right: All / Dances / Accessories,
-- six cards a page (no scrolling), ‹ › to page. A dance you own gets a Dance button instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGC = require(ReplicatedStorage.Modules.UGC)
local UGCCatalog = require(ReplicatedStorage.Constants.UGCCatalog)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local LILAC = C("B9A6FF")
local GREY = C("EDE4D4")

local PER_PAGE = 6
local FILTERS = { All = true, Dances = "Dance", Accessories = "Accessory" }

local Emotes = {}
Emotes.__index = Emotes

function Emotes.new(page: Frame, janitor, onDance: () -> ())
	local self = setmetatable({}, Emotes)
	self._page = page
	self._filter = "All"
	self._pageIndex = 1
	self._selected = nil :: number?
	self._onDance = onDance

	for name in FILTERS do
		janitor:Add(page.Filters[name].Activated:Connect(function()
			if self._filter ~= name then
				self._filter = name
				self._pageIndex = 1
				self._selected = nil
				self:Fill()
			end
		end))
	end
	for step, n in { [-1] = "Prev", [1] = "Next" } do
		janitor:Add(page.Pager[n].Activated:Connect(function()
			local pages = math.max(1, math.ceil(#self:_list() / PER_PAGE))
			local nextIndex = math.clamp(self._pageIndex + step, 1, pages)
			if nextIndex ~= self._pageIndex then
				self._pageIndex = nextIndex
				self:Fill()
			end
		end))
	end
	for i = 1, PER_PAGE do
		local holder = page.Grid["Card" .. i]
		janitor:Add(holder.Face.Art.Select.Activated:Connect(function()
			local id = holder:GetAttribute("AssetId")
			if id and id ~= self._selected then
				self._selected = id
				self:Fill()
				Juice.Pop(page.Preview, 0.06)
			end
		end))
		janitor:Add(holder.Face.Action.Activated:Connect(function()
			self:_action(holder:GetAttribute("AssetId"))
		end))
	end
	janitor:Add(page.Preview.Action.Activated:Connect(function()
		self:_action(self._selected)
	end))
	-- filled even while hidden, so the first page is ready (models + dances loaded) before
	-- anyone opens the tab
	janitor:Add(UGC.Changed:Connect(function()
		self:Fill()
	end))
	CosmeticView.EnableSpin(page.Preview.Art) -- drag the big preview to turn around it
	return self
end

function Emotes:_list(): { any }
	local want = FILTERS[self._filter]
	local list = {}
	for _, item in UGC.Items do
		if want == true or item.Kind == want then
			table.insert(list, item)
		end
	end
	return list
end

-- buy, or dance one you own
function Emotes:_action(id: number?)
	local item = UGC.Get(id)
	if not item then
		return
	end
	if UGC.Owned(item.Id) then
		if item.Kind == "Dance" then
			UGC.Dance(item.Id)
			self._onDance()
		end
		return
	end
	UGC.Buy(item.Id, "Shop")
end

local function robuxIcon(button: GuiButton)
	local icon = button:FindFirstChild("Icon") :: ImageLabel?
	if icon and UGCCatalog.ROBUX_ICON ~= "" then
		icon.Image = UGCCatalog.ROBUX_ICON
		icon.ImageColor3 = INK -- the icon is white; ink like the label
	end
end

local function setAction(button: GuiButton, item, owned: boolean?)
	local label = button:FindFirstChild("Label") :: TextLabel
	local icon = button:FindFirstChild("Icon") :: ImageLabel
	robuxIcon(button)
	if owned and item.Kind == "Dance" then
		label.Text = "Dance"
		icon.Visible = false
		button.BackgroundColor3 = YELLOW
		button.Active = true
	elseif owned then
		label.Text = "Owned"
		icon.Visible = false
		button.BackgroundColor3 = GREY
		button.Active = false
	else
		label.Text = tostring(item.Price)
		icon.Visible = true
		button.BackgroundColor3 = MINT
		button.Active = owned == false -- still checking: wait a moment
	end
end

local function paintChips(art: Frame, item)
	art.Kind.Text = if item.Kind == "Dance" then "DANCE" else "ACCESSORY"
	art.Kind.BackgroundColor3 = if item.Kind == "Dance" then YELLOW else LILAC
end

function Emotes:Fill()
	local page = self._page
	local list = self:_list()
	local pages = math.max(1, math.ceil(#list / PER_PAGE))
	self._pageIndex = math.clamp(self._pageIndex, 1, pages)
	page.Grid.Empty.Visible = #list == 0
	page.Grid.Empty.Text = if #UGC.Items == 0 then "Loading the group's items…" else "Nothing here yet"

	for name in FILTERS do
		local b = page.Filters[name]
		local on = name == self._filter
		b.BackgroundColor3 = if on then INK else WHITE
		b.TextColor3 = if on then YELLOW else INK
	end
	page.Pager.PageLabel.Text = `{self._pageIndex} / {pages}`
	page.Pager.Prev.Visible = pages > 1
	page.Pager.Next.Visible = pages > 1

	-- default selection: the first card on the page
	local first = list[(self._pageIndex - 1) * PER_PAGE + 1]
	if not UGC.Get(self._selected) then
		self._selected = first and first.Id
	end

	for i = 1, PER_PAGE do
		local holder = page.Grid["Card" .. i]
		local item = list[(self._pageIndex - 1) * PER_PAGE + i]
		holder.Visible = item ~= nil
		local shadow = holder.Parent:FindFirstChild(holder.Name .. "Shadow")
		if shadow then
			shadow.Visible = item ~= nil
		end
		holder:SetAttribute("AssetId", item and item.Id or nil)
		if item then
			local face = holder.Face
			paintChips(face.Art, item)
			CosmeticView.Show(face.Art, item.Kind, tostring(item.Id))
			face.ItemName.Text = item.Name
			face.Sub.Text = item.Artist
			face.BackgroundColor3 = if item.Id == self._selected then C("FFF6D6") else WHITE
			setAction(face.Action, item, UGC.Owned(item.Id))
		end
	end

	local item = UGC.Get(self._selected)
	local preview = page.Preview
	preview.Visible = item ~= nil
	if page:FindFirstChild("PreviewShadow") then
		page.PreviewShadow.Visible = item ~= nil
	end
	if item then
		paintChips(preview.Art, item)
		CosmeticView.Show(preview.Art, item.Kind, tostring(item.Id))
		preview.ItemName.Text = item.Name
		preview.Sub.Text = `{item.Name} - by {UGCCatalog.CREATOR}`
		setAction(preview.Action, item, UGC.Owned(item.Id))
	end
end

return Emotes
