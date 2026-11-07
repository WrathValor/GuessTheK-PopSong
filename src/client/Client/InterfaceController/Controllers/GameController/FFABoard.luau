--| FFABoard
-- The round screen's scoreboard for a Party Stage match with 3–6 players (Game.FFABoard,
-- built by PartyController/Build): the duel ticket's round stub (ROUND n/7 + pips, dashed
-- edge), then one cell per player in setlist order with their place, name, status and score.
-- The cells share the panel's width between however many are playing. Your cell has a red
-- hard shadow; place badges take each player's colour, 1st (with points) goes yellow.

local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local YELLOW = C("FFE07A")
local GREY = C("EDE4D4")
local RED = C("E0382C")
-- place badge colours per setlist slot (as the Party results photocards / PartyRound board)
local AV = { C("DCD3FF"), C("FFD2CE"), C("C8EFD6"), C("CDEBFA"), C("FFE9A8"), C("F4D6FF") }
-- pips, as Game.Scoreboard
local PIP = { Done = INK, Current = C("FF5A4E"), Upcoming = C("FFFFFF") }
-- cell layout inside Panel.Players (PartyController/Build)
local GAP, PAD_R, CELL_H, MAX_W = 8, 12, 60, 230
local FULL_W, CENTRE_X = 980, 640 -- the built panel's width; the ticket stays centred on the canvas
local STATUS = {
	ok = C("166534"),
	bad = C("B42318"),
	wait = C("6B6577"),
	you = C("5B45D6"),
}

local FFABoard = {}
FFABoard.__index = FFABoard

-- profiles = PreDuel Players ({ ["1"] = profile, … }), title = the stage's name line
function FFABoard.new(frame: Frame, profiles, title: string?)
	local self = setmetatable({}, FFABoard)
	self.Frame = frame
	self.Order = {} :: { any } -- profiles in setlist order
	for i = 1, 6 do
		local p = profiles and profiles[tostring(i)]
		if p then
			table.insert(self.Order, p)
		end
	end
	self.Scores = {}
	self.Left = {}
	frame.Tag.Text = title or "Party Stage · free-for-all"
	return self
end

function FFABoard:_cell(userId: number): Frame?
	for i, p in self.Order do
		if p.UserId == userId then
			return self.Frame.Panel.Players["Player" .. i]
		end
	end
	return nil
end

