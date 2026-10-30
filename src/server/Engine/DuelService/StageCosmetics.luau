--| StageCosmetics
-- Shows each player's equipped Stage (their spot platform) and Mic stand on the duel stage
-- while they're on it. Models live in ReplicatedStorage.Assets.Cosmetics.Stages / .Mics
-- (the shop + inventory cards show them too; ServerStorage.Cosmetics still works), named by
-- catalog Id (ShopCatalog), each with its WorldPivot at the bottom centre and LookVector =
-- the front (stage: towards the mic, mic: towards the player). "Default" (or a missing model)
-- shows the stage's own SpotPlatform<slot> / MicStand<slot> parts instead.
-- Apply(stage, slot, player?) is called by DuelService on join/leave; a player who equips
-- something else while on a stage is redrawn through their EquippedStage/EquippedMic
-- attributes (mirrored by DataService).

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StageCosmetics = {}

-- the stage model's own parts each cosmetic replaces (inside DuelStageN.Visual)
local DEFAULT_PARTS = {
	Stage = { "SpotPlatform%s", "SpotPlatform%s_Ring" },
	Mic = { "MicStand%s", "Mic%s", "MicGrille%s" },
}
local ATTRIBUTE = { Stage = "EquippedStage", Mic = "EquippedMic" }
local FOLDER = { Stage = "Stages", Mic = "Mics" }

local function visualPart(stage, pattern: string, slot: string): BasePart?
	local visual = stage.Model:FindFirstChild("Visual")
	return visual and visual:FindFirstChild(string.format(pattern, slot)) :: BasePart?
end

local function setDefaultsVisible(stage, kind: string, slot: string, visible: boolean)
	for _, pattern in DEFAULT_PARTS[kind] do
		local part = visualPart(stage, pattern, slot)
		if part then
			if part:GetAttribute("CosmeticTransparency") == nil then
				part:SetAttribute("CosmeticTransparency", part.Transparency)
			end
			part.Transparency = if visible then part:GetAttribute("CosmeticTransparency") else 1
		end
	end
end

local function template(kind: string, id: string?): Model?
	if not id or id == "" or id == "Default" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local root = (assets and assets:FindFirstChild("Cosmetics")) or ServerStorage:FindFirstChild("Cosmetics")
	local folder = root and root:FindFirstChild(FOLDER[kind])
	local model = folder and folder:FindFirstChild(id)
	return if model and model:IsA("Model") then model else nil
end

-- where a cosmetic goes and which way it faces: bottom centre of the part it replaces,
-- looking at the other piece (platform <-> mic), kept level
local function placement(stage, kind: string, slot: string): CFrame?
	local pad = visualPart(stage, "SpotPlatform%s", slot)
	local stand = visualPart(stage, "MicStand%s", slot)
	if not (pad and stand) then
		return nil
	end
	local from, to = if kind == "Stage" then pad else stand, if kind == "Stage" then stand else pad
	local bottom = from.Position - Vector3.new(0, from.Size.Y / 2, 0)
	local target = Vector3.new(to.Position.X, bottom.Y, to.Position.Z)
	return CFrame.lookAt(bottom, target)
end

local function clearSlot(stage, kind: string, slot: string)
	local name = `Cosmetic{kind}{slot}`
	local old = stage.Model:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	setDefaultsVisible(stage, kind, slot, true)
end

local function drawSlot(stage, kind: string, slot: string, player: Player?)
	clearSlot(stage, kind, slot)
	if not player then
		return
	end
	local source = template(kind, player:GetAttribute(ATTRIBUTE[kind]))
	local at = source and placement(stage, kind, slot)
	if not (source and at) then
		return
	end
	local model = source:Clone()
	model.Name = `Cosmetic{kind}{slot}`
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model:PivotTo(at)
	model.Parent = stage.Model
	setDefaultsVisible(stage, kind, slot, false)
end

-- player = who's on the slot now (nil = empty: back to the stage's own parts)
function StageCosmetics.Apply(stage, slot: string, player: Player?)
	stage.CosmeticConns = stage.CosmeticConns or {}
	local conns = stage.CosmeticConns[slot]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
	end
	stage.CosmeticConns[slot] = {}
	for kind, attribute in ATTRIBUTE do
		drawSlot(stage, kind, slot, player)
		if player then
			table.insert(stage.CosmeticConns[slot], player:GetAttributeChangedSignal(attribute):Connect(function()
				drawSlot(stage, kind, slot, player)
			end))
		end
	end
end

return StageCosmetics