-- share the panel's width between the players (capped, so 3 don't look stretched), then
-- shrink the ticket to fit them so there's no empty white end, and keep it centred
function FFABoard:_layout()
	local panel = self.Frame.Panel
	local holder = panel.Players
	local n = math.max(#self.Order, 1)
	-- canvas offsets (the Frames' UIScale does the rest): full panel width minus the stub
	local left = holder.Position.X.Offset
	local w = math.min(MAX_W, math.floor((FULL_W - left - PAD_R - GAP * (n - 1)) / n))
	local width = left + n * w + (n - 1) * GAP + PAD_R
	local x0 = CENTRE_X - math.floor(width / 2)
	panel.Size = UDim2.fromOffset(width, panel.Size.Y.Offset)
	panel.Position = UDim2.fromOffset(x0, panel.Position.Y.Offset)
	local shadow = self.Frame:FindFirstChild("PanelShadow")
	if shadow then
		shadow.Size = panel.Size
		shadow.Position = UDim2.fromOffset(x0 + 5, shadow.Position.Y.Offset)
	end
	local y = math.floor((84 - CELL_H) / 2) - 1
	for i = 1, 6 do
		local cell = holder["Player" .. i]
		local drop = holder:FindFirstChild("Shadow" .. i)
		local x = (i - 1) * (w + GAP)
		cell.Size = UDim2.fromOffset(w, CELL_H)
		cell.Position = UDim2.fromOffset(x, y)
		if drop then
			drop.Size = UDim2.fromOffset(w, CELL_H)
			drop.Position = UDim2.fromOffset(x + 3, y + 3)
			drop.Visible = cell.Visible
		end
	end
end

function FFABoard:Initialize(rounds: number)
	self.Rounds = rounds
	local holder = self.Frame.Panel.Players
	for i = 1, 6 do
		local cell = holder["Player" .. i]
		local drop = holder:FindFirstChild("Shadow" .. i)
		local p = self.Order[i]
		cell.Visible = p ~= nil
		if p then
			local me = p.UserId == LOCAL_PLAYER.UserId
			cell.PlayerName.Text = if me then "You" else p.Name
			cell.Score.Text = "0"
			cell.Score.TextColor3 = if me then RED else C("4A4460")
			cell.Status.Text = ""
			cell:FindFirstChildOfClass("UIStroke").Color = INK
			cell.BackgroundColor3 = if me then C("FFF0EE") else CREAM
			if drop then
				drop.BackgroundColor3 = if me then RED else INK
			end
			self.Scores[p.UserId] = 0
		end
	end
	self:_layout()
	self:_ranks()
	self:UpdateRound(1)
end

function FFABoard:UpdateRound(round: number)
	local stub = self.Frame.Panel.Stub
	stub.Round.Text = `{round}/{self.Rounds or 7}`
	local pips = stub:FindFirstChild("Pips")
	if pips then
		for _, pip in pips:GetChildren() do
			local n = tonumber(pip.Name:match("%d+"))
			if n and pip:IsA("GuiObject") then
				pip.Visible = n <= (self.Rounds or 7)
				pip.BackgroundColor3 = if n < round then PIP.Done elseif n == round then PIP.Current else PIP.Upcoming
			end
		end
	end
end

-- every player's status at once (a new round: everyone's listening)
function FFABoard:SetAll(text: string)
	for i, p in self.Order do
		if not self.Left[p.UserId] then
			local cell = self.Frame.Panel.Players["Player" .. i]
			cell.Status.Text = text
			cell.Status.TextColor3 = STATUS.wait
		end
	end
end

function FFABoard:SetStatus(userId: number, text: string, tone: string?)
	local cell = self:_cell(userId)
	if cell and not self.Left[userId] then
		cell.Status.Text = text
		cell.Status.TextColor3 = STATUS[tone or "wait"] or STATUS.wait
	end
end

-- the RoundEnd packet: scores, each pick's result, and who has left
function FFABoard:OnRoundEnd(packet)
	for _, id in packet.Left or {} do
		self.Left[id] = true
	end
	for _, p in self.Order do
		local k = tostring(p.UserId)
		local cell = self:_cell(p.UserId)
		self.Scores[p.UserId] = packet.Scores[k] or self.Scores[p.UserId] or 0
		if cell then
			cell.Score.Text = tostring(self.Scores[p.UserId])
			local pick = packet.Picks[k]
			if self.Left[p.UserId] then
				cell.Status.Text = "Left"
				cell.Status.TextColor3 = STATUS.bad
				cell.BackgroundColor3 = GREY
			elseif pick and pick.Correct then
				cell.Status.Text = `Correct · +{pick.Points}`
				cell.Status.TextColor3 = STATUS.ok
			elseif pick and pick.Picked then
				cell.Status.Text = "Wrong · 0"
				cell.Status.TextColor3 = STATUS.bad
			else
				cell.Status.Text = "No answer"
				cell.Status.TextColor3 = STATUS.wait
			end
		end
	end
	self:_ranks()
end

-- the little place badges follow the scores (leavers drop to the bottom)
function FFABoard:_ranks()
	local list = table.clone(self.Order)
	table.sort(list, function(a, b)
		local la, lb = self.Left[a.UserId] == true, self.Left[b.UserId] == true
		if la ~= lb then
			return not la
		end
		return (self.Scores[a.UserId] or 0) > (self.Scores[b.UserId] or 0)
	end)
	for place, p in list do
		local cell = self:_cell(p.UserId)
		if cell then
			local slot = table.find(self.Order, p) or place
			local leading = place == 1 and (self.Scores[p.UserId] or 0) > 0
			cell.Rank.Text = tostring(place)
			cell.Rank.BackgroundColor3 = if self.Left[p.UserId] then GREY elseif leading then YELLOW else AV[slot] or C("FFFFFF")
			if p.UserId ~= LOCAL_PLAYER.UserId then
				cell.Score.TextColor3 = if leading then INK else C("4A4460")
			end
		end
	end
end

return FFABoard
